//! Current-layout loading for cold Threads.
//!
//! Pre-v2 shared journals remain isolated; complete current documents are validated on activation.
//!
//! Which entries may touch storage:
//!
//! - **May prepare storage** (one-shot schema upgrade or legacy current materialization):
//!   [`load_current_for_recovery`] when called by explicit activation or other storage maintenance.
//! - **Read-only**: [`StudioStore::load_current_read_only`] and projections such as directory
//!   listing, Thread snapshot and interaction reads report only an already-complete
//!   `current.json`; missing and invalid current stay distinct at their normal error boundaries.

use anyhow::Result;
use pl_core::thread::current::ThreadCurrent;

use crate::studio::{StudioStore, producer_migration, session_data_error::SessionDataError};

/// Explicit activation, parent continuation or archive prepares one-shot storage before decoding
/// restart state. Production still receives the complete `ThreadCurrent`; this function never
/// reconstructs a Core checkpoint, history fence or snapshot bridge.
pub(crate) fn load_current_for_recovery<'a>(
    store: &'a StudioStore,
    thread: &'a crate::Thread,
) -> impl std::future::Future<Output = Result<Option<ThreadCurrent>>> + Send + 'a {
    Box::pin(async move {
        load_saved_current(store, thread)
            .await
            .map_err(SessionDataError::Load)?
            .map(prepare_loaded_current)
            .transpose()
    })
}

async fn load_saved_current(
    store: &StudioStore,
    thread: &crate::Thread,
) -> Result<Option<ThreadCurrent>> {
    let session = store.session_paths(&thread.workspace_id, &thread.id)?;
    store
        .thread_persistence()
        .upgrade_current_for_recovery(&thread.id, session.root().to_path_buf())
        .await?;
    let state = store.state_for(&thread.workspace_id, &thread.id)?;
    if let Some(current) = state.load_current().await? {
        return Ok(Some(current));
    }
    // An old Thread may not have current.json until the parent-owned maintenance gate upgrades
    // its schema-24 history. Ordinary current reads never take this branch.
    let history_path = store
        .registered_session_paths(&thread.id)?
        .history_database();
    if tokio::fs::try_exists(history_path).await? || state.legacy_checkpoint().await?.is_some() {
        drop(store.history_for(&thread.workspace_id, &thread.id).await?);
        return state.load_current().await;
    }
    Ok(None)
}

fn prepare_loaded_current(mut current: ThreadCurrent) -> Result<ThreadCurrent> {
    producer_migration::prepare_model_current(&mut current)?;
    producer_migration::prepare_plan_current(&mut current.state.extensions)?;
    Ok(current)
}
