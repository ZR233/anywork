//! Closed Profiles fields over the original adopted scan, preserving ordering and raw text.
use pl_protocol::products::identity::ProductEntityRef;
use pl_protocol::products::read::agent_profiles::*;
use pl_protocol::products::read::primitives::TypedListRef;
use pl_protocol::studio::{ReadText, StudioError, TextChunk};
use std::sync::Arc;

use super::super::super::models::page_budget::{PageBinding, page};
use super::super::super::read_budget::{FieldTable, bounded_header, count, text_chunk};
use crate::config::ProfilesMaterial;

#[derive(Clone, Copy, PartialEq, Eq)]
enum ProfileText {
    Id,
    Name,
    Description,
    WhenToUse,
    Instructions,
    Account,
    Model,
    Effort,
    Source,
    Revision,
    Hash,
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum TextField {
    Profile(usize, ProfileText),
    DiagnosticPath(usize),
    DiagnosticMessage(usize),
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum ListField {
    Profiles,
    Diagnostics,
}

pub(super) struct ProfilesReadMaterial {
    source: Arc<ProfilesMaterial>,
    texts: FieldTable<TextField>,
    lists: FieldTable<ListField>,
    // Path conversion is the same lossless-where-UTF8 representation used by the original
    // resource projection, captured once for this scope (never reread from disk).
    paths: Vec<String>,
}
impl ProfilesReadMaterial {
    pub(super) fn new(source: Arc<ProfilesMaterial>) -> Self {
        let paths = source
            .value
            .diagnostics
            .iter()
            .map(|diagnostic| diagnostic.path.to_string_lossy().into_owned())
            .collect();
        Self {
            source,
            texts: FieldTable::default(),
            lists: FieldTable::default(),
            paths,
        }
    }
    pub(super) fn header(&self) -> Result<AgentProfilesReadHeader, StudioError> {
        bounded_header(|_| {
            Ok(AgentProfilesReadHeader {
                profiles: TypedListRef {
                    list_id: self.lists.register(ListField::Profiles)?,
                    total: count(self.source.value.profiles.len())?,
                },
                diagnostics: TypedListRef {
                    list_id: self.lists.register(ListField::Diagnostics)?,
                    total: count(self.source.value.diagnostics.len())?,
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
        text_chunk(
            field_id,
            self.text_source(self.texts.field(field_id)?)?,
            offset,
            max_bytes,
        )
    }
    fn text_source(&self, field: TextField) -> Result<&str, StudioError> {
        Ok(match field {
            TextField::Profile(index, key) => {
                let profile = self
                    .source
                    .value
                    .profiles
                    .get(index)
                    .ok_or_else(wrong_field)?;
                match key {
                    ProfileText::Id => &profile.profile_id,
                    ProfileText::Name => &profile.display_name,
                    ProfileText::Description => &profile.description,
                    ProfileText::WhenToUse => &profile.when_to_use,
                    ProfileText::Instructions => &profile.system_instructions,
                    ProfileText::Account => &profile.account_id,
                    ProfileText::Model => &profile.model_id,
                    ProfileText::Effort => profile.effort.as_deref().ok_or_else(wrong_field)?,
                    ProfileText::Source => &profile.source,
                    ProfileText::Revision => &profile.revision,
                    ProfileText::Hash => &profile.content_hash,
                }
            }
            TextField::DiagnosticPath(index) => self.paths.get(index).ok_or_else(wrong_field)?,
            TextField::DiagnosticMessage(index) => {
                &self
                    .source
                    .value
                    .diagnostics
                    .get(index)
                    .ok_or_else(wrong_field)?
                    .message
            }
        })
    }
    fn read_text(&self, field: TextField, inline: usize) -> Result<ReadText, StudioError> {
        self.texts.read(field, self.text_source(field)?, inline)
    }
    fn profile(&self, index: usize, inline: usize) -> Result<AgentProfileRead, StudioError> {
        let profile = self
            .source
            .value
            .profiles
            .get(index)
            .ok_or_else(wrong_field)?;
        let text = |key| self.read_text(TextField::Profile(index, key), inline);
        Ok(AgentProfileRead {
            profile_id: text(ProfileText::Id)?,
            display_name: text(ProfileText::Name)?,
            description: text(ProfileText::Description)?,
            when_to_use: text(ProfileText::WhenToUse)?,
            system_instructions: text(ProfileText::Instructions)?,
            account_id: text(ProfileText::Account)?,
            model_id: text(ProfileText::Model)?,
            effort: profile
                .effort
                .as_ref()
                .map(|_| text(ProfileText::Effort))
                .transpose()?,
            source: text(ProfileText::Source)?,
            revision: text(ProfileText::Revision)?,
            content_hash: text(ProfileText::Hash)?,
            system: profile.system,
            enabled: profile.enabled,
            workspace_mode: profile.workspace_mode,
        })
    }
    pub(super) fn entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<AgentProfilesEntryPage, StudioError> {
        let collection = self.source.collection;
        let result = page(
            PageBinding::Collection(collection),
            self.source.entities.len(),
            offset,
            limit,
            |index, _| Ok(self.source.entities[index]),
        )?;
        Ok(AgentProfilesEntryPage {
            collection,
            offset,
            items: result.items,
            next_offset: result.next_offset,
        })
    }
    pub(super) fn entity(
        &self,
        reference: ProductEntityRef,
    ) -> Result<AgentProfilesEntityRead, StudioError> {
        let index = self
            .source
            .entities
            .iter()
            .position(|entity| entity == &reference)
            .ok_or_else(wrong_field)?;
        bounded_header(|inline| {
            Ok(AgentProfilesEntityRead {
                reference,
                value: self.profile(index, inline)?,
            })
        })
    }
    pub(super) fn lookup_profile(
        &self,
        profile_id: &str,
    ) -> Result<Option<ProductEntityRef>, StudioError> {
        Ok(self
            .source
            .value
            .profiles
            .iter()
            .position(|profile| profile.profile_id == profile_id)
            .map(|index| self.source.entities[index]))
    }
    pub(super) fn profiles(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<AgentProfileReadPage, StudioError> {
        if self.lists.field(list_id)? != ListField::Profiles {
            return Err(wrong_field());
        }
        let result = page(
            PageBinding::List(list_id),
            self.source.value.profiles.len(),
            offset,
            limit,
            |index, inline| self.profile(index, inline),
        )?;
        Ok(AgentProfileReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }
    pub(super) fn diagnostics(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<ProfileDiagnosticReadPage, StudioError> {
        if self.lists.field(list_id)? != ListField::Diagnostics {
            return Err(wrong_field());
        }
        let result = page(
            PageBinding::List(list_id),
            self.source.value.diagnostics.len(),
            offset,
            limit,
            |index, inline| {
                Ok(ProfileDiagnosticRead {
                    path: self.read_text(TextField::DiagnosticPath(index), inline)?,
                    message: self.read_text(TextField::DiagnosticMessage(index), inline)?,
                })
            },
        )?;
        Ok(ProfileDiagnosticReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }
}
fn wrong_field() -> StudioError {
    StudioError::invalid_argument(
        "Field, list or entity does not belong to this pinned Profiles scope",
    )
}
