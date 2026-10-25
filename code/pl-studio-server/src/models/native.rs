//! Closed native read dispatch. No shared payload, recapture or policy lives in HTTP.
use super::tasks;
use pl_protocol::{
    products::{
        identity::{
            ProductReadOrigin, ProductReadScopeIdentity, ProductReadVersion, ProductSourceStatusRef,
        },
        read::delegation_models::DelegationModelReadTarget,
        references::ModelCatalogReadRef,
    },
    studio::{FeedCloseReport, StudioError},
};
use pl_studio_runtime::{
    StudioRuntime,
    models::{
        StudioDelegationModelRead, StudioModelCatalogRead, StudioModelCatalogSourceStatusRead,
    },
};
use std::future::Future;

#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum ReadKind {
    Catalog,
    SourceStatus,
    Delegation,
}
#[derive(Clone, Copy)]
pub(super) enum Capability {
    Kind(ReadKind),
    Fields,
    Text,
}
impl Capability {
    pub(super) fn accepts(self, kind: ReadKind) -> bool {
        match self {
            Self::Kind(expected) => expected == kind,
            Self::Fields => matches!(kind, ReadKind::Catalog | ReadKind::Delegation),
            Self::Text => true,
        }
    }
}
pub(super) enum OpenRead {
    Catalog {
        reference: ModelCatalogReadRef,
        origin: ProductReadOrigin,
    },
    SourceStatus {
        reference: ProductSourceStatusRef,
        origin: ProductReadOrigin,
    },
    Delegation(DelegationModelReadTarget),
}
impl OpenRead {
    pub(super) fn kind(&self) -> ReadKind {
        match self {
            Self::Catalog { .. } => ReadKind::Catalog,
            Self::SourceStatus { .. } => ReadKind::SourceStatus,
            Self::Delegation(_) => ReadKind::Delegation,
        }
    }
    // Calling the concrete opener here synchronously installs its original ReadCalls task.
    // The boxed future only erases the three future types, not ownership, payload or budgets.
    pub(super) fn start(
        &self,
        runtime: &StudioRuntime,
    ) -> std::pin::Pin<Box<dyn Future<Output = anyhow::Result<NativeRead>> + Send>> {
        match self {
            Self::Catalog { reference, origin } => {
                let opened = runtime.open_model_catalog_read(*reference, origin.clone());
                Box::pin(async move { Ok(NativeRead::Catalog(opened.await?)) })
            }
            Self::SourceStatus { reference, origin } => {
                let opened =
                    runtime.open_model_catalog_source_status_read(*reference, origin.clone());
                Box::pin(async move { Ok(NativeRead::SourceStatus(opened.await?)) })
            }
            Self::Delegation(target) => {
                let opened = runtime.open_delegation_model_read(target.clone());
                Box::pin(async move { Ok(NativeRead::Delegation(opened.await?)) })
            }
        }
    }
    pub(super) fn validate(&self, source: &NativeRead) -> Result<(), StudioError> {
        let identity = source.identity();
        let (origin, version) = match self {
            Self::Catalog { origin, reference } => (
                origin,
                ProductReadVersion::Value {
                    entry: reference.entry,
                    revision: reference.revision,
                },
            ),
            Self::SourceStatus { origin, reference } => (
                origin,
                ProductReadVersion::SourceStatus {
                    entry: reference.entry,
                    revision: reference.revision,
                },
            ),
            Self::Delegation(target) => {
                if source.target().as_ref() != Some(target) {
                    return Err(protocol());
                }
                (
                    &target.sources.catalog.origin,
                    ProductReadVersion::Value {
                        entry: target.sources.catalog.reference.entry,
                        revision: target.sources.catalog.reference.revision,
                    },
                )
            }
        };
        if identity.scope_id.is_empty()
            || identity.owner_epoch != origin.owner_epoch
            || identity.incarnation != origin.incarnation
            || identity.version != version
        {
            return Err(protocol());
        }
        source.ensure_open()
    }
}
pub(super) enum NativeRead {
    Catalog(StudioModelCatalogRead),
    SourceStatus(StudioModelCatalogSourceStatusRead),
    Delegation(StudioDelegationModelRead),
}
impl NativeRead {
    pub(super) fn identity(&self) -> ProductReadScopeIdentity {
        match self {
            Self::Catalog(v) => v.identity(),
            Self::SourceStatus(v) => v.identity(),
            Self::Delegation(v) => v.identity(),
        }
    }
    pub(super) fn target(&self) -> Option<DelegationModelReadTarget> {
        match self {
            Self::Delegation(v) => Some(v.target()),
            Self::Catalog(_) | Self::SourceStatus(_) => None,
        }
    }
    pub(super) fn ensure_open(&self) -> Result<(), StudioError> {
        match self {
            Self::Catalog(v) => v.ensure_open(),
            Self::SourceStatus(v) => v.ensure_open(),
            Self::Delegation(v) => v.ensure_open(),
        }
    }
    pub(super) fn request_close(&self) {
        match self {
            Self::Catalog(v) => v.request_close(),
            Self::SourceStatus(v) => v.request_close(),
            Self::Delegation(v) => v.request_close(),
        }
    }
    pub(super) async fn close(&self, retry: bool) -> FeedCloseReport {
        match self {
            Self::Catalog(v) => {
                if retry {
                    v.retry_close().await
                } else {
                    v.close().await
                }
            }
            Self::SourceStatus(v) => {
                if retry {
                    v.retry_close().await
                } else {
                    v.close().await
                }
            }
            Self::Delegation(v) => {
                if retry {
                    v.retry_close().await
                } else {
                    v.close().await
                }
            }
        }
    }
    pub(super) fn catalog(&self) -> Result<&StudioModelCatalogRead, StudioError> {
        if let Self::Catalog(v) = self {
            Ok(v)
        } else {
            Err(tasks::wrong())
        }
    }
    pub(super) fn status(&self) -> Result<&StudioModelCatalogSourceStatusRead, StudioError> {
        if let Self::SourceStatus(v) = self {
            Ok(v)
        } else {
            Err(tasks::wrong())
        }
    }
    pub(super) fn delegation(&self) -> Result<&StudioDelegationModelRead, StudioError> {
        if let Self::Delegation(v) = self {
            Ok(v)
        } else {
            Err(tasks::wrong())
        }
    }
}
fn protocol() -> StudioError {
    StudioError::new(
        pl_protocol::studio::StudioErrorCode::Protocol,
        "The native Models read returned a different original identity or target",
        false,
    )
}
