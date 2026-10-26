//! Immutable persistence publications over the original writers and coordinator.
mod feed;
mod frames;
mod material;
mod queue_feed;
mod queue_material;
mod read;
mod scope;
mod source;

pub use feed::StudioPersistenceFeed;
pub use pl_protocol::products::feed::persistence::PersistenceFrame;
pub use pl_protocol::products::feed::persistence_queue::PersistenceQueueFrame;
pub use pl_protocol::products::read::persistence::*;
pub use pl_protocol::products::references::{
    PersistenceQueueReadRef, PersistenceReadRef, PersistenceReadTarget,
};
pub use queue_feed::StudioPersistenceQueueFeed;
pub use read::{StudioPersistenceQueueRead, StudioPersistenceRead};
pub(in crate::studio) use source::{PersistenceQueueSource, PersistenceSource};

#[derive(serde::Serialize)]
#[serde(transparent)]
pub struct PersistenceRetryResult {
    pub target: PersistenceReadTarget,
    #[serde(skip)]
    _publication: std::sync::Arc<source::PersistenceSnapshot>,
}
impl super::StudioRuntime {
    pub async fn retry_persistence(&self) -> anyhow::Result<PersistenceRetryResult> {
        self.persistence_source.ensure_open()?;
        let persistence = self.agent_facility.persistence.lock().await.clone();
        if let Some(persistence) = persistence {
            self.store.thread_persistence().retry_now();
            persistence.retry_now().await?;
        }
        let captured = self.agent_facility.product_events.persistence_state();
        let publication = self.persistence_source.capture_committed(captured)?;
        Ok(PersistenceRetryResult {
            target: PersistenceReadTarget {
                origin: self.persistence_source.origin().clone(),
                reference: publication.reference,
            },
            _publication: publication,
        })
    }
}
