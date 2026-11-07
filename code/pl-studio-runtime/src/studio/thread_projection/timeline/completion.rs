//! Recovery contains only indexed reliable-fact cuts. Open product state remains in the fold.
use super::*;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(in crate::studio) struct Frontier {
    pub source: ChatSourceId,
    pub effect: u64,
    pub suborder: u32,
    pub source_order: Option<u64>,
}

impl TimelineProjection {
    pub(in crate::studio) fn next_position(&self) -> u64 {
        self.next_position
    }
    /// Bounded read over the original in-memory member accumulator.
    pub(in crate::studio) fn member_page(
        &self,
        item: &str,
        upper: u64,
        limit: usize,
    ) -> Option<(u64, Vec<MemberChange>)> {
        let index = self.item_ids.get(item)?;
        let head = self.items.get(index)?.item.summary.as_ref()?;
        let members = self
            .members
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .page(item, upper, limit);
        Some((u64::from(head.member_count), members))
    }
    pub(in crate::studio) fn admit_legacy_header_retained(
        &mut self,
        atom: &ChatAtom,
    ) -> Result<(), ProjectionError> {
        if atom.kind == ChatAtomKind::TurnReceipt || self.excluded(atom) {
            return Ok(());
        }
        let mut header = lightweight(atom);
        let started = match header.lifecycle {
            ChatAtomLifecycle::Active { started, .. }
            | ChatAtomLifecycle::Terminal { started, .. } => started,
        };
        header.lifecycle = ChatAtomLifecycle::Active {
            started,
            status: ChatActiveStatus::Running,
        };
        header.finished_at = None;
        header.completion_item_id = None;
        header.completion_seq = None;
        header.content_present = None;
        header.contents.clear();
        self.admit(header, atom.completion_seq, None, None)
    }
    pub(in crate::studio) fn active_atoms(&self) -> Vec<ChatAtom> {
        self.active
            .values()
            .map(|member| {
                let mut atom = member.atom.clone();
                atom.contents.clear();
                atom.payload = None;
                atom
            })
            .collect()
    }
    pub(super) fn freeze_frontier(&self) -> Result<Vec<u8>, ProjectionError> {
        let mut sources = BTreeMap::<ChatSourceId, (u64, u32, Option<u64>)>::new();
        for live in self.items.values() {
            let at = (live.anchor.effect, live.anchor.suborder, live.source_order);
            sources
                .entry(live.item.source.clone())
                .and_modify(|first| *first = (*first).min(at))
                .or_insert(at);
        }
        serde_json::to_vec(
            &sources
                .into_iter()
                .map(|(source, (effect, suborder, source_order))| Frontier {
                    source,
                    effect,
                    suborder,
                    source_order,
                })
                .collect::<Vec<_>>(),
        )
        .map_err(|error| ProjectionError::History(error.to_string()))
    }

    /// Called only for Core's real Interrupted attempt, never for a source end or cold read.
    /// The start proves identity, while the interruption proves the terminal position.
    pub(in crate::studio) fn interrupted_model_members(
        &self,
        attempt: &str,
        ended: ChatFactPosition,
    ) -> Vec<ChatAtom> {
        self.active
            .values()
            .filter_map(|member| {
                let mut atom = member.atom.clone();
                let ChatAtomLifecycle::Active {
                    started: Some(started),
                    ..
                } = atom.lifecycle
                else {
                    return None;
                };
                if atom.attempt_id.as_deref() != Some(attempt)
                    || !matches!(atom.kind, ChatAtomKind::Text | ChatAtomKind::Reasoning)
                {
                    return None;
                }
                atom.lifecycle = ChatAtomLifecycle::Terminal {
                    started: Some(started),
                    ended: Some(ended),
                    outcome: ChatTerminalOutcome::Cancelled,
                };
                atom.finished_at = None;
                atom.completion_item_id = None;
                atom.completion_seq = None;
                atom.payload = None;
                atom.contents.clear();
                atom.content_present = None;
                atom.wait = None;
                atom.source_state = None;
                Some(atom)
            })
            .collect()
    }
}
