//! Deterministic registry/owner interleavings; no model, real user workspace or remote endpoint.
use super::*;
use crate::thread_assembler::{
    ChildThreadRequest, Entry, EntryPurpose, Preparation, StudioChildFactory, StudioThreadSpec,
    child_resources::{UnpublishedChild, WorkspacePreparationOwner},
    children::{ChildFactory, PreparingChild},
};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use tokio_util::sync::CancellationToken;

#[test]
fn contradictory_archive_parentage_fails_before_sealing_or_cancelling_any_owner() {
    let owner = StudioThreadAssembler::default();
    let cancellation = CancellationToken::new();
    {
        let mut state = owner.0.state();
        state.creating.insert(
            "child".into(),
            Preparation {
                purpose: None,
                parent_id: Some("root".into()),
                cancellation: cancellation.clone(),
                result: None,
            },
        );
        state.preparing_children.insert(
            "child".into(),
            PreparingChild {
                parent: "another-root".into(),
                cancellation: cancellation.clone(),
            },
        );
    }
    assert!(matches!(
        owner.seal_archive_scope(&["root".into()]),
        Err(ThreadAssemblyError::Identity(_))
    ));
    assert!(!cancellation.is_cancelled());
    assert!(owner.0.state().sealed_agents.is_empty());
}

#[tokio::test]
async fn archive_seals_and_cancels_before_waiting_on_a_preparer_owned_root_permit() {
    let owner = StudioThreadAssembler::default();
    let reservation = owner.reserve("root", None).unwrap();
    let unrelated = owner.reserve("unrelated", None).unwrap();
    let root_cancel = owner.0.state().creating["root"].cancellation.clone();
    let unrelated_cancel = owner.0.state().creating["unrelated"].cancellation.clone();
    let permit = owner.agent_operation("root").await;
    let scope = owner.seal_archive_scope(&["root".into()]).unwrap();
    assert!(
        root_cancel.is_cancelled(),
        "broadcast must precede the permit wait"
    );
    assert!(!unrelated_cancel.is_cancelled());
    assert!(matches!(
        owner.reserve("late", Some("root")),
        Err(ThreadAssemblyError::Closed)
    ));
    {
        let drain = owner.drain_archive_preparations(&scope);
        tokio::pin!(drain);
        assert!(futures::poll!(&mut drain).is_pending());
        drop(permit);
        assert!(
            futures::poll!(&mut drain).is_pending(),
            "the permit alone is not preparation completion"
        );
        drop(reservation);
        tokio::time::timeout(std::time::Duration::from_secs(2), &mut drain)
            .await
            .unwrap()
            .unwrap();
    }
    drop(scope);
    assert!(
        owner.reserve("root", None).is_ok(),
        "RAII admission must not become a permanent close"
    );
    drop(unrelated);
}

#[derive(Debug)]
struct Disposal {
    fail: Arc<AtomicBool>,
    calls: Arc<AtomicUsize>,
    resource: std::path::PathBuf,
    gate: Option<(
        tokio::sync::watch::Sender<bool>,
        Arc<tokio::sync::Semaphore>,
    )>,
}

impl StudioChildFactory for Disposal {
    async fn prepare(
        &self,
        _: ChildThreadRequest,
    ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
        Err(ThreadAssemblyError::Closed)
    }
    async fn discard_unpublished(
        &self,
        _: &str,
        _: Option<&crate::studio::WorkspaceUsageLease>,
        _: pl_tool::collaboration::thread::WorkspaceRelease,
    ) -> Result<(), ThreadAssemblyError> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        if let Some((entered, release)) = &self.gate {
            entered.send_replace(true);
            release.acquire().await.unwrap().forget();
        }
        if self.fail.load(Ordering::SeqCst) {
            return Err(ThreadAssemblyError::Resource {
                operation: "injected unpublished disposal failure",
                source: Box::new(std::io::Error::other("disposal failed")),
            });
        }
        tokio::fs::remove_file(&self.resource)
            .await
            .map_err(|source| ThreadAssemblyError::Resource {
                operation: "dispose isolated prepared resource",
                source: Box::new(source),
            })
    }
}

