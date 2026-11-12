//! Physical process and filesystem capabilities over a single resumable HTTP/2 connection.

pub mod process_worker_protocol;
pub mod start_control;
pub mod transport;

mod capture;
mod child;
mod command;
mod executor;
pub mod fs;
pub mod http;
mod native;
mod remote;
mod stdio_server;
mod stream;
mod target_path;
mod wire;
pub use stdio_server::serve as serve_connection;
pub use target_path::TargetPath;

#[derive(Debug, thiserror::Error)]
pub enum PatchExecutionError {
    #[error(transparent)]
    Execution(#[from] ExecutionError),
    #[error(transparent)]
    Patch(#[from] pl_patch::PatchFailure),
}

pub use capture::{CaptureResult, CaptureSpec, CaptureState, CapturedStream};
pub use child::{Child, ChildStderr, ChildStdin, ChildStdout, Output, PartialOutput, ProcessExit};
pub use command::{Command, Stdio};
pub use executor::{
    ExecutionError, Executor, ExecutorId, IoErrorKind, SpawnError, StartKnowledge, TargetInfo,
    TargetIoError,
};

pub use pl_protocol::remote::RemoteError;

/// Host process creation and background ownership shared by execution adapters.
pub mod process;

/// Host-side physical process supervision, shared by local execution and the SSH service.
#[cfg(target_os = "linux")]
pub mod client;

#[cfg(target_os = "linux")]
mod path;
#[cfg(target_os = "linux")]
mod server;

#[cfg(target_os = "linux")]
pub use server::{attach_stdio, run_owner, run_stdio};

/// Failure of the physical SSH helper service.
#[derive(Debug, thiserror::Error)]
pub enum ServerError {
    #[error("foreground server cleanup exceeded two seconds")]
    CleanupTimedOut,
    #[error("remote helper stdio failed: {0}")]
    Io(#[from] std::io::Error),
    #[error("remote helper resource cleanup failed: {0:?}")]
    Cleanup(RemoteError),
    #[error("the SSH helper executable requires Linux")]
    UnsupportedPlatform,
}

/// The bundled SSH helper targets Linux; other hosts may still use its client adapters.
/// # Errors
/// Always reports UnsupportedPlatform on non-Linux targets.
#[cfg(not(target_os = "linux"))]
pub async fn run_stdio() -> Result<(), ServerError> {
    Err(ServerError::UnsupportedPlatform)
}
