//! Hyper polls the original native Authoring FIFO directly; there is no SSE pending queue.
use super::*;
use axum::response::sse::Event;
use futures::Stream;
use pl_studio_runtime::thread_authoring::DeliveryStep;
use std::convert::Infallible;
use std::pin::Pin;
use std::task::{Context, Poll};

pub(super) struct AuthoringBody {
    owner: Arc<Owner>,
    source: Arc<StudioThreadAuthoring>,
    ready: Option<Pin<Box<dyn Future<Output = ()> + Send>>>,
    ended: bool,
}
impl Opening {
    pub(super) fn authoring_body(&mut self) -> Result<AuthoringBody, StudioError> {
        let mut state = self
            .owner
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.closing {
            return Err(cancelled());
        }
        let Some(Native::Authoring(source)) = &state.source else {
            return Err(wrong());
        };
        source.claim()?;
        let source = source.clone();
        state.body = BodyPhase::Active;
        self.adopted = true;
        Ok(AuthoringBody {
            owner: self.owner.clone(),
            source,
            ready: None,
            ended: false,
        })
    }
}
impl Stream for AuthoringBody {
    type Item = Result<Event, Infallible>;
    fn poll_next(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        if self.ended {
            self.finish_body();
            return Poll::Ready(None);
        }
        loop {
            let mut event = None;
            let result = self.source.send_next(|frame| {
                event = Some(
                    Event::default()
                        .event("authoring")
                        .json_data(frame)
                        .map_err(|_| {
                            StudioError::new(
                                StudioErrorCode::Protocol,
                                "Authoring SSE serialization failed",
                                false,
                            )
                        })?,
                );
                Ok(())
            });
            match result {
                Ok(DeliveryStep::Data) => {
                    self.ready = None;
                    return Poll::Ready(event.map(Ok));
                }
                Ok(DeliveryStep::Terminal) => {
                    self.ended = true;
                    // A terminal event handoff is not Hyper's EOF. Keep this actual body/pin
                    // until poll(None) or Drop, including a slow final network write.
                    if event.is_none() {
                        self.finish_body();
                    }
                    return Poll::Ready(event.map(Ok));
                }
                Err(_) => {
                    self.owner
                        .state
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner)
                        .join_issue
                        .get_or_insert_with(|| {
                            issue(
                                "deliveryError",
                                "The Authoring HTTP body could not deliver its typed frame",
                                CleanupRecovery::Terminal,
                            )
                        });
                    self.ended = true;
                    self.finish_body();
                    self.owner.request_close();
                    return Poll::Ready(None);
                }
                Ok(DeliveryStep::Waiting) => {}
            }
            if self.ready.is_none() {
                let source = self.source.clone();
                self.ready = Some(Box::pin(async move { source.ready().await }));
            }
            if let Some(ready) = self.ready.as_mut() {
                match ready.as_mut().poll(cx) {
                    Poll::Ready(()) => self.ready = None,
                    Poll::Pending => return Poll::Pending,
                }
            }
        }
    }
}
impl AuthoringBody {
    fn finish_body(&self) {
        self.owner
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .body = BodyPhase::Ended;
        self.owner.changed.notify_waiters();
    }
}
impl Drop for AuthoringBody {
    fn drop(&mut self) {
        self.finish_body();
        self.owner.request_close();
    }
}
