use super::product::{FeedKind, NativeFrame};
use super::{feed::Transport, tasks};
use axum::response::sse::Event;
use futures::{FutureExt, Stream};
use pl_protocol::products::identity::ProductFeedIdentity;
use pl_protocol::studio::{
    CleanupRecovery, FeedCloseIssue, StudioError, StudioErrorCode, StudioShutdownIssue,
};
use pl_studio_runtime::StudioRuntime;
use std::{
    convert::Infallible,
    pin::Pin,
    sync::Arc,
    task::{Context, Poll},
};
use tokio::sync::{mpsc, oneshot};
use tokio_stream::wrappers::ReceiverStream;

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

pub(super) async fn run(
    owner: Arc<Transport>,
    runtime: StudioRuntime,
    kind: FeedKind,
    sender: mpsc::Sender<Result<Event, Infallible>>,
    opened: oneshot::Sender<Result<ProductFeedIdentity, StudioError>>,
) {
    let outcome = std::panic::AssertUnwindSafe(async {
        let feed = match kind.open(&runtime).await { Ok(feed) => Arc::new(feed), Err(error) => { let _ = opened.send(Err(pl_studio_runtime::studio_error_from_anyhow(error))); return; } };
        let identity = match owner.install(feed.clone()) { Ok(identity) => identity, Err(error) => { let _ = opened.send(Err(error)); return; } };
        if opened.send(Ok(identity)).is_err() { owner.request_close(); return; }
        loop {
            if owner.cancel.is_cancelled() || feed.is_closing() {
                if !sender.is_closed() && let Err(error) = feed.send_closed(|frame| send(&owner, &sender, frame)) { record_error(&owner, error); }
                break;
            }
            match owner.admit(|| feed.send_pending(|frame| send(&owner, &sender, frame))) {
                Ok(_) => {}, Err(error) if error.code == StudioErrorCode::Cancelled => { owner.request_close(); continue; },
                Err(error) => {
                    if !sender.is_closed() && let Err(error) = feed.send_failure(error, |frame| send(&owner, &sender, frame)) { record_error(&owner, error); } break; }
            }
            tokio::select! { biased;
                () = owner.cancel.cancelled() => {}, () = feed.cancelled() => {}, () = sender.closed() => owner.request_close(),
                result = feed.changed() => if let Err(error) = result {
                    if error.code != StudioErrorCode::Cancelled
                        && !sender.is_closed()
                        && let Err(error) = feed.send_failure(error, |frame| send(&owner, &sender, frame))
                    { record_error(&owner, error); }
                    owner.request_close();
                }
            }
        }
    }).catch_unwind().await;
    if outcome.is_err() {
        owner.record(tasks::issue(
            "pumpPanic",
            "Configuration HTTP pump panicked",
            CleanupRecovery::Terminal,
        ));
        if let Some(feed) = owner.runtime_feed()
            && !sender.is_closed()
            && let Err(error) = feed.send_failure(StudioError::internal(), |frame| {
                send(&owner, &sender, frame)
            })
        {
            record_error(&owner, error);
        }
    }
    owner.request_close();
    drop(sender);
    futures::join!(owner.close_reads(), owner.wait_consumer());
    if let Err(panic) = outcome {
        std::panic::resume_unwind(panic);
    }
}
fn send(
    owner: &Transport,
    sender: &mpsc::Sender<Result<Event, Infallible>>,
    frame: NativeFrame,
) -> Result<(), StudioError> {
    let sequence = frame.sequence();
    let mut event = Event::default()
        .event("frame")
        .json_data(frame)
        .map_err(|_| {
            StudioError::new(
                StudioErrorCode::Protocol,
                "Configuration typed frame cannot be encoded",
                false,
            )
        })?;
    if let Some(sequence) = sequence {
        event = event.id(sequence.to_string());
    }
    let result = sender.try_send(Ok(event)).map_err(|error| match error {
        mpsc::error::TrySendError::Closed(_) => tasks::delivery_error(),
        mpsc::error::TrySendError::Full(_) => StudioError::new(
            StudioErrorCode::Overloaded,
            "Configuration HTTP transport buffer is full",
            false,
        ),
    });
    if let Err(error) = &result {
        record_error(owner, error.clone());
    }
    result
}
fn record_error(owner: &Transport, error: StudioError) {
    owner.record(FeedCloseIssue {
        diagnostic: StudioShutdownIssue {
            stage: "configurationHttp".into(),
            code: "deliveryFailed".into(),
            message: error.message,
            retryable: error.retryable,
            correlation_id: error.correlation_id,
        },
        recovery: CleanupRecovery::Terminal,
    });
}
