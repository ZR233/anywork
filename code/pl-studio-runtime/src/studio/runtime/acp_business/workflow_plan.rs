//! Per-agent ACP Workflow and Plan ownership, atomic persistence, and state push.
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};

use anyhow::{Context, Result, ensure};
use pl_tool_plan::{
    Plan, PlanActor, PlanHistoryArgs, PlanHistoryResponse, PlanHost, PlanNextResponse, PlanRecord,
    PlanSnapshot, PlanTransitionArgs, PlanTransitionCommand, PlanTransitionOutcome,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use tokio::sync::{Mutex as AsyncMutex, oneshot, watch};
use tokio_util::sync::CancellationToken;

use crate::mode::{SavedThreadMode, ThreadModeId, ThreadModeManager};
use crate::plan_tool::AgentSessionPlanRuntimeSnapshot;
use crate::protocol::{AcpHostInteractionAnswer, AcpPendingInteraction, AcpWorkflowStateSnapshot};
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
    interaction: Option<PendingInteraction>,
}

struct PendingInteraction {
    view: AcpPendingInteraction,
    caller: CancellationToken,
    prompt: CancellationToken,
    answer: Option<oneshot::Sender<InteractionDecision>>,
    published: bool,
}

struct InteractionDecision {
    answer: AcpHostInteractionAnswer,
    recorded: oneshot::Sender<Result<()>>,
}

impl PendingInteraction {
    fn id(&self) -> &str {
        match &self.view {
            AcpPendingInteraction::Question { id, .. }
            | AcpPendingInteraction::PlanConfirmation { id } => id,
        }
    }

    fn is_cancelled(&self) -> bool {
        self.caller.is_cancelled() || self.prompt.is_cancelled()
    }
}

struct InteractionWait<'a> {
    owner: &'a AcpWorkflowPlanOwner,
    id: String,
    prompt: CancellationToken,
    answer: oneshot::Receiver<InteractionDecision>,
}

impl Drop for InteractionWait<'_> {
    fn drop(&mut self) {
        let mut guard = self
            .owner
            .inner
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if guard
            .interaction
            .as_ref()
            .is_some_and(|pending| pending.id() == self.id)
        {
            guard.interaction = None;
            self.owner.updates.send_modify(|snapshot| {
                if let Some(snapshot) = snapshot {
                    snapshot.pending_interaction = None;
                }
            });
        }
    }
}

