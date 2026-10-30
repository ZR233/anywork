//! Frozen review relationships and restricted host feedback; ordinary send permissions are unchanged.
pub(crate) use super::agent_evaluation::validate_idle;
use super::{StudioThreadAssembler, observation::DurableMessageIdentity};
use crate::studio::agent_close::terminal_report_id;
use anyhow::{Context, Result, ensure};
use pl_core::thread::ThreadSnapshot;
use pl_protocol::{
    AgentReviewBaseline, AgentReviewFeedback, AgentReviewTargetSnapshot,
    AgentWorkspaceAssignmentSnapshot,
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
    IdentityUnverifiable,
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
fn error_chain(error: &(dyn std::error::Error + 'static)) -> Vec<String> {
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

pub(crate) fn review_message_id(agent: &str, turn: &str, sequence: u64) -> String {
    format!(
        "studio.review.{}:{agent}:{}:{turn}:{sequence}",
        agent.len(),
        turn.len()
    )
}

impl StudioThreadAssembler {
    async fn adjudicate_review_message(
        &self,
        target: &str,
        message: &pl_core::thread::inbox::ThreadMessage,
    ) -> Result<super::observation::DeliveryDisposition, super::ThreadAssemblyError> {
        use super::observation::DeliveryDisposition;
        let disposition = self.adjudicate_message(target, message).await?;
        if disposition != DeliveryDisposition::New {
            return Ok(disposition);
        }
        if let Some(thread) = self.thread(target) {
            let snapshot = thread.snapshot();
            let resident = snapshot
                .inbox
                .iter()
                .find(|record| record.message.id == message.id)
                .map(|record| (record.sequence, record.message.digest()))
                .or_else(|| {
                    snapshot
                        .consumed_message_identities
                        .iter()
                        .find(|record| record.id == message.id)
                        .map(|record| (record.sequence, record.digest.clone()))
                });
            if let Some((sequence, digest)) = resident {
                return Ok(if digest == message.digest() {
                    DeliveryDisposition::Receipt(sequence)
                } else {
                    DeliveryDisposition::Conflict
                });
            }
        }
        Ok(DeliveryDisposition::New)
    }
    /// Restricted host send. The only recipient and parent come from the frozen review relationship.
    pub(crate) async fn forward_review(
        &self,
        request: ReviewFeedbackDelivery<'_>,
    ) -> ReviewForward {
        use super::observation::DeliveryDisposition;
        use pl_core::{
            context::{AgentMessageKind, ContextContent, OpaquePayload},
            thread::inbox::ThreadMessage,
        };
        let id = review_message_id(request.reviewer, request.turn_id, request.terminal_sequence);
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
        let delivery = ThreadMessage {
            kind: AgentMessageKind::Report,
            id: id.clone(),
            source_id: format!("studio.review:{}", request.reviewer),
            payload: OpaquePayload::text(request.body),
            context: vec![ContextContent::Text {
                text: request.body.to_owned().into(),
            }],
        };
        // Receipt adjudication precedes idle/version/availability checks, including cold activation.
        match self.adjudicate_review_message(target_id, &delivery).await {
            Ok(DeliveryDisposition::Receipt(sequence)) => {
                return ReviewForward::Accepted {
                    message_id: id,
                    sequence,
                };
            }
            Ok(DeliveryDisposition::Conflict) => {
                return reject(ReviewForwardReason::IdentityConflict);
            }
            Ok(DeliveryDisposition::Unverifiable) => {
                return unknown(ReviewForwardReason::IdentityUnverifiable);
            }
            Err(error) => {
                return unknown(ReviewForwardReason::StorageUnavailable(Arc::new(error)));
            }
            Ok(DeliveryDisposition::New) => {}
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
        let relationship = async {
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
                    && request.assignment.mode == pl_protocol::AgentWorkspaceMode::Review
                    && crate::studio::model_route::saved_profile(&reviewer_snapshot)?
                        .is_some_and(|(profile, _)| profile.workspace_mode
                            == pl_protocol::AgentWorkspaceMode::Review),
                "reviewer frozen authority is no longer valid"
            );
            let parent = reviewer
                .parent_thread_id
                .context("reviewer has no parent")?;
            let target = services.record(target_id).await?;
            ensure!(
                !target.archived
                    && target.parent_thread_id.as_deref() == Some(parent.as_str())
                    && target.root_thread_id == reviewer.root_thread_id
                    && target.workspace_id == reviewer.workspace_id,
                "review relationship is no longer valid"
            );
            self.ensure_agent_admission_open(&parent)?;
            Ok::<_, anyhow::Error>(parent)
        }
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
        let mut operation = self.agent_operation(target_id).await;
        if self.thread(target_id).is_none() {
            match self.adjudicate_review_message(target_id, &delivery).await {
                Ok(DeliveryDisposition::Receipt(sequence)) => {
                    return ReviewForward::Accepted {
                        message_id: id,
                        sequence,
                    };
                }
                Ok(DeliveryDisposition::Conflict) => {
                    return reject(ReviewForwardReason::IdentityConflict);
                }
                Ok(DeliveryDisposition::Unverifiable) => {
                    return unknown(ReviewForwardReason::IdentityUnverifiable);
                }
                Err(error) => {
                    return unknown(ReviewForwardReason::StorageUnavailable(Arc::new(error)));
                }
                Ok(DeliveryDisposition::New) => {}
            }
            let (snapshot, turn) = match self.review_target_state(target_id).await {
                Ok(state) => state,
                Err(error) => {
                    return reject(ReviewForwardReason::AdmissionRejected(Arc::new(
                        super::ThreadAssemblyError::Resource {
                            operation: "read frozen cold target",
                            source: error.into(),
                        },
                    )));
                }
            };
            if !turn.as_ref().is_some_and(|turn| {
                turn.state.is_terminal() && same_delivery(&baseline(&snapshot, turn), expected)
            }) {
                return reject(ReviewForwardReason::TargetChanged);
            }
            let workspace = match crate::studio::workspace_receipt::from_snapshot(&snapshot) {
                Ok(Some(workspace)) if same_workspace(&workspace, request.assignment) => workspace,
                _ => return reject(ReviewForwardReason::TargetChanged),
            };
            let proof = match services
                .factory
                .verify_local_review_resume(target_id, &workspace)
                .await
            {
                Ok(proof) => proof,
                Err(error) => {
                    return reject(ReviewForwardReason::WorkspaceCheckRejected(Arc::new(error)));
                }
            };
            // The existing activation worker consumes this very permit; it must not acquire it
            // again while its caller waits. Only verified local resources can enter this branch.
            if let Err(error) = services
                .activate_verified_review_child(self, &parent, target_id, proof, operation)
                .await
            {
                return reject(ReviewForwardReason::WorkspaceCheckRejected(Arc::new(
                    crate::studio::thread_factory::ReviewWorkspaceError::Assembly(error),
                )));
            }
            operation = self.agent_operation(target_id).await;
        }
        let _operation = operation;
        // Another incarnation's notification may have won while this sender waited for the gate.
        // Its original receipt wins before a busy/changed target can reject a replay.
        match self.adjudicate_review_message(target_id, &delivery).await {
            Ok(DeliveryDisposition::Receipt(sequence)) => {
                return ReviewForward::Accepted {
                    message_id: id,
                    sequence,
                };
            }
            Ok(DeliveryDisposition::Conflict) => {
                return reject(ReviewForwardReason::IdentityConflict);
            }
            Ok(DeliveryDisposition::Unverifiable) => {
                return unknown(ReviewForwardReason::IdentityUnverifiable);
            }
            Err(error) => {
                return unknown(ReviewForwardReason::StorageUnavailable(Arc::new(error)));
            }
            Ok(DeliveryDisposition::New) => {}
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
        let options =
            {
                let state = self.0.state();
                let Some(entry) = state.entries.get(target_id).filter(|entry| {
                    entry.ready && entry.parent_id.as_deref() == Some(parent.as_str())
                }) else {
                    return reject(ReviewForwardReason::TargetUnavailable);
                };
                entry.execution
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
        match target.send_message_and_continue(delivery, options).await {
            Ok(sequence) => ReviewForward::Accepted {
                message_id: id,
                sequence,
            },
            Err(error) => unknown(ReviewForwardReason::SendUnconfirmed(Arc::new(error))),
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
            record.parent_thread_id.as_deref() == Some(parent)
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
        let report_id = terminal_report_id(target, turn.revision);
        ensure!(
            matches!(
                self.durable_message_identity(parent, &report_id).await?,
                Some(DurableMessageIdentity::Proven { .. })
            ),
            "review target latest terminal report has not been durably delivered to its parent"
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
    ) -> Result<(ThreadSnapshot, Option<pl_protocol::Turn>)> {
        let services = self
            .0
            .state()
            .agent_services
            .clone()
            .context("review services unavailable")?;
        let history = services.store.history(target).await?;
        services
            .store
            .ensure_agent_execution_allowed(target)
            .await?;
        services
            .recovery
            .ensure_thread_read_access(&services.record(target).await?)?;
        let (snapshot, turn) = if let Some(thread) = self.thread(target) {
            self.ensure_agent_admission_open(target)?;
            let before = thread.snapshot();
            validate_idle(&before)?;
            thread.flush().await?;
            let after = thread.snapshot();
            ensure!(
                after.commit_sequence == before.commit_sequence,
                "review target changed during history barrier"
            );
            let turn = history.latest_turn_at(after.commit_sequence).await?;
            let current = thread.snapshot();
            ensure!(
                current.commit_sequence == after.commit_sequence,
                "review target changed during history read"
            );
            (current, turn)
        } else {
            let (checkpoint, turn) = history
                .read_only_checkpoint_with_latest_turn()
                .await?
                .context(
                    "review target canonical checkpoint is missing; explicit recovery is required",
                )?;
            ensure!(
                checkpoint.history_fence == checkpoint.state.commit_sequence,
                "review target checkpoint is not durable"
            );
            (checkpoint.state, turn)
        };
        validate_idle(&snapshot)?;
        ensure!(
            !crate::studio::agent_close::is_explicitly_closed(&snapshot)?,
            "review target is explicitly closed"
        );
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
            || record.parent_thread_id.as_deref() != Some(parent)
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

fn baseline(snapshot: &ThreadSnapshot, turn: &pl_protocol::Turn) -> AgentReviewBaseline {
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
