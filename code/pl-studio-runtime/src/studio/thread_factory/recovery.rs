//! Current-layout checkpoint loading for cold Threads.
//!
//! Old shared journals remain isolated outside v2. Activation and timeline queries only read
//! current session storage; checkpoints are validated on explicit activation.

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
