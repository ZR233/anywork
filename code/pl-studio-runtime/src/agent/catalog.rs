//! Built-in declarations shared by root Agent selection and the child Profile view.

use std::collections::BTreeSet;
use std::sync::OnceLock;

use pl_protocol::{AgentWorkspaceMode, PureError};
use serde::Serialize;

use super::definition::{
    AgentDefinitionIdentity, AgentDefinitionOrigin, AgentDefinitionScope, AgentRootEntry,
    AgentUsageBinding,
};

static CATALOG: OnceLock<std::result::Result<Vec<BuiltinAgentDefinition>, AgentCatalogError>> =
    OnceLock::new();

const DECLARATIONS: [Declaration; 6] = [
    Declaration {
        id: "executor",
        scope: DeclarationScope::Child,
        entry: None,
        display_name: "执行者",
        description: "实施明确、边界清楚的工程任务。",
        when_to_use: "已有目标和范围，需要修改与验证代码时。",
        instructions: include_str!("prompts/executor.md"),
        workspace_mode: Some(AgentWorkspaceMode::Directory),
    },
    Declaration {
        id: "explorer",
        scope: DeclarationScope::Child,
        entry: None,
        display_name: "探索者",
        description: "只读探索代码、文档和现场事实。",
        when_to_use: "需要快速定位边界、依赖、实现入口或验证事实时。",
        instructions: include_str!("prompts/explorer.md"),
        workspace_mode: Some(AgentWorkspaceMode::Unrestricted),
    },
    Declaration {
        id: "reviewer",
        scope: DeclarationScope::Child,
        entry: None,
        display_name: "审查者",
        description: "检查实现、测试、错误路径和需求一致性。",
        when_to_use: "需要独立复核已完成工作并报告具体问题时。",
        instructions: include_str!("prompts/reviewer.md"),
        workspace_mode: Some(AgentWorkspaceMode::Review),
    },
    Declaration {
        id: "root:feishu",
        scope: DeclarationScope::Root,
        entry: Some(AgentRootEntry::Bot),
        display_name: "飞书主智能体",
        description: "通过已验证飞书入口处理用户请求并在原会话回复。",
        when_to_use: "可信飞书机器人归属的根会话。",
        instructions: include_str!("prompts/feishu.md"),
        workspace_mode: None,
    },
    Declaration {
        id: "root:main",
        scope: DeclarationScope::Root,
        entry: Some(AgentRootEntry::Studio),
        display_name: "主智能体",
        description: "接收用户请求并对整体任务负责。",
        when_to_use: "普通 Studio 会话的用户入口。",
        instructions: include_str!("prompts/main.md"),
        workspace_mode: None,
    },
    Declaration {
        id: "worktree_executor",
        scope: DeclarationScope::Child,
        entry: None,
        display_name: "Worktree 执行者",
        description: "在独立 Git worktree 中实施明确任务。",
        when_to_use: "需要物理隔离修改，并由主代理审查、整合和清理时。",
        instructions: include_str!("prompts/worktree_executor.md"),
        workspace_mode: Some(AgentWorkspaceMode::Worktree),
    },
];

/// Typed built-in catalog failure; startup must not treat this as damaged user data.
#[derive(Debug, Clone, thiserror::Error)]
#[error("invalid built-in Agent declarations: {message}")]
pub(crate) struct AgentCatalogError {
    message: String,
}

impl AgentCatalogError {
    pub(crate) fn invalid(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

/// An immutable product declaration. Usage scope is independent of its builtin origin.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct BuiltinAgentDefinition {
    pub identity: AgentDefinitionIdentity,
    pub display_name: String,
    pub description: String,
    pub when_to_use: String,
    pub instructions: String,
    pub workspace_mode: Option<AgentWorkspaceMode>,
}

#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "snake_case")]
struct Declaration {
    id: &'static str,
    scope: DeclarationScope,
    entry: Option<AgentRootEntry>,
    display_name: &'static str,
    description: &'static str,
    when_to_use: &'static str,
    instructions: &'static str,
    workspace_mode: Option<AgentWorkspaceMode>,
}

#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum DeclarationScope {
    Root,
    Child,
}

/// Returns the validated built-in catalog. The first caller publishes either the complete
/// immutable catalog or its error; no caller can observe a partially loaded declaration set.
pub(crate) fn definitions() -> Result<&'static [BuiltinAgentDefinition], PureError> {
    definitions_typed().map_err(|error| PureError::ConfigError(error.to_string()))
}

pub(crate) fn definition(id: &str) -> Result<Option<&'static BuiltinAgentDefinition>, PureError> {
    Ok(definitions()?
        .iter()
        .find(|definition| definition.identity.id == id))
}

pub(crate) fn child_ids() -> Result<BTreeSet<String>, PureError> {
    Ok(definitions()?
        .iter()
        .filter(|definition| definition.identity.scope == AgentDefinitionScope::Child)
        .map(|definition| definition.identity.id.clone())
        .collect())
}

/// Validates the complete built-in catalog before configuration recovery or publication starts.
pub(crate) fn validate_startup_entries() -> Result<(), AgentCatalogError> {
    definitions_typed().map(|_| ())
}

pub(crate) fn root_definition(
    entry: AgentRootEntry,
) -> Result<&'static BuiltinAgentDefinition, PureError> {
    definitions()?
        .iter()
        .find(|definition| definition.identity.usage_binding == AgentUsageBinding::RootEntry(entry))
        .ok_or_else(|| {
            PureError::ConfigError(format!(
                "trusted product entry `{entry:?}` has no built-in root Agent declaration"
            ))
        })
}

