//! Dispatch only between the two original Recovery read capabilities, never a material mirror.
use futures::{FutureExt, future::BoxFuture};
use pl_protocol::products::identity::{
    ProductReadOrigin, ProductReadScopeIdentity, ProductReadVersion, ProductSourceStatusRef,
};
use pl_protocol::products::references::RecoveryReadRef;
use pl_protocol::studio::{FeedCloseReport, StudioError, StudioErrorCode};
use pl_studio_runtime::{
    StudioRuntime,
    recovery::{StudioRecoveryRead, StudioRecoverySourceStatusRead},
};

use super::tasks;

pub(super) enum OpenReadKind {
    Value(RecoveryReadRef),
    SourceStatus(ProductSourceStatusRef),
}

impl OpenReadKind {
    pub(super) fn version(&self) -> ProductReadVersion {
        match self {
            Self::Value(reference) => ProductReadVersion::Value {
                entry: reference.entry,
                revision: reference.revision,
            },
            Self::SourceStatus(reference) => ProductReadVersion::SourceStatus {
                entry: reference.entry,
                revision: reference.revision,
            },
        }
    }

    // Call the native method now: it synchronously registers its original ReadCalls worker.
    pub(super) fn start(
        self,
        runtime: &StudioRuntime,
        origin: ProductReadOrigin,
    ) -> BoxFuture<'static, anyhow::Result<NativeRead>> {
        match self {
            Self::Value(reference) => runtime
                .open_recovery_read(reference, origin)
                .map(|result| result.map(NativeRead::Value))
                .boxed(),
            Self::SourceStatus(reference) => runtime
                .open_recovery_source_status_read(reference, origin)
                .map(|result| result.map(NativeRead::SourceStatus))
                .boxed(),
        }
    }
}

pub(super) enum NativeRead {
    Value(StudioRecoveryRead),
    SourceStatus(StudioRecoverySourceStatusRead),
}

impl NativeRead {
    pub(super) fn value(&self) -> Result<&StudioRecoveryRead, StudioError> {
        match self {
            Self::Value(source) => Ok(source),
            Self::SourceStatus(_) => Err(tasks::wrong_scope()),
        }
    }

    pub(super) fn status(&self) -> Result<&StudioRecoverySourceStatusRead, StudioError> {
        match self {
            Self::SourceStatus(source) => Ok(source),
            Self::Value(_) => Err(tasks::wrong_scope()),
        }
    }

    pub(super) fn identity(&self) -> ProductReadScopeIdentity {
        match self {
            Self::Value(source) => source.identity(),
            Self::SourceStatus(source) => source.identity(),
        }
    }

    pub(super) fn validate(
        &self,
        origin: &ProductReadOrigin,
        version: ProductReadVersion,
    ) -> Result<(), StudioError> {
        let identity = self.identity();
        if identity.owner_epoch != origin.owner_epoch
            || identity.incarnation != origin.incarnation
            || identity.version != version
        {
            return Err(StudioError::new(
                StudioErrorCode::Protocol,
                "Recovery read identity differs from the original feed origin and reference",
                false,
            ));
        }
        self.ensure_open()
    }

    pub(super) fn ensure_open(&self) -> Result<(), StudioError> {
        match self {
            Self::Value(source) => source.ensure_open(),
            Self::SourceStatus(source) => source.ensure_open(),
        }
    }

    pub(super) fn request_close(&self) {
        match self {
            Self::Value(source) => source.request_close(),
            Self::SourceStatus(source) => source.request_close(),
        }
    }

    pub(super) async fn close(&self, retry: bool) -> FeedCloseReport {
        match (self, retry) {
            (Self::Value(source), false) => source.close().await,
            (Self::Value(source), true) => source.retry_close().await,
            (Self::SourceStatus(source), false) => source.close().await,
            (Self::SourceStatus(source), true) => source.retry_close().await,
        }
    }
}
