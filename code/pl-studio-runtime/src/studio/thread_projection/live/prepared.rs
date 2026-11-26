//! Immutable material and resource proofs captured for reliable History admission.
use super::{ProjectionError, memory_budget::*};
use crate::history::{HistoryEvent, HistorySourceHead, HistoryTurnHead, HistoryTurnState};
use crate::studio::runtime::chat_item::{BodyKey, TOOL_RESULT_FIELD};
use crate::{ExecutionItem, ExecutionShape, ThreadToolState};
use pl_core::{
    model::ContentBlock,
    thread::{ThreadEffectBatch, ThreadSnapshot, current::RuntimeEpoch},
};
use std::{collections::BTreeMap, sync::Arc};

/// The product content one committed effect contributes, projected exactly once.
///
/// It is the output of the Thread's single live projection owner: the same projection that
/// freezes the effect's completion batch and broadcasts its typed changes. The reliable
/// admission queue carries it to the history writer, which commits this exact identity/revision
/// set instead of projecting the effect a second time.
///
/// Every item carries its own **content version** (never the effect sequence that happens to
/// commit it). The writer stores that exact version and confirms it back by identity/version, so a
/// save receipt can never acknowledge a payload it did not write.
#[derive(Debug, Clone)]
pub(in crate::studio) struct PreparedEffect {
    /// Effect sequence this batch belongs to; the writer matches it against its admission queue.
    pub(in crate::studio) sequence: u64,
    /// Original journal timestamp in Unix seconds, retained across publication/ACK retries.
    pub(in crate::studio) committed_at: i64,
    pub(in crate::studio) run_id: RuntimeEpoch,
    pub(in crate::studio) accounting: Arc<super::super::PreparedAccounting>,
    /// Stateless atomic History events produced by the projection for this effect.
    pub(in crate::studio) history_events: Arc<[HistoryEvent]>,
    pub(in crate::studio) history_turns: Arc<[HistoryTurnHead]>,
    pub(in crate::studio) history_turn_details: Arc<BTreeMap<String, crate::Turn>>,
    pub(in crate::studio) history_sources: Arc<[HistorySourceHead]>,
    /// Input admissions and transitions frozen from this effect's original observation cut.
    pub(in crate::studio) retained_resources: Arc<[RetainedResourceFact]>,
    /// Turn ID transitioned to a terminal state by this exact effect (`effect.turn`), if any.
    pub(in crate::studio) terminal_turn_id: Option<String>,
    /// Exact terminal handoff, committed in the same history transaction as its terminal effect.
    pub(in crate::studio) parent_report: Option<Arc<pl_core::thread::inbox::ThreadMessage>>,
    pub(in crate::studio) parent_finish: Option<Arc<pl_tool::finish_turn::SavedFinishTurn>>,
    pub(in crate::studio) terminal_retention:
        Option<std::sync::Arc<crate::thread_assembler::review_dispatch::TerminalMaterialRetention>>,
    /// Immutable diagnostics produced by application CAS changes in this very effect.
    pub(in crate::studio) review_delivery:
        Arc<[crate::thread_assembler::review_delivery::ReviewDeliveryFact]>,
    /// True when `MetaEventBus` is already translating & admitting `HistoryEvent`s in RAM.
    pub(in crate::studio) bus_admitted: bool,
}

