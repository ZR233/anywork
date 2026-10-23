//! Prompt dispatch does not infer admission from error codes or diagnostic text.
use crate::api::studio::bridge_runtime::active_bridge;
use crate::api::studio::types::{
    BridgeError, BridgeStudioCommandReceipt, BridgeStudioPromptInput, SubmitPromptResponse,
};

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeSubmitPromptOutcome {
    Returned { value: SubmitPromptResponse },
    Rejected { error: BridgeError },
    UnknownOutcome { error: BridgeError },
    CommittedButUnobserved { receipt: BridgeStudioCommandReceipt, error: BridgeError },
    ConfirmedWithoutReceipt { error: BridgeError },
}

/// Submits the frozen input exactly once. Before native runtime dispatch, an unavailable bridge
/// proves rejection. Once dispatch begins, an ordinary runtime error cannot prove non-admission:
/// only the returned original receipt is positive evidence. No error-code heuristic is used.
pub async fn submit_prompt(
    thread_id: String,
    input: BridgeStudioPromptInput,
    expected_model_route_revision: u64,
) -> BridgeSubmitPromptOutcome {
    let bridge = match active_bridge().await {
        Ok(bridge) => bridge,
        Err(error) => return BridgeSubmitPromptOutcome::Rejected { error },
    };
    let result = bridge.studio.submit_prompt_command(
        thread_id,
        pl_protocol::studio::SubmitPromptRequest {
            input: input.into(),
            expected_model_route_revision,
        },
    ).await;
    match result {
        Ok(receipt) => BridgeSubmitPromptOutcome::Returned {
            value: SubmitPromptResponse {
                thread_id: receipt.thread_id,
                input_id: receipt.input_id,
                cursor: receipt.cursor,
                request_digest: receipt.request_digest,
            },
        },
        // The old core call boundary has no negative-admission proof on this error path. Keep
        // the original owner/input alive in the client instead of pretending a retry is safe.
        Err(error) => BridgeSubmitPromptOutcome::UnknownOutcome { error: error.into() },
    }
}
