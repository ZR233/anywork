use pl_output::{OutputTruncation, TruncatedOutput, TruncationStrategy};

use super::{
    CommandOutputSnapshot, CommandProcessFailure, CommandProcessFinalResult,
    CommandProcessLifecycle, CommandProcessState, CommandTerminationReason,
};

/// 一条截断指示行在可见正文里占用的字节上界。
///
/// [`TruncationStrategy`] 保留的是 head + tail **字节**，指示行本身还要另外占字节
/// （`"... [N characters omitted] ..."`，N 最多 20 位十进制）。按字节上限分配预算时先扣掉这份
/// 上界，可见正文之和才不会因为指示行而越过上限。
const MODEL_OUTPUT_MARKER_BYTES: usize = 64;

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

/// 按**字节**预算截断一段模型可见正文。
///
/// `max_bytes` 的计量单位是字节：`TruncationStrategy` 的 head/tail 都是字节上限，多字节字符
/// 按其在 `String` 中的实际长度计入，因此这里不是 Unicode 字符数，函数名与参数名都不按字符称。
pub(super) fn truncate_text(text: &str, max_bytes: usize) -> TruncatedOutput {
    let head = max_bytes / 2;
    let tail = max_bytes.saturating_sub(head);
    TruncationStrategy::new(head, tail).truncate(text)
}

/// 将已投影正文限制在硬字节预算内，并保留原始长度和截断事实。
///
/// 预算不足以放下省略标记时，仅保留能容纳的 UTF-8 前缀；截断事实仍由结构化字段报告。
pub(super) fn limit_model_output(output: TruncatedOutput, max_bytes: usize) -> TruncatedOutput {
    if output.content.len() <= max_bytes {
        return output;
    }
    let original_length = output.original_length;
    let mut limited = if max_bytes < MODEL_OUTPUT_MARKER_BYTES {
        output
    } else {
        truncate_text(&output.content, max_bytes - MODEL_OUTPUT_MARKER_BYTES)
    };
    let boundary = limited
        .content
        .floor_char_boundary(max_bytes.min(limited.content.len()));
    limited.content.truncate(boundary);
    limited.original_length = original_length;
    limited.was_truncated = true;
    limited
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
