//! Thread 生命周期命令：创建、改名、自动标题、模式切换、归档与失败补偿。

use anyhow::{Context, Result, bail};

use crate::studio::records::ThreadRecord;
use crate::studio::store::directory::DirectoryDelta;

use super::super::StudioRuntime;
use super::super::thread_title::{
    ThreadTitleCancellation, ThreadTitleCancellationCause, manual_title, provisional_title,
};
use super::super::{
    ArchiveThreadCommandReply, RenameThreadCommandReply, StudioArchiveThreadResult,
    StudioStartNewThreadRequest, StudioStartNewThreadResponse, StudioSubmitPromptRequest,
};

/// 归档收束轮询间隔：既避免忙等，又让正常收束延迟保持在可忽略范围。
const ARCHIVE_TREE_SETTLE_POLL_INTERVAL: std::time::Duration = std::time::Duration::from_millis(25);

impl StudioRuntime {
    pub async fn create_thread(&self, project_id: &str, title: &str) -> Result<ThreadRecord> {
        self.create_thread_with_id(crate::studio::ids::new_id("thread"), project_id, title)
            .await
    }

    pub(crate) async fn create_thread_with_id(
        &self,
        thread_id: impl Into<String>,
        project_id: &str,
        title: &str,
    ) -> Result<ThreadRecord> {
        let _lifecycle_guard = self.thread_lifecycle_admission().await?;
        let thread_id = thread_id.into();
        if let Some(existing) = self.find_owned_thread(&thread_id).await? {
            anyhow::ensure!(
                existing.project_id == project_id,
                "bot Thread identity is bound to another project"
            );
            anyhow::ensure!(
                existing.visibility == crate::studio::ThreadVisibility::Active,
                "archived Thread cannot accept bot traffic"
            );
            let protocol = pl_protocol::Thread::from(existing.clone());
            self.check_thread_read_access(&protocol)?;
            self.verify_thread_execution_preparation(&protocol, None)
                .await?;
            self.check_thread_execution_access(&protocol)?;
            return Ok(existing);
        }
        self.ensure_project_thread_admission_open(project_id)?;
        let project = self
            .agent_facility
            .product_events
            .project_snapshot()
            .await
            .into_iter()
            .find(|project| project.id == project_id)
            .context("selected Project not found")?;
        self.thread_factory
            .verify_project_workspace(&project)
            .await?;
        let workspace_path = local_thread_workspace(&project, &thread_id).await?;
        let (mut delta, mut thread) = DirectoryDelta::register_root_thread(
            thread_id,
            project_id,
            title,
            pl_protocol::ThreadModeId::simple(),
            pl_protocol::ThreadWorkspaceMode::Local,
            workspace_path,
        );
        let delegation = self.config_runtime.read()?.config.delegation;
        thread.delegation_mode = delegation.mode;
        thread.delegation_preference = delegation.preference;
        delta.thread_upserts = vec![thread.clone()];
        self.agent_facility
            .product_events
            .commit_directory(delta)
            .await?;
        let thread = ThreadRecord::from_directory_thread(thread);
        self.register_new_thread(thread.clone()).await?;
        Ok(thread)
    }

