//! 只沿冻结创建身份接续原绑定；创建冲突交给入站 finisher 原子收束。

use super::error::{attention, failure, history, retry};
use super::owner::{IngressControl, IngressRun};
use crate::bots::InboundWorkOutcome;
use crate::bots::creation::{self, CreatedThreadState, CreationFailure, TargetProject};
use crate::bots::owner::{BotRuntime, ManagedBot};
use crate::bots::storage::publication::{DeliveryScopeKey, DeliveryScopeOrigin};
use crate::bots::storage::target::{TargetClaim, TargetKind};
use crate::bots::storage::{BindingProjection, FrozenInbound, ThreadBindingClaim};
use crate::studio::{StudioRuntime, ThreadVisibility};
use std::sync::Arc;

impl BotRuntime {
    /// Locate an ORIGINAL Thread before applying new-action gates. A replaced route must not
    /// hide a durable accepted input, nor may the successor receive the predecessor's input.
    pub(super) async fn known_inbound_thread(
        &self,
        managed: &ManagedBot,
        runtime: &StudioRuntime,
        run: &IngressRun,
    ) -> Result<Option<String>, InboundWorkOutcome> {
        let inbound = &run.inbound;
        let route = managed
            .store
            .binding_for_chat(&inbound.chat_id, &inbound.bot_id, &inbound.project_id)
            .await
            .map_err(|error| failure("original inbound binding read failed", error))?;
        if original_route(&route, inbound) && route.status == "bound" {
            return route
                .thread_id
                .map(Some)
                .ok_or_else(|| attention("bound input route lacks a Thread identity"));
        }
        let key = DeliveryScopeKey::LegacyFinal {
            inbound_identity: inbound_identity(inbound),
        };
        if let Some(scope) = managed
            .store
            .delivery_scope(&key)
            .await
            .map_err(|error| failure("legacy input origin read failed", error))?
        {
            if scope.bot_id != inbound.bot_id
                || scope.chat_id != inbound.chat_id
                || scope.app_id != inbound.app_id
                || scope.project_id != inbound.project_id
                || scope.creation_id != inbound.creation_id
                || scope.binding_revision != inbound.binding_revision
            {
                return Err(attention(
                    "legacy input scope conflicts with frozen inbound identity",
                ));
            }
            if !scope.thread_id.is_empty() {
                let DeliveryScopeOrigin::LegacyFinal { legacy } = &scope.origin else {
                    return Err(attention("original inbound lookup has a non-legacy scope"));
                };
                if scope.needs_recovery
                    || legacy.needs_recovery.is_some()
                    || legacy.inbound_identity != inbound_identity(inbound)
                    || legacy.original_input_id != run.input_id
                    || legacy.source.as_ref() != Some(&run.source(&scope.thread_id))
                {
                    return Err(attention(
                        "original legacy Thread provenance requires local recovery",
                    ));
                }
                super::admission::check_target(&legacy.target, inbound)?;
                return Ok(Some(scope.thread_id));
            }
        }
        // Current factories use creation_id as the actual Thread id. Do not guess that equality:
        // require both the real directory record and its immutable creation origin before reading.
        let existing = runtime
            .find_owned_thread(&inbound.creation_id)
            .await
            .map_err(|error| history("original creation Thread lookup failed", error))?;
        if let Some(existing) = existing {
            let scope = managed
                .store
                .audience_scope(&existing.id, &inbound.bot_id)
                .await
                .map_err(|error| failure("original Thread provenance read failed", error))?;
            if scope.is_some_and(|scope| {
                scope.origin.chat_id == inbound.chat_id
                    && scope.origin.project_id == inbound.project_id
                    && scope.origin.creation_id == inbound.creation_id
                    && scope.origin.binding_revision == inbound.binding_revision
            }) {
                return Ok(Some(existing.id));
            }
            if original_route(&route, inbound)
                && route.status == "creating"
                && existing.project_id == inbound.project_id
            {
                // Creation completed but binding has not: this exact route is still the owner.
                return Ok(Some(existing.id));
            }
        }
        Ok(None)
    }

