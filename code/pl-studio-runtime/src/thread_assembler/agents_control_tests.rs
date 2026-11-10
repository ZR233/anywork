//! Real Native owners and tool bindings; only physical preparation is replaced.
use super::*;
use crate::thread_assembler::{
    ChildThreadRequest, StudioChildFactory, StudioThreadSpec, ThreadActivation,
};
use pl_agent_tool::Tool;
use pl_core::tool::opaque::CallContext;

fn call(agent: &str) -> AgentCallContext {
    AgentCallContext {
        caller: pl_protocol::AgentId::new(agent).unwrap(),
        call_id: "trusted-call".into(),
        cancellation: Default::default(),
    }
}

fn native_call(thread: &str) -> CallContext {
    CallContext {
        thread_id: thread.into(),
        turn_id: "turn".into(),
        call_id: "trusted-call".into(),
        grant: Default::default(),
        context: Default::default(),
        history_fence: 0,
        model_projection: None,
        tasks: None,
        cancellation: Default::default(),
        extensions: Arc::new(Default::default()),
        catalog: Arc::from([]),
        extension_sequence: 0,
    }
}

fn host(owner: &SessionRuntime, thread: &str) -> Arc<AgentHost> {
    let state = owner.0.state();
    let entry = &state.entries[thread];
    Arc::new(AgentHost {
        registry: Arc::downgrade(&owner.0),
        identity: entry.identity.clone(),
        resources: Arc::downgrade(&entry.native.resources),
    })
}

fn frontend(host: Arc<AgentHost>, kind: AgentControlKind) -> ThreadAgentControl<AgentHost> {
    ThreadAgentControl::new(
        host.clone(),
        kind,
        kind.declaration(
            &[AgentSpawnProfile {
                profile_id: "fixture".into(),
                workspace_mode: pl_protocol::AgentWorkspaceMode::Directory,
            }],
            pl_protocol::DelegationMode::default(),
        )
        .unwrap()
        .unwrap(),
        host.identity.clone(),
        move || host.validate_instance(),
    )
}

async fn member(
    owner: &SessionRuntime,
    root: &std::path::Path,
    thread: &str,
    agent: &str,
    parent: Option<(&str, &str)>,
) -> pl_core::thread::ThreadHandle {
    let mut identity = ThreadActivation::native_test(thread, parent.map(|(thread, _)| thread));
    identity.agent.session_id = owner.id().clone();
    identity.agent.agent_id = pl_protocol::AgentId::new(agent).unwrap();
    identity.agent.parent_agent_id =
        parent.map(|(_, agent)| pl_protocol::AgentId::new(agent).unwrap());
    owner.install_explicit_activation(identity);
    owner
        .assemble(archive_tests::spec(
            thread.into(),
            parent.map(|(thread, _)| thread.into()),
            root,
        ))
        .await
        .unwrap()
}

#[tokio::test]
async fn product_tree_controls_native_members_with_distinct_typed_ids() {
    let dir = tempfile::tempdir().unwrap();
    let owner = SessionRuntime::default();
    member(&owner, dir.path(), "native-root", "root-member", None).await;
    member(
        &owner,
        dir.path(),
        "native-child",
        "child-member",
        Some(("native-root", "root-member")),
    )
    .await;
    {
        let mut state = owner.0.state();
        // Native binding metadata cannot redefine the product member tree.
        state
            .entries
            .get_mut("native-root")
            .unwrap()
            .native
            .parent_id = Some("irrelevant".into());
        state
            .entries
            .get_mut("native-child")
            .unwrap()
            .native
            .parent_id = None;
    }
    let root = host(&owner, "native-root");
    let mut foreign = ThreadActivation::native_test("foreign-native", None);
    foreign.agent.session_id = pl_protocol::SessionId::new("other-session").unwrap();
    owner.install_explicit_activation(foreign);
    let rejected = owner
        .assemble(archive_tests::spec(
            "foreign-native".into(),
            None,
            dir.path(),
        ))
        .await
        .unwrap_err();
    assert!(matches!(rejected, ThreadAssemblyError::Identity(_)));
    assert!(matches!(
        root.interrupt(call("root-member"), "foreign-native").await,
        Err(ControlError::Missing(_))
    ));
    let rows = root.list(call("root-member")).await.unwrap();
    assert_eq!(rows.len(), 2);
    let child = rows.iter().find(|row| row["id"] == "child-member").unwrap();
    assert_eq!(child["parentId"], "root-member");
    assert!(matches!(
        root.interrupt(call("root-member"), "child-member").await,
        Err(ControlError::StaleExecution(_))
    ));
    assert!(matches!(
        root.interrupt(call("root-member"), "root-member").await,
        Err(ControlError::Relationship { .. })
    ));
    let child = host(&owner, "native-child");
    assert!(matches!(
        child.interrupt(call("child-member"), "root-member").await,
        Err(ControlError::Relationship { .. })
    ));
    assert!(
        root.list(call("child-member")).await.is_err(),
        "trusted caller still must match the frozen binding"
    );
    assert!(owner.close_session().await.is_empty());
}

