//! The only discovery path: one resolution and two read-only supervised commands.

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex, PoisonError};

use pl_protocol::studio::{AcpLocalDetectionFailureKind as FailureKind, AcpLocalDetectionState};
use tokio::io::AsyncReadExt;
use tokio::time::Instant;
use tokio_util::sync::CancellationToken;

use super::super::acp_launch::{AcpLaunchError, ResolvedAcpLaunch, resolve_launch};
use super::super::acp_worker::{
    AcpSpawnError, AcpSpawnRequest, AcpWorker, PROCESS_CLEANUP_LIMIT, Reclaim,
};
use super::{Inner, Operation, Resources, failed};
use crate::config::{AcpLaunch, AcpServiceDefinition};

const OUTPUT_LIMIT: usize = 64 * 1024;

/// One budget spans both commands and both streams. Stderr is captured only
/// inside this bounded probe, to classify an explicit unsupported-subcommand
/// response; it is never published or logged.
struct Output {
    data: Mutex<OutputData>,
    exceeded: CancellationToken,
}

#[derive(Default)]
struct OutputData {
    total: usize,
    stderr: Vec<u8>,
}

impl Output {
    fn new() -> Self {
        Self {
            data: Mutex::new(OutputData::default()),
            exceeded: CancellationToken::new(),
        }
    }

    fn record(&self, bytes: &[u8], stderr: bool) {
        let mut data = self.data.lock().unwrap_or_else(PoisonError::into_inner);
        let remaining = OUTPUT_LIMIT.saturating_sub(data.total);
        if stderr {
            data.stderr
                .extend_from_slice(&bytes[..bytes.len().min(remaining)]);
        }
        data.total = data.total.saturating_add(bytes.len());
        if data.total > OUTPUT_LIMIT {
            self.exceeded.cancel();
        }
    }

    fn reset_stderr(&self) {
        self.data
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .stderr
            .clear();
    }

    fn stderr(&self) -> Vec<u8> {
        self.data
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .stderr
            .clone()
    }
}

pub(super) async fn run(inner: &Inner, operation: &Operation) -> AcpLocalDetectionState {
    let output = Arc::new(Output::new());
    let mut resources = operation.resources.lock().await;
    match detect(inner, operation, &output, &mut resources).await {
        Ok(state) | Err(state) => state,
    }
}

async fn detect(
    inner: &Inner,
    operation: &Operation,
    output: &Arc<Output>,
    resources: &mut Resources,
) -> Result<AcpLocalDetectionState, AcpLocalDetectionState> {
    check_budget(operation, output)?;
    // Caller creates the cwd. The shared worker never creates directories.
    let root = inner.store.paths().acp_probe_root();
    std::fs::create_dir_all(&root).map_err(|_| failed(FailureKind::Execution))?;
    let directory = tempfile::Builder::new()
        .prefix(".local-detection-")
        .tempdir_in(root)
        .map_err(|_| failed(FailureKind::Execution))?
        .keep();
    resources.directory = Some(directory.clone());
    let definition = AcpServiceDefinition {
        id: "local-agy-detection".into(),
        display_name: "Local agy detection".into(),
        enabled: true,
        launch: AcpLaunch::Command {
            command: "agy".into(),
            args: Vec::new(),
        },
        env: BTreeMap::new(),
    };
    #[cfg(test)]
    let definition = inner
        .fixture_definition
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .clone()
        .unwrap_or(definition);
    // Generic command resolution, never template installation/config lookup.
    let launch = resolve_launch(&inner.store, &definition, &directory, &operation.cancel)
        .await
        .map_err(|error| match error {
            AcpLaunchError::MissingExecutable => AcpLocalDetectionState::Missing,
            AcpLaunchError::Cancelled => AcpLocalDetectionState::Cancelled,
            _ => failed(FailureKind::Execution),
        })?;
    check_budget(operation, output)?;

    let version = command(inner, operation, output, resources, &launch, &["--version"]).await?;
    if !version.success {
        return Err(failed(FailureKind::Execution));
    }
    let version = safe_version(&version.stdout).ok_or_else(|| failed(FailureKind::Execution))?;
    let help = command(
        inner,
        operation,
        output,
        resources,
        &launch,
        &["acp", "--help"],
    )
    .await?;
    if !help.success {
        return if unsupported(&help.stdout) || unsupported(&output.stderr()) {
            Ok(AcpLocalDetectionState::Unsupported)
        } else {
            Err(failed(FailureKind::Execution))
        };
    }
    // Do not infer support from a zero exit alone (some CLIs show root help for
    // unknown subcommands). No protocol session is opened to "double check".
    if !acp_help(&help.stdout) && !acp_help(&output.stderr()) {
        return Ok(AcpLocalDetectionState::Unsupported);
    }
    let program = launch
        .program
        .to_str()
        .ok_or_else(|| failed(FailureKind::Execution))?
        .to_owned();
    Ok(AcpLocalDetectionState::Available { program, version })
}