    pub async fn start_new_thread(
        &self,
        request: StudioStartNewThreadRequest,
    ) -> Result<StudioStartNewThreadResponse> {
        let project_id = request.project_id.clone();
        let input_id = request.input.input_id.clone();
        let report = |stage, workspace_path: Option<&str>, branch: Option<&str>| {
            if let Some(observer) = &request.preparation_observer {
                observer(super::super::ThreadPreparationProgress {
                    project_id: project_id.clone(),
                    input_id: input_id.clone(),
                    stage,
                    workspace_path: workspace_path.map(str::to_owned),
                    branch: branch.map(str::to_owned),
                });
            }
        };
        use super::super::ThreadPreparationStage;
        super::super::prompt_runner::validate_prompt_content(&request.input)?;
        let auto_title = request.title.is_none() && !request.input.text.trim().is_empty();
        let provisional = request
            .title
            .clone()
            .unwrap_or_else(|| provisional_title(&request.input.text));
        let title_prompt = request.input.text.clone();
        let _lifecycle_guard = self.thread_lifecycle_admission().await?;
        report(ThreadPreparationStage::CheckingProject, None, None);
        self.ensure_prompt_runtime_ready().await?;
        let drafts = self
            .attachment_drafts
            .resolve(&request.input.attachment_draft_ids)
            .await?;
        let config = self.config_runtime.read()?;
        let selector = super::super::settings_api::validated_route(
            &config.config,
            "new Thread",
            &request.route.account_id,
            &request.route.model_id,
            request.route.effort.as_deref(),
        )?;
        let route = config
            .config
            .models
            .resolve_route(crate::config::root_agent_route_id(), &selector)?;
        crate::studio::delegation::validate_credential(&route)?;
        self.thread_modes
            .snapshot()
            .mode(&request.mode)
            .context("requested Thread Mode is unavailable")?;

        self.attachment_drafts
            .validate_for_model(&route.model, &drafts)?;
        // 校验走内存目录 owner：open_project 的落库是异步跟随的。
        let projects = self.agent_facility.product_events.project_snapshot().await;
        let project = projects
            .iter()
            .find(|project| project.id == request.project_id)
            .cloned()
            .context("selected Project not found")?;
        anyhow::ensure!(
            project.kind != pl_protocol::studio::WorkspaceKind::Standalone
                || request.workspace_mode == pl_protocol::ThreadWorkspaceMode::Local,
            "standalone sessions only support local workspaces"
        );
        self.ensure_project_thread_admission_open(&request.project_id)?;
        self.thread_factory
            .verify_project_workspace(&project)
            .await?;
        self.ensure_mode_available(&request.mode)?;

        // D4：会话工作区在发布 Thread 之前就已确定。`worktree` 先做前置校验与物理创建，
        // 再记录 `active` lease；任一阶段失败都让命令失败且不留下已发布 Thread。
        let thread_id = crate::studio::ids::new_id("thread");
        let mut session_lease = None;
        report(
            ThreadPreparationStage::PreparingWorkspace,
            (request.workspace_mode == pl_protocol::ThreadWorkspaceMode::Local)
                .then_some(project.path.as_str()),
            None,
        );
        if request.workspace_mode == pl_protocol::ThreadWorkspaceMode::Worktree {
            // 创建窗口内的 lease 由进程内「创建中」标记保护：在记录 `prepared` 之前设置，
            // 直到 owner Thread 目录事实提交（或失败 settle 并发布）之后才清除。
            self.agent_facility.worktrees.mark_creating(&thread_id);
            let created =
                crate::studio::agent_host::workspace_preparation::create_root_session_worktree(
                    &self.store,
                    &self.agent_facility.worktrees,
                    &self.ssh_manager,
                    &project,
                    &thread_id,
                    &report,
                )
                .await;
            let lease = match created {
                Ok(lease) => lease,
                Err(error) => {
                    self.settle_session_worktree_failure(
                        &thread_id,
                        Some("the session worktree could not be created"),
                    )
                    .await;
                    return Err(error);
                }
            };
            session_lease = Some(lease);
        }

        // Standalone roots own an exclusive per-Thread local directory, never the shared owner root.
        let workspace_path = match &session_lease {
            Some(lease) => lease.path.clone(),
            None => local_thread_workspace(&project, &thread_id).await?,
        };
        report(
            ThreadPreparationStage::InitializingSession,
            Some(&workspace_path),
            None,
        );
        let (mut delta, mut thread) = DirectoryDelta::register_root_thread(
            thread_id,
            &request.project_id,
            &provisional,
            request.mode,
            request.workspace_mode,
            workspace_path,
        );
        thread.delegation_mode = request
            .delegation_mode
            .unwrap_or(config.config.delegation.mode);
        thread.delegation_preference = request
            .delegation_preference
            .unwrap_or(config.config.delegation.preference);
        delta.thread_upserts = vec![thread.clone()];
        // Stage before publication: a directory observer may concurrently
        // activate this identity, and must use this exact request route.
        self.thread_factory
            .stage_initial_route(&thread.id, selector);
        // 目录事实内存先行；SQLite 失败进入持久化降级而不是命令失败
        // （design/18 §18.2）。
        if let Err(error) = self
            .agent_facility
            .product_events
            .commit_directory(delta)
            .await
        {
            self.thread_factory.clear_initial_route(&thread.id);
            self.clear_creating_session_worktree(&session_lease);
            let error = match self
                .preserve_session_worktree(
                    session_lease.take(),
                    Some("the new session Thread was not published"),
                )
                .await
            {
                Ok(()) => error,
                Err(retention) => error.context(format!(
                    "failed to preserve new session worktree: {retention:#}"
                )),
            };
            return Err(error);
        }
        // 目录事实已提交：owner Thread 行已存在，创建窗口收束。
        self.clear_creating_session_worktree(&session_lease);
        let thread = ThreadRecord::from_directory_thread(thread);
        if let Err(error) = self.register_new_thread(thread.clone()).await {
            self.thread_factory.clear_initial_route(&thread.id);
            // 目录事实已发布：必须先按未启动会话补偿（关闭并归档），不能留下无法激活的
            // 已发布会话；会话自身 worktree 仍按 D6 只收束为 `preserved`。
            let error = match self
                .preserve_session_worktree(
                    session_lease.take(),
                    Some("the new session Thread could not be activated"),
                )
                .await
            {
                Ok(()) => error,
                Err(retention) => error.context(format!(
                    "failed to preserve new session worktree: {retention:#}"
                )),
            };
            if let Err(cleanup_error) = self.compensate_unstarted_thread(&thread.id).await {
                return Err(error.context(format!(
                    "failed to compensate new Thread {}: {cleanup_error:#}",
                    thread.id
                )));
            }
            return Err(error);
        }
        self.thread_factory.clear_initial_route(&thread.id);
        report(
            ThreadPreparationStage::SubmittingPrompt,
            Some(&thread.workspace_path),
            None,
        );
        let submission = self
            .submit_prompt_for_owned_thread_with_lifecycle_lock(
                StudioSubmitPromptRequest {
                    thread_id: thread.id.clone(),
                    input: request.input,
                    options: request.options,
                },
                thread.clone(),
            )
            .await;
        let submission = match submission {
            Ok(submission) => submission,
            Err(error) => {
                // 已发布 Thread 的补偿归档后，会话自身 worktree 仍按 D6 保留现场等待显式清理。
                let error = match self
                    .preserve_session_worktree(
                        session_lease.take(),
                        Some("the first prompt of the new session was rejected"),
                    )
                    .await
                {
                    Ok(()) => error,
                    Err(retention) => error.context(format!(
                        "failed to preserve new session worktree: {retention:#}"
                    )),
                };
                if let Err(cleanup_error) = self.compensate_unstarted_thread(&thread.id).await {
                    return Err(error.context(format!(
                        "failed to compensate new Thread {}: {cleanup_error:#}",
                        thread.id
                    )));
                }
                return Err(error);
            }
        };
        if auto_title {
            self.title_tasks
                .spawn(self.clone(), thread.id.clone(), provisional, title_prompt)
                .await;
        }
        Ok(StudioStartNewThreadResponse { thread, submission })
    }

