use serde::{Deserialize, Serialize};
/// prompt generation 发生冷启动的原因。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum PromptPrefixChangedReason {
    Initial,
    PromptScopeChanged,
    AccountChanged,
    ModelChanged,
    BaseInstructionsChanged,
    GlobalInstructionsChanged,
    ModeRoleChanged,
    SkillCatalogChanged,
    WorkspaceInstructionsChanged,
    RequestPropertiesChanged,
    FixedPrefixChanged,
    ToolSchemaChanged,
    ContextCompacted,
    ContextAppended,
    ContextRecovered,
}
