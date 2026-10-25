use super::source::RecoverySnapshot;
use pl_protocol::ObservedResource;
use pl_protocol::products::feed::recovery::*;
use pl_protocol::products::identity::*;
use pl_protocol::products::source::{ObservedBrief, ObservedHeader};

pub(super) fn event(
    identity: &ProductFeedIdentity,
    current: &RecoverySnapshot,
    previous: Option<&SentRecovery>,
) -> Result<RecoveryEvent, ProductResyncReason> {
    let stamp = ProductProjectionStamp {
        owner_epoch: identity.owner_epoch.clone(),
        incarnation: identity.incarnation,
        revision: current.revision,
    };
    let header = RecoveryHeader {
        source: ObservedHeader {
            brief: brief(&current.metadata),
            status: current.status,
        },
        reference: current.reference,
    };
    let Some(previous) = previous else {
        return Ok(RecoveryEvent::Baseline {
            identity: identity.clone(),
            stamp,
            value: RecoveryBaseline {
                header,
                collection: current.collection,
            },
        });
    };
    let upserted: Vec<_> = current
        .entities
        .iter()
        .filter(|reference| !previous.entities.contains(reference))
        .copied()
        .collect();
    let removed_entries: Vec<_> = previous
        .entities
        .iter()
        .filter(|old| !current.entities.iter().any(|new| new.entry == old.entry))
        .map(|old| old.entry)
        .collect();
    if upserted.len() + removed_entries.len() > 100 {
        return Err(ProductResyncReason::SourceLagged);
    }
    Ok(RecoveryEvent::Change {
        stamp,
        base_revision: previous.revision,
        value: RecoveryChange {
            header,
            base_collection_revision: previous.collection.map(|value| value.revision),
            collection: current.collection,
            upserted,
            removed_entries,
        },
    })
}
pub(super) struct SentRecovery {
    pub revision: u64,
    collection: Option<ProductCollectionRef>,
    entities: Vec<ProductEntityRef>,
}
impl SentRecovery {
    pub fn capture(value: &RecoverySnapshot) -> Self {
        Self {
            revision: value.revision,
            collection: value.collection,
            entities: value.entities.clone(),
        }
    }
}
fn brief(value: &ObservedResource<()>) -> ObservedBrief {
    match value {
        ObservedResource::Uninitialized(s) => ObservedBrief::Uninitialized {
            revision: s.revision(),
            updated_at: s.updated_at(),
        },
        ObservedResource::Loading(s) => ObservedBrief::Loading {
            revision: s.revision(),
            started_at: s.started_at(),
        },
        ObservedResource::Ready(s) => ObservedBrief::Ready {
            revision: s.revision(),
            updated_at: s.updated_at(),
            last_checked_at: s.last_checked_at(),
        },
        ObservedResource::Refreshing(s) => ObservedBrief::Refreshing {
            revision: s.revision(),
            started_at: s.started_at(),
            last_checked_at: s.last_checked_at(),
        },
        ObservedResource::Stale(s) => ObservedBrief::Stale {
            revision: s.revision(),
            stale_at: s.stale_at(),
            last_checked_at: s.last_checked_at(),
        },
        ObservedResource::Degraded(s) => ObservedBrief::Degraded {
            revision: s.revision(),
            failed_at: s.failed_at(),
            last_checked_at: s.last_checked_at(),
            retryable: s.error().retryable,
        },
        ObservedResource::Failed(s) => ObservedBrief::Failed {
            revision: s.revision(),
            failed_at: s.failed_at(),
            retryable: s.error().retryable,
        },
        ObservedResource::Stopped(s) => ObservedBrief::Stopped {
            revision: s.revision(),
            stopped_at: s.stopped_at(),
        },
    }
}
