//! Local audience projection and observation; neither path activates a Thread or bot connection.

use anyhow::{Result, ensure};
use pl_protocol::{Thread, ThreadAudience, ThreadAudienceUnavailableReason, studio::*};
use tokio::sync::watch;

use super::StudioRuntime;
use crate::studio::thread_audience::{
    BotAudienceWatchVersion, BotThreadInputReadiness, ThreadAudienceOwner,
    VerifiedBotAudienceOwner, frozen_owner,
};

pub(super) struct ThreadAudienceObservation {
    pub(super) current: ThreadAudience,
    owner: Option<VerifiedBotAudienceOwner>,
    updates: Option<watch::Receiver<BotAudienceWatchVersion>>,
    observed: Option<BotAudienceWatchVersion>,
    closed: bool,
}

fn unavailable(reason: ThreadAudienceUnavailableReason) -> ThreadAudience {
    ThreadAudience::Unavailable { reason }
}

impl ThreadAudienceObservation {
    /// `changed` may mark the watch seen, so refresh compares the retained value with the version
    /// read BEFORE the previous SQL query, not merely with watch::has_changed.
    pub(super) async fn changed(&mut self) {
        match self.updates.as_mut() {
            Some(receiver) => {
                if receiver.changed().await.is_err() {
                    self.updates = None;
                    self.closed = true;
                }
            }
            None => std::future::pending().await,
        }
    }

    pub(super) async fn refresh(
        &mut self,
        runtime: &StudioRuntime,
        thread_id: &str,
    ) -> Option<ThreadAudience> {
        let receiver_closed = self
            .updates
            .as_ref()
            .is_some_and(|receiver| receiver.has_changed().is_err());
        let next = if self.closed || receiver_closed {
            self.closed = false;
            self.updates = None;
            unavailable(ThreadAudienceUnavailableReason::BotUnavailable)
        } else {
            let receiver = self.updates.as_mut()?;
            let version = receiver.borrow_and_update().clone();
            if self.observed.as_ref() == Some(&version) {
                return None;
            }
            let owner = self.owner.as_ref()?;
            let next = runtime.audience_from_bot(owner, thread_id).await;
            // `recv` can lose a select while this query waits. Only acknowledge the version after
            // the projection is available, so reusing that subscription retries a cancelled read.
            self.observed = Some(version);
            next
        };
        if self.current == next {
            return None;
        }
        self.current = next.clone();
        Some(next)
    }
}

impl StudioRuntime {
    /// Called after canonical input replay checks but before configuration or attachment changes.
    /// This is a read of initialization facts, not a delivery permission or an initializer.
    pub(super) async fn ensure_thread_input_ready(
        &self,
        thread: &crate::studio::ThreadRecord,
        state: &pl_core::thread::ThreadSnapshot,
    ) -> Result<()> {
        let owner = match frozen_owner(&thread.clone().into(), state)? {
            ThreadAudienceOwner::Unbound => return Ok(()),
            ThreadAudienceOwner::Bot(owner) => owner,
            ThreadAudienceOwner::Unavailable(reason) => {
                return Err(StudioError::new(
                    StudioErrorCode::Unavailable,
                    format!("Thread input ownership is unavailable: {reason:?}"),
                    true,
                )
                .into());
            }
        };
        match self
            .bots
            .read_thread_input_readiness(&owner, &thread.id)
            .await
            .map_err(|error| anyhow::Error::from(error.studio_error()))?
        {
            BotThreadInputReadiness::Ready => Ok(()),
            BotThreadInputReadiness::Preparing => Err(StudioError::new(
                StudioErrorCode::Busy,
                "The bot conversation is preparing its first input; retry after initialization",
                true,
            )
            .into()),
        }
    }

    async fn audience_from_bot(
        &self,
        owner: &VerifiedBotAudienceOwner,
        thread_id: &str,
    ) -> ThreadAudience {
        self.bots
            .read_thread_audience(owner, thread_id)
            .await
            .unwrap_or_else(|_| unavailable(ThreadAudienceUnavailableReason::StateUnreadable))
    }

    pub(super) async fn observe_thread_audience(
        &self,
        thread: &Thread,
        state: &pl_core::thread::ThreadSnapshot,
    ) -> ThreadAudienceObservation {
        let mut observation = ThreadAudienceObservation {
            current: unavailable(ThreadAudienceUnavailableReason::OwnershipUnproven),
            owner: None,
            updates: None,
            observed: None,
            closed: false,
        };
        match frozen_owner(thread, state) {
            Ok(ThreadAudienceOwner::Unbound) => observation.current = ThreadAudience::Unbound {},
            Ok(ThreadAudienceOwner::Unavailable(reason)) => {
                observation.current = unavailable(reason)
            }
            Err(_) => {
                observation.current = unavailable(ThreadAudienceUnavailableReason::InvalidOwnership)
            }
            Ok(ThreadAudienceOwner::Bot(owner)) => {
                match self.bots.audience_watch(&owner).await {
                    Ok(mut updates) => {
                        // Subscribe and record the observed version before reading the baseline.
                        // Any intervening mutation remains observable on the next refresh.
                        observation.observed = Some(updates.borrow_and_update().clone());
                        observation.updates = Some(updates);
                    }
                    Err(_) => {
                        observation.current =
                            unavailable(ThreadAudienceUnavailableReason::BotUnavailable);
                        observation.owner = Some(owner);
                        return observation;
                    }
                }
                observation.current = self.audience_from_bot(&owner, &thread.id).await;
                observation.owner = Some(owner);
            }
        }
        observation
    }

