//! 本机检测薄入口：runtime 拥有受理、取消身份与进程收束。

use pl_studio_runtime::{CancelAcpLocalDetectionRequest, StartAcpLocalDetectionRequest};

use crate::api::studio::bridge_runtime::active_bridge;
use crate::api::studio::convert::acp_detection::bridge_acp_local_detection_reply;
use crate::api::studio::types::{BridgeAcpLocalDetectionCommandReply, BridgeError};

/// 显式受理检测；不等待后台进程完成。
pub async fn start_acp_local_detection(
    operation_id: String,
) -> Result<BridgeAcpLocalDetectionCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bridge_acp_local_detection_reply(
        bridge
            .studio
            .start_acp_local_detection(StartAcpLocalDetectionRequest { operation_id })?,
    ))
}

/// 取消指定的检测操作；不将旧操作身份替换成当前操作。
pub async fn cancel_acp_local_detection(
    operation_id: String,
    target_operation_id: String,
) -> Result<BridgeAcpLocalDetectionCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bridge_acp_local_detection_reply(
        bridge
            .studio
            .cancel_acp_local_detection(CancelAcpLocalDetectionRequest {
                operation_id,
                target_operation_id,
            })?,
    ))
}
