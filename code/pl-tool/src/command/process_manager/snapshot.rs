use super::{
    CommandProcessFailure, CommandProcessFinalResult, CommandProcessLifecycle, CommandProcessState,
};

/// 一条截断指示行在可见正文里占用的字节上界。
///
pub(super) fn message_for_state(state: &CommandProcessState) -> String {
    match &state.lifecycle {
        CommandProcessLifecycle::Running(_) => "Command is running.".into(),
        CommandProcessLifecycle::Terminating(state) => format!(
            "Command {}; termination is in progress.",
            state.reason().message_fragment()
        ),
        CommandProcessLifecycle::Draining(_) => {
            "Command exited; its owner is draining captured output.".into()
        }
        CommandProcessLifecycle::Final(state) => match state.result() {
            CommandProcessFinalResult::Succeeded { .. } => {
                "Command completed successfully.".to_string()
            }
            CommandProcessFinalResult::Failed { failure } => failure_message(failure),
            CommandProcessFinalResult::TimedOut => {
                "Command timed out and was terminated.".to_string()
            }
            CommandProcessFinalResult::Cancelled => {
                "Command was interrupted and its process tree was reaped.".to_string()
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
