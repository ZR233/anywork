//! `catalog.toml`: 轻量会话目录摘要的持久化所有者。
//!
//! 启动时为目录 owner 建立当前摘要，不读取任何会话
//! `state.toml` 或 `history.sqlite`（design/17 §17.1、§17.2）。文件按会话目录事实
//! （`sessions`）与成员事实（`agents`）两级记录：会话标题、排序时间、归档、工作区
//! 与分发设置唯一归属会话记录；成员关系（`parent_agent_id`）、定义 ID、backend
//! 绑定与目录状态唯一归属成员记录。当前上下文、Turn、历史正文、指令正文、
//! 请求/工具结果与执行资源一律不在其中，当前展示由运行期目录 owner 交付。
//!
//! 文件使用版本化 schema、CAS revision 与原子写入；运行期目录（`ProductEventBus`）
//! 与冻结保存批次分别负责当前查询和持久化，不在查询时合并两份当前态。

mod schema;

use std::path::PathBuf;
use std::sync::{Arc, Mutex, PoisonError};

use anyhow::{Result, ensure};
use pl_protocol::ThreadStatus;
use version_migrate::Versioned;

use super::records::{AgentDirectoryRecord, SessionDirectoryRecord};
use super::toml_store::{self, RevisionedDocument};
use crate::toml_schema;

/// `catalog.toml` 的持久化文档。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CatalogDocument {
    revision: u64,
    sessions: Vec<SessionDirectoryRecord>,
    agents: Vec<AgentDirectoryRecord>,
}

