//! Finite original-input Final policy, executed by the same Cycle/cards/operation owner.
//! No model submission, inbound claim, old ReplyRun or separate reply task survives here.

use super::worker::{Cycle, goal};
use super::{attention, cards, operation, projection, scan, unavailable};
use crate::bots::protocol::error::FeishuError;
use crate::bots::storage::card::CardLifecycle;
use crate::bots::storage::publication::{
    DeliveryAction, DeliveryContent, DeliveryEntity, DeliveryInputChain, DeliveryLegacyCandidate,
    DeliveryScopeOrigin, DeliveryText, DeliveryTurnIdentity, DeliveryTurnOwner,
    LegacyLocalCompletion, MergeOutcome, SettlementOutcome,
};
use crate::bots::{BotInputRead, BotInteractionKind, BotInteractionRead};
use crate::studio::{TimelineContentReader, TimelineMetadataRead};
use pl_core::thread::input::{InputDelivery, InputState};
use pl_protocol::studio::BotPublicTextChannel;
use pl_protocol::{
    InteractionStatus, ThreadItemState, ThreadTextChannel, TimelineLifecycle, TimelinePageQuery,
};
use std::collections::BTreeSet;

pub(super) async fn advance(
    cycle: &Cycle<'_>,
    reader: &TimelineContentReader,
    budget: &mut scan::RecoveryBudget,
) -> Result<bool, FeishuError> {
    let DeliveryScopeOrigin::LegacyFinal { legacy } = &cycle.scope.origin else {
        return Err(attention(
            "finite publication has no original input evidence",
        ));
    };
    if !legacy.resumable || legacy.needs_recovery.is_some() {
        return Ok(false);
    }
    let page = cycle
        .managed
        .store
        .delivery_entities(&cycle.scope.key, None, 2)
        .await?;
    if page.entities.len() != 1 || page.next_after.is_some() {
        return Err(attention(
            "finite publication must retain exactly its original single-card entity",
        ));
    }
    let entity = &page.entities[0];
    if entity.state.halt.is_some()
        || entity
            .state
            .card
            .lifecycle
            .is_some_and(CardLifecycle::terminal)
    {
        return Ok(false);
    }
    if let Some(intent) = &entity.state.in_flight {
        cycle
            .managed
            .store
            .retire_orphaned_delivery_intent(
                &cycle.scope.key,
                &entity.entity,
                &intent.operation_id,
                "legacy card Intent has no confirmed original owner result; it is not replayable",
            )
            .await?;
        cycle.changed();
        return Ok(false);
    }
    let coverage = scan::recover(cycle, reader, budget, &BTreeSet::new()).await?;
    retain_input(
        budget,
        &legacy.original_input_id,
        legacy.original_input_id.len(),
    )?;
    let mut input = legacy.original_input_id.clone();
    let mut seen = BTreeSet::new();
    let mut ancestors: Vec<String> = Vec::new();
    let mut turn_identity = scan::IdentityReservation::default();
    let mut changed = false;
    loop {
        cycle.active()?;
        if seen.len() >= scan::MAX_ITEMS || seen.contains(&input) {
            return Err(attention(
                "finite publication continuation proof is cyclic or exceeds its budget",
            ));
        }
        seen.insert(input.clone());
        budget.inspect(1)?;
        let fact = cycle
            .host
            .bot_input_fact(&cycle.scope.thread_id, &input)
            .await
            .map_err(|e| FeishuError::history_read("read finite publication original input", e))?;
        let turn = match fact {
            BotInputRead::Absent | BotInputRead::NotReady => return Ok(changed),
            BotInputRead::Ready {
                delivery: InputDelivery::CurrentTurn { .. },
                ..
            } => {
                return Err(attention(
                    "finite publication input was routed onto an unrelated current Turn",
                ));
            }
            BotInputRead::Ready {
                delivery: InputDelivery::NextTurn,
                state: InputState::Pending,
            } => return Ok(changed),
            BotInputRead::Ready {
                delivery: InputDelivery::NextTurn,
                state: InputState::Discarded,
            } => {
                return finish_existing(
                    cycle,
                    entity,
                    CardLifecycle::InteractionEnded,
                    Some(LegacyLocalCompletion::Discarded),
                )
                .await
                .map(|work| changed | work);
            }
            BotInputRead::Ready {
                delivery: InputDelivery::NextTurn,
                state: InputState::Consumed { turn_id, .. },
            } => turn_id,
        };
        budget.replace_identity(
            &mut turn_identity,
            turn.capacity()
                .checked_add(size_of::<String>())
                .ok_or_else(|| attention("finite Turn identity size overflow"))?,
        )?;
        if input == legacy.original_input_id
            && legacy
                .original_turn_id
                .as_ref()
                .is_some_and(|original| *original != turn)
        {
            return Err(attention(
                "finite publication original input/Turn evidence conflicts",
            ));
        }
        let owner_bytes = chain_bytes(&input, &ancestors)?
            .checked_add(cycle.scope.thread_id.len())
            .and_then(|bytes| bytes.checked_add(turn.len()))
            .and_then(|bytes| bytes.checked_add(128))
            .ok_or_else(|| attention("finite owner identity size overflow"))?;
        let correct_owner = budget
            .with_identity_bytes(owner_bytes, async {
                let owner = cycle
                    .managed
                    .store
                    .delivery_turn_owner(&DeliveryTurnIdentity {
                        thread_id: cycle.scope.thread_id.clone(),
                        turn_id: turn.clone(),
                        input_chain: input_chain(&input, &ancestors),
                    })
                    .await?;
                Ok(matches!(owner, DeliveryTurnOwner::LegacyFinal { scope }
                    if scope == cycle.scope.key))
            })
            .await?;
        if !correct_owner {
            return Err(attention(
                "finite publication original/continuation chain does not have a unique owner",
            ));
        }
        // Unlike the new frontend, old Final can be proved by the original input/Turn and
        // committed interaction chain even if this history predates Turn-start receipts.
        let mut lifecycle = goal(cycle, reader, &turn, budget).await?;
        if lifecycle == CardLifecycle::Paused {
            match continuation(cycle, reader, &turn, budget).await? {
                Continuation::Next(next) => {
                    // Reconstruct the whole trusted target before reading or rendering Final.
                    // Re-reading every ancestor's content on each recovery is not bounded by
                    // the number of unique content items in this pass.
                    if seen.contains(&next) {
                        return Err(attention("finite publication continuation proof is cyclic"));
                    }
                    retain_input(budget, &next, next.capacity())?;
                    ancestors.push(input);
                    input = next;
                    continue;
                }
                Continuation::Ended => lifecycle = CardLifecycle::InteractionEnded,
                Continuation::Waiting => {}
            }
        }
        // Failed/cancelled finite inputs do not authorize a new answer. Their canonical
        // input/Turn proof suffices to close an existing card or settle a never-created card.
        if matches!(
            lifecycle,
            CardLifecycle::Cancelled
                | CardLifecycle::Failed
                | CardLifecycle::BudgetLimited
                | CardLifecycle::InteractionEnded
        ) {
            return finish_existing(cycle, entity, lifecycle, local_completion(lifecycle)).await;
        }
        let mut body = String::new();
        let mut full = true;
        let mut saved = true;
        let mut finals_terminal = true;
        for (_, id) in &coverage.items {
            cycle.active()?;
            budget.inspect(1)?;
            let reads = reader
                .read_metadata(std::slice::from_ref(id))
                .await
                .map_err(|e| {
                    super::content_error("read finite publication canonical metadata", e)
                })?;
            let Some(TimelineMetadataRead::Present(metadata)) = reads.into_iter().next() else {
                return Err(unavailable(
                    "finite publication source is temporarily missing; original materials retained",
                ));
            };
            if metadata.shell.turn_id != turn {
                continue;
            }
            match metadata.shell.state() {
                ThreadItemState::Text(text) if text.channel() == ThreadTextChannel::Final => {
                    finals_terminal &= metadata.lifecycle == TimelineLifecycle::Terminal;
                    saved &= metadata.saved;
                    if body.chars().count() <= 4000 {
                        let text = projection::read(reader, &metadata).await?;
                        if !text.body.trim().is_empty() {
                            if !body.is_empty() {
                                body.push_str("\n\n");
                            }
                            body.extend(
                                text.body
                                    .chars()
                                    .take(4001usize.saturating_sub(body.chars().count())),
                            );
                        }
                        full &= text.integrity == pl_protocol::studio::BotTextIntegrity::Full;
                    } else {
                        full = false;
                    }
                }
                _ => {}
            }
        }
        if lifecycle == CardLifecycle::Completed && !finals_terminal {
            return Ok(changed);
        }
        if !body.trim().is_empty() {
            let text = projection::text_from_projection(
                projection::fit(&body, full)?,
                BotPublicTextChannel::Final,
                0,
                saved,
            );
            let current = cycle
                .managed
                .store
                .delivery_entity(&cycle.scope.key, &entity.entity)
                .await?
                .ok_or_else(|| {
                    attention(
                        "finite publication original entity is missing before projection merge",
                    )
                })?;
            // S owns a second chain during its fenced ownership check, plus the presentation's
            // Turn identity. Neither temporary chain survives this merge or counts as a new input.
            let merge_bytes = chain_bytes(&input, &ancestors)?
                .checked_mul(2)
                .and_then(|bytes| bytes.checked_add(turn.len().checked_mul(3)?))
                .and_then(|bytes| bytes.checked_add(cycle.scope.thread_id.len()))
                .and_then(|bytes| bytes.checked_add(256))
                .ok_or_else(|| attention("finite merge identity size overflow"))?;
            let merged = budget
                .with_identity_bytes(merge_bytes, async {
                    cycle
                        .managed
                        .store
                        .merge_legacy_delivery_presentation(
                            cycle.token,
                            &entity.entity,
                            current.ledger_version,
                            &DeliveryLegacyCandidate {
                                turn_id: turn.clone(),
                                input_chain: input_chain(&input, &ancestors),
                                body: text.body.clone(),
                                integrity: text.integrity,
                                saved: text.saved,
                                request_bytes: text.request_bytes,
                            },
                        )
                        .await
                })
                .await?;
            match merged {
                MergeOutcome::Applied { .. } => cycle.changed(),
                MergeOutcome::Unchanged { .. } => {}
                MergeOutcome::Fenced => return Err(FeishuError::cancelled()),
                MergeOutcome::Stale { .. } => {
                    return Err(unavailable(
                        "finite projection was superseded by a newer proof",
                    ));
                }
                MergeOutcome::Conflict | MergeOutcome::NotCanonical => {
                    return Err(attention(
                        "finite projection does not match its unique original owner",
                    ));
                }
            }
            changed |= cards::drive(
                cycle,
                &entity.entity,
                &text,
                lifecycle,
                lifecycle == CardLifecycle::Completed && finals_terminal,
            )
            .await?;
        } else if lifecycle != CardLifecycle::Streaming {
            changed |= finish_existing(
                cycle,
                entity,
                if lifecycle == CardLifecycle::Completed {
                    CardLifecycle::NoFinalReply
                } else {
                    lifecycle
                },
                local_completion(lifecycle),
            )
            .await?;
        }
        return Ok(changed);
    }
}

