//! openai-xai model protocol.

pub mod xai_catalog;

mod models;
pub use models::bundled_definition;

pub mod endpoint;

pub mod adapter;
