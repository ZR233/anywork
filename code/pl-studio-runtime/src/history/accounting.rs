use super::*;
use pl_core::{
    model::ModelUsage,
    thread::{UsageSummary, current::RuntimeEpoch},
    usage::{UsageCacheSummary, UsageOutcome, UsageSource, UsageTotals},
};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct HistoryUsageFact {
    pub event_id: String,
    pub runtime_epoch: RuntimeEpoch,
    pub turn_id: Option<String>,
    pub outcome: UsageOutcome,
    pub record: pl_protocol::InferenceBillingRecord,
}

impl HistoryStore {
    /// Folds the existing Core usage reducer into one fixed history summary. Costs are loaded by
    /// their exact purpose/currency key; committed calls and purpose lists are never replayed.
    pub async fn record_usage(&self, fact: &HistoryUsageFact) -> Result<u64> {
        let _admission = self.inner.admission.lock().await;
        let payload = serde_json::to_vec(&fact)?;
        let pending = self
            .inner
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .pending
            .clone();
        if let Some(accepted) = pending.event(&fact.event_id) {
            let same = accepted
                .event
                .bodies
                .iter()
                .find(|body| body.role == HistoryBodyRole::CanonicalPayload)
                .is_some_and(|body| body.bytes.as_ref() == payload);
            return if same {
                Ok(accepted.event.header.seq)
            } else {
                Err(HistoryError::Conflict(fact.event_id.clone()))
            };
        }
        if let Some(old) = db::event(&self.inner.reader, &fact.event_id).await? {
            let body_id = old
                .payload_body_id
                .ok_or_else(|| HistoryError::Conflict(fact.event_id.clone()))?;
            let body = db::body(&self.inner.reader, &body_id)
                .await?
                .ok_or_else(|| HistoryError::Integrity("usage payload is missing".into()))?;
            if body.length != payload.len() as u64 {
                return Err(HistoryError::Conflict(fact.event_id.clone()));
            }
            for (chunk, bytes) in payload.chunks(BODY_CHUNK_BYTES).enumerate() {
                if db::window(
                    &self.inner.reader,
                    &body,
                    (chunk * BODY_CHUNK_BYTES) as u64,
                    bytes.len(),
                )
                .await?
                    != bytes
                {
                    return Err(HistoryError::Conflict(fact.event_id.clone()));
                }
            }
            return Ok(old.header.seq);
        }
        let previous = match self
            .latest_record("accounting:session")
            .await?
            .and_then(|record| record.head)
        {
            None => HistoryAccountingHead::default(),
            Some(HistoryRowHead::Accounting(head)) => head,
            Some(_) => {
                return Err(HistoryError::Integrity(
                    "accounting row has another head type".into(),
                ));
            }
        };
        let mut summary = UsageSummary {
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
        };
        let usage = &fact.record.accounting.usage;
        summary.add_usage(
            &ModelUsage {
                input_tokens: usage.input_tokens,
                output_tokens: usage.output_tokens,
                cache_read_tokens: usage.cache_read_tokens,
                cache_write_tokens: usage.cache_write_tokens,
                reasoning_tokens: usage.reasoning_tokens,
                total_tokens: usage.total_tokens,
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
        let cache = &summary.cache;
        let head = HistoryAccountingHead {
            prompt_tokens: summary.totals.prompt_tokens,
            completion_tokens: summary.totals.completion_tokens,
            cached_prompt_tokens: summary.totals.cached_prompt_tokens,
            cache_write_tokens: summary.totals.cache_write_tokens,
            reasoning_tokens: summary.totals.reasoning_tokens,
            inference_count: summary.totals.inference_count,
            total_tokens: summary.totals.total_tokens,
            cache_usage: CacheUsageSummary {
                sample_count: cache.sample_count,
                legacy_sample_count_unknown: previous.cache_usage.legacy_sample_count_unknown,
                input_tokens: cache.input_tokens,
                cache_read_tokens: cache.read_tokens,
                hit_rate: (cache.input_tokens != 0)
                    .then(|| cache.read_tokens as f64 / cache.input_tokens as f64),
                has_incomplete_usage: cache.incomplete,
            },
            has_incomplete_usage: previous.has_incomplete_usage || summary.has_incomplete_usage(),
            has_unpriced_usage: previous.has_unpriced_usage
                || fact.record.accounting.has_unpriced_usage(),
            updated_at: fact.record.recorded_at,
            detail_event_id: Some(fact.event_id.clone()),
        };
        let mut event = HistoryEvent::new(
            &fact.event_id,
            HistoryEventKind::UsageRecorded,
            fact.record.recorded_at,
        );
        event.header.run_id = Some(fact.runtime_epoch.to_string());
        event.header.turn_id = fact.turn_id.clone();
        event.header.row_key = Some("accounting:session".into());
        event.is_anchor = !self.anchor_exists("accounting:session").await?;
        event.head = Some(HistoryRowHead::Accounting(head));
        let body = HistoryBody::new("accounting", HistoryBodyRole::CanonicalPayload, payload);
        event.payload_body_id = Some(body.body_id.clone());
        event.bodies.push(body);
        let mut events = vec![event];
        for cost in fact.record.accounting.estimated_costs() {
            let mut head = HistoryCostHead {
                purpose: fact.record.purpose.clone(),
                currency: cost.currency.clone(),
                cost_delta: Some(cost.amount),
                cost_total: cost.amount,
                cache_savings_delta: None,
                cache_savings_total: None,
                updated_at: fact.record.recorded_at,
                detail_event_id: Some(fact.event_id.clone()),
            };
            let key = head.row_key()?;
            let previous = self
                .latest_record(&key)
                .await?
                .and_then(|record| record.head);
            let savings = fact
                .record
                .accounting
                .estimated_cache_savings()
                .into_iter()
                .find(|saving| saving.currency == cost.currency)
                .map(|saving| saving.amount);
            head.cache_savings_delta = savings;
            let anchor = previous.is_none();
            if let Some(previous) = previous {
                let HistoryRowHead::Cost(previous) = previous else {
                    return Err(HistoryError::Integrity(
                        "cost row has another head type".into(),
                    ));
                };
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
                fact.record.recorded_at,
            );
            event.header.run_id = Some(fact.runtime_epoch.to_string());
            event.header.turn_id = fact.turn_id.clone();
            event.header.row_key = Some(key);
            event.is_anchor = anchor;
            event.head = Some(HistoryRowHead::Cost(head));
            events.push(event);
        }
        let sequences = self.accept_locked(&events).await?;
        Ok(sequences[0])
    }
}
