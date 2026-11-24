use crate::types::{
    DEFAULT_HISTORY_LIMIT, MAX_FEEDBACK_BYTES, MAX_HISTORY_RECORDS, MAX_PLAN_BYTES,
    MAX_REASON_BYTES, MAX_RECEIPT_RECORDS, PlanDocument, PlanErrorCode, PlanHistoryResponse,
    PlanNextResponse, PlanOperationReceipt, PlanRecord, PlanSnapshot, PlanState,
    PlanTransitionCommand, PlanTransitionError, PlanTransitionOutcome, PlanTransitionRecord,
    PlanTransitionRule, content_hash,
};
use std::fmt::Write as _;
use thiserror::Error;

/// Corrupted or invariant-violating persisted Plan state.
#[derive(Debug, Clone, PartialEq, Eq, Error)]
#[error("invalid Plan state: {0}")]
pub struct PlanValidationError(String);

/// Standalone per-agent Plan object encapsulating the complete 4-state Plan state machine.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Plan {
    record: PlanRecord,
}

impl Plan {
    /// Creates a new Plan object starting in `Drafting` at revision 0.
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// Restores a Plan object from persisted state and validates all invariants.
    ///
    /// # Errors
    /// Returns [`PlanValidationError`] if content hash mismatches, sizes exceed limits,
    /// or `AwaitingConfirmation` is entered without a Plan document.
    pub fn from_record(record: PlanRecord) -> Result<Self, PlanValidationError> {
        validate_record(&record)?;
        Ok(Self { record })
    }

    #[must_use]
    pub fn record(&self) -> &PlanRecord {
        &self.record
    }

    #[must_use]
    pub fn into_record(self) -> PlanRecord {
        self.record
    }

    #[must_use]
    pub fn state(&self) -> PlanState {
        self.record.state
    }

    #[must_use]
    pub fn revision(&self) -> u64 {
        self.record.revision
    }

    #[must_use]
    pub fn document(&self) -> Option<&PlanDocument> {
        self.record.document.as_ref()
    }

    #[must_use]
    pub fn allowed_transitions(&self) -> Vec<PlanTransitionRule> {
        allowed_transitions_for(self.record.state)
    }

    #[must_use]
    pub fn snapshot(&self) -> PlanSnapshot {
        PlanSnapshot {
            state: self.record.state,
            revision: self.record.revision,
            document: self.record.document.clone(),
            last_revision_feedback: self.record.last_revision_feedback.clone(),
            allowed_transitions: self.allowed_transitions(),
            all_states: PlanState::ALL.to_vec(),
            updated_at_ms: self.record.updated_at_ms,
        }
    }

    #[must_use]
    pub fn next(&self) -> PlanNextResponse {
        PlanNextResponse {
            revision: self.record.revision,
            state: self.record.state,
            allowed_transitions: self.allowed_transitions(),
            all_states: PlanState::ALL.to_vec(),
        }
    }

    #[must_use]
    pub fn history(&self, limit: Option<usize>) -> PlanHistoryResponse {
        let count = limit.unwrap_or(DEFAULT_HISTORY_LIMIT);
        let history = if count == 0 || self.record.history.is_empty() {
            Vec::new()
        } else {
            let start = self.record.history.len().saturating_sub(count);
            self.record.history[start..].to_vec()
        };
        PlanHistoryResponse {
            revision: self.record.revision,
            state: self.record.state,
            history,
            archived_transition_count: self.record.archived_transition_count,
            archived_transition_digest: self.record.archived_transition_digest.clone(),
        }
    }

