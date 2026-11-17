//! Independent append-only history, schema 25. Production activation is owned by issue #470.
//!
//! Accepting a batch publishes one historical cut. `flush` persists accepted immutable batches;
//! it neither reads nor acknowledges `current.json`. The caller's existing writer lifecycle
//! schedules flush and retains failures. No background task or second runtime is created here.
//! History header timestamps use UTC epoch milliseconds. Native adapters convert seconds;
//! canonical payloads keep their original representation and units.

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
mod upgrade;
mod validate;

pub use accounting::HistoryUsageFact;
pub(crate) use accounting::PreparedHistoryUsage;
pub use classifier::*;
pub use import::*;
pub use reader::HistoryReader;
pub use store::{HistoryStore, HistoryStoreShare};
pub(crate) use types::milliseconds_from_seconds;
pub use types::*;
pub(crate) use upgrade::requires_history_upgrade;
pub use upgrade::{UpgradeReport, UpgradeStatus, upgrade_history};