    /// Renames a root Thread and publishes the canonical directory update.
    pub async fn rename_thread(
        &self,
        operation_id: String,
        thread_id: String,
        title: String,
    ) -> Result<RenameThreadCommandReply> {
        Self::validate_operation_id(&operation_id)?;
        let title = manual_title(&title)?;
        let _lifecycle_guard = self.lifecycle_lock.lock().await;
        self.ensure_prompt_runtime_ready().await?;
        let mut thread = self.read_protocol_thread(&thread_id).await?;
        anyhow::ensure!(
            thread.parent_thread_id.is_none(),
            "only root Threads can be renamed"
        );
        if thread.archived {
            bail!("archived Threads cannot be renamed");
        }
        // A user edit is authoritative: stop the best-effort Explorer task
        // before publishing the canonical manual title.
        self.title_tasks
            .cancel(&thread_id, ThreadTitleCancellationCause::ManualRename)
            .await;
        let changed = thread.title != title;
        thread.title = title;
        thread.updated_at = crate::studio::unix_seconds();
        let committed = self
            .agent_facility
            .product_events
            .commit_directory(DirectoryDelta {
                thread_upserts: vec![thread.clone()],
                ..Default::default()
            })
            .await?;
        Ok(RenameThreadCommandReply {
            thread: ThreadRecord::from_directory_thread(thread),
            receipt: self.command_receipt(
                operation_id,
                changed,
                vec![self.thread_directory_stamp(&committed)?],
                pl_protocol::studio::CommandEffectPoint::Immediate,
                false,
            ),
        })
    }