struct CommandOutput {
    success: bool,
    stdout: Vec<u8>,
}

async fn command(
    inner: &Inner,
    operation: &Operation,
    output: &Arc<Output>,
    resources: &mut Resources,
    launch: &ResolvedAcpLaunch,
    args: &[&str],
) -> Result<CommandOutput, AcpLocalDetectionState> {
    check_budget(operation, output)?;
    output.reset_stderr();
    let observed = Arc::clone(output);
    let observer: super::super::acp_worker::StderrObserver =
        Arc::new(move |bytes| observed.record(bytes, true));
    let spawn_cancel = operation.cancel.child_token();
    let spawn = AcpWorker::spawn_with_stderr_observer(
        AcpSpawnRequest {
            program: launch.program.clone(),
            args: args.iter().map(|arg| (*arg).to_owned()).collect(),
            cwd: resources
                .directory
                .as_ref()
                .expect("probe cwd is registered before spawn")
                .clone(),
            env: launch.env.clone(),
        },
        &inner.source,
        &spawn_cancel,
        observer,
    );
    tokio::pin!(spawn);
    // Startup futures must not be dropped after they may have spawned. Signal
    // cancellation, then await that SAME future and register its returned owner.
    let spawned = tokio::select! {
        biased;
        () = operation.cancel.cancelled() => {
            spawn_cancel.cancel();
            spawn.await
        }
        () = output.exceeded.cancelled() => {
            spawn_cancel.cancel();
            spawn.await
        }
        () = tokio::time::sleep_until(operation.deadline) => {
            spawn_cancel.cancel();
            spawn.await
        }
        result = &mut spawn => result,
    };
    match spawned {
        Ok(worker) => resources.worker = Some(worker),
        Err(error) => {
            check_budget(operation, output)?;
            return Err(match error {
                AcpSpawnError::MissingExecutable => AcpLocalDetectionState::Missing,
                AcpSpawnError::Cancelled => AcpLocalDetectionState::Cancelled,
                AcpSpawnError::Startup { .. } => failed(FailureKind::Execution),
            });
        }
    }
    check_budget(operation, output)?;
    let worker = resources.worker.as_mut().expect("spawn registered worker");
    let (stdin, mut stdout) = worker
        .take_streams()
        .ok_or_else(|| failed(FailureKind::Execution))?;
    drop(stdin);
    let mut captured = Vec::new();
    let mut buffer = [0; 1024];
    let mut eof = false;
    let mut exited = false;
    while !eof || !exited {
        check_budget(operation, output)?;
        tokio::select! {
            biased;
            () = operation.cancel.cancelled() => {
                return Err(AcpLocalDetectionState::Cancelled);
            }
            () = output.exceeded.cancelled() => {
                return Err(failed(FailureKind::OutputLimit));
            }
            () = tokio::time::sleep_until(operation.deadline) => {
                return Err(failed(FailureKind::Timeout));
            }
            read = stdout.read(&mut buffer), if !eof => {
                let read = read.map_err(|_| failed(FailureKind::Execution))?;
                if read == 0 {
                    eof = true;
                } else {
                    output.record(&buffer[..read], false);
                    check_budget(operation, output)?;
                    captured.extend_from_slice(&buffer[..read]);
                }
            }
            result = worker.observe_exit(), if !exited => {
                result.map_err(|_| failed(FailureKind::Execution))?;
                exited = true;
            }
        }
    }
    drop(stdout);
    let success = worker
        .exit_success()
        .ok_or_else(|| failed(FailureKind::Execution))?;
    // Join stderr and reclaim the tree before moving to the second command.
    // Borrowing the worker preserves it if either deadline interrupts this wait.
    let cleanup_deadline = operation
        .deadline
        .min(Instant::now() + PROCESS_CLEANUP_LIMIT);
    match tokio::time::timeout_at(cleanup_deadline, worker.reclaim()).await {
        Ok(Reclaim::Stopped) => resources.worker = None,
        Ok(Reclaim::Settled(_)) => {
            resources.worker = None;
            return Err(failed(FailureKind::Cleanup));
        }
        Ok(Reclaim::Pending(_)) | Err(_) => return Err(failed(FailureKind::Cleanup)),
    }
    check_budget(operation, output)?;
    Ok(CommandOutput {
        success,
        stdout: captured,
    })
}

