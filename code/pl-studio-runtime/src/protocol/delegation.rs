//! 会话分发模式、模型查询与最终评价的共享 wire 类型。
//!
//! 这些类型只表达接口契约：候选资格、授权与持久化由 Studio 运行时拥有。
//! 查询结果是本地准入与参考资料的投影，不证明远端健康、订阅有效或额度充足。
//!
//! 完整模型选择复用 [`crate::NewThreadModelRoute`]（`accountId`/`modelId`/`effort`），
//! 新建会话草稿、child 派发输入与目录冻结身份共用同一定义，不建立第二份同义结构。

use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use crate::{
    AgentTaskCategory, BillingKind, DelegationMode, DelegationPreference, ModelCapabilitiesDto,
    ModelDescriptor, NewThreadModelRoute,
};

/// 单次详情查询的模型数量上限；完整候选目录没有分页或条数限制。
pub const DELEGATION_MODEL_DETAILS_MAX: usize = 10;
/// 评价评论的 Unicode 字符上限；超长提交被拒绝，不静默截断。
pub const AGENT_EVALUATION_COMMENT_MAX_CHARS: usize = 300;
/// 评价详情与摘要统计的有效样本窗口。
pub const AGENT_EVALUATION_WINDOW: u32 = 10;

/// 列表查询可要求的模型声明能力；全部条件同时成立才入选。
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, JsonSchema, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum DelegationModelCapability {
    /// 子代理候选的必要条件。
    ToolCalling,
    ParallelToolCalls,
    Reasoning,
    ImageInput,
    AudioInput,
    VideoInput,
    FileInput,
    CustomTools,
    FreeformTools,
    WebSearch,
    Streaming,
}

/// 完整候选目录的硬条件过滤；省略条件时返回全部合格模型。
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq, JsonSchema, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ListDelegationModelsRequest {
    #[serde(default)]
    pub capabilities: Vec<DelegationModelCapability>,
    #[serde(default)]
    pub account_id: Option<String>,
    #[serde(default)]
    pub billing_kind: Option<BillingKind>,
    #[serde(default)]
    pub min_context_window: Option<u64>,
}

/// 完整目录的一行；价格、性能和评价按候选批量读取，不在索引中重复展开。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, JsonSchema, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DelegationModelListItem {
    pub account_id: String,
    /// 账号展示名，用于区分同名模型。
    pub account_name: String,
    pub model_id: String,
    pub display_name: String,
    /// 短简介：优先使用选模资料；该型号未收录资料时复用既有 `ModelDefinition` 描述并按
    /// 240 字符上限有界投影（投影与上限由运行时负责），两者都没有时留空，不伪造。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub summary: Option<String>,
    /// 任务适配参考标注。
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub task_suitability: Vec<AgentTaskCategory>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub context_window: Option<u64>,
    pub capabilities: ModelCapabilitiesDto,
    /// 该模型声明的 effort 候选；空表示没有 effort 参数。
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub reasoning_efforts: Vec<String>,
    pub billing_kind: BillingKind,
}

/// 一次读取的完整合格候选目录。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, JsonSchema, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DelegationModelList {
    pub models: Vec<DelegationModelListItem>,
    /// 本次读取的 canonical 模型目录快照 revision。
    pub catalog_revision: u64,
}

/// 单个精确账号模型的详情查询输入。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, JsonSchema, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct GetDelegationModelRequest {
    pub account_id: String,
    pub model_id: String,
}

/// 按精确账号模型身份批量读取详情；单项查询使用长度为一的数组。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, JsonSchema, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct GetDelegationModelsRequest {
    pub models: Vec<GetDelegationModelRequest>,
}

impl GetDelegationModelsRequest {
    /// 校验数量、非空身份和重复项；无效整批输入不会开始读取。
    pub fn validate(&self) -> crate::Result<()> {
        if self.models.is_empty() || self.models.len() > DELEGATION_MODEL_DETAILS_MAX {
            return Err(crate::PureError::Protocol(format!(
                "model details require 1 to {DELEGATION_MODEL_DETAILS_MAX} models"
            )));
        }
        let mut identities = std::collections::BTreeSet::new();
        for model in &self.models {
            if model.account_id.trim().is_empty() || model.model_id.trim().is_empty() {
                return Err(crate::PureError::Protocol(
                    "model details require nonempty accountId and modelId".into(),
                ));
            }
            if !identities.insert((&model.account_id, &model.model_id)) {
                return Err(crate::PureError::Protocol(
                    "model details require distinct account/model identities".into(),
                ));
            }
        }
        Ok(())
    }
}

/// 同一目录快照上的批量详情，结果顺序与输入相同。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DelegationModelDetails {
    pub results: Vec<DelegationModelResult>,
    pub catalog_revision: u64,
}

