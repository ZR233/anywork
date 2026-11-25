use crate::thread_assembler::test_support::*;
use crate::thread_assembler::*;
/// Real publication failure retains the close owner and the original cleanup authorization.
#[tokio::test]
async fn cancelled_unpublished_cleanup_keeps_the_real_preparer_until_disposal_joins() -> Result<()>
{
    #[derive(Debug)]
    struct DelayedDisposal {
        factory: crate::studio::StudioThreadFactory,
        entered: tokio::sync::watch::Sender<bool>,
        release: Arc<tokio::sync::Semaphore>,
    }
    impl StudioChildFactory for DelayedDisposal {
        type Admission = ();

        async fn admit(
            &self,
            _: &str,
            _: crate::DelegationSettings,
            _: Option<crate::NewThreadModelRoute>,
        ) -> Result<(), ThreadAssemblyError> {
            Ok(())
        }

        async fn prepare(
            &self,
            _: ChildThreadRequest,
            _: (),
        ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
            Err(ThreadAssemblyError::Closed)
        }
        async fn discard_unpublished(
            &self,
            id: &str,
            usage: Option<&WorkspaceUsageLease>,
            disposition: WorkspaceRelease,
        ) -> Result<(), ThreadAssemblyError> {
            self.entered.send_replace(true);
            let _permit = self.release.acquire().await.map_err(storage_error)?;
            super::super::StudioChildResources::discard_unpublished(
                &self.factory,
                id,
                usage,
                disposition,
            )
            .await
        }
    }
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let resources = crate::studio::storage_fault_test_support::close_factory(&store)?;
    let root = temp.path().join("shared-root");
    tokio::fs::create_dir_all(&root).await?;
    let preparation = resources
        .unpublished_workspace("unpublished-directory", &root)
        .await?;
    let owner = SessionRuntime::default();
    let (entered, mut observed) = tokio::sync::watch::channel(false);
    let release = Arc::new(tokio::sync::Semaphore::new(0));
    owner.0.state().activation.unpublished_children.insert(
        "unpublished-directory".into(),
        super::super::child_resources::UnpublishedChild {
            retirement: Default::default(),
            workspace: preparation,
            disposal: Default::default(),
            parent: "parent".into(),
            cleanup: Default::default(),
            factory: super::super::children::ChildFactory::new(DelayedDisposal {
                factory: resources.factory.clone(),
                entered,
                release: release.clone(),
            }),
        },
    );
    let caller_owner = owner.clone();
    let caller = tokio::spawn(async move {
        caller_owner
            .discard_unpublished_child("unpublished-directory")
            .await
    });
    while !*observed.borrow_and_update() {
        observed.changed().await?;
    }
    caller.abort();
    assert!(caller.await.unwrap_err().is_cancelled());
    let files = root.join(pl_tool::workspace::SessionFiles::new("unpublished-directory").root());
    assert!(resources.workspace_is_busy("unpublished-directory"));
    assert!(tokio::fs::try_exists(files.join("scratch/prepared")).await?);
    assert!(
        owner
            .0
            .state()
            .activation
            .unpublished_children
            .contains_key("unpublished-directory")
    );
    release.add_permits(1);
    owner
        .discard_unpublished_child("unpublished-directory")
        .await?;
    assert!(!resources.workspace_is_busy("unpublished-directory"));
    assert!(
        !owner
            .0
            .state()
            .activation
            .unpublished_children
            .contains_key("unpublished-directory")
    );
    assert!(!tokio::fs::try_exists(&files).await?);
    assert!(
        tokio::fs::try_exists(&root).await?,
        "shared root is never the removal target"
    );
    resources.shutdown().await?;
    Ok(())
}
