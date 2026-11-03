//! Catalog TOML 的冻结历史 DTO 与 1→2→3→4→5→6 类型迁移链。
//!
//! 历史条目的嵌套 enum / 冻结路由使用本模块的 wire 形状，不借用会演进的
//! `pl_protocol` 类型。库链输出最新冻结文件 DTO [`CatalogV6`]；owner 再
//! `TryFrom` 为运行期 [`super::CatalogDocument`]。V5→V6 把逐 Thread 复合身份
//! 重组为会话/成员两级记录，缺失根、跨会话 parent 与循环都给出明确诊断。

use std::path::Path;
use std::sync::OnceLock;

use anyhow::{Result, bail, ensure};
use pl_protocol::{ThreadModeId, ThreadStatus, ThreadWorkspaceMode};
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use version_migrate::{IntoDomain, MigratesTo, Migrator, Versioned};

use super::CatalogDocument;
use crate::studio::records::{AgentDirectoryRecord, SessionDirectoryRecord};
use crate::toml_schema::{self, LoadedDocument};

pub(super) const ENTITY: &str = "catalog";
pub(super) const SCHEMA_KEY: &str = "schemaVersion";

pub(super) fn current_version() -> Result<u32> {
    toml_schema::integer_version(CatalogV6::VERSION)
        .map_err(|error| toml_schema::chain_error(ENTITY, error))
}

fn migrator() -> Result<&'static Migrator> {
    static MIGRATOR: OnceLock<Migrator> = OnceLock::new();
    if let Some(migrator) = MIGRATOR.get() {
        return Ok(migrator);
    }
    let mut migrator = Migrator::new();
    migrator
        .register(
            Migrator::define(ENTITY)
                .with_keys(SCHEMA_KEY, "data")
                .from::<CatalogDocumentV1>()
                .step::<CatalogDocumentV2>()
                .step::<CatalogDocumentV3>()
                .step::<CatalogV4>()
                .step::<CatalogV5>()
                .step::<CatalogV6>()
                .into::<CatalogV6>(),
        )
        .map_err(|error| toml_schema::chain_error(ENTITY, error))?;
    Ok(MIGRATOR.get_or_init(|| migrator))
}

pub(super) fn load_document(path: &Path, content: &str) -> Result<LoadedDocument<CatalogDocument>> {
    let loaded = toml_schema::load::<CatalogDocumentV1, CatalogV6>(
        path,
        content,
        migrator()?,
        ENTITY,
        SCHEMA_KEY,
    )?;
    let target = current_version()?;
    let document = CatalogDocument::try_from(loaded.document).map_err(|error| {
        toml_schema::migration_error(
            path,
            ENTITY,
            Some(loaded.source_version),
            target,
            "construct",
            error,
        )
    })?;
    validate(&document).map_err(|error| {
        toml_schema::migration_error(
            path,
            ENTITY,
            Some(loaded.source_version),
            target,
            "validate",
            error,
        )
    })?;
    Ok(LoadedDocument {
        document,
        source_version: loaded.source_version,
        migrated: loaded.migrated,
    })
}

