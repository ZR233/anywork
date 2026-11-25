//! Close admission and operation serialization; guarded by the session transaction lock.
use super::*;

#[derive(Debug)]
pub(crate) struct CloseCoordinator {
    pub(crate) operation_gates: BTreeMap<String, std::sync::Weak<tokio::sync::Mutex<()>>>,
    pub(crate) sealed_agents: BTreeMap<String, usize>,
    pub(crate) closing: bool,
    pub(crate) attachment: Arc<dyn close_storage::StorageAttachment>,
}

impl Default for CloseCoordinator {
    fn default() -> Self {
        Self {
            operation_gates: Default::default(),
            sealed_agents: Default::default(),
            closing: false,
            attachment: Arc::new(close_storage::NativeStorageAttachment),
        }
    }
}

impl CloseCoordinator {
    pub(crate) fn operation_gate(&mut self, id: &str) -> Arc<tokio::sync::Mutex<()>> {
        if let Some(gate) = self
            .operation_gates
            .get(id)
            .and_then(std::sync::Weak::upgrade)
        {
            return gate;
        }
        self.operation_gates
            .retain(|_, gate| gate.strong_count() > 0);
        let gate = Arc::new(tokio::sync::Mutex::new(()));
        self.operation_gates
            .insert(id.to_owned(), Arc::downgrade(&gate));
        gate
    }
}

impl SessionRuntime {
    /// Evicts a leaf only after core atomically seals idle admission and saves its final facts.
    ///
    /// # Errors
    /// Retains an unpublished closing owner when resource release or persistence fails.
    pub async fn evict_idle(&self, id: &str) -> Result<bool, ThreadAssemblyError> {
        if self.phase() != crate::session::SessionPhase::Open {
            return Ok(false);
        }
        let candidate =
            {
                let mut state = self.0.state();
                if state.members.entries.get(id).is_some_and(|entry| {
                    matches!(entry.runtime, crate::session::AgentRuntime::Acp(_))
                }) {
                    return Ok(false);
                }
                if state.activation.creating.contains_key(id)
                    || state.members.entries.get(id).is_some_and(|entry| {
                        entry.native().is_ok_and(|native| {
                            entry.identity.parent_agent_id.is_some()
                                && native.thread.snapshot().lifecycle != ThreadLifecycle::Closed
                        })
                    })
                    || state.members.entries.values().any(|entry| {
                        EntryRegistry::membership_parent(&state.members.by_agent, entry) == Some(id)
                    })
                    || state
                        .activation
                        .creating
                        .values()
                        .any(|entry| entry.parent_id.as_deref() == Some(id))
                    || state
                        .activation
                        .preparing_children
                        .values()
                        .any(|entry| entry.parent == id)
                    || state
                        .activation
                        .unpublished_children
                        .values()
                        .any(|entry| entry.parent == id)
                {
                    return Ok(false);
                }
                state.members.entries.get_mut(id).and_then(|entry| {
                    let native = entry.native_mut().ok()?;
                    Some({
                        native.ready = false;
                        (native.incarnation.clone(), native.thread.clone())
                    })
                })
            };
        let Some((incarnation, thread)) = candidate else {
            return Ok(true);
        };
        if !thread.close_if_idle().await? {
            let mut state = self.0.state();
            if !state.close.closing
                && let Some(entry) = state.members.entries.get_mut(id)
                && Arc::ptr_eq(&entry.native()?.incarnation, &incarnation)
            {
                entry.native_mut()?.ready = true;
            }
            return Ok(false);
        }
        self.close(id).await?;
        Ok(true)
    }

    /// Closes one tree from leaves to root, retaining failures for a later retry.
    ///
    /// # Errors
    /// Propagates resource cleanup or concurrent preparation failures without removing the owner.
    pub(crate) async fn close_tree(
        &self,
        root: &str,
        members: &[crate::studio::store::thread_preparation::PreparationIdentity],
    ) -> Result<(), ThreadAssemblyError> {
        self.close_tree_with_purpose(root, members, ClosePurpose::Preserve)
            .await
    }

    pub(crate) async fn close_tree_for_deletion(
        &self,
        root: &str,
        members: &[crate::studio::store::thread_preparation::PreparationIdentity],
    ) -> Result<(), ThreadAssemblyError> {
        self.close_tree_with_purpose(root, members, ClosePurpose::Delete)
            .await
    }

    pub(crate) fn prepare_deletion(&self, ids: &[String]) {
        for id in ids {
            self.begin_operation_close(id, ClosePurpose::Delete);
            if let Some(thread) = self.observed_thread(id) {
                drop(self.prepare_close_for_purpose(id, &thread, ClosePurpose::Delete));
            }
        }
    }

