use std::future::Future;
use std::sync::Arc;

use anyhow::Result;
use pl_protocol::products::identity::ProductReadVersion;

use super::super::StudioRuntime;
use super::material::ConfigurationReadMaterial;
use super::scope::ConfigurationScope;
use super::*;
use crate::config::ConfigurationPair;

pub struct StudioConfigurationRead {
    scope: ConfigurationScope<ConfigurationReadMaterial>,
}
pub struct StudioConfigurationRoleRead {
    scope: ConfigurationScope<Arc<ConfigurationPair>>,
}
pub struct StudioConfigurationStartRead {
    scope: ConfigurationScope<Arc<ConfigurationPair>>,
}

impl StudioRuntime {
    /// Pins only an original published origin/ref. Overloaded shares the original 8/64 limits;
    /// Cancelled rejects sealed/replaced owners, Superseded rejects expired material.
    pub fn open_configuration_read(
        &self,
        reference: ConfigurationReadRef,
        origin: ProductReadOrigin,
    ) -> impl Future<Output = Result<StudioConfigurationRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let source = runtime.configuration_source.pin(&origin, reference)?;
            let scope = ConfigurationScope::open(
                &runtime,
                origin,
                ProductReadVersion::Value {
                    entry: reference.entry,
                    revision: reference.revision,
                },
                ConfigurationReadMaterial::new(source),
            )?;
            Ok(StudioConfigurationRead { scope })
        })
    }

    /// Native verifies the entire pair credential, both watermarks and both original targets.
    /// No role query, latest read or new material is used to manufacture the requested pair.
    pub fn open_configuration_role_read(
        &self,
        target: ConfigurationRoleReadTarget,
    ) -> impl Future<Output = Result<StudioConfigurationRoleRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let pair = runtime.configuration_source.pin_pair(&target)?;
            let scope = ConfigurationScope::open(
                &runtime,
                target.configuration.origin,
                ProductReadVersion::Value {
                    entry: target.reference.entry,
                    revision: target.reference.revision,
                },
                pair,
            )?;
            Ok(StudioConfigurationRoleRead { scope })
        })
    }

    /// Start is its own read capability, with no configuration writes, probes or Thread creation.
    pub fn open_configuration_start_read(
        &self,
        target: ConfigurationRoleReadTarget,
    ) -> impl Future<Output = Result<StudioConfigurationStartRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let pair = runtime.configuration_source.pin_pair(&target)?;
            let scope = ConfigurationScope::open(
                &runtime,
                target.configuration.origin,
                ProductReadVersion::Value {
                    entry: target.reference.entry,
                    revision: target.reference.revision,
                },
                pair,
            )?;
            Ok(StudioConfigurationStartRead { scope })
        })
    }
}

impl StudioConfigurationRead {
    pub fn identity(&self) -> ProductReadScopeIdentity {
        self.scope.identity()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.scope.ensure_open()
    }
    pub fn header(
        &self,
    ) -> impl Future<Output = Result<ConfigurationReadHeader>> + Send + 'static + use<> {
        self.scope.query(ConfigurationReadMaterial::header)
    }
    pub fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> impl Future<Output = Result<TextChunk>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.text(field_id, offset, max_bytes))
    }
    pub fn entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<ConfigurationEntryPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.entries(offset, limit))
    }
    pub fn entity(
        &self,
        reference: ProductEntityRef,
    ) -> impl Future<Output = Result<ConfigurationEntityRead>> + Send + 'static + use<> {
        self.scope.query(move |material| material.entity(reference))
    }
    pub fn lookup_account(
        &self,
        account_id: String,
    ) -> impl Future<Output = Result<Option<ProductEntityRef>>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.lookup_account(&account_id))
    }
    pub fn accounts(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<AccountConfigurationReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.accounts(list_id, offset, limit))
    }
    pub fn custom_models(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<CustomModelConfigurationReadPage>> + Send + 'static + use<>
    {
        self.scope
            .query(move |material| material.custom_models(list_id, offset, limit))
    }
    pub fn model_connections(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<ModelConnectionReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.model_connections(list_id, offset, limit))
    }
    pub fn auto_compact_overrides(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<ModelAutoCompactReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.auto_compact_overrides(list_id, offset, limit))
    }
    pub fn mode_routes(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<ModeModelRouteReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.mode_routes(list_id, offset, limit))
    }
    pub fn role_routes(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<RoleModelRouteReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.role_routes(list_id, offset, limit))
    }
    pub fn mcp_configs(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<McpConfigurationReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.mcp_configs(list_id, offset, limit))
    }
    pub fn strings(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<TextReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.strings_page(list_id, offset, limit))
    }
    pub fn input_capabilities(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<ModelInputCapabilityReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.input_capabilities(list_id, offset, limit))
    }
    pub fn input_sources(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<ModelInputSourceReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.input_sources(list_id, offset, limit))
    }
    pub fn request_close(&self) {
        self.scope.request_close();
    }
    pub async fn close(&self) -> FeedCloseReport {
        self.scope.close().await
    }
    pub async fn retry_close(&self) -> FeedCloseReport {
        self.scope.close().await
    }
}

impl StudioConfigurationRoleRead {
    pub fn identity(&self) -> ProductReadScopeIdentity {
        self.scope.identity()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.scope.ensure_open()
    }
    pub fn header(
        &self,
    ) -> impl Future<Output = Result<ConfigurationRoleReadTarget>> + Send + 'static + use<> {
        self.scope.query(|pair| Ok(pair.target.clone()))
    }
    pub fn role_route(
        &self,
        role_id: String,
    ) -> impl Future<Output = Result<RoleRouteRead>> + Send + 'static + use<> {
        self.scope.query(move |pair| pair.role_route(&role_id))
    }
    pub fn request_close(&self) {
        self.scope.request_close();
    }
    pub async fn close(&self) -> FeedCloseReport {
        self.scope.close().await
    }
    pub async fn retry_close(&self) -> FeedCloseReport {
        self.scope.close().await
    }
}

impl StudioConfigurationStartRead {
    pub fn identity(&self) -> ProductReadScopeIdentity {
        self.scope.identity()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.scope.ensure_open()
    }
    pub fn header(
        &self,
    ) -> impl Future<Output = Result<ConfigurationRoleReadTarget>> + Send + 'static + use<> {
        self.scope.query(|pair| Ok(pair.target.clone()))
    }
    pub fn resolve(
        &self,
        query: StartRouteQuery,
    ) -> impl Future<Output = Result<StartRouteRead>> + Send + 'static + use<> {
        self.scope.query(move |pair| pair.start_route(query))
    }
    pub fn request_close(&self) {
        self.scope.request_close();
    }
    pub async fn close(&self) -> FeedCloseReport {
        self.scope.close().await
    }
    pub async fn retry_close(&self) -> FeedCloseReport {
        self.scope.close().await
    }
}
