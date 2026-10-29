//! One bounded private evidence sink shared by event writers and paginated export.
use anyhow::{Context, Result};
use serde::Serialize;
use sha2::{Digest, Sha256};
use std::{
    fs::{File, OpenOptions},
    io::Write,
    path::{Path, PathBuf},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicU64, Ordering},
    },
    time::{SystemTime, UNIX_EPOCH},
};

pub const MAX_BYTES: u64 = 256 * 1024 * 1024;
const SUMMARY_RESERVE: u64 = 1024 * 1024;
pub const MAX_THREADS: usize = 64;
pub const MAX_ITEMS: usize = 10_000;

#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum Termination {
    SetupError,
    CollectionError,
    StorageError,
    ApiError,
    TaskCompletedObserved,
    TaskStopped,
    SimpleTreeIdleObserved,
    TimedOut,
    Interrupted,
    EvidenceIncomplete,
    BudgetExceeded,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Manifest {
    pub mode: String,
    pub root_route_override: bool,
    pub requested_seconds: u64,
    pub root: Option<pl_protocol::Thread>,
    pub root_route: Option<pl_protocol::studio::NewThreadModelRoute>,
    pub root_model_route: Option<pl_protocol::ThreadModelRouteSnapshot>,
    pub root_workflow: Option<pl_protocol::WorkflowRuntimeSnapshot>,
    pub root_workflow_snapshot_revision: Option<u64>,
    pub members: Vec<MemberIdentity>,
    pub workspace: Option<PathBuf>,
    pub workspace_location: Option<WorkspaceLocation>,
    pub started_at: i64,
    pub ended_at: i64,
    pub elapsed_millis: u128,
    pub termination: Termination,
    pub evidence_complete: bool,
    pub shutdown_observed: bool,
    pub scenario_elapsed_millis: u128,
    pub cleanup_elapsed_millis: u128,
    pub cleanup_budget_expired: bool,
    pub shutdown_elapsed_millis: u128,
    pub admitted_operations: Vec<OperationTiming>,
    pub events: Vec<EventCoverage>,
    pub writers_joined: usize,
    pub collected_bytes: u64,
    pub timeline_items: usize,
    pub thread_exports: Vec<ThreadExport>,
    pub retired_owed_work: Vec<RetiredOwedWork>,
    pub prompt_sha256: String,
    pub binary: SourceIdentity,
    pub compiled_sources: Vec<SourceIdentity>,
    pub issues: Vec<String>,
    pub unfinished: Vec<String>,
    pub file_index: &'static str,
    pub limits: Limits,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Limits {
    total_bytes: u64,
    threads: usize,
    timeline_items: usize,
    decisions: usize,
    decision_bytes: usize,
}

#[derive(Debug, Clone, Serialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum WorkspaceLocation {
    Local { path: PathBuf },
    Ssh { alias: String, path: String },
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SourceIdentity {
    path: String,
    bytes: u64,
    sha256: String,
}

#[derive(Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ThreadExport {
    pub thread_id: String,
    pub directory: String,
    pub snapshot_revision: Option<u64>,
    pub storage: Option<pl_protocol::ThreadStorageState>,
    pub latest_turn: Option<pl_protocol::Turn>,
    pub turn_pages: usize,
    pub timeline_pages: usize,
    pub detail_fields: usize,
    pub nonterminal_tools: usize,
    pub complete: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RetiredOwedWork {
    pub thread_id: String,
    pub continuation: pl_protocol::ContinuationView,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct OperationTiming {
    pub operation: String,
    pub elapsed_millis: u128,
    pub stopped_on_return: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TurnAnchor {
    pub turn_id: String,
    pub turn_revision: u64,
    pub terminal_state: pl_protocol::TurnState,
}
impl TurnAnchor {
    pub fn from_turn(turn: &pl_protocol::Turn) -> Result<Self> {
        anyhow::ensure!(turn.state.is_terminal(), "anchor Turn is not terminal");
        Ok(Self {
            turn_id: turn.id.clone(),
            turn_revision: turn.revision,
            terminal_state: turn.state.clone(),
        })
    }
    fn key(&self) -> (String, u64) {
        (self.turn_id.clone(), self.turn_revision)
    }
}

#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StreamWatermark {
    pub epoch: u64,
    pub revision: u64,
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EventCoverage {
    pub thread_id: String,
    pub initial_snapshot_revision: Option<u64>,
    pub consumed_last: Option<StreamWatermark>,
    pub target: Option<TurnAnchor>,
    pub matched_at: Option<StreamWatermark>,
    pub join_elapsed_millis: u128,
    pub stream_ended: bool,
    pub complete: bool,
    pub error: Option<String>,
    pub source: &'static str,
}

struct EventProgress {
    coverage: EventCoverage,
    anchors: std::collections::BTreeMap<(String, u64), (pl_protocol::TurnState, StreamWatermark)>,
    eof: bool,
}

pub struct EventWriter {
    pub thread_id: String,
    progress: Arc<Mutex<EventProgress>>,
    changed: tokio::sync::watch::Receiver<u64>,
    stop: tokio_util::sync::CancellationToken,
    target: tokio::sync::watch::Sender<Option<TurnAnchor>>,
    handle: tokio::task::JoinHandle<Result<()>>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MemberIdentity {
    id: String,
    thread_id: String,
    root_thread_id: String,
    role: String,
    delegation_mode: pl_protocol::DelegationMode,
    delegation_preference: pl_protocol::DelegationPreference,
    frozen_model: Option<pl_protocol::studio::NewThreadModelRoute>,
    state: pl_protocol::AgentState,
    execution: Option<pl_protocol::AgentExecution>,
    can_stop: bool,
    awaiting_scheduling: bool,
}

impl From<&pl_studio_runtime::StudioAgentDirectoryEntry> for MemberIdentity {
    fn from(agent: &pl_studio_runtime::StudioAgentDirectoryEntry) -> Self {
        Self {
            id: agent.id.clone(),
            thread_id: agent.thread_id.clone(),
            root_thread_id: agent.root_thread_id.clone(),
            role: agent.role.clone(),
            delegation_mode: agent.delegation_mode,
            delegation_preference: agent.delegation_preference,
            frozen_model: agent.frozen_model.clone(),
            state: agent.state.clone(),
            execution: agent.execution.clone(),
            can_stop: agent.can_stop,
            awaiting_scheduling: agent.awaiting_scheduling,
        }
    }
}

impl Manifest {
    pub fn new() -> Result<Self> {
        let executable = std::env::current_exe()?;
        let mut file = File::open(&executable)?;
        let mut hasher = Sha256::new();
        let bytes = std::io::copy(&mut file, &mut HashWriter(&mut hasher))?;
        let binary = SourceIdentity {
            path: executable.to_string_lossy().into_owned(),
            bytes,
            sha256: hex::encode(hasher.finalize()),
        };
        // include_str binds these identities to this build, not to a later checkout read.
        let sources = [
            (
                "src/prompts/system.md",
                include_str!("../../src/prompts/system.md"),
            ),
            (
                "src/studio/thread/task.rs",
                include_str!("../../src/studio/thread/task.rs"),
            ),
            (
                "src/agent/catalog.rs",
                include_str!("../../src/agent/catalog.rs"),
            ),
            (
                "src/agent/prompts/main.md",
                include_str!("../../src/agent/prompts/main.md"),
            ),
            (
                "src/agent/prompts/executor.md",
                include_str!("../../src/agent/prompts/executor.md"),
            ),
            (
                "src/agent/prompts/worktree_executor.md",
                include_str!("../../src/agent/prompts/worktree_executor.md"),
            ),
            (
                "src/agent/prompts/reviewer.md",
                include_str!("../../src/agent/prompts/reviewer.md"),
            ),
            (
                "src/agent/prompts/explorer.md",
                include_str!("../../src/agent/prompts/explorer.md"),
            ),
            (
                "src/agent/prompts/feishu.md",
                include_str!("../../src/agent/prompts/feishu.md"),
            ),
            (
                "assets/skills/subagent-workflow/SKILL.md",
                include_str!("../../assets/skills/subagent-workflow/SKILL.md"),
            ),
        ];
        Ok(Self {
            mode: String::new(),
            root_route_override: false,
            requested_seconds: 0,
            root: None,
            root_route: None,
            root_model_route: None,
            root_workflow: None,
            root_workflow_snapshot_revision: None,
            members: Vec::new(),
            workspace: None,
            workspace_location: None,
            started_at: unix_seconds()?,
            ended_at: 0,
            elapsed_millis: 0,
            termination: Termination::SetupError,
            evidence_complete: false,
            shutdown_observed: false,
            scenario_elapsed_millis: 0,
            cleanup_elapsed_millis: 0,
            cleanup_budget_expired: false,
            shutdown_elapsed_millis: 0,
            admitted_operations: Vec::new(),
            events: Vec::new(),
            writers_joined: 0,
            collected_bytes: 0,
            timeline_items: 0,
            thread_exports: Vec::new(),
            retired_owed_work: Vec::new(),
            prompt_sha256: String::new(),
            binary,
            compiled_sources: sources
                .into_iter()
                .map(|(path, text)| SourceIdentity {
                    path: path.into(),
                    bytes: text.len() as u64,
                    sha256: sha256(text.as_bytes()),
                })
                .collect(),
            issues: Vec::new(),
            unfinished: Vec::new(),
            file_index: "files.jsonl",
            limits: Limits {
                total_bytes: MAX_BYTES,
                threads: MAX_THREADS,
                timeline_items: MAX_ITEMS,
                decisions: 256,
                decision_bytes: 128 * 1024,
            },
        })
    }
}

struct HashWriter<'a>(&'a mut Sha256);
impl Write for HashWriter<'_> {
    fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
        self.0.update(bytes);
        Ok(bytes.len())
    }
    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

pub fn sha256(bytes: &[u8]) -> String {
    hex::encode(Sha256::digest(bytes))
}
pub fn unix_seconds() -> Result<i64> {
    Ok(SystemTime::now()
        .duration_since(UNIX_EPOCH)?
        .as_secs()
        .try_into()?)
}

#[derive(Clone)]
pub struct Evidence(Arc<Sink>);
struct Sink {
    root: PathBuf,
    bytes: AtomicU64,
    exhausted: AtomicBool,
    index: Mutex<File>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct FileRecord<'a> {
    path: &'a str,
    identity: &'a str,
    bytes: u64,
    sha256: String,
    complete: bool,
    mutable_after_capture: bool,
}

impl Evidence {
    pub fn new(root: PathBuf) -> Result<Self> {
        let index = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(root.join("files.jsonl"))?;
        Ok(Self(Arc::new(Sink {
            root,
            bytes: AtomicU64::new(0),
            exhausted: AtomicBool::new(false),
            index: Mutex::new(index),
        })))
    }
    pub fn root(&self) -> &Path {
        &self.0.root
    }
    pub fn bytes(&self) -> u64 {
        self.0.bytes.load(Ordering::Relaxed)
    }
    pub fn exhausted(&self) -> bool {
        self.0.exhausted.load(Ordering::Relaxed)
    }
    pub fn check_limit(&self, condition: bool, reason: &str) -> Result<()> {
        if !condition {
            self.0.exhausted.store(true, Ordering::Relaxed);
            anyhow::bail!("{reason}");
        }
        Ok(())
    }
    pub fn create(&self, relative: &str, identity: &str) -> Result<EvidenceFile> {
        let path = self.root().join(relative);
        // All relative names are generated indices/hashes, never opaque external IDs.
        if let Some(parent) = Path::new(relative).parent() {
            let mut current = self.root().to_path_buf();
            for component in parent.components() {
                let std::path::Component::Normal(component) = component else {
                    anyhow::bail!("evidence path must be relative ordinary components");
                };
                current.push(component);
                match std::fs::symlink_metadata(&current) {
                    Ok(metadata) => anyhow::ensure!(
                        metadata.is_dir() && !metadata.file_type().is_symlink(),
                        "evidence parent must be an ordinary directory"
                    ),
                    Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                        std::fs::create_dir(&current)?
                    }
                    Err(error) => return Err(error.into()),
                }
            }
        }
        let file = OpenOptions::new().write(true).create_new(true).open(path)?;
        Ok(EvidenceFile {
            file,
            sink: self.clone(),
            path: relative.into(),
            identity: identity.into(),
            hasher: Sha256::new(),
            bytes: 0,
        })
    }
    pub fn json(&self, relative: &str, identity: &str, value: &impl Serialize) -> Result<()> {
        let mut file = self.create(relative, identity)?;
        let result = serde_json::to_writer_pretty(&mut file, value);
        let finish = file.finish(result.is_ok());
        combine_write_result(result.map_err(Into::into), finish, relative)?;
        Ok(())
    }
    pub fn raw(&self, relative: &str, identity: &str, bytes: &[u8]) -> Result<()> {
        let mut file = self.create(relative, identity)?;
        let result = file.write_all(bytes);
        let finish = file.finish(result.is_ok());
        combine_write_result(result.map_err(Into::into), finish, relative)?;
        Ok(())
    }
    fn reserve(&self, bytes: usize) -> std::io::Result<()> {
        // This counter only reserves capacity; no data publication relies on its ordering.
        if self
            .0
            .bytes
            .try_update(Ordering::Relaxed, Ordering::Relaxed, |used| {
                used.checked_add(bytes as u64)
                    .filter(|next| *next <= MAX_BYTES - SUMMARY_RESERVE)
            })
            .is_err()
        {
            self.0.exhausted.store(true, Ordering::Relaxed);
            return Err(std::io::Error::other("evidence byte budget exceeded"));
        }
        Ok(())
    }
    pub fn check_disk_budget(&self) -> Result<()> {
        // Studio owns its own DB/provider outputs: sample their real size as well as limiting all
        // collector writes. Symlinks are not followed, including in caller-provided fixtures.
        let mut pending = vec![self.root().to_path_buf()];
        let mut total = 0u64;
        let mut entries = 0usize;
        while let Some(directory) = pending.pop() {
            for entry in std::fs::read_dir(directory)? {
                let entry = entry?;
                entries += 1;
                self.check_limit(
                    entries <= 100_000,
                    "artifact directory entry budget exceeded",
                )?;
                let metadata = std::fs::symlink_metadata(entry.path())?;
                if metadata.is_dir() {
                    pending.push(entry.path());
                } else {
                    total = total
                        .checked_add(metadata.len())
                        .context("artifact size overflow")?;
                }
                if total > MAX_BYTES - SUMMARY_RESERVE {
                    self.0.exhausted.store(true, Ordering::Relaxed);
                    anyhow::bail!("artifact disk budget exceeded");
                }
            }
        }
        Ok(())
    }
    pub fn finish(&self, manifest: &Manifest) -> Result<()> {
        self.0
            .index
            .lock()
            .map_err(|_| anyhow::anyhow!("file index lock poisoned"))?
            .sync_all()?;
        // A separate bounded reserve keeps the failure summary writable after evidence exhaustion.
        let bytes = serde_json::to_vec_pretty(manifest)?;
        anyhow::ensure!(
            bytes.len() as u64 <= SUMMARY_RESERVE,
            "manifest exceeds summary reserve"
        );
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(self.root().join("manifest.json"))?;
        file.write_all(&bytes)?;
        file.sync_all()?;
        Ok(())
    }
}

fn combine_write_result(result: Result<()>, finish: Result<()>, path: &str) -> Result<()> {
    match (result, finish) {
        (Err(error), Err(finish)) => {
            Err(error.context(format!("{path}; also finishing failed: {finish:#}")))
        }
        (Err(error), _) | (_, Err(error)) => Err(error.context(path.to_owned())),
        _ => Ok(()),
    }
}

pub struct EvidenceFile {
    file: File,
    sink: Evidence,
    path: String,
    identity: String,
    hasher: Sha256,
    bytes: u64,
}
impl Write for EvidenceFile {
    fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
        self.sink.reserve(bytes.len())?;
        let written = self.file.write(bytes)?;
        self.hasher.update(&bytes[..written]);
        self.bytes += written as u64;
        Ok(written)
    }
    fn flush(&mut self) -> std::io::Result<()> {
        self.file.flush()
    }
}
impl EvidenceFile {
    pub fn finish(mut self, complete: bool) -> Result<()> {
        self.file.flush()?;
        let record = FileRecord {
            path: &self.path,
            identity: &self.identity,
            bytes: self.bytes,
            sha256: hex::encode(self.hasher.finalize()),
            complete,
            mutable_after_capture: self.path.starts_with("studio-home/"),
        };
        let mut bytes = serde_json::to_vec(&record)?;
        bytes.push(b'\n');
        // The index is also charged; failure remains visible in the manifest even if full.
        self.sink.reserve(bytes.len())?;
        let mut index = self
            .sink
            .0
            .index
            .lock()
            .map_err(|_| anyhow::anyhow!("file index lock poisoned"))?;
        index.write_all(&bytes)?;
        index.flush()?;
        Ok(())
    }
}

