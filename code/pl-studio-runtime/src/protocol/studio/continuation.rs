//! 停止与继续的产品请求、回执和只读回查视图。
//!
//! 两条命令都是「受理」而不是「完成」：停止回执只证明目标执行的停止请求已被 owner 接受，
//! 继续回执只证明控制意图已被 owner 接纳并预约执行。生效条件分别是目标执行及其清理
//! 真正结束、以及模型请求真正准入，因此两者都要求身份观察。

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use super::StudioCommandReceipt;

/// 用户无新内容继续主会话。
///
/// `operation_id` 是控制请求身份；同一 owner 的最近 64 条缓存按原回执回答，不再次消费
/// token。缓存之外不回读持久化补永久去重。`expected_continuation_token` 与
/// `expected_model_route_revision` 是调用方冻结的观察结果，用于拒绝过时点击。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ContinueThreadRequest {
    pub operation_id: String,
    pub expected_continuation_token: String,
    pub expected_model_route_revision: u64,
}

/// 精确停止：目标是执行身份，不是可空的轮次投影。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StopThreadRequest {
    pub operation_id: String,
    pub expected_execution_id: String,
}

/// 继续受理回执；新轮次尚未开始时不虚构轮次编号。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ContinueThreadResponse {
    pub thread_id: String,
    /// 控制输入身份，与请求的 `operationId` 相同。
    pub input_id: String,
    pub continuation_id: String,
    /// 受理提交序号。
    pub cursor: u64,
    pub receipt: StudioCommandReceipt,
}

/// 停止受理回执；`stopped` 只说明请求被接受。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StopThreadResponse {
    pub thread_id: String,
    pub execution_id: String,
    pub stopped: bool,
    pub receipt: StudioCommandReceipt,
}

/// 回查区分同一 owner 尚未接纳与已知回执；过期 token 由 typed StaleContinuation 拒绝。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum ContinuationOperationState {
    Known,
    NotAccepted,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", tag = "kind", content = "reason")]
pub enum ContinuationDisposition {
    Scheduled,
    Effective,
    NotExecuted(String),
}

/// 有界控制回执。accepted_revision 是 RAM 逻辑版本，History 保存不影响控制准入。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ContinuationOperationView {
    pub thread_id: String,
    pub operation_id: String,
    pub expected_continuation_token: String,
    pub state: ContinuationOperationState,
    pub acceptance_epoch: Option<String>,
    pub execution_id: Option<String>,
    pub turn_id: Option<String>,
    pub accepted_revision: Option<u64>,
    pub disposition: Option<ContinuationDisposition>,
    pub receipt: Option<StudioCommandReceipt>,
}
