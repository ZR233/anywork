//! Current-layout checkpoint loading for cold Threads.
//!
//! Old shared journals remain isolated outside v2; checkpoints are validated on explicit activation.
//!
//! Which entries may touch storage:
//!
//! - **May prepare the current store**: [`load_checkpoint_for_recovery`] and the explicit
//!   activation/recovery entries that call it. Legacy import is owned by the catalog preparation
//!   boundary before activation, and its source files remain preserved.
//! - **Must never migrate**: [`load_checkpoint_read_only`] and every projection — directory listing,
//!   thread snapshot, timeline pages/content handles, Turn pages and interaction reads. Those report
//!   only already-durable facts; an unsupported or still-legacy structure stays invisible and a
//!   storage fault is returned as a typed error.

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

/// Explicit activation or parent continuation validates current history before decoding state.
/// This prepares storage only; it never installs an owner or executes the recovered Thread.
///
/// Root and child recovery share this boundary. It never guesses a missing current store to be a
/// new Thread, imports a legacy source, or deletes the files that a migration preserved.
pub(crate) async fn load_checkpoint_for_recovery(
    store: &StudioStore,
    thread: &pl_protocol::Thread,
) -> Result<Option<ThreadCheckpoint>> {
    let history = store.history_for(&thread.project_id, &thread.id).await?;
    history.prepare_activation().await?;
    history.checkpoint().await
}
