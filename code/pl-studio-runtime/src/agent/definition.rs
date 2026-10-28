//! 产品 Agent 定义：驱动统一指令装配的稳定身份、适用范围与角色指令。
//!
//! 普通根会话与飞书根会话使用本模块的产品内置定义，child 从已冻结的系统或用户 Agent
//! Profile 解析定义。定义只回答“谁在执行”：它不拥有模型路由、workspace 归属、步骤预算或
//! 工具权限，也不进入可派发的 Profile 目录。已解析定义随 instruction snapshot 冻结，Mode
//! 执行方式由独立的指令来源更新。

use pl_protocol::{AgentProfileSnapshot, AgentWorkspaceMode, PureError};
use serde::{Deserialize, Serialize};

use super::catalog::{self, BuiltinAgentDefinition};

/// 旧快照迁移边界上的普通根身份；正常恢复不依赖这些 ID。
pub(crate) const STUDIO_ROOT_ID: &str = "root:main";
/// 旧快照迁移边界上的机器人根身份；正常恢复不依赖这些 ID。
pub(crate) const FEISHU_ROOT_ID: &str = "root:feishu";
/// 迁移专用的渠道未指定根身份。
///
/// 旧通用根会话没有可验证的渠道归属时使用：它保留原正文，明确表示渠道未指定，既不能用于
/// 新建，也不能被派发，更不是正常运行的后备身份。
pub(crate) const LEGACY_ROOT_ID: &str = "root:legacy";
/// 旧版混用来源迁移后的修订：明确区别于任何当前内置或 Profile 修订。
const MIGRATED_REVISION: &str = "legacy";
/// 根定义占用保留命名空间，因此不能与用户 Agent Profile 名称冲突，也不能被派发。
const ROOT_ID_PREFIX: &str = "root:";

/// Trusted product entry that may bind a root Agent definition.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub(crate) enum AgentRootEntry {
    Studio,
    Bot,
}

/// Frozen usage binding, independent from definition source and allowed scope.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(
    tag = "kind",
    content = "entry",
    rename_all = "camelCase",
    deny_unknown_fields
)]
pub(crate) enum AgentUsageBinding {
    RootEntry(AgentRootEntry),
    Child,
    /// Set only after validating a historical snapshot whose root channel was not provable.
    LegacyUnspecifiedRoot {
        source_version: u32,
    },
}

/// 定义适用的会话范围；root 定义不可派发为 child。
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(crate) enum AgentDefinitionScope {
    Root,
    Child,
}

/// 定义来源，用于区分当前内置/Profile 定义与迁移保留下来的旧版指令。
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(crate) enum AgentDefinitionOrigin {
    Builtin,
    Profile,
    Migrated,
}

/// 随 instruction snapshot 冻结的 Agent 身份与修订。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct AgentDefinitionIdentity {
    pub id: String,
    pub scope: AgentDefinitionScope,
    pub usage_binding: AgentUsageBinding,
    pub revision: String,
    pub origin: AgentDefinitionOrigin,
}

/// 实际驱动一次指令装配的已解析 Agent 定义。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ResolvedAgentDefinition {
    identity: AgentDefinitionIdentity,
    display_name: String,
    description: String,
    when_to_use: String,
    instructions: String,
    workspace_mode: Option<AgentWorkspaceMode>,
}

impl ResolvedAgentDefinition {
    /// Resolves a trusted product-entry binding to its common embedded Agent declaration.
    pub(crate) fn root(entry: AgentRootEntry) -> Result<Self, PureError> {
        let declaration = catalog::root_definition(entry)?;
        if declaration.identity.scope != AgentDefinitionScope::Root {
            return Err(PureError::ConfigError(format!(
                "trusted product entry `{entry:?}` does not resolve to a root Agent"
            )));
        }
        Ok(Self::from_builtin(declaration))
    }

