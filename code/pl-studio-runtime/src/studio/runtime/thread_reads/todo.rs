use std::sync::Arc;

use pl_protocol::TodoItem;
use pl_protocol::studio::{ReadText, StudioError, TextChunk};
use pl_protocol::thread_facets::identity::ReadScopeIdentity;
use pl_protocol::thread_facets::read::values::{TodoItemPage, TodoReadHeader, TodoReadItem};

use super::super::read_budget::{FieldTable, bounded_header, count, protocol, text_chunk};
use super::budget::{page, validate_revision};

/// `call_id` is populated only by the original delivery/source identity proof. A restored todo
/// without that proof remains None; an empty string is never synthesized as a stable identity.
#[derive(PartialEq, Eq)]
pub(in crate::studio::runtime) struct TodoSource {
    pub(in crate::studio::runtime) revision: u64,
    pub(in crate::studio::runtime) call_id: Option<String>,
    pub(in crate::studio::runtime) agent_id: Option<String>,
    pub(in crate::studio::runtime) path: Option<String>,
    pub(in crate::studio::runtime) parent_path: Option<String>,
    pub(in crate::studio::runtime) explanation: Option<String>,
    pub(in crate::studio::runtime) items: Vec<TodoItem>,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Field {
    CallId,
    AgentId,
    Path,
    ParentPath,
    Explanation,
    Item(usize),
}

pub(in crate::studio::runtime) struct TodoMaterial {
    scope: ReadScopeIdentity,
    source: Arc<TodoSource>,
    fields: FieldTable<Field>,
}

impl TodoMaterial {
    pub(in crate::studio::runtime) fn new(
        scope: ReadScopeIdentity,
        source: Arc<TodoSource>,
    ) -> Result<Self, StudioError> {
        validate_revision(&scope, source.revision)?;
        Ok(Self {
            scope,
            source,
            fields: FieldTable::default(),
        })
    }

    pub(in crate::studio::runtime) fn header(&self) -> Result<TodoReadHeader, StudioError> {
        bounded_header(|inline| {
            let optional = |value: &Option<String>, field| {
                value.as_ref().map(|_| self.read(field, inline)).transpose()
            };
            Ok(TodoReadHeader {
                scope: self.scope.clone(),
                call_id: optional(&self.source.call_id, Field::CallId)?,
                agent_id: optional(&self.source.agent_id, Field::AgentId)?,
                path: optional(&self.source.path, Field::Path)?,
                parent_path: optional(&self.source.parent_path, Field::ParentPath)?,
                explanation: optional(&self.source.explanation, Field::Explanation)?,
                item_count: count(self.source.items.len())?,
            })
        })
    }

    pub(in crate::studio::runtime) fn items(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<TodoItemPage, StudioError> {
        let result = page(
            &self.scope,
            self.source.items.len(),
            offset,
            limit,
            |index, inline| {
                Ok(TodoReadItem {
                    index: count(index)?,
                    step: self.read(Field::Item(index), inline)?,
                    status: self.source.items[index].status,
                })
            },
        )?;
        Ok(TodoItemPage {
            scope: result.scope,
            offset: result.offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }

    pub(in crate::studio::runtime) fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> Result<TextChunk, StudioError> {
        text_chunk(
            field_id,
            self.source_text(self.fields.field(field_id)?)?,
            offset,
            max_bytes,
        )
    }

    fn read(&self, field: Field, inline: usize) -> Result<ReadText, StudioError> {
        self.fields.read(field, self.source_text(field)?, inline)
    }

    fn source_text(&self, field: Field) -> Result<&str, StudioError> {
        let value = match field {
            Field::CallId => self.source.call_id.as_deref(),
            Field::AgentId => self.source.agent_id.as_deref(),
            Field::Path => self.source.path.as_deref(),
            Field::ParentPath => self.source.parent_path.as_deref(),
            Field::Explanation => self.source.explanation.as_deref(),
            Field::Item(index) => self.source.items.get(index).map(|item| item.step.as_str()),
        };
        value.ok_or_else(|| protocol("Text field does not address the pinned Todo schema"))
    }
}
