//! Serialized `(H,current)` publication, with reliable cuts separate from coalescable progress.
use crate::studio::thread_projection::{CurrentHandoff, CurrentState};
use pl_core::chat::Session;
use std::sync::{Arc, Mutex};
use tokio::sync::{broadcast, watch};

pub(in crate::studio::runtime) const CURRENT_FRAME_BYTES: usize = 64 * 1024;
const CUT_FRAMES: usize = 16;

fn current_frame_len(serial: u64, head: u64, handoff: &CurrentHandoff) -> serde_json::Result<u64> {
    #[derive(serde::Serialize)]
    #[serde(rename_all = "camelCase")]
    struct Frame<'a> {
        serial: u64,
        head: u64,
        main_through: u64,
        before: (),
        after: (),
        entries: &'a [pl_protocol::ChatEntry],
        members: &'a [crate::studio::thread_projection::timeline::MemberChange],
        sources: &'a [pl_protocol::ChatSourceState],
        retirements: &'a [crate::studio::thread_projection::CurrentRetirement],
    }
    let envelope = serde_json::to_vec(&Frame {
        serial,
        head,
        main_through: handoff.main_through(),
        before: (),
        after: (),
        entries: handoff.entries(),
        members: handoff.members(),
        sources: handoff.sources(),
        retirements: handoff.retirements(),
    })?;
    // Both unit placeholders encode as `null`. Replace exactly those two
    // fragments with the same frozen heads' true JSON lengths, not retained
    // estimates (which additionally charge caches, Arc metadata and reserves).
    Ok(u64::try_from(envelope.len())
        .ok()
        .and_then(|bytes| bytes.checked_sub(2 * b"null".len() as u64))
        .and_then(|bytes| bytes.checked_add(handoff.before().json_bytes()))
        .and_then(|bytes| bytes.checked_add(handoff.after().json_bytes()))
        .unwrap_or(u64::MAX))
}

#[derive(Clone)]
pub(in crate::studio::runtime) struct ConversationSource {
    pub projection_generation: String,
    pub serial: u64,
    pub session: Session,
    pub head: u64,
    pub current: Arc<CurrentState>,
    pub handoff: Arc<CurrentHandoff>,
}
pub(in crate::studio::runtime) struct ConversationCut {
    pub serial: u64,
    pub session: Session,
    pub head: u64,
    pub handoff: Arc<CurrentHandoff>,
}
// Only the <=64 KiB handoff envelope enters this 16-frame queue. Old current bodies/collections stay
// with their actual read/effect owners, never a subscriber's delivery backlog.
impl ConversationSource {
    pub fn cut(&self) -> Arc<ConversationCut> {
        Arc::new(ConversationCut {
            serial: self.serial,
            session: self.session.clone(),
            head: self.head,
            handoff: self.handoff.clone(),
        })
    }
}
pub(in crate::studio::runtime) struct ConversationRegistration {
    pub source: Option<Arc<ConversationSource>>,
    pub cuts: broadcast::Receiver<Arc<ConversationCut>>,
    pub progress: watch::Receiver<Option<Arc<ConversationSource>>>,
    pub owner_progress: watch::Receiver<super::Progress>,
}