    pub(crate) async fn close_tree_with_purpose(
        &self,
        root: &str,
        members: &[crate::studio::store::thread_preparation::PreparationIdentity],
        purpose: ClosePurpose,
    ) -> Result<(), ThreadAssemblyError> {
        let root_operation = self.agent_operation(root).await;
        let mut targets = self.0.state().members.close_targets(root, members)?;
        let ids = targets
            .iter()
            .filter(|(_, id)| id != root)
            .map(|(_, id)| id.clone())
            .collect::<Vec<_>>();
        let _child_seals = self.seal_agent_operations(&ids).await;
        let _root_seal = self.seal_agent_operation(root);
        drop(root_operation);
        targets.sort_by(|left, right| right.0.cmp(&left.0).then_with(|| left.1.cmp(&right.1)));
        // Broadcast cancellation to the entire tree before the first dependent wait.
        // Each close below awaits the same retained cleanup barrier.
        let owners = {
            let mut state = self.0.state();
            targets
                .iter()
                .filter_map(|(_, id)| {
                    state.members.entries.get_mut(id).and_then(|entry| {
                        let native = entry.native_mut().ok()?;
                        Some({
                            native.ready = false;
                            (id.clone(), native.thread.clone())
                        })
                    })
                })
                .collect::<Vec<_>>()
        };
        for (id, owner) in owners {
            self.begin_operation_close(&id, purpose);
            drop(self.prepare_close_for_purpose(&id, &owner, purpose));
        }
        // A deletion scope can contain cold intermediate members. Freeze only dependency
        // positions here; their identities do not become executable or storage owners.
        let dependencies = self
            .0
            .state()
            .members
            .close_dependencies(root, &targets, members, purpose)?;
        let mut failures = self
            .close_entry_tree_in_scope(root.to_owned(), purpose, Some(&dependencies))
            .await
            .into_iter();
        match failures.next() {
            None => {
                if purpose == ClosePurpose::Delete {
                    // All frozen identities, including cold intermediates, passed through the
                    // operation seals and real collaboration joins above. Check every registry
                    // owner before acknowledging a durable private preparation.
                    let services = {
                        let state = self.0.state();
                        for member in members {
                            let id = &member.thread_id;
                            if state.members.entries.contains_key(id)
                                || state.activation.creating.contains_key(id)
                                || state.activation.preparing_children.contains_key(id)
                                || state.activation.unpublished_children.contains_key(id)
                                || state.activation.failed_preparations.contains_key(id)
                                || state.activation.pending_activation.contains_key(id)
                            {
                                return Err(ThreadAssemblyError::Preparing(id.clone()));
                            }
                        }
                        state.agent_services.clone()
                    };
                    if let Some(services) = services {
                        for member in members {
                            let record = services
                                .store
                                .thread_preparation_for_deletion(&member.thread_id)
                                .await
                                .map_err(|source| ThreadAssemblyError::Resource {
                                    operation: "read deletion preparation",
                                    source: source.into(),
                                })?;
                            if let Some(record) = record {
                                if record.identity != *member {
                                    return Err(ThreadAssemblyError::Identity(
                                        member.thread_id.clone(),
                                    ));
                                }
                                if !record.published && !record.deletion_stopped {
                                    services
                                        .store
                                        .confirm_preparation_stop_for_deletion(&member.thread_id)
                                        .await
                                        .map_err(|source| ThreadAssemblyError::Resource {
                                            operation: "acknowledge drained deletion preparation",
                                            source: source.into(),
                                        })?;
                                }
                            }
                        }
                    }
                }
                Ok(())
            }
            Some((id, first)) => Err(ThreadAssemblyError::SubtreeClose {
                id,
                first: Box::new(first),
                others: failures.collect(),
            }),
        }
    }

    /// Closes an owner, including failed unpublished assembly, while retaining failed closes for retry.
    ///
    /// # Errors
    /// Returns in-progress assembly or the actual Thread shutdown failure.
    pub async fn close(&self, id: &str) -> Result<(), ThreadAssemblyError> {
        self.close_for_purpose(id, ClosePurpose::Preserve).await
    }

    pub(crate) async fn close_for_purpose(
        &self,
        id: &str,
        purpose: ClosePurpose,
    ) -> Result<(), ThreadAssemblyError> {
        let purpose = self.operation_close_purpose(id, purpose);
        let _seal = self.seal_agent_operation(id);
        self.begin_operation_close(id, purpose);
        if let Some((_, thread)) = self.admit_thread_close(id)? {
            drop(self.prepare_close_for_purpose(id, &thread, purpose));
        }
        let operation = self.agent_operation(id).await;
        self.close_with_permit_for_purpose(id, operation, purpose)
            .await
    }

