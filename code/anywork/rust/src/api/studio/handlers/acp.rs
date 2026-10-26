//! ACP 认证与模板目录的 FRB 入口。
//!
//! 账号保存/删除已迁入配置领域的受管调用（`begin_acp_account_command` /
//! `find_acp_account_command`），因此这里不再提供一次性写入入口。检查连接、登录与取消仍是
//! 独立认证命令，返回受理回执与受理时快照，不等待人工登录或进程退出（见 design/25、design/28）。

use pl_protocol::studio::{CancelAcpAuthRequest, StartAcpAuthRequest};

use crate::api::studio::bridge_runtime::{active_bridge, installed_bridge};
use crate::api::studio::convert::acp::{
    bridge_acp_account_catalog, bridge_acp_auth_snapshot, protocol_auth_action,
};
use crate::api::studio::convert::commands::command_receipt;
use crate::api::studio::types::{
    BridgeAcpAccountCatalog, BridgeAcpAuthAction, BridgeAcpAuthCommandReply, BridgeAcpAuthSnapshot,
    BridgeError,
};

/// 读取 ACP 接入模板目录；纯读取默认值，不启动程序。
pub fn load_acp_account_catalog() -> Result<BridgeAcpAccountCatalog, BridgeError> {
    Ok(bridge_acp_account_catalog(
        installed_bridge()?.studio.load_acp_account_catalog(),
    ))
}

/// 当前 canonical ACP 认证快照；纯读取，不启动程序。
pub async fn read_acp_auth_state() -> Result<BridgeAcpAuthSnapshot, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bridge_acp_auth_snapshot(
        bridge.studio.read_acp_auth_state(),
    ))
}

/// 受理一次 ACP 检查或登录操作。
pub async fn start_acp_auth(
    operation_id: String,
    account_id: String,
    expected_connection_revision: u64,
    action: BridgeAcpAuthAction,
) -> Result<BridgeAcpAuthCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    let reply = bridge.studio.start_acp_auth(StartAcpAuthRequest {
        operation_id,
        account_id,
        expected_connection_revision,
        action: protocol_auth_action(action),
    })?;
    Ok(BridgeAcpAuthCommandReply {
        receipt: command_receipt(reply.receipt),
        snapshot: bridge_acp_auth_snapshot(reply.snapshot),
    })
}

/// 取消当前 ACP 认证操作。
pub async fn cancel_acp_auth(
    operation_id: String,
    account_id: String,
    target_operation_id: String,
) -> Result<BridgeAcpAuthCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    let reply = bridge.studio.cancel_acp_auth(CancelAcpAuthRequest {
        operation_id,
        account_id,
        target_operation_id,
    })?;
    Ok(BridgeAcpAuthCommandReply {
        receipt: command_receipt(reply.receipt),
        snapshot: bridge_acp_auth_snapshot(reply.snapshot),
    })
}
