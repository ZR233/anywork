//! 模型元数据、能力、参数与内置数据目录。

mod accounting;
pub mod capabilities;
mod catalog;
mod definition;
mod descriptor;
pub mod family;
pub mod info;
pub mod observation;
pub mod parameter;
pub mod pricing;
mod profile_error;
mod selection;
pub mod usage;

pub use accounting::{
    InferenceAccounting, ModelPriceTierDto, ModelPricingDto, ModelPricingSnapshot, PricingMode,
    PricingOutcome, RuntimeCostAmount, UnpricedReason, UsageReport,
};
pub use capabilities::{
    ModelCapabilities, ModelInputCapability, ModelInputLimits, ModelInputSource, ModelModality,
    PromptCacheModelCapabilities, ReasoningInterleaved, ReasoningInterleavedField,
    ToolCapabilities,
};
pub use catalog::{MediaSendOrder, image_media_profiles, wire_set_one};
pub use definition::validate_inventory;
pub use definition::{BundledModelDefinition, ModelDefinitionError};
pub use descriptor::{
    ModelContextAdjustment, ModelContextResolution, ModelContextUnavailable, ModelType,
    ModelTypeExclusion, ModelTypeSupport,
};
pub use family::ModelFamily;
pub use info::{
    ChatRequestOptions, MaxTokensField, MediaMixPolicy, MediaRepresentation, MediaWireFormat,
    ModelBinding, ModelInfo, ModelMediaInputProfile, ModelProtocolOptions, ModelRequestProfile,
    ModelTransportProfile, ResponsesMaxTokensField, ResponsesRequestOptions, TruncationMode,
    TruncationPolicy,
};
pub use observation::{ModelMetadataField, ModelObservation, ModelParameterDefaultObservation};
pub use parameter::{
    MissingCandidatePolicy, ModelParameter, ModelParameterCandidateError,
    ModelParameterCandidateRequest, ParameterWire, WireAssignment, wire_assignments_from_value,
};
pub use pricing::{
    DailyPriceWindow, ModelPricing, PricingError, TokenPriceTier, WeeklyPriceAdjustment,
};
pub use profile_error::ModelProfileError;
pub use selection::{
    AgentTaskCategory, BundledSelectionGuide, ModelSelectionGuide, ModelSelectionGuideError,
    ModelSelectionMeasurement, ModelSelectionSource, ModelSelectionSourceKind,
    SELECTION_SOURCE_MAX, SELECTION_SUMMARY_MAX_CHARS, bundled_selection_guide,
    bundled_selection_guides,
};
