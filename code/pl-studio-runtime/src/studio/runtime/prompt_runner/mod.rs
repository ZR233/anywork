//! StudioRuntime 的 prompt 生命周期实现。
//!
//! 职责划分:
//! - `submit`: prompt/turn 提交入口、内容校验与 root 角色对齐;
//! - `control`: 精确停止（按执行身份）与无内容继续（控制输入 + 继续点认领）的用户入口;
//! - `activation`: Thread 对应 agent 的激活、驻留恢复与 canonical owner 读取;
//! - `interaction`: 交互读取、收束与重启后的 pending 交互恢复。

mod activation;
mod control;
mod handover;
mod interaction;
mod submit;

pub(in crate::studio::runtime) use control::{
    UserThreadAction, ensure_thread_not_archived, ensure_user_root_target,
};
pub(super) use submit::validate_prompt_content;
