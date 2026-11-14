//! Versioned run export coordinator for `anywk exec --output-dir`.
//!
//! Coordinates startup manifest (`run.json`), real-time streaming of completed records and raw
//! content blobs (`events.jsonl` + `contents/<sha256>.bin`), idempotent accounting handoffs with
//! bounded backpressure, and atomic `result.json` / `runSealed` closure after persistence flush.

pub mod manifest;
pub mod reader;
pub mod types;
pub mod usage;
pub mod writer;

use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Instant;

use anyhow::Result;
use pl_core::chat::Session;
use pl_core::thread::UsageSummary;
use pl_tool::skill::FrozenSkillCatalog;
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

pub use manifest::{
    prepare_output_dir, sha256_hex, validate_output_dir_preflight, write_result_atomic,
    write_run_manifest,
};
pub use types::{
    BuildInfoV2, ChatItemHeaderExportV2, CompletionCursorV2, ConfigInputEntryV2,
    EVENTS_SCHEMA_VERSION, EventBodyV2, EventSourceV2, EventV2, ExecutionErrorStage,
    ExecutionErrorV2, ExecutionLifecycleExportV2, ExecutionOutcome, ExportSchemaV2, ExportedBlobV2,
    ExportedContentV2, ModelUsageExportV2, RESULT_SCHEMA_VERSION, RUN_MANIFEST_SCHEMA_VERSION,
    ResultOutcome, ResultV2, RunExportOptions, RunExportReport, RunInvocationV2, RunManifestV2,
    SealedMemberCutV2, SkillSearchManifestV2, ThreadUsageExportV2, TimingReportV2, TraceSummaryV2,
    UsageCoverage, UsageExportV2, UsageKnownTotalsV2, UsageMetricKey, UsageTotalsV2,
    format_utc_rfc3339,
};
use writer::{
    BoundedExportQueue, ExportCommand, FinalizeWriterOutcome, MemberFinalCut, MemberSnapshot,
    SharedMemberState, await_finalize_with_budget, estimate_handoff_metadata_bytes,
    spawn_writer_task,
};

use crate::StudioStore;
use crate::studio::thread_projection::PreparedAccounting;

/// Host handle enabling atomic run export across `StudioRuntime` lifecycle stages.
#[derive(Clone)]
pub struct RunExporter {
    inner: Arc<RunExportCoordinator>,
}

impl std::fmt::Debug for RunExporter {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("RunExporter")
            .field("run_id", &self.inner.run_id)
            .field("output_dir", &self.inner.output_dir)
            .finish_non_exhaustive()
    }
}

/// Parameters describing one newly created Thread member enrolled into this run export.
pub struct NewMemberRegistration {
    pub root_thread_id: String,
    pub thread_id: String,
    pub agent_id: String,
    pub parent_agent_id: Option<String>,
    pub parent_thread_id: Option<String>,
    pub role: Option<String>,
    pub workspace_id: String,
    pub spawn_tool_call_id: Option<String>,
    pub initial_effect_seq: u64,
    pub session: Session,
}

/// Immutable terminal state captured from a retiring `ProjectionWorker`.
pub struct RetiredThreadCut {
    pub thread_id: String,
    pub through_effect_seq: u64,
    pub session: Session,
    pub summary: UsageSummary,
    pub status: Option<String>,
    pub aborted: bool,
    pub error: Option<String>,
}

pub(in crate::studio) struct RunExportCoordinator {
    run_id: String,
    started_at: String,
    output_dir: PathBuf,
    manifest: RunManifestV2,
    manifest_sha256: String,
    queue: Arc<BoundedExportQueue>,
    shared_members: Arc<Mutex<SharedMemberState>>,
    state: Mutex<CoordinatorState>,
    finalize: tokio::sync::Mutex<()>,
    run_cancel: CancellationToken,
    deadline_cancel: Mutex<Option<CancellationToken>>,
    writer_task: Mutex<Option<JoinHandle<()>>>,
}

