use crate::api::studio::bridge_runtime::active_bridge;
use crate::api::studio::types::{
    BridgeDelegationModelDetail, BridgeDelegationModelList, BridgeError,
    BridgeGetDelegationModelRequest, BridgeListDelegationModelsRequest,
};

/// Reads local reference data only; never performs paid inference or writes evaluations.
pub async fn list_delegation_models(
    request: BridgeListDelegationModelsRequest,
) -> Result<BridgeDelegationModelList, BridgeError> {
    Ok(active_bridge()
        .await?
        .studio
        .list_delegation_models(request.into())
        .await?
        .into())
}

/// Reads one exact account member, preserving typed not-found/stale failures.
pub async fn get_delegation_model(
    request: BridgeGetDelegationModelRequest,
) -> Result<BridgeDelegationModelDetail, BridgeError> {
    Ok(active_bridge()
        .await?
        .studio
        .get_delegation_model(pl_protocol::GetDelegationModelRequest {
            account_id: request.account_id,
            model_id: request.model_id,
        })
        .await?
        .into())
}
