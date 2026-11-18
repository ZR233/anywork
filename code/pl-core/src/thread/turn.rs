//! One Turn's model/tool loop, executed entirely inside the Thread owner.
use super::*;

impl Owner {
    /// The continuation a Turn's terminal outcome leaves behind, if it leaves one.
    pub(super) fn turn_continuation_reason(
        &self,
        result: &Result<TurnCompletion, ThreadError>,
    ) -> Option<ContinuationReason> {
        if self.interrupt.is_deleting() {
            return None;
        }
        match result {
            Ok(completion) if completion.outcome == TurnOutcome::StepLimit => {
                Some(ContinuationReason::StepLimit)
            }
            // A close that had to cut live work leaves that same owed work behind, under its own
            // reason, so a restart offers an explicit continuation instead of silently dropping it.
            Err(ThreadError::Cancelled) if self.interrupt.is_closing() => {
                Some(ContinuationReason::HostShutdown)
            }
            // A cancellation that latched a real failure is that failure, exactly like the terminal
            // state records it; the run itself reports cancellation.
            Err(ThreadError::Cancelled) => self
                .policy
                .error()
                .filter(|error| recoverable_continuation(error))
                .map(|_| ContinuationReason::ExecutionFailed),
            Err(error) if recoverable_continuation(error) => {
                Some(ContinuationReason::ExecutionFailed)
            }
            Ok(_) | Err(_) => None,
        }
    }

    pub(super) fn cancel_pending_calls(
        &mut self,
        turn_id: Option<&str>,
    ) -> Result<(), ThreadError> {
        let selected = self
            .pending
            .iter()
            .filter(|(_, call)| turn_id.is_none_or(|turn| call.turn_id == turn))
            .map(|(id, _)| id.clone())
            .collect::<Vec<_>>();
        if selected.is_empty() {
            return Ok(());
        }
        let revision = self
            .state
            .context
            .revision
            .checked_add(1)
            .ok_or(ThreadError::RevisionExhausted)?;
        let mut records = self.state.context.records.to_vec();
        let mut deliveries = self.state.deliveries.to_vec();
        let mut identities = records
            .iter()
            .map(|record| record.id.clone())
            .collect::<std::collections::BTreeSet<_>>();
        for call_id in selected {
            let Some(call) = self.pending.remove(&call_id) else {
                return Err(ThreadError::MissingCall);
            };
            let content = vec![ContextContent::Text {
                text: Arc::from(
                    "Tool call was cancelled before execution. No tool side effects were started.",
                ),
            }];
            let mut suffix = 0_u64;
            let id = loop {
                let id = format!("cancelled:{revision}:{call_id}:{suffix}");
                if identities.insert(id.clone()) {
                    break id;
                }
                suffix += 1;
            };
            records.push(ContextRecord {
                id,
                turn_id: Some(call.turn_id),
                source: ContextSource::ToolResult {
                    call_id: call_id.clone(),
                    tool_id: call.call.tool_id.clone(),
                },
                content: content.clone(),
                tool_calls: Vec::new(),
            });
            deliveries.push(ToolDelivery {
                target: ToolDeliveryTarget::CallResult,
                call_id,
                tool_id: call.call.tool_id,
                output: crate::tool::ToolOutput::new(
                    OpaquePayload::text("cancelled before execution"),
                    content.clone(),
                ),
                delivered_context: content,
                outcome: ToolOutcome::Cancelled,
            });
        }
        self.state.context = ContextSnapshot {
            revision,
            records: records.into(),
        };
        self.state.deliveries = deliveries.into();
        Ok(())
    }
}

pub(super) fn failed_turn(error: &ThreadError) -> TurnState {
    TurnState::Failed {
        description: error.to_string(),
        model_failure: match error {
            ThreadError::Model(error) => Some(Box::new(error.failure_facts())),
            _ => None,
        },
    }
}

/// Whether a Turn failure leaves work a caller can recover by explicitly continuing.
///
/// Only a failure a later explicit request can actually change counts, and a Thread whose model binding
/// itself is unavailable. The model categories are:
///
/// - `Unavailable`: the provider is temporarily unavailable, so a retry or a new binding can succeed.
/// - `ContextLimit`: the context no longer fits. The Turn already had its one automatic compaction, so
///   continuing needs a host decision — a bigger window or a different binding — and without a point the
///   consumed request could never be run again once that decision is made.
/// - `UnsupportedContent`: this binding cannot carry the request content. A binding that can is a host
///   decision too, and the already consumed request is otherwise lost.
///
/// Everything else keeps its own state instead of pretending to be continuable: `InvalidResponse` (the
/// answer could not be used), `ImplementationPanicked` (an adapter defect), `IncompatibleContext` (the
/// request shape has to change, not the authorization), a storage fault (explicit save recovery), a
/// pending tool commit (retry), an interaction (its own resolution entry), a closed owner, a cancellation
/// and every validation or identity violation. Nothing here ever retries by itself: a point only makes an
/// explicit continuation possible.
fn recoverable_continuation(error: &ThreadError) -> bool {
    match error {
        ThreadError::ModelUnavailable => true,
        ThreadError::Model(error) => matches!(
            error.kind,
            crate::model::ModelFailureKind::Unavailable
                | crate::model::ModelFailureKind::ContextLimit
                | crate::model::ModelFailureKind::UnsupportedContent
        ),
        _ => false,
    }
}