impl std::fmt::Debug for RunExportCoordinator {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("RunExportCoordinator")
            .field("run_id", &self.run_id)
            .field("output_dir", &self.output_dir)
            .finish_non_exhaustive()
    }
}

#[derive(Default)]
struct CoordinatorState {
    enrolled_roots: BTreeSet<String>,
    primary_root_thread_id: Option<String>,
    admitted_effect_fingerprints: BTreeMap<String, BTreeMap<u64, String>>,
    report: Option<RunExportReport>,
}

impl RunExporter {
    /// Validates/prepares `--output-dir`, atomically writes `run.json` BEFORE runtime startup,
    /// starts the bounded writer task, and emits `runStarted` into `events.jsonl`.
    pub async fn start(options: RunExportOptions) -> Result<Self> {
        uuid::Uuid::parse_str(&options.run_id)?;
        prepare_output_dir(&options.output_dir)?;
        let (manifest, manifest_sha256) = write_run_manifest(&options)?;
        let run_cancel = CancellationToken::new();
        let queue = BoundedExportQueue::new(run_cancel.clone());
        let shared_members = Arc::new(Mutex::new(SharedMemberState::default()));
        let writer_task = spawn_writer_task(
            manifest.run_id.clone(),
            options.output_dir.clone(),
            queue.clone(),
            shared_members.clone(),
        );
        let coordinator = Arc::new(RunExportCoordinator {
            run_id: manifest.run_id.clone(),
            started_at: manifest.started_at.clone(),
            output_dir: options.output_dir,
            manifest: manifest.clone(),
            manifest_sha256: manifest_sha256.clone(),
            queue: queue.clone(),
            shared_members,
            state: Mutex::new(CoordinatorState::default()),
            finalize: tokio::sync::Mutex::new(()),
            run_cancel,
            deadline_cancel: Mutex::new(None),
            writer_task: Mutex::new(Some(writer_task)),
        });

        let _ = queue
            .admit(
                ExportCommand::RunStarted {
                    build: manifest.build,
                    manifest_sha256,
                },
                256,
            )
            .await;

        Ok(Self { inner: coordinator })
    }

    pub(in crate::studio) fn coordinator(&self) -> Arc<RunExportCoordinator> {
        self.inner.clone()
    }

    /// Returns the written startup manifest (`run.json`).
    pub fn manifest(&self) -> &RunManifestV2 {
        &self.inner.manifest
    }

    /// SHA-256 of the serialized `run.json` bytes.
    pub fn manifest_sha256(&self) -> &str {
        &self.inner.manifest_sha256
    }

    /// Output directory validated and owned by this exporter.
    pub fn output_dir(&self) -> &std::path::Path {
        &self.inner.output_dir
    }

    /// Fires if an unrecoverable exporter error requires cancelling active model execution.
    pub fn cancellation(&self) -> CancellationToken {
        self.inner.run_cancel.clone()
    }

    /// Returns the finalized report if `StudioRuntime` shutdown finalized this exporter, or builds
    /// a non-sealed fallback report if startup failed before shutdown ran.
    pub async fn finish_report(&self) -> RunExportReport {
        if let Some(report) = self.inner.cached_report() {
            return report;
        }
        self.inner
            .finalize_internal(None, false, false, None, None)
            .await
    }

    /// Atomically writes `result.json` into `<output-dir>/result.json`.
    pub fn write_result(&self, result: &ResultV2) -> Result<()> {
        write_result_atomic(&self.inner.output_dir, result)
    }
}

impl RunExportCoordinator {
    /// Marks `root_thread_id` as a run root created after exporter activation.
    pub fn enroll_root(&self, root_thread_id: &str) {
        let mut guard = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        guard.enrolled_roots.insert(root_thread_id.to_string());
        if guard.primary_root_thread_id.is_none() {
            guard.primary_root_thread_id = Some(root_thread_id.to_string());
        }
    }

