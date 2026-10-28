//! Exec-owned records and bounded model projections; no execution state lives here.
use crate::command::{
    CommandCaptureFailure, CommandOutputSnapshot, CommandProcessFinalResult,
    CommandProcessLifecycle,
};
use pl_core::{
    context::{ContextContent, OpaquePayload, ResourceReference},
    tool::{
        ToolOutput,
        opaque::{CallContext, ToolError},
    },
};
use serde::Serialize;
use std::{path::Path, sync::Arc};

#[derive(Debug, Clone, Copy, Serialize)]
enum ExecDiagnosticCode {
    #[serde(rename = "exec.stdin_partial")]
    StdinPartial,
    #[serde(rename = "exec.stdin_closed")]
    StdinClosed,
    #[serde(rename = "exec.exit_nonzero")]
    ExitNonzero,
    #[serde(rename = "exec.timed_out")]
    TimedOut,
    #[serde(rename = "exec.cancelled")]
    Cancelled,
    #[serde(rename = "exec.output_limit")]
    OutputLimit,
    #[serde(rename = "exec.capture_io")]
    CaptureIo,
    #[serde(rename = "exec.archive_failed")]
    ArchiveFailed,
    #[serde(rename = "exec.start_uncertain")]
    StartUncertain,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Diagnostic<'a> {
    code: ExecDiagnosticCode,
    detail: &'a str,
    next_action: &'static str,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Stream<'a> {
    content: &'a str,
    original_bytes: usize,
    displayed_bytes: usize,
    omitted_bytes: Option<usize>,
    text_lossy: bool,
    was_truncated: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Record<'a> {
    task_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    target_task_id: Option<&'a str>,
    state: &'a CommandProcessLifecycle,
    process_started: Option<bool>,
    exit_code: Option<i32>,
    signal: Option<i32>,
    supervision_failure: Option<&'a str>,
    input_receipt: Option<&'a crate::command::CommandInputReceipt>,
    stdout: Stream<'a>,

    stderr: Stream<'a>,
    stdout_file: &'a Path,
    stderr_file: &'a Path,
    captured_bytes: Option<u64>,
    confirmed_bytes: u64,
    stdout_confirmed_bytes: u64,
    stderr_confirmed_bytes: u64,
    capture_status: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    archive_status: Option<&'static str>,
    stdout_resource: Option<&'a ResourceReference>,
    stderr_resource: Option<&'a ResourceReference>,
    requested_body_bytes: usize,
    effective_body_bytes: usize,
    diagnostic: Option<Diagnostic<'a>>,
    next_action: &'static str,
}

fn stream<'a>(
    snapshot: &CommandOutputSnapshot,
    kind: crate::command::CommandCaptureStream,
    content: &'a str,
) -> Stream<'a> {
    let (original, marker, lossy, confirmed) = match kind {
        crate::command::CommandCaptureStream::Stdout => (
            &snapshot.stdout,
            &snapshot.stdout_omission_marker,
            snapshot.stdout_text_lossy,
            snapshot.capture_offsets.stdout,
        ),
        crate::command::CommandCaptureStream::Stderr => (
            &snapshot.stderr,
            &snapshot.stderr_omission_marker,
            snapshot.stderr_text_lossy,
            snapshot.capture_offsets.stderr,
        ),
    };
    let original_bytes = original
        .original_length
        .max(usize::try_from(confirmed).unwrap_or(usize::MAX));
    let marker_bytes = marker.as_ref().map_or(0, |range| {
        range.end.min(content.len()).saturating_sub(range.start)
    });
    let source_displayed = content.len().saturating_sub(marker_bytes);
    let was_truncated = original.was_truncated
        || content.len() < original.content.len()
        || original_bytes > original.original_length;
    Stream {
        content,
        original_bytes,
        displayed_bytes: content.len(),
        omitted_bytes: if lossy && was_truncated {
            None
        } else if lossy {
            Some(0)
        } else {
            Some(original_bytes.saturating_sub(source_displayed))
        },
        text_lossy: lossy,
        was_truncated,
    }
}

