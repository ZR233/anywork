//! ACP 接入保存/删除的受管调用入口。
//!
//! 复用既有 Configuration 调用所有者、操作身份、结果保留与真实关闭机制，只把结果类型换成
//! ACP 专用的窄形状（Settings-only 回执 + 本次提交捕获的配置读取目标）。没有第二套调用
//! 登记表，也不是 HTTP 公开写请求的变体。
use pl_protocol::products::configuration_calls::{
    AcpAccountCallRequest, AcpAccountCommandOutcome, ConfigurationCallKind,
    ConfigurationCallRequest,
};
use pl_protocol::studio as native;
use std::sync::Arc;

use super::super::references::BridgeConfigurationReadTarget;
use super::configuration_command_registry::{BridgeCallOutcome, CommandOwner, close_call};
use crate::api::studio::bridge_runtime::{BridgeRuntime, installed_bridge};
use crate::api::studio::convert::acp::update_acp_account_request;
use crate::api::studio::convert::commands::command_receipt;
use crate::api::studio::types::{
    BridgeAcpAccountUpdate, BridgeError, BridgeFeedCloseReport, BridgeStudioCommandReceipt,
};

/// ACP 接入的两种提交意图；字段与严格校验沿用既有请求类型。
#[derive(Debug, Clone)]
pub enum BridgeAcpAccountMutation {
    SaveAccount { input: BridgeAcpAccountUpdate },
    RemoveAccount { account_id: String },
}

/// 提交成功只返回真实 Settings 回执与本次提交捕获的配置读取目标。
#[derive(Debug, Clone)]
pub struct BridgeAcpAccountCommandReply {
    pub receipt: BridgeStudioCommandReceipt,
    pub configuration: BridgeConfigurationReadTarget,
}

/// 四个诚实阶段：只有真实提交前拒绝才是 `Rejected`，传输异常仍是 `Unknown`。
#[derive(Debug, Clone)]
pub enum BridgeAcpAccountCommandOutcome {
    Committed {
        reply: BridgeAcpAccountCommandReply,
    },
    CommittedButUnobserved {
        receipt: BridgeStudioCommandReceipt,
        error: BridgeError,
    },
    Rejected {
        operation_id: String,
        error: BridgeError,
    },
    Unknown {
        operation_id: String,
        error: BridgeError,
    },
}

/// 一次原始 ACP 提交调用。Dropping 这个不透明句柄不是显式消费：原注册表仍保留任务、
/// 结果与本次提交捕获的材料，`find` 可以恢复丢失或丢弃的 begin 回执。
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeAcpAccountCommandCall {
    owner: Arc<CommandOwner>,
    bridge: &'static BridgeRuntime,
}

pub async fn begin_acp_account_command(
    operation_id: String,
    expected_settings_revision: u64,
    mutation: BridgeAcpAccountMutation,
) -> Result<BridgeAcpAccountCommandCall, BridgeError> {
    let bridge = installed_bridge()?;
    let owner = bridge.configuration_commands.begin(
        bridge,
        ConfigurationCallRequest::AcpAccount(native_request(
            operation_id,
            expected_settings_revision,
            mutation,
        )),
    )?;
    Ok(BridgeAcpAccountCommandCall { owner, bridge })
}

/// 只查找原活动调用。缺失既不代表未受理，也不创建第二次提交。
pub async fn find_acp_account_command(
    operation_id: String,
) -> Result<Option<BridgeAcpAccountCommandCall>, BridgeError> {
    let bridge = installed_bridge()?;
    Ok(bridge
        .configuration_commands
        .find(&operation_id, ConfigurationCallKind::AcpAccount)?
        .map(|owner| BridgeAcpAccountCommandCall { owner, bridge }))
}

impl BridgeAcpAccountCommandCall {
    #[flutter_rust_bridge::frb(sync)]
    pub fn call_id(&self) -> String {
        self.owner.identity().call_id
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn operation_id(&self) -> String {
        self.owner.identity().operation_id
    }
    pub async fn result(&self) -> Result<BridgeAcpAccountCommandOutcome, BridgeError> {
        let mut query = self.owner.result_query()?;
        match query.result().await? {
            BridgeCallOutcome::AcpAccount(outcome) => Ok(outcome),
            BridgeCallOutcome::Configuration(_)
            | BridgeCallOutcome::Profile(_)
            | BridgeCallOutcome::Reload(_) => Err(pl_protocol::studio::StudioError::new(
                pl_protocol::studio::StudioErrorCode::Protocol,
                "Original call result has the wrong resource kind",
                false,
            )
            .into()),
        }
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.owner.request_close();
    }
    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.owner.require_kind(ConfigurationCallKind::AcpAccount)?;
        Ok(close_call(&self.owner, self.bridge).await)
    }
    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.close().await
    }
}

fn native_request(
    operation_id: String,
    expected_revision: u64,
    mutation: BridgeAcpAccountMutation,
) -> AcpAccountCallRequest {
    match mutation {
        BridgeAcpAccountMutation::SaveAccount { input } => AcpAccountCallRequest::Save(
            update_acp_account_request(operation_id, expected_revision, input),
        ),
        BridgeAcpAccountMutation::RemoveAccount { account_id } => {
            AcpAccountCallRequest::Remove(native::RemoveAcpAccountRequest {
                operation_id,
                expected_revision,
                account_id,
            })
        }
    }
}

impl From<AcpAccountCommandOutcome> for BridgeAcpAccountCommandOutcome {
    fn from(value: AcpAccountCommandOutcome) -> Self {
        match value {
            AcpAccountCommandOutcome::Committed { reply } => Self::Committed {
                reply: BridgeAcpAccountCommandReply {
                    receipt: command_receipt(reply.receipt),
                    configuration: reply.configuration.into(),
                },
            },
            AcpAccountCommandOutcome::CommittedButUnobserved { receipt, error } => {
                Self::CommittedButUnobserved {
                    receipt: command_receipt(receipt),
                    error: error.into(),
                }
            }
            AcpAccountCommandOutcome::Rejected {
                operation_id,
                error,
            } => Self::Rejected {
                operation_id,
                error: error.into(),
            },
            AcpAccountCommandOutcome::Unknown {
                operation_id,
                error,
            } => Self::Unknown {
                operation_id,
                error: error.into(),
            },
        }
    }
}
