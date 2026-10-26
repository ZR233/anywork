use super::super::models::page_budget::{PageBinding, page};
use super::super::read_budget::{FieldTable, bounded_header, count, text_chunk};
use super::source::{IdentityMaterial, IdentityValue, Key, Root, StatisticsMaterial};
use pl_protocol::products::identity::ProductEntityRef;
use pl_protocol::products::read::primitives::TypedListRef;
use pl_protocol::products::read::statistics::*;
use pl_protocol::products::references::{
    PerformanceEffortIdentityRef, PerformanceSampleIdentityRef, PerformanceSummaryIdentityRef,
};
use pl_protocol::studio::{ReadText, StudioError, StudioErrorCode, TextChunk};
use std::sync::Arc;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Text {
    Root,
    Purpose(usize),
    Currency(Option<usize>, usize),
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum List {
    Summaries,
    Samples,
    Efforts(usize),
    Purposes,
    Amounts(Option<usize>),
}
pub(super) struct StatisticsReadMaterial {
    source: Arc<StatisticsMaterial>,
    texts: FieldTable<Text>,
    lists: FieldTable<List>,
}
impl StatisticsReadMaterial {
    pub fn new(source: Arc<StatisticsMaterial>) -> Self {
        Self {
            source,
            texts: FieldTable::default(),
            lists: FieldTable::default(),
        }
    }
    /// 固定读取数据只来自材料本身；发布状态不在材料里，读取不暴露它。
    fn summary_values(&self) -> Result<&[crate::statistics::StudioModelPerformanceSummary], StudioError> {
        match &self.source.root {
            Root::Summaries(summaries) => Ok(summaries),
            Root::History { .. } | Root::Costs(_) => Err(wrong()),
        }
    }
    fn sample_values(&self) -> Result<&[crate::statistics::StudioModelPerformanceSample], StudioError> {
        match &self.source.root {
            Root::History { samples, .. } => Ok(samples),
            Root::Summaries(_) | Root::Costs(_) => Err(wrong()),
        }
    }
    fn cost(&self) -> Result<&crate::StudioSessionCostSnapshot, StudioError> {
        match &self.source.root {
            Root::Costs(cost) => cost.as_ref().ok_or_else(wrong),
            Root::Summaries(_) | Root::History { .. } => Err(wrong()),
        }
    }
    fn list(&self, key: List, len: usize) -> Result<TypedListRef, StudioError> {
        Ok(TypedListRef {
            list_id: self.lists.register(key)?,
            total: count(len)?,
        })
    }
    fn read(&self, field: Text, inline: usize) -> Result<ReadText, StudioError> {
        self.texts.read(field, self.text_source(field)?, inline)
    }
    pub fn summaries_header(&self) -> Result<PerformanceSummariesReadHeader, StudioError> {
        if self.source.key != Key::Summaries {
            return Err(wrong());
        }
        Ok(PerformanceSummariesReadHeader {
            summaries: self.list(List::Summaries, self.summary_values()?.len())?,
        })
    }
    pub fn history_header(&self) -> Result<PerformanceHistoryReadHeader, StudioError> {
        if self.source.key != Key::History {
            return Err(wrong());
        }
        Ok(PerformanceHistoryReadHeader {
            samples: self.list(List::Samples, self.sample_values()?.len())?,
        })
    }
    pub fn costs_header(&self) -> Result<SessionCostsReadHeader, StudioError> {
        let Root::Costs(cost) = &self.source.root else {
            return Err(wrong());
        };
        bounded_header(|inline| {
            Ok(SessionCostsReadHeader {
                cost: cost
                    .as_ref()
                    .map(|cost| -> Result<_, StudioError> {
                        Ok(SessionCostRead {
                            root_thread_id: self.read(Text::Root, inline)?,
                            purpose_costs: self.list(List::Purposes, cost.purpose_costs.len())?,
                            estimated_costs: self
                                .list(List::Amounts(None), cost.estimated_costs.len())?,
                            has_unpriced_usage: cost.has_unpriced_usage,
                        })
                    })
                    .transpose()?,
            })
        })
    }
    fn summary(&self, index: usize) -> Result<PerformanceSummaryRead, StudioError> {
        let value = self.summary_values()?.get(index).ok_or_else(wrong)?;
        let identity = self
            .source
            .identities
            .get(index)
            .ok_or_else(wrong)?
            .reference;
        Ok(PerformanceSummaryRead {
            identity: PerformanceSummaryIdentityRef {
                entry: identity.entry,
                revision: identity.revision,
            },
            counters: value.clone().into(),
            effort_breakdowns: self.list(List::Efforts(index), value.effort_breakdowns.len())?,
        })
    }
    fn sample(&self, index: usize) -> Result<PerformanceSampleRead, StudioError> {
        let value = self.sample_values()?.get(index).ok_or_else(wrong)?;
        let identity = self
            .source
            .identities
            .get(index)
            .ok_or_else(wrong)?
            .reference;
        Ok(PerformanceSampleRead {
            identity: PerformanceSampleIdentityRef {
                entry: identity.entry,
                revision: identity.revision,
            },
            counters: PerformanceSampleCounters {
                completed_at: value.completed_at,
                completion_tokens: value.completion_tokens,
                ttft_millis: value.ttft_millis,
                decode_millis: value.decode_millis,
                total_response_millis: value.total_response_millis,
                tokens_per_second: value.tokens_per_second,
            },
        })
    }
    fn entity_index(&self, reference: ProductEntityRef) -> Result<usize, StudioError> {
        let index = self
            .source
            .entities
            .iter()
            .position(|entry| entry.entry == reference.entry)
            .ok_or_else(|| StudioError::not_found("Statistics member"))?;
        if self.source.entities[index] != reference {
            return Err(StudioError::new(
                StudioErrorCode::Superseded,
                "Statistics entity revision is not in this immutable scope",
                false,
            ));
        }
        Ok(index)
    }
    pub fn summaries_entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<PerformanceSummariesEntryPage, StudioError> {
        if self.source.key != Key::Summaries {
            return Err(wrong());
        }
        let collection = self.source.collection.ok_or_else(wrong)?;
        let result = page(
            PageBinding::Collection(collection),
            self.source.entities.len(),
            offset,
            limit,
            |index, _| Ok(self.source.entities[index]),
        )?;
        Ok(PerformanceSummariesEntryPage {
            collection,
            offset,
            items: result.items,
            next_offset: result.next_offset,
        })
    }
    pub fn history_entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<PerformanceHistoryEntryPage, StudioError> {
        if self.source.key != Key::History {
            return Err(wrong());
        }
        let collection = self.source.collection.ok_or_else(wrong)?;
        let result = page(
            PageBinding::Collection(collection),
            self.source.entities.len(),
            offset,
            limit,
            |index, _| Ok(self.source.entities[index]),
        )?;
        Ok(PerformanceHistoryEntryPage {
            collection,
            offset,
            items: result.items,
            next_offset: result.next_offset,
        })
    }
    pub fn summary_entity(
        &self,
        reference: ProductEntityRef,
    ) -> Result<PerformanceSummariesEntityRead, StudioError> {
        if self.source.key != Key::Summaries {
            return Err(wrong());
        }
        Ok(PerformanceSummariesEntityRead {
            reference,
            value: self.summary(self.entity_index(reference)?)?,
        })
    }
    pub fn sample_entity(
        &self,
        reference: ProductEntityRef,
    ) -> Result<PerformanceHistoryEntityRead, StudioError> {
        if self.source.key != Key::History {
            return Err(wrong());
        }
        Ok(PerformanceHistoryEntityRead {
            reference,
            value: self.sample(self.entity_index(reference)?)?,
        })
    }
    pub fn lookup_summary(
        &self,
        account: &str,
        model: &str,
    ) -> Result<Option<ProductEntityRef>, StudioError> {
        if self.source.key != Key::Summaries {
            return Err(wrong());
        }
        Ok(self
            .summary_values()?
            .iter()
            .position(|value| value.account_id == account && value.model_id == model)
            .map(|index| self.source.entities[index]))
    }
    pub fn summaries(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<PerformanceSummaryReadPage, StudioError> {
        if self.lists.field(list_id)? != List::Summaries {
            return Err(wrong());
        }
        let result = page(
            PageBinding::List(list_id),
            self.summary_values()?.len(),
            offset,
            limit,
            |index, _| self.summary(index),
        )?;
        Ok(PerformanceSummaryReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }
    pub fn effort_breakdowns(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<PerformanceEffortReadPage, StudioError> {
        let List::Efforts(summary) = self.lists.field(list_id)? else {
            return Err(wrong());
        };
        let values = &self
            .summary_values()?
            .get(summary)
            .ok_or_else(wrong)?
            .effort_breakdowns;
        let result = page(
            PageBinding::List(list_id),
            values.len(),
            offset,
            limit,
            |index, _| {
                let identity = self
                    .source
                    .efforts
                    .get(summary)
                    .and_then(|values| values.get(index))
                    .ok_or_else(wrong)?
                    .reference;
                Ok(PerformanceEffortRead {
                    identity: PerformanceEffortIdentityRef {
                        entry: identity.entry,
                        revision: identity.revision,
                    },
                    counters: values[index].clone().into(),
                })
            },
        )?;
        Ok(PerformanceEffortReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }
    pub fn samples(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<PerformanceSampleReadPage, StudioError> {
        if self.lists.field(list_id)? != List::Samples {
            return Err(wrong());
        }
        let result = page(
            PageBinding::List(list_id),
            self.sample_values()?.len(),
            offset,
            limit,
            |index, _| self.sample(index),
        )?;
        Ok(PerformanceSampleReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }
    pub fn purposes(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<PurposeCostReadPage, StudioError> {
        if self.lists.field(list_id)? != List::Purposes {
            return Err(wrong());
        }
        let values = &self.cost()?.purpose_costs;
        let result = page(
            PageBinding::List(list_id),
            values.len(),
            offset,
            limit,
            |index, inline| {
                let value = &values[index];
                Ok(PurposeCostRead {
                    purpose: value
                        .purpose
                        .as_ref()
                        .map(|_| self.read(Text::Purpose(index), inline))
                        .transpose()?,
                    estimated_costs: self
                        .list(List::Amounts(Some(index)), value.estimated_costs.len())?,
                    has_unpriced_usage: value.has_unpriced_usage,
                })
            },
        )?;
        Ok(PurposeCostReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }
    pub fn amounts(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<RuntimeCostReadPage, StudioError> {
        let List::Amounts(purpose) = self.lists.field(list_id)? else {
            return Err(wrong());
        };
        let values = match purpose {
            None => &self.cost()?.estimated_costs,
            Some(index) => {
                &self
                    .cost()?
                    .purpose_costs
                    .get(index)
                    .ok_or_else(wrong)?
                    .estimated_costs
            }
        };
        let result = page(
            PageBinding::List(list_id),
            values.len(),
            offset,
            limit,
            |index, inline| {
                Ok(RuntimeCostRead {
                    currency: self.read(Text::Currency(purpose, index), inline)?,
                    amount: values[index].amount,
                })
            },
        )?;
        Ok(RuntimeCostReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }
    pub fn text(
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
    fn text_source(&self, field: Text) -> Result<&str, StudioError> {
        let cost = self.cost()?;
        Ok(match field {
            Text::Root => &cost.root_thread_id,
            Text::Purpose(index) => cost
                .purpose_costs
                .get(index)
                .and_then(|value| value.purpose.as_deref())
                .ok_or_else(wrong)?,
            Text::Currency(purpose, index) => {
                let values = match purpose {
                    None => &cost.estimated_costs,
                    Some(index) => {
                        &cost
                            .purpose_costs
                            .get(index)
                            .ok_or_else(wrong)?
                            .estimated_costs
                    }
                };
                &values.get(index).ok_or_else(wrong)?.currency
            }
        })
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum IdentityText {
    Account,
    DisplayName,
    Model,
    Sent,
    Reported,
    Effort,
}
pub(super) struct StatisticsIdentityReadMaterial {
    source: Arc<IdentityMaterial>,
    texts: FieldTable<IdentityText>,
}
impl StatisticsIdentityReadMaterial {
    pub fn new(source: Arc<IdentityMaterial>) -> Self {
        Self {
            source,
            texts: FieldTable::default(),
        }
    }
    fn read(&self, field: IdentityText, inline: usize) -> Result<ReadText, StudioError> {
        self.texts.read(field, self.text_source(field)?, inline)
    }
    pub fn summary(&self) -> Result<PerformanceSummaryIdentityRead, StudioError> {
        if !matches!(self.source.value, IdentityValue::Summary { .. }) {
            return Err(wrong());
        }
        bounded_header(|inline| {
            Ok(PerformanceSummaryIdentityRead {
                account_id: self.read(IdentityText::Account, inline)?,
                account_display_name: self.read(IdentityText::DisplayName, inline)?,
                model_id: self.read(IdentityText::Model, inline)?,
            })
        })
    }
    pub fn effort(&self) -> Result<PerformanceEffortIdentityRead, StudioError> {
        let IdentityValue::Effort(value) = &self.source.value else {
            return Err(wrong());
        };
        bounded_header(|inline| {
            Ok(PerformanceEffortIdentityRead {
                effort: value
                    .as_ref()
                    .map(|_| self.read(IdentityText::Effort, inline))
                    .transpose()?,
            })
        })
    }
    pub fn sample(&self) -> Result<PerformanceSampleIdentityRead, StudioError> {
        let IdentityValue::Sample {
            model_id,
            sent_model,
            reported_model,
            model_match_state,
            effort,
            ..
        } = &self.source.value
        else {
            return Err(wrong());
        };
        bounded_header(|inline| {
            Ok(PerformanceSampleIdentityRead {
                account_id: self.read(IdentityText::Account, inline)?,
                account_display_name: self.read(IdentityText::DisplayName, inline)?,
                model_id: model_id
                    .as_ref()
                    .map(|_| self.read(IdentityText::Model, inline))
                    .transpose()?,
                sent_model: sent_model
                    .as_ref()
                    .map(|_| self.read(IdentityText::Sent, inline))
                    .transpose()?,
                reported_model: reported_model
                    .as_ref()
                    .map(|_| self.read(IdentityText::Reported, inline))
                    .transpose()?,
                model_match_state: *model_match_state,
                effort: effort
                    .as_ref()
                    .map(|_| self.read(IdentityText::Effort, inline))
                    .transpose()?,
            })
        })
    }
    pub fn text(
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
    fn text_source(&self, field: IdentityText) -> Result<&str, StudioError> {
        match (&self.source.value, field) {
            (
                IdentityValue::Summary { account_id, .. }
                | IdentityValue::Sample { account_id, .. },
                IdentityText::Account,
            ) => Ok(account_id),
            (
                IdentityValue::Summary {
                    account_display_name,
                    ..
                }
                | IdentityValue::Sample {
                    account_display_name,
                    ..
                },
                IdentityText::DisplayName,
            ) => Ok(account_display_name),
            (IdentityValue::Summary { model_id, .. }, IdentityText::Model) => Ok(model_id),
            (IdentityValue::Sample { model_id, .. }, IdentityText::Model) => {
                model_id.as_deref().ok_or_else(wrong)
            }
            (IdentityValue::Sample { sent_model, .. }, IdentityText::Sent) => {
                sent_model.as_deref().ok_or_else(wrong)
            }
            (IdentityValue::Sample { reported_model, .. }, IdentityText::Reported) => {
                reported_model.as_deref().ok_or_else(wrong)
            }
            (
                IdentityValue::Effort(effort) | IdentityValue::Sample { effort, .. },
                IdentityText::Effort,
            ) => effort.as_deref().ok_or_else(wrong),
            _ => Err(wrong()),
        }
    }
}
// These are existing native counters; never recompute, sort, estimate or replace missing values.
macro_rules! counters {
    ($source:ty) => {
        impl From<$source> for PerformanceCounters {
            fn from(value: $source) -> Self {
                Self {
                    sample_count: value.sample_count,
                    completion_tokens: value.completion_tokens,
                    total_ttft_millis: value.total_ttft_millis,
                    ttft_sample_count: value.ttft_sample_count,
                    total_response_millis: value.total_response_millis,
                    tokens_per_second: value.tokens_per_second,
                    average_ttft_millis: value.average_ttft_millis,
                    average_response_millis: value.average_response_millis,
                }
            }
        }
    };
}
counters!(crate::statistics::StudioModelPerformanceSummary);
counters!(crate::statistics::StudioModelPerformanceEffortSummary);
fn wrong() -> StudioError {
    StudioError::invalid_argument("Unknown field, list or variant in this Statistics scope")
}
