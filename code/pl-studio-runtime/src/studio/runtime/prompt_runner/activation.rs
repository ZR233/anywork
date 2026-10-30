//! Thread 对应 agent 的激活、驻留恢复与 canonical owner 读取。

use anyhow::Result;

use crate::studio::{ThreadKind, ThreadRecord, ThreadVisibility};

use super::super::StudioRuntime;

impl StudioRuntime {
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
            None => Err(anyhow::Error::new(
                pl_protocol::studio::StudioError::not_found("session"),
            )),
        }
    }

    pub(crate) async fn find_owned_thread(&self, thread_id: &str) -> Result<Option<ThreadRecord>> {
        let thread = if let Some(thread) = self
            .agent_facility
            .product_events
            .thread_snapshot(thread_id)
        {
            thread
        } else {
            match self.store.read_thread(thread_id).await {
                Ok(Some(record)) => pl_protocol::Thread::from(record),
                Ok(None) => return Ok(None),
                Err(error) => return Err(error),
            }
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