    /// The caller retains this identity's operation permit, including cold close restoration.
    pub(crate) async fn close_with_permit(
        &self,
        id: &str,
        operation: tokio::sync::OwnedMutexGuard<()>,
    ) -> Result<(), ThreadAssemblyError> {
        self.close_with_permit_for_purpose(id, operation, ClosePurpose::Preserve)
            .await
    }

    pub(crate) async fn close_with_permit_for_purpose(
        &self,
        id: &str,
        operation: tokio::sync::OwnedMutexGuard<()>,
        purpose: ClosePurpose,
    ) -> Result<(), ThreadAssemblyError> {
        let purpose = self.operation_close_purpose(id, purpose);
        let _seal = self.seal_agent_operation(id);
        // Signal the actual owner before a retained collaboration producer can
        // wait for its projection. close_thread awaits the original cleanup.
        if let Some((_, thread)) = self.admit_thread_close(id)? {
            drop(self.prepare_close_for_purpose(id, &thread, purpose));
        }
        let acp = self
            .0
            .state()
            .members
            .entries
            .get(id)
            .is_some_and(|entry| matches!(entry.runtime, crate::session::AgentRuntime::Acp(_)));
        drop(operation);
        if !acp && purpose == ClosePurpose::Preserve {
            self.retry_failed_review_deliveries(id)
                .await
                .map_err(|source| ThreadAssemblyError::Resource {
                    operation: "recover failed terminal review producer",
                    source: source.into(),
                })?;
        }
        self.join_root_operations(id)
            .await
            .map_err(|source| ThreadAssemblyError::Resource {
                operation: "join root collaboration operations",
                source: source.into(),
            })?;
        let operation = self.agent_operation(id).await;
        self.close_thread_for_purpose(id, operation, purpose)
            .await?;
        self.discard_unpublished_child(id).await
    }

    /// Reject invalid targets before revoking delivery; a failed admitted close
    /// keeps this owner unavailable for new work until the original close retries.
    pub(crate) fn admit_thread_close(
        &self,
        id: &str,
    ) -> Result<Option<(Arc<()>, ThreadHandle)>, ThreadAssemblyError> {
        let mut state = self.0.state();
        if let Some(preparation) = state.activation.creating.get(id) {
            preparation.cancellation.cancel();
        }
        if let Some(entry) = state.members.entries.get(id)
            && let crate::session::AgentRuntime::Acp(acp) = &entry.runtime
        {
            acp.cancel();
        }
        if state.activation.preparing_children.contains_key(id) {
            return Err(ThreadAssemblyError::Preparing(id.into()));
        }
        Self::close_entry(&mut state, id)
    }

    // Internal cleanup already owns its reservation and operation permit. Only
    // external admission cancels or rejects the target's own preparation.
    pub(crate) fn close_entry(
        state: &mut State,
        id: &str,
    ) -> Result<Option<(Arc<()>, ThreadHandle)>, ThreadAssemblyError> {
        if state
            .activation
            .creating
            .get(id)
            .is_some_and(|preparation| preparation.settlement.is_none())
        {
            return Err(ThreadAssemblyError::Preparing(id.into()));
        }
        if let Some((child, _)) = state
            .activation
            .unpublished_children
            .iter()
            .find(|(_, child)| child.parent == id)
        {
            return Err(ThreadAssemblyError::Preparing(child.clone()));
        }
        if let Some((child, _)) = state.members.entries.iter().find(|(_, entry)| {
            EntryRegistry::membership_parent(&state.members.by_agent, entry) == Some(id)
        }) {
            return Err(ThreadAssemblyError::Descendant(child.clone()));
        }
        if let Some((child, _)) = state
            .activation
            .creating
            .iter()
            .find(|(_, preparation)| preparation.parent_id.as_deref() == Some(id))
        {
            return Err(ThreadAssemblyError::Preparing(child.clone()));
        }
        Ok(state.members.entries.get_mut(id).and_then(|entry| {
            let native = entry.native_mut().ok()?;
            Some({
                native.ready = false;
                (native.incarnation.clone(), native.thread.clone())
            })
        }))
    }

