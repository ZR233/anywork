//! Single background writer task owning `events.jsonl`, streaming `contents/<sha256>.bin`,
//! bounded queue admission (`256 batches / 16 MiB`), backpressure, and failure isolation.

use std::collections::{BTreeMap, VecDeque};
use std::fs::{self, File, OpenOptions};
use std::io::{BufWriter, Read, Write};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::SystemTime;

use anyhow::{Context, Result, anyhow, ensure};
use pl_core::chat::WeakSession;
use sha2::{Digest, Sha256};
use tokio::sync::Notify;
use tokio::time::Instant;
use tokio_util::sync::CancellationToken;

use super::reader::{export_completions_range, resolve_readonly_session};
use super::types::{
    BuildInfoV1, CompletionCursorV1, EVENTS_SCHEMA_VERSION, EventBodyV1, EventSourceV1, EventV1,
    ExecutionErrorStage, ExecutionErrorV1, ExportedBlobV1, MAX_QUEUED_BATCHES,
    MAX_QUEUED_METADATA_BYTES, SealedMemberCutV1, TraceSummaryV1, format_utc_rfc3339,
    validate_export_relative_path,
};
use super::usage::{ThreadUsageInput, build_and_reconcile_usage};
use crate::StudioStore;
use crate::studio::thread_projection::{BillingFact, PreparedAccounting};

const EVENTS_FILE_NAME: &str = "events.jsonl";
const EVENTS_REL_PATH: &str = "events.jsonl";
const VERIFY_CHUNK_BYTES: usize = 64 * 1024;

/// Streaming content-addressed blob writer abstraction (allows test doubles without bypassing real files).
pub trait ContentBlobSink {
    type Writer: BlobChunkWriter;
    fn begin_blob(&mut self) -> Result<Self::Writer>;
}

pub trait BlobChunkWriter {
    fn write_chunk(&mut self, chunk: &[u8]) -> Result<()>;
    fn finish(self, media_type: Option<String>, encoding: String) -> Result<ExportedBlobV1>;
}

pub struct FsContentBlobSink {
    output_dir: PathBuf,
    contents_dir: PathBuf,
}

impl FsContentBlobSink {
    pub fn new(output_dir: PathBuf) -> Self {
        let contents_dir = output_dir.join("contents");
        Self {
            output_dir,
            contents_dir,
        }
    }
}

pub struct FsBlobWriter {
    output_dir: PathBuf,
    contents_dir: PathBuf,
    temp_path: PathBuf,
    file: Option<BufWriter<File>>,
    hasher: Sha256,
    byte_length: u64,
}

impl Drop for FsBlobWriter {
    fn drop(&mut self) {
        if self.file.take().is_some() {
            let _ = fs::remove_file(&self.temp_path);
        }
    }
}

impl ContentBlobSink for FsContentBlobSink {
    type Writer = FsBlobWriter;

    fn begin_blob(&mut self) -> Result<Self::Writer> {
        fs::create_dir_all(&self.contents_dir)
            .with_context(|| format!("ensure contents dir {}", self.contents_dir.display()))?;
        let nonce = uuid::Uuid::new_v4().simple();
        let temp_path = self
            .contents_dir
            .join(format!(".blob.{}.{nonce}.tmp", std::process::id()));
        let file = File::create(&temp_path)
            .with_context(|| format!("create content temp file {}", temp_path.display()))?;
        Ok(FsBlobWriter {
            output_dir: self.output_dir.clone(),
            contents_dir: self.contents_dir.clone(),
            temp_path,
            file: Some(BufWriter::new(file)),
            hasher: Sha256::new(),
            byte_length: 0,
        })
    }
}

impl BlobChunkWriter for FsBlobWriter {
    fn write_chunk(&mut self, chunk: &[u8]) -> Result<()> {
        let writer = self.file.as_mut().context("blob writer already finished")?;
        writer.write_all(chunk)?;
        self.hasher.update(chunk);
        self.byte_length = self
            .byte_length
            .checked_add(chunk.len() as u64)
            .context("blob length overflow")?;
        Ok(())
    }

    fn finish(mut self, media_type: Option<String>, encoding: String) -> Result<ExportedBlobV1> {
        let mut writer = self.file.take().context("blob writer already finished")?;
        writer.flush()?;
        let file = writer
            .into_inner()
            .map_err(|err| anyhow!("flush content temp file: {err}"))?;
        file.sync_all()?;
        drop(file);

        let sha256 = hex::encode(self.hasher.clone().finalize());
        let rel_path = format!("contents/{sha256}.bin");
        validate_export_relative_path(&rel_path)?;
        let final_path = self.output_dir.join(&rel_path);
        ensure!(
            final_path.starts_with(&self.contents_dir),
            "resolved content path escaped contents directory: {}",
            final_path.display()
        );

        match fs::symlink_metadata(&final_path) {
            Ok(meta) => {
                ensure!(
                    !meta.file_type().is_symlink() && meta.is_file(),
                    "existing content target {} is not a regular file",
                    final_path.display()
                );
                ensure!(
                    meta.len() == self.byte_length,
                    "existing content blob {} length {} disagrees with expected {}",
                    rel_path,
                    meta.len(),
                    self.byte_length
                );
                verify_existing_file_sha256(&final_path, &sha256)?;
                let _ = fs::remove_file(&self.temp_path);
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                fs::rename(&self.temp_path, &final_path).with_context(|| {
                    format!(
                        "commit content blob {} -> {}",
                        self.temp_path.display(),
                        final_path.display()
                    )
                })?;
            }
            Err(error) => {
                let _ = fs::remove_file(&self.temp_path);
                return Err(error)
                    .with_context(|| format!("inspect content target {}", final_path.display()));
            }
        }

        Ok(ExportedBlobV1 {
            path: rel_path,
            byte_length: self.byte_length,
            sha256,
            media_type,
            encoding,
        })
    }
}

