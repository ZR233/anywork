mod support;

use std::{
    sync::{
        Arc, LazyLock, Mutex,
        atomic::{AtomicU64, AtomicUsize, Ordering},
    },
    time::Duration,
};

use pl_core::{
    context::OpaquePayload,
    model::{DynModelSession, ModelError, ModelRequest, ModelSession, PreparedModelCall},
    thread::{
        StepInput, ThreadCheckpoint, ThreadError, ThreadHandle, ThreadSnapshot,
        cold::{ColdStore, ColdStoreError, ColdStoreHandle, StoragePressure, ThreadWrite},
        interactions::{
            InteractionRequest, InteractionResolution, InteractionResponse, InteractionState,
        },
        permissions::{PermissionDecision, PermissionResolution, PermissionState},
    },
    tool::{
        ToolOutput,
        opaque::{CallContext, Registration, RuntimeTool, ToolError},
    },
};
use tokio_util::sync::CancellationToken;

use support::{ScriptedModel, response, text, turn};

#[derive(Debug, Clone, Default)]
struct Capture {
    transfers: Arc<Mutex<Vec<ThreadCheckpoint>>>,
    durable: Arc<AtomicU64>,
    provider_calls: Arc<AtomicUsize>,
}

impl Capture {
    fn last(&self) -> ThreadCheckpoint {
        self.transfers.lock().unwrap().last().unwrap().clone()
    }
}

impl ColdStore for Capture {
    fn admit(&self, _: &str, write: ThreadWrite) -> Result<(), ColdStoreError> {
        self.transfers.lock().unwrap().push(write.checkpoint);
        Ok(())
    }

    fn pressure(&self, _: &str) -> StoragePressure {
        StoragePressure {
            durable_sequence: self.durable.load(Ordering::SeqCst),
            ..Default::default()
        }
    }

    async fn flush(&self, _: &str, sequence: u64) -> Result<(), ColdStoreError> {
        self.durable.store(sequence, Ordering::SeqCst);
        Ok(())
    }
}

fn question(id: &str) -> InteractionRequest {
    InteractionRequest {
        id: id.into(),
        turn_id: "question-turn".into(),
        payload: OpaquePayload::text(format!("question {id}")),
    }
}

fn answer(id: &str) -> InteractionResolution {
    InteractionResolution {
        id: id.into(),
        expected_revision: 1,
        continuation: None,
        response: InteractionResponse {
            payload: OpaquePayload::text("answered"),
            context: vec![text("the answer")],
        },
        mutations: vec![],
    }
}

async fn observe(
    thread: &ThreadHandle,
    predicate: impl Fn(&ThreadSnapshot) -> bool,
) -> ThreadSnapshot {
    tokio::time::timeout(Duration::from_secs(10), async {
        let mut stream = thread.subscribe();
        loop {
            let snapshot = stream.next().await.expect("owner is still available");
            if predicate(&snapshot) {
                return snapshot;
            }
        }
    })
    .await
    .expect("owner reaches the controlled boundary")
}

async fn at<T>(label: &str, future: impl std::future::Future<Output = T>) -> T {
    tokio::time::timeout(Duration::from_secs(10), future)
        .await
        .unwrap_or_else(|_| panic!("owner stalled at {label}"))
}

