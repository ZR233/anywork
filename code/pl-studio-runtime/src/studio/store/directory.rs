//! 会话/成员目录事实：内存目录 owner 提交的 delta、write-behind 落库
//! applier 与 `catalog.toml` 冷分页查询。
//!
//! 目录 mutation 一律"内存先行 + delta 异步落库"（见 design/17 §17.2）；本模块
//! 只承载已经由 owner 决定的事实，不做业务校验或状态转换。目录的会话事实与
//! 成员事实在 [`SessionDirectoryRecord`]／[`AgentDirectoryRecord`] 中各自唯一
//! 归属，父子关系只保存在成员记录的 `parent_agent_id` 中。

use anyhow::Result;
use pl_protocol::{NativeAgentConfig, ThreadModeId, ThreadWorkspaceMode};

use crate::studio::ids::unix_seconds;
use crate::studio::records::{AgentDirectoryRecord, SessionDirectoryRecord};
use crate::studio::store::StudioStore;
use crate::studio::store_support::non_empty_title;

/// 一次目录事实提交。
///
/// 由内存目录 owner（ProductEventBus 侧命令）在更新热集合同一临界区构建；
/// FIFO 队列保证注册先于该成员的首个 state commit 落库。
#[derive(Debug, Clone, Default)]
pub(in crate::studio) struct DirectoryDelta {
    pub(in crate::studio) session_upserts: Vec<SessionDirectoryRecord>,
    pub(in crate::studio) agent_upserts: Vec<AgentDirectoryRecord>,
    pub(in crate::studio) session_removals: Vec<SessionRemoval>,
    pub(in crate::studio) unregistered_faults: Vec<UnregisteredChildFault>,
    pub(in crate::studio) thread_deletions: Vec<String>,
    pub(in crate::studio) project_upserts: Vec<ProjectDirectoryRecord>,
    pub(in crate::studio) project_removals: Vec<ProjectRemoval>,
}

#[derive(Debug, Clone)]
pub(in crate::studio) struct UnregisteredChildFault {
    pub(in crate::studio) agent_id: String,
    pub(in crate::studio) state: crate::studio::records::DirectoryState,
}

impl DirectoryDelta {
    pub(in crate::studio) fn is_empty(&self) -> bool {
        self.unregistered_faults.is_empty()
            && self.session_upserts.is_empty()
            && self.agent_upserts.is_empty()
            && self.session_removals.is_empty()
            && self.thread_deletions.is_empty()
            && self.project_upserts.is_empty()
            && self.project_removals.is_empty()
    }

    /// 注册一个新会话：会话事实与主成员事实一次提交，Thread ID 原字节保留。
    #[allow(clippy::too_many_arguments)]
    pub(in crate::studio) fn register_session(
        session_id: String,
        workspace_id: &str,
        title: &str,
        mode: ThreadModeId,
        workspace_mode: ThreadWorkspaceMode,
        workspace_path: String,
        role: &str,
    ) -> (Self, SessionDirectoryRecord, AgentDirectoryRecord) {
        let now = unix_seconds();
        let session = SessionDirectoryRecord {
            session_id: session_id.clone(),
            root_agent_id: session_id.clone(),
            workspace_id: workspace_id.to_string(),
            title: non_empty_title(title),
            native_mode: Some(mode),
            workspace_mode,
            delegation_mode: Default::default(),
            delegation_preference: Default::default(),
            workspace_path,
            created_at: now,
            updated_at: now,
            last_user_message_at: None,
            archived: false,
        };
        let agent = AgentDirectoryRecord {
            agent_id: session_id.clone(),
            session_id: session_id.clone(),
            parent_agent_id: None,
            thread_id: session_id,
            role: role.to_string(),
            title: None,
            backend: pl_protocol::session::AgentBackend::Native {
                config: NativeAgentConfig {
                    route: None,
                    system_instructions: None,
                },
                status: pl_protocol::ThreadStatus::Idle,
            },
            explicitly_closed: false,
            created_at: now,
            updated_at: now,
        };
        (
            Self {
                session_upserts: vec![session.clone()],
                agent_upserts: vec![agent.clone()],
                ..Default::default()
            },
            session,
            agent,
        )
    }

    /// 注册一个 durable child 成员（executor/reviewer/explorer spawn）。
    pub(in crate::studio) fn register_child_agent(spec: RegisteredChildAgent) -> Self {
        let now = unix_seconds();
        Self {
            agent_upserts: vec![AgentDirectoryRecord {
                agent_id: spec.agent_id.clone(),
                session_id: spec.session_id,
                parent_agent_id: Some(spec.parent_agent_id),
                thread_id: spec.agent_id,
                role: spec.role,
                title: Some(non_empty_title(&spec.title)),
                backend: pl_protocol::session::AgentBackend::Native {
                    config: NativeAgentConfig {
                        route: spec.frozen_model,
                        system_instructions: None,
                    },
                    status: pl_protocol::ThreadStatus::Idle,
                },
                explicitly_closed: false,
                created_at: now,
                updated_at: now,
            }],
            ..Default::default()
        }
    }

    /// 归档若干会话树（调用方已确定全部会话 ID；成员归档事实随会话派生）。
    pub(in crate::studio) fn archive_sessions(session_ids: Vec<String>) -> Self {
        Self {
            session_removals: vec![SessionRemoval {
                session_ids,
                archived_at: unix_seconds(),
            }],
            ..Default::default()
        }
    }

    pub(in crate::studio) fn delete_threads(thread_ids: Vec<String>) -> Self {
        Self {
            thread_deletions: thread_ids,
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

/// child 成员注册事实；父成员与会话的目录事实由调用方（agent host）提供。
#[derive(Debug, Clone)]
pub(in crate::studio) struct RegisteredChildAgent {
    pub(in crate::studio) agent_id: String,
    pub(in crate::studio) parent_agent_id: String,
    pub(in crate::studio) session_id: String,
    pub(in crate::studio) role: String,
    pub(in crate::studio) title: String,
    pub(in crate::studio) frozen_model: Option<pl_protocol::studio::NewThreadModelRoute>,
}

#[derive(Debug, Clone)]
pub(in crate::studio) struct SessionRemoval {
    pub(in crate::studio) session_ids: Vec<String>,
    pub(in crate::studio) archived_at: i64,
}

#[derive(Debug, Clone)]
pub(in crate::studio) struct ProjectRemoval {
    pub(in crate::studio) workspace_id: String,
    pub(in crate::studio) session_ids: Vec<String>,
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
/// 同一 delta 经 [`StudioStore::persist_directory_summaries`] 幂等写入 canonical
/// TOML（`catalog.toml` + `workspaces.toml`）。write-behind 批次因此成为目录摘要的
/// 异步持久化点：观察热路径只把状态摘要并入队列，文件 I/O 由 writer 完成；命令通道已同步写入的
/// delta 在此重放为 no-op，不推进 revision。
pub(in crate::studio) async fn apply_directory_delta(
    store: &StudioStore,
    tx: &sea_orm::DatabaseTransaction,
    delta: &DirectoryDelta,
) -> Result<()> {
    store.persist_directory_summaries_on(delta, tx).await
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
        if id.trim().is_empty() {
            return None;
        }
        Some(Self {
            sort_time: sort_time.parse().ok()?,
            id: id.to_string(),
        })
    }
}
