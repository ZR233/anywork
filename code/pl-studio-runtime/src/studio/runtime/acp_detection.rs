//! A single, memory-only local CLI probe slot.
//!
//! Admission, cancellation and publication share one lock. The slot owns the
//! supervisor join and physical resources, including after a cancelled waiter.
//! Neither reads nor construction touch the executable or filesystem.

mod probe;

use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};

use crate::{
    AcpLocalDetectionFailure, AcpLocalDetectionFailureKind, AcpLocalDetectionSnapshot,
    AcpLocalDetectionState, CancelAcpLocalDetectionRequest, StartAcpLocalDetectionRequest,
    StudioError, StudioErrorCode,
};
use anyhow::Result;
use futures::FutureExt;
use tokio::sync::Mutex as AsyncMutex;
use tokio_util::sync::CancellationToken;

use super::acp_ops::{RetainedJoin, RetainedPoll, RetainedTask};
use super::acp_worker::{AcpWorker, PROCESS_CLEANUP_LIMIT, Reclaim};
use crate::studio::{ProductEventBus, StudioStore};
use pl_remote_helper::Executor;

#[derive(Clone)]
pub(crate) struct AcpLocalDetectionRuntime {
    inner: Arc<Inner>,
}

pub(crate) type AcpLocalDetectionAcceptance =
    super::acp_ops::TopicAcceptance<AcpLocalDetectionSnapshot>;

struct Inner {
    store: StudioStore,
    events: ProductEventBus,
    source: Executor,
    slot: Mutex<Slot>,
    /// Test-only launch inputs, never a process-global PATH or user config edit.
    #[cfg(test)]
    fixture_definition: Mutex<Option<crate::config::AcpServiceDefinition>>,
    /// Synchronous stand-in for an observer that re-enters admission during emit.
    #[cfg(test)]
    emit_probe: Mutex<Option<Arc<dyn Fn() + Send + Sync>>>,
}

struct Slot {
    closed: bool,
    snapshot: AcpLocalDetectionSnapshot,
    operation: Option<Arc<Operation>>,
}

struct Operation {
    id: String,
    cancel: CancellationToken,
    deadline: tokio::time::Instant,
    join: RetainedTask<()>,
    resources: AsyncMutex<Resources>,
    resources_released: AtomicBool,
    /// Thin fault assembly around real resources; production has no such gates.
    #[cfg(test)]
    cleanup_pause: Mutex<Option<CancellationToken>>,
    #[cfg(test)]
    cleanup_pending: AtomicBool,
}

#[derive(Default)]
struct Resources {
    worker: Option<AcpWorker>,
    /// Owned empty probe cwd, never an account/workspace directory.
    directory: Option<PathBuf>,
}

impl AcpLocalDetectionRuntime {
    pub(crate) fn new(store: StudioStore, events: ProductEventBus, executor: Executor) -> Self {
        Self {
            inner: Arc::new(Inner {
                store,
                events,
                source: executor,
                slot: Mutex::new(Slot {
                    closed: false,
                    snapshot: AcpLocalDetectionSnapshot {
                        revision: 0,
                        operation_id: None,
                        state: AcpLocalDetectionState::Idle,
                    },
                    operation: None,
                }),
                #[cfg(test)]
                fixture_definition: Mutex::new(None),
                #[cfg(test)]
                emit_probe: Mutex::new(None),
            }),
        }
    }

    #[cfg(test)]
    fn set_emit_probe(&self, probe: impl Fn() + Send + Sync + 'static) {
        *self
            .inner
            .emit_probe
            .lock()
            .unwrap_or_else(PoisonError::into_inner) = Some(Arc::new(probe));
    }

    #[cfg(test)]
    fn publish_checking_for_probe(&self) {
        let mut admission = Published::lock(&self.inner);
        admission.assign(AcpLocalDetectionState::Checking);
    }

    pub(crate) fn read_state(&self) -> AcpLocalDetectionSnapshot {
        self.inner.lock().snapshot.clone()
    }

