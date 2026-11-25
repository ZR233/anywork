//! Per-agent ACP Workflow and Plan ownership, atomic persistence, and state push.
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use anyhow::{Context, Result, ensure};
use pl_tool_plan::{
    Plan, PlanActor, PlanHistoryArgs, PlanHistoryResponse, PlanHost, PlanNextResponse, PlanRecord,
    PlanSnapshot, PlanTransitionArgs, PlanTransitionCommand, PlanTransitionOutcome,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use tokio::sync::{Mutex as AsyncMutex, watch};

#[cfg(test)]
use std::sync::atomic::{AtomicBool, Ordering};

use crate::mode::{SavedThreadMode, ThreadModeId, ThreadModeManager};
use crate::plan_tool::AgentSessionPlanRuntimeSnapshot;
use crate::protocol::AcpWorkflowStateSnapshot;
use crate::studio::thread_projection::workflow_graph_from_saved_mode;
use crate::workflow_tool::machine::{
    RestartInput, TransitionInput, WorkflowMachine, WorkflowOperation,
};
use crate::workflow_tool::{
    WorkflowSessionState, archive_workflow_for_mode_change, reconcile_workflow_for_turn,
};

const WORKFLOW_FILE_NAME: &str = "acp-workflow.json";
const PLAN_FILE_NAME: &str = "acp-plan.json";

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PersistedAcpWorkflow {
    mode_id: ThreadModeId,
    saved_mode: SavedThreadMode,
    state: WorkflowSessionState,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    injected_prompt_hash: Option<String>,
}

#[derive(Debug, thiserror::Error)]
#[error("{0}")]
pub(crate) struct AcpWorkflowPlanError(pub String);

#[derive(Debug, Clone)]
pub(crate) struct AcpPlanToolContext {
    pub call_id: String,
    pub turn_id: String,
    pub now_ms: i64,
}

struct AcpWorkflowStateInner {
    workflow: Option<PersistedAcpWorkflow>,
    plan: PlanRecord,
}

/// Owns the per-agent ACP `Plan` state machine and (for root) the selected Thread Mode +
/// workflow state machine, independently of Native catalog `session.native_mode`.
pub(crate) struct AcpWorkflowPlanOwner {
    thread_id: String,
    is_root: bool,
    resources_dir: PathBuf,
    thread_modes: ThreadModeManager,
    inner: Arc<Mutex<AcpWorkflowStateInner>>,
    /// Shared by the owner task that writes, commits memory, and notifies.
    /// Caller cancellation abandons only the wait, not this transaction.
    persist_gate: Arc<AsyncMutex<()>>,
    updates: watch::Sender<Option<AcpWorkflowStateSnapshot>>,
    #[cfg(test)]
    persist_pause: Arc<AtomicBool>,
    #[cfg(test)]
    persist_entered: Arc<tokio::sync::Notify>,
    #[cfg(test)]
    persist_release: Arc<tokio::sync::Notify>,
}

impl std::fmt::Debug for AcpWorkflowPlanOwner {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("AcpWorkflowPlanOwner")
            .field("thread_id", &self.thread_id)
            .field("is_root", &self.is_root)
            .finish_non_exhaustive()
    }
}

