//! ACP 官方 server 自动准备的 FRB 入口。
//!
//! 读取是纯查询，不联网、不扫描、不启动任何程序；准备与取消是显式命令，只返回受理回执与
//! 受理时快照，长网络/文件 IO 在 runtime owner 内后台推进（见 design/25、design/28 §28.6）。

use pl_protocol::studio::{CancelAcpInstallRequest, StartAcpInstallRequest};

use crate::api::studio::bridge_runtime::active_bridge;
use crate::api::studio::convert::acp_install::{
    bridge_acp_install_snapshot, protocol_acp_install_provider,
};
use crate::api::studio::convert::commands::command_receipt;
use crate::api::studio::types::{
    BridgeAcpInstallCommandReply, BridgeAcpInstallSnapshot, BridgeAcpProvider, BridgeError,
};

/// 当前 canonical 安装快照；纯读取，不联网。
pub async fn read_acp_install_state() -> Result<BridgeAcpInstallSnapshot, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bridge_acp_install_snapshot(
        bridge.studio.read_acp_install_state(),
    ))
}

/// 受理一次官方 server 准备；不保存账号、不启动认证。
pub async fn start_acp_install(
    operation_id: String,
    provider: BridgeAcpProvider,
) -> Result<BridgeAcpInstallCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    let reply = bridge.studio.start_acp_install(StartAcpInstallRequest {
        operation_id,
        provider: protocol_acp_install_provider(provider),
    })?;
    Ok(BridgeAcpInstallCommandReply {
        receipt: command_receipt(reply.receipt),
        snapshot: bridge_acp_install_snapshot(reply.snapshot),
    })
}

/// 取消当前安装操作；`target_operation_id` 必须命中当前 operation 才生效。
pub async fn cancel_acp_install(
    operation_id: String,
    provider: BridgeAcpProvider,
    target_operation_id: String,
) -> Result<BridgeAcpInstallCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    let reply = bridge.studio.cancel_acp_install(CancelAcpInstallRequest {
        operation_id,
        provider: protocol_acp_install_provider(provider),
        target_operation_id,
    })?;
    Ok(BridgeAcpInstallCommandReply {
        receipt: command_receipt(reply.receipt),
        snapshot: bridge_acp_install_snapshot(reply.snapshot),
    })
}
