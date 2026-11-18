use crate::api::studio::bridge_runtime::active_bridge;
use crate::api::studio::convert::commands::command_receipt;
use crate::api::studio::convert::thread_stream::{bridge_child_interaction, bridge_interaction};
use crate::api::studio::types::{
    BridgeChildInteractionSummary, BridgeContinuationDisposition, BridgeContinuationOperationState,
    BridgeContinuationOperationView, BridgeContinueThreadReply, BridgeError,
    BridgeInteractionCommandReply, BridgeInteractionResolution, BridgeStopThreadReply,
    BridgeStudioPromptInput, BridgeToolApprovalResolution, SubmitPromptResponse,
};
use pl_studio_runtime::{
    InteractionResolution, ToolApprovalResolution, ToolApprovalResolutionPayload, UserInputAnswer,
    UserInputResolution,
};
use std::collections::HashMap;
// ── Prompt / Interaction ──

pub async fn submit_prompt(
    thread_id: String,
    input: BridgeStudioPromptInput,
    expected_model_route_revision: u64,
) -> Result<SubmitPromptResponse, BridgeError> {
    let bridge = active_bridge().await?;
    let response = bridge
        .studio
        .submit_prompt_command(
            thread_id,
            pl_studio_runtime::SubmitPromptRequest {
                input: input.into(),
                expected_model_route_revision,
            },
        )
        .await?;
    Ok(SubmitPromptResponse {
        thread_id: response.thread_id,
        input_id: response.input_id,
        revision: response.cursor,
    })
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
            pl_studio_runtime::StopThreadRequest {
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
    expected_continuation_token: String,
    expected_model_route_revision: u64,
) -> Result<BridgeContinueThreadReply, BridgeError> {
    let bridge = active_bridge().await?;
    let response = bridge
        .studio
        .continue_thread(
            thread_id,
            pl_studio_runtime::ContinueThreadRequest {
                operation_id,
                expected_continuation_token,
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
    expected_continuation_token: String,
) -> Result<BridgeContinuationOperationView, BridgeError> {
    let bridge = active_bridge().await?;
    let view = bridge
        .studio
        .read_continuation_operation(thread_id, operation_id, expected_continuation_token)
        .await?;
    Ok(BridgeContinuationOperationView {
        thread_id: view.thread_id,
        operation_id: view.operation_id,
        expected_continuation_token: view.expected_continuation_token,
        state: match view.state {
            pl_studio_runtime::ContinuationOperationState::Known => {
                BridgeContinuationOperationState::Known
            }
            pl_studio_runtime::ContinuationOperationState::NotAccepted => {
                BridgeContinuationOperationState::NotAccepted
            }
        },
        acceptance_epoch: view.acceptance_epoch,
        execution_id: view.execution_id,
        turn_id: view.turn_id,
        accepted_revision: view.accepted_revision,
        disposition: view.disposition.map(|d| match d {
            pl_studio_runtime::ContinuationDisposition::Scheduled => {
                BridgeContinuationDisposition::Scheduled
            }
            pl_studio_runtime::ContinuationDisposition::Effective => {
                BridgeContinuationDisposition::Effective
            }
            pl_studio_runtime::ContinuationDisposition::NotExecuted(reason) => {
                BridgeContinuationDisposition::NotExecuted { reason }
            }
        }),
        receipt: view.receipt.map(command_receipt),
    })
}

/// 主会话可见的子任务待决交互只读摘要；列举不激活任何子会话。
pub async fn read_child_interactions(
    thread_id: String,
) -> Result<Vec<BridgeChildInteractionSummary>, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bridge
        .studio
        .read_child_interactions(&thread_id)
        .await?
        .into_iter()
        .map(bridge_child_interaction)
        .collect::<anyhow::Result<Vec<_>>>()?)
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
