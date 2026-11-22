use super::{
    body::{
        BusinessEnvelope, PendingBody, decode_business_head_from_record, pack_bodies,
        read_event_body_bytes,
    },
    db::{self, Record},
    types::milliseconds_from_seconds,
    *,
};
use pl_core::{
    model::ModelUsage,
    thread::{UsageSummary, current::RuntimeEpoch},
    usage::{UsageCacheSummary, UsageOutcome, UsageSource, UsageTotals},
};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct HistoryUsageFact {
    pub event_id: String,
    pub runtime_epoch: RuntimeEpoch,
    pub turn_id: Option<String>,
    pub outcome: UsageOutcome,
    pub record: crate::InferenceBillingRecord,
}

/// Immutable usage/accounting candidates for one admission unit.
#[derive(Debug, Clone)]
pub(crate) struct PreparedHistoryUsage {
    pub(crate) events: Vec<HistoryEvent>,
    pub(crate) accepted_sequence: Option<u64>,
}

#[derive(Debug, Clone)]
struct UsageFold {
    events: Vec<HistoryEvent>,
    summary: UsageSummary,
    has_incomplete_usage: bool,
    has_unpriced_usage: bool,
    legacy_cache_count_unknown: bool,
    accounting_anchor: bool,
    costs: BTreeMap<String, HistoryCostHead>,
}

impl UsageFold {
    fn record(&mut self, fact: &HistoryUsageFact, database_id: &str) -> Result<()> {
        let recorded_at = milliseconds_from_seconds(fact.record.recorded_at)?;
        let payload = serde_json::to_vec(&fact.record)?;
        self.summary.add_usage(
            &ModelUsage {
                input_tokens: fact.record.accounting.usage.input_tokens,
                output_tokens: fact.record.accounting.usage.output_tokens,
                cache_read_tokens: fact.record.accounting.usage.cache_read_tokens,
                cache_write_tokens: fact.record.accounting.usage.cache_write_tokens,
                reasoning_tokens: fact.record.accounting.usage.reasoning_tokens,
                total_tokens: fact.record.accounting.usage.total_tokens,
            },
            UsageSource {
                thread_id: String::new(),
                call_id: fact.record.inference_id.clone(),
                turn_id: fact.turn_id.clone(),
                effect_sequence: 0,
                observed_at: fact.record.recorded_at,
                purpose: fact.record.purpose.clone(),
                outcome: fact.outcome,
            },
            false,
            None,
        );
        self.has_incomplete_usage |= self.summary.has_incomplete_usage();
        self.has_unpriced_usage |= fact.record.accounting.has_unpriced_usage();

        let cache = &self.summary.cache;
        let head = HistoryAccountingHead {
            prompt_tokens: self.summary.totals.prompt_tokens,
            completion_tokens: self.summary.totals.completion_tokens,
            cached_prompt_tokens: self.summary.totals.cached_prompt_tokens,
            cache_write_tokens: self.summary.totals.cache_write_tokens,
            reasoning_tokens: self.summary.totals.reasoning_tokens,
            inference_count: self.summary.totals.inference_count,
            total_tokens: self.summary.totals.total_tokens,
            cache_usage: CacheUsageSummary {
                sample_count: cache.sample_count,
                legacy_sample_count_unknown: self.legacy_cache_count_unknown,
                input_tokens: cache.input_tokens,
                cache_read_tokens: cache.read_tokens,
                hit_rate: (cache.input_tokens != 0)
                    .then(|| cache.read_tokens as f64 / cache.input_tokens as f64),
                has_incomplete_usage: cache.incomplete,
            },
            has_incomplete_usage: self.has_incomplete_usage,
            has_unpriced_usage: self.has_unpriced_usage,
            updated_at: recorded_at,
            detail_event_id: Some(fact.event_id.clone()),
        };
        let mut event = HistoryEvent::new(
            &fact.event_id,
            HistoryEventKind::UsageRecorded,
            HistoryTimelineRole::Hidden,
            recorded_at,
        );
        event.run_id = Some(fact.runtime_epoch.to_string());
        event.turn_id = fact.turn_id.clone();
        event.row_scope = Some(HistoryBusinessRowScope::Accounting);
        event.row_key = Some("accounting:session".into());
        event.is_anchor = !self.accounting_anchor;
        let bodies = pack_bodies(
            &mut event,
            vec![PendingBody::new(
                "accounting",
                HistoryBodyRole::Other {
                    name: "accounting".into(),
                },
                Some("application/json".into()),
                payload,
            )],
            database_id,
        )?;
        event.payload_schema = "anywork.accounting/1".into();
        event.payload_json = serde_json::to_string(&BusinessEnvelope { head, bodies })?;
        self.accounting_anchor = true;
        self.events.push(event);
        let costs = self.cost_events(fact, recorded_at)?;
        self.events.extend(costs);
        Ok(())
    }

