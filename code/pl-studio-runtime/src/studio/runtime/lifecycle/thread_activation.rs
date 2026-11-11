//! Product activation follows saved ancestry and shares the single Thread assembler.
use super::super::StudioRuntime;
use crate::studio::ThreadRecord;
use crate::thread_assembler::ThreadActivation;
use anyhow::{Context, Result};

impl StudioRuntime {
    #[tracing::instrument(target = "thread_preparation", level = "debug", skip_all, fields(thread_id = id))]
    pub(in crate::studio) async fn ensure_thread_owner(
        &self,
        id: &str,
    ) -> Result<pl_core::thread::ThreadHandle> {
        tracing::debug!(
            target: "conversation_work",
            thread_id = id,
            execution_activation = 1,
            "execution owner requested"
        );
        // Directory identity/backend admission precedes workspace, history, model and tool reads.
        let requested_activation = self.thread_factory.activation(id)?;
        // Keep the preflight snapshot and its platform-dependent IO state out of ancestry
        // activation's inline future, while retaining this caller's cancellation ownership.
        let preflight_started = std::time::Instant::now();
        tracing::debug!(target: "thread_preparation", stage = "activation_preflight", "starting");
        Box::pin(self.verify_activation_preflight(id)).await?;
        tracing::debug!(target: "thread_preparation", stage = "activation_preflight", elapsed_ms = preflight_started.elapsed().as_millis() as u64, "completed");
        // This operation already borrows the runtime. Retain only the residency owner, not
        // another full StudioRuntime clone, across activation/recovery awaits.
        let _activation_pin = self.residency.pin_many([id.to_owned()]);
        if let Some(thread) = self.session_of(id).and_then(|session| session.thread(id)) {
            self.residency.touch(id).await;
            self.enforce_residency_limit().await;
            return Ok(thread);
        }
        let mut ancestry: Vec<(ThreadActivation, ThreadRecord)> = Vec::new();
        let mut seen = std::collections::BTreeSet::new();
        let mut cursor = id.to_owned();
        loop {
            anyhow::ensure!(seen.insert(cursor.clone()), "cyclic Thread ancestry");
            let member = self
                .agent_facility
                .product_events
                .directory_member(&cursor)?
                .or(self.store.directory_member(&cursor)?)
                .context("activation directory member is missing")?;
            if !member.is_native() {
                // Parentage requires its real product identity, not a Native handle,
                // model route, history or a newly opened ACP connection.
                let identity = pl_protocol::AgentThreadIdentity {
                    session_id: pl_protocol::SessionId::new(member.session.session_id)?,
                    agent_id: pl_protocol::AgentId::new(member.agent.agent_id)?,
                    parent_agent_id: member
                        .agent
                        .parent_agent_id
                        .map(pl_protocol::AgentId::new)
                        .transpose()?,
                    thread_id: pl_protocol::ThreadId::new(member.agent.thread_id)?,
                };
                self.sessions
                    .materialize(&identity.session_id)?
                    .retain_directory_identity(&identity)?;
                if let Some(parent) = member.parent_thread_id {
                    cursor = parent;
                    continue;
                }
                break;
            }
            if self
                .session_of(&cursor)
                .and_then(|session| session.thread(&cursor))
                .is_some()
            {
                break;
            }
            let record = self.read_owned_thread(&cursor).await?;
            self.store.ensure_agent_execution_allowed(&cursor).await?;
            // The requested target was just verified by preflight (also for hot owners).
            // Only additional cold ancestors need their own physical workspace check.
            if cursor != id {
                self.verify_thread_execution_preparation(
                    &pl_protocol::Thread::from(record.clone()),
                    None,
                )
                .await?;
            }
            self.check_thread_execution_access(&pl_protocol::Thread::from(record.clone()))?;
            anyhow::ensure!(
                record.visibility == crate::studio::ThreadVisibility::Active,
                "archived Thread cannot be activated for execution"
            );
            let parent = record.parent_thread_id.clone();
            let activation = if record.id == id {
                requested_activation.clone()
            } else {
                self.thread_factory.activation(&record.id)?
            };
            ancestry.push((activation, record));
            let Some(parent) = parent else {
                break;
            };
            cursor = parent;
        }
        for (identity, record) in ancestry.into_iter().rev() {
            let activated_id = identity.id().to_owned();
            let session = self.sessions.materialize(&identity.agent.session_id)?;
            // The assembler owns/coalesces preparation. Its waiter need not inline that
            // state alongside the runtime's ancestry records and residency protection.
            let assembler_started = std::time::Instant::now();
            tracing::debug!(target: "thread_preparation", thread_id = %activated_id, stage = "assembler", "starting");
            if let Err(error) =
                Box::pin(session.activate(identity, self.thread_factory.clone())).await
            {
                // `worktree` 会话激活失败必须显式发布该 Thread 的 Recovery，
                // 不允许静默回落到主工作区。
                if record.workspace_mode == pl_protocol::ThreadWorkspaceMode::Worktree {
                    let failure = anyhow::Error::from(error);
                    self.publish_session_workspace_issue(
                        &pl_protocol::Thread::from(record),
                        &failure,
                    )
                    .await;
                    return Err(failure);
                }
                return Err(error.into());
            }
            tracing::debug!(target: "thread_preparation", thread_id = %activated_id, stage = "assembler", elapsed_ms = assembler_started.elapsed().as_millis() as u64, "completed");
            self.residency.touch(&activated_id).await;
        }
        // 主会话载入/恢复时就地核对它自己的子成员：中断事实与待决摘要只在各自保存的检查点里
        // 读取并投影到目录，不激活成员、不重建工作区、不发模型请求（design/17）。
        let restored_root = self.read_owned_thread(id).await?;
        if restored_root.parent_thread_id.is_none() {
            self.thread_observations.reconcile_children(id).await?;
        }
        self.residency.touch(id).await;
        self.enforce_residency_limit().await;
        self.session_of(id)
            .and_then(|session| session.thread(id))
            .context("Thread activation did not publish its owner")
    }

