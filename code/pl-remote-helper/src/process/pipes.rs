use std::io;

use process_wrap::tokio::{ChildWrapper, CommandWrap};

/// Distinguishes an OS launch failure from failed stdio setup after execution started.
#[derive(Debug, thiserror::Error)]
pub enum BackgroundSpawnError {
    #[error("process spawn failed: {0}")]
    Process(#[source] io::Error),
    #[error("stdio registration failed after process spawn: {0}")]
    Stdio(#[source] io::Error),
}

impl From<BackgroundSpawnError> for io::Error {
    fn from(error: BackgroundSpawnError) -> Self {
        let kind = match &error {
            BackgroundSpawnError::Process(source) | BackgroundSpawnError::Stdio(source) => {
                source.kind()
            }
        };
        io::Error::new(kind, error)
    }
}

#[cfg(windows)]
pub use tokio::net::windows::named_pipe::{
    NamedPipeServer as BackgroundStderr, NamedPipeServer as BackgroundStdin,
    NamedPipeServer as BackgroundStdout,
};
#[cfg(not(windows))]
pub use tokio::process::{
    ChildStderr as BackgroundStderr, ChildStdin as BackgroundStdin, ChildStdout as BackgroundStdout,
};

/// One process-tree owner and its independently owned asynchronous standard streams.
#[derive(Debug)]
pub struct BackgroundChild {
    pub process: Box<dyn ChildWrapper>,
    pub stdin: Option<BackgroundStdin>,
    pub stdout: Option<BackgroundStdout>,
    pub stderr: Option<BackgroundStderr>,
}

impl BackgroundChild {
    /// Closes stdin, drains both output streams and waits for the owned process tree.
    pub async fn wait_with_output(mut self) -> io::Result<std::process::Output> {
        use tokio::io::AsyncReadExt;

        self.stdin.take();
        let mut stdout = Vec::new();
        let mut stderr = Vec::new();
        let (status, (), ()) = tokio::try_join!(
            self.process.wait(),
            async {
                if let Some(pipe) = self.stdout.as_mut() {
                    pipe.read_to_end(&mut stdout).await?;
                }
                io::Result::Ok(())
            },
            async {
                if let Some(pipe) = self.stderr.as_mut() {
                    pipe.read_to_end(&mut stderr).await?;
                }
                io::Result::Ok(())
            },
        )?;
        Ok(std::process::Output {
            status,
            stdout,
            stderr,
        })
    }
}

pub(super) fn spawn(command: &mut CommandWrap) -> Result<BackgroundChild, BackgroundSpawnError> {
    let mut process = command.spawn().map_err(BackgroundSpawnError::Process)?;
    #[cfg(windows)]
    let (stdin, stdout, stderr) = {
        // These handles are taken immediately after spawn. No read, write or
        // blocking task has been issued on their Tokio child-stdio adapters.
        let stdin = process
            .stdin()
            .take()
            .map(|pipe| pipe.into_owned_handle().and_then(register_pipe))
            .transpose()
            .map_err(BackgroundSpawnError::Stdio)?;
        let stdout = process
            .stdout()
            .take()
            .map(|pipe| pipe.into_owned_handle().and_then(register_pipe))
            .transpose()
            .map_err(BackgroundSpawnError::Stdio)?;
        let stderr = process
            .stderr()
            .take()
            .map(|pipe| pipe.into_owned_handle().and_then(register_pipe))
            .transpose()
            .map_err(BackgroundSpawnError::Stdio)?;
        (stdin, stdout, stderr)
    };
    #[cfg(not(windows))]
    let (stdin, stdout, stderr) = (
        process.stdin().take(),
        process.stdout().take(),
        process.stderr().take(),
    );
    Ok(BackgroundChild {
        process,
        stdin,
        stdout,
        stderr,
    })
}

#[cfg(windows)]
fn register_pipe(
    handle: std::os::windows::io::OwnedHandle,
) -> io::Result<tokio::net::windows::named_pipe::NamedPipeServer> {
    use std::os::windows::io::IntoRawHandle;
    use tokio::net::windows::named_pipe::NamedPipeServer;

    // SAFETY: a fresh ChildStdin/Stdout/Stderr owns the server end of a connected
    // Windows named pipe opened for overlapped I/O by std::process::Command.
    // into_owned_handle then into_raw_handle transfers its sole ownership, with
    // no pending I/O or prior IOCP registration. Tokio consumes and closes the
    // handle on both success and registration failure, and owns all subsequent
    // OVERLAPPED operations and their buffers until completion/cancellation.
    unsafe { NamedPipeServer::from_raw_handle(handle.into_raw_handle()) }
}
