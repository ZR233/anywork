//! Independent, immutable review-delivery diagnostics; never a replacement terminal report.
use super::agent_review::{ReviewDeliverySource, ReviewForward, ReviewForwardReason};
use anyhow::{Result, ensure};
use pl_core::{
    context::{AgentMessageKind, ContextContent, OpaquePayload},
    thread::inbox::ThreadMessage,
};
use serde::{Deserialize, Serialize};

pub(crate) const FACT_FORMAT: &str = "pl.studio.review-delivery-fact";
pub(crate) const MESSAGE_FORMAT: &str = "pl.studio.review-delivery-exception";
pub(crate) const EXTENSION_PREFIX: &str = "studio.review-delivery:";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct ReviewDeliveryException {
    pub reviewer_id: String,
    pub turn_id: String,
    pub input_id: Option<String>,
    pub terminal_sequence: u64,
    pub target_agent_id: String,
    pub feedback_message_id: String,
    pub observation: DeliveryObservation,
    pub outcome: DeliveryExceptionOutcome,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(crate) enum DeliveryObservation {
    LiveTerminal,
    Reconciliation,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "state", rename_all = "camelCase", deny_unknown_fields)]
pub(crate) enum DeliveryExceptionOutcome {
    Rejected { reason: DeliveryExceptionReason },
    Unconfirmed { reason: DeliveryExceptionReason },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(
    tag = "kind",
    content = "detail",
    rename_all = "camelCase",
    deny_unknown_fields
)]
pub(crate) enum DeliveryExceptionReason {
    RecoveryRequiresScheduling,
    MissingFrozenBaseline,
    TargetChanged,
    TargetUnavailable,
    AdmissionRejected(Vec<String>),
    IdentityConflict,
    IdentityUnverifiable,
    StorageUnavailable(Vec<String>),
    SendUnconfirmed(Vec<String>),
    WorkspaceCheckRejected(WorkspaceFailure),
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct WorkspaceFailure {
    pub certainty: WorkspaceFailureCertainty,
    pub source: Vec<String>,
}
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(crate) enum WorkspaceFailureCertainty {
    Invalid,
    Unconfirmed,
}

/// The extension is only the CAS carrier. The history receipt retains these exact bytes.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct ReviewDeliveryFact {
    pub terminal_sequence: u64,
    pub message: ThreadMessage,
}

impl ReviewDeliveryException {
    pub(crate) fn from_forward(
        reviewer: &str,
        turn: &str,
        input: Option<&str>,
        terminal_sequence: u64,
        target: &str,
        observation: ReviewDeliverySource,
        forward: &ReviewForward,
    ) -> Option<Self> {
        let (message_id, outcome) = match forward {
            ReviewForward::Rejected { message_id, reason } => (
                message_id,
                DeliveryExceptionOutcome::Rejected {
                    reason: reason.into(),
                },
            ),
            ReviewForward::Unconfirmed { message_id, reason } => (
                message_id,
                DeliveryExceptionOutcome::Unconfirmed {
                    reason: reason.into(),
                },
            ),
            ReviewForward::NotRequested
            | ReviewForward::NotRequired
            | ReviewForward::Accepted { .. } => return None,
        };
        Some(Self {
            reviewer_id: reviewer.into(),
            turn_id: turn.into(),
            input_id: input.map(str::to_owned),
            terminal_sequence,
            target_agent_id: target.into(),
            feedback_message_id: message_id.clone(),
            observation: match observation {
                ReviewDeliverySource::LiveTerminal => DeliveryObservation::LiveTerminal,
                ReviewDeliverySource::Reconciliation => DeliveryObservation::Reconciliation,
            },
            outcome,
        })
    }

    pub(crate) fn message_id(&self) -> String {
        format!(
            "studio.review-exception.{}:{}:{}:{}:{}:{}:{}",
            self.reviewer_id.len(),
            self.reviewer_id,
            self.turn_id.len(),
            self.turn_id,
            self.terminal_sequence,
            self.target_agent_id.len(),
            self.target_agent_id
        )
    }

    pub(crate) fn into_fact(self) -> Result<ReviewDeliveryFact> {
        let content = serde_json::to_string(&self)?;
        Ok(ReviewDeliveryFact {
            terminal_sequence: self.terminal_sequence,
            message: ThreadMessage {
                id: self.message_id(),
                kind: AgentMessageKind::Report,
                source_id: format!("studio.review:{}", self.reviewer_id),
                payload: OpaquePayload::new(MESSAGE_FORMAT, 1, content.clone())?,
                context: vec![ContextContent::Text {
                    text: content.into(),
                }],
            },
        })
    }
}

