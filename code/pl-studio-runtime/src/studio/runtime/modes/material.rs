use super::super::models::page_budget::{PageBinding, page};
use super::super::read_budget::{FieldTable, bounded_header, count, text_chunk};
use super::source::ModesMaterial;
use pl_protocol::ThreadModeId;
use pl_protocol::products::identity::ProductEntityRef;
use pl_protocol::products::read::modes::*;
use pl_protocol::products::read::primitives::TypedListRef;
use pl_protocol::studio::{StudioError, StudioErrorCode, TextChunk};
use std::sync::Arc;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Text {
    Name(usize),
    Description(usize),
}
pub(super) struct ModesReadMaterial {
    source: Arc<ModesMaterial>,
    texts: FieldTable<Text>,
    lists: FieldTable<()>,
}
impl ModesReadMaterial {
    pub fn new(source: Arc<ModesMaterial>) -> Self {
        Self {
            source,
            texts: FieldTable::default(),
            lists: FieldTable::default(),
        }
    }
    pub fn header(&self) -> Result<ModeCatalogReadHeader, StudioError> {
        Ok(ModeCatalogReadHeader {
            revision: self.source.value.revision,
            modes: TypedListRef {
                list_id: self.lists.register(())?,
                total: count(self.source.value.modes.len())?,
            },
        })
    }
    fn descriptor(
        &self,
        index: usize,
        inline: usize,
    ) -> Result<ThreadModeDescriptorRead, StudioError> {
        let value = &self.source.value.modes[index];
        Ok(ThreadModeDescriptorRead {
            id: value.id.clone(),
            display_name: self
                .texts
                .read(Text::Name(index), &value.display_name, inline)?,
            description: self
                .texts
                .read(Text::Description(index), &value.description, inline)?,
            order: value.order,
            has_workflow: value.has_workflow,
            read_only: value.read_only,
        })
    }
    pub fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> Result<TextChunk, StudioError> {
        let source = match self.texts.field(field_id)? {
            Text::Name(index) => &self.source.value.modes[index].display_name,
            Text::Description(index) => &self.source.value.modes[index].description,
        };
        text_chunk(field_id, source, offset, max_bytes)
    }
    pub fn entries(&self, offset: u64, limit: u32) -> Result<ModeCatalogEntryPage, StudioError> {
        let collection = self.source.collection;
        let result = page(
            PageBinding::Collection(collection),
            self.source.entities.len(),
            offset,
            limit,
            |index, _| Ok(self.source.entities[index]),
        )?;
        Ok(ModeCatalogEntryPage {
            collection,
            offset,
            items: result.items,
            next_offset: result.next_offset,
        })
    }
    pub fn entity(
        &self,
        reference: ProductEntityRef,
    ) -> Result<ModeCatalogEntityRead, StudioError> {
        let index = self
            .source
            .entities
            .iter()
            .position(|entity| entity.entry == reference.entry)
            .ok_or_else(|| StudioError::not_found("Mode member"))?;
        if self.source.entities[index] != reference {
            return Err(StudioError::new(
                StudioErrorCode::Superseded,
                "Mode entity revision does not belong to this immutable scope",
                false,
            ));
        }
        bounded_header(|inline| {
            Ok(ModeCatalogEntityRead {
                reference,
                value: self.descriptor(index, inline)?,
            })
        })
    }
    pub fn lookup(&self, mode: ThreadModeId) -> Result<Option<ProductEntityRef>, StudioError> {
        Ok(self
            .source
            .value
            .modes
            .iter()
            .position(|value| value.id == mode)
            .map(|index| self.source.entities[index]))
    }
    pub fn modes(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<ThreadModeDescriptorReadPage, StudioError> {
        self.lists.field(list_id)?;
        let result = page(
            PageBinding::List(list_id),
            self.source.entities.len(),
            offset,
            limit,
            |index, inline| self.descriptor(index, inline),
        )?;
        Ok(ThreadModeDescriptorReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }
}