pub(crate) fn prepared_turns(
    items: &[ExecutionItem],
    run: RuntimeEpoch,
    effect_sequence: u64,
) -> Result<(Vec<HistoryTurnHead>, BTreeMap<String, crate::Turn>), ProjectionError> {
    let mut heads = Vec::new();
    let mut details = BTreeMap::new();
    for item in items {
        let ExecutionShape::Turn(turn) = item.state() else {
            continue;
        };
        let started_at = turn
            .state()
            .started_at()
            .map(super::history_millis)
            .transpose()?;
        let finished_at = turn
            .state()
            .completed_at()
            .map(super::history_millis)
            .transpose()?;
        let state = match turn.state() {
            crate::TurnState::Queued(_) => HistoryTurnState::Queued,
            crate::TurnState::Running(_) => HistoryTurnState::Running,
            crate::TurnState::Completed(_) => HistoryTurnState::Completed,
            crate::TurnState::Cancelled(_) => HistoryTurnState::Cancelled,
            crate::TurnState::Failed(_) => HistoryTurnState::Failed,
            crate::TurnState::BudgetLimited(_) => HistoryTurnState::BudgetLimited,
        };
        let queued_at = match turn.state() {
            crate::TurnState::Queued(state) => Some(super::history_millis(state.queued_at())?),
            _ => None,
        };
        heads.push(HistoryTurnHead {
            turn_id: item.turn_id.clone(),
            input_id: turn.input_id().map(str::to_owned),
            run_id: Some(run.to_string()),
            state,
            phase: turn.state().phase(),
            context_disposition: crate::ThreadContextDisposition::Active,
            queued_at,
            started_at,
            finished_at,
            updated_at: super::history_millis(item.updated_at)?,
            detail_event_id: None,
        });
        details.insert(
            item.turn_id.clone(),
            crate::Turn {
                input_id: turn.input_id().map(str::to_owned),
                id: item.turn_id.clone(),
                thread_id: item.thread_id.clone(),
                // `Turn.revision` belongs to the Thread-wide monotonic `effect.sequence` domain
                // (matching `prepare_turn_frames`, `project_active_turn`, `publish_last_turn`,
                // `ConversationStateFeed::reflect_terminal`, and `agent_review::baseline`),
                // unlike per-item `ExecutionItem.revision`.
                revision: effect_sequence,
                state: turn.state().clone(),
                updated_at: item.updated_at,
            },
        );
    }
    Ok((heads, details))
}

pub(super) fn history_sources(sources: &[crate::ChatSourceState]) -> Vec<HistorySourceHead> {
    sources
        .iter()
        .map(|source| HistorySourceHead {
            source: source.source.clone(),
            lifecycle: source.lifecycle.clone(),
            started_at: None,
            ended_at: None,
            observed_at: None,
            detail_event_id: None,
        })
        .collect()
}

pub(crate) fn retained_resources(
    effect: &ThreadEffectBatch,
) -> Result<Vec<RetainedResourceFact>, ProjectionError> {
    let mut facts = BTreeMap::new();
    let mut retain = |call_id: &str,
                      reference: pl_core::context::ResourceReference|
     -> Result<(), ProjectionError> {
        let key = (call_id.to_owned(), reference.id().to_owned());
        if let Some(old) = facts.get(&key) {
            if old != &reference {
                return Err(ProjectionError::History(
                    "contradictory delivered resource references".into(),
                ));
            }
        } else {
            facts.insert(key, reference);
        }
        Ok(())
    };
    for delivery in effect.deliveries.iter() {
        for reference in super::super::resource_references(delivery)? {
            retain(&delivery.call_id, reference)?;
        }
    }
    for repair in effect.delivery_repairs.iter() {
        retain(&repair.call_id, repair.reference.clone())?;
    }
    Ok(facts
        .into_iter()
        .map(|((call_id, _), reference)| {
            let turn_id = effect
                .tasks
                .iter()
                .find(|task| task.call_id == call_id)
                .map(|task| task.turn_id.clone());
            RetainedResourceFact {
                call_id,
                turn_id,
                reference,
            }
        })
        .collect())
}

pub(crate) fn review_delivery_facts(
    thread_id: &str,
    effect: &ThreadEffectBatch,
) -> anyhow::Result<Vec<crate::thread_assembler::review_delivery::ReviewDeliveryFact>> {
    use crate::thread_assembler::review_delivery::{EXTENSION_PREFIX, ReviewDeliveryFact};
    let mut facts = Vec::new();
    for change in effect.extensions.iter() {
        if let pl_core::thread::extensions::ExtensionChange::Put { id, record } = change
            && id.starts_with(EXTENSION_PREFIX)
        {
            let fact = ReviewDeliveryFact::decode(&record.payload)?;
            anyhow::ensure!(
                fact.extension_id() == *id
                    && fact.message.source_id == format!("studio.review:{thread_id}")
                    && fact.terminal_sequence < effect.sequence,
                "review delivery carrier provenance mismatch"
            );
            facts.push(fact);
        }
    }
    Ok(facts)
}

