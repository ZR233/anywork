//! Intent -> first poll under admission -> drain same HTTP future -> settle original result.

use super::worker::Cycle;
use super::{attention, eligibility, projection, unavailable};
use crate::bots::protocol::cardkit::{self, FeishuCardKit, PublicationResponse};
use crate::bots::protocol::error::FeishuError;
use crate::bots::protocol::http::PostFailure;
use crate::bots::storage::publication::{
    ConfirmedDeliveryCardAttempt, DeliveryAction, DeliveryCardAdmission, DeliveryCardAttempt,
    DeliveryEntity, DeliveryIntent, DeliveryOperationIdentity, DeliveryRequestTarget,
    DeliveryResult, DeliveryText, FrozenDeliveryRequest, SettlementOutcome,
};
use std::future::{Future, poll_fn};
use std::task::Poll;
use std::time::Duration;

pub(super) struct Render<'a> {
    pub text: &'a DeliveryText,
    pub lifecycle: crate::bots::storage::card::CardLifecycle,
    pub streaming: bool,
    pub whole: bool,
}

fn freeze(
    identity: &DeliveryOperationIdentity,
    action: &DeliveryAction,
    render: &Render<'_>,
    chat: &str,
) -> Result<FrozenDeliveryRequest, FeishuError> {
    use DeliveryRequestTarget as Target;
    let host = projection::render_host(&render.text.body, render.text.integrity, render.lifecycle);
    let (target, body) = match action {
        DeliveryAction::CreateCard { text } => (
            Target::CreateCard,
            cardkit::publication_create(cardkit::publication_card_json(
                text,
                &projection::render_host(
                    text,
                    render.text.integrity,
                    crate::bots::storage::card::CardLifecycle::Streaming,
                ),
                true,
                crate::bots::storage::card::CardLifecycle::Streaming.summary(),
            )?)?,
        ),
        DeliveryAction::SendCard { card_id } => (
            Target::SendCard,
            cardkit::publication_send(chat, card_id, &identity.uuid)?,
        ),
        DeliveryAction::UpdateContent { text, .. } if render.whole => (
            Target::WholeCard,
            cardkit::publication_whole(
                cardkit::publication_card_json(
                    text,
                    &host,
                    render.streaming,
                    render.lifecycle.summary(),
                )?,
                identity.sequence,
                &identity.uuid,
            )?,
        ),
        DeliveryAction::UpdateContent { text, .. } => (
            Target::ElementContent,
            cardkit::publication_content(text, identity.sequence, &identity.uuid)?,
        ),
        DeliveryAction::UpdateSettings {
            streaming,
            lifecycle,
            ..
        } => (
            Target::Settings,
            cardkit::publication_settings(
                *streaming,
                lifecycle.summary(),
                identity.sequence,
                &identity.uuid,
            )?,
        ),
    };
    FrozenDeliveryRequest::new(target, body)
}

