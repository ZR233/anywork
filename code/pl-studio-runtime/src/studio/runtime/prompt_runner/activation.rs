//! Thread 对应 agent 的激活、驻留恢复与 canonical owner 读取。

use anyhow::Result;

use crate::studio::{ThreadKind, ThreadRecord, ThreadVisibility};

use super::super::StudioRuntime;
use super::{UserThreadAction, ensure_user_root_target};
use crate::thread_assembler::ThreadAssemblyError;

impl StudioRuntime {
    /// Prepare a user input while the caller holds the Studio lifecycle lock.
    ///
    /// Activation owns its own preparation task and takes the per-agent permit itself. Do not
    /// hold that permit while awaiting it. After activation, retain the permit through Core's
    /// admission and revalidate the exact session and Thread incarnation under that permit.
    pub(super) async fn prepare_prompt_admission(
        &self,
        id: &str,
        action: UserThreadAction,
        input_id: &str,
    ) -> Result<(
        ThreadRecord,
        pl_core::thread::ThreadHandle,
        tokio::sync::OwnedMutexGuard<()>,
    )> {
        let started = std::time::Instant::now();
        self.ensure_prompt_runtime_ready().await?;
        let thread = self.ensure_thread_owner(id).await?;
        let operation_started = std::time::Instant::now();
        let session = self.require_session(id)?;
        let permit = session.agent_operation(id).await;
        tracing::debug!(
            target: "prompt_submission",
            thread_id = id,
            input_id,
            ?action,
            owner_ready_us = operation_started.duration_since(started).as_micros() as u64,
            operation_wait_us = operation_started.elapsed().as_micros() as u64,
            "prompt thread admission acquired"
        );
        let record = self.read_owned_thread(id).await?;
        ensure_user_root_target(&record, action)?;
        self.validate_prompt_owner(id, &session, &thread)?;
        Ok((record, thread, permit))
    }

    pub(super) fn validate_prompt_owner(
        &self,
        id: &str,
        session: &crate::session::SessionRuntime,
        thread: &pl_core::thread::ThreadHandle,
    ) -> Result<()> {
        let current = self.require_session(id)?;
        if !std::sync::Arc::ptr_eq(&session.0, &current.0)
            || !session
                .thread(id)
                .is_some_and(|owner| owner.same_instance(thread))
        {
            return Err(ThreadAssemblyError::Closed.into());
        }
        session.ensure_agent_admission_open(id)?;
        Ok(())
    }

    pub(in crate::studio::runtime) async fn register_new_thread(
        &self,
        thread: ThreadRecord,
    ) -> Result<()> {
        self.ensure_thread_owner(&thread.id).await?;
        Ok(())
    }

    pub(in crate::studio::runtime) async fn read_owned_thread(
        &self,
        thread_id: &str,
    ) -> Result<ThreadRecord> {
        match self.find_owned_thread(thread_id).await? {
            Some(record) => Ok(record),
            // An unknown Thread is an API-visible rejection, not an internal failure: the transports
            // must be able to answer 404 with a typed reason.
            None => Err(anyhow::Error::new(crate::StudioError::not_found("session"))),
        }
    }

    pub(crate) async fn find_owned_thread(&self, thread_id: &str) -> Result<Option<ThreadRecord>> {
        let Some(thread) = self
            .agent_facility
            .product_events
            .thread_snapshot(thread_id)?
        else {
            return Ok(None);
        };
        Ok(Some(ThreadRecord {
            id: thread.id,
            workspace_id: thread.workspace_id,
            title: thread.title,
            mode: thread.mode,
            workspace_mode: thread.workspace_mode,
            delegation_mode: thread.delegation_mode,
            delegation_preference: thread.delegation_preference,
            frozen_model: thread.frozen_model,
            workspace_path: thread.workspace_path,
            created_at: thread.created_at,
            updated_at: thread.updated_at,
            last_user_message_at: thread.last_user_message_at,
            visibility: if thread.archived {
                ThreadVisibility::Archived
            } else {
                ThreadVisibility::Active
            },
            thread_kind: if thread.parent_thread_id.is_some() {
                ThreadKind::Agent
            } else {
                ThreadKind::Root
            },
            parent_thread_id: thread.parent_thread_id,
            root_thread_id: thread.root_thread_id,
            agent_path: thread.agent_path,
            role: thread.role,
            status: thread.status,
            summary: None,
            error: None,
            runtime_updated_at: None,
        }))
    }
}
