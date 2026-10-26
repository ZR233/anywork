//! Direct SQL history queries; execution owners are never activated for historical pages.
//!
//! 冷历史读取复用 `history.rs` 的只读句柄：它只读打开一个**已存在**的 history 数据库，
//! 不创建目录/数据库、不执行 schema 变更；缺失的库以空 Turn 页回答，损坏或身份不符的库
//! 直接失败闭锁。只有显式激活/写入才会由历史 writer 建库。

use anyhow::Result;

use crate::studio::StudioRuntime;

impl StudioRuntime {
    pub fn list_thread_turns(
        &self,
        thread_id: &str,
        cursor: Option<&str>,
        limit: usize,
    ) -> impl std::future::Future<Output = Result<pl_protocol::ThreadTurnPage>> + Send + 'static + use<>
    {
        let runtime = self.clone();
        let thread_id = thread_id.to_owned();
        let cursor = cursor.map(str::to_owned);
        self.read_calls.run(async move {
            runtime.read_owned_thread(&thread_id).await?;
            // Preserve the original bounded, cursor-validated history implementation (2 MiB
            // ordinary page budget and its oversize-first-item progress exception). This is a
            // page read, not a cross-page transaction snapshot or an execution activation.
            runtime
                .read_timeline_history(&thread_id)
                .await?
                .turn_page(cursor.as_deref(), limit)
                .await
        })
    }
}
