//! 稳定 ConversationStore 的最新完成边界与当前状态；通知不拥有可靠保存队列。
//! 完成历史仍由同一 Session 读取，执行驱动只推进此处的共享发布。
use crate::studio::thread_projection::CurrentState;
use pl_core::chat::Session;
use pl_protocol::ActivitySnapshot;
use std::sync::{Arc, Mutex};
use tokio::sync::watch;

pub(in crate::studio) const CURRENT_FRAME_BYTES: usize = 64 * 1024;

#[derive(Clone)]
pub(in crate::studio) struct ConversationSource {
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
pub(in crate::studio) struct ConversationPublication {
    presentation: Mutex<crate::studio::thread_projection::presentation::PresentationHandle>,
    latest: Mutex<Option<Arc<ConversationSource>>>,
    progress: watch::Sender<Option<Arc<ConversationSource>>>,
    content_changed: watch::Sender<u64>,
}
impl ConversationPublication {
    pub(in crate::studio) fn subscribe_progress(
        &self,
    ) -> watch::Receiver<Option<Arc<ConversationSource>>> {
        self.progress.subscribe()
    }
    pub(in crate::studio) fn new() -> Self {
        Self {
            presentation: Mutex::new(Default::default()),
            latest: Mutex::new(None),
            progress: watch::channel(None).0,
            content_changed: watch::channel(0).0,
        }
    }
    pub(in crate::studio) fn bind_presentation(
        &self,
        owner: crate::studio::thread_projection::presentation::PresentationHandle,
    ) {
        *self
            .presentation
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = owner;
    }
    pub(in crate::studio) fn content_changes(&self) -> watch::Receiver<u64> {
        self.content_changed.subscribe()
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
    pub(in crate::studio) fn publish(
        &self,
        session: &Session,
        current: Arc<CurrentState>,
    ) -> anyhow::Result<()> {
        let source = self.prepare(session, session.head_seq(), current)?;
        self.apply(source);
        Ok(())
    }

    pub(in crate::studio) fn prepare(
        &self,
        session: &Session,
        head: u64,
        current: Arc<CurrentState>,
    ) -> anyhow::Result<Arc<ConversationSource>> {
        let latest = self
            .latest
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let serial = latest.as_ref().map_or(Ok(1), |source| {
            source
                .serial
                .checked_add(1)
                .filter(|serial| *serial < u64::MAX)
                .ok_or_else(|| anyhow::anyhow!("activity revision exhausted"))
        })?;
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
        Ok(source)
    }

    /// 退出执行只清除执行可用性，保留同一 Store 的业务与展示切面。
    /// 正常发布预留一个修订号，因此该同步收束段不会发生计数失败。
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
        let current = crate::studio::thread_projection::CurrentState::with_projection(
            previous.current.clone(),
            crate::studio::thread_projection::FrozenCurrentProjection::new(projection),
        );
        let serial = previous
            .serial
            .checked_add(1)
            .expect("publication reserved retirement revision");
        self.apply(Arc::new(ConversationSource {
            presentation: previous.presentation.clone(),
            serial,
            session: previous.session.clone(),
            head: previous.head,
            current,
            activity: Arc::new(ActivitySnapshot {
                revision: serial,
                completed_through: previous.head,
                execution_present: false,
                entries: Vec::new(),
            }),
        }));
    }

    pub(in crate::studio) fn apply(&self, source: Arc<ConversationSource>) {
        source
            .presentation
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .observe_execution(source.current.projection().execution_present)
            .expect("display publication revision exhausted");
        let serial = source.serial;
        *self
            .latest
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(source.clone());
        self.progress.send_replace(Some(source));
        self.content_changed.send_replace(serial);
    }
}
