//! openai model protocol.

pub mod openai_catalog;

pub mod images;

pub mod search;

pub mod codex_usage;

mod models;
pub use models::bundled_definition;

pub mod endpoint;

pub mod adapter;
