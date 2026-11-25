use crate::{
    discovery::{DiscoveryPolicy, ModelCatalogQueryError, ParsedCatalogPage},
    model::{ModelDefinition, ModelRequestProfile},
    protocol::{
        ApiKeyHeaderScheme, HostedWebSearchDialect, InstructionWireRole, ProtocolEndpoint,
        ProtocolId, ProtocolServiceCapabilities,
    },
    wire_codec::WireCodec,
};

/// Provider-family adapter policies selected during route assembly.
#[derive(Debug)]
pub struct Adapter {
    pub id: ProtocolId,
    pub codec: &'static dyn WireCodec,
    pub error_policy: &'static dyn crate::provider_error::ProviderErrorPolicy,
    pub api_key_header: ApiKeyHeaderScheme,
    pub responses_instruction_role: InstructionWireRole,
    pub discovery: DiscoveryPolicy,
    pub discovery_query_params: &'static [(&'static str, &'static str)],
    pub discovery_page_token_param: Option<&'static str>,
    pub file_upload: Option<&'static crate::files::FileUploadService>,
    pub prepare_request: Option<fn(&ProtocolEndpoint, &mut ModelRequestProfile)>,
    /// Optional legacy API label for a hosted search dialect with a different stored ID.
    pub hosted_search_label: Option<(HostedWebSearchDialect, &'static str)>,
    pub on_base_url_override: Option<fn(&mut ProtocolServiceCapabilities)>,
    pub parse_catalog_page: fn(&[u8]) -> Result<ParsedCatalogPage, ModelCatalogQueryError>,
}

impl Adapter {
    /// Freezes the provider's defaults before model validation and wire encoding.
    pub fn bind(&self, endpoint: &mut ProtocolEndpoint, model: &mut ModelDefinition) {
        endpoint.responses_instruction_role = self.responses_instruction_role;
        endpoint.api_key_header = self.api_key_header;
        if let Some(prepare) = self.prepare_request {
            prepare(endpoint, &mut model.extra.binding.request);
        }
    }
}