impl AcpWorkflowPlanOwner {
    /// Initializes or restores per-agent workflow and plan state from `resources_dir`.
    pub(crate) async fn load_or_init(
        thread_id: String,
        is_root: bool,
        resources_dir: PathBuf,
        thread_modes: ThreadModeManager,
        requested_mode: Option<ThreadModeId>,
    ) -> Result<Arc<Self>> {
        let plan_path = resources_dir.join(PLAN_FILE_NAME);
        let plan = if tokio::fs::try_exists(&plan_path).await? {
            let bytes = tokio::fs::read(&plan_path).await?;
            let record: PlanRecord = serde_json::from_slice(&bytes)
                .with_context(|| format!("decode ACP plan state `{}`", plan_path.display()))?;
            // Validate via `Plan::from_record`.
            let _ = Plan::from_record(record.clone())
                .map_err(|err| anyhow::anyhow!("invalid persisted ACP plan: {err}"))?;
            record
        } else {
            Plan::default().into_record()
        };

        let mut initial_workflow_created = false;
        let workflow = if is_root {
            let wf_path = resources_dir.join(WORKFLOW_FILE_NAME);
            if tokio::fs::try_exists(&wf_path).await? {
                let bytes = tokio::fs::read(&wf_path).await?;
                let mut persisted: PersistedAcpWorkflow = serde_json::from_slice(&bytes)
                    .with_context(|| {
                        format!("decode ACP workflow state `{}`", wf_path.display())
                    })?;
                if let Some(replacement) = persisted.mode_id.legacy_builtin_replacement()
                    && let Some(auto_mode) = thread_modes.snapshot().mode(&replacement)
                {
                    persisted.mode_id = replacement;
                    persisted.saved_mode = SavedThreadMode::capture(&auto_mode, None);
                    initial_workflow_created = true;
                }
                Some(persisted)
            } else {
                let resolved_mode_id = requested_mode
                    .map(|id| id.legacy_builtin_replacement().unwrap_or(id))
                    .unwrap_or_else(ThreadModeId::auto);
                let catalog = thread_modes.snapshot();
                let registered = catalog
                    .mode(&resolved_mode_id)
                    .or_else(|| catalog.mode(&ThreadModeId::auto()))
                    .context("requested or built-in auto Thread Mode is unavailable")?;
                let saved_mode = SavedThreadMode::capture(&registered, None);
                initial_workflow_created = true;
                Some(PersistedAcpWorkflow {
                    mode_id: saved_mode.definition.id.clone(),
                    saved_mode,
                    state: WorkflowSessionState::default(),
                    injected_prompt_hash: None,
                })
            }
        } else {
            None
        };

        let (updates, _) = watch::channel(None);
        let owner = Arc::new(Self {
            thread_id,
            is_root,
            resources_dir,
            thread_modes,
            inner: Arc::new(Mutex::new(AcpWorkflowStateInner { workflow, plan })),
            persist_gate: Arc::new(AsyncMutex::new(())),
            updates,
            #[cfg(test)]
            persist_pause: Arc::new(AtomicBool::new(false)),
            #[cfg(test)]
            persist_entered: Arc::new(tokio::sync::Notify::new()),
            #[cfg(test)]
            persist_release: Arc::new(tokio::sync::Notify::new()),
        });
        if initial_workflow_created {
            owner.persist_workflow().await?;
        }
        let initial_snapshot = owner.snapshot();
        owner.updates.send_replace(Some(initial_snapshot));
        Ok(owner)
    }

    /// Reads a root ACP thread's workflow graph directly from disk without activating the session.
    pub(crate) async fn read_cold_graph(
        resources_dir: &Path,
        thread_modes: &ThreadModeManager,
    ) -> Result<Option<crate::workflow_tool::WorkflowRuntimeGraphSnapshot>> {
        let wf_path = resources_dir.join(WORKFLOW_FILE_NAME);
        if tokio::fs::try_exists(&wf_path).await? {
            let bytes = tokio::fs::read(&wf_path).await?;
            let persisted: PersistedAcpWorkflow = serde_json::from_slice(&bytes)
                .with_context(|| format!("decode cold ACP workflow `{}`", wf_path.display()))?;
            let deleted = thread_modes
                .snapshot()
                .mode(&persisted.saved_mode.definition.id)
                .is_none();
            return Ok(workflow_graph_from_saved_mode(
                &persisted.saved_mode,
                deleted,
            ));
        }
        let catalog = thread_modes.snapshot();
        if let Some(auto) = catalog.mode(&ThreadModeId::auto()) {
            return Ok(
                crate::studio::thread_projection::workflow_graph_from_definition(
                    &auto.definition(),
                    false,
                ),
            );
        }
        Ok(None)
    }

    pub(crate) fn subscribe(&self) -> watch::Receiver<Option<AcpWorkflowStateSnapshot>> {
        self.updates.subscribe()
    }

    pub(crate) fn snapshot(&self) -> AcpWorkflowStateSnapshot {
        let modes = self.thread_modes.snapshot();
        let guard = self
            .inner
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        Self::snapshot_locked(&guard, &modes)
    }

    fn snapshot_locked(
        guard: &AcpWorkflowStateInner,
        modes: &crate::mode::ThreadModeRegistrySnapshot,
    ) -> AcpWorkflowStateSnapshot {
        let plan_snapshot = Plan::from_record(guard.plan.clone())
            .unwrap_or_default()
            .snapshot();
        let plan = Some(AgentSessionPlanRuntimeSnapshot::from(&plan_snapshot));
        if let Some(wf) = &guard.workflow {
            let mode_deleted = modes.mode(&wf.mode_id).is_none();
            let mut run = wf
                .saved_mode
                .project_workflow_state(&wf.state, mode_deleted)
                .current_run;
            if let Some(r) = run.as_mut()
                && wf.state.revision > 0
                && r.visited_state_ids.is_empty()
            {
                r.visited_state_ids.push(r.current_state_id.clone());
            }
            let graph = workflow_graph_from_saved_mode(&wf.saved_mode, mode_deleted);
            AcpWorkflowStateSnapshot {
                mode_id: Some(wf.mode_id.clone()),
                mode_display_name: Some(wf.saved_mode.definition.display_name.clone()),
                run,
                graph,
                plan,
            }
        } else {
            AcpWorkflowStateSnapshot {
                mode_id: None,
                mode_display_name: None,
                run: None,
                graph: None,
                plan,
            }
        }
    }