#[tokio::test]
async fn old_native_tools_cannot_rebind_a_reactivated_member() {
    let dir = tempfile::tempdir().unwrap();
    let owner = SessionRuntime::default();
    member(&owner, dir.path(), "native-root", "root-member", None).await;
    let old_host = host(&owner, "native-root");
    let old = frontend(old_host.clone(), AgentControlKind::List);
    let json = || OpaquePayload::new("application/json", 1, "{}").unwrap();
    assert!(
        old.execute(json(), native_call("other-native"))
            .await
            .is_err()
    );
    assert!(
        old.execute(json(), native_call("native-root"))
            .await
            .is_ok()
    );
    owner.close("native-root").await.unwrap();
    member(&owner, dir.path(), "native-root", "root-member", None).await;
    assert!(
        old.execute(json(), native_call("native-root"))
            .await
            .is_err()
    );
    assert!(old_host.list(call("root-member")).await.is_err());
    let current = host(&owner, "native-root");
    assert_eq!(current.list(call("root-member")).await.unwrap().len(), 1);
    owner
        .0
        .state()
        .sealed_agents
        .insert("native-root".into(), 1);
    assert!(current.list(call("root-member")).await.is_err());
    owner.0.state().sealed_agents.remove("native-root");
    crate::studio::agent_close::commit(&owner.thread("native-root").unwrap())
        .await
        .unwrap();
    assert!(current.list(call("root-member")).await.is_err());
    assert!(owner.close_session().await.is_empty());
}

#[tokio::test]
async fn native_send_replays_the_original_receipt_and_rejects_changed_body() {
    let dir = tempfile::tempdir().unwrap();
    let owner = SessionRuntime::default();
    member(&owner, dir.path(), "native-root", "root-member", None).await;
    let child = member(
        &owner,
        dir.path(),
        "native-child",
        "child-member",
        Some(("native-root", "root-member")),
    )
    .await;
    let sequence = child
        .send_message(pl_core::thread::inbox::ThreadMessage {
            kind: pl_core::context::AgentMessageKind::Report,
            id: format!(
                "agent-message:{}:native-root:trusted-call",
                "native-root".len()
            ),
            source_id: "agent:native-root".into(),
            payload: OpaquePayload::text("same"),
            context: vec![ContextContent::Text {
                text: Arc::from("same"),
            }],
        })
        .await
        .unwrap();
    let tool = frontend(host(&owner, "native-root"), AgentControlKind::Send);
    let input = |body: &str| {
        OpaquePayload::new(
            "application/json",
            1,
            serde_json::json!({"target":"child-member", "message":body}).to_string(),
        )
        .unwrap()
    };
    let receipt = tool
        .execute(input("same"), native_call("native-root"))
        .await
        .unwrap();
    let receipt: serde_json::Value = serde_json::from_str(receipt.payload().content()).unwrap();
    assert_eq!(receipt["sequence"], sequence);
    assert_eq!(receipt["target"], "child-member");
    assert!(
        tool.execute(input("changed"), native_call("native-root"))
            .await
            .is_err()
    );
    assert_eq!(child.snapshot().inbox_sequence, sequence);
    assert!(
        child.snapshot().execution.is_none(),
        "a duplicate must not start or stop execution"
    );
    assert!(child.snapshot().inputs.is_empty());
    assert!(owner.close_session().await.is_empty());
}

