//! Protocol-agnostic wire contracts, capability descriptors, SSE framing and codec traits.
pub mod completion;
pub mod config;
pub mod discovery;
mod discovery_error;
mod discovery_policy;
pub mod files;
pub mod model;
pub mod protocol;
pub mod service_tiers;
pub mod wire_codec;
pub use pl_model_types::authorization;
pub use pl_model_types::{
    ApiKeyHeaderScheme, ModelMemberState, PromptPrefixChangedReason, PureError, Result, headers,
    headers_with_scheme,
};

pub mod provider_error;
pub mod transport;

pub mod generic_catalog;

mod query_error;
pub use query_error::query_transport_error;

pub mod catalog_http;

pub mod adapter;
