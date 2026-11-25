//! 会话/成员目录：有界查询、metadata 观察与产品事件水位。
//! 索引归属 `index`，成员运行态归属 `agent_directory`，耐久命令归属 `commands`，
//! ACP 标题优先级归属 `acp_titles`。
//!
//! 目录身份是 typed 四元组（SessionId/AgentId/parent AgentId/ThreadId）；查询只
//! 从本 owner 的提交切面投影 [`SessionDirectoryRow`]，不从 Native 执行快照反推
//! 成员归属。会话级事实（标题、排序时间、归档、Mode、工作区、分发设置）唯一归属
//! 会话记录；成员关系唯一归属成员记录的 `parent_agent_id`。

use crate::{
    ResourceStamp, StudioError, StudioErrorCode, ThreadDirectoryFrame, ThreadDirectoryQuery,
    ThreadDirectoryWindow, ThreadMetadataFrame,
};
use crate::{SessionDirectoryRow, ThreadStatus};
use anyhow::{Context, Result};
use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::sync::{Arc, Mutex, Weak};
use tokio::sync::watch;

use crate::studio::records::{
    AcpDirectoryTitle, AcpPeerTitle, AcpTitleLabel, AgentDirectoryRecord, SessionDirectoryRecord,
    row_projection, thread_projection,
};
use crate::studio::store::directory::{DirectoryDelta, ThreadDirectoryCursor};
use crate::{
    StudioAgentActivity, StudioAgentDirectoryData, StudioAgentDirectoryEntry,
    StudioAgentDirectoryState, StudioProductEventEnvelope, StudioProductEventKind,
    StudioThreadDirectoryData, StudioThreadDirectoryDelta, StudioThreadDirectoryPage,
    StudioThreadDirectoryPageData, StudioThreadDirectoryState,
};

use super::ProductEventBus;
use super::topics::{TopicLease, TopicMap};

const THREAD_DIRECTORY_RESOURCE_KEY: &str = "thread-directory";

mod acp_titles;
mod agent_directory;
mod commands;
mod index;

use agent_directory::cold_native_activity;
use commands::*;
pub(in crate::studio) use index::NativeAgentObservation;
pub(super) use index::ThreadDirectoryIndex;
use index::*;

#[cfg(test)]
pub(super) mod tests;

/// A demand-scoped wakeup registration, not a metadata/version source.
pub(crate) struct ThreadMetadataSignal {
    receiver: Option<watch::Receiver<()>>,
    index: Weak<Mutex<ThreadDirectoryIndex>>,
    registration: TopicLease<String>,
}

impl ThreadMetadataSignal {
    pub(crate) fn receiver(&mut self) -> &mut watch::Receiver<()> {
        self.receiver.as_mut().expect("live metadata registration")
    }
}