    pub(crate) fn from_builtin(definition: &BuiltinAgentDefinition) -> Self {
        Self {
            identity: definition.identity.clone(),
            display_name: definition.display_name.clone(),
            description: definition.description.clone(),
            when_to_use: definition.when_to_use.clone(),
            instructions: definition.instructions.trim().to_owned(),
            workspace_mode: definition.workspace_mode,
        }
    }

    /// 从已冻结的系统或用户 Profile 解析 child 定义。
    ///
    /// 身份与修订来自该 Profile 快照本身，因此重启或配置更新不会重新选择 child 角色。
    pub(crate) fn from_profile(profile: &AgentProfileSnapshot) -> Result<Self, PureError> {
        if profile.profile_id.trim().is_empty() || profile.profile_id.trim() != profile.profile_id {
            return Err(PureError::ConfigError(
                "saved Agent Profile has an invalid identity".into(),
            ));
        }
        if is_root_definition_id(&profile.profile_id) {
            return Err(PureError::ConfigError(format!(
                "root Agent definition `{}` cannot become a child Agent",
                profile.profile_id
            )));
        }
        let origin = if profile.system {
            AgentDefinitionOrigin::Builtin
        } else {
            AgentDefinitionOrigin::Profile
        };
        Ok(Self {
            identity: AgentDefinitionIdentity {
                id: profile.profile_id.clone(),
                scope: AgentDefinitionScope::Child,
                usage_binding: AgentUsageBinding::Child,
                revision: profile.revision.clone(),
                origin,
            },
            display_name: profile.display_name.clone(),
            description: profile.description.clone(),
            when_to_use: profile.when_to_use.clone(),
            instructions: profile.system_instructions.trim().to_owned(),
            workspace_mode: Some(profile.workspace_mode),
        })
    }

    pub(crate) fn identity(&self) -> &AgentDefinitionIdentity {
        &self.identity
    }

    /// 指令块标签；与 Mode 标签相互独立。
    pub(crate) fn label(&self) -> &str {
        &self.display_name
    }

    pub(crate) fn display_name(&self) -> &str {
        &self.display_name
    }

    pub(crate) fn description(&self) -> &str {
        &self.description
    }

    pub(crate) fn when_to_use(&self) -> &str {
        &self.when_to_use
    }

    /// 角色正文；空正文表示该定义不追加角色提示词。
    pub(crate) fn instructions(&self) -> &str {
        &self.instructions
    }

    pub(crate) fn workspace_mode(&self) -> Option<AgentWorkspaceMode> {
        self.workspace_mode
    }
}

/// 恢复和迁移边界上可核实的身份事实。
///
/// 它校验已冻结身份，并为旧版快照选择要冻结的身份。新建会话不使用它：新建身份直接来自
/// [`ResolvedAgentDefinition`]。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum VerifiedAgentIdentity {
    /// 已核实机器人归属的根会话。
    BotRoot,
    /// 保存事实可证明根角色，但没有可验证渠道的旧通用根会话。
    GenericRoot,
    /// child 已冻结的 Profile 身份。
    Child {
        id: String,
        revision: String,
        origin: AgentDefinitionOrigin,
    },
}

impl VerifiedAgentIdentity {
    /// 从已冻结 Profile 得到 child 的可核实身份。
    pub(crate) fn child(profile: &AgentProfileSnapshot) -> Result<Self, PureError> {
        let definition = ResolvedAgentDefinition::from_profile(profile)?;
        Ok(Self::Child {
            id: definition.identity.id.clone(),
            revision: definition.identity.revision.clone(),
            origin: definition.identity.origin,
        })
    }

    pub(crate) fn scope(&self) -> AgentDefinitionScope {
        match self {
            Self::Child { .. } => AgentDefinitionScope::Child,
            Self::BotRoot | Self::GenericRoot => AgentDefinitionScope::Root,
        }
    }