    pub(crate) fn compiled_mode_instructions(&self) -> Option<String> {
        let guard = self
            .inner
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let wf = guard.workflow.as_ref()?;
        let mode_prompt = wf.saved_mode.definition.prompt.trim();
        let mut out = format!(
            "\n# Thread Mode: {} (`{}`)\n",
            wf.saved_mode.definition.display_name, wf.mode_id
        );
        if !mode_prompt.is_empty() {
            out.push_str(mode_prompt);
            out.push('\n');
        }
        out.push_str(
            "\n[ACP Host Tool Name Mapping]\n\
             In this ACP Host MCP session, all workflow_* and plan_* tools referenced in Mode \
             instructions are exposed with the `anywork_` prefix:\n\
             - Root workflow tools: `anywork_workflow_current`, `anywork_workflow_next`, \
               `anywork_workflow_graph`, `anywork_workflow_history`, `anywork_workflow_transition`, \
               `anywork_workflow_restart`.\n\
             - Independent per-agent Plan tools: `anywork_plan_current`, `anywork_plan_next`, \
               `anywork_plan_history`, `anywork_plan_transition`.\n\
             Both `anywork_workflow_transition` and `anywork_plan_transition` default to `force=false` \
             and validate allowed paths (returning allowed candidates and all states on rejection). \
             Keep `force=false` when submitting `anywork_plan_transition` to `awaitingConfirmation` \
             (transition `approved -> drafting` first when re-planning), and write ELI5 Markdown by \
             default. During `reviewing`, call `anywork_plan_current` to read the full Plan \
             document and guide reviewers accordingly. Only pass `force=true` when you intentionally \
             need to override state-machine rules.\n",
        );
        Some(out)
    }

    /// Reconciles workflow state before sending a prompt on an ACP root agent and builds
    /// an assistant-only `[Studio Host State]` context block without rewriting user text.
    pub(crate) async fn reconcile_run_for_turn(&self) -> Result<Option<String>> {
        if !self.is_root {
            return Ok(None);
        }
        let now = crate::studio::unix_seconds();
        let thread_id = self.thread_id.clone();
        let modes = self.thread_modes.snapshot();
        self.commit_record(move |guard| {
            let plan_snapshot = Plan::from_record(guard.plan.clone())
                .unwrap_or_default()
                .snapshot();
            let Some(current) = guard.workflow.clone() else {
                return Ok(PreparedRecord::Ready(None));
            };
            let registered = current
                .saved_mode
                .registered()
                .map_err(|err| anyhow::anyhow!("invalid frozen ACP mode: {err}"))?;
            let before = current.state.clone();
            let next_state = reconcile_workflow_for_turn(
                Some(current.state.clone()),
                &registered.descriptor().id,
                registered.workflow_binding(),
                &thread_id,
                now,
            )
            .map_err(|err| anyhow::anyhow!("reconcile ACP workflow failed: {err}"))?
            .unwrap_or_default();
            let state_changed = next_state != before;
            let prompt_hash =
                pl_core::context::content_hash(current.saved_mode.definition.prompt.as_bytes());
            let mode_prompt_changed = current.injected_prompt_hash.as_ref() != Some(&prompt_hash);
            let mut next = current;
            next.state = next_state;
            next.injected_prompt_hash = Some(prompt_hash);
            let block = studio_host_state_block(&next, &plan_snapshot, mode_prompt_changed);
            if !state_changed && !mode_prompt_changed {
                return Ok(PreparedRecord::Ready(Some(block)));
            }
            write_workflow(&guard.plan, next, &modes, state_changed, Some(block))
        })
        .await
    }

    pub(crate) async fn set_mode(
        &self,
        mode_id: ThreadModeId,
        registered: &crate::mode::RegisteredThreadMode,
    ) -> Result<AcpWorkflowStateSnapshot> {
        ensure!(self.is_root, "only root ACP session owns workflow Mode");
        let now = crate::studio::unix_seconds();
        let modes = self.thread_modes.snapshot();
        let saved_mode = SavedThreadMode::capture(registered, None);
        let descriptor_id = registered.descriptor().id.clone();
        self.commit_record(move |guard| {
            let previous_state = guard.workflow.as_ref().map(|wf| wf.state.clone());
            let next_state = archive_workflow_for_mode_change(previous_state, &mode_id, now)
                .map_err(|err| anyhow::anyhow!("archive ACP workflow on mode change: {err}"))?
                .unwrap_or_default();
            let workflow = PersistedAcpWorkflow {
                mode_id: descriptor_id,
                saved_mode,
                state: next_state,
                injected_prompt_hash: None,
            };
            let snapshot = AcpWorkflowPlanOwner::snapshot_locked(
                &AcpWorkflowStateInner {
                    workflow: Some(workflow.clone()),
                    plan: guard.plan.clone(),
                },
                &modes,
            );
            write_workflow(&guard.plan, workflow, &modes, true, snapshot)
        })
        .await
    }

