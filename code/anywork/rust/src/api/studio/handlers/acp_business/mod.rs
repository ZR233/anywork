//! Production ACP commands. Only the runtime owns business resources and SDK controls.
pub mod feed;
pub use feed::BridgeAcpSessionObservation;

use crate::api::studio::bridge_runtime::active_bridge;
use crate::api::studio::convert::acp_business as convert;
use crate::api::studio::types::*;

pub async fn open_acp_session(
    request: BridgeOpenAcpSessionRequest,
) -> Result<BridgeAcpSessionObservation, BridgeAcpBusinessError> {
    let bridge = active_bridge().await?;
    let opened = bridge
        .studio
        .open_acp_session(request.into())
        .await
        .map_err(convert::runtime_error)?;
    Ok(BridgeAcpSessionObservation::new(
        opened,
        bridge.shutdown.child_token(),
    ))
}

pub async fn prompt_acp_session(
    request: BridgeAcpPromptRequest,
) -> Result<BridgeAcpRunId, BridgeAcpBusinessError> {
    let content = request
        .content
        .into_iter()
        .map(convert::protocol_content)
        .collect::<Result<Vec<_>, _>>()?;
    let bridge = active_bridge().await?;
    bridge
        .studio
        .prompt_acp_session(request.target.into(), content)
        .await
        .map(Into::into)
        .map_err(convert::business_error)
}
pub async fn replace_acp_session(
    request: BridgeAcpReplaceRequest,
) -> Result<BridgeAcpRunId, BridgeAcpBusinessError> {
    let content = request
        .content
        .into_iter()
        .map(convert::protocol_content)
        .collect::<Result<Vec<_>, _>>()?;
    let bridge = active_bridge().await?;
    bridge
        .studio
        .replace_acp_session(request.target.into(), request.run.into(), content)
        .await
        .map(Into::into)
        .map_err(convert::business_error)
}
pub async fn interrupt_acp_session(
    request: BridgeAcpInterruptRequest,
) -> Result<(), BridgeAcpBusinessError> {
    let bridge = active_bridge().await?;
    bridge
        .studio
        .interrupt_acp_session(request.target.into(), request.run.into())
        .await
        .map_err(convert::business_error)
}
pub async fn configure_acp_session(
    request: BridgeAcpConfigureRequest,
) -> Result<(), BridgeAcpBusinessError> {
    let bridge = active_bridge().await?;
    bridge
        .studio
        .configure_acp_session(
            request.target.into(),
            request.config_id.value.into(),
            convert::protocol_config_value(request.value),
        )
        .await
        .map_err(convert::business_error)
}
pub async fn set_acp_session_mode(
    request: BridgeAcpSetModeRequest,
) -> Result<(), BridgeAcpBusinessError> {
    let bridge = active_bridge().await?;
    bridge
        .studio
        .set_acp_session_mode(request.target.into(), request.mode_id.value.into())
        .await
        .map_err(convert::business_error)
}
pub async fn answer_acp_permission(
    request: BridgeAcpPermissionAnswerRequest,
) -> Result<(), BridgeAcpBusinessError> {
    let bridge = active_bridge().await?;
    bridge
        .studio
        .answer_acp_permission(
            request.target.into(),
            request.permission_id.into(),
            request.option_id.map(|id| id.value.into()),
        )
        .await
        .map_err(convert::business_error)
}
pub async fn list_acp_sessions(
    request: BridgeAcpListRequest,
) -> Result<BridgeAcpListResponse, BridgeAcpBusinessError> {
    let (target, request) = convert::protocol_list(request)?;
    let bridge = active_bridge().await?;
    convert::list(
        bridge
            .studio
            .list_acp_sessions(target, request)
            .await
            .map_err(convert::business_error)?,
    )
}
pub async fn acp_session_snapshot(
    target: BridgeAcpSessionTarget,
) -> Result<BridgeAcpBusinessSnapshot, BridgeAcpBusinessError> {
    let bridge = active_bridge().await?;
    convert::snapshot(
        bridge
            .studio
            .acp_session_snapshot(target.into())
            .await
            .map_err(convert::business_error)?,
    )
}
/// Closes the original business owner. Observation close is a separate, local operation.
pub async fn close_acp_session(
    target: BridgeAcpSessionTarget,
) -> Result<BridgeAcpBusinessClose, BridgeAcpBusinessError> {
    let bridge = active_bridge().await?;
    convert::close(
        bridge
            .studio
            .close_acp_session(target.into())
            .await
            .map_err(convert::runtime_error)?,
    )
}
