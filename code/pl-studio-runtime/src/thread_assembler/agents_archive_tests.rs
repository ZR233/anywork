//! Real spawn/assembly/retained-disposal interleavings; only the physical factory is a fixture.
use super::*;
use crate::thread_assembler::{ChildThreadRequest, StudioChildFactory, StudioThreadSpec};
use pl_core::thread::extensions::ExtensionMutation;
use std::{
    collections::BTreeMap,
    future::Future,
    sync::{
        Mutex,
        atomic::{AtomicBool, Ordering},
    },
    task::Poll,
};

pub(crate) fn spec(
    id: String,
    parent_id: Option<String>,
    root: &std::path::Path,
) -> StudioThreadSpec {
    let info = pl_model::model::ModelInfo::compatible("archive-fixture");
    let route = pl_model::config::ResolvedModelRoute {
        pricing_mode: Default::default(),
        role: crate::config::root_agent_route_id(),
        account_id: pl_model::config::AccountId::new("archive-fixture").unwrap(),
        endpoint: pl_model::protocol::ProtocolEndpoint::compatible(
            "archive fixture",
            "http://127.0.0.1:0",
        ),
        context: info.resolve_context(None),
        model: info,
        effort: None,
    };
    let profile = pl_protocol::AgentProfileSnapshot {
        profile_id: "fixture".into(),
        display_name: "fixture".into(),
        description: String::new(),
        when_to_use: String::new(),
        system_instructions: String::new(),
        account_id: "archive-fixture".into(),
        model_id: "archive-fixture".into(),
        effort: None,
        source: "fixture".into(),
        revision: "1".into(),
        content_hash: "fixture".into(),
        system: false,
        enabled: true,
        workspace_mode: pl_protocol::AgentWorkspaceMode::Directory,
    };
    StudioThreadSpec {
        workspace_usage: None,
        preparation_guard: None,
        context_preparation: None,
        agent_controls: Vec::new(),
        execution: pl_core::thread::input::InputDriverOptions {
            max_model_steps: pl_core::thread::ModelStepLimit::Unlimited,
        },
        id,
        parent_id,
        model: pl_model::runtime::ThreadModel::new(
            pl_model::runtime::ModelRuntime::from_route(&route).unwrap(),
            None,
        ),
        route,
        model_available: false,
        checkpoint: None,
        initial_context: Vec::new(),
        initial_runtime_facts: Vec::new(),
        initial_extensions: BTreeMap::from([(
            crate::studio::model_route::AGENT_PROFILE_EXTENSION.into(),
            crate::studio::model_route::encode_profile(&profile).unwrap(),
        )]),
        tools: Vec::new(),
        resources: pl_core::context::ResourceAccess::new(
            crate::resource_store::FileResourceStore::new(root.join("resources")),
        ),
        capacity: Default::default(),
        cold_store: None,
    }
}

#[derive(Debug)]
struct SpawnFactory {
    id: Arc<Mutex<Option<String>>>,
    release: Arc<tokio::sync::Semaphore>,
    dispositions: Arc<Mutex<Vec<pl_tool::collaboration::thread::WorkspaceRelease>>>,
    root: std::path::PathBuf,
}
impl StudioChildFactory for SpawnFactory {
    async fn prepare(
        &self,
        request: ChildThreadRequest,
    ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
        *self.id.lock().unwrap() = Some(request.id.clone());
        self.release.acquire().await.unwrap().forget();
        Ok(spec(request.id, Some(request.caller), &self.root))
    }

    async fn discard_unpublished(
        &self,
        _: &str,
        _: Option<&crate::studio::WorkspaceUsageLease>,
        disposition: pl_tool::collaboration::thread::WorkspaceRelease,
    ) -> Result<(), ThreadAssemblyError> {
        self.dispositions.lock().unwrap().push(disposition);
        Ok(())
    }
}

/// Product environment replacement only; reservation, spawn ownership and failed disposal remain real.
pub(crate) async fn spawn_failed_archive_fixture(
    owner: StudioThreadAssembler,
    root: String,
    factory: impl StudioChildFactory,
) -> Result<ToolOutput, ToolError> {
    owner.0.state().child_factory = Some(crate::thread_assembler::children::ChildFactory::new(
        factory,
    ));
    let context = pl_core::tool::opaque::CallContext {
        grant: Default::default(),
        context: Default::default(),
        history_fence: 0,
        model_projection: None,
        tasks: None,
        thread_id: root.clone(),
        turn_id: "fixture".into(),
        call_id: "archive-first-write".into(),
        cancellation: Default::default(),
        extensions: Arc::new(BTreeMap::new()),
        catalog: Arc::from([]),
        extension_sequence: 0,
    };
    let request = AgentSpawn {
        profile_id: "fixture".into(),
        model_selection: None,
        task_summary: "archive first write".to_owned().try_into().unwrap(),
        message: "never delivered".into(),
        writable_paths: None,
        review_target_agent_id: None,
        review_feedback: None,
        metadata: serde_json::Value::Null,
    };
    let permit = owner.agent_operation(&root).await;
    AgentHost(Arc::downgrade(&owner.0))
        .spawn_owned(owner, context, request, permit)
        .await
}

