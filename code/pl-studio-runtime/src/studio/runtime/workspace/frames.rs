use std::collections::{BTreeMap, BTreeSet};

use pl_protocol::products::feed::{
    agent_directory as agent, project_directory as project, thread_directory as thread,
};
use pl_protocol::products::identity::{
    ProductFeedCloseReason, ProductFeedIdentity, ProductProjectionStamp, ProductResyncReason,
};
use pl_protocol::products::references::{
    AgentDirectoryReadRef, ProjectDirectoryReadRef, ThreadDirectoryReadRef,
};
use pl_protocol::studio::StudioError;
use serde::Serialize;

use super::source::DirectorySnapshot;
use super::source_status::observed;

pub(super) enum FrameError {
    Source(StudioError),
    Resync(ProductResyncReason),
}
impl From<StudioError> for FrameError {
    fn from(error: StudioError) -> Self {
        Self::Source(error)
    }
}

pub(super) trait DirectoryFrames {
    type Frame: Serialize;
    type Event;
    fn event(
        identity: &ProductFeedIdentity,
        snapshot: &DirectorySnapshot,
        previous: Option<&DirectorySnapshot>,
    ) -> Result<Self::Event, FrameError>;
    fn data(sequence: u64, event: Self::Event) -> Self::Frame;
    fn resync(identity: ProductFeedIdentity, reason: ProductResyncReason) -> Self::Frame;
    fn failure(identity: ProductFeedIdentity, error: StudioError) -> Self::Frame;
    fn closed(identity: ProductFeedIdentity, reason: ProductFeedCloseReason) -> Self::Frame;
}

pub(super) struct ProjectFrames;
pub(super) struct AgentFrames;
pub(super) struct ThreadFrames;

fn stamp(identity: &ProductFeedIdentity, snapshot: &DirectorySnapshot) -> ProductProjectionStamp {
    ProductProjectionStamp {
        owner_epoch: identity.owner_epoch.clone(),
        incarnation: identity.incarnation,
        revision: snapshot.revision,
    }
}
fn visible(snapshot: &DirectorySnapshot) -> bool {
    snapshot.capture.metadata.value().is_some()
}
fn changes(
    snapshot: &DirectorySnapshot,
    previous: &DirectorySnapshot,
) -> Result<
    (
        Vec<pl_protocol::products::identity::ProductEntityRef>,
        Vec<u64>,
    ),
    FrameError,
> {
    if snapshot.revision <= previous.revision {
        return Err(FrameError::Resync(ProductResyncReason::RevisionGap));
    }
    // Unavailability preserves the SDK's last-known window; it is not a deletion fact.
    if !visible(snapshot) {
        return Ok((Vec::new(), Vec::new()));
    }
    let current: BTreeSet<_> = snapshot.entities.iter().map(|value| value.entry).collect();
    let prior: BTreeMap<_, _> = previous
        .entities
        .iter()
        .map(|value| (value.entry, value.revision))
        .collect();
    let mut upserted = Vec::new();
    let mut removed = Vec::new();
    for reference in &snapshot.entities {
        if prior.get(&reference.entry) != Some(&reference.revision) {
            upserted.push(*reference);
            if upserted.len() > 100 {
                return Err(FrameError::Resync(ProductResyncReason::SourceLagged));
            }
        }
    }
    for reference in &previous.entities {
        if !current.contains(&reference.entry) {
            removed.push(reference.entry);
            if upserted.len() + removed.len() > 100 {
                return Err(FrameError::Resync(ProductResyncReason::SourceLagged));
            }
        }
    }
    Ok((upserted, removed))
}

