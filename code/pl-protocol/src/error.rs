use thiserror::Error;

use crate::ProviderFailure;

#[derive(Debug, Error)]
pub enum PureError {
    #[error("LLM provider error: {0}")]
    LlmError(String),

    #[error("LLM provider error: {0}")]
    Provider(#[source] Box<ProviderFailure>),

    #[error("context window exceeded: {0} tokens")]
    ContextOverflow(usize),

    #[error("tool not found: {0}")]
    ToolNotFound(String),

    #[error("tool execution failed: {tool}: {error}")]
    ToolExecutionFailed { tool: String, error: String },

    #[error("agent limit reached: max agents {max_agents}")]
    AgentLimitReached { max_agents: usize },

    #[error("agent depth limit reached: max depth {max_depth}")]
    AgentDepthLimitReached { max_depth: u32 },

    #[error("provider capacity unavailable: {message}")]
    ProviderCapacity { message: String },

    #[error("permission denied: {0}")]
    PermissionDenied(String),

    #[error("sandbox error: {0}")]
    SandboxError(String),

    #[error("memory store error: {0}")]
    MemoryError(String),

    #[error("configuration error: {0}")]
    ConfigError(String),

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("JSON error: {0}")]
    SerdeJson(#[from] serde_json::Error),

    #[error("protocol error: {0}")]
    Protocol(String),

    #[error("HTTP error: {0}")]
    HttpError(String),
}

impl From<ProviderFailure> for PureError {
    fn from(failure: ProviderFailure) -> Self {
        Self::Provider(Box::new(failure))
    }
}

impl PureError {
    /// 返回结构化 Provider failure（如果该错误来自 typed provider 边界）。
    pub fn provider_failure_ref(&self) -> Option<&ProviderFailure> {
        match self {
            Self::Provider(failure) => Some(failure),
            _ => None,
        }
    }
}

pub type Result<T> = std::result::Result<T, PureError>;