fn verify_existing_file_sha256(path: &Path, expected_sha256: &str) -> Result<()> {
    let mut file = File::open(path)
        .with_context(|| format!("open existing content blob {}", path.display()))?;
    let mut hasher = Sha256::new();
    let mut buf = [0_u8; VERIFY_CHUNK_BYTES];
    loop {
        let n = file.read(&mut buf)?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    let actual = hex::encode(hasher.finalize());
    ensure!(
        actual == expected_sha256,
        "content hash mismatch in {}: expected {expected_sha256}, observed {actual}",
        path.display()
    );
    Ok(())
}

/// Commands queued onto the single background writer task.
pub enum ExportCommand {
    RunStarted {
        build: BuildInfoV1,
        manifest_sha256: String,
    },
    AgentRegistered {
        agent_id: String,
        thread_id: String,
        parent_agent_id: Option<String>,
        parent_thread_id: Option<String>,
        role: Option<String>,
        workspace_id: String,
        spawn_tool_call_id: Option<String>,
        initial_effect_seq: u64,
        initial_completion_epoch: Option<String>,
        initial_completion_seq: u64,
    },
    SkillsDiscovered {
        thread_id: String,
        report: pl_tool::skill::SkillDiscoveryReport,
    },
    LiveHandoff {
        thread_id: String,
        effect_seq: u64,
        accounting: PreparedAccounting,
        session: WeakSession,
    },
    Finalize {
        store: Option<StudioStore>,
        agent_ok: bool,
        flush_ok: bool,
        pending_after: Option<usize>,
        reply: tokio::sync::oneshot::Sender<FinalizeWriterOutcome>,
    },
}

pub struct FinalizeWriterOutcome {
    pub trace_complete: bool,
    pub usage_complete: bool,
    pub cost_complete: bool,
    pub trace: TraceSummaryV1,
    pub usage: Option<super::types::UsageExportV1>,
    pub failure: Option<ExecutionErrorV1>,
}

struct QueuedItem {
    cmd: ExportCommand,
    metadata_bytes: usize,
}

#[derive(Default)]
struct QueueState {
    queue: VecDeque<QueuedItem>,
    queued_batches: usize,
    queued_bytes: usize,
    admission_closed: bool,
    fatal_error: Option<ExecutionErrorV1>,
    writer_exited: bool,
    #[cfg(test)]
    paused: bool,
}

/// Shared immutable member final cut passed cleanly when `ProjectionWorker` retires.
#[derive(Clone)]
pub struct MemberFinalCut {
    pub through_effect_seq: u64,
    pub completion_epoch: Option<String>,
    pub completion_head_seq: u64,
    pub session: WeakSession,
    pub summary: pl_core::thread::UsageSummary,
    pub status: Option<String>,
    pub aborted: bool,
    pub error: Option<String>,
}

/// Synchronized live & final cut registry shared between producers and finalize stage.
#[derive(Default)]
pub struct SharedMemberState {
    pub members: BTreeMap<String, MemberSnapshot>,
}

#[derive(Clone)]
pub struct MemberSnapshot {
    pub agent_id: String,
    pub parent_agent_id: Option<String>,
    pub role: Option<String>,
    pub workspace_id: String,
    pub initial_effect_seq: u64,
    pub session: WeakSession,
    pub latest_usage: pl_core::thread::UsageSummary,
    pub latest_effect_seq: u64,
    pub latest_completion_epoch: Option<String>,
    pub latest_completion_head_seq: u64,
    pub final_cut: Option<MemberFinalCut>,
    pub spawn_aborted: Option<String>,
}

struct WriterMemberState {
    agent_id: String,
    parent_agent_id: Option<String>,
    role: Option<String>,
    workspace_id: String,
    initial_effect_seq: u64,
    exported_completion_seq: u64,
    last_epoch: Option<String>,
    last_effect_seq: u64,
    admitted_effects: BTreeMap<u64, String>,
    admitted_receipts: Vec<PreparedAccounting>,
    inferences: BTreeMap<String, (u64, String)>,
    completions_by_seq: BTreeMap<u64, (String, String)>,
    completions_by_epoch: BTreeMap<(String, u64), String>,
}

pub struct BoundedExportQueue {
    state: Mutex<QueueState>,
    slot_notify: Notify,
    work_notify: Notify,
    #[cfg(test)]
    pause_notify: Notify,
    run_cancel: CancellationToken,
}

impl BoundedExportQueue {
    pub fn new(run_cancel: CancellationToken) -> Arc<Self> {
        Arc::new(Self {
            state: Mutex::new(QueueState::default()),
            slot_notify: Notify::new(),
            work_notify: Notify::new(),
            #[cfg(test)]
            pause_notify: Notify::new(),
            run_cancel,
        })
    }

    pub async fn admit(
        &self,
        cmd: ExportCommand,
        metadata_bytes: usize,
    ) -> Result<(), Box<ExecutionErrorV1>> {
        if metadata_bytes > MAX_QUEUED_METADATA_BYTES {
            let err = ExecutionErrorV1 {
                stage: ExecutionErrorStage::Export,
                code: "exportBatchTooLarge".to_string(),
                message: format!(
                    "export metadata batch ({metadata_bytes} bytes) exceeds 16 MiB admission bound"
                ),
                turn_failure: None,
            };
            self.fail_permanently(err.clone());
            return Err(Box::new(err));
        }

        loop {
            let notified = {
                let mut guard = self
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                if let Some(fatal) = &guard.fatal_error {
                    return Err(Box::new(fatal.clone()));
                }
                if guard.admission_closed || guard.writer_exited {
                    return Err(Box::new(ExecutionErrorV1 {
                        stage: ExecutionErrorStage::Export,
                        code: "exportAdmissionClosed".to_string(),
                        message: "run exporter admission gate is closed".to_string(),
                        turn_failure: None,
                    }));
                }
                if guard.queued_batches < MAX_QUEUED_BATCHES
                    && guard.queued_bytes.saturating_add(metadata_bytes)
                        <= MAX_QUEUED_METADATA_BYTES
                {
                    guard.queued_batches += 1;
                    guard.queued_bytes += metadata_bytes;
                    guard.queue.push_back(QueuedItem {
                        cmd,
                        metadata_bytes,
                    });
                    drop(guard);
                    self.work_notify.notify_one();
                    return Ok(());
                }
                self.slot_notify.notified()
            };
            notified.await;
        }
    }

    /// Enqueues Finalize even when `admission_closed` was armed on deadline, provided writer task
    /// has not exited, so finalize can still flush/report partial state.
    pub async fn enqueue_finalize(
        &self,
        store: Option<StudioStore>,
        agent_ok: bool,
        flush_ok: bool,
        pending_after: Option<usize>,
    ) -> Result<tokio::sync::oneshot::Receiver<FinalizeWriterOutcome>, Box<ExecutionErrorV1>> {
        let (tx, rx) = tokio::sync::oneshot::channel();
        {
            let mut guard = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if guard.writer_exited {
                return Err(Box::new(guard.fatal_error.clone().unwrap_or(
                    ExecutionErrorV1 {
                        stage: ExecutionErrorStage::Export,
                        code: "exportWriterStopped".to_string(),
                        message: "exporter writer task exited before finalization".to_string(),
                        turn_failure: None,
                    },
                )));
            }
            guard.queue.push_back(QueuedItem {
                cmd: ExportCommand::Finalize {
                    store,
                    agent_ok,
                    flush_ok,
                    pending_after,
                    reply: tx,
                },
                metadata_bytes: 0,
            });
            guard.queued_batches += 1;
        }
        self.work_notify.notify_one();
        Ok(rx)
    }

    pub fn close_admission(&self, reason: ExecutionErrorV1) {
        self.fail_permanently(reason);
    }

    pub fn fail_permanently(&self, err: ExecutionErrorV1) {
        let mut guard = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        guard.admission_closed = true;
        if guard.fatal_error.is_none() {
            guard.fatal_error = Some(err);
        }
        drop(guard);
        self.slot_notify.notify_waiters();
        self.work_notify.notify_waiters();
        #[cfg(test)]
        self.pause_notify.notify_waiters();
        self.run_cancel.cancel();
    }

    pub fn fatal_error(&self) -> Option<ExecutionErrorV1> {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .fatal_error
            .clone()
    }

    #[cfg(test)]
    pub fn queued_counts(&self) -> (usize, usize) {
        let guard = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        (guard.queued_batches, guard.queued_bytes)
    }

    #[cfg(test)]
    pub fn set_paused(&self, paused: bool) {
        let mut guard = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        guard.paused = paused;
        drop(guard);
        self.pause_notify.notify_waiters();
    }

    async fn pop(&self) -> Option<ExportCommand> {
        loop {
            #[cfg(test)]
            {
                let pause_notified = {
                    let guard = self
                        .state
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner);
                    if guard.paused && !guard.admission_closed {
                        Some(self.pause_notify.notified())
                    } else {
                        None
                    }
                };
                if let Some(notified) = pause_notified {
                    notified.await;
                    continue;
                }
            }
            let notified = {
                let mut guard = self
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                if let Some(item) = guard.queue.pop_front() {
                    guard.queued_batches = guard.queued_batches.saturating_sub(1);
                    guard.queued_bytes = guard.queued_bytes.saturating_sub(item.metadata_bytes);
                    drop(guard);
                    self.slot_notify.notify_waiters();
                    return Some(item.cmd);
                }
                if guard.writer_exited {
                    return None;
                }
                self.work_notify.notified()
            };
            notified.await;
        }
    }

    fn mark_writer_exited(&self) {
        let mut guard = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        guard.writer_exited = true;
        guard.admission_closed = true;
        drop(guard);
        self.slot_notify.notify_waiters();
    }
}

