//! Current runtime facts, projected by hosts and keyed by stable source identity.
//!
//! Current facts retain one value per source. Model-visible snapshots append on change so an
//! already observed prefix stays immutable until explicit context replacement.
use super::*;
use std::{
    borrow::Cow,
    collections::{BTreeMap, BTreeSet},
};

impl Owner {
    pub(super) fn queue_runtime_facts(
        &mut self,
        facts: Vec<RuntimeFact>,
    ) -> Result<(), ThreadError> {
        if self.state.lifecycle != ThreadLifecycle::Open || self.interrupt.is_closing() {
            return Err(ThreadError::Closed);
        }
        let mut sources = BTreeSet::new();
        if facts
            .iter()
            .any(|fact| fact.source_id.is_empty() || !sources.insert(&fact.source_id))
        {
            return Err(ThreadError::InvalidContext);
        }
        for fact in facts {
            self.pending_runtime_facts
                .insert(fact.source_id.clone(), fact);
        }
        Ok(())
    }

    pub(super) fn apply_pending_runtime_facts(&mut self) -> Result<(), ThreadError> {
        if !self.pending_runtime_facts.is_empty() {
            self.patch_runtime_facts(self.pending_runtime_facts.values().cloned().collect())?;
            self.pending_runtime_facts.clear();
        }
        Ok(())
    }

    pub(super) fn patch_runtime_facts(
        &mut self,
        facts: Vec<RuntimeFact>,
    ) -> Result<ContextSnapshot, ThreadError> {
        if !self.pending.is_empty() {
            return Err(ThreadError::PendingTools);
        }
        let context = stage_fact_changes(&mut self.state, facts)?;
        self.publish()?;
        Ok(context)
    }

    pub(super) fn update_facts(
        &mut self,
        facts: Vec<RuntimeFact>,
    ) -> Result<ContextSnapshot, ThreadError> {
        if !self.pending.is_empty() {
            return Err(ThreadError::PendingTools);
        }
        let context = stage_facts(&mut self.state, facts)?;
        self.publish()?;
        Ok(context)
    }
}

pub(super) fn stage_fact_changes(
    state: &mut ThreadSnapshot,
    changes: Vec<RuntimeFact>,
) -> Result<ContextSnapshot, ThreadError> {
    let mut sources = BTreeSet::new();
    let mut merged = state
        .runtime_facts
        .iter()
        .map(|fact| (fact.source_id.clone(), fact.clone()))
        .collect::<BTreeMap<_, _>>();
    for fact in changes {
        if fact.source_id.is_empty() || !sources.insert(fact.source_id.clone()) {
            return Err(ThreadError::InvalidContext);
        }
        merged.insert(fact.source_id.clone(), fact);
    }
    stage_facts(state, merged.into_values().collect())
}

pub(super) fn stage_facts(
    state: &mut ThreadSnapshot,
    facts: Vec<RuntimeFact>,
) -> Result<ContextSnapshot, ThreadError> {
    if state.lifecycle != ThreadLifecycle::Open {
        return Err(ThreadError::Closed);
    }
    let mut next = BTreeMap::new();
    for fact in facts {
        if fact.source_id.is_empty() || next.insert(fact.source_id.clone(), fact).is_some() {
            return Err(ThreadError::InvalidContext);
        }
    }
    // An omitted known source is a cleared fact, kept as a tombstone for rewind/compaction.
    for old in state.runtime_facts.iter() {
        next.entry(old.source_id.clone())
            .or_insert_with(|| RuntimeFact {
                source_id: old.source_id.clone(),
                content: Vec::new(),
            });
    }
    let mut records = Cow::Borrowed(state.context.records.as_ref());
    let revision = state
        .context
        .revision
        .checked_add(1)
        .ok_or(ThreadError::RevisionExhausted)?;
    for fact in next.values() {
        if let Some(record) = changed_fact(&records, fact, revision) {
            records.to_mut().push(record);
        }
    }
    if let Cow::Owned(records) = records {
        state.context = ContextSnapshot {
            revision,
            records: records.into(),
        };
    }
    state.runtime_facts = next.into_values().collect();
    Ok(state.context.clone())
}

pub(super) fn restore_facts(
    records: &mut Vec<ContextRecord>,
    facts: &[RuntimeFact],
    revision: u64,
) {
    for fact in facts {
        if let Some(record) = changed_fact(records, fact, revision) {
            records.push(record);
        }
    }
}

/// Writes one source's current facts at most once.
///
/// A changed value appends a full snapshot; unchanged values do not change the prefix.
/// An absent source appends an explicit invalidation.
fn changed_fact(
    records: &[ContextRecord],
    fact: &RuntimeFact,
    revision: u64,
) -> Option<ContextRecord> {
    let content = if fact.content.is_empty() {
        vec![ContextContent::Text {
            text: Arc::from(
                "This source has no active facts. Previously supplied facts from this source are no longer current.",
            ),
        }]
    } else {
        fact.content.clone()
    };
    let source = ContextSource::RuntimeFact {
        source_id: fact.source_id.clone(),
    };
    if let Some(previous) = records.iter().rfind(|record| record.source == source)
        && previous.content == content
    {
        return None;
    }
    let mut identities = records
        .iter()
        .map(|record| record.id.clone())
        .collect::<BTreeSet<_>>();
    let mut suffix = 0_u64;
    let id = loop {
        let id = format!("runtime:{revision}:{}:{suffix}", fact.source_id);
        if identities.insert(id.clone()) {
            break id;
        }
        suffix += 1;
    };
    Some(ContextRecord {
        tool_calls: Vec::new(),
        id,
        turn_id: None,
        source,
        content,
    })
}
