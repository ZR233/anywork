//! 从已提交的模型 attempt 事实构造稳定的计费记录。
//!
//! `pl-core` 只负责保存 opaque attempt 事实；模型 receipt 的解释属于本 crate。把这段解码
//! 放在模型边界，Studio、其它宿主和历史查询都能复用同一套语义，而无需复制 provider
//! receipt 解析或读取存储表。

use crate::completion::InferenceBillingRecord;
use pl_core::thread::{AttemptOutcome, journal::AttemptUpdate};

use pl_core::context::OpaquePayload;
use pl_core::model::{ModelError, ModelFailureKind};
use serde::{Deserialize, Serialize};

const SETTLEMENT_FORMAT: &str = "pl.model.sub-attempt-settlement";
const SETTLEMENT_VERSION: u32 = 2;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ModelRecoveryStopReason {
    BudgetExhausted,
    SideEffects,
    SaveFailed,
    RepairFailed,
    WaitUnrepresentable,
    ContextCompactionRequired,
    PermanentFailure,
    Cancelled,
}

impl ModelRecoveryStopReason {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::BudgetExhausted => "budgetExhausted",
            Self::SideEffects => "sideEffects",
            Self::SaveFailed => "saveFailed",
            Self::RepairFailed => "repairFailed",
            Self::WaitUnrepresentable => "waitUnrepresentable",
            Self::ContextCompactionRequired => "contextCompactionRequired",
            Self::PermanentFailure => "permanentFailure",
            Self::Cancelled => "cancelled",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelRecoveryDecision {
    pub failure_kind: pl_protocol::ProviderFailureKind,
    pub recovery: pl_protocol::ProviderRecovery,
    pub retry: u32,
    pub max_retries: u32,
    pub effective_wait_millis: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub provider_failure: Option<pl_protocol::ProviderFailure>,
}

impl ModelRecoveryDecision {
    pub(super) fn encode(&self) -> Result<OpaquePayload, serde_json::Error> {
        Ok(OpaquePayload::new(
            "pl.model.recovery-decision",
            1,
            serde_json::to_string(self)?,
        )
        .expect("constant recovery decision format and version"))
    }
}

pub fn model_recovery_decision(
    payload: &OpaquePayload,
) -> Result<ModelRecoveryDecision, ModelError> {
    decode(payload, "pl.model.recovery-decision", 1)
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelSubAttemptReceipt {
    pub turn_id: Option<String>,
    pub attempt_id: String,
    pub logical_request_id: String,
    pub generation: u32,
    pub retry: u32,
    pub provider_failure: Option<pl_protocol::ProviderFailure>,
    pub message: Option<String>,
    pub billing: InferenceBillingRecord,
}

impl ModelSubAttemptReceipt {
    pub(super) fn encode(&self) -> Result<OpaquePayload, serde_json::Error> {
        Ok(OpaquePayload::new(
            SETTLEMENT_FORMAT,
            SETTLEMENT_VERSION,
            serde_json::to_string(self)?,
        )
        .expect("constant settlement format and version"))
    }
}

/// Validates an original owner's settlement envelope and returns its frozen receipt.
pub fn model_sub_attempt_receipt(
    settlement: &pl_core::model::ModelSubAttemptSettlement,
) -> Result<ModelSubAttemptReceipt, ModelError> {
    let receipt: ModelSubAttemptReceipt =
        decode_sub_attempt(&settlement.payload, SETTLEMENT_VERSION)?;
    if receipt.attempt_id != settlement.attempt_id
        || receipt.turn_id != settlement.turn_id
        || receipt.generation != settlement.generation
    {
        return Err(invalid(std::io::Error::other(
            "settlement receipt identity mismatch",
        )));
    }
    Ok(receipt)
}

/// Opens a saved original at the History or Current read boundary. Legacy v1 records retain
/// their as-recorded source and frozen accounting. They never enter current admission.
pub fn model_saved_sub_attempt_receipt(
    payload: &OpaquePayload,
) -> Result<ModelSubAttemptReceipt, ModelError> {
    let version = match payload.version() {
        1 => 1,
        _ => SETTLEMENT_VERSION,
    };
    decode_sub_attempt(payload, version)
}

fn decode_sub_attempt(
    payload: &OpaquePayload,
    version: u32,
) -> Result<ModelSubAttemptReceipt, ModelError> {
    let receipt: ModelSubAttemptReceipt = decode(payload, SETTLEMENT_FORMAT, version)?;
    let matches_billing_identity = receipt.billing.attempt.as_ref().is_some_and(|attempt| {
        attempt.core_attempt_id == receipt.attempt_id
            && attempt.generation == receipt.generation
            && attempt.logical_request_id == receipt.logical_request_id
    });
    if receipt.attempt_id.is_empty()
        || receipt.turn_id.as_ref().is_some_and(String::is_empty)
        || (version == 1 && receipt.turn_id.is_none())
        || receipt.logical_request_id.is_empty()
        || !matches_billing_identity
        || receipt.billing.inference_id
            != model_sub_attempt_id(&receipt.attempt_id, receipt.generation)
    {
        return Err(invalid(std::io::Error::other(
            "settlement receipt identity mismatch",
        )));
    }
    Ok(receipt)
}

/// Stable recorded inference identity for one physical attempt generation.
pub fn model_sub_attempt_id(attempt: &str, generation: u32) -> String {
    format!("sub-attempt:{}:{attempt}:{generation}", attempt.len())
}

/// Reads the already counted settlement of a Core-committed result for context and throughput.
pub fn model_committed_sub_attempt_billing(
    attempt: &AttemptUpdate,
) -> Result<Option<InferenceBillingRecord>, ModelError> {
    let AttemptOutcome::Committed(output) = &attempt.outcome else {
        return Ok(None);
    };
    let Some(frame) = super::thread_model::model_response_receipt(output)? else {
        return Ok(None);
    };
    let response = frame.response;
    let Some(last) = response.settlements.last() else {
        return Ok(None);
    };
    let generation =
        u32::try_from(response.settlements.len() - 1).map_err(|error| invalid(error))?;
    let receipt = model_sub_attempt_receipt(&pl_core::model::ModelSubAttemptSettlement {
        turn_id: Some(attempt.turn_id.clone()),
        attempt_id: attempt.attempt_id.clone(),
        generation,
        payload: last.clone(),
    })?;
    if receipt.billing.accounting != response.accounting
        || receipt.billing.attempt.as_ref().is_none_or(|metadata| {
            metadata.outcome != crate::completion::InferenceAttemptOutcome::Succeeded
        })
    {
        return Err(invalid(std::io::Error::other(
            "settlement does not describe the committed response",
        )));
    }
    Ok(Some(receipt.billing))
}

fn invalid(source: impl std::error::Error + Send + Sync + 'static) -> ModelError {
    super::thread_model::failure(ModelFailureKind::UnsupportedContent, source)
}

fn decode<T: serde::de::DeserializeOwned>(
    payload: &OpaquePayload,
    format: &str,
    version: u32,
) -> Result<T, ModelError> {
    if payload.format() != format || payload.version() != version {
        return Err(invalid(std::io::Error::other(
            "unsupported model billing receipt",
        )));
    }
    serde_json::from_str(payload.content()).map_err(invalid)
}

#[cfg(test)]
mod tests {
    #[test]
    fn historical_orchestration_values_round_trip_without_changing_admission_bytes() {
        let encoded = concat!(
            r#"{"toolSchemaEstimatedTokens":0,"toolResultEstimatedTokens":0,"toolCalls":2,"#,
            r#""parallelCandidates":0,"actualParallelCalls":0,"toolBatchElapsedMillis":0,"#,
            r#""toolExecutionMillis":0,"toolCriticalPathMillis":0,"toolCacheHits":0,"#,
            r#""duplicateSuppressed":0,"programCount":0,"programToolCalls":0,"#,
            r#""transportAttempts":1,"continuationAttempts":0,"continuationUsed":0,"#,
            r#""continuationInvalid":0,"httpFallbacks":0}"#,
        );
        let historical: crate::completion::InferenceOrchestrationMetrics =
            serde_json::from_str(encoded).unwrap();
        assert_eq!(serde_json::to_string(&historical).unwrap(), encoded);
        let mut unknown = crate::completion::InferenceOrchestrationMetrics::default();
        assert_eq!(unknown.parallel_saved_millis(), None);
        unknown.merge(&historical);
        assert_eq!(unknown.actual_parallel_calls, None);
        assert_eq!(unknown.parallel_saved_millis(), None);
    }
}