    pub(crate) fn start(
        &self,
        request: StartAcpLocalDetectionRequest,
    ) -> Result<AcpLocalDetectionAcceptance> {
        super::StudioRuntime::validate_operation_id(&request.operation_id)?;
        let mut admission = Published::lock(&self.inner);
        if admission.slot().closed {
            return Err(command_error(
                StudioErrorCode::RuntimeStopped,
                "运行时正在关闭，不能开始本机检测",
            ));
        }
        if admission.slot().snapshot.operation_id.as_deref() == Some(request.operation_id.as_str())
        {
            return Ok(acceptance(admission.slot(), false));
        }
        // Poll only a finished join, by reference, before recycling the one slot.
        // Completion of the domain state alone is not evidence of task termination.
        let existing = admission.slot().operation.clone();
        if let Some(operation) = existing {
            match operation.join.poll_finished() {
                RetainedPoll::Pending => return Err(busy()),
                RetainedPoll::Observed(outcome) => {
                    if outcome.is_err() {
                        admission.assign(failed(AcpLocalDetectionFailureKind::Cleanup));
                    }
                }
                RetainedPoll::Idle => {}
            }
            if !operation.resources_released.load(Ordering::Acquire) {
                return Err(busy());
            }
            admission.slot().operation = None;
        }

        let operation = Arc::new(Operation {
            id: request.operation_id,
            cancel: CancellationToken::new(),
            deadline: tokio::time::Instant::now() + std::time::Duration::from_secs(10),
            join: RetainedTask::empty(),
            resources: AsyncMutex::new(Resources::default()),
            resources_released: AtomicBool::new(false),
            #[cfg(test)]
            cleanup_pause: Mutex::new(None),
            #[cfg(test)]
            cleanup_pending: AtomicBool::new(false),
        });
        admission.slot().snapshot.operation_id = Some(operation.id.clone());
        admission.slot().operation = Some(Arc::clone(&operation));
        admission.assign(AcpLocalDetectionState::Checking);
        // Responsibility is visible before spawn, with no intervening await.
        let task = tokio::spawn(supervise(Arc::clone(&self.inner), Arc::clone(&operation)));
        operation.join.install(task);
        Ok(acceptance(admission.slot(), true))
    }

    pub(crate) fn cancel(
        &self,
        request: CancelAcpLocalDetectionRequest,
    ) -> Result<AcpLocalDetectionAcceptance> {
        super::StudioRuntime::validate_operation_id(&request.operation_id)?;
        super::StudioRuntime::validate_operation_id(&request.target_operation_id)?;
        let mut admission = Published::lock(&self.inner);
        if admission.slot().snapshot.operation_id.as_deref()
            != Some(request.target_operation_id.as_str())
        {
            return Err(command_error(
                StudioErrorCode::Conflict,
                "检测操作已被替换，不能取消另一操作",
            ));
        }
        if request.operation_id == request.target_operation_id {
            return Err(command_error(
                StudioErrorCode::Conflict,
                "取消命令必须使用独立的 operationId",
            ));
        }
        if !matches!(
            admission.slot().snapshot.state,
            AcpLocalDetectionState::Checking | AcpLocalDetectionState::Cancelling
        ) {
            return Ok(acceptance(admission.slot(), false));
        }
        if let Some(operation) = &admission.slot().operation {
            operation.cancel.cancel();
        }
        let changed = admission.slot().snapshot.state != AcpLocalDetectionState::Cancelling;
        if changed {
            admission.assign(AcpLocalDetectionState::Cancelling);
        }
        Ok(acceptance(admission.slot(), changed))
    }

    /// Synchronous shutdown gate, before waiting for sibling resource owners.
    pub(crate) fn signal_cancel(&self) {
        let mut admission = Published::lock(&self.inner);
        admission.slot().closed = true;
        let operation = admission.slot().operation.clone();
        if let Some(operation) = operation {
            operation.cancel.cancel();
            if admission.slot().snapshot.state == AcpLocalDetectionState::Checking {
                admission.assign(AcpLocalDetectionState::Cancelling);
            }
        }
    }

    /// Close admission and borrow the retained join. A timed-out/dropped waiter
    /// leaves this same owner available to the existing shutdown retry.
    pub(crate) async fn close(&self) -> Result<()> {
        self.signal_cancel();
        let operation = self.inner.lock().operation.clone();
        let Some(operation) = operation else {
            return Ok(());
        };
        let deadline = tokio::time::Instant::now() + PROCESS_CLEANUP_LIMIT;
        let joined = operation.join.join_until(deadline).await;
        if matches!(joined, RetainedJoin::TimedOut) {
            anyhow::bail!("本机检测任务仍在收束，保留原 owner 待重试");
        }
        // Even a panicked task leaves its physical worker in Operation.resources.
        let cleaned = release_resources(&operation).await;
        // Report a join failure when it is first observed. Retrying still has to prove
        // resource cleanup, even when the original handle has already been consumed.
        if matches!(joined, RetainedJoin::Observed(Err(_))) || !cleaned {
            self.inner
                .finish(&operation, failed(AcpLocalDetectionFailureKind::Cleanup));
            anyhow::bail!("本机检测资源收束失败，请重试关闭");
        }
        Ok(())
    }
}