pub(super) fn validate(document: &CatalogDocument) -> Result<()> {
    ensure!(document.revision >= 1, "Studio catalog revision is invalid");
    let mut sessions = std::collections::BTreeSet::new();
    for session in &document.sessions {
        ensure!(
            sessions.insert(session.session_id.as_str()),
            "Studio catalog has a duplicate session identity"
        );
        ensure!(
            !session.session_id.is_empty() && !session.root_agent_id.is_empty(),
            "Studio catalog session identity is incomplete"
        );
        ensure!(
            session.workspace_mode != ThreadWorkspaceMode::Worktree
                || !session.workspace_path.is_empty(),
            "Studio worktree catalog session has no workspace address"
        );
    }
    let mut agents = std::collections::BTreeMap::new();
    let mut threads = std::collections::BTreeSet::new();
    for agent in &document.agents {
        ensure!(
            agents
                .insert(agent.agent_id.clone(), agent.parent_agent_id.clone())
                .is_none(),
            "Studio catalog has a duplicate agent identity"
        );
        ensure!(
            threads.insert(agent.thread_id.as_str()),
            "Studio catalog agent identities do not map one-to-one to default threads"
        );
        ensure!(
            sessions.contains(agent.session_id.as_str()),
            "Studio catalog agent {} references a missing session",
            agent.agent_id
        );
    }
    // 成员关系唯一归属 agents 记录：parent 必须在同会话内且不构成环。
    let agent_sessions: std::collections::BTreeMap<String, &str> = document
        .agents
        .iter()
        .map(|agent| (agent.agent_id.clone(), agent.session_id.as_str()))
        .collect();
    for agent in &document.agents {
        if let Some(parent) = &agent.parent_agent_id {
            let parent_session = agent_sessions.get(parent).copied();
            ensure!(
                parent_session == Some(agent.session_id.as_str()),
                "Studio catalog agent {} has a parent outside its session",
                agent.agent_id
            );
        }
    }
    // 会话的主成员必须存在且确为主成员（parent 为空并属于该会话）。
    let agent_roots: std::collections::BTreeMap<&str, bool> = document
        .agents
        .iter()
        .map(|agent| (agent.agent_id.as_str(), agent.parent_agent_id.is_none()))
        .collect();
    for session in &document.sessions {
        ensure!(
            agent_roots
                .get(session.root_agent_id.as_str())
                .copied()
                .unwrap_or(false),
            "Studio catalog session {} has no root member",
            session.session_id
        );
    }
    for agent in &document.agents {
        let mut visited = std::collections::BTreeSet::new();
        let mut current = agent.parent_agent_id.clone();
        while let Some(id) = current {
            ensure!(
                visited.insert(id.clone()),
                "Studio catalog member chain from {} is cyclic",
                agent.agent_id
            );
            current = agents.get(&id).cloned().flatten();
        }
    }
    if document.sessions.is_empty() && document.revision > 1 {
        bail!("Studio catalog lost all sessions without a fresh install");
    }
    Ok(())
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Versioned)]
#[versioned(version = "1.0.0")]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct CatalogDocumentV1 {
    revision: u64,
    entries: Vec<CatalogEntryV1>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct CatalogEntryV1 {
    id: String,
    project_id: String,
    title: String,
    mode: FrozenModeId,
    workspace_mode: FrozenWorkspaceMode,
    workspace_path: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    parent_thread_id: Option<String>,
    root_thread_id: String,
    role: String,
    agent_path: String,
    status: FrozenThreadStatus,
    created_at: i64,
    updated_at: i64,
    archived: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Versioned)]
#[versioned(version = "2.0.0")]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct CatalogDocumentV2 {
    revision: u64,
    entries: Vec<CatalogEntryV2>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct CatalogEntryV2 {
    id: String,
    project_id: String,
    title: String,
    mode: FrozenModeId,
    workspace_mode: FrozenWorkspaceMode,
    workspace_path: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    parent_thread_id: Option<String>,
    root_thread_id: String,
    role: String,
    agent_path: String,
    status: FrozenThreadStatus,
    created_at: i64,
    updated_at: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    last_user_message_at: Option<i64>,
    archived: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Versioned)]
#[versioned(version = "3.0.0")]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct CatalogDocumentV3 {
    revision: u64,
    entries: Vec<CatalogEntryV3>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct CatalogEntryV3 {
    id: String,
    project_id: String,
    title: String,
    mode: FrozenModeId,
    workspace_mode: FrozenWorkspaceMode,
    delegation_mode: FrozenDelegationMode,
    delegation_preference: FrozenDelegationPreference,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    frozen_model: Option<FrozenModelRoute>,
    workspace_path: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    parent_thread_id: Option<String>,
    root_thread_id: String,
    role: String,
    agent_path: String,
    status: FrozenThreadStatus,
    created_at: i64,
    updated_at: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    last_user_message_at: Option<i64>,
    archived: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Versioned)]
#[versioned(version = "4.0.0")]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct CatalogV4 {
    revision: u64,
    entries: Vec<CatalogEntryV4>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct CatalogEntryV4 {
    explicitly_closed: bool,
    id: String,
    project_id: String,
    title: String,
    mode: FrozenModeId,
    workspace_mode: FrozenWorkspaceMode,
    delegation_mode: FrozenDelegationMode,
    delegation_preference: FrozenDelegationPreference,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    frozen_model: Option<FrozenModelRoute>,
    workspace_path: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    parent_thread_id: Option<String>,
    root_thread_id: String,
    role: String,
    agent_path: String,
    status: FrozenThreadStatus,
    created_at: i64,
    updated_at: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    last_user_message_at: Option<i64>,
    archived: bool,
}

