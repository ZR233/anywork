//! Frozen review relationships and restricted host feedback; ordinary send permissions are unchanged.
use super::SessionRuntime;
pub(crate) use super::agent_evaluation::validate_idle;
use crate::{
    AgentReviewBaseline, AgentReviewFeedback, AgentReviewTargetSnapshot,
    AgentWorkspaceAssignmentSnapshot,
};
use anyhow::{Context, Result, ensure};
use pl_core::{
    context::OpaquePayload,
    thread::{
        ThreadSnapshot,
        inbox::{ThreadMessage, message_receipt},
    },
};

/// First-send authority is provenance, never inferred from whether a notification wakes its parent.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ReviewDeliverySource {
    LiveTerminal,
    Reconciliation,
}

#[derive(Debug, Clone, serde::Serialize)]
#[serde(
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    tag = "state"
)]
pub(crate) enum ReviewForward {
    NotRequested,
    NotRequired,
    Accepted {
        message_id: String,
        sequence: u64,
    },
    Rejected {
        message_id: String,
        reason: ReviewForwardReason,
    },
    Unconfirmed {
        message_id: String,
        reason: ReviewForwardReason,
    },
}

#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase", tag = "kind", content = "detail")]
pub(crate) enum ReviewForwardReason {
    RecoveryRequiresScheduling,
    MissingFrozenBaseline,
    TargetChanged,
    TargetUnavailable,
    AdmissionRejected(#[serde(serialize_with = "serialize_error")] Arc<super::ThreadAssemblyError>),
    IdentityConflict,
    StorageUnavailable(
        #[serde(serialize_with = "serialize_error")] Arc<super::ThreadAssemblyError>,
    ),
    SendUnconfirmed(#[serde(serialize_with = "serialize_error")] Arc<pl_core::thread::ThreadError>),
    WorkspaceCheckRejected(
        #[serde(serialize_with = "serialize_workspace_error")]
        Arc<crate::studio::thread_factory::ReviewWorkspaceError>,
    ),
}

use std::sync::Arc;
pub(super) fn error_chain(error: &(dyn std::error::Error + 'static)) -> Vec<String> {
    let mut source = Some(error);
    let mut chain = Vec::new();
    while let Some(error) = source {
        chain.push(error.to_string().chars().take(512).collect::<String>());
        if chain.len() == 8 {
            break;
        }
        source = error.source();
    }
    chain
}

fn serialize_error<S: serde::Serializer, E: std::error::Error + 'static>(
    error: &Arc<E>,
    serializer: S,
) -> Result<S::Ok, S::Error> {
    serde::Serialize::serialize(&error_chain(error.as_ref()), serializer)
}

pub(crate) fn serialize_workspace_error<S: serde::Serializer>(
    error: &Arc<crate::studio::thread_factory::ReviewWorkspaceError>,
    serializer: S,
) -> Result<S::Ok, S::Error> {
    use serde::ser::SerializeStruct;
    let chain = error_chain(error.as_ref());
    let mut output = serializer.serialize_struct("WorkspaceFailure", 2)?;
    output.serialize_field(
        "certainty",
        if error.is_unconfirmed() {
            "unconfirmed"
        } else {
            "invalid"
        },
    )?;
    output.serialize_field("source", &chain)?;
    output.end()
}

pub(crate) struct ReviewFeedbackDelivery<'a> {
    pub reviewer: &'a str,
    pub turn_id: &'a str,
    pub terminal_sequence: u64,
    pub assignment: &'a AgentWorkspaceAssignmentSnapshot,
    /// Exact immutable body saved by the successful finish producer.
    pub body: &'a str,
    pub source: ReviewDeliverySource,
    /// Observer discontinuity permanently revokes first-send authority through this watermark.
    pub revocation: Option<&'a std::sync::atomic::AtomicU64>,
}

const REVIEW_FEEDBACK_SETTLEMENT_FORMAT: &str = "pl.studio.review-feedback-settlement";
const REVIEW_FEEDBACK_SETTLEMENT_PREFIX: &str = "studio.review-feedback-settlement:";
const REVIEW_FEEDBACK_RECEIPT_PREFIX: &str = "studio.review-feedback:";

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct ReviewFeedbackSettlement {
    decision_message_id: String,
    target_agent_id: String,
    sequence: u64,
    message: ThreadMessage,
}

impl ReviewFeedbackSettlement {
    pub(crate) fn new(
        decision_message_id: String,
        target_agent_id: String,
        sequence: u64,
        message: ThreadMessage,
    ) -> Result<Self> {
        ensure!(
            !decision_message_id.is_empty() && !target_agent_id.is_empty() && sequence > 0,
            "review feedback settlement has an invalid identity"
        );
        let settlement = Self {
            decision_message_id,
            target_agent_id,
            sequence,
            message,
        };
        settlement.validate()?;
        Ok(settlement)
    }