    /// Executes a Plan state transition.
    ///
    /// When `command.force` is `false`, `command.target_state` must be one of the outgoing
    /// edges in `allowed_transitions_for(self.state())`. Otherwise a rich diagnostic error
    /// enumerating valid transitions and all valid states is returned without mutating state.
    /// When `command.force` is `true`, transitions can jump to any `PlanState` directly
    /// (while still preserving CAS, size limits, and document presence for `AwaitingConfirmation`).
    pub fn transition(&mut self, command: PlanTransitionCommand) -> PlanTransitionOutcome {
        let arg_hash = command
            .argument_hash
            .clone()
            .unwrap_or_else(|| default_command_hash(&command));

        if let Some(key) = command
            .idempotency_key
            .as_deref()
            .map(str::trim)
            .filter(|k| !k.is_empty())
            && let Some(receipt) = self.record.receipts.iter().find(|r| r.key == key)
        {
            if receipt.argument_hash == arg_hash {
                return PlanTransitionOutcome {
                    accepted: true,
                    forced: false,
                    replayed: true,
                    awaiting_confirmation: self.record.state == PlanState::AwaitingConfirmation,
                    record: None,
                    snapshot: self.snapshot(),
                    error: None,
                };
            }
            return self.rejected(
                command.target_state,
                PlanErrorCode::IdempotencyConflict,
                format!(
                    "Idempotency key `{key}` was already used with different plan_transition arguments."
                ),
                "Retry with a fresh idempotencyKey or omit idempotencyKey for a new transition.",
            );
        }

        if let Some(expected) = command.expected_revision
            && expected != self.record.revision
        {
            return self.rejected(
                command.target_state,
                PlanErrorCode::StaleRevision,
                format!(
                    "Plan revision conflict: expected revision {expected}, but current revision is {} in state `{}`.",
                    self.record.revision, self.record.state
                ),
                "Call plan_current to read the latest revision and state, then retry with that expectedRevision.",
            );
        }

        if let Some(reason) = command.reason.as_deref()
            && reason.len() > MAX_REASON_BYTES
        {
            return self.rejected(
                command.target_state,
                PlanErrorCode::ReasonTooLarge,
                format!("Transition reason exceeds maximum size of {MAX_REASON_BYTES} bytes."),
                "Provide a concise transition reason within 2048 bytes.",
            );
        }

        let feedback_trimmed = command
            .feedback
            .as_deref()
            .map(str::trim)
            .filter(|text| !text.is_empty())
            .map(str::to_string);
        if let Some(feedback) = &feedback_trimmed
            && feedback.len() > MAX_FEEDBACK_BYTES
        {
            return self.rejected(
                command.target_state,
                PlanErrorCode::FeedbackTooLarge,
                format!("Revision feedback exceeds maximum size of {MAX_FEEDBACK_BYTES} bytes."),
                "Shorten feedback to at most 8192 bytes.",
            );
        }

        let content_trimmed = command
            .content
            .as_deref()
            .map(str::trim)
            .filter(|text| !text.is_empty())
            .map(str::to_string);
        if let Some(content) = &content_trimmed
            && content.len() > MAX_PLAN_BYTES
        {
            return self.rejected(
                command.target_state,
                PlanErrorCode::PlanTooLarge,
                format!("Plan Markdown content exceeds maximum size of {MAX_PLAN_BYTES} bytes."),
                "Keep the Plan Markdown within 65536 bytes.",
            );
        }
        if command
            .content
            .as_deref()
            .is_some_and(|raw| raw.trim().is_empty())
        {
            return self.rejected(
                command.target_state,
                PlanErrorCode::MissingPlanContent,
                "Provided Plan `content` is empty or whitespace-only.",
                "Omit `content` to keep the existing document, or provide non-empty Markdown plan content.",
            );
        }

        let current_state = self.record.state;
        let allowed = allowed_transitions_for(current_state);
        let rule = allowed
            .iter()
            .find(|candidate| candidate.target_state == command.target_state);

        if !command.force && rule.is_none() {
            let allowed_summary = format_allowed_transitions(&allowed);
            let all_states_summary = PlanState::ALL
                .iter()
                .map(|s| s.as_str())
                .collect::<Vec<_>>()
                .join(", ");
            let message = format!(
                "Cannot transition Plan from `{}` to `{}` (force=false). Allowed transitions from `{}`: {allowed_summary}. Valid Plan states: [{all_states_summary}]. Pass force=true only if an out-of-path override is intentionally needed.",
                current_state, command.target_state, current_state
            );
            let recovery = if allowed.is_empty() {
                "Inspect plan_next or use force=true to jump explicitly to any valid state."
                    .to_string()
            } else {
                let valid_targets = allowed
                    .iter()
                    .map(|r| r.target_state.as_str())
                    .collect::<Vec<_>>()
                    .join(", ");
                format!(
                    "Transition to one of the allowed states [{valid_targets}], or pass force=true if an out-of-path override is intentionally needed."
                )
            };
            return self.rejected(
                command.target_state,
                PlanErrorCode::TransitionNotAllowed,
                message,
                recovery,
            );
        }

        let reason_trimmed = command
            .reason
            .as_deref()
            .map(str::trim)
            .filter(|text| !text.is_empty())
            .map(str::to_string);

        if !command.force
            && command.target_state == PlanState::RevisionRequested
            && feedback_trimmed.is_none()
            && reason_trimmed.is_none()
        {
            return self.rejected(
                command.target_state,
                PlanErrorCode::MissingFeedback,
                "Transitioning to `revisionRequested` requires non-empty `feedback` or `reason`.",
                "Provide `feedback` explaining what needs to change in the Plan.",
            );
        }

        if command.target_state == PlanState::AwaitingConfirmation
            && content_trimmed.is_none()
            && self.record.document.is_none()
        {
            return self.rejected(
                command.target_state,
                PlanErrorCode::MissingPlanContent,
                "Cannot enter `awaitingConfirmation` without a Plan document.",
                "Supply non-empty Markdown in `content` when transitioning to `awaitingConfirmation`.",
            );
        }

        let next_revision = self.record.revision.saturating_add(1);
        let seq = self.record.next_seq.saturating_add(1);

        if let Some(content) = content_trimmed {
            let doc_revision = self
                .record
                .document
                .as_ref()
                .map_or(1, |doc| doc.revision.saturating_add(1));
            let hash = content_hash(content.as_bytes());
            self.record.document = Some(PlanDocument {
                revision: doc_revision,
                content,
                hash,
                updated_at_ms: command.timestamp_ms,
            });
        }

        match command.target_state {
            PlanState::AwaitingConfirmation => {
                self.record.last_revision_feedback = None;
            }
            PlanState::RevisionRequested => {
                self.record.last_revision_feedback =
                    feedback_trimmed.clone().or_else(|| reason_trimmed.clone());
            }
            PlanState::Drafting => {
                if feedback_trimmed.is_some() {
                    self.record.last_revision_feedback = feedback_trimmed.clone();
                }
            }
            PlanState::Approved => {
                self.record.last_revision_feedback = None;
            }
        }

        self.record.state = command.target_state;
        self.record.revision = next_revision;
        self.record.next_seq = seq;
        self.record.updated_at_ms = command.timestamp_ms;

        let record = PlanTransitionRecord {
            seq,
            idempotency_key: command
                .idempotency_key
                .as_deref()
                .map(str::trim)
                .filter(|k| !k.is_empty())
                .map(str::to_string),
            from_state: current_state,
            to_state: command.target_state,
            forced: command.force,
            actor: command.actor,
            reason: reason_trimmed,
            feedback: feedback_trimmed,
            document_hash: self.record.document.as_ref().map(|d| d.hash.clone()),
            document_revision: self.record.document.as_ref().map(|d| d.revision),
            timestamp_ms: command.timestamp_ms,
        };
        self.push_history(record.clone());

        if let Some(key) = &record.idempotency_key {
            self.record.receipts.push(PlanOperationReceipt {
                key: key.clone(),
                argument_hash: arg_hash,
                resulting_revision: next_revision,
            });
            if self.record.receipts.len() > MAX_RECEIPT_RECORDS {
                let drain = self.record.receipts.len() - MAX_RECEIPT_RECORDS;
                self.record.receipts.drain(..drain);
            }
        }

        debug_assert!(validate_record(&self.record).is_ok());

        PlanTransitionOutcome {
            accepted: true,
            forced: command.force,
            replayed: false,
            awaiting_confirmation: self.record.state == PlanState::AwaitingConfirmation,
            record: Some(record),
            snapshot: self.snapshot(),
            error: None,
        }
    }