impl Inner {
    fn lock(&self) -> MutexGuard<'_, Slot> {
        self.slot.lock().unwrap_or_else(PoisonError::into_inner)
    }

    fn emit_snapshots(&self, snapshots: Vec<AcpLocalDetectionSnapshot>) {
        for snapshot in snapshots {
            #[cfg(test)]
            self.run_emit_probe();
            self.events.emit(
                crate::StudioProductEventKind::AcpLocalDetectionStateChanged(Box::new(snapshot)),
            );
        }
    }

    #[cfg(test)]
    fn run_emit_probe(&self) {
        let probe = self
            .emit_probe
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .clone();
        if let Some(probe) = probe {
            probe();
        }
    }

    fn finish(&self, operation: &Arc<Operation>, state: AcpLocalDetectionState) {
        let mut admission = Published::lock(self);
        if !admission
            .slot()
            .operation
            .as_ref()
            .is_some_and(|current| Arc::ptr_eq(current, operation))
        {
            return;
        }
        let state = if operation.cancel.is_cancelled()
            && !matches!(state, AcpLocalDetectionState::Failed { .. })
        {
            AcpLocalDetectionState::Cancelled
        } else {
            state
        };
        admission.assign(state);
    }
}

/// Updates admission under `slot`, then emits only after that lock is released.
struct Published<'a> {
    inner: &'a Inner,
    slot: Option<MutexGuard<'a, Slot>>,
    snapshots: Vec<AcpLocalDetectionSnapshot>,
}

impl<'a> Published<'a> {
    fn lock(inner: &'a Inner) -> Self {
        Self {
            inner,
            slot: Some(inner.lock()),
            snapshots: Vec::new(),
        }
    }

    fn slot(&mut self) -> &mut Slot {
        self.slot.as_mut().expect("detection admission slot")
    }

    fn assign(&mut self, state: AcpLocalDetectionState) {
        let snapshot = {
            let slot = self.slot();
            slot.snapshot.state = state;
            slot.snapshot.revision += 1;
            slot.snapshot.clone()
        };
        self.snapshots.push(snapshot);
    }
}

impl Drop for Published<'_> {
    fn drop(&mut self) {
        self.slot.take();
        self.inner
            .emit_snapshots(std::mem::take(&mut self.snapshots));
    }
}

async fn supervise(inner: Arc<Inner>, operation: Arc<Operation>) {
    let outcome = std::panic::AssertUnwindSafe(probe::run(&inner, &operation))
        .catch_unwind()
        .await;
    let state = outcome.unwrap_or_else(|_| failed(AcpLocalDetectionFailureKind::Execution));
    let cleaned = release_resources(&operation).await;
    inner.finish(
        &operation,
        if cleaned {
            state
        } else {
            failed(AcpLocalDetectionFailureKind::Cleanup)
        },
    );
}

async fn release_resources(operation: &Operation) -> bool {
    #[cfg(test)]
    {
        let pause = operation
            .cleanup_pause
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .clone();
        if let Some(pause) = pause {
            pause.cancelled().await;
        }
        if operation.cleanup_pending.load(Ordering::Acquire) {
            return false;
        }
    }
    let mut resources = operation.resources.lock().await;
    let mut succeeded = true;
    if let Some(worker) = resources.worker.as_mut() {
        match tokio::time::timeout(PROCESS_CLEANUP_LIMIT, worker.reclaim()).await {
            Ok(Reclaim::Stopped) => resources.worker = None,
            Ok(Reclaim::Settled(_)) => {
                resources.worker = None;
                succeeded = false;
            }
            Ok(Reclaim::Pending(_)) | Err(_) => return false,
        }
    }
    if let Some(directory) = &resources.directory {
        match std::fs::remove_dir_all(directory) {
            Ok(()) => resources.directory = None,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                resources.directory = None;
            }
            Err(_) => return false,
        }
    }
    operation.resources_released.store(true, Ordering::Release);
    succeeded
}

fn acceptance(slot: &Slot, changed: bool) -> AcpLocalDetectionAcceptance {
    AcpLocalDetectionAcceptance {
        snapshot: slot.snapshot.clone(),
        changed,
    }
}

fn busy() -> anyhow::Error {
    command_error(
        StudioErrorCode::Busy,
        "已有本机检测操作或资源尚未收束，请等待后重新检测",
    )
}

fn command_error(code: StudioErrorCode, message: &str) -> anyhow::Error {
    StudioError::new(code, message, code == StudioErrorCode::Busy).into()
}

fn failed(kind: AcpLocalDetectionFailureKind) -> AcpLocalDetectionState {
    let message = match kind {
        AcpLocalDetectionFailureKind::Timeout => "本机检测超过 10 秒，请检查程序后重新检测",
        AcpLocalDetectionFailureKind::OutputLimit => {
            "本机检测输出超过 64 KiB，请检查程序后重新检测"
        }
        AcpLocalDetectionFailureKind::Execution => "无法完成本机检测，请检查程序是否可运行",
        AcpLocalDetectionFailureKind::Cleanup => "本机检测资源未正常收束，请重试关闭",
    };
    AcpLocalDetectionState::Failed {
        failure: AcpLocalDetectionFailure {
            kind,
            message: message.into(),
        },
    }
}

