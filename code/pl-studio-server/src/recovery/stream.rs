use std::convert::Infallible;
use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;
use std::task::{Context, Poll};

use axum::response::sse::Event;
use futures::{FutureExt, Stream};
use pl_protocol::products::feed::recovery::RecoveryFrame;
use pl_protocol::products::identity::ProductFeedIdentity;
use pl_protocol::studio::{CleanupRecovery, StudioError, StudioErrorCode};
use pl_studio_runtime::recovery::StudioRecoveryFeed;
use tokio::sync::{mpsc, oneshot};
use tokio_stream::wrappers::ReceiverStream;

use super::feed::Transport;
use super::tasks;

pub(super) struct BodyStream {
    receiver: Option<ReceiverStream<Result<Event, Infallible>>>,
    owner: Arc<Transport>,
    done: bool,
}

impl BodyStream {
    pub(super) fn new(
        receiver: mpsc::Receiver<Result<Event, Infallible>>,
        owner: Arc<Transport>,
    ) -> Self {
        Self {
            receiver: Some(ReceiverStream::new(receiver)),
            owner,
            done: false,
        }
    }

    fn finish(&mut self) {
        if !self.done {
            self.done = true;
            // Release the actual receiver/buffer before acknowledging local consumer completion.
            drop(self.receiver.take());
            self.owner.request_close();
            self.owner.consumer_done();
        }
    }
}

impl Stream for BodyStream {
    type Item = Result<Event, Infallible>;

    fn poll_next(self: Pin<&mut Self>, context: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        let this = self.get_mut();
        let value = match this.receiver.as_mut() {
            Some(receiver) => Pin::new(receiver).poll_next(context),
            None => Poll::Ready(None),
        };
        if matches!(&value, Poll::Ready(None)) {
            this.finish();
        }
        value
    }
}

impl Drop for BodyStream {
    fn drop(&mut self) {
        self.finish();
    }
}

/// The already-registered owner retains this opening and the producer after HTTP cancellation.
pub(super) async fn run(
    owner: Arc<Transport>,
    opening: impl Future<Output = anyhow::Result<StudioRecoveryFeed>> + Send,
    sender: mpsc::Sender<Result<Event, Infallible>>,
    opened: oneshot::Sender<Result<ProductFeedIdentity, StudioError>>,
) {
    let outcome = std::panic::AssertUnwindSafe(async {
        let feed = match opening.await {
            Ok(feed) => Arc::new(feed),
            Err(error) => {
                let _ = opened.send(Err(pl_studio_runtime::studio_error_from_anyhow(error)));
                return;
            }
        };
        let identity = match owner.install(feed.clone()) {
            Ok(identity) => identity,
            Err(error) => {
                let _ = opened.send(Err(error));
                return;
            }
        };
        if opened.send(Ok(identity)).is_err() {
            owner.request_close();
            return;
        }
        loop {
            if owner.cancel.is_cancelled() || feed.is_closing() {
                finish(&owner, &feed, &sender, tasks::cancelled());
                break;
            }
            let mut failed_send = None;
            let result = owner.admit(|| {
                feed.send_pending(|frame| {
                    let result = send(&sender, frame);
                    if let Err(error) = &result {
                        failed_send = Some(error.clone());
                    }
                    result
                })
            });
            // The synchronous native callback must not reenter this owner's admission lock.
            if let Some(error) = failed_send {
                owner.record(tasks::delivery_failure(error));
            }
            if let Err(error) = result {
                finish(&owner, &feed, &sender, error);
                break;
            }
            tokio::select! { biased;
                () = owner.cancel.cancelled() => {},
                () = feed.cancelled() => {},
                () = sender.closed() => owner.request_close(),
                result = feed.changed() => if let Err(error) = result {
                    finish(&owner, &feed, &sender, error);
                    break;
                },
            }
        }
    })
    .catch_unwind()
    .await;
    if outcome.is_err() {
        owner.record(tasks::issue(
            "pumpPanic",
            "The Recovery HTTP producer panicked",
            CleanupRecovery::Terminal,
        ));
        if let Some(feed) = owner.runtime_feed() {
            finish(&owner, &feed, &sender, StudioError::internal());
        }
    }
    owner.request_close();
    drop(sender);
    // EOF only enables consumer completion; it does not stand in for the real read/query join.
    futures::join!(owner.close_reads(false), owner.wait_consumer());
    if let Err(panic) = outcome {
        std::panic::resume_unwind(panic);
    }
}

fn finish(
    owner: &Transport,
    feed: &StudioRecoveryFeed,
    sender: &mpsc::Sender<Result<Event, Infallible>>,
    error: StudioError,
) {
    // A known dropped body is cancellation. Preserve any actual failed send separately above.
    if sender.is_closed() {
        return;
    }
    let result = if error.code == StudioErrorCode::Cancelled {
        feed.send_closed(|frame| send(sender, frame))
    } else {
        feed.send_failure(error, |frame| send(sender, frame))
    };
    if let Err(error) = result {
        owner.record(tasks::delivery_failure(error));
    }
}

fn send(
    sender: &mpsc::Sender<Result<Event, Infallible>>,
    frame: RecoveryFrame,
) -> Result<(), StudioError> {
    let sequence = match &frame {
        RecoveryFrame::Data {
            delivery_sequence, ..
        } => Some(*delivery_sequence),
        RecoveryFrame::ResyncRequired { .. }
        | RecoveryFrame::Failure { .. }
        | RecoveryFrame::Closed { .. } => None,
    };
    let mut event = Event::default()
        .event("frame")
        .json_data(frame)
        .map_err(|_| {
            StudioError::new(
                StudioErrorCode::Protocol,
                "The typed Recovery frame could not be encoded",
                false,
            )
        })?;
    if let Some(sequence) = sequence {
        event = event.id(sequence.to_string());
    }
    sender.try_send(Ok(event)).map_err(|error| match error {
        mpsc::error::TrySendError::Closed(_) => StudioError::new(
            StudioErrorCode::Unavailable,
            "The Recovery HTTP stream sink is unavailable",
            false,
        ),
        mpsc::error::TrySendError::Full(_) => StudioError::new(
            StudioErrorCode::Overloaded,
            "The Recovery HTTP transport buffer is full",
            false,
        ),
    })
}
