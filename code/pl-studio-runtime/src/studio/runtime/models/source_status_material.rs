//! Complete metadata comes from the original S1 status pin; field IDs locate borrowed strings.
use std::sync::Arc;

use pl_protocol::ObservedResource;
use pl_protocol::products::source::{ProductSourceStatusReadHeader, SourceStateErrorRead};
use pl_protocol::studio::{ReadText, StudioError, TextChunk};

use super::super::read_budget::{FieldTable, bounded_header, text_chunk};
use super::material::wrong_field;
use crate::config::ModelSourceStatusMaterial;

#[derive(Clone, Copy, PartialEq, Eq)]
enum SourceText {
    OperationId,
    ErrorCode,
    ErrorMessage,
}

pub(super) struct SourceStatusReadMaterial {
    status: Arc<ModelSourceStatusMaterial>,
    texts: FieldTable<SourceText>,
}

impl SourceStatusReadMaterial {
    pub(super) fn new(status: Arc<ModelSourceStatusMaterial>) -> Self {
        Self {
            status,
            texts: FieldTable::default(),
        }
    }

    pub(super) fn header(&self) -> Result<ProductSourceStatusReadHeader, StudioError> {
        bounded_header(|inline| {
            let text = |field| self.read(field, inline);
            let error = |retryable| -> Result<SourceStateErrorRead, StudioError> {
                Ok(SourceStateErrorRead {
                    code: text(SourceText::ErrorCode)?,
                    message: text(SourceText::ErrorMessage)?,
                    retryable,
                })
            };
            Ok(match self.status.metadata() {
                ObservedResource::Uninitialized(state) => {
                    ProductSourceStatusReadHeader::Uninitialized {
                        revision: state.revision(),
                        updated_at: state.updated_at(),
                    }
                }
                ObservedResource::Loading(state) => ProductSourceStatusReadHeader::Loading {
                    revision: state.revision(),
                    operation: state.operation(),
                    operation_id: text(SourceText::OperationId)?,
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
                    operation_id: text(SourceText::OperationId)?,
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

    pub(super) fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> Result<TextChunk, StudioError> {
        let field = self.texts.field(field_id)?;
        text_chunk(field_id, self.text_source(field)?, offset, max_bytes)
    }

    fn read(&self, field: SourceText, inline: usize) -> Result<ReadText, StudioError> {
        self.texts.read(field, self.text_source(field)?, inline)
    }

    fn text_source(&self, field: SourceText) -> Result<&str, StudioError> {
        match field {
            SourceText::OperationId => match self.status.metadata() {
                ObservedResource::Loading(state) => Ok(state.operation_id()),
                ObservedResource::Refreshing(state) => Ok(state.operation_id()),
                _ => Err(wrong_field()),
            },
            SourceText::ErrorCode | SourceText::ErrorMessage => {
                let error = match self.status.metadata() {
                    ObservedResource::Degraded(state) => state.error(),
                    ObservedResource::Failed(state) => state.error(),
                    _ => return Err(wrong_field()),
                };
                Ok(match field {
                    SourceText::ErrorCode => &error.code,
                    SourceText::ErrorMessage => &error.message,
                    SourceText::OperationId => return Err(wrong_field()),
                })
            }
        }
    }
}
