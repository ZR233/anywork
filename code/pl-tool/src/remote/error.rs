//! SSH remote 客户端、物理连接与管理器的共享错误类型。
//!
//! 这里的变体同时是 Studio 的错误映射输入，因此保持既有穷尽集合；协议诊断信息通过
//! `Protocol` 的文本与首次失联原因携带，不新增更细的公共变体。

use std::sync::Arc;

/// Bound on one aggregated context string; diagnostics never grow without limit.
const MAX_CONTEXT_CHARS: usize = 1024;

use pl_protocol::remote::RemoteErrorCode;

/// SSH 认证失败诊断：保留原始失败文本，并在能解析时附带服务器公布的认证方法。
///
/// `password_offered()` 在未能从 OpenSSH `Permission denied (...)` 文本解析出方法列表时返回
/// `None`，调用方应按需要密码处理，以保持旧行为。
#[derive(Debug, Clone)]
pub struct SshAuthFailure {
    reason: String,
    methods: Vec<String>,
}

impl SshAuthFailure {
    /// 用原始失败文本与已解析的认证方法构造诊断。
    pub fn new(reason: impl Into<String>, methods: Vec<String>) -> Self {
        Self {
            reason: reason.into(),
            methods,
        }
    }

    /// 服务器是否公布了密码类认证。
    ///
    /// - 方法列表含精确的 `password`，或前缀为 `keyboard-interactive`（容忍 `keyboard-interactive:pam` 等后缀）→ `Some(true)`
    /// - 解析到方法列表但两者都没有 → `Some(false)`
    /// - 解析不到方法列表 → `None`
    pub fn password_offered(&self) -> Option<bool> {
        if self.methods.is_empty() {
            None
        } else {
            Some(
                self.methods.iter().any(|method| {
                    method == "password" || method.starts_with("keyboard-interactive")
                }),
            )
        }
    }
}

impl std::fmt::Display for SshAuthFailure {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(&self.reason)
    }
}

/// SSH remote 客户端与管理器的统一失败。
#[derive(Debug, Clone, thiserror::Error)]
pub enum RemoteClientError {
    /// The host has sealed SSH connection admission for shutdown.
    #[error("SSH manager is closing")]
    ManagerClosing,
    #[error("remoteDisconnected")]
    Disconnected,
    #[error("remote operation cancelled before admission")]
    Cancelled,
    /// SSH authentication failed (e.g. password required or rejected).
    #[error("SSH authentication required or failed: {0}")]
    AuthenticationFailed(SshAuthFailure),
    #[error("remote helper protocol failed: {0}")]
    Protocol(String),
    #[error("remote helper rejected the request ({code:?}): {message}")]
    Remote {
        code: RemoteErrorCode,
        message: String,
    },
    /// One real local I/O failure, keeping the original source instead of a formatted copy.
    #[error("remote I/O failed during {stage}: {source}")]
    Io {
        stage: &'static str,
        #[source]
        source: Arc<std::io::Error>,
    },
    /// One real task failure (panic, cancellation of an owner task), keeping the join source.
    #[error("remote task failed during {stage}: {source}")]
    Task {
        stage: &'static str,
        #[source]
        source: Arc<tokio::task::JoinError>,
    },
    /// Bounded context around the first real cause. The source keeps its own classification, so a
    /// context never turns a disconnect or an authentication failure into something else.
    #[error("{context}: {source}")]
    Context {
        context: String,
        #[source]
        source: Arc<RemoteClientError>,
    },
}

impl RemoteClientError {
    /// Maps one helper-authored error, preserving its typed code and message.
    pub(in crate::remote) fn remote(error: &pl_protocol::remote::RemoteError) -> Self {
        Self::Remote {
            code: error.code,
            message: error.message.clone(),
        }
    }

    /// A client-side protocol violation; never used for a helper application error.
    pub(in crate::remote) fn protocol(message: impl Into<String>) -> Self {
        Self::Protocol(message.into())
    }

    /// One local I/O failure with its real source.
    pub(in crate::remote) fn io(stage: &'static str, source: std::io::Error) -> Self {
        Self::Io {
            stage,
            source: Arc::new(source),
        }
    }

    /// One task failure with its real join source.
    pub(in crate::remote) fn task(stage: &'static str, source: tokio::task::JoinError) -> Self {
        Self::Task {
            stage,
            source: Arc::new(source),
        }
    }

    /// Combines bounded diagnostics with the first real typed cause.
    ///
    /// The first cause is preserved as the source and is never wrapped twice: without another cause
    /// the diagnostics would only decorate success, so a context is created only around a real cause.
    /// This is what keeps repeated retries from growing an unbounded context chain.
    pub(in crate::remote) fn aggregate(
        context: impl Into<String>,
        first: Option<Self>,
        diagnostics: &[String],
    ) -> Self {
        let mut context = context.into();
        for diagnostic in diagnostics {
            context.push_str("; ");
            context.push_str(diagnostic);
        }
        // The context is bounded observation; the typed cause keeps the real detail.
        if context.chars().count() > MAX_CONTEXT_CHARS {
            context = context.chars().take(MAX_CONTEXT_CHARS).collect();
        }
        match first {
            Some(source) => Self::Context {
                context,
                source: Arc::new(source),
            },
            None => Self::Protocol(context),
        }
    }

    /// Whether the failure means the physical connection is unusable.
    ///
    /// A context carries the classification of the cause it wraps.
    pub(in crate::remote) fn is_disconnect(&self) -> bool {
        match self {
            Self::Disconnected | Self::ManagerClosing => true,
            Self::Context { source, .. } => source.is_disconnect(),
            // A transport I/O failure or an owned-task failure ends the physical connection just like a
            // closed driver: keeping the typed source must never make a broken connection look healthy.
            Self::Io { .. } | Self::Task { .. } => true,
            Self::Cancelled
            | Self::AuthenticationFailed(_)
            | Self::Protocol(_)
            | Self::Remote { .. } => false,
        }
    }
}

impl From<std::io::Error> for RemoteClientError {
    fn from(error: std::io::Error) -> Self {
        // The real I/O source is kept instead of being flattened into protocol text.
        Self::io("local io", error)
    }
}
