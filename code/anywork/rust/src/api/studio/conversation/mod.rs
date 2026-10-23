//! Typed conversation transport. Mutation certainty and per-facet feeds are separate capabilities.
mod convert;
pub mod commands;
pub mod authoring;
pub mod configuration;
pub mod context;
pub mod execution;
pub mod identity;
pub mod metrics;
pub mod metrics_feed;
pub mod read;
