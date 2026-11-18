//! OpenAI Chat Completions and Responses wire codecs.
pub mod openai;
use pl_model_types::{completion, model, protocol};

pub mod provider_error;
pub mod transport;

pub mod generic_catalog;

mod query_error;
pub use query_error::query_transport_error;

pub mod catalog_http;