    fn cost_events(
        &mut self,
        fact: &HistoryUsageFact,
        recorded_at: i64,
    ) -> Result<Vec<HistoryEvent>> {
        let savings_by_currency = fact
            .record
            .accounting
            .estimated_cache_savings()
            .into_iter()
            .map(|saving| (saving.currency.clone(), saving.amount))
            .collect::<BTreeMap<_, _>>();
        let mut events = Vec::new();
        for cost in fact.record.accounting.estimated_costs() {
            let mut head = HistoryCostHead {
                purpose: fact.record.purpose.clone(),
                currency: cost.currency.clone(),
                cost_delta: Some(cost.amount),
                cost_total: cost.amount,
                cache_savings_delta: None,
                cache_savings_total: None,
                updated_at: recorded_at,
                detail_event_id: Some(fact.event_id.clone()),
            };
            let key = head.row_key()?;
            let savings = savings_by_currency.get(&cost.currency).copied();
            let previous = self.costs.get(&key).cloned();
            head.cache_savings_delta = savings;
            let anchor = previous.is_none();
            if let Some(previous) = previous {
                head.cost_total += previous.cost_total;
                head.cache_savings_total = previous
                    .cache_savings_total
                    .zip(savings)
                    .map(|(previous, delta)| previous + delta);
            } else {
                head.cache_savings_total = savings;
            }
            let mut event = HistoryEvent::new(
                format!("usage_cost:{}:{key}", fact.event_id),
                HistoryEventKind::UsageRecorded,
                HistoryTimelineRole::Hidden,
                recorded_at,
            );
            event.run_id = Some(fact.runtime_epoch.to_string());
            event.turn_id = fact.turn_id.clone();
            event.row_scope = Some(HistoryBusinessRowScope::Cost);
            event.row_key = Some(key.clone());
            event.is_anchor = anchor;
            event.payload_schema = "anywork.cost/1".into();
            event.payload_json = serde_json::to_string(&BusinessEnvelope {
                head: head.clone(),
                bodies: Vec::new(),
            })?;
            self.costs.insert(key, head);
            events.push(event);
        }
        Ok(events)
    }
}

impl HistoryStore {
    pub async fn record_usage(&self, fact: &HistoryUsageFact) -> Result<u64> {
        let admission = self.admission_guard().await;
        let prepared = self
            .prepare_usage(&admission, std::slice::from_ref(fact))
            .await?;
        if let Some(sequence) = prepared.accepted_sequence {
            return Ok(sequence);
        }
        let mut sequences = self.accept_locked(&admission, &prepared.events).await;
        if matches!(sequences, Err(HistoryError::Capacity)) {
            self.flush().await?;
            sequences = self.accept_locked(&admission, &prepared.events).await;
        }
        let sequences = sequences?;
        Ok(sequences[0])
    }