pub(super) async fn perform(
    cycle: &Cycle<'_>,
    entity: &DeliveryEntity,
    action: DeliveryAction,
    render: Render<'_>,
) -> Result<(), FeishuError> {
    cycle.active()?;
    eligibility::guard(cycle.runtime, cycle.managed, cycle.scope, cycle.token).await?;
    let token = cycle
        .runtime
        .publication_token(cycle.managed, &cycle.scope.app_id)
        .await?;
    // Local validation/preparation, token acquisition and rate waiting are outside admission.
    // Identity allocation itself belongs to the Intent transaction; exact bytes are checked again
    // in its synchronous callback and substituted into the prepared request without serialization.
    let preflight = freeze(
        &DeliveryOperationIdentity {
            operation_id: String::new(),
            sequence: i32::MAX,
            uuid: "u".repeat(32),
        },
        &action,
        &render,
        &cycle.scope.chat_id,
    )?;
    let cardkit = FeishuCardKit::new(cycle.runtime.inner.http.clone());
    let mut prepared =
        cardkit.prepare_publication(&token, &cycle.scope.chat_id, action.card_id(), &preflight)?;
    let permit = tokio::select! {
        _ = cycle.cancel.cancelled() => return Err(FeishuError::cancelled()),
        permit = cycle.managed.send_rate.acquire() => permit,
    };
    cycle.active()?;
    let admission = cycle.managed.admission.lock().await;
    cycle.active()?;
    eligibility::guard(cycle.runtime, cycle.managed, cycle.scope, cycle.token).await?;
    let registered = cycle
        .managed
        .store
        .register_delivery_card_intent(
            cycle.token,
            &entity.entity,
            entity.ledger_version,
            action.clone(),
            |identity, action| freeze(identity, action, &render, &cycle.scope.chat_id),
        )
        .await;
    let mut attempt: ConfirmedDeliveryCardAttempt = match registered {
        Ok(DeliveryCardAdmission::Confirmed(attempt)) => attempt,
        Ok(DeliveryCardAdmission::Unconfirmed { mut attempt, error }) => {
            // This exact new attempt is known not to have reached HTTP. First try the short
            // local correction under admission, then release it before any persistence retry.
            let retired = cycle
                .managed
                .store
                .retire_unstarted_delivery_card(&mut attempt)
                .await;
            drop(admission);
            drop(permit);
            finish_unstarted_retirement(cycle, &mut attempt, retired).await?;
            return Err(error);
        }
        Ok(DeliveryCardAdmission::Existing) => {
            drop(admission);
            // A recovered Intent is only a fact, never a replacement for this process's cap.
            // The original owner settles it, or the existing orphan path preserves Unknown
            // after its lease is gone. Neither this branch nor a retry can start it directly.
            return Err(unavailable(
                "existing card Intent has no start capability; original-owner or orphan recovery is required",
            ));
        }
        Err(error) => {
            drop(admission);
            // Pre-commit errors carry no attempt. Do not scan for another same-owner Intent
            // and substitute its identity or manufacture a result for it.
            return Err(error);
        }
    };
    // This copy carries result/request identity only. The unique start/retirement capability
    // remains in `attempt`; it cannot be reconstructed from this clone or any stored Intent.
    let intent = attempt.intent().clone();
    let ready = async {
        cycle.active()?;
        eligibility::guard(cycle.runtime, cycle.managed, cycle.scope, cycle.token).await?;
        cycle.renew().await?;
        let current = cycle
            .managed
            .store
            .delivery_entity(&cycle.scope.key, &entity.entity)
            .await?
            .ok_or_else(|| attention("publication entity disappeared after Intent"))?;
        let expected_version = entity
            .ledger_version
            .checked_add(1)
            .ok_or_else(|| attention("publication Intent ledger version overflow"))?;
        if current.state.in_flight.as_ref() != Some(&intent)
            || current.ledger_version != expected_version
        {
            return Err(attention(
                "publication Intent identity/version changed before first HTTP poll",
            ));
        }
        cycle.active()?;
        cycle.runtime.reject_closed_admission(cycle.managed)?;
        prepared.bind_frozen(&intent.request)?;
        Ok::<_, FeishuError>(())
    }
    .await;
    if let Err(error) = ready {
        let mut retirement = attempt.into_retirement();
        let retired = cycle
            .managed
            .store
            .retire_unstarted_delivery_card(&mut retirement)
            .await;
        drop(admission);
        drop(permit);
        finish_unstarted_retirement(cycle, &mut retirement, retired).await?;
        return Err(error);
    }
    let http = cardkit.execute_publication(prepared, intent.request.target());
    tokio::pin!(http);
    permit.start();
    attempt.mark_request_started();
    // The guard cannot be released between durable Intent and the *first poll* of this very
    // future. No await/request reconstruction separates the cap's start mark from this poll.
    // Close shares admission, so it can only order before Intent or after request start.
    let immediate = poll_fn(|cx| {
        Poll::Ready(match http.as_mut().poll(cx) {
            Poll::Ready(result) => Some(result),
            Poll::Pending => None,
        })
    })
    .await;
    drop(admission);
    let response = match immediate {
        Some(response) => response,
        None => http.await,
    };
    let result = match response {
        Ok(PublicationResponse::Created(card_id)) => DeliveryResult::Created { card_id },
        Ok(PublicationResponse::Sent(message_id)) => DeliveryResult::Sent {
            card_id: intent
                .action
                .card_id()
                .ok_or_else(|| attention("sent card lacks original identity"))?
                .to_owned(),
            message_id,
        },
        Ok(PublicationResponse::Updated) => match &intent.action {
            DeliveryAction::UpdateContent { card_id, .. } => DeliveryResult::ContentAccepted {
                card_id: card_id.clone(),
            },
            DeliveryAction::UpdateSettings {
                card_id, streaming, ..
            } => DeliveryResult::SettingsAccepted {
                card_id: card_id.clone(),
                streaming: *streaming,
            },
            _ => DeliveryResult::Unknown {
                diagnostic: Some("response kind mismatches original frozen action".to_owned()),
            },
        },
        Err(PostFailure::Rejected(error)) => DeliveryResult::Rejected {
            diagnostic: error.to_string(),
        },
        Err(PostFailure::Unknown(error)) => DeliveryResult::Unknown {
            diagnostic: Some(error.to_string()),
        },
    };
    // No cancellation or lease condition here: the original owner retains Intent+Result until
    // the result's durable confirmation. Nothing in this loop can resend HTTP.
    settle(cycle, entity, &intent, result).await
}

