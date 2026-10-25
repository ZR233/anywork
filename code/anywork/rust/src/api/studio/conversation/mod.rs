//! Typed conversation transport. Mutation certainty and per-facet feeds are separate capabilities.
pub mod authoring;
pub mod authoring_feed;
pub mod commands;
pub mod configuration;
pub mod configuration_feed;
pub mod context;
pub mod context_feed;
mod convert;
pub mod execution;
pub mod execution_feed;
pub mod identity;
pub mod metrics;
pub mod metrics_feed;
pub mod read;
pub mod turn_history;
