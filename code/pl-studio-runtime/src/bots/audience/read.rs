//! Local snapshots and bounded item status. Canonical metadata is read only through Session.

use crate::bots::BotRuntime;
use crate::bots::owner::ManagedBot;
use crate::bots::protocol::error::{FeishuError, FeishuErrorKind};
use crate::bots::storage::audience::{AudienceScope, Authorization, unreadable};
use crate::studio::thread_audience::{BotAudienceWatchVersion, VerifiedBotAudienceOwner};
use pl_protocol::studio::*;
use pl_protocol::*;
use serde::{Deserialize, Serialize};
use std::result::Result;

impl BotRuntime {
    /// Local input admission reads only the original creation/authorization facts. Display target,
    /// delivery counters, current trust and sockets do not decide whether local work can continue.
    pub(crate) async fn read_thread_input_readiness(
        &self,
        owner: &VerifiedBotAudienceOwner,
        thread_id: &str,
    ) -> Result<crate::studio::thread_audience::BotThreadInputReadiness, FeishuError> {
        let managed = self.managed(owner.bot_id()).await?;
        let project = managed.config.lock().await.project_id.clone();
        managed
            .store
            .thread_input_readiness(owner.bot_id(), thread_id, &project)
            .await
    }

    pub(crate) async fn audience_watch(
        &self,
        owner: &VerifiedBotAudienceOwner,
    ) -> Result<tokio::sync::watch::Receiver<BotAudienceWatchVersion>, FeishuError> {
        Ok(self
            .managed(owner.bot_id())
            .await?
            .audience_changes
            .subscribe())
    }

    pub(crate) async fn read_thread_audience(
        &self,
        owner: &VerifiedBotAudienceOwner,
        thread: &str,
    ) -> Result<ThreadAudience, FeishuError> {
        let managed = match self.managed(owner.bot_id()).await {
            Ok(m) => m,
            Err(_) => return Ok(unavailable(ThreadAudienceUnavailableReason::BotUnavailable)),
        };
        self.audience_view(&managed, thread).await
    }

    pub(super) async fn audience_view(
        &self,
        managed: &ManagedBot,
        thread: &str,
    ) -> Result<ThreadAudience, FeishuError> {
        if self.runtime_released() {
            return Ok(unavailable(ThreadAudienceUnavailableReason::RuntimeClosed));
        }
        let bot_id = managed.config.lock().await.id.clone();
        let scope = match managed.store.audience_scope(thread, &bot_id).await {
            Ok(Some(scope)) => scope,
            Ok(None) => {
                return Ok(unavailable(
                    ThreadAudienceUnavailableReason::OwnershipUnproven,
                ));
            }
            Err(_) => {
                return Ok(unavailable(
                    ThreadAudienceUnavailableReason::InconsistentScope,
                ));
            }
        };
        if scope.binding.thread_id.as_deref() == Some(thread) && scope.binding.status != "bound" {
            return Ok(unavailable(
                ThreadAudienceUnavailableReason::BindingUnavailable,
            ));
        }
        let config = managed.config.lock().await.clone();
        let target = match target(managed, &config, &scope).await {
            Ok(t) => t,
            Err(_) => {
                return Ok(unavailable(
                    ThreadAudienceUnavailableReason::StateUnreadable,
                ));
            }
        };
        let current = scope.binding.thread_id.as_deref() == Some(thread);
        let head = scope
            .head
            .as_ref()
            .map_or(BotAuthorizationHead::None {}, |a| {
                BotAuthorizationHead::Present {
                    authorization: a.reference(),
                }
            });
        let binding = if current {
            let sync = if scope.origin.requires_upgrade {
                BotCurrentSync::RequiresUpgrade {}
            } else {
                match scope.head.as_ref().filter(|a| a.intent.thread_id == thread) {
                    Some(a) => sync(a),
                    None => BotCurrentSync::Closed {},
                }
            };
            BotThreadBindingPosition::Current {
                cas: BotSyncCas {
                    binding_revision: scope.binding.revision,
                    authorization_head: head,
                },
                sync: Box::new(sync),
            }
        } else {
            BotThreadBindingPosition::Replaced {
                last_binding_revision: scope.origin.binding_revision,
                current_binding_revision: scope.binding.revision,
            }
        };
        let (delivery, legacy_final) = match managed
            .store
            .audience_counts(thread, scope.origin.summary_version)
            .await
        {
            Ok(counts) => counts,
            Err(_) => {
                return Ok(unavailable(
                    ThreadAudienceUnavailableReason::StateUnreadable,
                ));
            }
        };
        Ok(ThreadAudience::Known {
            audience: Box::new(BotThreadAudience {
                target,
                binding,
                latest_closed: scope.latest_closed.as_ref().map(closed).transpose()?,
                has_older_closed: scope.has_older_closed,
                delivery,
                legacy_final,
            }),
        })
    }

