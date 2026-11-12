use std::{
    path::{Path, PathBuf},
    sync::{
        Arc, Weak,
        atomic::{AtomicU64, Ordering},
    },
};

use process_wrap::tokio::ChildWrapper;
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    sync::{Notify, mpsc, watch},
};
use tokio_util::sync::CancellationToken;

use crate::{
    CaptureState, CapturedStream, Child, ChildStdin, ChildStdout, Command, ExecutionError,
    ProcessExit, SpawnError, StartKnowledge, Stdio,
};
use crate::{
    capture::CaptureCompletion,
    child::{KillRequest, PipeLifetime},
    process::{BackgroundSpawnError, spawn_background_command, wrap_background_command},
};

pub(crate) async fn spawn(command: &Command) -> Result<Child, SpawnError> {
    let directory = Path::new(&command.executor.target_info().initial_directory)
        .join(command.cwd.as_deref().unwrap_or("."));
    let program = if command.program.contains(std::path::MAIN_SEPARATOR)
        || (cfg!(windows) && command.program.contains('/'))
    {
        directory.join(&command.program).into_os_string()
    } else {
        command.program.clone().into()
    };
    let mut native = tokio::process::Command::new(program);
    native.args(&command.arguments).current_dir(&directory);
    native.env_clear();
    if !command.clear_environment {
        native.envs(&command.executor.inner.environment);
    }
    for (key, value) in &command.environment {
        match value {
            Some(value) => {
                native.env(key, value);
            }
            None => {
                native.env_remove(key);
            }
        }
    }
    native
        .stdin(stdio(command.stdin))
        .stdout(stdio(command.stdout))
        .stderr(stdio(command.stderr));
    let capture = if let Some(spec) = &command.capture {
        let stdout = tokio::fs::File::create(resolve_capture(command, &spec.stdout_path))
            .await
            .map_err(not_started)?;
        let stderr = tokio::fs::File::create(resolve_capture(command, &spec.stderr_path))
            .await
            .map_err(not_started)?;
        Some((stdout, stderr, Arc::new(AtomicU64::new(spec.max_bytes))))
    } else {
        None
    };
    let spawned =
        spawn_background_command(&mut wrap_background_command(native)).map_err(|error| {
            let knowledge = match &error {
                BackgroundSpawnError::Process(_) => StartKnowledge::NotStarted,
                BackgroundSpawnError::Stdio(_) => StartKnowledge::Started,
            };
            SpawnError {
                knowledge,
                cause: ExecutionError::io("spawn process", error.into()),
            }
        })?;
    let pid = spawned.process.id();
    let notify = Arc::new(Notify::new());
    let mut lifetimes = Vec::new();
    let mut lifetime = || {
        let guard = Arc::new(PipeLifetime {
            notify: notify.clone(),
            _executor: command.executor.clone(),
        });
        lifetimes.push(Arc::downgrade(&guard));
        guard
    };
    let stdin = spawned.stdin.map(|io| ChildStdin {
        io: Some(Box::pin(io)),
        lifetime: Some(lifetime()),
    });
    let mut stdout = spawned.stdout.map(|io| ChildStdout {
        io: Box::pin(io),
        lifetime: Some(lifetime()),
        cancel: None,
    });
    let mut stderr = spawned.stderr.map(|io| ChildStdout {
        io: Box::pin(io),
        lifetime: Some(lifetime()),
        cancel: None,
    });
    let cancellation = CancellationToken::new();
    let capture = capture.map(|(out_file, err_file, budget)| {
        let (out, out_done) = capture_pipe(
            stdout.take().expect("validated piped stdout"),
            out_file,
            budget.clone(),
            cancellation.clone(),
            &command.executor.inner.tasks,
        );
        let (err, err_done) = capture_pipe(
            stderr.take().expect("validated piped stderr"),
            err_file,
            budget,
            cancellation.clone(),
            &command.executor.inner.tasks,
        );
        stdout = Some(out);
        stderr = Some(err);
        (out_done, err_done)
    });
    let (exit_send, exit) = watch::channel(None);
    let (kill, requests) = mpsc::channel(8);
    let closing = command.executor.inner.closing.clone();
    command.executor.inner.tasks.spawn(own_process(
        spawned.process,
        requests,
        cancellation.clone(),
        closing,
        exit_send,
        lifetimes,
        notify,
    ));
    Ok(Child {
        stdin,
        stdout,
        stderr,
        pid,
        exit,
        kill,
        cancellation,
        capture,
        executor: command.executor.clone(),
    })
}

fn not_started(error: std::io::Error) -> SpawnError {
    SpawnError {
        knowledge: StartKnowledge::NotStarted,
        cause: ExecutionError::io("prepare capture", error),
    }
}
fn resolve_capture(command: &Command, path: &str) -> PathBuf {
    Path::new(&command.executor.target_info().initial_directory).join(path)
}
fn stdio(value: Option<Stdio>) -> std::process::Stdio {
    match value.unwrap_or(Stdio::Null) {
        Stdio::Null => std::process::Stdio::null(),
        Stdio::Piped => std::process::Stdio::piped(),
    }
}

