use std::path::Path;

use pl_model::model::ModelInfo;
use serde::{Deserialize, Serialize};

use crate::agent::definition::{AgentDefinitionIdentity, ResolvedAgentDefinition};
use crate::config::InstructionsConfig;
use pl_tool::environment::ExecutionEnvironment;
use pl_tool::skill::SkillsConfig;
use pl_tool::workspace::WorkspaceInstructions;

/// 当前 instruction snapshot 的载荷格式与版本。
pub(crate) const SNAPSHOT_FORMAT: &str = "pl.studio.instructions";
pub(crate) const SNAPSHOT_VERSION: u32 = 2;

/// 统一指令装配的输入。
///
/// Agent 定义与 Mode 指令是两个独立来源：前者表达谁在执行，后者表达本轮如何执行。装配只
/// 读取已解析定义与已冻结 Mode，不重新选择角色、不扫描 Profile 目录。
#[derive(Debug, Clone)]
pub struct InstructionAssemblyRequest<'a> {
    pub instructions: Option<&'a InstructionsConfig>,
    pub skills: Option<&'a SkillsConfig>,
    pub skill_catalog: Option<&'a pl_tool::skill::SkillCatalog>,
    /// 已解析的 Agent 定义；普通 root、飞书 root 与 child 都必须提供。
    pub agent: &'a ResolvedAgentDefinition,
    /// 当前根会话 Mode 的执行方式指令；child 没有。
    pub mode: Option<ModeInstructionProfile<'a>>,
    pub model: &'a ModelInfo,
    pub workspace_root: &'a Path,
    pub current_dir: &'a Path,
    /// 已由宿主读取的项目说明文档。
    ///
    /// 远程工作区的路径只存在于远程主机，不能再次交给本地文件系统读取；
    /// 宿主若已完成读取，应通过此字段传入 canonical 文档集合。
    pub workspace_documents: Option<&'a WorkspaceInstructions>,
    pub workspace_instructions: Option<&'a str>,
    pub subagent_constraint: Option<&'a str>,
    pub delegation_preference: Option<&'a str>,
    pub skill_suggestions: Option<SkillSuggestionRequest<'a>>,
    /// Runtime facts for the command execution target. When absent, the local
    /// resolver is used; no login-shell environment variable is consulted.
    pub execution_environment: Option<&'a ExecutionEnvironment>,
}

/// Turn-local task text used to suggest Skill summaries without loading them.
#[derive(Debug, Clone, Copy)]
pub struct SkillSuggestionRequest<'a> {
    pub query: &'a str,
    pub excluded_names: &'a [String],
}

/// 产品层为一次 Turn 提供的 Mode 执行方式指令。
#[derive(Debug, Clone, Copy)]
pub struct ModeInstructionProfile<'a> {
    pub label: &'a str,
    pub instructions: &'a str,
}

