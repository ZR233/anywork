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
        }
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

    pub fn diagnostic(&self) -> BotDiagnostic {
        match self {
            Self::Protocol {
                kind,
                message,
                retryable,
                platform_code,
            } => BotDiagnostic {
                code: kind.label().to_string(),
                message: message.clone(),
                retryable: *retryable,
                platform_code: platform_code.clone(),
                guidance: if *kind == FeishuErrorKind::Permission
                    && platform_code.as_deref() == Some("21001")
                {
                    Some("checkTenantAccessPolicy".to_string())
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