    pub(crate) async fn workflow_current_json(&self) -> Result<Value, AcpWorkflowPlanError> {
        let machine = self.workflow_machine()?;
        Ok(machine.current_snapshot())
    }

    pub(crate) async fn workflow_next_json(&self) -> Result<Value, AcpWorkflowPlanError> {
        let machine = self.workflow_machine()?;
        Ok(machine.next_snapshot())
    }

    pub(crate) async fn workflow_graph_json(&self) -> Result<Value, AcpWorkflowPlanError> {
        let machine = self.workflow_machine()?;
        Ok(machine.graph_snapshot())
    }

    pub(crate) async fn workflow_history_json(&self) -> Result<Value, AcpWorkflowPlanError> {
        let machine = self.workflow_machine()?;
        Ok(machine.history_snapshot())
    }

    pub(crate) async fn workflow_transition(
        &self,
        input: TransitionInput,
        identity: WorkflowOperation,
        argument_hash: String,
    ) -> Result<Value, AcpWorkflowPlanError> {
        let modes = self.thread_modes.snapshot();
        self.commit_record(move |guard| {
            let workflow = guard
                .workflow
                .as_ref()
                .ok_or_else(|| AcpWorkflowPlanError("ACP agent has no active workflow".into()))?;
            let registered = workflow
                .saved_mode
                .registered()
                .map_err(|err| AcpWorkflowPlanError(err.to_string()))?;
            let binding = registered.workflow_binding().ok_or_else(|| {
                AcpWorkflowPlanError("Selected Mode has no workflow graph".into())
            })?;
            let mut machine = WorkflowMachine::new(binding, workflow.state.clone());
            let response = machine
                .apply_transition(
                    input,
                    &identity,
                    argument_hash,
                    crate::studio::unix_seconds(),
                )
                .map_err(|err| AcpWorkflowPlanError(err.to_string()))?;
            let next = machine.into_state();
            let value = serde_json::to_value(&response)
                .map_err(|err| AcpWorkflowPlanError(err.to_string()))?;
            if next == workflow.state {
                return Ok(PreparedRecord::Ready(value));
            }
            let mut updated = workflow.clone();
            updated.state = next;
            write_workflow(&guard.plan, updated, &modes, true, value)
        })
        .await
        .map_err(|err| AcpWorkflowPlanError(err.to_string()))
    }

    pub(crate) async fn workflow_restart(
        &self,
        input: RestartInput,
        identity: WorkflowOperation,
        argument_hash: String,
    ) -> Result<Value, AcpWorkflowPlanError> {
        let modes = self.thread_modes.snapshot();
        self.commit_record(move |guard| {
            let workflow = guard
                .workflow
                .as_ref()
                .ok_or_else(|| AcpWorkflowPlanError("ACP agent has no active workflow".into()))?;
            let registered = workflow
                .saved_mode
                .registered()
                .map_err(|err| AcpWorkflowPlanError(err.to_string()))?;
            let binding = registered.workflow_binding().ok_or_else(|| {
                AcpWorkflowPlanError("Selected Mode has no workflow graph".into())
            })?;
            let mut machine = WorkflowMachine::new(binding, workflow.state.clone());
            let response = machine
                .apply_restart(
                    input,
                    &identity,
                    argument_hash,
                    crate::studio::unix_seconds(),
                )
                .map_err(|err| AcpWorkflowPlanError(err.to_string()))?;
            let next = machine.into_state();
            let value = serde_json::to_value(&response)
                .map_err(|err| AcpWorkflowPlanError(err.to_string()))?;
            if next == workflow.state {
                return Ok(PreparedRecord::Ready(value));
            }
            let mut updated = workflow.clone();
            updated.state = next;
            write_workflow(&guard.plan, updated, &modes, true, value)
        })
        .await
        .map_err(|err| AcpWorkflowPlanError(err.to_string()))
    }

    fn workflow_machine(&self) -> Result<WorkflowMachine, AcpWorkflowPlanError> {
        let guard = self
            .inner
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let wf = guard
            .workflow
            .as_ref()
            .ok_or_else(|| AcpWorkflowPlanError("ACP agent has no active workflow".into()))?;
        let registered = wf
            .saved_mode
            .registered()
            .map_err(|err| AcpWorkflowPlanError(err.to_string()))?;
        let binding = registered
            .workflow_binding()
            .ok_or_else(|| AcpWorkflowPlanError("Selected Mode has no workflow graph".into()))?;
        Ok(WorkflowMachine::new(binding, wf.state.clone()))
    }

