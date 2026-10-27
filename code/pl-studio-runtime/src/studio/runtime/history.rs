//! Direct SQL history queries; execution owners are never activated for historical pages.
//!
//! 独立轮次页先显式准备已有历史，再以只读句柄查询。缺失库仍为空且不创建；
//! 准备不导入 TOML、不激活执行 owner，损坏或身份不符直接失败。

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