fn project_header(
    snapshot: &DirectorySnapshot,
) -> Result<project::ProjectDirectoryHeader, StudioError> {
    Ok(project::ProjectDirectoryHeader {
        source: observed(&snapshot.status),
        reference: visible(snapshot).then_some(ProjectDirectoryReadRef {
            entry: snapshot.entry,
            revision: snapshot.revision,
        }),
    })
}
fn agent_header(snapshot: &DirectorySnapshot) -> Result<agent::AgentDirectoryHeader, StudioError> {
    Ok(agent::AgentDirectoryHeader {
        source: observed(&snapshot.status),
        reference: visible(snapshot).then_some(AgentDirectoryReadRef {
            entry: snapshot.entry,
            revision: snapshot.revision,
        }),
    })
}
fn thread_header(
    snapshot: &DirectorySnapshot,
) -> Result<thread::ThreadDirectoryHeader, StudioError> {
    super::super::read_budget::bounded_header(|inline| {
        Ok(thread::ThreadDirectoryHeader {
            source: observed(&snapshot.status),
            reference: visible(snapshot).then_some(ThreadDirectoryReadRef {
                entry: snapshot.entry,
                revision: snapshot.revision,
            }),
            directory_revision: snapshot.capture.directory_revision,
            search_project_revision: snapshot.capture.search_project_revision,
            has_more: visible(snapshot).then_some(snapshot.capture.frontier.is_some()),
            next_cursor: snapshot.cursor_text(inline)?,
        })
    })
}

// Nominal protocol enums differ, but have the same exhaustive envelope. This macro does not
// contain admission, send, ACK, cancellation or cleanup; those remain explicit in feed.rs.
macro_rules! directory_frames {
    ($adapter:ident, $module:ident, $event:ident, $frame:ident, $baseline:ident, $change:ident, $header:ident) => {
        impl DirectoryFrames for $adapter {
            type Frame = $module::$frame;
            type Event = $module::$event;
            fn event(
                identity: &ProductFeedIdentity,
                snapshot: &DirectorySnapshot,
                previous: Option<&DirectorySnapshot>,
            ) -> Result<Self::Event, FrameError> {
                let header = $header(snapshot)?;
                let collection = visible(snapshot).then_some(snapshot.collection);
                let stamp = stamp(identity, snapshot);
                let Some(previous) = previous else {
                    return Ok($module::$event::Baseline {
                        identity: identity.clone(),
                        stamp,
                        value: $module::$baseline { header, collection },
                    });
                };
                let (upserted, removed_entries) = changes(snapshot, previous)?;
                Ok($module::$event::Change {
                    stamp,
                    base_revision: previous.revision,
                    value: $module::$change {
                        header,
                        base_collection_revision: visible(previous)
                            .then_some(previous.collection.revision),
                        collection,
                        upserted,
                        removed_entries,
                    },
                })
            }
            fn data(delivery_sequence: u64, event: Self::Event) -> Self::Frame {
                $module::$frame::Data {
                    delivery_sequence,
                    event,
                }
            }
            fn resync(identity: ProductFeedIdentity, reason: ProductResyncReason) -> Self::Frame {
                $module::$frame::ResyncRequired { identity, reason }
            }
            fn failure(identity: ProductFeedIdentity, error: StudioError) -> Self::Frame {
                $module::$frame::Failure { identity, error }
            }
            fn closed(
                identity: ProductFeedIdentity,
                reason: ProductFeedCloseReason,
            ) -> Self::Frame {
                $module::$frame::Closed { identity, reason }
            }
        }
    };
}
directory_frames!(
    ProjectFrames,
    project,
    ProjectDirectoryEvent,
    ProjectDirectoryFrame,
    ProjectDirectoryBaseline,
    ProjectDirectoryChange,
    project_header
);
directory_frames!(
    AgentFrames,
    agent,
    AgentDirectoryEvent,
    AgentDirectoryFrame,
    AgentDirectoryBaseline,
    AgentDirectoryChange,
    agent_header
);
directory_frames!(
    ThreadFrames,
    thread,
    ThreadDirectoryEvent,
    ThreadDirectoryFrame,
    ThreadDirectoryBaseline,
    ThreadDirectoryChange,
    thread_header
);