    pub(crate) async fn cancel_and_drain_child_preparations(
        &self,
        id: &str,
    ) -> Result<(), ThreadAssemblyError> {
        loop {
            let changed = self.0.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            let preparing = {
                let mut state = self.0.state();
                if let Some(entry) = state.members.entries.get_mut(id) {
                    match &mut entry.runtime {
                        crate::session::AgentRuntime::Native(native) => native.ready = false,
                        crate::session::AgentRuntime::Acp(acp) => acp.cancel(),
                    }
                }
                state
                    .activation
                    .preparing_children
                    .values()
                    .filter(|child| child.parent == id)
                    .map(|child| child.cancellation.clone())
                    .collect::<Vec<_>>()
            };
            if preparing.is_empty() {
                break;
            }
            for cancellation in preparing {
                cancellation.cancel();
            }
            changed.await;
        }
        {
            let state = self.0.state();
            if let Some((child, _)) = state
                .activation
                .preparing_children
                .iter()
                .find(|(_, preparing)| preparing.parent == id)
            {
                return Err(ThreadAssemblyError::Preparing(child.clone()));
            }
        }
        Ok(())
    }

    pub(crate) async fn close_native_core(
        &self,
        id: &str,
        thread: &ThreadHandle,
        purpose: ClosePurpose,
    ) -> Result<(), ThreadAssemblyError> {
        if purpose == ClosePurpose::Delete {
            match thread.close_for_deletion().await {
                Ok(()) => {}
                Err(ThreadError::Closed)
                    if thread.snapshot().lifecycle == ThreadLifecycle::Closed => {}
                Err(error) => return Err(error.into()),
            }
        } else if self.close_storage_binding(id)?.is_some() {
            self.close_storage_core(id).await?;
        } else {
            match thread.close().await {
                Ok(()) => {}
                Err(ThreadError::Closed)
                    if thread.snapshot().lifecycle == ThreadLifecycle::Closed =>
                {
                    thread.flush().await?;
                }
                Err(error) => return Err(error.into()),
            }
        }
        Ok(())
    }

    pub(crate) async fn close_thread_for_purpose(
        &self,
        id: &str,
        operation: tokio::sync::OwnedMutexGuard<()>,
        purpose: ClosePurpose,
    ) -> Result<(), ThreadAssemblyError> {
        let _seal = self.seal_agent_operation(id);
        self.cancel_and_drain_child_preparations(id).await?;
        let (thread, acp) = {
            let mut state = self.0.state();
            let thread = Self::close_entry(&mut state, id)?;
            let acp = state
                .members
                .entries
                .get(id)
                .and_then(|entry| match &entry.runtime {
                    crate::session::AgentRuntime::Acp(acp) => Some(acp.clone()),
                    crate::session::AgentRuntime::Native(_) => None,
                });
            (thread, acp)
        };
        if let Some(acp) = acp {
            let outcome = acp.close().await;
            if outcome.local_complete {
                let mut state = self.0.state();
                if state
                    .members
                    .entries
                    .get(id)
                    .is_some_and(|entry| match &entry.runtime {
                        crate::session::AgentRuntime::Acp(current) => Arc::ptr_eq(current, &acp),
                        crate::session::AgentRuntime::Native(_) => false,
                    })
                {
                    state.members.remove_entry(id);
                }
            } else {
                return Err(ThreadAssemblyError::Unpublished(id.into()));
            }
            return Ok(());
        }
        let Some((incarnation, thread)) = thread else {
            return Ok(());
        };
        self.attach_close_storage_for_purpose(id, purpose).await?;
        self.prepare_close_for_purpose(id, &thread, purpose).await?;
        // Pause queued execution and let the admitted execution settle while application CAS is
        // still available. A terminal producer must be able to save its diagnostic before this
        // core/writer is retired; closing the core first would force it to recreate its own source.
        if purpose == ClosePurpose::Preserve && thread.snapshot().lifecycle == ThreadLifecycle::Open
        {
            thread.interrupt_turn(None).await?;
            let mut updates = thread.subscribe();
            while thread.snapshot().execution.is_some() {
                if updates.next().await.is_none() {
                    return Err(ThreadAssemblyError::Closed);
                }
            }
        }
        if purpose == ClosePurpose::Preserve && self.0.state().observation.is_some() {
            self.synchronize_observation(id).await?;
        }
        drop(operation);
        self.join_root_operations(id)
            .await
            .map_err(|source| ThreadAssemblyError::Resource {
                operation: "join review producers before core shutdown",
                source: source.into(),
            })?;
        let operation = self.agent_operation(id).await;
        if self.0.state().members.entries.get(id).is_some_and(|entry| {
            entry
                .native()
                .is_ok_and(|native| !Arc::ptr_eq(&native.incarnation, &incarnation))
        }) {
            return Box::pin(self.close_thread_for_purpose(id, operation, purpose)).await;
        }
        self.close_native_core(id, &thread, purpose).await?;
        if purpose == ClosePurpose::Preserve && self.0.state().observation.is_some() {
            self.synchronize_observation(id).await?;
        }
        // Core shutdown can itself publish a terminal. Its producer is registered before the
        // projection ACK. Join outside this gate: storage-only repair may need that same gate.
        drop(operation);
        self.join_root_operations(id)
            .await
            .map_err(|source| ThreadAssemblyError::Resource {
                operation: "join terminal review delivery",
                source: source.into(),
            })?;
        let operation = self.agent_operation(id).await;
        if self.0.state().members.entries.get(id).is_some_and(|entry| {
            entry
                .native()
                .is_ok_and(|native| !Arc::ptr_eq(&native.incarnation, &incarnation))
        }) {
            return Box::pin(self.close_thread_for_purpose(id, operation, purpose)).await;
        }
        let resources = self.native_resources(&thread)?;
        self.finish_native_retirement(id, &resources, &incarnation, purpose)
            .await?;
        let removed = {
            let mut state = self.0.state();
            if state.members.entries.get(id).is_some_and(|entry| {
                entry
                    .native()
                    .is_ok_and(|native| Arc::ptr_eq(&native.incarnation, &incarnation))
            }) {
                state.members.remove_entry(id)
            } else {
                None
            }
        };
        drop(removed);
        Ok(())
    }