    pub(super) async fn thread_audience_snapshot(
        &self,
        thread: &Thread,
        state: &pl_core::thread::ThreadSnapshot,
    ) -> ThreadAudience {
        match frozen_owner(thread, state) {
            Ok(ThreadAudienceOwner::Unbound) => ThreadAudience::Unbound {},
            Ok(ThreadAudienceOwner::Unavailable(reason)) => unavailable(reason),
            Ok(ThreadAudienceOwner::Bot(owner)) => self.audience_from_bot(&owner, &thread.id).await,
            Err(_) => unavailable(ThreadAudienceUnavailableReason::InvalidOwnership),
        }
    }

    async fn audience_owner_for_query(&self, thread_id: &str) -> Result<ThreadAudienceOwner> {
        let thread = self.read_protocol_thread(thread_id).await?;
        let state = match self.read_thread_state(thread_id).await {
            Ok(state) => state,
            Err(_) => {
                return Ok(ThreadAudienceOwner::Unavailable(
                    ThreadAudienceUnavailableReason::StateUnreadable,
                ));
            }
        };
        Ok(
            frozen_owner(&thread, &state).unwrap_or(ThreadAudienceOwner::Unavailable(
                ThreadAudienceUnavailableReason::InvalidOwnership,
            )),
        )
    }

    pub async fn read_thread_closed_authorizations(
        &self,
        request: ReadThreadClosedAuthorizationsRequest,
    ) -> Result<ReadThreadClosedAuthorizationsReply> {
        ensure!(
            (1..=MAX_CLOSED_AUTHORIZATION_PAGE_SIZE).contains(
                &request
                    .limit
                    .unwrap_or(DEFAULT_CLOSED_AUTHORIZATION_PAGE_SIZE)
            ),
            StudioError::new(
                StudioErrorCode::InvalidArgument,
                "invalid closed authorization page size",
                false
            )
        );
        let result = match self.audience_owner_for_query(&request.thread_id).await? {
            ThreadAudienceOwner::Unbound => ThreadClosedAuthorizationsRead::Unbound {},
            ThreadAudienceOwner::Unavailable(reason) => {
                ThreadClosedAuthorizationsRead::Unavailable { reason }
            }
            ThreadAudienceOwner::Bot(owner) => self
                .bots
                .read_thread_closed_authorizations(&owner, &request)
                .await
                .map_err(|error| anyhow::Error::from(error.studio_error()))?,
        };
        Ok(ReadThreadClosedAuthorizationsReply {
            thread_id: request.thread_id,
            result,
        })
    }

    pub async fn read_thread_audience_items(
        &self,
        request: ReadThreadAudienceItemsRequest,
    ) -> Result<ReadThreadAudienceItemsReply> {
        ensure!(
            !request.item_ids.is_empty() && request.item_ids.len() <= MAX_THREAD_AUDIENCE_ITEM_IDS,
            StudioError::new(
                StudioErrorCode::InvalidArgument,
                "audience item query requires 1..=100 identities",
                false
            )
        );
        let unique = request
            .item_ids
            .iter()
            .collect::<std::collections::BTreeSet<_>>();
        ensure!(
            unique.len() == request.item_ids.len()
                && request.item_ids.iter().all(|id| !id.is_empty()),
            StudioError::new(
                StudioErrorCode::InvalidArgument,
                "audience item identities must be nonempty and unique",
                false
            )
        );
        let result = match self.audience_owner_for_query(&request.thread_id).await? {
            ThreadAudienceOwner::Bot(owner) if owner.bot_id() == request.authorization.bot_id => {
                self.bots
                    .read_thread_audience_items(&owner, &request)
                    .await
                    .map_err(|error| anyhow::Error::from(error.studio_error()))?
            }
            ThreadAudienceOwner::Unavailable(_) => BotAudienceItemsRead::Unavailable {
                reason: BotAudienceItemsUnavailableReason::OwnerUnavailable,
            },
            ThreadAudienceOwner::Unbound | ThreadAudienceOwner::Bot(_) => {
                BotAudienceItemsRead::Unavailable {
                    reason: BotAudienceItemsUnavailableReason::ScopeChanged,
                }
            }
        };
        Ok(ReadThreadAudienceItemsReply {
            thread_id: request.thread_id,
            authorization: request.authorization,
            result,
        })
    }

    pub async fn change_bot_thread_sync(
        &self,
        request: ChangeBotThreadSyncRequest,
    ) -> Result<ChangeBotThreadSyncReply> {
        Self::validate_operation_id(&request.operation_id)?;
        let ThreadAudienceOwner::Bot(owner) =
            self.audience_owner_for_query(&request.thread_id).await?
        else {
            return Err(StudioError::new(
                StudioErrorCode::PermissionDenied,
                "Thread has no proven bot audience",
                false,
            )
            .into());
        };
        self.bots
            .change_thread_sync(&owner, request, &self.owner_epoch)
            .await
            .map_err(|error| anyhow::Error::from(error.studio_error()))
    }
}