    pub(crate) async fn read_thread_closed_authorizations(
        &self,
        owner: &VerifiedBotAudienceOwner,
        request: &ReadThreadClosedAuthorizationsRequest,
    ) -> Result<ThreadClosedAuthorizationsRead, FeishuError> {
        let limit = request
            .limit
            .unwrap_or(DEFAULT_CLOSED_AUTHORIZATION_PAGE_SIZE);
        if !(1..=MAX_CLOSED_AUTHORIZATION_PAGE_SIZE).contains(&limit) {
            return Err(invalid());
        }
        let managed = self.managed(owner.bot_id()).await?;
        let scope = match managed
            .store
            .audience_scope(&request.thread_id, owner.bot_id())
            .await
        {
            Ok(Some(s)) => s,
            _ => {
                return Ok(ThreadClosedAuthorizationsRead::Unavailable {
                    reason: ThreadAudienceUnavailableReason::InconsistentScope,
                });
            }
        };
        let config = managed.config.lock().await.clone();
        let target = target(&managed, &config, &scope).await?;
        let cursor = match request.cursor.as_deref() {
            Some(text) => {
                let cursor: ClosedCursor =
                    serde_json::from_str(text.strip_prefix("bot-auth-v1:").ok_or_else(invalid)?)
                        .map_err(|_| invalid())?;
                if cursor.thread != request.thread_id
                    || cursor.bot != owner.bot_id()
                    || cursor.chat != scope.origin.chat_id
                    || cursor.highest == 0
                    || cursor
                        .before
                        .is_none_or(|before| before == 0 || before > cursor.highest)
                {
                    return Err(invalid());
                }
                cursor
            }
            None => ClosedCursor {
                thread: request.thread_id.clone(),
                bot: owner.bot_id().into(),
                chat: scope.origin.chat_id.clone(),
                highest: scope
                    .latest_closed
                    .as_ref()
                    .map_or(0, |a| a.intent.authorization.generation),
                before: None,
            },
        };
        let mut rows = managed
            .store
            .closed_authorizations(&request.thread_id, cursor.highest, cursor.before, limit + 1)
            .await?;
        let more = rows.len() > limit as usize;
        rows.truncate(limit as usize);
        let next_cursor = if more {
            let last = rows.last().ok_or_else(unreadable)?;
            Some(format!(
                "bot-auth-v1:{}",
                serde_json::to_string(&ClosedCursor {
                    before: Some(last.intent.authorization.generation),
                    ..cursor
                })
                .map_err(|_| unreadable())?
            ))
        } else {
            None
        };
        Ok(ThreadClosedAuthorizationsRead::Page {
            page: ThreadClosedAuthorizationPage {
                target,
                authorizations: rows.iter().map(closed).collect::<Result<_, _>>()?,
                next_cursor,
            },
        })
    }