    fn push_history(&mut self, entry: PlanTransitionRecord) {
        self.record.history.push(entry);
        while self.record.history.len() > MAX_HISTORY_RECORDS {
            let archived = self.record.history.remove(0);
            let encoded = serde_json::to_vec(&archived).unwrap_or_default();
            let mut input = self.record.archived_transition_digest.as_bytes().to_vec();
            input.extend(encoded);
            self.record.archived_transition_digest = content_hash(&input);
            self.record.archived_transition_count =
                self.record.archived_transition_count.saturating_add(1);
        }
    }

    fn rejected(
        &self,
        attempted: PlanState,
        code: PlanErrorCode,
        message: impl Into<String>,
        recovery_action: impl Into<String>,
    ) -> PlanTransitionOutcome {
        let message = message.into();
        let snapshot = self.snapshot();
        PlanTransitionOutcome {
            accepted: false,
            forced: false,
            replayed: false,
            awaiting_confirmation: self.record.state == PlanState::AwaitingConfirmation,
            record: None,
            snapshot: snapshot.clone(),
            error: Some(PlanTransitionError {
                code,
                message,
                current_state: self.record.state,
                current_revision: self.record.revision,
                attempted_target_state: attempted,
                allowed_transitions: snapshot.allowed_transitions,
                all_states: snapshot.all_states,
                recovery_action: recovery_action.into(),
            }),
        }
    }
}

