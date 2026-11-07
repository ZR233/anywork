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
            pl_studio_runtime::ConversationEvent::State { .. } => {}
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
            let crate::api::studio::types::BridgeChatEntry::Item(item) = entry else {
                continue;
            };
            let Some(item_id) = item.content_item_id.as_deref() else {
                continue;
            };
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
async fn overlapping_next_is_rejected_and_close_cancels_before_waiting_for_recv_lock() -> Result<()>
{
    let env = Environment::new().await?;
    let result = async {
        let (facade, reference) = conversation(&env).await?;
        let id = facade
            .open_content_watch(reference.clone(), range())
            .await?;
        let owner = facade
            .inner
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
        ensure!(facade.inner.watches.lookup(&id)?.is_none());
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
            .watches
            .lookup(&id)?
            .context("watch not registered")?;
        let (entered, release) = arm(&owner);
        let mut next = Box::pin(facade.next_content_window(id.clone()));
        reached(&mut next, entered).await?;
        drop(next);
        drop(release);
        ensure!(
            facade.inner.watches.lookup(&id)?.is_some(),
            "cancelling next is not close"
        );
        let failure = error(
            StudioErrorCode::Storage,
            "injected native watch close boundary",
        );
        *owner.hooks.close_failure.lock().unwrap() = Some(failure.clone());
        ensure!(facade.close_content_watch(id.clone()).await.unwrap_err() == failure);
        ensure!(
            facade.inner.watches.lookup(&id)?.is_some(),
            "a failed close must retain identity and capacity"
        );
        facade.close_content_watch(id.clone()).await?;
        ensure!(facade.inner.watches.lookup(&id)?.is_none());
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
        let reader = facade.inner.reader.clone();
        let reference = chat::protocol_content_ref(reference);
        let id = facade
            .inner
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
        ensure!(facade.inner.watches.lookup(&id)?.is_none());
        facade.close().await?;
        Ok(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn eof_keeps_explicit_ownership_and_capacity_and_foreign_ids_are_rejected() -> Result<()> {
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
            facade.inner.watches.lookup(&first)?.is_some(),
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
            .reader
            .read_content(&chat::protocol_content_ref(reference), chat::range(range()))
            .await
            .expect_err("watch failure must not skip read close");
        ensure!(BridgeError::from(read_failure).code == BridgeErrorCode::Cancelled);
        // Retrying close uses the same cancelled native owners and then releases their identities.
        // The facade may itself have retried them while retaining its original failure diagnostics.
        facade.close_content_watch(first.clone()).await?;
        facade.close_content_watch(second.clone()).await?;
        ensure!(facade.inner.watches.lookup(&first)?.is_none());
        ensure!(facade.inner.watches.lookup(&second)?.is_none());
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