#[cfg(all(test, target_os = "linux"))]
mod tests {
    //! Linux boundary tests: only the executable/launch environment and explicit
    //! cleanup fault gates are synthetic. Runtime commands, save, topic baseline,
    //! event delivery, launch resolution and ManagedWorker are production paths.

    use std::os::unix::fs::PermissionsExt;
    use std::path::{Path, PathBuf};
    use std::time::Duration;

    use crate::{
        AcpAccountUpdate, AcpLocalDetectionFailureKind as FailureKind,
        AcpLocalDetectionState as State, UpdateAcpAccountRequest,
    };
    use anyhow::Result;
    use serde::Deserialize;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tokio::time::timeout;

    use super::*;
    use crate::config::{AcpLaunch, AcpServiceDefinition};
    use crate::{
        StudioHostKind, StudioProductBaselineState, StudioProductEventKind, StudioProductFrame,
        StudioProductTopic, StudioRuntime, StudioRuntimeOptions,
    };

    const FIXTURE: &str = r#"#!/usr/bin/python3
import json, os, pathlib, socket, subprocess, sys
root = pathlib.Path(os.environ['DETECTION_FIXTURE_ROOT'])
mode = (root / 'mode').read_text()
args = sys.argv[1:]
assert args in [['--version'], ['acp', '--help']], args
child = None
gate = socket.create_connection(('127.0.0.1', int(os.environ['DETECTION_FIXTURE_GATE'])))
if mode == 'hang' and args == ['acp', '--help']:
    child = subprocess.Popen(
        [sys.executable, '-c',
         'import socket,sys; socket.socket(fileno=int(sys.argv[1])).recv(1)',
         str(gate.fileno())], pass_fds=(gate.fileno(),))
with (root / 'calls').open('a') as log:
    log.write(json.dumps({'args': args, 'pid': os.getpid(),
                         'child': child.pid if child else None,
                         'cwd': os.getcwd()}) + '\n')
    log.flush()
gate.sendall(os.getpid().to_bytes(4, 'little'))
if mode == 'deadline':
    assert gate.recv(1) == b'x'
if child:
    child.wait()
if args == ['--version']:
    sys.stdout.write('1.5.4\n')
    if mode == 'version-fail':
        sys.exit(7)
    if mode == 'combined':
        sys.stdout.write('x' * 20000)
        sys.stderr.write('y' * 13000)
else:
    if mode == 'unsupported':
        sys.stderr.write("error: unknown command 'acp'\n")
        sys.exit(2)
    if mode == 'help-fail':
        sys.stderr.write('private-diagnostic-not-for-ui\n')
        sys.exit(9)
    if mode == 'root-help':
        sys.stdout.write('Usage: agy [options] [command]\nCommands:\n  acp  Agent Client Protocol\n')
    else:
        help_text = 'Usage: agy acp [flags]\n'
        if mode == 'multiline-help':
            sys.stdout.write('Usage:\n  agy acp [flags]\n')
        elif mode == 'stderr-help':
            sys.stderr.write(help_text)
        else:
            sys.stdout.write(help_text)
        if mode == 'combined':
            sys.stdout.write('x' * 20000)
            sys.stderr.write('y' * 13000)
        if mode in ['exact-limit', 'over-limit']:
            sys.stderr.write('z' * (65536 - len('1.5.4\n') - len(help_text)
                                   + (1 if mode == 'over-limit' else 0)))
sys.stdout.flush()
sys.stderr.flush()
"#;

    #[derive(Debug, Deserialize)]
    struct Call {
        args: Vec<String>,
        pid: u32,
        child: Option<u32>,
        cwd: PathBuf,
    }

    struct Fixture {
        runtime: StudioRuntime,
        home: tempfile::TempDir,
        program: PathBuf,
        gate: tokio::net::TcpListener,
        launched: AsyncMutex<Vec<(u32, tokio::net::TcpStream)>>,
    }

