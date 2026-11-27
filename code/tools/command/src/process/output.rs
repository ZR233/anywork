//! Command result projections from one process and capture observation.
use crate::process::{
    CommandCaptureFailure, CommandOutputSnapshot, CommandProcessFailure, CommandProcessFinalResult,
    CommandProcessLifecycle,
};
use serde::Serialize;
use serde_json::{Value, json};
use std::path::Path;

#[derive(Debug, Clone, Copy, Serialize)]
enum ExecDiagnosticCode {
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
    #[serde(rename = "exec.signalled")]
    Signalled,
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
struct Stream {
    original_bytes: usize,
    displayed_bytes: usize,
    omitted_bytes: Option<usize>,
    text_lossy: bool,
    was_truncated: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CaptureDetails<'a, R> {
    state: &'a CommandProcessLifecycle,
    exit_code: Option<i32>,
    signal: Option<i32>,
    output_failure: Option<&'a CommandCaptureFailure>,
    stdout: Stream,
    stderr: Stream,
    capture_file: &'a Path,
    stderr_capture_file: &'a Path,
    stdout_file: &'a Path,
    stderr_file: &'a Path,
    confirmed_bytes: Option<u64>,
    stdout_confirmed_bytes: Option<u64>,
    stderr_confirmed_bytes: Option<u64>,
    capture_status: &'static str,
    capture: Option<&'a crate::process::CommandCaptureResult>,
    archive_status: &'static str,
    stdout_resource: Option<&'a R>,
    stderr_resource: Option<&'a R>,
    requested_body_bytes: usize,
    effective_body_bytes: usize,
}

fn stream(
    snapshot: &CommandOutputSnapshot,
    kind: crate::process::CommandCaptureStream,
    content: &str,
) -> Stream {
    let (original, marker, lossy, confirmed) = match kind {
        crate::process::CommandCaptureStream::Stdout => (
            &snapshot.stdout,
            &snapshot.stdout_omission_marker,
            snapshot.stdout_text_lossy,
            snapshot.confirmed_bytes(crate::process::CommandCaptureStream::Stdout),
        ),
        crate::process::CommandCaptureStream::Stderr => (
            &snapshot.stderr,
            &snapshot.stderr_omission_marker,
            snapshot.stderr_text_lossy,
            snapshot.confirmed_bytes(crate::process::CommandCaptureStream::Stderr),
        ),
    };
    let original_bytes = original.original_length.max(
        confirmed
            .and_then(|count| usize::try_from(count).ok())
            .unwrap_or(original.original_length),
    );
    let marker_bytes = marker.as_ref().map_or(0, |range| {
        range.end.min(content.len()).saturating_sub(range.start)
    });
    let source_displayed = content.len().saturating_sub(marker_bytes);
    let was_truncated = original.was_truncated
        || content.len() < original.content.len()
        || original_bytes > original.original_length;
    Stream {
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
    task_id: Option<&str>,
    requested: usize,
) -> Result<pl_agent_tool::ToolResult<String>, serde_json::Error> {
    let resource_for = |stream| {
        resources
            .iter()
            .find(|(kind, _)| *kind == stream)
            .map(|(_, resource)| resource)
    };
    let stdout_resource = resource_for(crate::process::CommandCaptureStream::Stdout);
    let stderr_resource = resource_for(crate::process::CommandCaptureStream::Stderr);
    let archived = stdout_resource.is_some() && stderr_resource.is_some();
    let code = match snapshot.state.final_result() {
        Some(CommandProcessFinalResult::Cancelled) => Some(ExecDiagnosticCode::Cancelled),
        _ if matches!(
            snapshot.output_failure,
            Some(CommandCaptureFailure::OutputLimitExceeded { .. })
        ) =>
        {
            Some(ExecDiagnosticCode::OutputLimit)
        }
        _ if snapshot.output_failure.is_some() => Some(ExecDiagnosticCode::CaptureIo),
        Some(CommandProcessFinalResult::TimedOut) => Some(ExecDiagnosticCode::TimedOut),
        _ if snapshot.signal.is_some() => Some(ExecDiagnosticCode::Signalled),
        Some(CommandProcessFinalResult::Failed { failure })
            if !matches!(
                failure,
                CommandProcessFailure::Exited { exit_code: Some(_) }
            ) =>
        {
            Some(ExecDiagnosticCode::StartUncertain)
        }
        _ if snapshot.state.final_result().is_some() && !archived => {
            Some(ExecDiagnosticCode::ArchiveFailed)
        }
        _ => None,
    };
    let mut detail_end = snapshot.message.len().min(4096);
    while !snapshot.message.is_char_boundary(detail_end) {
        detail_end -= 1;
    }
    let record = CaptureDetails {
        state: &snapshot.state,
        exit_code: snapshot.exit_code,
        signal: snapshot.signal,
        output_failure: snapshot.output_failure.as_ref(),
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
        capture_file: &snapshot.capture_file,
        stderr_capture_file: &snapshot.stderr_capture_file,
        confirmed_bytes: snapshot
            .capture
            .as_ref()
            .and_then(|capture| capture.confirmed_total()),
        stdout_confirmed_bytes: snapshot
            .confirmed_bytes(crate::process::CommandCaptureStream::Stdout),
        stderr_confirmed_bytes: snapshot
            .confirmed_bytes(crate::process::CommandCaptureStream::Stderr),
        capture_status: if snapshot.state.final_result().is_none() {
            "inProgress"
        } else if snapshot.output_failure.is_some() {
            "partial"
        } else if snapshot
            .capture
            .as_ref()
            .is_some_and(|capture| capture.complete())
        {
            "complete"
        } else {
            "unknown"
        },
        capture: snapshot.capture.as_ref(),
        archive_status: if archived {
            "retained"
        } else if snapshot.state.final_result().is_some() {
            "failed"
        } else {
            "pending"
        },
        stdout_resource,
        stderr_resource,
        requested_body_bytes: requested,
        effective_body_bytes: requested.min(crate::process::MAX_MODEL_BODY_BYTES).min(
            snapshot
                .model_output_bytes_cap
                .and_then(|cap| usize::try_from(cap).ok())
                .unwrap_or(usize::MAX),
        ),
    };
    let mut data = json!({
        "taskId": task_id,
        "exitCode": snapshot.exit_code,
        "stdout": snapshot.stdout.content,
        "stderr": snapshot.stderr.content,
    });
    let values = data.as_object_mut().expect("command data is an object");
    if let Some(signal) = snapshot.signal {
        values.insert("signal".into(), signal.into());
    }
    if let Some(code) = code {
        let diagnostic = Diagnostic {
            code,
            detail: match code {
                ExecDiagnosticCode::ArchiveFailed => {
                    "Complete capture resources could not be retained"
                }
                _ => &snapshot.message[..detail_end],
            },
            next_action: "inspect_original_result",
        };
        values.insert("diagnostic".into(), serde_json::to_value(diagnostic)?);
        values.insert("captureStatus".into(), record.capture_status.into());
        values.insert("archiveStatus".into(), record.archive_status.into());
        values.insert(
            "stdoutFile".into(),
            serde_json::to_value(record.stdout_file)?,
        );
        values.insert(
            "stderrFile".into(),
            serde_json::to_value(record.stderr_file)?,
        );
    }
    for (name, stream, path) in [
        ("stdout", &record.stdout, record.stdout_file),
        ("stderr", &record.stderr, record.stderr_file),
    ] {
        if stream.was_truncated {
            values.insert(format!("{name}WasTruncated"), true.into());
            values.insert(
                format!("{name}OmittedBytes"),
                Value::from(stream.omitted_bytes),
            );
        }
        if stream.text_lossy {
            values.insert(format!("{name}TextLossy"), true.into());
        }
        if stream.was_truncated || stream.text_lossy {
            values.insert(format!("{name}File"), serde_json::to_value(path)?);
        }
    }

    let mut text = String::from("Command");
    if let Some(task_id) = task_id {
        text.push_str(&format!(" {task_id}"));
    }
    if let Some(code) = snapshot.exit_code {
        text.push_str(&format!(" exited with code {code}."));
    } else if let Some(signal) = snapshot.signal {
        text.push_str(&format!(" terminated by signal {signal}."));
    } else {
        text.push_str(" has no exit code.");
    }
    if record.archive_status == "failed" {
        text.push_str("\nComplete capture resources could not be retained.");
    }
    let mut details = json!({"command": serde_json::to_value(&record)?});
    let needs_recovery = code.is_some();
    if needs_recovery && let Some(task_id) = task_id {
        let id = Value::from(task_id);
        text.push_str(&format!(
            "\nOriginal command result: tools.get_tool_task({{taskId={id},resultCursor=0}})"
        ));
    }
    let mut content = vec![text];
    let mut diagnostic_content = vec![0];
    for (name, stream, body, path) in [
        (
            "stdout",
            &record.stdout,
            &snapshot.stdout.content,
            record.stdout_file,
        ),
        (
            "stderr",
            &record.stderr,
            &snapshot.stderr.content,
            record.stderr_file,
        ),
    ] {
        let mut text = String::new();
        if stream.was_truncated || stream.text_lossy {
            text.push_str(&format!("Original {name}: {}\n", path.display()));
        }
        if !body.is_empty() {
            text.push_str(&format!("{name}:\n{body}"));
        }
        if !text.is_empty() {
            if name == "stderr" {
                diagnostic_content.push(content.len());
            }
            content.push(text);
        }
    }
    if needs_recovery {
        // Select text already present in the authored projection, without duplicating stderr.
        details["invocationDiagnosticContent"] = json!(diagnostic_content);
    }
    Ok(pl_agent_tool::ToolResult::from_data(data, content).with_details(details))
}
