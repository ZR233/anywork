//! Current-file and live CurrentWriter ownership entry points.

use std::sync::Arc;

use anyhow::{Context, Result};
use pl_core::thread::current::{RuntimeEpoch, ThreadCurrent};

use super::super::current_writer::CurrentSaveReceipt;
use super::super::{
    coordinator::ThreadPersistenceCoordinator,
    current_file::CurrentFile,
    current_writer::{CurrentSaveState, CurrentSource, CurrentWriter},
};
use super::StateStore;

#[derive(Clone)]
pub(super) struct CurrentRegistration {
    coordinator: ThreadPersistenceCoordinator,
    writer: Arc<CurrentWriter>,
}

impl StateStore {
    /// Reads only this session's complete current file, without opening or consulting history.
    /// Invalid schema/identity or missing/corrupt resources leave all originals untouched.
    pub(crate) async fn load_current(&self) -> Result<Option<ThreadCurrent>> {
        let mut current = CurrentFile::new(self.directory.clone(), self.thread_id.clone())
            .load()
            .await?;
        if let Some(current) = current.as_mut() {
            crate::studio::producer_migration::permission_responses(
                current.state.permissions.values_mut(),
            )?;
        }
        Ok(current)
    }

    /// Registers the independent current writer for the live Thread owner.
    ///
    /// The expected predecessor is checked by the stable writer after all old I/O has ended.
    pub(crate) async fn attach_current(
        &mut self,
        coordinator: ThreadPersistenceCoordinator,
        previous_epoch: Option<RuntimeEpoch>,
        epoch: RuntimeEpoch,
        source: CurrentSource,
    ) -> Result<()> {
        let writer = coordinator
            .current_writer(&self.thread_id, self.directory.clone())
            .await?;
        // Keep subsequent loads/resources bound to the same resolved directory as the writer,
        // rather than following the caller's original alias again after activation.
        self.directory = writer.directory().to_owned();
        self.current = Some(CurrentRegistration {
            coordinator: coordinator.clone(),
            writer: writer.clone(),
        });
        self.coordinator = Some(coordinator);
        // Store the registration before await. Cancellation or failed admission leaves a handle
        // with which the caller can resume or explicitly close/join the registered writer.
        writer.activate(previous_epoch, epoch, source).await
    }

    pub(crate) async fn flush_current(&self, epoch: RuntimeEpoch) -> Result<CurrentSaveReceipt> {
        self.current
            .as_ref()
            .context("current source is not registered")?
            .writer
            .flush(epoch)
            .await
    }

    pub(crate) fn current_save_state(&self) -> Result<CurrentSaveState> {
        Ok(self
            .current
            .as_ref()
            .context("current source is not registered")?
            .writer
            .snapshot())
    }

