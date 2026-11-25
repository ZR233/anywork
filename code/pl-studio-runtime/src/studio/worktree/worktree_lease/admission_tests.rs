use super::*;
use std::collections::BTreeSet;
use std::panic::{AssertUnwindSafe, catch_unwind};

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
