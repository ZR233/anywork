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

pub use error::StudioDatabaseError;
impl StudioStore {
    pub(crate) fn database(&self) -> &DatabaseConnection {
        &self.db
    }

    pub(crate) fn paths(&self) -> &StudioPaths {
        &self.paths
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
    /// `connect(mode=rwc)` 刚创建文件后就把它当成损坏库。没有活跃持有者时，新打开的句柄立刻
    /// 登记进弱引用表，让并发 reader 与随后的 writer 共用同一初始化锁；最后一位持有者释放后
    /// 弱表回收，不会留下永不过期的强缓存。不存在的库继续读成空且不被创建。
    pub(crate) async fn history(&self, thread_id: &str) -> anyhow::Result<HistoryStore> {
        if let Some(shared) = self.thread_persistence.shared_history(thread_id) {
            return Ok(shared);
        }
        let opened = HistoryStore::open(
            &self.thread_storage_dir(thread_id).join("history.sqlite"),
            thread_id,
        )
        .await?;
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
        if let Some(active) = self.thread_persistence.chat_session(thread_id) {
            return Ok(active);
        }
        let session = pl_core::chat::Session::new(self.history(thread_id).await?);
        Ok(self
            .thread_persistence
            .install_chat_session(thread_id, session))
    }

    pub(crate) fn state(&self, thread_id: &str) -> StateStore {
        StateStore::new(self.thread_storage_dir(thread_id), thread_id)
            .with_legacy_calls(self.calls.clone())
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

    pub(crate) fn thread_storage_dir(&self, thread_id: &str) -> PathBuf {
        self.paths.thread_storage_dir(thread_id)
    }

    /// 新附件与迁移附件共用的每会话 blob 根（content-addressed）。
    pub(crate) fn thread_blobs_dir(&self, thread_id: &str) -> PathBuf {
        self.paths.thread_blobs_dir(thread_id)
    }

    /// Temporary attachment-draft root derived from the canonical Studio layout.
    pub(crate) fn attachment_drafts_dir(&self) -> PathBuf {
        self.paths.attachment_drafts_dir()
    }

    /// 每会话资源（工具持久化媒体等）根目录；与附件 blob 根同属一个会话目录。
    pub(crate) fn session_resources_dir(&self, thread_id: &str) -> PathBuf {
        self.thread_storage_dir(thread_id).join("thread-resources")
    }
}

// Legacy Task persistence tests were removed with the fixed Task runtime.
