//! Independent append-only History store, reader, hybrid body codec, and legacy upgrade boundary.
#![allow(
    clippy::missing_errors_doc,
    clippy::missing_panics_doc,
    clippy::module_name_repetitions
)]

mod accounting;
pub mod body;
mod db;
pub(crate) mod import;
mod pending;
mod reader;
mod schema;
mod store;
mod token;
mod types;
pub mod upgrade;
mod validate;
mod writer_lease;

#[cfg(test)]
mod reader_regression_tests;
#[cfg(test)]
mod scale;

pub use accounting::HistoryUsageFact;
pub(crate) use accounting::PreparedHistoryUsage;
pub use body::{
    EventPayloadEnvelope, PendingBody, decode_event_envelope, pack_bodies, read_event_body_bytes,
    stream_body_reference,
};
pub use reader::HistoryReader;
pub use store::{HistoryStore, HistoryStoreShare};
pub(crate) use types::milliseconds_from_seconds;
pub use types::*;
pub(crate) use upgrade::requires_history_upgrade;
pub use upgrade::{UpgradeReport, UpgradeStatus, upgrade_history};