/// 单项失败保留身份和安全的类型化错误，不丢弃同批其他候选。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
#[serde(
    tag = "status",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum DelegationModelResult {
    Found {
        account_id: String,
        model_id: String,
        detail: Box<DelegationModelDetail>,
    },
    Error {
        account_id: String,
        model_id: String,
        error: crate::StudioError,
    },
}

/// 单个账号模型的完整资料与最近评价窗口。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, JsonSchema, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DelegationModelDetail {
    pub account_id: String,
    pub account_name: String,
    /// 该账号有效目录中的完整模型投影（含 `enabled`、价格、能力与上下文）。
    pub descriptor: ModelDescriptor,
    /// 该模型当前是否可作为执行选择；与路由可用性来自同一次准入结果。
    pub available: bool,
    /// 不可用原因（禁用、类型不合格、缺少合法 effort 或连接、缺少凭据等）；
    /// `available` 为真时通常为 `None`。它只解释本地准入，不保证远端健康或额度。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub unavailable_reason: Option<String>,
    pub billing_kind: BillingKind,
    /// 可追溯选模资料；未核实时为 `None`，不从同名模型补写。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub guide: Option<crate::ModelSelectionGuideDto>,
    pub performance: LocalModelPerformanceSummary,
    pub evaluations: AgentEvaluationSummary,
    /// 最近 [`AGENT_EVALUATION_WINDOW`] 条有效评价，按更新时间与稳定身份排序。
    pub recent_evaluations: Vec<AgentEvaluation>,
}

/// 本地计费样本的既有性能指标投影。
///
/// 字段精确承接 canonical 模型性能统计，不产生第二套汇总：`tokens_per_second` 以含首字
/// 等待的总响应耗时为分母；首字均值的分母是 `ttft_sample_count` 而不是 `sample_count`，
/// 因此没有首字样本时保持未知。它只描述本机已观察样本，不是供应商承诺，也不参与准入
/// 过滤；样本数为 0 时全部指标未知。
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, JsonSchema, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct LocalModelPerformanceSummary {
    /// 参与统计的有效调用样本数。
    pub sample_count: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tokens_per_second: Option<f64>,
    /// 已知首字样本的均值；没有首字样本时为 `None`。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub average_ttft_millis: Option<f64>,
    /// 首字均值的样本数；小于 `sample_count` 表示只有部分样本测到首字。
    pub ttft_sample_count: u64,
    /// 来源统计投影的更新时间；未知为 `None`，不是该模型的样本时间。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub updated_at: Option<i64>,
}

/// 最终任务评价的结果分类。
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, JsonSchema, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum AgentEvaluationOutcome {
    Passed,
    Failed,
    /// 无法判断时不参与均分，也不冒充能力结论。
    NotRated,
}

/// 主代理对自己直接 child 的最终评价记录。
///
/// 账号、模型、effort、Profile 与分发策略由宿主从冻结事实写入，不接受调用者指定。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, JsonSchema, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentEvaluation {
    /// 被评价 child 的 Thread 身份。
    pub agent_id: String,
    /// 作为评价者的父 Thread 身份。
    pub parent_agent_id: String,
    /// 创建时冻结的最终模型选择。
    pub model: NewThreadModelRoute,
    pub profile_id: String,
    pub mode: DelegationMode,
    pub preference: DelegationPreference,
    /// 被评价的最终 Turn。
    pub turn_id: String,
    /// 记录版本；首次写入为 1。
    pub revision: u64,
    pub task_category: AgentTaskCategory,
    pub outcome: AgentEvaluationOutcome,
    /// 质量分项，1–5；`notRated` 时为 `None`。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub quality: Option<u8>,
    /// 指令遵循分项，1–5；`notRated` 时为 `None`。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub instruction_following: Option<u8>,
    pub comment: String,
    pub created_at: i64,
    pub updated_at: i64,
}

/// 评价窗口摘要：只统计最近 [`AGENT_EVALUATION_WINDOW`] 条有效记录。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, JsonSchema, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentEvaluationSummary {
    /// 统计窗口大小，固定为 [`AGENT_EVALUATION_WINDOW`]。
    pub window: u32,
    /// 窗口内可评分样本数（`passed`、`failed`）。
    pub rated_samples: u32,
    pub passed: u32,
    pub failed: u32,
    pub not_rated: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub average_quality: Option<f32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub average_instruction_following: Option<f32>,
}

impl Default for AgentEvaluationSummary {
    /// 空窗口摘要：窗口大小固定，样本与均分保持未知（未知不是零分）。
    fn default() -> Self {
        Self {
            window: AGENT_EVALUATION_WINDOW,
            rated_samples: 0,
            passed: 0,
            failed: 0,
            not_rated: 0,
            average_quality: None,
            average_instruction_following: None,
        }
    }
}

