//! Catalog TOML 的冻结历史 DTO 与 1→2→3→4 类型迁移链。
//!
//! 历史条目的嵌套 enum / 冻结路由使用本模块的 wire 形状，不借用会演进的
//! `pl_protocol` 类型。库链输出最新冻结文件 DTO [`CatalogV4`]；owner 再
//! `TryFrom` 为运行期 [`super::CatalogDocument`]。

use std::path::Path;
use std::sync::OnceLock;

use anyhow::{Result, bail, ensure};
use pl_protocol::{ThreadModeId, ThreadStatus, ThreadWorkspaceMode};
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use version_migrate::{IntoDomain, MigratesTo, Migrator, Versioned};

use super::{CatalogDocument, CatalogEntry};
use crate::toml_schema::{self, LoadedDocument};

pub(super) const ENTITY: &str = "catalog";
pub(super) const SCHEMA_KEY: &str = "schemaVersion";

pub(super) fn current_version() -> Result<u32> {
    toml_schema::integer_version(CatalogV5::VERSION)
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
                .into::<CatalogV5>(),
        )
        .map_err(|error| toml_schema::chain_error(ENTITY, error))?;
    Ok(MIGRATOR.get_or_init(|| migrator))
}

pub(super) fn load_document(path: &Path, content: &str) -> Result<LoadedDocument<CatalogDocument>> {
    let loaded = toml_schema::load::<CatalogDocumentV1, CatalogV5>(
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
    let mut seen = std::collections::BTreeSet::new();
    for entry in &document.entries {
        ensure!(
            seen.insert(entry.id.as_str()),
            "Studio catalog has a duplicate Thread identity"
        );
        ensure!(
            !entry.id.is_empty() && entry.agent_path == entry.id,
            "Studio catalog entry identity is inconsistent"
        );
        ensure!(
            entry.workspace_mode != ThreadWorkspaceMode::Worktree
                || !entry.workspace_path.is_empty(),
            "Studio worktree catalog entry has no workspace address"
        );
        if entry.parent_thread_id.is_none() {
            ensure!(
                entry.root_thread_id == entry.id,
                "Studio root catalog entry is not its own root"
            );
        }
    }
    if document.entries.is_empty() && document.revision > 1 {
        bail!("Studio catalog lost all entries without a fresh install");
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
impl IntoDomain<CatalogV5> for CatalogV5 {
    fn into_domain(self) -> CatalogV5 {
        self
    }
}

impl TryFrom<CatalogV5> for CatalogDocument {
    type Error = anyhow::Error;

    fn try_from(document: CatalogV5) -> Result<Self> {
        Ok(Self {
            revision: document.revision,
            entries: document
                .entries
                .into_iter()
                .map(CatalogEntry::try_from)
                .collect::<Result<Vec<_>>>()?,
        })
    }
}

impl TryFrom<CatalogEntryV5> for CatalogEntry {
    type Error = anyhow::Error;

    fn try_from(entry: CatalogEntryV5) -> Result<Self> {
        Ok(Self {
            explicitly_closed: entry.explicitly_closed,
            id: entry.id,
            workspace_id: entry.workspace_id,
            title: entry.title,
            mode: ThreadModeId::new(entry.mode.0)?,
            workspace_mode: entry.workspace_mode.current(),
            delegation_mode: entry.delegation_mode.current(),
            delegation_preference: entry.delegation_preference.current(),
            frozen_model: entry.frozen_model.map(FrozenModelRoute::current),
            workspace_path: entry.workspace_path,
            parent_thread_id: entry.parent_thread_id,
            root_thread_id: entry.root_thread_id,
            role: entry.role,
            agent_path: entry.agent_path,
            status: entry.status.current(),
            created_at: entry.created_at,
            updated_at: entry.updated_at,
            last_user_message_at: entry.last_user_message_at,
            archived: entry.archived,
        })
    }
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

        let current = CatalogDocument::try_from(v4.migrate()).expect("construct current");
        assert!(!current.entries[0].explicitly_closed);
        assert_eq!(current.entries[0].status, ThreadStatus::Closed);
        assert_eq!(
            current.entries[0].frozen_model,
            Some(pl_protocol::studio::NewThreadModelRoute {
                account_id: "acc".into(),
                model_id: "model".into(),
                effort: Some("high".into()),
            })
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
        let current: CatalogV5 = current.migrate();
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
        assert!(!loaded.document.entries[0].explicitly_closed);
        assert_eq!(
            loaded.document.entries[0].delegation_mode,
            pl_protocol::DelegationMode::Profile
        );
        assert_eq!(
            loaded.document.entries[0].delegation_preference,
            pl_protocol::DelegationPreference::Balanced
        );
        assert_eq!(loaded.document.entries[0].last_user_message_at, None);
        assert_eq!(loaded.document.entries[0].frozen_model, None);
    }
}

pub(super) fn migrate_v2_content(path: &Path, content: &str) -> Result<String> {
    let loaded = load_document(path, content)?;
    toml_schema::encode(&loaded.document, SCHEMA_KEY)
}