    async fn verify_activation_preflight(&self, id: &str) -> Result<()> {
        let record = self.read_protocol_thread(id).await?;
        self.store.ensure_agent_execution_allowed(id).await?;
        self.check_thread_read_access(&record)?;
        let live = self
            .session_of(id)
            .and_then(|session| session.observed_thread(id))
            .map(|thread| thread.snapshot());
        self.verify_thread_execution_preparation(&record, live.as_ref())
            .await?;
        self.check_thread_execution_access(&record)?;
        self.store.ensure_agent_execution_allowed(id).await?;
        Ok(())
    }
}

#[cfg(test)]
mod future_sizes {
    use super::*;

    fn check<Input, F: std::future::Future + Send>(name: &str, _: impl FnOnce(Input) -> F) {
        let bytes = std::mem::size_of::<F>();
        eprintln!("{name}: {bytes} bytes");
        assert!(
            bytes <= 16 * 1024,
            "{name} has {bytes} bytes of inline state"
        );
    }

    #[test]
    fn activation_futures_remain_bounded() {
        check("directory lookup", |runtime: &'static StudioRuntime| {
            runtime.read_owned_thread("size")
        });
        check("execution seal", |runtime: &'static StudioRuntime| {
            runtime.store.ensure_agent_execution_allowed("size")
        });
        check(
            "workspace failure",
            |(runtime, thread, error): (
                &'static StudioRuntime,
                &'static pl_protocol::Thread,
                &'static anyhow::Error,
            )| { runtime.publish_session_workspace_issue(thread, error) },
        );
        check(
            "workspace preflight",
            |(runtime, thread): (&'static StudioRuntime, &'static pl_protocol::Thread)| {
                runtime.verify_thread_execution_preparation(thread, None)
            },
        );
        check(
            "workspace verification",
            |(runtime, thread): (&'static StudioRuntime, &'static pl_protocol::Thread)| {
                runtime.thread_factory.verify_execution_workspace(
                    thread,
                    None,
                    crate::studio::thread_factory::ExecutionWorkspaceCheck::Prepare,
                )
            },
        );
        check(
            "assembler activation",
            |(session, runtime): (
                &'static crate::session::SessionRuntime,
                &'static StudioRuntime,
            )| {
                session.activate(
                    ThreadActivation::native_test("size", None),
                    runtime.thread_factory.clone(),
                )
            },
        );
        check("cold children", |runtime: &'static StudioRuntime| {
            runtime.thread_observations.reconcile_children("size")
        });
        check(
            "residency enforcement",
            |runtime: &'static StudioRuntime| runtime.enforce_residency_limit(),
        );
    }
}
