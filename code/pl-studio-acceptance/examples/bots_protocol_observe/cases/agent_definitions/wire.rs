//! Assertions over provider requests actually recorded by FixtureServer.
//! Expected markers select a synthetic phase; they never prove role assembly.
use super::saved::Instructions;
use anyhow::{Context, Result, ensure};
use pl_protocol::AgentProfileSnapshot;
use pl_provider_fixture::{
    RecordedRequest,
    agent_definitions::{AgentPhase, DISABLED_PROFILE, UNAVAILABLE_PROFILE},
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Catalog {
    pub profiles: Vec<AgentProfileSnapshot>,
    pub diagnostics: Vec<Value>,
}

pub(super) fn phase(body: &Value) -> Result<AgentPhase> {
    let items = body
        .get("input")
        .and_then(Value::as_array)
        .context("wire input absent")?;
    let last = items
        .iter()
        .rev()
        .filter(|item| item.get("role").and_then(Value::as_str) == Some("user"))
        .filter_map(text)
        .find(|text| {
            !text.starts_with("[当前宿主事实：")
                && !(text.contains("\"childId\"") && text.contains("\"commitSequence\""))
                && !text.starts_with("Task task:")
        })
        .context("wire authored input absent")?;
    if last.ends_with("请根据以上完整上下文生成压缩摘要。") {
        let main = items
            .iter()
            .filter_map(text)
            .any(|text| text.contains(AgentPhase::MainFirst.marker()));
        let feishu = items
            .iter()
            .filter_map(text)
            .any(|text| text.contains(AgentPhase::FeishuFirst.marker()));
        ensure!(main != feishu, "wire summary root ambiguous");
        return Ok(if main {
            AgentPhase::CompactMain
        } else {
            AgentPhase::CompactFeishu
        });
    }
    AgentPhase::ALL
        .iter()
        .copied()
        .find(|phase| last.starts_with(phase.marker()))
        .context("unrecognized wire phase")
}

pub(super) fn requests(all: &[RecordedRequest], wanted: AgentPhase) -> Result<Vec<&Value>> {
    let mut selected = Vec::new();
    for request in all {
        ensure!(
            request.accepted,
            "rejected model attempt: {:?}",
            request.diagnostic
        );
        let actual_phase = phase(&request.body)?;
        let child = matches!(
            actual_phase,
            AgentPhase::ChildSystem
                | AgentPhase::ChildUser
                | AgentPhase::ChildSystemResumed
                | AgentPhase::ChildUserResumed
        );
        let path = if child {
            "/v1/openai/responses"
        } else {
            "/v1/responses"
        };
        ensure!(
            request.method == "POST" && request.path == path,
            "unexpected model transport for {actual_phase:?}"
        );
        if actual_phase == wanted {
            selected.push(&request.body);
        }
    }
    ensure!(
        selected.len() == wanted.expected_attempts(),
        "{wanted:?} had {} attempts, expected {}",
        selected.len(),
        wanted.expected_attempts()
    );
    Ok(selected)
}

pub(super) fn audit_attempts(all: &[RecordedRequest]) -> Result<()> {
    let expected: usize = AgentPhase::ALL
        .iter()
        .map(|phase| phase.expected_attempts())
        .sum();
    ensure!(
        all.len() == expected,
        "all model attempts, including rejected: {}/{expected}",
        all.len()
    );
    for phase in AgentPhase::ALL {
        requests(all, *phase)?;
    }
    Ok(())
}

pub(super) fn assert_instructions(body: &Value, sources: &Instructions) -> Result<()> {
    let mut system = body
        .get("instructions")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string();
    for item in body
        .get("input")
        .and_then(Value::as_array)
        .context("wire input missing")?
    {
        if matches!(
            item.get("role").and_then(Value::as_str),
            Some("system" | "developer")
        ) && let Some(text) = text(item)
        {
            system.push('\n');
            system.push_str(&text);
        }
    }
    ensure!(
        system.contains(&sources.base.content),
        "actual request lost captured base source"
    );
    for source in sources
        .blocks("agentDefinition")
        .into_iter()
        .chain(sources.blocks("modeDefinition"))
    {
        ensure!(
            system.contains(&source.content),
            "actual request lost {} source {}",
            source.source.kind,
            source.source.label
        );
    }
    if sources.agent.id == "root:main" {
        ensure!(
            !system.contains("你是通过飞书与用户协作的 Studio 根会话 Agent"),
            "ordinary root acquired the Feishu role"
        );
    }
    Ok(())
}

pub(super) fn tool<'a>(body: &'a Value, name: &str) -> Result<Option<&'a Value>> {
    let tools = body
        .get("tools")
        .and_then(Value::as_array)
        .context("wire tools missing")?;
    let found = tools
        .iter()
        .filter(|tool| tool.get("name").and_then(Value::as_str) == Some(name))
        .collect::<Vec<_>>();
    ensure!(found.len() <= 1, "duplicate wire tool {name}");
    Ok(found.first().copied())
}

pub(super) fn catalog(body: &Value, phase: AgentPhase) -> Result<Catalog> {
    let output = output(body, &phase.action_call())?;
    serde_json::from_str(output).context("decode real list_agent_profiles result")
}

