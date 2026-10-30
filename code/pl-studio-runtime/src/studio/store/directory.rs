//! Thread/Project 目录事实：内存目录 owner 提交的 delta、write-behind 落库
//! applier 与 `catalog.toml` 冷分页查询。
//!
//! 目录 mutation 一律"内存先行 + delta 异步落库"（见 design/17 §17.2）；本模块
//! 只承载已经由 owner 决定的事实，不做业务校验或状态转换。SQLite `thread`/`project`
//! 表是 write-behind 镜像，冷分页/搜索/归档范围只从 `catalog.toml` 读取。

use anyhow::Result;
use pl_protocol::{Thread, ThreadModeId, ThreadWorkspaceMode};

use crate::studio::ids::unix_seconds;
use crate::studio::store::StudioStore;
use crate::studio::store_support::non_empty_title;

/// 一次目录事实提交。
///
/// 由内存目录 owner（ProductEventBus 侧命令）在更新热集合同一临界区构建；
/// FIFO 队列保证 `thread_upserts` 的注册先于该 Thread 的首个 state commit 落库。
#[derive(Debug, Clone, Default)]
pub(in crate::studio) struct DirectoryDelta {
    pub(in crate::studio) session_activity: Vec<(String, i64)>,
    pub(in crate::studio) session_registrations: Vec<String>,
    pub(in crate::studio) thread_upserts: Vec<Thread>,
    pub(in crate::studio) unregistered_faults: Vec<UnregisteredChildFault>,
    pub(in crate::studio) thread_removals: Vec<ThreadRemoval>,
    pub(in crate::studio) project_upserts: Vec<ProjectDirectoryRecord>,
    pub(in crate::studio) project_removals: Vec<ProjectRemoval>,
}

#[derive(Debug, Clone)]
pub(in crate::studio) struct UnregisteredChildFault {
    pub thread_id: String,
    pub state: crate::studio::records::DirectoryState,
}

impl DirectoryDelta {
    pub(in crate::studio) fn is_empty(&self) -> bool {
        self.unregistered_faults.is_empty()
            && self.session_registrations.is_empty()
            && self.session_activity.is_empty()
            && self.thread_upserts.is_empty()
            && self.thread_removals.is_empty()
            && self.project_upserts.is_empty()
            && self.project_removals.is_empty()
    }

    pub(in crate::studio) fn register_root_thread(
        id: String,
        workspace_id: &str,
        title: &str,
        mode: ThreadModeId,
        workspace_mode: ThreadWorkspaceMode,
        workspace_path: String,
    ) -> (Self, Thread) {
        let now = unix_seconds();
        let thread = Thread {
            root_thread_id: id.clone(),
            agent_path: id.clone(),
            id,
            workspace_id: workspace_id.to_string(),
            title: non_empty_title(title),
            mode: mode.clone(),
            workspace_mode,
            delegation_mode: Default::default(),
            delegation_preference: Default::default(),
            frozen_model: None,
            workspace_path,
            parent_thread_id: None,
            role: crate::config::ROOT_AGENT_ROUTE_KEY.to_string(),
            status: pl_protocol::ThreadStatus::Idle,
            created_at: now,
            updated_at: now,
            last_user_message_at: None,
            archived: false,
        };
        (
            Self {
                thread_upserts: vec![thread.clone()],
                ..Default::default()
            },
            thread,
        )
    }

    /// 注册一个 durable child Thread（executor/reviewer/explorer spawn）。
    pub(in crate::studio) fn register_child_thread(spec: RegisteredChildThread) -> Self {
        let now = unix_seconds();
        Self {
            thread_upserts: vec![Thread {
                agent_path: spec.agent_path,
                id: spec.id,
                workspace_id: spec.workspace_id,
                title: non_empty_title(&spec.title),
                mode: spec.mode,
                workspace_mode: spec.workspace_mode,
                delegation_mode: spec.delegation.mode,
                delegation_preference: spec.delegation.preference,
                frozen_model: spec.frozen_model,
                workspace_path: spec.workspace_path,
                root_thread_id: spec.root_thread_id,
                parent_thread_id: Some(spec.parent_thread_id),
                role: spec.role,
                status: pl_protocol::ThreadStatus::Idle,
                created_at: now,
                updated_at: now,
                last_user_message_at: None,
                archived: false,
            }],
            ..Default::default()
        }
    }

    /// 归档一棵 Thread 树（调用方已确定全部成员 id）。
    pub(in crate::studio) fn archive_threads(thread_ids: Vec<String>) -> Self {
        Self {
            thread_removals: vec![ThreadRemoval {
                thread_ids,
                archived_at: unix_seconds(),
            }],
            ..Default::default()
        }
    }

