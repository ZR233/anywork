use crate::api::studio::bridge_runtime::active_bridge;
use crate::api::studio::convert::commands::command_receipt;
use crate::api::studio::convert::thread_stream::bridge_interaction;
use crate::api::studio::types::{
    BridgeError, BridgeInteractionCommandReply, BridgeInteractionResolution,
    BridgeInterruptTurnCommandReply, BridgeStudioPromptInput, BridgeToolApprovalResolution,
    SubmitPromptResponse,
};
use pl_protocol::{
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
            pl_protocol::studio::SubmitPromptRequest {
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

pub async fn interrupt_turn(
    operation_id: String,
    thread_id: String,
    turn_id: String,
) -> Result<BridgeInterruptTurnCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    let response = bridge
        .studio
        .interrupt_prompt(operation_id, thread_id, turn_id)
        .await?;
    Ok(BridgeInterruptTurnCommandReply {
        thread_id: response.thread_id,
        turn_id: response.turn_id,
        interrupted: response.interrupted,
        receipt: command_receipt(response.receipt),
    })
}

pub async fn respond_interaction(
    operation_id: String,
    interaction_id: String,
    resolution: BridgeInteractionResolution,
) -> Result<BridgeInteractionCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    let resolution = interaction_resolution(resolution)?;
    let response = bridge
        .studio
        .resolve_interaction(operation_id, interaction_id, resolution)
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
