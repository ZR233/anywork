//! Thread 目录：唯一内存摘要、查询窗口与目录事实提交。

use anyhow::Result;
use pl_protocol::Thread;
use pl_protocol::studio::{
    ResourceStamp, StudioError, StudioErrorCode, ThreadDirectoryFrame, ThreadDirectoryQuery,
    ThreadDirectoryWindow, ThreadMetadataFrame,
};
use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};

#[cfg(test)]
pub(super) mod tests;

use crate::studio::store::directory::{
    DirectoryDelta, RegisteredChildThread, ThreadDirectoryCursor,
};
use crate::{
    StudioProductEventEnvelope, StudioProductEventKind, StudioThreadDirectoryData,
    StudioThreadDirectoryDelta, StudioThreadDirectoryPage, StudioThreadDirectoryPageData,
    StudioThreadDirectoryState,
};

use super::ProductEventBus;

const THREAD_DIRECTORY_RESOURCE_KEY: &str = "thread-directory";

pub(super) struct ThreadDirectoryIndex {
    rows: HashMap<String, Thread>,
    order: BTreeSet<(i64, String)>,
    projects: HashMap<String, String>,
    explicitly_closed: HashSet<String>,
}

impl ThreadDirectoryIndex {
    pub(super) fn new(
        threads: Vec<Thread>,
        projects: &[crate::WorkspaceRecord],
    ) -> ThreadDirectoryIndex {
        let mut index = Self {
            rows: HashMap::new(),
            order: BTreeSet::new(),
            projects: HashMap::new(),
            explicitly_closed: HashSet::new(),
        };
        for thread in threads {
            if matches!(
                thread.status,
                pl_protocol::ThreadStatus::Closing | pl_protocol::ThreadStatus::Closed
            ) {
                index.explicitly_closed.insert(thread.id.clone());
            }
            index.insert(thread);
        }
        index.update_projects(projects, &[]);
        index
    }

    fn insert(&mut self, thread: Thread) -> Option<Thread> {
        let id = thread.id.clone();
        let previous = self.rows.remove(&id);
        if let Some(previous) = &previous {
            self.order
                .remove(&(previous.directory_sort_time(), id.clone()));
        }
        self.order
            .insert((thread.directory_sort_time(), id.clone()));
        self.rows.insert(id, thread);
        previous
    }

    fn remove(&mut self, id: &str) -> Option<Thread> {
        let previous = self.rows.remove(id)?;
        self.explicitly_closed.remove(id);
        self.order
            .remove(&(previous.directory_sort_time(), id.to_owned()));
        Some(previous)
    }

    fn get(&self, id: &str) -> Option<&Thread> {
        self.rows.get(id)
    }

    pub(super) fn update_projects(
        &mut self,
        upserted: &[crate::WorkspaceRecord],
        _removed: &[crate::studio::store::directory::ProjectRemoval],
    ) {
        for project in upserted {
            self.projects.insert(
                project.id.clone(),
                format!("{} {}", project.name, project.path).to_lowercase(),
            );
        }
    }

    fn sorted_active_roots(&self) -> Vec<Thread> {
        self.order
            .iter()
            .rev()
            .filter_map(|(_, id)| self.rows.get(id))
            .filter(|thread| !thread.archived && thread.parent_thread_id.is_none())
            .cloned()
            .collect()
    }