impl Drop for ThreadMetadataSignal {
    fn drop(&mut self) {
        // Remove the receiver before checking the last demand under the same lock as registration.
        self.receiver.take();
        if let Some(index) = self.index.upgrade() {
            let mut index = index
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            index.metadata_signals.reclaim(&self.registration);
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct DirectoryReadMetrics {
    scanned: usize,
    materialized: usize,
}

#[derive(Debug)]
struct DirectoryRead {
    query: ThreadDirectoryQuery,
    window: ThreadDirectoryWindow,
    stamp: ResourceStamp,
    rows: Vec<SessionDirectoryRow>,
    next_cursor: Option<String>,
    updated_at: i64,
}

impl DirectoryRead {
    fn into_page(self) -> Result<StudioThreadDirectoryPage> {
        let page = StudioThreadDirectoryPage {
            state: crate::ObservedResource::ready(
                self.stamp.revision,
                self.updated_at,
                StudioThreadDirectoryPageData {
                    rows: self.rows,
                    next_cursor: self.next_cursor,
                },
            ),
        };
        ProductEventBus::check_frame_size(&page)?;
        Ok(page)
    }

    fn into_frame(self) -> ThreadDirectoryFrame {
        ThreadDirectoryFrame {
            query: self.query,
            window: self.window,
            stamp: self.stamp,
            thread_ids: self.rows.into_iter().map(|row| row.thread_id).collect(),
            next_cursor: self.next_cursor,
        }
    }
}

impl ProductEventBus {
    pub(crate) fn subscribe_thread_metadata(&self, thread_id: &str) -> ThreadMetadataSignal {
        let mut index = self
            .thread_index
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let (receiver, registration) = index.metadata_signals.subscribe(thread_id.to_owned());
        ThreadMetadataSignal {
            receiver: Some(receiver),
            index: Arc::downgrade(&self.thread_index),
            registration,
        }
    }

    pub async fn read_thread_directory(&self) -> Result<StudioThreadDirectoryState> {
        let index = self
            .thread_index
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        Ok(StudioThreadDirectoryState {
            state: self.resource(
                &self.revisions.thread,
                StudioThreadDirectoryData {
                    rows: index.sorted_active_root_rows(),
                },
            ),
        })
    }

    pub fn read_threads_window(
        &self,
        query: &ThreadDirectoryQuery,
        window: &ThreadDirectoryWindow,
        owner_epoch: &str,
    ) -> Result<ThreadDirectoryFrame> {
        let frame = self
            .read_threads_window_inner(query, window, owner_epoch)?
            .into_frame();
        Self::check_frame_size(&frame)?;
        Ok(frame)
    }

    pub fn read_thread_metadata(
        &self,
        thread_id: &str,
        owner_epoch: &str,
    ) -> Result<ThreadMetadataFrame> {
        let frame = {
            let index = self
                .thread_index
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            ThreadMetadataFrame {
                thread_id: thread_id.to_owned(),
                stamp: self.thread_stamp(owner_epoch),
                row: index
                    .directory_facts(thread_id)
                    .map(|(session, agent)| row_projection(session, agent)),
            }
        };
        Self::check_frame_size(&frame)?;
        Ok(frame)
    }

    pub(super) fn thread_stamp(&self, owner_epoch: &str) -> ResourceStamp {
        ResourceStamp {
            resource_key: THREAD_DIRECTORY_RESOURCE_KEY.into(),
            owner_epoch: owner_epoch.into(),
            revision: self.revision(&self.revisions.thread).0,
        }
    }

    pub(super) fn check_frame_size(frame: &impl serde::Serialize) -> Result<()> {
        let bytes = serde_json::to_vec(frame)?;
        if bytes.len() > ThreadDirectoryWindow::MAX_FRAME_BYTES {
            return Err(StudioError::new(
                StudioErrorCode::Overloaded,
                "Directory frame exceeds the 256 KiB delivery limit",
                false,
            )
            .into());
        }
        Ok(())
    }

    pub(super) async fn read_legacy_thread_page(
        &self,
        query: &ThreadDirectoryQuery,
        cursor: Option<&str>,
        limit: usize,
    ) -> Result<StudioThreadDirectoryPage> {
        let limit = limit.clamp(1, ThreadDirectoryWindow::MAX_LIMIT as usize) as u32;
        let read = self.read_threads_window_inner(
            query,
            &ThreadDirectoryWindow {
                before: cursor.map(str::to_owned),
                limit,
            },
            "",
        )?;
        read.into_page()
    }

    /// Legacy one-shot page entry; it uses the same current RAM owner as observations.
    pub async fn read_thread_directory_page(
        &self,
        cursor: Option<&str>,
        limit: usize,
    ) -> Result<StudioThreadDirectoryPage> {
        self.read_legacy_thread_page(&ThreadDirectoryQuery::default(), cursor, limit)
            .await
    }

    /// Legacy filtered query entry; it delegates to the same RAM query slice.
    pub async fn query_threads(
        &self,
        query: &ThreadDirectoryQuery,
        cursor: Option<&str>,
        limit: usize,
    ) -> Result<StudioThreadDirectoryPage> {
        self.read_legacy_thread_page(query, cursor, limit).await
    }

    /// Caller holds thread_index through mutation, watermark capture and synchronous dispatch.
    pub(super) fn emit_thread_delta_locked(
        &self,
        _index: &ThreadDirectoryIndex,
        upserted: Vec<SessionDirectoryRow>,
        removed: Vec<String>,
    ) -> StudioProductEventEnvelope {
        self.bump(&self.revisions.thread);
        let (revision, updated_at) = self.revision(&self.revisions.thread);
        self.emit(StudioProductEventKind::ThreadDirectoryChanged(
            StudioThreadDirectoryDelta {
                revision,
                updated_at,
                upserted,
                removed,
            },
        ))
    }

    /// Records the acceptance of a user message as a directory fact.
    ///
    /// Called only after the runtime successfully admitted a user input (queued inputs count;
    /// rejected submissions never reach this point). The timestamp never regresses, and a missing
    /// or archived entry is not reinserted. Persistence rides the same write-behind directory
    /// queue as runtime patches; a later model/storage failure cannot undo the recorded fact.
    pub(in crate::studio) fn record_user_message(&self, thread_id: &str, accepted_at: i64) {
        let mut index = self
            .thread_index
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let Some((mut session, agent)) = index
            .directory_facts(thread_id)
            .map(|(session, agent)| (session.clone(), agent.clone()))
        else {
            return;
        };
        if session.archived {
            return;
        }
        let previous = session.clone();
        session.last_user_message_at = Some(
            session
                .last_user_message_at
                .map_or(accepted_at, |existing| existing.max(accepted_at)),
        );
        session.updated_at = session.updated_at.max(accepted_at);
        if session == previous {
            return;
        }
        index.insert_session(session.clone());
        self.writer.record_directory(DirectoryDelta {
            session_upserts: vec![session.clone()],
            ..Default::default()
        });
        let row = row_projection(&session, &agent);
        self.emit_thread_delta_locked(&index, vec![row], Vec::new());
    }

    /// Reads the current metadata summary without activating a cold Thread.
    pub(crate) fn thread_snapshot(&self, thread_id: &str) -> Result<Option<crate::Thread>> {
        self.thread_index
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .thread_snapshot(thread_id)
    }

    /// 纯读目录提交切面；不激活成员，也不读取 Native history/snapshot。
    pub(crate) fn agent_execution_identity(
        &self,
        thread_id: &str,
    ) -> Option<(
        crate::AgentThreadIdentity,
        crate::AgentBinding,
        Option<crate::ThreadId>,
    )> {
        self.thread_index
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .execution_identity(thread_id)
    }

    /// Resolve a product member without activating Native resources or reading history.
    pub(crate) fn member_identity(
        &self,
        session: &crate::SessionId,
        agent: &crate::AgentId,
    ) -> Option<crate::AgentThreadIdentity> {
        let index = self
            .thread_index
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let member = index
            .sessions
            .get(session.as_str())?
            .agents
            .get(agent.as_str())?;
        index
            .execution_identity(&member.thread_id)
            .map(|(identity, _, _)| identity)
    }

    /// 当前摘要中一个 Thread 的会话/成员事实快照（目录 owner 提交切面）。
    pub(in crate::studio) fn directory_facts(
        &self,
        thread_id: &str,
    ) -> Option<(SessionDirectoryRecord, AgentDirectoryRecord)> {
        self.thread_index
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .directory_facts(thread_id)
            .map(|(session, agent)| (session.clone(), agent.clone()))
    }

    pub(in crate::studio) fn directory_member(
        &self,
        thread_id: &str,
    ) -> Result<Option<crate::studio::records::DirectoryMember>> {
        let index = self
            .thread_index
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        index
            .directory_facts(thread_id)
            .map(|(session, agent)| {
                crate::studio::records::DirectoryMember::resolve(
                    session.clone(),
                    agent.clone(),
                    |id| {
                        index
                            .sessions
                            .get(&session.session_id)?
                            .agents
                            .get(id)
                            .cloned()
                    },
                )
            })
            .transpose()
    }

    pub(in crate::studio) fn members_for_root(
        &self,
        root_thread_id: &str,
    ) -> Result<Vec<crate::studio::records::DirectoryMember>> {
        let index = self
            .thread_index
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let Some(entry) = index
            .thread_to_session
            .get(root_thread_id)
            .and_then(|id| index.sessions.get(id))
            .filter(|entry| {
                entry
                    .root_agent()
                    .is_some_and(|root| root.thread_id == root_thread_id)
            })
        else {
            return Ok(Vec::new());
        };
        entry
            .agents
            .values()
            .map(|agent| {
                crate::studio::records::DirectoryMember::resolve(
                    entry.session.clone(),
                    agent.clone(),
                    |id| entry.agents.get(id).cloned(),
                )
            })
            .collect()
    }
}

impl ProductEventBus {
    fn read_threads_window_inner(
        &self,
        query: &ThreadDirectoryQuery,
        window: &ThreadDirectoryWindow,
        owner_epoch: &str,
    ) -> Result<DirectoryRead> {
        let query = query.clone().normalized()?;
        window.validate()?;
        let before = window
            .before
            .as_deref()
            .map(|cursor| {
                ThreadDirectoryCursor::decode(cursor)
                    .ok_or_else(|| StudioError::invalid_argument("Invalid directory cursor"))
            })
            .transpose()?;
        let lock_wait_started = std::time::Instant::now();
        let index = self
            .thread_index
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let lock_acquired = std::time::Instant::now();
        let (rows, next_cursor, metrics) =
            index.query(&query, before.as_ref(), window.limit as usize);
        let (revision, updated_at) = self.revision(&self.revisions.thread);
        drop(index);
        let lock_wait_micros =
            u64::try_from(lock_acquired.duration_since(lock_wait_started).as_micros())
                .unwrap_or(u64::MAX);
        let lock_held_micros =
            u64::try_from(lock_acquired.elapsed().as_micros()).unwrap_or(u64::MAX);
        tracing::trace!(
            scanned = metrics.scanned,
            materialized = metrics.materialized,
            lock_wait_micros,
            lock_held_micros,
            "read thread directory window"
        );
        Ok(DirectoryRead {
            query,
            window: window.clone(),
            stamp: ResourceStamp {
                resource_key: THREAD_DIRECTORY_RESOURCE_KEY.into(),
                owner_epoch: owner_epoch.into(),
                revision,
            },
            rows,
            next_cursor,
            updated_at,
        })
    }
}
