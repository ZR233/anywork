use std::future::Future;
use std::sync::Arc;

use anyhow::Result;
use pl_protocol::ObservedResource;
use pl_protocol::products::identity::ProductReadVersion;
use pl_protocol::products::source::{ObservedBrief, ObservedHeader, SourceStateErrorRead};

use super::super::StudioRuntime;
use super::super::read_budget::{FieldTable, bounded_header, text_chunk};
use super::scope::WorkspaceReadScope;
use super::source::WorkspaceStatus;
use super::*;

#[derive(Clone, Copy, PartialEq, Eq)]
enum SourceText {
    Operation,
    Code,
    Message,
}
struct StatusMaterial {
    status: Arc<WorkspaceStatus>,
    texts: FieldTable<SourceText>,
}
pub struct StudioWorkspaceSourceStatusRead {
    scope: WorkspaceReadScope<StatusMaterial>,
}

impl StudioRuntime {
    pub fn open_workspace_source_status_read(
        &self,
        reference: ProductSourceStatusRef,
        origin: ProductReadOrigin,
    ) -> impl Future<Output = Result<StudioWorkspaceSourceStatusRead>> + Send + 'static + use<>
    {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let status = runtime.workspace_source.pin_status(&origin, reference)?;
            let binding = status.binding.clone();
            let scope = WorkspaceReadScope::open(
                &runtime,
                origin,
                ProductReadVersion::SourceStatus {
                    entry: reference.entry,
                    revision: reference.revision,
                },
                &binding,
                StatusMaterial {
                    status,
                    texts: FieldTable::default(),
                },
            )?;
            Ok(StudioWorkspaceSourceStatusRead { scope })
        })
    }
}

impl StudioWorkspaceSourceStatusRead {
    pub fn identity(&self) -> ProductReadScopeIdentity {
        self.scope.identity()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.scope.ensure_open()
    }
    pub fn header(
        &self,
    ) -> impl Future<Output = Result<ProductSourceStatusReadHeader>> + Send + 'static + use<> {
        self.scope.query(StatusMaterial::header)
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

pub(super) fn observed(status: &WorkspaceStatus) -> ObservedHeader {
    let brief = match &status.metadata {
        ObservedResource::Uninitialized(state) => ObservedBrief::Uninitialized {
            revision: state.revision(),
            updated_at: state.updated_at(),
        },
        ObservedResource::Loading(state) => ObservedBrief::Loading {
            revision: state.revision(),
            started_at: state.started_at(),
        },
        ObservedResource::Ready(state) => ObservedBrief::Ready {
            revision: state.revision(),
            updated_at: state.updated_at(),
            last_checked_at: state.last_checked_at(),
        },
        ObservedResource::Refreshing(state) => ObservedBrief::Refreshing {
            revision: state.revision(),
            started_at: state.started_at(),
            last_checked_at: state.last_checked_at(),
        },
        ObservedResource::Stale(state) => ObservedBrief::Stale {
            revision: state.revision(),
            stale_at: state.stale_at(),
            last_checked_at: state.last_checked_at(),
        },
        ObservedResource::Degraded(state) => ObservedBrief::Degraded {
            revision: state.revision(),
            failed_at: state.failed_at(),
            last_checked_at: state.last_checked_at(),
            retryable: state.error().retryable,
        },
        ObservedResource::Failed(state) => ObservedBrief::Failed {
            revision: state.revision(),
            failed_at: state.failed_at(),
            retryable: state.error().retryable,
        },
        ObservedResource::Stopped(state) => ObservedBrief::Stopped {
            revision: state.revision(),
            stopped_at: state.stopped_at(),
        },
    };
    ObservedHeader {
        brief,
        status: status.reference,
    }
}

impl StatusMaterial {
    fn header(&self) -> Result<ProductSourceStatusReadHeader, StudioError> {
        bounded_header(|inline| {
            let text = |field| self.texts.read(field, self.source(field)?, inline);
            let error = |retryable| -> Result<SourceStateErrorRead, StudioError> {
                Ok(SourceStateErrorRead {
                    code: text(SourceText::Code)?,
                    message: text(SourceText::Message)?,
                    retryable,
                })
            };
            Ok(match &self.status.metadata {
                ObservedResource::Uninitialized(state) => {
                    ProductSourceStatusReadHeader::Uninitialized {
                        revision: state.revision(),
                        updated_at: state.updated_at(),
                    }
                }
                ObservedResource::Loading(state) => ProductSourceStatusReadHeader::Loading {
                    revision: state.revision(),
                    operation: state.operation(),
                    operation_id: text(SourceText::Operation)?,
                    started_at: state.started_at(),
                },
                ObservedResource::Ready(state) => ProductSourceStatusReadHeader::Ready {
                    revision: state.revision(),
                    updated_at: state.updated_at(),
                    last_checked_at: state.last_checked_at(),
                },
                ObservedResource::Refreshing(state) => ProductSourceStatusReadHeader::Refreshing {
                    revision: state.revision(),
                    operation: state.operation(),
                    operation_id: text(SourceText::Operation)?,
                    started_at: state.started_at(),
                    last_checked_at: state.last_checked_at(),
                },
                ObservedResource::Stale(state) => ProductSourceStatusReadHeader::Stale {
                    revision: state.revision(),
                    stale_at: state.stale_at(),
                    last_checked_at: state.last_checked_at(),
                },
                ObservedResource::Degraded(state) => ProductSourceStatusReadHeader::Degraded {
                    revision: state.revision(),
                    failed_at: state.failed_at(),
                    last_checked_at: state.last_checked_at(),
                    operation: state.operation(),
                    error: error(state.error().retryable)?,
                },
                ObservedResource::Failed(state) => ProductSourceStatusReadHeader::Failed {
                    revision: state.revision(),
                    failed_at: state.failed_at(),
                    operation: state.operation(),
                    error: error(state.error().retryable)?,
                },
                ObservedResource::Stopped(state) => ProductSourceStatusReadHeader::Stopped {
                    revision: state.revision(),
                    stopped_at: state.stopped_at(),
                },
            })
        })
    }
    fn source(&self, field: SourceText) -> Result<&str, StudioError> {
        match field {
            SourceText::Operation => match &self.status.metadata {
                ObservedResource::Loading(state) => Ok(state.operation_id()),
                ObservedResource::Refreshing(state) => Ok(state.operation_id()),
                _ => Err(super::wrong_field()),
            },
            SourceText::Code | SourceText::Message => {
                let error = match &self.status.metadata {
                    ObservedResource::Degraded(state) => state.error(),
                    ObservedResource::Failed(state) => state.error(),
                    _ => return Err(super::wrong_field()),
                };
                if field == SourceText::Code {
                    Ok(&error.code)
                } else {
                    Ok(&error.message)
                }
            }
        }
    }
    fn text(&self, field_id: u64, offset: u64, max_bytes: u32) -> Result<TextChunk, StudioError> {
        text_chunk(
            field_id,
            self.source(self.texts.field(field_id)?)?,
            offset,
            max_bytes,
        )
    }
}
