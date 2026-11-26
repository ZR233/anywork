use std::{path::Path, time::Duration};

use anyhow::Context;
use sea_orm::{ConnectionTrait, DbBackend, Statement};

use super::test_support::prepared_child_lease;
use super::*;
use crate::agent::worktree::{WorktreeManager, WorktreeOwnership};
use crate::studio::storage::write_behind::test_support::writer_with_lease_ack_gate;

fn assign_execution_use(
    owner: &WorktreeLeaseOwner,
    thread_id: &str,
    identity: &WorkspaceIdentity,
) -> Result<WorkspaceUsageLease> {
    let usage = owner.reserve_workspace(thread_id, identity.endpoint.clone())?;
    owner.assign_workspace(&usage, identity.clone())?;
    Ok(usage)
}

#[tokio::test]
async fn verified_binding_rejects_unassigned_and_foreign_execution_uses() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let writer = ThreadWriteBehindWriter::new(store.clone());
    let owner = WorktreeLeaseOwner::new(writer.clone());
    let expected = prepared_child_lease(temp.path(), "verified-child");
    owner.record_durable(expected.clone()).await?;
    let admitted = writer.admitted_ticket();
    let id = &expected.owner_thread_id;
    let identity = WorkspaceIdentity::canonical(WorkspaceEndpoint::Local, expected.path.clone())?;
    let wrong_identity = WorkspaceIdentity::canonical(
        WorkspaceEndpoint::Local,
        temp.path().to_string_lossy().into_owned(),
    )?;
    let foreign_owner = WorktreeLeaseOwner::new(writer.clone());

    for (usage, reason) in [
        (
            owner.reserve_workspace(id, WorkspaceEndpoint::Local)?,
            "requires an assigned execution workspace",
        ),
        (
            assign_execution_use(&foreign_owner, id, &identity)?,
            "belongs to another runtime owner",
        ),
        (
            assign_execution_use(&owner, "another-child", &identity)?,
            "does not belong to this execution use",
        ),
        (
            assign_execution_use(&owner, id, &wrong_identity)?,
            "differs from the assigned workspace",
        ),
        (
            owner.cleanup_resolution(id, identity)?,
            "does not belong to this execution use",
        ),
    ] {
        let error = owner
            .prepare_verified_binding(&expected, &usage)
            .err()
            .context("invalid use was admitted")?;
        assert!(error.to_string().contains(reason), "{reason}: {error:#}");
    }
    assert_eq!(writer.admitted_ticket(), admitted);
    assert_eq!(load_leases(&store).await?, vec![expected]);
    writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn verified_binding_rejects_changed_and_retiring_lease_revisions() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let writer = ThreadWriteBehindWriter::new(store);
    let owner = WorktreeLeaseOwner::new(writer.clone());
    let mut expected = prepared_child_lease(temp.path(), "verified-child");
    owner.record_durable(expected.clone()).await?;
    let identity = WorkspaceIdentity::canonical(WorkspaceEndpoint::Local, expected.path.clone())?;
    let usage = assign_execution_use(&owner, &expected.owner_thread_id, &identity)?;
    let mut changed = expected.clone();
    changed.base_commit = "b".repeat(40);
    let error = owner
        .confirm_verified_binding(&changed, &usage)
        .await
        .unwrap_err();
    assert!(error.to_string().contains("binding or revision changed"));

    for state in [
        WorktreeLeaseState::CleanupRequested,
        WorktreeLeaseState::Cleaned,
    ] {
        let previous = expected.clone();
        expected.transition(state);
        owner.record_durable(expected.clone()).await?;
        let admitted = writer.admitted_ticket();
        let stale = owner
            .confirm_verified_binding(&previous, &usage)
            .await
            .unwrap_err();
        assert!(
            stale.to_string().contains("binding or revision changed"),
            "{state:?}: {stale:#}"
        );
        let current = owner
            .confirm_verified_binding(&expected, &usage)
            .await
            .unwrap_err();
        assert!(
            current.to_string().contains("cannot be confirmed"),
            "{state:?}: {current:#}"
        );
        assert_eq!(writer.admitted_ticket(), admitted);
        assert_eq!(owner.get(&expected.owner_thread_id), Some(expected.clone()));
    }
    writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn preserved_binding_activates_once_and_refuses_confirmation_when_sealed() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let writer = ThreadWriteBehindWriter::new(store.clone());
    let owner = WorktreeLeaseOwner::new(writer.clone());
    let mut expected = prepared_child_lease(temp.path(), "verified-child");
    owner.record_durable(expected.clone()).await?;
    expected.transition(WorktreeLeaseState::Preserved);
    owner.record_durable(expected.clone()).await?;
    let identity = WorkspaceIdentity::canonical(WorkspaceEndpoint::Local, expected.path.clone())?;
    let usage = assign_execution_use(&owner, &expected.owner_thread_id, &identity)?;
    let active = owner.confirm_verified_binding(&expected, &usage).await?;
    assert_eq!(active.state, WorktreeLeaseState::Active);
    assert_eq!(active.revision, expected.revision + 1);
    let admitted = writer.admitted_ticket();
    assert_eq!(
        owner.confirm_verified_binding(&active, &usage).await?,
        active
    );
    owner.restore_workspace_seal(&active.owner_thread_id, identity)?;
    let sealed = owner
        .confirm_verified_binding(&active, &usage)
        .await
        .unwrap_err();
    assert!(sealed.to_string().contains("sealed for retirement"));
    assert_eq!(writer.admitted_ticket(), admitted);
    assert_eq!(load_leases(&store).await?, vec![active]);
    writer.shutdown().await?;
    Ok(())
}

