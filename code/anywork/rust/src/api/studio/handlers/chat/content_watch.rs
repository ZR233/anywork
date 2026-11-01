//! Facade-owned pull observations. No port producer, second read lease or body cache.
mod registry;
#[cfg(test)]
mod tests;

use std::sync::{Arc, Mutex as SyncMutex};

use futures::future::BoxFuture;
use pl_protocol::{CONTENT_WINDOW_MAX_BYTES, ContentRange, ContentRef, studio::StudioErrorCode};
use pl_studio_runtime::{ContentWatch, ConversationReader};
use tokio::sync::Mutex;
use tokio_util::sync::CancellationToken;

use super::owner::{closed, error};
use crate::api::studio::{
    convert::chat,
    types::{BridgeContentWindow, BridgeError},
};
use crate::frb_generated::SseEncode;
use registry::{AdmissionError, WatchRegistry};

pub(super) struct ContentWatches {
    registry: SyncMutex<WatchRegistry<Arc<WatchOwner>>>,
}

struct WatchOwner {
    cancel: CancellationToken,
    native: Mutex<NativeWatch>,
    next_gate: Mutex<()>,
    #[cfg(test)]
    hooks: tests::Hooks,
}

enum NativeWatch {
    // Kept inside the original slot across cancellation of an open waiter, not recreated on retry.
    Opening(BoxFuture<'static, Result<ContentWatch, BridgeError>>),
    Ready(ContentWatch),
    Failed(BridgeError),
    Closed,
}

impl ContentWatches {
    pub(super) fn new(subscription_id: &str) -> Self {
        Self {
            registry: SyncMutex::new(WatchRegistry::new(subscription_id)),
        }
    }

    pub(super) async fn open(
        &self,
        reader: &ConversationReader,
        facade_cancel: &CancellationToken,
        reference: ContentRef,
        range: ContentRange,
    ) -> Result<String, BridgeError> {
        validate_range(&range)?;
        let (id, owner) = {
            let mut registry = self.registry.lock().unwrap_or_else(|e| e.into_inner());
            if facade_cancel.is_cancelled() {
                return Err(closed());
            }
            let reader = reader.clone();
            let id = registry
                .insert_with(|| {
                    Arc::new(WatchOwner {
                        cancel: facade_cancel.child_token(),
                        native: Mutex::new(NativeWatch::Opening(Box::pin(async move {
                            reader
                                .watch_content(&reference, range)
                                .await
                                .map_err(BridgeError::from)
                        }))),
                        next_gate: Mutex::new(()),
                        #[cfg(test)]
                        hooks: tests::Hooks::default(),
                    })
                })
                .map_err(admission_error)?;
            let owner = Arc::clone(
                registry
                    .get(&id)
                    .expect("just issued")
                    .expect("just inserted"),
            );
            (id, owner)
        };
        // A cancelled unpublished open remains registered with its exact future and capacity.
        // Facade close drives and joins that future before releasing the original read lease.
        let opening = owner.cancel.clone().drop_guard();
        let result = owner.initialize().await;
        if let Err(error) = result {
            self.close(&id).await?;
            return Err(error);
        }
        if owner.cancel.is_cancelled() {
            self.close(&id).await?;
            return Err(closed());
        }
        drop(opening.disarm());
        Ok(id)
    }

    fn lookup(&self, id: &str) -> Result<Option<Arc<WatchOwner>>, BridgeError> {
        self.registry
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .get(id)
            .map(|owner| owner.cloned())
            .map_err(|()| {
                error(
                    StudioErrorCode::NotFound,
                    "content watch does not belong to this conversation facade",
                )
            })
    }

    pub(super) async fn next(&self, id: &str) -> Result<Option<BridgeContentWindow>, BridgeError> {
        match self.lookup(id)? {
            Some(owner) => owner.next().await,
            None => Ok(None),
        }
    }

    pub(super) fn request_close(&self, id: &str) -> Result<(), BridgeError> {
        if let Some(owner) = self.lookup(id)? {
            owner.cancel.cancel();
        }
        Ok(())
    }

    pub(super) async fn close(&self, id: &str) -> Result<(), BridgeError> {
        if let Some(owner) = self.lookup(id)? {
            owner.close().await?;
            self.registry
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .remove(id);
        }
        Ok(())
    }

    pub(super) fn request_close_all(&self) {
        let mut registry = self.registry.lock().unwrap_or_else(|e| e.into_inner());
        registry.seal();
        for (_, owner) in registry.values() {
            owner.cancel.cancel();
        }
    }

