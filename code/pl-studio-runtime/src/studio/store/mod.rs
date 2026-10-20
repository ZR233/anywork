use sea_orm::DatabaseConnection;
use std::path::PathBuf;

use crate::studio::paths::StudioPaths;
use crate::studio::storage::coordinator::ThreadPersistenceCoordinator;
use crate::studio::storage::history::HistoryStore;
use crate::studio::storage::{calls::CallsStore, state::StateStore};

mod agent_framework;
pub(crate) mod attachment;
pub(in crate::studio) mod catalog;
pub(in crate::studio) mod directory;
mod error;
mod interaction;
pub(in crate::studio) mod object;
mod project;
pub(in crate::studio) mod session_layout;
pub(in crate::studio) mod settings;
mod thread;
pub(in crate::studio) mod workspaces;

#[derive(Clone)]
pub struct StudioStore {
    db: DatabaseConnection,
    calls: CallsStore,
    catalog: crate::studio::catalog::CatalogStore,
    settings: settings::SettingsStore,
    workspaces: workspaces::WorkspaceStore,
    thread_persistence: ThreadPersistenceCoordinator,
    attachment_lock: std::sync::Arc<tokio::sync::Mutex<()>>,
    paths: StudioPaths,
}

pub use error::{SessionLayoutMigrationFailed, StudioDatabaseError};
impl StudioStore {
    pub(crate) fn database(&self) -> &DatabaseConnection {
        &self.db
    }

    /// 轻量会话目录摘要事实源；首屏/分页/搜索只读取这里。
    pub(in crate::studio) fn catalog(&self) -> &crate::studio::catalog::CatalogStore {
        &self.catalog
    }

    pub(in crate::studio) fn settings_store(&self) -> &settings::SettingsStore {
        &self.settings
    }

    /// 打开一个 Thread 的 history 句柄。
    ///
    /// 冷读（分页、按身份读条目、Turn 页）只读打开**已存在**的库并校验 schema、Thread 与
    /// 数据库身份，绝不创建目录/数据库或执行 schema 变更；只有显式写入（历史 writer 的
    /// commit/reserve 或迁移 export）才会创建并升级它。打开句柄本身不做 IO，用完即随句柄释放，
    /// 因此不存在无界连接缓存，也不会在启动时 eager 建库。
    ///
    /// 该 Thread 已有活跃 writer 持有者时返回**同一个**权威句柄：reader 与 writer 复用同一份
    /// 数据库身份与初始化状态，冷读会等待本句柄 writer 完成建表与 identity meta，而不是在新库
    /// `connect(mode=rwc)` 刚创建文件后就把它当成损坏库。没有活跃持有者时仍返回新的只读句柄，
    /// 不存在的库继续读成空且不被创建。
    pub(crate) async fn history(&self, thread_id: &str) -> anyhow::Result<HistoryStore> {
        if let Some(shared) = self.thread_persistence.shared_history(thread_id) {
            return Ok(shared);
        }
        HistoryStore::open(
            &self.registered_session_paths(thread_id)?.history_database(),
            thread_id,
        )
        .await
    }

    /// Explicit Project + Thread history handle for tests and child prepare before catalog
    /// publication. Cold reads still do not create the database file.
    pub(crate) async fn history_for(
        &self,
        project_id: &str,
        thread_id: &str,
    ) -> anyhow::Result<HistoryStore> {
        if let Some(shared) = self.thread_persistence.shared_history(thread_id) {
            return Ok(shared);
        }
        HistoryStore::open(
            &self
                .session_paths(project_id, thread_id)?
                .history_database(),
            thread_id,
        )
        .await
    }