/// 冻结的完整指令来源。
///
/// `agent` 只保存身份、范围与修订；角色正文保存在 `developer` 的 Agent 来源块中，因此不会
/// 出现第二份可变角色提示词。Mode 来源块由 Mode 更新独占。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct InstructionSnapshot {
    pub agent: AgentDefinitionIdentity,
    pub base: InstructionBlock,
    #[serde(default)]
    pub developer: Vec<InstructionBlock>,
    #[serde(default)]
    pub user: Vec<InstructionBlock>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct InstructionBlock {
    pub source: InstructionSource,
    pub content: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct InstructionSource {
    pub kind: InstructionSourceKind,
    pub label: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum InstructionSourceKind {
    BuiltInBase,
    ModelBase,
    ConfigBaseOverride,
    /// 历史快照中的 base override 来源；当前没有生产者。
    ProfileBaseOverride,
    /// 由 Agent 定义提供的角色指令。
    AgentDefinition,
    /// 由当前 Mode 提供的执行方式指令。
    ModeDefinition,
    DelegationPreference,
    Platform,
    ConfigDeveloper,
    /// 历史快照中的 Profile 上下文档来源；当前没有生产者。
    ProfileDeveloper,
    Skills,
    ToolGroup,
    SubagentConstraint,
    SubagentForce,
    ConfigUser,
    /// 历史快照中的 Profile 上下文来源；当前没有生产者。
    ProfileUser,
    ProjectDoc,
    WorkspaceFallback,
    SkillInvocation,
    SkillSuggestions,
}

impl InstructionSnapshot {
    /// Rebinds model-owned defaults while preserving explicit host/config overrides.
    pub(crate) fn rebind_model_base(&mut self, instructions: &str) -> bool {
        if !matches!(
            self.base.source.kind,
            InstructionSourceKind::BuiltInBase | InstructionSourceKind::ModelBase
        ) {
            return false;
        }
        let base = super::assembler::model_base_block(instructions);
        if self.base == base {
            return false;
        }
        self.base = base;
        true
    }

    /// Rewrites the single Mode-owned instruction source of an already validated snapshot.
    ///
    /// The frozen Agent source is never touched here: Mode switching, Turn preparation and
    /// compaction own execution semantics, never identity. A missing or duplicated Mode source is
    /// a structural error instead of being silently created, removed or defaulted.
    pub(crate) fn set_mode_instruction(
        &mut self,
        label: &str,
        content: &str,
    ) -> Result<bool, pl_protocol::PureError> {
        if content.trim().is_empty() {
            return Err(pl_protocol::PureError::ConfigError(
                "Mode instructions must not be empty".into(),
            ));
        }
        let mut modes = self
            .developer
            .iter_mut()
            .filter(|block| block.source.kind == InstructionSourceKind::ModeDefinition);
        let block = modes.next().ok_or_else(|| {
            pl_protocol::PureError::ConfigError(
                "saved instruction snapshot has no Mode source".into(),
            )
        })?;
        if modes.next().is_some() {
            return Err(pl_protocol::PureError::ConfigError(
                "saved instruction snapshot has more than one Mode source".into(),
            ));
        }
        let content = content.trim();
        let changed = block.content != content || block.source.label != label;
        block.content = content.to_owned();
        block.source.label = label.to_owned();
        Ok(changed)
    }

    /// Projects captured instruction sources without rescanning files or changing their content.
    pub(crate) fn context_records(&self, thread_id: &str) -> Vec<pl_core::context::ContextRecord> {
        use pl_core::context::{ContextContent, ContextRecord, ContextSource};
        use std::sync::Arc;
        let mut records = Vec::new();
        for (index, (block, instruction)) in std::iter::once((&self.base, true))
            .chain(self.developer.iter().map(|block| (block, true)))
            .chain(self.user.iter().map(|block| (block, false)))
            .enumerate()
        {
            let text = match &block.source.path {
                Some(path) => format!("# {} ({path})\n{}", block.source.label, block.content),
                None => format!("# {}\n{}", block.source.label, block.content),
            };
            records.push(ContextRecord {
                id: format!("instruction:{}:{index}", thread_id),
                turn_id: None,
                source: if instruction {
                    ContextSource::Instruction
                } else {
                    ContextSource::RuntimeFact {
                        source_id: format!("studio.instructions:{index}"),
                    }
                },
                content: vec![ContextContent::Text {
                    text: Arc::from(text),
                }],
                tool_calls: Vec::new(),
            });
        }
        records
    }

    pub(super) fn push_developer(&mut self, source: InstructionSource, content: &str) {
        push_non_empty(&mut self.developer, source, content);
    }

    pub(super) fn push_user(&mut self, source: InstructionSource, content: &str) {
        push_non_empty(&mut self.user, source, content);
    }
}

impl InstructionSource {
    pub(super) fn new(kind: InstructionSourceKind, label: impl Into<String>) -> Self {
        Self {
            kind,
            label: label.into(),
            path: None,
        }
    }

    pub(super) fn path(kind: InstructionSourceKind, label: impl Into<String>, path: &Path) -> Self {
        Self {
            kind,
            label: label.into(),
            path: Some(path.display().to_string()),
        }
    }
}

fn push_non_empty(blocks: &mut Vec<InstructionBlock>, source: InstructionSource, content: &str) {
    let content = content.trim();
    if content.is_empty() {
        return;
    }
    blocks.push(InstructionBlock {
        source,
        content: content.to_string(),
    });
}
