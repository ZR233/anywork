//! Models-only immutable material and identity advancement inside the canonical config owner.
mod material;
mod owner;
mod qualification;
mod selection;
mod source;
mod status;

pub(crate) use material::{CapturedModels, ModelCatalogMaterial};
pub(crate) use qualification::ModelExecutionQualification;
pub(crate) use source::{ModelCaptureFailure, ModelCatalogSource, ModelsSnapshot};
pub(in crate::config::runtime) use status::{ModelSourceMetadata, observe_source, stop_source};
pub(crate) use status::{ModelSourceStatusFailure, ModelSourceStatusMaterial};