/// Spawns the single background writer task for one run.
pub fn spawn_writer_task(
    run_id: String,
    output_dir: PathBuf,
    queue: Arc<BoundedExportQueue>,
    shared_members: Arc<Mutex<SharedMemberState>>,
) -> tokio::task::JoinHandle<()> {
    tokio::spawn(async move {
        let mut worker = WriterWorker::new(run_id, output_dir, queue.clone(), shared_members);
        worker.run().await;
        queue.mark_writer_exited();
    })
}

struct WriterWorker {
    run_id: String,
    events_path: PathBuf,
    queue: Arc<BoundedExportQueue>,
    shared_members: Arc<Mutex<SharedMemberState>>,
    events_file: Option<BufWriter<File>>,
    blob_sink: FsContentBlobSink,
    next_event_seq: u64,
    last_event_seq: Option<u64>,
    members: BTreeMap<String, WriterMemberState>,
    sealed: bool,
}

impl WriterWorker {
    fn new(
        run_id: String,
        output_dir: PathBuf,
        queue: Arc<BoundedExportQueue>,
        shared_members: Arc<Mutex<SharedMemberState>>,
    ) -> Self {
        let events_path = output_dir.join(EVENTS_FILE_NAME);
        let blob_sink = FsContentBlobSink::new(output_dir);
        Self {
            run_id,
            events_path,
            queue,
            shared_members,
            events_file: None,
            blob_sink,
            next_event_seq: 1,
            last_event_seq: None,
            members: BTreeMap::new(),
            sealed: false,
        }
    }

