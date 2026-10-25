//! Hyper consumes the native Models window directly. There is no transport publication queue.
use super::feed::FeedOwner;
use axum::response::sse::Event;
use futures::Stream;
use pl_protocol::{
    products::feed::model_catalog::ModelCatalogFrame,
    studio::{StudioError, StudioErrorCode},
};
use pl_studio_runtime::models::StudioModelCatalogFeed;
use std::{
    convert::Infallible,
    future::Future,
    pin::Pin,
    sync::Arc,
    task::{Context, Poll},
};

type PendingReady = Pin<Box<dyn Future<Output = Result<(), StudioError>> + Send>>;

pub(super) struct CatalogBody {
    owner: Arc<FeedOwner>,
    source: Option<Arc<StudioModelCatalogFeed>>,
    ready: Option<PendingReady>,
    failure: Option<StudioError>,
    ended: bool,
    finished: bool,
}
impl CatalogBody {
    pub(super) fn new(owner: Arc<FeedOwner>, source: Arc<StudioModelCatalogFeed>) -> Self {
        Self {
            owner,
            source: Some(source),
            ready: None,
            failure: None,
            ended: false,
            finished: false,
        }
    }
    fn finish(&mut self) {
        if self.finished {
            return;
        }
        self.finished = true;
        // Release the actual wait/source before acknowledging consumer completion. Returning
        // the last Event alone is never this boundary, including a slow final network write.
        self.ready.take();
        self.source.take();
        self.owner.request_close();
        self.owner.body_ended();
    }
}
impl Stream for CatalogBody {
    type Item = Result<Event, Infallible>;
    fn poll_next(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        if self.ended {
            self.finish();
            return Poll::Ready(None);
        }
        loop {
            let Some(source) = self.source.clone() else {
                self.finish();
                return Poll::Ready(None);
            };
            // Register ACK/close notifications before examining native credit. The future can
            // survive Pending; after a Ready wake a new registration precedes the next send.
            if self.ready.is_none() {
                let owner = self.owner.clone();
                let wait_source = source.clone();
                let changed = owner.changed.clone();
                self.ready = Some(Box::pin(async move {
                    let wake = changed.notified_owned();
                    tokio::pin!(wake);
                    wake.as_mut().enable();
                    tokio::select! { biased;
                        () = owner.cancel.cancelled() => Ok(()),
                        () = wait_source.cancelled() => Ok(()),
                        result = wait_source.changed() => result,
                        () = wake => Ok(()),
                    }
                }));
                // Poll once to install Notify before send_pending checks a full native window.
                if let Some(ready) = self.ready.as_mut()
                    && let Poll::Ready(result) = ready.as_mut().poll(cx)
                {
                    self.ready = None;
                    if let Err(error) = result {
                        self.failure = Some(error);
                    }
                }
            }
            let mut event = None;
            let mut terminal = false;
            let mut send = |frame: ModelCatalogFrame| {
                let sequence = match &frame {
                    ModelCatalogFrame::Data {
                        delivery_sequence, ..
                    } => Some(*delivery_sequence),
                    _ => {
                        terminal = true;
                        None
                    }
                };
                let mut encoded =
                    Event::default()
                        .event("frame")
                        .json_data(frame)
                        .map_err(|_| {
                            StudioError::new(
                                StudioErrorCode::Protocol,
                                "Catalog typed frame cannot be serialized",
                                false,
                            )
                        })?;
                if let Some(sequence) = sequence {
                    encoded = encoded.id(sequence.to_string());
                }
                event = Some(encoded);
                Ok(())
            };
            let result = if let Some(error) = self.failure.take() {
                self.owner.record(error.clone());
                source.send_failure(error, &mut send).map(|()| true)
            } else if self.owner.cancel.is_cancelled() || source.is_closing() {
                source.send_closed(&mut send).map(|()| true)
            } else {
                self.owner.send_pending(&mut send)
            };
            match result {
                Err(error)
                    if error.code == StudioErrorCode::Cancelled
                        && (self.owner.cancel.is_cancelled() || source.is_closing()) =>
                {
                    self.ready = None;
                    continue;
                }
                Err(error) => {
                    self.ready = None;
                    if source.is_closing() {
                        self.owner.record(error);
                        self.ended = true;
                        self.finish();
                        return Poll::Ready(None);
                    }
                    self.failure = Some(error);
                    continue;
                }
                Ok(_) if terminal => {
                    self.ended = true;
                    self.ready = None;
                    return Poll::Ready(event.map(Ok));
                }
                Ok(_) if event.is_some() => {
                    self.ready = None;
                    return Poll::Ready(event.map(Ok));
                }
                Ok(true) if source.is_closing() => {
                    self.ended = true;
                    self.finish();
                    return Poll::Ready(None);
                }
                Ok(_) => {}
            }
            if let Some(ready) = self.ready.as_mut() {
                match ready.as_mut().poll(cx) {
                    Poll::Pending => return Poll::Pending,
                    Poll::Ready(result) => {
                        self.ready = None;
                        if let Err(error) = result {
                            self.failure = Some(error);
                        }
                    }
                }
            }
        }
    }
}
impl Drop for CatalogBody {
    fn drop(&mut self) {
        self.finish();
    }
}