#[tokio::test]
async fn resolved_transfer_and_resident_are_distinct_cuts_and_restart_keeps_the_resident_version() {
    let thread = ThreadHandle::resume_without_model("collection".into(), None).unwrap();
    let capture = Capture::default();
    thread
        .attach_storage(ColdStoreHandle::new(capture.clone()))
        .await
        .unwrap();
    assert_eq!(thread.snapshot().interaction_collection_revision, 0);
    thread.request_interaction(question("a")).await.unwrap();
    assert_eq!(thread.snapshot().interaction_collection_revision, 1);
    thread.request_interaction(question("b")).await.unwrap();
    assert_eq!(thread.snapshot().interaction_collection_revision, 2);
    let pending_b = thread.snapshot().interactions["b"].clone();
    thread.request_interaction(question("b")).await.unwrap();
    assert_eq!(thread.snapshot().interaction_collection_revision, 2);

    thread.resolve_interaction(answer("a")).await.unwrap();
    let transfer = capture.last();
    assert_eq!(transfer.state.interaction_collection_revision, 3);
    assert!(matches!(
        transfer.state.interactions["a"].state,
        InteractionState::Resolved(_)
    ));
    let resident = thread.snapshot();
    assert_eq!(resident.interaction_collection_revision, 4);
    assert!(!resident.interactions.contains_key("a"));
    assert_eq!(resident.interactions["b"], pending_b);
    let restart = transfer.pruned().unwrap();
    assert_eq!(restart.state.interaction_collection_revision, 4);
    assert_eq!(restart.state.interactions, resident.interactions);
    assert_eq!(
        serde_json::to_value(restart.pruned().unwrap().state).unwrap(),
        serde_json::to_value(&restart.state).unwrap()
    );

    thread.resolve_interaction(answer("a")).await.unwrap();
    assert_eq!(thread.snapshot().interaction_collection_revision, 4);
    thread.flush().await.unwrap();
    assert_eq!(thread.snapshot().interaction_collection_revision, 4);
    thread.close().await.unwrap();
    let reopened = ThreadHandle::resume_without_model(
        "collection".into(),
        Some(serde_json::from_slice(&serde_json::to_vec(&restart).unwrap()).unwrap()),
    )
    .unwrap();
    assert_eq!(reopened.snapshot().interaction_collection_revision, 4);
    assert_eq!(reopened.snapshot().interactions["b"], pending_b);
    reopened.close().await.unwrap();
}

#[tokio::test]
async fn exhaustion_rejects_the_whole_command_before_changing_resources_or_context() {
    let seed = ThreadHandle::resume_without_model("boundary".into(), None).unwrap();
    seed.request_interaction(question("a")).await.unwrap();
    let mut checkpoint = seed.checkpoint(seed.snapshot().commit_sequence).unwrap();
    seed.close().await.unwrap();

    for revision in [u64::MAX - 1, u64::MAX] {
        checkpoint.state.interaction_collection_revision = revision;
        let thread =
            ThreadHandle::resume_without_model("boundary".into(), Some(checkpoint.clone()))
                .unwrap();
        let before = thread.snapshot();
        assert!(matches!(
            thread.resolve_interaction(answer("a")).await,
            Err(ThreadError::RevisionExhausted)
        ));
        assert_eq!(
            serde_json::to_value(thread.snapshot()).unwrap(),
            serde_json::to_value(&before).unwrap()
        );
        if revision == u64::MAX {
            assert!(matches!(
                thread.request_interaction(question("b")).await,
                Err(ThreadError::RevisionExhausted)
            ));
            assert_eq!(thread.snapshot().interactions, before.interactions);
        }
        thread.close().await.unwrap();
    }

    checkpoint.state.interaction_collection_revision = u64::MAX - 2;
    let thread = ThreadHandle::resume_without_model("boundary".into(), Some(checkpoint)).unwrap();
    let capture = Capture::default();
    capture
        .durable
        .store(thread.snapshot().commit_sequence, Ordering::SeqCst);
    thread
        .attach_storage(ColdStoreHandle::new(capture.clone()))
        .await
        .unwrap();
    thread.resolve_interaction(answer("a")).await.unwrap();
    let transfer = capture.last();
    assert_eq!(transfer.state.interaction_collection_revision, u64::MAX - 1);
    assert_eq!(thread.snapshot().interaction_collection_revision, u64::MAX);
    assert!(thread.snapshot().interactions.is_empty());
    assert_eq!(
        transfer
            .pruned()
            .unwrap()
            .state
            .interaction_collection_revision,
        u64::MAX
    );
    let mut exhausted = transfer;
    exhausted.state.interaction_collection_revision = u64::MAX;
    let original = serde_json::to_value(&exhausted).unwrap();
    assert!(matches!(
        exhausted.pruned(),
        Err(ThreadError::RevisionExhausted)
    ));
    assert_eq!(serde_json::to_value(exhausted).unwrap(), original);
    thread.close().await.unwrap();
}

