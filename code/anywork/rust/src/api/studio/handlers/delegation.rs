use crate::api::studio::bridge_runtime::active_bridge;
use crate::api::studio::types::{
    BridgeDelegationModelDetail, BridgeError, BridgeGetDelegationModelRequest,
};

/// Reads one exact account member, preserving typed not-found/stale failures.
pub async fn get_delegation_model(
    request: BridgeGetDelegationModelRequest,
) -> Result<BridgeDelegationModelDetail, BridgeError> {
    Ok(active_bridge()
        .await?
        .studio
        .get_delegation_model(pl_studio_runtime::GetDelegationModelRequest {
            account_id: request.account_id,
            model_id: request.model_id,
        })
        .await?
        .into())
}
