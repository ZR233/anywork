use pl_protocol::products::identity::ProductSourceStatusRef;
use pl_protocol::products::source::{ObservedBrief, ObservedHeader};
use pl_protocol::studio::{StudioError, StudioErrorCode};
use pl_protocol::{ObservedResource, ObservedResourceCommand};
use std::sync::Arc;

use super::source::ConfigurationCaptureFailure;

pub(in crate::config::runtime) type ConfigurationMetadata =
    Result<Arc<ObservedResource<()>>, Arc<ConfigurationCaptureFailure>>;

pub(crate) struct ConfigurationStatusMaterial {
    pub(crate) header: ObservedHeader,
    metadata: Arc<ObservedResource<()>>,
}

impl ConfigurationStatusMaterial {
    // Domain-neutral ObservedResource representation; Profiles constructs its own independent
    // metadata here. Only the owning source's full origin and weak index grant a readable pin.
    pub(in crate::config) fn new(revision: u64, metadata: Arc<ObservedResource<()>>) -> Self {
        let brief = match metadata.as_ref() {
            ObservedResource::Uninitialized(state) => ObservedBrief::Uninitialized {
                revision: state.revision(),
                updated_at: state.updated_at(),
            },
            ObservedResource::Loading(state) => ObservedBrief::Loading {
                revision: state.revision(),
                started_at: state.started_at(),
            },
            ObservedResource::Ready(state) => ObservedBrief::Ready {
                revision: state.revision(),
                updated_at: state.updated_at(),
                last_checked_at: state.last_checked_at(),
            },
            ObservedResource::Refreshing(state) => ObservedBrief::Refreshing {
                revision: state.revision(),
                started_at: state.started_at(),
                last_checked_at: state.last_checked_at(),
            },
            ObservedResource::Stale(state) => ObservedBrief::Stale {
                revision: state.revision(),
                stale_at: state.stale_at(),
                last_checked_at: state.last_checked_at(),
            },
            ObservedResource::Degraded(state) => ObservedBrief::Degraded {
                revision: state.revision(),
                failed_at: state.failed_at(),
                last_checked_at: state.last_checked_at(),
                retryable: state.error().retryable,
            },
            ObservedResource::Failed(state) => ObservedBrief::Failed {
                revision: state.revision(),
                failed_at: state.failed_at(),
                retryable: state.error().retryable,
            },
            ObservedResource::Stopped(state) => ObservedBrief::Stopped {
                revision: state.revision(),
                stopped_at: state.stopped_at(),
            },
        };
        Self {
            header: ObservedHeader {
                brief,
                status: ProductSourceStatusRef { entry: 3, revision },
            },
            metadata,
        }
    }

    pub(crate) fn metadata(&self) -> &ObservedResource<()> {
        &self.metadata
    }
}

/// ConfigRuntime invokes this before capturing every canonical publication, not on feed poll.
pub(in crate::config::runtime) fn advance(
    metadata: &mut ConfigurationMetadata,
    closing: bool,
    at: i64,
) {
    let Ok(current) = metadata else {
        return;
    };
    let revision = current.revision();
    if revision.checked_add(1).is_none() {
        *metadata = Err(ConfigurationCaptureFailure::new(
            StudioError::new(
                StudioErrorCode::Overloaded,
                "Configuration source metadata revision is exhausted",
                false,
            )
            .into(),
        ));
        return;
    }
    let command = if closing {
        ObservedResourceCommand::Stop {
            expected_revision: revision,
            stopped_at: at,
        }
    } else {
        ObservedResourceCommand::Observe {
            expected_revision: revision,
            observed_at: at,
            last_checked_at: None,
            value: (),
        }
    };
    *metadata = current
        .decide(command)
        .map(|decision| Arc::new(decision.next_state))
        .map_err(|error| {
            ConfigurationCaptureFailure::metadata_transition(anyhow::Error::new(error))
        });
}