    pub(crate) fn decision_message_id(&self) -> &str {
        &self.decision_message_id
    }

    pub(crate) fn target_agent_id(&self) -> &str {
        &self.target_agent_id
    }

    pub(crate) fn sequence(&self) -> u64 {
        self.sequence
    }

    pub(crate) fn message(&self) -> &ThreadMessage {
        &self.message
    }

    pub(crate) fn extension_id(&self) -> String {
        format!("{REVIEW_FEEDBACK_SETTLEMENT_PREFIX}{}", self.message.id)
    }

    pub(crate) fn encode(&self) -> Result<OpaquePayload> {
        Ok(OpaquePayload::new(
            REVIEW_FEEDBACK_SETTLEMENT_FORMAT,
            1,
            serde_json::to_string(self)?,
        )?)
    }

    pub(crate) fn decode(extension_id: &str, payload: &OpaquePayload) -> Result<Self> {
        ensure!(
            payload.format() == REVIEW_FEEDBACK_SETTLEMENT_FORMAT && payload.version() == 1,
            "unsupported review feedback settlement format"
        );
        let settlement: Self = serde_json::from_str(payload.content())?;
        ensure!(
            extension_id == settlement.extension_id(),
            "review feedback settlement key mismatch"
        );
        settlement.validate()?;
        Ok(settlement)
    }

    pub(crate) fn saved_in(state: &ThreadSnapshot) -> Result<Vec<Self>> {
        state
            .extensions
            .iter()
            .filter(|(id, _)| id.starts_with(REVIEW_FEEDBACK_SETTLEMENT_PREFIX))
            .map(|(id, record)| Self::decode(id, &record.payload))
            .collect()
    }

    fn validate(&self) -> Result<()> {
        ensure!(
            !self.decision_message_id.is_empty()
                && !self.target_agent_id.is_empty()
                && self.message.kind == pl_core::context::AgentMessageKind::Report
                && !self.message.id.is_empty()
                && self.message.source_id.starts_with("studio.review:")
                && self.sequence > 0
                && self.message.context
                    == vec![pl_core::context::ContextContent::Text {
                        text: self.message.payload.content().to_owned().into()
                    }],
            "review feedback settlement message identity mismatch"
        );
        Ok(())
    }
}

pub(crate) fn review_message_id(agent: &str, turn: &str, sequence: u64) -> String {
    format!(
        "studio.review.{}:{agent}:{}:{turn}:{sequence}",
        agent.len(),
        turn.len()
    )
}

pub(crate) fn review_feedback_receipt_extension_id(message_id: &str) -> String {
    format!("{REVIEW_FEEDBACK_RECEIPT_PREFIX}{message_id}")
}

pub(crate) fn review_feedback_message(
    reviewer: &str,
    turn_id: &str,
    terminal_sequence: u64,
    body: &str,
) -> ThreadMessage {
    ThreadMessage {
        kind: pl_core::context::AgentMessageKind::Report,
        id: review_message_id(reviewer, turn_id, terminal_sequence),
        source_id: format!("studio.review:{reviewer}"),
        payload: pl_core::context::OpaquePayload::text(body),
        context: vec![pl_core::context::ContextContent::Text {
            text: body.to_owned().into(),
        }],
    }
}

impl ReviewForward {
    pub(crate) fn remains_pending_with_source_marker(&self) -> bool {
        matches!(
            self,
            Self::Unconfirmed {
                reason: ReviewForwardReason::SendUnconfirmed(_)
                    | ReviewForwardReason::StorageUnavailable(_),
                ..
            }
        )
    }
}

fn exact_receipt_disposition(
    state: &ThreadSnapshot,
    receipt_extension_id: &str,
    message: &ThreadMessage,
) -> Result<super::observation::DeliveryDisposition, super::ThreadAssemblyError> {
    use super::observation::DeliveryDisposition;
    match message_receipt(state, receipt_extension_id, message) {
        Ok(Some(receipt)) => Ok(DeliveryDisposition::Receipt(receipt.sequence)),
        Ok(None) => Ok(DeliveryDisposition::New),
        Err(pl_core::thread::ThreadError::InvalidIdentity) => Ok(DeliveryDisposition::Conflict),
        Err(error) => Err(error.into()),
    }
}

impl SessionRuntime {
    fn adjudicate_review_message(
        &self,
        target: &str,
        message: &ThreadMessage,
        receipt_extension_id: &str,
    ) -> Result<super::observation::DeliveryDisposition, super::ThreadAssemblyError> {
        use super::observation::DeliveryDisposition;
        let Some(thread) = self.observed_thread(target) else {
            return Ok(DeliveryDisposition::New);
        };
        let snapshot = thread.snapshot();
        match exact_receipt_disposition(&snapshot, receipt_extension_id, message)? {
            DeliveryDisposition::New => {}
            known => return Ok(known),
        }
        Ok(match self.adjudicate_message(target, message) {
            DeliveryDisposition::Receipt(_) => DeliveryDisposition::New,
            other => other,
        })
    }

