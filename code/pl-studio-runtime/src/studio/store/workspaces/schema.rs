//! Workspaces TOML 的独立 V1 路径。正常运行只消费当前 [`super::WorkspacesDocument`]。

use std::path::Path;
use std::sync::OnceLock;

use anyhow::{Result, ensure};
use version_migrate::{IntoDomain, Migrator, Versioned};

use super::WorkspacesDocument;
use crate::toml_schema::{self, LoadedDocument};

pub(super) const ENTITY: &str = "workspaces";
pub(super) const SCHEMA_KEY: &str = "schemaVersion";

pub(super) fn current_version() -> Result<u32> {
    toml_schema::integer_version(WorkspacesDocument::VERSION)
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
                .from::<WorkspacesDocument>()
                .into::<WorkspacesDocument>(),
        )
        .map_err(|error| toml_schema::chain_error(ENTITY, error))?;
    Ok(MIGRATOR.get_or_init(|| migrator))
}

pub(super) fn load_document(
    path: &Path,
    content: &str,
) -> Result<LoadedDocument<WorkspacesDocument>> {
    let loaded = toml_schema::load::<WorkspacesDocument, WorkspacesDocument>(
        path,
        content,
        migrator()?,
        ENTITY,
        SCHEMA_KEY,
    )?;
    let target = current_version()?;
    validate(&loaded.document).map_err(|error| {
        toml_schema::migration_error(
            path,
            ENTITY,
            Some(loaded.source_version),
            target,
            "validate",
            error,
        )
    })?;
    Ok(loaded)
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
    Ok(())
}

impl IntoDomain<WorkspacesDocument> for WorkspacesDocument {
    fn into_domain(self) -> WorkspacesDocument {
        self
    }
}

#[cfg(test)]
mod tests {
    use super::super::WorkspaceEntry;
    use super::*;
    use crate::toml_schema::DocumentMigrationFailed;

    fn current_entry() -> WorkspaceEntry {
        WorkspaceEntry {
            id: "project-a".into(),
            name: "A".into(),
            path: "/tmp/a".into(),
            ssh_alias: None,
            created_at: 1,
            updated_at: 2,
            last_opened_at: Some(3),
            closed: false,
        }
    }

    #[test]
    fn current_dto_roundtrips_through_real_serde() {
        let document = WorkspacesDocument {
            revision: 2,
            workspaces: vec![current_entry()],
        };
        let encoded = toml::to_string(&document).expect("serialize");
        let decoded: WorkspacesDocument = toml::from_str(&encoded).expect("deserialize");
        assert_eq!(decoded.revision, 2);
        assert_eq!(decoded.workspaces, document.workspaces);
    }

    #[test]
    fn future_version_is_rejected_even_when_shape_matches_current() {
        let encoded = toml_schema::encode(
            &WorkspacesDocument {
                revision: 1,
                workspaces: vec![current_entry()],
            },
            SCHEMA_KEY,
        )
        .expect("encode");
        let future = encoded.replacen("schemaVersion = 1", "schemaVersion = 2", 1);
        let error = load_document(Path::new("workspaces.toml"), &future)
            .err()
            .expect("future version");
        assert!(error.is::<DocumentMigrationFailed>());
    }

    #[test]
    fn validation_failure_is_wrapped_as_migration() {
        let raw = "schemaVersion = 1\nrevision = 0\nworkspaces = []\n";
        let error = load_document(Path::new("workspaces.toml"), raw)
            .err()
            .expect("invalid revision");
        assert!(error.is::<DocumentMigrationFailed>());
    }
}
