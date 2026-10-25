//! Single-card orchestration, owned by the original inbound reply task.

mod operation;

use super::owner::{ReplyRun, ReplyTarget, attention, classify_send_error};
use crate::bots::InboundWorkOutcome;
use crate::bots::owner::{BotRuntime, ManagedBot};
use crate::bots::protocol::cardkit::validate_card;
use crate::bots::protocol::error::FeishuError;
use crate::bots::storage::MarkOutcome;
use crate::bots::storage::card::{
    CardAction, CardLifecycle, CardOperationStatus, CardRecovery, CardRecoveryPhase, CardStream,
    hash,
};
use tokio_util::sync::CancellationToken;

enum CardFailure {
    Stop(InboundWorkOutcome),
    Rejected(FeishuError),
}

struct CardProgress<'a> {
    target: ReplyTarget<'a>,
    text: Option<&'a str>,
    goal: CardLifecycle,
    cancel: &'a CancellationToken,
}

impl BotRuntime {
    pub(super) async fn progress_card(
        &self,
        run: &mut ReplyRun,
        target: ReplyTarget<'_>,
        text: Option<&str>,
        goal: CardLifecycle,
        cancel: &CancellationToken,
    ) -> Result<(), InboundWorkOutcome> {
        if run.card.is_none()
            && (text.is_none_or(|text| text.trim().is_empty())
                || goal != CardLifecycle::Streaming && goal != CardLifecycle::Completed)
        {
            return Ok(());
        }
        // Check the complete card before creating an entity or changing the last
        // confirmed preview. Reserve the mandatory no-final warning's space too,
        // so an accepted preview can be closed without truncating its contents.
        // Oversize answers remain in canonical local history.
        if let Some(text) = text
            && let Err(error) = validate_card(text, true, CardLifecycle::Streaming.summary())
                .and_then(|()| {
                    validate_card(text, goal == CardLifecycle::Streaming, goal.summary())
                })
                .and_then(|()| validate_card(text, false, CardLifecycle::NoFinalReply.summary()))
        {
            return self.card_budget_failure(run, error).await;
        }
        let managed = self
            .managed(&run.bot_id)
            .await
            .map_err(classify_send_error)?;
        let mut state = match run.card.take() {
            Some(state) => state,
            None => match target {
                ReplyTarget::Consumed(turn_id) => {
                    CardStream::new(run.card_binding(), &run.watch_input, turn_id)
                }
                ReplyTarget::Unconsumed => return Ok(()),
            },
        };
        let result = self
            .drive_card(
                &managed,
                run,
                &mut state,
                CardProgress {
                    target,
                    text,
                    goal,
                    cancel,
                },
            )
            .await;
        let result = match result {
            Ok(()) => Ok(()),
            Err(CardFailure::Stop(outcome)) => Err(outcome),
            Err(CardFailure::Rejected(error)) => {
                state.lifecycle = CardLifecycle::NeedsAttention;
                state.diagnostic = Some(error.diagnostic());
                match self.persist_card(&managed, run, &mut state).await {
                    Ok(()) => Err(attention(safe_failure(
                        "CardKit operation rejected",
                        &error,
                    ))),
                    Err(outcome) => Err(outcome),
                }
            }
        };
        run.card = Some(state);
        result
    }

    pub(super) async fn bind_reply_card_target(
        &self,
        run: &mut ReplyRun,
        target: ReplyTarget<'_>,
    ) -> Result<(), InboundWorkOutcome> {
        let Some(mut state) = run.card.take() else {
            return Ok(());
        };
        let result = match self.managed(&run.bot_id).await {
            Ok(managed) => {
                self.align_card_target(&managed, run, &mut state, target)
                    .await
            }
            Err(error) => Err(classify_send_error(error)),
        };
        run.card = Some(state);
        result
    }

    async fn align_card_target(
        &self,
        managed: &ManagedBot,
        run: &ReplyRun,
        state: &mut CardStream,
        target: ReplyTarget<'_>,
    ) -> Result<(), InboundWorkOutcome> {
        if state
            .bind_target(&run.watch_input, target.turn_id())
            .map_err(classify_send_error)?
        {
            self.persist_card(managed, run, state).await?;
        }
        Ok(())
    }