    async fn run(&mut self) {
        while let Some(cmd) = self.queue.pop().await {
            match cmd {
                ExportCommand::Finalize {
                    store,
                    agent_ok,
                    flush_ok,
                    pending_after,
                    reply,
                } => {
                    let outcome = self
                        .handle_finalize(store, agent_ok, flush_ok, pending_after)
                        .await;
                    let _ = reply.send(outcome);
                    break;
                }
                other => {
                    if self.queue.fatal_error().is_some() {
                        // Drain remaining non-finalize commands promptly after permanent failure.
                        continue;
                    }
                    if let Err(err) = self.process_command(other).await {
                        let diag = ExecutionErrorV1 {
                            stage: ExecutionErrorStage::Export,
                            code: "exportWriteFailed".to_string(),
                            message: err.to_string(),
                            turn_failure: None,
                        };
                        self.queue.fail_permanently(diag);
                    }
                }
            }
        }
    }

    async fn process_command(&mut self, cmd: ExportCommand) -> Result<()> {
        match cmd {
            ExportCommand::RunStarted {
                build,
                manifest_sha256,
            } => {
                self.write_event(
                    None,
                    EventSourceV1::default(),
                    EventBodyV1::RunStarted {
                        run_id: self.run_id.clone(),
                        build,
                        manifest_sha256,
                    },
                )?;
            }
            ExportCommand::AgentRegistered {
                agent_id,
                thread_id,
                parent_agent_id,
                parent_thread_id,
                role,
                workspace_id,
                spawn_tool_call_id,
                initial_effect_seq,
                initial_completion_epoch,
                initial_completion_seq,
            } => {
                if let Some(existing) = self.members.get(&thread_id) {
                    ensure!(
                        existing.agent_id == agent_id
                            && existing.parent_agent_id == parent_agent_id
                            && existing.role == role
                            && existing.workspace_id == workspace_id
                            && existing.initial_effect_seq == initial_effect_seq,
                        "conflicting member re-registration for thread {thread_id}"
                    );
                    return Ok(());
                }
                self.members.insert(
                    thread_id.clone(),
                    WriterMemberState {
                        agent_id: agent_id.clone(),
                        parent_agent_id: parent_agent_id.clone(),
                        role: role.clone(),
                        workspace_id: workspace_id.clone(),
                        initial_effect_seq,
                        exported_completion_seq: initial_completion_seq,
                        last_epoch: initial_completion_epoch.clone(),
                        last_effect_seq: initial_effect_seq,
                        admitted_effects: BTreeMap::new(),
                        admitted_receipts: Vec::new(),
                        inferences: BTreeMap::new(),
                        completions_by_seq: BTreeMap::new(),
                        completions_by_epoch: BTreeMap::new(),
                    },
                );
                self.write_event(
                    Some(thread_id.clone()),
                    EventSourceV1 {
                        epoch: initial_completion_epoch.clone(),
                        effect_seq: Some(initial_effect_seq),
                        tool_call_id: spawn_tool_call_id.clone(),
                        completion_seq: Some(initial_completion_seq),
                        ..Default::default()
                    },
                    EventBodyV1::AgentRegistered {
                        agent_id,
                        thread_id,
                        parent_agent_id,
                        parent_thread_id,
                        role,
                        workspace_id,
                        spawn_tool_call_id,
                        initial_effect_seq,
                        initial_completion_cursor: CompletionCursorV1 {
                            epoch: initial_completion_epoch,
                            completion_seq: initial_completion_seq,
                        },
                    },
                )?;
            }
            ExportCommand::SkillsDiscovered { thread_id, report } => {
                self.write_event(
                    Some(thread_id.clone()),
                    EventSourceV1::default(),
                    EventBodyV1::SkillsDiscovered {
                        thread_id,
                        source_fingerprint: report.source_fingerprint,
                        sources: report.sources,
                        winners: report.winners,
                        warnings: report.warnings,
                        complete: report.complete,
                    },
                )?;
            }
            ExportCommand::LiveHandoff {
                thread_id,
                effect_seq,
                accounting,
                session,
            } => {
                self.handle_live_handoff(thread_id, effect_seq, accounting, session)
                    .await?;
            }
            ExportCommand::Finalize { .. } => {}
        }
        Ok(())
    }