    pub(in crate::studio::runtime) async fn apply_automatic_thread_title(
        &self,
        thread_id: &str,
        expected_title: &str,
        title: &str,
        cancellation: &mut ThreadTitleCancellation,
    ) -> Result<()> {
        let _lifecycle_guard = tokio::select! {
            _ = cancellation.cancelled() => return Ok(()),
            guard = self.lifecycle_lock.lock() => guard,
        };
        if cancellation.is_cancelled() {
            return Ok(());
        }
        let Some(mut thread) = self
            .agent_facility
            .product_events
            .thread_snapshot(thread_id)
        else {
            return Ok(());
        };
        if thread.archived
            || thread.parent_thread_id.is_some()
            || thread.title != expected_title
            || thread.title == title
        {
            return Ok(());
        }
        thread.title = title.to_string();
        thread.updated_at = crate::studio::unix_seconds();
        self.agent_facility
            .product_events
            .commit_directory(DirectoryDelta {
                thread_upserts: vec![thread],
                ..Default::default()
            })
            .await?;
        Ok(())
    }

    pub async fn archive_thread(
        &self,
        operation_id: String,
        thread_id: String,
    ) -> Result<Option<ArchiveThreadCommandReply>> {
        Self::validate_operation_id(&operation_id)?;
        let runtime = self.clone();
        self.run_thread_lifecycle_operation(async move {
            runtime.archive_thread_owned(operation_id, thread_id).await
        })
        .await
    }

    async fn archive_thread_owned(
        &self,
        operation_id: String,
        thread_id: String,
    ) -> Result<Option<ArchiveThreadCommandReply>> {
        let root_operation = self.threads.agent_operation(&thread_id).await;
        let Some((thread, roots, thread_tree)) = self.load_thread_archive_scope(&thread_id).await?
        else {
            return Ok(None);
        };
        let _pins = self
            .residency
            .pin_many(thread_tree.iter().map(|thread| thread.id.clone()));
        let root_index = roots
            .iter()
            .position(|candidate| candidate.id == thread_id)
            .context("selected root Thread not found")?;
        let next_root = roots
            .get(root_index + 1)
            .or_else(|| root_index.checked_sub(1).and_then(|index| roots.get(index)))
            .cloned();
        let removed_thread_ids = thread_tree
            .iter()
            .map(|candidate| candidate.id.clone())
            .chain(std::iter::once(thread.id.clone()))
            .collect::<Vec<_>>();
        let _child_seals = self
            .threads
            .seal_agent_operations(
                &removed_thread_ids
                    .iter()
                    .filter(|id| **id != thread_id)
                    .cloned()
                    .collect::<Vec<_>>(),
            )
            .await;
        let _root_seal = self.threads.seal_agent_operation(&thread_id);
        drop(root_operation);
        // 归档先结束整棵树的活动工作（design/01 §1.4）：中断当前 Turn、丢弃未消费输入，
        // 再有界等待收束；无法结束时返回类型化失败并保留会话现场。
        self.end_thread_tree_work(&removed_thread_ids).await?;
        // 关闭与保存不得探测或清理物理工作树；目录归档只在整棵树关闭成功后发布。
        self.retire_archived_thread_tree(&removed_thread_ids)
            .await?;
        let committed = self
            .agent_facility
            .product_events
            .commit_directory(DirectoryDelta::archive_threads(removed_thread_ids.clone()))
            .await?;
        for removed_thread_id in &removed_thread_ids {
            self.title_tasks
                .cancel(
                    removed_thread_id,
                    ThreadTitleCancellationCause::ThreadArchive,
                )
                .await;
        }
        self.model_performance.remove_session(&thread.id).await?;
        Ok(Some(ArchiveThreadCommandReply {
            result: StudioArchiveThreadResult {
                archived_root_id: thread.id,
                removed_thread_ids,
                next_root,
            },
            receipt: self.command_receipt(
                operation_id,
                true,
                vec![self.thread_directory_stamp(&committed)?],
                pl_protocol::studio::CommandEffectPoint::Immediate,
                false,
            ),
        }))
    }

