use super::super::read_budget::{FieldTable, bounded_header, count, require_budget, text_chunk};
use super::source::PersistenceQueueSnapshot;
use pl_protocol::products::{
    identity::ProductEntityRef,
    read::{persistence::*, primitives::TypedListRef},
};
use pl_protocol::studio::{ReadText, StudioError, TextChunk};
use std::sync::Arc;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Text {
    Error,
    ThreadId(usize),
    ThreadError(usize),
}
pub(super) struct QueueMaterial {
    source: Arc<PersistenceQueueSnapshot>,
    texts: FieldTable<Text>,
    lists: FieldTable<()>,
}
impl QueueMaterial {
    pub fn new(source: Arc<PersistenceQueueSnapshot>) -> Self {
        Self {
            source,
            texts: FieldTable::default(),
            lists: FieldTable::default(),
        }
    }
    pub fn header(&self) -> Result<PersistenceQueueReadHeader, StudioError> {
        bounded_header(|inline| {
            let source = &self.source.value;
            let queue = &source.queue;
            Ok(PersistenceQueueReadHeader {
                revision: source.revision,
                updated_at: source.updated_at,
                queue: PersistenceQueueSnapshotRead {
                    statistics_gap: queue.statistics_gap,
                    pending_operations: queue.pending_operations,
                    pending_bytes: queue.pending_bytes,
                    in_flight_bytes: queue.in_flight_bytes,
                    oldest_pending_age_millis: queue.oldest_pending_age_millis,
                    last_error: queue
                        .last_error
                        .as_ref()
                        .map(|_| self.read(Text::Error, inline))
                        .transpose()?,
                    pressure_paused: queue.pressure_paused,
                    threads: TypedListRef {
                        list_id: self.lists.register(())?,
                        total: count(queue.threads.len())?,
                    },
                },
            })
        })
    }
    pub fn entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<PersistenceQueueEntryPage, StudioError> {
        let (start, end) = range(self.source.entities.len(), offset, limit)?;
        Ok(PersistenceQueueEntryPage {
            collection: self.source.collection,
            offset,
            items: self.source.entities[start..end].to_vec(),
            next_offset: next(end, self.source.entities.len())?,
        })
    }
    pub fn entity(
        &self,
        reference: ProductEntityRef,
    ) -> Result<PersistenceQueueEntityRead, StudioError> {
        let index = self
            .source
            .entities
            .iter()
            .position(|value| value == &reference)
            .ok_or_else(wrong)?;
        bounded_header(|inline| {
            Ok(PersistenceQueueEntityRead {
                reference,
                value: self.thread(index, inline)?,
            })
        })
    }
    pub fn lookup(&self, id: &str) -> Result<Option<ProductEntityRef>, StudioError> {
        Ok(self
            .source
            .value
            .queue
            .threads
            .iter()
            .position(|value| value.thread_id == id)
            .map(|index| self.source.entities[index]))
    }
    pub fn threads(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<ThreadPersistenceReadPage, StudioError> {
        self.lists.field(list_id)?;
        let total = self.source.value.queue.threads.len();
        let (start, end) = range(total, offset, limit)?;
        let mut page = ThreadPersistenceReadPage {
            list_id,
            offset,
            total: count(total)?,
            items: Vec::new(),
            next_offset: None,
        };
        for index in start..end {
            page.items.push(self.thread(index, 0)?);
            page.next_offset = next(index + 1, total)?;
            if let Err(error) = require_budget(&page) {
                page.items.pop();
                if page.items.is_empty() {
                    return Err(error);
                }
                page.next_offset = Some(count(index)?);
                break;
            }
        }
        Ok(page)
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
    fn read(&self, field: Text, inline: usize) -> Result<ReadText, StudioError> {
        self.texts.read(field, self.text_source(field)?, inline)
    }
    fn text_source(&self, field: Text) -> Result<&str, StudioError> {
        let queue = &self.source.value.queue;
        match field {
            Text::Error => queue.last_error.as_deref().ok_or_else(wrong),
            Text::ThreadId(index) => Ok(&queue.threads.get(index).ok_or_else(wrong)?.thread_id),
            Text::ThreadError(index) => queue
                .threads
                .get(index)
                .ok_or_else(wrong)?
                .last_error
                .as_deref()
                .ok_or_else(wrong),
        }
    }
    fn thread(&self, index: usize, inline: usize) -> Result<ThreadPersistenceRead, StudioError> {
        let value = self
            .source
            .value
            .queue
            .threads
            .get(index)
            .ok_or_else(wrong)?;
        Ok(ThreadPersistenceRead {
            thread_id: self.read(Text::ThreadId(index), inline)?,
            fault_generation: value.fault_generation,
            fault: value.fault,
            state_dirty_revision: value.state_dirty_revision,
            state_saving_revision: value.state_saving_revision,
            state_durable_revision: value.state_durable_revision,
            history_admitted_sequence: value.history_admitted_sequence,
            history_durable_sequence: value.history_durable_sequence,
            calls_admitted_sequence: value.calls_admitted_sequence,
            calls_durable_sequence: value.calls_durable_sequence,
            pending_operations: value.pending_operations,
            pending_bytes: value.pending_bytes,
            oldest_pending_age_millis: value.oldest_pending_age_millis,
            in_flight_bytes: value.in_flight_bytes,
            last_error: value
                .last_error
                .as_ref()
                .map(|_| self.read(Text::ThreadError(index), inline))
                .transpose()?,
            pressure_paused: value.pressure_paused,
        })
    }
}
fn wrong() -> StudioError {
    StudioError::invalid_argument(
        "Unknown Persistence queue field, list or member in the original scope",
    )
}
fn range(total: usize, offset: u64, limit: u32) -> Result<(usize, usize), StudioError> {
    if !(1..=100).contains(&limit) {
        return Err(StudioError::invalid_argument(
            "Page limit must be in 1..=100",
        ));
    }
    let start = usize::try_from(offset)
        .ok()
        .filter(|start| *start <= total)
        .ok_or_else(wrong)?;
    Ok((start, start.saturating_add(limit as usize).min(total)))
}
fn next(end: usize, total: usize) -> Result<Option<u64>, StudioError> {
    if end < total {
        Ok(Some(count(end)?))
    } else {
        Ok(None)
    }
}