    /// Restricted host send. The only recipient and parent come from the frozen review relationship.
    fn adjudicate_review_forward(
        &self,
        target_id: &str,
        delivery: &ThreadMessage,
        receipt_extension_id: &str,
        id: &str,
    ) -> Option<ReviewForward> {
        use super::observation::DeliveryDisposition;
        match self.adjudicate_review_message(target_id, delivery, receipt_extension_id) {
            Ok(DeliveryDisposition::Receipt(sequence)) => Some(ReviewForward::Accepted {
                message_id: id.to_owned(),
                sequence,
            }),
            Ok(DeliveryDisposition::Conflict) => Some(ReviewForward::Rejected {
                message_id: id.to_owned(),
                reason: ReviewForwardReason::IdentityConflict,
            }),
            Err(error) => Some(ReviewForward::Unconfirmed {
                message_id: id.to_owned(),
                reason: ReviewForwardReason::StorageUnavailable(Arc::new(error)),
            }),
            Ok(DeliveryDisposition::New) => None,
        }
    }

    async fn validate_review_relationship(
        &self,
        services: &super::agent_services::AgentServices,
        request: &ReviewFeedbackDelivery<'_>,
        target_id: &str,
    ) -> Result<String> {
        let reviewer = services.record(request.reviewer).await?;
        self.ensure_agent_admission_open(request.reviewer)?;
        let reviewer_thread = self
            .thread(request.reviewer)
            .context("reviewer is not resident")?;
        let reviewer_snapshot = reviewer_thread.snapshot();
        validate_idle(&reviewer_snapshot)?;
        ensure!(
            crate::studio::workspace_receipt::from_snapshot(&reviewer_snapshot)?.as_ref()
                == Some(request.assignment)
                && request.assignment.mode == crate::AgentWorkspaceMode::Review
                && crate::studio::model_route::saved_profile(&reviewer_snapshot)?.is_some_and(
                    |(profile, _)| profile.workspace_mode == crate::AgentWorkspaceMode::Review
                ),
            "reviewer frozen authority is no longer valid"
        );
        let parent = reviewer
            .parent_thread_id
            .context("reviewer has no parent")?;
        let target = services.record(target_id).await?;
        ensure!(
            !target.archived
                && services.direct_child(&parent, target_id)?
                && target.root_thread_id == reviewer.root_thread_id
                && target.workspace_id == reviewer.workspace_id,
            "review relationship is no longer valid"
        );
        self.ensure_agent_admission_open(&parent)?;
        Ok(parent)
    }