    impl Fixture {
        async fn new(mode: &str) -> Result<Self> {
            let home = tempfile::tempdir()?;
            let gate = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
            let bin = home.path().join("bin");
            std::fs::create_dir(&bin)?;
            let program = bin.join("agy");
            std::fs::write(&program, FIXTURE)?;
            std::fs::set_permissions(&program, std::fs::Permissions::from_mode(0o700))?;
            std::fs::write(home.path().join("mode"), mode)?;
            let runtime = StudioRuntime::initialize(StudioRuntimeOptions {
                studio_home: Some(home.path().join("studio-home")),
                host: StudioHostKind::Test,
                skill_search: pl_tool::skill::SkillSearchOptions {
                    include_default_user_dir: false,
                    additional_dirs: Vec::new(),
                },
                ..StudioRuntimeOptions::desktop()
            })
            .await?;
            let isolated = home.path().join("cli-home");
            std::fs::create_dir(&isolated)?;
            let mut env = std::collections::BTreeMap::from([
                ("PATH".into(), bin.to_string_lossy().into_owned()),
                (
                    "DETECTION_FIXTURE_ROOT".into(),
                    home.path().to_string_lossy().into_owned(),
                ),
                (
                    "DETECTION_FIXTURE_GATE".into(),
                    gate.local_addr()?.port().to_string(),
                ),
            ]);
            for key in [
                "HOME",
                "XDG_CONFIG_HOME",
                "XDG_DATA_HOME",
                "XDG_CACHE_HOME",
                "XDG_STATE_HOME",
                "XDG_RUNTIME_DIR",
            ] {
                env.insert(key.into(), isolated.to_string_lossy().into_owned());
            }
            *runtime
                .acp_detection
                .inner
                .fixture_definition
                .lock()
                .unwrap() = Some(AcpServiceDefinition {
                id: "synthetic-detection".into(),
                display_name: "Synthetic detection".into(),
                enabled: true,
                launch: AcpLaunch::Command {
                    command: "agy".into(),
                    args: Vec::new(),
                },
                env,
            });
            Ok(Self {
                runtime,
                home,
                program,
                gate,
                launched: AsyncMutex::new(Vec::new()),
            })
        }

        fn mode(&self, mode: &str) {
            std::fs::write(self.home.path().join("mode"), mode).unwrap();
        }

        fn calls(&self) -> Vec<Call> {
            std::fs::read_to_string(self.home.path().join("calls"))
                .unwrap_or_default()
                .lines()
                .map(|line| serde_json::from_str(line).unwrap())
                .collect()
        }

        fn start(&self, id: &str) -> crate::AcpLocalDetectionCommandReply {
            self.runtime
                .start_acp_local_detection(StartAcpLocalDetectionRequest {
                    operation_id: id.into(),
                })
                .unwrap()
        }

        fn operation(&self) -> Arc<Operation> {
            self.runtime
                .acp_detection
                .inner
                .lock()
                .operation
                .clone()
                .unwrap()
        }

        async fn launch_notification(&self) -> Result<(u32, tokio::net::TcpStream)> {
            let (mut connection, _) = self.gate.accept().await?;
            let pid = connection.read_u32_le().await?;
            Ok((pid, connection))
        }

        async fn calls_reached(&self, count: usize) {
            timeout(Duration::from_secs(5), async {
                let mut launched = self.launched.lock().await;
                while launched.len() < count {
                    launched.push(
                        self.launch_notification()
                            .await
                            .expect("CLI launch notification"),
                    );
                }
                assert_eq!(self.calls().len(), count);
            })
            .await
            .expect("fixture must be launched through the real worker");
        }

        async fn terminal(&self) -> State {
            timeout(Duration::from_secs(18), async {
                let operation = self.operation();
                match operation.join.join().await {
                    RetainedJoin::Observed(result) => {
                        result.expect("the original detection owner finishes");
                    }
                    RetainedJoin::Settled(Ok(())) | RetainedJoin::Absent => {}
                    RetainedJoin::Settled(Err(error)) => {
                        panic!("the original detection owner finishes: {error}")
                    }
                    RetainedJoin::TimedOut => unreachable!("unbounded join has no deadline"),
                }
                let state = self.runtime.read_acp_local_detection_state().state;
                assert!(!matches!(state, State::Checking | State::Cancelling));
                state
            })
            .await
            .expect("probe and physical cleanup must finish")
        }

        async fn finish(&self) {
            self.runtime.shutdown_runtime().await.unwrap();
            let stopped = self
                .runtime
                .start_acp_local_detection(StartAcpLocalDetectionRequest {
                    operation_id: "after-shutdown".into(),
                })
                .unwrap_err();
            assert_eq!(
                stopped.downcast_ref::<StudioError>().unwrap().code,
                StudioErrorCode::RuntimeStopped
            );
            let operation = self.operation();
            assert!(operation.join.slot_is_empty().await, "join must be reaped");
            let resources = operation.resources.lock().await;
            assert!(resources.worker.is_none());
            assert!(resources.directory.is_none());
            self.assert_reclaimed().await;
        }

        async fn assert_reclaimed(&self) {
            let stopped = timeout(Duration::from_secs(5), async {
                let mut launched = self.launched.lock().await;
                for (_, connection) in launched.iter_mut() {
                    let mut byte = [0];
                    assert_eq!(connection.read(&mut byte).await.unwrap(), 0);
                }
                launched.iter().map(|(pid, _)| *pid).collect::<Vec<_>>()
            })
            .await
            .expect("root and descendant must both close their inherited notification socket");
            let probe_root = self
                .runtime
                .acp_detection
                .inner
                .store
                .paths()
                .acp_probe_root();
            for call in self.calls() {
                assert!(
                    call.cwd.starts_with(&probe_root),
                    "probe cwd must belong to StudioStore"
                );
                assert!(!call.cwd.exists(), "probe cwd must outlive only its worker");
                assert!(!Path::new(&format!("/proc/{}", call.pid)).exists());
                if let Some(pid) = call.child {
                    // The descendant only blocks on this inherited socket. EOF proves
                    // it stopped, independently of its system parent's zombie reaping.
                    assert!(stopped.contains(&call.pid), "unobserved descendant {pid}");
                }
            }
        }
    }

