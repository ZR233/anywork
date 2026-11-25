use serde::{Deserialize, Serialize};

use crate::{ProviderFailureKind, RetryDisposition};
use pl_model::runtime::ModelRecoveryStopReason;
use pl_protocol::{ProviderFailureStage, ProviderRecovery};

/// Turn 失败所属的稳定领域类别。
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum TurnFailureCategory {
    Provider,
    ProviderCapacity,
    Tool,
    Validation,
    Protocol,
    Internal,
}

/// 跨 runtime 与宿主边界保存的结构化 turn 失败。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct TurnFailure {
    pub category: TurnFailureCategory,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub provider_kind: Option<ProviderFailureKind>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub code: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub http_status: Option<u16>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error_type: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub request_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub stage: Option<ProviderFailureStage>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub recovery: Option<ModelRecoveryInfo>,
    pub message: String,
    #[serde(with = "ProductRetryDisposition")]
    pub retry: RetryDisposition,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ModelRecoveryInfo {
    pub retry_count: Option<u32>,
    pub max_retries: Option<u32>,
    #[serde(default, with = "optional_decimal_u64")]
    pub effective_wait_millis: Option<u64>,
    pub reason: Option<ProviderRecovery>,
    pub stop_reason: Option<ModelRecoveryStopReason>,
    pub error: Option<String>,
}

/// Recovery facts attached to the existing commentary Timeline item.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, utoipa::ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ModelRecoveryNotice {
    #[schema(value_type = Option<String>)]
    pub failure_kind: Option<ProviderFailureKind>,
    #[schema(value_type = Option<String>)]
    pub reason: Option<ProviderRecovery>,
    pub retry_count: u32,
    pub max_retries: u32,
    #[serde(default, with = "optional_decimal_u64")]
    #[schema(value_type = Option<String>)]
    pub effective_wait_millis: Option<u64>,
    #[schema(value_type = String)]
    pub phase: pl_core::model::ModelRecoveryPhase,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[schema(value_type = Option<Object>)]
    pub failure: Option<TurnFailure>,
}

// Studio product JSON sends wait values as decimal strings so all u64 values survive JS readers.
#[derive(Serialize, Deserialize)]
#[serde(remote = "RetryDisposition", rename_all = "camelCase", tag = "kind")]
enum ProductRetryDisposition {
    Retryable {
        #[serde(
            rename = "retryAfterMs",
            default,
            skip_serializing_if = "Option::is_none",
            with = "optional_decimal_u64"
        )]
        retry_after_ms: Option<u64>,
    },
    Permanent,
    WaitUnrepresentable,
}

mod optional_decimal_u64 {
    use serde::{Deserialize, Deserializer, Serializer, de::Error};

    pub(super) fn serialize<S: Serializer>(
        value: &Option<u64>,
        serializer: S,
    ) -> Result<S::Ok, S::Error> {
        match value {
            Some(value) => serializer.collect_str(value),
            None => serializer.serialize_none(),
        }
    }

    pub(super) fn deserialize<'de, D: Deserializer<'de>>(
        deserializer: D,
    ) -> Result<Option<u64>, D::Error> {
        Option::<String>::deserialize(deserializer)?
            .map(|value| value.parse().map_err(D::Error::custom))
            .transpose()
    }
}

impl TurnFailure {
    /// 构造一个不应由宿主自动重试的失败。
    pub fn permanent(category: TurnFailureCategory, message: impl Into<String>) -> Self {
        Self {
            category,
            provider_kind: None,
            code: None,
            http_status: None,
            error_type: None,
            request_id: None,
            stage: None,
            recovery: None,
            message: message.into(),
            retry: RetryDisposition::Permanent,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn product_failure_waits_use_decimal_strings_and_preserve_unknown() {
        let mut failure = TurnFailure::permanent(TurnFailureCategory::Provider, "provider busy");
        failure.retry = RetryDisposition::Retryable {
            retry_after_ms: Some(u64::MAX),
        };
        failure.recovery = Some(ModelRecoveryInfo {
            retry_count: Some(2),
            max_retries: Some(5),
            effective_wait_millis: Some(u64::MAX),
            reason: Some(ProviderRecovery::None),
            stop_reason: None,
            error: None,
        });
        let wire = serde_json::to_value(&failure).unwrap();
        assert_eq!(wire["retry"]["retryAfterMs"], "18446744073709551615");
        assert_eq!(
            wire["recovery"]["effectiveWaitMillis"],
            "18446744073709551615"
        );
        assert_eq!(
            serde_json::from_value::<TurnFailure>(wire.clone()).unwrap(),
            failure
        );
        assert_eq!(
            serde_json::to_value(&failure.retry).unwrap()["retryAfterMs"],
            json!(u64::MAX)
        );

        for (group, field) in [
            ("retry", "retryAfterMs"),
            ("recovery", "effectiveWaitMillis"),
        ] {
            let mut numeric = wire.clone();
            numeric[group][field] = json!(30);
            assert!(serde_json::from_value::<TurnFailure>(numeric).is_err());
        }
        let mut unknown = wire;
        unknown["retry"]["retryAfterMs"] = serde_json::Value::Null;
        unknown["recovery"]
            .as_object_mut()
            .unwrap()
            .remove("effectiveWaitMillis");
        let unknown = serde_json::from_value::<TurnFailure>(unknown).unwrap();
        assert_eq!(
            unknown.retry,
            RetryDisposition::Retryable {
                retry_after_ms: None
            }
        );
        assert_eq!(unknown.recovery.unwrap().effective_wait_millis, None);
    }
}
