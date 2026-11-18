//! 内置模型的只读选模资料。
//!
//! 资料只附着于明确的「目录 + model_id」，不按同名模型跨账号补写；它补充
//! 模型描述 的官方简介，提供有界的适配任务、局限与可追溯来源。
//! 资料不是协议能力、不是模型指令，也不在运行时联网或调用模型生成，因此不进入冻结的
//! runtime 模型载荷。
//!
//! 基准来源必须携带被测型号、effort 与指标；给出分数时还必须带已核实的指标版本，没有版本
//! 或无法核实的不保留分数。别名版本不冒充精确版本，不同测量口径不合成网络总分。社区反馈
//! 只作为个体经验参考。

use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

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

pl_protocol::impl_labeled_enum!(
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

/// 选模短简介的 Unicode 字符上限。
pub const SELECTION_SUMMARY_MAX_CHARS: usize = 240;
/// 单个模型的资料来源上限。
pub const SELECTION_SOURCE_MAX: usize = 6;

/// 一条模型选模资料。
#[derive(Debug, Clone, PartialEq)]
pub struct ModelSelectionGuide {
    /// 面向选模的短简介；不复制能力声明。
    pub summary: &'static str,
    /// 参考适配的任务类别；不是能力过滤依据。
    pub task_suitability: &'static [AgentTaskCategory],
    /// 已核实的局限与使用风险。
    pub limitations: &'static [&'static str],
    /// 可追溯来源，按官方、基准、社区顺序。
    pub sources: &'static [ModelSelectionSource],
}

/// 一条来源。
#[derive(Debug, Clone, PartialEq)]
pub struct ModelSelectionSource {
    pub kind: ModelSelectionSourceKind,
    pub url: &'static str,
    /// 核验日期（Unix 秒）。
    pub verified_at: i64,
    /// 基准来源必须给出测量条件；官方说明与社区反馈通常没有。
    pub measurement: Option<ModelSelectionMeasurement>,
}

/// 来源类型。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ModelSelectionSourceKind {
    Official,
    Benchmark,
    Community,
}

/// 基准测量条件。
#[derive(Debug, Clone, PartialEq)]
pub struct ModelSelectionMeasurement {
    /// 被测量的精确型号或版本。
    pub model: &'static str,
    /// 测量时的 effort 档位。
    pub effort: Option<&'static str>,
    /// 指标名称。
    pub metric: &'static str,
    /// 指标版本（例如 `v4.3.2`）；给出分数时必须明确，否则分数不可比。
    pub metric_version: Option<&'static str>,
    /// 分数只在该指标口径内可比；未核实时为 `None`。
    pub score: Option<f64>,
}

/// 一条内置资料及其精确归属。
#[derive(Debug, Clone)]
pub struct BundledSelectionGuide {
    /// 该资料适用的内置目录 id；同一模型族的多套目录显式列出，不按名称模糊匹配。
    pub catalogs: &'static [&'static str],
    pub model_id: &'static str,
    pub guide: ModelSelectionGuide,
}

/// 资料的声明错误；内置数据缺陷，不是用户配置错误。
#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
pub enum ModelSelectionGuideError {
    #[error("selection guide summary exceeds the character limit")]
    SummaryTooLong,
    #[error("selection guide has too many sources")]
    TooManySources,
    #[error("selection guide source requires an absolute http(s) url")]
    InvalidSource,
    #[error("selection guide benchmark source must name its measurement")]
    MissingMeasurement,
    #[error("selection guide benchmark score requires an explicit metric version")]
    MissingMetricVersion,
    #[error("selection guide references an unknown catalog model")]
    UnknownModel,
    #[error("selection guide is declared twice for the same catalog model")]
    Duplicate,
}

impl ModelSelectionGuide {
    /// 校验长度与来源形式；内置资料的打包完整性检查复用同一规则。
    ///
    /// # Errors
    /// 简介超长、来源过多或来源 URL 不是绝对 http(s) 地址时失败。
    pub fn validate(&self) -> Result<(), ModelSelectionGuideError> {
        if self.summary.chars().count() > SELECTION_SUMMARY_MAX_CHARS {
            return Err(ModelSelectionGuideError::SummaryTooLong);
        }
        if self.sources.len() > SELECTION_SOURCE_MAX {
            return Err(ModelSelectionGuideError::TooManySources);
        }
        for source in self.sources {
            if !(source.url.starts_with("https://") || source.url.starts_with("http://")) {
                return Err(ModelSelectionGuideError::InvalidSource);
            }
            if source.kind == ModelSelectionSourceKind::Benchmark && source.measurement.is_none() {
                return Err(ModelSelectionGuideError::MissingMeasurement);
            }
            // 精确分数必须绑定已核实的指标版本；无法核实版本时只能不保留分数。
            if let Some(measurement) = &source.measurement
                && measurement.score.is_some()
                && measurement
                    .metric_version
                    .is_none_or(|version| version.trim().is_empty())
            {
                return Err(ModelSelectionGuideError::MissingMetricVersion);
            }
        }
        Ok(())
    }
}