pub(super) fn projection(
    snapshot: &CommandOutputSnapshot,
    resources: &[(crate::command::CommandCaptureStream, ResourceReference)],
    context: &CallContext,
    requested: usize,
    target_task_id: Option<&str>,
) -> Result<ToolOutput, ToolError> {
    let resource_for = |stream| {
        resources
            .iter()
            .find(|(kind, _)| *kind == stream)
            .map(|(_, resource)| resource)
    };
    let stdout_resource = resource_for(crate::command::CommandCaptureStream::Stdout);
    let stderr_resource = resource_for(crate::command::CommandCaptureStream::Stderr);
    let archived = stdout_resource.is_some() && stderr_resource.is_some();
    let input_failure = snapshot
        .input_receipt
        .as_ref()
        .and_then(|receipt| match receipt.outcome {
            crate::command::CommandInputOutcome::Partial => Some(ExecDiagnosticCode::StdinPartial),
            crate::command::CommandInputOutcome::Failed => Some(ExecDiagnosticCode::StdinClosed),
            crate::command::CommandInputOutcome::Cancelled => Some(ExecDiagnosticCode::Cancelled),
            crate::command::CommandInputOutcome::Complete => None,
        });
    let code = input_failure.or_else(|| match snapshot.state.final_result() {
        Some(CommandProcessFinalResult::Cancelled) => Some(ExecDiagnosticCode::Cancelled),
        _ if matches!(
            snapshot.output_failure,
            Some(CommandCaptureFailure::OutputLimitExceeded { .. })
        ) =>
        {
            Some(ExecDiagnosticCode::OutputLimit)
        }
        _ if snapshot.output_failure.is_some() || snapshot.supervision_failure.is_some() => {
            Some(ExecDiagnosticCode::CaptureIo)
        }
        Some(CommandProcessFinalResult::TimedOut) => Some(ExecDiagnosticCode::TimedOut),
        Some(CommandProcessFinalResult::Failed { .. }) if snapshot.state.exit_code().is_some() => {
            Some(ExecDiagnosticCode::ExitNonzero)
        }
        Some(CommandProcessFinalResult::Failed { .. }) => Some(ExecDiagnosticCode::StartUncertain),
        _ if snapshot.state.final_result().is_some() && !archived && target_task_id.is_none() => {
            Some(ExecDiagnosticCode::ArchiveFailed)
        }
        _ => None,
    });
    let next_action = if input_failure.is_some() {
        "inspect_input_receipt_do_not_resend"
    } else if snapshot.state.final_result().is_none() {
        "wait_same_task"
    } else if code.is_some() {
        "inspect_original_result"
    } else {
        "read_original_output_if_needed"
    };
    let mut detail_end = snapshot.message.len().min(4096);
    while !snapshot.message.is_char_boundary(detail_end) {
        detail_end -= 1;
    }
    let mut record = Record {
        task_id: context.tasks.as_ref().and_then(|tasks| {
            tasks
                .list()
                .into_iter()
                .find(|task| task.call_id == context.call_id)
                .map(|task| task.id)
        }),
        target_task_id,
        state: &snapshot.state,
        process_started: (snapshot.exit_code.is_some()
            || snapshot.signal.is_some()
            || snapshot.stdout.original_length > 0
            || snapshot.stderr.original_length > 0)
            .then_some(true),
        exit_code: snapshot.exit_code,
        signal: snapshot.signal,
        supervision_failure: snapshot
            .supervision_failure
            .as_deref()
            .map(|text| prefix(text, 4096)),
        input_receipt: snapshot.input_receipt.as_ref(),
        stdout: stream(
            snapshot,
            crate::command::CommandCaptureStream::Stdout,
            &snapshot.stdout.content,
        ),
        stderr: stream(
            snapshot,
            crate::command::CommandCaptureStream::Stderr,
            &snapshot.stderr.content,
        ),
        stdout_file: &snapshot.output_file,
        stderr_file: &snapshot.stderr_output_file,
        captured_bytes: snapshot.capture_usage.map(|usage| usage.captured_bytes),
        confirmed_bytes: snapshot.capture_offsets.total(),
        stdout_confirmed_bytes: snapshot.capture_offsets.stdout,
        stderr_confirmed_bytes: snapshot.capture_offsets.stderr,
        capture_status: if snapshot.state.final_result().is_none() {
            "inProgress"
        } else if snapshot.output_failure.is_some() {
            "partial"
        } else if snapshot.capture_usage.is_some() {
            "complete"
        } else {
            "unknown"
        },
        archive_status: target_task_id.is_none().then_some(if archived {
            "retained"
        } else if snapshot.state.final_result().is_some() {
            "failed"
        } else {
            "pending"
        }),
        stdout_resource,
        stderr_resource,
        requested_body_bytes: requested,
        effective_body_bytes: requested.min(super::MAX_MODEL_OUTPUT_BYTES).min(
            snapshot
                .model_output_bytes_cap
                .and_then(|cap| usize::try_from(cap).ok())
                .unwrap_or(usize::MAX),
        ),
        diagnostic: code.map(|code| Diagnostic {
            code,
            detail: &snapshot.message[..detail_end],
            next_action,
        }),
        next_action,
    };
    let payload = OpaquePayload::new(
        "pl.tool.exec",
        2,
        serde_json::to_string(&record).map_err(ToolError::new)?,
    )
    .map_err(ToolError::new)?;
    let content = loop {
        let mut content = vec![ContextContent::Text {
            text: Arc::from(serde_json::to_string(&record).map_err(ToolError::new)?),
        }];
        for (_, reference) in resources {
            content.push(ContextContent::Resource {
                reference: reference.clone(),
            });
        }
        let bytes = serde_json::to_vec(&content).map_err(ToolError::new)?.len();
        if bytes <= super::MAX_MODEL_OUTPUT_BYTES {
            break content;
        }
        if record.stdout.content.is_empty() && record.stderr.content.is_empty() {
            break vec![ContextContent::Text {
                text: Arc::from(
                    "{\"diagnostic\":{\"code\":\"exec.metadata_too_large\",\"nextAction\":\"query_original_payload\"},\"processStarted\":null,\"wasTruncated\":true}",
                ),
            }];
        }
        // Rebuild valid JSON at each step. Never split serialized JSON or required metadata.
        let reduce = (bytes - super::MAX_MODEL_OUTPUT_BYTES).div_ceil(2).max(1);
        let stdout_len = record.stdout.content.len();
        let stderr_len = record.stderr.content.len();
        let total = stdout_len + stderr_len;
        let out_reduce = ((reduce as u128 * stdout_len as u128) / total as u128) as usize;
        record.stdout = stream(
            snapshot,
            crate::command::CommandCaptureStream::Stdout,
            prefix(record.stdout.content, stdout_len.saturating_sub(out_reduce)),
        );
        record.stderr = stream(
            snapshot,
            crate::command::CommandCaptureStream::Stderr,
            prefix(
                record.stderr.content,
                stderr_len.saturating_sub(reduce - out_reduce),
            ),
        );
    };
    Ok(ToolOutput::new(payload, content))
}

