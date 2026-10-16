use std::path::PathBuf;
use std::sync::Arc;

use pl_protocol::remote::{
    RemoteError, RemoteErrorCode, RemoteEvent, RemoteMessage, RemoteProcessExit,
    RemoteShellDescriptor, RemoteShellDialect, RemoteSpawnRequest,
};
use tokio::sync::{Semaphore, mpsc, watch};

use super::super::outbound::Outbound;
use super::{
    Reply,
    streams::{self, Input},
};
use crate::client::{ManagedWorker, ProcessCommand, ProcessTermination};
use crate::path::{io_error, remote_error};

pub(super) struct Launch {
    pub request: RemoteSpawnRequest,
    pub cwd: PathBuf,
    pub capture: Option<PathBuf>,
    pub shell: RemoteShellDescriptor,
    pub writer: Outbound,
    pub cancel: watch::Sender<bool>,
    pub cancelled: watch::Receiver<bool>,
    pub incoming: mpsc::Receiver<Input>,
    pub reply: Reply,
    pub output_credit: Arc<Semaphore>,
}

pub(super) async fn run(mut launch: Launch) {
    let prepared = prepare(&launch).await;
    let (mut worker, capture) = match prepared {
        Ok(prepared) => prepared,
        Err(error) => {
            let _ = launch.reply.send(Err(error));
            return;
        }
    };
    let control = worker.control();
    let stdin = worker.take_stdin();
    let stdout = worker.take_stdout();
    let stderr = worker.take_stderr();
    let _ = launch.reply.send(Ok(()));
    let (finished, stopped) = watch::channel(false);
    let wait = async {
        let result = tokio::select! {
            biased;
            _ = async { let _ = launch.cancelled.wait_for(|cancelled| *cancelled).await; } => {
                if control.cancel().await.is_err() { control.close(); }
                worker.wait().await
            }
            result = worker.wait() => result,
        };
        finished.send_replace(true);
        result
    };
    let (result, output, ()) = tokio::join!(
        wait,
        streams::output(streams::Output {
            id: &launch.request.process_id,
            stdout,
            stderr,
            capture,
            writer: &launch.writer,
            cancel: &launch.cancel,
            credit: &launch.output_credit,
        }),
        streams::input(stdin, launch.incoming, stopped),
    );
    let (exit_code, signal, failure) = match result {
        Ok(ProcessTermination::ExitCode(code)) => (Some(code), None, output.failure),
        Ok(ProcessTermination::Signal(signal)) => (None, Some(signal), output.failure),
        Err(error) => (
            None,
            None,
            Some(remote_error(RemoteErrorCode::Io, error.to_string())),
        ),
    };
    // All physical and IO futures have ended; this is the only remote terminal emission.
    let _ = launch
        .writer
        .write(
            None,
            RemoteMessage::Event(RemoteEvent::ProcessExit(RemoteProcessExit {
                process_id: launch.request.process_id,
                exit_code,
                signal,
                failure,
                capture: output.receipt,
            })),
            &[],
        )
        .await;
}

async fn prepare(launch: &Launch) -> Result<(ManagedWorker, super::capture::Capture), RemoteError> {
    if *launch.cancelled.borrow() {
        return Err(super::closed());
    }
    let capture = super::capture::Capture::prepare(
        &launch.request.capture,
        launch.capture.as_deref(),
        &launch.request.command,
        &launch.cwd,
    )
    .await?;
    let option = match launch.shell.dialect {
        RemoteShellDialect::Bash | RemoteShellDialect::Sh => "-c",
        RemoteShellDialect::Pwsh | RemoteShellDialect::PowerShell => "-Command",
        RemoteShellDialect::Cmd => "/C",
    };
    let mut command = ProcessCommand::new(&launch.shell.path);
    if launch.shell.dialect == RemoteShellDialect::Bash {
        // SSH environment variables can make bash -c read .bashrc again. The connection
        // already owns its initialized environment; individual commands must not reload it.
        command = command.args(["--noprofile", "--norc"]);
    }
    let mut command = command
        .args([option, &launch.request.command])
        .current_dir(&launch.cwd)
        // Startup hooks must not reload configuration after the connection snapshot.
        // An explicit request may still opt into them via its own environment overrides.
        .env_remove("BASH_ENV")
        .env_remove("ENV");
    for (key, value) in &launch.request.environment {
        command = command.env(key, value);
    }
    if *launch.cancelled.borrow() {
        return Err(super::closed());
    }
    let executable =
        std::env::current_exe().map_err(|error| io_error("locate process worker", error))?;
    // This future belongs to the registry job, not the cancellable Spawn RPC waiter.
    let worker = ManagedWorker::spawn(&executable, command)
        .await
        .map_err(|error| remote_error(RemoteErrorCode::Io, error.to_string()))?;
    Ok((worker, capture))
}
