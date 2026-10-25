//! Opaque Configuration scopes reuse the original bridge registry and native read owner.
use super::super::identity::{
    BridgeProductEntityRef, BridgeProductReadOrigin, BridgeProductReadScopeIdentity,
    BridgeProductSourceStatusRef,
};
use super::super::references::BridgeConfigurationReadRef;
use super::super::source::BridgeProductSourceStatusReadHeader;
use super::configuration_pages::*;
use super::configuration_values::*;
use super::owner::{ModelsRead, ModelsReadHandle, open_read};
use super::pages::{BridgeModelInputCapabilityReadPage, BridgeModelInputSourceReadPage};
use super::primitives::BridgeTextReadPage;
use crate::api::studio::observation::BridgeTextChunk;
use crate::api::studio::types::{BridgeError, BridgeFeedCloseReport};
use pl_studio_runtime::configuration::{
    StudioConfigurationRead, StudioConfigurationRoleRead, StudioConfigurationSourceStatusRead,
    StudioConfigurationStartRead,
};

macro_rules! native_read {
    ($source:ty) => {
        impl ModelsRead for $source {
            fn identity(&self) -> pl_protocol::products::identity::ProductReadScopeIdentity {
                <$source>::identity(self)
            }
            fn ensure_open(&self) -> Result<(), pl_protocol::studio::StudioError> {
                <$source>::ensure_open(self)
            }
            fn request_close(&self) {
                <$source>::request_close(self);
            }
            fn close(
                &self,
            ) -> impl std::future::Future<Output = pl_protocol::studio::FeedCloseReport> + Send
            {
                <$source>::close(self)
            }
        }
    };
}
native_read!(StudioConfigurationRead);
native_read!(StudioConfigurationRoleRead);
native_read!(StudioConfigurationStartRead);
native_read!(StudioConfigurationSourceStatusRead);

#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeConfigurationReadConnection {
    read: ModelsReadHandle<StudioConfigurationRead>,
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeConfigurationRoleReadConnection {
    read: ModelsReadHandle<StudioConfigurationRoleRead>,
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeConfigurationStartReadConnection {
    read: ModelsReadHandle<StudioConfigurationStartRead>,
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeConfigurationSourceStatusReadConnection {
    read: ModelsReadHandle<StudioConfigurationSourceStatusRead>,
}

pub async fn open_configuration_read(
    reference: BridgeConfigurationReadRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgeConfigurationReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeConfigurationReadConnection {
        read: open_read(move |runtime| runtime.open_configuration_read(reference, origin)).await?,
    })
}
pub async fn open_configuration_role_read(
    target: BridgeConfigurationRoleReadTarget,
) -> Result<BridgeConfigurationRoleReadConnection, BridgeError> {
    let target = target.into();
    Ok(BridgeConfigurationRoleReadConnection {
        read: open_read(move |runtime| runtime.open_configuration_role_read(target)).await?,
    })
}
pub async fn open_configuration_start_read(
    target: BridgeConfigurationRoleReadTarget,
) -> Result<BridgeConfigurationStartReadConnection, BridgeError> {
    let target = target.into();
    Ok(BridgeConfigurationStartReadConnection {
        read: open_read(move |runtime| runtime.open_configuration_start_read(target)).await?,
    })
}
pub async fn open_configuration_source_status_read(
    reference: BridgeProductSourceStatusRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgeConfigurationSourceStatusReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeConfigurationSourceStatusReadConnection {
        read: open_read(move |runtime| {
            runtime.open_configuration_source_status_read(reference, origin)
        })
        .await?,
    })
}

impl BridgeConfigurationReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeConfigurationReadHeader, BridgeError> {
        Ok(self
            .read
            .query(StudioConfigurationRead::header)?
            .await?
            .into())
    }
    pub async fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> Result<BridgeTextChunk, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.text(field_id, offset, max_bytes))?
            .await?
            .into())
    }
    pub async fn entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeConfigurationEntryPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.entries(offset, limit))?
            .await?
            .into())
    }
    pub async fn entity(
        &self,
        reference: BridgeProductEntityRef,
    ) -> Result<BridgeConfigurationEntityRead, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.entity(reference.into()))?
            .await?
            .into())
    }
    pub async fn lookup_account(
        &self,
        account_id: String,
    ) -> Result<Option<BridgeProductEntityRef>, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.lookup_account(account_id))?
            .await?
            .map(Into::into))
    }
    pub async fn accounts(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeAccountConfigurationReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.accounts(list_id, offset, limit))?
            .await?
            .into())
    }
    pub async fn custom_models(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeCustomModelConfigurationReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.custom_models(list_id, offset, limit))?
            .await?
            .into())
    }
    pub async fn model_connections(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeModelConnectionReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.model_connections(list_id, offset, limit))?
            .await?
            .into())
    }
    pub async fn auto_compact_overrides(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeModelAutoCompactReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.auto_compact_overrides(list_id, offset, limit))?
            .await?
            .into())
    }
    pub async fn mode_routes(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeModeModelRouteReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.mode_routes(list_id, offset, limit))?
            .await?
            .into())
    }
    pub async fn role_routes(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeRoleModelRouteReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.role_routes(list_id, offset, limit))?
            .await?
            .into())
    }
    pub async fn mcp_configs(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeMcpConfigurationReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.mcp_configs(list_id, offset, limit))?
            .await?
            .into())
    }
    pub async fn strings(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeTextReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.strings(list_id, offset, limit))?
            .await?
            .into())
    }
    pub async fn input_capabilities(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeModelInputCapabilityReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.input_capabilities(list_id, offset, limit))?
            .await?
            .into())
    }
    pub async fn input_sources(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeModelInputSourceReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.input_sources(list_id, offset, limit))?
            .await?
            .into())
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.read.request_close();
    }
    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.close().await
    }
    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.retry_close().await
    }
}

impl BridgeConfigurationRoleReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeConfigurationRoleReadTarget, BridgeError> {
        Ok(self
            .read
            .query(StudioConfigurationRoleRead::header)?
            .await?
            .into())
    }
    pub async fn role_route(&self, role_id: String) -> Result<BridgeRoleRouteRead, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.role_route(role_id))?
            .await?
            .into())
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.read.request_close();
    }
    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.close().await
    }
    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.retry_close().await
    }
}

impl BridgeConfigurationStartReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeConfigurationRoleReadTarget, BridgeError> {
        Ok(self
            .read
            .query(StudioConfigurationStartRead::header)?
            .await?
            .into())
    }
    pub async fn resolve(
        &self,
        query: BridgeStartRouteQuery,
    ) -> Result<BridgeStartRouteRead, BridgeError> {
        let query = query.try_into()?;
        Ok(self
            .read
            .query(move |source| source.resolve(query))?
            .await?
            .into())
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.read.request_close();
    }
    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.close().await
    }
    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.retry_close().await
    }
}

impl BridgeConfigurationSourceStatusReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeProductSourceStatusReadHeader, BridgeError> {
        Ok(self
            .read
            .query(StudioConfigurationSourceStatusRead::header)?
            .await?
            .into())
    }
    pub async fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> Result<BridgeTextChunk, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.text(field_id, offset, max_bytes))?
            .await?
            .into())
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.read.request_close();
    }
    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.close().await
    }
    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.retry_close().await
    }
}