    pub fn is_enrolled_root(&self, root_thread_id: &str) -> bool {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .enrolled_roots
            .contains(root_thread_id)
    }

    pub fn is_member(&self, thread_id: &str) -> bool {
        self.shared_members
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .members
            .contains_key(thread_id)
    }

    pub fn should_admit_behind_effect(&self, thread_id: &str, effect_seq: u64) -> bool {
        self.shared_members
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .members
            .get(thread_id)
            .is_some_and(|member| effect_seq > member.initial_effect_seq)
    }

    pub fn unenroll_or_abort_root(&self, root_thread_id: &str, reason: &str) {
        if self.is_member(root_thread_id) {
            self.mark_spawn_aborted(root_thread_id, reason);
            return;
        }
        let mut guard = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        guard.enrolled_roots.remove(root_thread_id);
        if guard.primary_root_thread_id.as_deref() == Some(root_thread_id) {
            guard.primary_root_thread_id = None;
        }
    }

    /// Registers a root or child thread member before its first effect or completion item.
    pub async fn register_member(&self, reg: NewMemberRegistration) {
        if !self.is_enrolled_root(&reg.root_thread_id) {
            return;
        }
        let initial_epoch = Some(reg.session.epoch().as_str().to_string());
        let initial_head_seq = reg.session.head_seq();

        {
            let mut guard = self
                .shared_members
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if let Some(existing) = guard.members.get(&reg.thread_id) {
                let matches = existing.agent_id == reg.agent_id
                    && existing.parent_agent_id == reg.parent_agent_id
                    && existing.role == reg.role
                    && existing.workspace_id == reg.workspace_id
                    && existing.initial_effect_seq == reg.initial_effect_seq
                    && existing.parent_thread_id == reg.parent_thread_id
                    && existing.spawn_tool_call_id == reg.spawn_tool_call_id
                    && existing.session.epoch() == reg.session.epoch()
                    && existing.initial_completion_seq == initial_head_seq;
                if !matches {
                    self.queue.fail_permanently(ExecutionErrorV2 {
                        stage: ExecutionErrorStage::Export,
                        code: "memberIdentityConflict".to_string(),
                        message: format!(
                            "conflicting member registration for thread {}",
                            reg.thread_id
                        ),
                        turn_failure: None,
                    });
                }
                return;
            }
            guard.members.insert(
                reg.thread_id.clone(),
                MemberSnapshot {
                    agent_id: reg.agent_id.clone(),
                    parent_agent_id: reg.parent_agent_id.clone(),
                    parent_thread_id: reg.parent_thread_id.clone(),
                    spawn_tool_call_id: reg.spawn_tool_call_id.clone(),
                    role: reg.role.clone(),
                    workspace_id: reg.workspace_id.clone(),
                    initial_effect_seq: reg.initial_effect_seq,
                    session: reg.session.clone(),
                    initial_completion_seq: initial_head_seq,
                    latest_usage: UsageSummary {
                        applied_sequence: reg.initial_effect_seq,
                        ..UsageSummary::default()
                    },
                    latest_effect_seq: reg.initial_effect_seq,
                    latest_completion_epoch: initial_epoch.clone(),
                    latest_completion_head_seq: initial_head_seq,
                    final_cut: None,
                    spawn_aborted: None,
                },
            );
        }

        let cmd = ExportCommand::AgentRegistered {
            agent_id: reg.agent_id,
            thread_id: reg.thread_id,
            parent_agent_id: reg.parent_agent_id,
            parent_thread_id: reg.parent_thread_id,
            role: reg.role,
            workspace_id: reg.workspace_id,
            spawn_tool_call_id: reg.spawn_tool_call_id,
            initial_effect_seq: reg.initial_effect_seq,
            initial_completion_epoch: initial_epoch,
            initial_completion_seq: initial_head_seq,
        };
        let metadata_bytes = match &cmd {
            ExportCommand::AgentRegistered {
                agent_id,
                thread_id,
                parent_agent_id,
                parent_thread_id,
                role,
                workspace_id,
                spawn_tool_call_id,
                initial_completion_epoch,
                ..
            } => [
                Some(agent_id),
                Some(thread_id),
                parent_agent_id.as_ref(),
                parent_thread_id.as_ref(),
                role.as_ref(),
                Some(workspace_id),
                spawn_tool_call_id.as_ref(),
                initial_completion_epoch.as_ref(),
            ]
            .into_iter()
            .flatten()
            .fold(std::mem::size_of::<ExportCommand>(), |bytes, text| {
                bytes.saturating_add(text.len())
            }),
            _ => unreachable!(),
        };
        let _ = self.queue.admit(cmd, metadata_bytes).await;
    }