async fn restore_saved_active_binding(
    store: &StudioStore,
    repo: &Path,
    writer: &ThreadWriteBehindWriter,
) -> Result<(WorktreeLeaseOwner, WorktreeLease, WorkspaceUsageLease)> {
    let mut active = prepared_child_lease(repo, "hydrated-active");
    let old_writer = ThreadWriteBehindWriter::new(store.clone());
    let old_owner = WorktreeLeaseOwner::new(old_writer.clone());
    old_owner.record_durable(active.clone()).await?;
    active.transition(WorktreeLeaseState::Active);
    old_owner.record_durable(active.clone()).await?;
    old_writer.shutdown().await?;

    let owner = WorktreeLeaseOwner::new(writer.clone());
    owner.restore(store, load_leases(store).await?).await?;
    assert_eq!(owner.get(&active.owner_thread_id), Some(active.clone()));
    assert_eq!(writer.admitted_ticket(), 0, "hydration must not enqueue");
    let identity = WorkspaceIdentity::canonical(WorkspaceEndpoint::Local, active.path.clone())?;
    let usage = assign_execution_use(&owner, &active.owner_thread_id, &identity)?;
    Ok((owner, active, usage))
}

#[tokio::test]
async fn hydrated_active_binding_waits_for_the_current_writer_ack() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let (writer, lease_acks) = writer_with_lease_ack_gate(store.clone());
    let (owner, active, usage) = restore_saved_active_binding(&store, temp.path(), &writer).await?;
    let (waiting, release) = lease_acks.arm(&active.owner_thread_id, WorktreeLeaseState::Active);
    let write = owner.prepare_verified_binding(&active, &usage)?;
    let ticket = writer.admitted_ticket();
    assert!(ticket > 0, "hydrated Active needs a current writer ticket");
    let reentry = owner.prepare_verified_binding(&active, &usage)?;
    assert_eq!(writer.admitted_ticket(), ticket);
    let mut confirming = Box::pin(owner.confirm_prepared_binding(write));
    assert!(futures::poll!(&mut confirming).is_pending());
    tokio::time::timeout(Duration::from_secs(5), waiting).await??;
    assert!(futures::poll!(&mut confirming).is_pending());
    assert_eq!(load_leases(&store).await?, vec![active.clone()]);
    assert!(!owner.is_durable(&active));
    release.send(()).unwrap();
    assert_eq!(confirming.await?, active);
    assert_eq!(owner.confirm_prepared_binding(reentry).await?, active);
    assert!(owner.is_durable(&active));
    writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn hydrated_active_binding_surfaces_a_real_revision_conflict_without_an_ack() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let writer = ThreadWriteBehindWriter::new(store.clone());
    let (owner, active, usage) = restore_saved_active_binding(&store, temp.path(), &writer).await?;
    // A competing persisted value at the hydrated revision must fail the real writer.
    let mut conflicting = active.clone();
    conflicting.base_commit = "b".repeat(40);
    let payload = serde_json::to_string(&conflicting)?;
    let hash = pl_core::context::content_hash(payload.as_bytes());
    let changed = store
        .database()
        .execute_raw(Statement::from_sql_and_values(
            DbBackend::Sqlite,
            "UPDATE studio_objects SET payload_json=?,payload_hash=? \
         WHERE owner_kind='agent' AND owner_id=? AND object_kind='worktreeLease'",
            [
                payload.into(),
                hash.into(),
                active.owner_thread_id.clone().into(),
            ],
        ))
        .await?;
    assert_eq!(changed.rows_affected(), 1);

    let failure = tokio::time::timeout(
        Duration::from_secs(5),
        owner.confirm_verified_binding(&active, &usage),
    )
    .await?
    .unwrap_err();
    assert!(
        failure.chain().any(|cause| cause
            .downcast_ref::<crate::PureError>()
            .is_some_and(|source| source.to_string().contains("revision conflicts"))),
        "{failure:#}"
    );
    assert!(matches!(
        writer.state_snapshot().state,
        crate::PersistenceState::Blocked(_)
    ));
    assert!(!crate::studio::thread_factory::is_workspace_preparation_failure(&failure));
    let wrapped = anyhow::Error::new(
        crate::thread_assembler::ThreadAssemblyError::ChildWorkspacePreparation {
            source: failure.reallocate_into_boxed_dyn_error_without_backtrace(),
        },
    );
    assert!(!crate::studio::thread_factory::is_workspace_preparation_failure(&wrapped));
    let mapped = crate::studio_error_from_anyhow(wrapped);
    assert_eq!(mapped.code, crate::StudioErrorCode::Storage);
    assert!(
        mapped.message.contains("persist the saved worktree lease"),
        "{mapped:?}"
    );
    assert!(mapped.retryable);
    assert!(writer.admitted_ticket() > 0);
    assert_eq!(writer.saved_watermark(), 0);
    assert!(!owner.is_durable(&active));
    assert_eq!(owner.get(&active.owner_thread_id), Some(active));
    assert_eq!(load_leases(&store).await?, vec![conflicting]);
    assert!(writer.shutdown().await.is_err());
    Ok(())
}

