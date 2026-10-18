//! Product Plan state machine and dynamic tools over generic Thread transactions.
mod common;
mod context;
mod dynamic;
mod restart;
pub mod state;
mod submit;
pub use context::plan_model_context_section;
pub(crate) use dynamic::PlanConfirmationPrompt;
pub use dynamic::{PLAN_EXTENSION, decode_plan_state, encode_plan_state, plan_registrations};
pub use restart::TOOL_PLAN_RESTART;
pub use submit::TOOL_PLAN_SUBMIT;
pub const TOOL_PLAN_CURRENT: &str = "plan_current";
pub const TOOL_PLAN_HISTORY: &str = "plan_history";
pub const TOOL_PLAN_NEXT: &str = "plan_next";
pub const PLAN_CONTEXT_SECTION_ID: &str = "pl.plan";
/// 计划确认提问载荷的格式标识：本层生产，交互投影与工具条目的历史投影共用同一解码。
pub(crate) const PLAN_CONFIRMATION_FORMAT: &str = "pl.studio.plan-confirmation";
/// 计划确认回答载荷的格式标识：本层生产，交互投影与工具条目的历史投影共用同一解码。
pub(crate) const PLAN_ANSWER_FORMAT: &str = "pl.studio.plan-answer";