struct Streaming {
    progress: tokio::sync::mpsc::UnboundedSender<pl_core::model::ModelProgressSender>,
    release: CancellationToken,
}

impl ModelSession for Streaming {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        let sender = self.progress.clone();
        let release = self.release.clone();
        Ok(PreparedModelCall::new(async move {
            sender.send(request.progress.clone().unwrap()).unwrap();
            release.cancelled().await;
            let mut output = response(&request, vec![]);
            output.usage.output_tokens = Some(17);
            Ok(output)
        }))
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

#[tokio::test]
async fn token_observations_terminal_usage_and_durable_ack_keep_the_resource_version() {
    let (sender, mut receiver) = tokio::sync::mpsc::unbounded_channel();
    let release = CancellationToken::new();
    let thread = ThreadHandle::start(
        "tokens".into(),
        DynModelSession::new(Streaming {
            progress: sender,
            release: release.clone(),
        }),
    )
    .unwrap();
    let capture = Capture::default();
    thread
        .attach_storage(ColdStoreHandle::new(capture.clone()))
        .await
        .unwrap();
    thread.request_interaction(question("a")).await.unwrap();
    thread.resolve_interaction(answer("a")).await.unwrap();
    let first_model_transfer = capture.transfers.lock().unwrap().len();
    let step = {
        let thread = thread.clone();
        tokio::spawn(async move { thread.run_turn(turn("token-turn")).await })
    };
    let progress = tokio::time::timeout(Duration::from_secs(10), receiver.recv())
        .await
        .unwrap()
        .unwrap();
    let before = thread.snapshot();
    progress.observe_usage(Some(11), Some(23));
    let live = observe(&thread, |snapshot| {
        snapshot.model_progress.as_ref().is_some_and(|active| {
            active
                .progress
                .usage_observation()
                .is_some_and(|usage| usage.completion_tokens == Some(11))
        })
    })
    .await;
    assert!(live.observation_revision > before.observation_revision);
    assert_eq!(live.interaction_collection_revision, 3);
    release.cancel();
    step.await.unwrap().unwrap();
    assert_eq!(thread.snapshot().interaction_collection_revision, 3);
    thread.flush().await.unwrap();
    assert!(thread.snapshot().persistence.durable_sequence >= live.commit_sequence);
    assert_eq!(thread.snapshot().interaction_collection_revision, 3);
    assert!(
        capture
            .transfers
            .lock()
            .unwrap()
            .iter()
            .skip(first_model_transfer)
            .all(|checkpoint| checkpoint.state.interaction_collection_revision == 3)
    );
    thread.close().await.unwrap();
}

#[derive(Debug)]
struct ControlledTool {
    permission: bool,
    reveal_hidden: bool,
    release: CancellationToken,
    executions: Arc<AtomicUsize>,
}

impl pl_agent_tool::Tool for ControlledTool {
    type Input = OpaquePayload;
    type Context = CallContext;
    type Output = ToolOutput;
    type Error = ToolError;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        static DEFINITION: LazyLock<pl_agent_tool::ToolDefinition> = LazyLock::new(|| {
            pl_agent_tool::ToolDefinition::text("controlled", "Controlled collection test tool")
                .unwrap()
        });
        &DEFINITION
    }

    async fn execute(
        &self,
        _: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        self.executions.fetch_add(1, Ordering::SeqCst);
        if self.permission {
            context
                .tasks
                .as_ref()
                .unwrap()
                .request_execution_permission(
                    OpaquePayload::text("allow?"),
                    context.cancellation.clone(),
                )
                .await
                .map_err(ToolError::new)?;
        }
        self.release.cancelled().await;
        let output = ToolOutput::new(OpaquePayload::text("original result"), vec![text("done")]);
        let output = if self.permission {
            output
        } else {
            output.with_interaction(OpaquePayload::text("original question"))
        };
        Ok(if self.reveal_hidden {
            output.with_revealed_tools(vec!["hidden".into()])
        } else {
            output
        })
    }
}

