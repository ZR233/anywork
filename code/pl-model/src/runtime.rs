//! Product model assembly over the shared invocation runtime.
use crate::{
    Result,
    config::ResolvedModelRoute,
    model::ModelInfo,
    protocol::{FileUploadCapability, ProtocolEndpoint},
};
pub use pl_model_runtime::runtime::*;

/// Creates the runtime for the account and model selected by the product.
pub fn from_route(route: &ResolvedModelRoute) -> Result<ModelRuntime> {
    ModelRuntime::bind_route(route, upload_for(&route.endpoint))
}

/// Binds an explicit account endpoint and model to their protocol services.
pub fn new_with_account_id(
    account_id: impl Into<String>,
    endpoint: ProtocolEndpoint,
    model: ModelInfo,
) -> Result<ModelRuntime> {
    let upload = upload_for(&endpoint);
    ModelRuntime::bind(account_id, endpoint, model, upload)
}

fn upload_for(endpoint: &ProtocolEndpoint) -> Option<pl_model_types::files::UploadFile> {
    match endpoint.service_capabilities.files {
        FileUploadCapability::None => None,
        FileUploadCapability::DeepSeek => Some(pl_model_openai_deepseek::UPLOAD),
    }
}

/// Constructs the host-facing completion client using the selected protocol.
pub fn turn_client_from_route(route: &ResolvedModelRoute) -> Result<ModelTurnClient> {
    from_route(route).map(ModelTurnClient::new)
}
