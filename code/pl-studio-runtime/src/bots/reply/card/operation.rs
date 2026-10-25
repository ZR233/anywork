use super::{CardFailure, safe_failure};
use crate::bots::InboundWorkOutcome;
use crate::bots::owner::{BotRuntime, ManagedBot};
use crate::bots::protocol::cardkit::{CardSettings, FeishuCardKit, validate_card};
use crate::bots::protocol::im::FeishuIm;
use crate::bots::reply::owner::{ReplyRun, attention, classify_send_error};
use crate::bots::storage::card::{
    CardAction, CardLifecycle, CardOperationStatus, CardStream, hash,
};
use std::sync::atomic::Ordering;
use tokio_util::sync::CancellationToken;

enum Confirmed {
    Entity(String),
    Message(String),
    Mutation,
}

impl BotRuntime {
    pub(super) async fn perform_card_action(
        &self,
        managed: &ManagedBot,
        run: &ReplyRun,
        state: &mut CardStream,
        action: CardAction,
        cancel: &CancellationToken,
    ) -> Result<(), CardFailure> {
        if cancel.is_cancelled() || self.inner.sealed.load(Ordering::Acquire) != 0 {
            return Err(CardFailure::Stop(InboundWorkOutcome::Interrupted));
        }
        let text = action.text().unwrap_or(&state.confirmed_text);
        let (streaming, summary) = match action {
            CardAction::Settings {
                streaming,
                lifecycle,
                ..
            } => (streaming, lifecycle.summary()),
            _ => (true, CardLifecycle::Streaming.summary()),
        };
        validate_card(text, streaming, summary).map_err(CardFailure::Rejected)?;
        let config = managed.config.lock().await.clone();
        crate::bots::source::authorize_source_identity(&config, &run.chat_id, &run.source)
            .map_err(|error| CardFailure::Stop(classify_send_error(error)))?;
        let membership = if matches!(action, CardAction::Create { .. } | CardAction::Send {}) {
            Some(
                self.prepare_chat_access(managed, &config, &run.chat_id, cancel)
                    .await
                    .map_err(|error| CardFailure::Stop(classify_send_error(error)))?,
            )
        } else {
            None
        };
        let token = self
            .token(managed, &config)
            .await
            .map_err(|error| CardFailure::Stop(classify_send_error(error)))?;
        let send_permit = tokio::select! {
            _ = cancel.cancelled() => return Err(CardFailure::Stop(InboundWorkOutcome::Interrupted)),
            permit = managed.send_rate.acquire() => permit,
        };
        {
            let _admission = managed.admission.lock().await;
            if cancel.is_cancelled() || self.inner.sealed.load(Ordering::Acquire) != 0 {
                return Err(CardFailure::Stop(InboundWorkOutcome::Interrupted));
            }
            if managed.admission_closed.load(Ordering::Acquire) {
                return Err(CardFailure::Stop(crate::bots::reply::owner::recoverable(
                    "bot admission is temporarily closed before card intent",
                )));
            }
            // Network/token preparation and rate waiting confer no authority. All
            // actions, including close/recovery, share the configuration publication
            // boundary. Connection generation is deliberately not an auth epoch.
            let current = managed.config.lock().await;
            crate::bots::source::authorize_source_identity(&current, &run.chat_id, &run.source)
                .map_err(|error| CardFailure::Stop(classify_send_error(error)))?;
            if let Some(membership) = membership
                && !membership.covers(&run.chat_id)
            {
                return Err(CardFailure::Stop(attention(
                    "original card target is no longer visible",
                )));
            }
            drop(current);
            let binding = managed
                .store
                .binding_for_chat(&run.chat_id, &run.bot_id, &run.source.project_id)
                .await
                .map_err(|error| CardFailure::Stop(classify_send_error(error)))?;
            if binding.status != "bound"
                || binding.thread_id.as_deref() != Some(&run.thread_id)
                || binding.creation_id != run.source.creation_id
                || binding.revision != run.source.binding_revision
            {
                return Err(CardFailure::Stop(attention(
                    "original card reply binding has been replaced or revoked",
                )));
            }
            state
                .reserve(action.clone())
                .map_err(CardFailure::Rejected)?;
            match managed
                .store
                .save_card_intent(state, &run.worker_id, &run.source)
                .await
            {
                Ok(crate::bots::storage::MarkOutcome::Applied) => {}
                Ok(crate::bots::storage::MarkOutcome::LostClaim) => {
                    return Err(CardFailure::Stop(InboundWorkOutcome::LostClaim));
                }
                Err(_) => {
                    return Err(CardFailure::Stop(attention(
                        "card intent persistence is unconfirmed; local recovery required",
                    )));
                }
            }
        }
        send_permit.start();
        let operation = state
            .last_operation
            .as_ref()
            .expect("reserved card intent")
            .clone();
        let cardkit = FeishuCardKit::new(self.inner.http.clone());
        // Once an intent is committed, the managed inbound owner waits for this
        // bounded HTTP operation and persists its actual result, even on stop.
        // Losing the lease drops this future, leaving Intent as an unknown fence.
        let result = match &action {
            CardAction::Create { text } => {
                cardkit.create(&token, text).await.map(Confirmed::Entity)
            }
            CardAction::Send {} => FeishuIm::new(self.inner.http.clone())
                .send_card(
                    &token,
                    &run.chat_id,
                    state.card_id.as_deref().expect("confirmed entity"),
                    &operation.uuid,
                )
                .await
                .map(|result| Confirmed::Message(result.message_id)),
            CardAction::Content { text, .. } => cardkit
                .content(
                    &token,
                    state.card_id.as_deref().expect("confirmed entity"),
                    text,
                    operation.sequence,
                    &operation.uuid,
                )
                .await
                .map(|()| Confirmed::Mutation),
            CardAction::Settings {
                streaming,
                lifecycle,
                ..
            } => cardkit
                .settings(
                    &token,
                    state.card_id.as_deref().expect("confirmed entity"),
                    CardSettings {
                        streaming: *streaming,
                        summary: lifecycle.summary(),
                        sequence: operation.sequence,
                        uuid: &operation.uuid,
                    },
                )
                .await
                .map(|()| Confirmed::Mutation),
        };
        let result = match result {
            Ok(confirmed) => {
                state.confirm_recovery(&action).map_err(|_| {
                    CardFailure::Stop(attention(
                        "card recovery confirmation conflicts with its durable phase",
                    ))
                })?;
                match confirmed {
                    Confirmed::Entity(card_id) => {
                        state.card_id = Some(card_id);
                        state.lifecycle = CardLifecycle::Created;
                    }
                    Confirmed::Message(message_id) => {
                        state.platform_message_id = Some(message_id);
                        state.lifecycle = CardLifecycle::Streaming;
                    }
                    Confirmed::Mutation => state.confirmed_sequence = operation.sequence,
                }
                match action {
                    CardAction::Create { text } => {
                        state.confirmed_content_hash = hash(text.as_bytes());
                        state.confirmed_text = text;
                    }
                    CardAction::Content {
                        text,
                        final_content,
                    } => {
                        let content_hash = hash(text.as_bytes());
                        state.final_content_hash = final_content.then(|| content_hash.clone());
                        state.confirmed_content_hash = content_hash;
                        state.confirmed_text = text;
                    }
                    CardAction::Settings {
                        streaming,
                        lifecycle,
                        ..
                    } => {
                        state.lifecycle = if streaming {
                            CardLifecycle::Streaming
                        } else {
                            lifecycle
                        };
                    }
                    CardAction::Send {} => {}
                }
                state
                    .last_operation
                    .as_mut()
                    .expect("reserved card intent")
                    .status = CardOperationStatus::Confirmed;
                Ok(())
            }
            Err(error) => {
                let unknown = error.acceptance_unknown();
                let operation = state.last_operation.as_mut().expect("reserved card intent");
                operation.status = if unknown {
                    CardOperationStatus::Unknown
                } else {
                    CardOperationStatus::Rejected
                };
                operation.diagnostic = Some(error.diagnostic());
                state.diagnostic = Some(error.diagnostic());
                if unknown {
                    state.lifecycle = CardLifecycle::NeedsAttention;
                    Err(CardFailure::Stop(attention(safe_failure(
                        "CardKit operation acceptance is unknown; automatic replay is disabled",
                        &error,
                    ))))
                } else {
                    if !matches!(error.platform_code(), Some("200850" | "300309"))
                        || state.recovery_used
                    {
                        state.lifecycle = CardLifecycle::NeedsAttention;
                    }
                    Err(CardFailure::Rejected(error))
                }
            }
        };
        self.persist_card(managed, run, state)
            .await
            .map_err(CardFailure::Stop)?;
        result
    }
}
