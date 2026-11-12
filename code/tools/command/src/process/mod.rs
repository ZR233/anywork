//! Process-domain capabilities and immutable observations.
//!
//! The host owns admission, deadlines, process ownership and confirmed capture prefixes. These
//! interfaces neither create an owner nor equate cancellation with physical exit.
pub mod input;
mod observation;
pub mod output;
pub mod state;

pub use observation::*;
pub use pl_output::TruncatedOutput;
pub use state::*;
pub use tokio_util::sync::CancellationToken;

use std::{error::Error, future::Future, path::PathBuf, time::Duration};

pub const MAX_MODEL_BODY_BYTES: usize = 64 * 1024;

/// A single process operation, before host admission establishes its deadline.
#[derive(Debug)]
pub struct ProcessRequest {
    pub command: String,
    pub cwd: Option<PathBuf>,
    pub allow_workspace_escape: bool,
    pub timeout: Duration,
    pub max_output_bytes: usize,
    pub cancellation: CancellationToken,
}

/// Restricted access to an existing process owner, not a tool-execution callback.
pub trait ProcessExecutor: Send + Sync + 'static {
    type Error: Error + Send + Sync + 'static;

    /// Return only after the original operation has exited and drained, including
    /// when cancellation was requested. Never restart it to recover output.
    fn run(
        &self,
        request: ProcessRequest,
    ) -> impl Future<Output = Result<CommandOutputSnapshot, Self::Error>> + Send;
}

#[derive(Debug)]
pub struct InputRequest<T> {
    pub target: T,
    pub chars: String,
    pub close_stdin: bool,
    pub max_output_bytes: usize,
    pub cancellation: CancellationToken,
}

/// A host-authorized live process, or a terminal EOF observation with no send.
#[derive(Debug)]
pub enum InputTarget<T> {
    Live(T),
    Terminal { status: String },
}

/// Resolves caller-visible receipts through the owning host and uses the same
/// process owner as exec. The opaque target is not a task record or a physical
/// filename that callers can synthesize.
pub trait ProcessInput: Send + Sync + 'static {
    type Target: Send + 'static;
    type Error: Error + Send + Sync + 'static;

    fn resolve(
        &self,
        receipt: &str,
        terminal_eof: bool,
    ) -> Result<InputTarget<Self::Target>, Self::Error>;

    fn write(
        &self,
        request: InputRequest<Self::Target>,
    ) -> impl Future<Output = Result<CommandOutputSnapshot, Self::Error>> + Send;
}