    pub(crate) async fn read_thread_audience_items(
        &self,
        owner: &VerifiedBotAudienceOwner,
        request: &ReadThreadAudienceItemsRequest,
    ) -> Result<BotAudienceItemsRead, FeishuError> {
        if request.authorization.bot_id != owner.bot_id()
            || request.item_ids.is_empty()
            || request.item_ids.len() > MAX_THREAD_AUDIENCE_ITEM_IDS
            || request.item_ids.iter().any(String::is_empty)
            || request
                .item_ids
                .iter()
                .collect::<std::collections::BTreeSet<_>>()
                .len()
                != request.item_ids.len()
        {
            return Err(invalid());
        }
        let managed = self.managed(owner.bot_id()).await?;
        let Some(auth) = managed
            .store
            .audience_authorization(&request.authorization)
            .await?
        else {
            return Err(FeishuError::new(
                FeishuErrorKind::NotFound,
                "audience generation not found",
                false,
                None,
            ));
        };
        if auth.intent.thread_id != request.thread_id {
            return Err(invalid());
        }
        let Some(scope) = managed
            .store
            .audience_scope(&request.thread_id, owner.bot_id())
            .await?
        else {
            return Ok(items_unavailable(
                BotAudienceItemsUnavailableReason::ScopeChanged,
            ));
        };
        if scope.origin.chat_id != request.authorization.chat_id {
            return Err(invalid());
        }
        let Some(host) = self.studio_host() else {
            return Ok(items_unavailable(
                BotAudienceItemsUnavailableReason::OwnerUnavailable,
            ));
        };
        let reader = host
            .timeline_reader(&request.thread_id)
            .await
            .map_err(|e| FeishuError::history_read("audience metadata reader unavailable", e))?;
        let metadata = reader
            .read_metadata(&request.item_ids)
            .await
            .map_err(|e| FeishuError::history_read("audience metadata unavailable", e))?;
        let mut items = Vec::with_capacity(metadata.len());
        for (id, read) in request.item_ids.iter().zip(metadata) {
            let observation = managed
                .store
                .audience_item(&request.authorization, id)
                .await?;
            let canonical = match read {
                crate::studio::TimelineMetadataRead::Missing { item_id } => {
                    if item_id != *id {
                        return Err(unreadable());
                    }
                    if observation.as_ref().is_some_and(|o| o.removed) {
                        BotAudienceCanonicalItem::Removed {}
                    } else {
                        BotAudienceCanonicalItem::Unavailable {
                            reason: BotCanonicalUnavailableReason::Missing,
                        }
                    }
                }
                crate::studio::TimelineMetadataRead::Present(meta) => {
                    if observation.as_ref().is_some_and(|o| {
                        o.thread_id != request.thread_id
                            || o.ledger.observed_revision > meta.shell.revision
                    }) {
                        return Ok(items_unavailable(
                            BotAudienceItemsUnavailableReason::CanonicalReadInvalidated,
                        ));
                    }
                    match self.item_eligibility(&host, &auth, &meta.shell).await? {
                        Some(eligibility) => BotAudienceCanonicalItem::Present {
                            revision: meta.shell.revision,
                            saved: meta.saved,
                            eligibility,
                        },
                        None => BotAudienceCanonicalItem::Unavailable {
                            reason: BotCanonicalUnavailableReason::StartProofUnavailable,
                        },
                    }
                }
            };
            items.push(BotAudienceItemStatus {
                item_id: id.clone(),
                canonical,
                delivery: match observation {
                    Some(o) => BotItemDelivery::Known {
                        ledger: Box::new(o.ledger),
                    },
                    None => BotItemDelivery::NotProjected {},
                },
            });
        }
        if managed
            .store
            .audience_authorization(&request.authorization)
            .await?
            .as_ref()
            != Some(&auth)
        {
            return Ok(items_unavailable(
                BotAudienceItemsUnavailableReason::ScopeChanged,
            ));
        }
        Ok(BotAudienceItemsRead::Items {
            authorization: auth.reference(),
            phase: auth.phase,
            summary_version: scope.origin.summary_version,
            delivery_version: auth.delivery_version,
            items,
        })
    }

