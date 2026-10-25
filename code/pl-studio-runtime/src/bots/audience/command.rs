//! Managed local commands. Durable preparation and exact cut recovery outlive the caller's wait.

use crate::bots::BotRuntime;
use crate::bots::owner::ManagedBot;
use crate::bots::protocol::error::{FeishuError, FeishuErrorKind};
use crate::studio::thread_audience::VerifiedBotAudienceOwner;
use pl_protocol::studio::*;
use std::sync::Arc;

impl BotRuntime {
    pub(in crate::bots) async fn mark_binding_unavailable(
        &self,
        managed: Arc<ManagedBot>,
        projection: crate::bots::storage::BindingProjection,
        diagnostic: &'static str,
    ) -> Result<bool, FeishuError> {
        let expected = crate::bots::storage::BoundThreadExpectation {
            chat_id: projection.chat_id,
            thread_id: projection.thread_id.ok_or_else(unavailable)?,
            creation_id: projection.creation_id,
            project_id: projection.project_id,
            revision: projection.revision,
        };
        let bytes = crate::bots::occupancy::counted_text_bytes([
            (expected.chat_id.as_str(), 4),
            (expected.thread_id.as_str(), 4),
            (expected.creation_id.as_str(), 4),
            (expected.project_id.as_str(), 4),
            (diagnostic, 2),
        ])?;
        self.submit_occupancy(bytes, move |_budget| async move {
            let _admission = managed.admission.lock().await;
            // This is a local fail-close, not new external work. Once registered it must finish
            // even if the original reply waiter is cancelled or shutdown seals new admission.
            let changed = managed
                .store
                .mark_binding_attention(&expected, diagnostic)
                .await?;
            if changed {
                managed.audience_changed();
            }
            Ok(changed)
        })
        .await
    }
    /// Before regranting config trust, finish closures required by the previous determined config.
    /// Each page has its own short admission/transaction; no socket or Thread gate is held here.
    pub(in crate::bots) async fn prune_audience_authorizations(
        &self,
        managed: &Arc<ManagedBot>,
        config: &crate::bots::config::BotConfigFile,
    ) -> Result<(), FeishuError> {
        let mut after = (String::new(), 0);
        loop {
            let (changed, next) = {
                let _admission = managed.admission.lock().await;
                managed
                    .store
                    .prune_authorization_page(config, (&after.0, after.1))
                    .await?
            };
            if changed {
                managed.audience_changed();
            }
            match next {
                Some(next) => after = next,
                None => return Ok(()),
            }
        }
    }
    pub(crate) async fn change_thread_sync(
        &self,
        owner: &VerifiedBotAudienceOwner,
        request: ChangeBotThreadSyncRequest,
        owner_epoch: &str,
    ) -> Result<ChangeBotThreadSyncReply, FeishuError> {
        // The Studio adapter validates the global operation grammar. This private bot entry
        // additionally rejects an absent identity before registering any work.
        if request.operation_id.is_empty() {
            return Err(super::read::invalid());
        }
        // This explicit command, not a read or a cancellable receipt waiter, ensures the durable
        // recovery driver exists before any preparation can be committed.
        self.ensure_inbound_recovery().await?;
        let bytes = serde_json::to_vec(&request)
            .map_err(|_| super::read::invalid())?
            .len();
        let frozen = crate::bots::occupancy::counted_extra_bytes(
            0,
            [
                (bytes, 8),
                (owner.bot_id().len(), 3),
                (owner_epoch.len(), 2),
            ],
        )?;
        let runtime = self.clone();
        let bot = owner.bot_id().to_owned();
        let epoch = owner_epoch.to_owned();
        self.submit_occupancy(frozen, move |mut budget| async move {
            let managed = runtime.managed(&bot).await?;
            let Some(host) = runtime.studio_host() else {
                return Err(unavailable());
            };
            // Frozen privacy is authoritative. This read cannot upgrade the saved instructions.
            if request.action == BotThreadSyncAction::Enable
                && !host
                    .bot_thread_supports_public_frontend(&request.thread_id)
                    .await
                    .map_err(|e| FeishuError::history_read("frozen bot frontend unavailable", e))?
            {
                return Err(permission());
            }
            let scope = managed
                .store
                .audience_scope(&request.thread_id, &bot)
                .await?
                .ok_or_else(permission)?;
            let config = managed.config.lock().await;
            let fields = [
                config.id.as_str(),
                config.name.as_str(),
                config.project_id.as_str(),
                config.feishu().app_id.as_str(),
                scope.origin.chat_id.as_str(),
                scope.origin.creation_id.as_str(),
            ];
            budget.reserve_more(crate::bots::occupancy::counted_text_bytes(
                fields.into_iter().map(|s| (s, 8)),
            )?)?;
            drop(config);
            if request.action != BotThreadSyncAction::Close {
                runtime
                    .check_audience_permission(&managed, &scope.origin.chat_id)
                    .await?;
            }
            let change = {
                let _admission = managed.admission.lock().await;
                runtime.reject_closed_admission(&managed)?;
                let config = managed.config.lock().await.clone();
                if request.action != BotThreadSyncAction::Close && !config.enabled {
                    return Err(permission());
                }
                managed.store.change_sync(&request, &config).await?
            };
            if change.changed {
                managed.audience_changed();
            }
            let auth = change.authorization;
            let auth = if auth.phase == BotAuthorizationPhase::PendingStart {
                // The transaction owns acceptance. Wake the existing recovery driver; never
                // register a child with the occupancy registry that may be joining this task.
                runtime.inner.audience_prepare_notify.notify_one();
                managed
                    .store
                    .audience_authorization(&auth.intent.authorization)
                    .await?
                    .ok_or_else(unavailable)?
            } else {
                auth
            };
            let state = if request.action == BotThreadSyncAction::Enable
                && auth.phase == BotAuthorizationPhase::Closed
            {
                BotThreadSyncCommandState::Superseded {
                    authorization: auth.intent.authorization.clone(),
                }
            } else if auth.phase == BotAuthorizationPhase::PendingStart {
                BotThreadSyncCommandState::PendingStart {
                    authorization: auth.intent.authorization.clone(),
                }
            } else {
                BotThreadSyncCommandState::Settled {}
            };
            let effective = matches!(state, BotThreadSyncCommandState::Settled {});
            let audience = runtime.audience_view(&managed, &request.thread_id).await?;
            Ok(ChangeBotThreadSyncReply {
                thread_id: request.thread_id,
                audience,
                state,
                receipt: StudioCommandReceipt {
                    operation_id: request.operation_id,
                    disposition: if change.changed {
                        CommandDisposition::Applied
                    } else {
                        CommandDisposition::NoChange
                    },
                    targets: vec![ResourceStamp {
                        resource_key: format!(
                            "bot-audience:{}:{}",
                            auth.intent.thread_id, auth.intent.authorization.generation
                        ),
                        owner_epoch: epoch,
                        revision: auth.revision,
                    }],
                    effect: if effective {
                        CommandEffectPoint::Immediate
                    } else {
                        CommandEffectPoint::NextTurn
                    },
                    effective,
                    durable: true,
                    requires_identity_observation: !effective,
                },
            })
        })
        .await
    }

    pub(in crate::bots) async fn check_audience_permission(
        &self,
        managed: &ManagedBot,
        chat: &str,
    ) -> Result<(), FeishuError> {
        let (kind, user) = managed.store.audience_target(chat).await?;
        let config = managed.config.lock().await;
        let trusted = match kind {
            BotConversationKind::Direct => user
                .as_ref()
                .is_some_and(|id| config.feishu().trusted_open_ids.contains(id)),
            BotConversationKind::Group => config.feishu().trusted_chat_ids.contains(chat),
        };
        if !config.enabled || !trusted {
            return Err(permission());
        }
        Ok(())
    }
}

pub(super) fn permission() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Permission,
        "bot audience is not currently authorized",
        false,
        None,
    )
}
pub(super) fn unavailable() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        "bot audience owner is unavailable",
        true,
        None,
    )
}
