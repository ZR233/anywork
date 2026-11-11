//! Catalog TOML 的冻结历史 DTO 与 1→2→3→4→5→6→7 类型迁移链。
//!
//! 历史条目的嵌套 enum / 冻结路由使用本模块的 wire 形状，不借用会演进的
//! `pl_protocol` 类型。库链输出最新冻结文件 DTO [`CatalogV7`]；owner 再
//! `TryFrom` 为运行期 [`super::CatalogDocument`]。V5→V6 把逐 Thread 复合身份
//! 重组为会话/成员两级记录，缺失根、跨会话 parent 与循环都给出明确诊断。

use std::path::Path;
use std::sync::OnceLock;

use anyhow::{Result, ensure};
use pl_protocol::{ThreadModeId, ThreadStatus, ThreadWorkspaceMode};
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use version_migrate::{IntoDomain, MigratesTo, Migrator, Versioned};

use super::CatalogDocument;
use crate::studio::records::{AgentDirectoryRecord, SessionDirectoryRecord};
use crate::toml_schema::{self, LoadedDocument};

pub(super) const ENTITY: &str = "catalog";
pub(super) const SCHEMA_KEY: &str = "schemaVersion";

pub(super) fn current_version() -> Result<u32> {
    toml_schema::integer_version(CatalogV7::VERSION)
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
                .step::<CatalogV7>()
                .into::<CatalogV7>(),
        )
        .map_err(|error| toml_schema::chain_error(ENTITY, error))?;
    Ok(MIGRATOR.get_or_init(|| migrator))
}

