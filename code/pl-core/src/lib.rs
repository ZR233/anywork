//! Minimal Thread execution, model/tool contracts, immutable context and single event stream.
//! Product configuration, provider protocols, persistence and concrete tools are owned by embedding crates.
#[cfg(test)]
extern crate self as pl_core;

pub mod chat;
pub mod context;
mod error_record;
pub mod model;
pub mod thread;
mod time;
pub mod tool;
pub mod usage;

#[cfg(test)]
#[path = "../tests/support/timeline.rs"]
mod test_fixture_timeline;
