use crate::api::studio::bridge_runtime::active_bridge;
use crate::api::studio::types::BridgeError;

pub async fn remove_attachment_draft(draft_id: String) -> Result<bool, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bridge.studio.remove_attachment_draft(draft_id).await?)
}
