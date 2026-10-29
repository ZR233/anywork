//! `catalog.toml`: 轻量会话目录摘要的唯一事实源。
//!
//! 首屏列表、目录分页与搜索只从本文件构造 `Thread` 摘要，不读取任何会话
//! `state.toml` 或 `history.sqlite`（design/17 §17.1、§17.2）。因此条目只保留
//! 目录展示与 `ThreadDirectoryQuery` 判定所需的稳定字段：身份、标题、Mode、角色、
//! 工作区模式/地址、时间戳、归档状态与有界活动摘要。当前上下文、Turn、历史正文、
//! 请求/工具结果与执行状态一律不在其中，活动指示器由内存热集合覆盖。
//!
//! 文件使用版本化 schema、CAS revision 与原子写入；运行期热集合（`ProductEventBus`）
//! 仍在内存中先行，本模块只承载已提交为目录事实的冷摘要。

mod schema;

use std::path::PathBuf;
use std::sync::{Arc, Mutex, PoisonError};

use anyhow::{Result, ensure};
use pl_protocol::studio::{ThreadDirectoryMatchFields, ThreadDirectoryQuery};
use pl_protocol::{Thread, ThreadModeId, ThreadStatus, ThreadWorkspaceMode};
use version_migrate::Versioned;

use super::toml_store::{self, RevisionedDocument};
use crate::toml_schema;

/// 一个会话的轻量目录摘要。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::studio) struct CatalogEntry {
    /// Derived only after the canonical checkpoint close intent is durable; false is not proof
    /// of open admission. Every execution recovery still validates its checkpoint.
    pub(in crate::studio) explicitly_closed: bool,
    pub(in crate::studio) id: String,
    pub(in crate::studio) project_id: String,
    pub(in crate::studio) title: String,
    pub(in crate::studio) mode: ThreadModeId,
    pub(in crate::studio) workspace_mode: ThreadWorkspaceMode,
    pub(in crate::studio) delegation_mode: pl_protocol::DelegationMode,
    pub(in crate::studio) delegation_preference: pl_protocol::DelegationPreference,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(in crate::studio) frozen_model: Option<pl_protocol::studio::NewThreadModelRoute>,
    pub(in crate::studio) workspace_path: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(in crate::studio) parent_thread_id: Option<String>,
    pub(in crate::studio) root_thread_id: String,
    pub(in crate::studio) role: String,
    pub(in crate::studio) agent_path: String,
    pub(in crate::studio) status: ThreadStatus,
    pub(in crate::studio) created_at: i64,
    pub(in crate::studio) updated_at: i64,
    /// 服务端最近一次成功受理用户消息的时间；缺失即尚未有已受理用户消息（含 v1 目录）。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(in crate::studio) last_user_message_at: Option<i64>,
    pub(in crate::studio) archived: bool,
}

impl CatalogEntry {
    /// 与 `Thread::directory_sort_time` 相同的目录排序键，避免排序时构造完整 `Thread`。
    fn directory_sort_time(&self) -> i64 {
        self.last_user_message_at.unwrap_or(self.created_at)
    }

    pub(in crate::studio) fn from_thread(thread: &Thread) -> Self {
        Self {
            explicitly_closed: false,
            id: thread.id.clone(),
            project_id: thread.project_id.clone(),
            title: thread.title.clone(),
            mode: thread.mode.clone(),
            workspace_mode: thread.workspace_mode,
            delegation_mode: thread.delegation_mode,
            delegation_preference: thread.delegation_preference,
            frozen_model: thread.frozen_model.clone(),
            workspace_path: thread.workspace_path.clone(),
            parent_thread_id: thread.parent_thread_id.clone(),
            root_thread_id: thread.root_thread_id.clone(),
            role: thread.role.clone(),
            agent_path: thread.agent_path.clone(),
            status: thread.status,
            created_at: thread.created_at,
            updated_at: thread.updated_at,
            last_user_message_at: thread.last_user_message_at,
            archived: thread.archived,
        }
    }

    pub(in crate::studio) fn to_thread(&self) -> Thread {
        Thread {
            id: self.id.clone(),
            project_id: self.project_id.clone(),
            title: self.title.clone(),
            mode: self.mode.clone(),
            workspace_mode: self.workspace_mode,
            delegation_mode: self.delegation_mode,
            delegation_preference: self.delegation_preference,
            frozen_model: self.frozen_model.clone(),
            workspace_path: self.workspace_path.clone(),
            root_thread_id: self.root_thread_id.clone(),
            parent_thread_id: self.parent_thread_id.clone(),
            role: self.role.clone(),
            agent_path: self.agent_path.clone(),
            status: self.projected_status(),
            created_at: self.created_at,
            updated_at: self.updated_at,
            last_user_message_at: self.last_user_message_at,
            archived: self.archived,
        }
    }