pub(super) enum Continuation {
    Next(String),
    Ended,
    Waiting,
}

pub(super) async fn continuation(
    cycle: &Cycle<'_>,
    reader: &TimelineContentReader,
    turn: &str,
    budget: &mut scan::RecoveryBudget,
) -> Result<Continuation, FeishuError> {
    let mut local_identities = scan::IdentityReservation::default();
    let mut cursor_identity = scan::IdentityReservation::default();
    let mut next_identity = scan::IdentityReservation::default();
    let result = async {
        let mut locals = BTreeSet::new();
        let snapshot = cycle
            .host
            .thread_snapshot(&cycle.scope.thread_id)
            .await
            .map_err(|e| {
                FeishuError::history_read("read finite publication interaction identities", e)
            })?;
        for interaction in snapshot
            .interactions
            .iter()
            .filter(|i| i.scope.turn_id == turn)
        {
            if let Ok((_, local)) =
                crate::thread_assembler::decode_interaction_key(&interaction.interaction_id)
            {
                remember_local(&mut locals, local, budget, &mut local_identities)?;
            }
        }
        drop(snapshot);
        // Settled user-input records may no longer be in the resident snapshot (while permission
        // records remain). Recover *all* local identities from the same reader's canonical Turn
        // range, rather than treating a partial snapshot as proof that no continuation exists.
        let mut before: Option<String> = None;
        loop {
            cycle.active()?;
            let limit = budget.page_limit()?;
            let query_bytes = before
                .as_ref()
                .map_or(0, String::len)
                .checked_add(size_of::<String>())
                .ok_or_else(|| attention("publication interaction cursor size overflow"))?;
            let page = budget
                .with_identity_bytes(query_bytes, async {
                    reader
                        .page(&TimelinePageQuery {
                            before: before.clone(),
                            limit: Some(limit),
                        })
                        .await
                        .map_err(|e| {
                            super::content_error("read publication interaction identity range", e)
                        })
                })
                .await?;
            if page.thread_id != cycle.scope.thread_id || page.items.len() > limit as usize {
                return Err(attention(
                    "publication interaction range identity/budget mismatch",
                ));
            }
            budget.inspect(page.items.len())?;
            let mut found_start = false;
            for item in page.items {
                if item.preview.turn_id != turn {
                    continue;
                }
                match item.preview.state() {
                    ThreadItemState::Turn(_) => found_start = true,
                    ThreadItemState::Tool(tool) => {
                        if let Some(input) = tool.user_input() {
                            remember_local(
                                &mut locals,
                                input.interaction_id(),
                                budget,
                                &mut local_identities,
                            )?;
                        }
                    }
                    _ => {}
                }
            }
            if found_start || !page.has_older {
                break;
            }
            let next = page
                .before
                .filter(|cursor| !cursor.is_empty())
                .ok_or_else(|| attention("publication interaction range lacks an older cursor"))?;
            if before.as_ref() == Some(&next) {
                return Err(attention("publication interaction cursor did not advance"));
            }
            budget.replace_identity(
                &mut cursor_identity,
                next.capacity()
                    .checked_add(size_of::<String>())
                    .ok_or_else(|| attention("publication interaction cursor size overflow"))?,
            )?;
            before = Some(next);
        }
        let mut continuation = None;
        let mut ended = false;
        let mut pending = false;
        for local in locals {
            budget.inspect(1)?;
            match cycle
                .host
                .bot_interaction_fact(&cycle.scope.thread_id, &local)
                .await
                .map_err(|e| {
                    FeishuError::history_read("read finite publication continuation decision", e)
                })? {
                BotInteractionRead::Ready(fact) => match (fact.kind, fact.status) {
                    (BotInteractionKind::UserInput, InteractionStatus::Resolved) => {
                        match fact.continuation_input {
                            Some(next) => {
                                budget.replace_identity(
                                    &mut next_identity,
                                    next.capacity()
                                        .checked_add(size_of::<String>())
                                        .ok_or_else(|| {
                                            attention("finite continuation identity size overflow")
                                        })?,
                                )?;
                                if continuation.as_ref().is_some_and(|old| *old != next) {
                                    return Err(attention(
                                        "finite publication continuation is ambiguous",
                                    ));
                                }
                                continuation = Some(next);
                            }
                            None => ended = true,
                        }
                    }
                    (
                        BotInteractionKind::UserInput,
                        InteractionStatus::Cancelled | InteractionStatus::Expired,
                    ) => ended = true,
                    (_, InteractionStatus::Pending) => pending = true,
                    (BotInteractionKind::Permission, _) => {}
                },
                BotInteractionRead::Absent | BotInteractionRead::NotReady => {
                    return Ok(Continuation::Waiting);
                }
            }
        }
        if let Some(next) = continuation {
            return Ok(Continuation::Next(next));
        }
        if ended && !pending {
            return Ok(Continuation::Ended);
        }
        Ok(Continuation::Waiting)
    }
    .await;
    // All local sets/cursors are dropped before these credits return. The returned Next value
    // transfers immediately to advance's retained input or is discarded by frontend goal.
    budget.release_identity(local_identities)?;
    budget.release_identity(cursor_identity)?;
    budget.release_identity(next_identity)?;
    result
}