fn prefix(text: &str, mut bytes: usize) -> &str {
    bytes = bytes.min(text.len());
    while !text.is_char_boundary(bytes) {
        bytes -= 1;
    }
    &text[..bytes]
}

pub(super) fn stdin_unavailable(target: &pl_core::thread::task::TaskRecord) -> ToolError {
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
        target_task_id: &target.id,
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
        task_id: target.id.clone(),
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
    context: &CallContext,
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
        task_id: context.tasks.as_ref().and_then(|tasks| {
            tasks
                .list()
                .into_iter()
                .find(|task| task.call_id == context.call_id)
                .map(|task| task.id)
        }),
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

/// Error receipts obey the same serialized-content budget as successful exec projections.
/// The immutable payload keeps complete identities even when metadata alone exceeds the cap.
pub(super) fn receipt_output(format: &'static str, text: String) -> Result<ToolOutput, ToolError> {
    let payload = OpaquePayload::new(format, 2, text.clone()).map_err(ToolError::new)?;
    let mut content = vec![ContextContent::Text {
        text: Arc::from(text),
    }];
    if serde_json::to_vec(&content).map_err(ToolError::new)?.len() > super::MAX_MODEL_OUTPUT_BYTES {
        content = vec![ContextContent::Text {
            text: Arc::from(
                "{\"diagnostic\":{\"code\":\"exec.metadata_too_large\",\"nextAction\":\"query_original_payload\"},\"wasTruncated\":true}",
            ),
        }];
    }
    Ok(ToolOutput::new(payload, content))
}
