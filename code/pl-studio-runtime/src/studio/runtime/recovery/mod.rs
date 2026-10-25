//! Recovery projection over the original audit registry, with source-issued immutable references.
mod feed;
mod frames;
mod material;
mod read;
mod scope;
mod source;
mod source_status;

pub use feed::StudioRecoveryFeed;
pub use pl_protocol::products::feed::recovery::RecoveryFrame;
pub use pl_protocol::products::identity::{ProductReadOrigin, ProductSourceStatusRef};
pub use pl_protocol::products::read::recovery::*;
pub use pl_protocol::products::references::{RecoveryReadRef, RecoveryReadTarget};
pub use read::StudioRecoveryRead;
pub(in crate::studio) use source::RecoverySource;
pub use source_status::StudioRecoverySourceStatusRead;

/// Retains the exact command publication until the transport has materialized its target.
#[derive(serde::Serialize)]
#[serde(transparent)]
pub struct RecoveryRetryResult {
    pub target: RecoveryReadTarget,
    #[serde(skip)]
    _publication: std::sync::Arc<source::RecoverySnapshot>,
}

impl super::StudioRuntime {
    pub async fn retry_recovery(&self) -> anyhow::Result<RecoveryRetryResult> {
        let _lifecycle = self.lifecycle_lock.lock().await;
        self.recovery_source.ensure_open()?;
        anyhow::ensure!(
            self.runtime_state.snapshot().state.is_ready(),
            "runtime is not ready"
        );
        self.start_recovery_scan().await;
        for (_, thread) in self.threads.observed_threads() {
            if !thread.snapshot().tool_cleanup.failures.is_empty() {
                thread.retry_tool_cleanup().await?;
            }
        }
        // Keep the original independent catalog refresh; a successful audit cannot repair it.
        self.tool_catalog_updates.notify_one();
        let publication = self
            .recovery_source
            .capture_committed(self.recovery.state())?;
        let reference = publication.reference.ok_or_else(|| {
            pl_protocol::studio::StudioError::new(
                pl_protocol::studio::StudioErrorCode::Unavailable,
                "Recovery has no readable material",
                true,
            )
        })?;
        Ok(RecoveryRetryResult {
            target: RecoveryReadTarget {
                origin: self.recovery_source.origin().clone(),
                reference,
            },
            _publication: publication,
        })
    }
}
