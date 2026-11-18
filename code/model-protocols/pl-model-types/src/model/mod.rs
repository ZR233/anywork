//! Shared model capabilities, metadata and accounting.
mod accounting;
pub mod capabilities;
mod descriptor;
pub mod parameter;
pub mod pricing;
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
pub use descriptor::{
    ModelContextAdjustment, ModelContextResolution, ModelContextUnavailable, ModelType,
    ModelTypeExclusion, ModelTypeSupport,
};
pub use parameter::{
    MissingCandidatePolicy, ModelParameter, ModelParameterCandidateError,
    ModelParameterCandidateRequest, ParameterWire, WireAssignment, wire_assignments_from_value,
};
pub use pricing::{
    DailyPriceWindow, ModelPricing, PricingError, TokenPriceTier, WeeklyPriceAdjustment,
};
pub use selection::{
    AgentTaskCategory, BundledSelectionGuide, ModelSelectionGuide, ModelSelectionGuideError,
    ModelSelectionMeasurement, ModelSelectionSource, ModelSelectionSourceKind,
    SELECTION_SOURCE_MAX, SELECTION_SUMMARY_MAX_CHARS,
};

mod metadata;
mod observation;
pub use metadata::{ModelMetadata, TruncationMode, TruncationPolicy};
pub use observation::{ModelMetadataField, ModelObservation, ModelParameterDefaultObservation};