#[derive(Debug)]
struct PhysicalFactory {
    owner: Weak<Registry>,
    path: std::path::PathBuf,
    wait_for_cancel: bool,
}

impl StudioChildFactory for PhysicalFactory {
    type Admission = ();
    async fn admit(
        &self,
        _: &str,
        _: pl_protocol::DelegationSettings,
        _: Option<pl_protocol::studio::NewThreadModelRoute>,
    ) -> Result<(), ThreadAssemblyError> {
        Ok(())
    }

    async fn prepare(
        &self,
        request: ChildThreadRequest,
        _: (),
    ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
        if self.wait_for_cancel {
            request.cancellation.cancelled().await;
            return Err(ThreadAssemblyError::Closed);
        }
        let mut activation = ThreadActivation::native_test(&request.id, Some(&request.caller));
        let owner = SessionRuntime(self.owner.upgrade().unwrap());
        activation.agent.session_id = owner.id().clone();
        activation.agent.parent_agent_id = Some(
            owner.0.state().entries[&request.caller]
                .identity
                .agent_id
                .clone(),
        );
        owner.install_explicit_activation(activation);
        let mut spec = archive_tests::spec(request.id, Some(request.caller), &self.path);
        let assignment = pl_protocol::AgentWorkspaceAssignmentSnapshot {
            mode: pl_protocol::AgentWorkspaceMode::Directory,
            project_root: self.path.to_string_lossy().into_owned(),
            root: self.path.to_string_lossy().into_owned(),
            writable_paths: Some(Vec::new()),
            worktree: None,
            review_target: None,
        };
        spec.initial_extensions.insert(
            crate::studio::workspace_receipt::EXTENSION.into(),
            crate::studio::workspace_receipt::to_payload(&assignment).unwrap(),
        );
        Ok(spec)
    }

    async fn discard_unpublished(
        &self,
        _: &str,
        _: Option<&crate::studio::WorkspaceUsageLease>,
        _: pl_tool::collaboration::thread::WorkspaceRelease,
    ) -> Result<(), ThreadAssemblyError> {
        Ok(())
    }
}

async fn spawning_owner(
    path: &std::path::Path,
    fail_initial: bool,
    wait_for_cancel: bool,
) -> SessionRuntime {
    let owner = SessionRuntime::default();
    owner
        .observe_assembly(
            |_, _, _| {},
            |_, _| Box::pin(async { Ok(()) }),
            Some(Arc::new(move |_, message| {
                Box::pin(async move {
                    if fail_initial && message.starts_with("initial:") {
                        Err(ThreadAssemblyError::Resource {
                            operation: "lookup initial message identity",
                            source: Box::new(std::io::Error::other(
                                "fixture message index unavailable",
                            )),
                        })
                    } else {
                        Ok(None)
                    }
                })
            })),
            |_, _, _| Box::pin(async { Ok(()) }),
            |_| Box::pin(async { Ok(()) }),
        )
        .unwrap();
    owner
        .set_child_factory(PhysicalFactory {
            owner: Arc::downgrade(&owner.0),
            path: path.into(),
            wait_for_cancel,
        })
        .unwrap();
    let root = member(&owner, path, "native-root", "root-member", None).await;
    root.mutate_extensions(vec![pl_core::thread::extensions::ExtensionMutation::Put {
        id: crate::studio::delegation::EXTENSION.into(),
        expected_revision: None,
        payload: crate::studio::delegation::encode(Default::default()).unwrap(),
    }])
    .await
    .unwrap();
    owner
}