#[derive(Debug, Serialize, Deserialize, Versioned)]
#[versioned(version = "5.0.0")]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct CatalogV5 {
    revision: u64,
    entries: Vec<CatalogEntryV5>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct CatalogEntryV5 {
    explicitly_closed: bool,
    id: String,
    workspace_id: String,
    title: String,
    mode: FrozenModeId,
    workspace_mode: FrozenWorkspaceMode,
    delegation_mode: FrozenDelegationMode,
    delegation_preference: FrozenDelegationPreference,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    frozen_model: Option<FrozenModelRoute>,
    workspace_path: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    parent_thread_id: Option<String>,
    root_thread_id: String,
    role: String,
    agent_path: String,
    status: FrozenThreadStatus,
    created_at: i64,
    updated_at: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    last_user_message_at: Option<i64>,
    archived: bool,
}

/// V6 会话目录事实记录（冻结 wire 形状）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct CatalogSessionV6 {
    session_id: String,
    root_agent_id: String,
    workspace_id: String,
    title: String,
    mode: FrozenModeId,
    workspace_mode: FrozenWorkspaceMode,
    delegation_mode: FrozenDelegationMode,
    delegation_preference: FrozenDelegationPreference,
    workspace_path: String,
    created_at: i64,
    updated_at: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    last_user_message_at: Option<i64>,
    archived: bool,
}

/// V6 成员事实记录（冻结 wire 形状）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct CatalogAgentV6 {
    agent_id: String,
    session_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    parent_agent_id: Option<String>,
    thread_id: String,
    role: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    title: Option<String>,
    binding: FrozenAgentBinding,
    status: FrozenThreadStatus,
    explicitly_closed: bool,
    created_at: i64,
    updated_at: i64,
}

/// 成员 backend 绑定的冻结 wire 形状；与 `pl_protocol::AgentBinding` 的
/// internally-tagged 形状保持一致，但字段固定在迁移边界。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub(super) enum FrozenAgentBinding {
    Native {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        route: Option<FrozenModelRoute>,
    },
    Acp {
        account_id: String,
        connection_revision: u64,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Versioned)]
#[versioned(version = "6.0.0")]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct CatalogV6 {
    revision: u64,
    sessions: Vec<CatalogSessionV6>,
    agents: Vec<CatalogAgentV6>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct FrozenModeId(String);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
