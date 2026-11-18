//! Current-layout loading for cold Threads.
//!
//! Pre-v2 shared journals remain isolated; complete current documents are validated on activation.
//!
//! Which entries may touch storage:
//!
//! - **May prepare storage** (one-shot schema upgrade or legacy current materialization):
//!   [`load_current_for_recovery`] and explicit activation/recovery entries that call it,
//!   including a cold Current reader preparing its first saved baseline.
//! - **Must never prepare storage**: [`load_current_read_only`] and every projection — directory
//!   listing, Thread snapshot and interaction reads. They report only an already-complete
//!   `current.json`; missing and invalid current stay distinct at their normal error boundaries.

use anyhow::Result;
use pl_core::thread::current::ThreadCurrent;

use crate::studio::StudioStore;

/// Strictly read-only current read for projections that must not prepare or migrate storage.
///
/// A read-only projection reports only an already-complete current document. A legacy checkpoint
/// that still needs materialization stays invisible until an explicit recovery/activation entry
/// prepares it.
pub(crate) async fn load_current_read_only(
    store: &StudioStore,
    thread: &crate::Thread,
) -> Result<Option<ThreadCurrent>> {
    store
        .state_for(&thread.workspace_id, &thread.id)?
        .load_current()
        .await
}

/// Explicit activation, parent continuation or archive prepares one-shot storage before decoding
/// restart state. Production still receives the complete `ThreadCurrent`; this function never
/// reconstructs a Core checkpoint, history fence or snapshot bridge.
pub(crate) fn load_current_for_recovery<'a>(
    store: &'a StudioStore,
    thread: &'a crate::Thread,
) -> impl std::future::Future<Output = Result<Option<ThreadCurrent>>> + Send + 'a {
    Box::pin(async move {
        let state = store.state_for(&thread.workspace_id, &thread.id)?;
        if let Some(current) = state.load_current().await? {
            return Ok(Some(current));
        }
        // An old Thread may not have current.json until the parent-owned maintenance gate upgrades
        // its schema-24 history. Ordinary current reads never take this branch.
        let history_path = store
            .registered_session_paths(&thread.id)?
            .history_database();
        if tokio::fs::try_exists(history_path).await? || state.legacy_checkpoint().await?.is_some()
        {
            drop(store.history_for(&thread.workspace_id, &thread.id).await?);
            return state.load_current().await;
        }
        Ok(None)
    })
}
