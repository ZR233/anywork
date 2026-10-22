//! ACP 接入与认证的 FRB 入口。
//!
//! 保存/删除接入沿用 Settings 写路径（返回既有 Settings 回执）；检查连接、登录与取消是独立的
//! 认证命令，返回受理回执与受理时快照。命令都不等待人工登录或进程退出（见 design/25、design/28）。

use pl_protocol::studio::{CancelAcpAuthRequest, RemoveAcpAccountRequest, StartAcpAuthRequest};

use crate::api::studio::bridge_runtime::{active_bridge, installed_bridge};
use crate::api::studio::convert::acp::{
    bridge_acp_account_catalog, bridge_acp_auth_snapshot, protocol_auth_action,
    update_acp_account_request,
};
use crate::api::studio::convert::commands::{command_receipt, settings_command_reply};
use crate::api::studio::types::{
    BridgeAcpAccountCatalog, BridgeAcpAccountUpdate, BridgeAcpAuthAction,
    BridgeAcpAuthCommandReply, BridgeAcpAuthSnapshot, BridgeError, BridgeSettingsCommandReply,
};

/// 读取 ACP 接入模板目录；纯读取默认值，不启动程序。
pub fn load_acp_account_catalog() -> Result<BridgeAcpAccountCatalog, BridgeError> {
    Ok(bridge_acp_account_catalog(
        installed_bridge()?.studio.load_acp_account_catalog(),
    ))
}

/// 保存（新增或更新）一条 ACP 接入。
pub async fn save_acp_account(
    operation_id: String,
    expected_settings_revision: u64,
    account: BridgeAcpAccountUpdate,
) -> Result<BridgeSettingsCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(settings_command_reply(bridge.studio.save_acp_account(
        update_acp_account_request(operation_id, expected_settings_revision, account),
    )?))
}

/// 删除一条 ACP 接入；不注销官方账号、不删除其凭据。
pub async fn remove_acp_account(
    operation_id: String,
    expected_settings_revision: u64,
    account_id: String,
) -> Result<BridgeSettingsCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(settings_command_reply(bridge.studio.remove_acp_account(
        RemoveAcpAccountRequest {
            operation_id,
            expected_revision: expected_settings_revision,
            account_id,
        },
    )?))
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