    async fn persist_workflow(&self) -> Result<()> {
        let _gate = self.persist_gate.lock().await;
        let payload = {
            let guard = self
                .inner
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let Some(wf) = &guard.workflow else {
                return Ok(());
            };
            serde_json::to_vec_pretty(wf)?
        };
        write_bytes(self.resources_dir.join(WORKFLOW_FILE_NAME), payload).await
    }

    /// Computes under the persist gate, writes the clone, then commits memory and notifies.
    ///
    /// The spawned owner keeps the gate until that sequence finishes. Dropping the caller only
    /// stops waiting; it does not roll back a write that has already been accepted.
    async fn commit_record<T, F>(&self, prepare: F) -> Result<T>
    where
        T: Send + 'static,
        F: FnOnce(&AcpWorkflowStateInner) -> Result<PreparedRecord<T>> + Send + 'static,
    {
        let (tx, rx) = tokio::sync::oneshot::channel();
        let gate = Arc::clone(&self.persist_gate);
        let inner = Arc::clone(&self.inner);
        let updates = self.updates.clone();
        let resources_dir = self.resources_dir.clone();
        #[cfg(test)]
        let pause = self.persist_test_pause();
        tokio::spawn(async move {
            let outcome = async {
                let _gate = gate.lock().await;
                let prepared = {
                    let guard = inner
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner);
                    prepare(&guard)?
                };
                match prepared {
                    PreparedRecord::Ready(value) => Ok(value),
                    PreparedRecord::Write(write) => {
                        let PreparedWrite {
                            bytes,
                            install,
                            snapshot,
                            value,
                        } = *write;
                        #[cfg(test)]
                        if let Some(pause) = pause {
                            pause.entered.notify_one();
                            pause.release.notified().await;
                        }
                        let path = resources_dir.join(install.file_name());
                        write_bytes(path, bytes).await?;
                        {
                            let mut guard = inner
                                .lock()
                                .unwrap_or_else(std::sync::PoisonError::into_inner);
                            install.commit(&mut guard);
                        }
                        if let Some(snapshot) = snapshot {
                            updates.send_replace(Some(snapshot));
                        }
                        Ok(value)
                    }
                }
            }
            .await;
            let _ = tx.send(outcome);
        });
        rx.await
            .context("ACP persist task ended before reporting a result")?
    }

    #[cfg(test)]
    fn persist_test_pause(&self) -> Option<PersistTestPause> {
        // The flag only selects this test hook. The notify itself is the synchronization edge.
        if self.persist_pause.swap(false, Ordering::Relaxed) {
            Some(PersistTestPause {
                entered: Arc::clone(&self.persist_entered),
                release: Arc::clone(&self.persist_release),
            })
        } else {
            None
        }
    }
}

impl PlanHost for AcpWorkflowPlanOwner {
    type Context = AcpPlanToolContext;
    type Error = AcpWorkflowPlanError;

    async fn current(&self, _context: Self::Context) -> Result<PlanSnapshot, Self::Error> {
        let guard = self
            .inner
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let plan = Plan::from_record(guard.plan.clone())
            .map_err(|err| AcpWorkflowPlanError(err.to_string()))?;
        Ok(plan.snapshot())
    }

    async fn next(&self, _context: Self::Context) -> Result<PlanNextResponse, Self::Error> {
        let guard = self
            .inner
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let plan = Plan::from_record(guard.plan.clone())
            .map_err(|err| AcpWorkflowPlanError(err.to_string()))?;
        Ok(plan.next())
    }

    async fn history(
        &self,
        args: PlanHistoryArgs,
        _context: Self::Context,
    ) -> Result<PlanHistoryResponse, Self::Error> {
        let guard = self
            .inner
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let plan = Plan::from_record(guard.plan.clone())
            .map_err(|err| AcpWorkflowPlanError(err.to_string()))?;
        Ok(plan.history(args.limit))
    }

    async fn transition(
        &self,
        args: PlanTransitionArgs,
        context: Self::Context,
    ) -> Result<PlanTransitionOutcome, Self::Error> {
        let idempotency_key = args.idempotency_key.clone().or_else(|| {
            Some(format!(
                "{}/{}/{}",
                self.thread_id, context.turn_id, context.call_id
            ))
        });
        let arg_hash = Some(pl_core::context::content_hash(
            serde_json::to_string(&args).unwrap_or_default().as_bytes(),
        ));
        let modes = self.thread_modes.snapshot();
        let now_ms = context.now_ms;
        self.commit_record(move |guard| {
            let mut plan = Plan::from_record(guard.plan.clone())
                .map_err(|err| AcpWorkflowPlanError(err.to_string()))?;
            let command = PlanTransitionCommand {
                target_state: args.target_state,
                content: args.content,
                feedback: args.feedback,
                reason: args.reason,
                force: args.force,
                expected_revision: args.expected_revision,
                idempotency_key,
                argument_hash: arg_hash,
                actor: PlanActor::Agent,
                timestamp_ms: now_ms,
            };
            let outcome = plan.transition(command);
            if !(outcome.accepted && !outcome.replayed) {
                return Ok(PreparedRecord::Ready(outcome));
            }
            write_plan(guard.workflow.as_ref(), plan.into_record(), &modes, outcome)
        })
        .await
        .map_err(|err| AcpWorkflowPlanError(err.to_string()))
    }
}

