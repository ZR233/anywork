//! 多 crate 同时直接依赖的最小共享基础契约。
//!
//! 本 crate 只承载跨平级或无直接依赖关系的多个 crate 共同消费的基础错误、枚举标签宏、
//! 首次输出观测来源，以及工具前端（`pl-tool`）与宿主运行时（`pl-studio-runtime`）共享的
//! 最小身份、工作区回执、路由与分发契约。单一领域或单一根消费者的定义均归各自所属 crate。

mod collaboration;
mod error;
mod first_output;
mod id;
mod labeled;
mod provider_failure;

pub use collaboration::{
    AgentBackendKind, AgentReviewBaseline, AgentReviewFeedback, AgentReviewTargetSnapshot,
    AgentThreadIdentity, AgentWorkspaceAssignmentSnapshot, AgentWorkspaceMode,
    AgentWorktreeSnapshot, DelegationMode, DelegationPreference, DelegationSettings,
    NewThreadModelRoute, StateError,
};
pub use error::{PureError, Result};
pub use first_output::FirstOutputSource;
pub use id::{AgentId, SessionId, ThreadId};
pub use labeled::{LabeledEnum, UnknownLabelError};
pub use provider_failure::{
    ProviderFailure, ProviderFailureContext, ProviderFailureKind, ProviderFailureStage,
    ProviderRecovery, RetryDisposition,
};
