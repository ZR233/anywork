use super::super::read_budget::{FieldTable, bounded_header, text_chunk};
use super::source::PersistenceSnapshot;
use crate::PersistenceState;
use pl_protocol::products::{read::persistence::*, source::SourceStateErrorRead};
use pl_protocol::studio::{StudioError, TextChunk};
use std::sync::Arc;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Text {
    Code,
    Message,
}
pub(super) struct PersistenceMaterial {
    pub source: Arc<PersistenceSnapshot>,
    texts: FieldTable<Text>,
}
impl PersistenceMaterial {
    pub fn new(source: Arc<PersistenceSnapshot>) -> Self {
        Self {
            source,
            texts: FieldTable::default(),
        }
    }
    pub fn header(&self) -> Result<PersistenceReadHeader, StudioError> {
        bounded_header(|inline| {
            let error = |value: &pl_protocol::StateError| -> Result<_, StudioError> {
                Ok(SourceStateErrorRead {
                    code: self.texts.read(Text::Code, &value.code, inline)?,
                    message: self.texts.read(Text::Message, &value.message, inline)?,
                    retryable: value.retryable,
                })
            };
            let state = match &self.source.value.state {
                PersistenceState::Ready(s) => PersistenceStatusRead::Ready {
                    pending_commits: s.pending_commits,
                },
                PersistenceState::Flushing(s) => PersistenceStatusRead::Flushing {
                    pending_commits: s.pending_commits,
                    oldest_pending_revision: s.oldest_pending_revision,
                },
                PersistenceState::Degraded(s) => PersistenceStatusRead::Degraded {
                    pending_commits: s.pending_commits,
                    oldest_pending_revision: s.oldest_pending_revision,
                    first_failed_at: s.first_failed_at,
                    error: error(&s.error)?,
                },
                PersistenceState::Recovering(s) => PersistenceStatusRead::Recovering {
                    pending_commits: s.pending_commits,
                    oldest_pending_revision: s.oldest_pending_revision,
                    first_failed_at: s.first_failed_at,
                },
                PersistenceState::Blocked(s) => PersistenceStatusRead::Blocked {
                    pending_commits: s.pending_commits,
                    oldest_pending_revision: s.oldest_pending_revision,
                    first_failed_at: s.first_failed_at,
                    error: error(&s.error)?,
                },
            };
            Ok(PersistenceReadHeader {
                revision: self.source.value.revision,
                state,
            })
        })
    }
    pub fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> Result<TextChunk, StudioError> {
        let error = match &self.source.value.state {
            PersistenceState::Degraded(s) => &s.error,
            PersistenceState::Blocked(s) => &s.error,
            _ => {
                return Err(StudioError::invalid_argument(
                    "This Persistence publication has no error text",
                ));
            }
        };
        let source = match self.texts.field(field_id)? {
            Text::Code => &error.code,
            Text::Message => &error.message,
        };
        text_chunk(field_id, source, offset, max_bytes)
    }
}