    pub(crate) async fn forward_review(
        &self,
        request: ReviewFeedbackDelivery<'_>,
    ) -> ReviewForward {
        let id = review_message_id(request.reviewer, request.turn_id, request.terminal_sequence);
        let receipt_extension_id = review_feedback_receipt_extension_id(&id);
        let reject = |reason| ReviewForward::Rejected {
            message_id: id.clone(),
            reason,
        };
        let unknown = |reason| ReviewForward::Unconfirmed {
            message_id: id.clone(),
            reason,
        };
        let Some(binding) = request.assignment.review_target.as_ref() else {
            return reject(ReviewForwardReason::MissingFrozenBaseline);
        };
        if binding.feedback != Some(AgentReviewFeedback::ToExecutor) {
            return ReviewForward::NotRequested;
        }
        let Some(expected) = binding.baseline.as_ref() else {
            return reject(ReviewForwardReason::MissingFrozenBaseline);
        };
        let target_id = &binding.agent_id;
        if target_id == request.reviewer {
            return reject(ReviewForwardReason::TargetUnavailable);
        }
        let delivery = review_feedback_message(
            request.reviewer,
            request.turn_id,
            request.terminal_sequence,
            request.body,
        );
        // Receipt adjudication precedes idle/version/availability checks, including cold activation.
        if let Some(outcome) =
            self.adjudicate_review_forward(target_id, &delivery, &receipt_extension_id, &id)
        {
            return outcome;
        }
        if request.source != ReviewDeliverySource::LiveTerminal
            || request.revocation.is_some_and(|fence| {
                fence.load(std::sync::atomic::Ordering::Acquire) >= request.terminal_sequence
            })
        {
            return unknown(ReviewForwardReason::RecoveryRequiresScheduling);
        }
        let Some(services) = self.0.state().agent_services.clone() else {
            return reject(ReviewForwardReason::TargetUnavailable);
        };
        let relationship = self
            .validate_review_relationship(&services, &request, target_id)
            .await;
        let parent = match relationship {
            Ok(parent) => parent,
            Err(error) => {
                return reject(ReviewForwardReason::AdmissionRejected(Arc::new(
                    super::ThreadAssemblyError::Resource {
                        operation: "validate frozen review relationship",
                        source: error.into(),
                    },
                )));
            }
        };
        let _operation = self.agent_operation(target_id).await;
        // Another incarnation's notification may have won while this sender waited for the gate.
        // Its original receipt wins before a busy/changed target can reject a replay.
        if let Some(outcome) =
            self.adjudicate_review_forward(target_id, &delivery, &receipt_extension_id, &id)
        {
            return outcome;
        }
        if self.ensure_agent_admission_open(target_id).is_err() {
            return reject(ReviewForwardReason::TargetUnavailable);
        }
        let (snapshot, turn) = match self.review_target_state(target_id).await {
            Ok(state) => state,
            Err(error) => {
                return reject(ReviewForwardReason::AdmissionRejected(Arc::new(
                    super::ThreadAssemblyError::Resource {
                        operation: "validate original reviewed delivery",
                        source: error.into(),
                    },
                )));
            }
        };
        let Some(turn) = turn else {
            return reject(ReviewForwardReason::TargetChanged);
        };
        let workspace = match crate::studio::workspace_receipt::from_snapshot(&snapshot) {
            Ok(Some(workspace)) => workspace,
            _ => return reject(ReviewForwardReason::TargetUnavailable),
        };
        if !turn.state.is_terminal()
            || !same_delivery(&baseline(&snapshot, &turn), expected)
            || !same_workspace(&workspace, request.assignment)
        {
            return reject(ReviewForwardReason::TargetChanged);
        }
        let Some(target) = self.thread(target_id) else {
            return reject(ReviewForwardReason::TargetUnavailable);
        };
        let options = {
            let state = self.0.state();
            let Some(entry) = state.members.entries.get(target_id).filter(|entry| {
                entry.native().is_ok_and(|native| {
                    native.ready
                        && super::EntryRegistry::membership_parent(&state.members.by_agent, entry)
                            == Some(parent.as_str())
                })
            }) else {
                return reject(ReviewForwardReason::TargetUnavailable);
            };
            let Ok(native) = entry.native() else {
                return reject(ReviewForwardReason::TargetUnavailable);
            };
            native.execution
        };
        // Prove the original capability before logical/model preparation. The restricted branch
        // never invokes ordinary Execute/Prepare resolvers or refreshes a missing tool binding.
        let workspace_check = match services
            .factory
            .verify_review_workspace(target_id, &workspace)
            .await
        {
            Ok(check) => check,
            Err(error) => {
                return reject(ReviewForwardReason::WorkspaceCheckRejected(Arc::new(error)));
            }
        };
        if let Err(error) = workspace_check.recheck() {
            return reject(ReviewForwardReason::WorkspaceCheckRejected(Arc::new(error)));
        }
        if let Err(error) = self
            .prepare_verified_review_admission(target_id, &target, &workspace_check)
            .await
        {
            return reject(ReviewForwardReason::AdmissionRejected(Arc::new(error)));
        }
        if let Err(error) = workspace_check.confirm().await {
            return reject(ReviewForwardReason::WorkspaceCheckRejected(Arc::new(error)));
        }
        let current = target.snapshot();
        let reviewer_idle = self
            .thread(request.reviewer)
            .is_some_and(|thread| validate_idle(&thread.snapshot()).is_ok());
        if self.ensure_agent_admission_open(&parent).is_err()
            || self.ensure_agent_admission_open(request.reviewer).is_err()
            || self.ensure_agent_admission_open(target_id).is_err()
            || !reviewer_idle
            || validate_idle(&current).is_err()
            || !same_delivery(&baseline(&current, &turn), expected)
        {
            return reject(ReviewForwardReason::TargetChanged);
        }
        if request.revocation.is_some_and(|fence| {
            fence.load(std::sync::atomic::Ordering::Acquire) >= request.terminal_sequence
        }) {
            return unknown(ReviewForwardReason::RecoveryRequiresScheduling);
        }
        match target
            .send_message_and_continue_with_receipt(delivery, options, receipt_extension_id.clone())
            .await
        {
            Ok(sequence) => {
                let flushed = async {
                    services
                        .store
                        .conversation_store(target_id)
                        .await?
                        .flush_current(target.runtime_epoch())
                        .await
                }
                .await;
                if let Err(error) = flushed {
                    return ReviewForward::Unconfirmed {
                        message_id: id,
                        reason: ReviewForwardReason::StorageUnavailable(Arc::new(
                            super::ThreadAssemblyError::Resource {
                                operation: "flush accepted review feedback",
                                source: error.into_boxed_dyn_error(),
                            },
                        )),
                    };
                }
                ReviewForward::Accepted {
                    message_id: id,
                    sequence,
                }
            }
            Err(error) => ReviewForward::Unconfirmed {
                message_id: id,
                reason: ReviewForwardReason::SendUnconfirmed(Arc::new(error)),
            },
        }
    }
    /// Caller holds root then target operation gates through publication of the review child.
    pub(super) async fn freeze_review_target(
        &self,
        parent: &str,
        target: &str,
        feedback: Option<AgentReviewFeedback>,
    ) -> Result<(
        AgentReviewTargetSnapshot,
        AgentWorkspaceAssignmentSnapshot,
        crate::studio::thread_factory::ReviewWorkspaceCheck,
    )> {
        let services = self
            .0
            .state()
            .agent_services
            .clone()
            .context("review services unavailable")?;
        let record = services.record(target).await?;
        let root = services.record(parent).await?;
        ensure!(
            services.direct_child(parent, target)?
                && record.root_thread_id == root.root_thread_id
                && record.workspace_id == root.workspace_id
                && !record.archived,
            "review target must be an available direct child in the same root and project"
        );
        let (snapshot, turn) = self.review_target_state(target).await?;
        let turn = turn.context("review target has no committed terminal delivery")?;
        ensure!(
            turn.state.is_terminal(),
            "review target latest Turn is not terminal"
        );
        let frozen_baseline = baseline(&snapshot, &turn);
        let workspace = crate::studio::workspace_receipt::from_snapshot(&snapshot)?
            .context("review target has no frozen workspace receipt")?;
        let workspace_check = services
            .factory
            .verify_review_workspace(target, &workspace)
            .await?;
        if let Some(thread) = self.thread(target) {
            let current = thread.snapshot();
            validate_idle(&current)?;
            ensure!(
                same_delivery(&baseline(&current, &turn), &frozen_baseline),
                "target changed during physical workspace verification"
            );
            self.ensure_agent_admission_open(target)?;
        }
        self.ensure_agent_admission_open(parent)?;
        workspace_check.recheck()?;
        Ok((
            AgentReviewTargetSnapshot {
                agent_id: target.into(),
                feedback,
                baseline: Some(frozen_baseline),
            },
            workspace,
            workspace_check,
        ))
    }

