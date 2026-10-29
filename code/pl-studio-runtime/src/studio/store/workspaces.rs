//! `workspaces.toml`: Project/Workspace 目录事实的 canonical TOML 存储。
//!
//! 旧 `projects` 表属于旧会话版本，v2 不导入；普通目录读取只访问本文件。
//! 写路径与 catalog 一样使用单锁读取-修改-原子替换，`revision` 单调递增并保证同内容幂等。

mod schema;

use std::path::PathBuf;
use std::sync::{Arc, Mutex, PoisonError};

use anyhow::{Result, bail, ensure};
use pl_protocol::studio::WorkspaceKind;
use version_migrate::Versioned;

use crate::studio::records::ProjectRecord;
use crate::studio::store::StudioStore;
use crate::studio::store::directory::DirectoryDelta;
use crate::studio::toml_store::{self, RevisionedDocument};

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::studio) struct WorkspaceEntry {
    pub(in crate::studio) id: String,
    pub(in crate::studio) kind: WorkspaceKind,
    pub(in crate::studio) name: String,
    pub(in crate::studio) path: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(in crate::studio) ssh_alias: Option<String>,
    pub(in crate::studio) created_at: i64,
    pub(in crate::studio) updated_at: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(in crate::studio) last_opened_at: Option<i64>,
    #[serde(default)]
    pub(in crate::studio) closed: bool,
}

