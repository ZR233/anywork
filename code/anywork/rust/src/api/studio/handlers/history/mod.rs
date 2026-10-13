use crate::api::studio::bridge_runtime::active_bridge;
use crate::api::studio::convert::runtime::bridge_thread_directory_page;
use crate::api::studio::convert::thread_stream::{bridge_activity_detail, bridge_thread_snapshot};
use crate::api::studio::types::{
    BridgeError, BridgeListThreadsPageRequest, BridgeThreadActivityDetail,
    BridgeThreadDirectoryPage, BridgeThreadSnapshot,
};

/// 从内存目录索引按 `(updatedAt, id)` 倒序 keyset 分页；GUI 触底加载使用。
pub async fn list_threads_page(
    request: BridgeListThreadsPageRequest,
) -> Result<BridgeThreadDirectoryPage, BridgeError> {
    let bridge = active_bridge().await?;
    let page = bridge
        .studio
        .list_threads_page(
            request.cursor.as_deref(),
            usize::try_from(request.limit).map_err(anyhow::Error::from)?,
        )
        .await?;
    Ok(bridge_thread_directory_page(page.state))
}

pub async fn read_thread(thread_id: String) -> Result<BridgeThreadSnapshot, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bridge_thread_snapshot(
        bridge.studio.thread_snapshot(&thread_id).await?,
    )?)
}

/// 按活动身份读取当前完整内容事实（reasoning / 输出正文 / 工具参数与流式输出）。
///
/// 只读：不激活 owner、不 flush writer、不改变 revision。身份不再成立时返回 `superseded` /
/// `ended`，未知 Thread 返回 `NotFound`；客户端据此丢弃迟到的展开请求而不是恢复旧活动。
pub async fn read_thread_activity_detail(
    thread_id: String,
    activity_id: String,
) -> Result<BridgeThreadActivityDetail, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bridge_activity_detail(
        bridge
            .studio
            .read_thread_activity_detail(&thread_id, &activity_id)
            .await?,
    ))
}

/// Searches the full project/session directory, including archived history.
pub async fn query_threads(
    request: crate::api::studio::types::BridgeDirectoryQuery,
) -> Result<BridgeThreadDirectoryPage, BridgeError> {
    let bridge = active_bridge().await?;
    let filter = match request.filter {
        crate::api::studio::types::BridgeDirectoryFilter::All => {
            pl_protocol::studio::ThreadDirectoryFilter::All
        }
        crate::api::studio::types::BridgeDirectoryFilter::Running => {
            pl_protocol::studio::ThreadDirectoryFilter::Running
        }
        crate::api::studio::types::BridgeDirectoryFilter::Attention => {
            pl_protocol::studio::ThreadDirectoryFilter::Attention
        }
    };
    let page = bridge
        .studio
        .query_threads(
            &pl_protocol::studio::ThreadDirectoryQuery {
                project_id: request.project_id,
                search: request.search,
                archived: request.archived,
                filter,
            },
            request.cursor.as_deref(),
            request.limit as usize,
        )
        .await?;
    Ok(bridge_thread_directory_page(page.state))
}