impl Versioned for CatalogDocument {
    const VERSION: &'static str = schema::CatalogV6::VERSION;
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
                ensure!(
                    loaded.source_version >= 5,
                    "retired catalog ownership requires explicit storage migration"
                );
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
                sessions: Vec::new(),
                agents: Vec::new(),
            },
            Err(error) => return Err(error.into()),
        };
        Ok(Self {
            path,
            inner: Arc::new(Mutex::new(document)),
        })
    }

    /// 全部会话记录的稳定快照（按 `(last_user_message_at ?? created_at, session_id)` 降序）。
    pub(in crate::studio) fn sessions(&self) -> Vec<SessionDirectoryRecord> {
        let mut sessions = self.lock().sessions.clone();
        sessions.sort_by(|left, right| {
            right
                .directory_sort_time()
                .cmp(&left.directory_sort_time())
                .then_with(|| right.session_id.cmp(&left.session_id))
        });
        sessions
    }

    pub(in crate::studio) fn archived_session_ids(&self) -> std::collections::HashSet<String> {
        self.lock()
            .sessions
            .iter()
            .filter(|session| session.archived)
            .map(|session| session.session_id.clone())
            .collect()
    }

    pub(in crate::studio) fn get_session(
        &self,
        session_id: &str,
    ) -> Option<SessionDirectoryRecord> {
        self.lock()
            .sessions
            .iter()
            .find(|session| session.session_id == session_id)
            .cloned()
    }

    pub(in crate::studio) fn get_agent(&self, agent_id: &str) -> Option<AgentDirectoryRecord> {
        self.lock()
            .agents
            .iter()
            .find(|agent| agent.agent_id == agent_id)
            .cloned()
    }

    /// 按默认 Thread 定位成员；首版 AgentId 与 ThreadId 一一同字节映射。
    pub(in crate::studio) fn agent_by_thread(
        &self,
        thread_id: &str,
    ) -> Option<AgentDirectoryRecord> {
        self.lock()
            .agents
            .iter()
            .find(|agent| agent.thread_id == thread_id)
            .cloned()
    }

    /// 一个会话的全部成员（按 `(created_at, agent_id)` 升序，主成员最先创建）。
    pub(in crate::studio) fn agents_for_session(
        &self,
        session_id: &str,
    ) -> Vec<AgentDirectoryRecord> {
        let mut agents = self
            .lock()
            .agents
            .iter()
            .filter(|agent| agent.session_id == session_id)
            .cloned()
            .collect::<Vec<_>>();
        agents.sort_by(|left, right| {
            left.created_at
                .cmp(&right.created_at)
                .then_with(|| left.agent_id.cmp(&right.agent_id))
        });
        agents
    }

    pub(in crate::studio) fn agents(&self) -> Vec<AgentDirectoryRecord> {
        self.lock().agents.clone()
    }

    /// 幂等写入/替换一个会话记录；内容不变时不推进 revision，也不落盘。
    ///
    /// 迟到快照不得使最近用户消息时间回退：写回时与既有记录取较新值，其余目录列
    /// 以命令顺序为准（design/17 §17.1）。
    #[cfg(test)]
    pub(in crate::studio) async fn upsert_session(
        &self,
        mut session: SessionDirectoryRecord,
    ) -> Result<()> {
        self.mutate_document(move |document| {
            match document
                .sessions
                .iter_mut()
                .find(|existing| existing.session_id == session.session_id)
            {
                Some(existing) if *existing == session => false,
                Some(existing) => {
                    session.last_user_message_at = existing
                        .last_user_message_at
                        .max(session.last_user_message_at);
                    if *existing == session {
                        return false;
                    }
                    *existing = session;
                    true
                }
                None => {
                    document.sessions.push(session);
                    true
                }
            }
        })
        .await
    }

    /// 幂等写入/替换一个成员记录；内容不变时不推进 revision，也不落盘。
    #[cfg(test)]
    pub(in crate::studio) async fn upsert_agent(
        &self,
        mut agent: AgentDirectoryRecord,
    ) -> Result<()> {
        self.mutate_document(move |document| {
            match document
                .agents
                .iter_mut()
                .find(|existing| existing.agent_id == agent.agent_id)
            {
                Some(existing) if *existing == agent => false,
                Some(existing) => {
                    // DTO observations do not carry closure intent. A late owner/metadata
                    // projection cannot erase the checkpoint-derived, monotonic seal.
                    agent.explicitly_closed |= existing.explicitly_closed;
                    if existing.explicitly_closed {
                        agent.status = existing.status;
                    }
                    if *existing == agent {
                        return false;
                    }
                    *existing = agent;
                    true
                }
                None => {
                    document.agents.push(agent);
                    true
                }
            }
        })
        .await
    }

    pub(in crate::studio) async fn project_explicit_close(
        &self,
        agent_id: &str,
        execution_closed: bool,
    ) -> Result<()> {
        ensure!(
            self.get_agent(agent_id)
                .is_some_and(|agent| agent.parent_agent_id.is_some()),
            "explicit close projection requires a saved child"
        );
        let agent_id = agent_id.to_owned();
        self.mutate_document(move |document| {
            let Some(agent) = document
                .agents
                .iter_mut()
                .find(|agent| agent.agent_id == agent_id)
            else {
                return false;
            };
            let status = if execution_closed {
                ThreadStatus::Closed
            } else {
                ThreadStatus::Closing
            };
            if agent.explicitly_closed && agent.status == status {
                return false;
            }
            agent.explicitly_closed = true;
            // Only the durable close owner can advance or restore this progress.
            agent.status = status;
            true
        })
        .await
    }

    /// 一次校验并原子提交完整会话/成员 delta，禁止落盘半组身份。
    pub(in crate::studio) async fn apply_delta(
        &self,
        delta: crate::studio::store::directory::DirectoryDelta,
    ) -> Result<()> {
        let inner = self.inner.clone();
        let path = self.path.clone();
        let now = crate::studio::ids::unix_seconds();
        tokio::task::spawn_blocking(move || {
            toml_store::mutate_document(&inner, &path, |document| {
                let previous = document.clone();
                for mut session in delta.session_upserts {
                    if let Some(existing) = document
                        .sessions
                        .iter_mut()
                        .find(|entry| entry.session_id == session.session_id)
                    {
                        session.last_user_message_at = existing
                            .last_user_message_at
                            .max(session.last_user_message_at);
                        *existing = session;
                    } else {
                        document.sessions.push(session);
                    }
                }
                for mut agent in delta.agent_upserts {
                    if let Some(existing) = document
                        .agents
                        .iter_mut()
                        .find(|entry| entry.agent_id == agent.agent_id)
                    {
                        agent.explicitly_closed |= existing.explicitly_closed;
                        if existing.explicitly_closed {
                            agent.status = existing.status;
                        }
                        *existing = agent;
                    } else {
                        document.agents.push(agent);
                    }
                }
                let removals = delta
                    .session_removals
                    .iter()
                    .flat_map(|removal| {
                        removal
                            .session_ids
                            .iter()
                            .map(move |id| (id, removal.archived_at))
                    })
                    .chain(delta.project_removals.iter().flat_map(|removal| {
                        removal
                            .session_ids
                            .iter()
                            .map(move |id| (id, removal.closed_at))
                    }));
                for (id, archived_at) in removals {
                    if let Some(session) = document
                        .sessions
                        .iter_mut()
                        .find(|entry| &entry.session_id == id)
                    {
                        session.archived = true;
                        session.updated_at = session.updated_at.max(archived_at);
                    }
                }
                for fault in delta.unregistered_faults {
                    let agent = document
                        .agents
                        .iter_mut()
                        .find(|agent| agent.agent_id == fault.agent_id)
                        .ok_or_else(|| {
                            anyhow::anyhow!(
                                "spawn compensation agent not found: {}",
                                fault.agent_id
                            )
                        })?;
                    if agent.status != fault.state.kind {
                        agent.status = fault.state.kind;
                        agent.updated_at = agent.updated_at.max(now);
                    }
                }
                let removed_sessions = document
                    .agents
                    .iter()
                    .filter(|agent| {
                        agent.is_root_agent() && delta.thread_deletions.contains(&agent.thread_id)
                    })
                    .map(|agent| agent.session_id.clone())
                    .collect::<std::collections::HashSet<_>>();
                document
                    .sessions
                    .retain(|session| !removed_sessions.contains(&session.session_id));
                document.agents.retain(|agent| {
                    !delta.thread_deletions.contains(&agent.thread_id)
                        && !removed_sessions.contains(&agent.session_id)
                });
                schema::validate(document)?;
                Ok(*document != previous)
            })
        })
        .await?
    }

    /// 把当前内存文档写入 canonical 文件；文件已存在时不覆盖。
    ///
    /// 新安装启动时确保 `catalog.toml` 存在，以便后续缺失被识别为数据丢失。
    pub(in crate::studio) async fn persist_if_absent(&self) -> Result<()> {
        let inner = self.inner.clone();
        let path = self.path.clone();
        tokio::task::spawn_blocking(move || toml_store::persist_if_absent(&inner, &path)).await?
    }

    async fn mutate_document(
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

    #[cfg(test)]
    pub(in crate::studio) async fn test_restore_records(
        &self,
        sessions: Vec<SessionDirectoryRecord>,
        agents: Vec<AgentDirectoryRecord>,
    ) -> Result<()> {
        self.mutate_document(move |document| {
            document.sessions = sessions;
            document.agents = agents;
            true
        })
        .await
    }

    #[cfg(test)]
    pub(in crate::studio) fn test_hold_document(&self) -> impl Drop + '_ {
        self.lock()
    }
}