impl WorkspaceEntry {
    pub(in crate::studio) fn project(&self) -> ProjectRecord {
        ProjectRecord {
            id: self.id.clone(),
            kind: self.kind,
            name: self.name.clone(),
            path: self.path.clone(),
            ssh_alias: self.ssh_alias.clone(),
            updated_at: self.updated_at,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct WorkspacesDocument {
    revision: u64,
    workspaces: Vec<WorkspaceEntry>,
}

impl Versioned for WorkspacesDocument {
    const VERSION: &'static str = <schema::WorkspacesV2 as Versioned>::VERSION;
}

impl RevisionedDocument for WorkspacesDocument {
    const KIND: &'static str = "Studio workspaces";
    const VERSION_KEY: &'static str = schema::SCHEMA_KEY;

    fn revision_mut(&mut self) -> &mut u64 {
        &mut self.revision
    }
}

#[derive(Clone)]
pub(in crate::studio) struct WorkspaceStore {
    path: PathBuf,
    inner: Arc<Mutex<WorkspacesDocument>>,
}

impl WorkspaceStore {
    pub(in crate::studio) async fn load(path: PathBuf) -> Result<Self> {
        let document = match tokio::fs::read_to_string(&path).await {
            Ok(content) => {
                let loaded = schema::load_document(&path, &content)?;
                if loaded.migrated {
                    let contents =
                        crate::toml_schema::encode(&loaded.document, schema::SCHEMA_KEY)?;
                    let target = path.clone();
                    tokio::task::spawn_blocking(move || {
                        pl_tool::workspace::write_file_atomically(&target, contents.as_bytes())
                    })
                    .await??;
                }
                loaded.document
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => WorkspacesDocument {
                revision: 1,
                workspaces: Vec::new(),
            },
            Err(error) => return Err(error.into()),
        };
        Ok(Self {
            path,
            inner: Arc::new(Mutex::new(document)),
        })
    }

    pub(in crate::studio) fn entries(&self) -> Vec<WorkspaceEntry> {
        self.lock().workspaces.clone()
    }

    pub(in crate::studio) fn get(&self, id: &str) -> Option<WorkspaceEntry> {
        self.lock()
            .workspaces
            .iter()
            .find(|entry| entry.id == id)
            .cloned()
    }

    pub(in crate::studio) fn find_by_path(
        &self,
        path: &str,
        ssh_alias: Option<&str>,
    ) -> Option<WorkspaceEntry> {
        self.lock()
            .workspaces
            .iter()
            .find(|entry| entry.path == path && entry.ssh_alias.as_deref() == ssh_alias)
            .cloned()
    }

    pub(in crate::studio) async fn apply_delta(&self, delta: &DirectoryDelta) -> Result<()> {
        if delta.project_upserts.is_empty() && delta.project_removals.is_empty() {
            return Ok(());
        }
        let upserts = delta
            .project_upserts
            .iter()
            .map(|record| WorkspaceEntry {
                id: record.id.clone(),
                kind: record.kind,
                name: record.name.clone(),
                path: record.path.clone(),
                ssh_alias: record.ssh_alias.clone(),
                created_at: record.created_at,
                updated_at: record.updated_at,
                last_opened_at: record.last_opened_at,
                closed: record.closed,
            })
            .collect::<Vec<_>>();
        let removals = delta
            .project_removals
            .iter()
            .map(|removal| (removal.project_id.clone(), removal.closed_at))
            .collect::<Vec<_>>();
        self.mutate(move |document| {
            let mut changed = false;
            for entry in upserts {
                if let Some(existing) = document
                    .workspaces
                    .iter_mut()
                    .find(|existing| existing.id == entry.id)
                {
                    ensure_identity_stable(existing, &entry)?;
                    let next = WorkspaceEntry {
                        created_at: existing.created_at,
                        ..entry
                    };
                    if *existing != next {
                        *existing = next;
                        changed = true;
                    }
                } else {
                    document.workspaces.push(entry);
                    changed = true;
                }
            }
            for (id, closed_at) in removals {
                if let Some(existing) = document.workspaces.iter_mut().find(|entry| entry.id == id)
                {
                    ensure!(
                        existing.kind != WorkspaceKind::Standalone,
                        "the standalone workspace cannot be archived"
                    );
                    if !existing.closed || existing.updated_at < closed_at {
                        existing.closed = true;
                        existing.updated_at = existing.updated_at.max(closed_at);
                        changed = true;
                    }
                }
            }
            schema::validate(document)?;
            Ok(changed)
        })
        .await
    }

    /// 把当前内存文档写入 canonical 文件；文件已存在时不覆盖。
    /// 只有 migration 边界使用，用来补齐旧发布遗留的空缺文档；正常运行写入都经 apply_delta。
    pub(in crate::studio) async fn persist_if_absent(&self) -> Result<()> {
        let inner = self.inner.clone();
        let path = self.path.clone();
        tokio::task::spawn_blocking(move || toml_store::persist_if_absent(&inner, &path)).await?
    }

    async fn mutate(
        &self,
        change: impl FnOnce(&mut WorkspacesDocument) -> Result<bool> + Send + 'static,
    ) -> Result<()> {
        let inner = self.inner.clone();
        let path = self.path.clone();
        tokio::task::spawn_blocking(move || toml_store::mutate_document(&inner, &path, change))
            .await?
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, WorkspacesDocument> {
        self.inner.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

impl StudioStore {
    pub(in crate::studio) fn workspaces(&self) -> &WorkspaceStore {
        &self.workspaces
    }
}

fn ensure_identity_stable(existing: &WorkspaceEntry, next: &WorkspaceEntry) -> Result<()> {
    if existing.path != next.path
        || existing.ssh_alias != next.ssh_alias
        || existing.kind != next.kind
    {
        bail!(
            "Project {} directory identity changed: persisted path {}, delta path {}",
            existing.id,
            existing.path,
            next.path
        );
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::studio::store::directory::{ProjectDirectoryRecord, ProjectRemoval};
    use crate::toml_schema::{self, DocumentMigrationFailed};

    fn current_entry() -> WorkspaceEntry {
        WorkspaceEntry {
            id: "project-a".into(),
            kind: WorkspaceKind::Project,
            name: "A".into(),
            path: "/tmp/a".into(),
            ssh_alias: Some("host".into()),
            created_at: 1,
            updated_at: 2,
            last_opened_at: Some(3),
            closed: false,
        }
    }

    fn project_upsert(id: &str, kind: WorkspaceKind) -> ProjectDirectoryRecord {
        ProjectDirectoryRecord {
            id: id.into(),
            kind,
            name: id.into(),
            path: format!("/workspaces/{id}"),
            ssh_alias: None,
            created_at: 1,
            updated_at: 2,
            last_opened_at: None,
            closed: false,
        }
    }

    fn empty_store_bytes(revision: u64) -> String {
        toml_schema::encode(
            &WorkspacesDocument {
                revision,
                workspaces: Vec::new(),
            },
            schema::SCHEMA_KEY,
        )
        .expect("encode empty workspaces")
    }

    #[tokio::test]
    async fn current_bytes_are_not_rewritten() {
        let dir = tempfile::tempdir().expect("temp");
        let path = dir.path().join("workspaces.toml");
        let document = WorkspacesDocument {
            revision: 5,
            workspaces: vec![current_entry()],
        };
        let encoded = toml_schema::encode(&document, schema::SCHEMA_KEY).expect("encode");
        tokio::fs::write(&path, &encoded).await.expect("write");
        let store = WorkspaceStore::load(path.clone())
            .await
            .expect("load current");
        assert_eq!(store.lock().revision, 5);
        assert_eq!(
            tokio::fs::read_to_string(&path).await.expect("read"),
            encoded
        );
    }

    #[tokio::test]
    async fn incomplete_identity_leaves_original_bytes() {
        let dir = tempfile::tempdir().expect("temp");
        let path = dir.path().join("workspaces.toml");
        let raw = "schemaVersion = 1\nrevision = 1\n\n[[workspaces]]\nid = \"\"\nname = \"A\"\npath = \"/tmp/a\"\ncreatedAt = 1\nupdatedAt = 1\n";
        tokio::fs::write(&path, raw).await.expect("write");
        let error = WorkspaceStore::load(path.clone())
            .await
            .err()
            .expect("invalid identity");
        assert!(error.is::<DocumentMigrationFailed>());
        assert_eq!(
            tokio::fs::read_to_string(&path).await.expect("unchanged"),
            raw
        );
    }

    #[tokio::test]
    async fn workspace_schema_one_migrates_all_fields_and_is_idempotent() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let path = temp.path().join("workspaces.toml");
        let old = r#"
schemaVersion = 1
revision = 17

[[workspaces]]
id = "open"
name = "保留项目"
path = "/projects/kept"
createdAt = 3
updatedAt = 8
lastOpenedAt = 7
closed = false

[[workspaces]]
id = "closed"
name = "Remote"
path = "/srv/kept"
sshAlias = "remote"
createdAt = 4
updatedAt = 11
lastOpenedAt = 9
closed = true
"#;
        tokio::fs::write(&path, old).await?;
        let store = WorkspaceStore::load(path.clone()).await?;
        assert_eq!(store.lock().revision, 17);
        assert_eq!(store.entries().len(), 2);
        let entries = store.entries();
        assert_eq!(entries[0].kind, WorkspaceKind::Project);
        assert_eq!(entries[0].id, "open");
        assert_eq!(entries[0].name, "保留项目");
        assert_eq!(entries[0].path, "/projects/kept");
        assert_eq!(entries[0].created_at, 3);
        assert_eq!(entries[0].updated_at, 8);
        assert_eq!(entries[0].last_opened_at, Some(7));
        assert!(!entries[0].closed);
        assert_eq!(entries[1].kind, WorkspaceKind::Project);
        assert_eq!(entries[1].ssh_alias.as_deref(), Some("remote"));
        assert_eq!(entries[1].last_opened_at, Some(9));
        assert!(entries[1].closed);
        let migrated_bytes = tokio::fs::read(&path).await?;
        let migrated_text = std::str::from_utf8(&migrated_bytes)?;
        let migrated: toml::Table = toml::from_str(migrated_text)?;
        assert_eq!(migrated["schemaVersion"].as_integer(), Some(2));
        assert_eq!(migrated["revision"].as_integer(), Some(17));
        let mut expected: toml::Table = toml::from_str(old)?;
        expected.insert("schemaVersion".into(), toml::Value::Integer(2));
        for entry in expected["workspaces"].as_array_mut().expect("workspaces") {
            entry
                .as_table_mut()
                .expect("workspace entry")
                .insert("kind".into(), toml::Value::String("project".into()));
        }
        assert_eq!(migrated, expected);
        let reopened = WorkspaceStore::load(path.clone()).await?;
        assert_eq!(reopened.entries(), entries);
        assert_eq!(tokio::fs::read(&path).await?, migrated_bytes);
        Ok(())
    }

    #[tokio::test]
    async fn apply_delta_rejects_invalid_candidates_without_publishing() -> Result<()> {
        let cases = [
            DirectoryDelta {
                project_upserts: vec![
                    project_upsert("standalone-a", WorkspaceKind::Standalone),
                    project_upsert("standalone-b", WorkspaceKind::Standalone),
                ],
                ..Default::default()
            },
            DirectoryDelta {
                project_upserts: vec![
                    project_upsert("same-id", WorkspaceKind::Project),
                    project_upsert("same-id", WorkspaceKind::Standalone),
                ],
                ..Default::default()
            },
            DirectoryDelta {
                project_upserts: vec![project_upsert(
                    "created-standalone",
                    WorkspaceKind::Standalone,
                )],
                project_removals: vec![ProjectRemoval {
                    project_id: "created-standalone".into(),
                    thread_ids: Vec::new(),
                    closed_at: 3,
                }],
                ..Default::default()
            },
        ];

        for delta in cases {
            let dir = tempfile::tempdir()?;
            let path = dir.path().join("workspaces.toml");
            let original = empty_store_bytes(9);
            tokio::fs::write(&path, &original).await?;
            let store = WorkspaceStore::load(path.clone()).await?;

            assert!(store.apply_delta(&delta).await.is_err());
            assert!(store.entries().is_empty());
            assert_eq!(store.lock().revision, 9);
            assert_eq!(tokio::fs::read_to_string(path).await?, original);
        }
        Ok(())
    }

    #[tokio::test]
    async fn concurrent_standalone_upserts_commit_at_most_one_owner() -> Result<()> {
        let dir = tempfile::tempdir()?;
        let path = dir.path().join("workspaces.toml");
        tokio::fs::write(&path, empty_store_bytes(1)).await?;
        let store = WorkspaceStore::load(path.clone()).await?;
        let barrier = Arc::new(tokio::sync::Barrier::new(3));

        let first = {
            let store = store.clone();
            let barrier = barrier.clone();
            tokio::spawn(async move {
                barrier.wait().await;
                store
                    .apply_delta(&DirectoryDelta {
                        project_upserts: vec![project_upsert(
                            "standalone-a",
                            WorkspaceKind::Standalone,
                        )],
                        ..Default::default()
                    })
                    .await
            })
        };
        let second = {
            let store = store.clone();
            let barrier = barrier.clone();
            tokio::spawn(async move {
                barrier.wait().await;
                store
                    .apply_delta(&DirectoryDelta {
                        project_upserts: vec![project_upsert(
                            "standalone-b",
                            WorkspaceKind::Standalone,
                        )],
                        ..Default::default()
                    })
                    .await
            })
        };

        barrier.wait().await;
        let results = [first.await?, second.await?];
        assert_eq!(results.iter().filter(|result| result.is_ok()).count(), 1);
        let entries = store.entries();
        assert_eq!(
            entries
                .iter()
                .filter(|entry| entry.kind == WorkspaceKind::Standalone)
                .count(),
            1
        );
        let reopened = WorkspaceStore::load(path.clone()).await?;
        assert_eq!(reopened.entries(), entries);
        Ok(())
    }
}
