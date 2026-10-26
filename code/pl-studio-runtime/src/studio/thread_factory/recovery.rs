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
//!   thread snapshot, timeline pages/content handles, Turn pages and interaction reads. Those report
//!   only already-durable facts; an unsupported or still-legacy structure stays invisible and a
//!   storage fault is returned as a typed error.

use anyhow::Result;
use pl_core::thread::ThreadCheckpoint;

use crate::studio::StudioStore;

pub(crate) async fn load_checkpoint(
    store: &StudioStore,
    thread: &pl_protocol::Thread,
) -> Result<Option<ThreadCheckpoint>> {
    let history = store.history_for(&thread.project_id, &thread.id).await?;
    store
        .state_for(&thread.project_id, &thread.id)?
        .load(&history)
        .await
}

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
pub(crate) async fn load_checkpoint_for_recovery(
    store: &StudioStore,
    thread: &pl_protocol::Thread,
) -> Result<Option<ThreadCheckpoint>> {
    let history = store.history_for(&thread.project_id, &thread.id).await?;
    let Some(checkpoint) = store
        .state_for(&thread.project_id, &thread.id)?
        .load_after_migration(&history)
        .await?
    else {
        return Ok(None);
    };
    let migrated = history
        .migrate_recovery_checkpoint(&checkpoint, |state| {
            // Absence in old v2 data stays absent: never manufacture closure from core lifecycle.
            crate::studio::agent_close::is_explicitly_closed(state)?;
            crate::studio::model_route::migrate_saved_representation(state)?;
            crate::studio::delegation::migrate(state)
        })
        .await?;
    Ok(Some(migrated))
}
