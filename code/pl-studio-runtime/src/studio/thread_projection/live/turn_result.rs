//! Retained report material for the newest Turn.
use super::{TURN_COMMENTARY_PARTS, memory_budget::*};
use crate::{ExecutionItem, ThreadTextChannel, ThreadToolItem};
use std::collections::{BTreeMap, BTreeSet};

///
/// Text facts are keyed by identity and ordinal, so a later revision of the same body replaces its
/// entry instead of appending a second copy: an uncommitted streaming preview and the committed
/// The facts a parent/child report and the directory summary need from one Turn.
///
/// The report is the committed **result** plus the stable identities it belongs to — not the
/// Turn's process bodies. Keeping this accumulator instead of the Turn's whole item set is what
/// bounds the live projection's memory: the final text, a bounded commentary fallback, the newest
/// tool item and every identity the Turn produced.
/// The preview and the committed
/// item it finalizes share one key, a Turn that rewrote its own summary keeps only the latest text,
/// and the report never grows with the number of revisions a long Turn committed.
#[derive(Debug, Default, Clone)]
pub(in crate::studio) struct TurnResult {
    identities: BTreeSet<String>,
    identity_bytes: u64,
    finals: BTreeMap<(u64, String), String>,
    /// Tail of the visible commentary, used only when the Turn committed no final text.
    commentary: BTreeMap<(u64, String), String>,
    last_tool: Option<(u64, ThreadToolItem)>,
    pub(in crate::studio) finish: Option<pl_tool::finish_turn::SavedFinishTurn>,
}

impl TurnResult {
    /// Every identity the Turn committed, in no particular order.
    pub(in crate::studio) fn identities(&self) -> impl Iterator<Item = &str> {
        self.identities.iter().map(String::as_str)
    }

    /// The committed final text, or `None` when the Turn committed none.
    pub(in crate::studio) fn final_text(&self) -> Option<String> {
        let text = self
            .finals
            .values()
            .cloned()
            .collect::<Vec<_>>()
            .join("\n\n");
        (!text.is_empty()).then_some(text)
    }

    /// The bounded commentary tail, joined; the fallback description of a Turn without a summary.
    pub(in crate::studio) fn commentary(&self) -> String {
        self.commentary
            .values()
            .cloned()
            .collect::<Vec<_>>()
            .join("\n\n")
    }

    /// The newest committed tool item, used when the Turn produced no final text.
    pub(in crate::studio) fn last_tool(&self) -> Option<&ThreadToolItem> {
        self.last_tool.as_ref().map(|(_, tool)| tool)
    }

    /// Bytes this Turn's report facts retain: the texts kept in full plus one shell per entry.
    /// Identity charges are accumulated at insertion; the accumulator's own fixed size is charged too.
    ///
    /// The report needs these texts, so a Turn under storage pressure keeps them instead of losing
    /// its result: the value is what the Thread's reliable budget charges, which is how a Turn that
    /// would otherwise grow its accumulator without bound becomes visible pressure.
    pub(in crate::studio) fn retained_bytes(&self) -> u64 {
        let mut bytes = self
            .identity_bytes
            .saturating_add(std::mem::size_of::<u64>() as u64);
        for (key, text) in self.finals.iter().chain(self.commentary.iter()) {
            bytes = bytes
                .saturating_add(key.1.len() as u64)
                .saturating_add(text.len() as u64)
                .saturating_add(RETAINED_ENTRY_OVERHEAD);
        }
        if let Some((_, tool)) = &self.last_tool {
            bytes = bytes.saturating_add(tool_bytes(tool));
        }
        if let Some(finish) = &self.finish {
            bytes = bytes
                .saturating_add(finish.message.len() as u64)
                .saturating_add(
                    finish
                        .feedback_message
                        .as_ref()
                        .map_or(0, |body| body.len()) as u64,
                )
                .saturating_add(finish.review.as_ref().map_or(0, |review| {
                    review.summary.len() + review.reviewed_version.len()
                }) as u64);
        }
        bytes
    }

    /// Adds one committed payload to the Turn's result facts.
    pub(in crate::studio) fn observe(&mut self, item: &ExecutionItem) {
        if self.identities.insert(item.id.clone()) {
            self.identity_bytes = self
                .identity_bytes
                .saturating_add(item.id.len() as u64)
                .saturating_add(RETAINED_ENTRY_OVERHEAD);
        }
        if let Some(tool) = item.tool() {
            let newest = self
                .last_tool
                .as_ref()
                .is_none_or(|(ordinal, _)| item.ordinal >= *ordinal);
            if newest {
                self.last_tool = Some((item.ordinal, tool.clone()));
            }
        }
        if let Some(text) = item.text() {
            let key = (item.ordinal, item.id.clone());
            match text.channel() {
                ThreadTextChannel::Final => {
                    self.finals.insert(key, text.text().to_owned());
                }
                ThreadTextChannel::Commentary => {
                    self.commentary.insert(key, text.text().to_owned());
                    // The tail is a diagnostic fallback, not a second process log: keep only the
                    // newest parts and drop the oldest by their canonical placement.
                    while self.commentary.len() > TURN_COMMENTARY_PARTS {
                        let oldest = self
                            .commentary
                            .keys()
                            .next()
                            .cloned()
                            .expect("commentary is non-empty");
                        self.commentary.remove(&oldest);
                    }
                }
                _ => {}
            }
        }
    }
}
