use crate::api::studio::bridge_runtime::active_bridge;
use crate::api::studio::convert::commands::command_receipt;
use crate::api::studio::convert::thread_stream::bridge_interaction;
use crate::api::studio::types::{
    BridgeContinuationOperationState, BridgeContinuationOperationView, BridgeContinueThreadReply,
    BridgeError, BridgeInteractionCommandReply, BridgeInteractionResolution, BridgeStopThreadReply,
    BridgeToolApprovalResolution,
};
use pl_protocol::{
    InteractionResolution, ToolApprovalResolution, ToolApprovalResolutionPayload, UserInputAnswer,
    UserInputResolution,
};
use std::collections::HashMap;
// ── Prompt / Interaction ──

pub async fn read_input_acceptance(
    thread_id: String,
    input_id: String,
) -> Result<Option<crate::api::studio::types::BridgeInputAcceptanceEvidence>, BridgeError> {
    use crate::api::studio::types::{
        BridgeInputAcceptanceEvidence, BridgePersistedInputDisposition,
    };
    use pl_protocol::studio::PersistedInputDisposition;
    let bridge = active_bridge().await?;
    Ok(bridge
        .studio
        .read_input_acceptance(thread_id, input_id)
        .await?
        .map(|evidence| BridgeInputAcceptanceEvidence {
            accepted_sequence: evidence.accepted_sequence,
            request_digest: evidence.request_digest,
            disposition: match evidence.disposition {
                PersistedInputDisposition::Consumed => BridgePersistedInputDisposition::Consumed,
                PersistedInputDisposition::Discarded => BridgePersistedInputDisposition::Discarded,
            },
        }))
}

pub async fn stop_thread(
    operation_id: String,
    thread_id: String,
    expected_execution_id: String,
) -> Result<BridgeStopThreadReply, BridgeError> {
    let bridge = active_bridge().await?;
    let response = bridge
        .studio
        .stop_thread(
            thread_id,
            pl_protocol::studio::StopThreadRequest {
                operation_id,
                expected_execution_id,
            },
        )
        .await?;
    Ok(BridgeStopThreadReply {
        thread_id: response.thread_id,
        execution_id: response.execution_id,
        stopped: response.stopped,
        receipt: command_receipt(response.receipt),
    })
}

pub async fn continue_thread(
    operation_id: String,
    thread_id: String,
    expected_continuation_id: String,
    expected_model_route_revision: u64,
) -> Result<BridgeContinueThreadReply, BridgeError> {
    let bridge = active_bridge().await?;
    let response = bridge
        .studio
        .continue_thread(
            thread_id,
            pl_protocol::studio::ContinueThreadRequest {
                operation_id,
                expected_continuation_id,
                expected_model_route_revision,
            },
        )
        .await?;
    Ok(BridgeContinueThreadReply {
        cursor: response.cursor,
        thread_id: response.thread_id,
        input_id: response.input_id,
        continuation_id: response.continuation_id,
        receipt: command_receipt(response.receipt),
    })
}

pub async fn read_continuation_operation(
    thread_id: String,
    operation_id: String,
) -> Result<BridgeContinuationOperationView, BridgeError> {
    let bridge = active_bridge().await?;
    let view = bridge
        .studio
        .read_continuation_operation(thread_id, operation_id)
        .await?;
    Ok(BridgeContinuationOperationView {
        accepted_sequence: view.accepted_sequence,
        state: match view.state {
            pl_protocol::studio::ContinuationOperationState::Pending => {
                BridgeContinuationOperationState::Pending
            }
            pl_protocol::studio::ContinuationOperationState::Consumed { turn_id } => {
                BridgeContinuationOperationState::Consumed { turn_id }
            }
            pl_protocol::studio::ContinuationOperationState::Discarded => {
                BridgeContinuationOperationState::Discarded
            }
        },
        durable: view.durable,
        thread_id: view.thread_id,
        operation_id: view.operation_id,
        input_id: view.input_id,
        continuation_id: view.continuation_id,
        receipt: command_receipt(view.receipt),
    })
}

pub async fn respond_interaction(
    operation_id: String,
    host_thread_id: String,
    expected_revision: u64,
    interaction_id: String,
    resolution: BridgeInteractionResolution,
) -> Result<BridgeInteractionCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    let resolution = interaction_resolution(resolution)?;
    let response = bridge
        .studio
        .resolve_interaction(
            operation_id,
            host_thread_id,
            expected_revision,
            interaction_id,
            resolution,
        )
        .await?;
    Ok(BridgeInteractionCommandReply {
        interaction: bridge_interaction(response.interaction)?,
        receipt: command_receipt(response.receipt),
    })
}

fn interaction_resolution(
    resolution: BridgeInteractionResolution,
) -> Result<InteractionResolution, BridgeError> {
    Ok(match resolution {
        BridgeInteractionResolution::UserInput { answers } => {
            let mut mapped = HashMap::with_capacity(answers.len());
            for answer in answers {
                if mapped
                    .insert(
                        answer.question_id.clone(),
                        UserInputAnswer {
                            answers: answer.answers,
                        },
                    )
                    .is_some()
                {
                    return Err(BridgeError::invalid_argument(format!(
                        "duplicate answer for question {}",
                        answer.question_id
                    )));
                }
            }
            InteractionResolution::UserInput(UserInputResolution { answers: mapped })
        }
        BridgeInteractionResolution::ToolApproval { decision, reason } => {
            InteractionResolution::ToolApproval(ToolApprovalResolutionPayload {
                decision: match decision {
                    BridgeToolApprovalResolution::Approved => ToolApprovalResolution::Approved,
                    BridgeToolApprovalResolution::Denied => ToolApprovalResolution::Denied,
                },
                reason,
            })
        }
    })
}
