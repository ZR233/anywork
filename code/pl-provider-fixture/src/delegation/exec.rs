//! Consume only the two current exec projections; ACKs never establish command facts.
use super::flow::*;
use anyhow::{Context, Result};
use serde::Deserialize;
use serde::de::DeserializeOwned;
use serde_json::json;

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
    let text = flow.raw(label, "exec_command", arguments)?;
    require(
        !text.contains("Lua execution failed:"),
        "production command failed",
    )?;
    let record: Record = serde_json::from_str(&text).context("decode selected command receipt")?;
    record.state.successful()?;
    Ok(stdout(
        clean_stream(record.stdout)?,
        clean_stream(record.stderr)?,
    )?)
}
