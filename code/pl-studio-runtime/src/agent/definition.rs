//! 产品 Agent 定义：驱动统一指令装配的稳定身份、适用范围与角色指令。
//!
//! 普通根会话与飞书根会话使用本模块的产品内置定义，child 从已冻结的系统或用户 Agent
//! Profile 解析定义。定义只回答“谁在执行”：它不拥有模型路由、workspace 归属、步骤预算或
//! 工具权限，也不进入可派发的 Profile 目录。已解析定义随 instruction snapshot 冻结，Mode
//! 执行方式由独立的指令来源更新。

use pl_protocol::{AgentProfileSnapshot, PureError};
use serde::{Deserialize, Serialize};

/// 产品内置的普通根会话定义身份。
pub(crate) const STUDIO_ROOT_ID: &str = "root:main";
/// 产品内置的飞书根会话定义身份。
pub(crate) const FEISHU_ROOT_ID: &str = "root:feishu";
/// 迁移专用的渠道未指定根身份。
///
/// 旧通用根会话没有可验证的渠道归属时使用：它保留原正文，明确表示渠道未指定，既不能用于
/// 新建，也不能被派发，更不是正常运行的后备身份。
pub(crate) const LEGACY_ROOT_ID: &str = "root:legacy";
/// 内置定义的修订；角色指令内容变化时才提高。
const BUILTIN_REVISION: &str = "1";
/// 旧版混用来源迁移后的修订：明确区别于任何当前内置或 Profile 修订。
const MIGRATED_REVISION: &str = "legacy";
/// 根定义占用保留命名空间，因此不能与用户 Agent Profile 名称冲突，也不能被派发。
const ROOT_ID_PREFIX: &str = "root:";

const FEISHU_INSTRUCTIONS: &str = include_str!("../prompts/feishu.md");

/// 拥有根会话的渠道。只用于选择内置定义，不代表执行循环或 Thread 所有权。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum AgentChannel {
    Studio,
    Bot,
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
    pub revision: String,
    pub origin: AgentDefinitionOrigin,
}

/// 实际驱动一次指令装配的已解析 Agent 定义。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ResolvedAgentDefinition {
    identity: AgentDefinitionIdentity,
    label: String,
    instructions: String,
}

impl ResolvedAgentDefinition {
    fn new(identity: AgentDefinitionIdentity, label: &str, instructions: &str) -> Self {
        Self {
            identity,
            label: label.to_owned(),
            instructions: instructions.trim().to_owned(),
        }
    }

    /// 根会话的内置定义。
    ///
    /// 普通根会话只冻结身份与范围：它的角色正文仍由统一 base 装配提供，本定义不追加额外
    /// 角色提示词。飞书根会话追加固定的渠道内容指令，不提供逐机器人编辑入口。
    pub(crate) fn root(channel: AgentChannel) -> Self {
        match channel {
            AgentChannel::Studio => Self::new(builtin_identity(STUDIO_ROOT_ID), "root agent", ""),
            AgentChannel::Bot => Self::new(
                builtin_identity(FEISHU_ROOT_ID),
                "feishu root agent",
                FEISHU_INSTRUCTIONS,
            ),
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
        Ok(Self::new(
            AgentDefinitionIdentity {
                id: profile.profile_id.clone(),
                scope: AgentDefinitionScope::Child,
                revision: profile.revision.clone(),
                origin: AgentDefinitionOrigin::Profile,
            },
            &profile.display_name,
            &profile.system_instructions,
        ))
    }

    pub(crate) fn identity(&self) -> &AgentDefinitionIdentity {
        &self.identity
    }

    /// 指令块标签；与 Mode 标签相互独立。
    pub(crate) fn label(&self) -> &str {
        &self.label
    }

    /// 角色正文；空正文表示该定义不追加角色提示词。
    pub(crate) fn instructions(&self) -> &str {
        &self.instructions
    }
}

fn builtin_identity(id: &str) -> AgentDefinitionIdentity {
    AgentDefinitionIdentity {
        id: id.to_owned(),
        scope: AgentDefinitionScope::Root,
        revision: BUILTIN_REVISION.to_owned(),
        origin: AgentDefinitionOrigin::Builtin,
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
    Child { id: String, revision: String },
}

impl VerifiedAgentIdentity {
    /// 从已冻结 Profile 得到 child 的可核实身份。
    pub(crate) fn child(profile: &AgentProfileSnapshot) -> Result<Self, PureError> {
        let definition = ResolvedAgentDefinition::from_profile(profile)?;
        Ok(Self::Child {
            id: definition.identity.id.clone(),
            revision: definition.identity.revision.clone(),
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
            Self::BotRoot => migrated_root_identity(FEISHU_ROOT_ID),
            Self::GenericRoot => migrated_root_identity(LEGACY_ROOT_ID),
            Self::Child { id, .. } => AgentDefinitionIdentity {
                id: id.clone(),
                scope: AgentDefinitionScope::Child,
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
        match self {
            Self::Child { id, revision } => {
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
                        "saved Agent identity has an invalid origin or revision",
                        saved,
                    )),
                }
            }
            Self::BotRoot | Self::GenericRoot => match (saved.origin, saved.id.as_str()) {
                (AgentDefinitionOrigin::Builtin, STUDIO_ROOT_ID | FEISHU_ROOT_ID) => {
                    if matches!(self, Self::BotRoot) && saved.id != FEISHU_ROOT_ID {
                        return Err(identity_conflict(
                            "saved Agent identity contradicts the verified bot ownership",
                            saved,
                        ));
                    }
                    Ok(())
                }
                (AgentDefinitionOrigin::Migrated, FEISHU_ROOT_ID | LEGACY_ROOT_ID)
                    if saved.revision == MIGRATED_REVISION =>
                {
                    Ok(())
                }
                _ => Err(identity_conflict(
                    "saved Agent identity has an invalid origin or revision",
                    saved,
                )),
            },
        }
    }
}

fn migrated_root_identity(id: &str) -> AgentDefinitionIdentity {
    AgentDefinitionIdentity {
        id: id.to_owned(),
        scope: AgentDefinitionScope::Root,
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