    /// Seals shared admission, broadcasts cancellation, then closes every independent
    /// forest/branch concurrently while a global final ACK confirms all admitted preparations
    /// actually drained.
    ///
    /// 与旧实现的区别：全局 preparation 等待不再是**前置** barrier——它与独立森林/分支的关闭并发
    /// （`futures::join!`），所以某个 root 的卡住子分支/准备只阻塞它自己之外，独立资源仍立即
    /// close；但本方法**绝不**在还有已准入 `creating`/`preparing_children` 未真实排空时返回成功，
    /// 因此不会让严格关闭误判生产者已停而停止 writer / 关库 / 发布 `Stopped`。父子依赖（子关闭
    /// 确认先于需要它的父关闭）与 owner 保留规则不变：失败累计、entry 保留、可重试。
    ///
    /// Failures retain their entries and can be retried with this method or `close`.
    ///
    /// 会话收束。等待者取消只放弃自己的等待，不取消已启动的共享任务；重复调用加入同一次运行。
    /// 失败留在 Closing，旧任务结束后才允许重试剩余义务。成功后对象进入 Closed，不能 reopen。
    pub(crate) async fn close_session(&self) -> SessionCloseReport {
        use futures::FutureExt;
        let completion = {
            let mut life = self.0.life();
            if let Some(current) = &life.current
                && current.peek().is_none()
            {
                current.clone()
            } else if life.phase == crate::session::SessionPhase::Closed {
                return life
                    .last
                    .clone()
                    .expect("closed session retains its successful result");
            } else {
                life.phase = crate::session::SessionPhase::Closing;
                self.0.state().close.closing = true;
                let owner = self.clone();
                let task = tokio::spawn(async move {
                    let report = Arc::new(
                        owner
                            .run_close_algorithm()
                            .await
                            .into_iter()
                            .map(|(id, error)| (id, Arc::new(error)))
                            .collect::<Vec<_>>(),
                    );
                    // Completing cleanup publishes its terminal phase even if every waiter left.
                    let mut life = owner.0.life();
                    life.last = Some(Arc::clone(&report));
                    if report.is_empty() {
                        life.phase = crate::session::SessionPhase::Closed;
                    }
                    drop(life);
                    report
                });
                let registry = Arc::downgrade(&self.0);
                let id = self.id().as_str().to_owned();
                let completion = async move {
                    let report = match task.await {
                        Ok(report) => report,
                        Err(source) => Arc::new(vec![(
                            id,
                            Arc::new(ThreadAssemblyError::Resource {
                                operation: "join session close task",
                                source: Box::new(source),
                            }),
                        )]),
                    };
                    // JoinHandle has really finished before failure permits another run.
                    if let Some(registry) = registry.upgrade() {
                        let mut life = registry.life();
                        life.last = Some(Arc::clone(&report));
                        if report.is_empty() {
                            life.phase = crate::session::SessionPhase::Closed;
                        }
                    }
                    report
                }
                .boxed()
                .shared();
                life.current = Some(completion.clone());
                completion
            }
        };
        completion.await
    }

