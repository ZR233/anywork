use std::sync::Arc;

use pl_protocol::RuntimeCostAmount;
use pl_protocol::studio::{ReadText, StudioError, TextChunk};
use pl_protocol::thread_facets::identity::ReadScopeIdentity;
use pl_protocol::thread_facets::read::values::{ContextReadHeader, CostPage, CostReadItem};

use super::super::read_budget::{FieldTable, bounded_header, count, protocol, text_chunk};
use super::budget::{page, validate_revision};

/// Built at the context publication boundary, independently of token-speed samples and of the
/// current model policy. A missing frozen binding must not be filled from Configuration.
#[derive(PartialEq)]
pub(super) struct ContextSource {
    pub(super) revision: u64,
    pub(super) frozen_model_id: Option<String>,
    pub(super) prompt_cache_policy: Option<String>,
    pub(super) estimated_costs: Vec<RuntimeCostAmount>,
    pub(super) estimated_cache_savings: Vec<RuntimeCostAmount>,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum CostList { Costs, CacheSavings }
#[derive(Clone, Copy, PartialEq, Eq)]
enum Field { Model, CachePolicy, Currency(CostList, usize) }

pub(super) struct ContextMaterial {
    scope: ReadScopeIdentity,
    source: Arc<ContextSource>,
    fields: FieldTable<Field>,
}

impl ContextMaterial {
    pub(super) fn new(scope: ReadScopeIdentity, source: Arc<ContextSource>) -> Result<Self, StudioError> {
        validate_revision(&scope, source.revision)?;
        if source.estimated_costs.iter().chain(&source.estimated_cache_savings).any(|cost| !cost.amount.is_finite()) {
            return Err(protocol("Context cost is not a finite JSON number"));
        }
        Ok(Self { scope, source, fields: FieldTable::default() })
    }

    pub(super) fn header(&self) -> Result<ContextReadHeader, StudioError> {
        bounded_header(|inline| Ok(ContextReadHeader { scope: self.scope.clone(),
            frozen_model_id: self.source.frozen_model_id.as_ref().map(|_| self.read(Field::Model, inline)).transpose()?,
            prompt_cache_policy: self.source.prompt_cache_policy.as_ref().map(|_| self.read(Field::CachePolicy, inline)).transpose()?,
            estimated_cost_count: count(self.source.estimated_costs.len())?,
            estimated_cache_saving_count: count(self.source.estimated_cache_savings.len())?,
        }))
    }

    pub(super) fn costs(&self, offset: u64, limit: u32) -> Result<CostPage, StudioError> {
        self.cost_page(CostList::Costs, offset, limit)
    }

    pub(super) fn cache_savings(&self, offset: u64, limit: u32) -> Result<CostPage, StudioError> {
        self.cost_page(CostList::CacheSavings, offset, limit)
    }

    pub(super) fn text(&self, field_id: u64, offset: u64, max_bytes: u32) -> Result<TextChunk, StudioError> {
        text_chunk(field_id, self.source_text(self.fields.field(field_id)?)?, offset, max_bytes)
    }

    fn cost_page(&self, list: CostList, offset: u64, limit: u32) -> Result<CostPage, StudioError> {
        let costs = self.source_costs(list);
        let result = page(&self.scope, costs.len(), offset, limit, |index, inline| {
            Ok(CostReadItem { index: count(index)?, currency: self.read(Field::Currency(list, index), inline)?,
                amount: costs[index].amount })
        })?;
        Ok(CostPage { scope: result.scope, offset: result.offset, total: result.total,
            items: result.items, next_offset: result.next_offset })
    }

    fn source_costs(&self, list: CostList) -> &[RuntimeCostAmount] {
        match list { CostList::Costs => &self.source.estimated_costs, CostList::CacheSavings => &self.source.estimated_cache_savings }
    }

    fn read(&self, field: Field, inline: usize) -> Result<ReadText, StudioError> {
        self.fields.read(field, self.source_text(field)?, inline)
    }

    fn source_text(&self, field: Field) -> Result<&str, StudioError> {
        let value = match field {
            Field::Model => self.source.frozen_model_id.as_deref(),
            Field::CachePolicy => self.source.prompt_cache_policy.as_deref(),
            Field::Currency(list, index) => self.source_costs(list).get(index).map(|cost| cost.currency.as_str()),
        };
        value.ok_or_else(|| protocol("Text field does not address the pinned context schema"))
    }
}
