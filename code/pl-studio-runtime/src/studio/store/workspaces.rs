//! `workspaces.toml`: Project/Workspace 目录事实的 canonical TOML 存储。
//!
//! 旧 `projects` 表属于旧会话版本，v2 不导入；普通目录读取只访问本文件。
//! 写路径与 catalog 一样使用单锁读取-修改-原子替换，`revision` 单调递增并保证同内容幂等。

mod schema;

use std::path::PathBuf;
use std::sync::{Arc, Mutex, PoisonError};

use anyhow::{Result, bail};
use version_migrate::Versioned;

use crate::studio::records::ProjectRecord;
use crate::studio::store::StudioStore;
use crate::studio::store::directory::DirectoryDelta;
use crate::studio::toml_store::{self, RevisionedDocument};

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::studio) struct WorkspaceEntry {
    pub(in crate::studio) id: String,
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
            name: self.name.clone(),
            path: self.path.clone(),
            ssh_alias: self.ssh_alias.clone(),
            updated_at: self.updated_at,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize, Versioned)]
#[versioned(version = "1.0.0")]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct WorkspacesDocument {
    revision: u64,
    workspaces: Vec<WorkspaceEntry>,
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
            Ok(content) => schema::load_document(&path, &content)?.document,
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
                name: record.name.clone(),
                path: record.path.clone(),
                ssh_alias: record.ssh_alias.clone(),
                created_at: record.created_at,
                updated_at: record.updated_at,
                last_opened_at: record.last_opened_at,
                closed: record.closed,
            })
            .collect::<Vec<_>>();
        {
            let document = self.lock();
            for entry in &upserts {
                if let Some(existing) = document
                    .workspaces
                    .iter()
                    .find(|existing| existing.id == entry.id)
                {
                    ensure_identity_stable(existing, entry)?;
                }
            }
        }
        let removals = delta
            .project_removals
            .iter()
            .map(|removal| (removal.project_id.clone(), removal.closed_at))
            .collect::<Vec<_>>();
        self.mutate(move |document| {
            let mut changed = false;
            for entry in upserts {
                match document
                    .workspaces
                    .iter_mut()
                    .find(|existing| existing.id == entry.id)
                {
                    Some(existing)
                        if existing.path == entry.path && existing.ssh_alias == entry.ssh_alias =>
                    {
                        let next = WorkspaceEntry {
                            created_at: existing.created_at,
                            ..entry
                        };
                        if *existing != next {
                            *existing = next;
                            changed = true;
                        }
                    }
                    Some(_) => {}
                    None => {
                        document.workspaces.push(entry);
                        changed = true;
                    }
                }
            }
            for (id, closed_at) in removals {
                if let Some(existing) = document.workspaces.iter_mut().find(|entry| entry.id == id)
                    && (!existing.closed || existing.updated_at < closed_at)
                {
                    existing.closed = true;
                    existing.updated_at = existing.updated_at.max(closed_at);
                    changed = true;
                }
            }
            changed
        })
        .await
    }

    /// 把当前内存文档写入 canonical 文件；文件已存在时不覆盖。
    ///
    /// 只有 migration 边界使用，用来补齐旧发布遗留的空缺文档；正常运行写入都经
    /// [`Self::apply_delta`]。
    pub(in crate::studio) async fn persist_if_absent(&self) -> Result<()> {
        let inner = self.inner.clone();
        let path = self.path.clone();
        tokio::task::spawn_blocking(move || toml_store::persist_if_absent(&inner, &path)).await?
    }

    async fn mutate(
        &self,
        change: impl FnOnce(&mut WorkspacesDocument) -> bool + Send + 'static,
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
    if existing.path != next.path || existing.ssh_alias != next.ssh_alias {
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
    use crate::toml_schema::{self, DocumentMigrationFailed};

    fn current_entry() -> WorkspaceEntry {
        WorkspaceEntry {
            id: "project-a".into(),
            name: "A".into(),
            path: "/tmp/a".into(),
            ssh_alias: Some("host".into()),
            created_at: 1,
            updated_at: 2,
            last_opened_at: Some(3),
            closed: false,
        }
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
}