    /// Restores an archived root and its descendants without executing historical work.
    pub async fn restore_thread(&self, thread_id: String) -> Result<ThreadRecord> {
        let _guard = self.lifecycle_lock.lock().await;
        let root = self.read_protocol_thread(&thread_id).await?;
        anyhow::ensure!(
            root.parent_thread_id.is_none(),
            "only root Threads can be restored"
        );
        let projects = self.agent_facility.product_events.project_snapshot().await;
        anyhow::ensure!(
            projects.iter().any(|project| project.id == root.project_id),
            "open the original Project before restoring its Threads"
        );
        if !root.archived {
            return Ok(ThreadRecord::from_directory_thread(root));
        }
        let mut tree = self
            .store
            .read_directory_tree(&thread_id)
            .await?
            .into_iter()
            .map(|record| (record.id.clone(), pl_protocol::Thread::from(record)))
            .collect::<std::collections::BTreeMap<_, _>>();
        for thread in self
            .agent_facility
            .product_events
            .threads_for_root(&thread_id)
        {
            tree.insert(thread.id.clone(), thread);
        }
        tree.insert(root.id.clone(), root);
        // 取消归档只改变目录可见性，不检查、重建或授权重建原工作区。
        let now = crate::studio::unix_seconds();
        for thread in tree.values_mut() {
            thread.archived = false;
            thread.updated_at = now;
        }
        let restored = tree
            .get(&thread_id)
            .context("root missing from restore tree")?
            .clone();
        self.agent_facility
            .product_events
            .commit_directory(DirectoryDelta {
                thread_upserts: tree.into_values().collect(),
                ..Default::default()
            })
            .await?;
        self.model_performance.refresh_directory_visibility().await;
        Ok(ThreadRecord::from_directory_thread(restored))
    }

    async fn compensate_unstarted_thread(&self, thread_id: &str) -> Result<()> {
        self.threads.close(thread_id).await?;
        self.residency.remove(thread_id).await;
        self.agent_facility
            .product_events
            .commit_directory(DirectoryDelta::archive_threads(vec![thread_id.to_string()]))
            .await?;
        self.title_tasks
            .cancel(
                thread_id,
                ThreadTitleCancellationCause::NewThreadCompensation,
            )
            .await;
        self.model_performance.remove_session(thread_id).await?;
        Ok(())
    }

    /// 会话自身 worktree 从不随 Thread 生命周期删除：失败路径只把它收束为 `preserved`，
    /// 由 Recovery 显式清理（design/12 §12.5）。
    ///
    /// 收束成功后**立即**基于当前 durable lease 发布/刷新 Recovery 条目（含 preview），
    /// 不依赖下一次启动审计；保留写入失败返回调用方，与原创建错误一起保留。
    async fn preserve_session_worktree(
        &self,
        lease: Option<crate::studio::agent_host::worktree_lease::WorktreeLease>,
        reason: Option<&str>,
    ) -> Result<()> {
        let Some(lease) = lease else {
            return Ok(());
        };
        let retained = self
            .agent_facility
            .worktrees
            .preserve_failed_session_binding(&lease)
            .await?;
        self.publish_worktree_recovery(reason, &retained).await;
        Ok(())
    }

    /// 创建阶段失败的统一收束出口：清除创建中标记，并在现场被保留为 `preserved` 时立即
    /// 发布带 preview 的 Recovery（同一 issue id upsert）。
    ///
    /// 顺序固定为「调用方已完成 settle → 清除标记 → 发布」：清除标记使并发的周期审计也能
    /// 把该资源算作需要人工处置，避免审计的 `replace` 与本次显式发布互相覆盖导致条目丢失。
    async fn settle_session_worktree_failure(&self, thread_id: &str, reason: Option<&str>) {
        use crate::studio::agent_host::worktree_lease::WorktreeLeaseState;
        self.agent_facility.worktrees.clear_creating(thread_id);
        let Some(lease) = self.agent_facility.worktrees.get(thread_id) else {
            return;
        };
        if lease.state != WorktreeLeaseState::Preserved {
            return;
        }
        self.publish_worktree_recovery(reason, &lease).await;
    }

    /// 会话 worktree 的创建窗口结束：owner Thread 目录事实已提交（或失败路径已自行清除）。
    fn clear_creating_session_worktree(
        &self,
        lease: &Option<crate::studio::agent_host::worktree_lease::WorktreeLease>,
    ) {
        if let Some(lease) = lease {
            self.agent_facility
                .worktrees
                .clear_creating(&lease.owner_thread_id);
        }
    }

