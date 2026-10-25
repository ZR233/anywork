//! Configuration's immutable capture and compatible Models pin, inside the canonical owner.
mod capture;
mod owner;
mod source;
mod status;

pub(crate) use source::{
    ConfigurationCaptureFailure, ConfigurationMaterial, ConfigurationPair, ConfigurationSnapshot,
    ConfigurationSource,
};
pub(super) use status::ConfigurationMetadata;
pub(crate) use status::ConfigurationStatusMaterial;
