use crate::protocol::ProtocolId;
use crate::{PureError, Result};
use pl_model_wire::adapter::Adapter;

const BUILTINS: &[&Adapter] = &[
    &pl_model_openai::adapter::ADAPTER,
    &pl_model_openai::adapter::COMPATIBLE_ADAPTER,
    &pl_model_openai_glm::adapter::ADAPTER,
    &pl_model_openai_deepseek::adapter::ADAPTER,
    &pl_model_openai_mimo::adapter::ADAPTER,
    &pl_model_openai_xai::adapter::ADAPTER,
    &pl_model_gemini::adapter::ADAPTER,
];

/// Providers are registered by the application at its composition root.
#[derive(Debug, Clone, Copy)]
pub struct ProtocolRegistry<'a> {
    adapters: &'a [&'static Adapter],
}

impl<'a> ProtocolRegistry<'a> {
    pub fn new(adapters: &'a [&'static Adapter]) -> Result<Self> {
        let mut ids = std::collections::BTreeSet::new();
        for adapter in adapters {
            if !ids.insert(&adapter.id) {
                return Err(PureError::ConfigError(format!(
                    "duplicate model protocol: {}",
                    adapter.id
                )));
            }
        }
        Ok(Self { adapters })
    }

    pub fn hosted_search_label<'id>(&self, id: &'id super::HostedWebSearchDialect) -> &'id str {
        self.adapters
            .iter()
            .filter_map(|adapter| adapter.hosted_search_label.as_ref())
            .find_map(|(stored, label)| (stored == id).then_some(*label))
            .unwrap_or_else(|| id.as_str())
    }

    pub fn file_upload(
        &self,
        id: &pl_model_wire::protocol::FileUploadCapability,
    ) -> Result<Option<&'static pl_model_wire::files::FileUploadService>> {
        use pl_model_wire::protocol::FileUploadCapability;

        if *id == FileUploadCapability::NONE {
            return Ok(None);
        }
        self.adapters
            .iter()
            .filter_map(|adapter| adapter.file_upload)
            .find(|service| &service.id == id)
            .map(Some)
            .ok_or_else(|| {
                PureError::ConfigError(format!(
                    "unregistered model file upload service: {}",
                    id.as_str()
                ))
            })
    }

    pub fn resolve(&self, id: &ProtocolId) -> Result<&'static Adapter> {
        self.adapters
            .iter()
            .copied()
            .find(|adapter| &adapter.id == id)
            .ok_or_else(|| PureError::ConfigError(format!("unregistered model protocol: {id}")))
    }
}

pub fn builtin_protocols() -> ProtocolRegistry<'static> {
    static REGISTRY: std::sync::OnceLock<ProtocolRegistry<'static>> = std::sync::OnceLock::new();
    *REGISTRY.get_or_init(|| {
        ProtocolRegistry::new(BUILTINS).expect("unique built-in model protocol IDs")
    })
}
