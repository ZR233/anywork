//! Point-in-time Thread snapshots and usage folds. Continuous State delivery lives in
//! `conversation_state_feed` and does not activate execution.
use super::StudioRuntime;
use anyhow::Result;
use pl_core::thread::ThreadSnapshot;

impl StudioRuntime {
    /// Uses the original bounded State assembler through the independent Current port.
    pub async fn thread_snapshot(&self, thread_id: &str) -> Result<crate::ThreadSnapshot> {
        let reader = self
            .open_current_reader(
                thread_id,
                crate::CURRENT_PROTOCOL_VERSION,
                crate::ReadDemand {
                    max_items: 128,
                    max_bytes: crate::CHAT_BATCH_MAX_BYTES,
                },
            )
            .await?;
        let result = reader
            .snapshot(crate::ReadDemand {
                max_items: 128,
                max_bytes: crate::CHAT_BATCH_MAX_BYTES,
            })
            .await;
        reader.close().await?;
        Ok(*result?.state)
    }

    /// 该 Thread 的 typed 持久化快照；没有登记过持久化的 Thread 为 `None`（未知不等于健康）。
    ///
    /// 这是 [`crate::ThreadStorageState`] 的 typed 来源：故障类别、代数与水位都来自协调器
    /// 的类型化值，不是错误文本的解析结果。
    pub(in crate::studio) fn thread_persistence_snapshot(
        &self,
        thread_id: &str,
    ) -> Option<crate::ThreadPersistenceSnapshot> {
        self.store
            .thread_persistence()
            .queue_snapshot()
            .threads
            .into_iter()
            .find(|snapshot| snapshot.thread_id == thread_id)
    }

    pub(in crate::studio) async fn read_thread_state(
        &self,
        thread_id: &str,
    ) -> Result<ThreadSnapshot> {
        if let Some((_, handle)) = self
            .sessions
            .observed_threads()
            .into_iter()
            .find(|(id, _)| id == thread_id)
        {
            let snapshot = handle.snapshot();
            self.store
                .thread_persistence()
                .seed_usage(thread_id, snapshot.usage_summary.clone());
            return Ok(snapshot);
        }
        let thread = self.read_protocol_thread(thread_id).await?;
        // A read-only projection never prepares storage: it reports only an already-complete
        // current document, so a legacy checkpoint stays invisible until explicit activation.
        let current =
            crate::studio::thread_factory::recovery::load_current_read_only(&self.store, &thread)
                .await?
                .ok_or_else(|| anyhow::anyhow!("Thread has no saved current"))?;
        let state = current.state.to_paused_snapshot();
        self.store
            .thread_persistence()
            .seed_usage(thread_id, state.usage_summary.clone());
        Ok(state)
    }
}