impl EventWriter {
    pub fn start(
        mut stream: pl_studio_runtime::StudioThreadSubscription,
        sink: &Evidence,
        id: &str,
        index: usize,
    ) -> Result<Self> {
        let mut file = sink.create(&format!("threads/{index:03}/events.jsonl"), id)?;
        let progress = Arc::new(Mutex::new(EventProgress {
            coverage: EventCoverage {
                thread_id: id.into(),
                initial_snapshot_revision: None,
                consumed_last: None,
                target: None,
                matched_at: None,
                join_elapsed_millis: 0,
                stream_ended: false,
                complete: false,
                error: None,
                source: "liveOrRetainedPublicApiCannotDistinguish",
            },
            anchors: Default::default(),
            eof: false,
        }));
        let (pulse, changed) = tokio::sync::watch::channel(0u64);
        let (target, mut targets) = tokio::sync::watch::channel::<Option<TurnAnchor>>(None);
        let stop = tokio_util::sync::CancellationToken::new();
        let worker_progress = progress.clone();
        let worker_stop = stop.clone();
        let handle = tokio::spawn(async move {
            let result: Result<()> = async {
                loop {
                    if let Some(anchor) = targets.borrow().clone() {
                        let key = anchor.key();
                        let mut state = worker_progress.lock().map_err(|_| anyhow::anyhow!("event progress poisoned"))?;
                        if state.coverage.initial_snapshot_revision.is_some() && state.coverage.error.is_none()
                            && let Some((terminal_state, watermark)) = state.anchors.get(&key).cloned()
                            && terminal_state == anchor.terminal_state {
                            state.coverage.target = Some(anchor);
                            state.coverage.matched_at = Some(watermark);
                            state.coverage.complete = true;
                            break;
                        }
                        state.coverage.target = Some(anchor);
                        anyhow::ensure!(!state.eof, "event stream ended before the requested terminal anchor");
                    }
                    if worker_progress.lock().map_err(|_| anyhow::anyhow!("event progress poisoned"))?.eof {
                        // EOF after a cached anchor does not erase that already consumed prefix.
                        // Wait only for a declared target (or bounded cleanup cancellation), never
                        // infer completeness from EOF itself.
                        tokio::select! { _ = worker_stop.cancelled() => break,
                            changed = targets.changed() => { changed.context("event target control closed")?; continue; } }
                    }
                    // recv owns only observation state. Cancellation may discard an unclaimed tail,
                    // never resources or a decision. Only an already confirmed prefix is complete.
                    let has_baseline = worker_progress.lock().map_err(|_| anyhow::anyhow!("event progress poisoned"))?.coverage.initial_snapshot_revision.is_some();
                    let event = tokio::select! {
                        _ = worker_stop.cancelled() => break,
                        // First-frame assembly takes its baseline before awaiting usage. A target
                        // wake must not cancel that assembly and destroy the initial snapshot.
                        changed = targets.changed(), if has_baseline => { changed.context("event target control closed")?; continue; },
                        event = stream.recv() => event?,
                    };
                    let Some(event) = event else {
                        let mut state = worker_progress.lock().map_err(|_| anyhow::anyhow!("event progress poisoned"))?;
                        state.eof = true; state.coverage.stream_ended = true;
                        drop(state);
                        pulse.send_modify(|value| *value = value.saturating_add(1));
                        continue;
                    };
                    serde_json::to_writer(&mut file, &event)?;
                    file.write_all(b"\n")?;
                    file.flush()?;
                    {
                        let mut state = worker_progress.lock().map_err(|_| anyhow::anyhow!("event progress poisoned"))?;
                        match event {
                            pl_protocol::ThreadSubscriptionUpdate::Snapshot { snapshot } => {
                                anyhow::ensure!(state.coverage.initial_snapshot_revision.is_none(), "unexpected second event baseline");
                                state.coverage.initial_snapshot_revision = Some(snapshot.revision);
                            }
                            pl_protocol::ThreadSubscriptionUpdate::Notification { notification } => {
                                let baseline = state.coverage.initial_snapshot_revision.context("notification before first snapshot")?;
                                let previous = state.coverage.consumed_last;
                                anyhow::ensure!(notification.base_revision == previous.map_or(baseline, |last| last.revision)
                                    && notification.base_revision.checked_add(1) == Some(notification.revision)
                                    && previous.is_none_or(|last| last.epoch == notification.epoch), "event revision/epoch gap");
                                anyhow::ensure!(!matches!(notification.notification, pl_protocol::ThreadNotification::Lagged { .. }), "event stream reported lag");
                                let watermark = StreamWatermark { epoch: notification.epoch, revision: notification.revision };
                                state.coverage.consumed_last = Some(watermark);
                                if let pl_protocol::ThreadNotification::TurnCompleted { turn } | pl_protocol::ThreadNotification::TurnUpdated { turn } = notification.notification
                                    && turn.state.is_terminal() {
                                    let key = TurnAnchor::from_turn(&turn)?.key();
                                    anyhow::ensure!(state.anchors.contains_key(&key) || state.anchors.len() < 1024, "terminal anchor cache budget exceeded (1024)");
                                    if let Some((previous, _)) = state.anchors.get(&key) { anyhow::ensure!(previous == &turn.state, "terminal Turn changed without revision"); }
                                    state.anchors.entry(key).or_insert((turn.state, watermark));
                                }
                            }
                        }
                    }
                    pulse.send_modify(|value| *value = value.saturating_add(1));
                }
                Ok(())
            }.await;
            drop(stream);
            let complete = {
                let mut state = worker_progress
                    .lock()
                    .map_err(|_| anyhow::anyhow!("event progress poisoned"))?;
                if let Err(error) = &result {
                    state.coverage.error = Some(format!("{error:#}"));
                }
                if !state.coverage.complete && state.coverage.error.is_none() {
                    state.coverage.error =
                        Some("observation stopped before confirmed terminal anchor".into());
                }
                state.coverage.complete && result.is_ok()
            };
            pulse.send_modify(|value| *value = value.saturating_add(1));
            let finish = file.finish(complete);
            combine_write_result(result, finish, "event writer")
        });
        Ok(Self {
            thread_id: id.into(),
            progress,
            changed,
            stop,
            target,
            handle,
        })
    }
    pub fn failure(&self) -> Result<Option<String>> {
        Ok(self
            .progress
            .lock()
            .map_err(|_| anyhow::anyhow!("event progress poisoned"))?
            .coverage
            .error
            .clone())
    }
    pub async fn finish(
        mut self,
        target: Result<TurnAnchor>,
        budget: &super::Boundary,
    ) -> Result<EventCoverage> {
        let mut failure = budget
            .check()
            .err()
            .map(|error| format!("coverage declaration: {error:#}"));
        match target {
            Ok(anchor) if failure.is_none() => {
                self.target.send_replace(Some(anchor));
            }
            Ok(_) => (),
            Err(error) => failure = Some(format!("terminal anchor unavailable: {error:#}")),
        }
        while failure.is_none() {
            if let Err(error) = budget.check() {
                failure = Some(format!("event coverage budget: {error:#}"));
                break;
            }
            {
                match self.progress.lock() {
                    Ok(state) => {
                        if state.coverage.complete {
                            break;
                        }
                        if state.coverage.error.is_some() {
                            failure = Some(
                                state
                                    .coverage
                                    .error
                                    .clone()
                                    .unwrap_or_else(|| "premature EOF".into()),
                            );
                        }
                    }
                    Err(_) => failure = Some("event progress poisoned".into()),
                }
            }
            if failure.is_none()
                && let Err(error) = budget
                    .read(async {
                        self.changed
                            .changed()
                            .await
                            .context("event writer ended before confirmation")
                    })
                    .await
            {
                failure = Some(format!("event coverage wait: {error:#}"));
            }
        }
        if failure.is_some() {
            self.stop.cancel();
        }
        // Never put this handle into a timeout or drop it: this is the actual writer exit and flush.
        let joining = std::time::Instant::now();
        let joined = self.handle.await;
        let mut state = self
            .progress
            .lock()
            .map_err(|_| anyhow::anyhow!("event progress poisoned"))?;
        state.coverage.join_elapsed_millis = joining.elapsed().as_millis();
        if let Some(error) = failure {
            state.coverage.complete = false;
            state.coverage.error = Some(error);
        }
        match joined {
            Ok(Ok(())) => (),
            Ok(Err(error)) => {
                state.coverage.complete = false;
                state.coverage.error = Some(format!("writer: {error:#}"));
            }
            Err(error) => {
                state.coverage.complete = false;
                state.coverage.error = Some(format!("writer join: {error}"));
            }
        }
        Ok(state.coverage.clone())
    }
}
