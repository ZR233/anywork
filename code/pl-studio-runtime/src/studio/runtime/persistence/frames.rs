use super::source::{PersistenceQueueSnapshot, PersistenceSnapshot};
use crate::PersistenceState;
use pl_protocol::products::{
    feed::{persistence::*, persistence_queue::*},
    identity::*,
};

pub(super) struct SentPersistence {
    pub revision: u64,
}
impl SentPersistence {
    pub fn capture(value: &PersistenceSnapshot) -> Self {
        Self {
            revision: value.revision,
        }
    }
}
pub(super) fn event(
    identity: &ProductFeedIdentity,
    value: &PersistenceSnapshot,
    previous: Option<&SentPersistence>,
) -> Result<PersistenceEvent, ProductResyncReason> {
    let stamp = ProductProjectionStamp {
        owner_epoch: identity.owner_epoch.clone(),
        incarnation: identity.incarnation,
        revision: value.revision,
    };
    let state = match &value.value.state {
        PersistenceState::Ready(s) => PersistenceBrief::Ready {
            pending_commits: s.pending_commits,
        },
        PersistenceState::Flushing(s) => PersistenceBrief::Flushing {
            pending_commits: s.pending_commits,
            oldest_pending_revision: s.oldest_pending_revision,
        },
        PersistenceState::Degraded(s) => PersistenceBrief::Degraded {
            pending_commits: s.pending_commits,
            oldest_pending_revision: s.oldest_pending_revision,
            first_failed_at: s.first_failed_at,
        },
        PersistenceState::Recovering(s) => PersistenceBrief::Recovering {
            pending_commits: s.pending_commits,
            oldest_pending_revision: s.oldest_pending_revision,
            first_failed_at: s.first_failed_at,
        },
        PersistenceState::Blocked(s) => PersistenceBrief::Blocked {
            pending_commits: s.pending_commits,
            oldest_pending_revision: s.oldest_pending_revision,
            first_failed_at: s.first_failed_at,
        },
    };
    let value = PersistenceHeader {
        reference: value.reference,
        revision: value.value.revision,
        state,
    };
    Ok(match previous {
        None => PersistenceEvent::Baseline {
            identity: identity.clone(),
            stamp,
            value,
        },
        Some(previous) => PersistenceEvent::Replace {
            stamp,
            base_revision: previous.revision,
            value,
        },
    })
}
pub(super) struct SentPersistenceQueue {
    pub revision: u64,
    collection: ProductCollectionRef,
    entities: Vec<ProductEntityRef>,
}
impl SentPersistenceQueue {
    pub fn capture(value: &PersistenceQueueSnapshot) -> Self {
        Self {
            revision: value.revision,
            collection: value.collection,
            entities: value.entities.clone(),
        }
    }
}
pub(super) fn queue_event(
    identity: &ProductFeedIdentity,
    current: &PersistenceQueueSnapshot,
    previous: Option<&SentPersistenceQueue>,
) -> Result<PersistenceQueueEvent, ProductResyncReason> {
    let stamp = ProductProjectionStamp {
        owner_epoch: identity.owner_epoch.clone(),
        incarnation: identity.incarnation,
        revision: current.revision,
    };
    let queue = &current.value.queue;
    let header = PersistenceQueueHeader {
        reference: current.reference,
        revision: current.value.revision,
        updated_at: current.value.updated_at,
        statistics_gap: queue.statistics_gap,
        pending_operations: queue.pending_operations,
        pending_bytes: queue.pending_bytes,
        in_flight_bytes: queue.in_flight_bytes,
        oldest_pending_age_millis: queue.oldest_pending_age_millis,
        pressure_paused: queue.pressure_paused,
        has_last_error: queue.last_error.is_some(),
    };
    let Some(previous) = previous else {
        return Ok(PersistenceQueueEvent::Baseline {
            identity: identity.clone(),
            stamp,
            value: PersistenceQueueBaseline {
                header,
                collection: Some(current.collection),
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
    Ok(PersistenceQueueEvent::Change {
        stamp,
        base_revision: previous.revision,
        value: PersistenceQueueChange {
            header,
            base_collection_revision: Some(previous.collection.revision),
            collection: Some(current.collection),
            upserted,
            removed_entries,
        },
    })
}
