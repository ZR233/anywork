//! OpenAI Chat Completions and Responses wire codecs.
pub mod completion;
pub mod config;
pub mod discovery;
mod discovery_error;
mod discovery_policy;
pub mod files;
pub mod model;
pub mod openai;
pub mod protocol;
pub use pl_model_types::authorization;
pub use pl_model_types::{ModelMemberState, PromptPrefixChangedReason, PureError, Result, headers};

pub mod provider_error;
pub mod transport;

pub mod generic_catalog;

mod query_error;
pub use query_error::query_transport_error;

pub mod catalog_http;

pub mod adapter;
