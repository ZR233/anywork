//! Independent append-only history, schema 25. Production activation is owned by issue #470.
//!
//! Accepting a batch publishes one historical cut. `flush` persists accepted immutable batches;
//! it neither reads nor acknowledges `current.json`. The caller's existing writer lifecycle
//! schedules flush and retains failures. No background task or second runtime is created here.

mod accounting;
mod classifier;
mod db;
mod import;
mod pending;
mod reader;
mod schema;
mod store;
mod token;
mod types;
mod validate;

pub use accounting::HistoryUsageFact;
pub use classifier::*;
pub use import::*;
pub use reader::HistoryReader;
pub use store::HistoryStore;
pub use types::*;