/// 一次评价写入输入。
///
/// `expected_revision` 首次为 0；更新携带已有 revision。`target` 必须是调用者的直接 child。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, JsonSchema, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct EvaluateAgentRequest {
    pub target: String,
    /// 必须是最新已提交终态 Turn。
    pub expected_turn_id: String,
    pub expected_revision: u64,
    pub task_category: AgentTaskCategory,
    pub outcome: AgentEvaluationOutcome,
    /// 1–5，仅可评分结果携带。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub quality: Option<u8>,
    /// 1–5，仅可评分结果携带。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub instruction_following: Option<u8>,
    /// 非空且最多 [`AGENT_EVALUATION_COMMENT_MAX_CHARS`] 个 Unicode 字符。
    pub comment: String,
}

impl EvaluateAgentRequest {
    /// 校验评价输入自身的一致性；授权、Turn 终态与 revision 冲突由拥有者裁决。
    ///
    /// # Errors
    /// `target` 或评论为空、评论超长、分项不在 1–5、以及结果与分项不匹配时失败。
    pub fn validate(&self) -> crate::Result<()> {
        if self.target.trim().is_empty() {
            return Err(crate::PureError::Protocol(
                "evaluate_agent requires a target agent".into(),
            ));
        }
        if self.expected_turn_id.trim().is_empty() {
            return Err(crate::PureError::Protocol(
                "evaluate_agent requires an expected turn".into(),
            ));
        }
        // 空白只用于判断「是否有正文」，长度按原始正文计数：不能用首尾空白稀释上限。
        if self.comment.trim().is_empty() {
            return Err(crate::PureError::Protocol(
                "evaluate_agent requires a non-empty comment".into(),
            ));
        }
        if self.comment.chars().count() > AGENT_EVALUATION_COMMENT_MAX_CHARS {
            return Err(crate::PureError::Protocol(format!(
                "evaluate_agent comment exceeds {AGENT_EVALUATION_COMMENT_MAX_CHARS} characters"
            )));
        }
        for score in [self.quality, self.instruction_following]
            .into_iter()
            .flatten()
        {
            if !(1..=5).contains(&score) {
                return Err(crate::PureError::Protocol(
                    "evaluate_agent scores must be between 1 and 5".into(),
                ));
            }
        }
        match self.outcome {
            AgentEvaluationOutcome::NotRated => {
                if self.quality.is_some() || self.instruction_following.is_some() {
                    return Err(crate::PureError::Protocol(
                        "notRated evaluation cannot carry scores".into(),
                    ));
                }
            }
            AgentEvaluationOutcome::Passed | AgentEvaluationOutcome::Failed => {
                if self.quality.is_none() || self.instruction_following.is_none() {
                    return Err(crate::PureError::Protocol(
                        "rated evaluation requires quality and instructionFollowing".into(),
                    ));
                }
            }
        }
        Ok(())
    }
}

/// 评价写入的落库后果。
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, JsonSchema, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum AgentEvaluationWrite {
    Created,
    Updated,
    /// 同一终态同一内容重复提交：返回原记录，不增加样本或改变排序。
    Unchanged,
}

/// 评价写入收据；成功持久化后才发布。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, JsonSchema, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct EvaluateAgentReceipt {
    pub target: String,
    pub write: AgentEvaluationWrite,
    /// 权威记录（含 revision 与时间戳）。
    pub evaluation: AgentEvaluation,
}

pl_protocol::impl_labeled_enum!(
    DelegationModelCapability,
    "DelegationModelCapability",
    [
        DelegationModelCapability::ToolCalling => "toolCalling",
        DelegationModelCapability::ParallelToolCalls => "parallelToolCalls",
        DelegationModelCapability::Reasoning => "reasoning",
        DelegationModelCapability::ImageInput => "imageInput",
        DelegationModelCapability::AudioInput => "audioInput",
        DelegationModelCapability::VideoInput => "videoInput",
        DelegationModelCapability::FileInput => "fileInput",
        DelegationModelCapability::CustomTools => "customTools",
        DelegationModelCapability::FreeformTools => "freeformTools",
        DelegationModelCapability::WebSearch => "webSearch",
        DelegationModelCapability::Streaming => "streaming",
    ]
);

pl_protocol::impl_labeled_enum!(
    AgentEvaluationOutcome,
    "AgentEvaluationOutcome",
    [
        AgentEvaluationOutcome::Passed => "passed",
        AgentEvaluationOutcome::Failed => "failed",
        AgentEvaluationOutcome::NotRated => "notRated",
    ]
);

pl_protocol::impl_labeled_enum!(
    AgentEvaluationWrite,
    "AgentEvaluationWrite",
    [
        AgentEvaluationWrite::Created => "created",
        AgentEvaluationWrite::Updated => "updated",
        AgentEvaluationWrite::Unchanged => "unchanged",
    ]
);
