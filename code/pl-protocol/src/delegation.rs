//! 会话分发模式、模型查询与最终评价的共享 wire 类型。
//!
//! 这些类型只表达接口契约：候选资格、授权、分页实现与持久化由 Studio 运行时拥有。
//! 查询结果是本地准入与参考资料的投影，不证明远端健康、订阅有效或额度充足。
//!
//! 完整模型选择复用 [`crate::studio::NewThreadModelRoute`]（`accountId`/`modelId`/`effort`），
//! 新建会话草稿、child 派发输入与目录冻结身份共用同一定义，不建立第二份同义结构。

use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use crate::account_catalog::{BillingKind, ModelCapabilitiesDto, ModelDescriptor, ModelPricingDto};
use crate::labeled::LabeledEnum;
use crate::studio::NewThreadModelRoute;

/// 查询列表默认返回条数。
pub const DELEGATION_MODEL_PAGE_DEFAULT: u8 = 5;
/// 查询列表单页最大条数；超出不静默截断，由调用方修正请求。
pub const DELEGATION_MODEL_PAGE_MAX: u8 = 10;
/// 评价评论的 Unicode 字符上限；超长提交被拒绝，不静默截断。
pub const AGENT_EVALUATION_COMMENT_MAX_CHARS: usize = 300;
/// 评价详情与摘要统计的有效样本窗口。
pub const AGENT_EVALUATION_WINDOW: u32 = 10;

/// 分页游标版本；查询身份或排序语义变化时递增。
pub const DELEGATION_MODEL_CURSOR_VERSION: u32 = 1;
const DELEGATION_MODEL_CURSOR_PREFIX: &str = "dmc1.";

/// 根会话的子智能体分发模式。
///
/// 与 Thread Mode、工作区模式独立；创建后只读，主代理模型不受其影响。
#[derive(
    Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq, JsonSchema, ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub enum DelegationMode {
    /// 使用 Profile 配置的固定路由（默认）。
    #[default]
    Profile,
    /// 派发时由主代理显式选择账号模型。
    Automatic,
}

/// 自动选模偏好；只通过主代理提示词表达，不是宿主排序算法。
#[derive(
    Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq, JsonSchema, ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub enum DelegationPreference {
    Economy,
    #[default]
    Balanced,
    Fast,
}

/// 新会话默认分发选择；已有会话不回读该默认值。
#[derive(
    Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq, JsonSchema, ToSchema,
)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DelegationSettings {
    #[serde(default)]
    pub mode: DelegationMode,
    /// 固定模式中保留但不生效。
    #[serde(default)]
    pub preference: DelegationPreference,
}

/// 任务类别；用于选模参考标注与评价分类，不覆盖真实能力判定。
#[derive(
    Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq, JsonSchema, ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub enum AgentTaskCategory {
    Reasoning,
    Coding,
    /// 工具调用与多步编排为主的任务。
    Tooling,
    LongContext,
    /// 需要图片、音频或文件输入的任务。
    Multimodal,
    #[default]
    General,
}

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

/// 查询的过滤条件；同时是游标绑定的查询身份。
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq, JsonSchema, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DelegationModelFilter {
    /// 已排序去重的硬能力条件。
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub capabilities: Vec<DelegationModelCapability>,
    /// 任务参考上下文，不改变资格或排序；缺少标注不等于不支持。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub task_category: Option<AgentTaskCategory>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub account_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub billing_kind: Option<BillingKind>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub min_context_window: Option<u64>,
}

/// 稳定目录身份；分页按该顺序推进。
#[derive(
    Debug,
    Clone,
    Default,
    Serialize,
    Deserialize,
    PartialEq,
    Eq,
    PartialOrd,
    Ord,
    JsonSchema,
    ToSchema,
)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DelegationModelKey {
    pub account_id: String,
    pub model_id: String,
}

/// 有界模型资格查询输入。
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq, JsonSchema, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ListDelegationModelsRequest {
    /// 必须同时成立的声明能力条件。
    #[serde(default)]
    pub capabilities: Vec<DelegationModelCapability>,
    /// 任务参考上下文，不改变候选资格或稳定排序。
    #[serde(default)]
    pub task_category: Option<AgentTaskCategory>,
    #[serde(default)]
    pub account_id: Option<String>,
    #[serde(default)]
    pub billing_kind: Option<BillingKind>,
    #[serde(default)]
    pub min_context_window: Option<u64>,
    /// 省略时使用 [`DELEGATION_MODEL_PAGE_DEFAULT`]。
    #[serde(default)]
    pub limit: Option<u8>,
    #[serde(default)]
    pub cursor: Option<String>,
}

impl ListDelegationModelsRequest {
    /// 归一化的查询身份：能力条件排序去重，其余条件原样保留。
    pub fn filter(&self) -> DelegationModelFilter {
        let mut capabilities = self.capabilities.clone();
        capabilities.sort_by_key(|capability| capability.label());
        capabilities.dedup();
        DelegationModelFilter {
            capabilities,
            task_category: self.task_category,
            account_id: self.account_id.clone(),
            billing_kind: self.billing_kind,
            min_context_window: self.min_context_window,
        }
    }