/// Returns the fixed normal transitions permitted from `state` when `force=false`.
#[must_use]
pub fn allowed_transitions_for(state: PlanState) -> Vec<PlanTransitionRule> {
    match state {
        PlanState::Drafting => vec![PlanTransitionRule {
            target_state: PlanState::AwaitingConfirmation,
            condition: "Submit a complete Markdown Plan in `content` for confirmation.".to_string(),
            requires_content: true,
            requires_feedback: false,
            requires_confirmation: true,
        }],
        PlanState::AwaitingConfirmation => vec![
            PlanTransitionRule {
                target_state: PlanState::Approved,
                condition: "User or reviewer approved the current Plan.".to_string(),
                requires_content: false,
                requires_feedback: false,
                requires_confirmation: false,
            },
            PlanTransitionRule {
                target_state: PlanState::RevisionRequested,
                condition: "Reviewer requested revisions with `feedback`.".to_string(),
                requires_content: false,
                requires_feedback: true,
                requires_confirmation: false,
            },
            PlanTransitionRule {
                target_state: PlanState::Drafting,
                condition: "Withdraw submitted Plan back into drafting before confirmation."
                    .to_string(),
                requires_content: false,
                requires_feedback: false,
                requires_confirmation: false,
            },
        ],
        PlanState::RevisionRequested => vec![
            PlanTransitionRule {
                target_state: PlanState::AwaitingConfirmation,
                condition: "Submit the revised Markdown Plan in `content` for confirmation."
                    .to_string(),
                requires_content: true,
                requires_feedback: false,
                requires_confirmation: true,
            },
            PlanTransitionRule {
                target_state: PlanState::Drafting,
                condition: "Return to `drafting` to rework the Plan.".to_string(),
                requires_content: false,
                requires_feedback: false,
                requires_confirmation: false,
            },
        ],
        PlanState::Approved => vec![PlanTransitionRule {
            target_state: PlanState::Drafting,
            condition: "Start drafting a new Plan revision due to updated requirements."
                .to_string(),
            requires_content: false,
            requires_feedback: false,
            requires_confirmation: false,
        }],
    }
}

