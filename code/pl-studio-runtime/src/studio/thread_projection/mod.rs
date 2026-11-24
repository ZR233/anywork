//! Product timeline projections read core facts and never drive models, tools or persistence reducers.
mod agent_directory;
mod item;
pub(in crate::studio) use agent_directory::{awaiting_scheduling, native_activity};
pub(crate) use item::{ExecutionItem, ExecutionKind, ExecutionShape};
mod accounting;
mod billing;
pub(crate) use accounting::PreparedAccounting;
pub(crate) use billing::AuxiliaryBillingReceipt;
pub(in crate::studio) use billing::BillingFact;
#[cfg(test)]
pub(in crate::studio) use billing::billing_facts;
mod activity;
mod completed_activity;
pub(in crate::studio) use activity::project_activity;
pub(in crate::studio) use completed_activity::activity_identity;
mod completions;
mod content;
mod current;
mod current_page;
pub(in crate::studio) use current::{CurrentEntryWrite, CurrentPositionIndex};
pub(in crate::studio) use current_page::{collection_revision, current_page, page_rows};
mod current_projection;
pub(in crate::studio) use content::{ContentError, InputView, input_presentation, input_view};
pub(in crate::studio) use current::CurrentState;
pub(in crate::studio) use current_projection::FrozenCurrentProjection;
mod effect;
pub(in crate::studio) use effect::project_effect_items;
pub(in crate::studio) mod live;
pub(in crate::studio) mod presentation;
pub(in crate::studio) use live::{
    LiveEvent, LiveProjection, PreparedEffect, TurnEvent, TurnResult,
};
pub(crate) use presentation::{hidden, work};
mod runtime;
mod usage_projection;
pub(in crate::studio) use runtime::{
    project_cold_runtime, project_runtime, workflow_graph_from_definition,
    workflow_graph_from_saved_mode,
};
pub(in crate::studio) use usage_projection::usage_status;
mod snapshot;
pub(in crate::studio) use snapshot::{saved_mode, status, storage_state};
pub(in crate::studio) mod order;
mod tool_media;
pub(crate) use tool_media::{delivery_attachments, read_persisted_media};
mod inputs;
mod responses;
pub(in crate::studio) mod tools;
mod turns;
mod user_input;
mod wait;
pub(in crate::studio) use turns::project_active_turn;
pub(in crate::studio) use user_input::{
    attach as attach_tool_user_input, project_user_input as project_tool_user_input,
};

/// The canonical terminal Turn transitioned by this reliable effect.
pub(in crate::studio) fn prepared_terminal_turn(prepared: &PreparedEffect) -> Option<crate::Turn> {
    let turn_id = prepared.terminal_turn_id.as_deref()?;
    prepared
        .history_turn_details
        .get(turn_id)
        .filter(|turn| turn.state.is_terminal())
        .cloned()
}

/// Identity of one streaming channel item (`reasoning` or `text`) for an attempt.
///
/// Both the durable writer and the live projection derive the finalize set from the same identity,
/// so a failure never finalizes a channel the attempt never started.
pub(in crate::studio) fn attempt_channel_id(attempt_id: &str, channel: &str) -> String {
    order::response_id(attempt_id, channel)
}

#[derive(Debug, thiserror::Error)]
pub(crate) enum ProjectionError {
    #[error("review delivery application fact cannot be projected")]
    ReviewDelivery(#[source] anyhow::Error),
    #[error("saved product state cannot be projected")]
    Product(#[from] crate::PureError),
    #[error("saved workflow state cannot be projected")]
    Workflow(#[from] pl_core::tool::opaque::ToolError),
    #[error("saved tool media receipt cannot be decoded")]
    ToolMedia(pl_core::tool::opaque::ToolError),
    #[error("durable history identity lookup failed: {0}")]
    History(String),
    #[error("timeline item {0} has no unique admission position")]
    ItemOrder(String),
    #[error("historical content metadata could not be encoded")]
    Encoding(#[from] serde_json::Error),
    #[error("duplicate or contradictory saved tool call {0}")]
    DuplicateCall(String),
    #[error("saved user-input history fact is invalid: {0}")]
    UserInput(String),
    #[error("terminal tool call {0} has no saved result")]
    MissingToolResult(String),
    #[error("saved model receipt cannot be decoded")]
    Model(#[from] pl_core::model::ModelError),
    #[error("unsupported saved model content: {0}")]
    UnsupportedOutput(String),
    #[error("missing committed metadata for input {0}")]
    MissingInput(String),
    #[error("durable history is missing the committed input item(s) {0}")]
    MissingDurableInput(String),
    #[error("hidden input {0} also has a visible durable timeline item")]
    ContradictoryHiddenInput(String),
    #[error("durable history is missing the accepted tool call item(s) {0}")]
    MissingDurableToolCall(String),
    #[error("timeline count exceeds the product representation")]
    Count,
    #[error("Turn {0} has no measured final duration")]
    MissingDuration(String),
}

pub(super) fn raw_payload(payload: &pl_core::context::OpaquePayload) -> crate::ThreadRawPayload {
    crate::ThreadRawPayload {
        format: payload.format().into(),
        version: payload.version(),
        content: payload.content().into(),
    }
}

pub(crate) use tool_media::{resource_references, resource_references_for_deliveries};

mod history_facts;