    async fn review_target_state(
        &self,
        target: &str,
    ) -> Result<(ThreadSnapshot, Option<crate::Turn>)> {
        self.ensure_agent_admission_open(target)?;
        let thread = self
            .thread(target)
            .context("review target has no current owner")?;
        let snapshot = thread.snapshot();
        validate_idle(&snapshot)?;
        ensure!(
            !crate::studio::agent_close::is_explicitly_closed(&snapshot)?,
            "review target is explicitly closed"
        );
        let turn = self
            .current_terminal_turn(target)
            .map(|turn| (*turn).clone());
        Ok((snapshot, turn))
    }

    /// Read-only version check under the target's operation gate. No activation or new input.
    pub(crate) async fn review_baseline_current(
        &self,
        parent: &str,
        assignment: &AgentWorkspaceAssignmentSnapshot,
    ) -> Result<bool> {
        let target = assignment
            .review_target
            .as_ref()
            .context("review target missing")?;
        let Some(expected) = target.baseline.as_ref() else {
            return Ok(false);
        };
        let _operation = self.agent_operation(&target.agent_id).await;
        let services = self
            .0
            .state()
            .agent_services
            .clone()
            .context("review services unavailable")?;
        let record = services.record(&target.agent_id).await?;
        let root = services.record(parent).await?;
        if record.archived
            || !services.direct_child(parent, &target.agent_id)?
            || record.root_thread_id != root.root_thread_id
            || record.workspace_id != root.workspace_id
        {
            return Ok(false);
        }
        let (snapshot, turn) = self.review_target_state(&target.agent_id).await?;
        let Some(turn) = turn else {
            return Ok(false);
        };
        let workspace = crate::studio::workspace_receipt::from_snapshot(&snapshot)?;
        let check = match workspace.as_ref() {
            Some(workspace) => {
                services
                    .factory
                    .verify_review_workspace(&target.agent_id, workspace)
                    .await?
            }
            None => return Ok(false),
        };
        check.recheck()?;
        self.ensure_agent_admission_open(parent)?;
        if let Some(thread) = self.thread(&target.agent_id) {
            let current = thread.snapshot();
            validate_idle(&current)?;
            if !same_delivery(&baseline(&current, &turn), expected) {
                return Ok(false);
            }
            self.ensure_agent_admission_open(&target.agent_id)?;
        }
        Ok(turn.state.is_terminal()
            && same_delivery(&baseline(&snapshot, &turn), expected)
            && workspace
                .as_ref()
                .is_some_and(|workspace| same_workspace(workspace, assignment)))
    }
}

fn same_delivery(current: &AgentReviewBaseline, expected: &AgentReviewBaseline) -> bool {
    // Runtime facts and tool/model refresh can advance the commit fence without admitting work.
    // All input, inbox, Turn, execution and continuation identities must nevertheless stay frozen.
    let mut current = current.clone();
    current.commit_sequence = expected.commit_sequence;
    current == *expected
}

fn baseline(snapshot: &ThreadSnapshot, turn: &crate::Turn) -> AgentReviewBaseline {
    AgentReviewBaseline {
        turn_id: turn.id.clone(),
        input_id: turn.input_id.clone(),
        terminal_sequence: turn.revision,
        commit_sequence: snapshot.commit_sequence,
        input_ordinal: snapshot.input_ordinal,
        message_sequence: snapshot.inbox_sequence,
        consumed_messages: snapshot.consumed_messages,
        wake_messages_through: snapshot.wake_messages_through,
        execution_sequence: snapshot.execution_sequence,
        continuation_id: snapshot.continuation.as_ref().map(|point| point.id.clone()),
    }
}

fn same_workspace(
    target: &AgentWorkspaceAssignmentSnapshot,
    review: &AgentWorkspaceAssignmentSnapshot,
) -> bool {
    target.project_root == review.project_root
        && target.root == review.root
        && target.worktree == review.worktree
}
