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
}
