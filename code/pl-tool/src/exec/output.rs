//! Host history envelopes, task receipt identity and typed host-error mapping.
use pl_core::{
    context::{ContextContent, OpaquePayload, ResourceReference},
    tool::{ToolOutput, opaque::ToolError},
};
use serde::Serialize;
use std::sync::Arc;

pub(super) fn current_receipt(context: &crate::invocation::WorkspaceInvocation) -> Option<String> {
    context
        .tasks
        .as_ref()
        .and_then(|tasks| tasks.current_receipt())
}

pub(super) fn archived_output(
    text: String,
    resources: &[(crate::command::CommandCaptureStream, ResourceReference)],
) -> Result<ToolOutput, ToolError> {
    let payload = OpaquePayload::new("pl.tool.exec", 2, text.clone()).map_err(ToolError::new)?;
    let mut content = vec![ContextContent::Text {
        text: Arc::from(text),
    }];
    for (_, reference) in resources {
        content.push(ContextContent::Resource {
            reference: reference.clone(),
        });
    }
    Ok(ToolOutput::new(payload, content))
}

fn prefix(text: &str, mut bytes: usize) -> &str {
    bytes = bytes.min(text.len());
    while !text.is_char_boundary(bytes) {
        bytes -= 1;
    }
    &text[..bytes]
}

pub(super) fn stdin_unavailable(target: &crate::invocation::CommandTask) -> ToolError {
    #[derive(Serialize)]
    #[serde(rename_all = "camelCase")]
    struct Receipt<'a> {
        target_task_id: &'a str,
        status: pl_core::thread::task::TaskStatus,
        accepted_bytes: u64,
        delivery_pending: bool,
        diagnostic: StdinDiagnostic,
    }
    #[derive(Serialize)]
    #[serde(rename_all = "camelCase")]
    struct StdinDiagnostic {
        code: &'static str,
        next_action: &'static str,
    }
    let receipt = Receipt {
        target_task_id: &target.task_id,
        status: target.status,
        accepted_bytes: 0,
        delivery_pending: false,
        diagnostic: StdinDiagnostic {
            code: if target.tool_id == super::TOOL_EXEC {
                "exec.stdin_closed"
            } else {
                "exec.invalid_arguments"
            },
            next_action: "inspect_original_exec_do_not_restart",
        },
    };
    let output = serde_json::to_string(&receipt)
        .map_err(ToolError::new)
        .and_then(|text| receipt_output("pl.tool.stdin", text));
    let error = ToolError::new(super::ExecFailure::TaskUnavailable {
        task_id: target.task_id.clone(),
        status: target.status,
        cancelled: target.cancel_requested,
    });
    match output {
        Ok(output) => error.with_output(output),
        Err(error) => error,
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
    let output = serde_json::to_string(&receipt)
        .map_err(ToolError::new)
        .and_then(|text| receipt_output("pl.tool.exec", text));
    match output {
        Ok(output) => ToolError::new(source).with_output(output),
        Err(error) => error,
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
    let cancelled = matches!(error.failure, crate::command::CommandRunFailure::Cancelled);
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
    let output = serde_json::to_string(&receipt)
        .map_err(ToolError::new)
        .and_then(|text| receipt_output("pl.tool.exec", text));
    let error = if cancelled {
        ToolError::new(pl_core::thread::ThreadError::Cancelled)
    } else {
        ToolError::new(error)
    };
    match output {
        Ok(output) => error.with_output(output),
        Err(error) => error,
    }
}

/// Metadata-only receipts do not consume the stdout/stderr body budget.
pub(super) fn receipt_output(format: &'static str, text: String) -> Result<ToolOutput, ToolError> {
    let payload = OpaquePayload::new(format, 2, text.clone()).map_err(ToolError::new)?;
    Ok(ToolOutput::new(
        payload,
        vec![ContextContent::Text {
            text: Arc::from(text),
        }],
    ))
}
