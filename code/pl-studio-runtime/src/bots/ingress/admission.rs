//! 本机 readiness、当前平台输入权限与原有限入站资格各自独立，不互相授予权限。

use super::binding::{inbound_identity, inbound_target, original_route};
use super::error::{attention, failure};
use super::owner::{IngressControl, IngressRun};
use crate::bots::InboundWorkOutcome;
use crate::bots::owner::{BotRuntime, ManagedBot};
use crate::bots::storage::FrozenInbound;
use crate::bots::storage::audience::AudienceScope;
use crate::bots::storage::publication::{DeliveryScopeKey, DeliveryScopeOrigin};
use crate::bots::storage::target::{TargetKind, TargetProof};
use crate::studio::thread_audience::BotThreadInputReadiness;
use pl_protocol::studio::BotAuthorizationPhase;

impl BotRuntime {
    pub(super) async fn current_inbound_permission(
        &self,
        managed: &ManagedBot,
        inbound: &FrozenInbound,
        target: &TargetKind,
    ) -> Result<(), InboundWorkOutcome> {
        let current = managed.config.lock().await;
        // Reuse the same current enabled/app/project/trust predicate as first binding and prepare.
        if crate::bots::audience::first_start(
            &current,
            &inbound.bot_id,
            &inbound.chat_id,
            &inbound.app_id,
            &inbound.project_id,
            target,
        )
        .is_none()
        {
            return Err(attention(
                "current bot config or trust does not permit the frozen inbound",
            ));
        }
        Ok(())
    }

    pub(super) async fn admit_inbound_input(
        &self,
        managed: &ManagedBot,
        run: &IngressRun,
        control: &IngressControl,
    ) -> Result<(), InboundWorkOutcome> {
        let Some(thread) = &run.thread_id else {
            return Err(attention("input admission has no original Thread"));
        };
        let inbound = &run.inbound;
        let _admission = managed.admission.lock().await;
        self.hold_inbound_claim(managed, run, control).await?;
        self.reject_closed_admission(managed)
            .map_err(|error| failure("platform input admission is closed", error))?;
        self.current_inbound_permission(managed, inbound, &inbound_target(inbound)?)
            .await?;
        match managed
            .store
            .thread_input_readiness(&inbound.bot_id, thread, &inbound.project_id)
            .await
        {
            Ok(BotThreadInputReadiness::Ready) => {}
            Ok(BotThreadInputReadiness::Preparing) => return Err(preparing()),
            Err(error) => return Err(failure("bot local input readiness is unreadable", error)),
        }
        let Some(scope) = managed
            .store
            .audience_scope(thread, &inbound.bot_id)
            .await
            .map_err(|error| failure("platform input audience read failed", error))?
        else {
            return Err(attention("platform input lacks proven creation provenance"));
        };
        self.check_inbound_scope(run, &scope)?;
        if let Some(auth) = &scope.head {
            // A head on another Thread (including a closed predecessor after Replace) is not
            // this binding's permission. Only explicit Enable can establish the successor cut.
            if auth.intent.thread_id != *thread
                || auth.intent.authorization.bot_id != inbound.bot_id
                || auth.intent.authorization.chat_id != inbound.chat_id
                || auth.app_id != inbound.app_id
                || auth.project_id != inbound.project_id
                || auth.creation_id != inbound.creation_id
                || auth.intent.binding_revision != inbound.binding_revision
            {
                return Err(attention(
                    "platform input audience belongs to another binding",
                ));
            }
            match auth.phase {
                BotAuthorizationPhase::Active | BotAuthorizationPhase::Paused => {
                    let Some(start) = &auth.start else {
                        return Err(attention(
                            "platform input audience has no saved starting cut",
                        ));
                    };
                    if start.intent != auth.intent
                        || start.version != 1
                        || start.sequence == 0
                        || start.extension_revision == 0
                    {
                        return Err(attention(
                            "platform input saved starting cut is inconsistent",
                        ));
                    }
                    if scope.origin.requires_upgrade
                        && !self.exact_legacy_inbound(managed, run, thread).await?
                    {
                        return Err(attention(
                            "platform input on an upgrade-required Thread has no original limited obligation",
                        ));
                    }
                    // Pause is output-only; same-generation input still enters the same Thread.
                    return Ok(());
                }
                BotAuthorizationPhase::PendingStart => return Err(preparing()),
                BotAuthorizationPhase::Closed => {
                    return Err(attention("platform input audience is closed"));
                }
            }
        }
        // RequiresUpgrade does not erase a migrated, already-admitted limited input obligation.
        // It is never a blanket authorization for later messages on that old Thread.
        if scope.origin.requires_upgrade && self.exact_legacy_inbound(managed, run, thread).await? {
            return Ok(());
        }
        Err(attention(
            "platform input needs an explicit saved frontend authorization",
        ))
    }

