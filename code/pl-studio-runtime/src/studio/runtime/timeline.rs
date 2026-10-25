//! 只读历史访问与共享会话解析。
//!
//! 这里只提供两件事：把 Thread 的共享 [`Session`] 内容源取出来（不激活 owner、不 flush writer），
//! 以及为独立的 Turns 历史打开一个已落盘且越过 checkpoint 栅栏的 history 句柄。Timeline 正文本身
//! 由 [`super::timeline_content`] 统一读取，不再有第二套纯 SQL 正文入口。
use super::StudioRuntime;
use crate::studio::storage::history::HistoryStore;
use anyhow::Result;
use pl_core::chat::Session;

impl StudioRuntime {
    /// Shares the same in-memory timeline with any live view or future producer.
    pub(in crate::studio::runtime) async fn chat_session(
        &self,
        thread_id: &str,
    ) -> Result<Session> {
        self.read_owned_thread(thread_id).await?;
        self.store.chat_session(thread_id).await
    }

    /// 只读地打开一个 Thread 的 history 数据库，并校验它已越过 durable checkpoint 栅栏。
    ///
    /// 关键约束：不激活 owner、不 flush writer、不触发恢复。需要的持久化栅栏直接来自已落盘的
    /// checkpoint（`history_fence`），因此冷 Thread 与热 Thread 走同一条只读路径。栅栏未满足时以
    /// 类型化 `Busy` 失败闭锁，绝不回落到落后行、也绝不因此自动恢复或激活 owner；空库与真实栅栏
    /// 落后是两种不同的事实。
    /// Same durable-fence check as [`Self::ensure_timeline_history`] without preparing storage.
    ///
    /// Read-only lookups (an accepted-operation query, or the repeat check of a control command
    /// before the owner is activated) must not migrate a legacy checkpoint or delete the files it
    /// replaced. A storage fault or an unreached fence is propagated as its typed error; only a
    /// reliable "no durable record" answer may become NotFound.
    pub(super) async fn read_timeline_history(&self, thread_id: &str) -> Result<HistoryStore> {
        let history = self.store.history(thread_id).await?;
        let thread = self.read_protocol_thread(thread_id).await?;
        let fence = crate::studio::thread_factory::recovery::load_checkpoint_read_only(
            &self.store,
            &thread,
        )
        .await?
        .map_or(0, |checkpoint| checkpoint.history_fence);
        let watermark = history.watermark().await?;
        ensure_fence_reached(watermark, fence)?;
        Ok(history)
    }

    pub(super) async fn ensure_timeline_history(&self, thread_id: &str) -> Result<HistoryStore> {
        let history = self.store.history(thread_id).await?;
        let thread = self.read_protocol_thread(thread_id).await?;
        let fence = crate::studio::thread_factory::recovery::load_checkpoint(&self.store, &thread)
            .await?
            .map_or(0, |checkpoint| checkpoint.history_fence);
        let watermark = history.watermark().await?;
        ensure_fence_reached(watermark, fence)?;
        Ok(history)
    }
}

/// A watermark behind the durable fence is a retryable storage condition, never "not found".
///
/// Read paths must surface it as its own typed error so a client can tell a not-yet-recovered save
/// apart from an identity that really was never accepted.
fn ensure_fence_reached(watermark: u64, fence: u64) -> Result<()> {
    if watermark >= fence {
        return Ok(());
    }
    Err(anyhow::Error::new(pl_protocol::studio::StudioError::new(
        pl_protocol::studio::StudioErrorCode::Busy,
        "Thread history is behind its durable checkpoint fence; pending persistence must recover first",
        true,
    )))
}
