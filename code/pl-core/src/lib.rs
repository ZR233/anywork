//! Minimal Thread execution, model/tool contracts, immutable context and optional cold storage.
//! Product configuration, provider protocols and concrete tools are owned by embedding crates.
#[cfg(test)]
extern crate self as pl_core;

pub mod chat;
pub mod context;
mod error_record;
pub mod model;
#[cfg(feature = "sqlite")]
pub mod persistence;
pub mod storage;
pub mod thread;
mod time;
pub mod tool;
pub mod usage;

#[cfg(test)]
#[path = "../tests/support/timeline.rs"]
mod test_fixture_timeline;
