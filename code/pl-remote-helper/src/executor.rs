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
#[derive(Debug, Clone, PartialEq, Eq)]
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
    #[error("executor disconnected: {0}")]
    Disconnected(String),
    #[error("executor protocol: {0}")]
    Protocol(String),
    #[error("execution cancelled")]
    Cancelled,
    #[error("output collection failed: {cause}")]
    CollectFailed {
        partial: Box<PartialOutput>,
        #[source]
        cause: Box<ExecutionError>,
    },
}

impl ExecutionError {
    pub(crate) fn io(operation: &'static str, source: std::io::Error) -> Self {
        Self::Io {
            operation,
            source: Arc::new(source),
        }
    }
}

pub(crate) struct LocalExecutor {
    pub id: ExecutorId,
    pub info: TargetInfo,
    pub tasks: TaskTracker,
    pub closing: CancellationToken,
    pub environment: std::collections::BTreeMap<std::ffi::OsString, std::ffi::OsString>,
}

impl Drop for LocalExecutor {
    fn drop(&mut self) {
        self.closing.cancel();
        self.tasks.close();
    }
}

/// An execution machine, independent of any workspace's default directory.
#[derive(Clone)]
pub struct Executor {
    pub(crate) local: Arc<LocalExecutor>,
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
    /// Freezes the local initial directory; later process-wide cwd changes have no effect.
    pub fn local() -> Result<Self, ExecutionError> {
        let directory = std::env::current_dir()
            .map_err(|error| ExecutionError::io("initial directory", error))?;
        let initial_directory = directory
            .into_os_string()
            .into_string()
            .map_err(|_| ExecutionError::InvalidInput("initial directory is not UTF-8".into()))?;
        Ok(Self {
            local: Arc::new(LocalExecutor {
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
        self.local.id
    }
    pub fn target_info(&self) -> &TargetInfo {
        &self.local.info
    }
    pub fn command(&self, program: impl Into<String>) -> Command {
        Command::new(self.clone(), program.into())
    }
}
