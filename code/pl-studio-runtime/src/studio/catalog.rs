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

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, PoisonError};

use anyhow::{Context, Result, bail, ensure};
use pl_protocol::studio::{ThreadDirectoryMatchFields, ThreadDirectoryQuery};
use pl_protocol::{Thread, ThreadModeId, ThreadStatus, ThreadWorkspaceMode};

use super::toml_store::{self, RevisionedDocument};

pub(in crate::studio) const CATALOG_SCHEMA_VERSION: u32 = 4;

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
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CatalogDocument {
    schema_version: u32,
    revision: u64,
    entries: Vec<CatalogEntry>,
}

impl RevisionedDocument for CatalogDocument {
    const KIND: &'static str = "Studio catalog";

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
                let (document, migrate) =
                    decode(&path, &content).map_err(crate::studio::startup::data_error)?;
                if migrate {
                    let bytes = toml::to_string_pretty(&document)?;
                    let path = path.clone();
                    tokio::task::spawn_blocking(move || {
                        pl_tool::workspace::write_file_atomically(&path, bytes.as_bytes())
                    })
                    .await??;
                }
                document
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => CatalogDocument {
                schema_version: CATALOG_SCHEMA_VERSION,
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
        tokio::task::spawn_blocking(move || toml_store::mutate_document(&inner, &path, change))
            .await?
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, CatalogDocument> {
        self.inner.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

fn decode(path: &Path, content: &str) -> Result<(CatalogDocument, bool)> {
    let mut legacy: toml::Value = toml::from_str(content)?;
    let version = legacy
        .get("schemaVersion")
        .and_then(toml::Value::as_integer)
        .context("Studio catalog schema version is missing")?;
    if (1..3).contains(&version)
        && let Some(entries) = legacy
            .get_mut("entries")
            .and_then(toml::Value::as_array_mut)
    {
        for entry in entries {
            let entry = entry.as_table_mut().context("invalid catalog entry")?;
            entry.insert("delegationMode".into(), "profile".into());
            entry.insert("delegationPreference".into(), "balanced".into());
        }
    }
    if (1..4).contains(&version)
        && let Some(entries) = legacy
            .get_mut("entries")
            .and_then(toml::Value::as_array_mut)
    {
        for entry in entries {
            let entry = entry.as_table_mut().context("invalid catalog entry")?;
            ensure!(
                !entry.contains_key("explicitlyClosed"),
                "old catalog contains unversioned close intent"
            );
            entry.insert("explicitlyClosed".into(), false.into());
        }
    }
    let mut document: CatalogDocument = legacy
        .try_into()
        .with_context(|| format!("invalid Studio catalog {}", path.display()))?;
    // v1 lacks the last accepted user timestamp; v2 lacks frozen delegation provenance.
    // Normalize only at this version boundary; opening commits the representation atomically.
    ensure!(
        (1..=CATALOG_SCHEMA_VERSION).contains(&document.schema_version),
        "unsupported Studio catalog schema in {}",
        path.display()
    );
    document.schema_version = CATALOG_SCHEMA_VERSION;
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
    Ok((document, version < i64::from(CATALOG_SCHEMA_VERSION)))
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