    async fn drive_card(
        &self,
        managed: &ManagedBot,
        run: &ReplyRun,
        state: &mut CardStream,
        progress: CardProgress<'_>,
    ) -> Result<(), CardFailure> {
        let CardProgress {
            target,
            text,
            goal,
            cancel,
        } = progress;
        if state.uncertain() || state.lifecycle == CardLifecycle::NeedsAttention {
            return Err(CardFailure::Stop(attention(
                "card operation acceptance is unknown; automatic replay is disabled",
            )));
        }
        self.align_card_target(managed, run, state, target)
            .await
            .map_err(CardFailure::Stop)?;
        if state.lifecycle.terminal() {
            return Ok(());
        }
        if goal == CardLifecycle::NoFinalReply {
            state.mark_no_final_reply();
        }
        if state.recovery.is_some() {
            self.resume_card_recovery(managed, run, state, cancel)
                .await?;
            if state.lifecycle.terminal() {
                return Ok(());
            }
        }
        // An explicitly rejected operation can be recovered after a clean stop,
        // but never by first sending another content request into the closed stream.
        if let Some(operation) = state.last_operation.as_ref()
            && operation.status == CardOperationStatus::Rejected
        {
            if operation.diagnostic.as_ref().is_some_and(|diagnostic| {
                matches!(
                    diagnostic.platform_code.as_deref(),
                    Some("200850" | "300309")
                )
            }) && !state.recovery_used
            {
                let action = operation.action.clone();
                self.recover_card_stream(managed, run, state, action, cancel)
                    .await?;
                if state.lifecycle.terminal() {
                    return Ok(());
                }
            } else {
                return Err(CardFailure::Stop(attention(
                    "card operation was explicitly rejected; local recovery required",
                )));
            }
        }
        if state.card_id.is_none() {
            let Some(text) = text.filter(|text| !text.trim().is_empty()) else {
                return Ok(());
            };
            self.card_action(
                managed,
                run,
                state,
                CardAction::Create {
                    text: text.to_string(),
                },
                cancel,
            )
            .await?;
        }
        if state.platform_message_id.is_none() {
            if goal.terminal() && goal != CardLifecycle::Completed {
                // A local cancellation/failure after entity creation must close
                // that known entity, not introduce a new chat message merely to
                // finish an already cancelled reply.
                self.card_action(
                    managed,
                    run,
                    state,
                    CardAction::Settings {
                        streaming: false,
                        lifecycle: goal,
                        recovery: false,
                    },
                    cancel,
                )
                .await?;
                return Ok(());
            }
            self.card_action(managed, run, state, CardAction::Send {}, cancel)
                .await?;
        }
        let needs_stream = matches!(goal, CardLifecycle::Streaming | CardLifecycle::Completed);
        if state.lifecycle == CardLifecycle::Paused && needs_stream {
            self.card_action(
                managed,
                run,
                state,
                CardAction::Settings {
                    streaming: true,
                    lifecycle: CardLifecycle::Streaming,
                    recovery: false,
                },
                cancel,
            )
            .await?;
        }
        if let Some(text) = text {
            let final_content = goal == CardLifecycle::Completed;
            let already_final = state.final_content_hash.as_deref() == Some(&hash(text.as_bytes()));
            if state.confirmed_text != text
                || state.confirmed_sequence == 0
                || final_content && !already_final
            {
                self.card_action(
                    managed,
                    run,
                    state,
                    CardAction::Content {
                        text: text.to_string(),
                        final_content,
                    },
                    cancel,
                )
                .await?;
            }
        }
        if goal != CardLifecycle::Streaming && state.lifecycle != goal {
            if goal == CardLifecycle::Completed
                && text.is_some_and(|text| {
                    state.final_content_hash.as_deref() != Some(&hash(text.as_bytes()))
                })
            {
                return Err(CardFailure::Stop(attention(
                    "final card content is not confirmed",
                )));
            }
            self.card_action(
                managed,
                run,
                state,
                CardAction::Settings {
                    streaming: false,
                    lifecycle: goal,
                    recovery: false,
                },
                cancel,
            )
            .await?;
        }
        Ok(())
    }

    /// Explicit stream timeout/closed is not a transport timeout. One bounded
    /// settings(true) -> full content -> desired close recovery, without probing
    /// the closed stream again or reissuing any uncertain operation.
    async fn card_action(
        &self,
        managed: &ManagedBot,
        run: &ReplyRun,
        state: &mut CardStream,
        action: CardAction,
        cancel: &CancellationToken,
    ) -> Result<(), CardFailure> {
        let failure = match self
            .perform_card_action(managed, run, state, action.clone(), cancel)
            .await
        {
            Ok(()) => return Ok(()),
            Err(CardFailure::Rejected(error)) => error,
            Err(other) => return Err(other),
        };
        if !matches!(failure.platform_code(), Some("200850" | "300309"))
            || state.recovery_used
            || state.card_id.is_none()
            || state.platform_message_id.is_none()
            || state.turn_id.is_none()
            || !matches!(
                action,
                CardAction::Content { .. } | CardAction::Settings { .. }
            )
        {
            return Err(CardFailure::Rejected(failure));
        }
        self.recover_card_stream(managed, run, state, action, cancel)
            .await
    }