fn validate_record(record: &PlanRecord) -> Result<(), PlanValidationError> {
    if record.state == PlanState::AwaitingConfirmation && record.document.is_none() {
        return Err(PlanValidationError(
            "awaitingConfirmation state requires a Plan document".to_string(),
        ));
    }
    if let Some(document) = &record.document {
        if document.content.trim().is_empty() {
            return Err(PlanValidationError(
                "Plan document content must not be empty".to_string(),
            ));
        }
        if document.content.len() > MAX_PLAN_BYTES {
            return Err(PlanValidationError(format!(
                "Plan document exceeds {MAX_PLAN_BYTES} bytes"
            )));
        }
        let expected_hash = content_hash(document.content.as_bytes());
        if expected_hash != document.hash {
            return Err(PlanValidationError(
                "Plan document hash does not match its content".to_string(),
            ));
        }
    }
    if record
        .last_revision_feedback
        .as_ref()
        .is_some_and(|fb| fb.len() > MAX_FEEDBACK_BYTES)
    {
        return Err(PlanValidationError(
            "last_revision_feedback exceeds size limit".to_string(),
        ));
    }
    if record.history.len() > MAX_HISTORY_RECORDS {
        return Err(PlanValidationError(
            "Plan history exceeds bounded tail".to_string(),
        ));
    }
    if record.receipts.len() > MAX_RECEIPT_RECORDS {
        return Err(PlanValidationError(
            "Plan receipts exceed bounded tail".to_string(),
        ));
    }
    Ok(())
}

fn format_allowed_transitions(rules: &[PlanTransitionRule]) -> String {
    if rules.is_empty() {
        return "none".to_string();
    }
    let mut out = String::from("[");
    for (idx, rule) in rules.iter().enumerate() {
        if idx > 0 {
            out.push_str(", ");
        }
        let _ = write!(out, "{} ({})", rule.target_state, rule.condition);
    }
    out.push(']');
    out
}

