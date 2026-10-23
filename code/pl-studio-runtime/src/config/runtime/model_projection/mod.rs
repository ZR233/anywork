//! Models-only immutable material and identity advancement inside the canonical config owner.
mod material;
mod owner;
mod selection;
mod source;

pub(crate) use material::{CapturedModels, ModelCatalogMaterial};
pub(crate) use source::{ModelCaptureFailure, ModelCatalogSource, ModelsSnapshot};
