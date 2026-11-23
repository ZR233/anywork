use crate::{
    discovery::{DiscoveryPolicy, ModelCatalogQueryError, Record},
    model::{ModelDefinition, ModelRequestProfile},
    protocol::{
        HostedWebSearchDialect, InstructionWireRole, ProtocolEndpoint, ProtocolId,
        ProtocolServiceCapabilities,
    },
};

/// OpenAI-family provider policies selected during route assembly.
#[derive(Debug)]
pub struct Adapter {
    pub id: ProtocolId,
    pub responses_instruction_role: InstructionWireRole,
    pub discovery: DiscoveryPolicy,
    pub file_upload: Option<&'static crate::files::FileUploadService>,
    pub prepare_request: Option<fn(&ProtocolEndpoint, &mut ModelRequestProfile)>,
    /// Optional legacy API label for a hosted search dialect with a different stored ID.
    pub hosted_search_label: Option<(HostedWebSearchDialect, &'static str)>,
    pub on_base_url_override: Option<fn(&mut ProtocolServiceCapabilities)>,
    pub parse_catalog: fn(&[u8]) -> Result<Vec<Record>, ModelCatalogQueryError>,
}

impl Adapter {
    /// Freezes the provider's defaults before model validation and wire encoding.
    pub fn bind(&self, endpoint: &mut ProtocolEndpoint, model: &mut ModelDefinition) {
        endpoint.responses_instruction_role = self.responses_instruction_role;
        if let Some(prepare) = self.prepare_request {
            prepare(endpoint, &mut model.extra.binding.request);
        }
    }
}
