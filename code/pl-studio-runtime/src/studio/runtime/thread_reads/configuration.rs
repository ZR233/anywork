use std::sync::Arc;

use pl_protocol::ThreadModelRouteSnapshot;
use pl_protocol::studio::{ReadText, StudioError, TextChunk};
use pl_protocol::thread_facets::identity::ReadScopeIdentity;
use pl_protocol::thread_facets::read::values::{ConfigurationReadHeader, ModelRouteReadValue,
    SkillNamePage, SkillNameReadItem};

use super::super::read_budget::{FieldTable, bounded_header, count, protocol, text_chunk};
use super::budget::{page, validate_revision};

#[derive(PartialEq, Eq)]
pub(super) struct ConfigurationSource {
    pub(super) revision: u64,
    pub(super) route: Option<ThreadModelRouteSnapshot>,
    pub(super) active_skills: Vec<String>,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Field { AccountId, ModelId, Effort, UnavailableReason, Skill(usize) }

pub(super) struct ConfigurationMaterial {
    scope: ReadScopeIdentity,
    source: Arc<ConfigurationSource>,
    fields: FieldTable<Field>,
}

impl ConfigurationMaterial {
    pub(super) fn new(scope: ReadScopeIdentity, source: Arc<ConfigurationSource>) -> Result<Self, StudioError> {
        validate_revision(&scope, source.revision)?;
        Ok(Self { scope, source, fields: FieldTable::default() })
    }

    pub(super) fn header(&self) -> Result<ConfigurationReadHeader, StudioError> {
        bounded_header(|inline| {
            let route = self.source.route.as_ref().map(|value| {
                Ok::<_, StudioError>(ModelRouteReadValue {
                    account_id: self.read(Field::AccountId, inline)?, model_id: self.read(Field::ModelId, inline)?,
                    effort: value.effort.as_ref().map(|_| self.read(Field::Effort, inline)).transpose()?,
                    revision: value.revision, available: value.available,
                    unavailable_reason: value.unavailable_reason.as_ref().map(|_| self.read(Field::UnavailableReason, inline)).transpose()?,
                })
            }).transpose()?;
            Ok(ConfigurationReadHeader { scope: self.scope.clone(), route,
                active_skill_count: count(self.source.active_skills.len())? })
        })
    }

    pub(super) fn active_skills(&self, offset: u64, limit: u32) -> Result<SkillNamePage, StudioError> {
        let result = page(&self.scope, self.source.active_skills.len(), offset, limit, |index, inline| {
            Ok(SkillNameReadItem { index: count(index)?, name: self.read(Field::Skill(index), inline)? })
        })?;
        Ok(SkillNamePage { scope: result.scope, offset: result.offset, total: result.total,
            items: result.items, next_offset: result.next_offset })
    }

    pub(super) fn text(&self, field_id: u64, offset: u64, max_bytes: u32) -> Result<TextChunk, StudioError> {
        text_chunk(field_id, self.source_text(self.fields.field(field_id)?)?, offset, max_bytes)
    }

    fn read(&self, field: Field, inline: usize) -> Result<ReadText, StudioError> {
        self.fields.read(field, self.source_text(field)?, inline)
    }

    fn source_text(&self, field: Field) -> Result<&str, StudioError> {
        let value = match field {
            Field::Skill(index) => self.source.active_skills.get(index).map(String::as_str),
            Field::AccountId => self.source.route.as_ref().map(|route| route.account_id.as_str()),
            Field::ModelId => self.source.route.as_ref().map(|route| route.model_id.as_str()),
            Field::Effort => self.source.route.as_ref().and_then(|route| route.effort.as_deref()),
            Field::UnavailableReason => self.source.route.as_ref().and_then(|route| route.unavailable_reason.as_deref()),
        };
        value.ok_or_else(|| protocol("Text field does not address the pinned configuration schema"))
    }
}
