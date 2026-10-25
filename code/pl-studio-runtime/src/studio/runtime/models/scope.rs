use std::future::Future;
use std::sync::Arc;

use anyhow::Result;
use pl_protocol::products::identity::{
    ProductReadOrigin, ProductReadScopeIdentity, ProductReadVersion, ProductResource,
};
use pl_protocol::products::references::{AccountTemplatesReadRef, ModelCatalogReadRef};
use pl_protocol::studio::{FeedCloseReport, StudioError, StudioErrorCode};
use serde::Serialize;

use super::super::StudioRuntime;
use super::super::read_budget::require_budget;
use super::super::read_calls::ReadCalls;
use super::super::read_scopes::{
    PinnedMaterial, ProductScopeBinding, ReadScopeBudgetKey, ReadScopeOwner,
};
use super::material::{ModelReadMaterial, ModelRoot};

pub(super) struct ModelReadScope {
    identity: ProductReadScopeIdentity,
    owner: Arc<ReadScopeOwner>,
    material: Arc<PinnedMaterial<ModelReadMaterial>>,
    calls: ReadCalls,
}

impl ModelReadScope {
    pub(super) fn open(
        runtime: &StudioRuntime,
        origin: ProductReadOrigin,
        version: ProductReadVersion,
        resource: ProductResource,
        material: ModelReadMaterial,
    ) -> Result<Self> {
        let identity = ProductReadScopeIdentity {
            scope_id: crate::studio::new_id("product-read"),
            owner_epoch: origin.owner_epoch,
            incarnation: origin.incarnation,
            version,
        };
        let group = runtime.read_scopes.group(
            ReadScopeBudgetKey::Product {
                resource,
                scope: ProductScopeBinding::Unscoped,
            },
            identity.incarnation,
        );
        let (owner, material) = group.open(identity.scope_id.clone(), material)?;
        Ok(Self {
            identity,
            owner,
            material,
            calls: runtime.read_calls.clone(),
        })
    }

    pub(super) fn identity(&self) -> ProductReadScopeIdentity {
        self.identity.clone()
    }
    pub(super) fn ensure_open(&self) -> Result<(), StudioError> {
        self.owner.ensure_open()
    }

    /// The concrete actual query is in the same shared 64-call registry before this returns.
    pub(super) fn query<T, F>(
        &self,
        read: F,
    ) -> impl Future<Output = Result<T>> + Send + 'static + use<T, F>
    where
        T: Serialize + Send + 'static,
        F: FnOnce(&ModelReadMaterial) -> Result<T, StudioError> + Send + 'static,
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

    pub(super) fn request_close(&self) {
        self.owner.request_close();
    }
    pub(super) async fn close(&self) -> FeedCloseReport {
        self.owner.close().await
    }
}

impl Drop for ModelReadScope {
    fn drop(&mut self) {
        self.request_close();
        self.owner.release_if_joined();
    }
}

/// One immutable Catalog value, its original field/list IDs and actual shared query tasks.
pub struct StudioModelCatalogRead {
    pub(super) scope: ModelReadScope,
}

/// Builtin templates have their own original product origin and no fabricated source-status API.
pub struct StudioAccountTemplatesRead {
    pub(super) scope: ModelReadScope,
}

impl StudioRuntime {
    /// Pins only the supplied original Catalog origin/ref; subsequent source updates do not
    /// change the value or field IDs. Opening is registered before the returned future can wait.
    ///
    /// # Errors
    /// Cancelled for closing/replaced origins, Unavailable for unpublished refs, Superseded for
    /// released old material, and Overloaded for the original scope/call admission limits.
    pub fn open_model_catalog_read(
        &self,
        reference: ModelCatalogReadRef,
        origin: ProductReadOrigin,
    ) -> impl Future<Output = Result<StudioModelCatalogRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            if runtime.shutdown_committed() {
                return Err(cancelled().into());
            }
            let material = runtime.models_source.pin(&origin, reference)?;
            let scope = ModelReadScope::open(
                &runtime,
                origin,
                ProductReadVersion::Value {
                    entry: reference.entry,
                    revision: reference.revision,
                },
                ProductResource::ModelCatalog,
                ModelReadMaterial::new(ModelRoot::Catalog(material)),
            )?;
            Ok(StudioModelCatalogRead { scope })
        })
    }

    /// Pins the builtin catalog captured by this runtime, not another load or current Config.
    ///
    /// # Errors
    /// Returns Cancelled for closing/replaced origins, Unavailable for an unknown immutable ref,
    /// or the shared scope/call admission error. No source-status scope is invented for templates.
    pub fn open_account_templates_read(
        &self,
        reference: AccountTemplatesReadRef,
        origin: ProductReadOrigin,
    ) -> impl Future<Output = Result<StudioAccountTemplatesRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            if runtime.shutdown_committed() {
                return Err(cancelled().into());
            }
            let material = runtime.templates_source.pin(&origin, reference)?;
            let scope = ModelReadScope::open(
                &runtime,
                origin,
                ProductReadVersion::Value {
                    entry: reference.entry,
                    revision: reference.revision,
                },
                ProductResource::AccountTemplates,
                ModelReadMaterial::new(ModelRoot::Templates(material)),
            )?;
            Ok(StudioAccountTemplatesRead { scope })
        })
    }
}

fn cancelled() -> StudioError {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "Studio Models reads are closing",
        false,
    )
}