#[tokio::test]
async fn archive_closure_keeps_unpublished_resources_until_the_real_disposal_ack_and_retry() {
    let temp = tempfile::tempdir().unwrap();
    let resource = temp.path().join("prepared-resource");
    tokio::fs::write(&resource, b"still owned").await.unwrap();
    let owner = StudioThreadAssembler::default();
    let fail = Arc::new(AtomicBool::new(true));
    let calls = Arc::new(AtomicUsize::new(0));
    let preparation_cancel = CancellationToken::new();
    let child_cancel = CancellationToken::new();
    {
        let mut state = owner.0.state();
        state.creating.insert(
            "creating-child".into(),
            Preparation {
                purpose: None,
                parent_id: Some("root".into()),
                cancellation: preparation_cancel.clone(),
                result: None,
            },
        );
        state.preparing_children.insert(
            "unpublished-grandchild".into(),
            PreparingChild {
                parent: "creating-child".into(),
                cancellation: child_cancel.clone(),
            },
        );
        state.unpublished_children.insert(
            "unpublished-grandchild".into(),
            UnpublishedChild {
                retirement: Default::default(),
                workspace: WorkspacePreparationOwner::default(),
                parent: "creating-child".into(),
                cleanup: Default::default(),
                disposal: Default::default(),
                factory: ChildFactory::new(Disposal {
                    fail: fail.clone(),
                    calls: calls.clone(),
                    resource: resource.clone(),
                    gate: None,
                }),
            },
        );
    }
    let scope = owner.seal_archive_scope(&["root".into()]).unwrap();
    assert!(preparation_cancel.is_cancelled() && child_cancel.is_cancelled());
    assert_eq!(
        scope.thread_ids(),
        vec!["unpublished-grandchild", "creating-child", "root"]
    );
    let drain = owner.drain_archive_preparations(&scope);
    tokio::pin!(drain);
    assert!(futures::poll!(&mut drain).is_pending());
    {
        let mut state = owner.0.state();
        state.creating.remove("creating-child");
        state.preparing_children.remove("unpublished-grandchild");
    }
    owner.0.changed.notify_waiters();
    assert!(drain.await.is_err());
    assert!(resource.exists());
    assert!(
        owner
            .0
            .state()
            .unpublished_children
            .contains_key("unpublished-grandchild")
    );
    fail.store(false, Ordering::SeqCst);
    owner.drain_archive_preparations(&scope).await.unwrap();
    assert!(!resource.exists());
    assert!(
        !owner
            .0
            .state()
            .unpublished_children
            .contains_key("unpublished-grandchild")
    );
    assert_eq!(calls.load(Ordering::SeqCst), 2);
}

#[tokio::test]
async fn archive_seal_racing_publication_cannot_release_the_unpublished_owner() {
    let owner = StudioThreadAssembler::default();
    let temp = tempfile::tempdir().unwrap();
    let resource = temp.path().join("resource");
    tokio::fs::write(&resource, b"owned").await.unwrap();
    let child = pl_core::thread::ThreadHandle::resume_without_model("child".into(), None).unwrap();
    let calls = Arc::new(AtomicUsize::new(0));
    {
        let mut state = owner.0.state();
        state.entries.insert(
            "child".into(),
            Entry {
                purpose: EntryPurpose::Execution,
                workspace_usage: None,
                close_storage: None,
                published_resources_closed: false,
                workspace_disposition: None,
                cleanup: Default::default(),
                execution: pl_core::thread::input::InputDriverOptions {
                    max_model_steps: pl_core::thread::ModelStepLimit::Limited(
                        std::num::NonZeroU32::new(1).unwrap(),
                    ),
                },
                incarnation: Arc::new(()),
                parent_id: Some("root".into()),
                ready: false,
                thread: child,
            },
        );
        state.unpublished_children.insert(
            "child".into(),
            UnpublishedChild {
                retirement: Default::default(),
                workspace: Default::default(),
                parent: "root".into(),
                cleanup: Default::default(),
                disposal: Default::default(),
                factory: ChildFactory::new(Disposal {
                    fail: Arc::new(AtomicBool::new(false)),
                    calls: calls.clone(),
                    resource: resource.clone(),
                    gate: None,
                }),
            },
        );
    }
    let scope = owner.seal_archive_scope(&["root".into()]).unwrap();
    assert!(matches!(
        owner.publish_child_resources("child"),
        Err(ThreadAssemblyError::Closed)
    ));
    assert!(owner.0.state().unpublished_children.contains_key("child"));
    owner.drain_archive_preparations(&scope).await.unwrap();
    assert!(!owner.0.state().entries.contains_key("child"));
    assert!(!resource.exists());
    assert_eq!(calls.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn cancelled_archive_waiter_rejoins_the_original_unpublished_disposal() {
    let owner = StudioThreadAssembler::default();
    let temp = tempfile::tempdir().unwrap();
    let resource = temp.path().join("resource");
    tokio::fs::write(&resource, b"owned").await.unwrap();
    let calls = Arc::new(AtomicUsize::new(0));
    let (entered, mut observed) = tokio::sync::watch::channel(false);
    let release = Arc::new(tokio::sync::Semaphore::new(0));
    owner.0.state().unpublished_children.insert(
        "child".into(),
        UnpublishedChild {
            retirement: Default::default(),
            workspace: Default::default(),
            parent: "root".into(),
            cleanup: Default::default(),
            disposal: Default::default(),
            factory: ChildFactory::new(Disposal {
                fail: Arc::new(AtomicBool::new(false)),
                calls: calls.clone(),
                resource: resource.clone(),
                gate: Some((entered, release.clone())),
            }),
        },
    );
    let scope = owner.seal_archive_scope(&["root".into()]).unwrap();
    let caller = owner.clone();
    let waiter = tokio::spawn(async move { caller.drain_archive_preparations(&scope).await });
    while !*observed.borrow_and_update() {
        observed.changed().await.unwrap();
    }
    waiter.abort();
    assert!(waiter.await.unwrap_err().is_cancelled());
    assert!(resource.exists());
    assert!(owner.0.state().unpublished_children.contains_key("child"));
    let retry_scope = owner.seal_archive_scope(&["root".into()]).unwrap();
    let retry = owner.drain_archive_preparations(&retry_scope);
    tokio::pin!(retry);
    assert!(futures::poll!(&mut retry).is_pending());
    release.add_permits(1);
    retry.await.unwrap();
    assert!(!resource.exists());
    assert_eq!(
        calls.load(Ordering::SeqCst),
        1,
        "retry joins, not restarts, the retained producer"
    );
}
