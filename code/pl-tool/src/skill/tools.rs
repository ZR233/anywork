use super::{SkillResourceBase, SkillSummary, is_main_skill_path};
use pl_protocol::PureError;
mod actions;
mod thread;
pub use thread::{ThreadSkillKind, ThreadSkillManageTool, ThreadSkillTool};
type SkillViewOutput = pl_tool_skill::support::ViewedSkill<SkillSummary, SkillResourceBase>;

/// Reads the identity of a previously loaded Skill from its frozen result.
///
/// # Errors
/// Rejects unsupported formats or malformed saved data without reading current Skill files.
pub fn saved_skill_name(payload: &pl_core::context::OpaquePayload) -> Result<String, PureError> {
    if payload.format() != "pl.tool.skill-view" || payload.version() != 1 {
        return Err(PureError::ConfigError(
            "unsupported saved Skill view".into(),
        ));
    }
    let view: SkillViewOutput = serde_json::from_str(payload.content())?;
    Ok(view.skill.name)
}

/// Decodes a successful main-document load without consulting the current catalog.
///
/// # Errors
/// Rejects malformed supported receipts; unrelated formats and support resources return None.
pub fn saved_skill_activation(
    payload: &pl_core::context::OpaquePayload,
    turn_id: String,
    cause: pl_protocol::SkillActivationCause,
) -> Result<Option<pl_protocol::SkillActivation>, PureError> {
    if payload.format() != "pl.tool.skill-view" || payload.version() != 1 {
        return Ok(None);
    }
    let view: SkillViewOutput = serde_json::from_str(payload.content())?;
    if !view.success || !is_main_skill_path(&view.file_path) {
        return Ok(None);
    }
    Ok(Some(pl_protocol::SkillActivation {
        name: view.skill.name,
        source: super::provider::source_label(view.skill.source).into(),
        provider_id: view.skill.provider_id.as_str().into(),
        resource_base: super::provider::activation_resource_base(&view.resource_base),
        turn_id,
        cause,
        activated_at: 0,
    }))
}