fn remember_local(
    locals: &mut BTreeSet<String>,
    local: &str,
    budget: &mut scan::RecoveryBudget,
    reservation: &mut scan::IdentityReservation,
) -> Result<(), FeishuError> {
    if !locals.contains(local) {
        let bytes = local
            .len()
            .checked_add(160)
            .ok_or_else(|| attention("finite interaction identity size overflow"))?;
        budget.extend_identity(reservation, bytes)?;
        locals.insert(local.to_owned());
    }
    Ok(())
}

fn retain_input(
    budget: &mut scan::RecoveryBudget,
    input: &str,
    owned_capacity: usize,
) -> Result<(), FeishuError> {
    // One owned current/ancestor String plus the seen-set copy. Moving current into ancestors
    // does not add an identity; fixed overhead includes tree entries and spare Vec slots.
    let bytes = owned_capacity
        .checked_add(input.len())
        .and_then(|bytes| bytes.checked_add(224))
        .ok_or_else(|| attention("finite input identity size overflow"))?;
    budget.retain_identity(bytes)
}

fn input_chain(input: &str, ancestors: &[String]) -> DeliveryInputChain {
    DeliveryInputChain::Proven {
        input_id: input.to_owned(),
        continuation_ancestors: ancestors.iter().rev().cloned().collect(),
    }
}