struct CountingModel {
    inner: ScriptedModel,
    executed: Arc<AtomicUsize>,
}

impl ModelSession for CountingModel {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        let prepared = self.inner.prepare(request).await?;
        let executed = self.executed.clone();
        Ok(PreparedModelCall::new(async move {
            executed.fetch_add(1, Ordering::SeqCst);
            prepared.execute().await
        }))
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        self.inner.close().await
    }
}

#[derive(Clone, Copy)]
enum ToolMode {
    Foreground,
    Background,
    Reveal,
}

async fn tool_thread(
    revision: u64,
    permission: bool,
) -> (ThreadHandle, CancellationToken, Arc<AtomicUsize>, Capture) {
    tool_thread_with_mode(revision, permission, ToolMode::Foreground).await
}

async fn tool_thread_with_mode(
    revision: u64,
    permission: bool,
    mode: ToolMode,
) -> (ThreadHandle, CancellationToken, Arc<AtomicUsize>, Capture) {
    let (model, _) = ScriptedModel::new(&["controlled"]);
    let capture = Capture::default();
    let model = CountingModel {
        inner: model,
        executed: capture.provider_calls.clone(),
    };
    let checkpoint = ThreadCheckpoint::capture(
        "tool".into(),
        0,
        ThreadSnapshot {
            interaction_collection_revision: revision,
            ..Default::default()
        },
    )
    .unwrap();
    let thread =
        ThreadHandle::resume("tool".into(), DynModelSession::new(model), Some(checkpoint)).unwrap();
    let release = CancellationToken::new();
    let executions = Arc::new(AtomicUsize::new(0));
    thread
        .attach_storage(ColdStoreHandle::new(capture.clone()))
        .await
        .unwrap();
    let registration =
        Registration::prepare("controlled".into(), OpaquePayload::text("controlled"))
            .unwrap()
            .attach(RuntimeTool::new(ControlledTool {
                permission,
                reveal_hidden: matches!(mode, ToolMode::Reveal),
                release: release.clone(),
                executions: executions.clone(),
            }));
    let mut registrations = vec![match mode {
        ToolMode::Background => registration,
        ToolMode::Foreground => registration.with_interactions().foreground_coexisting(),
        ToolMode::Reveal => registration
            .with_interactions()
            .with_tool_discovery()
            .foreground_coexisting(),
    }];
    if matches!(mode, ToolMode::Reveal) {
        registrations.push(
            Registration::prepare("hidden".into(), OpaquePayload::text("hidden"))
                .unwrap()
                .attach(RuntimeTool::new(ControlledTool {
                    permission: false,
                    reveal_hidden: false,
                    release: release.clone(),
                    executions: executions.clone(),
                }))
                .deferred(),
        );
    }
    thread.register_tools(registrations).await.unwrap();
    thread
        .step(StepInput {
            turn_id: "tool-turn".into(),
            attempt_id: "tool-attempt".into(),
            content: vec![text("run")],
            cancellation: CancellationToken::new(),
        })
        .await
        .unwrap();
    (thread, release, executions, capture)
}