    pub(super) async fn close_all(&self) -> Vec<(String, BridgeError)> {
        self.request_close_all();
        let entries = self
            .registry
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .values()
            .map(|(id, owner)| (id.clone(), Arc::clone(owner)))
            .collect::<Vec<_>>();
        let outcomes = futures::future::join_all(
            entries
                .into_iter()
                .map(|(id, owner)| async move { (id, owner.close().await) }),
        )
        .await;
        let mut errors = Vec::new();
        let mut registry = self.registry.lock().unwrap_or_else(|e| e.into_inner());
        for (id, outcome) in outcomes {
            match outcome {
                Ok(()) => registry.remove(&id),
                Err(error) => errors.push((id, error)),
            }
        }
        errors
    }
}

impl WatchOwner {
    async fn initialize(&self) -> Result<(), BridgeError> {
        let mut native = self.native.lock().await;
        if let NativeWatch::Opening(open) = &mut *native {
            *native = match open.await {
                Ok(watch) => NativeWatch::Ready(watch),
                Err(error) => NativeWatch::Failed(error),
            };
        }
        match &*native {
            NativeWatch::Ready(_) => Ok(()),
            NativeWatch::Failed(error) => Err(error.clone()),
            NativeWatch::Closed => Err(closed()),
            NativeWatch::Opening(_) => unreachable!("original open was awaited"),
        }
    }

    async fn next(&self) -> Result<Option<BridgeContentWindow>, BridgeError> {
        if self.cancel.is_cancelled() {
            return Ok(None);
        }
        let _next = self.next_gate.try_lock().map_err(|_| {
            error(
                StudioErrorCode::Conflict,
                "a content window read is already in flight",
            )
        })?;
        let mut native = tokio::select! {
            biased;
            () = self.cancel.cancelled() => return Ok(None),
            native = self.native.lock() => native,
        };
        let watch = match &mut *native {
            NativeWatch::Ready(watch) => watch,
            NativeWatch::Closed => return Ok(None),
            NativeWatch::Failed(error) => return Err(error.clone()),
            NativeWatch::Opening(_) => {
                return Err(error(
                    StudioErrorCode::Conflict,
                    "content watch is still opening",
                ));
            }
        };
        let result = tokio::select! {
            biased;
            () = self.cancel.cancelled() => return Ok(None),
            result = async {
                let result = watch.recv().await;
                #[cfg(test)]
                if matches!(&result, Ok(Some(_))) {
                    self.hooks.after_receive().await;
                }
                result
            } => result,
        };
        // Never deliver a window to a retired original watch, including cancellation after receive.
        if self.cancel.is_cancelled() {
            return Ok(None);
        }
        result?.map(bounded_window).transpose()
    }

    async fn close(&self) -> Result<(), BridgeError> {
        // This cancellation wakes next before waiting for the native recv mutex.
        self.cancel.cancel();
        let mut native = self.native.lock().await;
        if let NativeWatch::Opening(open) = &mut *native {
            *native = match open.await {
                Ok(watch) => NativeWatch::Ready(watch),
                Err(_) => NativeWatch::Closed,
            };
        }
        if let NativeWatch::Ready(watch) = &mut *native {
            watch.request_close();
            #[cfg(test)]
            self.hooks.before_close()?;
            watch.close().await?;
        }
        *native = NativeWatch::Closed;
        drop(native);
        let _next = self.next_gate.lock().await;
        Ok(())
    }
}

fn validate_range(range: &ContentRange) -> Result<(), BridgeError> {
    if range.max_bytes == 0
        || range.max_bytes > CONTENT_WINDOW_MAX_BYTES
        || range
            .offset
            .checked_add(u64::from(range.max_bytes))
            .is_none()
    {
        return Err(BridgeError::invalid_argument(
            "content range exceeds the bounded window limit",
        ));
    }
    Ok(())
}

fn bounded_window(window: pl_protocol::ContentWindow) -> Result<BridgeContentWindow, BridgeError> {
    if window.bytes.len() > CONTENT_WINDOW_MAX_BYTES as usize {
        return Err(error(
            StudioErrorCode::Overloaded,
            "native content window exceeds the byte limit",
        ));
    }
    let window = chat::window(window);
    let mut serializer = flutter_rust_bridge::for_generated::SseSerializer::new();
    // next returns Option<Window>; count its tag and the FRB success action as well as all fields.
    Some(window.clone()).sse_encode(&mut serializer);
    if serializer.cursor.get_ref().len() + 1 > CONTENT_WINDOW_MAX_BYTES as usize {
        return Err(error(
            StudioErrorCode::Overloaded,
            "content window exceeds the encoded transport budget",
        ));
    }
    Ok(window)
}

fn admission_error(error_value: AdmissionError) -> BridgeError {
    match error_value {
        AdmissionError::Closed => closed(),
        AdmissionError::Full => error(
            StudioErrorCode::Overloaded,
            "conversation has reached its content watch limit",
        ),
        AdmissionError::Exhausted => error(
            StudioErrorCode::Overloaded,
            "content watch identities are exhausted",
        ),
    }
}
