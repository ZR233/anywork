//! 模型类别支持度与上下文策略解析结果描述。

use serde::{Deserialize, Serialize};

/// Optional classification for final catalog queries.
#[derive(
    schemars::JsonSchema,
    Debug,
    Clone,
    Copy,
    Serialize,
    Deserialize,
    PartialEq,
    Eq,
    utoipa::ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub enum ModelType {
    Text,
}

#[derive(
    schemars::JsonSchema,
    Debug,
    Clone,
    Copy,
    Serialize,
    Deserialize,
    PartialEq,
    Eq,
    utoipa::ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub enum ModelTypeExclusion {
    TextInputUnsupported,
    TextOutputUnsupported,
    ContextParametersInvalid,
}

/// Final model-owned context policy, frozen after catalog and account configuration merge.
#[derive(
    schemars::JsonSchema, Debug, Clone, Serialize, Deserialize, PartialEq, Eq, utoipa::ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub struct ModelContextResolution {
    pub unavailable: Option<ModelContextUnavailable>,
    pub context_window: Option<u64>,
    pub auto_compact_limit: Option<u64>,
    pub adjustment: Option<ModelContextAdjustment>,
}

#[derive(
    schemars::JsonSchema,
    Debug,
    Clone,
    Copy,
    Serialize,
    Deserialize,
    PartialEq,
    Eq,
    utoipa::ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub enum ModelContextUnavailable {
    InvalidParameters,
}

#[derive(
    schemars::JsonSchema,
    Debug,
    Clone,
    Copy,
    Serialize,
    Deserialize,
    PartialEq,
    Eq,
    utoipa::ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub enum ModelContextAdjustment {
    SafetyLimit,
}

#[derive(
    schemars::JsonSchema, Debug, Clone, Serialize, Deserialize, PartialEq, Eq, utoipa::ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub struct ModelTypeSupport {
    pub model_type: ModelType,
    pub exclusions: Vec<ModelTypeExclusion>,
}
