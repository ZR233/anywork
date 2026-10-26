//! Recovery reads share the original runtime 8-scope/64-call owners.
use super::super::read_budget::require_budget;
use super::super::read_scopes::{
    PinnedMaterial, ProductScopeBinding, ReadScopeBudgetKey, ReadScopeOwner,
};
use super::super::{StudioRuntime, read_calls::ReadCalls};
use anyhow::Result;
use pl_protocol::products::identity::{
    ProductReadOrigin, ProductReadScopeIdentity, ProductReadVersion, ProductResource,
};
use pl_protocol::studio::{FeedCloseReport, StudioError};
use serde::Serialize;
use std::{future::Future, sync::Arc};

pub(super) struct RecoveryReadScope<M: Send + Sync + 'static> {
    identity: ProductReadScopeIdentity,
    owner: Arc<ReadScopeOwner>,
    material: Arc<PinnedMaterial<M>>,
    calls: ReadCalls,
}
impl<M: Send + Sync + 'static> RecoveryReadScope<M> {
    pub(super) fn open(
        runtime: &StudioRuntime,
        origin: ProductReadOrigin,
        version: ProductReadVersion,
        material: M,
    ) -> Result<Self> {
        let identity = ProductReadScopeIdentity {
            scope_id: crate::studio::new_id("recovery-read"),
            owner_epoch: origin.owner_epoch,
            incarnation: origin.incarnation,
            version,
        };
        let group = runtime.read_scopes.group(
            ReadScopeBudgetKey::Product {
                resource: ProductResource::Recovery,
                scope: ProductScopeBinding::Named("recovery.read"),
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
    pub(super) fn query<T, F>(
        &self,
        read: F,
    ) -> impl Future<Output = Result<T>> + Send + 'static + use<M, T, F>
    where
        T: Serialize + Send + 'static,
        F: FnOnce(&M) -> Result<T, StudioError> + Send + 'static,
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
impl<M: Send + Sync + 'static> Drop for RecoveryReadScope<M> {
    fn drop(&mut self) {
        self.request_close();
        self.owner.release_if_joined();
    }
}
