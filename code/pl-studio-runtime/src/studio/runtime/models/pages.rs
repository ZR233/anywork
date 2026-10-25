use pl_protocol::products::read::model_pages::*;
use pl_protocol::products::read::models::{
    ModelInputSourceReadItem, ModelModalityReadItem, ModelTypeExclusionReadItem,
};
use pl_protocol::products::read::primitives::{TextReadItem, TextReadPage};
use pl_protocol::studio::StudioError;

use super::fields::{ListField, ModelPath, TextField};
use super::material::{ModelReadMaterial, wrong_field};
use super::page_budget::{PageBinding, page};

impl ModelReadMaterial {
    pub(super) fn catalog_entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<ModelCatalogEntryPage, StudioError> {
        self.catalog()?;
        let collection = self.collection();
        let result = page(
            PageBinding::Collection(collection),
            self.entities().len(),
            offset,
            limit,
            |index, _| Ok(self.entities()[index]),
        )?;
        Ok(ModelCatalogEntryPage {
            collection,
            offset,
            items: result.items,
            next_offset: result.next_offset,
        })
    }

    pub(super) fn template_entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<AccountTemplatesEntryPage, StudioError> {
        self.templates()?;
        let collection = self.collection();
        let result = page(
            PageBinding::Collection(collection),
            self.entities().len(),
            offset,
            limit,
            |index, _| Ok(self.entities()[index]),
        )?;
        Ok(AccountTemplatesEntryPage {
            collection,
            offset,
            items: result.items,
            next_offset: result.next_offset,
        })
    }

    pub(super) fn accounts_page(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<AccountCatalogEntryReadPage, StudioError> {
        if self.lists.field(list_id)? != ListField::Accounts {
            return Err(wrong_field());
        }
        let result = page(
            PageBinding::List(list_id),
            self.catalog()?.accounts.len(),
            offset,
            limit,
            |index, inline| self.account_read(index, inline),
        )?;
        Ok(AccountCatalogEntryReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }

    pub(super) fn templates_page(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<AccountTemplateReadPage, StudioError> {
        if self.lists.field(list_id)? != ListField::Templates {
            return Err(wrong_field());
        }
        let result = page(
            PageBinding::List(list_id),
            self.templates()?.templates.len(),
            offset,
            limit,
            |index, inline| self.template_read(index, inline),
        )?;
        Ok(AccountTemplateReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }

    pub(super) fn catalogs_page(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<NamedModelCatalogReadPage, StudioError> {
        if self.lists.field(list_id)? != ListField::Catalogs {
            return Err(wrong_field());
        }
        let result = page(
            PageBinding::List(list_id),
            self.templates()?.model_catalogs.len(),
            offset,
            limit,
            |index, inline| self.named_catalog_read(index, inline),
        )?;
        Ok(NamedModelCatalogReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }

    pub(super) fn models_page(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<ModelDescriptorReadPage, StudioError> {
        let ListField::Models(group) = self.lists.field(list_id)? else {
            return Err(wrong_field());
        };
        let result = page(
            PageBinding::List(list_id),
            self.model_group(group)?.len(),
            offset,
            limit,
            |model, inline| self.model_read(ModelPath { group, model }, inline),
        )?;
        Ok(ModelDescriptorReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }

    pub(super) fn type_support_page(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<ModelTypeSupportReadPage, StudioError> {
        let ListField::TypeSupport(path) = self.lists.field(list_id)? else {
            return Err(wrong_field());
        };
        let result = page(
            PageBinding::List(list_id),
            self.model(path)?.type_support.len(),
            offset,
            limit,
            |index, _| self.type_support_read(path, index),
        )?;
        Ok(ModelTypeSupportReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }

    pub(super) fn exclusions_page(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<ModelTypeExclusionReadPage, StudioError> {
        let ListField::Exclusions(path, index) = self.lists.field(list_id)? else {
            return Err(wrong_field());
        };
        let source = &self
            .model(path)?
            .type_support
            .get(index)
            .ok_or_else(wrong_field)?
            .exclusions;
        let result = page(
            PageBinding::List(list_id),
            source.len(),
            offset,
            limit,
            |index, _| {
                Ok(ModelTypeExclusionReadItem {
                    value: source[index],
                })
            },
        )?;
        Ok(ModelTypeExclusionReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }

    pub(super) fn connections_page(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<ConnectionModeReadPage, StudioError> {
        let ListField::ConnectionModes(path) = self.lists.field(list_id)? else {
            return Err(wrong_field());
        };
        let result = page(
            PageBinding::List(list_id),
            self.model(path)?.transport.connection_modes.len(),
            offset,
            limit,
            |index, inline| self.connection_read(path, index, inline),
        )?;
        Ok(ConnectionModeReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }

    pub(super) fn inputs_page(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<ModelInputCapabilityReadPage, StudioError> {
        let ListField::Inputs(path) = self.lists.field(list_id)? else {
            return Err(wrong_field());
        };
        let result = page(
            PageBinding::List(list_id),
            self.model(path)?.capabilities.input.len(),
            offset,
            limit,
            |index, _| self.input_read(path, index),
        )?;
        Ok(ModelInputCapabilityReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }

    pub(super) fn input_sources_page(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<ModelInputSourceReadPage, StudioError> {
        let ListField::InputSources(path, index) = self.lists.field(list_id)? else {
            return Err(wrong_field());
        };
        let source = &self
            .model(path)?
            .capabilities
            .input
            .get(index)
            .ok_or_else(wrong_field)?
            .sources;
        let result = page(
            PageBinding::List(list_id),
            source.len(),
            offset,
            limit,
            |index, _| {
                Ok(ModelInputSourceReadItem {
                    value: source[index],
                })
            },
        )?;
        Ok(ModelInputSourceReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }

    pub(super) fn modalities_page(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<ModelModalityReadPage, StudioError> {
        let ListField::Modalities(path) = self.lists.field(list_id)? else {
            return Err(wrong_field());
        };
        let source = &self.model(path)?.capabilities.output;
        let result = page(
            PageBinding::List(list_id),
            source.len(),
            offset,
            limit,
            |index, _| {
                Ok(ModelModalityReadItem {
                    value: source[index],
                })
            },
        )?;
        Ok(ModelModalityReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }

    pub(super) fn tiers_page(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<ModelPriceTierReadPage, StudioError> {
        let ListField::Tiers(path) = self.lists.field(list_id)? else {
            return Err(wrong_field());
        };
        let source = self.model(path)?.pricing.as_ref().ok_or_else(wrong_field)?;
        let result = page(
            PageBinding::List(list_id),
            source.tiers.len(),
            offset,
            limit,
            |index, inline| self.tier_read(path, index, inline),
        )?;
        Ok(ModelPriceTierReadPage {
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
        let ListField::Strings(list) = self.lists.field(list_id)? else {
            return Err(wrong_field());
        };
        let result = page(
            PageBinding::List(list_id),
            self.strings_source(list)?.len(),
            offset,
            limit,
            |index, inline| {
                Ok(TextReadItem {
                    value: self.read(TextField::String(list, index), inline)?,
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
}
