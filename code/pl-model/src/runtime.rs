//! Product model assembly over the shared invocation runtime.
use crate::{Result, config::ResolvedModelRoute, model::ModelInfo, protocol::ProtocolEndpoint};
pub use pl_model_runtime::runtime::*;

/// Creates the runtime for the account and model selected by the product.
pub fn from_route(route: &ResolvedModelRoute) -> Result<ModelRuntime> {
    let registry = crate::protocol::builtin_protocols();
    let mut route = route.clone();
    registry
        .resolve(&route.endpoint.protocol)?
        .bind(&mut route.endpoint, &mut route.model);
    let upload = registry.file_upload(&route.endpoint.service_capabilities.files)?;
    ModelRuntime::bind_route(route, upload)
}

/// Binds an explicit account endpoint and model to their protocol services.
pub fn new_with_account_id(
    account_id: impl Into<String>,
    endpoint: ProtocolEndpoint,
    model: ModelInfo,
) -> Result<ModelRuntime> {
    new_with_registry(
        account_id,
        endpoint,
        model,
        crate::protocol::builtin_protocols(),
    )
}

pub fn new_with_registry(
    account_id: impl Into<String>,
    mut endpoint: ProtocolEndpoint,
    mut model: ModelInfo,
    registry: crate::protocol::ProtocolRegistry<'_>,
) -> Result<ModelRuntime> {
    registry
        .resolve(&endpoint.protocol)?
        .bind(&mut endpoint, &mut model);
    let upload = registry.file_upload(&endpoint.service_capabilities.files)?;
    ModelRuntime::bind(account_id, endpoint, model, upload)
}

/// Constructs the host-facing completion client using the selected protocol.
pub fn turn_client_from_route(route: &ResolvedModelRoute) -> Result<ModelTurnClient> {
    from_route(route).map(ModelTurnClient::new)
}