pub(super) struct ConversationPublication {
    latest: Mutex<Option<Arc<ConversationSource>>>,
    cuts: broadcast::Sender<Arc<ConversationCut>>,
    progress: watch::Sender<Option<Arc<ConversationSource>>>,
    content_changed: watch::Sender<u64>,
}
impl Default for ConversationPublication {
    fn default() -> Self {
        Self {
            latest: Mutex::new(None),
            cuts: broadcast::channel(CUT_FRAMES).0,
            progress: watch::channel(None).0,
            content_changed: watch::channel(0).0,
        }
    }
}
impl ConversationPublication {
    pub(super) fn content_changes(&self) -> watch::Receiver<u64> {
        self.content_changed.subscribe()
    }
    pub(super) fn current(&self) -> Option<Arc<ConversationSource>> {
        self.latest
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }
    pub(super) fn capture(
        &self,
        owner_progress: watch::Receiver<super::Progress>,
    ) -> ConversationRegistration {
        let latest = self
            .latest
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        ConversationRegistration {
            source: latest.clone(),
            cuts: self.cuts.subscribe(),
            progress: self.progress.subscribe(),
            owner_progress,
        }
    }
    pub(super) fn publish(
        &self,
        session: &Session,
        current: Arc<CurrentState>,
        handoff: Option<Arc<CurrentHandoff>>,
    ) -> anyhow::Result<()> {
        self.publish_in(session, current, handoff, None)
    }
    pub(super) fn publish_generation(
        &self,
        session: &Session,
        current: Arc<CurrentState>,
        generation: &str,
    ) -> anyhow::Result<()> {
        self.publish_in(session, current, None, Some(generation))
    }
    fn publish_in(
        &self,
        session: &Session,
        current: Arc<CurrentState>,
        handoff: Option<Arc<CurrentHandoff>>,
        generation: Option<&str>,
    ) -> anyhow::Result<()> {
        let reliable = handoff.is_some();
        let mut latest = self
            .latest
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let serial = latest.as_ref().map_or(Ok(1), |source| {
            source
                .serial
                .checked_add(1)
                .ok_or_else(|| anyhow::anyhow!("conversation publication serial exhausted"))
        })?;
        let handoff = handoff.unwrap_or_else(|| {
            let projection = current.frozen_projection().clone();
            Arc::new(
                CurrentHandoff::new(
                    latest
                        .as_ref()
                        .map_or(0, |source| source.handoff.main_through()),
                    projection.clone(),
                    projection,
                    Arc::from([]),
                )
                .with_publication(
                    generation.map(str::to_owned).unwrap_or_else(|| {
                        latest
                            .as_ref()
                            .map_or_else(String::new, |source| source.projection_generation.clone())
                    }),
                    Arc::from([]),
                    Arc::from([]),
                    Arc::from([]),
                ),
            )
        });
        let source = Arc::new(ConversationSource {
            projection_generation: handoff.projection_generation().to_owned(),
            serial,
            session: session.clone(),
            head: session.head_seq(),
            current,
            handoff,
        });
        anyhow::ensure!(
            source.handoff.main_through() <= source.head
                && source.handoff.after().projection() == source.current.projection(),
            "current handoff differs from its published completion cut"
        );
        if !reliable
            && latest.as_ref().is_some_and(|old| {
                old.projection_generation == source.projection_generation
                    && old.head == source.head
                    && old.current.projection() == source.current.projection()
                    && old.current.contents().len() == source.current.contents().len()
                    && old.current.contents().iter().all(|(key, content)| {
                        source
                            .current
                            .contents()
                            .get(key)
                            .is_some_and(|next| next.descriptor == content.descriptor)
                    })
            })
        {
            return Ok(());
        }
        anyhow::ensure!(
            current_frame_len(source.serial, source.head, &source.handoff)?
                <= CURRENT_FRAME_BYTES as u64,
            "current handoff exceeds bounded publication budget"
        );
        if reliable {
            let _ = self.cuts.send(source.cut());
        }
        self.progress.send_replace(Some(source.clone()));
        self.content_changed.send_replace(serial);
        *latest = Some(source);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::studio::thread_projection::{CurrentRetirement, FrozenCurrentProjection};

    #[test]
    fn component_frame_length_matches_original_json() -> anyhow::Result<()> {
        use pl_protocol::*;
        let source = ChatSourceState {
            source: ChatSourceId::ForegroundTurn {
                turn_id: "turn汉📖".into(),
            },
            lifecycle: ChatSourceLifecycle::Active,
            started: Some(ChatFactPosition {
                effect_seq: 17,
                suborder: 1,
            }),
            ended: None,
        };
        let reference = ContentRef {
            database_id: "db".into(),
            target: ContentTarget::ItemPayload {
                item_id: "member".into(),
            },
        };
        let atom = ChatAtom {
            id: "member".into(),
            completion_item_id: None,
            completion_seq: None,
            source: source.source.clone(),
            source_state: None,
            source_order: Some(1),
            kind: ChatAtomKind::Reasoning,
            delivery: ChatDeliveryKind::Foreground,
            lifecycle: ChatAtomLifecycle::Active {
                started: source.started,
                status: ChatActiveStatus::Running,
            },
            turn_id: Some("turn汉📖".into()),
            attempt_id: Some("attempt".into()),
            tool: None,
            wait: None,
            text_channel: None,
            started_at: Some(17),
            finished_at: None,
            content_present: None,
            contents: vec![ChatAtomContent {
                role: ChatContentRole::Body,
                reference: reference.clone(),
            }],
            payload: None,
        };
        let mut timeline = crate::studio::thread_projection::TimelineProjection::new(
            "db".into(),
            "generation".into(),
            0,
        );
        timeline.observe(&atom, None)?;
        let update = timeline.take_update()?;
        assert!(!update.current().is_empty() && !update.members().is_empty());
        let mut before = pl_protocol::CurrentProjection::empty(
            17,
            pl_protocol::Thread::placeholder("thread").status,
        );
        before.execution_present = true;
        before.items = update.current().to_vec();
        before.atoms.push(atom);
        before.sources.push(source.clone());
        before.previews.push(CurrentContentPreview {
            id: "member".into(),
            role: CurrentContentRole::Reasoning,
            text_channel: Some(ThreadTextChannel::Commentary),
            text: String::new(),
            reference,
        });
        for copies in [0, 1, 4096] {
            before.previews[0].text = "汉📖\"\\\n".repeat(copies);
            let mut after = before.clone();
            after.source_effect_seq = 999;
            after.execution_present = false;
            after.previews[0].text.push('尾');
            let handoff = CurrentHandoff::new(
                41,
                FrozenCurrentProjection::new(before.clone()),
                FrozenCurrentProjection::new(after),
                Arc::from([ChatEntry::Source(source.clone())]),
            )
            .with_publication(
                "generation".into(),
                Arc::from([source.clone()]),
                update.members().to_vec().into(),
                Arc::from([
                    CurrentRetirement {
                        item_id: "汉📖\"\\\n".into(),
                        through: u64::MAX,
                    },
                    CurrentRetirement {
                        item_id: "item".into(),
                        through: 0,
                    },
                ]),
            );
            for (serial, head) in [(0, 42), (u64::MAX, u64::MAX)] {
                let retirements = handoff.retirements().iter().map(|retirement| {
                serde_json::json!({"itemId":retirement.item_id,"through":retirement.through})
            }).collect::<Vec<_>>();
                let original = serde_json::json!({
                    "serial":serial,
                    "head":head,
                    "mainThrough":handoff.main_through(),
                    "before":handoff.before().projection(),
                    "after":handoff.after().projection(),
                    "entries":handoff.entries(),
                    "members":handoff.members(),
                    "sources":handoff.sources(),
                    "retirements":retirements,
                });
                let expected = serde_json::to_vec(&original)?.len() as u64;
                assert_eq!(current_frame_len(serial, head, &handoff)?, expected);
                assert_eq!(current_frame_len(serial, head, &handoff)?, expected);
                if copies == 4096 {
                    assert!(expected > CURRENT_FRAME_BYTES as u64);
                }
            }
        }
        Ok(())
    }
}