impl InteractionWait<'_> {
    fn publish(&self) -> Result<()> {
        let mut guard = self
            .owner
            .inner
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let pending = guard
            .interaction
            .as_mut()
            .context("ACP interaction retired")?;
        ensure!(!pending.is_cancelled(), "ACP interaction cancelled");
        pending.published = true;
        self.owner.updates.send_modify(|snapshot| {
            if let Some(snapshot) = snapshot {
                snapshot.pending_interaction = Some(pending.view.clone());
            }
        });
        Ok(())
    }

    async fn receive(&mut self, caller: &CancellationToken) -> Result<InteractionDecision> {
        tokio::select! {
            biased;
            () = caller.cancelled() => anyhow::bail!("ACP interaction cancelled"),
            () = self.prompt.cancelled() => anyhow::bail!("ACP prompt ended while waiting for input"),
            answer = &mut self.answer => answer.context("ACP interaction answer dropped"),
        }
    }
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
    session: OnceLock<pl_acp::session::Session>,
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
            inner: Arc::new(Mutex::new(AcpWorkflowStateInner {
                workflow,
                plan,
                interaction: None,
            })),
            persist_gate: Arc::new(AsyncMutex::new(())),
            updates,
            session: OnceLock::new(),
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

    pub(super) fn bind_session(&self, session: pl_acp::session::Session) -> Result<()> {
        self.session
            .set(session)
            .map_err(|_| anyhow::anyhow!("ACP workflow session already bound"))
    }

    async fn reserve_interaction(
        &self,
        view: AcpPendingInteraction,
        caller: &CancellationToken,
    ) -> Result<InteractionWait<'_>> {
        let prompt = self
            .session
            .get()
            .context("ACP session is unavailable")?
            .active_prompt_lifetime()?;
        let _gate = self.persist_gate.lock().await;
        let mut guard = self
            .inner
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        ensure!(
            !caller.is_cancelled() && !prompt.is_cancelled(),
            "ACP interaction cancelled"
        );
        ensure!(
            guard.interaction.is_none(),
            "Another ACP interaction is already active"
        );
        if let Some(workflow) = &guard.workflow
            && workflow.mode_id == ThreadModeId::auto()
        {
            ensure!(
                workflow
                    .state
                    .current_run
                    .as_ref()
                    .is_some_and(|run| run.current_state_id == "planning"),
                "Advance the ACP workflow to planning before requesting user input or Plan confirmation"
            );
        }
        let (send, answer) = oneshot::channel();
        let pending = PendingInteraction {
            view,
            caller: caller.clone(),
            prompt: prompt.clone(),
            answer: Some(send),
            published: false,
        };
        let id = pending.id().to_owned();
        guard.interaction = Some(pending);
        Ok(InteractionWait {
            owner: self,
            id,
            prompt,
            answer,
        })
    }

    pub(super) async fn answer_interaction(
        &self,
        id: &str,
        answer: AcpHostInteractionAnswer,
    ) -> Result<()> {
        let (recorded, result) = oneshot::channel();
        self.submit_decision(id, InteractionDecision { answer, recorded })?;
        result
            .await
            .context("ACP interaction ended before recording the decision")?
    }

    fn submit_decision(&self, id: &str, decision: InteractionDecision) -> Result<()> {
        let mut guard = self
            .inner
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let pending = guard
            .interaction
            .as_mut()
            .filter(|pending| pending.id() == id && pending.published && !pending.is_cancelled())
            .context("ACP interaction is no longer active")?;
        match (&pending.view, &decision.answer) {
            (_, AcpHostInteractionAnswer::Cancel)
            | (
                AcpPendingInteraction::PlanConfirmation { .. },
                AcpHostInteractionAnswer::ApprovePlan,
            ) => {}
            (
                AcpPendingInteraction::PlanConfirmation { .. },
                AcpHostInteractionAnswer::RevisePlan { feedback },
            ) => {
                ensure!(
                    !feedback.trim().is_empty(),
                    "Plan revision requires feedback"
                );
            }
            (
                AcpPendingInteraction::Question { questions, .. },
                AcpHostInteractionAnswer::Question { answers },
            ) => {
                ensure!(!answers.is_empty(), "Answers are empty");
                for (id, answer) in answers {
                    ensure!(
                        questions.iter().any(|question| question.id == *id),
                        "Unknown question `{id}`"
                    );
                    ensure!(!answer.answers.is_empty(), "Question `{id}` has no answer");
                }
            }
            _ => anyhow::bail!("Answer does not match the ACP interaction"),
        }
        pending
            .answer
            .take()
            .context("ACP interaction was already answered")?
            .send(decision)
            .map_err(|_| anyhow::anyhow!("ACP interaction is no longer active"))
    }

    pub(crate) async fn ask_user(
        &self,
        id: String,
        questions: Vec<crate::UserQuestion>,
        caller: &CancellationToken,
    ) -> Result<crate::protocol::UserInputResolution> {
        let mut wait = self
            .reserve_interaction(AcpPendingInteraction::Question { id, questions }, caller)
            .await?;
        wait.publish()?;
        let decision = wait.receive(caller).await?;
        drop(wait);
        let _ = decision.recorded.send(Ok(()));
        match decision.answer {
            AcpHostInteractionAnswer::Question { answers } => {
                Ok(crate::protocol::UserInputResolution { answers })
            }
            _ => anyhow::bail!("The user cancelled the question"),
        }
    }

    pub(crate) async fn transition_from_tool(
        &self,
        args: PlanTransitionArgs,
        context: AcpPlanToolContext,
        caller: &CancellationToken,
    ) -> Result<PlanTransitionOutcome> {
        ensure!(
            !matches!(
                args.target_state,
                pl_tool_plan::PlanState::Approved | pl_tool_plan::PlanState::RevisionRequested
            ),
            "Plan approval and revision are decided by the user in the confirmation card"
        );
        if args.target_state != pl_tool_plan::PlanState::AwaitingConfirmation {
            return Ok(self.transition(args, context).await?);
        }
        ensure!(!args.force, "Submit Plan confirmation without force");
        let mut wait = self
            .reserve_interaction(
                AcpPendingInteraction::PlanConfirmation {
                    id: context.call_id.clone(),
                },
                caller,
            )
            .await?;
        let submitted = self.transition(args, context.clone()).await?;
        if !submitted.accepted || !submitted.awaiting_confirmation || submitted.replayed {
            return Ok(submitted);
        }
        wait.publish()?;
        let decision = wait.receive(caller).await?;
        let (target_state, feedback, cancelled) = match decision.answer {
            AcpHostInteractionAnswer::ApprovePlan => {
                (pl_tool_plan::PlanState::Approved, None, false)
            }
            AcpHostInteractionAnswer::RevisePlan { feedback } => (
                pl_tool_plan::PlanState::RevisionRequested,
                Some(feedback),
                false,
            ),
            AcpHostInteractionAnswer::Cancel => (pl_tool_plan::PlanState::Drafting, None, true),
            AcpHostInteractionAnswer::Question { .. } => {
                unreachable!("interaction answer was validated")
            }
        };
        let decided = self
            .transition_as(
                PlanTransitionArgs {
                    target_state,
                    content: None,
                    feedback,
                    reason: cancelled.then(|| "The user cancelled Plan confirmation".to_owned()),
                    force: false,
                    expected_revision: Some(submitted.snapshot.revision),
                    idempotency_key: Some(format!("{}/user-decision", context.call_id)),
                },
                AcpPlanToolContext {
                    now_ms: crate::studio::unix_seconds() * 1000,
                    ..context
                },
                PlanActor::User,
            )
            .await;
        drop(wait);
        let decided = match decided {
            Ok(decided) if decided.accepted => decided,
            result => {
                let message = result.err().map_or_else(
                    || "Could not record the user's Plan decision".to_owned(),
                    |error| error.to_string(),
                );
                let _ = decision
                    .recorded
                    .send(Err(anyhow::anyhow!(message.clone())));
                anyhow::bail!(message);
            }
        };
        let _ = decision.recorded.send(Ok(()));
        if cancelled {
            anyhow::bail!("The user cancelled Plan confirmation");
        }
        Ok(decided)
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
        let pending_interaction = guard
            .interaction
            .as_ref()
            .filter(|pending| pending.published)
            .map(|pending| pending.view.clone());
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
                pending_interaction,
            }
        } else {
            AcpWorkflowStateSnapshot {
                mode_id: None,
                mode_display_name: None,
                run: None,
                graph: None,
                plan,
                pending_interaction,
            }
        }
    }

    pub(crate) fn compiled_mode_instructions(&self) -> Option<String> {
        let guard = self
            .inner
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let wf = guard.workflow.as_ref()?;
        let mode_prompt = acp_mode_prompt(wf);
        let mut out = format!(
            "\n# Thread Mode: {} (`{}`)\n",
            wf.saved_mode.definition.display_name, wf.mode_id
        );
        if !mode_prompt.is_empty() {
            out.push_str(mode_prompt);
            out.push('\n');
        }
        out.push_str(
            "\n[ACP Root Workflow]\n\
             Use the latest Studio Host State for the active mode, run, revision, and stage. \
             Continue from the actual current stage across turns and reconnects. If the state \
             is missing or stale, read `anywork_workflow_current`. The current state and each \
             accepted transition already contain allowed edges. Use `anywork_workflow_next`, \
             `anywork_workflow_graph`, or `anywork_workflow_history` for additional detail. \
             Interpret references to host tools in Mode text according to the current top-level \
             `anywork_*` MCP catalog. Follow this ACP call sequence if a workflow tool's stage \
             or guard text uses Native calling or confirmation conventions.\n\
             Advance with `anywork_workflow_transition` along an allowed edge with `force=false`. \
             Use the actual `runId`, `revision`, and `currentStateId` as `expectedRunId`, \
             `expectedRevision`, and `expectedStateId`, and submit the `targetStateId` and \
             `completion` (reason, summary, evidence). Check `accepted` and the returned `snapshot` \
             before acting on the new stage. On a CAS conflict or rejection, refresh the current \
             state and allowed edges before choosing a new action. Use `anywork_workflow_restart` \
             only for an explicitly required new run.\n\
             In the built-in `mode.auto` workflow, reach `planning` before requesting structured \
             user input or submitting a Plan for confirmation. If outside `planning`, transition first \
             and wait for an accepted snapshot showing `planning` before making either call. If \
             the active graph or catalog prevents that, report the blocker and pause dependent work. \
             Clarify material conflicts with `anywork_request_user_input`, then submit the Plan \
             with `anywork_plan_transition` using `targetState=awaitingConfirmation` and `force=false`. \
             Wait for the host to confirm approval before advancing from planning to implementation. \
             In `reviewing`, first call `anywork_plan_current` and read `document.content`. Use the \
             Plan's scope, decisions, risks, and checks to guide the review and any reviewers.\n",
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
                    interaction: None,
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
            ensure!(
                guard.interaction.is_none(),
                "Wait for the active ACP interaction before advancing the workflow"
            );
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
            ensure!(
                guard.interaction.is_none(),
                "Wait for the active ACP interaction before restarting the workflow"
            );
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
                        let path = resources_dir.join(install.file_name());
                        write_bytes(path, bytes).await?;
                        {
                            let mut guard = inner
                                .lock()
                                .unwrap_or_else(std::sync::PoisonError::into_inner);
                            install.commit(&mut guard);
                            if let Some(mut snapshot) = snapshot {
                                snapshot.pending_interaction = guard
                                    .interaction
                                    .as_ref()
                                    .filter(|pending| pending.published)
                                    .map(|pending| pending.view.clone());
                                updates.send_replace(Some(snapshot));
                            }
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
        self.transition_as(args, context, PlanActor::Agent).await
    }
}

impl AcpWorkflowPlanOwner {
    async fn transition_as(
        &self,
        args: PlanTransitionArgs,
        context: AcpPlanToolContext,
        actor: PlanActor,
    ) -> Result<PlanTransitionOutcome, AcpWorkflowPlanError> {
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
            if let Some(pending) = &guard.interaction {
                ensure!(
                    pending.id() == context.call_id
                        && matches!(pending.view, AcpPendingInteraction::PlanConfirmation { .. }),
                    "Wait for the active ACP interaction before changing the Plan"
                );
            }
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
                actor,
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
                interaction: None,
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
            interaction: None,
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

fn acp_mode_prompt(workflow: &PersistedAcpWorkflow) -> &str {
    if workflow.mode_id.as_str() == ThreadModeId::AUTO {
        "Use `simple` for a small, clear task with no design conflict or request for a plan. \
         Choose `planning` for complex or risky work, an explicit request for a plan, or a conflict \
         with existing design or contracts. If one of these conditions arises later, pause the \
         affected work, preserve valid evidence, and return to `planning` along an allowed edge. \
         Continue through the stages of the actual run and advance to `completed` after delivery \
         and verification."
    } else {
        &workflow.saved_mode.definition.prompt
    }
}

fn acp_current_stage(state: &crate::workflow_tool::WorkflowState, is_builtin_auto: bool) -> Value {
    // Only built-in stages have Studio-owned Native interaction instructions to replace.
    // Leave custom mode prose and the frozen workflow graph intact.
    let (instructions, criteria): (&str, &[&str]) = match (is_builtin_auto, state.id.as_str()) {
        (true, "triage") => (
            "Check the user goal, constraints, scope, and any relevant design. Even for an \
             ordinary question, commit the route with `anywork_workflow_transition` before \
             answering. Choose `simple` for a small clear task. Choose `planning` for \
             complex work, a plan request, or a design conflict, and wait for the accepted \
             transition before opening a structured question or Plan confirmation.",
            &[
                "The scope and any design conflict are understood, and the selected edge fits the task.",
            ],
        ),
        (true, "simple") => (
            "Complete the small task and verify the result. Call `anywork_workflow_transition` \
             to record `completed` before giving the final answer, including for a one-line \
             reply. If the task turns out to require planning, take the edge to `planning` first.",
            &["The requested result is ready and the necessary checks have passed."],
        ),
        (true, "planning") => (
            "Check the relevant code, design, and contracts. If the user needs to resolve a \
             conflict, explain the current design, options, trade-offs, and recommendation using \
             `anywork_request_user_input`. Use the returned decision to finish the Plan. Submit \
             a complete plain-language Markdown Plan via `anywork_plan_transition` with \
             `targetState=awaitingConfirmation` and `force=false`. Include the goal, current \
             constraints, proposed steps and trade-offs, scope, and how to verify the outcome. \
             Leave `planning` for implementation after the host confirms approval.",
            &[
                "Scope, trade-offs, and acceptance checks are clear. The user has resolved any material conflict.",
                "The host returned an approved Plan for the proposed work.",
            ],
        ),
        (true, "reviewing") => (
            "First read `document.content` from `anywork_plan_current`. Review the actual changes \
             and verification evidence against the Plan's goals, scope, decisions, and acceptance \
             checks. If a reviewer is available, provide the relevant Plan and concrete pass and \
             fail criteria. Return implementation defects to `working`, document discrepancies to \
             `editing_documents`, and design conflicts to `planning`.",
            &[
                "The current Plan has been read and checked against the changes and verification results.",
                "Applicable acceptance checks, evaluations, and resource cleanup are complete.",
            ],
        ),
        _ => return serde_json::json!(state),
    };
    let mut stage = state.clone();
    stage.instructions = instructions.to_owned();
    stage.completion_criteria = criteria
        .iter()
        .map(|criterion| (*criterion).to_owned())
        .collect();
    serde_json::json!(stage)
}

fn studio_host_state_block(
    workflow: &PersistedAcpWorkflow,
    plan: &PlanSnapshot,
    include_mode_prompt: bool,
) -> String {
    let is_builtin_auto = workflow.mode_id.as_str() == ThreadModeId::AUTO;
    let mode_prompt = acp_mode_prompt(workflow);
    let mode_prompt_section = if include_mode_prompt && !mode_prompt.is_empty() {
        format!(
            "Mode `{}` (`{}`) instructions:\n{mode_prompt}\n\n",
            workflow.saved_mode.definition.display_name, workflow.mode_id,
        )
    } else {
        String::new()
    };
    let machine_json = workflow.state.current_run.as_ref().map(|run| {
        let graph = workflow.saved_mode.definition.workflow.as_ref();
        let use_acp_planning_guards = is_builtin_auto && run.current_state_id == "planning";
        let current_state = graph
            .and_then(|g| g.states.iter().find(|s| s.id == run.current_state_id))
            .map(|state| acp_current_stage(state, is_builtin_auto));
        let outgoing: Vec<Value> = graph
            .map(|g| {
                g.transitions
                    .iter()
                    .filter(|t| t.source_state_id == run.current_state_id)
                    .map(|t| {
                        let guard = match (use_acp_planning_guards, t.target_state_id.as_str()) {
                            (true, "editing_documents") => {
                                "The host confirmed Plan approval and design or contract documents need updating first."
                            }
                            (true, "working") => {
                                "The host confirmed Plan approval and implementation can start without prior document changes."
                            }
                            _ => t.guard.as_str(),
                        };
                        serde_json::json!({
                            "targetStateId": t.target_state_id,
                            "guard": guard,
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
            "currentStateId": run.current_state_id,
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
        "[Studio Host State]\n{mode_prompt_section}{}\nPlan: {}\n\
         Use this mode and state in place of earlier snapshots. Update your view after each \
         accepted tool transition. Commit phase changes with tools before replying, even when \
         the user wants a short final answer. In `mode.auto`, confirm `planning` before \
         opening a structured question or Plan confirmation. In `reviewing`, first read the \
         latest Plan body with `anywork_plan_current`.\n",
        machine_json.as_ref().map_or_else(
            || format!("Workflow: none for mode `{}`", workflow.mode_id),
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
        // Hold the same gate that serializes ordinary writes. Polling the call once
        // schedules the commit and leaves the caller waiting for its receipt.
        let gate = owner.persist_gate.lock().await;
        {
            let mut caller = std::pin::pin!(owner.workflow_transition(
                force_to_planning(dir.path()),
                operation("cancel-workflow"),
                "hash-cancel".into(),
            ));
            assert!(futures::poll!(caller.as_mut()).is_pending());
        }
        assert_eq!(state_id(&workflow_on_disk(dir.path())), before_state);
        assert_eq!(std::fs::read(dir.path().join(WORKFLOW_FILE_NAME))?, before);
        assert_eq!(
            owner.snapshot().run.expect("run").current_state_id,
            before_state
        );
        assert!(!updates.has_changed().expect("workflow watch"));

        drop(gate);
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