    impl Drop for Fixture {
        fn drop(&mut self) {
            // Failure unwinding must not deliberately leave a fault gate armed.
            if let Some(operation) = self.runtime.acp_detection.inner.lock().operation.clone() {
                operation.cleanup_pending.store(false, Ordering::Release);
                if let Some(pause) = operation.cleanup_pause.lock().unwrap().as_ref() {
                    pause.cancel();
                }
                operation.cancel.cancel();
            }
        }
    }

    fn assert_failure(state: State, expected: FailureKind) {
        let State::Failed { failure } = state else {
            panic!("expected {expected:?}, got {state:?}");
        };
        assert_eq!(failure.kind, expected);
        assert!(!failure.message.contains("private-diagnostic"));
    }

    #[tokio::test]
    async fn runtime_baseline_reads_are_inert_and_available_can_save_normal_command() -> Result<()>
    {
        let fixture = Fixture::new("available").await?;
        for _ in 0..3 {
            assert_eq!(
                fixture.runtime.read_acp_local_detection_state().state,
                State::Idle
            );
            let mut subscription = fixture
                .runtime
                .subscribe_product_topic(StudioProductTopic::AcpLocalDetection)
                .await?;
            let Some(StudioProductFrame::Baseline(baseline)) = subscription.recv().await? else {
                panic!("typed baseline is required");
            };
            assert!(matches!(
                baseline.state,
                StudioProductBaselineState::AcpLocalDetection(state) if state.state == State::Idle
            ));
        }
        assert!(fixture.calls().is_empty());
        let mut subscription = fixture
            .runtime
            .subscribe_product_topic(StudioProductTopic::AcpLocalDetection)
            .await?;
        subscription.recv().await?;
        let accepted = fixture.start("available");
        assert_eq!(accepted.snapshot.state, State::Checking);
        assert_eq!(
            accepted.receipt.targets[0].resource_key,
            "acp-local-detection"
        );
        assert!(!accepted.receipt.durable);
        let state = fixture.terminal().await;
        assert_eq!(
            state,
            State::Available {
                program: fixture.program.to_string_lossy().into_owned(),
                version: "1.5.4".into(),
            }
        );
        let mut seen_terminal = false;
        while let Some(StudioProductFrame::Event(event)) =
            timeout(Duration::from_secs(1), subscription.recv()).await??
        {
            if let StudioProductEventKind::AcpLocalDetectionStateChanged(snapshot) = event.kind {
                assert_eq!(snapshot.operation_id.as_deref(), Some("available"));
                if snapshot.state == state {
                    seen_terminal = true;
                    break;
                }
            }
        }
        assert!(
            seen_terminal,
            "owner result must reach the registered topic"
        );
        fixture.start("available");
        assert_eq!(fixture.calls().len(), 2, "same operation must not restart");
        fixture.runtime.save_acp_account(UpdateAcpAccountRequest {
            operation_id: "save-local-entry".into(),
            expected_document_revision: None,
            account: AcpAccountUpdate {
                account_id: "local-entry".into(),
                name: "Local CLI".into(),
                enabled: true,
                command: Some("agy".into()),
                args: Some(vec!["acp".into()]),
                template: None,
                env: Default::default(),
            },
        })?;
        let definitions = fixture.runtime.config_runtime.read_acp_definitions();
        assert!(matches!(
            &definitions.definitions["local-entry"].definition.launch,
            AcpLaunch::Command { command, args } if command == "agy" && args == &["acp"]
        ));
        assert_eq!(
            fixture.calls().len(),
            2,
            "saving must not authenticate/spawn"
        );
        assert_eq!(fixture.calls()[0].args, ["--version"]);
        assert_eq!(fixture.calls()[1].args, ["acp", "--help"]);
        fixture.finish().await;
        Ok(())
    }

    #[tokio::test]
    async fn classifications_and_shared_output_budget_use_real_exit_and_stderr() -> Result<()> {
        let fixture = Fixture::new("available").await?;
        let hidden = fixture.program.with_extension("hidden");
        std::fs::rename(&fixture.program, &hidden)?;
        fixture.start("missing");
        assert_eq!(fixture.terminal().await, State::Missing);
        assert!(fixture.calls().is_empty());
        std::fs::rename(hidden, &fixture.program)?;
        for (index, mode) in [
            "unsupported",
            "root-help",
            "version-fail",
            "help-fail",
            "multiline-help",
            "stderr-help",
            "combined",
            "exact-limit",
            "over-limit",
        ]
        .into_iter()
        .enumerate()
        {
            fixture.mode(mode);
            fixture.start(&format!("classification-{index}"));
            let state = fixture.terminal().await;
            match mode {
                "unsupported" | "root-help" => assert_eq!(state, State::Unsupported),
                "version-fail" | "help-fail" => assert_failure(state, FailureKind::Execution),
                "combined" | "over-limit" => assert_failure(state, FailureKind::OutputLimit),
                "exact-limit" | "multiline-help" | "stderr-help" => {
                    assert!(matches!(state, State::Available { .. }))
                }
                _ => unreachable!(),
            }
            fixture.assert_reclaimed().await;
        }
        fixture.finish().await;
        Ok(())
    }