fn check_budget(operation: &Operation, output: &Output) -> Result<(), AcpLocalDetectionState> {
    if operation.cancel.is_cancelled() {
        Err(AcpLocalDetectionState::Cancelled)
    } else if output.exceeded.is_cancelled() {
        Err(failed(FailureKind::OutputLimit))
    } else if Instant::now() >= operation.deadline {
        Err(failed(FailureKind::Timeout))
    } else {
        Ok(())
    }
}

/// Only a numeric version token is public; never echo a line of process output.
fn safe_version(bytes: &[u8]) -> Option<String> {
    std::str::from_utf8(bytes)
        .ok()?
        .split_ascii_whitespace()
        .find_map(|token| {
            let token = token.strip_prefix('v').unwrap_or(token);
            let parts: Vec<_> = token.split('.').collect();
            (token.len() <= 32
                && parts.len() == 3
                && parts
                    .iter()
                    .all(|part| !part.is_empty() && part.bytes().all(|byte| byte.is_ascii_digit())))
            .then(|| token.to_owned())
        })
}

fn unsupported(bytes: &[u8]) -> bool {
    let diagnostic = String::from_utf8_lossy(bytes).to_ascii_lowercase();
    diagnostic.lines().any(|line| {
        line.split(|character: char| !character.is_ascii_alphanumeric())
            .any(|word| word == "acp")
            && [
                "unknown command",
                "unknown subcommand",
                "unrecognized command",
                "unrecognized subcommand",
                "invalid choice",
            ]
            .iter()
            .any(|marker| line.contains(marker))
    })
}

/// Require the subcommand's own usage, not a mention in the root menu or prose.
/// The official CLI documents `agy acp [flags]`; help is the only read-only
/// capability evidence used here, never a protocol initialize/session.
fn acp_help(bytes: &[u8]) -> bool {
    let help = String::from_utf8_lossy(bytes).to_ascii_lowercase();
    let mut lines = help.lines();
    while let Some(line) = lines.next() {
        let Some(usage) = line.trim().strip_prefix("usage:") else {
            continue;
        };
        let usage = if usage.trim().is_empty() {
            lines.next().unwrap_or_default()
        } else {
            usage
        };
        let mut words = usage.split_ascii_whitespace();
        if matches!(words.next(), Some("agy" | "agy.exe"))
            && words.next() == Some("acp")
            && words.next().is_none_or(|word| word.starts_with('['))
        {
            return true;
        }
    }
    false
}
