//! Profile-specific argument declarations; Studio owns catalog selection and generation.
use super::thread::{
    AgentSpawn, AgentSpawnProfile, AgentSpawnSchemaError, AgentWorkspaceMode, DelegationMode,
    NewThreadModelRoute, ToolSpec,
};
use schemars::{JsonSchema, Schema, SchemaGenerator};
use serde_json::Value;
use std::collections::BTreeMap;

pub(super) fn declaration(
    profiles: &[AgentSpawnProfile],
    mode: DelegationMode,
) -> Result<Option<ToolSpec>, AgentSpawnSchemaError> {
    if profiles.is_empty() {
        return Ok(None);
    }
    // Inline the typed request's definitions so each cloned branch remains self-contained.
    // Common fields keep exactly the parser's serde/schemars contract.
    let template = schemars::generate::SchemaSettings::default()
        .with(|settings| settings.inline_subschemas = true)
        .into_generator()
        .into_root_schema_for::<AgentSpawn>();
    let mut modes = BTreeMap::new();
    let mut branches = Vec::with_capacity(profiles.len());
    for profile in profiles {
        if modes
            .insert(&profile.profile_id, profile.workspace_mode.label())
            .is_some()
        {
            return Err(AgentSpawnSchemaError::DuplicateProfile(
                profile.profile_id.clone(),
            ));
        }
        branches.push(branch(&template, profile, mode)?);
    }
    let description = format!(
        "Create a child with an independent context using an authorized profile. Provide taskSummary: a brief task description (1–80 Unicode characters after whitespace normalization) shown in the child list, and message: the complete self-contained instructions without an application length limit. Select the matching oneOf branch. Automatic mode requires modelSelection from a current model query; fixed Profile mode forbids overrides. writablePaths is optional only for directory Profiles: omit it for the whole workspace, or use [] for business read-only access (Thread scratch/artifacts remain writable). reviewTargetAgentId is required only for review Profiles and must be the reviewed direct child's agentId; the host adopts its frozen workspace. The host independently validates permissions, current availability and limits. Open-agent capacity covers the root plus every open and preparing child in the tree; when a spawn is rejected for capacity, close finished agents with close_agent before spawning more. Profile workspace modes: {}.",
        serde_json::to_string(&modes)?
    );
    Ok(Some(ToolSpec::function(
        "spawn_agent",
        description,
        schemars::json_schema!({"type": "object", "oneOf": branches}).to_value(),
    )))
}

fn branch(
    template: &Schema,
    profile: &AgentSpawnProfile,
    mode: DelegationMode,
) -> Result<Schema, AgentSpawnSchemaError> {
    let mut schema = template.clone();
    let object = schema
        .as_object_mut()
        .ok_or(AgentSpawnSchemaError::Shape("request must be an object"))?;
    object.remove("$schema");
    object.remove("title");
    let properties = object
        .get_mut("properties")
        .and_then(Value::as_object_mut)
        .ok_or(AgentSpawnSchemaError::Shape(
            "request properties are missing",
        ))?;
    let identity = properties
        .get_mut("profileId")
        .and_then(Value::as_object_mut)
        .ok_or(AgentSpawnSchemaError::Shape(
            "profileId must be a string schema",
        ))?;
    identity.insert("const".into(), Value::String(profile.profile_id.clone()));
    if profile.workspace_mode != AgentWorkspaceMode::Directory {
        properties.remove("writablePaths");
    }
    if profile.workspace_mode == AgentWorkspaceMode::Review {
        // Option<String> is appropriate for parsing all modes, but a review branch requires a
        // non-null target. The host still checks that the target is an authorized direct child.
        properties.insert(
            "reviewTargetAgentId".into(),
            String::json_schema(&mut SchemaGenerator::default()).to_value(),
        );
        object
            .get_mut("required")
            .and_then(Value::as_array_mut)
            .ok_or(AgentSpawnSchemaError::Shape("required fields are missing"))?
            .push(Value::String("reviewTargetAgentId".into()));
    } else {
        properties.remove("reviewTargetAgentId");
    }
    if mode == DelegationMode::Automatic {
        let mut generator = schemars::generate::SchemaSettings::default()
            .with(|settings| settings.inline_subschemas = true)
            .into_generator();
        object
            .get_mut("properties")
            .and_then(Value::as_object_mut)
            .ok_or(AgentSpawnSchemaError::Shape(
                "request properties are missing",
            ))?
            .insert(
                "modelSelection".into(),
                NewThreadModelRoute::json_schema(&mut generator).to_value(),
            );
        object
            .get_mut("required")
            .and_then(Value::as_array_mut)
            .ok_or(AgentSpawnSchemaError::Shape("required fields are missing"))?
            .push(Value::String("modelSelection".into()));
    } else {
        object
            .get_mut("properties")
            .and_then(Value::as_object_mut)
            .ok_or(AgentSpawnSchemaError::Shape(
                "request properties are missing",
            ))?
            .remove("modelSelection");
    }
    object.insert("additionalProperties".into(), Value::Bool(false));
    Ok(schema)
}
