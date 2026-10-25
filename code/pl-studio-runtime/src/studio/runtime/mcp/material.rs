use super::super::models::page_budget::{PageBinding, page};
use super::super::read_budget::{FieldTable, bounded_header, count, text_chunk};
use super::source::McpMaterial;
use pl_protocol::products::identity::ProductEntityRef;
use pl_protocol::products::read::mcp::*;
use pl_protocol::products::read::primitives::{TextReadItem, TextReadPage, TypedListRef};
use pl_protocol::studio::{ReadText, StudioError, StudioErrorCode, TextChunk};
use std::sync::Arc;

#[derive(Clone, Copy, PartialEq, Eq)]
enum ListField {
    Members,
    Active,
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum MemberText {
    Id,
    Transport,
    Endpoint,
    Source,
    Mutation,
    Message,
    ErrorCode,
    ErrorMessage,
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum TextField {
    Desired,
    Applied,
    Member(usize, MemberText),
    String(ListField, usize),
}
pub(super) struct ReadMaterial {
    source: Arc<McpMaterial>,
    texts: FieldTable<TextField>,
    lists: FieldTable<ListField>,
}
impl ReadMaterial {
    pub(super) fn new(source: Arc<McpMaterial>) -> Self {
        Self {
            source,
            texts: FieldTable::default(),
            lists: FieldTable::default(),
        }
    }
    fn value(&self) -> &crate::StudioMcpStateData {
        &self.source.value
    }
    fn list(&self, field: ListField, total: usize) -> Result<TypedListRef, StudioError> {
        Ok(TypedListRef {
            list_id: self.lists.register(field)?,
            total: count(total)?,
        })
    }
    fn read(&self, field: TextField, inline: usize) -> Result<ReadText, StudioError> {
        self.texts.read(field, self.text_source(field)?, inline)
    }
    pub(super) fn text(
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
    pub(super) fn entries(&self, offset: u64, limit: u32) -> Result<McpEntryPage, StudioError> {
        let collection = self.source.collection;
        let result = page(
            PageBinding::Collection(collection),
            self.source.entities.len(),
            offset,
            limit,
            |index, _| Ok(self.source.entities[index]),
        )?;
        Ok(McpEntryPage {
            collection,
            offset,
            items: result.items,
            next_offset: result.next_offset,
        })
    }
    pub(super) fn entity(&self, reference: ProductEntityRef) -> Result<McpEntityRead, StudioError> {
        let index = self
            .source
            .entities
            .iter()
            .position(|entity| entity.entry == reference.entry)
            .ok_or_else(|| StudioError::not_found("Mcp member"))?;
        if self.source.entities[index] != reference {
            return Err(StudioError::new(
                StudioErrorCode::Superseded,
                "Member revision differs from the original immutable Mcp scope",
                false,
            ));
        }
        bounded_header(|inline| {
            Ok(McpEntityRead {
                reference,
                value: self.member(index, inline)?,
            })
        })
    }
    pub(super) fn lookup(&self, key: &str) -> Result<Option<ProductEntityRef>, StudioError> {
        Ok(self
            .value()
            .health
            .mcp_servers
            .iter()
            .position(|member| member.id == key)
            .map(|index| self.source.entities[index]))
    }
    pub(super) fn members(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<McpServerReadPage, StudioError> {
        if self.lists.field(list_id)? != ListField::Members {
            return Err(wrong_field());
        }
        let result = page(
            PageBinding::List(list_id),
            self.value().health.mcp_servers.len(),
            offset,
            limit,
            |index, inline| self.member(index, inline),
        )?;
        Ok(McpServerReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }
    pub(super) fn strings_page(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<TextReadPage, StudioError> {
        let field = self.lists.field(list_id)?;
        let strings = self.strings(field)?;
        let result = page(
            PageBinding::List(list_id),
            strings.len(),
            offset,
            limit,
            |index, inline| {
                Ok(TextReadItem {
                    value: self.read(TextField::String(field, index), inline)?,
                })
            },
        )?;
        Ok(TextReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }
    pub(super) fn header(&self) -> Result<McpReadHeader, StudioError> {
        bounded_header(|inline| {
            Ok(McpReadHeader {
                desired_config_fingerprint: self.read(TextField::Desired, inline)?,
                applied_config_fingerprint: self.read(TextField::Applied, inline)?,
                health: McpHealthRead {
                    mcp_servers: self
                        .list(ListField::Members, self.value().health.mcp_servers.len())?,
                    active_mcp_servers: self.list(
                        ListField::Active,
                        self.value().health.active_mcp_servers.len(),
                    )?,
                },
            })
        })
    }
    fn member(&self, index: usize, inline: usize) -> Result<McpServerRead, StudioError> {
        use crate::StudioMcpServerState as State;
        let value = self
            .value()
            .health
            .mcp_servers
            .get(index)
            .ok_or_else(wrong_field)?;
        let text = |field| self.read(TextField::Member(index, field), inline);
        let state = match &value.state {
            State::Disabled(_) => McpServerStateRead::Disabled {
                message: text(MemberText::Message)?,
            },
            State::MissingCredential(_) => McpServerStateRead::MissingCredential {
                message: text(MemberText::Message)?,
            },
            State::Checking(_) => McpServerStateRead::Checking {
                message: text(MemberText::Message)?,
            },
            State::Available(state) => McpServerStateRead::Available {
                checked_at: state.checked_at(),
                tool_count: state.tool_count(),
            },
            State::Unavailable(state) => McpServerStateRead::Unavailable {
                checked_at: state.checked_at(),
                error: pl_protocol::products::source::SourceStateErrorRead {
                    code: text(MemberText::ErrorCode)?,
                    message: text(MemberText::ErrorMessage)?,
                    retryable: state.error().retryable,
                },
            },
        };
        Ok(McpServerRead {
            id: text(MemberText::Id)?,
            transport: text(MemberText::Transport)?,
            endpoint: text(MemberText::Endpoint)?,
            source_kind: text(MemberText::Source)?,
            mutation_policy: text(MemberText::Mutation)?,
            state,
        })
    }
    fn strings(&self, field: ListField) -> Result<&[String], StudioError> {
        match field {
            ListField::Active => Ok(&self.value().health.active_mcp_servers),
            ListField::Members => Err(wrong_field()),
        }
    }
    fn text_source(&self, field: TextField) -> Result<&str, StudioError> {
        use crate::StudioMcpServerState as State;
        Ok(match field {
            TextField::Desired => &self.value().desired_config_fingerprint,
            TextField::Applied => &self.value().applied_config_fingerprint,
            TextField::String(field, index) => {
                self.strings(field)?.get(index).ok_or_else(wrong_field)?
            }
            TextField::Member(index, field) => {
                let value = self
                    .value()
                    .health
                    .mcp_servers
                    .get(index)
                    .ok_or_else(wrong_field)?;
                match field {
                    MemberText::Id => &value.id,
                    MemberText::Transport => &value.transport,
                    MemberText::Endpoint => &value.endpoint,
                    MemberText::Source => &value.source_kind,
                    MemberText::Mutation => &value.mutation_policy,
                    MemberText::Message => match &value.state {
                        State::Disabled(state) => state.message(),
                        State::MissingCredential(state) => state.message(),
                        State::Checking(state) => state.message(),
                        State::Available(_) | State::Unavailable(_) => return Err(wrong_field()),
                    },
                    MemberText::ErrorCode | MemberText::ErrorMessage => {
                        let State::Unavailable(state) = &value.state else {
                            return Err(wrong_field());
                        };
                        if field == MemberText::ErrorCode {
                            &state.error().code
                        } else {
                            &state.error().message
                        }
                    }
                }
            }
        })
    }
}
pub(super) fn wrong_field() -> StudioError {
    StudioError::invalid_argument(
        "Field or list does not belong to this original Mcp read scope/type",
    )
}
