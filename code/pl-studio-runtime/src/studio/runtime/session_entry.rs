//! 跨 Thread 入口先按目录 `SessionId` 定位会话，再调用该代次自己的方法。
//!
//! 这里不是成员强表，也不转发旧 assembler 的方法全集。冷读找不到已物化代次时返回
//! `None`，不因此激活成员。
use super::StudioRuntime;
use crate::session::SessionRuntime;
use crate::thread_assembler::ThreadAssemblyError;

impl StudioRuntime {
    /// 目录已有身份时只返回已物化代次。目录没有这一行时，才看尚未写入目录的在途准备。
    pub(super) fn session_of(&self, thread_id: &str) -> Option<SessionRuntime> {
        if let Some((identity, _, _)) = self
            .agent_facility
            .product_events
            .agent_execution_identity(thread_id)
        {
            return self.sessions.get(&identity.session_id);
        }
        self.sessions.holding(thread_id)
    }

    pub(super) fn require_session(
        &self,
        thread_id: &str,
    ) -> Result<SessionRuntime, ThreadAssemblyError> {
        self.session_of(thread_id)
            .ok_or_else(|| ThreadAssemblyError::Identity(thread_id.to_owned()))
    }

    /// 归档/删除要封住的是目录里的会话代次，不是一个全局成员表。
    /// 多个根不属于同一会话时拒绝，不猜应该封哪一个。
    pub(super) fn session_for_roots(
        &self,
        roots: &[String],
    ) -> Result<SessionRuntime, ThreadAssemblyError> {
        let mut session_id = None;
        for root in roots {
            let (identity, _, _) = self
                .agent_facility
                .product_events
                .agent_execution_identity(root)
                .ok_or_else(|| ThreadAssemblyError::Identity(root.clone()))?;
            match &session_id {
                None => session_id = Some(identity.session_id),
                Some(existing) if existing != &identity.session_id => {
                    return Err(ThreadAssemblyError::Identity(root.clone()));
                }
                Some(_) => {}
            }
        }
        let session_id = session_id
            .ok_or_else(|| ThreadAssemblyError::Identity("archive scope is empty".into()))?;
        self.sessions.materialize(&session_id)
    }
}
