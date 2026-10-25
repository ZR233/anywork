use pl_protocol::studio::{BotDiagnostic, StudioError, StudioErrorCode};

/// 飞书协议失败。保留安全类别与平台错误码，不携带 secret、正文或票据 URL。
#[derive(Debug, Clone, thiserror::Error)]
pub enum FeishuError {
    #[error("{kind:?}: {message}")]
    Protocol {
        kind: FeishuErrorKind,
        message: String,
        retryable: bool,
        platform_code: Option<String>,
        observed_send: Option<Box<pl_protocol::studio::BotSendResult>>,
        #[source]
        source: Option<std::sync::Arc<dyn std::error::Error + Send + Sync>>,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FeishuErrorKind {
    Transport,
    Timeout,
    Auth,
    Permission,
    NotFound,
    Conflict,
    Busy,
    Protocol,
    Unavailable,
    Rejected,
    Cancelled,
}

impl FeishuError {
    pub fn new(
        kind: FeishuErrorKind,
        message: impl Into<String>,
        retryable: bool,
        platform_code: Option<String>,
    ) -> Self {
        Self::Protocol {
            kind,
            message: message.into(),
            retryable,
            platform_code,
            observed_send: None,
            source: None,
        }
    }

    pub(crate) fn cancelled() -> Self {
        Self::new(
            FeishuErrorKind::Cancelled,
            "bot operation was interrupted locally",
            false,
            None,
        )
    }

    pub(crate) fn with_source(
        mut self,
        cause: impl std::error::Error + Send + Sync + 'static,
    ) -> Self {
        let Self::Protocol { source, .. } = &mut self;
        *source = Some(std::sync::Arc::new(cause));
        self
    }

    pub(crate) fn send_resource(error: crate::resource_store::ResourceStoreError) -> Self {
        use crate::resource_store::ResourceStoreError;
        let retryable = match &error {
            ResourceStoreError::Io { source, .. } | ResourceStoreError::Read(source) => !matches!(
                source.kind(),
                std::io::ErrorKind::InvalidData
                    | std::io::ErrorKind::InvalidInput
                    | std::io::ErrorKind::Unsupported
            ),
            // A real Unix barrier error, including Unsupported from this filesystem, remains
            // an unresolved IO obligation. Only the Windows capability is a terminal outcome.
            ResourceStoreError::DirectorySync(_) => cfg!(unix),
            ResourceStoreError::Worker(_) => true,
            _ => false,
        };
        let message = if !cfg!(any(unix, windows))
            && matches!(&error, ResourceStoreError::DirectorySync(source) if source.kind() == std::io::ErrorKind::Unsupported)
        {
            "send resource directory persistence barrier is unsupported on this platform; references and pending cleanup are retained"
        } else {
            "send resource retention/cleanup is incomplete; ledger references are retained"
        };
        Self::new(FeishuErrorKind::Unavailable, message, retryable, None).with_source(error)
    }

    /// Preserve the original typed cause privately. Diagnostic/Display never expose its content.
    pub(crate) fn history_read(context: &'static str, error: anyhow::Error) -> Self {
        use crate::studio::startup::{StudioStartupError, StudioStartupErrorKind};
        let cause = StudioStartupError::input(context, error);
        let retryable = cause.kind == StudioStartupErrorKind::Environment;
        let message = if retryable {
            format!("{context}: canonical history is temporarily unavailable")
        } else {
            format!("{context}: canonical history is unreadable; local recovery required")
        };
        let mut error = Self::new(FeishuErrorKind::Unavailable, message, retryable, None);
        let Self::Protocol { source, .. } = &mut error;
        *source = Some(std::sync::Arc::new(cause));
        error
    }

    pub(crate) fn with_observed_send(
        mut self,
        mut result: pl_protocol::studio::BotSendResult,
    ) -> Self {
        // HTTP effects were observed but their latest ledger write is not confirmed. Do not turn
        // the successful platform response into a durable completion receipt.
        result.receipt.durable = false;
        let Self::Protocol { observed_send, .. } = &mut self;
        *observed_send = Some(Box::new(result));
        self
    }

    pub(crate) fn observed_send(&self) -> Option<&pl_protocol::studio::BotSendResult> {
        let Self::Protocol { observed_send, .. } = self;
        observed_send.as_deref()
    }

    pub fn retryable(&self) -> bool {
        match self {
            Self::Protocol { retryable, .. } => *retryable,
        }
    }

    pub fn kind(&self) -> FeishuErrorKind {
        match self {
            Self::Protocol { kind, .. } => *kind,
        }
    }

    pub fn platform_code(&self) -> Option<&str> {
        match self {
            Self::Protocol { platform_code, .. } => platform_code.as_deref(),
        }
    }

    /// A side-effecting request without an explicit rejection may already have applied.
    /// Malformed success responses and HTTP 5xx are not evidence of non-acceptance.
    pub fn acceptance_unknown(&self) -> bool {
        match self.kind() {
            FeishuErrorKind::Timeout | FeishuErrorKind::Transport | FeishuErrorKind::Protocol => {
                true
            }
            FeishuErrorKind::Unavailable => self.platform_code().is_none_or(|code| {
                code.parse::<u16>()
                    .is_ok_and(|status| (500..600).contains(&status))
            }),
            _ => false,
        }
    }

    pub fn diagnostic(&self) -> BotDiagnostic {
        match self {
            Self::Protocol {
                kind,
                message,
                retryable,
                platform_code,
                ..
            } => BotDiagnostic {
                code: kind.label().to_string(),
                message: message.clone(),
                retryable: *retryable,
                platform_code: platform_code.clone(),
                guidance: if *kind == FeishuErrorKind::Permission
                    && platform_code.as_deref() == Some("21001")
                {
                    Some("checkTenantAccessPolicy".to_string())
                } else if platform_code.as_deref() == Some("300311") {
                    Some("grantCardkitCardWrite".to_string())
                } else {
                    kind.guidance().map(str::to_string)
                },
            },
        }
    }

    pub fn studio_error(&self) -> StudioError {
        let diagnostic = self.diagnostic();
        let code = match self.kind() {
            FeishuErrorKind::Auth | FeishuErrorKind::Permission => {
                StudioErrorCode::PermissionDenied
            }
            FeishuErrorKind::NotFound => StudioErrorCode::NotFound,
            FeishuErrorKind::Conflict => StudioErrorCode::Conflict,
            FeishuErrorKind::Busy => StudioErrorCode::Busy,
            FeishuErrorKind::Timeout
            | FeishuErrorKind::Unavailable
            | FeishuErrorKind::Transport
                if self.retryable() =>
            {
                StudioErrorCode::Unavailable
            }
            FeishuErrorKind::Rejected => StudioErrorCode::InvalidArgument,
            FeishuErrorKind::Protocol => StudioErrorCode::Protocol,
            _ => StudioErrorCode::Unavailable,
        };
        StudioError::new(code, diagnostic.message, self.retryable()).with_details(
            serde_json::json!({
                "botError": diagnostic.code,
                "platformCode": diagnostic.platform_code,
                "guidance": diagnostic.guidance,
                "observedSend": self.observed_send(),
            }),
        )
    }
}

impl FeishuErrorKind {
    pub const fn label(self) -> &'static str {
        match self {
            Self::Transport => "transport",
            Self::Timeout => "timeout",
            Self::Auth => "auth",
            Self::Permission => "permission",
            Self::NotFound => "notFound",
            Self::Conflict => "conflict",
            Self::Busy => "busy",
            Self::Protocol => "protocol",
            Self::Unavailable => "unavailable",
            Self::Rejected => "rejected",
            Self::Cancelled => "cancelled",
        }
    }

    pub const fn guidance(self) -> Option<&'static str> {
        match self {
            Self::Auth => Some("checkAppSecretAndPublish"),
            Self::Permission => Some("checkImScopesAndVisibility"),
            Self::Unavailable => Some("retryOrWaitAdminReview"),
            _ => None,
        }
    }
}