    pub(crate) fn broadcast_close_cancellation(&self) {
        let (preparing, executing, resources) = {
            let mut state = self.0.state();
            state.close.closing = true;
            for preparation in state.activation.creating.values() {
                preparation.resources.cancel();
            }
            for failed in state.activation.failed_preparations.values() {
                failed.resources.cancel();
            }
            let preparing = state
                .activation
                .preparing_children
                .values()
                .map(|child| child.cancellation.clone())
                .chain(
                    state
                        .activation
                        .creating
                        .values()
                        .map(|preparation| preparation.cancellation.clone()),
                )
                .collect::<Vec<_>>();
            for entry in state.members.entries.values() {
                if let crate::session::AgentRuntime::Acp(acp) = &entry.runtime {
                    acp.cancel();
                }
            }
            let executing = state
                .members
                .entries
                .values_mut()
                .filter_map(|entry| {
                    let native = entry.native_mut().ok()?;
                    Some({
                        native.ready = false;
                        native.thread.clone()
                    })
                })
                .collect::<Vec<_>>();
            let resources = state
                .members
                .entries
                .values()
                .filter_map(|entry| {
                    let native = entry.native().ok()?;
                    Some(native.resources.clone())
                })
                .chain(
                    state
                        .activation
                        .creating
                        .values()
                        .filter_map(|preparation| preparation.resources.native().cloned()),
                )
                .chain(
                    state
                        .activation
                        .unpublished_children
                        .values()
                        .map(|child| child.workspace.native_resources()),
                )
                .chain(
                    state
                        .activation
                        .failed_preparations
                        .values()
                        .filter_map(|failed| failed.resources.native().cloned()),
                )
                .collect::<Vec<_>>();
            (preparing, executing, resources)
        };
        for cancellation in preparing {
            cancellation.cancel();
        }
        for thread in executing {
            thread.request_shutdown();
        }
        for resources in resources {
            resources.cancel_tool_producers();
        }
    }

    pub(crate) async fn run_close_algorithm(&self) -> Vec<(String, ThreadAssemblyError)> {
        // 共享准入先封闭，所有准备过程 cancellation 先广播；此处不等待它们排空。
        self.broadcast_close_cancellation();

        let mut covered: BTreeSet<String> = BTreeSet::new();
        let mut failures = Vec::new();

        // 第一轮：独立森林/orphan 关闭与「全部已准入 creating/preparing 真实排空」的全局最终 ACK
        // 并发推进——独立资源先开始自身 close，不被全局 ACK 前置阻塞；全局 ACK 又保证最终成功前
        // 不存在仍在清理/持有资源的准备 owner。
        let (roots, orphan_unpublished) = self.select_uncovered_roots(&covered);
        self.mark_covered(&mut covered, &roots, &orphan_unpublished);
        let (first_failures, ()) = futures::join!(
            self.close_independent_batch(roots, orphan_unpublished),
            self.await_all_preparations_drained(),
        );
        failures.extend(first_failures);

        // 迟到 owner：准备排空后才可见、第一轮快照未覆盖的 entries/unpublished（例如 closing 前
        // 已准入、快照之后才插入 entry、setup 失败后 cleanup 也失败而保留 owner），用同一局部化
        // 方式收尾。此刻不会再有新的 assembly / child preparation，集合只会收缩，循环终止。
        loop {
            let (roots, orphan_unpublished) = self.select_uncovered_roots(&covered);
            if roots.is_empty() && orphan_unpublished.is_empty() {
                break;
            }
            self.mark_covered(&mut covered, &roots, &orphan_unpublished);
            let batch_failures = self
                .close_independent_batch(roots, orphan_unpublished)
                .await;
            failures.extend(batch_failures);
        }
        let failed = self
            .0
            .state()
            .activation
            .failed_preparations
            .keys()
            .cloned()
            .collect::<Vec<_>>();
        let outcomes = futures::future::join_all(failed.into_iter().map(|id| async move {
            let result = self.close_failed_preparation(&id).await;
            (id, result)
        }))
        .await;
        for (id, result) in outcomes {
            if let Err(error) = result {
                failures.push((id, error));
            }
        }
        // Closing a core can still publish its final normal finish. Keep the retained operation
        // owner open until every such producer has registered and its source owner has drained.
        if failures.is_empty()
            && let Err(source) = self.close_agent_operations().await
        {
            failures.push((
                "agent-operations".into(),
                ThreadAssemblyError::Resource {
                    operation: "join collaboration operations",
                    source: source.into(),
                },
            ));
        }
        failures
    }