#[tokio::test]
async fn verified_binding_and_active_reentry_wait_for_the_exact_ack() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let (writer, lease_acks) = writer_with_lease_ack_gate(store.clone());
    let owner = WorktreeLeaseOwner::new(writer.clone());
    let prepared = prepared_child_lease(temp.path(), "ack-child");
    owner.record_durable(prepared.clone()).await?;
    let usage = owner.reserve_workspace(&prepared.owner_thread_id, WorkspaceEndpoint::Local)?;
    owner.assign_workspace(
        &usage,
        WorkspaceIdentity::canonical(WorkspaceEndpoint::Local, prepared.path.clone())?,
    )?;
    let (waiting, release) = lease_acks.arm(&prepared.owner_thread_id, WorktreeLeaseState::Active);
    let confirming_owner = owner.clone();
    let confirming_usage = usage.clone();
    let confirming = tokio::spawn(async move {
        confirming_owner
            .confirm_verified_binding(&prepared, &confirming_usage)
            .await
    });
    tokio::time::timeout(std::time::Duration::from_secs(5), waiting).await??;
    let active = owner.get("ack-child").context("admitted Active lease")?;
    assert_eq!(load_leases(&store).await?, vec![active.clone()]);
    assert!(!owner.is_durable(&active));
    assert!(!confirming.is_finished());
    let mut reentry = Box::pin(owner.confirm_verified_binding(&active, &usage));
    assert!(futures::poll!(&mut reentry).is_pending());
    // Cancelling one waiter must not lose the admitted write or bypass its original ACK.
    confirming.abort();
    assert!(confirming.await.unwrap_err().is_cancelled());
    assert!(futures::poll!(&mut reentry).is_pending());
    release.send(()).unwrap();
    assert_eq!(reentry.await?, active);
    assert!(owner.is_durable(&active));
    assert_eq!(load_leases(&store).await?, vec![active]);
    writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn verified_binding_rechecks_retirement_after_the_write_ack() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let (writer, lease_acks) = writer_with_lease_ack_gate(store.clone());
    let owner = WorktreeLeaseOwner::new(writer.clone());
    let prepared = prepared_child_lease(temp.path(), "sealed-during-ack");
    owner.record_durable(prepared.clone()).await?;
    let identity = WorkspaceIdentity::canonical(WorkspaceEndpoint::Local, prepared.path.clone())?;
    let usage = owner.reserve_workspace(&prepared.owner_thread_id, WorkspaceEndpoint::Local)?;
    owner.assign_workspace(&usage, identity.clone())?;
    let (waiting, release) = lease_acks.arm(&prepared.owner_thread_id, WorktreeLeaseState::Active);
    let confirming_owner = owner.clone();
    let confirming = tokio::spawn(async move {
        confirming_owner
            .confirm_verified_binding(&prepared, &usage)
            .await
    });
    tokio::time::timeout(std::time::Duration::from_secs(5), waiting).await??;
    let admitted = owner
        .get("sealed-during-ack")
        .context("admitted Active lease")?;
    assert!(!owner.is_durable(&admitted));
    owner.restore_workspace_seal(&admitted.owner_thread_id, identity.clone())?;
    release.send(()).unwrap();
    let failure = confirming.await?.unwrap_err();
    assert!(
        failure.to_string().contains("sealed for retirement"),
        "{failure:#}"
    );
    assert!(
        crate::studio::thread_factory::is_workspace_preparation_failure(&failure),
        "{failure:#}"
    );
    // The ACK still belongs to its original write; rejecting execution must not
    // erase the durable binding or remove the independent retirement seal.
    assert!(owner.is_durable(&admitted));
    assert_eq!(owner.get(&admitted.owner_thread_id), Some(admitted.clone()));
    let late_usage =
        owner.reserve_workspace(&admitted.owner_thread_id, WorkspaceEndpoint::Local)?;
    assert!(owner.assign_workspace(&late_usage, identity).is_err());
    writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn failed_session_retention_follows_only_the_original_confirmed_binding() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let writer = ThreadWriteBehindWriter::new(store.clone());
    let owner = WorktreeLeaseOwner::new(writer.clone());
    let mut prepared = prepared_child_lease(temp.path(), "failed-root");
    prepared.owner_kind = WorktreeLeaseOwnerKind::Session;
    prepared.root_thread_id = prepared.owner_thread_id.clone();
    prepared.path = WorktreeManager::allocate_path(
        temp.path(),
        &prepared.root_thread_id,
        &WorktreeOwnership::Session {
            thread_id: prepared.owner_thread_id.clone(),
        },
    )
    .to_string_lossy()
    .into_owned();
    owner.record_durable(prepared.clone()).await?;
    let identity = WorkspaceIdentity::canonical(WorkspaceEndpoint::Local, prepared.path.clone())?;
    let usage = owner.reserve_workspace(&prepared.owner_thread_id, WorkspaceEndpoint::Local)?;
    owner.assign_workspace(&usage, identity.clone())?;
    let active = owner.confirm_verified_binding(&prepared, &usage).await?;
    let mut retained = owner.preserve_failed_session_binding(&prepared).await?;
    assert_eq!(retained.state, WorktreeLeaseState::Preserved);
    assert_eq!(retained.revision, active.revision + 1);
    assert!(owner.is_durable(&retained));
    assert_eq!(
        owner.preserve_failed_session_binding(&prepared).await?,
        retained
    );
    let mut other_binding = prepared.clone();
    other_binding.base_commit = "b".repeat(40);
    assert!(
        owner
            .preserve_failed_session_binding(&other_binding)
            .await
            .is_err()
    );
    let mut conflicting_revision = retained.clone();
    conflicting_revision.state = WorktreeLeaseState::Active;
    assert!(
        owner
            .preserve_failed_session_binding(&conflicting_revision)
            .await
            .is_err()
    );
    for state in [
        WorktreeLeaseState::CleanupRequested,
        WorktreeLeaseState::Cleaned,
    ] {
        retained.transition(state);
        owner.record_durable(retained.clone()).await?;
        assert!(
            owner
                .preserve_failed_session_binding(&prepared)
                .await
                .is_err()
        );
        assert_eq!(owner.get(&prepared.owner_thread_id), Some(retained.clone()));
    }
    retained.transition(WorktreeLeaseState::Active);
    owner.record_durable(retained.clone()).await?;
    drop(usage);
    let removing = owner.begin_workspace_cleanup(&prepared.owner_thread_id, &identity, None)?;
    assert!(
        owner
            .preserve_failed_session_binding(&prepared)
            .await
            .is_err()
    );
    drop(removing);
    owner.restore_workspace_seal(&prepared.owner_thread_id, identity)?;
    assert!(
        owner
            .preserve_failed_session_binding(&prepared)
            .await
            .is_err()
    );
    assert_eq!(owner.get(&prepared.owner_thread_id), Some(retained));
    writer.shutdown().await?;
    Ok(())
}
