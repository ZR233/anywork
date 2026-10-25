//! Immutable material pinned by the original Thread observation entry.
//!
//! These readers do not resolve a Thread by its display selection, activate execution, flush a
//! writer or fetch a newer revision. The registry installs their source before publishing its ref;
//! scope/call admission and completion remain owned by that same observation entry.
pub(super) mod activity;
pub(super) mod budget;
pub(super) mod configuration;
pub(super) mod context;
pub(super) mod index;
pub(super) mod interaction;
pub(super) mod lifetime;
pub(super) mod scalar;
pub(super) mod todo;
pub(super) mod turn;