pub(crate) fn original_tool_result_body(
    item: &ExecutionItem,
    state: &ThreadSnapshot,
) -> Option<(BodyKey, Arc<ContentBlock>)> {
    let ExecutionShape::Tool(tool) = item.state() else {
        return None;
    };
    if !matches!(
        tool.state(),
        ThreadToolState::Interrupted(_) | ThreadToolState::Cancelled(_)
    ) || tool.terminal_output().is_some()
    {
        return None;
    }
    let call_id = tool.invocation().tool_call_id();
    let task_id = tool.invocation().task_id().map(str::to_owned).or_else(|| {
        state
            .tasks
            .values()
            .chain(state.terminal_tasks.iter())
            .find(|task| task.call_id == call_id)
            .map(|task| task.id.clone())
    })?;
    let progress = state.tool_progress.get(&task_id)?;
    (!progress.is_empty()).then(|| (BodyKey::host(TOOL_RESULT_FIELD), progress.content()))
}

impl PreparedEffect {
    /// The report's current share of this batch's charge, before terminal transfer.
    pub(in crate::studio) fn parent_report_retained_bytes(&self) -> u64 {
        self.parent_report.as_ref().map_or(0, |message| {
            if self.terminal_retention.is_some() {
                0
            } else {
                (message.payload.content().len() as u64)
                    .saturating_mul(2)
                    .saturating_add(message.id.len() as u64)
                    .saturating_add(self.parent_finish.as_deref().map_or(
                        0,
                        crate::thread_assembler::review_dispatch::finish_material_bytes,
                    ))
                    .saturating_add(256)
            }
        })
    }

    /// Cheap retained-memory estimate of this prepared batch, owner-provided for the reliable
    /// budget.
    ///
    /// This is the batch's one estimate — the very value the writer's reliable queue has always
    /// charged at handoff — moved next to the content it sizes, so the projection owner that
    /// builds a batch and the writer that budgets it can never drift into two formulas for one
    /// fact. It stays the established conservative estimate rather than a claim of exact physical
    /// memory: resident item bodies use `charged_item_bytes` below (every
    /// variable-length body plus each item's fixed shell), and each report-like message is charged as
    /// `content * 2 + id + 256` — its context carries a second copy of the same content text, and the
    /// fixed term covers the message shell and short identity fields. A parent report already held by
    /// `terminal_retention` is excluded here because that managed owner carries its one charge.
    /// Nothing is serialized, no second budget account is created, and the arithmetic saturates.
    ///
    /// 条目使用共享的 Arc 切片，本估算已包含条目与报告本身的外壳；没有 Vec 预留容量。
    /// 即使内容批次为空，也保留准备好的记账资料及其对应预算。
    pub(in crate::studio) fn retained_bytes(&self) -> u64 {
        let parent_report = self.parent_report_retained_bytes();
        let review_delivery = self.review_delivery.iter().fold(0_u64, |bytes, fact| {
            bytes
                .saturating_add((fact.message.payload.content().len() as u64).saturating_mul(2))
                .saturating_add(fact.message.id.len() as u64)
                .saturating_add(256)
        });
        self.history_events
            .iter()
            .fold(0_u64, |bytes, event| {
                bytes
                    .saturating_add(RETAINED_ITEM_OVERHEAD)
                    .saturating_add(event.payload_json.len() as u64)
                    .saturating_add(event.bodies.iter().fold(0_u64, |bodies, body| {
                        bodies.saturating_add(body.bytes.len() as u64)
                    }))
            })
            .saturating_add(
                (self.history_turns.len() as u64)
                    .saturating_mul(std::mem::size_of::<HistoryTurnHead>() as u64),
            )
            .saturating_add(
                serde_json::to_vec(self.history_turn_details.as_ref())
                    .map_or(u64::MAX, |bytes| bytes.len() as u64),
            )
            .saturating_add(
                (self.history_sources.len() as u64)
                    .saturating_mul(std::mem::size_of::<HistorySourceHead>() as u64),
            )
            .saturating_add(
                serde_json::to_vec(self.retained_resources.as_ref())
                    .map_or(u64::MAX, |bytes| bytes.len() as u64),
            )
            .saturating_add(self.accounting.retained_bytes())
            .saturating_add(
                self.terminal_turn_id
                    .as_ref()
                    .map_or(0, |id| id.len() as u64),
            )
            .saturating_add(parent_report)
            .saturating_add(review_delivery)
    }
}

/// Original ownership proof for a resource actually delivered or repaired in this effect.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct RetainedResourceFact {
    pub call_id: String,
    pub turn_id: Option<String>,
    pub reference: pl_core::context::ResourceReference,
}