    /// 旧版快照迁移后要冻结的身份：保留原正文，来源与修订明确标为迁移。
    pub(crate) fn migrated_identity(&self) -> AgentDefinitionIdentity {
        match self {
            Self::BotRoot => migrated_root_identity(
                FEISHU_ROOT_ID,
                AgentUsageBinding::RootEntry(AgentRootEntry::Bot),
            ),
            Self::GenericRoot => migrated_root_identity(
                LEGACY_ROOT_ID,
                AgentUsageBinding::LegacyUnspecifiedRoot { source_version: 1 },
            ),
            Self::Child { id, .. } => AgentDefinitionIdentity {
                id: id.clone(),
                scope: AgentDefinitionScope::Child,
                usage_binding: AgentUsageBinding::Child,
                revision: MIGRATED_REVISION.to_owned(),
                origin: AgentDefinitionOrigin::Migrated,
            },
        }
    }

    /// 校验已冻结身份：ID、范围与来源/修订组合必须与可核实事实一致。
    ///
    /// 内置根身份允许任意非空修订，因此当前构建升级内置提示词版本后仍能恢复旧会话；它不
    /// 允许借保留旧版本接受另一个 Profile 或另一个范围的身份。
    pub(crate) fn validate(&self, saved: &AgentDefinitionIdentity) -> Result<(), PureError> {
        if saved.id.trim().is_empty()
            || saved.id.trim() != saved.id
            || saved.revision.trim().is_empty()
            || saved.revision.trim() != saved.revision
        {
            return Err(identity_conflict(
                "saved Agent identity is incomplete",
                saved,
            ));
        }
        if saved.scope != self.scope() {
            return Err(identity_conflict(
                "saved Agent identity has a conflicting scope",
                saved,
            ));
        }
        if !usage_binding_matches_scope(saved) {
            return Err(identity_conflict(
                "saved Agent identity has a usage binding incompatible with its scope",
                saved,
            ));
        }
        match self {
            Self::Child {
                id,
                revision,
                origin,
            } => {
                if &saved.id != id {
                    return Err(identity_conflict(
                        "saved Agent identity does not belong to the frozen Profile",
                        saved,
                    ));
                }
                if saved.usage_binding != AgentUsageBinding::Child {
                    return Err(identity_conflict(
                        "saved child Agent has a conflicting usage binding",
                        saved,
                    ));
                }
                match saved.origin {
                    saved_origin if saved_origin == *origin && &saved.revision == revision => {
                        Ok(())
                    }
                    AgentDefinitionOrigin::Migrated if saved.revision == MIGRATED_REVISION => {
                        Ok(())
                    }
                    _ => Err(identity_conflict(
                        "saved Agent identity has an invalid origin or revision",
                        saved,
                    )),
                }
            }
            Self::BotRoot | Self::GenericRoot => validate_current_root(self, saved),
        }
    }

    /// Validates the version-2 identity contract before its Agent block shape is upgraded.
    pub(crate) fn validate_v2(&self, saved: &AgentDefinitionIdentity) -> Result<(), PureError> {
        if saved.id.trim().is_empty()
            || saved.id.trim() != saved.id
            || saved.revision.trim().is_empty()
            || saved.revision.trim() != saved.revision
            || saved.scope != self.scope()
        {
            return Err(identity_conflict(
                "saved version-2 Agent identity is incomplete or conflicting",
                saved,
            ));
        }
        match self {
            Self::Child { id, revision, .. } => {
                if &saved.id != id {
                    return Err(identity_conflict(
                        "saved Agent identity does not belong to the frozen Profile",
                        saved,
                    ));
                }
                match saved.origin {
                    AgentDefinitionOrigin::Profile if &saved.revision == revision => Ok(()),
                    AgentDefinitionOrigin::Migrated if saved.revision == MIGRATED_REVISION => {
                        Ok(())
                    }
                    _ => Err(identity_conflict(
                        "saved version-2 child identity has an invalid origin or revision",
                        saved,
                    )),
                }
            }
            Self::BotRoot | Self::GenericRoot => {
                let accepted = match (self, saved.origin) {
                    (Self::BotRoot, AgentDefinitionOrigin::Builtin) => saved.id == FEISHU_ROOT_ID,
                    (Self::GenericRoot, AgentDefinitionOrigin::Builtin) => {
                        matches!(saved.id.as_str(), STUDIO_ROOT_ID | FEISHU_ROOT_ID)
                    }
                    (Self::BotRoot | Self::GenericRoot, AgentDefinitionOrigin::Migrated) => {
                        saved.revision == MIGRATED_REVISION
                            && matches!(saved.id.as_str(), FEISHU_ROOT_ID | LEGACY_ROOT_ID)
                    }
                    (Self::BotRoot | Self::GenericRoot, AgentDefinitionOrigin::Profile) => false,
                    (Self::Child { .. }, _) => false,
                };
                if !accepted {
                    return Err(identity_conflict(
                        "saved version-2 root identity contradicts the verified root facts",
                        saved,
                    ));
                }
                Ok(())
            }
        }
    }
}