    fn query(
        &self,
        query: &ThreadDirectoryQuery,
        before: Option<&ThreadDirectoryCursor>,
        limit: usize,
    ) -> (Vec<Thread>, Option<String>, DirectoryReadMetrics) {
        let boundary = before.map(|cursor| (cursor.sort_time, cursor.id.clone()));
        let search = query
            .search
            .as_deref()
            .map(str::trim)
            .unwrap_or_default()
            .to_lowercase();
        let mut threads = Vec::with_capacity(limit.saturating_add(1));
        let mut scanned = 0;
        let mut visit = |(_, id): &(i64, String)| {
            let thread = self.rows.get(id).expect("directory order references row");
            scanned += 1;
            let project_matches = query.search.is_some()
                && self
                    .projects
                    .get(&thread.workspace_id)
                    .is_some_and(|project| project.contains(&search));
            if query.matches(thread, project_matches) {
                threads.push(thread.clone());
                if threads.len() > limit {
                    return false;
                }
            }
            true
        };
        // A fixed ID group has at most the configured pin budget. Sort only its
        // ID keys instead of scanning the whole directory to find those rows.
        let included = query.thread_ids.as_ref().map(|ids| {
            ids.iter()
                .filter_map(|id| self.rows.get(id))
                .map(|thread| (thread.directory_sort_time(), thread.id.clone()))
                .collect::<BTreeSet<_>>()
        });
        let order = included.as_ref().unwrap_or(&self.order);
        if let Some(boundary) = boundary.as_ref() {
            for key in order.range(..boundary.clone()).rev() {
                if !visit(key) {
                    break;
                }
            }
        } else {
            for key in order.iter().rev() {
                if !visit(key) {
                    break;
                }
            }
        }
        let materialized = threads.len();
        let has_more = materialized > limit;
        threads.truncate(limit);
        let next_cursor = has_more
            .then(|| threads.last())
            .flatten()
            .map(|thread| ThreadDirectoryCursor {
                sort_time: thread.directory_sort_time(),
                id: thread.id.clone(),
            })
            .map(|cursor| cursor.encode());
        (
            threads,
            next_cursor,
            DirectoryReadMetrics {
                scanned,
                materialized,
            },
        )
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct DirectoryReadMetrics {
    scanned: usize,
    materialized: usize,
}

struct DirectoryRead {
    frame: ThreadDirectoryFrame,
    updated_at: i64,
    #[cfg(test)]
    metrics: DirectoryReadMetrics,
}

fn rebase_command_thread(mut current: Thread, requested: &Thread, baseline: &Thread) -> Thread {
    debug_assert_eq!(current.id, requested.id);
    debug_assert_eq!(baseline.id, requested.id);
    macro_rules! command_field {
        ($field:ident) => {
            if requested.$field != baseline.$field {
                current.$field = requested.$field.clone();
            }
        };
    }
    command_field!(workspace_id);
    command_field!(title);
    command_field!(mode);
    command_field!(workspace_mode);
    command_field!(delegation_mode);
    command_field!(delegation_preference);
    command_field!(frozen_model);
    command_field!(workspace_path);
    command_field!(parent_thread_id);
    command_field!(root_thread_id);
    command_field!(role);
    command_field!(agent_path);
    command_field!(status);
    command_field!(created_at);
    command_field!(archived);
    current.updated_at = current.updated_at.max(requested.updated_at);
    current.last_user_message_at = current
        .last_user_message_at
        .max(requested.last_user_message_at);
    current
}

impl ProductEventBus {
    pub(in crate::studio) async fn record_attachments(
        &self,
        records: Vec<crate::studio::AttachmentRecord>,
    ) -> Result<()> {
        self.store.record_attachments(records).await
    }

    pub async fn read_thread_directory(&self) -> Result<StudioThreadDirectoryState> {
        let index = self
            .thread_index
            .lock()
            .expect("thread index lock poisoned");
        Ok(StudioThreadDirectoryState {
            state: self.resource(
                &self.revisions.thread,
                StudioThreadDirectoryData {
                    threads: index.sorted_active_roots(),
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
        let read = self.read_threads_window_inner(query, window, owner_epoch)?;
        Self::check_frame_size(&read.frame)?;
        Ok(read.frame)
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
                .expect("thread index lock poisoned");
            ThreadMetadataFrame {
                thread_id: thread_id.to_owned(),
                stamp: self.thread_stamp(owner_epoch),
                thread: index.get(thread_id).cloned(),
            }
        };
        Self::check_frame_size(&frame)?;
        Ok(frame)
    }

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
            .expect("thread index lock poisoned");
        let lock_acquired = std::time::Instant::now();
        let (threads, next_cursor, metrics) =
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
            frame: ThreadDirectoryFrame {
                query,
                window: window.clone(),
                stamp: ResourceStamp {
                    resource_key: THREAD_DIRECTORY_RESOURCE_KEY.into(),
                    owner_epoch: owner_epoch.into(),
                    revision,
                },
                threads,
                next_cursor,
            },
            updated_at,
            #[cfg(test)]
            metrics,
        })
    }

    fn thread_stamp(&self, owner_epoch: &str) -> ResourceStamp {
        ResourceStamp {
            resource_key: THREAD_DIRECTORY_RESOURCE_KEY.into(),
            owner_epoch: owner_epoch.into(),
            revision: self.revision(&self.revisions.thread).0,
        }
    }

    fn check_frame_size(frame: &impl serde::Serialize) -> Result<()> {
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

    async fn read_legacy_thread_page(
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
        Self::check_frame_size(&read.frame)?;
        #[cfg(test)]
        tests::pause(&self.directory_test_pauses.page_captured).await;
        Ok(StudioThreadDirectoryPage {
            state: pl_protocol::ObservedResource::ready(
                read.frame.stamp.revision,
                read.updated_at,
                StudioThreadDirectoryPageData {
                    threads: read.frame.threads,
                    next_cursor: read.frame.next_cursor,
                },
            ),
        })
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

    /// 应用一次目录增量并发布 `ThreadDirectoryChanged` 事件（纯内存维护）。
    pub async fn apply_thread_delta(
        &self,
        upserted: Vec<Thread>,
        removed: Vec<String>,
    ) -> Result<StudioProductEventEnvelope> {
        Ok(self.publish_thread_delta(upserted, removed, Vec::new()))
    }

    fn publish_thread_delta(
        &self,
        upserted: Vec<Thread>,
        removed: Vec<String>,
        archived: Vec<Thread>,
    ) -> StudioProductEventEnvelope {
        let mut index = self
            .thread_index
            .lock()
            .expect("thread index lock poisoned");
        self.publish_thread_delta_locked(&mut index, upserted, removed, archived)
    }

    fn publish_thread_delta_locked(
        &self,
        index: &mut ThreadDirectoryIndex,
        mut upserted: Vec<Thread>,
        removed: Vec<String>,
        archived: Vec<Thread>,
    ) -> StudioProductEventEnvelope {
        for thread in &mut upserted {
            Self::apply_explicit_close(index, thread);
            // 迟到快照不得使最近用户消息时间回退：目录命令携带的完整 Thread 可能
            // 早于一次已受理的用户输入，进入当前摘要前保留较新值。
            if let Some(existing) = index.get(&thread.id) {
                thread.last_user_message_at = existing
                    .last_user_message_at
                    .max(thread.last_user_message_at);
            }
            index.insert(thread.clone());
        }
        for id in &removed {
            index.remove(id);
        }
        for thread in archived {
            index.insert(thread);
        }
        self.prepare_child_interaction_directory(&upserted);
        self.remove_child_interaction_directory(&removed);
        // State and tombstones are visible before observers receive removal.
        self.emit_thread_delta_locked(index, upserted, removed)
    }

    fn apply_explicit_close(index: &ThreadDirectoryIndex, thread: &mut Thread) {
        if index.explicitly_closed.contains(&thread.id) {
            thread.status = if index
                .get(&thread.id)
                .is_some_and(|row| row.status == pl_protocol::ThreadStatus::Closed)
            {
                pl_protocol::ThreadStatus::Closed
            } else {
                crate::studio::agent_close::directory_status(thread.status, true)
            };
        }
    }

    /// Publish the durable close intent into this same current-metadata boundary.
    pub(in crate::studio) async fn commit_explicit_close(&self, thread_id: &str) -> Result<()> {
        let _command = self.directory_commands.lock().await;
        self.store
            .catalog()
            .project_explicit_close(thread_id)
            .await?;
        let mut index = self
            .thread_index
            .lock()
            .expect("thread index lock poisoned");
        let Some(mut thread) = index.get(thread_id).cloned() else {
            return Err(StudioError::not_found("session").into());
        };
        let newly_closed = index.explicitly_closed.insert(thread_id.to_owned());
        let previous_status = thread.status;
        Self::apply_explicit_close(&index, &mut thread);
        if !newly_closed && previous_status == thread.status {
            return Ok(());
        }
        index.insert(thread.clone());
        self.writer.record_directory(DirectoryDelta {
            thread_upserts: vec![thread.clone()],
            ..Default::default()
        });
        self.emit_thread_delta_locked(&index, vec![thread], vec![]);
        Ok(())
    }

    /// Caller holds thread_index through mutation, watermark capture and synchronous dispatch.
    fn emit_thread_delta_locked(
        &self,
        _index: &ThreadDirectoryIndex,
        upserted: Vec<Thread>,
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

    /// Applies only runtime-owned fields to the current directory summary.
    /// Missing or archived entries are never reinserted by a delayed observation.
    pub(in crate::studio) fn patch_thread_runtime(
        &self,
        thread_id: &str,
        status: pl_protocol::ThreadStatus,
        committed_at: i64,
        snapshot: &pl_core::thread::ThreadSnapshot,
    ) -> Result<Option<Thread>> {
        let delegation = crate::studio::delegation::saved(snapshot)?;
        let frozen_profile = crate::studio::model_route::saved_profile(snapshot)?;
        let explicitly_closed = crate::studio::agent_close::is_explicitly_closed(snapshot)?;
        let mut index = self
            .thread_index
            .lock()
            .expect("thread index lock poisoned");
        let Some(mut thread) = index.get(thread_id).cloned() else {
            return Ok(None);
        };
        if thread.archived {
            return Ok(None);
        }
        if let Some((profile, _)) = &frozen_profile {
            anyhow::ensure!(
                thread.parent_thread_id.is_some() && profile.profile_id == thread.role,
                "frozen Profile conflicts with directory identity"
            );
        }
        if let Some(delegation) = delegation {
            thread.delegation_mode = delegation.mode;
            thread.delegation_preference = delegation.preference;
        }
        if let Some((profile, _)) = frozen_profile {
            thread.frozen_model = Some(crate::studio::delegation::profile_model(&profile));
        }
        if explicitly_closed {
            index.explicitly_closed.insert(thread_id.to_owned());
        }
        thread.status = status;
        Self::apply_explicit_close(&index, &mut thread);
        thread.updated_at = thread.updated_at.max(committed_at);
        index.insert(thread.clone());
        // 状态观察是目录事实：只把有界摘要并入 write-behind 目录队列，不在观察热路径做文件 I/O。
        // 同 Thread 的连续 delta 由队列合并；write-behind 批次经 `apply_directory_delta` 把摘要
        // 幂等写入 catalog/workspaces TOML。调用方在发布后用固定目标 ticket（`flush_through`）
        // 建立保存屏障；状态错误不回滚已提交的内存目录事实。
        self.writer.record_directory(DirectoryDelta {
            thread_upserts: vec![thread.clone()],
            ..Default::default()
        });
        self.emit_thread_delta_locked(&index, vec![thread.clone()], Vec::new());
        Ok(Some(thread))
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
            .expect("thread index lock poisoned");
        let Some(mut thread) = index.get(thread_id).cloned() else {
            return;
        };
        if thread.archived {
            return;
        }
        thread.last_user_message_at = Some(
            thread
                .last_user_message_at
                .map_or(accepted_at, |existing| existing.max(accepted_at)),
        );
        thread.updated_at = thread.updated_at.max(accepted_at);
        index.insert(thread.clone());
        self.writer.record_directory(DirectoryDelta {
            thread_upserts: vec![thread.clone()],
            ..Default::default()
        });
        self.emit_thread_delta_locked(&index, vec![thread], Vec::new());
    }

    /// Records only the Mode fact already committed by core, not an earlier whole-row copy.
    /// A failed/cancelled wait cannot reject that fact: write-behind retains the exact delta and
    /// exposes its normal PersistenceState/retry path. No core operation is replayed on retry.
    pub(in crate::studio) async fn commit_observed_thread_mode(
        &self,
        thread_id: &str,
        mode: pl_protocol::ThreadModeId,
        committed_at: i64,
    ) -> Result<StudioProductEventEnvelope> {
        let (ticket, event) = {
            let mut index = self
                .thread_index
                .lock()
                .expect("thread index lock poisoned");
            let mut thread = index
                .get(thread_id)
                .cloned()
                .ok_or_else(|| StudioError::not_found("session"))?;
            thread.mode = mode;
            thread.updated_at = thread.updated_at.max(committed_at);
            self.writer.record_directory(DirectoryDelta {
                thread_upserts: vec![thread.clone()],
                ..Default::default()
            });
            let ticket = self.writer.admitted_ticket();
            let event =
                self.publish_thread_delta_locked(&mut index, vec![thread], Vec::new(), Vec::new());
            (ticket, event)
        };
        self.writer.flush_through(ticket).await?;
        Ok(event)
    }

    /// 提交一次目录事实：持久化成功后更新唯一内存摘要并广播。
    ///
    /// 这是 Thread/Project 目录 mutation 的唯一命令通道；后台保存不能拒绝目录事实。
    pub(in crate::studio) async fn commit_directory(
        &self,
        delta: DirectoryDelta,
    ) -> Result<StudioProductEventEnvelope> {
        self.commit_directory_with_bases(delta, HashMap::new())
            .await
    }

    /// The caller freezes this baseline when deriving its update, before any await.
    pub(in crate::studio) async fn commit_thread_update(
        &self,
        baseline: Thread,
        updated: Thread,
    ) -> Result<StudioProductEventEnvelope> {
        anyhow::ensure!(baseline.id == updated.id, "thread update identity mismatch");
        let bases = HashMap::from([(baseline.id.clone(), baseline)]);
        self.commit_directory_with_bases(
            DirectoryDelta {
                thread_upserts: vec![updated],
                ..Default::default()
            },
            bases,
        )
        .await
    }

    async fn commit_directory_with_bases(
        &self,
        delta: DirectoryDelta,
        thread_baselines: HashMap<String, Thread>,
    ) -> Result<StudioProductEventEnvelope> {
        if delta.is_empty() {
            return Err(anyhow::anyhow!("directory delta is empty"));
        }
        let _command = self.directory_commands.lock().await;
        #[cfg(test)]
        tests::pause(&self.directory_test_pauses.commit_before_persist).await;
        // Persist without holding the metadata lock. Readers continue to see the previous
        // committed RAM slice until this durable operation succeeds.
        self.store.persist_directory_summaries(&delta).await?;
        #[cfg(test)]
        tests::pause(&self.directory_test_pauses.commit_persisted).await;
        let thread_removals = delta
            .thread_removals
            .iter()
            .flat_map(|removal| removal.thread_ids.iter().cloned())
            .chain(
                delta
                    .project_removals
                    .iter()
                    .flat_map(|removal| removal.thread_ids.iter().cloned()),
            )
            .collect::<Vec<_>>();
        let project_upserts = delta
            .project_upserts
            .iter()
            .map(|project| crate::WorkspaceRecord {
                id: project.id.clone(),
                kind: project.kind,
                name: project.name.clone(),
                path: project.path.clone(),
                ssh_alias: project.ssh_alias.clone(),
                updated_at: project.updated_at,
            })
            .collect::<Vec<_>>();
        let project_changed = !project_upserts.is_empty() || !delta.project_removals.is_empty();
        let mut envelope = {
            let mut index = self
                .thread_index
                .lock()
                .expect("thread index lock poisoned");
            let mut published_upserts = Vec::new();
            let mut frozen_rows = BTreeMap::new();
            for requested in &delta.thread_upserts {
                let mut merged = match thread_baselines.get(&requested.id) {
                    None => requested.clone(),
                    Some(baseline) => {
                        let Some(current) = index.get(&requested.id).cloned() else {
                            // A later removal remains authoritative; this older command cannot
                            // resurrect the identity.
                            continue;
                        };
                        rebase_command_thread(current, requested, baseline)
                    }
                };
                Self::apply_explicit_close(&index, &mut merged);
                index.insert(merged.clone());
                frozen_rows.insert(merged.id.clone(), merged.clone());
                published_upserts.push(merged);
            }

            let removals = delta
                .thread_removals
                .iter()
                .flat_map(|removal| {
                    removal
                        .thread_ids
                        .iter()
                        .map(move |id| (id, removal.archived_at))
                })
                .chain(delta.project_removals.iter().flat_map(|removal| {
                    removal
                        .thread_ids
                        .iter()
                        .map(move |id| (id, removal.closed_at))
                }));
            for (id, archived_at) in removals {
                if let Some(mut current) = index.get(id).cloned() {
                    current.archived = true;
                    current.updated_at = current.updated_at.max(archived_at);
                    index.insert(current.clone());
                    frozen_rows.insert(current.id.clone(), current);
                }
            }
            if project_changed {
                index.update_projects(&project_upserts, &delta.project_removals);
            }
            let mut writer_delta = delta.clone();
            writer_delta.thread_upserts = frozen_rows.into_values().collect();
            self.writer.record_directory(writer_delta);

            self.prepare_child_interaction_directory(&published_upserts);
            self.remove_child_interaction_directory(&thread_removals);
            let thread_changed = !published_upserts.is_empty() || !thread_removals.is_empty();
            if thread_changed {
                Some(self.emit_thread_delta_locked(&index, published_upserts, thread_removals))
            } else if project_changed {
                self.bump(&self.revisions.thread);
                self.topics
                    .lock()
                    .expect("product topic channels lock poisoned")
                    .notify(&crate::StudioProductTopic::ThreadDirectory);
                None
            } else {
                None
            }
        };
        if let Some(project_event) = self
            .apply_project_snapshot_delta(&project_upserts, &delta.project_removals)
            .await?
        {
            envelope = Some(project_event);
        }
        envelope.ok_or_else(|| anyhow::anyhow!("directory delta has no observable changes"))
    }

    /// Reads the current metadata summary without activating a cold Thread.
    pub(crate) fn thread_snapshot(&self, thread_id: &str) -> Option<Thread> {
        self.thread_index
            .lock()
            .expect("thread index lock poisoned")
            .get(thread_id)
            .cloned()
    }

    /// 注册一个 child Thread：typed delta 与摘要集合共同形成内存提交。
    pub(in crate::studio) async fn register_child_thread(
        &self,
        spec: RegisteredChildThread,
    ) -> Result<()> {
        let delta = DirectoryDelta::register_child_thread(spec);
        self.commit_directory(delta).await?;
        Ok(())
    }

    pub(in crate::studio) async fn fault_unregistered_child(
        &self,
        id: &str,
        message: &str,
    ) -> Result<()> {
        let mut thread = self
            .thread_snapshot(id)
            .ok_or_else(|| anyhow::anyhow!("unregistered child is not resident: {id}"))?;
        let baseline = thread.clone();
        let state = crate::studio::records::DirectoryState {
            kind: pl_protocol::ThreadStatus::Faulted,
            error: Some(message.into()),
        };
        thread.status = pl_protocol::ThreadStatus::Faulted;
        thread.updated_at = crate::studio::unix_seconds();
        let delta = DirectoryDelta {
            unregistered_faults: vec![crate::studio::store::directory::UnregisteredChildFault {
                thread_id: id.into(),
                state,
            }],
            thread_upserts: vec![thread],
            ..Default::default()
        };
        self.commit_directory_with_bases(delta, HashMap::from([(id.to_owned(), baseline)]))
            .await?;
        Ok(())
    }

    /// 当前摘要中属于指定 root 的全部条目。
    pub(in crate::studio) fn threads_for_root(&self, root_thread_id: &str) -> Vec<Thread> {
        self.thread_index
            .lock()
            .expect("thread index lock poisoned")
            .rows
            .values()
            .filter(|thread| thread.root_thread_id == root_thread_id)
            .cloned()
            .collect()
    }
}
