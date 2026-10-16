use pl_output::OutputTruncation;

use super::{
    CommandOutputSnapshot, CommandProcessFailure, CommandProcessFinalResult,
    CommandProcessLifecycle, CommandProcessState, CommandTerminationReason,
};

/// 一条截断指示行在可见正文里占用的字节上界。
///
pub(super) fn message_for_state(
    state: &CommandProcessState,
    process_id: Option<&str>,
    output_file: &std::path::Path,
) -> String {
    match &state.lifecycle {
        CommandProcessLifecycle::Running(_) => format!(
            "Command is still running. Use wait for completion or write_stdin with taskId '{}' to send input. Read outputFile for complete output.",
            process_id.unwrap_or_default()
        ),
        CommandProcessLifecycle::Terminating(state) => format!(
            "Command {} and termination is in progress for task '{}'. Use wait for completion. Read outputFile for captured output.",
            state.reason().message_fragment(),
            process_id.unwrap_or_default()
        ),
        CommandProcessLifecycle::Draining(_) => format!(
            "Command exited and is draining remaining output for task '{}'. Use wait for completion. Read outputFile for complete output.",
            process_id.unwrap_or_default()
        ),
        CommandProcessLifecycle::Final(state) => match state.result() {
            CommandProcessFinalResult::Succeeded { .. } => {
            "Command completed successfully. Read outputFile for complete output if needed."
                .to_string()
            }
            CommandProcessFinalResult::Failed { failure } => format!(
                "{}. Full command output is available at '{}'.",
                failure_message(failure),
                output_file.display()
            ),
            CommandProcessFinalResult::TimedOut => {
            "Command timed out and was terminated. Read outputFile for captured output.".to_string()
            }
            CommandProcessFinalResult::Cancelled => {
            "Command was interrupted and termination was requested. Read outputFile for captured output."
                .to_string()
            }
        },
    }
}

fn failure_message(failure: &CommandProcessFailure) -> String {
    match failure {
        CommandProcessFailure::Exited { exit_code } => format!(
            "Command exited with code {}",
            exit_code.map_or_else(|| "unknown".to_string(), |code| code.to_string())
        ),
        CommandProcessFailure::Wait { message } | CommandProcessFailure::Output { message, .. } => {
            message.clone()
        }
    }
}

impl CommandTerminationReason {
    fn message_fragment(self) -> &'static str {
        match self {
            Self::TimedOut => "timed out",
            Self::Cancelled => "was cancelled",
            Self::OutputFailed => "output capture could not continue",
        }
    }
}

impl From<&CommandOutputSnapshot> for OutputTruncation {
    fn from(snapshot: &CommandOutputSnapshot) -> Self {
        Self {
            stdout: snapshot.stdout.clone(),
            stderr: snapshot.stderr.clone(),
        }
    }
}
