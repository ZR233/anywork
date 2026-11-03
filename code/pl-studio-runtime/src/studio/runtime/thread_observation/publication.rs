//! Serialized `(H,current)` publication, with reliable cuts separate from coalescable progress.
use crate::studio::thread_projection::{CurrentHandoff, CurrentState};
use pl_core::chat::Session;
use std::sync::{Arc, Mutex};
use tokio::sync::{broadcast, watch};

pub(in crate::studio::runtime) const CURRENT_FRAME_BYTES: usize = 64 * 1024;
const CUT_FRAMES: usize = 16;

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
            let projection = Arc::new(current.projection.clone());
            Arc::new(CurrentHandoff {
                projection_generation: generation.map(str::to_owned).unwrap_or_else(|| {
                    latest
                        .as_ref()
                        .map_or_else(String::new, |source| source.projection_generation.clone())
                }),
                sources: std::sync::Arc::from([]),
                members: std::sync::Arc::from([]),
                main_through: latest
                    .as_ref()
                    .map_or(0, |source| source.handoff.main_through),
                before: projection.clone(),
                after: projection,
                retirements: Arc::from([]),
                entries: Arc::from([]),
            })
        });
        let source = Arc::new(ConversationSource {
            projection_generation: handoff.projection_generation.clone(),
            serial,
            session: session.clone(),
            head: session.head_seq(),
            current,
            handoff,
        });
        anyhow::ensure!(
            source.handoff.main_through <= source.head
                && source.handoff.after.as_ref() == &source.current.projection,
            "current handoff differs from its published completion cut"
        );
        if !reliable
            && latest.as_ref().is_some_and(|old| {
                old.projection_generation == source.projection_generation
                    && old.head == source.head
                    && old.current.projection == source.current.projection
                    && old.current.contents.len() == source.current.contents.len()
                    && old.current.contents.iter().all(|(key, content)| {
                        source
                            .current
                            .contents
                            .get(key)
                            .is_some_and(|next| next.descriptor == content.descriptor)
                    })
            })
        {
            return Ok(());
        }
        let retirements = source.handoff.retirements.iter().map(|retirement| {
            serde_json::json!({"itemId":retirement.item_id,"through":retirement.through})
        }).collect::<Vec<_>>();
        anyhow::ensure!(
            serde_json::to_vec(&serde_json::json!({
                "serial":source.serial,
                "head":source.head,
                "mainThrough":source.handoff.main_through,
                "before":source.handoff.before,
                "after":source.handoff.after,
                "entries":source.handoff.entries,
                "members":source.handoff.members,
                "sources":source.handoff.sources,
                "retirements":retirements,
            }))?
            .len()
                <= CURRENT_FRAME_BYTES,
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