enum FrozenWorkspaceMode {
    Local,
    Worktree,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
enum FrozenThreadStatus {
    Idle,
    Queued,
    Running,
    WaitingTool,
    WaitingInteraction,
    Cancelling,
    Closing,
    Closed,
    Faulted,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
enum FrozenDelegationMode {
    Profile,
    Automatic,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
enum FrozenDelegationPreference {
    Economy,
    Balanced,
    Fast,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct FrozenModelRoute {
    account_id: String,
    model_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    effort: Option<String>,
}

impl Serialize for FrozenModeId {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(&self.0)
    }
}

impl<'de> Deserialize<'de> for FrozenModeId {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let canonical = String::deserialize(deserializer)?;
        parse_frozen_mode_id(canonical).map_err(serde::de::Error::custom)
    }
}

fn parse_frozen_mode_id(canonical: String) -> Result<FrozenModeId, String> {
    let name = canonical.strip_prefix("mode.").unwrap_or_default();
    if name.is_empty()
        || canonical.len() > 64
        || !name.bytes().all(|byte| {
            byte.is_ascii_lowercase() || byte.is_ascii_digit() || matches!(byte, b'-' | b'_')
        })
    {
        return Err(format!("invalid catalog mode {canonical}"));
    }
    Ok(FrozenModeId(canonical))
}

impl FrozenWorkspaceMode {
    fn current(self) -> ThreadWorkspaceMode {
        match self {
            Self::Local => ThreadWorkspaceMode::Local,
            Self::Worktree => ThreadWorkspaceMode::Worktree,
        }
    }
}

impl FrozenThreadStatus {
    fn current(self) -> ThreadStatus {
        match self {
            Self::Idle => ThreadStatus::Idle,
            Self::Queued => ThreadStatus::Queued,
            Self::Running => ThreadStatus::Running,
            Self::WaitingTool => ThreadStatus::WaitingTool,
            Self::WaitingInteraction => ThreadStatus::WaitingInteraction,
            Self::Cancelling => ThreadStatus::Cancelling,
            Self::Closing => ThreadStatus::Closing,
            Self::Closed => ThreadStatus::Closed,
            Self::Faulted => ThreadStatus::Faulted,
        }
    }
}

impl FrozenDelegationMode {
    fn current(self) -> pl_protocol::DelegationMode {
        match self {
            Self::Profile => pl_protocol::DelegationMode::Profile,
            Self::Automatic => pl_protocol::DelegationMode::Automatic,
        }
    }
}

impl FrozenDelegationPreference {
    fn current(self) -> pl_protocol::DelegationPreference {
        match self {
            Self::Economy => pl_protocol::DelegationPreference::Economy,
            Self::Balanced => pl_protocol::DelegationPreference::Balanced,
            Self::Fast => pl_protocol::DelegationPreference::Fast,
        }
    }
}

impl FrozenModelRoute {
    fn current(self) -> pl_protocol::studio::NewThreadModelRoute {
        pl_protocol::studio::NewThreadModelRoute {
            account_id: self.account_id,
            model_id: self.model_id,
            effort: self.effort,
        }
    }
}

impl MigratesTo<CatalogDocumentV2> for CatalogDocumentV1 {
    fn migrate(self) -> CatalogDocumentV2 {
        CatalogDocumentV2 {
            revision: self.revision,
            entries: self
                .entries
                .into_iter()
                .map(|entry| CatalogEntryV2 {
                    id: entry.id,
                    project_id: entry.project_id,
                    title: entry.title,
                    mode: entry.mode,
                    workspace_mode: entry.workspace_mode,
                    workspace_path: entry.workspace_path,
                    parent_thread_id: entry.parent_thread_id,
                    root_thread_id: entry.root_thread_id,
                    role: entry.role,
                    agent_path: entry.agent_path,
                    status: entry.status,
                    created_at: entry.created_at,
                    updated_at: entry.updated_at,
                    last_user_message_at: None,
                    archived: entry.archived,
                })
                .collect(),
        }
    }
}

impl MigratesTo<CatalogDocumentV3> for CatalogDocumentV2 {
    fn migrate(self) -> CatalogDocumentV3 {
        CatalogDocumentV3 {
            revision: self.revision,
            entries: self
                .entries
                .into_iter()
                .map(|entry| CatalogEntryV3 {
                    id: entry.id,
                    project_id: entry.project_id,
                    title: entry.title,
                    mode: entry.mode,
                    workspace_mode: entry.workspace_mode,
                    delegation_mode: FrozenDelegationMode::Profile,
                    delegation_preference: FrozenDelegationPreference::Balanced,
                    frozen_model: None,
                    workspace_path: entry.workspace_path,
                    parent_thread_id: entry.parent_thread_id,
                    root_thread_id: entry.root_thread_id,
                    role: entry.role,
                    agent_path: entry.agent_path,
                    status: entry.status,
                    created_at: entry.created_at,
                    updated_at: entry.updated_at,
                    last_user_message_at: entry.last_user_message_at,
                    archived: entry.archived,
                })
                .collect(),
        }
    }
}

impl MigratesTo<CatalogV4> for CatalogDocumentV3 {
    fn migrate(self) -> CatalogV4 {
        CatalogV4 {
            revision: self.revision,
            entries: self
                .entries
                .into_iter()
                .map(|entry| CatalogEntryV4 {
                    explicitly_closed: false,
                    id: entry.id,
                    project_id: entry.project_id,
                    title: entry.title,
                    mode: entry.mode,
                    workspace_mode: entry.workspace_mode,
                    delegation_mode: entry.delegation_mode,
                    delegation_preference: entry.delegation_preference,
                    frozen_model: entry.frozen_model,
                    workspace_path: entry.workspace_path,
                    parent_thread_id: entry.parent_thread_id,
                    root_thread_id: entry.root_thread_id,
                    role: entry.role,
                    agent_path: entry.agent_path,
                    status: entry.status,
                    created_at: entry.created_at,
                    updated_at: entry.updated_at,
                    last_user_message_at: entry.last_user_message_at,
                    archived: entry.archived,
                })
                .collect(),
        }
    }
}

impl MigratesTo<CatalogV5> for CatalogV4 {
    fn migrate(self) -> CatalogV5 {
        CatalogV5 {
            revision: self.revision,
            entries: self
                .entries
                .into_iter()
                .map(|entry| CatalogEntryV5 {
                    workspace_id: entry.project_id,
                    explicitly_closed: entry.explicitly_closed,
                    id: entry.id,
                    title: entry.title,
                    mode: entry.mode,
                    workspace_mode: entry.workspace_mode,
                    delegation_mode: entry.delegation_mode,
                    delegation_preference: entry.delegation_preference,
                    frozen_model: entry.frozen_model,
                    workspace_path: entry.workspace_path,
                    parent_thread_id: entry.parent_thread_id,
                    root_thread_id: entry.root_thread_id,
                    role: entry.role,
                    agent_path: entry.agent_path,
                    status: entry.status,
                    created_at: entry.created_at,
                    updated_at: entry.updated_at,
                    last_user_message_at: entry.last_user_message_at,
                    archived: entry.archived,
                })
                .collect(),
        }
    }
}

/// V5 → V6：把逐 Thread 复合身份重组为会话/成员两级记录。
///
/// 同步迁移步骤必须是全函数（panic 不是文档装载的诊断通道）：按 `root_thread_id`
/// 分组，组内存在主成员时确立会话记录，旧 parent 引用按原字节转换为
/// `parent_agent_id`。缺失根、跨会话 parent、重复身份与成员环不做静默修复，
/// 原样保留给装载后的 [`validate`] 以类型化错误拒绝；会话级继承事实冲突时以
/// 主成员记录为准（成员记录不再携带这些列）。原 ID 字节不变。
impl MigratesTo<CatalogV6> for CatalogV5 {
    fn migrate(self) -> CatalogV6 {
        migrate_v5_to_v6(self)
    }
}

fn migrate_v5_to_v6(document: CatalogV5) -> CatalogV6 {
    let mut groups: std::collections::BTreeMap<&str, Vec<&CatalogEntryV5>> =
        std::collections::BTreeMap::new();
    for entry in &document.entries {
        groups
            .entry(entry.root_thread_id.as_str())
            .or_default()
            .push(entry);
    }
    let mut sessions = Vec::with_capacity(groups.len());
    let mut agents = Vec::with_capacity(document.entries.len());
    for (root_id, members) in groups {
        let root = members
            .iter()
            .find(|entry| entry.parent_thread_id.is_none() && entry.id == root_id);
        if let Some(root) = root {
            sessions.push(CatalogSessionV6 {
                session_id: root.id.clone(),
                root_agent_id: root.id.clone(),
                workspace_id: root.workspace_id.clone(),
                title: root.title.clone(),
                mode: root.mode.clone(),
                workspace_mode: root.workspace_mode,
                delegation_mode: root.delegation_mode,
                delegation_preference: root.delegation_preference,
                workspace_path: root.workspace_path.clone(),
                created_at: root.created_at,
                updated_at: root.updated_at,
                last_user_message_at: root.last_user_message_at,
                archived: root.archived,
            });
        }
        for entry in &members {
            let is_root = entry.id == root_id;
            agents.push(CatalogAgentV6 {
                agent_id: entry.id.clone(),
                session_id: entry.root_thread_id.clone(),
                parent_agent_id: entry.parent_thread_id.clone(),
                thread_id: entry.id.clone(),
                role: entry.role.clone(),
                title: (!is_root).then(|| entry.title.clone()),
                binding: FrozenAgentBinding::Native {
                    route: entry.frozen_model.clone(),
                },
                status: entry.status,
                explicitly_closed: entry.explicitly_closed,
                created_at: entry.created_at,
                updated_at: entry.updated_at,
            });
        }
    }
    CatalogV6 {
        revision: document.revision,
        sessions,
        agents,
    }
}

impl IntoDomain<CatalogV6> for CatalogV6 {
    fn into_domain(self) -> CatalogV6 {
        self
    }
}

impl TryFrom<CatalogV6> for CatalogDocument {
    type Error = anyhow::Error;