    pub(in crate::studio) fn upsert_project(record: ProjectDirectoryRecord) -> Self {
        Self {
            project_upserts: vec![record],
            ..Default::default()
        }
    }
}

/// child Thread 注册事实；父 Thread 的目录事实由调用方（agent host）提供。
#[derive(Debug, Clone)]
pub(in crate::studio) struct RegisteredChildThread {
    pub(in crate::studio) delegation: pl_protocol::DelegationSettings,
    pub(in crate::studio) frozen_model: Option<pl_protocol::studio::NewThreadModelRoute>,
    pub(in crate::studio) id: String,
    pub(in crate::studio) parent_thread_id: String,
    pub(in crate::studio) agent_path: String,
    pub(in crate::studio) workspace_id: String,
    pub(in crate::studio) root_thread_id: String,
    pub(in crate::studio) mode: ThreadModeId,
    pub(in crate::studio) workspace_mode: ThreadWorkspaceMode,
    pub(in crate::studio) workspace_path: String,
    pub(in crate::studio) role: String,
    pub(in crate::studio) title: String,
}

#[derive(Debug, Clone)]
pub(in crate::studio) struct ThreadRemoval {
    pub(in crate::studio) thread_ids: Vec<String>,
    pub(in crate::studio) archived_at: i64,
}

#[derive(Debug, Clone)]
pub(in crate::studio) struct ProjectRemoval {
    pub(in crate::studio) workspace_id: String,
    pub(in crate::studio) thread_ids: Vec<String>,
    pub(in crate::studio) closed_at: i64,
}

/// Project 目录行事实；插入时需要完整列，更新时只改目录列。
#[derive(Debug, Clone)]
pub(in crate::studio) struct ProjectDirectoryRecord {
    pub(in crate::studio) id: String,
    pub(in crate::studio) kind: pl_protocol::studio::WorkspaceKind,
    pub(in crate::studio) name: String,
    pub(in crate::studio) path: String,
    pub(in crate::studio) ssh_alias: Option<String>,
    pub(in crate::studio) created_at: i64,
    pub(in crate::studio) updated_at: i64,
    pub(in crate::studio) last_opened_at: Option<i64>,
    pub(in crate::studio) closed: bool,
}

/// 在 writer 已开启的事务中幂等应用一次目录 delta。
///
/// 除 SQLite 目录镜像外，同一 delta 也经 [`StudioStore::persist_directory_summaries`] 幂等写入
/// canonical TOML（`catalog.toml` + `workspaces.toml`）。write-behind 批次因此成为目录摘要的
/// 异步持久化点：观察热路径只把状态摘要并入队列，文件 I/O 由 writer 完成；命令通道已同步写入的
/// delta 在此重放为 no-op，不推进 revision。
pub(in crate::studio) async fn apply_directory_delta(
    store: &StudioStore,
    tx: &sea_orm::DatabaseTransaction,
    delta: &DirectoryDelta,
) -> Result<()> {
    let _ = tx;
    store.persist_directory_summaries(delta).await
}

/// Thread 目录 keyset 分页游标：`v2:{sort_time}:{id}`。
///
/// `sort_time` 是 `(last_user_message_at ?? created_at)` 目录排序键。排序键语义与
/// v1（普通更新时间）不同，因此使用独立版本：旧 `v1:` 游标解码为 `None` 并回到
/// 首页重新读取，不会被解释成新排序键。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(in crate::studio) struct ThreadDirectoryCursor {
    pub(in crate::studio) sort_time: i64,
    pub(in crate::studio) id: String,
}

impl ThreadDirectoryCursor {
    pub(in crate::studio) fn encode(&self) -> String {
        format!("v2:{}:{}", self.sort_time, self.id)
    }

    pub(in crate::studio) fn decode(raw: &str) -> Option<Self> {
        let rest = raw.strip_prefix("v2:")?;
        let (sort_time, id) = rest.split_once(':')?;
        Some(Self {
            sort_time: sort_time.parse().ok()?,
            id: id.to_string(),
        })
    }
}

impl StudioStore {
    /// 未归档 Thread 的冷分页：按 `(last_user_message_at ?? created_at, id)` 倒序
    /// keyset，cursor 为闭区间锚点（下一页取严格小于该键的条目）。
    pub(in crate::studio) async fn list_thread_directory_page(
        &self,
        cursor: Option<&ThreadDirectoryCursor>,
        limit: usize,
    ) -> Result<Vec<Thread>> {
        // `catalog.toml` is the only cold source for the first screen; no session state is read.
        self.catalog_page_active(cursor, limit).await
    }
}
