//! Persisted Studio execution policy.
use pl_model::completion::OpenAiCompactionMode;
use serde::{Deserialize, Serialize};

use crate::approval::PermissionMode;
use pl_tool::workspace::ToolCapabilityConfig;

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
pub struct RuntimeConfig {
    #[serde(default, skip_serializing_if = "PermissionMode::is_default")]
    pub permission_mode: PermissionMode,
    #[serde(default, skip_serializing_if = "ToolCapabilityConfig::is_default")]
    pub tool_capabilities: ToolCapabilityConfig,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub active_skills: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub active_mcp_servers: Vec<String>,
    #[serde(default, skip_serializing_if = "OpenAiCompactionMode::is_default")]
    pub openai_compaction_mode: OpenAiCompactionMode,
}

impl RuntimeConfig {
    pub fn is_empty(&self) -> bool {
        self.permission_mode.is_default()
            && self.tool_capabilities.is_default()
            && self.active_skills.is_empty()
            && self.active_mcp_servers.is_empty()
            && self.openai_compaction_mode.is_default()
    }

    /// 本版本产品策略固定完全访问：Studio GUI 不再暴露权限模式选择，执行路径恒用 `full-access`。
    ///
    /// 保留 `permission_mode` 字段与三值语义以便将来恢复；这里只归一化 effective 运行时配置，
    /// 不改写持久化的 desired/canonical 配置。
    pub fn enforce_fixed_permission_mode(&mut self) {
        self.permission_mode = PermissionMode::FullAccess;
    }
}