pub(super) fn output<'a>(body: &'a Value, call: &str) -> Result<&'a str> {
    let found = body
        .get("input")
        .and_then(Value::as_array)
        .context("wire input absent")?
        .iter()
        .filter(|item| {
            item.get("type").and_then(Value::as_str) == Some("function_call_output")
                && item.get("call_id").and_then(Value::as_str) == Some(call)
        })
        .collect::<Vec<_>>();
    ensure!(found.len() == 1, "real output for {call} absent/duplicated");
    found[0]
        .get("output")
        .and_then(Value::as_str)
        .context("tool result was not text")
}

pub(super) fn assert_delegation(
    body: &Value,
    phase: AgentPhase,
    child: &str,
    turn: &str,
) -> Result<()> {
    output(body, &phase.action_call())?;
    output(body, &phase.wait_call())?;
    let mut reports = Vec::new();
    for item in body
        .get("input")
        .and_then(Value::as_array)
        .context("delegation input missing")?
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
        let value: Value =
            serde_json::from_str(&text).context("malformed delivered report JSON")?;
        if value.get("childId").and_then(Value::as_str) == Some(child)
            && value.pointer("/turn/turnId").and_then(Value::as_str) == Some(turn)
        {
            reports.push(value);
        }
    }
    ensure!(
        reports.len() == 1,
        "current child/Turn report missing or duplicated"
    );
    let report = &reports[0];
    let expected = phase
        .child_phase()
        .context("no delegated child phase")?
        .report();
    ensure!(
        report.get("message").and_then(Value::as_str) == Some(expected.as_str())
            && report
                .get("commitSequence")
                .and_then(Value::as_u64)
                .is_some_and(|sequence| sequence > 0),
        "current report body/commit identity invalid"
    );
    for field in ["runningTasks", "pendingInteractions"] {
        ensure!(
            report
                .get(field)
                .and_then(Value::as_array)
                .is_some_and(Vec::is_empty),
            "current report left {field}"
        );
    }
    Ok(())
}

/// Schema and list result come from the same *request's* frozen tool plan. In
/// the held-request phase the live catalog is deliberately changed in between.
pub(super) fn assert_schema(body: &Value, catalog: &Catalog) -> Result<()> {
    let profiles = catalog
        .profiles
        .iter()
        .map(|profile| (profile.profile_id.as_str(), profile))
        .collect::<BTreeMap<_, _>>();
    ensure!(
        profiles.len() == catalog.profiles.len(),
        "catalog duplicated a Profile"
    );
    ensure!(
        profiles.keys().all(|id| !id.starts_with("root:")
            && *id != "planner"
            && *id != DISABLED_PROFILE
            && *id != UNAVAILABLE_PROFILE),
        "catalog exposed root-only/disabled/unavailable Profile"
    );
    let spec = tool(body, "spawn_agent")?;
    if profiles.is_empty() {
        ensure!(spec.is_none(), "empty catalog still exposes spawn_agent");
        return Ok(());
    }
    let spec = spec.context("root request lacks spawn_agent")?;
    super::schema::mapping(spec, &catalog.profiles)?;
    let schema = spec.get("parameters").context("spawn parameters missing")?;
    let branches = schema
        .get("oneOf")
        .and_then(Value::as_array)
        .context("spawn schema is not oneOf")?;
    ensure!(
        branches.len() == profiles.len(),
        "schema/catalog sizes differ"
    );
    let mut seen = BTreeSet::new();
    for branch in branches {
        ensure!(
            branch.get("type").and_then(Value::as_str) == Some("object")
                && branch.get("additionalProperties").and_then(Value::as_bool) == Some(false),
            "spawn branch not a closed object"
        );
        let properties = branch
            .get("properties")
            .and_then(Value::as_object)
            .context("spawn branch properties missing")?;
        let id = properties
            .get("profileId")
            .and_then(|id| id.get("const"))
            .and_then(Value::as_str)
            .context("profileId const missing")?;
        ensure!(seen.insert(id), "duplicate spawn branch {id}");
        let profile = profiles
            .get(id)
            .context("schema contains a Profile absent from frozen catalog")?;
        ensure!(profile.enabled, "disabled Profile in dispatch schema");
        super::schema::branch(branch, profile)?;
    }
    ensure!(
        seen == profiles.keys().copied().collect(),
        "oneOf identities differ from frozen catalog"
    );
    Ok(())
}

pub(super) fn assert_all_modes(catalog: &Catalog) -> Result<()> {
    let modes = catalog
        .profiles
        .iter()
        .map(|profile| profile.workspace_mode.label())
        .collect::<BTreeSet<_>>();
    ensure!(
        modes == BTreeSet::from(["unrestricted", "directory", "worktree", "review"]),
        "wire schema did not exercise all workspace-mode branches"
    );
    Ok(())
}

fn text(item: &Value) -> Option<String> {
    let content = item.get("content")?;
    if let Some(text) = content.as_str() {
        return Some(text.into());
    }
    Some(
        content
            .as_array()?
            .iter()
            .filter_map(|part| part.get("text").and_then(Value::as_str))
            .collect::<Vec<_>>()
            .join("\n"),
    )
}
