use super::test_support::prepared_child_lease;
use super::*;
use std::collections::BTreeSet;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::path::Path;

#[tokio::test]
async fn poisoned_owner_releases_receipts_and_keeps_retirement_sealed() -> Result<()> {
    let writer = ThreadWriteBehindWriter::new(StudioStore::open_memory().await?);
    let owner = WorktreeLeaseOwner::new(writer.clone());
    let endpoint = WorkspaceEndpoint::Ssh {
        host: "remote.invalid".into(),
        port: 22,
        username: "worker".into(),
    };
    let identity = WorkspaceIdentity::canonical(endpoint.clone(), "/repo/checkout".into())?;
    let creating = owner.creation_guard("child");
    let usage = owner.reserve_workspace("child", endpoint.clone())?;
    owner.assign_workspace(&usage, identity.clone())?;
    let seal =
        owner.try_seal_workspace("root", identity.clone(), &BTreeSet::from(["child".into()]))?;

    assert!(
        catch_unwind(AssertUnwindSafe(|| {
            let _state = owner.state.lock().unwrap();
            panic!("simulate a panicking holder without changing its admitted state");
        }))
        .is_err()
    );
    drop(creating);
    drop(usage);
    assert!(!owner.is_creating("child"));
    owner.ensure_thread_workspace_idle("child")?;
    seal.durable()?;

    let next = owner.reserve_workspace("next", endpoint)?;
    let rejected = owner.assign_workspace(&next, identity.clone()).unwrap_err();
    assert!(rejected.to_string().contains("sealed for retirement"));
    owner.release_workspace_seal("root", &identity)?;
    owner.assign_workspace(&next, identity)?;
    drop(next);
    owner.ensure_thread_workspace_idle("next")?;
    writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn restored_ssh_cleanup_authority_requires_the_saved_endpoint_and_an_idle_workspace()
-> Result<()> {
    for has_binding in [true, false] {
        let temp = tempfile::tempdir()?;
        let database = temp.path().join("data/studio.sqlite");
        let store = StudioStore::open(&database).await?;
        let mut active = prepared_child_lease(Path::new("/repository"), "cold-ssh-child");
        active.repository_root = "/repository".into();
        active.path = "/repository/.anywork/worktrees/root/cold-ssh-child".into();
        active.ssh_alias = Some("original-alias".into());
        let identity = WorkspaceIdentity::canonical(
            WorkspaceEndpoint::Ssh {
                host: "original.example".into(),
                port: 22,
                username: "fixture".into(),
            },
            active.path.clone(),
        )?;
        if has_binding {
            store
                .bind_workspace_identity(&active.owner_thread_id, &identity)
                .await?;
        }
        let old_writer = ThreadWriteBehindWriter::new(store.clone());
        let old_owner = WorktreeLeaseOwner::new(old_writer.clone());
        old_owner.record_durable(active.clone()).await?;
        active.transition(WorktreeLeaseState::Active);
        old_owner.record_durable(active.clone()).await?;
        old_writer.shutdown().await?;
        drop(old_owner);
        drop(store);

        let store = StudioStore::open(&database).await?;
        let writer = ThreadWriteBehindWriter::new(store.clone());
        let owner = WorktreeLeaseOwner::new(writer.clone());
        owner.restore(&store, load_leases(&store).await?).await?;
        assert_eq!(writer.admitted_ticket(), 0, "restore must not write leases");
        if has_binding {
            let borrower = owner.reserve_workspace("borrower", identity.endpoint.clone())?;
            owner.assign_workspace(&borrower, identity.clone())?;
            assert!(
                owner
                    .begin_workspace_cleanup(&active.owner_thread_id, &identity, None)
                    .is_err(),
                "saved identity must not bypass a live borrower"
            );
            drop(borrower);
            let changed = WorkspaceIdentity::canonical(
                WorkspaceEndpoint::Ssh {
                    host: "replacement.example".into(),
                    port: 22,
                    username: "fixture".into(),
                },
                identity.root.clone(),
            )?;
            assert!(
                owner
                    .begin_workspace_cleanup(&active.owner_thread_id, &changed, None)
                    .is_err(),
                "the same path on a different endpoint is not deletion authority"
            );
            // No execution owner or SSH connection is needed to recover cleanup authority.
            let removal =
                owner.begin_workspace_cleanup(&active.owner_thread_id, &identity, None)?;
            drop(removal);
            owner
                .begin_workspace_cleanup(&active.owner_thread_id, &identity, None)?
                .complete();
        } else {
            assert!(
                owner
                    .begin_workspace_cleanup(&active.owner_thread_id, &identity, None)
                    .is_err(),
                "an old alias without a saved endpoint must remain protected"
            );
        }
        writer.shutdown().await?;
    }
    Ok(())
}
