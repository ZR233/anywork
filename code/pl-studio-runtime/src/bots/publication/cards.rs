//! Stable per-item cards and the one migrated legacy entity share these exact action paths.

use super::worker::Cycle;
use super::{attention, operation, projection};
use crate::bots::protocol::error::FeishuError;
use crate::bots::storage::card::CardLifecycle;
use crate::bots::storage::publication::{
    DeliveryAction, DeliveryContent, DeliveryEntityKey, DeliveryText, SettlementOutcome,
};

pub(super) async fn drive(
    cycle: &Cycle<'_>,
    key: &DeliveryEntityKey,
    text: &DeliveryText,
    goal: CardLifecycle,
    final_content: bool,
) -> Result<bool, FeishuError> {
    let mut changed = false;
    // Creation, one IM send, reopen, content, close. Every stage reloads the ledger and independently
    // obtains current authorization/claim/admission; an earlier success never authorizes the next.
    for _ in 0..8 {
        cycle.active()?;
        let entity = cycle
            .managed
            .store
            .delivery_entity(&cycle.scope.key, key)
            .await?
            .ok_or_else(|| attention("publication card entity is missing"))?;
        if let Some(intent) = &entity.state.in_flight {
            cycle
                .managed
                .store
                .retire_orphaned_delivery_intent(
                    &cycle.scope.key,
                    key,
                    &intent.operation_id,
                    "prior publication owner has no confirmed result; automatic replay is disabled",
                )
                .await?;
            cycle.changed();
            return Ok(changed);
        }
        if entity.removed
            || entity.state.halt.is_some()
            || entity.state.card.lifecycle == Some(CardLifecycle::NeedsAttention)
        {
            return Ok(changed);
        }
        let card = &entity.state.card;
        let host = projection::render_host(&text.body, text.integrity, goal);
        if card.card_id.is_none()
            && text.body.trim().is_empty()
            && projection::host_region(text.integrity, goal).is_empty()
        {
            return Ok(changed);
        }
        if !cycle.scope.key.is_frontend() && card.lifecycle.is_some_and(CardLifecycle::terminal) {
            return Ok(changed);
        }
        // CardKit enforces its original 14-day entity window. An explicit expiry is a durable
        // Rejected result, never permission to create a replacement card or send another message.
        let previous_host = last_host(&entity);
        let whole = previous_host.as_deref() != Some(host.as_str())
            || card.streaming == Some(false) && card.confirmed_text != text.body;
        let action = if card.card_id.is_none() {
            DeliveryAction::CreateCard {
                text: text.body.clone(),
            }
        } else if card.platform_message_id.is_none() {
            DeliveryAction::SendCard {
                card_id: card
                    .card_id
                    .clone()
                    .ok_or_else(|| attention("card id disappeared"))?,
            }
        } else {
            let id = card
                .card_id
                .clone()
                .ok_or_else(|| attention("card id disappeared"))?;
            let streaming = goal == CardLifecycle::Streaming;
            if whole {
                // Update the independent host region before a settings transition overwrites the
                // latest frozen whole-card material; settings never change that Markdown region.
                DeliveryAction::UpdateContent {
                    card_id: id,
                    text: text.body.clone(),
                    final_content,
                }
            } else if streaming && card.streaming == Some(false) {
                DeliveryAction::UpdateSettings {
                    card_id: id,
                    streaming: true,
                    lifecycle: CardLifecycle::Streaming,
                    recovery: false,
                }
            } else if card.confirmed_text != text.body
                // Create/Send establish the entity and message, not the first sequenced
                // streaming content baseline. Confirm it once, then suppress unchanged writes.
                || card.confirmed_sequence == 0
                || whole
                || final_content
                    && card.final_content_hash.as_deref()
                        != Some(&crate::bots::storage::card::hash(text.body.as_bytes()))
            {
                DeliveryAction::UpdateContent {
                    card_id: id,
                    text: text.body.clone(),
                    final_content,
                }
            } else if !streaming && (card.streaming != Some(false) || card.lifecycle != Some(goal))
            {
                DeliveryAction::UpdateSettings {
                    card_id: id,
                    streaming: false,
                    lifecycle: goal,
                    recovery: false,
                }
            } else {
                if cycle.scope.key.is_frontend() {
                    let current = cycle
                        .managed
                        .store
                        .delivery_entity(&cycle.scope.key, key)
                        .await?
                        .ok_or_else(|| attention("unchanged public card entity is missing"))?;
                    if !matches!(&current.state.content, DeliveryContent::Text { text: current_text } if current_text == text)
                    {
                        return Err(super::unavailable(
                            "public card projection changed before local revision confirmation",
                        ));
                    }
                    match cycle
                        .managed
                        .store
                        .confirm_unchanged_delivery_text(cycle.token, key, current.ledger_version)
                        .await?
                    {
                        SettlementOutcome::Applied => {
                            cycle.changed();
                            changed = true;
                        }
                        SettlementOutcome::AlreadySettled => {}
                        SettlementOutcome::Superseded => {
                            return Err(super::unavailable(
                                "public card local revision confirmation was superseded",
                            ));
                        }
                    }
                }
                return Ok(changed);
            }
        };
        operation::perform(
            cycle,
            &entity,
            action,
            operation::Render {
                text,
                lifecycle: goal,
                streaming: card.streaming.unwrap_or(true),
                whole,
            },
        )
        .await?;
        changed = true;
    }
    Err(attention(
        "publication card actions did not converge within their bounded stages",
    ))
}

