//! Prompt admission, execution controls, and interaction handling for Threads.

mod activation;
mod control;
mod handover;
mod interaction;
mod submit;

pub(in crate::studio::runtime) use control::{
    UserThreadAction, ensure_thread_not_archived, ensure_user_root_target,
};
pub(super) use submit::validate_prompt_content;