    async fn handle_live_handoff(
        &mut self,
        thread_id: String,
        effect_seq: u64,
        accounting: PreparedAccounting,
        weak_session: WeakSession,
    ) -> Result<()> {
        let member = self
            .members
            .get_mut(&thread_id)
            .with_context(|| format!("live handoff arrived for unregistered thread {thread_id}"))?;
        let effect_fp = fingerprint_prepared_accounting(&accounting)?;
        if let Some(prev_fp) = member.admitted_effects.get(&effect_seq) {
            ensure!(
                *prev_fp == effect_fp,
                "conflicting accounting redelivery for thread {thread_id} at effect_seq {effect_seq}"
            );
            return Ok(());
        }

        let turn_id = accounting.primary_turn_id().map(str::to_owned);
        let mut events_to_emit = Vec::new();
        for fact in accounting.facts.iter() {
            let fact_fp = fingerprint_billing_fact(fact)?;
            if let Some((prev_effect_seq, prev_fact_fp)) =
                member.inferences.get(&fact.record.inference_id)
            {
                ensure!(
                    *prev_effect_seq == effect_seq && *prev_fact_fp == fact_fp,
                    "inference_id conflict for {} in thread {thread_id}: effect {prev_effect_seq} vs {effect_seq}",
                    fact.record.inference_id
                );
                continue;
            }
            member
                .inferences
                .insert(fact.record.inference_id.clone(), (effect_seq, fact_fp));
            events_to_emit.push((
                EventSourceV1 {
                    effect_seq: Some(effect_seq),
                    turn_id: turn_id.clone(),
                    ..Default::default()
                },
                EventBodyV1::InferenceFinished {
                    status: fact.status.as_str().to_string(),
                    auxiliary: fact.auxiliary,
                    billing: fact.record.clone(),
                },
            ));
        }

        member.admitted_effects.insert(effect_seq, effect_fp);
        if effect_seq > member.initial_effect_seq {
            member.admitted_receipts.push(accounting);
        }
        if effect_seq > member.last_effect_seq {
            member.last_effect_seq = effect_seq;
        }

        for (source, body) in events_to_emit {
            self.write_event(Some(thread_id.clone()), source, body)?;
        }

        // Incrementally stream newly sealed completion items while the session is alive so
        // body content reads proceed continuously without waiting for final producer ACK.
        if let Some(live_session) = weak_session.upgrade() {
            self.export_completions_for_member(&thread_id, &live_session, None, None)
                .await?;
        }
        Ok(())
    }

    async fn export_completions_for_member(
        &mut self,
        thread_id: &str,
        session: &pl_core::chat::Session,
        database_id: Option<&str>,
        ceiling: Option<u64>,
    ) -> Result<()> {
        let after_seq = self
            .members
            .get(thread_id)
            .with_context(|| format!("missing member {thread_id}"))?
            .exported_completion_seq;
        let target = ceiling.unwrap_or_else(|| session.head_seq());
        if target <= after_seq {
            return Ok(());
        }
        let (through_seq, records) = export_completions_range(
            session,
            database_id,
            after_seq,
            Some(target),
            &mut self.blob_sink,
        )
        .await?;
        for record in records {
            let member = self
                .members
                .get_mut(thread_id)
                .with_context(|| format!("missing member {thread_id}"))?;
            let seq = record.header.append_seq;
            let key = (record.epoch.clone(), seq);
            if let Some(prev_fp) = member.completions_by_epoch.get(&key) {
                ensure!(
                    *prev_fp == record.header_payload_fingerprint,
                    "conflicting completion record at ({thread_id}, {}, {seq})",
                    record.epoch
                );
                continue;
            }
            if let Some((prev_id, prev_fp)) = member.completions_by_seq.get(&seq) {
                ensure!(
                    *prev_id == record.header.item_id
                        && *prev_fp == record.header_payload_fingerprint,
                    "conflicting completion record across epochs at ({thread_id}, seq={seq})"
                );
                continue;
            }
            member
                .completions_by_epoch
                .insert(key, record.header_payload_fingerprint.clone());
            member.completions_by_seq.insert(
                seq,
                (
                    record.header.item_id.clone(),
                    record.header_payload_fingerprint,
                ),
            );
            member.last_epoch = Some(record.epoch);
            member.exported_completion_seq = member.exported_completion_seq.max(seq);
            self.write_event(
                Some(thread_id.to_string()),
                record.source,
                EventBodyV1::Completion {
                    header: record.header,
                    atom: record.atom,
                    payload: record.payload,
                    contents: record.contents,
                },
            )?;
        }
        if let Some(member) = self.members.get_mut(thread_id) {
            member.exported_completion_seq = member.exported_completion_seq.max(through_seq);
            member.last_epoch = Some(session.epoch().as_str().to_string());
        }
        Ok(())
    }