    /// 生效的单页条数。
    ///
    /// # Errors
    /// 请求超过 [`DELEGATION_MODEL_PAGE_MAX`] 或为 0 时失败，不静默截断。
    pub fn page_limit(&self) -> crate::Result<u8> {
        match self.limit {
            None => Ok(DELEGATION_MODEL_PAGE_DEFAULT),
            Some(limit) if limit == 0 || limit > DELEGATION_MODEL_PAGE_MAX => {
                Err(crate::PureError::Protocol(format!(
                    "delegation model page limit must be between 1 and {DELEGATION_MODEL_PAGE_MAX}"
                )))
            }
            Some(limit) => Ok(limit),
        }
    }
}

/// 绑定查询条件与目录水位的分页游标。
///
/// 只表达身份边界：查询条件、目录水位或锚点不成立时必须重新查询，而不是把游标当成
/// 「附近某条」的猜测位置。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DelegationModelCursor {
    pub version: u32,
    pub filter: DelegationModelFilter,
    /// 产生该位置的目录水位。
    pub catalog_watermark: u64,
    /// 本页最后一条的稳定身份。
    pub after: DelegationModelKey,
}

impl DelegationModelCursor {
    /// 构造当前版本游标。
    pub fn new(
        filter: DelegationModelFilter,
        catalog_watermark: u64,
        after: DelegationModelKey,
    ) -> Self {
        Self {
            version: DELEGATION_MODEL_CURSOR_VERSION,
            filter,
            catalog_watermark,
            after,
        }
    }

    /// 编码为可跨 wire 传输的 opaque token。
    ///
    /// # Panics
    /// 仅在内部 JSON 编码失败时 panic；字段均为可序列化的原始类型。
    pub fn encode(&self) -> String {
        let payload = serde_json::to_string(self).expect("delegation cursor is serializable");
        format!("{DELEGATION_MODEL_CURSOR_PREFIX}{payload}")
    }

    /// 解析 opaque token；非游标输入或版本不符返回 `None`。
    pub fn decode(token: &str) -> Option<Self> {
        let payload = token.strip_prefix(DELEGATION_MODEL_CURSOR_PREFIX)?;
        let cursor: Self = serde_json::from_str(payload).ok()?;
        (cursor.version == DELEGATION_MODEL_CURSOR_VERSION).then_some(cursor)
    }
}

/// 列表一行：紧凑资料、价格/计费、本地速度样本与评价窗口摘要。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, JsonSchema, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DelegationModelListItem {
    pub account_id: String,
    /// 账号展示名，用于区分同名模型。
    pub account_name: String,
    pub model_id: String,
    pub display_name: String,
    /// 短简介：优先使用选模资料；该型号未收录资料时复用既有 `ModelInfo` 描述并按
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pricing: Option<ModelPricingDto>,
    pub billing_kind: BillingKind,
    pub performance: LocalModelPerformanceSummary,
    pub evaluations: AgentEvaluationSummary,
}

/// 查询结果页。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, JsonSchema, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DelegationModelList {
    pub models: Vec<DelegationModelListItem>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub next_cursor: Option<String>,
    /// 本页消费的目录水位，与 [`DelegationModelCursor::catalog_watermark`] 同一身份，
    /// 即 canonical 模型目录快照 revision；不用第二套哈希域。
    pub catalog_revision: u64,
}

/// 单个精确账号模型的详情查询输入。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, JsonSchema, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct GetDelegationModelRequest {
    pub account_id: String,
    pub model_id: String,
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

crate::impl_labeled_enum!(
    DelegationMode,
    "DelegationMode",
    [
        DelegationMode::Profile => "profile",
        DelegationMode::Automatic => "automatic",
    ]
);

crate::impl_labeled_enum!(
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

crate::impl_labeled_enum!(
    DelegationPreference,
    "DelegationPreference",
    [
        DelegationPreference::Economy => "economy",
        DelegationPreference::Balanced => "balanced",
        DelegationPreference::Fast => "fast",
    ]
);

crate::impl_labeled_enum!(
    AgentTaskCategory,
    "AgentTaskCategory",
    [
        AgentTaskCategory::Reasoning => "reasoning",
        AgentTaskCategory::Coding => "coding",
        AgentTaskCategory::Tooling => "tooling",
        AgentTaskCategory::LongContext => "longContext",
        AgentTaskCategory::Multimodal => "multimodal",
        AgentTaskCategory::General => "general",
    ]
);

crate::impl_labeled_enum!(
    AgentEvaluationOutcome,
    "AgentEvaluationOutcome",
    [
        AgentEvaluationOutcome::Passed => "passed",
        AgentEvaluationOutcome::Failed => "failed",
        AgentEvaluationOutcome::NotRated => "notRated",
    ]
);

crate::impl_labeled_enum!(
    AgentEvaluationWrite,
    "AgentEvaluationWrite",
    [
        AgentEvaluationWrite::Created => "created",
        AgentEvaluationWrite::Updated => "updated",
        AgentEvaluationWrite::Unchanged => "unchanged",
    ]
);