    pub(super) async fn item_eligibility(
        &self,
        host: &crate::studio::StudioRuntime,
        auth: &Authorization,
        item: &ThreadItem,
    ) -> Result<Option<BotItemEligibility>, FeishuError> {
        if auth.phase == BotAuthorizationPhase::Closed {
            return Ok(Some(excluded(BotItemExclusion::OutsideAuthorization)));
        }
        let content = match item.state() {
            ThreadItemState::Text(text) => match text.channel() {
                ThreadTextChannel::Commentary => BotItemEligibility::Text {
                    channel: BotPublicTextChannel::Commentary,
                },
                ThreadTextChannel::Final => BotItemEligibility::Text {
                    channel: BotPublicTextChannel::Final,
                },
                _ => return Ok(Some(excluded(BotItemExclusion::NonPublicContent))),
            },
            ThreadItemState::PublicArtifact(_) => BotItemEligibility::PublicArtifact {},
            _ => return Ok(Some(excluded(BotItemExclusion::NonPublicContent))),
        };
        if item.thread_id != auth.intent.thread_id {
            return Err(unreadable());
        }
        let Some(start) = &auth.start else {
            return Ok(None);
        };
        if start.excluded_turn_id.as_deref() == Some(&item.turn_id) {
            return Ok(Some(excluded(BotItemExclusion::ExcludedStartedTurn)));
        }
        if item.turn_id.is_empty() {
            return Ok(None);
        }
        let Some(turn) = host
            .bot_turn_start_fact(&item.thread_id, &item.turn_id)
            .await
            .map_err(|e| FeishuError::history_read("Turn start proof unavailable", e))?
        else {
            return Ok(None);
        };
        if turn.sequence <= start.sequence {
            return Ok(Some(excluded(BotItemExclusion::OutsideAuthorization)));
        }
        Ok(Some(content))
    }
}

pub(super) async fn target(
    managed: &ManagedBot,
    config: &crate::bots::config::BotConfigFile,
    scope: &AudienceScope,
) -> Result<BotAudienceTarget, FeishuError> {
    let (kind, _) = managed.store.audience_target(&scope.origin.chat_id).await?;
    Ok(BotAudienceTarget {
        bot_id: config.id.clone(),
        bot_name: config.name.clone(),
        chat_id: scope.origin.chat_id.clone(),
        chat_name: None,
        kind,
    })
}

fn sync(auth: &Authorization) -> BotCurrentSync {
    let started = || {
        auth.start.as_ref().map(|start| BotStartedAuthorization {
            authorization: auth.reference(),
            binding_revision: auth.intent.binding_revision,
            start: BotAudienceStart {
                commit_sequence: start.sequence,
                excluded_turn_id: start.excluded_turn_id.clone(),
            },
        })
    };
    match auth.phase {
        BotAuthorizationPhase::PendingStart => BotCurrentSync::PendingStart {
            pending: BotPendingAuthorization {
                authorization: auth.reference(),
                operation_id: auth.intent.operation_id.clone(),
                diagnostic: None,
            },
        },
        BotAuthorizationPhase::Active => started()
            .map_or(BotCurrentSync::Closed {}, |authorization| {
                BotCurrentSync::Active { authorization }
            }),
        BotAuthorizationPhase::Paused => started()
            .map_or(BotCurrentSync::Closed {}, |authorization| {
                BotCurrentSync::Paused { authorization }
            }),
        BotAuthorizationPhase::Closed => BotCurrentSync::Closed {},
    }
}

fn closed(auth: &Authorization) -> Result<BotClosedAuthorization, FeishuError> {
    let (reason, closed_at) = auth.closed.ok_or_else(unreadable)?;
    Ok(BotClosedAuthorization {
        authorization: auth.reference(),
        binding_revision: auth.intent.binding_revision,
        start: auth
            .start
            .as_ref()
            .map_or(BotClosedStart::NeverActivated {}, |s| {
                BotClosedStart::Saved {
                    start: BotAudienceStart {
                        commit_sequence: s.sequence,
                        excluded_turn_id: s.excluded_turn_id.clone(),
                    },
                }
            }),
        reason,
        closed_at,
    })
}
fn unavailable(reason: ThreadAudienceUnavailableReason) -> ThreadAudience {
    ThreadAudience::Unavailable { reason }
}
fn items_unavailable(reason: BotAudienceItemsUnavailableReason) -> BotAudienceItemsRead {
    BotAudienceItemsRead::Unavailable { reason }
}
fn excluded(reason: BotItemExclusion) -> BotItemEligibility {
    BotItemEligibility::NotAuthorized { reason }
}
pub(super) fn invalid() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Rejected,
        "invalid bot audience request",
        false,
        None,
    )
}
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct ClosedCursor {
    thread: String,
    bot: String,
    chat: String,
    highest: u64,
    before: Option<u64>,
}
