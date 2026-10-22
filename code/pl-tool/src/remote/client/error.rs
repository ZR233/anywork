use std::io;
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
        code: pl_protocol::remote::RemoteErrorCode,
        message: String,
    },
}

impl From<io::Error> for RemoteClientError {
    fn from(error: io::Error) -> Self {
        Self::Protocol(error.to_string())
    }
}
