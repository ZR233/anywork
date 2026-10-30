//! Current-layout checkpoint loading for cold Threads.
//!
//! Old shared journals remain isolated outside v2; checkpoints are validated on explicit activation.
//!
//! Which entries may touch storage:
//!
//! - **May migrate** (import a legacy checkpoint, delete the files it replaced, upgrade saved
//!   representations): [`load_checkpoint_for_recovery`] and the explicit activation/recovery entries
//!   that call it. Per design/17 a child that is not loaded is migrated by its own single history
//!   writer before anyone reads it.
//! - **Must never migrate**: [`load_checkpoint_read_only`] and every projection — directory listing,
//!   thread snapshot and interaction reads. Explicit content handles and Turn pages first prepare
//!   existing SQLite content at their own entry, then use these read-only projections. Unsupported
//!   or still-legacy SQLite structures fail explicitly, never masquerading as absent facts.

use anyhow::Result;
use pl_core::thread::ThreadCheckpoint;

use crate::studio::StudioStore;

/// Strictly read-only checkpoint read for projections that must not prepare or migrate storage.
///
/// A read-only projection reports only already-durable facts; a legacy checkpoint that still needs
/// import stays invisible until an explicit recovery/activation entry migrates it.
pub(crate) async fn load_checkpoint_read_only(
    store: &StudioStore,
    thread: &pl_protocol::Thread,
) -> Result<Option<ThreadCheckpoint>> {
    let history = store.history_for(&thread.project_id, &thread.id).await?;
    store
        .state_for(&thread.project_id, &thread.id)?
        .load_read_only(&history)
        .await
}

/// Explicit activation or parent continuation migrates history before decoding restart state.
/// This prepares storage only; it never installs an owner or executes the recovered Thread.
///
/// Model-access extensions saved by a retired format are committed as the current representation
/// here, in the single history writer transaction, before any owner or model sees the checkpoint.
/// Root and child recovery share this boundary, so a saved v1 route or Agent Profile never stays in
/// the old shape just because the Thread was not opened again by its previous owner.
pub(crate) fn load_checkpoint_for_recovery<'a>(
    store: &'a StudioStore,
    thread: &'a pl_protocol::Thread,
) -> impl std::future::Future<Output = Result<Option<ThreadCheckpoint>>> + Send + 'a {
    // Cold root/child recovery owns the import/model-preparation state on the heap. Every
    // activation and parent continuation shares this boundary; polling and cancellation stay
    // with the caller, rather than creating an independently running recovery task.
    Box::pin(async move {
        let history = store.history_for(&thread.project_id, &thread.id).await?;
        let Some(_) = store
            .state_for(&thread.project_id, &thread.id)?
            .prepare_recovery(&history)
            .await?
        else {
            return Ok(None);
        };
        history.prepare_model_access().await
    })
}
