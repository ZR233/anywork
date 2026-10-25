//! Hyper owns the native progress receiver. Cancellation is not an actual body/receiver join.
use axum::response::sse::Event;
use futures::Stream;
use pl_protocol::studio::{StudioError, ThreadPreparationProgress};
use pl_studio_runtime::draft_commands::StudioThreadCreationProgress;
use std::future::Future;
use std::pin::Pin;
use std::task::{Context, Poll};
use tokio::sync::OwnedSemaphorePermit;

type Waiting = Pin<
    Box<
        dyn Future<
                Output = (
                    StudioThreadCreationProgress,
                    Result<Option<ThreadPreparationProgress>, StudioError>,
                ),
            > + Send,
    >,
>;
enum State {
    Ready(StudioThreadCreationProgress),
    Waiting(Waiting),
    Ended,
}
pub(super) struct ProgressBody {
    state: State,
    first: bool,
    _permit: OwnedSemaphorePermit,
}

impl ProgressBody {
    pub(super) fn new(
        progress: StudioThreadCreationProgress,
        permit: OwnedSemaphorePermit,
    ) -> Self {
        Self {
            state: State::Ready(progress),
            first: true,
            _permit: permit,
        }
    }
}
impl Stream for ProgressBody {
    type Item = Result<Event, StudioError>;
    fn poll_next(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        loop {
            match std::mem::replace(&mut self.state, State::Ended) {
                State::Ended => return Poll::Ready(None),
                State::Ready(mut progress) => {
                    if self.first {
                        self.first = false;
                        if let Some(value) = progress.current() {
                            let event = progress_event(value);
                            if event.is_ok() {
                                self.state = State::Ready(progress);
                            }
                            return Poll::Ready(Some(event));
                        }
                    }
                    self.state = State::Waiting(Box::pin(async move {
                        let value = progress.changed().await;
                        (progress, value)
                    }));
                }
                State::Waiting(mut waiting) => match waiting.as_mut().poll(cx) {
                    Poll::Pending => {
                        self.state = State::Waiting(waiting);
                        return Poll::Pending;
                    }
                    Poll::Ready((progress, Ok(Some(value)))) => {
                        let event = progress_event(value);
                        if event.is_ok() {
                            self.state = State::Ready(progress);
                        }
                        return Poll::Ready(Some(event));
                    }
                    Poll::Ready((_progress, Err(error))) => return Poll::Ready(Some(Err(error))),
                    Poll::Ready((_progress, Ok(None))) => {
                        // Dropping the original receiver here is the actual EOF; Drop of this
                        // body also drops a pending wait/receiver. Native close waits that lease.
                        return Poll::Ready(None);
                    }
                },
            }
        }
    }
}

fn progress_event(value: ThreadPreparationProgress) -> Result<Event, StudioError> {
    Event::default()
        .event("preparation")
        .json_data(value)
        .map_err(|_| {
            StudioError::new(
                pl_protocol::studio::StudioErrorCode::Protocol,
                "Preparation progress serialization failed",
                false,
            )
        })
}