#[tokio::test]
async fn failed_admission_keeps_background_results_and_does_not_register_an_unexecuted_attempt() {
    let (thread, release, executions, capture) =
        tool_thread_with_mode(u64::MAX - 2, true, ToolMode::Background).await;
    let running = {
        let thread = thread.clone();
        tokio::spawn(async move {
            thread
                .execute_tool("tool-turn-controlled".into(), CancellationToken::new())
                .await
        })
    };
    observe(&thread, |snapshot| !snapshot.permissions.is_empty()).await;
    thread
        .resolve_execution_permission(PermissionResolution {
            id: "permission:tool-turn-controlled".into(),
            expected_revision: 1,
            decision: PermissionDecision::Allow,
            payload: None,
        })
        .await
        .unwrap();
    assert!(matches!(
        at("background acknowledgement", running)
            .await
            .unwrap()
            .unwrap(),
        pl_core::thread::ToolDispatch::Running(_)
    ));
    release.cancel();
    let before = observe(&thread, |snapshot| !snapshot.deliveries.is_empty()).await;
    assert_eq!(before.interaction_collection_revision, u64::MAX);
    assert_eq!(before.permissions.len(), 1);
    assert_eq!(before.consumed_messages, 0);
    assert!(!before.inbox.is_empty());
    let provider_calls = capture.provider_calls.load(Ordering::SeqCst);
    assert_eq!(provider_calls, 1);

    let result = thread
        .step(StepInput {
            turn_id: "next-turn".into(),
            attempt_id: "next-attempt".into(),
            content: vec![text("consume queued result")],
            cancellation: CancellationToken::new(),
        })
        .await;
    assert!(matches!(result, Err(ThreadError::RevisionExhausted)));
    let after = thread.snapshot();
    let close = at(
        "delete after rejected model admission",
        thread.close_for_deletion(),
    )
    .await;
    assert_eq!(after.consumed_messages, before.consumed_messages);
    assert_eq!(after.context, before.context);
    assert_eq!(after.inbox, before.inbox);
    assert_eq!(after.inputs, before.inputs);
    assert_eq!(after.tasks, before.tasks);
    assert_eq!(after.permissions, before.permissions);
    assert_eq!(after.attempt_ids, before.attempt_ids);
    assert_eq!(
        serde_json::to_value(&after.attempts).unwrap(),
        serde_json::to_value(&before.attempts).unwrap()
    );
    assert_eq!(
        serde_json::to_value(&after.continuation).unwrap(),
        serde_json::to_value(&before.continuation).unwrap()
    );
    assert_eq!(
        capture.provider_calls.load(Ordering::SeqCst),
        provider_calls
    );
    assert_eq!(executions.load(Ordering::SeqCst), 1);
    close.unwrap();
}

