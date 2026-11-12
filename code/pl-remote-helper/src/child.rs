use std::{
    pin::Pin,
    sync::Arc,
    task::{Context, Poll},
};

use tokio::{
    io::{AsyncRead, AsyncReadExt, AsyncWrite, ReadBuf},
    sync::{mpsc, oneshot, watch},
};
use tokio_util::sync::CancellationToken;

use crate::{
    CaptureResult, ExecutionError, Executor,
    capture::{CaptureCompletion, completion},
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProcessExit {
    Code(i32),
    Signal(i32),
}

impl ProcessExit {
    pub fn success(self) -> bool {
        self == Self::Code(0)
    }
    pub fn code(self) -> Option<i32> {
        match self {
            Self::Code(code) => Some(code),
            Self::Signal(_) => None,
        }
    }
}

#[derive(Debug, Clone, Default)]
pub struct PartialOutput {
    pub root_exit: Option<ProcessExit>,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
    pub capture: Option<CaptureResult>,
}

#[derive(Debug)]
pub struct Output {
    pub status: ProcessExit,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
    pub capture: Option<CaptureResult>,
}

pub(crate) struct PipeLifetime(pub Arc<tokio::sync::Notify>);
impl Drop for PipeLifetime {
    fn drop(&mut self) {
        self.0.notify_one();
    }
}

pub struct ChildStdout {
    pub(crate) io: Pin<Box<dyn AsyncRead + Send>>,
    pub(crate) lifetime: Option<Arc<PipeLifetime>>,
    pub(crate) cancel: Option<CancellationToken>,
}
pub type ChildStderr = ChildStdout;

impl Drop for ChildStdout {
    fn drop(&mut self) {
        if let Some(cancel) = &self.cancel {
            cancel.cancel();
        }
    }
}

impl AsyncRead for ChildStdout {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buffer: &mut ReadBuf<'_>,
    ) -> Poll<std::io::Result<()>> {
        let before = buffer.filled().len();
        let capacity = buffer.remaining();
        let result = self.io.as_mut().poll_read(cx, buffer);
        if matches!(result, Poll::Ready(Err(_)))
            || (matches!(result, Poll::Ready(Ok(())))
                && capacity > 0
                && buffer.filled().len() == before)
        {
            self.lifetime.take();
        }
        result
    }
}

pub struct ChildStdin {
    pub(crate) io: Option<Pin<Box<dyn AsyncWrite + Send>>>,
    pub(crate) lifetime: Option<Arc<PipeLifetime>>,
}

impl AsyncWrite for ChildStdin {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        bytes: &[u8],
    ) -> Poll<std::io::Result<usize>> {
        match self.io.as_mut() {
            Some(io) => io.as_mut().poll_write(cx, bytes),
            None => Poll::Ready(Err(std::io::ErrorKind::BrokenPipe.into())),
        }
    }
    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        match self.io.as_mut() {
            Some(io) => io.as_mut().poll_flush(cx),
            None => Poll::Ready(Ok(())),
        }
    }
    fn poll_shutdown(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        let result = match self.io.as_mut() {
            Some(io) => io.as_mut().poll_shutdown(cx),
            None => return Poll::Ready(Ok(())),
        };
        if result.is_ready() {
            self.io.take();
            self.lifetime.take();
        }
        result
    }
}

pub(crate) type KillRequest = oneshot::Sender<Result<(), ExecutionError>>;
pub(crate) type ExitReceiver = watch::Receiver<Option<Result<ProcessExit, ExecutionError>>>;

/// A managed root process. Drop requests cancellation; its registered owner performs reaping.
pub struct Child {
    pub stdin: Option<ChildStdin>,
    pub stdout: Option<ChildStdout>,
    pub stderr: Option<ChildStderr>,
    pub(crate) pid: Option<u32>,
    pub(crate) exit: ExitReceiver,
    pub(crate) kill: mpsc::Sender<KillRequest>,
    pub(crate) cancellation: CancellationToken,
    pub(crate) capture: Option<(CaptureCompletion, CaptureCompletion)>,
    pub(crate) executor: Executor,
}

impl std::fmt::Debug for Child {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Child")
            .field("pid", &self.id())
            .field("executor", &self.executor.id())
            .finish_non_exhaustive()
    }
}

impl Drop for Child {
    fn drop(&mut self) {
        if self.exit.borrow().is_none() {
            self.cancellation.cancel();
        }
    }
}

impl Child {
    pub fn id(&self) -> Option<u32> {
        if self.exit.borrow().is_some() {
            None
        } else {
            self.pid
        }
    }
    pub fn try_wait(&mut self) -> Result<Option<ProcessExit>, ExecutionError> {
        self.exit.borrow().clone().transpose()
    }
    pub async fn wait(&mut self) -> Result<ProcessExit, ExecutionError> {
        self.stdin.take();
        loop {
            if let Some(exit) = self.exit.borrow().clone() {
                return exit;
            }
            self.exit.changed().await.map_err(|_| {
                ExecutionError::Protocol("process owner ended without an exit result".into())
            })?;
        }
    }
    pub async fn start_kill(&mut self) -> Result<(), ExecutionError> {
        if self.exit.borrow().is_some() {
            return Ok(());
        }
        let (send, receive) = oneshot::channel();
        if self.kill.send(send).await.is_err() {
            return if self.exit.borrow().is_some() {
                Ok(())
            } else {
                Err(ExecutionError::Protocol(
                    "process control owner ended".into(),
                ))
            };
        }
        receive
            .await
            .map_err(|_| ExecutionError::Protocol("process kill was not acknowledged".into()))?
    }
    pub async fn kill(&mut self) -> Result<(), ExecutionError> {
        self.start_kill().await?;
        self.wait().await.map(|_| ())
    }
    pub async fn finish_capture(&mut self) -> Result<Option<CaptureResult>, ExecutionError> {
        let Some((stdout, stderr)) = &mut self.capture else {
            return Ok(None);
        };
        let (stdout, stderr) = tokio::join!(completion(stdout), completion(stderr));
        Ok(Some(CaptureResult { stdout, stderr }))
    }
    pub async fn wait_with_output(mut self) -> Result<Output, ExecutionError> {
        self.stdin.take();
        let mut stdout = self.stdout.take();
        let mut stderr = self.stderr.take();
        let mut partial = PartialOutput::default();
        let (exit, out, err) = tokio::join!(
            self.wait(),
            read(&mut stdout, &mut partial.stdout),
            read(&mut stderr, &mut partial.stderr)
        );
        partial.root_exit = exit.as_ref().ok().copied();
        partial.capture = self.finish_capture().await?;
        let cause = exit
            .as_ref()
            .err()
            .cloned()
            .or_else(|| out.err())
            .or_else(|| err.err());
        if let Some(cause) = cause {
            return Err(ExecutionError::CollectFailed {
                partial: Box::new(partial),
                cause: Box::new(cause),
            });
        }
        Ok(Output {
            status: exit?,
            stdout: partial.stdout,
            stderr: partial.stderr,
            capture: partial.capture,
        })
    }
}

async fn read(reader: &mut Option<ChildStdout>, bytes: &mut Vec<u8>) -> Result<(), ExecutionError> {
    if let Some(reader) = reader {
        reader
            .read_to_end(bytes)
            .await
            .map_err(|error| ExecutionError::io("collect process output", error))?;
    }
    Ok(())
}
