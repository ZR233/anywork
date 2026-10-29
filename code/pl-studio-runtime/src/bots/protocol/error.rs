use pl_protocol::studio::{BotDiagnostic, StudioError, StudioErrorCode};

/// 飞书协议失败。保留安全类别与平台错误码，不携带 secret、正文或票据 URL。
#[derive(Debug, Clone)]
pub enum FeishuError {
    Protocol {
        kind: FeishuErrorKind,
        message: String,
        retryable: bool,
        platform_code: Option<String>,
        source: Option<std::sync::Arc<dyn std::error::Error + Send + Sync>>,
    },
}

impl std::fmt::Display for FeishuError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Protocol { kind, message, .. } => write!(formatter, "{kind:?}: {message}"),
        }
    }
}

impl std::error::Error for FeishuError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            // Return the Arc's pointee, not Arc's own Error implementation (which would
            // skip the underlying root error when enumerating source()).
            Self::Protocol { source, .. } => source
                .as_deref()
                .map(|source| source as &(dyn std::error::Error + 'static)),
        }
    }
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
            source: None,
        }
    }

    /// Retains storage/decoder causes without exposing them through the public diagnostic DTO.
    pub fn with_source(mut self, source: impl Into<anyhow::Error>) -> Self {
        let Self::Protocol { source: slot, .. } = &mut self;
        *slot = Some(std::sync::Arc::from(
            source
                .into()
                .reallocate_into_boxed_dyn_error_without_backtrace(),
        ));
        self
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

#[cfg(test)]
mod source_tests {
    use super::*;
    use std::error::Error;

    #[test]
    fn retained_cause_is_typed_cloneable_and_not_in_the_diagnostic() {
        let error = FeishuError::new(
            FeishuErrorKind::Protocol,
            "invalid bot document",
            false,
            None,
        )
        .with_source(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            "private-input",
        ));
        let cloned = error.clone();
        let source = cloned.source().expect("typed cause survives cloning");
        assert!(source.is::<std::io::Error>());
        assert_eq!(cloned.diagnostic().message, "invalid bot document");
        assert!(!cloned.to_string().contains("private-input"));
    }
}