    /// Emits `skillsDiscovered` provenance for an enrolled run member from a frozen catalog.
    pub async fn record_skills_discovered(
        &self,
        root_thread_id: &str,
        thread_id: &str,
        catalog: &FrozenSkillCatalog,
    ) {
        if !self.is_enrolled_root(root_thread_id) {
            return;
        }
        let report = match catalog.discovery_report() {
            Ok(report) => report,
            Err(error) => {
                self.queue.fail_permanently(ExecutionErrorV2 {
                    stage: ExecutionErrorStage::Export,
                    code: "skillsDiscoveryReportFailed".to_string(),
                    message: format!(
                        "failed to extract frozen skill discovery provenance: {error}"
                    ),
                    turn_failure: None,
                });
                return;
            }
        };
        let estimated = match serde_json::to_vec(&report) {
            Ok(bytes) => bytes
                .len()
                .saturating_mul(2)
                .saturating_add(thread_id.len())
                .saturating_add(std::mem::size_of::<ExportCommand>()),
            Err(error) => {
                self.queue.fail_permanently(ExecutionErrorV2 {
                    stage: ExecutionErrorStage::Export,
                    code: "skillsDiscoveryReportFailed".to_string(),
                    message: error.to_string(),
                    turn_failure: None,
                });
                return;
            }
        };
        let _ = self
            .queue
            .admit(
                ExportCommand::SkillsDiscovered {
                    thread_id: thread_id.to_string(),
                    report,
                },
                estimated,
            )
            .await;
    }

    /// Marks an unpublished child spawn that rolled back before execution started so finalization
    /// does not falsely require an execution observation cut.
    pub fn mark_spawn_aborted(&self, thread_id: &str, reason: &str) {
        let mut guard = self
            .shared_members
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(member) = guard.members.get_mut(thread_id)
            && member.final_cut.is_none()
        {
            member.spawn_aborted = Some(reason.to_string());
        }
    }

