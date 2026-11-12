//! Physical process and filesystem capabilities over a single foreground HTTP/2 connection.

pub mod process_worker_protocol;
pub mod start_control;

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
/// Exact foreground execution wire version used by bundled-asset verification.
pub const EXECUTOR_WIRE_VERSION: u32 = wire::VERSION;
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

/// Host process creation and background ownership shared by execution adapters.
pub mod process;

/// Host-side physical process supervision, shared by local execution and the SSH service.
#[cfg(target_os = "linux")]
pub mod client;

/// Failure of the physical SSH helper service.
#[derive(Debug, thiserror::Error)]
pub enum ServerError {
    #[error("foreground server cleanup exceeded two seconds")]
    CleanupTimedOut,
    #[error("remote helper stdio failed: {0}")]
    Io(#[from] std::io::Error),
    #[error("the SSH helper executable requires Linux")]
    UnsupportedPlatform,
}
