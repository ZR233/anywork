//! The current owner's latest RAM projection. History has a separate owner and sequence.
use crate::studio::thread_projection::CurrentState;
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicU64, Ordering},
};
use tokio::sync::watch;

#[derive(Clone)]
pub(in crate::studio) struct ConversationSource {
    pub serial: u64,
    pub current: Arc<CurrentState>,
}
pub(in crate::studio::runtime) struct ConversationRegistration {
    pub source: Option<Arc<ConversationSource>>,
    pub progress: watch::Receiver<Option<Arc<ConversationSource>>>,
    pub owner_progress: watch::Receiver<super::Progress>,
}
pub(in crate::studio) struct ConversationPublication {
    latest: Mutex<Option<Arc<ConversationSource>>>,
    progress: watch::Sender<Option<Arc<ConversationSource>>>,
    content_changed: watch::Sender<u64>,
    metadata_revision: AtomicU64,
    current_owner: Mutex<Option<String>>,
}
impl ConversationPublication {
    /// Bind before exposing a successor feed. The owner lock also serializes late publication.
    pub(in crate::studio) fn bind_current_owner(&self, owner_id: String) {
        let mut owner = self
            .current_owner
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if owner.as_ref() == Some(&owner_id) {
            return;
        }
        *owner = Some(owner_id);
        *self
            .latest
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = None;
        self.metadata_changed();
        self.progress.send_replace(None);
    }
    pub(in crate::studio) fn metadata_revision(&self) -> u64 {
        self.metadata_revision.load(Ordering::Acquire)
    }
    pub(in crate::studio) fn metadata_changed(&self) {
        let _ =
            self.metadata_revision
                .try_update(Ordering::AcqRel, Ordering::Acquire, |revision| {
                    revision.checked_add(1)
                });
    }
    pub(in crate::studio) fn new() -> Self {
        Self {
            latest: Mutex::new(None),
            progress: watch::channel(None).0,
            content_changed: watch::channel(0).0,
            metadata_revision: AtomicU64::new(0),
            current_owner: Mutex::new(None),
        }
    }

    pub(in crate::studio) fn current(&self) -> Option<Arc<ConversationSource>> {
        self.latest
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }
    pub(in crate::studio::runtime) fn capture(
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
    pub(in crate::studio) fn prepare(
        &self,
        current: Arc<CurrentState>,
    ) -> anyhow::Result<Arc<ConversationSource>> {
        let serial = self
            .content_changed
            .borrow()
            .checked_add(1)
            .filter(|serial| *serial < u64::MAX)
            .ok_or_else(|| anyhow::anyhow!("current publication revision exhausted"))?;
        Ok(Arc::new(ConversationSource { serial, current }))
    }
    pub(in crate::studio) fn publish(&self, current: Arc<CurrentState>) -> anyhow::Result<()> {
        self.apply(self.prepare(current)?);
        Ok(())
    }
    pub(in crate::studio) fn retire_execution(&self) {
        let Some(previous) = self
            .current()
            .filter(|source| source.current.projection().execution_present)
        else {
            return;
        };
        let mut projection = previous.current.projection().clone();
        projection.execution_present = false;
        projection.active = None;
        let current = CurrentState::with_projection(
            previous.current.clone(),
            crate::studio::thread_projection::FrozenCurrentProjection::new(projection),
        );
        self.apply(Arc::new(ConversationSource {
            serial: previous
                .serial
                .checked_add(1)
                .expect("publication reserves retirement revision"),
            current,
        }));
    }
    pub(in crate::studio) fn apply(&self, source: Arc<ConversationSource>) {
        let owner = self
            .current_owner
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if owner
            .as_ref()
            .is_some_and(|owner| owner != source.current.owner_id())
        {
            return;
        }
        let mut latest = self
            .latest
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if latest.as_ref().is_none_or(|old| {
            old.current.owner_id() != source.current.owner_id()
                || old.current.projection() != source.current.projection()
        }) {
            self.metadata_changed();
        }
        *latest = Some(source.clone());
        self.progress.send_replace(Some(source.clone()));
        self.content_changed.send_replace(source.serial);
    }
}