    pub(in crate::studio) fn projected_status(&self) -> ThreadStatus {
        if self.parent_thread_id.is_some() {
            super::agent_close::directory_status(self.status, self.explicitly_closed)
        } else {
            self.status
        }
    }
}

/// `catalog.toml` 的持久化文档。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CatalogDocument {
    revision: u64,
    entries: Vec<CatalogEntry>,
}

impl Versioned for CatalogDocument {
    const VERSION: &'static str = schema::CatalogV4::VERSION;
}

impl RevisionedDocument for CatalogDocument {
    const KIND: &'static str = "Studio catalog";
    const VERSION_KEY: &'static str = schema::SCHEMA_KEY;

    fn revision_mut(&mut self) -> &mut u64 {
        &mut self.revision
    }
}

/// 目录摘要的进程内 owner：文件是唯一事实源，内存缓存避免分页时的重复解析。
///
/// 所有 mutation 都走同一把锁内的读取-修改-原子替换，`revision` 单调递增用于
/// CAS 语义；读路径返回缓存克隆，不读取会话状态。
#[derive(Clone)]
pub(in crate::studio) struct CatalogStore {
    path: PathBuf,
    inner: Arc<Mutex<CatalogDocument>>,
}

impl CatalogStore {
    /// 从磁盘加载（缺失时为带 revision 1 的空目录）。
    pub(in crate::studio) async fn load(path: PathBuf) -> Result<Self> {
        let document = match tokio::fs::read_to_string(&path).await {
            Ok(content) => {
                let loaded = schema::load_document(&path, &content)?;
                if loaded.migrated {
                    let bytes = toml_schema::encode(&loaded.document, schema::SCHEMA_KEY)?;
                    let path = path.clone();
                    tokio::task::spawn_blocking(move || {
                        pl_tool::workspace::write_file_atomically(&path, bytes.as_bytes())
                    })
                    .await??;
                }
                loaded.document
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => CatalogDocument {
                revision: 1,
                entries: Vec::new(),
            },
            Err(error) => return Err(error.into()),
        };
        Ok(Self {
            path,
            inner: Arc::new(Mutex::new(document)),
        })
    }

    /// 全部条目的稳定快照（按 `(last_user_message_at ?? created_at, id)` 降序）。
    pub(in crate::studio) fn entries(&self) -> Vec<CatalogEntry> {
        let mut entries = self.lock().entries.clone();
        sort_desc(&mut entries);
        entries
    }

    pub(in crate::studio) fn get(&self, thread_id: &str) -> Option<CatalogEntry> {
        self.lock()
            .entries
            .iter()
            .find(|entry| entry.id == thread_id)
            .cloned()
    }

    /// 冷目录分页：`(last_user_message_at ?? created_at, id)` 降序 keyset；
    /// 查询命中后才应用 cursor，保证搜索语义。
    pub(in crate::studio) fn page(
        &self,
        query: &ThreadDirectoryQuery,
        project_matches: &std::collections::HashSet<String>,
        cursor: Option<&(i64, String)>,
        limit: usize,
    ) -> Vec<Thread> {
        let matched = self
            .lock()
            .entries
            .iter()
            .filter(|entry| {
                query.matches_fields(
                    ThreadDirectoryMatchFields {
                        parent_thread_id: entry.parent_thread_id.as_deref(),
                        archived: entry.archived,
                        project_id: &entry.project_id,
                        title: &entry.title,
                        status: entry.status,
                    },
                    project_matches.contains(&entry.project_id),
                )
            })
            .cloned()
            .collect::<Vec<_>>();
        page_threads(matched, cursor, limit)
    }

    /// 未归档 root Thread 的冷分页（无搜索过滤）。
    pub(in crate::studio) fn page_active(
        &self,
        cursor: Option<&(i64, String)>,
        limit: usize,
    ) -> Vec<Thread> {
        let matched = self
            .lock()
            .entries
            .iter()
            .filter(|entry| !entry.archived && entry.parent_thread_id.is_none())
            .cloned()
            .collect::<Vec<_>>();
        page_threads(matched, cursor, limit)
    }

    /// 幂等写入/替换一个条目；内容不变时不推进 revision，也不落盘。
    ///
    /// 迟到快照不得使最近用户消息时间回退：写回时与既有条目取较新值，其余目录列
    /// 以命令顺序为准（design/17 §17.1）。
    pub(in crate::studio) async fn upsert(&self, mut entry: CatalogEntry) -> Result<()> {
        self.mutate(move |document| {
            match document
                .entries
                .iter_mut()
                .find(|existing| existing.id == entry.id)
            {
                Some(existing) if *existing == entry => false,
                Some(existing) => {
                    // DTO observations do not carry closure intent. A late owner/metadata
                    // projection cannot erase the checkpoint-derived, monotonic seal.
                    entry.explicitly_closed |= existing.explicitly_closed;
                    if existing.explicitly_closed && existing.status == ThreadStatus::Closed {
                        entry.status = ThreadStatus::Closed;
                    }
                    if *existing == entry {
                        return false;
                    }
                    let last_user_message_at = existing
                        .last_user_message_at
                        .max(entry.last_user_message_at);
                    *existing = entry;
                    existing.last_user_message_at = last_user_message_at;
                    true
                }
                None => {
                    document.entries.push(entry);
                    true
                }
            }
        })
        .await
    }

    pub(in crate::studio) async fn project_explicit_close(&self, id: &str) -> Result<()> {
        ensure!(
            self.get(id)
                .is_some_and(|entry| entry.parent_thread_id.is_some()),
            "explicit close projection requires a saved child"
        );
        let id = id.to_owned();
        self.mutate(move |document| {
            let Some(entry) = document.entries.iter_mut().find(|entry| entry.id == id) else {
                return false;
            };
            if entry.explicitly_closed {
                return false;
            }
            entry.explicitly_closed = true;
            // An old normal-shutdown Closed status says nothing about this close's progress.
            // The current owner publishes Closed only after its real shutdown is confirmed.
            entry.status = ThreadStatus::Closing;
            true
        })
        .await
    }

    /// 幂等标记归档；条目缺失或已归档时不落盘。
    pub(in crate::studio) async fn archive(
        &self,
        thread_ids: &[String],
        archived_at: i64,
    ) -> Result<()> {
        let thread_ids = thread_ids.to_vec();
        self.mutate(move |document| {
            let mut changed = false;
            for id in &thread_ids {
                if let Some(entry) = document.entries.iter_mut().find(|entry| entry.id == *id)
                    && !entry.archived
                {
                    entry.archived = true;
                    entry.updated_at = entry.updated_at.max(archived_at);
                    changed = true;
                }
            }
            changed
        })
        .await
    }

    /// 幂等推进活动时间戳；缺失条目 no-op。
    pub(in crate::studio) async fn touch(&self, thread_ids: &[(String, i64)]) -> Result<()> {
        let thread_ids = thread_ids.to_vec();
        self.mutate(move |document| {
            let mut changed = false;
            for (id, updated_at) in &thread_ids {
                if let Some(entry) = document.entries.iter_mut().find(|entry| entry.id == *id) {
                    let next = entry.updated_at.max(*updated_at);
                    if next != entry.updated_at {
                        entry.updated_at = next;
                        changed = true;
                    }
                }
            }
            changed
        })
        .await
    }

    /// 把当前内存文档写入 canonical 文件；文件已存在时不覆盖。
    ///
    /// 新安装启动时确保 `catalog.toml` 存在，以便后续缺失被识别为数据丢失。
    pub(in crate::studio) async fn persist_if_absent(&self) -> Result<()> {
        let inner = self.inner.clone();
        let path = self.path.clone();
        tokio::task::spawn_blocking(move || toml_store::persist_if_absent(&inner, &path)).await?
    }

    async fn mutate(
        &self,
        change: impl FnOnce(&mut CatalogDocument) -> bool + Send + 'static,
    ) -> Result<()> {
        let inner = self.inner.clone();
        let path = self.path.clone();
        tokio::task::spawn_blocking(move || {
            toml_store::mutate_document(&inner, &path, |document| Ok(change(document)))
        })
        .await?
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, CatalogDocument> {
        self.inner.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

fn page_threads(
    mut entries: Vec<CatalogEntry>,
    cursor: Option<&(i64, String)>,
    limit: usize,
) -> Vec<Thread> {
    sort_desc(&mut entries);
    entries
        .into_iter()
        .filter(|entry| {
            cursor.is_none_or(|(sort_time, id)| {
                (entry.directory_sort_time(), entry.id.as_str()) < (*sort_time, id.as_str())
            })
        })
        .take(limit)
        .map(|entry| entry.to_thread())
        .collect()
}

fn sort_desc(entries: &mut [CatalogEntry]) {
    entries.sort_by(|left, right| {
        right
            .directory_sort_time()
            .cmp(&left.directory_sort_time())
            .then_with(|| right.id.cmp(&left.id))
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::toml_schema::DocumentMigrationFailed;

    fn current_entry() -> CatalogEntry {
        CatalogEntry {
            explicitly_closed: false,
            id: "thread-a".into(),
            project_id: "project-a".into(),
            title: "Root".into(),
            mode: ThreadModeId::simple(),
            workspace_mode: ThreadWorkspaceMode::Local,
            delegation_mode: pl_protocol::DelegationMode::Profile,
            delegation_preference: pl_protocol::DelegationPreference::Balanced,
            frozen_model: None,
            workspace_path: "/tmp/a".into(),
            parent_thread_id: None,
            root_thread_id: "thread-a".into(),
            role: "root".into(),
            agent_path: "thread-a".into(),
            status: ThreadStatus::Idle,
            created_at: 10,
            updated_at: 20,
            last_user_message_at: Some(15),
            archived: false,
        }
    }

    #[tokio::test]
    async fn current_bytes_are_not_rewritten_and_keep_revision() {
        let dir = tempfile::tempdir().expect("temp");
        let path = dir.path().join("catalog.toml");
        let document = CatalogDocument {
            revision: 7,
            entries: vec![current_entry()],
        };
        let encoded = toml_schema::encode(&document, schema::SCHEMA_KEY).expect("encode");
        tokio::fs::write(&path, &encoded).await.expect("write");
        let store = CatalogStore::load(path.clone())
            .await
            .expect("load current");
        assert_eq!(store.lock().revision, 7);
        assert_eq!(
            tokio::fs::read_to_string(&path).await.expect("read"),
            encoded
        );

        store.upsert(current_entry()).await.expect("idempotent");
        assert_eq!(store.lock().revision, 7);
        assert_eq!(
            tokio::fs::read_to_string(&path).await.expect("read"),
            encoded
        );
    }

    #[tokio::test]
    async fn old_catalog_upgrades_once_and_keeps_revision() {
        let dir = tempfile::tempdir().expect("temp");
        let path = dir.path().join("catalog.toml");
        let raw = "schemaVersion = 2\nrevision = 4\n\n[[entries]]\nid = \"thread-a\"\nprojectId = \"project-a\"\ntitle = \"Root\"\nmode = \"mode.simple\"\nworkspaceMode = \"local\"\nworkspacePath = \"/tmp/a\"\nrootThreadId = \"thread-a\"\nrole = \"root\"\nagentPath = \"thread-a\"\nstatus = \"idle\"\ncreatedAt = 10\nupdatedAt = 20\narchived = false\n";
        tokio::fs::write(&path, raw).await.expect("write v2");
        let store = CatalogStore::load(path.clone()).await.expect("upgrade");
        let first = tokio::fs::read_to_string(&path).await.expect("upgraded");
        let table: toml::Table = toml::from_str(&first).expect("toml");
        assert_eq!(
            table["schemaVersion"].as_integer(),
            Some(i64::from(
                schema::current_version().expect("catalog integer version")
            ))
        );
        assert_eq!(table["revision"].as_integer(), Some(4));
        assert_eq!(
            table["entries"][0]["delegationMode"].as_str(),
            Some("profile")
        );
        assert_eq!(
            table["entries"][0]["explicitlyClosed"].as_bool(),
            Some(false)
        );
        drop(store);
        let store = CatalogStore::load(path.clone()).await.expect("reopen");
        assert_eq!(store.lock().revision, 4);
        assert_eq!(
            tokio::fs::read_to_string(&path).await.expect("stable"),
            first
        );
    }

    #[tokio::test]
    async fn validation_failure_leaves_original_bytes() {
        let dir = tempfile::tempdir().expect("temp");
        let path = dir.path().join("catalog.toml");
        let raw = "schemaVersion = 4\nrevision = 2\nentries = []\n";
        tokio::fs::write(&path, raw).await.expect("write");
        let error = CatalogStore::load(path.clone())
            .await
            .err()
            .expect("empty catalog");
        assert!(error.is::<DocumentMigrationFailed>());
        assert_eq!(
            tokio::fs::read_to_string(&path).await.expect("unchanged"),
            raw
        );
    }
}