enum PreparedRecord<T> {
    Ready(T),
    Write(Box<PreparedWrite<T>>),
}

struct PreparedWrite<T> {
    bytes: Vec<u8>,
    install: InstalledRecord,
    snapshot: Option<AcpWorkflowStateSnapshot>,
    value: T,
}

enum InstalledRecord {
    Workflow(Box<PersistedAcpWorkflow>),
    Plan(PlanRecord),
}

impl InstalledRecord {
    fn file_name(&self) -> &'static str {
        match self {
            Self::Workflow(_) => WORKFLOW_FILE_NAME,
            Self::Plan(_) => PLAN_FILE_NAME,
        }
    }

    fn commit(self, guard: &mut AcpWorkflowStateInner) {
        match self {
            Self::Workflow(workflow) => guard.workflow = Some(*workflow),
            Self::Plan(plan) => guard.plan = plan,
        }
    }
}

#[cfg(test)]
struct PersistTestPause {
    entered: Arc<tokio::sync::Notify>,
    release: Arc<tokio::sync::Notify>,
}

fn write_workflow<T>(
    current_plan: &PlanRecord,
    workflow: PersistedAcpWorkflow,
    modes: &crate::mode::ThreadModeRegistrySnapshot,
    notify: bool,
    value: T,
) -> Result<PreparedRecord<T>> {
    let bytes = serde_json::to_vec_pretty(&workflow)?;
    let snapshot = notify.then(|| {
        AcpWorkflowPlanOwner::snapshot_locked(
            &AcpWorkflowStateInner {
                workflow: Some(workflow.clone()),
                plan: current_plan.clone(),
            },
            modes,
        )
    });
    Ok(PreparedRecord::Write(Box::new(PreparedWrite {
        bytes,
        install: InstalledRecord::Workflow(Box::new(workflow)),
        snapshot,
        value,
    })))
}

fn write_plan<T>(
    current_workflow: Option<&PersistedAcpWorkflow>,
    plan: PlanRecord,
    modes: &crate::mode::ThreadModeRegistrySnapshot,
    value: T,
) -> Result<PreparedRecord<T>> {
    let bytes = serde_json::to_vec_pretty(&plan)?;
    let snapshot = AcpWorkflowPlanOwner::snapshot_locked(
        &AcpWorkflowStateInner {
            workflow: current_workflow.cloned(),
            plan: plan.clone(),
        },
        modes,
    );
    Ok(PreparedRecord::Write(Box::new(PreparedWrite {
        bytes,
        install: InstalledRecord::Plan(plan),
        snapshot: Some(snapshot),
        value,
    })))
}

fn studio_host_state_block(
    workflow: &PersistedAcpWorkflow,
    plan: &PlanSnapshot,
    include_mode_prompt: bool,
) -> String {
    let mode_prompt_section =
        if include_mode_prompt && !workflow.saved_mode.definition.prompt.trim().is_empty() {
            Some(format!(
                "Mode `{}` (`{}`) instructions:\n{}",
                workflow.saved_mode.definition.display_name,
                workflow.mode_id,
                workflow.saved_mode.definition.prompt.trim()
            ))
        } else {
            None
        };
    let machine_json = workflow.state.current_run.as_ref().map(|run| {
        let graph = workflow.saved_mode.definition.workflow.as_ref();
        let current_state =
            graph.and_then(|g| g.states.iter().find(|s| s.id == run.current_state_id));
        let outgoing: Vec<Value> = graph
            .map(|g| {
                g.transitions
                    .iter()
                    .filter(|t| t.source_state_id == run.current_state_id)
                    .map(|t| {
                        serde_json::json!({
                            "targetStateId": t.target_state_id,
                            "guard": t.guard,
                        })
                    })
                    .collect()
            })
            .unwrap_or_default();
        serde_json::json!({
            "modeId": workflow.mode_id,
            "modeDisplayName": workflow.saved_mode.definition.display_name,
            "runId": run.run_id,
            "revision": workflow.state.revision,
            "lifecycle": run.lifecycle,
            "currentState": current_state,
            "allowedTransitions": outgoing,
        })
    });
    let plan_json = serde_json::json!({
        "state": plan.state,
        "revision": plan.revision,
        "hasDocument": plan.document.is_some(),
    });
    format!(
        "[Studio Host State]\n{}{}\nPlan: {}\nUse `anywork_workflow_*` (when workflow is present) and `anywork_plan_*` MCP tools to inspect or advance states. In `planning`, clarify design conflicts first, then submit an ELI5 plan via `anywork_plan_transition(targetState=\"awaitingConfirmation\", force=false)`. In `reviewing`, call `anywork_plan_current` to read the full Plan document and instruct reviewers from it.\n",
        mode_prompt_section
            .as_ref()
            .map_or(String::new(), |section| format!("{section}\n\n")),
        machine_json.as_ref().map_or_else(
            || "Workflow: none".to_string(),
            |value| format!("Workflow: {value}")
        ),
        plan_json,
    )
}