    fn try_from(document: CatalogV6) -> Result<Self> {
        Ok(Self {
            revision: document.revision,
            sessions: document
                .sessions
                .into_iter()
                .map(SessionDirectoryRecord::try_from)
                .collect::<Result<Vec<_>>>()?,
            agents: document
                .agents
                .into_iter()
                .map(AgentDirectoryRecord::try_from)
                .collect::<Result<Vec<_>>>()?,
        })
    }
}

impl TryFrom<CatalogSessionV6> for SessionDirectoryRecord {
    type Error = anyhow::Error;

    fn try_from(session: CatalogSessionV6) -> Result<Self> {
        Ok(Self {
            session_id: session.session_id,
            root_agent_id: session.root_agent_id,
            workspace_id: session.workspace_id,
            title: session.title,
            mode: ThreadModeId::new(session.mode.0)?,
            workspace_mode: session.workspace_mode.current(),
            delegation_mode: session.delegation_mode.current(),
            delegation_preference: session.delegation_preference.current(),
            workspace_path: session.workspace_path,
            created_at: session.created_at,
            updated_at: session.updated_at,
            last_user_message_at: session.last_user_message_at,
            archived: session.archived,
        })
    }
}

impl TryFrom<CatalogAgentV6> for AgentDirectoryRecord {
    type Error = anyhow::Error;