    async fn recover_card_stream(
        &self,
        managed: &ManagedBot,
        run: &ReplyRun,
        state: &mut CardStream,
        action: CardAction,
        cancel: &CancellationToken,
    ) -> Result<(), CardFailure> {
        let content = action.text().unwrap_or(&state.confirmed_text).to_string();
        validate_card(&content, true, CardLifecycle::Streaming.summary())
            .map_err(CardFailure::Rejected)?;
        state.recovery = Some(CardRecovery {
            action,
            phase: CardRecoveryPhase::Reopen,
        });
        self.resume_card_recovery(managed, run, state, cancel).await
    }

    async fn resume_card_recovery(
        &self,
        managed: &ManagedBot,
        run: &ReplyRun,
        state: &mut CardStream,
        cancel: &CancellationToken,
    ) -> Result<(), CardFailure> {
        for _ in 0..3 {
            let Some(recovery) = state.recovery.clone() else {
                return Ok(());
            };
            let action = match recovery.phase {
                CardRecoveryPhase::Reopen => CardAction::Settings {
                    streaming: true,
                    lifecycle: CardLifecycle::Streaming,
                    recovery: true,
                },
                CardRecoveryPhase::Content => {
                    let text = recovery
                        .action
                        .text()
                        .unwrap_or(&state.confirmed_text)
                        .to_string();
                    let final_content = match recovery.action {
                        CardAction::Content { final_content, .. } => final_content,
                        _ => state.final_content_hash.as_deref() == Some(&hash(text.as_bytes())),
                    };
                    CardAction::Content {
                        text,
                        final_content,
                    }
                }
                CardRecoveryPhase::Close => {
                    let CardAction::Settings {
                        streaming: false,
                        lifecycle,
                        ..
                    } = recovery.action
                    else {
                        return Err(CardFailure::Stop(attention(
                            "card recovery close target is inconsistent",
                        )));
                    };
                    CardAction::Settings {
                        streaming: false,
                        lifecycle,
                        recovery: false,
                    }
                }
            };
            self.perform_card_action(managed, run, state, action, cancel)
                .await?;
        }
        if state.recovery.is_none() {
            Ok(())
        } else {
            Err(CardFailure::Stop(attention(
                "card recovery did not advance within its bounded stages",
            )))
        }
    }

    async fn persist_card(
        &self,
        managed: &ManagedBot,
        run: &ReplyRun,
        state: &mut CardStream,
    ) -> Result<(), InboundWorkOutcome> {
        match managed.store.save_card(state, &run.worker_id).await {
            Ok(MarkOutcome::Applied) => Ok(()),
            Ok(MarkOutcome::LostClaim) => Err(InboundWorkOutcome::LostClaim),
            // A failed commit/confirmation does not prove rollback. The stored
            // intent, if committed, remains the no-replay barrier on restart.
            Err(_) => Err(attention(
                "card progress persistence is unconfirmed; local recovery required",
            )),
        }
    }

    async fn card_budget_failure(
        &self,
        run: &mut ReplyRun,
        error: FeishuError,
    ) -> Result<(), InboundWorkOutcome> {
        if let Some(state) = run.card.as_mut() {
            let managed = self
                .managed(&run.bot_id)
                .await
                .map_err(classify_send_error)?;
            state.lifecycle = CardLifecycle::NeedsAttention;
            state.diagnostic = Some(error.diagnostic());
            match managed.store.save_card(state, &run.worker_id).await {
                Ok(MarkOutcome::Applied) => {}
                Ok(MarkOutcome::LostClaim) => return Err(InboundWorkOutcome::LostClaim),
                Err(_) => {
                    return Err(attention(
                        "oversize card diagnostic persistence is unconfirmed",
                    ));
                }
            }
        }
        Err(attention(safe_failure(
            "card size validation failed",
            &error,
        )))
    }
}

fn safe_failure(context: &str, error: &FeishuError) -> String {
    match error.platform_code() {
        Some(code) => format!("{context}: {error} (platform code {code})"),
        None => format!("{context}: {error}"),
    }
}