    /// 选取当前尚未负责（`covered` 之外）的独立森林根与 orphan unpublished 子资源。
    ///
    /// 根 = 父 entry 不在册，或父 entry 已在 `covered`（其自身 close 不会再等待该子项）。orphan =
    /// 父 entry 不在册，或父 entry 已在 `covered`。这样迟到 owner 也有归属、不被漏关。
    pub(crate) fn select_uncovered_roots(
        &self,
        covered: &BTreeSet<String>,
    ) -> (Vec<String>, Vec<String>) {
        let state = self.0.state();
        let mut roots = Vec::new();
        for (id, entry) in state.members.entries.iter() {
            if covered.contains(id) {
                continue;
            }
            let parent =
                EntryRegistry::membership_parent(&state.members.by_agent, entry).map(str::to_owned);
            let parent_present = parent
                .as_deref()
                .is_some_and(|parent| state.members.entries.contains_key(parent));
            let parent_covered = parent
                .as_deref()
                .is_some_and(|parent| covered.contains(parent));
            if !parent_present || parent_covered {
                roots.push(id.clone());
            }
        }
        let mut orphan_unpublished = Vec::new();
        for (id, child) in state.activation.unpublished_children.iter() {
            if covered.contains(id) {
                continue;
            }
            if !state.members.entries.contains_key(&child.parent) || covered.contains(&child.parent)
            {
                orphan_unpublished.push(id.clone());
            }
        }
        (roots, orphan_unpublished)
    }

    /// 把一批根及其可达子树、以及 orphan 子资源标记为已负责，避免后续批次重复 close。
    pub(crate) fn mark_covered(
        &self,
        covered: &mut BTreeSet<String>,
        roots: &[String],
        orphan_unpublished: &[String],
    ) {
        let state = self.0.state();
        let mut stack = roots.to_vec();
        while let Some(id) = stack.pop() {
            if !covered.insert(id.clone()) {
                continue;
            }
            for (child, entry) in state.members.entries.iter() {
                if EntryRegistry::membership_parent(&state.members.by_agent, entry)
                    == Some(id.as_str())
                {
                    stack.push(child.clone());
                }
            }
        }
        for id in orphan_unpublished {
            covered.insert(id.clone());
        }
    }

    /// 并发关闭一批独立森林根与 orphan unpublished，返回累计失败（`join_all` 保序，顺序确定）。
    pub(crate) async fn close_independent_batch(
        &self,
        roots: Vec<String>,
        orphan_unpublished: Vec<String>,
    ) -> Vec<(String, ThreadAssemblyError)> {
        let mut root_futures = Vec::with_capacity(roots.len());
        for root in roots {
            root_futures.push(self.close_entry_tree(root));
        }
        let mut orphan_futures = Vec::with_capacity(orphan_unpublished.len());
        for child in orphan_unpublished {
            orphan_futures.push(async move {
                // 只有该子资源自身的创建准备排空后才可 discard（`close_thread` 会拒绝 preparing 者）。
                self.await_own_preparations_drained(&child).await;
                match self.discard_unpublished_child(&child).await {
                    Ok(()) => Vec::new(),
                    Err(error) => vec![(child, error)],
                }
            });
        }
        let (tree_failures, orphan_failures) = futures::join!(
            futures::future::join_all(root_futures),
            futures::future::join_all(orphan_futures),
        );
        let mut failures = Vec::new();
        for group in tree_failures {
            failures.extend(group);
        }
        for group in orphan_failures {
            failures.extend(group);
        }
        failures
    }

    /// 全局最终 ACK：等待**全部**已准入的 `creating`/`preparing_children` owner 真实排空。
    ///
    /// 与独立树关闭并发进行，不是前置 barrier；但 close_session 成功返回前必须等到它完成，避免仍在
    /// 清理/持有资源的准备 owner 被误判为已停（否则严格关闭会停 writer / 关库 / 发布 `Stopped`）。
    /// 取消已广播，`closing` 保证不会新增准备 owner，因此集合只会收缩。
    pub(crate) async fn await_all_preparations_drained(&self) {
        loop {
            let changed = self.0.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            let drained = {
                let state = self.0.state();
                state.activation.creating.is_empty()
                    && state.activation.preparing_children.is_empty()
            };
            if drained {
                break;
            }
            changed.await;
        }
    }