fn definitions_typed() -> Result<&'static [BuiltinAgentDefinition], AgentCatalogError> {
    match CATALOG
        .get_or_init(|| load().map_err(|error| AgentCatalogError::invalid(format!("{error:#}"))))
    {
        Ok(definitions) => Ok(definitions),
        Err(error) => Err(error.clone()),
    }
}

fn load() -> anyhow::Result<Vec<BuiltinAgentDefinition>> {
    let mut definitions = Vec::with_capacity(DECLARATIONS.len());
    let mut ids = BTreeSet::new();
    for declaration in &DECLARATIONS {
        validate_declaration(declaration)?;
        if !ids.insert(declaration.id) {
            anyhow::bail!("duplicate built-in Agent id `{}`", declaration.id);
        }
        let instructions = declaration.instructions.trim();
        let revision = content_revision(declaration, instructions)?;
        let usage_binding = match (declaration.scope, declaration.entry) {
            (DeclarationScope::Root, Some(entry)) => AgentUsageBinding::RootEntry(entry),
            (DeclarationScope::Child, None) => AgentUsageBinding::Child,
            _ => anyhow::bail!("invalid usage binding for Agent `{}`", declaration.id),
        };
        let identity = AgentDefinitionIdentity {
            id: declaration.id.to_owned(),
            scope: declaration.scope.into(),
            usage_binding,
            revision,
            origin: AgentDefinitionOrigin::Builtin,
        };
        definitions.push(BuiltinAgentDefinition {
            identity,
            display_name: declaration.display_name.to_owned(),
            description: declaration.description.to_owned(),
            when_to_use: declaration.when_to_use.to_owned(),
            instructions: instructions.to_owned(),
            workspace_mode: declaration.workspace_mode,
        });
    }
    if definitions.is_empty() {
        anyhow::bail!("built-in Agent declaration catalog is empty");
    }
    for entry in [AgentRootEntry::Studio, AgentRootEntry::Bot] {
        let count = DECLARATIONS
            .iter()
            .filter(|declaration| {
                declaration.scope == DeclarationScope::Root && declaration.entry == Some(entry)
            })
            .count();
        anyhow::ensure!(
            count == 1,
            "trusted product entry `{entry:?}` has {count} root declarations; expected exactly one"
        );
    }
    definitions.sort_by(|left, right| left.identity.id.cmp(&right.identity.id));
    Ok(definitions)
}

fn validate_declaration(declaration: &Declaration) -> anyhow::Result<()> {
    let id_valid = match declaration.scope {
        DeclarationScope::Root => declaration
            .id
            .strip_prefix("root:")
            .is_some_and(valid_agent_id),
        DeclarationScope::Child => {
            declaration.id != crate::config::ROOT_AGENT_ROUTE_KEY && valid_agent_id(declaration.id)
        }
    };
    if !id_valid {
        anyhow::bail!(
            "Agent declaration `{}` has an invalid id for its scope",
            declaration.id
        );
    }
    match (declaration.scope, declaration.entry) {
        (DeclarationScope::Root, Some(_)) | (DeclarationScope::Child, None) => {}
        (DeclarationScope::Root, None) => {
            anyhow::bail!(
                "root Agent declaration `{}` must bind one trusted product entry",
                declaration.id
            )
        }
        (DeclarationScope::Child, Some(_)) => {
            anyhow::bail!(
                "child Agent declaration `{}` cannot bind a root product entry",
                declaration.id
            )
        }
    }
    for (field, value) in [
        ("display_name", declaration.display_name),
        ("description", declaration.description),
        ("when_to_use", declaration.when_to_use),
    ] {
        if value.trim().is_empty() {
            anyhow::bail!("Agent declaration `{}` has empty {field}", declaration.id);
        }
    }
    anyhow::ensure!(
        !declaration.instructions.trim().is_empty(),
        "Agent declaration `{}` has empty instructions",
        declaration.id
    );
    anyhow::ensure!(
        declaration.scope != DeclarationScope::Root || declaration.workspace_mode.is_none(),
        "root Agent declaration `{}` cannot define a child workspace mode",
        declaration.id
    );
    anyhow::ensure!(
        declaration.scope != DeclarationScope::Child || declaration.workspace_mode.is_some(),
        "child Agent declaration `{}` must define a workspace mode",
        declaration.id
    );
    Ok(())
}

fn valid_agent_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 64
        && id.bytes().all(|byte| {
            byte.is_ascii_lowercase() || byte.is_ascii_digit() || matches!(byte, b'-' | b'_')
        })
}

fn content_revision(declaration: &Declaration, instructions: &str) -> anyhow::Result<String> {
    #[derive(Serialize)]
    #[serde(rename_all = "camelCase")]
    struct Revision<'a> {
        id: &'a str,
        scope: DeclarationScope,
        entry: Option<AgentRootEntry>,
        display_name: &'a str,
        description: &'a str,
        when_to_use: &'a str,
        instructions: &'a str,
        workspace_mode: Option<AgentWorkspaceMode>,
    }
    let revision = Revision {
        id: declaration.id,
        scope: declaration.scope,
        entry: declaration.entry,
        display_name: declaration.display_name,
        description: declaration.description,
        when_to_use: declaration.when_to_use,
        instructions,
        workspace_mode: declaration.workspace_mode,
    };
    Ok(pl_core::context::content_hash(&serde_json::to_vec(
        &revision,
    )?))
}

impl From<DeclarationScope> for AgentDefinitionScope {
    fn from(scope: DeclarationScope) -> Self {
        match scope {
            DeclarationScope::Root => Self::Root,
            DeclarationScope::Child => Self::Child,
        }
    }
}