    async fn handle_finalize(
        &mut self,
        store: Option<StudioStore>,
        agent_ok: bool,
        flush_ok: bool,
        pending_after: Option<usize>,
    ) -> FinalizeWriterOutcome {
        let mut fatal = self.queue.fatal_error();
        let snapshots = {
            let guard = self
                .shared_members
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            guard.members.clone()
        };

        // Ensure every member present in shared registry (e.g. if admission failed earlier) is accounted for.
        let mut missing_final_cut = Vec::new();
        let mut member_usage_inputs = Vec::new();

        // First phase: backfill missing durable completions using read-only Session handles (never thread_snapshot).
        if fatal.is_none() {
            for (thread_id, snap) in &snapshots {
                if snap.spawn_aborted.is_some() {
                    continue;
                }
                let final_cut = snap.final_cut.as_ref();
                if final_cut.is_none() {
                    missing_final_cut.push(thread_id.clone());
                }
                if !self.members.contains_key(thread_id) {
                    fatal = Some(ExecutionErrorV1 {
                        stage: ExecutionErrorStage::Export,
                        code: "missingMemberRegistration".to_string(),
                        message: format!(
                            "member {thread_id} was registered without writer AgentRegistered state"
                        ),
                        turn_failure: None,
                    });
                    break;
                }
                let expected_head = final_cut.map(|c| c.completion_head_seq);
                let weak_session = final_cut.map(|c| &c.session).unwrap_or(&snap.session);
                let res = match (&store, weak_session.upgrade()) {
                    (Some(store), _) => {
                        resolve_readonly_session(weak_session, store, thread_id).await
                    }
                    (None, Some(session)) => Ok((session, None)),
                    (None, None) => Err(anyhow!(
                        "store unavailable to reopen retired session {thread_id}"
                    )),
                };
                match res {
                    Ok((session, db_id)) => {
                        if let Some(expected) = expected_head
                            && session.head_seq() < expected
                        {
                            fatal = Some(ExecutionErrorV1 {
                                stage: ExecutionErrorStage::Export,
                                code: "completionHeadRegressed".to_string(),
                                message: format!(
                                    "session {thread_id} head_seq {} is behind final cut {expected}",
                                    session.head_seq()
                                ),
                                turn_failure: None,
                            });
                            break;
                        }
                        if let Err(err) = self
                            .export_completions_for_member(
                                thread_id,
                                &session,
                                db_id.as_deref(),
                                expected_head,
                            )
                            .await
                        {
                            fatal = Some(ExecutionErrorV1 {
                                stage: ExecutionErrorStage::Export,
                                code: "completionBackfillFailed".to_string(),
                                message: err.to_string(),
                                turn_failure: None,
                            });
                            break;
                        }
                    }
                    Err(err) => {
                        fatal = Some(ExecutionErrorV1 {
                            stage: ExecutionErrorStage::Export,
                            code: "sessionOpenFailed".to_string(),
                            message: err.to_string(),
                            turn_failure: None,
                        });
                        break;
                    }
                }
            }
        }

        // Verify all member cuts, reconcile receipts, and emit ThreadSealed + RunSealed when clean.
        let native_clean = agent_ok && flush_ok && pending_after == Some(0);
        let cuts_complete =
            fatal.is_none() && missing_final_cut.is_empty() && !snapshots.is_empty();

        // Check that admitted effects per member cover [initial ..= final through_effect_seq] without missing cuts.
        let mut usage_storage: Vec<(
            String,
            u64,
            u64,
            pl_core::thread::UsageSummary,
            Vec<PreparedAccounting>,
        )> = Vec::new();
        for (thread_id, snap) in &snapshots {
            if let Some(writer_member) = self.members.get(thread_id) {
                let (through_seq, summary) = match &snap.final_cut {
                    Some(cut) => (cut.through_effect_seq, cut.summary.clone()),
                    None => (snap.latest_effect_seq, snap.latest_usage.clone()),
                };
                usage_storage.push((
                    thread_id.clone(),
                    snap.initial_effect_seq,
                    through_seq,
                    summary,
                    writer_member.admitted_receipts.clone(),
                ));
            }
        }

        let tentative_trace_complete = native_clean && cuts_complete && fatal.is_none();
        for (thread_id, init_seq, through_seq, summary, receipts) in &usage_storage {
            member_usage_inputs.push(ThreadUsageInput {
                thread_id,
                initial_effect_seq: *init_seq,
                through_effect_seq: *through_seq,
                summary,
                receipts,
            });
        }
        let built_usage = build_and_reconcile_usage(tentative_trace_complete, &member_usage_inputs);

        if fatal.is_none() && !built_usage.reconciled {
            fatal = Some(ExecutionErrorV1 {
                stage: ExecutionErrorStage::Export,
                code: "usageReconcileFailed".to_string(),
                message: built_usage
                    .reconcile_error
                    .clone()
                    .unwrap_or_else(|| "accounting reconciliation failed".to_string()),
                turn_failure: None,
            });
        }

        let can_seal = native_clean
            && cuts_complete
            && fatal.is_none()
            && built_usage.reconciled
            && !self.queue.fatal_error().is_some();

        // Emit `threadSealed` for every member with a settled cut or explicit abort (if writer alive).
        let mut sealed_member_cuts = Vec::with_capacity(snapshots.len());
        let mut sealed_write_ok = self.queue.fatal_error().is_none() && fatal.is_none();
        for (thread_id, snap) in &snapshots {
            let cut_epoch = snap
                .final_cut
                .as_ref()
                .and_then(|c| c.completion_epoch.clone())
                .or_else(|| {
                    self.members
                        .get(thread_id)
                        .and_then(|m| m.last_epoch.clone())
                })
                .or_else(|| snap.latest_completion_epoch.clone());
            let cut_seq = snap
                .final_cut
                .as_ref()
                .map(|c| c.completion_head_seq)
                .unwrap_or(snap.latest_completion_head_seq);
            let through_effect_seq = snap
                .final_cut
                .as_ref()
                .map(|c| c.through_effect_seq)
                .unwrap_or(snap.latest_effect_seq);
            let summary = snap
                .final_cut
                .as_ref()
                .map(|c| c.summary.clone())
                .unwrap_or_else(|| snap.latest_usage.clone());
            let (status, aborted, err_msg) = if let Some(abort_err) = &snap.spawn_aborted {
                (Some("aborted".to_string()), true, Some(abort_err.clone()))
            } else if let Some(cut) = &snap.final_cut {
                (cut.status.clone(), cut.aborted, cut.error.clone())
            } else {
                (
                    Some("incomplete".to_string()),
                    false,
                    Some("missing member final cut".to_string()),
                )
            };

            let member_clean = snap.spawn_aborted.is_some() || snap.final_cut.is_some();
            if sealed_write_ok
                && member_clean
                && let Err(err) = self.write_event(
                    Some(thread_id.clone()),
                    EventSourceV1 {
                        epoch: cut_epoch.clone(),
                        effect_seq: Some(through_effect_seq),
                        completion_seq: Some(cut_seq),
                        ..Default::default()
                    },
                    EventBodyV1::ThreadSealed {
                        thread_id: thread_id.clone(),
                        through_effect_seq,
                        completion_cut: CompletionCursorV1 {
                            epoch: cut_epoch.clone(),
                            completion_seq: cut_seq,
                        },
                        summary,
                        status,
                        aborted,
                        error: err_msg,
                    },
                )
            {
                sealed_write_ok = false;
                if fatal.is_none() {
                    fatal = Some(ExecutionErrorV1 {
                        stage: ExecutionErrorStage::Export,
                        code: "exportWriteFailed".to_string(),
                        message: err.to_string(),
                        turn_failure: None,
                    });
                }
            }

            sealed_member_cuts.push(SealedMemberCutV1 {
                thread_id: thread_id.clone(),
                agent_id: snap.agent_id.clone(),
                parent_agent_id: snap.parent_agent_id.clone(),
                role: snap.role.clone(),
                through_effect_seq,
                completion_cut: CompletionCursorV1 {
                    epoch: cut_epoch,
                    completion_seq: cut_seq,
                },
                aborted,
                sealed: member_clean && sealed_write_ok,
            });
        }

        if can_seal && sealed_write_ok {
            if let Err(err) = self.write_event(
                None,
                EventSourceV1::default(),
                EventBodyV1::RunSealed {
                    members: sealed_member_cuts,
                    reconciled: built_usage.reconciled,
                    reconcile_error: built_usage.reconcile_error.clone(),
                    trace_complete: true,
                    usage_complete: built_usage.usage_complete,
                    cost_complete: built_usage.cost_complete,
                },
            ) {
                if fatal.is_none() {
                    fatal = Some(ExecutionErrorV1 {
                        stage: ExecutionErrorStage::Export,
                        code: "exportWriteFailed".to_string(),
                        message: err.to_string(),
                        turn_failure: None,
                    });
                }
            } else {
                self.sealed = true;
            }
        }

        if let Err(err) = self.flush_and_close_events_file() {
            self.sealed = false;
            if fatal.is_none() {
                fatal = Some(ExecutionErrorV1 {
                    stage: ExecutionErrorStage::Export,
                    code: "exportFlushFailed".to_string(),
                    message: err.to_string(),
                    turn_failure: None,
                });
            }
        }

        let trace_complete = self.sealed && fatal.is_none() && native_clean;
        // Recompute UsageExportV1 only if final trace_complete ended up false while tentative was true.
        let final_usage = if trace_complete == tentative_trace_complete {
            built_usage
        } else {
            build_and_reconcile_usage(trace_complete, &member_usage_inputs)
        };

        let (events_sha256, event_count) = self.measure_events_file();
        let reason = if trace_complete {
            None
        } else if let Some(err) = &fatal {
            Some(err.message.clone())
        } else if !native_clean {
            Some(format!(
                "native runtime did not finish cleanly before export seal (agentOk={agent_ok}, flushOk={flush_ok}, pendingAfter={pending_after:?})"
            ))
        } else if !missing_final_cut.is_empty() {
            Some(format!(
                "missing final cut for members: {}",
                missing_final_cut.join(", ")
            ))
        } else {
            Some("export trace did not seal cleanly".to_string())
        };

        FinalizeWriterOutcome {
            trace_complete,
            usage_complete: final_usage.usage_complete,
            cost_complete: final_usage.cost_complete,
            trace: TraceSummaryV1 {
                events_path: EVENTS_REL_PATH.to_string(),
                events_sha256,
                event_count,
                last_event_seq: self.last_event_seq,
                sealed: self.sealed,
                reason,
            },
            usage: (!snapshots.is_empty()).then_some(final_usage.export),
            failure: fatal,
        }
    }