async fn write_bytes(path: PathBuf, bytes: Vec<u8>) -> Result<()> {
    let display = path.display().to_string();
    tokio::task::spawn_blocking(move || pl_tool::workspace::write_file_atomically(&path, &bytes))
        .await
        .with_context(|| format!("join ACP state persist `{display}`"))?
        .with_context(|| format!("persist ACP state `{display}`"))
}

#[cfg(test)]
mod tests {
    use std::path::Path;
    use std::sync::Arc;
    use std::time::Duration;

    use pl_tool_plan::{PlanHost, PlanState, PlanTransitionArgs};
    use tokio::time::timeout;

    use super::{
        AcpPlanToolContext, AcpWorkflowPlanOwner, PLAN_FILE_NAME, PersistedAcpWorkflow,
        WORKFLOW_FILE_NAME,
    };
    use crate::mode::ThreadModeManager;
    use crate::studio::thread::register_builtins;
    use crate::workflow_tool::machine::{CompletionInput, TransitionInput, WorkflowOperation};

    async fn started_owner(dir: &Path) -> anyhow::Result<Arc<AcpWorkflowPlanOwner>> {
        let modes = ThreadModeManager::default();
        register_builtins(&modes)?;
        let owner = AcpWorkflowPlanOwner::load_or_init(
            "thread-persist".into(),
            true,
            dir.to_path_buf(),
            modes,
            None,
        )
        .await?;
        owner.reconcile_run_for_turn().await?;
        Ok(owner)
    }

    fn workflow_on_disk(dir: &Path) -> PersistedAcpWorkflow {
        let bytes = std::fs::read(dir.join(WORKFLOW_FILE_NAME)).expect("workflow file");
        serde_json::from_slice(&bytes).expect("workflow json")
    }

    fn state_id(workflow: &PersistedAcpWorkflow) -> String {
        workflow
            .state
            .current_run
            .as_ref()
            .expect("active run")
            .current_state_id
            .clone()
    }

    fn force_to_planning(owner_dir: &Path) -> TransitionInput {
        let workflow = workflow_on_disk(owner_dir);
        let run = workflow.state.current_run.expect("active run");
        TransitionInput {
            expected_run_id: run.run_id,
            expected_revision: workflow.state.revision,
            expected_state_id: run.current_state_id,
            target_state_id: "planning".into(),
            force: true,
            completion: CompletionInput {
                reason: "force".into(),
                summary: "move".into(),
                evidence: vec!["e".into()],
            },
        }
    }

    fn operation(call_id: &str) -> WorkflowOperation {
        WorkflowOperation {
            turn_id: "turn-1".into(),
            call_id: call_id.into(),
        }
    }

    fn plan_args(force: bool) -> PlanTransitionArgs {
        PlanTransitionArgs {
            target_state: PlanState::Approved,
            content: Some("# Plan\n\n- step".into()),
            feedback: None,
            reason: Some("commit".into()),
            force,
            expected_revision: Some(0),
            idempotency_key: None,
        }
    }

    fn plan_context(call_id: &str) -> AcpPlanToolContext {
        AcpPlanToolContext {
            call_id: call_id.into(),
            turn_id: "turn-1".into(),
            now_ms: 1_700_000_000_000,
        }
    }

