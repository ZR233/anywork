use schemars::JsonSchema;
use serde::Deserialize;
#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", tag = "action")]
pub enum SkillManageInput {
    Create(CreateSkillInput),
    Patch(PatchSkillInput),
    Edit(EditSkillInput),
    Delete(DeleteSkillInput),
    WriteFile(WriteSkillFileInput),
    RemoveFile(RemoveSkillFileInput),
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CreateSkillInput {
    pub name: String,
    /// Full SKILL.md content.
    pub content: String,
    /// Optional category path.
    pub category: Option<String>,
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PatchSkillInput {
    pub name: String,
    /// Exact existing text to replace.
    pub old_string: String,
    /// Replacement text.
    pub new_string: String,
    /// Replace one occurrence or all occurrences.
    pub replace_mode: Option<ReplaceMode>,
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct EditSkillInput {
    pub name: String,
    /// Complete replacement SKILL.md content.
    pub content: String,
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DeleteSkillInput {
    pub name: String,
    /// Optional note identifying where its knowledge was absorbed.
    pub absorbed_into: Option<String>,
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WriteSkillFileInput {
    pub name: String,
    /// Support file under references/, templates/, scripts/, or assets/.
    pub file_path: String,
    /// Complete support file content.
    pub file_content: String,
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RemoveSkillFileInput {
    pub name: String,
    /// Existing support file path.
    pub file_path: String,
}

#[derive(Debug, Clone, Copy, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub enum ReplaceMode {
    One,
    All,
}
