//! Responses request inspection, confined to this synthetic observation.
use super::AgentPhase;
use anyhow::{Context, Result, ensure};
use serde_json::Value;

pub(super) fn phase(body: &Value) -> Result<AgentPhase> {
    ensure!(
        body.get("stream").and_then(Value::as_bool) == Some(true),
        "Responses stream required"
    );
    let items = body
        .get("input")
        .and_then(Value::as_array)
        .context("Responses input missing")?;
    let prompt = items
        .iter()
        .rev()
        .filter(|item| authored(item))
        .find_map(text)
        .context("authored input missing")?;
    if prompt.ends_with("请根据以上完整上下文生成压缩摘要。") {
        let main = items
            .iter()
            .filter_map(text)
            .any(|text| text.contains(AgentPhase::MainFirst.marker()));
        let feishu = items
            .iter()
            .filter_map(text)
            .any(|text| text.contains(AgentPhase::FeishuFirst.marker()));
        ensure!(main != feishu, "compaction has ambiguous root context");
        return Ok(if main {
            AgentPhase::CompactMain
        } else {
            AgentPhase::CompactFeishu
        });
    }
    let found = AgentPhase::ALL
        .iter()
        .filter(|phase| {
            !matches!(phase, AgentPhase::CompactMain | AgentPhase::CompactFeishu)
                && prompt.starts_with(phase.marker())
        })
        .copied()
        .collect::<Vec<_>>();
    ensure!(
        found.len() == 1,
        "unknown or ambiguous Agent observation marker"
    );
    Ok(found[0])
}

fn authored(item: &Value) -> bool {
    item.get("role").and_then(Value::as_str) == Some("user")
        && text(item).is_some_and(|text| {
            !text.starts_with("[当前宿主事实：")
                && !text.starts_with("Task task:")
                && !(text.contains("\"childId\"") && text.contains("\"commitSequence\""))
        })
}

pub(super) fn text(item: &Value) -> Option<String> {
    let content = item.get("content")?;
    if let Some(text) = content.as_str() {
        return Some(text.into());
    }
    let parts = content.as_array()?;
    Some(
        parts
            .iter()
            .filter_map(|part| part.get("text").and_then(Value::as_str))
            .collect::<Vec<_>>()
            .join("\n"),
    )
}

pub(super) fn tool_output<'a>(body: &'a Value, call_id: &str) -> Result<&'a str> {
    let outputs = body
        .get("input")
        .and_then(Value::as_array)
        .context("tool input missing")?
        .iter()
        .filter(|item| {
            item.get("type").and_then(Value::as_str) == Some("function_call_output")
                && item.get("call_id").and_then(Value::as_str) == Some(call_id)
        })
        .collect::<Vec<_>>();
    ensure!(
        outputs.len() == 1,
        "current call {call_id} has {} outputs, expected exactly one",
        outputs.len()
    );
    outputs[0]
        .get("output")
        .and_then(Value::as_str)
        .context("tool output is not text")
}

pub(super) fn child_report(body: &Value, id: &str, turn_id: &str, report: &str) -> Result<()> {
    #[derive(serde::Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct Report {
        child_id: String,
        commit_sequence: u64,
        message: String,
        turn: Turn,
        running_tasks: Vec<String>,
        pending_interactions: Vec<String>,
    }
    #[derive(serde::Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct Turn {
        turn_id: String,
    }
    let mut matching = Vec::new();
    for item in body
        .get("input")
        .and_then(Value::as_array)
        .context("report input missing")?
    {
        if item.get("role").and_then(Value::as_str) != Some("user") {
            continue;
        }
        let Some(text) = text(item) else {
            continue;
        };
        if !(text.contains("\"childId\"") && text.contains("\"commitSequence\"")) {
            continue;
        }
        let value: Value = serde_json::from_str(&text).context("malformed child report JSON")?;
        if value.get("childId").and_then(Value::as_str) == Some(id)
            && value.pointer("/turn/turnId").and_then(Value::as_str) == Some(turn_id)
        {
            matching.push(
                serde_json::from_value::<Report>(value)
                    .context("malformed current child report")?,
            );
        }
    }
    ensure!(
        matching.len() == 1,
        "current child {id} Turn {turn_id} report missing/duplicated"
    );
    let value = &matching[0];
    ensure!(
        value.child_id == id
            && value.turn.turn_id == turn_id
            && value.commit_sequence > 0
            && value.message == report
            && value.running_tasks.is_empty()
            && value.pending_interactions.is_empty(),
        "current child report is incomplete or has wrong body"
    );
    Ok(())
}

pub(super) fn declared(body: &Value, name: &str) -> bool {
    body.get("tools")
        .and_then(Value::as_array)
        .is_some_and(|tools| {
            tools
                .iter()
                .any(|tool| tool.get("name").and_then(Value::as_str) == Some(name))
        })
}