    fn write_event(
        &mut self,
        thread_id: Option<String>,
        source: EventSourceV1,
        body: EventBodyV1,
    ) -> Result<()> {
        if self.events_file.is_none() {
            let file = OpenOptions::new()
                .create(true)
                .append(true)
                .open(&self.events_path)
                .with_context(|| format!("open events file {}", self.events_path.display()))?;
            self.events_file = Some(BufWriter::new(file));
        }
        let event_seq = self.next_event_seq;
        let event = EventV1 {
            schema_version: EVENTS_SCHEMA_VERSION,
            run_id: self.run_id.clone(),
            event_seq,
            body,
            emitted_at: format_utc_rfc3339(SystemTime::now()),
            thread_id,
            source,
        };
        let mut line = serde_json::to_vec(&event).context("serialize EventV1 line")?;
        line.push(b'\n');
        let writer = self
            .events_file
            .as_mut()
            .context("events writer not initialized")?;
        writer.write_all(&line)?;
        self.next_event_seq = event_seq.checked_add(1).context("event_seq overflow")?;
        self.last_event_seq = Some(event_seq);
        Ok(())
    }

    fn flush_and_close_events_file(&mut self) -> Result<()> {
        if let Some(mut writer) = self.events_file.take() {
            writer.flush()?;
            let file = writer
                .into_inner()
                .map_err(|err| anyhow!("unwrap buffered events writer: {err}"))?;
            file.sync_all()?;
        }
        Ok(())
    }