async fn finish_unstarted_retirement(
    cycle: &Cycle<'_>,
    attempt: &mut DeliveryCardAttempt,
    mut retired: Result<SettlementOutcome, FeishuError>,
) -> Result<(), FeishuError> {
    // The first attempt was already made under admission. No admission guard reaches this
    // loop: shutdown/control may proceed while the same cap retains only local save/readback
    // responsibility. Cancellation/expiry cannot turn an uncertain local commit into success.
    loop {
        match retired {
            Ok(SettlementOutcome::Applied | SettlementOutcome::AlreadySettled) => {
                cycle.changed();
                return Ok(());
            }
            Ok(SettlementOutcome::Superseded) => return Err(FeishuError::cancelled()),
            Err(error) => {
                cycle.diagnostic(error).await;
                tokio::time::sleep(Duration::from_secs(1)).await;
            }
        }
        retired = cycle
            .managed
            .store
            .retire_unstarted_delivery_card(attempt)
            .await;
    }
}

async fn settle(
    cycle: &Cycle<'_>,
    entity: &DeliveryEntity,
    intent: &DeliveryIntent,
    result: DeliveryResult,
) -> Result<(), FeishuError> {
    loop {
        match cycle
            .managed
            .store
            .settle_delivery_card_result(
                &cycle.scope.key,
                &entity.entity,
                &intent.operation_id,
                result.clone(),
            )
            .await
        {
            Ok(SettlementOutcome::Applied | SettlementOutcome::AlreadySettled) => {
                cycle.changed();
                return Ok(());
            }
            Ok(SettlementOutcome::Superseded) => {
                cycle.diagnostic(attention(
                    "started card result conflicts with a successor; original owner retains its result for local recovery without HTTP replay",
                )).await;
                tokio::time::sleep(Duration::from_secs(1)).await;
            }
            Err(_) => {
                // A known stronger result must not be overwritten by a weak Unknown after an
                // uncertain local commit. Readback proves that this operation is already durable.
                if let Ok(Some(current)) = cycle
                    .managed
                    .store
                    .delivery_entity(&cycle.scope.key, &entity.entity)
                    .await
                    && current.state.settled.as_ref().is_some_and(|saved| {
                        saved.intent.operation_id == intent.operation_id
                            && confirms_platform_result(&saved.result, &result)
                    })
                {
                    cycle.changed();
                    return Ok(());
                }
                cycle.diagnostic(unavailable("started card result persistence is unconfirmed; original owner will retry local settlement without HTTP replay")).await;
                tokio::time::sleep(Duration::from_secs(1)).await;
            }
        }
    }
}

fn confirms_platform_result(saved: &DeliveryResult, result: &DeliveryResult) -> bool {
    match saved {
        // A local retirement is not a stronger platform response to a started request.
        DeliveryResult::NotStarted => false,
        DeliveryResult::Unknown { .. } => saved == result,
        DeliveryResult::Created { .. }
        | DeliveryResult::Sent { .. }
        | DeliveryResult::ContentAccepted { .. }
        | DeliveryResult::SettingsAccepted { .. }
        | DeliveryResult::Rejected { .. } => {
            saved == result || matches!(result, DeliveryResult::Unknown { .. })
        }
    }
}
