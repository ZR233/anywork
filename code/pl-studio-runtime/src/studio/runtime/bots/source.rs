//! Immutable captures of BotRuntime canonical/topic material, not a second business reducer.
use std::collections::BTreeMap;
use std::sync::{Arc, Mutex, Weak};

use pl_protocol::products::identity::{ProductReadOrigin, ProductSourceStatusRef};
use pl_protocol::products::source::{ObservedBrief, ObservedHeader, ProductSourceStatusReadHeader};
use pl_protocol::studio::{StudioError, StudioErrorCode};

use super::{BotsHeader, BotsStateSnapshot};

pub(super) struct BotsStatusMaterial {
    pub(super) header: ObservedHeader,
    pub(super) value: ProductSourceStatusReadHeader,
}

pub(super) struct BotsPublication {
    pub(super) value: Arc<BotsStateSnapshot>,
    pub(super) status: Arc<BotsStatusMaterial>,
}

impl BotsPublication {
    pub(super) fn header(&self) -> BotsHeader {
        BotsHeader {
            source: self.status.header.clone(),
            bots_revision: Some(self.value.revision),
            updated_at: Some(self.value.updated_at),
        }
    }
}

#[derive(Default)]
struct State {
    sealed: bool,
    current: Option<Arc<BotsPublication>>,
    statuses: BTreeMap<u64, Weak<BotsStatusMaterial>>,
    status_revision: u64,
}

/// Runtime-owned source. Only an actual canonical capture is marked Ready; socket connection,
/// credential availability and registration progress remain verbatim business fields.
/// No method calls BotRuntime while holding this guard. Actual send is bounded/non-reentrant.
pub(in crate::studio::runtime) struct BotsSource {
    origin: ProductReadOrigin,
    state: Mutex<State>,
}

impl BotsSource {
    pub(in crate::studio::runtime) fn new(origin: ProductReadOrigin) -> Arc<Self> {
        Arc::new(Self {
            origin,
            state: Mutex::new(State::default()),
        })
    }

    pub(super) fn origin(&self) -> &ProductReadOrigin {
        &self.origin
    }

    /// `value` comes only from BotRuntime.snapshot or a BotsStateChanged topic payload.
    /// A lagged topic is never repaired here by looking up latest.
    pub(super) fn capture(
        &self,
        value: BotsStateSnapshot,
    ) -> Result<Arc<BotsPublication>, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.sealed {
            return Err(cancelled());
        }
        if value.revision == 0 {
            return Err(StudioError::new(
                StudioErrorCode::Protocol,
                "Bots canonical capture has no published revision",
                false,
            ));
        }
        if let Some(current) = &state.current {
            if value.revision < current.value.revision {
                return Ok(current.clone());
            }
            if value.revision == current.value.revision {
                if value != *current.value {
                    return Err(StudioError::new(
                        StudioErrorCode::Protocol,
                        "Bots canonical material changed without advancing its revision",
                        false,
                    ));
                }
                return Ok(current.clone());
            }
        }
        let revision = state.status_revision.checked_add(1).ok_or_else(|| {
            StudioError::new(
                StudioErrorCode::Overloaded,
                "Bots source status identity space is exhausted",
                false,
            )
        })?;
        let reference = ProductSourceStatusRef { entry: 1, revision };
        let status = Arc::new(BotsStatusMaterial {
            header: ObservedHeader {
                status: reference,
                brief: ObservedBrief::Ready {
                    revision,
                    updated_at: value.updated_at,
                    last_checked_at: None,
                },
            },
            value: ProductSourceStatusReadHeader::Ready {
                revision,
                updated_at: value.updated_at,
                last_checked_at: None,
            },
        });
        let publication = Arc::new(BotsPublication {
            value: Arc::new(value),
            status,
        });
        state.status_revision = revision;
        state.current = Some(publication.clone());
        state.statuses.retain(|_, value| value.strong_count() != 0);
        Ok(publication)
    }

    pub(super) fn pin_source_status(
        &self,
        origin: &ProductReadOrigin,
        reference: ProductSourceStatusRef,
    ) -> Result<Arc<BotsStatusMaterial>, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.sealed || origin != &self.origin {
            return Err(cancelled());
        }
        state.statuses.retain(|_, value| value.strong_count() != 0);
        if reference.entry != 1
            || reference.revision == 0
            || reference.revision > state.status_revision
        {
            return Err(unpublished());
        }
        // Unexposed current and failed sends are deliberately not reachable by reference.
        state
            .statuses
            .get(&reference.revision)
            .and_then(Weak::upgrade)
            .ok_or_else(|| {
                StudioError::new(
                    StudioErrorCode::Superseded,
                    "The original published Bots status is no longer retained or was never exposed",
                    true,
                )
            })
    }

    /// The send and exposure commit under the same guard. Failed sends neither publish a target
    /// nor grant ACK credit. Inline ACK/read/re-entry from `send` is forbidden.
    pub(super) fn send_exposing(
        &self,
        publication: &BotsPublication,
        send: impl FnOnce() -> Result<bool, StudioError>,
    ) -> Result<bool, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.sealed {
            return Err(cancelled());
        }
        let sent = send()?;
        if sent {
            state.statuses.insert(
                publication.status.header.status.revision,
                Arc::downgrade(&publication.status),
            );
        }
        Ok(sent)
    }

    pub(super) fn ensure_open(&self) -> Result<(), StudioError> {
        if self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .sealed
        {
            Err(cancelled())
        } else {
            Ok(())
        }
    }

    pub(in crate::studio::runtime) fn seal(&self) {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .sealed = true;
    }

    /// Called only after original transport and read owners have joined, never on requestClose.
    pub(in crate::studio::runtime) fn finish_close(&self) {
        let current = {
            let mut state = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            state.sealed = true;
            state.statuses.clear();
            state.current.take()
        };
        drop(current);
    }
}

fn cancelled() -> StudioError {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "The original Bots source is closing or replaced",
        false,
    )
}
fn unpublished() -> StudioError {
    StudioError::new(
        StudioErrorCode::Unavailable,
        "This status was not published by the original Bots source",
        false,
    )
}