#[tokio::test]
async fn published_spawn_input_failure_keeps_child_identity_and_source() {
    let dir = tempfile::tempdir().unwrap();
    let owner = spawning_owner(dir.path(), true, false).await;
    let request: AgentSpawn = pl_agent_tool::typed::decode_json(
        r#"{"profileId":"fixture","taskSummary":"test","message":"first input"}"#,
    )
    .unwrap();
    let result = host(&owner, "native-root")
        .spawn(call("root-member"), request)
        .await
        .unwrap();
    assert!(!result.receipt.message_accepted);
    assert!(result.receipt.message_sequence.is_none());
    assert!(owner.thread(&result.receipt.agent_id).is_some());
    assert_eq!(
        result.receipt.workspace.as_ref().unwrap().root,
        dir.path().to_string_lossy()
    );
    let control = result.message_error.unwrap();
    assert!(
        std::error::Error::source(&control)
            .unwrap()
            .is::<ThreadAssemblyError>()
    );
    assert_eq!(
        std::error::Error::source(std::error::Error::source(&control).unwrap())
            .unwrap()
            .to_string(),
        "fixture message index unavailable"
    );
    assert!(owner.close_session().await.is_empty());
}

#[tokio::test]
async fn preparing_capacity_and_root_policy_use_product_membership() {
    let dir = tempfile::tempdir().unwrap();
    let owner = spawning_owner(dir.path(), false, false).await;
    let request: AgentSpawn = pl_agent_tool::typed::decode_json(
        r#"{"profileId":"fixture","taskSummary":"invalid review","message":"test","reviewTargetAgentId":"root-member"}"#,
    ).unwrap();
    let error = host(&owner, "native-root")
        .spawn(call("root-member"), request)
        .await
        .unwrap_err();
    assert!(matches!(
        error,
        ControlError::Service(source) if matches!(source.downcast_ref::<ThreadAssemblyError>(), Some(ThreadAssemblyError::ReviewTargetInvalid(_)))
    ));
    assert!(owner.0.state().unpublished_children.is_empty());
    member(
        &owner,
        dir.path(),
        "native-child",
        "child-member",
        Some(("native-root", "root-member")),
    )
    .await;
    {
        let mut state = owner.0.state();
        state
            .entries
            .get_mut("native-root")
            .unwrap()
            .native
            .parent_id = Some("irrelevant".into());
        state
            .entries
            .get_mut("native-child")
            .unwrap()
            .native
            .parent_id = None;
    }
    assert!(matches!(
        owner.reserve_child(&call("child-member")),
        Err(ThreadAssemblyError::ChildDepth)
    ));
    let mut reservations = Vec::new();
    let context = call("root-member");
    for _ in 0..14 {
        reservations.push(owner.reserve_child(&context).unwrap().1);
    }
    assert!(matches!(
        owner.reserve_child(&call("root-member")),
        Err(ThreadAssemblyError::ChildCapacity(16))
    ));
    assert_eq!(
        host(&owner, "native-root")
            .list(call("root-member"))
            .await
            .unwrap()
            .len(),
        16
    );
    context.cancellation.cancel();
    assert!(
        !reservations[0].cancellation.is_cancelled(),
        "call cancellation is not child lifetime"
    );
    drop(reservations);
    assert!(owner.close_session().await.is_empty());
}

#[tokio::test]
async fn call_cancellation_settles_the_original_unpublished_preparation() {
    let dir = tempfile::tempdir().unwrap();
    let owner = spawning_owner(dir.path(), false, true).await;
    let context = call("root-member");
    let cancellation = context.cancellation.clone();
    let request = pl_agent_tool::typed::decode_json(
        r#"{"profileId":"fixture","taskSummary":"cancel preparation","message":"test"}"#,
    )
    .unwrap();
    let host = host(&owner, "native-root");
    let spawn = host.spawn(context, request);
    tokio::pin!(spawn);
    assert!(futures::poll!(&mut spawn).is_pending());
    assert_eq!(owner.0.state().unpublished_children.len(), 1);
    cancellation.cancel();
    assert!(
        tokio::time::timeout(std::time::Duration::from_secs(2), spawn)
            .await
            .unwrap()
            .is_err()
    );
    assert!(owner.0.state().unpublished_children.is_empty());
    assert!(owner.0.state().preparing_children.is_empty());
    assert!(owner.close_session().await.is_empty());
}

mod publication_commit {
    use super::*;
    use crate::studio::{ProductEventBus, StudioStore, storage_fault_test_support::close_factory};
    use pl_core::model::{
        DynModelSession, Model, ModelError, ModelFactory, ModelRequest, ModelSession,
        ModelStepOutput, ModelToolCall, PreparedModelCall,
    };
    use sea_orm::ConnectionTrait;