    fn try_from(agent: CatalogAgentV6) -> Result<Self> {
        Ok(Self {
            agent_id: agent.agent_id,
            session_id: agent.session_id,
            parent_agent_id: agent.parent_agent_id,
            thread_id: agent.thread_id,
            role: agent.role,
            title: agent.title,
            binding: match agent.binding {
                FrozenAgentBinding::Native { route } => {
                    pl_protocol::AgentBinding::Native(pl_protocol::NativeAgentConfig {
                        route: route.map(FrozenModelRoute::current),
                    })
                }
                FrozenAgentBinding::Acp {
                    account_id,
                    connection_revision,
                } => pl_protocol::AgentBinding::Acp(pl_protocol::AcpAgentConfig {
                    account_id,
                    connection_revision,
                }),
            },
            status: agent.status.current(),
            explicitly_closed: agent.explicitly_closed,
            created_at: agent.created_at,
            updated_at: agent.updated_at,
        })
    }
}

pub(super) fn migrate_v2_content(path: &Path, content: &str) -> Result<String> {
    let loaded = load_document(path, content)?;
    toml_schema::encode(&loaded.document, SCHEMA_KEY)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::toml_schema::DocumentMigrationFailed;

    fn v1_entry() -> CatalogEntryV1 {
        CatalogEntryV1 {
            id: "thread-a".into(),
            project_id: "project-a".into(),
            title: "Root".into(),
            mode: FrozenModeId("mode.simple".into()),
            workspace_mode: FrozenWorkspaceMode::Local,
            workspace_path: "/tmp/a".into(),
            parent_thread_id: None,
            root_thread_id: "thread-a".into(),
            role: "root".into(),
            agent_path: "thread-a".into(),
            status: FrozenThreadStatus::Idle,
            created_at: 10,
            updated_at: 20,
            archived: false,
        }
    }

    fn roundtrip_toml<T>(value: &T) -> T
    where
        T: Serialize + for<'de> Deserialize<'de>,
    {
        toml::from_str(&toml::to_string(value).expect("serialize DTO")).expect("deserialize DTO")
    }

    #[test]
    fn historical_dtos_roundtrip_through_real_serde() {
        let v1 = CatalogDocumentV1 {
            revision: 3,
            entries: vec![v1_entry()],
        };
        assert_eq!(roundtrip_toml(&v1), v1);

        let v2: CatalogDocumentV2 = v1.clone().migrate();
        assert_eq!(v2.entries[0].last_user_message_at, None);
        assert_eq!(roundtrip_toml(&v2), v2);

        let mut v2_with_time = v2.clone();
        v2_with_time.entries[0].last_user_message_at = Some(15);
        assert_eq!(roundtrip_toml(&v2_with_time), v2_with_time);

        let v3: CatalogDocumentV3 = v2_with_time.migrate();
        assert_eq!(v3.entries[0].delegation_mode, FrozenDelegationMode::Profile);
        assert_eq!(
            v3.entries[0].delegation_preference,
            FrozenDelegationPreference::Balanced
        );
        assert_eq!(v3.entries[0].frozen_model, None);
        assert_eq!(roundtrip_toml(&v3), v3);

        let mut v3_with_route = v3.clone();
        v3_with_route.entries[0].frozen_model = Some(FrozenModelRoute {
            account_id: "acc".into(),
            model_id: "model".into(),
            effort: Some("high".into()),
        });
        v3_with_route.entries[0].delegation_mode = FrozenDelegationMode::Automatic;
        v3_with_route.entries[0].status = FrozenThreadStatus::Closed;
        assert_eq!(roundtrip_toml(&v3_with_route), v3_with_route);

        let v4: CatalogV4 = v3_with_route.migrate();
        assert!(!v4.entries[0].explicitly_closed);
        assert_eq!(v4.entries[0].status, FrozenThreadStatus::Closed);
        assert_eq!(
            v4.entries[0].frozen_model,
            Some(FrozenModelRoute {
                account_id: "acc".into(),
                model_id: "model".into(),
                effort: Some("high".into()),
            })
        );
        assert_eq!(roundtrip_toml(&v4), v4);

        let current = CatalogDocument::try_from(v4.migrate().migrate()).expect("construct current");
        assert_eq!(current.sessions.len(), 1);
        assert_eq!(current.sessions[0].session_id, "thread-a");
        assert_eq!(
            current.sessions[0].delegation_mode,
            pl_protocol::DelegationMode::Automatic
        );
        assert_eq!(current.agents.len(), 1);
        assert!(!current.agents[0].explicitly_closed);
        assert_eq!(current.agents[0].status, ThreadStatus::Closed);
        assert_eq!(
            current.agents[0].frozen_model(),
            Some(pl_protocol::studio::NewThreadModelRoute {
                account_id: "acc".into(),
                model_id: "model".into(),
                effort: Some("high".into()),
            })
        );
    }

    #[test]
    fn v6_dto_roundtrips_session_and_agent_records() {
        let v6 = CatalogV6 {
            revision: 5,
            sessions: vec![CatalogSessionV6 {
                session_id: "thread-a".into(),
                root_agent_id: "thread-a".into(),
                workspace_id: "project-a".into(),
                title: "Root".into(),
                mode: FrozenModeId("mode.simple".into()),
                workspace_mode: FrozenWorkspaceMode::Local,
                delegation_mode: FrozenDelegationMode::Profile,
                delegation_preference: FrozenDelegationPreference::Balanced,
                workspace_path: "/tmp/a".into(),
                created_at: 1,
                updated_at: 2,
                last_user_message_at: Some(3),
                archived: false,
            }],
            agents: vec![
                CatalogAgentV6 {
                    agent_id: "thread-a".into(),
                    session_id: "thread-a".into(),
                    parent_agent_id: None,
                    thread_id: "thread-a".into(),
                    role: "root".into(),
                    title: None,
                    binding: FrozenAgentBinding::Native { route: None },
                    status: FrozenThreadStatus::Idle,
                    explicitly_closed: false,
                    created_at: 1,
                    updated_at: 2,
                },
                CatalogAgentV6 {
                    agent_id: "thread-b".into(),
                    session_id: "thread-a".into(),
                    parent_agent_id: Some("thread-a".into()),
                    thread_id: "thread-b".into(),
                    role: "executor".into(),
                    title: Some("任务".into()),
                    binding: FrozenAgentBinding::Native {
                        route: Some(FrozenModelRoute {
                            account_id: "acc".into(),
                            model_id: "model".into(),
                            effort: Some("high".into()),
                        }),
                    },
                    status: FrozenThreadStatus::Idle,
                    explicitly_closed: false,
                    created_at: 4,
                    updated_at: 5,
                },
            ],
        };
        assert_eq!(roundtrip_toml(&v6), v6);
    }

    #[test]
    fn v5_to_v6_groups_members_and_keeps_identities() {
        let root = CatalogEntryV5 {
            explicitly_closed: false,
            id: "thread-a".into(),
            workspace_id: "project-a".into(),
            title: "Root".into(),
            mode: FrozenModeId("mode.simple".into()),
            workspace_mode: FrozenWorkspaceMode::Worktree,
            delegation_mode: FrozenDelegationMode::Automatic,
            delegation_preference: FrozenDelegationPreference::Fast,
            frozen_model: None,
            workspace_path: "/wt/a".into(),
            parent_thread_id: None,
            root_thread_id: "thread-a".into(),
            role: "planner".into(),
            agent_path: "thread-a".into(),
            status: FrozenThreadStatus::Running,
            created_at: 10,
            updated_at: 20,
            last_user_message_at: Some(15),
            archived: false,
        };
        let child = CatalogEntryV5 {
            explicitly_closed: true,
            id: "thread-b".into(),
            title: "子任务".into(),
            mode: FrozenModeId("mode.simple".into()),
            parent_thread_id: Some("thread-a".into()),
            role: "executor".into(),
            frozen_model: Some(FrozenModelRoute {
                account_id: "acc".into(),
                model_id: "model".into(),
                effort: None,
            }),
            status: FrozenThreadStatus::Closing,
            created_at: 11,
            updated_at: 21,
            last_user_message_at: None,
            workspace_mode: FrozenWorkspaceMode::Worktree,
            delegation_mode: FrozenDelegationMode::Automatic,
            delegation_preference: FrozenDelegationPreference::Fast,
            workspace_path: "/wt/a".into(),
            workspace_id: "project-a".into(),
            root_thread_id: "thread-a".into(),
            agent_path: "thread-b".into(),
            archived: false,
        };
        let v6 = migrate_v5_to_v6(CatalogV5 {
            revision: 8,
            entries: vec![root, child],
        });
        assert_eq!(v6.revision, 8);
        assert_eq!(v6.sessions.len(), 1);
        assert_eq!(v6.sessions[0].session_id, "thread-a");
        assert_eq!(v6.sessions[0].root_agent_id, "thread-a");
        assert_eq!(v6.sessions[0].last_user_message_at, Some(15));
        assert_eq!(v6.agents.len(), 2);
        assert_eq!(v6.agents[0].agent_id, "thread-a");
        assert_eq!(v6.agents[0].thread_id, "thread-a");
        assert_eq!(v6.agents[0].parent_agent_id, None);
        assert_eq!(v6.agents[0].title, None);
        assert_eq!(v6.agents[1].agent_id, "thread-b");
        assert_eq!(v6.agents[1].parent_agent_id.as_deref(), Some("thread-a"));
        assert_eq!(v6.agents[1].title.as_deref(), Some("子任务"));
        assert!(v6.agents[1].explicitly_closed);
        assert_eq!(
            v6.agents[1].binding,
            FrozenAgentBinding::Native {
                route: Some(FrozenModelRoute {
                    account_id: "acc".into(),
                    model_id: "model".into(),
                    effort: None,
                })
            }
        );
    }

    #[test]
    fn old_versions_reject_unversioned_close_intent() {
        for version in [1_i64, 2, 3] {
            let raw = format!(
                "schemaVersion = {version}\nrevision = 1\n\n[[entries]]\nid = \"thread-a\"\nprojectId = \"project-a\"\ntitle = \"Root\"\nmode = \"mode.simple\"\nworkspaceMode = \"local\"\nworkspacePath = \"/tmp/a\"\nrootThreadId = \"thread-a\"\nrole = \"root\"\nagentPath = \"thread-a\"\nstatus = \"closed\"\ncreatedAt = 1\nupdatedAt = 1\narchived = false\nexplicitlyClosed = true\n"
            );
            let error = load_document(Path::new("catalog.toml"), &raw)
                .err()
                .expect("old close field");
            assert!(error.is::<DocumentMigrationFailed>());
        }
    }

    #[test]
    fn future_version_is_rejected_even_when_shape_matches_current() {
        let current = CatalogV4 {
            revision: 1,
            entries: vec![CatalogEntryV4 {
                explicitly_closed: false,
                id: "thread-a".into(),
                project_id: "project-a".into(),
                title: "Root".into(),
                mode: FrozenModeId("mode.simple".into()),
                workspace_mode: FrozenWorkspaceMode::Local,
                delegation_mode: FrozenDelegationMode::Profile,
                delegation_preference: FrozenDelegationPreference::Balanced,
                frozen_model: None,
                workspace_path: "/tmp/a".into(),
                parent_thread_id: None,
                root_thread_id: "thread-a".into(),
                role: "root".into(),
                agent_path: "thread-a".into(),
                status: FrozenThreadStatus::Idle,
                created_at: 1,
                updated_at: 1,
                last_user_message_at: None,
                archived: false,
            }],
        };
        let current: CatalogV6 = current.migrate().migrate();
        let encoded = toml_schema::encode(&current, SCHEMA_KEY).expect("current bytes");
        let future = encoded.replacen(
            &format!(
                "schemaVersion = {}",
                current_version().expect("catalog integer version")
            ),
            &format!(
                "schemaVersion = {}",
                current_version().expect("version") + 1
            ),
            1,
        );
        let error = load_document(Path::new("catalog.toml"), &future)
            .err()
            .expect("future version");
        assert!(error.is::<DocumentMigrationFailed>());
    }

    #[test]
    fn v1_to_current_keeps_revision_and_does_not_invent_close_or_frozen_model() {
        let raw = "schemaVersion = 1\nrevision = 9\n\n[[entries]]\nid = \"thread-a\"\nprojectId = \"project-a\"\ntitle = \"Root\"\nmode = \"mode.simple\"\nworkspaceMode = \"local\"\nworkspacePath = \"/tmp/a\"\nrootThreadId = \"thread-a\"\nrole = \"root\"\nagentPath = \"thread-a\"\nstatus = \"idle\"\ncreatedAt = 1\nupdatedAt = 2\narchived = false\n";
        let loaded = load_document(Path::new("catalog.toml"), raw).expect("v1");
        assert!(loaded.migrated);
        assert_eq!(loaded.source_version, 1);
        assert_eq!(loaded.document.revision, 9);
        assert_eq!(loaded.document.sessions.len(), 1);
        assert_eq!(loaded.document.agents.len(), 1);
        assert!(!loaded.document.agents[0].explicitly_closed);
        assert_eq!(
            loaded.document.sessions[0].delegation_mode,
            pl_protocol::DelegationMode::Profile
        );
        assert_eq!(
            loaded.document.sessions[0].delegation_preference,
            pl_protocol::DelegationPreference::Balanced
        );
        assert_eq!(loaded.document.sessions[0].last_user_message_at, None);
        assert_eq!(loaded.document.agents[0].frozen_model(), None);
    }
}
