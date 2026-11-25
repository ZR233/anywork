use serde::{Deserialize, Serialize};
use std::{error::Error, fmt, sync::Arc, time::Instant};

/// Provider 失败的稳定语义类别；控制流不得从 message 或 provider code 反向推断。
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum ProviderFailureKind {
    Authentication,
    Authorization,
    Quota,
    RateLimit,
    ServiceBusy,
    ContextLimit,
    InvalidRequest,
    ContentBlocked,
    OutputLimit,
    Transport,
    Protocol,
    Unknown,
}

impl ProviderFailureKind {
    /// Stable camelCase spelling used by the serialized failure and product consumers.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Authentication => "authentication",
            Self::Authorization => "authorization",
            Self::Quota => "quota",
            Self::RateLimit => "rateLimit",
            Self::ServiceBusy => "serviceBusy",
            Self::ContextLimit => "contextLimit",
            Self::InvalidRequest => "invalidRequest",
            Self::ContentBlocked => "contentBlocked",
            Self::OutputLimit => "outputLimit",
            Self::Transport => "transport",
            Self::Protocol => "protocol",
            Self::Unknown => "unknown",
        }
    }
}

/// 供应商失败的暂时性及建议最短等待。重放资格由调用执行器判断。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", tag = "kind")]
pub enum RetryDisposition {
    Retryable {
        #[serde(
            rename = "retryAfterMs",
            default,
            skip_serializing_if = "Option::is_none"
        )]
        retry_after_ms: Option<u64>,
    },
    Permanent,
    /// 存在有效约束，但当前时钟或历史时间单位无法安全表示。
    WaitUnrepresentable,
}

impl RetryDisposition {
    /// 是否属于可进入重试判断的暂时失败。
    pub fn is_retryable(&self) -> bool {
        matches!(self, Self::Retryable { .. })
    }

    /// 返回 provider 建议的最短等待时间。
    pub fn retry_after_ms(&self) -> Option<u64> {
        match self {
            Self::Retryable { retry_after_ms } => *retry_after_ms,
            Self::Permanent | Self::WaitUnrepresentable => None,
        }
    }
}

/// Provider adapter 跨 crate 返回的结构化失败阶段。
#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum ProviderFailureStage {
    #[default]
    Unknown,
    Request,
    Handshake,
    Stream,
    Attachment,
}

#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum ProviderRecovery {
    #[default]
    None,
    HttpFallback,
    RefreshAttachments,
    FullContext,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ProviderFailureContext {
    pub stage: ProviderFailureStage,
    pub request_id: Option<String>,
    pub recovery: ProviderRecovery,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderFailure {
    #[serde(default)]
    pub context: ProviderFailureContext,
    pub kind: ProviderFailureKind,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub code: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error_type: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub http_status: Option<u16>,
    pub message: String,
    pub retry: RetryDisposition,
    /// Wall-clock receive time of the selected wait hint or, without a hint, the failure.
    /// The time is in Unix milliseconds and is never used as a running timer.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub observed_at_unix_ms: Option<u64>,
    /// A vendor delay reported alongside a permanent failure, including repair candidates.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reported_wait_ms: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub details: Option<Box<serde_json::Value>>,
    #[serde(skip)]
    retry_deadline: Option<Instant>,
    #[serde(skip)]
    cause: FailureCause,
}

impl ProviderFailure {
    pub fn new(
        kind: ProviderFailureKind,
        message: impl Into<String>,
        retry: RetryDisposition,
    ) -> Self {
        Self {
            context: ProviderFailureContext::default(),
            kind,
            code: None,
            error_type: None,
            http_status: None,
            message: message.into(),
            retry,
            observed_at_unix_ms: None,
            reported_wait_ms: None,
            details: None,
            retry_deadline: None,
            cause: FailureCause::default(),
        }
    }

    /// The earliest next send, fixed on the monotonic clock when the hint arrived.
    pub fn retry_deadline(&self) -> Option<Instant> {
        self.retry_deadline
    }

    pub fn with_retry_deadline(mut self, deadline: Instant) -> Self {
        self.retry_deadline = Some(deadline);
        self
    }

    pub fn at_stage(mut self, stage: ProviderFailureStage) -> Self {
        self.context.stage = stage;
        self
    }

    /// Retains another observed cause without replacing the original cause or its chain.
    pub fn with_source(mut self, source: impl Error + Send + Sync + 'static) -> Self {
        self.cause.0.push(Arc::new(source));
        self
    }

    /// All runtime causes in observation order; each retains its own source chain.
    ///
    /// [`Error::source`] exposes the first cause. This view also retains independent
    /// failures, such as a body read failing after an invalid envelope was observed.
    /// Causes are omitted from serialized facts and from diagnostic `Debug` output.
    pub fn sources(&self) -> impl ExactSizeIterator<Item = &(dyn Error + Send + Sync + 'static)> {
        self.cause.0.iter().map(Arc::as_ref)
    }
}

impl PartialEq for ProviderFailure {
    fn eq(&self, other: &Self) -> bool {
        self.context == other.context
            && self.kind == other.kind
            && self.code == other.code
            && self.error_type == other.error_type
            && self.http_status == other.http_status
            && self.message == other.message
            && self.retry == other.retry
            && self.observed_at_unix_ms == other.observed_at_unix_ms
            && self.reported_wait_ms == other.reported_wait_ms
            && self.details == other.details
    }
}

impl Eq for ProviderFailure {}

// A typed cause is available to the running caller, but cannot enter diagnostics
// through the derived Debug formatter or a persisted product record.
#[derive(Clone, Default)]
struct FailureCause(Vec<Arc<dyn Error + Send + Sync>>);

impl fmt::Debug for FailureCause {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("FailureCause")
            .finish_non_exhaustive()
    }
}

impl Error for ProviderFailure {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        self.cause
            .0
            .first()
            .map(|source| source.as_ref() as &dyn Error)
    }
}

impl fmt::Display for ProviderFailure {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.message)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn failure_persists_camel_case_retry_metadata_and_omits_runtime_fields() {
        let mut failure = ProviderFailure::new(
            ProviderFailureKind::RateLimit,
            "retry later",
            RetryDisposition::Retryable {
                retry_after_ms: Some(45_000),
            },
        )
        .with_retry_deadline(Instant::now())
        .with_source(std::io::Error::other("runtime-only diagnostic"));
        assert_eq!(failure.observed_at_unix_ms, None);
        failure.observed_at_unix_ms = Some(1234);
        let json = serde_json::to_value(&failure).unwrap();
        assert_eq!(json["kind"], ProviderFailureKind::RateLimit.as_str());
        assert_eq!(json["observedAtUnixMs"], 1234);
        assert_eq!(
            json["retry"],
            serde_json::json!({"kind":"retryable","retryAfterMs":45000})
        );
        let restored: ProviderFailure = serde_json::from_value(json.clone()).unwrap();
        assert_eq!(restored, failure);
        assert_eq!(restored.retry_deadline(), None);
        assert!(restored.source().is_none());

        let mut legacy = json;
        legacy.as_object_mut().unwrap().remove("observedAtUnixMs");
        let legacy: ProviderFailure = serde_json::from_value(legacy).unwrap();
        assert_eq!(legacy.observed_at_unix_ms, None);
        assert_ne!(legacy, restored);

        let error: crate::PureError = failure.into();
        assert_eq!(error.provider_failure_ref(), Some(&restored));
        let cause = error.source().and_then(Error::source).unwrap();
        assert!(cause.is::<std::io::Error>());
        assert!(!format!("{error:?}").contains("runtime-only diagnostic"));
    }
}
