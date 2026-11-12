use std::sync::{
    Arc,
    atomic::{AtomicU64, Ordering},
};

use tokio_util::{sync::CancellationToken, task::TaskTracker};

use crate::{Command, PartialOutput};

static NEXT_EXECUTOR: AtomicU64 = AtomicU64::new(1);

/// Process-local identity. A replacement connection always has a different identity.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct ExecutorId(u64);

/// Non-sensitive facts about the machine which interprets commands and paths.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct TargetInfo {
    pub os: String,
    pub arch: String,
    pub home: Option<String>,
    pub initial_directory: String,
    pub shell: Option<String>,
}

/// The amount known about a failed launch; transport loss is never a spawn rejection.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StartKnowledge {
    NotStarted,
    Started,
    Unknown,
}

#[derive(Debug, thiserror::Error)]
#[error("{knowledge:?}: {cause}")]
pub struct SpawnError {
    pub knowledge: StartKnowledge,
    #[source]
    pub cause: ExecutionError,
}

/// Failures retain their original source and do not replace an observed process exit.
#[derive(Debug, Clone, thiserror::Error)]
pub enum ExecutionError {
    #[error("invalid command: {0}")]
    InvalidInput(String),
    #[error("{operation}: {source}")]
    Io {
        operation: &'static str,
        #[source]
        source: Arc<std::io::Error>,
    },
    #[error("HTTP request: {0}")]
    Http(#[source] Arc<reqwest::Error>),
    #[error(transparent)]
    TargetIo(#[from] TargetIoError),
    #[error("executor disconnected: {0}")]
    Disconnected(String),
    #[error("executor protocol: {0}")]
    Protocol(String),
    #[error("executor wire version mismatch: expected {expected}, received {actual}")]
    ProtocolMismatch { expected: u32, actual: u32 },
    #[error("execution cancelled")]
    Cancelled,
    #[error("output collection failed: {cause}")]
    CollectFailed {
        partial: Box<PartialOutput>,
        #[source]
        cause: Box<ExecutionError>,
    },
}

/// Target OS codes are diagnostic facts; the desktop must not reinterpret them
/// through its own `from_raw_os_error` (notably Windows hosts of Linux targets).
#[derive(Debug, Clone, thiserror::Error, serde::Serialize, serde::Deserialize)]
#[error("{operation}: target IO ({kind:?}, os={raw_os_error:?})")]
pub struct TargetIoError {
    pub operation: String,
    pub kind: IoErrorKind,
    pub raw_os_error: Option<i32>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum IoErrorKind {
    NotFound,
    PermissionDenied,
    AlreadyExists,
    InvalidInput,
    InvalidData,
    Interrupted,
    Unsupported,
    UnexpectedEof,
    BrokenPipe,
    TimedOut,
    WriteZero,
    WouldBlock,
    NotADirectory,
    IsADirectory,
    DirectoryNotEmpty,
    Other,
}
impl From<std::io::ErrorKind> for IoErrorKind {
    fn from(kind: std::io::ErrorKind) -> Self {
        use std::io::ErrorKind as Io;
        match kind {
            Io::NotFound => Self::NotFound,
            Io::PermissionDenied => Self::PermissionDenied,
            Io::AlreadyExists => Self::AlreadyExists,
            Io::InvalidInput => Self::InvalidInput,
            Io::InvalidData => Self::InvalidData,
            Io::Interrupted => Self::Interrupted,
            Io::Unsupported => Self::Unsupported,
            Io::UnexpectedEof => Self::UnexpectedEof,
            Io::BrokenPipe => Self::BrokenPipe,
            Io::TimedOut => Self::TimedOut,
            Io::WriteZero => Self::WriteZero,
            Io::WouldBlock => Self::WouldBlock,
            Io::NotADirectory => Self::NotADirectory,
            Io::IsADirectory => Self::IsADirectory,
            Io::DirectoryNotEmpty => Self::DirectoryNotEmpty,
            _ => Self::Other,
        }
    }
}

impl ExecutionError {
    pub(crate) fn io(operation: &'static str, source: std::io::Error) -> Self {
        Self::Io {
            operation,
            source: Arc::new(source),
        }
    }
}

pub(crate) enum ExecutorBackend {
    Local,
    Remote(crate::remote::RemoteConnection),
}

pub(crate) struct ExecutorInner {
    pub id: ExecutorId,
    pub info: TargetInfo,
    pub tasks: TaskTracker,
    pub closing: CancellationToken,
    pub backend: ExecutorBackend,
    pub environment: std::collections::BTreeMap<std::ffi::OsString, std::ffi::OsString>,
}

impl Drop for ExecutorInner {
    fn drop(&mut self) {
        self.closing.cancel();
        self.tasks.close();
    }
}

/// An execution machine, independent of any workspace's default directory.
#[derive(Clone)]
pub struct Executor {
    pub(crate) inner: Arc<ExecutorInner>,
}

impl std::fmt::Debug for Executor {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Executor")
            .field("id", &self.id())
            .field("target", self.target_info())
            .finish()
    }
}

impl Executor {
    /// Binds permanently to one foreground server over an already authenticated transport.
    pub async fn remote<T>(io: T) -> Result<Self, ExecutionError>
    where
        T: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin + Send + 'static,
    {
        let (connection, hello) = crate::remote::RemoteConnection::connect(io).await?;
        Ok(Self {
            inner: Arc::new(ExecutorInner {
                id: ExecutorId(NEXT_EXECUTOR.fetch_add(1, Ordering::Relaxed)),
                info: hello.target,
                tasks: connection.tasks.clone(),
                closing: connection.closing.clone(),
                backend: ExecutorBackend::Remote(connection),
                environment: Default::default(),
            }),
        })
    }
    /// Freezes the local initial directory; later process-wide cwd changes have no effect.
    pub fn local() -> Result<Self, ExecutionError> {
        let directory = std::env::current_dir()
            .map_err(|error| ExecutionError::io("initial directory", error))?;
        let initial_directory = directory
            .into_os_string()
            .into_string()
            .map_err(|_| ExecutionError::InvalidInput("initial directory is not UTF-8".into()))?;
        Ok(Self {
            inner: Arc::new(ExecutorInner {
                backend: ExecutorBackend::Local,
                id: ExecutorId(NEXT_EXECUTOR.fetch_add(1, Ordering::Relaxed)),
                info: TargetInfo {
                    os: std::env::consts::OS.into(),
                    arch: std::env::consts::ARCH.into(),
                    initial_directory,
                    home: std::env::var(if cfg!(windows) { "USERPROFILE" } else { "HOME" }).ok(),
                    shell: std::env::var(if cfg!(windows) { "COMSPEC" } else { "SHELL" }).ok(),
                },
                tasks: TaskTracker::new(),
                closing: CancellationToken::new(),
                environment: std::env::vars_os().collect(),
            }),
        })
    }

    pub fn id(&self) -> ExecutorId {
        self.inner.id
    }
    pub fn target_info(&self) -> &TargetInfo {
        &self.inner.info
    }
    pub fn command(&self, program: impl Into<String>) -> Command {
        Command::new(self.clone(), program.into())
    }

    pub fn is_closed(&self) -> bool {
        self.inner.closing.is_cancelled()
    }

    /// Ends this concrete execution connection. It can never be reopened.
    pub async fn close(&self) -> Result<(), ExecutionError> {
        self.inner.closing.cancel();
        self.inner.tasks.close();
        tokio::time::timeout(std::time::Duration::from_secs(2), self.inner.tasks.wait())
            .await
            .map_err(|_| {
                ExecutionError::Disconnected(
                    "executor cleanup unconfirmed after two seconds".into(),
                )
            })
    }
}