fn default_command_hash(command: &PlanTransitionCommand) -> String {
    let summary = serde_json::json!({
        "targetState": command.target_state,
        "content": command.content,
        "feedback": command.feedback,
        "reason": command.reason,
        "force": command.force,
        "expectedRevision": command.expected_revision,
    });
    content_hash(summary.to_string().as_bytes())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::PlanActor;

    fn cmd(target: PlanState) -> PlanTransitionCommand {
        PlanTransitionCommand {
            target_state: target,
            content: None,
            feedback: None,
            reason: None,
            force: false,
            expected_revision: None,
            idempotency_key: None,
            argument_hash: None,
            actor: PlanActor::Agent,
            timestamp_ms: 1000,
        }
    }

    #[test]
    fn normal_lifecycle_transitions_and_revision_loop() {
        let mut plan = Plan::new();
        assert_eq!(plan.state(), PlanState::Drafting);
        assert_eq!(plan.revision(), 0);

        let mut submit = cmd(PlanState::AwaitingConfirmation);
        submit.content = Some("# Initial Plan\n- step 1".into());
        let out = plan.transition(submit);
        assert!(out.accepted);
        assert!(!out.forced);
        assert!(out.awaiting_confirmation);
        assert_eq!(out.snapshot.state, PlanState::AwaitingConfirmation);
        assert_eq!(out.snapshot.revision, 1);

        let mut revise = cmd(PlanState::RevisionRequested);
        revise.actor = PlanActor::User;
        revise.feedback = Some("Add tests".into());
        let out = plan.transition(revise);
        assert!(out.accepted);
        assert_eq!(out.snapshot.state, PlanState::RevisionRequested);
        assert_eq!(
            out.snapshot.last_revision_feedback.as_deref(),
            Some("Add tests")
        );

        let mut resubmit = cmd(PlanState::AwaitingConfirmation);
        resubmit.content = Some("# Revised Plan\n- step 1\n- test".into());
        let out = plan.transition(resubmit);
        assert!(out.accepted);
        assert_eq!(out.snapshot.last_revision_feedback, None);

        let mut approve = cmd(PlanState::Approved);
        approve.actor = PlanActor::User;
        let out = plan.transition(approve);
        assert!(out.accepted);
        assert_eq!(out.snapshot.state, PlanState::Approved);
        assert_eq!(plan.history(None).history.len(), 4);
    }

    #[test]
    fn non_forced_disallowed_transition_returns_rich_error_hints() {
        let mut plan = Plan::new();
        let out = plan.transition(cmd(PlanState::Approved));
        assert!(!out.accepted);
        let err = out.error.expect("must return structured error");
        assert_eq!(err.code, PlanErrorCode::TransitionNotAllowed);
        assert_eq!(err.current_state, PlanState::Drafting);
        assert_eq!(err.attempted_target_state, PlanState::Approved);
        assert_eq!(err.allowed_transitions.len(), 1);
        assert_eq!(
            err.allowed_transitions[0].target_state,
            PlanState::AwaitingConfirmation
        );
        assert_eq!(err.all_states, PlanState::ALL);
        assert!(err.message.contains("drafting"));
        assert!(err.message.contains("awaitingConfirmation"));
        assert!(err.message.contains("force=true"));
        assert_eq!(plan.state(), PlanState::Drafting);
        assert_eq!(plan.revision(), 0);
    }

    #[test]
    fn force_transition_bypasses_graph_and_marks_forced_in_history() {
        let mut plan = Plan::new();
        let mut forced_approve = cmd(PlanState::Approved);
        forced_approve.force = true;
        forced_approve.content = Some("# Forced plan".into());
        forced_approve.reason = Some("Emergency hotfix".into());
        let out = plan.transition(forced_approve);
        assert!(out.accepted);
        assert!(out.forced);
        assert_eq!(out.snapshot.state, PlanState::Approved);
        assert_eq!(out.record.as_ref().map(|r| r.forced), Some(true));

        let mut forced_revise = cmd(PlanState::RevisionRequested);
        forced_revise.force = true;
        forced_revise.feedback = Some("Re-check constraint".into());
        let out = plan.transition(forced_revise);
        assert!(out.accepted);
        assert!(out.forced);
        assert_eq!(out.snapshot.state, PlanState::RevisionRequested);
    }

    #[test]
    fn awaiting_confirmation_requires_non_empty_content_even_when_forced() {
        let mut plan = Plan::new();
        let mut forced_wait = cmd(PlanState::AwaitingConfirmation);
        forced_wait.force = true;
        let out = plan.transition(forced_wait);
        assert!(!out.accepted);
        assert_eq!(out.error.unwrap().code, PlanErrorCode::MissingPlanContent);
        assert_eq!(plan.state(), PlanState::Drafting);
    }

    #[test]
    fn cas_and_idempotency_preserve_state() {
        let mut plan = Plan::new();
        let mut first = cmd(PlanState::AwaitingConfirmation);
        first.content = Some("Step A".into());
        first.expected_revision = Some(0);
        first.idempotency_key = Some("op-1".into());
        first.argument_hash = Some("hash-a".into());
        assert!(plan.transition(first.clone()).accepted);

        let replay = plan.transition(first);
        assert!(replay.accepted);
        assert!(replay.replayed);
        assert_eq!(plan.revision(), 1);

        let mut conflict = cmd(PlanState::Approved);
        conflict.idempotency_key = Some("op-1".into());
        conflict.argument_hash = Some("hash-b".into());
        let conflict_out = plan.transition(conflict);
        assert!(!conflict_out.accepted);
        assert_eq!(
            conflict_out.error.unwrap().code,
            PlanErrorCode::IdempotencyConflict
        );

        let mut stale = cmd(PlanState::Approved);
        stale.expected_revision = Some(0);
        let stale_out = plan.transition(stale);
        assert!(!stale_out.accepted);
        assert_eq!(stale_out.error.unwrap().code, PlanErrorCode::StaleRevision);
    }
}