    pub(super) async fn retire_archived_thread_tree(&self, thread_ids: &[String]) -> Result<()> {
        self.close_project_agent_trees(thread_ids).await?;
        for thread_id in thread_ids {
            self.residency.remove(thread_id).await;
            let issues = self.recovery.retire_thread(thread_id);
            self.agent_facility
                .product_events
                .emit_recovery_state(issues);
        }
        Ok(())
    }

    async fn load_thread_archive_scope(
        &self,
        root_thread_id: &str,
    ) -> Result<Option<(ThreadRecord, Vec<ThreadRecord>, Vec<ThreadRecord>)>> {
        let (mut roots, mut tree) = tokio::try_join!(
            self.store.list_root_threads_for_archive(root_thread_id),
            self.store.list_threads_for_archive(root_thread_id),
        )?;
        for hot in self
            .agent_facility
            .product_events
            .threads_for_root(root_thread_id)
        {
            if !tree.iter().any(|candidate| candidate.id == hot.id) {
                tree.push(ThreadRecord::from_directory_thread(hot));
            }
        }
        let Some(root) = tree
            .iter()
            .find(|thread| thread.id == root_thread_id && thread.parent_thread_id.is_none())
            .cloned()
        else {
            return Ok(None);
        };
        // A newly created root may not yet be in SQLite. Archive selection must
        // use the same canonical hot facts as the tree itself.
        let hot = self
            .agent_facility
            .product_events
            .read_thread_directory()
            .await?;
        if let Some(directory) = hot.state.value() {
            for thread in &directory.threads {
                if thread.project_id == root.project_id
                    && thread.parent_thread_id.is_none()
                    && !thread.archived
                {
                    roots.retain(|entry| entry.id != thread.id);
                    roots.push(ThreadRecord::from_directory_thread(thread.clone()));
                }
            }
        }
        // 归档后的候选会话选择与目录排序使用同一顺序键（design/19）：
        // 最近用户消息时间（缺失回退创建时间）降序，同秒以 ID 稳定破平。
        roots.sort_by(|a, b| {
            let left = a.last_user_message_at.unwrap_or(a.created_at);
            let right = b.last_user_message_at.unwrap_or(b.created_at);
            right.cmp(&left).then_with(|| b.id.cmp(&a.id))
        });
        let mut entries = roots
            .iter()
            .chain(tree.iter())
            .cloned()
            .map(pl_protocol::Thread::from)
            .collect::<Vec<_>>();
        entries.sort_by(|left, right| left.id.cmp(&right.id));
        entries.dedup_by(|left, right| left.id == right.id);
        self.agent_facility
            .product_events
            .warm_thread_index(entries);
        Ok(Some((root, roots, tree)))
    }

    fn ensure_mode_available(&self, mode_id: &pl_protocol::ThreadModeId) -> Result<()> {
        anyhow::ensure!(
            self.thread_modes.snapshot().mode(mode_id).is_some(),
            "selected Thread Mode `{mode_id}` is unavailable"
        );
        Ok(())
    }

    /// 未驻留即不 busy：钉住集合恢复保证有 pending 工作的 Thread 会被恢复，
    /// LRU 只淘汰空闲且已耐久化的 actor（design/17 §17.5）。
    pub(in crate::studio::runtime) async fn thread_is_busy(&self, thread_id: &str) -> Result<bool> {
        let Some(thread) = self.threads.observed_thread(thread_id) else {
            return Ok(false);
        };
        let snapshot = thread.snapshot();
        Ok(snapshot
            .turns
            .iter()
            .any(|turn| turn.state == pl_core::thread::TurnState::Running)
            || snapshot
                .inputs
                .iter()
                .any(|input| input.state == pl_core::thread::input::InputState::Pending)
            || snapshot
                .tasks
                .values()
                .any(|task| task.status == pl_core::thread::task::TaskStatus::Running))
    }