pub(super) fn load_document(path: &Path, content: &str) -> Result<LoadedDocument<CatalogDocument>> {
    let target = current_version()?;
    let value = toml_schema::parse(path, content, ENTITY, target)?;
    if value.get(SCHEMA_KEY).and_then(toml::Value::as_integer) == Some(6) {
        let mut legacy = value.clone();
        legacy.remove(SCHEMA_KEY);
        let legacy: CatalogV6 = legacy.try_into().map_err(|error| {
            toml_schema::migration_error(path, ENTITY, Some(6), target, "decode", error)
        })?;
        if legacy
            .agents
            .iter()
            .any(|agent| matches!(agent.binding, FrozenAgentBinding::Acp { .. }))
        {
            return Err(toml_schema::migration_error(
                path,
                ENTITY,
                Some(6),
                target,
                "validate",
                anyhow::anyhow!(
                    "legacy ACP member has no real remote session reference; original catalog must be retained"
                ),
            ));
        }
    }
    let loaded = toml_schema::load_table::<CatalogDocumentV1, CatalogV7>(
        path,
        value,
        migrator()?,
        ENTITY,
        SCHEMA_KEY,
    )?;
    if loaded.source_version == 5 {
        validate_v5_inheritance(path, content).map_err(|error| {
            toml_schema::migration_error(path, ENTITY, Some(5), target, "validate", error)
        })?;
    }
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

/// V6 drops inherited copies. Old root-only mode changes left legitimate stale child modes;
/// the root owns the session mode, while the remaining ownership facts must still agree.
fn validate_v5_inheritance(path: &Path, content: &str) -> Result<()> {
    let mut value = toml_schema::parse(path, content, ENTITY, 6)?;
    value.remove(SCHEMA_KEY);
    let document: CatalogV5 = value.try_into()?;
    for child in &document.entries {
        if child.parent_thread_id.is_none() {
            continue;
        }
        let Some(root) = document
            .entries
            .iter()
            .find(|root| root.id == child.root_thread_id && root.parent_thread_id.is_none())
        else {
            // The topology validator supplies the missing-root diagnostic.
            continue;
        };
        ensure!(
            child.workspace_id == root.workspace_id
                && child.workspace_mode == root.workspace_mode
                && child.workspace_path == root.workspace_path
                && child.delegation_mode == root.delegation_mode
                && child.delegation_preference == root.delegation_preference
                && child.archived == root.archived,
            "Studio catalog child {} has conflicting inherited session facts",
            child.id
        );
    }
    Ok(())
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
            !session.session_id.trim().is_empty() && !session.root_agent_id.trim().is_empty(),
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
            !agent.agent_id.trim().is_empty() && !agent.thread_id.trim().is_empty(),
            "Studio catalog member identity is incomplete"
        );
        if let pl_protocol::session::AgentBackend::Native { config: native, .. } = &agent.backend {
            ensure!(
                native.system_instructions.is_none(),
                "Studio catalog cannot contain Native instruction bodies"
            );
        }
        if let pl_protocol::session::AgentBackend::Acp { reference } = &agent.backend {
            ensure!(
                !reference.account_id.trim().is_empty()
                    && !reference.acp_session_id.trim().is_empty()
                    && !reference.cwd.trim().is_empty(),
                "Studio catalog ACP reference is incomplete"
            );
        }
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
    for session in &document.sessions {
        let root = document
            .agents
            .iter()
            .find(|agent| agent.agent_id == session.root_agent_id);
        if let Some(root) = root {
            ensure!(
                session.native_mode.is_some()
                    == matches!(
                        root.backend,
                        pl_protocol::session::AgentBackend::Native { .. }
                    ),
                "Studio catalog root Native mode does not match its backend"
            );
        }
        ensure!(
            document.agents.iter().any(|agent| {
                agent.agent_id == session.root_agent_id
                    && agent.session_id == session.session_id
                    && agent.parent_agent_id.is_none()
            }),
            "Studio catalog session {} has no root member",
            session.session_id
        );
        ensure!(
            document
                .agents
                .iter()
                .filter(|agent| {
                    agent.session_id == session.session_id && agent.parent_agent_id.is_none()
                })
                .count()
                == 1,
            "Studio catalog session {} has multiple root members",
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
#[serde(tag = "kind", rename_all = "camelCase", deny_unknown_fields)]
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

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Versioned)]
#[versioned(version = "7.0.0")]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct CatalogV7 {
    revision: u64,
    sessions: Vec<CatalogSessionV7>,
    agents: Vec<CatalogAgentV7>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CatalogSessionV7 {
    session_id: String,
    root_agent_id: String,
    workspace_id: String,
    title: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    native_mode: Option<FrozenModeId>,
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

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CatalogAgentV7 {
    agent_id: String,
    session_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    parent_agent_id: Option<String>,
    thread_id: String,
    role: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    title: Option<String>,
    backend: FrozenBackendV7,
    explicitly_closed: bool,
    created_at: i64,
    updated_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase", deny_unknown_fields)]
enum FrozenBackendV7 {
    Native {
        config: FrozenNativeConfigV7,
        status: FrozenThreadStatus,
    },
    Acp {
        reference: FrozenAcpReferenceV7,
    },
    // The migration library's step is infallible. Carry the original invalid fact
    // to the fallible owner conversion; never serialize or admit it as current wire.
    #[serde(skip)]
    LegacyAcpWithoutReference {
        account_id: String,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct FrozenNativeConfigV7 {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    route: Option<FrozenModelRoute>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct FrozenAcpReferenceV7 {
    account_id: String,
    acp_session_id: String,
    cwd: String,
}

impl MigratesTo<CatalogV7> for CatalogV6 {
    fn migrate(self) -> CatalogV7 {
        let sessions = self
            .sessions
            .into_iter()
            .map(|session| {
                let native = self.agents.iter().any(|agent| {
                    agent.agent_id == session.root_agent_id
                        && matches!(agent.binding, FrozenAgentBinding::Native { .. })
                });
                CatalogSessionV7 {
                    session_id: session.session_id,
                    root_agent_id: session.root_agent_id,
                    workspace_id: session.workspace_id,
                    title: session.title,
                    native_mode: native.then_some(session.mode),
                    workspace_mode: session.workspace_mode,
                    delegation_mode: session.delegation_mode,
                    delegation_preference: session.delegation_preference,
                    workspace_path: session.workspace_path,
                    created_at: session.created_at,
                    updated_at: session.updated_at,
                    last_user_message_at: session.last_user_message_at,
                    archived: session.archived,
                }
            })
            .collect();
        CatalogV7 {
            revision: self.revision,
            sessions,
            agents: self
                .agents
                .into_iter()
                .map(|agent| CatalogAgentV7 {
                    agent_id: agent.agent_id,
                    session_id: agent.session_id,
                    parent_agent_id: agent.parent_agent_id,
                    thread_id: agent.thread_id,
                    role: agent.role,
                    title: agent.title,
                    backend: match agent.binding {
                        FrozenAgentBinding::Native { route } => FrozenBackendV7::Native {
                            config: FrozenNativeConfigV7 { route },
                            status: agent.status,
                        },
                        FrozenAgentBinding::Acp { account_id, .. } => {
                            FrozenBackendV7::LegacyAcpWithoutReference { account_id }
                        }
                    },
                    explicitly_closed: agent.explicitly_closed,
                    created_at: agent.created_at,
                    updated_at: agent.updated_at,
                })
                .collect(),
        }
    }
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

impl IntoDomain<CatalogV7> for CatalogV7 {
    fn into_domain(self) -> CatalogV7 {
        self
    }
}

impl TryFrom<CatalogV7> for CatalogDocument {
    type Error = anyhow::Error;

    fn try_from(document: CatalogV7) -> Result<Self> {
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

impl TryFrom<CatalogSessionV7> for SessionDirectoryRecord {
    type Error = anyhow::Error;

    fn try_from(session: CatalogSessionV7) -> Result<Self> {
        Ok(Self {
            session_id: session.session_id,
            root_agent_id: session.root_agent_id,
            workspace_id: session.workspace_id,
            title: session.title,
            native_mode: session
                .native_mode
                .map(|mode| ThreadModeId::new(mode.0))
                .transpose()?,
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

impl TryFrom<CatalogAgentV7> for AgentDirectoryRecord {
    type Error = anyhow::Error;

    fn try_from(agent: CatalogAgentV7) -> Result<Self> {
        Ok(Self {
            agent_id: agent.agent_id,
            session_id: agent.session_id,
            parent_agent_id: agent.parent_agent_id,
            thread_id: agent.thread_id,
            role: agent.role,
            title: agent.title,
            backend: match agent.backend {
                FrozenBackendV7::Native { config, status } => {
                    pl_protocol::session::AgentBackend::Native {
                        config: pl_protocol::NativeAgentConfig {
                            route: config.route.map(FrozenModelRoute::current),
                            system_instructions: None,
                        },
                        status: status.current(),
                    }
                }
                FrozenBackendV7::Acp { reference } => {
                    ensure!(
                        !reference.account_id.trim().is_empty()
                            && !reference.acp_session_id.trim().is_empty()
                            && !reference.cwd.trim().is_empty(),
                        "Studio catalog ACP reference is incomplete"
                    );
                    pl_protocol::session::AgentBackend::Acp {
                        reference: pl_protocol::session::AcpSessionReference {
                            account_id: reference.account_id,
                            acp_session_id: reference.acp_session_id,
                            cwd: reference.cwd,
                        },
                    }
                }
                FrozenBackendV7::LegacyAcpWithoutReference { .. } => anyhow::bail!(
                    "Studio catalog legacy ACP member has no real remote session reference; original catalog must be retained"
                ),
            },
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

        let current =
            CatalogDocument::try_from(v4.migrate().migrate().migrate()).expect("construct current");
        assert_eq!(current.sessions.len(), 1);
        assert_eq!(current.sessions[0].session_id, "thread-a");
        assert_eq!(
            current.sessions[0].delegation_mode,
            pl_protocol::DelegationMode::Automatic
        );
        assert_eq!(current.agents.len(), 1);
        assert!(!current.agents[0].explicitly_closed);
        assert_eq!(
            current.agents[0].native_status(),
            Some(ThreadStatus::Closed)
        );
        assert_eq!(
            current.agents[0].frozen_model(),
            Some(pl_protocol::studio::NewThreadModelRoute {
                account_id: "acc".into(),
                model_id: "model".into(),
                effort: Some("high".into()),
            })
        );
    }

    fn v6_document() -> CatalogV6 {
        CatalogV6 {
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
        }
    }

    #[test]
    fn v6_dto_roundtrips_session_and_agent_records() {
        let v6 = v6_document();
        assert_eq!(roundtrip_toml(&v6), v6);
    }

    #[test]
    fn v6_to_v7_keeps_all_native_directory_facts() {
        let legacy = v6_document();
        let migrated = legacy.clone().migrate();
        assert_eq!(roundtrip_toml(&migrated), migrated);
        let current = CatalogDocument::try_from(migrated).expect("current V7");
        validate(&current).expect("valid topology");
        let session = &current.sessions[0];
        assert_eq!(session.session_id, legacy.sessions[0].session_id);
        assert_eq!(session.root_agent_id, legacy.sessions[0].root_agent_id);
        assert_eq!(session.native_mode, Some(ThreadModeId::simple()));
        assert_eq!(session.last_user_message_at, Some(3));
        assert_eq!(session.created_at, legacy.sessions[0].created_at);
        assert_eq!(session.updated_at, legacy.sessions[0].updated_at);
        assert_eq!(session.workspace_path, legacy.sessions[0].workspace_path);
        for (agent, old) in current.agents.iter().zip(&legacy.agents) {
            assert_eq!(agent.agent_id, old.agent_id);
            assert_eq!(agent.session_id, old.session_id);
            assert_eq!(agent.parent_agent_id, old.parent_agent_id);
            assert_eq!(agent.thread_id, old.thread_id);
            assert_eq!(agent.title, old.title);
            assert_eq!(agent.explicitly_closed, old.explicitly_closed);
            assert_eq!(agent.native_status(), Some(old.status.current()));
        }
        let root = crate::studio::records::thread_projection(session, &current.agents[0], |id| {
            current
                .agents
                .iter()
                .find(|agent| agent.agent_id == id)
                .map(|agent| agent.thread_id.clone())
        })
        .expect("Native root projection");
        let child = crate::studio::records::thread_projection(session, &current.agents[1], |id| {
            current
                .agents
                .iter()
                .find(|agent| agent.agent_id == id)
                .map(|agent| agent.thread_id.clone())
        })
        .expect("Native child projection");
        assert_eq!(root.mode, Some(ThreadModeId::simple()));
        assert_eq!(child.mode, None);
    }

    #[test]
    fn v7_acp_reference_roundtrips_without_native_facts() {
        let mut v7 = v6_document().migrate();
        v7.agents.truncate(1);
        v7.sessions[0].native_mode = None;
        v7.agents[0].backend = FrozenBackendV7::Acp {
            reference: FrozenAcpReferenceV7 {
                account_id: "generic".into(),
                acp_session_id: "remote-session".into(),
                cwd: "/project".into(),
            },
        };
        assert_eq!(roundtrip_toml(&v7), v7);
        let current = CatalogDocument::try_from(v7).expect("ACP reference");
        validate(&current).expect("valid ACP root");
        let bytes = toml_schema::encode(&current, SCHEMA_KEY).expect("encode V7");
        assert!(!bytes.contains("nativeMode"));
        assert!(!bytes.contains("connectionRevision"));
        assert!(!bytes.contains("status"));
        assert!(
            crate::studio::records::thread_projection(
                &current.sessions[0],
                &current.agents[0],
                |_| None
            )
            .is_err()
        );
    }

    #[test]
    fn native_projection_resolves_real_thread_addresses_and_requires_root_mode() {
        let mut document = CatalogDocument::try_from(v6_document().migrate()).expect("V7");
        document.sessions[0].session_id = "product-session".into();
        document.sessions[0].root_agent_id = "root-agent".into();
        document.agents[0].agent_id = "root-agent".into();
        document.agents[0].session_id = "product-session".into();
        document.agents[0].thread_id = "root-thread".into();
        document.agents[1].session_id = "product-session".into();
        document.agents[1].parent_agent_id = Some("root-agent".into());
        validate(&document).expect("separate identities are valid");
        let resolve = |id: &str| {
            document
                .agents
                .iter()
                .find(|agent| agent.agent_id == id)
                .map(|agent| agent.thread_id.clone())
        };
        let child = crate::studio::records::thread_projection(
            &document.sessions[0],
            &document.agents[1],
            resolve,
        )
        .expect("Native child");
        assert_eq!(child.root_thread_id, "root-thread");
        assert_eq!(child.parent_thread_id.as_deref(), Some("root-thread"));
        assert_eq!(child.mode, None);
        document.sessions[0].native_mode = None;
        assert!(validate(&document).is_err());
        assert!(
            crate::studio::records::thread_projection(
                &document.sessions[0],
                &document.agents[0],
                |_| Some("root-thread".into()),
            )
            .is_err()
        );
    }

    #[tokio::test]
    async fn legacy_acp_without_remote_reference_retains_original_file() {
        let mut legacy = v6_document();
        legacy.agents[0].binding = FrozenAgentBinding::Acp {
            account_id: "generic".into(),
            connection_revision: 8,
        };
        let bytes = toml_schema::encode(&legacy, SCHEMA_KEY).expect("legacy bytes");
        let dir = tempfile::tempdir().expect("temp");
        let path = dir.path().join("catalog.toml");
        tokio::fs::write(&path, &bytes).await.expect("write legacy");
        assert!(
            super::super::CatalogStore::load(path.clone())
                .await
                .is_err()
        );
        assert_eq!(
            tokio::fs::read_to_string(path)
                .await
                .expect("original remains"),
            bytes
        );
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
        let current: CatalogV7 = current.migrate().migrate().migrate();
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
