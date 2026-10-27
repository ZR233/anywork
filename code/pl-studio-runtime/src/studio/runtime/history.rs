//! Direct SQL history queries; execution owners are never activated for historical pages.
//!
//! 无句柄的独立轮次入口先显式准备已有 SQLite 内容，再通过只读查询核对 checkpoint 栅栏。
//! 不推进模型或执行身份准备，不装配 owner；缺失库不创建，损坏或身份不符直接失败。

use anyhow::Result;

use crate::studio::StudioRuntime;

impl StudioRuntime {
    pub async fn list_thread_turns(
        &self,
        thread_id: &str,
        cursor: Option<&str>,
        limit: usize,
    ) -> Result<pl_protocol::ThreadTurnPage> {
        self.prepare_timeline_history(thread_id)
            .await?
            .turn_page(cursor, limit)
            .await
    }
}