    pub(super) async fn resolve_inbound_thread(
        &self,
        managed: &Arc<ManagedBot>,
        runtime: &StudioRuntime,
        run: &IngressRun,
        control: &IngressControl,
    ) -> Result<String, InboundWorkOutcome> {
        let inbound = &run.inbound;
        let target = inbound_target(inbound)?;
        // The frozen work already owns a route. Never create a missing/replaced route here.
        let claim = {
            let _admission = managed.admission.lock().await;
            self.hold_inbound_claim(managed, run, control).await?;
            self.reject_closed_admission(managed)
                .map_err(|error| failure("bot input binding admission is closed", error))?;
            self.current_inbound_permission(managed, inbound, &target)
                .await?;
            let route = managed
                .store
                .binding_for_chat(&inbound.chat_id, &inbound.bot_id, &inbound.project_id)
                .await
                .map_err(|error| failure("inbound binding read failed", error))?;
            if !original_route(&route, inbound)
                || !matches!(route.status.as_str(), "bound" | "creating")
            {
                return Err(attention(
                    "inbound no longer owns its original conversation route",
                ));
            }
            let draft = TargetClaim::from_inbound(
                &inbound.bot_id,
                &inbound.app_id,
                &inbound.project_id,
                &inbound.chat_id,
                &inbound.creation_id,
                &inbound.message_id,
                target.clone(),
            );
            managed
                .store
                .claim_thread_binding(&draft)
                .await
                .map_err(|error| failure("inbound binding claim failed", error))?
        };
        let thread_id = match claim {
            ThreadBindingClaim::Bound { thread_id } => thread_id,
            ThreadBindingClaim::NeedsAttention { diagnostic } => return Err(attention(diagnostic)),
            ThreadBindingClaim::Creating { creation_id } => {
                if creation_id != inbound.creation_id {
                    return Err(attention(
                        "creation claim differs from frozen inbound identity",
                    ));
                }
                if let Some(outcome) = control.stopped(self) {
                    return Err(outcome);
                }
                let title = {
                    let config = managed.config.lock().await;
                    format!("{} / {}", config.name, inbound.chat_id)
                };
                // No DB/admission lock across Thread creation, and no cancellation select drops
                // an already-started factory call. Its result remains owned by this managed run.
                let created = match runtime
                    .create_thread_with_id(creation_id.clone(), &inbound.project_id, &title)
                    .await
                {
                    Ok(created) => created,
                    Err(error) => return Err(creation_failure(runtime, inbound, error).await),
                };
                let bound = {
                    let _admission = managed.admission.lock().await;
                    self.hold_inbound_claim(managed, run, control).await?;
                    self.reject_closed_admission(managed).map_err(|error| {
                        failure("bot admission closed before first authorization", error)
                    })?;
                    self.current_inbound_permission(managed, inbound, &target)
                        .await?;
                    let route = managed
                        .store
                        .binding_for_chat(&inbound.chat_id, &inbound.bot_id, &inbound.project_id)
                        .await
                        .map_err(|error| failure("created inbound route read failed", error))?;
                    if !original_route(&route, inbound)
                        || !matches!(route.status.as_str(), "bound" | "creating")
                    {
                        return Err(attention(
                            "created inbound Thread no longer owns the frozen binding revision",
                        ));
                    }
                    // Read current config AFTER creation, in the same short admission boundary
                    // as binding. first_pending_start in bind_thread refuses ANY existing head.
                    let first = {
                        let current = managed.config.lock().await;
                        crate::bots::audience::first_start(
                            &current,
                            &inbound.bot_id,
                            &inbound.chat_id,
                            &inbound.app_id,
                            &inbound.project_id,
                            &target,
                        )
                    };
                    let bound = managed
                        .store
                        .bind_thread(
                            &inbound.chat_id,
                            &created.id,
                            &creation_id,
                            &inbound.project_id,
                            first.as_ref(),
                        )
                        .await
                        .map_err(|error| {
                            failure("inbound Thread binding persistence failed", error)
                        })?;
                    managed.audience_changed();
                    bound
                };
                // Wake only the original prepare owner; it obtains and saves the first cut.
                self.inner.audience_prepare_notify.notify_one();
                bound
            }
        };
        let projection = managed
            .store
            .binding_for_chat(&inbound.chat_id, &inbound.bot_id, &inbound.project_id)
            .await
            .map_err(|error| failure("bound inbound route read failed", error))?;
        if !original_route(&projection, inbound)
            || projection.status != "bound"
            || projection.thread_id.as_deref() != Some(&thread_id)
        {
            return Err(attention(
                "inbound was admitted against a previous conversation binding",
            ));
        }
        let unavailable = match runtime.find_owned_thread(&thread_id).await {
            Ok(Some(thread)) if thread.project_id != inbound.project_id => {
                Some("bound Thread belongs to another project")
            }
            Ok(Some(thread)) if thread.visibility != ThreadVisibility::Active => {
                Some("bound Thread is archived")
            }
            Ok(None) => Some("bound Thread is missing"),
            Ok(Some(_)) => None,
            Err(error) => return Err(history("bound inbound Thread lookup failed", error)),
        };
        if let Some(diagnostic) = unavailable {
            self.hold_inbound_claim(managed, run, control).await?;
            self.mark_binding_unavailable(managed.clone(), projection, diagnostic)
                .await
                .map_err(|error| {
                    failure("bound inbound unavailability persistence failed", error)
                })?;
            return Err(attention(diagnostic));
        }
        Ok(thread_id)
    }
}