#[tokio::test]
async fn failed_completion_keeps_tool_discovery_private_through_retries_and_empty_reveals() {
    let (thread, release, executions, _) =
        tool_thread_with_mode(u64::MAX, false, ToolMode::Reveal).await;
    release.cancel();
    assert!(matches!(
        thread
            .execute_tool("tool-turn-controlled".into(), CancellationToken::new())
            .await,
        Err(ThreadError::RevisionExhausted)
    ));
    assert!(thread.snapshot().discovered_tools.is_empty());
    thread.reveal_tools(vec![]).await.unwrap();
    let after_empty_reveal = thread.snapshot().discovered_tools;
    assert!(matches!(
        thread.retry_tool_commits().await,
        Err(ThreadError::RevisionExhausted)
    ));
    thread.reveal_tools(vec![]).await.unwrap();
    let after_retry = thread.snapshot();
    at(
        "delete retained discovery completion",
        thread.close_for_deletion(),
    )
    .await
    .unwrap();
    assert!(
        after_empty_reveal.is_empty(),
        "uncommitted discovery escaped the manager"
    );
    assert!(after_retry.discovered_tools.is_empty());
    assert_eq!(after_retry.pending_tool_commits, ["tool-turn-controlled"]);
    assert!(after_retry.interactions.is_empty());
    assert_eq!(executions.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn successful_completion_commits_discovery_together_with_its_interaction() {
    let (thread, release, executions, capture) =
        tool_thread_with_mode(0, false, ToolMode::Reveal).await;
    release.cancel();
    thread
        .execute_tool("tool-turn-controlled".into(), CancellationToken::new())
        .await
        .unwrap();
    let committed = thread.snapshot();
    assert_eq!(committed.interaction_collection_revision, 1);
    assert_eq!(committed.interactions.len(), 1);
    assert_eq!(committed.discovered_tools.len(), 1);
    assert_eq!(committed.discovered_tools[0].tool_id, "hidden");
    assert_eq!(
        capture.last().state.discovered_tools,
        committed.discovered_tools
    );
    thread.reveal_tools(vec![]).await.unwrap();
    assert_eq!(
        thread.snapshot().discovered_tools,
        committed.discovered_tools
    );
    assert!(thread.snapshot().pending_tool_commits.is_empty());
    assert_eq!(executions.load(Ordering::SeqCst), 1);
    thread.close().await.unwrap();
}

#[tokio::test]
async fn permission_record_changes_and_actual_task_pruning_advance_the_joint_collection() {
    let (thread, release, _, capture) = tool_thread(0, true).await;
    let execution = {
        let thread = thread.clone();
        tokio::spawn(async move {
            thread
                .execute_tool("tool-turn-controlled".into(), CancellationToken::new())
                .await
        })
    };
    let pending = observe(&thread, |snapshot| !snapshot.permissions.is_empty()).await;
    assert_eq!(pending.interaction_collection_revision, 1);
    let resolution = PermissionResolution {
        id: "permission:tool-turn-controlled".into(),
        expected_revision: 1,
        decision: PermissionDecision::Allow,
        payload: Some(OpaquePayload::text("approved")),
    };
    thread
        .resolve_execution_permission(resolution.clone())
        .await
        .unwrap();
    let allowed = thread.snapshot();
    assert_eq!(allowed.interaction_collection_revision, 2);
    assert_eq!(
        allowed.permissions[&resolution.id].state,
        PermissionState::Allowed
    );
    thread
        .resolve_execution_permission(resolution)
        .await
        .unwrap();
    assert_eq!(thread.snapshot().interaction_collection_revision, 2);
    release.cancel();
    execution.await.unwrap().unwrap();
    let transfer = capture.last();
    assert_eq!(transfer.state.interaction_collection_revision, 2);
    assert_eq!(thread.snapshot().interaction_collection_revision, 3);
    assert!(thread.snapshot().permissions.is_empty());
    let checkpoint = transfer.pruned().unwrap();
    assert_eq!(checkpoint.state.interaction_collection_revision, 3);
    assert_eq!(
        checkpoint
            .pruned()
            .unwrap()
            .state
            .interaction_collection_revision,
        3
    );
    thread.close().await.unwrap();
}

#[tokio::test]
async fn a_completed_tool_is_retained_on_revision_exhaustion_without_reexecution() {
    let (thread, release, executions, capture) = tool_thread(u64::MAX, false).await;
    release.cancel();
    assert!(matches!(
        at(
            "completed interaction tool",
            thread.execute_tool("tool-turn-controlled".into(), CancellationToken::new()),
        )
        .await,
        Err(ThreadError::RevisionExhausted)
    ));
    let snapshot = thread.snapshot();
    assert_eq!(snapshot.interaction_collection_revision, u64::MAX);
    assert!(snapshot.interactions.is_empty());
    assert_eq!(snapshot.pending_tool_commits, ["tool-turn-controlled"]);
    assert!(snapshot.deliveries.is_empty());
    assert_eq!(
        snapshot.tasks["task:tool-turn-controlled"].status,
        pl_core::thread::task::TaskStatus::Running
    );
    assert!(matches!(
        at("retry interaction completion", thread.retry_tool_commits()).await,
        Err(ThreadError::RevisionExhausted)
    ));
    assert_eq!(executions.load(Ordering::SeqCst), 1);
    assert_eq!(
        thread.snapshot().pending_tool_commits,
        snapshot.pending_tool_commits
    );
    assert!(capture.last().state.interactions.is_empty());
    // The isolated fixture has no user data. Explicit deletion releases the retained completion
    // after checking that preserving close cannot claim it was saved.
    assert!(matches!(
        at("preserve retained completion", thread.close()).await,
        Err(ThreadError::RevisionExhausted)
    ));
    at("delete retained completion", thread.close_for_deletion())
        .await
        .unwrap();
}

#[tokio::test]
async fn permission_exhaustion_rejects_decisions_and_retains_results_that_cannot_be_pruned() {
    for initial in [u64::MAX - 1, u64::MAX - 2] {
        let (thread, release, executions, _) = tool_thread(initial, true).await;
        let execution = {
            let thread = thread.clone();
            tokio::spawn(async move {
                thread
                    .execute_tool("tool-turn-controlled".into(), CancellationToken::new())
                    .await
            })
        };
        let pending = observe(&thread, |snapshot| !snapshot.permissions.is_empty()).await;
        assert_eq!(pending.interaction_collection_revision, initial + 1);
        let resolution = PermissionResolution {
            id: "permission:tool-turn-controlled".into(),
            expected_revision: 1,
            decision: PermissionDecision::Allow,
            payload: Some(OpaquePayload::text("approved")),
        };
        if initial == u64::MAX - 1 {
            assert!(matches!(
                thread.resolve_execution_permission(resolution).await,
                Err(ThreadError::RevisionExhausted)
            ));
            assert_eq!(thread.snapshot().permissions, pending.permissions);
            assert_eq!(thread.snapshot().context, pending.context);
            assert_eq!(thread.snapshot().interaction_collection_revision, u64::MAX);
            at("delete pending permission", thread.close_for_deletion())
                .await
                .unwrap();
            assert!(matches!(
                at("cancel pending permission execution", execution)
                    .await
                    .unwrap(),
                Err(ThreadError::RevisionExhausted)
            ));
        } else {
            thread
                .resolve_execution_permission(resolution)
                .await
                .unwrap();
            let allowed = thread.snapshot();
            assert_eq!(allowed.interaction_collection_revision, u64::MAX);
            release.cancel();
            assert!(matches!(
                at("retain permission completion", execution).await.unwrap(),
                Err(ThreadError::RevisionExhausted)
            ));
            let retained = thread.snapshot();
            assert_eq!(retained.permissions, allowed.permissions);
            assert_eq!(retained.context, allowed.context);
            assert_eq!(retained.interaction_collection_revision, u64::MAX);
            assert_eq!(retained.pending_tool_commits, ["tool-turn-controlled"]);
            assert!(matches!(
                at("retry permission completion", thread.retry_tool_commits()).await,
                Err(ThreadError::RevisionExhausted)
            ));
            at("delete permission completion", thread.close_for_deletion())
                .await
                .unwrap();
        }
        assert_eq!(executions.load(Ordering::SeqCst), 1);
    }
}

#[cfg(feature = "sqlite")]
#[tokio::test]
async fn sqlite_writer_reopens_the_same_resource_cut_as_the_resident_owner() {
    use pl_core::persistence::{SqliteSessionOptions, SqliteSessionStore};

    let directory = tempfile::tempdir().unwrap();
    let options = SqliteSessionOptions {
        path: directory.path().join("interaction-revisions.sqlite"),
    };
    let store = SqliteSessionStore::open(options.clone()).await.unwrap();
    let thread = ThreadHandle::resume_without_model("durable".into(), None).unwrap();
    thread
        .attach_storage(ColdStoreHandle::new(store.clone()))
        .await
        .unwrap();
    thread.request_interaction(question("a")).await.unwrap();
    thread.request_interaction(question("b")).await.unwrap();
    thread.resolve_interaction(answer("a")).await.unwrap();
    thread.flush().await.unwrap();
    let hot = thread.snapshot();
    assert_eq!(hot.interaction_collection_revision, 4);
    thread.close().await.unwrap();
    store.shutdown().await.unwrap();

    let reopened = SqliteSessionStore::open(options).await.unwrap();
    let checkpoint = reopened
        .read_thread_checkpoint("durable")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(checkpoint.state.interaction_collection_revision, 4);
    assert_eq!(checkpoint.state.interactions, hot.interactions);
    let restored = ThreadHandle::resume_without_model("durable".into(), Some(checkpoint)).unwrap();
    assert_eq!(restored.snapshot().interaction_collection_revision, 4);
    assert_eq!(restored.snapshot().interactions, hot.interactions);
    restored.close().await.unwrap();
    reopened.shutdown().await.unwrap();
}
