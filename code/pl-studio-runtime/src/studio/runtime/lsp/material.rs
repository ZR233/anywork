use super::super::models::page_budget::{PageBinding, page};
use super::super::read_budget::{FieldTable, bounded_header, count, text_chunk};
use super::source::LspMaterial;
use pl_protocol::products::identity::ProductEntityRef;
use pl_protocol::products::read::lsp::*;
use pl_protocol::products::read::primitives::{TextReadItem, TextReadPage, TypedListRef};
use pl_protocol::studio::{ReadText, StudioError, StudioErrorCode, TextChunk};
use std::sync::Arc;

#[derive(Clone, Copy, PartialEq, Eq)]
enum ListField {
    Members,
    Active,
    Extensions(usize),
    Languages(usize),
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum MemberText {
    Id,
    Name,
    Message,
    ErrorCode,
    ErrorMessage,
    Title,
    ActivityMessage,
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum TextField {
    Member(usize, MemberText),
    String(ListField, usize),
}
pub(super) struct ReadMaterial {
    source: Arc<LspMaterial>,
    texts: FieldTable<TextField>,
    lists: FieldTable<ListField>,
}
impl ReadMaterial {
    pub(super) fn new(source: Arc<LspMaterial>) -> Self {
        Self {
            source,
            texts: FieldTable::default(),
            lists: FieldTable::default(),
        }
    }
    fn value(&self) -> &crate::StudioLspHealth {
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
    pub(super) fn entries(&self, offset: u64, limit: u32) -> Result<LspEntryPage, StudioError> {
        let collection = self.source.collection;
        let result = page(
            PageBinding::Collection(collection),
            self.source.entities.len(),
            offset,
            limit,
            |index, _| Ok(self.source.entities[index]),
        )?;
        Ok(LspEntryPage {
            collection,
            offset,
            items: result.items,
            next_offset: result.next_offset,
        })
    }
    pub(super) fn entity(&self, reference: ProductEntityRef) -> Result<LspEntityRead, StudioError> {
        let index = self
            .source
            .entities
            .iter()
            .position(|entity| entity.entry == reference.entry)
            .ok_or_else(|| StudioError::not_found("Lsp member"))?;
        if self.source.entities[index] != reference {
            return Err(StudioError::new(
                StudioErrorCode::Superseded,
                "Member revision differs from the original immutable Lsp scope",
                false,
            ));
        }
        bounded_header(|inline| {
            Ok(LspEntityRead {
                reference,
                value: self.member(index, inline)?,
            })
        })
    }
    pub(super) fn lookup(&self, key: &str) -> Result<Option<ProductEntityRef>, StudioError> {
        let mut matches = self
            .value()
            .lsp_servers
            .iter()
            .enumerate()
            .filter(|(_, member)| member.id == key);
        let first = matches.next().map(|(index, _)| self.source.entities[index]);
        if matches.next().is_some() {
            return Err(StudioError::new(
                StudioErrorCode::Conflict,
                "LSP server ID belongs to multiple workspaces; use the original collection entry",
                false,
            ));
        }
        Ok(first)
    }
    pub(super) fn members(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<LspServerReadPage, StudioError> {
        if self.lists.field(list_id)? != ListField::Members {
            return Err(wrong_field());
        }
        let result = page(
            PageBinding::List(list_id),
            self.value().lsp_servers.len(),
            offset,
            limit,
            |index, inline| self.member(index, inline),
        )?;
        Ok(LspServerReadPage {
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
    pub(super) fn header(&self) -> Result<LspReadHeader, StudioError> {
        Ok(LspReadHeader {
            lsp_servers: self.list(ListField::Members, self.value().lsp_servers.len())?,
            active_lsp_servers: self
                .list(ListField::Active, self.value().active_lsp_servers.len())?,
        })
    }
    fn member(&self, index: usize, inline: usize) -> Result<LspServerRead, StudioError> {
        use crate::{LspAvailableActivity as Activity, StudioLspServerState as State};
        let value = self
            .value()
            .lsp_servers
            .get(index)
            .ok_or_else(wrong_field)?;
        let text = |field| self.read(TextField::Member(index, field), inline);
        let state = match &value.state {
            State::Checking(_) => LspServerStateRead::Checking {
                message: text(MemberText::Message)?,
            },
            State::Disabled(_) => LspServerStateRead::Disabled {
                message: text(MemberText::Message)?,
            },
            State::Unavailable(state) => LspServerStateRead::Unavailable {
                checked_at: state.checked_at(),
                error: pl_protocol::products::source::SourceStateErrorRead {
                    code: text(MemberText::ErrorCode)?,
                    message: text(MemberText::ErrorMessage)?,
                    retryable: state.error().retryable,
                },
            },
            State::Available(state) => LspServerStateRead::Available {
                checked_at: state.checked_at(),
                diagnostic_count: state.diagnostic_count(),
                activity: match state.activity() {
                    Activity::Idle(_) => LspActivityRead::Idle,
                    Activity::Busy(activity) => LspActivityRead::Busy {
                        title: activity
                            .title()
                            .map(|_| text(MemberText::Title))
                            .transpose()?,
                        message: activity
                            .message()
                            .map(|_| text(MemberText::ActivityMessage))
                            .transpose()?,
                        percentage: activity.percentage(),
                    },
                    Activity::Indexing(activity) => LspActivityRead::Indexing {
                        title: activity
                            .title()
                            .map(|_| text(MemberText::Title))
                            .transpose()?,
                        message: activity
                            .message()
                            .map(|_| text(MemberText::ActivityMessage))
                            .transpose()?,
                        percentage: activity.percentage(),
                    },
                },
            },
        };
        Ok(LspServerRead {
            id: text(MemberText::Id)?,
            display_name: text(MemberText::Name)?,
            extensions: self.list(ListField::Extensions(index), value.extensions.len())?,
            language_ids: self.list(ListField::Languages(index), value.language_ids.len())?,
            state,
        })
    }
    fn strings(&self, field: ListField) -> Result<&[String], StudioError> {
        match field {
            ListField::Active => Ok(&self.value().active_lsp_servers),
            ListField::Extensions(index) => Ok(&self
                .value()
                .lsp_servers
                .get(index)
                .ok_or_else(wrong_field)?
                .extensions),
            ListField::Languages(index) => Ok(&self
                .value()
                .lsp_servers
                .get(index)
                .ok_or_else(wrong_field)?
                .language_ids),
            ListField::Members => Err(wrong_field()),
        }
    }
    fn text_source(&self, field: TextField) -> Result<&str, StudioError> {
        use crate::{LspAvailableActivity as Activity, StudioLspServerState as State};
        match field {
            TextField::String(field, index) => self
                .strings(field)?
                .get(index)
                .map(String::as_str)
                .ok_or_else(wrong_field),
            TextField::Member(index, field) => {
                let value = self
                    .value()
                    .lsp_servers
                    .get(index)
                    .ok_or_else(wrong_field)?;
                Ok(match field {
                    MemberText::Id => &value.id,
                    MemberText::Name => &value.display_name,
                    MemberText::Message => match &value.state {
                        State::Checking(state) => state.message(),
                        State::Disabled(state) => state.message(),
                        State::Unavailable(_) | State::Available(_) => return Err(wrong_field()),
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
                    MemberText::Title | MemberText::ActivityMessage => {
                        let State::Available(state) = &value.state else {
                            return Err(wrong_field());
                        };
                        match state.activity() {
                            Activity::Idle(_) => None,
                            Activity::Busy(activity) => {
                                if field == MemberText::Title {
                                    activity.title()
                                } else {
                                    activity.message()
                                }
                            }
                            Activity::Indexing(activity) => {
                                if field == MemberText::Title {
                                    activity.title()
                                } else {
                                    activity.message()
                                }
                            }
                        }
                        .ok_or_else(wrong_field)?
                    }
                })
            }
        }
    }
}
pub(super) fn wrong_field() -> StudioError {
    StudioError::invalid_argument(
        "Field or list does not belong to this original Lsp read scope/type",
    )
}