#[tokio::test]
async fn archive_spawn_publication_failure_releases_child_permit_and_joins_root_spawn() {
    let root = tempfile::tempdir().unwrap();
    let owner = StudioThreadAssembler::default();
    let id = Arc::new(Mutex::new(None));
    let release = Arc::new(tokio::sync::Semaphore::new(0));
    let dispositions = Arc::new(Mutex::new(Vec::new()));
    owner
        .set_child_factory(SpawnFactory {
            id: id.clone(),
            release: release.clone(),
            dispositions: dispositions.clone(),
            root: root.path().into(),
        })
        .unwrap();
    let observed = Arc::new(AtomicBool::new(false));
    let observed_child = observed.clone();
    owner
        .observe_assembly(
            move |id, _| {
                if id != "root" {
                    observed_child.store(true, Ordering::SeqCst);
                }
            },
            |_| Box::pin(async { Ok(()) }),
            None,
            |_, _| Box::pin(async { Ok(()) }),
            |_| Box::pin(async { Ok(()) }),
        )
        .unwrap();
    let parent = owner
        .assemble(spec("root".into(), None, root.path()))
        .await
        .unwrap();
    parent
        .mutate_extensions(vec![ExtensionMutation::Put {
            id: crate::studio::delegation::EXTENSION.into(),
            expected_revision: None,
            payload: crate::studio::delegation::encode(Default::default()).unwrap(),
        }])
        .await
        .unwrap();
    let context = pl_core::tool::opaque::CallContext {
        grant: Default::default(),
        context: Default::default(),
        history_fence: 0,
        model_projection: None,
        tasks: None,
        thread_id: "root".into(),
        turn_id: "turn".into(),
        call_id: "spawn".into(),
        cancellation: Default::default(),
        extensions: Arc::new(BTreeMap::new()),
        catalog: Arc::from([]),
        extension_sequence: 0,
    };
    let request = AgentSpawn {
        profile_id: "fixture".into(),
        model_selection: None,
        task_summary: "archive publication race".to_owned().try_into().unwrap(),
        message: "must never be delivered".into(),
        writable_paths: None,
        review_target_agent_id: None,
        review_feedback: None,
        metadata: serde_json::Value::Null,
    };
    let host = AgentHost(Arc::downgrade(&owner.0));
    let parent_operation = owner.agent_operation("root").await;
    let spawn = host.spawn_owned(owner.clone(), context, request, parent_operation);
    tokio::pin!(spawn);
    assert!(futures::poll!(&mut spawn).is_pending());
    let child_id = id.lock().unwrap().clone().unwrap();
    let child_operation = owner.agent_operation(&child_id).await;
    release.add_permits(1);
    // The observer runs at the end of real assembly. With no review target or services there
    // is no await from that callback until spawn_owned queues on the held publication permit.
    futures::future::poll_fn(|cx| {
        assert!(spawn.as_mut().poll(cx).is_pending());
        if observed.load(Ordering::SeqCst) {
            Poll::Ready(())
        } else {
            Poll::Pending
        }
    })
    .await;
    let child = owner.observed_thread(&child_id).unwrap();
    assert!(child.snapshot().inputs.is_empty());
    let scope = owner.seal_archive_scope(&["root".into()]).unwrap();
    drop(child_operation);
    let result = tokio::time::timeout(std::time::Duration::from_secs(2), &mut spawn)
        .await
        .expect("publish rejection must not deadlock its own retained-disposal permit");
    assert!(result.is_err());
    tokio::time::timeout(
        std::time::Duration::from_secs(2),
        owner.drain_archive_preparations(&scope),
    )
    .await
    .expect("the failed spawn must also release the root permit")
    .unwrap();
    assert_eq!(
        *dispositions.lock().unwrap(),
        vec![pl_tool::collaboration::thread::WorkspaceRelease::Preserve]
    );
    assert!(owner.observed_thread(&child_id).is_none());
    assert!(child.snapshot().inputs.is_empty());
    drop(scope);
    owner.close("root").await.unwrap();
}

#[derive(Debug)]
struct FailClosedFlush {
    sink: crate::studio::storage_fault_test_support::ThreadStorageSink,
    fail: Arc<AtomicBool>,
}
impl pl_core::thread::cold::ColdStore for FailClosedFlush {
    fn pressure(&self, thread_id: &str) -> pl_core::thread::cold::StoragePressure {
        self.sink.pressure(thread_id)
    }

