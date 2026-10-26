use std::future::Future;

use anyhow::Result;
use pl_protocol::products::identity::{ProductReadVersion, ProductResource};
use pl_protocol::studio::{StudioError, StudioErrorCode};

use super::super::StudioRuntime;
use super::DelegationModelReadTarget;
use super::delegation_material::DelegationMaterial;
use super::material::ModelReadMaterial;
use super::scope::ModelReadScope;

/// One verified Configuration/catalog pair and this opening's immutable local observations.
/// Queries, pins, scope capacity and shutdown are owned by the original Models read lifecycle.
pub struct StudioDelegationModelRead {
    pub(super) scope: ModelReadScope,
    pub(super) target: DelegationModelReadTarget,
}

impl StudioRuntime {
    /// Verify and pin the complete Rust-issued pair, then capture one local detail window.
    /// Opening is registered by ReadCalls before this method returns a future to its caller;
    /// abandoning that future does not cancel the owned capture or orphan a late scope.
    ///
    /// # Errors
    /// Returns original pair/origin/expiry, account/model, store/decoding or admission errors.
    /// Qualification rejection is available=false material, not a failed opening or fake source.
    pub fn open_delegation_model_read(
        &self,
        target: DelegationModelReadTarget,
    ) -> impl Future<Output = Result<StudioDelegationModelRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            if runtime.shutdown_committed() {
                return Err(cancelled().into());
            }
            // pin_pair verifies both original targets, their references and the full stamp.
            // Its strong pair owns Configuration, Models and the original metadata publication.
            let pair = runtime.configuration_source.pin_pair(&target.sources)?;
            let material = DelegationMaterial::capture(&runtime, pair, target.clone()).await?;
            if runtime.shutdown_committed() {
                return Err(cancelled().into());
            }
            runtime.configuration_source.ensure_open()?;
            let catalog = &target.sources.catalog;
            let scope = ModelReadScope::open(
                &runtime,
                catalog.origin.clone(),
                ProductReadVersion::Value {
                    entry: catalog.reference.entry,
                    revision: catalog.reference.revision,
                },
                ProductResource::ModelCatalog,
                ModelReadMaterial::for_delegation(material),
            )?;
            // A fence during capture/admission cannot publish a healthy late handle. If this
            // rejects, the already registered scope's existing Drop seals/releases after join.
            runtime.configuration_source.ensure_open()?;
            if runtime.shutdown_committed() {
                return Err(cancelled().into());
            }
            scope.ensure_open()?;
            Ok(StudioDelegationModelRead { scope, target })
        })
    }
}

fn cancelled() -> StudioError {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "Exact model reads are closing",
        false,
    )
}
