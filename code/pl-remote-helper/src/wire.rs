//! Private execution protocol; no product, workspace, Thread or recovery state.
use crate::{
    CaptureSpec, CaptureState, CapturedStream, Command, ExecutionError, ProcessExit, Stdio,
    TargetInfo,
};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

pub(crate) const VERSION: u32 = 1;
pub(crate) const RESULT_LIMIT: usize = 8 * 1024;

#[derive(Serialize, Deserialize)]
pub(crate) struct Hello {
    pub wire: u32,
    pub build: String,
    pub target: TargetInfo,
}

#[derive(Serialize, Deserialize)]
pub(crate) struct CommandSpec {
    pub program: String,
    pub arguments: Vec<String>,
    pub cwd: Option<String>,
    pub environment: BTreeMap<String, Option<String>>,
    pub clear_environment: bool,
    pub stdin: Stdio,
    pub stdout: Stdio,
    pub stderr: Stdio,
    pub capture: Option<CaptureSpec>,
}

impl From<&Command> for CommandSpec {
    fn from(command: &Command) -> Self {
        Self {
            program: command.program.clone(),
            arguments: command.arguments.clone(),
            cwd: command.cwd.clone(),
            environment: command.environment.clone(),
            clear_environment: command.clear_environment,
            stdin: command.stdin.unwrap_or(Stdio::Null),
            stdout: command.stdout.unwrap_or(Stdio::Null),
            stderr: command.stderr.unwrap_or(Stdio::Null),
            capture: command.capture.clone(),
        }
    }
}

#[derive(Serialize, Deserialize)]
pub(crate) enum Failure {
    InvalidInput(String),
    Io {
        operation: String,
        kind: String,
        raw_os_error: Option<i32>,
    },
    Protocol(String),
    Cancelled,
}

impl From<&ExecutionError> for Failure {
    fn from(error: &ExecutionError) -> Self {
        match error {
            ExecutionError::Io { operation, source } => Self::Io {
                operation: (*operation).into(),
                kind: format!("{:?}", source.kind()),
                raw_os_error: source.raw_os_error(),
            },
            ExecutionError::InvalidInput(message) => Self::InvalidInput(message.clone()),
            ExecutionError::Cancelled => Self::Cancelled,
            _ => Self::Protocol(error.to_string()),
        }
    }
}
impl From<Failure> for ExecutionError {
    fn from(error: Failure) -> Self {
        match error {
            Failure::InvalidInput(message) => Self::InvalidInput(message),
            Failure::Io {
                operation,
                kind,
                raw_os_error,
            } => Self::io(
                "target IO",
                match raw_os_error {
                    Some(code) => std::io::Error::from_raw_os_error(code),
                    None => std::io::Error::other(format!("{operation}: {kind}")),
                },
            ),
            Failure::Protocol(message) => Self::Protocol(message),
            Failure::Cancelled => Self::Cancelled,
        }
    }
}

pub(crate) type ExitOutcome = Result<ProcessExit, Failure>;

#[derive(Serialize, Deserialize)]
pub(crate) struct CaptureOutcome {
    pub state: CaptureState,
    pub confirmed_bytes: Option<u64>,
    pub error: Option<Failure>,
}
impl From<CapturedStream> for CaptureOutcome {
    fn from(value: CapturedStream) -> Self {
        Self {
            state: value.state,
            confirmed_bytes: value.confirmed_bytes,
            error: value.error.map(|source| Failure::Io {
                operation: "capture".into(),
                kind: format!("{:?}", source.kind()),
                raw_os_error: source.raw_os_error(),
            }),
        }
    }
}
impl From<CaptureOutcome> for CapturedStream {
    fn from(value: CaptureOutcome) -> Self {
        Self {
            state: value.state,
            confirmed_bytes: value.confirmed_bytes,
            error: value.error.map(|error| {
                std::sync::Arc::new(std::io::Error::other(ExecutionError::from(error)))
            }),
        }
    }
}
