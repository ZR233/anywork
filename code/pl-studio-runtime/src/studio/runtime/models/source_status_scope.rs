use std::future::Future;
use std::sync::Arc;

use anyhow::Result;
use pl_protocol::products::identity::{ProductReadVersion, ProductResource};
use serde::Serialize;

use super::super::read_budget::require_budget;
use super::super::read_scopes::{
    PinnedMaterial, ProductScopeBinding, ReadScopeBudgetKey, ReadScopeOwner,
};
use super::super::{StudioRuntime, read_calls::ReadCalls};
use super::source_status_material::SourceStatusReadMaterial;
use super::{
    FeedCloseReport, ProductReadOrigin, ProductReadScopeIdentity, ProductSourceStatusReadHeader,
    ProductSourceStatusRef, StudioError, TextChunk,
};

/// Pins one original Catalog metadata version. Value and status scopes share the same resource
/// key, eight-scope budget, 64 actual read calls and original shutdown/join registry.
pub struct StudioModelCatalogSourceStatusRead {
    identity: ProductReadScopeIdentity,
    owner: Arc<ReadScopeOwner>,
    material: Arc<PinnedMaterial<SourceStatusReadMaterial>>,
    calls: ReadCalls,
}

impl StudioRuntime {
    /// Pin only this origin/status ref, without probing, reloading or reading current metadata.
    /// Admission is registered in the shared read-call owner before the returned future waits.
    ///
    /// # Errors
    /// Returns Cancelled for closing/replaced origin, Unavailable for unpublished refs,
    /// Superseded for released old material, or the original scope/call admission error.
    pub fn open_model_catalog_source_status_read(
        &self,
        reference: ProductSourceStatusRef,
        origin: ProductReadOrigin,
    ) -> impl Future<Output = Result<StudioModelCatalogSourceStatusRead>> + Send + 'static + use<>
    {
        let runtime = self.clone();
        self.read_calls.run(async move {
            if runtime.shutdown_committed() {
                return Err(cancelled().into());
            }
            let status = runtime
                .models_source
                .pin_source_status(&origin, reference)?;
            let identity = ProductReadScopeIdentity {
                scope_id: crate::studio::new_id("product-read"),
                owner_epoch: origin.owner_epoch,
                incarnation: origin.incarnation,
                version: ProductReadVersion::SourceStatus {
                    entry: reference.entry,
                    revision: reference.revision,
                },
            };
            let group = runtime.read_scopes.group(
                ReadScopeBudgetKey::Product {
                    resource: ProductResource::ModelCatalog,
                    scope: ProductScopeBinding::Unscoped,
                },
                identity.incarnation,
            );
            let (owner, material) = group.open(
                identity.scope_id.clone(),
                SourceStatusReadMaterial::new(status),
            )?;
            Ok(StudioModelCatalogSourceStatusRead {
                identity,
                owner,
                material,
                calls: runtime.read_calls.clone(),
            })
        })
    }
}

impl StudioModelCatalogSourceStatusRead {
    pub fn identity(&self) -> ProductReadScopeIdentity {
        self.identity.clone()
    }

    /// # Errors
    /// Returns Cancelled once the original scope/runtime has been sealed.
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.owner.ensure_open()
    }

    /// # Errors
    /// Returns the original typed metadata/budget/query error, without changing its source phase.
    pub fn header(
        &self,
    ) -> impl Future<Output = Result<ProductSourceStatusReadHeader>> + Send + 'static + use<> {
        self.query(SourceStatusReadMaterial::header)
    }

    /// # Errors
    /// Rejects wrong field IDs, non-UTF-8 boundaries, invalid maxBytes or original closing/errors.
    pub fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> impl Future<Output = Result<TextChunk>> + Send + 'static + use<> {
        self.query(move |material| material.text(field_id, offset, max_bytes))
    }

    pub fn request_close(&self) {
        self.owner.request_close();
    }
    pub async fn close(&self) -> FeedCloseReport {
        self.owner.close().await
    }
    pub async fn retry_close(&self) -> FeedCloseReport {
        self.owner.close().await
    }

    fn query<T, F>(&self, read: F) -> impl Future<Output = Result<T>> + Send + 'static + use<T, F>
    where
        T: Serialize + Send + 'static,
        F: FnOnce(&SourceStatusReadMaterial) -> Result<T, StudioError> + Send + 'static,
    {
        let material = self.material.clone();
        self.owner.run(&self.calls, async move {
            material.read(|material| {
                let value = read(material)?;
                require_budget(&value)?;
                Ok(value)
            })
        })
    }
}

impl Drop for StudioModelCatalogSourceStatusRead {
    fn drop(&mut self) {
        self.request_close();
        self.owner.release_if_joined();
    }
}

fn cancelled() -> StudioError {
    StudioError::new(
        pl_protocol::studio::StudioErrorCode::Cancelled,
        "Models source-status reads are closing",
        false,
    )
}
