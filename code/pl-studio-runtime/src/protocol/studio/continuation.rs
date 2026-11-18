//! 停止与继续的产品请求、回执和只读回查视图。
//!
//! 两条命令都是「受理」而不是「完成」：停止回执只证明目标执行的停止请求已被 owner 接受，
//! 继续回执只证明控制输入与继续点认领已被受理并进入保存。生效条件分别是目标执行及其清理
//! 真正结束、以及模型请求真正准入，因此两者都要求身份观察。

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use super::StudioCommandReceipt;

/// 用户无新内容继续主会话。
///
/// `operation_id` 同时就是控制输入身份。仅当前 owner 保留的输入可识别重复请求；
/// 不查询历史，不承诺永久幂等或原始回执重放。`expected_continuation_id` 与
/// `expected_model_route_revision` 是调用方冻结的观察结果，用于拒绝过时点击。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ContinueThreadRequest {
    pub operation_id: String,
    pub expected_continuation_id: String,
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

/// 控制输入当前阶段；由输入事实唯一推导，不是另一份可写状态。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    tag = "kind"
)]
pub enum ContinuationOperationState {
    /// 已受理、尚未消费。
    Pending,
    /// 已随某个轮次的模型请求一起消费。
    Consumed { turn_id: String },
    /// 已被放弃，例如被新的明确授权取代。
    Discarded,
}

/// 一次继续操作的只读回查结果。
///
/// 仅观察当前 owner 保留的输入事实；不回读持久化，也不承诺重现已裁剪的旧回执。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ContinuationOperationView {
    pub thread_id: String,
    pub operation_id: String,
    pub input_id: String,
    pub continuation_id: String,
    pub accepted_sequence: u64,
    pub state: ContinuationOperationState,
    pub receipt: StudioCommandReceipt,
}