    #[tokio::test]
    async fn version_and_help_share_one_ten_second_deadline() -> Result<()> {
        let fixture = Fixture::new("deadline").await?;
        // Inhibit auto-advance while real process/socket preparation is pending. The
        // blocking wait doubles as a wall-clock watchdog and is released on success.
        let (release, blocked) = std::sync::mpsc::channel::<()>();
        let (expired, wall_deadline) = tokio::sync::oneshot::channel();
        let (started, blocking_started) = tokio::sync::oneshot::channel();
        let inhibit = tokio::task::spawn_blocking(move || {
            let _ = started.send(());
            if matches!(
                blocked.recv_timeout(Duration::from_secs(20)),
                Err(std::sync::mpsc::RecvTimeoutError::Timeout)
            ) {
                let _ = expired.send(());
                let _ = blocked.recv();
            }
        });
        blocking_started.await?;
        tokio::time::pause();
        fixture.start("deadline");
        let operation = fixture.operation();
        let cleanup = CancellationToken::new();
        *operation.cleanup_pause.lock().unwrap() = Some(cleanup.clone());
        let outcome = tokio::select! {
            biased;
            _ = wall_deadline => Err(anyhow::anyhow!("the shared probe deadline did not finish")),
            result = async {
                let (_, mut version) = fixture.launch_notification().await?;
                tokio::time::advance(Duration::from_secs(6)).await;
                version.write_all(b"x").await?;
                let (_, _help) = fixture.launch_notification().await?;
                tokio::time::advance(Duration::from_millis(3999)).await;
                anyhow::ensure!(
                    operation.resources.try_lock().is_err(),
                    "the held help command must still own its resources before ten seconds"
                );
                tokio::time::advance(Duration::from_millis(2)).await;
                // The real probe holds this lock across both commands. It releases it on
                // timeout, before the existing cleanup gate permits physical reclamation.
                let resources = operation.resources.lock().await;
                anyhow::ensure!(resources.worker.is_some());
                anyhow::Ok(())
            } => result,
        };
        tokio::time::resume();
        cleanup.cancel();
        drop(release);
        inhibit.await?;
        if let Err(error) = outcome {
            fixture.finish().await;
            return Err(error);
        }
        let state = fixture.terminal().await;
        assert_eq!(fixture.calls().len(), 2, "both commands consume one budget");
        fixture.assert_reclaimed().await;
        fixture.finish().await;
        assert_failure(state, FailureKind::Timeout);
        Ok(())
    }

    #[tokio::test]
    async fn cancel_busy_and_late_cancel_preserve_operation_identity_and_reclaim_tree() -> Result<()>
    {
        let fixture = Fixture::new("hang").await?;
        fixture.start("old");
        fixture.calls_reached(2).await;
        fixture.start("old");
        assert_eq!(fixture.calls().len(), 2);
        let busy = fixture
            .runtime
            .start_acp_local_detection(StartAcpLocalDetectionRequest {
                operation_id: "too-early".into(),
            })
            .unwrap_err();
        assert_eq!(
            busy.downcast_ref::<StudioError>().unwrap().code,
            StudioErrorCode::Busy
        );
        let cancelling =
            fixture
                .runtime
                .cancel_acp_local_detection(CancelAcpLocalDetectionRequest {
                    operation_id: "cancel-old".into(),
                    target_operation_id: "old".into(),
                })?;
        assert_eq!(cancelling.snapshot.state, State::Cancelling);
        assert_eq!(fixture.terminal().await, State::Cancelled);
        fixture.assert_reclaimed().await;
        fixture.mode("available");
        fixture.start("new");
        let stale = fixture
            .runtime
            .cancel_acp_local_detection(CancelAcpLocalDetectionRequest {
                operation_id: "late-cancel".into(),
                target_operation_id: "old".into(),
            })
            .unwrap_err();
        assert_eq!(
            stale.downcast_ref::<StudioError>().unwrap().code,
            StudioErrorCode::Conflict
        );
        assert!(matches!(fixture.terminal().await, State::Available { .. }));
        fixture.finish().await;
        Ok(())
    }

