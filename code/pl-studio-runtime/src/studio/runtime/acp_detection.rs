//! A single, memory-only local CLI probe slot.
//!
//! Admission, cancellation and publication share one lock. The slot owns the
//! supervisor join and physical resources, including after a cancelled waiter.
//! Neither reads nor construction touch the executable or filesystem.

mod probe;

use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};

use anyhow::Result;
use futures::FutureExt;
use pl_protocol::studio::{
    AcpLocalDetectionFailure, AcpLocalDetectionFailureKind, AcpLocalDetectionSnapshot,
    AcpLocalDetectionState, CancelAcpLocalDetectionRequest, StartAcpLocalDetectionRequest,
    StudioError, StudioErrorCode,
};
use tokio::sync::Mutex as AsyncMutex;
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

use super::acp_worker::{AcpWorker, PROCESS_CLEANUP_LIMIT, Reclaim};
use crate::studio::{ProductEventBus, StudioStore};
use pl_remote_helper::Executor;

#[derive(Clone)]
pub(crate) struct AcpLocalDetectionRuntime {
    inner: Arc<Inner>,
}

pub(crate) struct AcpLocalDetectionAcceptance {
    pub snapshot: AcpLocalDetectionSnapshot,
    pub changed: bool,
}

struct Inner {
    store: StudioStore,
    events: ProductEventBus,
    source: Executor,
    slot: Mutex<Slot>,
    /// Test-only launch inputs, never a process-global PATH or user config edit.
    #[cfg(test)]
    fixture_definition: Mutex<Option<crate::config::AcpServiceDefinition>>,
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
    join: AsyncMutex<Option<JoinHandle<()>>>,
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
            }),
        }
    }

    pub(crate) fn read_state(&self) -> AcpLocalDetectionSnapshot {
        self.inner.lock().snapshot.clone()
    }

    pub(crate) fn start(
        &self,
        request: StartAcpLocalDetectionRequest,
    ) -> Result<AcpLocalDetectionAcceptance> {
        super::StudioRuntime::validate_operation_id(&request.operation_id)?;
        let mut slot = self.inner.lock();
        if slot.closed {
            return Err(command_error(
                StudioErrorCode::RuntimeStopped,
                "运行时正在关闭，不能开始本机检测",
            ));
        }
        if slot.snapshot.operation_id.as_deref() == Some(request.operation_id.as_str()) {
            return Ok(acceptance(&slot, false));
        }
        // Poll only a finished join, by reference, before recycling the one slot.
        // Completion of the domain state alone is not evidence of task termination.
        if let Some(operation) = slot.operation.clone() {
            let Ok(mut join) = operation.join.try_lock() else {
                return Err(busy());
            };
            if let Some(task) = join.as_mut() {
                if !task.is_finished() {
                    return Err(busy());
                }
                let Some(outcome) = task.now_or_never() else {
                    return Err(busy());
                };
                *join = None;
                if outcome.is_err() {
                    self.inner
                        .publish_locked(&mut slot, failed(AcpLocalDetectionFailureKind::Cleanup));
                }
            }
            if !operation.resources_released.load(Ordering::Acquire) {
                return Err(busy());
            }
            slot.operation = None;
        }

        let operation = Arc::new(Operation {
            id: request.operation_id,
            cancel: CancellationToken::new(),
            deadline: tokio::time::Instant::now() + std::time::Duration::from_secs(10),
            join: AsyncMutex::new(None),
            resources: AsyncMutex::new(Resources::default()),
            resources_released: AtomicBool::new(false),
            #[cfg(test)]
            cleanup_pause: Mutex::new(None),
            #[cfg(test)]
            cleanup_pending: AtomicBool::new(false),
        });
        slot.snapshot.operation_id = Some(operation.id.clone());
        slot.operation = Some(Arc::clone(&operation));
        self.inner
            .publish_locked(&mut slot, AcpLocalDetectionState::Checking);
        // Responsibility is visible before spawn, with no intervening await.
        let task = tokio::spawn(supervise(Arc::clone(&self.inner), Arc::clone(&operation)));
        *operation
            .join
            .try_lock()
            .expect("new detection join is idle") = Some(task);
        Ok(acceptance(&slot, true))
    }

    pub(crate) fn cancel(
        &self,
        request: CancelAcpLocalDetectionRequest,
    ) -> Result<AcpLocalDetectionAcceptance> {
        super::StudioRuntime::validate_operation_id(&request.operation_id)?;
        super::StudioRuntime::validate_operation_id(&request.target_operation_id)?;
        let mut slot = self.inner.lock();
        if slot.snapshot.operation_id.as_deref() != Some(request.target_operation_id.as_str()) {
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
            slot.snapshot.state,
            AcpLocalDetectionState::Checking | AcpLocalDetectionState::Cancelling
        ) {
            return Ok(acceptance(&slot, false));
        }
        if let Some(operation) = &slot.operation {
            operation.cancel.cancel();
        }
        let changed = slot.snapshot.state != AcpLocalDetectionState::Cancelling;
        if changed {
            self.inner
                .publish_locked(&mut slot, AcpLocalDetectionState::Cancelling);
        }
        Ok(acceptance(&slot, changed))
    }

    /// Synchronous shutdown gate, before waiting for sibling resource owners.
    pub(crate) fn signal_cancel(&self) {
        let mut slot = self.inner.lock();
        slot.closed = true;
        if let Some(operation) = &slot.operation {
            operation.cancel.cancel();
            if slot.snapshot.state == AcpLocalDetectionState::Checking {
                self.inner
                    .publish_locked(&mut slot, AcpLocalDetectionState::Cancelling);
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
        let joined = tokio::time::timeout(PROCESS_CLEANUP_LIMIT, async {
            let mut join = operation.join.lock().await;
            if let Some(task) = join.as_mut() {
                let outcome = task.await;
                *join = None;
                outcome.map_err(|_| ())?;
            }
            Ok::<(), ()>(())
        })
        .await;
        if joined.is_err() {
            anyhow::bail!("本机检测任务仍在收束，保留原 owner 待重试");
        }
        // Even a panicked task leaves its physical worker in Operation.resources.
        let cleaned = release_resources(&operation).await;
        if !matches!(joined, Ok(Ok(()))) || !cleaned {
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

    fn publish_locked(&self, slot: &mut Slot, state: AcpLocalDetectionState) {
        slot.snapshot.state = state;
        slot.snapshot.revision += 1;
        // The event bus only enqueues; publication shares admission ordering.
        self.events.emit(
            crate::StudioProductEventKind::AcpLocalDetectionStateChanged(Box::new(
                slot.snapshot.clone(),
            )),
        );
    }

    fn finish(&self, operation: &Arc<Operation>, state: AcpLocalDetectionState) {
        let mut slot = self.lock();
        if !slot
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
        self.publish_locked(&mut slot, state);
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

    use anyhow::Result;
    use pl_protocol::studio::{
        AcpAccountUpdate, AcpLocalDetectionFailureKind as FailureKind,
        AcpLocalDetectionState as State, UpdateAcpAccountRequest,
    };
    use serde::Deserialize;
    use tokio::time::{Instant, sleep, timeout};

    use super::*;
    use crate::config::{AcpLaunch, AcpServiceDefinition};
    use crate::{
        StudioHostKind, StudioProductBaselineState, StudioProductEventKind, StudioProductFrame,
        StudioProductTopic, StudioRuntime, StudioRuntimeOptions,
    };

    const FIXTURE: &str = r#"#!/usr/bin/python3
import json, os, pathlib, subprocess, sys, time
root = pathlib.Path(os.environ['DETECTION_FIXTURE_ROOT'])
mode = (root / 'mode').read_text()
args = sys.argv[1:]
assert args in [['--version'], ['acp', '--help']], args
child = None
if mode == 'hang' and args == ['acp', '--help']:
    child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])
with (root / 'calls').open('a') as log:
    log.write(json.dumps({'args': args, 'pid': os.getpid(),
                         'child': child.pid if child else None,
                         'cwd': os.getcwd()}) + '\n')
    log.flush()
if mode == 'deadline':
    time.sleep(6)
if child:
    time.sleep(60)
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
    }

    impl Fixture {
        async fn new(mode: &str) -> Result<Self> {
            let home = tempfile::tempdir()?;
            let bin = home.path().join("bin");
            std::fs::create_dir(&bin)?;
            let program = bin.join("agy");
            std::fs::write(&program, FIXTURE)?;
            std::fs::set_permissions(&program, std::fs::Permissions::from_mode(0o700))?;
            std::fs::write(home.path().join("mode"), mode)?;
            let runtime = StudioRuntime::initialize(StudioRuntimeOptions {
                studio_home: Some(home.path().join("studio-home")),
                host: StudioHostKind::Test,
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

        fn start(&self, id: &str) -> pl_protocol::studio::AcpLocalDetectionCommandReply {
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

        async fn calls_reached(&self, count: usize) {
            timeout(Duration::from_secs(5), async {
                while self.calls().len() < count {
                    sleep(Duration::from_millis(10)).await;
                }
            })
            .await
            .expect("fixture must be launched through the real worker");
        }

        async fn terminal(&self) -> State {
            timeout(Duration::from_secs(18), async {
                loop {
                    let state = self.runtime.read_acp_local_detection_state().state;
                    let operation = self.operation();
                    let finished = operation
                        .join
                        .lock()
                        .await
                        .as_ref()
                        .is_some_and(JoinHandle::is_finished);
                    if finished && !matches!(state, State::Checking | State::Cancelling) {
                        return state;
                    }
                    sleep(Duration::from_millis(10)).await;
                }
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
            assert!(operation.join.lock().await.is_none(), "join must be reaped");
            let resources = operation.resources.lock().await;
            assert!(resources.worker.is_none());
            assert!(resources.directory.is_none());
            self.assert_reclaimed();
        }

        fn assert_reclaimed(&self) {
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
                    assert!(!Path::new(&format!("/proc/{pid}")).exists());
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
            expected_revision: fixture.runtime.config_runtime.read()?.revision,
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
            fixture.assert_reclaimed();
        }
        fixture.finish().await;
        Ok(())
    }

    #[tokio::test]
    async fn version_and_help_share_one_ten_second_deadline() -> Result<()> {
        let fixture = Fixture::new("deadline").await?;
        let started = Instant::now();
        fixture.start("deadline");
        assert_failure(fixture.terminal().await, FailureKind::Timeout);
        assert!(started.elapsed() >= Duration::from_secs(9));
        // Detection has a ten-second budget; physical cleanup may use its own five.
        assert!(started.elapsed() < Duration::from_secs(16));
        assert_eq!(fixture.calls().len(), 2, "both commands consume one budget");
        fixture.finish().await;
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
        fixture.assert_reclaimed();
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
        let join = operation.join.lock().await;
        assert!(!join.as_ref().unwrap().is_finished());
        drop(join);
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
