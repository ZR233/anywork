//! Availability metadata from the canonical config guard, without another Models business value.
use std::sync::Arc;

use pl_protocol::products::identity::ProductSourceStatusRef;
use pl_protocol::products::source::{ObservedBrief, ObservedHeader};
use pl_protocol::studio::{StudioError, StudioErrorCode};
use pl_protocol::{ObservedResource, ObservedResourceCommand, ObservedResourceTransitionError};

pub(in crate::config::runtime) type ModelSourceMetadata =
    Result<Arc<ObservedResource<()>>, Arc<ModelSourceStatusFailure>>;

/// Source metadata failure is distinct from a Models business capture or a transport failure.
#[derive(Debug, thiserror::Error)]
pub(crate) enum ModelSourceStatusFailure {
    #[error("Models source metadata revision is exhausted at {revision}")]
    RevisionExhausted { revision: u64 },
    #[error("Models source status reference identity space is exhausted")]
    IdentityExhausted,
    #[error(transparent)]
    Transition(#[from] ObservedResourceTransitionError<()>),
}

impl ModelSourceStatusFailure {
    pub(crate) fn diagnostic(&self) -> StudioError {
        match self {
            Self::RevisionExhausted { .. } | Self::IdentityExhausted => StudioError::new(
                StudioErrorCode::Overloaded,
                "Models source metadata identity space is exhausted",
                false,
            ),
            Self::Transition(_) => StudioError::new(
                StudioErrorCode::Protocol,
                "The canonical Models source metadata transition failed",
                false,
            ),
        }
    }
}

/// A status pin retains the complete original typed metadata, including operation/diagnostic
/// strings in the phases that own them. A later ReadText scope can borrow those strings rather
/// than truncating them or resolving them against the current config owner.
pub(crate) struct ModelSourceStatusMaterial {
    pub(crate) header: ObservedHeader,
    metadata: Arc<ObservedResource<()>>,
}

impl ModelSourceStatusMaterial {
    pub(super) fn new(
        reference: ProductSourceStatusRef,
        metadata: Arc<ObservedResource<()>>,
    ) -> Self {
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
                status: reference,
            },
            metadata,
        }
    }

    pub(crate) fn metadata(&self) -> &ObservedResource<()> {
        self.metadata.as_ref()
    }
}

pub(in crate::config::runtime) fn observe_source(
    metadata: &mut ModelSourceMetadata,
    observed_at: i64,
) {
    let Ok(current) = metadata else {
        return;
    };
    let command = ObservedResourceCommand::Observe {
        expected_revision: current.revision(),
        observed_at,
        last_checked_at: None,
        value: (),
    };
    transition(metadata, command);
}

pub(in crate::config::runtime) fn stop_source(metadata: &mut ModelSourceMetadata, stopped_at: i64) {
    let Ok(current) = metadata else {
        return;
    };
    let command = ObservedResourceCommand::Stop {
        expected_revision: current.revision(),
        stopped_at,
    };
    transition(metadata, command);
}

fn transition(metadata: &mut ModelSourceMetadata, command: ObservedResourceCommand<()>) {
    let Ok(current) = metadata else {
        return;
    };
    // ObservedResource's shared transition uses saturating arithmetic. Check first here so an
    // exhausted source is explicitly unavailable without changing a committed config result.
    *metadata = if current.revision().checked_add(1).is_none() {
        Err(Arc::new(ModelSourceStatusFailure::RevisionExhausted {
            revision: current.revision(),
        }))
    } else {
        current
            .decide(command)
            .map(|decision| Arc::new(decision.next_state))
            .map_err(|error| Arc::new(ModelSourceStatusFailure::Transition(error)))
    };
}