    struct PersistentFactory {
        physical: PhysicalFactory,
        events: ProductEventBus,
    }

    impl std::fmt::Debug for PersistentFactory {
        fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            f.write_str("PersistentFactory")
        }
    }

    impl StudioChildFactory for PersistentFactory {
        type Admission = ();

        async fn admit(
            &self,
            _: &str,
            _: pl_protocol::DelegationSettings,
            _: Option<pl_protocol::studio::NewThreadModelRoute>,
        ) -> Result<(), ThreadAssemblyError> {
            Ok(())
        }

        async fn prepare(
            &self,
            request: ChildThreadRequest,
            _: (),
        ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
            let mut record = pl_protocol::Thread::placeholder(&request.id);
            record.workspace_id = "publication-project".into();
            record.root_thread_id = SessionRuntime(self.physical.owner.upgrade().unwrap())
                .id()
                .to_string();
            record.parent_thread_id = Some(request.caller.clone());
            record.workspace_path = self.physical.path.to_string_lossy().into_owned();
            self.events
                .commit_test_thread(&record)
                .await
                .map_err(|source| ThreadAssemblyError::Resource {
                    operation: "commit fixture child directory",
                    source: source.into(),
                })?;
            self.physical.prepare(request, ()).await
        }

        async fn discard_unpublished(
            &self,
            _: &str,
            _: Option<&crate::studio::WorkspaceUsageLease>,
            _: pl_tool::collaboration::thread::WorkspaceRelease,
        ) -> Result<(), ThreadAssemblyError> {
            Ok(())
        }
    }

    struct SpawnModel;
    struct SpawnSession(bool);
    impl Model for SpawnModel {
        async fn open_session(&self) -> Result<DynModelSession, ModelError> {
            Ok(DynModelSession::new(SpawnSession(false)))
        }
    }
    impl ModelSession for SpawnSession {
        async fn prepare(
            &mut self,
            request: ModelRequest,
        ) -> Result<PreparedModelCall, ModelError> {
            let calls = if std::mem::replace(&mut self.0, true) {
                Vec::new()
            } else {
                vec![ModelToolCall {
                    call_id: "publish-commit".into(),
                    tool_id: "spawn_agent".into(),
                    arguments: OpaquePayload::new("application/json", 1,
                        r#"{"profileId":"fixture","taskSummary":"publication failure","message":"must not be admitted"}"#).unwrap(),
                    rejection: None,
                    presentation_contract: request.tools[0].presentation_contract.clone(),
                }]
            };
            Ok(PreparedModelCall::new(async move {
                Ok(ModelStepOutput {
                    turn_action: Default::default(),
                    attempt_id: request.attempt_id,
                    base_context_revision: request.context.revision,
                    content: vec![ContextContent::Text {
                        text: Arc::from("fixture step"),
                    }],
                    tool_calls: calls,
                    private_context: None,
                    usage: Default::default(),
                })
            }))
        }
        async fn close(&mut self) -> Result<(), ModelError> {
            Ok(())
        }
    }

    #[tokio::test]
    async fn sqlite_publication_failure_retains_native_receipt_and_closeable_child()
    -> anyhow::Result<()> {
        let dir = tempfile::tempdir()?;
        let store = StudioStore::open(dir.path().join("data/studio.sqlite")).await?;
        let services = close_factory(&store)?;
        let owner = SessionRuntime::open(pl_protocol::SessionId::new("native-root")?);
        owner.set_child_factory(PersistentFactory {
            physical: PhysicalFactory {
                owner: Arc::downgrade(&owner.0),
                path: dir.path().into(),
                wait_for_cancel: false,
            },
            events: services.events.clone(),
        })?;
        services.install(&owner)?;
        let mut record = pl_protocol::Thread::placeholder("native-root");
        record.workspace_id = "publication-project".into();
        record.root_thread_id = "native-root".into();
        record.workspace_path = dir.path().to_string_lossy().into_owned();
        services.events.commit_test_thread(&record).await?;
        let root = member(&owner, dir.path(), "native-root", "native-root", None).await;
        root.mutate_extensions(vec![pl_core::thread::extensions::ExtensionMutation::Put {
            id: crate::studio::delegation::EXTENSION.into(),
            expected_revision: None,
            payload: crate::studio::delegation::encode(Default::default())?,
        }])
        .await?;
        let tool = frontend(host(&owner, "native-root"), AgentControlKind::Spawn);
        let prepared = pl_tool::binding::prepare_registration(
            "spawn_agent",
            tool.definition(),
            pl_model::completion::ToolCallPolicy::DirectOnly,
        )?;
        root.register_tools(vec![tool.registration(prepared)])
            .await?;
        root.replace_model(ModelFactory::new(SpawnModel)).await?;
        // Reject only the real false -> true publication write, not preparation/assembly writes.
        store
            .database()
            .execute_unprepared(
                "CREATE TRIGGER reject_spawn_publication BEFORE UPDATE ON studio_objects
             WHEN NEW.object_kind='threadPreparation'
               AND json_extract(OLD.payload_json,'$.published')=0
               AND json_extract(NEW.payload_json,'$.published')=1
             BEGIN SELECT RAISE(ABORT,'controlled spawn publication rejection'); END",
            )
            .await?;
        tokio::time::timeout(
            std::time::Duration::from_secs(10),
            root.run_turn(pl_core::thread::TurnInput {
                turn_id: "publish".into(),
                attempt_prefix: "attempt-publish".into(),
                content: vec![ContextContent::Text {
                    text: Arc::from("spawn"),
                }],
                max_model_steps: pl_core::thread::ModelStepLimit::Limited(3.try_into()?),
                cancellation: Default::default(),
            }),
        )
        .await??;
        let deliveries = root
            .effects()
            .await?
            .iter()
            .flat_map(|effect| effect.deliveries.to_vec())
            .collect::<Vec<_>>();
        assert_eq!(deliveries.len(), 1);
        let delivery = &deliveries[0];
        let pl_core::thread::ToolOutcome::Failed(error) = &delivery.outcome else {
            panic!("publication rejection must remain a failed Native tool call: {delivery:?}");
        };
        assert!(error.source.is::<ControlError>(), "{error:?}");
        let mut source: Option<&(dyn std::error::Error + 'static)> = Some(error.as_ref());
        let mut database_error = false;
        while let Some(cause) = source {
            database_error |= cause.downcast_ref::<sea_orm::DbErr>().is_some();
            source = cause.source();
        }
        assert!(
            database_error,
            "the original typed SQLite error must survive Native delivery: {error:?}"
        );
        assert!(
            format!("{error}").contains("controlled spawn publication rejection"),
            "{error:?}"
        );
        assert_eq!(
            owner.0.state().entries.len(),
            2,
            "the child was already published"
        );
        assert!(owner.0.state().unpublished_children.is_empty());
        assert_eq!(
            delivery.output.payload().format(),
            "pl.studio.agent-control"
        );
        let receipt: serde_json::Value = serde_json::from_str(delivery.output.payload().content())?;
        assert_eq!(receipt["messageAccepted"], false);
        assert!(receipt.get("messageSequence").is_none());
        assert_eq!(
            receipt["workspace"]["root"],
            dir.path().to_string_lossy().as_ref()
        );
        let id = receipt["agentId"]
            .as_str()
            .expect("published member identity");
        let child = owner.thread(id).expect("memory publication remains ready");
        assert!(!owner.0.state().unpublished_children.contains_key(id));
        assert!(!store.thread_preparation(id).await?.unwrap().published);
        assert!(child.snapshot().inbox.is_empty());
        assert!(child.snapshot().inputs.is_empty());
        assert!(child.snapshot().execution.is_none());
        store
            .database()
            .execute_unprepared("DROP TRIGGER reject_spawn_publication")
            .await?;
        let close = host(&owner, "native-root")
            .close(call("native-root"), id, Default::default())
            .await?;
        assert_eq!(close.target, id);
        assert!(
            close
                .agents
                .iter()
                .any(|agent| agent.agent_id == id && agent.execution_closed)
        );
        assert!(owner.close_session().await.is_empty());
        services.shutdown().await?;
        store.close().await?;
        Ok(())
    }
}
