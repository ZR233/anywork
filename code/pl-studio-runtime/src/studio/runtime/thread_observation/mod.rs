//! Owned, retryable product projections of the Thread's committed effect stream.
//!
//! Observation consumes the Thread's reliable admission queue and is its **single realtime
//! projection owner**: it projects every admitted fact and the streaming overlay once, publishes the
//! content into the shared session and broadcasts the same typed changes on a bounded feed that
//! subscriptions only read. Billing, directory and terminal facts come from the same in-memory
//! projection, so an ordinary commit neither parks this observer behind the owner's command queue
//! nor waits for the disk. Installation seeds the projection from the current Core owner and the
//! channel's RAM identity/index; it never reads History to rebuild execution or report material.
mod billing;
mod directory;
mod live_owner;
mod registry;
mod reports;
mod slot;
mod worker;
pub(in crate::studio) use live_owner::RetainedProjection;
pub(crate) use registry::Observation;
pub(super) use registry::{ObservationServices, ThreadObservations};

use super::StudioRuntime;
use anyhow::Result;

impl StudioRuntime {
    /// Waits for product directories and billing to reach the current committed Thread watermark.
    /// Reattempts a previously failed projection without invoking models or tools.
    pub async fn synchronize_thread_observation(&self, thread_id: &str) -> Result<()> {
        self.thread_observations
            .synchronize(Some(thread_id))
            .await?;
        self.require_session(thread_id)?
            .settle_review_deliveries(thread_id)
            .await?;
        self.thread_observations.synchronize(Some(thread_id)).await
    }
}
