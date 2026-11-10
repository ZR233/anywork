//! Linux boundary tests: only the executable/launch environment and explicit
//! cleanup fault gates are synthetic. Runtime commands, save, topic baseline,
//! event delivery, launch resolution and ManagedWorker are production paths.

use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::time::Duration;

use anyhow::Result;
use pl_protocol::studio::{
    AcpAccountUpdate, AcpLocalDetectionFailureKind as FailureKind, AcpLocalDetectionState as State,
    UpdateAcpAccountRequest,
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
async fn runtime_baseline_reads_are_inert_and_available_can_save_normal_command() -> Result<()> {
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
async fn cancel_busy_and_late_cancel_preserve_operation_identity_and_reclaim_tree() -> Result<()> {
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