fn last_host(entity: &crate::bots::storage::publication::DeliveryEntity) -> Option<String> {
    use crate::bots::storage::publication::{DeliveryRequestTarget, DeliveryResult};
    // Compare the actual frozen JSON that the platform accepted, not a projection of the latest
    // revision. Settings/content-only requests preserve the prior host region. That prior region
    // is reconstructed from the confirmed presentation and card lifecycle when no whole card is
    // available in the latest settled operation.
    let card = &entity.state.card;
    if entity
        .state
        .settled
        .as_ref()
        .is_some_and(|settled| matches!(settled.result, DeliveryResult::NotStarted))
    {
        // These frozen bytes were never sent. They cannot prove the current host region or
        // authorize unchanged local acceptance; a later eligible action reconciles the whole
        // real card at a new sequence without replaying this retired operation.
        return None;
    }
    if entity
        .state
        .settled
        .as_ref()
        .is_some_and(|settled| settled.intent.legacy_action_hash.is_some())
    {
        // The retired renderer never had an independent host element. Its lifecycle summary
        // cannot be mistaken for a Markdown region that was actually sent to the platform.
        return Some(String::new());
    }
    if let Some(settled) = &entity.state.settled
        && matches!(
            settled.intent.request.target(),
            DeliveryRequestTarget::CreateCard | DeliveryRequestTarget::WholeCard
        )
    {
        #[derive(serde::Deserialize)]
        struct Card {
            body: Body,
        }
        #[derive(serde::Deserialize)]
        struct Body {
            elements: Vec<Element>,
        }
        #[derive(serde::Deserialize)]
        struct Element {
            element_id: String,
            content: String,
        }
        #[derive(serde::Deserialize)]
        struct EncodedCard {
            data: String,
        }
        #[derive(serde::Deserialize)]
        struct Whole {
            card: EncodedCard,
        }
        let data = if settled.intent.request.target() == DeliveryRequestTarget::CreateCard {
            serde_json::from_str::<EncodedCard>(settled.intent.request.body())
                .ok()
                .map(|c| c.data)
        } else {
            serde_json::from_str::<Whole>(settled.intent.request.body())
                .ok()
                .map(|c| c.card.data)
        };
        if let Some(data) = data
            && let Ok(card) = serde_json::from_str::<Card>(&data)
        {
            return Some(
                card.body
                    .elements
                    .into_iter()
                    .find(|e| e.element_id == "publication_status")
                    .map(|e| e.content)
                    .unwrap_or_default(),
            );
        }
    }
    let integrity = match &card.confirmed_presentation {
        Some(pl_protocol::studio::BotItemPresentation::Text { integrity, .. }) => *integrity,
        _ => pl_protocol::studio::BotTextIntegrity::Full,
    };
    Some(projection::render_host(
        &card.confirmed_text,
        integrity,
        card.lifecycle.unwrap_or(CardLifecycle::Streaming),
    ))
}