    /// Admits one frozen `PreparedAccounting` handoff from `LiveOwner::finish_pending` before
    /// `handover_pending`. Never propagates errors to abort Studio's own handoff.
    pub async fn admit_live_handoff(
        &self,
        thread_id: &str,
        accounting: &PreparedAccounting,
        lifecycle: &Arc<[crate::studio::storage::history::execution_lifecycle::ExecutionLifecycle]>,
        latest_usage: &UsageSummary,
        session: &Session,
        database_id: Option<&str>,
    ) {
        let effect_seq = accounting.sequence;
        {
            let guard = self
                .shared_members
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let Some(member) = guard.members.get(thread_id) else {
                return;
            };
            if effect_seq <= member.initial_effect_seq {
                return;
            }
        }
        let effect_fp = types::handoff_fingerprint(accounting, lifecycle);
        {
            let mut guard = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let effects = guard
                .admitted_effect_fingerprints
                .entry(thread_id.to_string())
                .or_default();
            if let Some(existing) = effects.get(&effect_seq) {
                if *existing == effect_fp {
                    return;
                }
                drop(guard);
                self.queue.fail_permanently(ExecutionErrorV2 {
                    stage: ExecutionErrorStage::Export,
                    code: "effectRedeliveryConflict".to_string(),
                    message: format!(
                        "conflicting accounting redelivery for thread {thread_id} at effect_seq {effect_seq}"
                    ),
                    turn_failure: None,
                });
                return;
            }
        }

        let head_seq_hint = session.head_seq();
        let epoch_str = Some(session.epoch().as_str().to_string());
        {
            let mut guard = self
                .shared_members
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if let Some(member) = guard.members.get_mut(thread_id) {
                if effect_seq > member.latest_effect_seq {
                    member.latest_effect_seq = effect_seq;
                    member.latest_usage = latest_usage.clone();
                }
                member.latest_completion_epoch = epoch_str;
                member.latest_completion_head_seq =
                    member.latest_completion_head_seq.max(head_seq_hint);
            }
        }

        let metadata_bytes = estimate_handoff_metadata_bytes(accounting)
            .saturating_add(database_id.map_or(0, str::len))
            .saturating_add(
                lifecycle
                    .iter()
                    .map(|fact| usize::try_from(fact.retained_bytes()).unwrap_or(usize::MAX))
                    .fold(0usize, usize::saturating_add),
            );
        let cmd = ExportCommand::LiveHandoff {
            thread_id: thread_id.to_string(),
            effect_seq,
            accounting: accounting.clone(),
            lifecycle: lifecycle.clone(),
            session: session.clone(),
            database_id: database_id.map(str::to_owned),
        };
        if self.queue.admit(cmd, metadata_bytes).await.is_ok() {
            // Admission may wait and be cancelled. Only accepted batches suppress a later
            // retained-handoff retry; the writer independently validates all redeliveries.
            self.state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .admitted_effect_fingerprints
                .entry(thread_id.to_string())
                .or_default()
                .insert(effect_seq, effect_fp);
        }
    }

    /// Captures the immutable final source cut and own `UsageSummary` right before
    /// `ProjectionWorker` exits after `ThreadLifecycle::Closed` + writer durability flush.
    pub fn record_thread_final_cut(&self, cut: RetiredThreadCut) {
        let mut guard = self
            .shared_members
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let Some(member) = guard.members.get_mut(&cut.thread_id) else {
            return;
        };
        if member.session.epoch() != cut.session.epoch() {
            self.queue.fail_permanently(ExecutionErrorV2 {
                stage: ExecutionErrorStage::Export,
                code: "completionEpochConflict".into(),
                message: format!(
                    "final completion source changed for thread {}",
                    cut.thread_id
                ),
                turn_failure: None,
            });
            return;
        }
        if member.final_cut.is_some() {
            return;
        }
        let completion_epoch = Some(cut.session.epoch().as_str().to_string());
        let completion_head_seq = cut.session.head_seq();
        member.final_cut = Some(MemberFinalCut {
            through_effect_seq: cut.through_effect_seq,
            completion_epoch,
            completion_head_seq,
            summary: cut.summary,
            status: cut.status,
            aborted: cut.aborted,
            error: cut.error,
        });
    }

    /// Arms a shared shutdown deadline watcher so a stalled exporter queue unblocks any parked
    /// `LiveOwner` instead of deadlocking `thread_observations.finish()`.
    pub fn arm_shutdown_deadline(&self, deadline: Option<tokio::time::Instant>) {
        let Some(deadline) = deadline else {
            return;
        };
        let cancel = CancellationToken::new();
        {
            let mut slot = self
                .deadline_cancel
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if let Some(prev) = slot.replace(cancel.clone()) {
                prev.cancel();
            }
        }
        let queue = self.queue.clone();
        tokio::spawn(async move {
            tokio::select! {
                () = cancel.cancelled() => {}
                () = tokio::time::sleep_until(deadline) => {
                    queue.close_admission(ExecutionErrorV2 {
                        stage: ExecutionErrorStage::Export,
                        code: "exportShutdownDeadline".to_string(),
                        message: "shared shutdown deadline expired while exporter queue had pending backpressure".to_string(),
                        turn_failure: None,
                    });
                }
            }
        });
    }

