use crate::api::studio::bridge_runtime::active_bridge;
use crate::api::studio::convert::runtime::bridge_lsp_state;
use crate::api::studio::types::{
    BridgeCreateMcpDocumentInput, BridgeDeleteMcpDocumentInput, BridgeError,
    BridgeLspStateSnapshot, BridgeMcpCatalogSnapshot, BridgeMcpDocumentCommitReceipt,
    BridgeMcpDocumentContent, BridgeMcpDocumentRef, BridgeMcpScope, BridgeReconnectThreadMcpInput,
    BridgeThreadMcpStateSnapshot, BridgeUpdateMcpDocumentInput, LspScopeInput,
};

pub async fn read_mcp_catalog(
    scope: BridgeMcpScope,
) -> Result<BridgeMcpCatalogSnapshot, BridgeError> {
    let bridge = active_bridge().await?;
    let snapshot = bridge.studio.read_mcp_catalog(&scope.into())?;
    Ok(snapshot.into())
}

pub async fn reload_mcp_catalog(
    scope: BridgeMcpScope,
) -> Result<BridgeMcpCatalogSnapshot, BridgeError> {
    let bridge = active_bridge().await?;
    let snapshot = bridge.studio.reload_mcp_catalog(&scope.into()).await?;
    Ok(snapshot.into())
}

pub async fn read_mcp_document(
    document: BridgeMcpDocumentRef,
) -> Result<BridgeMcpDocumentContent, BridgeError> {
    let bridge = active_bridge().await?;
    let content = bridge
        .studio
        .read_mcp_document(&document.into())
        .map_err(anyhow::Error::from)?;
    Ok(content.into())
}

pub async fn create_mcp_document(
    input: BridgeCreateMcpDocumentInput,
) -> Result<BridgeMcpDocumentCommitReceipt, BridgeError> {
    let bridge = active_bridge().await?;
    let receipt = bridge
        .studio
        .create_mcp_document(&input.into())
        .await
        .map_err(anyhow::Error::from)?;
    Ok(receipt.into())
}

pub async fn update_mcp_document(
    input: BridgeUpdateMcpDocumentInput,
) -> Result<BridgeMcpDocumentCommitReceipt, BridgeError> {
    let bridge = active_bridge().await?;
    let receipt = bridge
        .studio
        .update_mcp_document(&input.into())
        .await
        .map_err(anyhow::Error::from)?;
    Ok(receipt.into())
}

pub async fn delete_mcp_document(
    input: BridgeDeleteMcpDocumentInput,
) -> Result<BridgeMcpDocumentCommitReceipt, BridgeError> {
    let bridge = active_bridge().await?;
    let receipt = bridge
        .studio
        .delete_mcp_document(&input.into())
        .await
        .map_err(anyhow::Error::from)?;
    Ok(receipt.into())
}

pub async fn read_thread_mcp(
    thread_id: String,
) -> Result<BridgeThreadMcpStateSnapshot, BridgeError> {
    let bridge = active_bridge().await?;
    let snapshot = bridge.studio.read_thread_mcp(&thread_id).await?;
    Ok(snapshot.into())
}

pub async fn reconnect_thread_mcp(
    input: BridgeReconnectThreadMcpInput,
) -> Result<BridgeThreadMcpStateSnapshot, BridgeError> {
    let bridge = active_bridge().await?;
    let snapshot = bridge.studio.reconnect_thread_mcp(input.into()).await?;
    Ok(snapshot.into())
}

pub async fn read_lsp_state() -> Result<BridgeLspStateSnapshot, BridgeError> {
    let bridge = active_bridge().await?;
    let state = bridge.studio.read_lsp_state().await;
    Ok(bridge_lsp_state(state.state))
}

pub async fn probe_lsp_server(workspace_id: String) -> Result<BridgeLspStateSnapshot, BridgeError> {
    let bridge = active_bridge().await?;
    bridge.studio.probe_lsp_server(&workspace_id).await?;
    read_lsp_state().await
}

pub async fn reset_lsp(input: LspScopeInput) -> Result<BridgeLspStateSnapshot, BridgeError> {
    let bridge = active_bridge().await?;
    let request = match input {
        LspScopeInput::Server {
            workspace_id,
            server_id,
        } => pl_protocol::studio::LspResetRequest::Server {
            workspace_id,
            server_id,
        },
        LspScopeInput::Workspace { workspace_id } => {
            pl_protocol::studio::LspResetRequest::Workspace { workspace_id }
        }
        LspScopeInput::All => pl_protocol::studio::LspResetRequest::All,
    };
    bridge.studio.reset_lsp_request(request).await?;
    read_lsp_state().await
}