    #[tokio::test]
    async fn dropped_close_waiter_retains_borrowed_join_and_real_worker() -> Result<()> {
        let fixture = Fixture::new("hang").await?;
        fixture.start("waiter");
        fixture.calls_reached(2).await;
        let operation = fixture.operation();
        let pause = CancellationToken::new();
        *operation.cleanup_pause.lock().unwrap() = Some(pause.clone());
        assert!(
            timeout(
                Duration::from_millis(80),
                fixture.runtime.acp_detection.close()
            )
            .await
            .is_err()
        );
        assert_eq!(operation.join.running_handle_retained(), Some(true));
        let resources = operation.resources.lock().await;
        assert!(resources.worker.is_some());
        assert!(resources.directory.as_ref().unwrap().is_dir());
        drop(resources);
        pause.cancel();
        fixture.runtime.acp_detection.close().await?;
        fixture.finish().await;
        Ok(())
    }

    #[tokio::test]
    async fn close_retries_after_reporting_a_failed_detection_join() -> Result<()> {
        let fixture = Fixture::new("hang").await?;
        let directory = fixture.home.path().join("owned-probe");
        std::fs::create_dir(&directory)?;
        let handle = tokio::spawn(std::future::pending::<()>());
        handle.abort();
        let detection = &fixture.runtime.acp_detection;
        detection.inner.lock().operation = Some(Arc::new(Operation {
            id: "aborted-probe".into(),
            cancel: CancellationToken::new(),
            deadline: tokio::time::Instant::now(),
            join: RetainedTask::running(handle),
            resources: AsyncMutex::new(Resources {
                worker: None,
                directory: Some(directory.clone()),
            }),
            resources_released: AtomicBool::new(false),
            cleanup_pause: Mutex::new(None),
            cleanup_pending: AtomicBool::new(false),
        }));
        assert!(detection.close().await.is_err());
        assert!(!directory.exists());
        detection.close().await?;
        fixture.finish().await;
        Ok(())
    }

    #[tokio::test]
    async fn cleanup_pending_keeps_slot_directory_and_worker_until_original_shutdown_retry()
    -> Result<()> {
        let fixture = Fixture::new("hang").await?;
        fixture.start("pending");
        fixture.calls_reached(2).await;
        let operation = fixture.operation();
        // The only fault is a Pending cleanup observation; the supervised process,
        // descendants, pipes and directory here are real and still owned.
        operation.cleanup_pending.store(true, Ordering::Release);
        fixture
            .runtime
            .cancel_acp_local_detection(CancelAcpLocalDetectionRequest {
                operation_id: "cancel-pending".into(),
                target_operation_id: "pending".into(),
            })?;
        assert_failure(fixture.terminal().await, FailureKind::Cleanup);
        {
            let resources = operation.resources.lock().await;
            assert!(resources.worker.is_some());
            assert!(resources.directory.as_ref().unwrap().is_dir());
        }
        let busy = fixture
            .runtime
            .start_acp_local_detection(StartAcpLocalDetectionRequest {
                operation_id: "must-remain-busy".into(),
            })
            .unwrap_err();
        assert_eq!(
            busy.downcast_ref::<StudioError>().unwrap().code,
            StudioErrorCode::Busy
        );
        operation.cleanup_pending.store(false, Ordering::Release);
        fixture.finish().await;
        Ok(())
    }
}

#[cfg(test)]
mod publication_tests {
    use std::sync::Arc;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::time::Duration;

    use super::*;
    use crate::studio::agent_host::ThreadWriteBehindWriter;
    use crate::studio::{ProductEventBus, StudioStore};

    #[tokio::test]
    async fn emit_releases_admission_before_a_synchronous_observer() {
        let temp = tempfile::tempdir().expect("temp dir");
        let store = StudioStore::open(temp.path().join("data/studio.sqlite"))
            .await
            .expect("store");
        let writer = ThreadWriteBehindWriter::new(store.clone());
        let events = ProductEventBus::new(store.clone(), writer);
        let runtime = AcpLocalDetectionRuntime::new(
            store,
            events,
            pl_remote_helper::Executor::local().expect("local executor"),
        );
        let locked = Arc::new(AtomicBool::new(false));
        let flag = Arc::clone(&locked);
        let probe_runtime = runtime.clone();
        runtime.set_emit_probe(move || {
            let _slot = probe_runtime.inner.lock();
            flag.store(true, Ordering::Release);
        });

        let publisher = runtime.clone();
        let published = tokio::time::timeout(
            Duration::from_secs(2),
            tokio::task::spawn_blocking(move || publisher.publish_checking_for_probe()),
        )
        .await;
        assert!(
            published.is_ok(),
            "synchronous observer could not re-lock admission during emit"
        );
        assert!(published.expect("join").is_ok());
        assert!(locked.load(Ordering::Acquire));
        assert_eq!(runtime.read_state().state, AcpLocalDetectionState::Checking);
    }
}