    /// Runs inside `shutdown.rs::write_chain` after `flush_persistence` and before `store.close()`.
    pub async fn finalize_during_shutdown(
        &self,
        store: StudioStore,
        deadline: Option<tokio::time::Instant>,
        agent_ok: bool,
        flush_ok: bool,
        pending_after: Option<usize>,
    ) -> RunExportReport {
        self.finalize_internal(Some(store), agent_ok, flush_ok, pending_after, deadline)
            .await
    }

    /// Closes admission if producer drain itself failed/timed out so no dangling awaits remain.
    pub fn close_admission_on_producer_timeout(&self) {
        self.queue.close_admission(ExecutionErrorV2 {
            stage: ExecutionErrorStage::Export,
            code: "producerDrainIncomplete".to_string(),
            message: "producer drain did not acknowledge before export finalization".to_string(),
            turn_failure: None,
        });
    }

    fn cached_report(&self) -> Option<RunExportReport> {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .report
            .clone()
    }

    async fn finalize_internal(
        &self,
        store: Option<StudioStore>,
        agent_ok: bool,
        flush_ok: bool,
        pending_after: Option<usize>,
        deadline: Option<tokio::time::Instant>,
    ) -> RunExportReport {
        let _finalize = self.finalize.lock().await;
        if let Some(report) = self.cached_report() {
            return report;
        }
        let finalize_start = Instant::now();
        let outcome = match self
            .queue
            .enqueue_finalize(store, agent_ok, flush_ok, pending_after)
            .await
        {
            Ok(rx) => await_finalize_with_budget(&self.queue, rx, deadline).await,
            Err(err) => {
                let err = *err;
                FinalizeWriterOutcome {
                    trace_complete: false,
                    usage_complete: false,
                    cost_complete: false,
                    trace: TraceSummaryV2 {
                        events_path: "events.jsonl".to_string(),
                        events_sha256: None,
                        event_count: 0,
                        last_event_seq: None,
                        sealed: false,
                        reason: Some(err.message.clone()),
                    },
                    usage: None,
                    failure: Some(err),
                }
            }
        };

        let join_handle = self
            .writer_task
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take();
        if let Some(handle) = join_handle {
            if let Some(limit) = deadline {
                let mut handle = handle;
                if tokio::time::timeout_at(limit, &mut handle).await.is_err() {
                    handle.abort();
                    let _ = handle.await;
                }
            } else {
                let _ = handle.await;
            }
        }
        // These are read-only sources, never execution owners. Release them before store.close(),
        // including the timeout path after the writer task has actually stopped.
        self.shared_members
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .members
            .clear();
        if let Some(cancel) = self
            .deadline_cancel
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take()
        {
            cancel.cancel();
        }

        let export_finalize_ms = Some(finalize_start.elapsed().as_millis() as u64);
        let mut guard = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(existing) = &guard.report {
            return existing.clone();
        }
        let report = RunExportReport {
            run_id: self.run_id.clone(),
            started_at: self.started_at.clone(),
            manifest_sha256: self.manifest_sha256.clone(),
            root_thread_id: guard.primary_root_thread_id.clone(),
            trace_complete: outcome.trace_complete,
            usage_complete: outcome.usage_complete,
            cost_complete: outcome.cost_complete,
            trace: outcome.trace,
            usage: outcome.usage,
            export_finalize_ms,
            failure: outcome.failure,
        };
        guard.report = Some(report.clone());
        report
    }

    #[cfg(test)]
    pub fn queue(&self) -> Arc<BoundedExportQueue> {
        self.queue.clone()
    }
}

#[cfg(test)]
mod tests;
