//! Facade-owned pull observations. No port producer, second read lease or body cache.
mod registry;

use std::sync::{Arc, Mutex as SyncMutex};

use futures::future::BoxFuture;
use pl_protocol::{CONTENT_WINDOW_MAX_BYTES, ContentRange, ContentRef, studio::StudioErrorCode};
use pl_studio_runtime::{ContentWatch, ConversationReader, DisplayMembers};
use tokio::sync::Mutex;
use tokio_util::sync::CancellationToken;

use super::owner::{closed, error};
use crate::api::studio::{
    convert::{chat, presentation},
    types::{BridgeContentWindow, BridgeDisplayMemberPage, BridgeError},
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
    OpeningMembers(BoxFuture<'static, Result<DisplayMembers, BridgeError>>),
    Members(DisplayMembers),
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
        let reader = reader.clone();
        self.install_open(
            facade_cancel,
            NativeWatch::Opening(Box::pin(async move {
                reader
                    .watch_content(&reference, range)
                    .await
                    .map_err(BridgeError::from)
            })),
        )
        .await
    }

    pub(super) async fn open_members(
        &self,
        reader: &ConversationReader,
        facade_cancel: &CancellationToken,
        reference: pl_protocol::DisplayBlockRef,
        window: pl_protocol::DisplayMemberWindow,
        demand: pl_protocol::ReadDemand,
    ) -> Result<String, BridgeError> {
        let reader = reader.clone();
        self.install_open(
            facade_cancel,
            NativeWatch::OpeningMembers(Box::pin(async move {
                reader
                    .open_display_members(reference, window, demand)
                    .await
                    .map_err(BridgeError::from)
            })),
        )
        .await
    }

    async fn install_open(
        &self,
        facade_cancel: &CancellationToken,
        native: NativeWatch,
    ) -> Result<String, BridgeError> {
        let (id, owner) = {
            let mut registry = self.registry.lock().unwrap_or_else(|e| e.into_inner());
            if facade_cancel.is_cancelled() {
                return Err(closed());
            }
            let id = registry
                .insert_with(|| {
                    Arc::new(WatchOwner {
                        cancel: facade_cancel.child_token(),
                        native: Mutex::new(native),
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

    pub(super) async fn next_members(
        &self,
        id: &str,
    ) -> Result<Option<BridgeDisplayMemberPage>, BridgeError> {
        match self.lookup(id)? {
            Some(owner) => owner.next_members().await,
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
        if let NativeWatch::OpeningMembers(open) = &mut *native {
            *native = match open.await {
                Ok(watch) => NativeWatch::Members(watch),
                Err(error) => NativeWatch::Failed(error),
            };
        }
        match &*native {
            NativeWatch::Ready(_) | NativeWatch::Members(_) => Ok(()),
            NativeWatch::Failed(error) => Err(error.clone()),
            NativeWatch::Closed => Err(closed()),
            NativeWatch::Opening(_) | NativeWatch::OpeningMembers(_) => {
                unreachable!("original open was awaited")
            }
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
            NativeWatch::Members(_) | NativeWatch::OpeningMembers(_) => {
                return Err(BridgeError::invalid_argument(
                    "member observation is not a content watch",
                ));
            }
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

    async fn next_members(&self) -> Result<Option<BridgeDisplayMemberPage>, BridgeError> {
        if self.cancel.is_cancelled() {
            return Ok(None);
        }
        let _next = self.next_gate.try_lock().map_err(|_| {
            error(
                StudioErrorCode::Conflict,
                "a member window read is already in flight",
            )
        })?;
        let mut native = tokio::select! {
            biased;
            () = self.cancel.cancelled() => return Ok(None),
            native = self.native.lock() => native,
        };
        let watch = match &mut *native {
            NativeWatch::Members(watch) => watch,
            NativeWatch::Closed => return Ok(None),
            NativeWatch::Failed(error) => return Err(error.clone()),
            _ => {
                return Err(BridgeError::invalid_argument(
                    "observation is not an open member window",
                ));
            }
        };
        let result = tokio::select! {
            biased;
            () = self.cancel.cancelled() => return Ok(None),
            result = watch.next() => result?,
        };
        if self.cancel.is_cancelled() {
            return Ok(None);
        }
        let sealed = result.as_ref().is_none_or(|page| page.sealed);
        let page = result.map(presentation::member_page);
        if let Some(page) = &page {
            let mut serializer = flutter_rust_bridge::for_generated::SseSerializer::new();
            Some(page.clone()).sse_encode(&mut serializer);
            if serializer.cursor.get_ref().len() + 1 > pl_protocol::CHAT_BATCH_MAX_BYTES as usize {
                return Err(error(
                    StudioErrorCode::Overloaded,
                    "member page exceeds the encoded transport budget",
                ));
            }
        }
        if sealed {
            // A fixed sealed page needs no watch. Keep the slot until native close succeeds.
            watch.request_close();
            watch.close().await?;
            *native = NativeWatch::Closed;
        }
        if self.cancel.is_cancelled() {
            return Ok(None);
        }
        Ok(page)
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
        if let NativeWatch::OpeningMembers(open) = &mut *native {
            *native = match open.await {
                Ok(watch) => NativeWatch::Members(watch),
                Err(_) => NativeWatch::Closed,
            };
        }
        if let NativeWatch::Ready(watch) = &mut *native {
            watch.request_close();
            #[cfg(test)]
            self.hooks.before_close()?;
            watch.close().await?;
        }
        if let NativeWatch::Members(watch) = &mut *native {
            watch.request_close();
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

#[cfg(test)]
mod tests {
    //! Exercise the production owner with actual Runtime watches. Hooks park a successful native
    //! receive or fail a close boundary; they never replace Runtime or manufacture content windows.
    use std::{future::Future, time::Duration};

    use anyhow::{Context, Result, ensure};
    use tokio::sync::oneshot;

    use super::*;
    use crate::api::studio::{
        handlers::chat::{BridgeConversationFeed, ConversationOwner, tests::Environment},
        types::{BridgeContentRange, BridgeContentRef, BridgeErrorCode, BridgeReadDemand},
    };

    #[derive(Default)]
    pub(super) struct Hooks {
        after_receive: SyncMutex<Option<ReceiveGate>>,
        close_failure: SyncMutex<Option<BridgeError>>,
    }

    struct ReceiveGate {
        entered: oneshot::Sender<()>,
        release: oneshot::Receiver<()>,
    }

    impl Hooks {
        pub(super) async fn after_receive(&self) {
            let gate = self.after_receive.lock().unwrap().take();
            if let Some(gate) = gate {
                let _ = gate.entered.send(());
                let _ = gate.release.await;
            }
        }

        pub(super) fn before_close(&self) -> Result<(), BridgeError> {
            match self.close_failure.lock().unwrap().take() {
                Some(error) => Err(error),
                None => Ok(()),
            }
        }
    }

    fn range() -> BridgeContentRange {
        BridgeContentRange {
            offset: 0,
            max_bytes: 1024,
        }
    }

    async fn conversation(env: &Environment) -> Result<(BridgeConversationFeed, BridgeContentRef)> {
        let mut native = env.feed().await?;
        let initial = loop {
            match native.recv().await?.context("initial feed ended")? {
                pl_studio_runtime::ConversationEvent::Chat { batch } => break batch,
                pl_studio_runtime::ConversationEvent::Activity { .. } => {}
            }
        };
        let owner = Arc::new(ConversationOwner::new(native, CancellationToken::new()));
        owner.install_lifecycle(|_| {})?;
        let facade = BridgeConversationFeed { inner: owner };
        let demand = BridgeReadDemand {
            max_items: 16,
            max_bytes: 64 * 1024,
        };
        let mut page = chat::batch(*initial);
        loop {
            for entry in page.entries {
                if entry.atom.contents.is_empty() && entry.atom.payload.is_none() {
                    continue;
                }
                let item_id = entry.record_id;
                let manifest = facade
                    .list_contents(item_id.to_owned(), None, demand)
                    .await?;
                if let Some(entry) = manifest.entries.into_iter().next() {
                    let window = facade
                        .read_content(entry.reference.clone(), range())
                        .await?;
                    ensure!(
                        !window.bytes.is_empty(),
                        "fixture body must be real, nonempty content"
                    );
                    return Ok((facade, entry.reference));
                }
            }
            let before = page.before.context("fixture has no body manifest")?;
            page = facade.load_older(before, demand).await?;
        }
    }

    fn arm(owner: &WatchOwner) -> (oneshot::Receiver<()>, oneshot::Sender<()>) {
        let (entered, reached) = oneshot::channel();
        let (release, held) = oneshot::channel();
        *owner.hooks.after_receive.lock().unwrap() = Some(ReceiveGate {
            entered,
            release: held,
        });
        (reached, release)
    }

    async fn reached<T>(
        future: &mut std::pin::Pin<Box<impl Future<Output = T>>>,
        reached: oneshot::Receiver<()>,
    ) -> Result<()> {
        tokio::time::timeout(Duration::from_secs(5), async {
            tokio::select! {
                reached = reached => reached.context("native receive did not reach its gate"),
                _ = future.as_mut() => anyhow::bail!("native method ended before the receive gate"),
            }
        })
        .await?
    }

    #[tokio::test]
    async fn overlapping_next_is_rejected_and_close_cancels_before_waiting_for_recv_lock()
    -> Result<()> {
        let env = Environment::new().await?;
        let result = async {
            let (facade, reference) = conversation(&env).await?;
            let id = facade
                .open_content_watch(reference.clone(), range())
                .await?;
            let owner = facade
                .inner
                .content()?
                .watches
                .lookup(&id)?
                .context("watch not registered")?;
            let (entered, release) = arm(&owner);
            let mut first = Box::pin(facade.next_content_window(id.clone()));
            reached(&mut first, entered).await?;
            let overlap = tokio::time::timeout(
                Duration::from_secs(5),
                facade.next_content_window(id.clone()),
            )
            .await?
            .expect_err("overlapping next must not queue");
            ensure!(overlap.code == BridgeErrorCode::Conflict);
            facade.request_close_content_watch(id.clone())?;
            let (next, close) = tokio::time::timeout(Duration::from_secs(5), async {
                tokio::join!(first, facade.close_content_watch(id.clone()))
            })
            .await?;
            ensure!(
                next?.is_none(),
                "retired watch must not publish its late native window"
            );
            close?;
            drop(release);
            ensure!(facade.inner.content()?.watches.lookup(&id)?.is_none());
            facade.close_content_watch(id.clone()).await?;
            facade.request_close_content_watch(id.clone())?;
            ensure!(facade.next_content_window(id.clone()).await?.is_none());
            let window = facade.read_content(reference, range()).await?;
            ensure!(
                !window.bytes.is_empty(),
                "closing a watch must not close the original read lease"
            );
            facade.close().await?;
            Ok(())
        }
        .await;
        env.finish(result).await
    }

    #[tokio::test]
    async fn cancelling_next_keeps_the_original_watch_and_failure_retains_its_id_until_retry()
    -> Result<()> {
        let env = Environment::new().await?;
        let result = async {
            let (facade, reference) = conversation(&env).await?;
            let id = facade
                .open_content_watch(reference.clone(), range())
                .await?;
            let owner = facade
                .inner
                .content()?
                .watches
                .lookup(&id)?
                .context("watch not registered")?;
            let (entered, release) = arm(&owner);
            let mut next = Box::pin(facade.next_content_window(id.clone()));
            reached(&mut next, entered).await?;
            drop(next);
            drop(release);
            ensure!(
                facade.inner.content()?.watches.lookup(&id)?.is_some(),
                "cancelling next is not close"
            );
            let failure = error(
                StudioErrorCode::Storage,
                "injected native watch close boundary",
            );
            *owner.hooks.close_failure.lock().unwrap() = Some(failure.clone());
            ensure!(facade.close_content_watch(id.clone()).await.unwrap_err() == failure);
            ensure!(
                facade.inner.content()?.watches.lookup(&id)?.is_some(),
                "a failed close must retain identity and capacity"
            );
            facade.close_content_watch(id.clone()).await?;
            ensure!(facade.inner.content()?.watches.lookup(&id)?.is_none());
            facade.close_content_watch(id).await?;
            ensure!(
                !facade
                    .read_content(reference, range())
                    .await?
                    .bytes
                    .is_empty()
            );
            facade.close().await?;
            Ok(())
        }
        .await;
        env.finish(result).await
    }

    #[tokio::test]
    async fn cancelled_open_and_close_waiters_keep_the_original_future_until_join() -> Result<()> {
        let env = Environment::new().await?;
        let result = async {
            let (facade, reference) = conversation(&env).await?;
            let (entered, reached_open) = oneshot::channel();
            let (release, held) = oneshot::channel();
            let reader = facade.inner.content()?.reader.clone();
            let reference = chat::protocol_content_ref(reference);
            let id = facade
                .inner
                .content()?
                .watches
                .registry
                .lock()
                .unwrap()
                .insert_with(|| {
                    Arc::new(WatchOwner {
                        cancel: facade.inner.cancel.child_token(),
                        native: Mutex::new(NativeWatch::Opening(Box::pin(async move {
                            // The actual native open finishes before the delivery boundary is parked.
                            let watch = reader
                                .watch_content(&reference, chat::range(range()))
                                .await?;
                            let _ = entered.send(());
                            held.await.map_err(|_| closed())?;
                            Ok(watch)
                        }))),
                        next_gate: Mutex::new(()),
                        hooks: Hooks::default(),
                    })
                })
                .unwrap();
            let owner = facade
                .inner
                .content()?
                .watches
                .lookup(&id)?
                .context("opening watch not registered")?;
            let mut open = Box::pin(owner.initialize());
            reached(&mut open, reached_open).await?;
            drop(open);
            facade.request_close_content_watch(id.clone())?;
            let mut close = Box::pin(facade.close_content_watch(id.clone()));
            ensure!(
                futures::poll!(close.as_mut()).is_pending(),
                "close must await the original open"
            );
            drop(close);
            let mut retry = Box::pin(facade.close_content_watch(id.clone()));
            ensure!(
                futures::poll!(retry.as_mut()).is_pending(),
                "cancelling close must not lose its open future"
            );
            release
                .send(())
                .map_err(|_| anyhow::anyhow!("native open was abandoned"))?;
            retry.await?;
            ensure!(facade.inner.content()?.watches.lookup(&id)?.is_none());
            facade.close().await?;
            Ok(())
        }
        .await;
        env.finish(result).await
    }

    #[tokio::test]
    async fn eof_keeps_explicit_ownership_and_capacity_and_foreign_ids_are_rejected() -> Result<()>
    {
        let env = Environment::new().await?;
        let result = async {
            let (facade, reference) = conversation(&env).await?;
            let (other, _) = conversation(&env).await?;
            let first = facade
                .open_content_watch(reference.clone(), range())
                .await?;
            for _ in 1..registry::MAX_CONTENT_WATCHES {
                facade
                    .open_content_watch(reference.clone(), range())
                    .await?;
            }
            ensure!(
                facade
                    .open_content_watch(reference.clone(), range())
                    .await
                    .unwrap_err()
                    .code
                    == BridgeErrorCode::Overloaded
            );
            ensure!(
                other
                    .next_content_window(first.clone())
                    .await
                    .unwrap_err()
                    .code
                    == BridgeErrorCode::NotFound
            );
            ensure!(other.request_close_content_watch(first.clone()).is_err());
            ensure!(other.close_content_watch(first.clone()).await.is_err());
            let window = facade
                .next_content_window(first.clone())
                .await?
                .context("sealed fixture must yield its initial window")?;
            ensure!(window.sealed);
            ensure!(facade.next_content_window(first.clone()).await?.is_none());
            ensure!(
                facade.inner.content()?.watches.lookup(&first)?.is_some(),
                "EOF does not substitute for explicit close"
            );
            facade.close_content_watch(first.clone()).await?;
            let replacement = facade.open_content_watch(reference, range()).await?;
            ensure!(replacement != first);
            ensure!(facade.next_content_window(first).await?.is_none());
            other.close().await?;
            facade.close().await?;
            Ok(())
        }
        .await;
        env.finish(result).await
    }

    #[tokio::test]
    async fn facade_close_keeps_all_watch_failures_and_still_closes_feed_and_read() -> Result<()> {
        let env = Environment::new().await?;
        let result = async {
            let (facade, reference) = conversation(&env).await?;
            let first = facade
                .open_content_watch(reference.clone(), range())
                .await?;
            let second = facade
                .open_content_watch(reference.clone(), range())
                .await?;
            let one = error(StudioErrorCode::Storage, "first watch close boundary");
            let two = error(StudioErrorCode::Unavailable, "second watch close boundary");
            for (id, failure) in [(&first, &one), (&second, &two)] {
                let owner = facade
                    .inner
                    .content()?
                    .watches
                    .lookup(id)?
                    .context("watch not registered")?;
                *owner.hooks.close_failure.lock().unwrap() = Some(failure.clone());
            }
            let diagnostic = facade
                .close()
                .await
                .expect_err("independent failures must be reported");
            let details: serde_json::Value = serde_json::from_str(
                diagnostic
                    .details_json
                    .as_deref()
                    .context("missing independent cleanup diagnostics")?,
            )?;
            let causes = details["closeFailures"]
                .as_array()
                .context("missing cleanup causes")?;
            for original in [&one, &two] {
                ensure!(
                    causes
                        .iter()
                        .any(|cause| cause["error"] == serde_json::to_value(original).unwrap())
                );
            }
            ensure!(
                facade.inner.native().await.is_none(),
                "watch failure must not skip feed close"
            );
            let read_failure = facade
                .inner
                .content()?
                .reader
                .read_content(&chat::protocol_content_ref(reference), chat::range(range()))
                .await
                .expect_err("watch failure must not skip read close");
            ensure!(BridgeError::from(read_failure).code == BridgeErrorCode::Cancelled);
            // Retrying close uses the same cancelled native owners and then releases their identities.
            // The facade may itself have retried them while retaining its original failure diagnostics.
            facade.close_content_watch(first.clone()).await?;
            facade.close_content_watch(second.clone()).await?;
            ensure!(facade.inner.content()?.watches.lookup(&first)?.is_none());
            ensure!(facade.inner.content()?.watches.lookup(&second)?.is_none());
            ensure!(
                facade.close().await.is_err(),
                "retained facade cleanup diagnostics must not disappear"
            );
            Ok(())
        }
        .await;
        env.finish(result).await
    }

    #[test]
    fn range_and_actual_option_window_encoding_are_bounded_without_truncating_payload() {
        assert!(
            validate_range(&ContentRange {
                offset: 0,
                max_bytes: 0
            })
            .is_err()
        );
        assert!(
            validate_range(&ContentRange {
                offset: u64::MAX,
                max_bytes: 1
            })
            .is_err()
        );
        assert!(
            validate_range(&ContentRange {
                offset: 0,
                max_bytes: CONTENT_WINDOW_MAX_BYTES + 1
            })
            .is_err()
        );
        let window = pl_protocol::ContentWindow {
            offset: 9,
            bytes: Vec::new(),
            generation: "真实generation".into(),
            available_through: 100,
            sealed: false,
        };
        let mut serializer = flutter_rust_bridge::for_generated::SseSerializer::new();
        Some(chat::window(window.clone())).sse_encode(&mut serializer);
        let overhead = serializer.cursor.get_ref().len() + 1;
        let mut exact = window;
        exact.bytes = vec![42; CONTENT_WINDOW_MAX_BYTES as usize - overhead];
        let accepted = bounded_window(exact.clone()).unwrap();
        assert_eq!(accepted.bytes, exact.bytes);
        exact.bytes.push(42);
        assert_eq!(
            bounded_window(exact).unwrap_err().code,
            BridgeErrorCode::Overloaded
        );
    }
}
