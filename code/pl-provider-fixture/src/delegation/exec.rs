//! Consume only the two current exec projections; ACKs never establish command facts.
use super::flow::*;
use anyhow::{Context, Result};
use serde::Deserialize;
use serde::de::DeserializeOwned;
use serde_json::{Value, json};

#[derive(Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
enum ProcessState {
    Final(FinalState),
}

#[derive(Deserialize)]
struct FinalState {
    result: ProcessResult,
}

#[derive(Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
enum ProcessResult {
    Succeeded { exit_code: i32 },
}

impl ProcessState {
    fn successful(&self) -> Result<()> {
        let Self::Final(FinalState {
            result: ProcessResult::Succeeded { exit_code },
        }) = self;
        require(*exit_code == 0, "exec did not exit successfully")
    }
}

#[derive(Deserialize)]
struct Preview {
    state: ProcessState,
    stdout: String,
    stderr: String,
    archived: bool,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Stream {
    content: String,
    was_truncated: bool,
    original_length: usize,
}

#[derive(Deserialize)]
struct Record {
    state: ProcessState,
    stdout: Stream,
    stderr: Stream,
}

#[derive(Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
enum TaskStatus {
    Running,
    Succeeded,
    Failed,
    Cancelled,
    Interrupted,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Task {
    task_id: String,
    tool_id: String,
    status: TaskStatus,
    cancel_requested: bool,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Payload {
    format: String,
    version: u32,
    content: String,
    next_cursor: Option<usize>,
    total_bytes: usize,
}

#[derive(Deserialize)]
struct TaskResult {
    task: Task,
    result: Option<Payload>,
}

/// Resource references follow the first complete JSON value in tool previews.
/// Only that value is decoded, never the unrelated tail.
pub(super) fn first<T: DeserializeOwned>(text: &str) -> Result<T> {
    serde_json::Deserializer::from_str(text)
        .into_iter::<T>()
        .next()
        .context("tool output contains no JSON value")?
        .context("decode first tool JSON value")
}

fn clean_stream(stream: Stream) -> Result<String> {
    require(
        !stream.was_truncated && stream.original_length == stream.content.len(),
        "exec stream was truncated or has inconsistent byte count",
    )?;
    Ok(stream.content)
}

fn stdout(stdout: String, stderr: String) -> Result<String> {
    require(
        stdout.len() + stderr.len() < 8192,
        "synthetic exec exceeded its bounded output contract",
    )?;
    require(
        stderr.is_empty(),
        "synthetic exec emitted unexpected stderr",
    )?;
    Ok(stdout)
}

fn complete_payload(
    flow: &Flow<'_>,
    label: &str,
    task_id: &str,
    mut page: Payload,
) -> Progress<String> {
    let total = page.total_bytes;
    require(
        total > 0 && total <= 64 * 1024,
        "exec Record payload exceeds its bounded eight-page contract",
    )?;
    let mut content = String::new();
    for index in 0..8 {
        require(
            page.format == "pl.tool.exec"
                && page.version == 1
                && page.total_bytes == total
                && !page.content.is_empty()
                && page.content.len() <= 8192
                && content.len() + page.content.len() <= total,
            "exec payload page changed format/version/total or returned invalid byte bounds",
        )?;
        content.push_str(&page.content);
        let Some(cursor) = page.next_cursor else {
            require(
                content.len() == total,
                "exec payload ended before its complete byte count",
            )?;
            return Ok(content);
        };
        require(
            cursor == content.len() && cursor < total && index < 7,
            "exec payload cursor is discontinuous or exceeds eight bounded pages",
        )?;
        // Once succeeded, this payload is immutable. Reading its subsequent
        // byte pages is not polling a running task and must preserve its identity.
        let result: TaskResult = flow.read(
            &format!("{label}-page-{}", index + 1),
            "get_tool_task",
            json!({"taskId":task_id,"resultCursor":cursor}),
        )?;
        require(
            result.task.task_id == task_id
                && result.task.tool_id == "exec"
                && result.task.status == TaskStatus::Succeeded
                && !result.task.cancel_requested,
            "exec payload pagination lost its successful immutable task identity",
        )?;
        page = result.result.context("exec payload page has no result")?;
    }
    Err(anyhow::anyhow!("exec payload exceeded eight bounded pages").into())
}

pub(super) fn exec<T: DeserializeOwned>(
    flow: &Flow<'_>,
    label: &str,
    command: String,
) -> Progress<T> {
    let output = read_stdout(flow, label, command)?;
    Ok(serde_json::from_str(&output).context("decode synthetic command stdout")?)
}

pub(super) fn read_stdout(flow: &Flow<'_>, label: &str, command: String) -> Progress<String> {
    let arguments = json!({"command":command,"cwd":".","timeoutSeconds":60,"maxOutputChars":12000});
    let text = flow.raw(label, "exec", arguments.clone())?;
    let id = format!("{}-{label}", flow.prefix);
    let call = flow
        .request
        .input
        .iter()
        .find(|item| item.kind == "function_call" && item.call_id.as_deref() == Some(&id))
        .context("exec result lost its exact call")?;
    let declared: Value =
        serde_json::from_str(call.arguments.as_deref().context("exec has no arguments")?)
            .context("decode exec arguments")?;
    require(
        declared == arguments,
        "exec command changed during history replay",
    )?;
    require(
        !text.contains("Framework recorded tool failure:"),
        "production exec failed",
    )?;
    let output = if let Some(task_id) = text.strip_prefix("Task ").and_then(|text| {
        text.strip_suffix(" is running. Its result will be delivered when execution finishes.")
    }) {
        require(
            !task_id.is_empty() && !task_id.contains(char::is_whitespace),
            "invalid exec ACK task identity",
        )?;
        let mut complete = None;
        for retry in 0..8 {
            // A message may wake wait before this task; observe status only after waiting.
            let _ = flow.raw(
                &format!("{label}-wait-{retry}"),
                "wait",
                json!({"taskIds":[task_id],"timeoutMs":300000}),
            )?;
            let result: TaskResult = flow.read(
                &format!("{label}-result-{retry}"),
                "get_tool_task",
                json!({"taskId":task_id,"resultCursor":0}),
            )?;
            require(
                result.task.task_id == task_id
                    && result.task.tool_id == "exec"
                    && !result.task.cancel_requested,
                "exec task result identity/cancellation changed",
            )?;
            match result.task.status {
                TaskStatus::Running => {
                    require(
                        result.result.is_none(),
                        "running task unexpectedly has a final payload",
                    )?;
                }
                TaskStatus::Succeeded => {
                    let payload = result
                        .result
                        .context("completed exec task has no payload")?;
                    let content = complete_payload(
                        flow,
                        &format!("{label}-result-{retry}"),
                        task_id,
                        payload,
                    )?;
                    let record: Record =
                        serde_json::from_str(&content).context("decode complete exec Record")?;
                    record.state.successful()?;
                    complete = Some(stdout(
                        clean_stream(record.stdout)?,
                        clean_stream(record.stderr)?,
                    )?);
                    break;
                }
                TaskStatus::Failed | TaskStatus::Cancelled | TaskStatus::Interrupted => {
                    return Err(anyhow::anyhow!(
                        "exec background task failed/cancelled/interrupted"
                    )
                    .into());
                }
            }
        }
        complete.context("exec did not finish after eight bounded waits")?
    } else {
        let preview: Preview = first(&text)?;
        preview.state.successful()?;
        // Commands emit bounded text. Archived marks a reliable copy, not
        // truncation; consumers validate the actual stdout below in either case.
        let _archived = preview.archived;
        stdout(preview.stdout, preview.stderr)?
    };
    Ok(output)
}