    /// 递归关闭一个在册 entry 及其整棵依赖子树，只等待自身需要的子资源与准备过程。
    ///
    /// 依赖：该 entry 的每个子 entry（`parent_id == id`）、它自己的 unpublished 子资源，以及它
    /// 自己的 creating/preparing 子过程。它们彼此独立，因此并发收束；全部就绪后才 `close(id)`。
    /// 只等待自身依赖，绝不等待其他森林/分支。失败累计并保留 owner，返回本子树全部失败（含 id
    /// 自身）。通过 boxed future 递归，避免 async fn 的无限类型。
    pub(crate) fn close_entry_tree<'a>(
        &'a self,
        id: String,
    ) -> futures::future::BoxFuture<'a, Vec<(String, ThreadAssemblyError)>> {
        self.close_entry_tree_for_purpose(id, ClosePurpose::Preserve)
    }

    pub(crate) fn close_entry_tree_for_purpose<'a>(
        &'a self,
        id: String,
        purpose: ClosePurpose,
    ) -> futures::future::BoxFuture<'a, Vec<(String, ThreadAssemblyError)>> {
        self.close_entry_tree_in_scope(id, purpose, None)
    }

    pub(crate) fn close_entry_tree_in_scope<'a>(
        &'a self,
        id: String,
        purpose: ClosePurpose,
        dependencies: Option<&'a BTreeMap<String, Vec<String>>>,
    ) -> futures::future::BoxFuture<'a, Vec<(String, ThreadAssemblyError)>> {
        Box::pin(async move {
            let mut failures = Vec::new();

            // 一次持锁快照自身直接子依赖，不跨 await。
            let (child_entries, child_unpublished) = {
                let state = self.0.state();
                let mut child_entries = Vec::new();
                let mut child_unpublished = Vec::new();
                if let Some(dependencies) = dependencies {
                    child_entries.extend(dependencies.get(&id).into_iter().flatten().cloned());
                } else {
                    for (child, entry) in state.members.entries.iter() {
                        if EntryRegistry::membership_parent(&state.members.by_agent, entry)
                            == Some(id.as_str())
                        {
                            child_entries.push(child.clone());
                        }
                    }
                }
                for (child, unpublished) in state.activation.unpublished_children.iter() {
                    if unpublished.parent == id {
                        child_unpublished.push(child.clone());
                    }
                }
                (child_entries, child_unpublished)
            };

            let mut child_futures: Vec<
                futures::future::BoxFuture<'a, Vec<(String, ThreadAssemblyError)>>,
            > = Vec::with_capacity(child_entries.len());
            for child in child_entries {
                child_futures.push(self.close_entry_tree_in_scope(child, purpose, dependencies));
            }
            let mut unpublished_futures = Vec::with_capacity(child_unpublished.len());
            for child in child_unpublished {
                unpublished_futures.push(async move {
                    // 该子资源自身的创建准备排空后才可 discard（`discard_unpublished_child` 会拒绝
                    // preparing 者）。
                    self.await_own_preparations_drained(&child).await;
                    let outcome = self.discard_unpublished_child(&child).await;
                    (child, outcome)
                });
            }
            // 自身的 creating/preparing 子过程：取消已由 `close_session` 会话内广播，这里只对自身这部分
            // 有界等待，不等待其他分支。
            let own_preparations = self.await_own_preparations_drained(&id);
            let (child_failures, unpublished_outcomes, ()) = futures::join!(
                futures::future::join_all(child_futures),
                futures::future::join_all(unpublished_futures),
                own_preparations,
            );
            for group in child_failures {
                failures.extend(group);
            }
            for (child, outcome) in unpublished_outcomes {
                if let Err(error) = outcome {
                    failures.push((child, error));
                }
            }

            // 依赖就绪后才关闭自身：原 `close` 的真实父子保护与 incarnation/owner 保留规则不变，
            // 子关闭未确认（失败保留）时 `close` 返回对应错误并被累计，绝不早释放。
            if let Err(error) = self.close_for_purpose(&id, purpose).await {
                failures.push((id, error));
            } else if purpose == ClosePurpose::Delete
                && let Err(error) = self.close_failed_preparation(&id).await
            {
                failures.push((id, error));
            }
            failures
        })
    }

    /// 等待并只等待某个节点的自身依赖型准备过程排空。
    ///
    /// 覆盖两类真实依赖：节点**自身**的创建准备（`creating`/`preparing_children` 含该 id），以及
    /// 节点**子项**的创建准备（`creating` 的 parent/`preparing_children` 的 parent 指向该 id）。
    /// 取消已由 `close_session` 会话内广播；这里只在该节点确有对应准备过程时等待其真实离开注册表，不等待
    /// 任何其他分支或全局集合。`closing`/`entry.native_mut()?.ready =false` 保证等待期间不会产生新的子过程。
    pub(crate) async fn await_own_preparations_drained(&self, id: &str) {
        loop {
            let changed = self.0.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            let blocked = {
                let state = self.0.state();
                state.activation.creating.contains_key(id)
                    || state.activation.preparing_children.contains_key(id)
                    || state
                        .activation
                        .creating
                        .values()
                        .any(|preparation| preparation.parent_id.as_deref() == Some(id))
                    || state
                        .activation
                        .preparing_children
                        .values()
                        .any(|child| child.parent == id)
            };
            if !blocked {
                break;
            }
            changed.await;
        }
    }
}