    /// 结束会话树的活动工作并有界等待收束，供 `archive_thread` 在 `lifecycle_lock` 下调用。
    ///
    /// 只复用既有能力：`ThreadHandle::interrupt_turn(None)` 停止当前正在执行的那个 Turn
    /// （不指定预期身份），`ThreadHandle::discard_input(id)` 逐条丢弃尚未消费的输入。
    /// 等待期间以 `thread_is_busy` 为唯一判定，不引入第二份并发状态；不得无限自旋，也
    /// 不得在仍 busy 时继续归档。
    ///
    /// 并发契约：`archive_thread` 与所有输入提交入口（`prompt_runner/submit.rs` 的
    /// `submit_prompt*`、`threads.rs` 的 `start_new_thread`）都在同一把 `lifecycle_lock`
    /// 下进入 owner mailbox，因此归档期间不会有并发新输入落入这棵树。
    async fn end_thread_tree_work(&self, thread_ids: &[String]) -> Result<()> {
        for thread_id in thread_ids {
            let Some(thread) = self.threads.observed_thread(thread_id) else {
                // Cold history has no active work and must not be activated for archiving.
                continue;
            };
            match thread.interrupt_turn(None).await {
                // owner 已关闭表示它不再运行新工作，按非 busy 处理而非失败。
                Ok(_) | Err(pl_core::thread::ThreadError::Closed) => {}
                Err(error) => return Err(anyhow::Error::new(error)),
            }
        }
        let deadline = tokio::time::Instant::now() + self.archive_settle_timeout();
        loop {
            let mut still_busy = None;
            for thread_id in thread_ids {
                if self.threads.observed_thread(thread_id).is_none() {
                    continue;
                }
                self.discard_pending_inputs(thread_id).await?;
                if still_busy.is_none() && self.thread_is_busy(thread_id).await? {
                    still_busy = Some(thread_id.clone());
                }
            }
            let Some(thread_id) = still_busy else {
                return Ok(());
            };
            if tokio::time::Instant::now() >= deadline {
                return Err(anyhow::Error::new(
                    pl_protocol::studio::StudioError::new(
                        pl_protocol::studio::StudioErrorCode::Busy,
                        "The session could not be ended before archiving",
                        true,
                    )
                    .with_details(serde_json::json!({ "threadId": thread_id })),
                ));
            }
            tokio::time::sleep(ARCHIVE_TREE_SETTLE_POLL_INTERVAL).await;
        }
    }

    /// 丢弃该 Thread 当前 canonical 快照里仍未消费的输入，不改写已消费/已丢弃的记录。
    async fn discard_pending_inputs(&self, thread_id: &str) -> Result<()> {
        let Some(thread) = self.threads.observed_thread(thread_id) else {
            return Ok(());
        };
        let snapshot = thread.snapshot();
        let pending = snapshot
            .inputs
            .iter()
            .filter(|record| record.state == pl_core::thread::input::InputState::Pending)
            .map(|record| record.input.id.clone())
            .collect::<Vec<_>>();
        for input_id in pending {
            match thread.discard_input(input_id).await {
                // 已消费：保持原样；正在被驱动：交由中断收束后的下一轮重试。
                Ok(_)
                | Err(pl_core::thread::ThreadError::InputConsumed)
                | Err(pl_core::thread::ThreadError::InputInUse)
                | Err(pl_core::thread::ThreadError::Closed) => {}
                Err(error) => return Err(anyhow::Error::new(error)),
            }
        }
        Ok(())
    }
}

async fn local_thread_workspace(
    project: &crate::studio::ProjectRecord,
    thread_id: &str,
) -> Result<String> {
    if project.kind == pl_protocol::studio::WorkspaceKind::Project {
        return Ok(project.path.clone());
    }
    anyhow::ensure!(
        project.ssh_alias.is_none(),
        "standalone workspace must be local"
    );
    let mut components = std::path::Path::new(thread_id).components();
    anyhow::ensure!(
        matches!(components.next(), Some(std::path::Component::Normal(_)))
            && components.next().is_none(),
        "standalone Thread identity must be a single directory name"
    );
    let root_path = project.path.clone();
    let root = tokio::task::spawn_blocking(move || dunce::canonicalize(root_path))
        .await?
        .context("resolve standalone workspace root")?;
    let path = root.join(thread_id);
    // Exclusive creation intentionally rejects unknown leftovers, including links. A failure after
    // this point preserves the owned directory rather than deleting possible user work.
    tokio::fs::create_dir(&path)
        .await
        .with_context(|| format!("create standalone Thread directory {}", path.display()))?;
    let canonical = tokio::task::spawn_blocking(move || dunce::canonicalize(path)).await??;
    anyhow::ensure!(
        canonical.parent() == Some(root.as_path()),
        "standalone Thread directory escaped its owner root"
    );
    Ok(canonical.to_string_lossy().into_owned())
}