    /// 该 Thread 的唯一有序历史写者句柄（没有活跃持有者时登记一个新的）。
    ///
    /// effect commit 与实时订阅的 ordinal 预留都必须经由这一个句柄，同一 `history.sqlite` 才不会
    /// 出现两条各自独立的 SQLite writer 互抢写锁。句柄只在真正的持有者（sink、订阅）存活期间存在，
    /// 因此关闭/淘汰 Thread 会释放连接，而不是留下永不失效的强引用缓存；重复打开而未登记的句柄
    /// 只绑定了路径（`HistoryStore::open` 不做 IO），不会产生第二条连接。
    pub(crate) async fn history_writer(&self, thread_id: &str) -> anyhow::Result<HistoryStore> {
        if let Some(shared) = self.thread_persistence.shared_history(thread_id) {
            return Ok(shared);
        }
        let opened = self.history(thread_id).await?;
        Ok(self
            .thread_persistence
            .install_shared_history(thread_id, &opened))
    }

    pub(crate) async fn history_writer_for(
        &self,
        project_id: &str,
        thread_id: &str,
    ) -> anyhow::Result<HistoryStore> {
        if let Some(shared) = self.thread_persistence.shared_history(thread_id) {
            return Ok(shared);
        }
        let opened = self.history_for(project_id, thread_id).await?;
        Ok(self
            .thread_persistence
            .install_shared_history(thread_id, &opened))
    }

    /// One session per live Thread, shared by the writer and every content reader.
    /// Opening a cold view does not activate a Thread or create a database file.
    pub(crate) async fn chat_session(
        &self,
        thread_id: &str,
    ) -> anyhow::Result<pl_core::chat::Session> {
        let session = self.registered_session_paths(thread_id)?;
        self.chat_session_for(session.project_id(), thread_id).await
    }

    pub(crate) async fn chat_session_for(
        &self,
        project_id: &str,
        thread_id: &str,
    ) -> anyhow::Result<pl_core::chat::Session> {
        if let Some(active) = self.thread_persistence.chat_session(thread_id) {
            return Ok(active);
        }
        let session =
            pl_core::chat::Session::new(self.history_writer_for(project_id, thread_id).await?);
        Ok(self
            .thread_persistence
            .install_chat_session(thread_id, session))
    }

    pub(crate) fn state_for(
        &self,
        project_id: &str,
        thread_id: &str,
    ) -> anyhow::Result<StateStore> {
        Ok(StateStore::new(
            self.session_paths(project_id, thread_id)?
                .root()
                .to_path_buf(),
            thread_id,
        )
        .with_legacy_calls(self.calls.clone()))
    }

    pub(crate) fn calls(&self) -> &CallsStore {
        &self.calls
    }

    pub(crate) fn thread_persistence(&self) -> &ThreadPersistenceCoordinator {
        &self.thread_persistence
    }

    pub(super) fn attachment_lock(&self) -> &tokio::sync::Mutex<()> {
        &self.attachment_lock
    }

    pub(crate) fn thread_storage_dir(&self, thread_id: &str) -> anyhow::Result<PathBuf> {
        Ok(self
            .registered_session_paths(thread_id)?
            .root()
            .to_path_buf())
    }

    /// 新附件与迁移附件共用的每会话 blob 根（content-addressed）。
    pub(crate) fn thread_blobs_dir(&self, thread_id: &str) -> anyhow::Result<PathBuf> {
        Ok(self.registered_session_paths(thread_id)?.blobs_dir())
    }

    /// Temporary attachment-draft root derived from the canonical Studio layout.
    pub(crate) fn attachment_drafts_dir(&self) -> PathBuf {
        self.paths.attachment_drafts_dir()
    }

    /// 每会话资源（工具持久化媒体等）根目录；与附件 blob 根同属一个会话目录。
    pub(crate) fn session_resources_dir(&self, thread_id: &str) -> anyhow::Result<PathBuf> {
        Ok(self.thread_storage_dir(thread_id)?.join("thread-resources"))
    }

    pub(crate) fn session_resources_dir_for(
        &self,
        project_id: &str,
        thread_id: &str,
    ) -> anyhow::Result<PathBuf> {
        Ok(self.session_paths(project_id, thread_id)?.resources_dir())
    }

    pub(crate) fn session_scratch_dir_for(
        &self,
        project_id: &str,
        thread_id: &str,
    ) -> anyhow::Result<PathBuf> {
        Ok(self.session_paths(project_id, thread_id)?.scratch_dir())
    }
}

// Legacy Task persistence tests were removed with the fixed Task runtime.