pub(super) fn inbound_identity(inbound: &FrozenInbound) -> String {
    format!(
        "{}:{}:{}",
        inbound.bot_id, inbound.chat_id, inbound.message_id
    )
}

pub(super) fn original_route(route: &BindingProjection, inbound: &FrozenInbound) -> bool {
    route.chat_id == inbound.chat_id
        && route.project_id == inbound.project_id
        && !inbound.creation_id.is_empty()
        && route.creation_id == inbound.creation_id
        && inbound.binding_revision != 0
        && route.revision == inbound.binding_revision
}

pub(super) fn inbound_target(inbound: &FrozenInbound) -> Result<TargetKind, InboundWorkOutcome> {
    match inbound.chat_kind.as_str() {
        "direct" if !inbound.open_id.is_empty() => Ok(TargetKind::Direct {
            open_id: inbound.open_id.clone(),
        }),
        "group" => Ok(TargetKind::Group),
        _ => Err(attention("bot inbound chat target kind is unproven")),
    }
}

async fn creation_failure(
    runtime: &StudioRuntime,
    inbound: &FrozenInbound,
    _error: anyhow::Error,
) -> InboundWorkOutcome {
    let thread = match runtime.find_owned_thread(&inbound.creation_id).await {
        Ok(thread) => creation::created_thread_state(thread.as_ref(), &inbound.project_id),
        // Lack of current evidence cannot prove a conflict or prove that no creation happened.
        Err(_) => CreatedThreadState::Absent,
    };
    let project = match runtime.list_projects().await {
        Ok(projects) => creation::target_project_state(&projects, &inbound.project_id),
        Err(_) => TargetProject::Present,
    };
    match creation::classify_creation_failure(project, thread) {
        CreationFailure::IdentityConflict => InboundWorkOutcome::CreationConflict {
            diagnostic: "conversation Thread creation identity cannot be bound".to_string(),
        },
        CreationFailure::Retryable => {
            retry("bot Thread creation did not complete; original creation identity retained")
        }
    }
}
