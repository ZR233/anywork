use super::super::StudioRuntime;
use super::{
    material::{Root, UpdateReadMaterial},
    scope::UpdatesScope,
};
use anyhow::Result;
use pl_protocol::products::identity::{
    ProductReadOrigin, ProductReadScopeIdentity, ProductReadVersion,
};
use pl_protocol::products::read::updates::*;
use pl_protocol::products::references::*;
use pl_protocol::products::source::SourceStateErrorRead;
use pl_protocol::studio::{FeedCloseReport, StudioError, TextChunk};
use std::future::Future;

pub struct StudioUpdatesRead {
    scope: UpdatesScope<UpdateReadMaterial>,
}
pub struct StudioUpdateSummaryRead {
    scope: UpdatesScope<UpdateReadMaterial>,
}
pub struct StudioUpdateOperationRead {
    scope: UpdatesScope<UpdateReadMaterial>,
}
pub struct StudioUpdateErrorRead {
    scope: UpdatesScope<UpdateReadMaterial>,
}
pub struct StudioUpdateDetailsRead {
    scope: UpdatesScope<UpdateReadMaterial>,
}
impl StudioRuntime {
    pub fn open_updates_read(
        &self,
        reference: UpdatesReadRef,
        origin: ProductReadOrigin,
    ) -> impl Future<Output = Result<StudioUpdatesRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let material = runtime.updates_source.pin(&origin, reference)?;
            let scope = UpdatesScope::open(
                &runtime,
                origin,
                ProductReadVersion::Value {
                    entry: reference.entry,
                    revision: reference.revision,
                },
                "updates.read",
                UpdateReadMaterial::new(Root::Updates(material)),
            )?;
            Ok(StudioUpdatesRead { scope })
        })
    }
    pub fn open_summary(
        &self,
        reference: UpdateSummaryReadRef,
        origin: ProductReadOrigin,
    ) -> impl Future<Output = Result<StudioUpdateSummaryRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let material = runtime.updates_source.pin_summary(
                &origin,
                reference.entry,
                reference.revision,
                false,
            )?;
            let scope = UpdatesScope::open(
                &runtime,
                origin,
                ProductReadVersion::Value {
                    entry: reference.entry,
                    revision: reference.revision,
                },
                "updates.summary",
                UpdateReadMaterial::new(Root::Summary(material)),
            )?;
            Ok(StudioUpdateSummaryRead { scope })
        })
    }
    pub fn open_operation(
        &self,
        reference: UpdateOperationReadRef,
        origin: ProductReadOrigin,
    ) -> impl Future<Output = Result<StudioUpdateOperationRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let material = runtime.updates_source.pin_operation(&origin, reference)?;
            let scope = UpdatesScope::open(
                &runtime,
                origin,
                ProductReadVersion::Value {
                    entry: reference.entry,
                    revision: reference.revision,
                },
                "updates.operation",
                UpdateReadMaterial::new(Root::Operation(material)),
            )?;
            Ok(StudioUpdateOperationRead { scope })
        })
    }
    pub fn open_error(
        &self,
        reference: UpdateErrorReadRef,
        origin: ProductReadOrigin,
    ) -> impl Future<Output = Result<StudioUpdateErrorRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let material = runtime.updates_source.pin_error(&origin, reference)?;
            let scope = UpdatesScope::open(
                &runtime,
                origin,
                ProductReadVersion::Value {
                    entry: reference.entry,
                    revision: reference.revision,
                },
                "updates.error",
                UpdateReadMaterial::new(Root::Error(material)),
            )?;
            Ok(StudioUpdateErrorRead { scope })
        })
    }
    pub fn open_details(
        &self,
        reference: UpdateDetailsReadRef,
        origin: ProductReadOrigin,
    ) -> impl Future<Output = Result<StudioUpdateDetailsRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let material = runtime.updates_source.pin_summary(
                &origin,
                reference.entry,
                reference.revision,
                true,
            )?;
            let scope = UpdatesScope::open(
                &runtime,
                origin,
                ProductReadVersion::Value {
                    entry: reference.entry,
                    revision: reference.revision,
                },
                "updates.details",
                UpdateReadMaterial::new(Root::Summary(material)),
            )?;
            Ok(StudioUpdateDetailsRead { scope })
        })
    }
}
macro_rules! connection {
    ($read:ident, $header:ty, $method:ident) => {
        impl $read {
            pub fn identity(&self) -> ProductReadScopeIdentity {
                self.scope.identity()
            }
            pub fn ensure_open(&self) -> Result<(), StudioError> {
                self.scope.ensure_open()
            }
            pub fn header(&self) -> impl Future<Output = Result<$header>> + Send + 'static + use<> {
                self.scope.query(UpdateReadMaterial::$method)
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
    };
}
connection!(StudioUpdatesRead, UpdatesReadHeader, header);
connection!(StudioUpdateSummaryRead, UpdateSummaryRead, summary);
connection!(
    StudioUpdateOperationRead,
    UpdateOperationReadHeader,
    operation
);
connection!(StudioUpdateErrorRead, SourceStateErrorRead, error);
connection!(StudioUpdateDetailsRead, UpdateDetailsRead, details);