    #[tokio::test]
    async fn unchanged_workflow_and_plan_do_not_persist_or_notify() -> anyhow::Result<()> {
        let dir = tempfile::tempdir()?;
        let owner = started_owner(dir.path()).await?;
        let mut updates = owner.subscribe();
        updates.borrow_and_update();
        let before = std::fs::read(dir.path().join(WORKFLOW_FILE_NAME))?;

        let again = owner.reconcile_run_for_turn().await?;
        assert!(again.is_some());
        assert!(!updates.has_changed().expect("workflow watch"));
        assert_eq!(std::fs::read(dir.path().join(WORKFLOW_FILE_NAME))?, before);

        let current = owner.workflow_current_json().await?;
        let rejected = owner
            .workflow_transition(
                TransitionInput {
                    expected_run_id: current["runId"].as_str().unwrap().to_string(),
                    expected_revision: current["revision"].as_u64().unwrap() + 1,
                    expected_state_id: current["currentStateId"].as_str().unwrap().to_string(),
                    target_state_id: "planning".into(),
                    force: true,
                    completion: CompletionInput {
                        reason: "stale".into(),
                        summary: "stale".into(),
                        evidence: Vec::new(),
                    },
                },
                operation("reject-workflow"),
                "hash-reject".into(),
            )
            .await?;
        assert_eq!(rejected["accepted"], false);
        assert!(!updates.has_changed().expect("workflow watch"));
        assert_eq!(std::fs::read(dir.path().join(WORKFLOW_FILE_NAME))?, before);

        let rejected_plan = owner
            .transition(plan_args(false), plan_context("reject-plan"))
            .await?;
        assert!(!rejected_plan.accepted);
        assert_eq!(owner.snapshot().plan.expect("plan").revision, 0);
        assert!(!dir.path().join(PLAN_FILE_NAME).exists());
        assert!(!updates.has_changed().expect("workflow watch"));
        Ok(())
    }

    #[tokio::test]
    async fn blocked_state_path_does_not_advance_memory_or_notification() -> anyhow::Result<()> {
        let dir = tempfile::tempdir()?;
        let resources = dir.path().join("resources");
        let saved = dir.path().join("saved");
        let owner = started_owner(&resources).await?;
        let before = std::fs::read(resources.join(WORKFLOW_FILE_NAME))?;
        let before_state = state_id(&workflow_on_disk(&resources));
        let transition = force_to_planning(&resources);
        let mut updates = owner.subscribe();
        updates.borrow_and_update();
        // Preserve the original files while making future writes fail on every platform.
        std::fs::rename(&resources, &saved)?;
        std::fs::write(&resources, b"block the state directory")?;

        let workflow_error = owner
            .workflow_transition(
                transition,
                operation("blocked-workflow"),
                "hash-blocked-workflow".into(),
            )
            .await
            .expect_err("workflow persist must fail");
        assert!(
            workflow_error.to_string().contains("persist ACP state"),
            "{workflow_error}"
        );
        let plan_error = owner
            .transition(plan_args(true), plan_context("blocked-plan"))
            .await
            .expect_err("plan persist must fail");
        assert!(
            plan_error.to_string().contains("persist ACP state"),
            "{plan_error}"
        );

        assert_eq!(std::fs::read(saved.join(WORKFLOW_FILE_NAME))?, before);
        assert_eq!(
            owner.snapshot().run.expect("run").current_state_id,
            before_state
        );
        assert_eq!(owner.snapshot().plan.expect("plan").revision, 0);
        assert!(!saved.join(PLAN_FILE_NAME).exists());
        assert_eq!(std::fs::read(&resources)?, b"block the state directory");
        assert!(!updates.has_changed().expect("workflow watch"));
        Ok(())
    }

    #[tokio::test]
    async fn caller_cancel_still_commits_persisted_workflow() -> anyhow::Result<()> {
        let dir = tempfile::tempdir()?;
        let owner = started_owner(dir.path()).await?;
        let before = std::fs::read(dir.path().join(WORKFLOW_FILE_NAME))?;
        let before_state = state_id(&workflow_on_disk(dir.path()));
        let mut updates = owner.subscribe();
        updates.borrow_and_update();
        owner
            .persist_pause
            .store(true, std::sync::atomic::Ordering::Relaxed);

        let worker = Arc::clone(&owner);
        let input = force_to_planning(dir.path());
        let running = tokio::spawn(async move {
            worker
                .workflow_transition(input, operation("cancel-workflow"), "hash-cancel".into())
                .await
        });
        timeout(Duration::from_secs(5), owner.persist_entered.notified())
            .await
            .expect("persist task should reach the gate");
        running.abort();
        let joined = timeout(Duration::from_secs(5), running)
            .await
            .expect("cancelled caller should stop waiting");
        assert!(joined.expect_err("caller task").is_cancelled());
        assert_eq!(state_id(&workflow_on_disk(dir.path())), before_state);
        assert_eq!(std::fs::read(dir.path().join(WORKFLOW_FILE_NAME))?, before);
        assert_eq!(
            owner.snapshot().run.expect("run").current_state_id,
            before_state
        );
        assert!(!updates.has_changed().expect("workflow watch"));

        owner.persist_release.notify_one();
        timeout(Duration::from_secs(5), updates.changed())
            .await
            .expect("background commit should notify")?;
        assert_eq!(
            owner.snapshot().run.expect("run").current_state_id,
            "planning"
        );
        assert_eq!(state_id(&workflow_on_disk(dir.path())), "planning");
        assert_ne!(std::fs::read(dir.path().join(WORKFLOW_FILE_NAME))?, before);
        Ok(())
    }
}
