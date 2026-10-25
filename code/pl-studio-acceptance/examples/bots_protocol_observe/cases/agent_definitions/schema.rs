//! Independent input-contract oracle, not generated from the producer schema.
//! Descriptive annotations are irrelevant; every validation keyword is kept.
use anyhow::{Context, Result, ensure};
use pl_protocol::{AgentProfileSnapshot, AgentWorkspaceMode};
use serde_json::{Value, json};
use std::collections::{BTreeMap, BTreeSet};

pub(super) fn branch(branch: &Value, profile: &AgentProfileSnapshot) -> Result<()> {
    ensure!(
        branch.get("type").and_then(Value::as_str) == Some("object")
            && branch.get("additionalProperties").and_then(Value::as_bool) == Some(false),
        "spawn branch is not closed object"
    );
    let properties = branch
        .get("properties")
        .and_then(Value::as_object)
        .context("branch properties missing")?;
    let mut keys = BTreeSet::from(["profileId", "taskSummary", "message", "metadata"]);
    let mut required = BTreeSet::from(["profileId", "taskSummary", "message"]);
    match profile.workspace_mode {
        AgentWorkspaceMode::Directory => {
            keys.insert("writablePaths");
        }
        AgentWorkspaceMode::Review => {
            keys.insert("reviewTargetAgentId");
            required.insert("reviewTargetAgentId");
        }
        AgentWorkspaceMode::Unrestricted | AgentWorkspaceMode::Worktree => {}
    }
    ensure!(
        properties
            .keys()
            .map(String::as_str)
            .collect::<BTreeSet<_>>()
            == keys,
        "wrong complete property set for {}",
        profile.profile_id
    );
    let actual = branch
        .get("required")
        .and_then(Value::as_array)
        .context("branch required missing")?;
    let actual_set = actual
        .iter()
        .map(|value| value.as_str().context("non-string required field"))
        .collect::<Result<BTreeSet<_>>>()?;
    ensure!(
        actual.len() == actual_set.len() && actual_set == required,
        "wrong exact required set for {}",
        profile.profile_id
    );
    ensure!(
        semantic(&properties["profileId"]) == json!({"type":"string", "const":profile.profile_id}),
        "profileId type/const/input constraints changed"
    );
    ensure!(
        semantic(&properties["taskSummary"])
            == json!({"type":"string", "minLength":1, "maxLength":80}),
        "taskSummary original string boundaries changed"
    );
    ensure!(
        semantic(&properties["message"]) == json!({"type":"string"}),
        "full message input was restricted or not string"
    );
    // serde_json::Value accepts every JSON value and #[serde(default)] means
    // absent metadata is null. It is optional, never an object-only schema.
    ensure!(
        semantic(&properties["metadata"]) == json!({"default":null}),
        "metadata lost optional arbitrary-JSON/default-null semantics"
    );
    if profile.workspace_mode == AgentWorkspaceMode::Directory {
        let mut scope = semantic(&properties["writablePaths"]);
        if let Some(default) = scope
            .as_object_mut()
            .and_then(|object| object.remove("default"))
        {
            ensure!(default.is_null(), "writablePaths default is not None/null");
        }
        let expected = json!({"type":["array","null"],"items":{"type":"string"}});
        let actual_types = scope
            .get("type")
            .and_then(Value::as_array)
            .map(|types| types.iter().map(Value::as_str).collect::<BTreeSet<_>>());
        let expected_types = expected["type"]
            .as_array()
            .map(|types| types.iter().map(Value::as_str).collect::<BTreeSet<_>>());
        ensure!(
            actual_types == expected_types
                && scope.get("items") == expected.get("items")
                && scope.as_object().is_some_and(|object| object.len() == 2),
            "directory scope must retain nullable unbounded Vec<String>, including empty array"
        );
    }
    if profile.workspace_mode == AgentWorkspaceMode::Review {
        ensure!(
            semantic(&properties["reviewTargetAgentId"]) == json!({"type":"string"}),
            "review target must be required non-null string with no new parser restrictions"
        );
    }
    let object = semantic(branch);
    ensure!(
        object.as_object().is_some_and(|object| object
            .keys()
            .map(String::as_str)
            .collect::<BTreeSet<_>>()
            == BTreeSet::from(["type", "properties", "required", "additionalProperties"])),
        "branch added an unexpected validation constraint"
    );
    Ok(())
}

pub(super) fn mapping(spec: &Value, profiles: &[AgentProfileSnapshot]) -> Result<()> {
    let description = spec
        .get("description")
        .and_then(Value::as_str)
        .context("spawn workspace-mode mapping missing")?;
    let (_, mapping) = description
        .rsplit_once("Profile workspace modes: ")
        .context("workspace-mode mapping JSON missing")?;
    // Core appends its foreground/batching contract after the product's
    // description. Decode exactly the mapping value, not that prose suffix.
    let mut values =
        serde_json::Deserializer::from_str(mapping).into_iter::<BTreeMap<String, String>>();
    let actual = values
        .next()
        .context("workspace-mode mapping JSON absent")?
        .context("decode workspace-mode mapping JSON")?;
    ensure!(
        mapping[values.byte_offset()..].starts_with('.'),
        "workspace-mode mapping is not followed by its description boundary"
    );
    let expected = profiles
        .iter()
        .map(|profile| {
            (
                profile.profile_id.clone(),
                profile.workspace_mode.label().to_owned(),
            )
        })
        .collect::<BTreeMap<_, _>>();
    ensure!(
        actual == expected,
        "workspace-mode mapping differs from same-generation catalog"
    );
    Ok(())
}

fn semantic(value: &Value) -> Value {
    match value {
        Value::Object(object) => Value::Object(
            object
                .iter()
                .filter(|(key, _)| !matches!(key.as_str(), "description" | "title" | "$schema"))
                .map(|(key, value)| (key.clone(), semantic(value)))
                .collect(),
        ),
        Value::Array(values) => Value::Array(values.iter().map(semantic).collect()),
        value => value.clone(),
    }
}