impl ReviewDeliveryFact {
    pub(crate) fn extension_id(&self) -> String {
        format!("{EXTENSION_PREFIX}{}", self.message.id)
    }
    pub(crate) fn encode(&self) -> Result<OpaquePayload> {
        Ok(OpaquePayload::new(
            FACT_FORMAT,
            1,
            serde_json::to_string(self)?,
        )?)
    }
    pub(crate) fn decode(payload: &OpaquePayload) -> Result<Self> {
        ensure!(
            payload.format() == FACT_FORMAT && payload.version() == 1,
            "unsupported review delivery fact"
        );
        let fact: Self = serde_json::from_str(payload.content())?;
        ensure!(
            fact.message.payload.format() == MESSAGE_FORMAT && fact.message.payload.version() == 1,
            "unsupported review delivery exception"
        );
        let exception: ReviewDeliveryException =
            serde_json::from_str(fact.message.payload.content())?;
        ensure!(
            exception.message_id() == fact.message.id
                && exception.terminal_sequence == fact.terminal_sequence
                && exception.terminal_sequence > 0
                && !exception.reviewer_id.is_empty()
                && !exception.turn_id.is_empty()
                && !exception.target_agent_id.is_empty()
                && exception.feedback_message_id
                    == super::agent_review::review_message_id(
                        &exception.reviewer_id,
                        &exception.turn_id,
                        exception.terminal_sequence
                    )
                && fact.message.kind == AgentMessageKind::Report
                && fact.message.source_id == format!("studio.review:{}", exception.reviewer_id),
            "review delivery fact identity mismatch"
        );
        let reason = match &exception.outcome {
            DeliveryExceptionOutcome::Rejected { reason }
            | DeliveryExceptionOutcome::Unconfirmed { reason } => reason,
        };
        let sources = match reason {
            DeliveryExceptionReason::AdmissionRejected(source)
            | DeliveryExceptionReason::StorageUnavailable(source)
            | DeliveryExceptionReason::SendUnconfirmed(source) => Some(source),
            DeliveryExceptionReason::WorkspaceCheckRejected(failure) => Some(&failure.source),
            DeliveryExceptionReason::RecoveryRequiresScheduling
            | DeliveryExceptionReason::MissingFrozenBaseline
            | DeliveryExceptionReason::TargetChanged
            | DeliveryExceptionReason::TargetUnavailable
            | DeliveryExceptionReason::IdentityConflict
            | DeliveryExceptionReason::IdentityUnverifiable => None,
        };
        ensure!(
            sources.is_none_or(|sources| sources.len() <= 8
                && sources.iter().all(|source| source.chars().count() <= 512)),
            "review exception diagnostics exceed their budget"
        );
        ensure!(
            fact.message.context
                == vec![ContextContent::Text {
                    text: fact.message.payload.content().to_owned().into()
                }],
            "review delivery context differs from its saved payload"
        );
        Ok(fact)
    }
}

fn bounded_sources(error: &(dyn std::error::Error + 'static)) -> Vec<String> {
    let mut source = Some(error);
    let mut chain = Vec::new();
    while let Some(error) = source {
        chain.push(error.to_string().chars().take(512).collect());
        if chain.len() == 8 {
            break;
        }
        source = error.source();
    }
    chain
}

impl From<&ReviewForwardReason> for DeliveryExceptionReason {
    fn from(reason: &ReviewForwardReason) -> Self {
        match reason {
            ReviewForwardReason::RecoveryRequiresScheduling => Self::RecoveryRequiresScheduling,
            ReviewForwardReason::MissingFrozenBaseline => Self::MissingFrozenBaseline,
            ReviewForwardReason::TargetChanged => Self::TargetChanged,
            ReviewForwardReason::TargetUnavailable => Self::TargetUnavailable,
            ReviewForwardReason::AdmissionRejected(error) => {
                Self::AdmissionRejected(bounded_sources(error.as_ref()))
            }
            ReviewForwardReason::IdentityConflict => Self::IdentityConflict,
            ReviewForwardReason::IdentityUnverifiable => Self::IdentityUnverifiable,
            ReviewForwardReason::StorageUnavailable(error) => {
                Self::StorageUnavailable(bounded_sources(error.as_ref()))
            }
            ReviewForwardReason::SendUnconfirmed(error) => {
                Self::SendUnconfirmed(bounded_sources(error.as_ref()))
            }
            ReviewForwardReason::WorkspaceCheckRejected(error) => {
                Self::WorkspaceCheckRejected(WorkspaceFailure {
                    certainty: if error.is_unconfirmed() {
                        WorkspaceFailureCertainty::Unconfirmed
                    } else {
                        WorkspaceFailureCertainty::Invalid
                    },
                    source: bounded_sources(error.as_ref()),
                })
            }
        }
    }
}
