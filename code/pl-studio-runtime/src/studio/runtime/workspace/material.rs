//! Field IDs locate strings in an immutable capture, never copied strings or another snapshot.
use pl_protocol::products::identity::ProductEntityRef;
use pl_protocol::products::read::primitives::TypedListRef;
use pl_protocol::products::read::workspace::*;
use pl_protocol::studio::{ReadText, StudioError, TextChunk};

use super::super::read_budget::{FieldTable, INLINE_BYTES, bounded_header, count, text_chunk};
use super::source::{DirectoryRows, DirectorySnapshot};

#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum RecordText {
    Id,
    Name,
    Path,
    SshAlias,
    ProjectId,
    Title,
    Mode,
    WorkspacePath,
    RootThreadId,
    ParentThreadId,
    Role,
    AgentPath,
    ThreadId,
    ParentPath,
    Task,
    Summary,
    AccountId,
    ModelId,
    Effort,
    TurnId,
    InteractionId,
    ErrorCode,
    ErrorMessage,
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum TextField {
    Record(usize, RecordText),
    Frontier,
    EntryCursor(usize),
}

#[derive(Default)]
pub(super) struct DirectoryMaterial {
    fields: FieldTable<TextField>,
}

impl DirectorySnapshot {
    pub(super) fn list(&self) -> TypedListRef {
        TypedListRef {
            list_id: 1,
            total: self.collection.total,
        }
    }
    pub(super) fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> Result<TextChunk, StudioError> {
        let field = self.material.fields.field(field_id)?;
        match field {
            TextField::Record(index, field) => {
                text_chunk(field_id, self.record_text(index, field)?, offset, max_bytes)
            }
            TextField::Frontier => text_chunk(
                field_id,
                self.capture
                    .frontier
                    .as_deref()
                    .ok_or_else(super::wrong_field)?,
                offset,
                max_bytes,
            ),
            TextField::EntryCursor(end) => {
                text_chunk(field_id, &self.entry_cursor(end), offset, max_bytes)
            }
        }
    }
    pub(super) fn read_text(
        &self,
        index: usize,
        field: RecordText,
        inline: usize,
    ) -> Result<ReadText, StudioError> {
        self.material.fields.read(
            TextField::Record(index, field),
            self.record_text(index, field)?,
            inline,
        )
    }
    pub(super) fn cursor_text(&self, inline: usize) -> Result<Option<ReadText>, StudioError> {
        self.capture
            .frontier
            .as_ref()
            .map(|cursor| {
                self.material
                    .fields
                    .read(TextField::Frontier, cursor, inline)
            })
            .transpose()
    }
    pub(super) fn entity_index(&self, reference: ProductEntityRef) -> Result<usize, StudioError> {
        self.entities
            .iter()
            .position(|entry| entry == &reference)
            .ok_or_else(super::wrong_field)
    }
    pub(super) fn lookup(&self, id: &str) -> Option<ProductEntityRef> {
        (0..self.capture.rows.len())
            .find(|index| self.capture.rows.id(*index) == id)
            .map(|index| self.entities[index])
    }
    pub(super) fn project_header(&self) -> Result<ProjectDirectoryReadHeader, StudioError> {
        if !matches!(&self.capture.rows, DirectoryRows::Projects(_)) {
            return Err(super::wrong_field());
        }
        Ok(ProjectDirectoryReadHeader {
            projects: self.list(),
        })
    }
    pub(super) fn agent_header(&self) -> Result<AgentDirectoryReadHeader, StudioError> {
        if !matches!(&self.capture.rows, DirectoryRows::Agents(_)) {
            return Err(super::wrong_field());
        }
        Ok(AgentDirectoryReadHeader {
            agents: self.list(),
        })
    }
    pub(super) fn thread_header(&self) -> Result<ThreadDirectoryReadHeader, StudioError> {
        bounded_header(|inline| {
            Ok(ThreadDirectoryReadHeader {
                threads: self.list(),
                next_cursor: self.cursor_text(inline)?,
                has_more: self.capture.frontier.is_some(),
            })
        })
    }
    pub(super) fn project_entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<ProjectDirectoryEntryPage, StudioError> {
        let (items, next_offset) = self.entry_slice(offset, limit)?;
        Ok(ProjectDirectoryEntryPage {
            collection: self.collection,
            offset,
            items,
            next_offset,
        })
    }
    pub(super) fn agent_entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<AgentDirectoryEntryPage, StudioError> {
        let (items, next_offset) = self.entry_slice(offset, limit)?;
        Ok(AgentDirectoryEntryPage {
            collection: self.collection,
            offset,
            items,
            next_offset,
        })
    }
    fn entry_slice(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<(Vec<ProductEntityRef>, Option<u64>), StudioError> {
        let (start, end) = range(self.entities.len(), offset, limit)?;
        Ok((
            self.entities[start..end].to_vec(),
            (end < self.entities.len())
                .then(|| count(end))
                .transpose()?,
        ))
    }
    /// A read cursor names the exact immutable collection and its keyset entry, not a live
    /// frontier or offset. Extending the live native query is only a feed operation.
    pub(super) fn thread_entries(
        &self,
        cursor: Option<String>,
        limit: u32,
    ) -> Result<ThreadDirectoryEntryPage, StudioError> {
        let start = match cursor {
            None => 0,
            Some(cursor) => (1..=self.entities.len())
                .find(|end| self.entry_cursor(*end) == cursor)
                .ok_or_else(super::wrong_field)?,
        };
        let (_, end) = range(self.entities.len(), count(start)?, limit)?;
        let next_cursor = if end < self.entities.len() {
            Some(self.material.fields.read(
                TextField::EntryCursor(end),
                &self.entry_cursor(end),
                INLINE_BYTES,
            )?)
        } else {
            None
        };
        Ok(ThreadDirectoryEntryPage {
            collection: self.collection,
            items: self.entities[start..end].to_vec(),
            has_more: next_cursor.is_some(),
            next_cursor,
        })
    }
    fn entry_cursor(&self, end: usize) -> String {
        let entry = self.entities[end - 1];
        format!(
            "workspace-entry:{}:{}:{}:{}",
            self.collection.entry, self.collection.revision, entry.entry, entry.revision
        )
    }
    pub(super) fn projects(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<ProjectRecordReadPage, StudioError> {
        self.check_list(list_id)?;
        let (start, end) = range(self.capture.rows.len(), offset, limit)?;
        bounded_header(|inline| {
            Ok(ProjectRecordReadPage {
                list_id,
                offset,
                total: self.collection.total,
                items: (start..end)
                    .map(|index| self.project_record(index, inline))
                    .collect::<Result<_, _>>()?,
                next_offset: (end < self.capture.rows.len())
                    .then(|| count(end))
                    .transpose()?,
            })
        })
    }
    pub(super) fn threads(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<WorkspaceThreadRecordReadPage, StudioError> {
        self.check_list(list_id)?;
        let (start, end) = range(self.capture.rows.len(), offset, limit)?;
        bounded_header(|inline| {
            Ok(WorkspaceThreadRecordReadPage {
                list_id,
                offset,
                total: self.collection.total,
                items: (start..end)
                    .map(|index| self.thread_record(index, inline))
                    .collect::<Result<_, _>>()?,
                next_offset: (end < self.capture.rows.len())
                    .then(|| count(end))
                    .transpose()?,
            })
        })
    }
    pub(super) fn agents(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<AgentDirectoryEntryReadPage, StudioError> {
        self.check_list(list_id)?;
        let (start, end) = range(self.capture.rows.len(), offset, limit)?;
        bounded_header(|inline| {
            Ok(AgentDirectoryEntryReadPage {
                list_id,
                offset,
                total: self.collection.total,
                items: (start..end)
                    .map(|index| self.agent_record(index, inline))
                    .collect::<Result<_, _>>()?,
                next_offset: (end < self.capture.rows.len())
                    .then(|| count(end))
                    .transpose()?,
            })
        })
    }
    fn check_list(&self, list_id: u64) -> Result<(), StudioError> {
        if list_id != 1 {
            return Err(super::wrong_field());
        }
        Ok(())
    }
    pub(super) fn project_entity(
        &self,
        reference: ProductEntityRef,
    ) -> Result<ProjectDirectoryEntityRead, StudioError> {
        let index = self.entity_index(reference)?;
        bounded_header(|inline| {
            Ok(ProjectDirectoryEntityRead {
                reference,
                value: self.project_record(index, inline)?,
            })
        })
    }
    pub(super) fn thread_entity(
        &self,
        reference: ProductEntityRef,
    ) -> Result<ThreadDirectoryEntityRead, StudioError> {
        let index = self.entity_index(reference)?;
        bounded_header(|inline| {
            Ok(ThreadDirectoryEntityRead {
                reference,
                value: self.thread_record(index, inline)?,
            })
        })
    }
    pub(super) fn agent_entity(
        &self,
        reference: ProductEntityRef,
    ) -> Result<AgentDirectoryEntityRead, StudioError> {
        let index = self.entity_index(reference)?;
        bounded_header(|inline| {
            Ok(AgentDirectoryEntityRead {
                reference,
                value: self.agent_record(index, inline)?,
            })
        })
    }
}

fn range(total: usize, offset: u64, limit: u32) -> Result<(usize, usize), StudioError> {
    if !(1..=100).contains(&limit) {
        return Err(StudioError::invalid_argument(
            "Directory limit must be in 1..=100",
        ));
    }
    let start = usize::try_from(offset)
        .ok()
        .filter(|start| *start <= total)
        .ok_or_else(super::wrong_field)?;
    let end = start.saturating_add(limit as usize).min(total);
    Ok((start, end))
}