fn chain_bytes(input: &str, ancestors: &[String]) -> Result<usize, FeishuError> {
    ancestors.iter().try_fold(
        input
            .len()
            .checked_add(128)
            .ok_or_else(|| attention("finite input chain size overflow"))?,
        |bytes, ancestor| {
            bytes
                .checked_add(ancestor.len())
                .and_then(|bytes| bytes.checked_add(2 * size_of::<String>()))
                .ok_or_else(|| attention("finite input chain size overflow"))
        },
    )
}

async fn finish_existing(
    cycle: &Cycle<'_>,
    original: &DeliveryEntity,
    lifecycle: CardLifecycle,
    completion: Option<LegacyLocalCompletion>,
) -> Result<bool, FeishuError> {
    let entity = cycle
        .managed
        .store
        .delivery_entity(&cycle.scope.key, &original.entity)
        .await?
        .ok_or_else(|| attention("finite publication original entity is missing"))?;
    if entity.state.card.card_id.is_none() {
        let Some(reason) = completion else {
            // No original Final and the interaction is still pending: this is waiting, not a
            // completed delivery and not permission to create an empty reply.
            return Ok(false);
        };
        return match cycle
            .managed
            .store
            .settle_legacy_without_card(cycle.token, &entity.entity, entity.ledger_version, reason)
            .await?
        {
            SettlementOutcome::Applied => {
                cycle.changed();
                Ok(true)
            }
            SettlementOutcome::AlreadySettled => Ok(false),
            SettlementOutcome::Superseded => Err(unavailable(
                "finite local terminal settlement was superseded",
            )),
        };
    }
    if entity.state.halt.is_some()
        || entity.state.in_flight.is_some()
        || entity.state.card.lifecycle == Some(CardLifecycle::NeedsAttention)
    {
        return Ok(false);
    }
    if entity.state.card.lifecycle == Some(lifecycle) && entity.state.card.streaming == Some(false)
    {
        return Ok(false);
    }
    if let DeliveryContent::Legacy {
        presentation: Some(presentation),
        ..
    } = &entity.state.content
        && presentation.body == entity.state.card.confirmed_text
    {
        // A proven existing projection can update its independent host status without changing
        // the old model preview. A migrated/unmatched projection cannot authorize such a body;
        // that case below is limited to original confirmed settings/summary, never a new answer.
        let text = DeliveryText {
            channel: BotPublicTextChannel::Final,
            revision: 0,
            integrity: presentation.integrity,
            saved: presentation.saved,
            body: presentation.body.clone(),
            body_chars: presentation.body.chars().count() as u64,
            request_bytes: presentation.request_bytes,
        };
        return cards::drive(cycle, &entity.entity, &text, lifecycle, false).await;
    }
    let Some(pl_protocol::studio::BotItemPresentation::Text {
        integrity, saved, ..
    }) = entity.state.card.confirmed_presentation.as_ref()
    else {
        return Err(attention(
            "finite card lacks its original confirmed presentation; no new body is authorized",
        ));
    };
    let text = DeliveryText {
        channel: BotPublicTextChannel::Final,
        revision: 0,
        integrity: *integrity,
        saved: *saved,
        body: entity.state.card.confirmed_text.clone(),
        body_chars: entity.state.card.confirmed_text.chars().count() as u64,
        request_bytes: 0,
    };
    operation::perform(
        cycle,
        &entity,
        DeliveryAction::UpdateSettings {
            card_id: entity
                .state
                .card
                .card_id
                .clone()
                .ok_or_else(|| attention("finite card identity disappeared"))?,
            streaming: false,
            lifecycle,
            recovery: false,
        },
        operation::Render {
            text: &text,
            lifecycle,
            streaming: entity.state.card.streaming.unwrap_or(false),
            whole: false,
        },
    )
    .await?;
    Ok(true)
}

fn local_completion(lifecycle: CardLifecycle) -> Option<LegacyLocalCompletion> {
    match lifecycle {
        CardLifecycle::Completed | CardLifecycle::NoFinalReply => {
            Some(LegacyLocalCompletion::NoFinal)
        }
        CardLifecycle::BudgetLimited => Some(LegacyLocalCompletion::BudgetLimited),
        CardLifecycle::Cancelled => Some(LegacyLocalCompletion::Cancelled),
        CardLifecycle::Failed => Some(LegacyLocalCompletion::Failed),
        CardLifecycle::InteractionEnded => Some(LegacyLocalCompletion::InteractionEnded),
        CardLifecycle::Empty
        | CardLifecycle::Created
        | CardLifecycle::Streaming
        | CardLifecycle::Paused
        | CardLifecycle::NeedsAttention => None,
    }
}
