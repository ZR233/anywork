//! `workspaces.toml`: Project/Workspace 目录事实的 canonical TOML 存储。
//!
//! 旧 `projects` 表属于旧会话版本，v2 不导入；普通目录读取只访问本文件。
//! 写路径与 catalog 一样使用单锁读取-修改-原子替换，`revision` 单调递增并保证同内容幂等。

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, PoisonError};

use anyhow::{Context, Result, bail, ensure};
use pl_protocol::studio::WorkspaceKind;

use crate::studio::records::ProjectRecord;
use crate::studio::store::StudioStore;
use crate::studio::store::directory::DirectoryDelta;
use crate::studio::toml_store::{self, RevisionedDocument};

pub(in crate::studio) const WORKSPACES_SCHEMA_VERSION: u32 = 2;

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

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct WorkspacesDocument {
    schema_version: u32,
    revision: u64,
    workspaces: Vec<WorkspaceEntry>,
}

impl RevisionedDocument for WorkspacesDocument {
    const KIND: &'static str = "Studio workspaces";

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
                let (document, migrated) =
                    decode_loaded(&path, &content).map_err(crate::studio::startup::data_error)?;
                if migrated {
                    let contents = toml::to_string_pretty(&document)?;
                    let target = path.clone();
                    tokio::task::spawn_blocking(move || {
                        pl_tool::workspace::write_file_atomically(&target, contents.as_bytes())
                    })
                    .await??;
                }
                document
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => WorkspacesDocument {
                schema_version: WORKSPACES_SCHEMA_VERSION,
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
        {
            let document = self.lock();
            for entry in &upserts {
                if entry.kind == WorkspaceKind::Standalone {
                    ensure!(
                        entry.ssh_alias.is_none()
                            && !entry.closed
                            && document.workspaces.iter().all(|existing| {
                                existing.kind != WorkspaceKind::Standalone
                                    || existing.id == entry.id
                            }),
                        "Studio workspaces contain an invalid standalone owner"
                    );
                }
                if let Some(existing) = document
                    .workspaces
                    .iter()
                    .find(|existing| existing.id == entry.id)
                {
                    ensure_identity_stable(existing, entry)?;
                }
            }
            for removal in &delta.project_removals {
                ensure!(
                    document.workspaces.iter().all(|existing| {
                        existing.id != removal.project_id
                            || existing.kind != WorkspaceKind::Standalone
                    }),
                    "the standalone workspace cannot be archived"
                );
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

/// The sole schema-1 decoding boundary; ordinary decoding requires an explicit kind.
fn decode_loaded(path: &Path, content: &str) -> Result<(WorkspacesDocument, bool)> {
    let mut value: toml::Table = toml::from_str(content)
        .with_context(|| format!("invalid Studio workspaces {}", path.display()))?;
    if value.get("schemaVersion").and_then(toml::Value::as_integer) != Some(1) {
        return decode(path, content).map(|document| (document, false));
    }
    let entries = value
        .get_mut("workspaces")
        .and_then(toml::Value::as_array_mut)
        .context("legacy Studio workspaces has no workspace array")?;
    for entry in entries {
        let entry = entry.as_table_mut().context("invalid legacy workspace")?;
        ensure!(
            !entry.contains_key("kind"),
            "legacy workspace contains kind"
        );
        entry.insert("kind".into(), toml::Value::String("project".into()));
    }
    value.insert("schemaVersion".into(), toml::Value::Integer(2));
    let mut document = decode(path, &toml::to_string(&value)?)?;
    document.revision = document
        .revision
        .checked_add(1)
        .context("Studio workspaces revision overflow")?;
    Ok((document, true))
}

fn decode(path: &Path, content: &str) -> Result<WorkspacesDocument> {
    let document: WorkspacesDocument = toml::from_str(content)
        .with_context(|| format!("invalid Studio workspaces {}", path.display()))?;
    ensure!(
        document.schema_version == WORKSPACES_SCHEMA_VERSION,
        "unsupported Studio workspaces schema in {}",
        path.display()
    );
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
    let standalone = document
        .workspaces
        .iter()
        .filter(|entry| entry.kind == WorkspaceKind::Standalone)
        .collect::<Vec<_>>();
    ensure!(
        standalone.len() <= 1
            && standalone
                .iter()
                .all(|entry| entry.ssh_alias.is_none() && !entry.closed),
        "Studio workspaces contain an invalid standalone owner"
    );
    Ok(document)
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
        assert_eq!(store.entries().len(), 2);
        assert!(
            store
                .entries()
                .iter()
                .all(|entry| entry.kind == WorkspaceKind::Project)
        );
        let contents = tokio::fs::read_to_string(&path).await?;
        let mut upgraded: toml::Table = toml::from_str(&contents)?;
        assert_eq!(upgraded["schemaVersion"].as_integer(), Some(2));
        assert_eq!(upgraded["revision"].as_integer(), Some(18));
        upgraded.insert("schemaVersion".into(), toml::Value::Integer(1));
        upgraded.insert("revision".into(), toml::Value::Integer(17));
        for entry in upgraded["workspaces"].as_array_mut().unwrap() {
            assert_eq!(
                entry
                    .as_table_mut()
                    .unwrap()
                    .remove("kind")
                    .unwrap()
                    .as_str(),
                Some("project")
            );
        }
        assert_eq!(upgraded, toml::from_str::<toml::Table>(old)?);
        let reopened = WorkspaceStore::load(path.clone()).await?;
        assert_eq!(reopened.entries(), store.entries());
        assert_eq!(tokio::fs::read_to_string(path).await?, contents);
        Ok(())
    }

    #[test]
    fn workspace_schema_two_requires_known_kind_and_unique_local_standalone() -> Result<()> {
        let path = Path::new("workspaces.toml");
        let header = "schemaVersion = 2\nrevision = 1\n";
        let entry = r#"
[[workspaces]]
id = "owner"
kind = "standalone"
name = "anywork"
path = "/documents/anywork"
createdAt = 1
updatedAt = 2
"#;
        let valid = format!("{header}{entry}");
        assert_eq!(
            decode(path, &valid)?.workspaces[0].kind,
            WorkspaceKind::Standalone
        );
        for invalid in [
            valid.replace("kind = \"standalone\"\n", ""),
            valid.replace("\"standalone\"", "\"unknown\""),
            format!("{valid}closed = true\n"),
            format!("{valid}sshAlias = \"remote\"\n"),
            format!("{valid}{}", entry.replace("\"owner\"", "\"other\"")),
        ] {
            assert!(decode(path, &invalid).is_err(), "{invalid}");
        }
        Ok(())
    }
}