    pub(crate) async fn prepare_usage(
        &self,
        _admission: &tokio::sync::MutexGuard<'_, ()>,
        facts: &[HistoryUsageFact],
    ) -> Result<PreparedHistoryUsage> {
        {
            let state = self
                .inner
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if !state.accepting {
                return Err(HistoryError::Closed);
            }
        }
        if facts.is_empty() {
            return Ok(PreparedHistoryUsage {
                events: Vec::new(),
                accepted_sequence: None,
            });
        }
        let mut identities = BTreeSet::new();
        for fact in facts {
            if !identities.insert(fact.event_id.as_str()) {
                return Err(HistoryError::Conflict(
                    "duplicate usage event identity within a batch".into(),
                ));
            }
        }
        if facts.len() > 1 {
            for fact in facts {
                if self.accepted_usage_sequence(fact).await?.is_some() {
                    return Err(HistoryError::Integrity(
                        "prepared usage effect mixes already accepted facts".into(),
                    ));
                }
            }
        } else if let [fact] = facts
            && let Some(sequence) = self.accepted_usage_sequence(fact).await?
        {
            return Ok(PreparedHistoryUsage {
                events: Vec::new(),
                accepted_sequence: Some(sequence),
            });
        }

        let previous = match self.latest_record("accounting:session").await? {
            None => HistoryAccountingHead::default(),
            Some(record) => match decode_business_head_from_record(&record.record)? {
                HistoryBusinessRowHead::Accounting(head) => head,
                _ => {
                    return Err(HistoryError::Integrity(
                        "accounting row has another head type".into(),
                    ));
                }
            },
        };

        let mut cost_rows = BTreeSet::new();
        for fact in facts {
            for cost in fact.record.accounting.estimated_costs() {
                let key = HistoryCostHead {
                    purpose: fact.record.purpose.clone(),
                    currency: cost.currency.clone(),
                    cost_delta: None,
                    cost_total: 0.0,
                    cache_savings_delta: None,
                    cache_savings_total: None,
                    updated_at: 0,
                    detail_event_id: None,
                }
                .row_key()?;
                cost_rows.insert(key);
            }
        }
        let mut costs = BTreeMap::new();
        for key in cost_rows {
            if let Some(record) = self.latest_record(&key).await? {
                match decode_business_head_from_record(&record.record)? {
                    HistoryBusinessRowHead::Cost(head) => {
                        costs.insert(key, head);
                    }
                    _ => {
                        return Err(HistoryError::Integrity(
                            "cost row has another head type".into(),
                        ));
                    }
                }
            }
        }

        let mut fold = UsageFold {
            events: Vec::new(),
            summary: UsageSummary {
                totals: UsageTotals {
                    prompt_tokens: previous.prompt_tokens,
                    completion_tokens: previous.completion_tokens,
                    cached_prompt_tokens: previous.cached_prompt_tokens,
                    cache_write_tokens: previous.cache_write_tokens,
                    reasoning_tokens: previous.reasoning_tokens,
                    inference_count: previous.inference_count,
                    total_tokens: previous.total_tokens,
                },
                cache: UsageCacheSummary {
                    input_tokens: previous.cache_usage.input_tokens,
                    read_tokens: previous.cache_usage.cache_read_tokens,
                    sample_count: previous.cache_usage.sample_count,
                    incomplete: previous.cache_usage.has_incomplete_usage,
                },
                ..Default::default()
            },
            has_incomplete_usage: previous.has_incomplete_usage,
            has_unpriced_usage: previous.has_unpriced_usage,
            legacy_cache_count_unknown: previous.cache_usage.legacy_sample_count_unknown,
            accounting_anchor: self.anchor_exists("accounting:session").await?,
            costs,
        };
        for fact in facts {
            fold.record(fact, self.database_id())?;
        }
        Ok(PreparedHistoryUsage {
            events: fold.events,
            accepted_sequence: None,
        })
    }

    async fn accepted_usage_sequence(&self, fact: &HistoryUsageFact) -> Result<Option<u64>> {
        let payload = serde_json::to_vec(&fact.record)?;
        let pending = {
            let state = self
                .inner
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            state.pending.clone()
        };
        let record = if let Some(accepted) = pending.event(&fact.event_id) {
            Record::from_event(&accepted.event).record
        } else if let Some(old) = db::event(&self.inner.reader, &fact.event_id).await? {
            old.record
        } else {
            return Ok(None);
        };
        let reader = self.reader();
        let existing = match read_event_body_bytes(&reader, &record, "accounting", None).await? {
            Some(bytes) => bytes,
            None => {
                // Legacy v25 migrated usage row may hold key "canonical_payload" in history_bodies
                read_event_body_bytes(&reader, &record, "canonical_payload", None)
                    .await?
                    .ok_or_else(|| HistoryError::Conflict(fact.event_id.clone()))?
            }
        };
        if existing == payload {
            Ok(Some(record.seq))
        } else {
            Err(HistoryError::Conflict(fact.event_id.clone()))
        }
    }
}