    pub(crate) async fn close_current(
        &self,
        epoch: RuntimeEpoch,
        purpose: crate::thread_assembler::ClosePurpose,
    ) -> Result<()> {
        let Some(current) = self.current.as_ref() else {
            // Preparation can be sealed before a Current source was ever admitted. Such an
            // owner has no writer to join; this does not acknowledge a save or invent data.
            return Ok(());
        };
        let result = current.writer.close(epoch, purpose).await;
        // A failed final write keeps its lease and retained data for an explicit close retry.
        // Deletion releases it only after the actual worker join; stale closes release nothing.
        if current.writer.is_joined()
            && (result.is_ok()
                || purpose == crate::thread_assembler::ClosePurpose::Delete
                || current.writer.snapshot().runtime_epoch.is_none())
        {
            current
                .coordinator
                .release_current_writer(&self.thread_id, &current.writer);
        }
        if purpose == crate::thread_assembler::ClosePurpose::Delete && current.writer.is_joined() {
            // Explicit deletion needs the original worker and every capture/observer joined, but
            // does not promise to repair or save data that the user has asked to remove.
            return Ok(());
        }
        result
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn cold_current_read_normalizes_legacy_approval_response() -> Result<()> {
        use crate::thread_assembler::{APPROVAL_RESPONSE_FORMAT, StoredApprovalDecision};
        use pl_core::{
            context::OpaquePayload,
            thread::permissions::{PermissionRecord, PermissionState},
        };

        let directory = tempfile::tempdir()?;
        let thread_id = "approval-response";
        let mut saved = ThreadCurrent::new(thread_id.into(), RuntimeEpoch::new());
        let legacy = OpaquePayload::new(
            APPROVAL_RESPONSE_FORMAT,
            1,
            r#"{"decision":"approved","reason":"user confirmed"}"#,
        )?;
        let canonical = OpaquePayload::new(
            APPROVAL_RESPONSE_FORMAT,
            1,
            r#"{"decision":{"decision":"denied","reason":null},"operationId":"deny-once"}"#,
        )?;
        for (id, state, response) in [
            ("allowed", PermissionState::Allowed, legacy.clone()),
            ("denied", PermissionState::Denied, canonical.clone()),
        ] {
            saved.state.permissions.insert(
                id.into(),
                PermissionRecord {
                    created_at: 10,
                    updated_at: 11,
                    id: id.into(),
                    task_id: format!("task-{id}"),
                    call_id: format!("call-{id}"),
                    turn_id: "turn".into(),
                    tool_id: "fixture".into(),
                    revision: 2,
                    payload: OpaquePayload::new("pl.studio.tool-approval", 1, "{}")?,
                    response: Some(response),
                    state,
                },
            );
        }
        let file = CurrentFile::new(directory.path().into(), thread_id.into());
        file.save(saved).await?;
        let loaded = StateStore::new(directory.path().into(), thread_id)
            .load_current()
            .await?
            .context("saved Current")?;
        let record = &loaded.state.permissions["allowed"];
        let response = record.response.as_ref().context("permission response")?;
        let decision: StoredApprovalDecision = serde_json::from_str(response.content())?;
        assert_eq!(
            decision.decision.decision,
            crate::ToolApprovalResolution::Approved
        );
        assert_eq!(decision.decision.reason.as_deref(), Some("user confirmed"));
        assert_eq!(decision.operation_id, None);
        assert_eq!(record.revision, 2);
        assert_eq!(
            loaded.state.permissions["denied"].response.as_ref(),
            Some(&canonical)
        );
        let original = file.load().await?.context("unchanged Current file")?;
        assert_eq!(
            original.state.permissions["allowed"].response.as_ref(),
            Some(&legacy)
        );
        Ok(())
    }

    fn named_source(thread_id: &str) -> CurrentSource {
        let capture_id = thread_id.to_owned();
        let finish_id = capture_id.clone();
        CurrentSource::new(
            move |epoch, _| {
                let id = capture_id.clone();
                Box::pin(async move { Ok(ThreadCurrent::new(id, epoch)) })
            },
            move |epoch| {
                let id = finish_id.clone();
                Box::pin(async move { Ok(ThreadCurrent::new(id, epoch)) })
            },
        )
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn concurrent_threads_cannot_both_register_and_save_the_same_current_path() -> Result<()>
    {
        let root = tempfile::tempdir()?;
        let directory = root.path().join("not-created-yet");
        let coordinator = ThreadPersistenceCoordinator::default();
        let barrier = Arc::new(tokio::sync::Barrier::new(2));
        let requests = ["first-thread", "second-thread"].map(|id| {
            let directory = directory.clone();
            let coordinator = coordinator.clone();
            let barrier = barrier.clone();
            tokio::spawn(async move {
                let mut store = StateStore::new(directory, id);
                let epoch = RuntimeEpoch::new();
                barrier.wait().await;
                store
                    .attach_current(coordinator, None, epoch, named_source(id))
                    .await?;
                Ok::<_, anyhow::Error>((store, epoch, id))
            })
        });
        let mut accepted = Vec::new();
        let mut errors = Vec::new();
        for request in requests {
            match request.await? {
                Ok(store) => accepted.push(store),
                Err(error) => errors.push(error),
            }
        }
        let mut receipts = Vec::new();
        for (store, epoch, _) in &accepted {
            receipts.push(store.flush_current(*epoch).await?);
        }
        // Clean up even on the old implementation, which accepts and acknowledges both writers.
        for (store, epoch, _) in &accepted {
            store
                .close_current(*epoch, crate::thread_assembler::ClosePurpose::Preserve)
                .await?;
        }
        assert_eq!(
            accepted.len(),
            1,
            "one physical current path must have one registered Thread owner"
        );
        assert_eq!(
            receipts.len(),
            1,
            "competing Thread snapshots cannot both claim save success"
        );
        assert_eq!(errors.len(), 1);
        assert!(format!("{:#}", errors[0]).contains("registered"));
        let next_id = if accepted[0].2 == "first-thread" {
            "second-thread"
        } else {
            "first-thread"
        };
        let mut next = StateStore::new(directory, next_id);
        let epoch = RuntimeEpoch::new();
        next.attach_current(coordinator, None, epoch, named_source(next_id))
            .await?;
        next.flush_current(epoch).await?;
        assert_eq!(next.load_current().await?.unwrap().thread_id, next_id);
        next.close_current(epoch, crate::thread_assembler::ClosePurpose::Preserve)
            .await?;
        Ok(())
    }

    #[tokio::test]
    async fn independent_state_entry_points_reuse_thread_registration_until_real_join() -> Result<()>
    {
        let directory = tempfile::tempdir()?;
        let coordinator = ThreadPersistenceCoordinator::default();
        let epoch = RuntimeEpoch::new();
        let source = CurrentSource::new(
            |epoch, _| Box::pin(async move { Ok(ThreadCurrent::new("state-test".into(), epoch)) }),
            |epoch| {
                Box::pin(async move {
                    let mut current = ThreadCurrent::new("state-test".into(), epoch);
                    current.snapshot_revision = 7;
                    Ok(current)
                })
            },
        );
        let mut store = StateStore::new(directory.path().into(), "state-test");
        assert!(
            store
                .attach_current(coordinator.clone(), Some(epoch), epoch, source.clone())
                .await
                .is_err()
        );
        assert!(
            store
                .close_current(epoch, crate::thread_assembler::ClosePurpose::Preserve)
                .await
                .is_err(),
            "an unbound writer joins but cannot invent final data"
        );
        store
            .attach_current(coordinator.clone(), None, epoch, source.clone())
            .await?;
        let first = coordinator
            .current_writer("state-test", directory.path().into())
            .await?;
        let second = coordinator
            .current_writer("state-test", directory.path().into())
            .await?;
        assert!(Arc::ptr_eq(&first, &second));
        assert!(
            coordinator
                .current_writer("state-test", directory.path().join("another-session"))
                .await
                .is_err()
        );
        let history = coordinator.history_channel("state-test");
        coordinator.release_delivery_channel("state-test", &history);
        assert!(
            Arc::ptr_eq(
                &first,
                &coordinator
                    .current_writer("state-test", directory.path().into())
                    .await?
            ),
            "history teardown cannot release the current slot"
        );
        assert!(coordinator.forget_deleted("state-test").is_err());
        assert_eq!(store.flush_current(epoch).await?.runtime_epoch, epoch);
        assert_eq!(
            store
                .current_save_state()?
                .receipt
                .unwrap()
                .snapshot_revision,
            0
        );
        assert_eq!(
            coordinator.snapshot().pending_commits,
            0,
            "current does not advance history pressure or watermarks"
        );
        store
            .close_current(epoch, crate::thread_assembler::ClosePurpose::Preserve)
            .await?;
        assert!(first.is_joined());
        assert_eq!(store.load_current().await?.unwrap().snapshot_revision, 7);
        coordinator.forget_deleted("state-test")?;
        let mut next = StateStore::new(directory.path().into(), "state-test");
        next.attach_current(coordinator.clone(), None, RuntimeEpoch::new(), source)
            .await?;
        assert!(!Arc::ptr_eq(&first, &next.current.as_ref().unwrap().writer));
        next.close_current(
            next.current_save_state()?.runtime_epoch.unwrap(),
            crate::thread_assembler::ClosePurpose::Preserve,
        )
        .await?;
        Ok(())
    }

    #[tokio::test]
    async fn closed_writer_releases_registration_before_saved_current_starts_r2() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let coordinator = ThreadPersistenceCoordinator::default();
        let r1 = RuntimeEpoch::new();
        let mut first = StateStore::new(directory.path().into(), "cold-r2");
        first
            .attach_current(coordinator.clone(), None, r1, named_source("cold-r2"))
            .await?;
        first.flush_current(r1).await?;
        first
            .close_current(r1, crate::thread_assembler::ClosePurpose::Preserve)
            .await?;

        // The saved file still names R1, but the coordinator slot was released after a real join.
        // A newly registered writer is Unbound, so R2 admission must use `previous = None`.
        let r2 = RuntimeEpoch::new();
        let mut second = StateStore::new(directory.path().into(), "cold-r2");
        second
            .attach_current(coordinator, None, r2, named_source("cold-r2"))
            .await?;
        assert_eq!(second.current_save_state()?.runtime_epoch, Some(r2));
        assert_eq!(second.flush_current(r2).await?.runtime_epoch, r2);
        assert_eq!(
            second.load_current().await?.unwrap().saved_runtime_epoch,
            r2
        );
        second
            .close_current(r2, crate::thread_assembler::ClosePurpose::Preserve)
            .await?;
        Ok(())
    }

    #[tokio::test]
    async fn open_registered_writer_replaces_observer_with_actual_epoch_as_predecessor()
    -> Result<()> {
        let directory = tempfile::tempdir()?;
        let coordinator = ThreadPersistenceCoordinator::default();
        let r1 = RuntimeEpoch::new();
        let writer = coordinator
            .current_writer("replace-r1", directory.path().into())
            .await?;
        writer
            .activate(None, r1, named_source("replace-r1"))
            .await?;

        let r2 = RuntimeEpoch::new();
        let mut store = StateStore::new(directory.path().into(), "replace-r1");
        store
            .attach_current(
                coordinator.clone(),
                Some(r1),
                r2,
                named_source("replace-r1"),
            )
            .await?;
        assert_eq!(store.current_save_state()?.runtime_epoch, Some(r2));
        assert!(store.flush_current(r1).await.is_err());
        assert_eq!(store.flush_current(r2).await?.runtime_epoch, r2);
        store
            .close_current(r2, crate::thread_assembler::ClosePurpose::Preserve)
            .await?;
        Ok(())
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn physical_directory_aliases_reuse_one_slot_until_join_and_release() -> Result<()> {
        let root = tempfile::tempdir()?;
        let physical = root.path().join("physical-session");
        std::fs::create_dir(&physical)?;
        let alias = root.path().join("alias-session");
        std::os::unix::fs::symlink(&physical, &alias)?;
        let branch = root.path().join("branch");
        std::fs::create_dir(&branch)?;
        let normalized = branch.join("..").join("physical-session").join(".");
        let coordinator = ThreadPersistenceCoordinator::default();
        let writer = coordinator
            .current_writer("alias-owner", normalized.clone())
            .await?;
        let epoch = RuntimeEpoch::new();
        writer
            .activate(None, epoch, named_source("alias-owner"))
            .await?;
        let aliased = coordinator
            .current_writer("alias-owner", alias.clone())
            .await?;
        assert!(Arc::ptr_eq(&writer, &aliased));
        assert_eq!(writer.directory(), dunce::canonicalize(&physical)?);
        assert!(
            coordinator
                .current_writer("foreign-owner", alias.clone())
                .await
                .is_err()
        );
        assert!(
            coordinator
                .current_writer("foreign-owner", normalized)
                .await
                .is_err()
        );
        coordinator.release_current_writer("alias-owner", &writer);
        assert!(
            coordinator
                .current_writer("foreign-owner", physical.clone())
                .await
                .is_err(),
            "release before join cannot surrender physical ownership"
        );
        writer
            .close(epoch, crate::thread_assembler::ClosePurpose::Preserve)
            .await?;
        assert!(writer.is_joined());
        assert!(
            coordinator
                .current_writer("foreign-owner", alias.clone())
                .await
                .is_err(),
            "a completed writer remains reserved until its slot is released"
        );
        coordinator.release_current_writer("alias-owner", &writer);

        let next = coordinator.current_writer("foreign-owner", alias).await?;
        assert!(!Arc::ptr_eq(&writer, &next));
        let epoch = RuntimeEpoch::new();
        next.activate(None, epoch, named_source("foreign-owner"))
            .await?;
        next.flush(epoch).await?;
        let loaded = StateStore::new(physical.clone(), "foreign-owner")
            .load_current()
            .await?
            .unwrap();
        assert_eq!(loaded.thread_id, "foreign-owner");
        coordinator.release_current_writer("alias-owner", &writer); // stale release cannot clear next.
        assert!(Arc::ptr_eq(
            &next,
            &coordinator
                .current_writer("foreign-owner", physical.clone())
                .await?
        ));
        assert!(
            coordinator
                .current_writer("alias-owner", physical)
                .await
                .is_err()
        );
        next.close(epoch, crate::thread_assembler::ClosePurpose::Preserve)
            .await?;
        coordinator.release_current_writer("foreign-owner", &next);
        Ok(())
    }

    #[tokio::test]
    async fn directory_preparation_failure_preserves_io_error_and_does_not_reserve_a_writer()
    -> Result<()> {
        let root = tempfile::tempdir()?;
        let file = root.path().join("not-a-directory");
        std::fs::write(&file, b"preserve existing bytes")?;
        let coordinator = ThreadPersistenceCoordinator::default();
        let error = coordinator
            .current_writer("failed-prepare", file.join("session"))
            .await
            .unwrap_err();
        assert!(
            error
                .chain()
                .any(|source| source.downcast_ref::<std::io::Error>().is_some()),
            "the real filesystem error remains in the source chain"
        );
        assert_eq!(std::fs::read(file)?, b"preserve existing bytes");
        let fresh = root.path().join("created-by-registration");
        let writer = coordinator
            .current_writer("failed-prepare", fresh.clone())
            .await?;
        assert!(
            fresh.is_dir(),
            "a missing directory is identified only after real creation"
        );
        assert!(
            !fresh.join(crate::studio::paths::CURRENT_FILE_NAME).exists(),
            "preparation creates no current JSON"
        );
        let epoch = RuntimeEpoch::new();
        assert!(
            writer
                .close(epoch, crate::thread_assembler::ClosePurpose::Preserve)
                .await
                .is_err(),
            "unbound close cannot invent a final state"
        );
        coordinator.release_current_writer("failed-prepare", &writer);
        Ok(())
    }
}
