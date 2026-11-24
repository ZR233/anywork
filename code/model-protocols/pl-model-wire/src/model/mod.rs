//! 模型元数据、能力、参数与内置数据目录。

mod catalog;
mod definition;
pub mod family;
pub mod info;
pub mod observation;
mod profile_error;

pub use catalog::{
    MediaSendOrder, effort_parameter, image_media_profiles, media_profile, wire_set_one,
};
pub use definition::validate_inventory;
pub use definition::{BundledModelDefinition, ModelDefinitionError};
pub use family::ModelFamily;
pub use info::{
    AutoCompactDefaultPolicy, ChatRequestOptions, DEFAULT_FALLBACK_AUTO_COMPACT_LIMIT,
    GeminiRequestOptions, MaxTokensField, MediaMixPolicy, MediaRepresentation, MediaWireFormat,
    ModelBinding, ModelDefinition, ModelExtras, ModelMediaInputProfile, ModelProtocolOptions,
    ModelRequestProfile, ModelTransportProfile, ResponsesMaxTokensField, ResponsesRequestOptions,
    TruncationMode, TruncationPolicy,
};
pub use observation::{ModelMetadataField, ModelObservation, ModelParameterDefaultObservation};
pub use profile_error::ModelProfileError;

pub use pl_model_types::model::*;

pub use pl_model_types::model::{capabilities, parameter, pricing, usage};

pub mod reasoning_fields;