    fn admit(
        &self,
        thread_id: &str,
        write: pl_core::thread::cold::ThreadWrite,
    ) -> Result<(), pl_core::thread::cold::ColdStoreError> {
        if write.checkpoint.state.lifecycle == ThreadLifecycle::Closed {
            self.fail.store(true, Ordering::SeqCst);
        }
        self.sink.admit(thread_id, write)
    }

    async fn flush(
        &self,
        thread_id: &str,
        sequence: u64,
    ) -> Result<(), pl_core::thread::cold::ColdStoreError> {
        // The real writer may have committed Closed even though its caller never received a
        // successful flush ACK. Preserve its real pressure; never invent a durable watermark.
        self.sink.flush(thread_id, sequence).await?;
        if self.fail.load(Ordering::SeqCst) {
            return Err(pl_core::thread::cold::ColdStoreError {
                source: Box::new(std::io::Error::other(
                    "injected closed checkpoint flush failure",
                )),
            });
        }
        Ok(())
    }
}

#[tokio::test]
async fn archive_setup_failure_before_observer_retains_original_storage_until_real_flush_ack()
-> anyhow::Result<()> {
    use crate::studio::{
        StudioStore,
        storage_fault_test_support::{
            ThreadStorageSink, close_factory, register_test_thread,
            spawn_live_projection_for_thread,
        },
        store::thread_preparation::{PreparationIdentity, PreparationSave},
    };
    use anyhow::Context;
    use pl_core::thread::cold::ColdStoreHandle;
    let temp = tempfile::tempdir()?;
    let database = temp.path().join("home/data/studio.sqlite");
    let store = StudioStore::open(&database).await.with_context(|| {
        format!(
            "open current storage-ACK fixture product database {}",
            database.display()
        )
    })?;
    let factory = close_factory(&store)?;
    let owner = StudioThreadAssembler::default();
    factory.install(&owner)?;
    let mut protocol = pl_protocol::Thread::placeholder("private-setup");
    protocol.workspace_id = "workspace".into();
    protocol.root_thread_id = protocol.id.clone();
    register_test_thread(&store, &protocol).await?;
    let host_temp = store.registered_session_paths(&protocol.id)?.temp_dir();
    let pending_file = host_temp.join("pending-private-setup");
    tokio::fs::write(
        &pending_file,
        b"not disposable before the original save ACK",
    )
    .await?;
    store
        .begin_thread_preparation(PreparationIdentity {
            thread_id: protocol.id.clone(),
            workspace_id: protocol.workspace_id.clone(),
            parent_id: None,
            root_id: protocol.id.clone(),
        })
        .await?;
    let sink = ThreadStorageSink::new(store.clone(), protocol.clone(), None).await?;
    let projection = spawn_live_projection_for_thread(store.clone(), &protocol.id);
    let failure = Arc::new(AtomicBool::new(false));
    let mut prepared = spec(protocol.id.clone(), None, temp.path());
    prepared.cold_store = Some(ColdStoreHandle::new(FailClosedFlush {
        sink,
        fail: failure.clone(),
    }));
    // Invalid extension initialization occurs after AttachCold but before publish_observation.
    prepared.initial_extensions.insert(
        String::new(),
        OpaquePayload::text("invalid extension identity"),
    );
    let result = owner.assemble(prepared).await;
    assert!(matches!(result, Err(ThreadAssemblyError::Cleanup { .. })));
    assert!(
        failure.load(Ordering::SeqCst),
        "real close reached the failing flush"
    );
    let retained = owner
        .observed_thread(&protocol.id)
        .expect("original storage owner");
    assert!(retained.flush().await.is_err());
    assert_eq!(retained.snapshot().lifecycle, ThreadLifecycle::Closed);
    {
        let state = owner.0.state();
        assert!(matches!(
            state.entries[&protocol.id].close_storage,
            Some(crate::thread_assembler::CloseStorage::Execution {
                observation_installed: false,
                joined: false,
                binding: Some(_),
                ..
            })
        ));
    }
    assert_eq!(
        store.thread_preparation(&protocol.id).await?.unwrap().save,
        PreparationSave::Required
    );
    assert!(
        owner.close(&protocol.id).await.is_err(),
        "Closed is not an ACK"
    );
    assert!(owner.observed_thread(&protocol.id).is_some());
    assert_eq!(
        tokio::fs::read(&pending_file).await?,
        b"not disposable before the original save ACK"
    );
    failure.store(false, Ordering::SeqCst);
    owner.close(&protocol.id).await?;
    assert!(owner.observed_thread(&protocol.id).is_none());
    let acknowledged = store.thread_preparation(&protocol.id).await?.unwrap();
    assert_eq!(acknowledged.save, PreparationSave::Confirmed);
    assert!(acknowledged.stopped && acknowledged.retired);
    let checkpoint = store
        .history(&protocol.id)
        .await?
        .checkpoint()
        .await?
        .unwrap();
    assert_eq!(checkpoint.state.lifecycle, ThreadLifecycle::Closed);
    projection.await?;
    factory.shutdown().await?;
    Ok(())
}
