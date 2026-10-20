use pl_protocol::ThreadModeId;

use crate::api::studio::bridge_runtime::{active_bridge, installed_bridge};
use crate::api::studio::convert::mode_editor::{
    bridge_thread_mode_command_reply, bridge_thread_mode_definition_snapshot,
    bridge_thread_mode_validation_result, bridge_workflow_preview_snapshot,
};
use crate::api::studio::types::{
    BridgeError, BridgeThreadModeDefinitionCommandReply, BridgeThreadModeDefinitionSnapshot,
    BridgeThreadModeDocument, BridgeThreadModeValidationResult, BridgeWorkflowPreviewRequest,
    BridgeWorkflowPreviewSnapshot,
};

fn thread_mode_id(value: String) -> Result<ThreadModeId, BridgeError> {
    let id = ThreadModeId::new(value).map_err(|error| {
        anyhow::Error::from(pl_protocol::studio::StudioError::invalid_argument(
            error.to_string(),
        ))
    })?;
    Ok(id)
}

/// Reads one authorable Mode definition, including editor layout metadata.
pub fn read_thread_mode_definition(
    mode_id: String,
) -> Result<BridgeThreadModeDefinitionSnapshot, BridgeError> {
    let bridge = installed_bridge()?;
    Ok(bridge_thread_mode_definition_snapshot(
        bridge
            .studio
            .read_thread_mode_definition(&thread_mode_id(mode_id)?)?,
    ))
}

/// Saves one Mode definition using the catalog revision as its CAS barrier.
pub async fn save_thread_mode_definition(
    operation_id: String,
    expected_revision: u64,
    document: BridgeThreadModeDocument,
) -> Result<BridgeThreadModeDefinitionCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bridge_thread_mode_command_reply(
        bridge
            .studio
            .save_thread_mode_definition(&operation_id, expected_revision, document.try_into()?)
            .await?,
    ))
}

/// Deletes one user-authored Mode definition.
pub async fn delete_thread_mode_definition(
    operation_id: String,
    expected_revision: u64,
    mode_id: String,
) -> Result<BridgeThreadModeDefinitionCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    let mode_id = thread_mode_id(mode_id)?;
    Ok(bridge_thread_mode_command_reply(
        bridge
            .studio
            .delete_thread_mode_definition(&operation_id, expected_revision, &mode_id)
            .await?,
    ))
}

/// Reloads all file-backed Mode definitions into the shared config manager.
pub async fn reload_thread_mode_definitions(
    operation_id: String,
    expected_revision: u64,
) -> Result<BridgeThreadModeDefinitionCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bridge_thread_mode_command_reply(
        bridge
            .studio
            .reload_thread_mode_definitions(&operation_id, expected_revision)
            .await?,
    ))
}

/// Validates an authored JSON document without publishing it.
pub fn validate_thread_mode_definition(
    json: String,
) -> Result<BridgeThreadModeValidationResult, BridgeError> {
    let bridge = installed_bridge()?;
    Ok(bridge_thread_mode_validation_result(
        bridge.studio.validate_thread_mode_definition(&json),
    ))
}

/// Returns the JSON schema used by the textual authoring surface.
pub fn thread_mode_definition_schema() -> Result<String, BridgeError> {
    Ok(installed_bridge()?.studio.thread_mode_definition_schema())
}

/// Replays a typed workflow preview through the production Rust machine.
pub fn preview_thread_mode_workflow(
    request: BridgeWorkflowPreviewRequest,
) -> Result<BridgeWorkflowPreviewSnapshot, BridgeError> {
    Ok(bridge_workflow_preview_snapshot(
        installed_bridge()?
            .studio
            .preview_thread_mode_workflow(request.try_into()?)?,
    ))
}
