//! One latest `(completion head, activity)` at the execution owner's serial boundary.
//! Completion history is replayed from Session; no reliable presentation queue exists here.
use crate::studio::thread_projection::CurrentState;
use pl_core::chat::Session;
use pl_protocol::ActivitySnapshot;
use std::sync::{Arc, Mutex};
use tokio::sync::watch;

pub(in crate::studio::runtime) const CURRENT_FRAME_BYTES: usize = 64 * 1024;

#[derive(Clone)]
pub(in crate::studio::runtime) struct ConversationSource {
    pub presentation: crate::studio::thread_projection::presentation::PresentationHandle,
    pub serial: u64,
    pub session: Session,
    pub head: u64,
    pub current: Arc<CurrentState>,
    pub activity: Arc<ActivitySnapshot>,
}
pub(in crate::studio::runtime) struct ConversationRegistration {
    pub source: Option<Arc<ConversationSource>>,
    pub progress: watch::Receiver<Option<Arc<ConversationSource>>>,
    pub owner_progress: watch::Receiver<super::Progress>,
}
pub(super) struct ConversationPublication {
    presentation: Mutex<crate::studio::thread_projection::presentation::PresentationHandle>,
    latest: Mutex<Option<Arc<ConversationSource>>>,
    progress: watch::Sender<Option<Arc<ConversationSource>>>,
    content_changed: watch::Sender<u64>,
}
impl ConversationPublication {
    pub(super) fn new() -> Self {
        Self {
            presentation: Mutex::new(Default::default()),
            latest: Mutex::new(None),
            progress: watch::channel(None).0,
            content_changed: watch::channel(0).0,
        }
    }
    pub(super) fn bind_presentation(
        &self,
        owner: crate::studio::thread_projection::presentation::PresentationHandle,
    ) {
        *self
            .presentation
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = owner;
    }
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
            progress: self.progress.subscribe(),
            owner_progress,
        }
    }
    pub(super) fn publish(
        &self,
        session: &Session,
        current: Arc<CurrentState>,
    ) -> anyhow::Result<()> {
        // Revoking delivery never revokes the owner's reliable completion /
        // storage obligations. Shutdown still publishes its final owner cut;
        // the slot/reader/State receiver independently reject retired reads.
        let mut latest = self
            .latest
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let serial = latest.as_ref().map_or(Ok(1), |source| {
            source
                .serial
                .checked_add(1)
                .ok_or_else(|| anyhow::anyhow!("activity revision exhausted"))
        })?;
        let head = session.head_seq();
        let projection = current.projection();
        let entries = if projection.execution_present {
            current.activity_entries().to_vec()
        } else {
            Vec::new()
        };
        let activity = Arc::new(ActivitySnapshot {
            revision: serial,
            completed_through: head,
            execution_present: projection.execution_present,
            entries,
        });
        anyhow::ensure!(
            serde_json::to_vec(activity.as_ref())?.len() <= CURRENT_FRAME_BYTES,
            "activity snapshot exceeds bounded publication budget"
        );
        let source = Arc::new(ConversationSource {
            presentation: self
                .presentation
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .clone(),
            serial,
            session: session.clone(),
            head,
            current,
            activity,
        });
        *latest = Some(source.clone());
        self.progress.send_replace(Some(source));
        self.content_changed.send_replace(serial);
        Ok(())
    }
}
