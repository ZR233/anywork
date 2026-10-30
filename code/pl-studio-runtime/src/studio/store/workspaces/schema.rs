//! Workspaces TOML 的 V1→V2 官方迁移路径；V1 DTO 冻结为不含 kind 的旧 wire。

use std::path::Path;
use std::sync::OnceLock;

use anyhow::{Result, ensure};
use pl_protocol::studio::WorkspaceKind;
use serde::{Deserialize, Serialize};
use version_migrate::{IntoDomain, MigratesTo, Migrator, Versioned};

use super::{WorkspaceEntry, WorkspacesDocument};
use crate::toml_schema::{self, LoadedDocument};

pub(super) const ENTITY: &str = "workspaces";
pub(super) const SCHEMA_KEY: &str = "schemaVersion";

pub(super) fn current_version() -> Result<u32> {
    toml_schema::integer_version(WorkspacesV2::VERSION)
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
                .from::<WorkspacesV1>()
                .step::<WorkspacesV2>()
                .into::<WorkspacesV2>(),
        )
        .map_err(|error| toml_schema::chain_error(ENTITY, error))?;
    Ok(MIGRATOR.get_or_init(|| migrator))
}

pub(super) fn load_document(
    path: &Path,
    content: &str,
) -> Result<LoadedDocument<WorkspacesDocument>> {
    let loaded = toml_schema::load::<WorkspacesV1, WorkspacesV2>(
        path,
        content,
        migrator()?,
        ENTITY,
        SCHEMA_KEY,
    )?;
    let target = current_version()?;
    let document = WorkspacesDocument::from(loaded.document);
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

pub(super) fn validate(document: &WorkspacesDocument) -> Result<()> {
    ensure!(
        document.revision >= 1,
        "Studio workspaces revision is invalid"
    );
    let mut seen = std::collections::BTreeSet::new();
    for entry in &document.workspaces {
        ensure!(
            !entry.id.is_empty() && !entry.path.is_empty(),
            "Studio workspace identity is incomplete"
        );
        ensure!(
            seen.insert(entry.id.as_str()),
            "Studio workspaces contain a duplicate Project identity"
        );
    }
    let mut standalone_count = 0;
    for entry in &document.workspaces {
        if entry.kind == WorkspaceKind::Standalone {
            standalone_count += 1;
            ensure!(
                entry.ssh_alias.is_none() && !entry.closed,
                "Studio workspaces contain an invalid standalone owner"
            );
        }
    }
    ensure!(
        standalone_count <= 1,
        "Studio workspaces contain an invalid standalone owner"
    );
    Ok(())
}

impl IntoDomain<WorkspacesV2> for WorkspacesV2 {
    fn into_domain(self) -> WorkspacesV2 {
        self
    }
}

impl From<WorkspacesV2> for WorkspacesDocument {
    fn from(document: WorkspacesV2) -> Self {
        Self {
            revision: document.revision,
            workspaces: document
                .workspaces
                .into_iter()
                .map(|entry| WorkspaceEntry {
                    id: entry.id,
                    kind: match entry.kind {
                        FrozenWorkspaceKind::Project => WorkspaceKind::Project,
                        FrozenWorkspaceKind::Standalone => WorkspaceKind::Standalone,
                    },
                    name: entry.name,
                    path: entry.path,
                    ssh_alias: entry.ssh_alias,
                    created_at: entry.created_at,
                    updated_at: entry.updated_at,
                    last_opened_at: entry.last_opened_at,
                    closed: entry.closed,
                })
                .collect(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct WorkspacesV1 {
    revision: u64,
    workspaces: Vec<WorkspacesV1Entry>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct WorkspacesV1Entry {
    id: String,
    name: String,
    path: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    ssh_alias: Option<String>,
    created_at: i64,
    updated_at: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    last_opened_at: Option<i64>,
    #[serde(default)]
    closed: bool,
}

impl Versioned for WorkspacesV1 {
    const VERSION: &'static str = "1.0.0";
}

impl MigratesTo<WorkspacesV2> for WorkspacesV1 {
    fn migrate(self) -> WorkspacesV2 {
        WorkspacesV2 {
            revision: self.revision,
            workspaces: self
                .workspaces
                .into_iter()
                .map(|entry| WorkspacesV2Entry {
                    id: entry.id,
                    kind: FrozenWorkspaceKind::Project,
                    name: entry.name,
                    path: entry.path,
                    ssh_alias: entry.ssh_alias,
                    created_at: entry.created_at,
                    updated_at: entry.updated_at,
                    last_opened_at: entry.last_opened_at,
                    closed: entry.closed,
                })
                .collect(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Versioned)]
#[versioned(version = "2.0.0")]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct WorkspacesV2 {
    revision: u64,
    workspaces: Vec<WorkspacesV2Entry>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct WorkspacesV2Entry {
    id: String,
    kind: FrozenWorkspaceKind,
    name: String,
    path: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    ssh_alias: Option<String>,
    created_at: i64,
    updated_at: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    last_opened_at: Option<i64>,
    #[serde(default)]
    closed: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
enum FrozenWorkspaceKind {
    Project,
    Standalone,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::toml_schema::DocumentMigrationFailed;

    fn v1_sample() -> WorkspacesV1 {
        WorkspacesV1 {
            revision: 17,
            workspaces: vec![WorkspacesV1Entry {
                id: "old".into(),
                name: "项目".into(),
                path: "/projects/old".into(),
                ssh_alias: Some("host".into()),
                created_at: 3,
                updated_at: 8,
                last_opened_at: Some(7),
                closed: true,
            }],
        }
    }

    #[test]
    fn v1_and_v2_wire_roundtrip_and_migration_preserve_fields() {
        let old = v1_sample();
        let old_wire = toml::to_string(&old).expect("encode v1");
        assert_eq!(
            toml::from_str::<WorkspacesV1>(&old_wire).expect("decode v1"),
            old
        );
        let upgraded = old.clone().migrate();
        assert_eq!(upgraded.revision, 17);
        let row = &upgraded.workspaces[0];
        assert_eq!(row.kind, FrozenWorkspaceKind::Project);
        assert_eq!(row.id, old.workspaces[0].id);
        assert_eq!(row.name, old.workspaces[0].name);
        assert_eq!(row.path, old.workspaces[0].path);
        assert_eq!(row.ssh_alias, old.workspaces[0].ssh_alias);
        assert_eq!(row.created_at, old.workspaces[0].created_at);
        assert_eq!(row.updated_at, old.workspaces[0].updated_at);
        assert_eq!(row.last_opened_at, old.workspaces[0].last_opened_at);
        assert_eq!(row.closed, old.workspaces[0].closed);
        let wire = toml::to_string(&upgraded).expect("encode v2");
        assert_eq!(
            toml::from_str::<WorkspacesV2>(&wire).expect("decode v2"),
            upgraded
        );
    }

    #[test]
    fn v1_kind_is_rejected_and_future_version_does_not_decode_by_shape() {
        let path = Path::new("workspaces.toml");
        let v1_with_kind = "schemaVersion = 1\nrevision = 1\n\n[[workspaces]]\nid = \"x\"\nkind = \"project\"\nname = \"x\"\npath = \"/x\"\ncreatedAt = 1\nupdatedAt = 1\n";
        assert!(load_document(path, v1_with_kind).is_err());
        let current =
            toml_schema::encode(&WorkspacesDocument::from(v1_sample().migrate()), SCHEMA_KEY)
                .expect("encode current");
        let future = current.replacen("schemaVersion = 2", "schemaVersion = 3", 1);
        let error = load_document(path, &future).err().expect("future version");
        assert!(error.is::<DocumentMigrationFailed>());
    }

    #[test]
    fn v2_requires_known_kind_and_valid_standalone_owner() {
        let path = Path::new("workspaces.toml");
        let valid = "schemaVersion = 2\nrevision = 1\n\n[[workspaces]]\nid = \"owner\"\nkind = \"standalone\"\nname = \"anywork\"\npath = \"/documents/anywork\"\ncreatedAt = 1\nupdatedAt = 2\n";
        assert_eq!(
            load_document(path, valid)
                .expect("valid")
                .document
                .workspaces[0]
                .kind,
            WorkspaceKind::Standalone
        );
        for invalid in [
            valid.replace("kind = \"standalone\"\n", ""),
            valid.replace("\"standalone\"", "\"unknown\""),
            format!("{valid}closed = true\n"),
            format!("{valid}sshAlias = \"remote\"\n"),
            format!(
                "{valid}\n[[workspaces]]\nid = \"other\"\nkind = \"standalone\"\nname = \"other\"\npath = \"/other\"\ncreatedAt = 1\nupdatedAt = 2\n"
            ),
        ] {
            assert!(load_document(path, &invalid).is_err(), "{invalid}");
        }
    }
}