async fn own_process(
    mut process: Box<dyn ChildWrapper>,
    mut requests: mpsc::Receiver<KillRequest>,
    cancellation: CancellationToken,
    closing: CancellationToken,
    exit: watch::Sender<Option<Result<ProcessExit, ExecutionError>>>,
    lifetimes: Vec<Weak<PipeLifetime>>,
    notify: Arc<Notify>,
) {
    let mut stopping = false;
    let mut control_open = true;
    let outcome = loop {
        tokio::select! {
            result = root_wait(process.as_mut()) => break result,
            request = requests.recv(), if control_open => {
                let result = match root_try_wait(process.as_mut()) {
                    Ok(Some(status)) => { if let Some(request) = request { let _ = request.send(Ok(())); } break Ok(status); },
                    Ok(None) => process.start_kill().map_err(|error| ExecutionError::io("kill process", error)),
                    Err(error) => Err(error),
                };
                if let Some(request) = request { let _ = request.send(result); }
                else { stopping = true; control_open = false; }
            }
            _ = cancellation.cancelled(), if !stopping => { stopping = true; let _ = kill_running(process.as_mut()); }
            _ = closing.cancelled(), if !stopping => { stopping = true; let _ = kill_running(process.as_mut()); }
        }
    };
    exit.send_replace(Some(outcome));
    requests.close();
    while let Some(request) = requests.recv().await {
        let _ = request.send(Ok(()));
    }
    // Windows' job guard must outlive tail output held by a descendant. On Unix,
    // retaining the wrapper never sends a signal after the root has been reaped.
    while lifetimes.iter().any(|guard| guard.strong_count() != 0) {
        notify.notified().await;
    }
    drop(process);
}

fn kill_running(process: &mut dyn ChildWrapper) -> Result<(), ExecutionError> {
    if root_try_wait(process)?.is_none() {
        process
            .start_kill()
            .map_err(|error| ExecutionError::io("kill process", error))?;
    }
    Ok(())
}

async fn root_wait(process: &mut dyn ChildWrapper) -> Result<ProcessExit, ExecutionError> {
    // SAFETY: only wrap_background_command constructs this fixed ProcessGroup /
    // JobObject + KillOnDrop chain. This task is its sole mutable owner; pipes
    // have already been taken. No outer wrapper wait/try_wait/kill is used, and
    // the wrapper remains alive until all pipe owners finish. Native wait only
    // reaps the root and cannot invalidate the retained job handle.
    let child = unsafe { process.try_inner_child_mut() }.ok_or_else(|| {
        ExecutionError::Protocol("background factory returned no native child".into())
    })?;
    child
        .wait()
        .await
        .map(exit_status)
        .map_err(|error| ExecutionError::io("wait root process", error))
}

fn root_try_wait(process: &mut dyn ChildWrapper) -> Result<Option<ProcessExit>, ExecutionError> {
    // SAFETY: same fixed factory chain, exclusive owner and retained wrappers as
    // root_wait. This synchronous probe never calls any wrapper wait method.
    let child = unsafe { process.try_inner_child_mut() }.ok_or_else(|| {
        ExecutionError::Protocol("background factory returned no native child".into())
    })?;
    child
        .try_wait()
        .map(|status| status.map(exit_status))
        .map_err(|error| ExecutionError::io("probe root process", error))
}

fn exit_status(status: std::process::ExitStatus) -> ProcessExit {
    if let Some(code) = status.code() {
        return ProcessExit::Code(code);
    }
    #[cfg(unix)]
    {
        use std::os::unix::process::ExitStatusExt;
        ProcessExit::Signal(
            status
                .signal()
                .expect("Unix exit without code has a signal"),
        )
    }
    #[cfg(not(unix))]
    {
        unreachable!("non-Unix exit status always has a code")
    }
}

fn capture_pipe(
    input: ChildStdout,
    mut file: tokio::fs::File,
    budget: Arc<AtomicU64>,
    cancellation: CancellationToken,
    tasks: &tokio_util::task::TaskTracker,
) -> (ChildStdout, CaptureCompletion) {
    let (writer, reader) = tokio::io::duplex(64 * 1024);
    let (done, completion) = watch::channel(None);
    let cancelled = CancellationToken::new();
    let stop = cancelled.clone();
    let lifetime = input.lifetime.clone();
    tasks.spawn(async move {
        let mut input = input;
        let mut writer = writer;
        let mut count = 0;
        let mut state = CaptureState::Complete;
        let result: std::io::Result<()> = async {
            let mut bytes = [0; 64 * 1024];
            loop {
                let length = tokio::select! {
                    biased;
                    _ = stop.cancelled() => { state = CaptureState::Incomplete; break; }
                    result = input.read(&mut bytes) => result?,
                };
                if length == 0 {
                    break;
                }
                let mut available = budget.load(Ordering::Relaxed);
                let accepted = loop {
                    let accepted = available.min(length as u64);
                    match budget.compare_exchange_weak(
                        available,
                        available - accepted,
                        Ordering::Relaxed,
                        Ordering::Relaxed,
                    ) {
                        Ok(_) => break accepted as usize,
                        Err(current) => available = current,
                    }
                };
                file.write_all(&bytes[..accepted]).await?;
                count += accepted as u64;
                if accepted < length {
                    state = CaptureState::LimitExceeded;
                    cancellation.cancel();
                }
                tokio::select! {
                    _ = stop.cancelled() => { state = CaptureState::Incomplete; break; }
                    result = writer.write_all(&bytes[..accepted]) => result?,
                }
                if accepted < length {
                    break;
                }
            }
            file.flush().await
        }
        .await;
        let error = result.err().map(Arc::new);
        if error.is_some() {
            state = CaptureState::IoFailed;
            cancellation.cancel();
        }
        done.send_replace(Some(CapturedStream {
            state,
            confirmed_bytes: if error.is_some() { None } else { Some(count) },
            error,
        }));
    });
    let (reader, observed) = crate::capture::observe(Box::pin(reader), move || {
        completion.borrow().clone().unwrap_or(CapturedStream {
            state: CaptureState::Incomplete,
            confirmed_bytes: None,
            error: None,
        })
    });
    (
        ChildStdout {
            io: reader,
            lifetime,
            cancel: Some(cancelled),
        },
        observed,
    )
}
