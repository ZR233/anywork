use super::super::{
    StudioUpdateStateSnapshot,
    read_budget::{FieldTable, bounded_header, text_chunk},
};
use super::source::{ErrorMaterial, OperationMaterial, SummaryMaterial, UpdatesMaterial};
use pl_protocol::products::feed::updates::{UpdatesBrief, UpdatesHeader};
use pl_protocol::products::read::updates::*;
use pl_protocol::products::source::SourceStateErrorRead;
use pl_protocol::studio::{ReadText, StudioError, TextChunk};
use std::sync::Arc;

pub(super) enum Root {
    Updates(Arc<UpdatesMaterial>),
    Summary(Arc<SummaryMaterial>),
    Operation(Arc<OperationMaterial>),
    Error(Arc<ErrorMaterial>),
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum Text {
    Version,
    Notes,
    Url,
    Sha256,
    Signature,
    Operation,
    ErrorCode,
    ErrorMessage,
}
pub(super) struct UpdateReadMaterial {
    root: Root,
    texts: FieldTable<Text>,
}
impl UpdateReadMaterial {
    pub fn new(root: Root) -> Self {
        Self {
            root,
            texts: FieldTable::default(),
        }
    }
    fn update(&self) -> Result<&crate::StudioUpdate, StudioError> {
        match &self.root {
            Root::Summary(value) => Ok(&value.update),
            Root::Updates(value) => value.value.update().ok_or_else(wrong),
            _ => Err(wrong()),
        }
    }
    fn error_value(&self) -> Result<&pl_protocol::StateError, StudioError> {
        match &self.root {
            Root::Error(value) => Ok(&value.error),
            Root::Updates(value) => value
                .error
                .as_ref()
                .map(|value| &value.error)
                .ok_or_else(wrong),
            _ => Err(wrong()),
        }
    }
    fn text_source(&self, text: Text) -> Result<&str, StudioError> {
        Ok(match text {
            Text::Version => &self.update()?.version,
            Text::Notes => &self.update()?.notes_url,
            Text::Url => &self.update()?.installer.url,
            Text::Sha256 => &self.update()?.installer.sha256,
            Text::Signature => &self.update()?.installer.signature,
            Text::ErrorCode => &self.error_value()?.code,
            Text::ErrorMessage => &self.error_value()?.message,
            Text::Operation => match &self.root {
                Root::Operation(value) => &value.operation_id,
                Root::Updates(value) => &value.operation.as_ref().ok_or_else(wrong)?.operation_id,
                _ => return Err(wrong()),
            },
        })
    }
    fn read(&self, text: Text, inline: usize) -> Result<ReadText, StudioError> {
        self.texts.read(text, self.text_source(text)?, inline)
    }
    fn summary_read(&self, inline: usize) -> Result<UpdateSummaryRead, StudioError> {
        Ok(UpdateSummaryRead {
            version: self.read(Text::Version, inline)?,
            published_at: self.update()?.published_at,
            notes_url: self.read(Text::Notes, inline)?,
        })
    }
    fn details_read(&self, inline: usize) -> Result<UpdateDetailsRead, StudioError> {
        Ok(UpdateDetailsRead {
            summary: self.summary_read(inline)?,
            installer: UpdateAssetRead {
                url: self.read(Text::Url, inline)?,
                size: self.update()?.installer.size,
                sha256: self.read(Text::Sha256, inline)?,
                signature: self.read(Text::Signature, inline)?,
            },
        })
    }
    fn error_read(&self, inline: usize) -> Result<SourceStateErrorRead, StudioError> {
        Ok(SourceStateErrorRead {
            code: self.read(Text::ErrorCode, inline)?,
            message: self.read(Text::ErrorMessage, inline)?,
            retryable: self.error_value()?.retryable,
        })
    }
    pub fn summary(&self) -> Result<UpdateSummaryRead, StudioError> {
        bounded_header(|inline| self.summary_read(inline))
    }
    pub fn details(&self) -> Result<UpdateDetailsRead, StudioError> {
        bounded_header(|inline| self.details_read(inline))
    }
    pub fn error(&self) -> Result<SourceStateErrorRead, StudioError> {
        bounded_header(|inline| self.error_read(inline))
    }
    pub fn operation(&self) -> Result<UpdateOperationReadHeader, StudioError> {
        bounded_header(|inline| {
            Ok(UpdateOperationReadHeader {
                operation_id: self.read(Text::Operation, inline)?,
            })
        })
    }
    pub fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> Result<TextChunk, StudioError> {
        text_chunk(
            field_id,
            self.text_source(self.texts.field(field_id)?)?,
            offset,
            max_bytes,
        )
    }
    pub fn header(&self) -> Result<UpdatesReadHeader, StudioError> {
        let Root::Updates(material) = &self.root else {
            return Err(wrong());
        };
        let revision = material.value.revision();
        let at = material.value.updated_at();
        bounded_header(|inline| {
            Ok(match &material.value {
                StudioUpdateStateSnapshot::Disabled(_) => UpdatesReadHeader::Disabled {
                    revision,
                    updated_at: at,
                },
                StudioUpdateStateSnapshot::Idle(_) => UpdatesReadHeader::Idle {
                    revision,
                    updated_at: at,
                },
                StudioUpdateStateSnapshot::Checking(_) => UpdatesReadHeader::Checking {
                    revision,
                    started_at: at,
                    operation_id: self.read(Text::Operation, inline)?,
                },
                StudioUpdateStateSnapshot::UpToDate(_) => UpdatesReadHeader::UpToDate {
                    revision,
                    checked_at: at,
                },
                StudioUpdateStateSnapshot::Available(_) => UpdatesReadHeader::Available {
                    revision,
                    checked_at: at,
                    update: self.details_read(inline)?,
                },
                StudioUpdateStateSnapshot::Downloading(value) => UpdatesReadHeader::Downloading {
                    revision,
                    updated_at: at,
                    update: self.details_read(inline)?,
                    downloaded: value.downloaded(),
                    total: value.total(),
                },
                StudioUpdateStateSnapshot::Verifying(value) => UpdatesReadHeader::Verifying {
                    revision,
                    updated_at: at,
                    update: self.details_read(inline)?,
                    downloaded: value.downloaded(),
                    total: value.total(),
                },
                StudioUpdateStateSnapshot::Ready(_) => UpdatesReadHeader::Ready {
                    revision,
                    ready_at: at,
                    update: self.details_read(inline)?,
                },
                StudioUpdateStateSnapshot::InstallerLaunched(_) => {
                    UpdatesReadHeader::InstallerLaunched {
                        revision,
                        launched_at: at,
                        update: self.details_read(inline)?,
                    }
                }
                StudioUpdateStateSnapshot::CheckFailed(_) => UpdatesReadHeader::CheckFailed {
                    revision,
                    failed_at: at,
                    error: self.error_read(inline)?,
                },
                StudioUpdateStateSnapshot::InstallFailed(_) => UpdatesReadHeader::InstallFailed {
                    revision,
                    failed_at: at,
                    update: self.details_read(inline)?,
                    error: self.error_read(inline)?,
                },
            })
        })
    }
}
pub(super) fn feed_header(material: &UpdatesMaterial) -> UpdatesHeader {
    let revision = material.value.revision();
    let at = material.value.updated_at();
    let brief = match &material.value {
        StudioUpdateStateSnapshot::Disabled(_) => UpdatesBrief::Disabled {
            revision,
            updated_at: at,
        },
        StudioUpdateStateSnapshot::Idle(_) => UpdatesBrief::Idle {
            revision,
            updated_at: at,
        },
        StudioUpdateStateSnapshot::Checking(_) => UpdatesBrief::Checking {
            revision,
            started_at: at,
        },
        StudioUpdateStateSnapshot::UpToDate(_) => UpdatesBrief::UpToDate {
            revision,
            checked_at: at,
        },
        StudioUpdateStateSnapshot::Available(_) => UpdatesBrief::Available {
            revision,
            checked_at: at,
        },
        StudioUpdateStateSnapshot::Downloading(value) => UpdatesBrief::Downloading {
            revision,
            updated_at: at,
            downloaded: value.downloaded(),
            total: value.total(),
        },
        StudioUpdateStateSnapshot::Verifying(value) => UpdatesBrief::Verifying {
            revision,
            updated_at: at,
            downloaded: value.downloaded(),
            total: value.total(),
        },
        StudioUpdateStateSnapshot::Ready(_) => UpdatesBrief::Ready {
            revision,
            ready_at: at,
        },
        StudioUpdateStateSnapshot::InstallerLaunched(_) => UpdatesBrief::InstallerLaunched {
            revision,
            launched_at: at,
        },
        StudioUpdateStateSnapshot::CheckFailed(value) => UpdatesBrief::CheckFailed {
            revision,
            failed_at: at,
            retryable: value.error().retryable,
        },
        StudioUpdateStateSnapshot::InstallFailed(value) => UpdatesBrief::InstallFailed {
            revision,
            failed_at: at,
            retryable: value.error().retryable,
        },
    };
    UpdatesHeader {
        reference: material.reference,
        brief,
        summary: material.summary.as_ref().map(|value| value.reference),
        details: material.summary.as_ref().map(|value| value.details),
        operation: material.operation.as_ref().map(|value| value.reference),
        error: material.error.as_ref().map(|value| value.reference),
    }
}
fn wrong() -> StudioError {
    StudioError::invalid_argument("Unknown text field or variant in this Updates scope")
}