pub(in crate::studio) fn migrate_v2_content(
    path: &std::path::Path,
    content: &str,
) -> Result<String> {
    schema::migrate_v2_content(path, content)
}

pub(in crate::studio) async fn relocate_managed_v2_paths(
    path: &std::path::Path,
    mappings: &[crate::studio::startup::storage_layout::bot_roots::BotRootMove],
) -> Result<()> {
    let content = tokio::fs::read_to_string(path).await?;
    let mut document = schema::load_document(path, &content)?.document;
    for session in &mut document.sessions {
        if let Some(mapping) = mappings.iter().find(|mapping| {
            mapping
                .threads
                .get(&session.root_agent_id)
                .is_some_and(|proof| proof.proven_local_root)
        }) {
            ensure!(
                session.workspace_id == mapping.workspace_id
                    && session.workspace_mode == pl_protocol::ThreadWorkspaceMode::Local,
                "bot catalog binding changed"
            );
            mapping.exact_path(&mut session.workspace_path)?;
        }
    }
    crate::studio::store::session_layout::write_manifest(
        path,
        &toml_schema::encode(&document, schema::SCHEMA_KEY)?,
    )
    .await
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::studio::store::directory::DirectoryDelta;
    use crate::toml_schema::DocumentMigrationFailed;

    fn v5_content(document: &CatalogDocument) -> String {
        let entries = document
            .agents
            .iter()
            .map(|agent| {
                let session = document
                    .sessions
                    .iter()
                    .find(|session| session.session_id == agent.session_id)
                    .expect("session");
                let thread = super::super::records::thread_projection(session, agent);
                let mut entry = toml::Value::try_from(thread)
                    .expect("entry")
                    .as_table()
                    .expect("table")
                    .clone();
                entry.insert("explicitlyClosed".into(), agent.explicitly_closed.into());
                toml::Value::Table(entry)
            })
            .collect::<Vec<_>>();
        let mut table = toml::Table::new();
        table.insert("schemaVersion".into(), 5_i64.into());
        table.insert("revision".into(), (document.revision as i64).into());
        table.insert("entries".into(), entries.into());
        toml::to_string(&table).expect("legacy catalog")
    }

    fn current_document() -> CatalogDocument {
        CatalogDocument {
            revision: 7,
            sessions: vec![SessionDirectoryRecord {
                session_id: "thread-a".into(),
                root_agent_id: "thread-a".into(),
                workspace_id: "project-a".into(),
                title: "Root".into(),
                mode: pl_protocol::ThreadModeId::simple(),
                workspace_mode: pl_protocol::ThreadWorkspaceMode::Local,
                delegation_mode: pl_protocol::DelegationMode::Profile,
                delegation_preference: pl_protocol::DelegationPreference::Balanced,
                workspace_path: "/tmp/a".into(),
                created_at: 10,
                updated_at: 20,
                last_user_message_at: Some(15),
                archived: false,
            }],
            agents: vec![AgentDirectoryRecord {
                agent_id: "thread-a".into(),
                session_id: "thread-a".into(),
                parent_agent_id: None,
                thread_id: "thread-a".into(),
                role: "root".into(),
                title: None,
                binding: pl_protocol::AgentBinding::Native(pl_protocol::NativeAgentConfig {
                    route: None,
                    system_instructions: None,
                }),
                status: ThreadStatus::Idle,
                explicitly_closed: false,
                created_at: 10,
                updated_at: 20,
            }],
        }
    }

    #[tokio::test]
    async fn current_bytes_are_not_rewritten_and_keep_revision() {
        let dir = tempfile::tempdir().expect("temp");
        let path = dir.path().join("catalog.toml");
        let document = current_document();
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

        let session = store.get_session("thread-a").expect("session");
        let agent = store.get_agent("thread-a").expect("agent");
        store
            .upsert_session(session.clone())
            .await
            .expect("idempotent session");
        store
            .upsert_agent(agent.clone())
            .await
            .expect("idempotent agent");
        assert_eq!(store.lock().revision, 7);
        assert_eq!(
            tokio::fs::read_to_string(&path).await.expect("read"),
            encoded
        );
    }

    #[tokio::test]
    async fn v5_catalog_upgrades_atomically_and_reopens_without_rewriting() {
        let dir = tempfile::tempdir().expect("temp");
        let path = dir.path().join("catalog.toml");
        let mut document = current_document();
        document.sessions[0].archived = true;
        document.sessions[0].mode = pl_protocol::ThreadModeId::task();
        let mut child = document.agents[0].clone();
        child.agent_id = "child".into();
        child.thread_id = "child".into();
        child.parent_agent_id = Some("thread-a".into());
        child.title = Some("Saved task".into());
        child.explicitly_closed = true;
        child.status = ThreadStatus::Closing;
        child.binding = pl_protocol::AgentBinding::Native(pl_protocol::NativeAgentConfig {
            route: Some(pl_protocol::studio::NewThreadModelRoute {
                account_id: "account".into(),
                model_id: "model".into(),
                effort: Some("high".into()),
            }),
            system_instructions: None,
        });
        document.agents.push(child);
        let mut legacy: toml::Table = toml::from_str(&v5_content(&document)).unwrap();
        // The old root-only mode command did not rewrite existing child copies.
        legacy["entries"][1]["mode"] = "mode.simple".into();
        let legacy = toml::to_string(&legacy).unwrap();
        tokio::fs::write(&path, &legacy)
            .await
            .expect("legacy source");
        let store = CatalogStore::load(path.clone()).await.expect("upgrade V5");
        assert_eq!(*store.lock(), document);
        let upgraded = tokio::fs::read_to_string(&path).await.expect("upgraded");
        assert_ne!(upgraded, legacy);
        assert_eq!(
            toml::from_str::<toml::Table>(&upgraded).unwrap()["schemaVersion"].as_integer(),
            Some(6)
        );
        drop(store);
        let reopened = CatalogStore::load(path.clone()).await.expect("reopen V6");
        assert_eq!(*reopened.lock(), document);
        assert_eq!(tokio::fs::read_to_string(&path).await.unwrap(), upgraded);
    }

    #[tokio::test]
    async fn invalid_root_topologies_preserve_original_catalog() {
        let dir = tempfile::tempdir().expect("temp");
        let path = dir.path().join("catalog.toml");
        let mut extra_root = current_document();
        let mut extra = extra_root.agents[0].clone();
        extra.agent_id = "extra-root".into();
        extra.thread_id = "extra-thread".into();
        extra_root.agents.push(extra);
        let mut cross_root = current_document();
        let mut other_session = cross_root.sessions[0].clone();
        other_session.session_id = "other-session".into();
        cross_root.sessions.push(other_session);
        for raw in [
            v5_content(&extra_root),
            toml_schema::encode(&extra_root, schema::SCHEMA_KEY).unwrap(),
            toml_schema::encode(&cross_root, schema::SCHEMA_KEY).unwrap(),
        ] {
            tokio::fs::write(&path, &raw).await.unwrap();
            let error = CatalogStore::load(path.clone())
                .await
                .err()
                .expect("reject topology");
            assert!(error.is::<DocumentMigrationFailed>(), "{error:#}");
            assert_eq!(tokio::fs::read_to_string(&path).await.unwrap(), raw);
        }
    }

    #[tokio::test]
    async fn stale_child_mode_does_not_hide_workspace_ownership_conflicts() {
        let dir = tempfile::tempdir().expect("temp");
        let path = dir.path().join("catalog.toml");
        let mut document = current_document();
        let mut child = document.agents[0].clone();
        child.agent_id = "child".into();
        child.thread_id = "child".into();
        child.parent_agent_id = Some("thread-a".into());
        document.agents.push(child);
        for (field, value) in [
            ("workspaceId", "another-workspace"),
            ("workspaceMode", "worktree"),
            ("workspacePath", "/another-workspace"),
        ] {
            let mut legacy: toml::Table = toml::from_str(&v5_content(&document)).unwrap();
            legacy["entries"][1]["mode"] = "mode.task".into();
            legacy["entries"][1][field] = value.into();
            let original = toml::to_string(&legacy).unwrap();
            tokio::fs::write(&path, &original).await.unwrap();
            let failure = CatalogStore::load(path.clone())
                .await
                .err()
                .expect("reject ownership conflict");
            assert!(failure.is::<DocumentMigrationFailed>(), "{failure:#}");
            assert_eq!(tokio::fs::read_to_string(&path).await.unwrap(), original);
        }
    }

    #[tokio::test]
    async fn directory_delta_never_publishes_half_a_session_and_allows_last_deletion() {
        let dir = tempfile::tempdir().expect("temp");
        let path = dir.path().join("catalog.toml");
        let store = CatalogStore::load(path.clone()).await.unwrap();
        store.persist_if_absent().await.unwrap();
        let before = tokio::fs::read(&path).await.unwrap();
        let document = current_document();
        let partial = DirectoryDelta {
            session_upserts: document.sessions.clone(),
            ..Default::default()
        };
        assert!(store.apply_delta(partial).await.is_err());
        assert_eq!(tokio::fs::read(&path).await.unwrap(), before);
        assert!(store.sessions().is_empty());
        let complete = DirectoryDelta {
            session_upserts: document.sessions,
            agent_upserts: document.agents,
            ..Default::default()
        };
        store.apply_delta(complete.clone()).await.unwrap();
        let committed = tokio::fs::read(&path).await.unwrap();
        store.apply_delta(complete).await.unwrap();
        assert_eq!(tokio::fs::read(&path).await.unwrap(), committed);
        let reopened = CatalogStore::load(path.clone()).await.unwrap();
        assert_eq!(reopened.agents().len(), 1);
        drop(reopened);
        store
            .apply_delta(DirectoryDelta::delete_threads(vec!["thread-a".into()]))
            .await
            .unwrap();
        let empty = CatalogStore::load(path)
            .await
            .expect("legitimate empty catalog");
        assert!(empty.sessions().is_empty());
        assert!(empty.agents().is_empty());
    }

    #[tokio::test]
    async fn v2_catalog_explicit_migration_keeps_revision_and_preserves_source() {
        let dir = tempfile::tempdir().expect("temp");
        let path = dir.path().join("catalog.toml");
        let raw = "schemaVersion = 2\nrevision = 4\n\n[[entries]]\nid = \"thread-a\"\nprojectId = \"project-a\"\ntitle = \"Root\"\nmode = \"mode.simple\"\nworkspaceMode = \"local\"\nworkspacePath = \"/tmp/a\"\nrootThreadId = \"thread-a\"\nrole = \"root\"\nagentPath = \"thread-a\"\nstatus = \"idle\"\ncreatedAt = 10\nupdatedAt = 20\narchived = false\n";
        let source = dir.path().join("v2-catalog.toml");
        tokio::fs::write(&source, raw)
            .await
            .expect("write frozen v2");
        assert!(
            CatalogStore::load(source.clone()).await.is_err(),
            "ordinary reads do not accept a retired owner vocabulary"
        );
        let encoded = migrate_v2_content(&source, raw).expect("explicit ownership migration");
        assert_eq!(
            tokio::fs::read_to_string(&source)
                .await
                .expect("source bytes"),
            raw
        );
        tokio::fs::write(&path, encoded)
            .await
            .expect("publish current");
        let store = CatalogStore::load(path.clone())
            .await
            .expect("load current");
        let first = tokio::fs::read_to_string(&path).await.expect("upgraded");
        let table: toml::Table = toml::from_str(&first).expect("toml");
        assert_eq!(
            table["schemaVersion"].as_integer(),
            Some(i64::from(
                schema::current_version().expect("catalog integer version")
            ))
        );
        assert_eq!(table["revision"].as_integer(), Some(4));
        assert_eq!(table["sessions"][0]["sessionId"].as_str(), Some("thread-a"));
        assert_eq!(
            table["sessions"][0]["delegationMode"].as_str(),
            Some("profile")
        );
        assert_eq!(table["agents"][0]["agentId"].as_str(), Some("thread-a"));
        assert!(table["agents"][0].get("parentAgentId").is_none());
        assert_eq!(
            table["agents"][0]["explicitlyClosed"].as_bool(),
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
        let raw = "schemaVersion = 6\nrevision = 0\nsessions = []\nagents = []\n";
        tokio::fs::write(&path, raw).await.expect("write");
        let error = CatalogStore::load(path.clone())
            .await
            .err()
            .expect("invalid revision");
        assert!(error.is::<DocumentMigrationFailed>());
        assert_eq!(
            tokio::fs::read_to_string(&path).await.expect("unchanged"),
            raw
        );
    }

    #[tokio::test]
    async fn migration_rejects_missing_root_and_cross_session_parent() {
        let missing_root = "schemaVersion = 5\nrevision = 3\n\n[[entries]]\nid = \"thread-b\"\nworkspaceId = \"project-a\"\ntitle = \"Child\"\nmode = \"mode.simple\"\nworkspaceMode = \"local\"\ndelegationMode = \"profile\"\ndelegationPreference = \"balanced\"\nworkspacePath = \"/tmp/a\"\nparentThreadId = \"thread-a\"\nrootThreadId = \"thread-a\"\nrole = \"executor\"\nagentPath = \"thread-b\"\nstatus = \"idle\"\ncreatedAt = 11\nupdatedAt = 21\nexplicitlyClosed = false\narchived = false\n";
        let error = migrate_v2_content(std::path::Path::new("catalog.toml"), missing_root)
            .expect_err("missing root");
        let diagnostic = format!("{error:#}");
        assert!(
            diagnostic.contains("Studio catalog agent thread-b references a missing session"),
            "unexpected error: {diagnostic}"
        );

        let cross_parent = "schemaVersion = 5\nrevision = 3\n\n[[entries]]\nid = \"thread-a\"\nworkspaceId = \"project-a\"\ntitle = \"Root\"\nmode = \"mode.simple\"\nworkspaceMode = \"local\"\ndelegationMode = \"profile\"\ndelegationPreference = \"balanced\"\nworkspacePath = \"/tmp/a\"\nrootThreadId = \"thread-a\"\nrole = \"root\"\nagentPath = \"thread-a\"\nstatus = \"idle\"\ncreatedAt = 10\nupdatedAt = 20\nexplicitlyClosed = false\narchived = false\n\n[[entries]]\nid = \"thread-c\"\nworkspaceId = \"project-a\"\ntitle = \"Child\"\nmode = \"mode.simple\"\nworkspaceMode = \"local\"\ndelegationMode = \"profile\"\ndelegationPreference = \"balanced\"\nworkspacePath = \"/tmp/a\"\nparentThreadId = \"thread-x\"\nrootThreadId = \"thread-a\"\nrole = \"executor\"\nagentPath = \"thread-c\"\nstatus = \"idle\"\ncreatedAt = 12\nupdatedAt = 22\nexplicitlyClosed = false\narchived = false\n";
        let error = migrate_v2_content(std::path::Path::new("catalog.toml"), cross_parent)
            .expect_err("cross-session parent");
        let diagnostic = format!("{error:#}");
        assert!(
            diagnostic.contains("Studio catalog agent thread-c has a parent outside its session"),
            "unexpected error: {diagnostic}"
        );
    }
}