fn validate_current_root(
    verified: &VerifiedAgentIdentity,
    saved: &AgentDefinitionIdentity,
) -> Result<(), PureError> {
    let valid_id = saved
        .id
        .strip_prefix(ROOT_ID_PREFIX)
        .is_some_and(valid_agent_id);
    let valid_origin = match saved.origin {
        AgentDefinitionOrigin::Builtin => true,
        AgentDefinitionOrigin::Migrated => saved.revision == MIGRATED_REVISION,
        AgentDefinitionOrigin::Profile => false,
    };
    let valid_binding = match verified {
        VerifiedAgentIdentity::BotRoot => {
            saved.usage_binding == AgentUsageBinding::RootEntry(AgentRootEntry::Bot)
        }
        VerifiedAgentIdentity::GenericRoot => matches!(
            &saved.usage_binding,
            AgentUsageBinding::RootEntry(AgentRootEntry::Studio)
                | AgentUsageBinding::LegacyUnspecifiedRoot {
                    source_version: 1 | 2
                }
        ),
        VerifiedAgentIdentity::Child { .. } => false,
    };
    if valid_id && valid_origin && valid_binding {
        Ok(())
    } else {
        Err(identity_conflict(
            "saved root identity contradicts its frozen usage binding or verified host ownership",
            saved,
        ))
    }
}

pub(crate) fn usage_binding_matches_scope(identity: &AgentDefinitionIdentity) -> bool {
    matches!(
        (&identity.scope, &identity.usage_binding),
        (
            AgentDefinitionScope::Root,
            AgentUsageBinding::RootEntry(_)
                | AgentUsageBinding::LegacyUnspecifiedRoot {
                    source_version: 1 | 2
                }
        ) | (AgentDefinitionScope::Child, AgentUsageBinding::Child)
    )
}

fn valid_agent_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 64
        && id.bytes().all(|byte| {
            byte.is_ascii_lowercase() || byte.is_ascii_digit() || matches!(byte, b'-' | b'_')
        })
}

pub(crate) fn migrated_root_identity(
    id: &str,
    usage_binding: AgentUsageBinding,
) -> AgentDefinitionIdentity {
    AgentDefinitionIdentity {
        id: id.to_owned(),
        scope: AgentDefinitionScope::Root,
        usage_binding,
        revision: MIGRATED_REVISION.to_owned(),
        origin: AgentDefinitionOrigin::Migrated,
    }
}

fn identity_conflict(reason: &str, saved: &AgentDefinitionIdentity) -> PureError {
    PureError::ConfigError(format!(
        "{reason}: id `{}`, scope {:?}, revision `{}`, origin {:?}",
        saved.id, saved.scope, saved.revision, saved.origin
    ))
}

/// 根定义身份占用保留命名空间，既不能派发为 child，也不能被用户 Profile 占用。
pub(crate) fn is_root_definition_id(id: &str) -> bool {
    id.starts_with(ROOT_ID_PREFIX)
}
