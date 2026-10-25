use std::convert::Infallible;
use std::pin::Pin;
use std::sync::Arc;
use std::task::{Context, Poll};

use axum::response::sse::Event;
use futures::{FutureExt, Stream};
use pl_protocol::products::identity::ProductFeedIdentity;
use pl_protocol::studio::{
    CleanupRecovery, FeedCloseIssue, StudioError, StudioErrorCode, StudioShutdownIssue,
};
use pl_studio_runtime::StudioRuntime;
use pl_studio_runtime::models::AccountTemplatesFrame;
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
            // No future can take another frame after this acknowledgement: release the actual
            // local receiver (and any encoded buffer) before publishing consumer completion.
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

/// This task is retained by its pre-registered parent. Cancelling an HTTP waiter never drops the
/// runtime opening, read openings, pump or body-consumer responsibility.
pub(super) async fn run(
    owner: Arc<Transport>,
    runtime: StudioRuntime,
    sender: mpsc::Sender<Result<Event, Infallible>>,
    opened: oneshot::Sender<Result<ProductFeedIdentity, StudioError>>,
) {
    let outcome = std::panic::AssertUnwindSafe(async {
        let feed = match runtime.open_account_templates().await {
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
                // A known dropped body is cancellation, not an invented successful send. Any
                // actual send admitted before disconnect that failed is still recorded below.
                if !sender.is_closed()
                    && let Err(error) = feed.send_closed(|frame| send(&sender, frame))
                {
                    record_error(&owner, error);
                }
                break;
            }
            match owner.admit(|| feed.send_pending(|frame| send(&sender, frame))) {
                Ok(_) => {}
                Err(error) if error.code == StudioErrorCode::Cancelled => {
                    owner.request_close();
                    continue;
                }
                Err(error) => {
                    record_error(&owner, error.clone());
                    if !sender.is_closed()
                        && let Err(error) = feed.send_failure(error, |frame| send(&sender, frame))
                    {
                        record_error(&owner, error);
                    }
                    break;
                }
            }
            // Static builtin source: do not fabricate changes or query EOF after baseline.
            tokio::select! { biased;
                () = owner.cancel.cancelled() => {}
                () = feed.cancelled() => {}
                () = sender.closed() => { owner.request_close(); }
            }
        }
    })
    .catch_unwind()
    .await;
    if outcome.is_err() {
        owner.record(tasks::issue(
            "pumpPanic",
            "The Templates HTTP pump panicked",
            CleanupRecovery::Terminal,
        ));
        if let Some(feed) = owner.runtime_feed()
            && !sender.is_closed()
            && let Err(error) =
                feed.send_failure(StudioError::internal(), |frame| send(&sender, frame))
        {
            record_error(&owner, error);
        }
    }
    owner.request_close();
    drop(sender);
    // Dropping the sender permits local EOF; only an actual consumer finish/drop acknowledges
    // that responsibility. Neither socket EOF nor this pump ending is used as native join proof.
    futures::join!(owner.close_reads(), owner.wait_consumer());
    if let Err(panic) = outcome {
        std::panic::resume_unwind(panic);
    }
}

fn send(
    sender: &mpsc::Sender<Result<Event, Infallible>>,
    frame: AccountTemplatesFrame,
) -> Result<(), StudioError> {
    let sequence = match &frame {
        AccountTemplatesFrame::Data {
            delivery_sequence, ..
        } => Some(*delivery_sequence),
        AccountTemplatesFrame::ResyncRequired { .. }
        | AccountTemplatesFrame::Failure { .. }
        | AccountTemplatesFrame::Closed { .. } => None,
    };
    let mut event = Event::default()
        .event("frame")
        .json_data(frame)
        .map_err(|_| {
            StudioError::new(
                StudioErrorCode::Protocol,
                "The typed Templates frame could not be encoded",
                false,
            )
        })?;
    if let Some(sequence) = sequence {
        event = event.id(sequence.to_string());
    }
    sender.try_send(Ok(event)).map_err(|error| match error {
        mpsc::error::TrySendError::Closed(_) => tasks::delivery_error(),
        mpsc::error::TrySendError::Full(_) => StudioError::new(
            StudioErrorCode::Overloaded,
            "The Templates HTTP transport buffer is full",
            false,
        ),
    })
}

fn record_error(owner: &Transport, error: StudioError) {
    owner.record(FeedCloseIssue {
        diagnostic: StudioShutdownIssue {
            stage: "templatesHttp".into(),
            code: "deliveryFailed".into(),
            message: error.message,
            retryable: error.retryable,
            correlation_id: error.correlation_id,
        },
        recovery: CleanupRecovery::Terminal,
    });
}
