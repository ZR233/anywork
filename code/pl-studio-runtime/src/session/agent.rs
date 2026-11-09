//! 会话内一个已物化成员：目录身份、冻结 binding 与具体 Native 运行时。
use pl_protocol::{AgentBinding, AgentThreadIdentity};

use super::agent_runtime::NativeThreadRuntime;

/// 一个已物化成员。冷成员不构造本对象。
#[derive(Debug)]
pub(crate) struct AgentInstance {
    pub(crate) identity: AgentThreadIdentity,
    pub(crate) binding: AgentBinding,
    pub(crate) native: NativeThreadRuntime,
}