    pub(super) fn check_inbound_scope(
        &self,
        run: &IngressRun,
        scope: &AudienceScope,
    ) -> Result<(), InboundWorkOutcome> {
        let inbound = &run.inbound;
        if !original_route(&scope.binding, inbound)
            || scope.binding.status != "bound"
            || scope.binding.thread_id.as_ref() != run.thread_id.as_ref()
            || scope.origin.thread_id != run.thread_id.as_deref().unwrap_or("")
            || scope.origin.chat_id != inbound.chat_id
            || scope.origin.project_id != inbound.project_id
            || scope.origin.creation_id != inbound.creation_id
            || scope.origin.binding_revision != inbound.binding_revision
        {
            return Err(attention(
                "platform input route or immutable origin no longer matches",
            ));
        }
        check_target(&scope.origin.target, inbound)
    }

    async fn exact_legacy_inbound(
        &self,
        managed: &ManagedBot,
        run: &IngressRun,
        thread: &str,
    ) -> Result<bool, InboundWorkOutcome> {
        let inbound = &run.inbound;
        let identity = inbound_identity(inbound);
        let key = DeliveryScopeKey::LegacyFinal {
            inbound_identity: identity.clone(),
        };
        let Some(scope) = managed
            .store
            .delivery_scope(&key)
            .await
            .map_err(|error| failure("legacy inbound permission read failed", error))?
        else {
            return Ok(false);
        };
        let DeliveryScopeOrigin::LegacyFinal { legacy } = &scope.origin else {
            return Ok(false);
        };
        let complete = !scope.needs_recovery
            && legacy.needs_recovery.is_none()
            && legacy.resumable
            && scope.bot_id == inbound.bot_id
            && scope.chat_id == inbound.chat_id
            && scope.thread_id == thread
            && scope.app_id == inbound.app_id
            && scope.project_id == inbound.project_id
            && scope.creation_id == inbound.creation_id
            && scope.binding_revision == inbound.binding_revision
            && legacy.inbound_identity == identity
            && legacy.original_input_id == run.input_id
            && legacy.watch_input == run.watch_input()
            && legacy.source.as_ref() == Some(&run.source(thread))
            && legacy.admission.as_ref().is_some_and(|admission| {
                admission.content_hash == inbound.content_hash
                    && admission.admitted_at > 0
                    && matches!(admission.status.as_str(), "pending" | "claimed" | "failed")
            });
        if complete {
            check_target(&legacy.target, inbound)?;
        }
        Ok(complete)
    }
}

pub(super) fn check_target(
    target: &TargetProof,
    inbound: &FrozenInbound,
) -> Result<(), InboundWorkOutcome> {
    target
        .validate()
        .map_err(|error| failure("inbound creation target is unreadable", error))?;
    if let TargetProof::Created { evidence } = target
        && (evidence.bot_id != inbound.bot_id
            || evidence.chat_id != inbound.chat_id
            || evidence.app_id != inbound.app_id
            || evidence.project_id != inbound.project_id
            || evidence.creation_id != inbound.creation_id
            || evidence.binding_revision != inbound.binding_revision)
    {
        return Err(attention(
            "inbound creation target belongs to another route",
        ));
    }
    if target.kind() != Some(&inbound_target(inbound)?) {
        return Err(attention(
            "inbound target kind or direct peer is not proven",
        ));
    }
    Ok(())
}

fn preparing() -> InboundWorkOutcome {
    InboundWorkOutcome::Deferred {
        diagnostic: "bot conversation is preparing its saved input starting cut; no new attachment preparation or input submission was started".to_string(),
    }
}
