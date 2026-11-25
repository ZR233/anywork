//! openai-deepseek model protocol.

pub mod deepseek_catalog;

pub mod tools;
pub mod upload;

mod models;
pub use models::bundled_definition;

pub mod endpoint;

pub mod adapter;
mod error;
