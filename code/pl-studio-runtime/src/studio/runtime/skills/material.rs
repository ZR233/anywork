use super::super::models::page_budget::{PageBinding, page};
use super::super::read_budget::{FieldTable, bounded_header, count, text_chunk};
use super::source::SkillsMaterial;
use pl_protocol::products::identity::ProductEntityRef;
use pl_protocol::products::read::primitives::{TextReadItem, TextReadPage, TypedListRef};
use pl_protocol::products::read::skills::*;
use pl_protocol::studio::{ReadText, StudioError, StudioErrorCode, TextChunk};
use std::sync::Arc;

#[derive(Clone, Copy, PartialEq, Eq)]
enum ListField {
    Members,
    Warnings,
    Platforms(usize),
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum MemberText {
    Name,
    Description,
    Category,
    Provider,
    Resource,
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum TextField {
    Project,
    Fingerprint,
    Directory,
    Member(usize, MemberText),
    String(ListField, usize),
}
pub(super) struct ReadMaterial {
    source: Arc<SkillsMaterial>,
    texts: FieldTable<TextField>,
    lists: FieldTable<ListField>,
}
impl ReadMaterial {
    pub(super) fn new(source: Arc<SkillsMaterial>) -> Self {
        Self {
            source,
            texts: FieldTable::default(),
            lists: FieldTable::default(),
        }
    }
    fn value(&self) -> &crate::StudioSkillsStateData {
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
    pub(super) fn entries(&self, offset: u64, limit: u32) -> Result<SkillsEntryPage, StudioError> {
        let collection = self.source.collection;
        let result = page(
            PageBinding::Collection(collection),
            self.source.entities.len(),
            offset,
            limit,
            |index, _| Ok(self.source.entities[index]),
        )?;
        Ok(SkillsEntryPage {
            collection,
            offset,
            items: result.items,
            next_offset: result.next_offset,
        })
    }
    pub(super) fn entity(
        &self,
        reference: ProductEntityRef,
    ) -> Result<SkillsEntityRead, StudioError> {
        let index = self
            .source
            .entities
            .iter()
            .position(|entity| entity.entry == reference.entry)
            .ok_or_else(|| StudioError::not_found("Skills member"))?;
        if self.source.entities[index] != reference {
            return Err(StudioError::new(
                StudioErrorCode::Superseded,
                "Member revision differs from the original immutable Skills scope",
                false,
            ));
        }
        bounded_header(|inline| {
            Ok(SkillsEntityRead {
                reference,
                value: self.member(index, inline)?,
            })
        })
    }
    pub(super) fn lookup(&self, key: &str) -> Result<Option<ProductEntityRef>, StudioError> {
        Ok(self
            .value()
            .catalog
            .skills
            .iter()
            .position(|member| member.name.eq_ignore_ascii_case(key))
            .map(|index| self.source.entities[index]))
    }
    pub(super) fn members(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<SkillSummaryReadPage, StudioError> {
        if self.lists.field(list_id)? != ListField::Members {
            return Err(wrong_field());
        }
        let result = page(
            PageBinding::List(list_id),
            self.value().catalog.skills.len(),
            offset,
            limit,
            |index, inline| self.member(index, inline),
        )?;
        Ok(SkillSummaryReadPage {
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
    pub(super) fn header(&self) -> Result<SkillsReadHeader, StudioError> {
        bounded_header(|inline| {
            Ok(SkillsReadHeader {
                project_id: self.read(TextField::Project, inline)?,
                config_fingerprint: self.read(TextField::Fingerprint, inline)?,
                catalog_revision: self.value().catalog_revision,
                catalog: SkillCatalogRead {
                    project_dir: self.read(TextField::Directory, inline)?,
                    skills: self.list(ListField::Members, self.value().catalog.skills.len())?,
                    warnings: self
                        .list(ListField::Warnings, self.value().catalog.warnings.len())?,
                    complete: self.value().catalog.complete,
                },
            })
        })
    }
    fn member(&self, index: usize, inline: usize) -> Result<SkillSummaryRead, StudioError> {
        use pl_tool::skill::{SkillResourceBase, SkillSourceKind};
        let value = self
            .value()
            .catalog
            .skills
            .get(index)
            .ok_or_else(wrong_field)?;
        let text = |field| self.read(TextField::Member(index, field), inline);
        let resource_base = match &value.resource_base {
            SkillResourceBase::Directory { .. } => SkillResourceBaseRead::Directory {
                path: text(MemberText::Resource)?,
            },
            SkillResourceBase::Url { .. } => SkillResourceBaseRead::Url {
                url: text(MemberText::Resource)?,
            },
            SkillResourceBase::Opaque { .. } => SkillResourceBaseRead::Opaque {
                description: text(MemberText::Resource)?,
            },
        };
        Ok(SkillSummaryRead {
            name: text(MemberText::Name)?,
            description: text(MemberText::Description)?,
            category: value
                .category
                .as_ref()
                .map(|_| text(MemberText::Category))
                .transpose()?,
            platforms: self.list(ListField::Platforms(index), value.platforms.len())?,
            source: match value.source {
                SkillSourceKind::Project => SkillSource::Project,
                SkillSourceKind::User => SkillSource::User,
                SkillSourceKind::System => SkillSource::System,
                SkillSourceKind::External => SkillSource::External,
            },
            provider_id: text(MemberText::Provider)?,
            invocation: SkillInvocationPolicyRead {
                model_invocable: value.invocation.model_invocable,
                user_invocable: value.invocation.user_invocable,
            },
            resource_base,
        })
    }
    fn strings(&self, field: ListField) -> Result<&[String], StudioError> {
        match field {
            ListField::Warnings => Ok(&self.value().catalog.warnings),
            ListField::Platforms(index) => Ok(&self
                .value()
                .catalog
                .skills
                .get(index)
                .ok_or_else(wrong_field)?
                .platforms),
            ListField::Members => Err(wrong_field()),
        }
    }
    fn text_source(&self, field: TextField) -> Result<&str, StudioError> {
        use pl_tool::skill::SkillResourceBase;
        match field {
            TextField::Project => Ok(&self.source.project_id),
            TextField::Fingerprint => Ok(&self.value().config_fingerprint),
            TextField::Directory => path_text(&self.value().catalog.project_dir),
            TextField::String(field, index) => self
                .strings(field)?
                .get(index)
                .map(String::as_str)
                .ok_or_else(wrong_field),
            TextField::Member(index, field) => {
                let value = self
                    .value()
                    .catalog
                    .skills
                    .get(index)
                    .ok_or_else(wrong_field)?;
                match field {
                    MemberText::Name => Ok(&value.name),
                    MemberText::Description => Ok(&value.description),
                    MemberText::Category => value.category.as_deref().ok_or_else(wrong_field),
                    MemberText::Provider => Ok(value.provider_id.as_str()),
                    MemberText::Resource => match &value.resource_base {
                        SkillResourceBase::Directory { path } => path_text(path),
                        SkillResourceBase::Url { url } => Ok(url),
                        SkillResourceBase::Opaque { description } => Ok(description),
                    },
                }
            }
        }
    }
}
pub(super) fn wrong_field() -> StudioError {
    StudioError::invalid_argument(
        "Field or list does not belong to this original Skills read scope/type",
    )
}

fn path_text(path: &std::path::Path) -> Result<&str, StudioError> {
    path.to_str().ok_or_else(|| {
        StudioError::new(
            StudioErrorCode::Protocol,
            "Skill path is not representable as UTF-8",
            false,
        )
    })
}
