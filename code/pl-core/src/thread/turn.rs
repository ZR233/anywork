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
                .driver
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
        let mut context = self.state.context.clone();
        let mut deliveries = self.state.deliveries.to_vec();
        for call_id in &selected {
            let Some(call) = self.pending.get(call_id) else {
                return Err(ThreadError::MissingCall);
            };
            let content = vec![ContextContent::Text {
                text: Arc::from(
                    "Tool call was cancelled before execution. No tool side effects were started.",
                ),
            }];
            let id = super::background::unique_id(
                &format!("cancelled:{}:{call_id}", context.revision),
                context.records.iter().map(|record| record.id.as_str()),
            )?;
            current::pair_known_call_result(
                &mut context,
                ContextRecord {
                    id,
                    turn_id: Some(call.turn_id.clone()),
                    source: ContextSource::ToolResult {
                        call_id: call_id.clone(),
                        tool_id: call.call.tool_id.clone(),
                    },
                    content: content.clone(),
                    tool_data: Default::default(),
                    tool_calls: Vec::new(),
                },
            )
            .map_err(|error| ThreadError::CurrentResume(Arc::new(error)))?;
            deliveries.push(ToolDelivery {
                target: ToolDeliveryTarget::CallResult,
                call_id: call_id.clone(),
                tool_id: call.call.tool_id.clone(),
                output: crate::tool::ToolOutput::new(pl_agent_tool::ToolResult::new(
                    pl_agent_tool::ToolData::Absent,
                    content.clone(),
                )),
                delivered_context: content,
                outcome: ToolOutcome::Cancelled,
                cancellation_cause: None,
            });
        }
        for call_id in selected {
            self.pending.remove(&call_id);
        }
        self.state.context = context;
        self.state.deliveries = deliveries.into();
        Ok(())
    }
}

pub(super) fn failed_turn(error: &ThreadError) -> TurnState {
    TurnState::Failed {
        description: error.to_string(),
        model_failure: match error {
            ThreadError::Model(error) => Some(Box::new(error.failure_facts())),
            ThreadError::ModelRepair { primary, repair } => {
                let mut facts = primary.failure_facts();
                facts.repair = Some(crate::model::ModelRepairFailure::from_error(repair));
                Some(Box::new(facts))
            }
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
/// request shape has to change, not the authorization), a storage fault (explicit save recovery),
/// an interaction (its own resolution entry), a closed owner, a cancellation
/// and every validation or identity violation. Nothing here ever retries by itself: a point only makes an
/// explicit continuation possible.
fn recoverable_continuation(error: &ThreadError) -> bool {
    match error {
        ThreadError::ModelUnavailable => true,
        ThreadError::Model(error) | ThreadError::ModelRepair { primary: error, .. } => matches!(
            error.kind,
            crate::model::ModelFailureKind::Unavailable
                | crate::model::ModelFailureKind::ContextLimit
                | crate::model::ModelFailureKind::UnsupportedContent
        ),
        _ => false,
    }
}
