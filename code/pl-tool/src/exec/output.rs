//! Task receipt identity, resource references and typed host-error mapping.
use pl_core::tool::{ToolOutput, opaque::ToolError};
use serde::Serialize;

pub(super) fn current_receipt(context: &crate::invocation::WorkspaceInvocation) -> Option<String> {
    context
        .tasks
        .as_ref()
        .and_then(|tasks| tasks.current_receipt())
}

fn prefix(text: &str, mut bytes: usize) -> &str {
    bytes = bytes.min(text.len());
    while !text.is_char_boundary(bytes) {
        bytes -= 1;
    }
    &text[..bytes]
}

pub(super) fn stdin_unavailable(
    task_id: Option<String>,
    target: &crate::invocation::CommandTask,
) -> ToolError {
    #[derive(Serialize)]
    #[serde(rename_all = "camelCase")]
    struct Receipt<'a> {
        task_id: Option<String>,
        target_task_id: &'a str,
        status: pl_core::thread::task::TaskStatus,
        input_receipt: serde_json::Value,
        diagnostic: StdinDiagnostic,
    }
    #[derive(Serialize)]
    #[serde(rename_all = "camelCase")]
    struct StdinDiagnostic {
        code: &'static str,
        next_action: &'static str,
    }
    let receipt = Receipt {
        task_id,
        target_task_id: &target.task_id,
        status: target.status,
        input_receipt: serde_json::json!({"acceptedBytes": 0, "outcome": "notSent"}),
        diagnostic: StdinDiagnostic {
            code: if target.tool_id == super::TOOL_EXEC {
                "exec.stdin_closed"
            } else {
                "exec.invalid_arguments"
            },
            next_action: "inspect_original_exec_do_not_restart",
        },
    };
    let output = serde_json::to_value(&receipt).map(ToolOutput::json);
    let error = ToolError::new(super::ExecFailure::TaskUnavailable {
        task_id: target.task_id.clone(),
        status: target.status,
        cancelled: target.cancel_requested,
    });
    match output {
        Ok(output) => error.with_output(output),
        Err(error) => ToolError::new(error),
    }
}

/// Keeps the host's typed permission source with an exec-specific no-start receipt.
pub fn permission_denied(source: impl std::error::Error + Send + Sync + 'static) -> ToolError {
    #[derive(Serialize)]
    struct Denial<'a> {
        code: &'static str,
        stage: &'static str,
        detail: &'a str,
    }
    #[derive(Serialize)]
    #[serde(rename_all = "camelCase")]
    struct Receipt<'a> {
        diagnostic: Denial<'a>,
        process_started: bool,
    }
    let detail = source.to_string();
    let receipt = Receipt {
        diagnostic: Denial {
            code: "exec.permission_denied",
            stage: "authorize",
            detail: prefix(&detail, 4096),
        },
        process_started: false,
    };
    let output = serde_json::to_value(&receipt).map(ToolOutput::json);
    match output {
        Ok(output) => ToolError::new(source).with_output(output),
        Err(error) => ToolError::new(error),
    }
}

pub(super) fn start_error(
    error: crate::command::CommandRunError,
    context: &crate::invocation::WorkspaceInvocation,
) -> ToolError {
    #[derive(Serialize)]
    #[serde(rename_all = "camelCase")]
    struct StartReceipt<'a> {
        task_id: Option<String>,
        process_started: Option<bool>,
        diagnostic: StartDiagnostic<'a>,
    }
    #[derive(Serialize)]
    #[serde(rename_all = "camelCase")]
    struct StartDiagnostic<'a> {
        code: crate::command::CommandRunFailure,
        detail: &'a str,
        next_action: &'static str,
    }
    let detail = error.to_string();
    let receipt = StartReceipt {
        task_id: current_receipt(context),
        process_started: error.process_started,
        diagnostic: StartDiagnostic {
            code: error.failure,
            detail: prefix(&detail, 4096),
            next_action: if matches!(
                error.failure,
                crate::command::CommandRunFailure::ArgumentOutOfRange
            ) {
                "correct_arguments"
            } else {
                "inspect_original_task_do_not_reexecute"
            },
        },
    };
    let output = serde_json::to_value(&receipt).map(ToolOutput::json);
    let error = ToolError::new(error);
    match output {
        Ok(output) => error.with_output(output),
        Err(error) => ToolError::new(error),
    }
}
