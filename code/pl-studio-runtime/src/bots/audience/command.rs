//! Managed local commands. Durable preparation and exact cut recovery outlive the caller's wait.

use crate::bots::BotRuntime;
use crate::bots::owner::ManagedBot;
use crate::bots::protocol::error::{FeishuError, FeishuErrorKind};
use crate::studio::thread_audience::VerifiedBotAudienceOwner;
use pl_protocol::BotAudienceCloseReason;
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
                None => break,
            }
        }
        // 旧有限回复可能没有任何授权头，不能只遍历 bot_authorizations 后就重新授信。
        // 每页仍在原短准入边界内收束；真实平台结果不受这些新写围栏影响。
        let mut after = None;
        loop {
            let (changed, next) = {
                let _admission = managed.admission.lock().await;
                managed
                    .store
                    .prune_legacy_delivery_page(config, after.as_deref())
                    .await?
            };
            if changed {
                managed.audience_changed();
            }
            match next {
                Some(next) => after = Some(next),
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

/// The automatic first authorization exists only under the *current* permission facts, and
/// it is decided from the target the caller already verified and froze — never from ledger
/// rows. A brand-new group has no `inbound_work` row at all, so inferring the kind from the
/// ledger would refuse a legitimately permitted first binding.
pub(in crate::bots) fn first_start(
    config: &crate::bots::config::BotConfigFile,
    bot_id: &str,
    chat_id: &str,
    app_id: &str,
    project_id: &str,
    target: &crate::bots::storage::target::TargetKind,
) -> Option<crate::bots::storage::FirstStart> {
    first_start_allowed(config, bot_id, chat_id, app_id, project_id, target).then(|| {
        crate::bots::storage::FirstStart {
            bot_id: bot_id.to_string(),
            app_id: app_id.to_string(),
            operation_id: first_start_operation(bot_id, chat_id),
        }
    })
}

/// The one permission predicate shared by the first-binding gate and the durable prepare
/// recovery: current config facts plus the typed target, never ledger inference.
pub(in crate::bots) fn first_start_allowed(
    config: &crate::bots::config::BotConfigFile,
    bot_id: &str,
    chat_id: &str,
    app_id: &str,
    project_id: &str,
    target: &crate::bots::storage::target::TargetKind,
) -> bool {
    if !config.enabled
        || config.id != bot_id
        || config.project_id != project_id
        || config.feishu().app_id != app_id
    {
        return false;
    }
    match target {
        crate::bots::storage::target::TargetKind::Group => {
            config.feishu().trusted_chat_ids.contains(chat_id)
        }
        // Unknown direct peer identity is never trusted by inference.
        crate::bots::storage::target::TargetKind::Direct { open_id } => {
            !open_id.is_empty() && config.feishu().trusted_open_ids.contains(open_id)
        }
    }
}

/// Durable-prepare recheck. It accepts only a provable current binding whose route, frozen
/// proof and pending authorization agree field by field; anything else is a real
/// inconsistency (fail-closed, pending retained) rather than a permission fact to close.
/// Only an explicitly persisted `Legacy`/`Unproven` proof keeps the old ledger judgement.
pub(in crate::bots) async fn prepare_permission(
    store: &crate::bots::storage::BotStateStore,
    config: &crate::bots::config::BotConfigFile,
    auth: &crate::bots::storage::audience::Authorization,
) -> Result<(), FeishuError> {
    let bot = auth.intent.authorization.bot_id.as_str();
    let chat = auth.intent.authorization.chat_id.as_str();
    let thread = auth.intent.thread_id.as_str();
    // 没有可证明的当前绑定（缺失行 / 不一致）时不得回退账本推断。
    let Some(scope) = store.audience_scope(thread, bot).await? else {
        return Err(crate::bots::storage::audience::unreadable());
    };
    // route 与 origin 必须同时等于本次 pending auth 的身份。
    if scope.binding.thread_id.as_deref() != Some(thread)
        || scope.binding.status != "bound"
        || scope.binding.creation_id != auth.creation_id
        || scope.binding.project_id != auth.project_id
        || scope.binding.revision != auth.intent.binding_revision
        || scope.origin.chat_id != chat
        || scope.origin.project_id != auth.project_id
        || scope.origin.creation_id != auth.creation_id
        || scope.origin.binding_revision != auth.intent.binding_revision
    {
        return Err(crate::bots::storage::audience::unreadable());
    }
    match &scope.origin.target {
        // 当前创建意图：证明内的全部身份必须逐字段等于本次 pending auth。
        crate::bots::storage::target::TargetProof::Created { evidence } => {
            if evidence.bot_id != bot
                || evidence.app_id != auth.app_id
                || evidence.project_id != auth.project_id
                || evidence.chat_id != chat
                || evidence.creation_id != auth.creation_id
                || evidence.binding_revision != auth.intent.binding_revision
            {
                return Err(crate::bots::storage::audience::unreadable());
            }
            if first_start_allowed(
                config,
                bot,
                chat,
                &auth.app_id,
                &auth.project_id,
                &evidence.target,
            ) {
                Ok(())
            } else {
                Err(permission())
            }
        }
        // 只有显式持久化的旧证明才允许沿用既有账本判定（不改旧行语义）。
        crate::bots::storage::target::TargetProof::Legacy { .. }
        | crate::bots::storage::target::TargetProof::Unproven => {
            check_audience_permission_for(store, config, chat).await
        }
    }
}

/// Ledger fallback used **only** for non-current proofs. It keeps the pre-existing judgement
/// of a migrated/legacy row unchanged instead of silently re-classifying it.
async fn check_audience_permission_for(
    store: &crate::bots::storage::BotStateStore,
    config: &crate::bots::config::BotConfigFile,
    chat: &str,
) -> Result<(), FeishuError> {
    let (kind, user) = store.audience_target(chat).await?;
    let trusted = match kind {
        pl_protocol::studio::BotConversationKind::Direct => user
            .as_ref()
            .is_some_and(|id| config.feishu().trusted_open_ids.contains(id)),
        pl_protocol::studio::BotConversationKind::Group => {
            config.feishu().trusted_chat_ids.contains(chat)
        }
    };
    if !config.enabled || !trusted {
        return Err(permission());
    }
    Ok(())
}

/// Stable identity of the automatic first preparation: the same chat/generation always
/// resumes the same operation, so a restart cannot establish a second cut.
pub(in crate::bots) fn first_start_operation(bot: &str, chat: &str) -> String {
    format!("botprepare:{bot}:{chat}:1")
}

/// A closed authorization records why it can no longer continue; never one fixed reason.
pub(in crate::bots) fn permission_close_reason(
    config: &crate::bots::config::BotConfigFile,
) -> BotAudienceCloseReason {
    if config.enabled {
        BotAudienceCloseReason::TrustRevoked
    } else {
        BotAudienceCloseReason::BotDisabled
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
