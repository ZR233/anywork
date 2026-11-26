//! Product Plan adapters and wire projections backed by `pl-tool-plan`.

use serde::{Deserialize, Serialize};

pub(crate) use pl_tool_plan::PlanActor;
pub use pl_tool_plan::{Plan, PlanDocument, PlanRecord, PlanSnapshot, PlanState};

use pl_tool_plan::{PLAN_TRANSITION_TOOL, PlanOperationReceipt, PlanTransitionRecord};

pub const TOOL_PLAN_TRANSITION: &str = PLAN_TRANSITION_TOOL;
/// Retained only for decoding historical timeline items/events created before unification.
pub const TOOL_PLAN_SUBMIT: &str = "plan_submit";

/// OpenAPI / Studio protocol alias for [`PlanState`].
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum AgentSessionPlanPhase {
    #[default]
    Drafting,
    AwaitingConfirmation,
    RevisionRequested,
    Approved,
}

impl From<PlanState> for AgentSessionPlanPhase {
    fn from(value: PlanState) -> Self {
        match value {
            PlanState::Drafting => Self::Drafting,
            PlanState::AwaitingConfirmation => Self::AwaitingConfirmation,
            PlanState::RevisionRequested => Self::RevisionRequested,
            PlanState::Approved => Self::Approved,
        }
    }
}

impl From<AgentSessionPlanPhase> for PlanState {
    fn from(value: AgentSessionPlanPhase) -> Self {
        match value {
            AgentSessionPlanPhase::Drafting => Self::Drafting,
            AgentSessionPlanPhase::AwaitingConfirmation => Self::AwaitingConfirmation,
            AgentSessionPlanPhase::RevisionRequested => Self::RevisionRequested,
            AgentSessionPlanPhase::Approved => Self::Approved,
        }
    }
}

/// Product Plan Markdown document projection matching GUI runtime expectations.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentSessionPlanDocument {
    pub version: u64,
    pub markdown: String,
    pub content_hash: String,
}

impl From<&PlanDocument> for AgentSessionPlanDocument {
    fn from(doc: &PlanDocument) -> Self {
        Self {
            version: doc.revision,
            markdown: doc.content.clone(),
            content_hash: doc.hash.clone(),
        }
    }
}

/// Legacy & current confirmation error result codes used by Studio Interaction resolution.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum AgentSessionPlanResultCode {
    InvalidState,
}

/// Canonical per-agent Plan hot state persisted inside `studio.plan` extension.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentSessionPlanState {
    pub plan: PlanRecord,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pending_interaction_id: Option<String>,
}

impl AgentSessionPlanState {
    #[must_use]
    pub fn from_plan(plan: Plan, pending_interaction_id: Option<String>) -> Self {
        Self {
            plan: plan.into_record(),
            pending_interaction_id,
        }
    }

    #[must_use]
    #[cfg(test)]
    pub fn with_document(
        state: PlanState,
        revision: u64,
        content: impl Into<String>,
        updated_at_ms: i64,
    ) -> Self {
        let content = content.into();
        let hash = pl_tool_plan::content_hash(content.as_bytes());
        Self {
            plan: PlanRecord {
                state,
                revision,
                document: Some(PlanDocument {
                    revision,
                    content,
                    hash,
                    updated_at_ms,
                }),
                updated_at_ms,
                ..Default::default()
            },
            pending_interaction_id: None,
        }
    }

    #[must_use]
    pub fn revision(&self) -> u64 {
        self.plan.revision
    }

    #[must_use]
    pub fn phase(&self) -> AgentSessionPlanPhase {
        self.plan.state.into()
    }
}

/// Plan confirmation Interaction typed binding stored in `InteractionScope`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentSessionPlanConfirmationPurpose {
    pub expected_revision: u64,
    pub operation_id: String,
    pub argument_hash: String,
    pub plan_hash: String,
}

