//! Shared admission stages for a sealed session tree.
//!
//! Archive and permanent deletion do not share a phase machine, recovery flags,
//! close policy, or command receipt. Archive keeps `ArchivePhase`; deletion keeps
//! `DeletePhase` and its independent physical-removal receipts. Both pin the
//! admitted tree, quiesce bot replies, cancel title tasks, and join preparations
//! inside the same close budget. Callers invoke those stages in their own order
//! and keep this value until publication so the pins and bot guard stay owned.

use anyhow::{Context, Result, bail};

use crate::bots::archive::BotArchiveGuard;
use crate::session::SessionRuntime;
use crate::thread_assembler::ArchiveScopeSeal;

use super::super::StudioRuntime;
use super::super::residency::ThreadResidencyPins;
use super::super::thread_title::ThreadTitleCancellationCause;
use crate::studio::store::thread_archive::{ArchivePhase, ThreadArchiveOperation};

/// Pins and bot quiescence for one sealed tree. Drop releases both, so the owner
/// must retain it through directory publication.
pub(super) struct TreeSettlementPipeline {
    bots: Option<BotArchiveGuard>,
    _pins: ThreadResidencyPins,
    ids: Vec<String>,
}

impl TreeSettlementPipeline {
    /// Pins the initially admitted identities. Later frozen ids are tracked for
    /// quiescence and membership checks, but are not pinned again.
    pub(super) fn pin(runtime: &StudioRuntime, ids: impl IntoIterator<Item = String>) -> Self {
        let mut ids = ids.into_iter().collect::<Vec<_>>();
        ids.sort();
        ids.dedup();
        let pins = runtime.residency.pin_many(ids.iter().cloned());
        Self {
            bots: None,
            _pins: pins,
            ids,
        }
    }

    pub(super) fn ids(&self) -> &[String] {
        &self.ids
    }

    pub(super) fn extend_ids(&mut self, extra: impl IntoIterator<Item = String>) {
        self.ids.extend(extra);
        self.ids.sort();
        self.ids.dedup();
    }

    pub(super) async fn quiesce(&mut self, runtime: &StudioRuntime) -> Result<()> {
        self.bots = Some(runtime.bots.quiesce_archive_threads(&self.ids).await?);
        Ok(())
    }

    pub(super) async fn cancel_titles(
        &self,
        runtime: &StudioRuntime,
        cause: ThreadTitleCancellationCause,
    ) {
        for id in &self.ids {
            runtime.title_tasks.cancel(id, cause).await;
        }
    }

    /// Joins one sealed scope inside the archive close budget. The timeout error
    /// keeps the caller's context; the inner join error is unchanged.
    pub(super) async fn join_scope(
        &self,
        session: &SessionRuntime,
        scope: &ArchiveScopeSeal,
        timeout_context: &'static str,
    ) -> Result<()> {
        tokio::time::timeout(
            super::super::ARCHIVE_TREE_SETTLE_TIMEOUT,
            session.drain_archive_preparations(scope),
        )
        .await
        .context(timeout_context)??;
        Ok(())
    }

    /// Project archive joins every sealed root inside one shared close budget.
    pub(super) async fn join_scopes(
        &self,
        scopes: &[(SessionRuntime, ArchiveScopeSeal)],
        timeout_context: &'static str,
    ) -> Result<()> {
        tokio::time::timeout(super::super::ARCHIVE_TREE_SETTLE_TIMEOUT, async {
            for (session, scope) in scopes {
                session.drain_archive_preparations(scope).await?;
            }
            Ok::<(), crate::thread_assembler::ThreadAssemblyError>(())
        })
        .await
        .context(timeout_context)??;
        Ok(())
    }

    pub(super) fn ensure_frozen<'a>(
        &self,
        member_ids: impl IntoIterator<Item = &'a str>,
        failure: &'static str,
    ) -> Result<()> {
        if member_ids
            .into_iter()
            .any(|id| !self.ids.iter().any(|admitted| admitted == id))
        {
            bail!("{}", failure);
        }
        Ok(())
    }
}

impl StudioRuntime {
    /// Archive-only tail: retire sealed owners, confirm the save ACK, then clean temps.
    ///
    /// Saved and Cleaned already own those receipts. This does not publish the
    /// directory or build a command receipt; thread and project archives do that
    /// themselves. Permanent deletion does not enter this phase machine.
    pub(super) async fn finish_sealed_archive(
        &self,
        archive: &mut ThreadArchiveOperation,
        thread_ids: &[String],
    ) -> Result<()> {
        if archive.phase == ArchivePhase::Sealed {
            self.retire_archived_thread_tree(thread_ids).await?;
            self.retire_private_archive_members(archive).await?;
        }
        // Saved/Cleaned already own the durable stop/save/retirement ACKs. Reopening a cold
        // writer on retry would recreate temp through directory projection after its cleanup ACK.
        self.archive_save_confirmed(archive).await?;
        self.clean_archive_temps(archive).await?;
        Ok(())
    }
}
