//! Startup errors retain whether business Start may have reached its owner.
use pl_protocol::PureError;

#[derive(Debug, Clone, Copy, serde::Serialize)]
pub enum CommandRunFailure {
    #[serde(rename = "exec.argument_out_of_range")]
    ArgumentOutOfRange,
    #[serde(rename = "exec.start_failed")]
    StartFailed,
    #[serde(rename = "exec.start_uncertain")]
    StartUncertain,
    #[serde(rename = "exec.cancelled")]
    Cancelled,
    #[serde(rename = "exec.timed_out")]
    TimedOut,
    #[serde(rename = "exec.archive_failed")]
    OutputPublication,
}

#[derive(Debug, thiserror::Error)]
#[error("{source}")]
pub struct CommandRunError {
    pub failure: CommandRunFailure,
    pub process_started: Option<bool>,
    #[source]
    pub source: PureError,
}
