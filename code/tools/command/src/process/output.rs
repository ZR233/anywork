//! Domain record formatting shared by command execution and stdin observations.
use crate::process::{
    CommandCaptureFailure, CommandOutputSnapshot, CommandProcessFinalResult,
    CommandProcessLifecycle,
};
use serde::Serialize;
use std::path::Path;

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
struct Record<'a, R> {
    task_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    target_task_id: Option<&'a str>,
    state: &'a CommandProcessLifecycle,
    process_started: Option<bool>,
    exit_code: Option<i32>,
    signal: Option<i32>,
    supervision_failure: Option<&'a str>,
    input_receipt: Option<&'a crate::process::CommandInputReceipt>,
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
    stdout_resource: Option<&'a R>,
    stderr_resource: Option<&'a R>,
    requested_body_bytes: usize,
    effective_body_bytes: usize,
    diagnostic: Option<Diagnostic<'a>>,
    next_action: &'static str,
}

fn stream<'a>(
    snapshot: &CommandOutputSnapshot,
    kind: crate::process::CommandCaptureStream,
    content: &'a str,
) -> Stream<'a> {
    let (original, marker, lossy, confirmed) = match kind {
        crate::process::CommandCaptureStream::Stdout => (
            &snapshot.stdout,
            &snapshot.stdout_omission_marker,
            snapshot.stdout_text_lossy,
            snapshot.capture_offsets.stdout,
        ),
        crate::process::CommandCaptureStream::Stderr => (
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

pub fn projection<R: Serialize>(
    snapshot: &CommandOutputSnapshot,
    resources: &[(crate::process::CommandCaptureStream, R)],
    task_id: Option<String>,
    requested: usize,
    target_task_id: Option<&str>,
) -> Result<String, serde_json::Error> {
    let resource_for = |stream| {
        resources
            .iter()
            .find(|(kind, _)| *kind == stream)
            .map(|(_, resource)| resource)
    };
    let stdout_resource = resource_for(crate::process::CommandCaptureStream::Stdout);
    let stderr_resource = resource_for(crate::process::CommandCaptureStream::Stderr);
    let archived = stdout_resource.is_some() && stderr_resource.is_some();
    let input_failure = snapshot
        .input_receipt
        .as_ref()
        .and_then(|receipt| match receipt.outcome {
            crate::process::CommandInputOutcome::Partial => Some(ExecDiagnosticCode::StdinPartial),
            crate::process::CommandInputOutcome::Failed => Some(ExecDiagnosticCode::StdinClosed),
            crate::process::CommandInputOutcome::Cancelled => Some(ExecDiagnosticCode::Cancelled),
            crate::process::CommandInputOutcome::Complete => None,
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
    let record = Record {
        task_id,
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
            crate::process::CommandCaptureStream::Stdout,
            &snapshot.stdout.content,
        ),
        stderr: stream(
            snapshot,
            crate::process::CommandCaptureStream::Stderr,
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
        effective_body_bytes: requested.min(crate::process::MAX_MODEL_BODY_BYTES).min(
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
    serde_json::to_string(&record)
}

fn prefix(text: &str, mut bytes: usize) -> &str {
    bytes = bytes.min(text.len());
    while !text.is_char_boundary(bytes) {
        bytes -= 1;
    }
    &text[..bytes]
}