    fn measure_events_file(&self) -> (Option<String>, u64) {
        let Ok(mut file) = File::open(&self.events_path) else {
            return (None, self.last_event_seq.unwrap_or(0));
        };
        let mut hasher = Sha256::new();
        let mut buf = [0_u8; VERIFY_CHUNK_BYTES];
        loop {
            match file.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => hasher.update(&buf[..n]),
                Err(_) => return (None, self.last_event_seq.unwrap_or(0)),
            }
        }
        (
            Some(hex::encode(hasher.finalize())),
            self.last_event_seq.unwrap_or(0),
        )
    }
}

fn fingerprint_prepared_accounting(accounting: &PreparedAccounting) -> Result<String> {
    let facts: Vec<&BillingFact> = accounting.facts.iter().collect();
    let value = serde_json::json!({
        "threadId": &accounting.thread_id,
        "sequence": accounting.sequence,
        "committedAt": accounting.committed_at(),
        "primaryTurnId": accounting.primary_turn_id(),
        "facts": facts.iter().map(|f| serde_json::json!({
            "status": f.status.as_str(),
            "auxiliary": f.auxiliary,
            "record": &f.record,
        })).collect::<Vec<_>>(),
    });
    Ok(crate::hash::canonical_json_hash(&value))
}

fn fingerprint_billing_fact(fact: &BillingFact) -> Result<String> {
    let value = serde_json::json!({
        "status": fact.status.as_str(),
        "auxiliary": fact.auxiliary,
        "record": &fact.record,
    });
    Ok(crate::hash::canonical_json_hash(&value))
}

/// Estimates serialized metadata byte size charged against the 16 MiB queue bound without copying
/// body content into the queue.
pub fn estimate_handoff_metadata_bytes(accounting: &PreparedAccounting) -> usize {
    let facts_bytes: usize = accounting
        .facts
        .iter()
        .map(|fact| serde_json::to_vec(&fact.record).map_or(256, |v| v.len()) + 32)
        .sum();
    accounting.thread_id.len() + facts_bytes + 128
}

/// Waits for finalize writer response, closing admission if `deadline` expires while blocked.
pub async fn await_finalize_with_budget(
    queue: &BoundedExportQueue,
    rx: tokio::sync::oneshot::Receiver<FinalizeWriterOutcome>,
    deadline: Option<Instant>,
) -> FinalizeWriterOutcome {
    match deadline {
        None => match rx.await {
            Ok(outcome) => outcome,
            Err(_) => crashed_outcome(queue),
        },
        Some(limit) => {
            if Instant::now() >= limit {
                queue.close_admission(ExecutionErrorV1 {
                    stage: ExecutionErrorStage::Export,
                    code: "exportDeadlineExceeded".to_string(),
                    message: "shutdown cleanup deadline expired before export finalization"
                        .to_string(),
                    turn_failure: None,
                });
            }
            match tokio::time::timeout_at(limit, rx).await {
                Ok(Ok(outcome)) => outcome,
                Ok(Err(_)) => crashed_outcome(queue),
                Err(_) => {
                    let err = ExecutionErrorV1 {
                        stage: ExecutionErrorStage::Export,
                        code: "exportDeadlineExceeded".to_string(),
                        message: "exporter finalization exceeded shared shutdown deadline"
                            .to_string(),
                        turn_failure: None,
                    };
                    queue.close_admission(err.clone());
                    FinalizeWriterOutcome {
                        trace_complete: false,
                        usage_complete: false,
                        cost_complete: false,
                        trace: TraceSummaryV1 {
                            events_path: EVENTS_REL_PATH.to_string(),
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
            }
        }
    }
}

fn crashed_outcome(queue: &BoundedExportQueue) -> FinalizeWriterOutcome {
    let err = queue.fatal_error().unwrap_or(ExecutionErrorV1 {
        stage: ExecutionErrorStage::Export,
        code: "exportWriterStopped".to_string(),
        message: "exporter writer dropped finalize response channel".to_string(),
        turn_failure: None,
    });
    FinalizeWriterOutcome {
        trace_complete: false,
        usage_complete: false,
        cost_complete: false,
        trace: TraceSummaryV1 {
            events_path: EVENTS_REL_PATH.to_string(),
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
