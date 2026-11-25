//! Product Plan state machine and dynamic tools powered by `pl-tool-plan`.
mod context;
mod dynamic;
pub mod state;
mod types;

pub use types::*;

pub use context::plan_model_context_section;
pub(crate) use dynamic::PlanConfirmationPrompt;
pub use dynamic::{PLAN_EXTENSION, decode_plan_state, encode_plan_state, plan_registrations};
pub(crate) use dynamic::{migrate_plan_payload, migrate_saved_plan};
pub const PLAN_CONTEXT_SECTION_ID: &str = "pl.plan";
/// Format identifier for Plan confirmation requests, shared across interaction and timeline projections.
pub(crate) const PLAN_CONFIRMATION_FORMAT: &str = "pl.studio.plan-confirmation";
/// Format identifier for Plan confirmation answers.
pub(crate) const PLAN_ANSWER_FORMAT: &str = "pl.studio.plan-answer";
