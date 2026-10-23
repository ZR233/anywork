use crate::api::studio::bridge_runtime::active_bridge;
use crate::api::studio::convert::commands::command_receipt;
use crate::api::studio::convert::thread_stream::bridge_interaction;
use crate::api::studio::types::{
    BridgeError, BridgeInteractionCommandReply, BridgeInteractionResolution,
    BridgeInterruptTurnCommandReply, BridgeToolApprovalResolution,
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
    use crate::api::studio::types::{BridgeInputAcceptanceEvidence, BridgePersistedInputDisposition};
    use pl_protocol::studio::PersistedInputDisposition;
    let bridge = active_bridge().await?;
    Ok(bridge.studio.read_input_acceptance(thread_id, input_id).await?.map(|evidence| {
        BridgeInputAcceptanceEvidence {
            accepted_sequence: evidence.accepted_sequence,
            request_digest: evidence.request_digest,
            disposition: match evidence.disposition {
                PersistedInputDisposition::Consumed => BridgePersistedInputDisposition::Consumed,
                PersistedInputDisposition::Discarded => BridgePersistedInputDisposition::Discarded,
            },
        }
    }))
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
    expected_interaction_revision: u64,
    resolution: BridgeInteractionResolution,
) -> Result<BridgeInteractionCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    let resolution = interaction_resolution(resolution)?;
    let response = bridge
        .studio
        .resolve_interaction(
            operation_id,
            interaction_id,
            expected_interaction_revision,
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
