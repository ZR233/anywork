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

use crate::mode::{SavedThreadMode, ThreadModeId, ThreadModeManager, reconcile_workflow_for_turn};
use crate::plan_tool::AgentSessionPlanRuntimeSnapshot;
use crate::protocol::AcpWorkflowStateSnapshot;
use crate::studio::thread_projection::workflow_graph_from_saved_mode;
use crate::workflow_tool::machine::{
    RestartInput, TransitionInput, WorkflowMachine, WorkflowOperation,
};
use crate::workflow_tool::{WorkflowRuntimeSnapshot, WorkflowSessionState};

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
    inner: Mutex<AcpWorkflowStateInner>,
    persist_gate: AsyncMutex<()>,
    updates: watch::Sender<Option<AcpWorkflowStateSnapshot>>,
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
                if matches!(persisted.mode_id.as_str(), "mode.simple" | "mode.task")
                    && let Some(auto_mode) = thread_modes.snapshot().mode(&ThreadModeId::auto())
                {
                    persisted.mode_id = ThreadModeId::auto();
                    persisted.saved_mode = SavedThreadMode::capture(&auto_mode, None);
                    initial_workflow_created = true;
                }
                Some(persisted)
            } else {
                let resolved_mode_id = requested_mode
                    .map(|id| {
                        if matches!(id.as_str(), "mode.simple" | "mode.task") {
                            ThreadModeId::auto()
                        } else {
                            id
                        }
                    })
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
            inner: Mutex::new(AcpWorkflowStateInner { workflow, plan }),
            persist_gate: AsyncMutex::new(()),
            updates,
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
        self.snapshot_locked(&guard, &modes)
    }

    fn snapshot_locked(
        &self,
        guard: &AcpWorkflowStateInner,
        modes: &crate::mode::ThreadModeRegistrySnapshot,
    ) -> AcpWorkflowStateSnapshot {
        let plan_snapshot = Plan::from_record(guard.plan.clone())
            .unwrap_or_default()
            .snapshot();
        let plan = Some(AgentSessionPlanRuntimeSnapshot::from(&plan_snapshot));
        if let Some(wf) = &guard.workflow {
            let mode_deleted = modes.mode(&wf.mode_id).is_none();
            let mut run =
                WorkflowRuntimeSnapshot::from(&wf.state)
                    .current_run
                    .map(|mut snap| {
                        snap.mode_display_name = wf.saved_mode.definition.display_name.clone();
                        snap.mode_deleted = mode_deleted;
                        if let Some(current) =
                            wf.saved_mode.definition.workflow.as_ref().and_then(|g| {
                                g.states.iter().find(|s| s.id == snap.current_state_id)
                            })
                        {
                            snap.current_state_title = current.title.clone();
                        }
                        snap
                    });
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
             Only pass `force=true` when you intentionally need to override state-machine rules.\n",
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
        let (changed, prompt_header, snapshot, turn_block) = {
            let modes = self.thread_modes.snapshot();
            let mut guard = self
                .inner
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let plan_snapshot = Plan::from_record(guard.plan.clone())
                .unwrap_or_default()
                .snapshot();
            let Some(wf) = guard.workflow.as_mut() else {
                return Ok(None);
            };
            let registered = wf
                .saved_mode
                .registered()
                .map_err(|err| anyhow::anyhow!("invalid frozen ACP mode: {err}"))?;
            let before = wf.state.clone();
            let next_state = reconcile_workflow_for_turn(
                Some(wf.state.clone()),
                &registered,
                &self.thread_id,
                now,
            )
            .map_err(|err| anyhow::anyhow!("reconcile ACP workflow failed: {err}"))?
            .unwrap_or_default();
            let changed = next_state != before;
            wf.state = next_state;

            let prompt_hash =
                pl_core::context::content_hash(wf.saved_mode.definition.prompt.as_bytes());
            let mode_prompt_changed = wf.injected_prompt_hash.as_ref() != Some(&prompt_hash);
            wf.injected_prompt_hash = Some(prompt_hash);

            let mode_prompt_section =
                if mode_prompt_changed && !wf.saved_mode.definition.prompt.trim().is_empty() {
                    Some(format!(
                        "Mode `{}` (`{}`) instructions:\n{}",
                        wf.saved_mode.definition.display_name,
                        wf.mode_id,
                        wf.saved_mode.definition.prompt.trim()
                    ))
                } else {
                    None
                };

            let machine_json = wf.state.current_run.as_ref().map(|run| {
                let graph = wf.saved_mode.definition.workflow.as_ref();
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
                    "modeId": wf.mode_id,
                    "modeDisplayName": wf.saved_mode.definition.display_name,
                    "runId": run.run_id,
                    "revision": wf.state.revision,
                    "lifecycle": run.lifecycle,
                    "currentState": current_state,
                    "allowedTransitions": outgoing,
                })
            });
            let plan_json = serde_json::json!({
                "state": plan_snapshot.state,
                "revision": plan_snapshot.revision,
                "hasDocument": plan_snapshot.document.is_some(),
            });
            let block = format!(
                "[Studio Host State]\n{}{}\nPlan: {}\nUse `anywork_workflow_*` (when workflow is present) and `anywork_plan_*` MCP tools to inspect or advance states.\n",
                mode_prompt_section
                    .as_ref()
                    .map_or(String::new(), |s| format!("{s}\n\n")),
                machine_json.as_ref().map_or_else(
                    || "Workflow: none".to_string(),
                    |v| format!("Workflow: {v}")
                ),
                plan_json,
            );
            let snap = self.snapshot_locked(&guard, &modes);
            (changed || mode_prompt_changed, changed, snap, block)
        };
        if changed {
            self.persist_workflow().await?;
        }
        if prompt_header {
            self.updates.send_replace(Some(snapshot));
        }
        Ok(Some(turn_block))
    }

    pub(crate) async fn set_mode(
        &self,
        mode_id: ThreadModeId,
        registered: &crate::mode::RegisteredThreadMode,
    ) -> Result<AcpWorkflowStateSnapshot> {
        ensure!(self.is_root, "only root ACP session owns workflow Mode");
        let now = crate::studio::unix_seconds();
        let snapshot = {
            let modes = self.thread_modes.snapshot();
            let mut guard = self
                .inner
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let previous_state = guard.workflow.as_ref().map(|wf| wf.state.clone());
            let next_state =
                crate::mode::state::archive_workflow_for_mode_change(previous_state, &mode_id, now)
                    .map_err(|err| anyhow::anyhow!("archive ACP workflow on mode change: {err}"))?
                    .unwrap_or_default();
            guard.workflow = Some(PersistedAcpWorkflow {
                mode_id: registered.descriptor().id.clone(),
                saved_mode: SavedThreadMode::capture(registered, None),
                state: next_state,
                injected_prompt_hash: None,
            });
            self.snapshot_locked(&guard, &modes)
        };
        self.persist_workflow().await?;
        self.updates.send_replace(Some(snapshot.clone()));
        Ok(snapshot)
    }

    pub(crate) async fn workflow_current_json(&self) -> Result<Value, AcpWorkflowPlanError> {
        let machine = self.workflow_machine()?;
        Ok(machine.current_snapshot(&machine.state()))
    }

    pub(crate) async fn workflow_next_json(&self) -> Result<Value, AcpWorkflowPlanError> {
        let machine = self.workflow_machine()?;
        Ok(machine.next_snapshot(&machine.state()))
    }

    pub(crate) async fn workflow_graph_json(&self) -> Result<Value, AcpWorkflowPlanError> {
        let machine = self.workflow_machine()?;
        Ok(machine.graph_snapshot(&machine.state()))
    }

    pub(crate) async fn workflow_history_json(&self) -> Result<Value, AcpWorkflowPlanError> {
        let machine = self.workflow_machine()?;
        Ok(machine.history_snapshot(&machine.state()))
    }

    pub(crate) async fn workflow_transition(
        &self,
        input: TransitionInput,
        identity: WorkflowOperation,
        argument_hash: String,
    ) -> Result<Value, AcpWorkflowPlanError> {
        let (response, changed, snapshot) = {
            let modes = self.thread_modes.snapshot();
            let mut guard = self
                .inner
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let wf = guard
                .workflow
                .as_mut()
                .ok_or_else(|| AcpWorkflowPlanError("ACP agent has no active workflow".into()))?;
            let registered = wf
                .saved_mode
                .registered()
                .map_err(|err| AcpWorkflowPlanError(err.to_string()))?;
            if registered.workflow().is_none() {
                return Err(AcpWorkflowPlanError(
                    "Selected Mode has no workflow graph".into(),
                ));
            }
            let before = wf.state.clone();
            let mut machine = WorkflowMachine::new(registered, wf.state.clone());
            let response = machine
                .apply_transition(input, &identity, argument_hash)
                .map_err(|err| AcpWorkflowPlanError(err.to_string()))?;
            let next = machine.state();
            let changed = next != before;
            wf.state = next;
            let value = serde_json::to_value(&response)
                .map_err(|err| AcpWorkflowPlanError(err.to_string()))?;
            let snap = changed.then(|| self.snapshot_locked(&guard, &modes));
            (value, changed, snap)
        };
        if changed {
            self.persist_workflow()
                .await
                .map_err(|err| AcpWorkflowPlanError(err.to_string()))?;
            if let Some(snap) = snapshot {
                self.updates.send_replace(Some(snap));
            }
        }
        Ok(response)
    }

    pub(crate) async fn workflow_restart(
        &self,
        input: RestartInput,
        identity: WorkflowOperation,
        argument_hash: String,
    ) -> Result<Value, AcpWorkflowPlanError> {
        let (response, changed, snapshot) = {
            let modes = self.thread_modes.snapshot();
            let mut guard = self
                .inner
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let wf = guard
                .workflow
                .as_mut()
                .ok_or_else(|| AcpWorkflowPlanError("ACP agent has no active workflow".into()))?;
            let registered = wf
                .saved_mode
                .registered()
                .map_err(|err| AcpWorkflowPlanError(err.to_string()))?;
            if registered.workflow().is_none() {
                return Err(AcpWorkflowPlanError(
                    "Selected Mode has no workflow graph".into(),
                ));
            }
            let before = wf.state.clone();
            let mut machine = WorkflowMachine::new(registered, wf.state.clone());
            let response = machine
                .apply_restart(input, &identity, argument_hash)
                .map_err(|err| AcpWorkflowPlanError(err.to_string()))?;
            let next = machine.state();
            let changed = next != before;
            wf.state = next;
            let value = serde_json::to_value(&response)
                .map_err(|err| AcpWorkflowPlanError(err.to_string()))?;
            let snap = changed.then(|| self.snapshot_locked(&guard, &modes));
            (value, changed, snap)
        };
        if changed {
            self.persist_workflow()
                .await
                .map_err(|err| AcpWorkflowPlanError(err.to_string()))?;
            if let Some(snap) = snapshot {
                self.updates.send_replace(Some(snap));
            }
        }
        Ok(response)
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
        if registered.workflow().is_none() {
            return Err(AcpWorkflowPlanError(
                "Selected Mode has no workflow graph".into(),
            ));
        }
        Ok(WorkflowMachine::new(registered, wf.state.clone()))
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
        atomic_write_bytes(&self.resources_dir.join(WORKFLOW_FILE_NAME), &payload).await
    }

    async fn persist_plan(&self) -> Result<()> {
        let _gate = self.persist_gate.lock().await;
        let payload = {
            let guard = self
                .inner
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            serde_json::to_vec_pretty(&guard.plan)?
        };
        atomic_write_bytes(&self.resources_dir.join(PLAN_FILE_NAME), &payload).await
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
        let (outcome, changed, snapshot) = {
            let modes = self.thread_modes.snapshot();
            let mut guard = self
                .inner
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
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
                timestamp_ms: context.now_ms,
            };
            let outcome = plan.transition(command);
            let changed = outcome.accepted && !outcome.replayed;
            if changed {
                guard.plan = plan.into_record();
            }
            let snap = changed.then(|| self.snapshot_locked(&guard, &modes));
            (outcome, changed, snap)
        };
        if changed {
            self.persist_plan()
                .await
                .map_err(|err| AcpWorkflowPlanError(err.to_string()))?;
            if let Some(snap) = snapshot {
                self.updates.send_replace(Some(snap));
            }
        }
        Ok(outcome)
    }
}

async fn atomic_write_bytes(path: &Path, bytes: &[u8]) -> Result<()> {
    if let Some(parent) = path.parent() {
        tokio::fs::create_dir_all(parent).await?;
    }
    let tmp = path.with_extension(format!("tmp-{}", uuid::Uuid::new_v4().simple()));
    tokio::fs::write(&tmp, bytes).await?;
    tokio::fs::rename(&tmp, path).await?;
    Ok(())
}