/// Thread stream lightweight Plan projection exposed to GUI.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentSessionPlanRuntimeSnapshot {
    pub revision: u64,
    pub state: AgentSessionPlanPhase,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub document: Option<AgentSessionPlanDocument>,
    pub updated_at: i64,
}

impl From<&AgentSessionPlanState> for AgentSessionPlanRuntimeSnapshot {
    fn from(value: &AgentSessionPlanState) -> Self {
        Self {
            revision: value.plan.revision,
            state: value.plan.state.into(),
            document: value
                .plan
                .document
                .as_ref()
                .map(AgentSessionPlanDocument::from),
            updated_at: value.plan.updated_at_ms / 1000,
        }
    }
}

impl From<&PlanSnapshot> for AgentSessionPlanRuntimeSnapshot {
    fn from(value: &PlanSnapshot) -> Self {
        Self {
            revision: value.revision,
            state: value.state.into(),
            document: value.document.as_ref().map(AgentSessionPlanDocument::from),
            updated_at: value.updated_at_ms / 1000,
        }
    }
}

/// Pre-unification `studio.plan` JSON. Decoded only while migrating a version-1 payload.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct LegacyAgentSessionPlanState {
    #[serde(default)]
    pub revision: u64,
    #[serde(default)]
    pub state: AgentSessionPlanPhase,
    #[serde(default)]
    pub document: Option<AgentSessionPlanDocument>,
    #[serde(default)]
    pub pending_interaction_id: Option<String>,
    #[serde(default)]
    pub last_revision_feedback: Option<String>,
    #[serde(default)]
    pub history_tail: Vec<LegacyTransitionRecord>,
    #[serde(default)]
    pub archived_transition_count: u64,
    #[serde(default)]
    pub archived_transition_digest: String,
    #[serde(default)]
    pub operation_receipts: Vec<LegacyReceipt>,
    #[serde(default)]
    pub updated_at: i64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct LegacyTransitionRecord {
    pub revision: u64,
    pub source_state: AgentSessionPlanPhase,
    pub target_state: AgentSessionPlanPhase,
    pub operation_id: String,
    pub reason: String,
    pub transitioned_at: i64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct LegacyReceipt {
    pub operation_id: String,
    pub argument_hash: String,
    pub operation_revision: u64,
}

impl From<LegacyAgentSessionPlanState> for AgentSessionPlanState {
    fn from(legacy: LegacyAgentSessionPlanState) -> Self {
        let updated_at_ms = legacy.updated_at.saturating_mul(1000);
        let history = legacy
            .history_tail
            .into_iter()
            .map(|entry| PlanTransitionRecord {
                seq: entry.revision,
                idempotency_key: Some(entry.operation_id),
                from_state: entry.source_state.into(),
                to_state: entry.target_state.into(),
                forced: false,
                actor: PlanActor::Agent,
                reason: Some(entry.reason),
                feedback: None,
                document_hash: None,
                document_revision: None,
                timestamp_ms: entry.transitioned_at.saturating_mul(1000),
            })
            .collect::<Vec<_>>();
        let next_seq = history.last().map_or(legacy.revision, |item| item.seq);
        Self {
            plan: PlanRecord {
                state: legacy.state.into(),
                revision: legacy.revision,
                document: legacy.document.map(|doc| PlanDocument {
                    revision: doc.version,
                    content: doc.markdown,
                    hash: doc.content_hash,
                    updated_at_ms,
                }),
                last_revision_feedback: legacy.last_revision_feedback,
                history,
                archived_transition_count: legacy.archived_transition_count,
                archived_transition_digest: legacy.archived_transition_digest,
                receipts: legacy
                    .operation_receipts
                    .into_iter()
                    .map(|r| PlanOperationReceipt {
                        key: r.operation_id,
                        argument_hash: r.argument_hash,
                        resulting_revision: r.operation_revision,
                    })
                    .collect(),
                next_seq,
                updated_at_ms,
            },
            pending_interaction_id: legacy.pending_interaction_id,
        }
    }
}
