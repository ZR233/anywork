use crate::support;

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
        HistoryExport, StepInput, ThreadEffectBatch, ThreadHandle, ThreadSnapshot, UsageSummary,
        cold::{ColdStoreError, StorageIdleStatus, StoragePressure},
        history_sink::{HistorySink, HistorySinkHandle},
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
    transfers: Arc<Mutex<Vec<Arc<HistoryExport>>>>,
    durable: Arc<AtomicU64>,
    provider_calls: Arc<AtomicUsize>,
}

impl Capture {
    fn last(&self) -> Arc<HistoryExport> {
        self.transfers.lock().unwrap().last().unwrap().clone()
    }
}

impl HistorySink for Capture {
    fn fold_usage(&self, summary: &mut UsageSummary, effect: &ThreadEffectBatch) {
        let _ = (summary, effect);
    }

    fn reserve_observed_item(&self, _: &str, _: &str, _: &str) -> Result<(), ColdStoreError> {
        Ok(())
    }

    fn reserve_operation_output(&self, _: &str, _: &str, max: u64) -> Result<u64, ColdStoreError> {
        Ok(max)
    }

    fn charge_operation_output(&self, _: &str, _: &str, _: u64) -> Result<(), ColdStoreError> {
        Ok(())
    }

    fn release_operation_output(&self, _: &str, _: &str) {}

    fn pressure(&self, _: &str) -> StoragePressure {
        StoragePressure {
            durable_sequence: self.durable.load(Ordering::SeqCst),
            ..Default::default()
        }
    }

    fn idle_status(&self, thread_id: &str) -> StorageIdleStatus {
        StorageIdleStatus {
            pressure: self.pressure(thread_id),
            reclaimable_thread_bytes: None,
        }
    }

    fn subscribe_pressure(&self, _: &str) -> Option<tokio::sync::watch::Receiver<()>> {
        None
    }

    fn admit(&self, _: &str, write: Arc<HistoryExport>) -> Result<(), ColdStoreError> {
        self.transfers.lock().unwrap().push(write);
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

#[tokio::test]
async fn resolved_transfer_and_resident_are_distinct_cuts_and_restart_keeps_the_resident_version() {
    let thread = ThreadHandle::start_current("collection".into(), None).unwrap();
    let capture = Capture::default();
    thread
        .attach_history(HistorySinkHandle::new(capture.clone()))
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
    let mut restart_state = transfer.state.clone();
    restart_state.retain_live_facts().unwrap();
    assert_eq!(restart_state.interaction_collection_revision, 4);
    assert_eq!(restart_state.interactions, resident.interactions);
    let mut idempotent_state = restart_state.clone();
    idempotent_state.retain_live_facts().unwrap();
    assert_eq!(
        serde_json::to_value(idempotent_state).unwrap(),
        serde_json::to_value(&restart_state).unwrap()
    );

    thread.resolve_interaction(answer("a")).await.unwrap();
    assert_eq!(thread.snapshot().interaction_collection_revision, 4);
    capture
        .durable
        .store(thread.snapshot().commit_sequence, Ordering::SeqCst);
    assert_eq!(thread.snapshot().interaction_collection_revision, 4);
    let current = thread.capture_current(CancellationToken::new()).await.unwrap();
    thread.close().await.unwrap();
    let reopened = ThreadHandle::restore_current(
        serde_json::from_slice(&serde_json::to_vec(&current).unwrap()).unwrap(),
        None,
    )
    .unwrap();
    assert_eq!(reopened.snapshot().interactions["b"], pending_b);
    reopened.close().await.unwrap();
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
    let thread = ThreadHandle::start("tokens".into(), DynModelSession::new(Streaming {
        progress: sender,
        release: release.clone(),
    }))
    .unwrap();
    let capture = Capture::default();
    thread
        .attach_history(HistorySinkHandle::new(capture.clone()))
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
    capture
        .durable
        .store(thread.snapshot().commit_sequence, Ordering::SeqCst);
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
            .all(|export| export.state.interaction_collection_revision == 3)
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
    Reveal,
}

async fn tool_thread(
    permission: bool,
) -> (ThreadHandle, CancellationToken, Arc<AtomicUsize>, Capture) {
    tool_thread_with_mode(permission, ToolMode::Foreground).await
}

async fn tool_thread_with_mode(
    permission: bool,
    mode: ToolMode,
) -> (ThreadHandle, CancellationToken, Arc<AtomicUsize>, Capture) {
    let (model, _) = ScriptedModel::new(&["controlled"]);
    let capture = Capture::default();
    let model = CountingModel {
        inner: model,
        executed: capture.provider_calls.clone(),
    };
    let thread = ThreadHandle::start("tool".into(), DynModelSession::new(model)).unwrap();
    let release = CancellationToken::new();
    let executions = Arc::new(AtomicUsize::new(0));
    thread
        .attach_history(HistorySinkHandle::new(capture.clone()))
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
async fn successful_completion_commits_discovery_together_with_its_interaction() {
    let (thread, release, executions, capture) =
        tool_thread_with_mode(false, ToolMode::Reveal).await;
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

    assert_eq!(executions.load(Ordering::SeqCst), 1);
    thread.close().await.unwrap();
}

#[tokio::test]
async fn permission_record_changes_and_actual_task_pruning_advance_the_joint_collection() {
    let (thread, release, _, capture) = tool_thread(true).await;
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
    let mut current_state = transfer.state.clone();
    current_state.retain_live_facts().unwrap();
    assert_eq!(current_state.interaction_collection_revision, 3);
    let mut again = current_state.clone();
    again.retain_live_facts().unwrap();
    assert_eq!(again.interaction_collection_revision, 3);
    thread.close().await.unwrap();
}
