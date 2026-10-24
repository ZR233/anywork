//! Current-source capability proof. Model JSON, visible IDs and a current chat binding grant none.
use super::config::BotConfigFile;
use super::protocol::error::{FeishuError, FeishuErrorKind};
use super::send::SendSource;
use super::{BotInputRead, BotInteractionKind, BotInteractionRead, BotRuntime};
use pl_core::thread::input::InputState;
use pl_core::tool::opaque::CallContext;
use pl_protocol::InteractionStatus;

impl BotRuntime {
    pub(crate) async fn has_source_thread(&self, thread_id: &str) -> Result<bool, FeishuError> {
        let bots = self
            .inner
            .bots
            .lock()
            .await
            .values()
            .filter_map(|record| record.published.clone())
            .collect::<Vec<_>>();
        for bot in bots {
            if bot.store.has_source_thread(thread_id).await? {
                return Ok(true);
            }
        }
        Ok(false)
    }

    pub(super) async fn source_for_call(
        &self,
        context: &CallContext,
    ) -> Result<SendSource, FeishuError> {
        self.check_send_active(&context.cancellation)?;
        let runtime = self.studio_host().ok_or_else(|| {
            FeishuError::new(
                FeishuErrorKind::Unavailable,
                "Studio runtime is closed",
                true,
                None,
            )
        })?;
        let input_id = self
            .read_source_fact(
                &context.cancellation,
                "read current bot tool input",
                runtime.bot_call_input(context),
            )
            .await?
            .ok_or_else(|| denied("current tool input does not match durable Thread facts"))?;
        let bots = self
            .inner
            .bots
            .lock()
            .await
            .values()
            .filter_map(|record| record.published.clone())
            .collect::<Vec<_>>();
        let mut found = None;
        for bot in bots {
            self.check_send_active(&context.cancellation)?;
            let sources = bot
                .store
                .inbound_sources(&context.thread_id, &input_id)
                .await;
            self.check_send_active(&context.cancellation)?;
            for mut source in sources? {
                if source.creation_id != context.thread_id || source.thread_id != context.thread_id
                {
                    return Err(denied("frozen source belongs to a different Thread"));
                }
                if self
                    .canonical_source_reaches(&runtime, &source, &input_id, &context.cancellation)
                    .await?
                {
                    if found.is_some() {
                        return Err(denied("ambiguous bot source for current input"));
                    }
                    source.input_id = input_id.clone();
                    let current = bot.config.lock().await;
                    self.check_send_active(&context.cancellation)?;
                    authorize_source(&current, &source.chat_id, &source)?;
                    found = Some(source);
                }
            }
        }
        self.check_send_active(&context.cancellation)?;
        found.ok_or_else(|| denied("submit_bot_file requires this Turn's authorized bot input or its canonical interaction continuation; local input and mentioned IDs grant no authority"))
    }

    async fn read_source_fact<T>(
        &self,
        cancel: &tokio_util::sync::CancellationToken,
        context: &'static str,
        read: impl std::future::Future<Output = anyhow::Result<T>>,
    ) -> Result<T, FeishuError> {
        self.check_send_active(cancel)?;
        let result = tokio::select! {
            _ = cancel.cancelled() => return Err(FeishuError::cancelled()),
            _ = self.inner.reply_cancel.cancelled() => return Err(FeishuError::cancelled()),
            result = read => result,
        };
        self.check_send_active(cancel)?;
        result.map_err(|error| FeishuError::history_read(context, error))
    }

    async fn canonical_source_reaches(
        &self,
        runtime: &crate::studio::StudioRuntime,
        source: &SendSource,
        target: &str,
        cancel: &tokio_util::sync::CancellationToken,
    ) -> Result<bool, FeishuError> {
        let mut current = source.original_input_id.clone();
        let mut visited = std::collections::BTreeSet::new();
        for _ in 0..32 {
            self.check_send_active(cancel)?;
            if !visited.insert(current.clone()) {
                return Err(denied("canonical source continuation contains a cycle"));
            }
            let turn_id = match self
                .read_source_fact(
                    cancel,
                    "read canonical bot source input",
                    runtime.bot_input_fact(&source.thread_id, &current),
                )
                .await?
            {
                BotInputRead::Ready {
                    state: InputState::Consumed { turn_id, .. },
                    ..
                } => turn_id,
                BotInputRead::NotReady => {
                    return Err(source_not_ready());
                }
                BotInputRead::Ready { .. } | BotInputRead::Absent => {
                    return Ok(false);
                }
            };
            if current == target {
                return Ok(true);
            }
            let locals = super::reply::discover_timeline_interactions(
                runtime,
                &source.thread_id,
                &turn_id,
                cancel,
            )
            .await?;
            self.check_send_active(cancel)?;
            let mut next = None;
            for local in locals {
                match self
                    .read_source_fact(
                        cancel,
                        "read canonical bot interaction source",
                        runtime.bot_interaction_fact(&source.thread_id, &local),
                    )
                    .await?
                {
                    BotInteractionRead::Ready(fact)
                        if fact.kind == BotInteractionKind::UserInput
                            && fact.status == InteractionStatus::Resolved =>
                    {
                        if let Some(continuation) = fact.continuation_input
                            && next.replace(continuation).is_some()
                        {
                            return Err(denied("ambiguous canonical continuation"));
                        }
                    }
                    BotInteractionRead::NotReady => return Err(source_not_ready()),
                    BotInteractionRead::Ready(_) | BotInteractionRead::Absent => {}
                }
            }
            match next {
                Some(next) => current = next,
                None => return Ok(false),
            }
        }
        Err(denied("source continuation exceeds 32 canonical links"))
    }
}

pub(super) fn authorize_source(
    config: &BotConfigFile,
    chat_id: &str,
    source: &SendSource,
) -> Result<(), FeishuError> {
    if !config.enabled
        || config.id != source.bot_id
        || config.feishu().app_id != source.app_id
        || config.project_id != source.project_id
        || chat_id != source.chat_id
        || source.thread_id != source.creation_id
        || source.input_id.is_empty()
    {
        return Err(denied(
            "bot source identity is disabled, changed or no longer applicable",
        ));
    }
    let trusted = match source.chat_kind.as_str() {
        "direct" => config.feishu().trusted_open_ids.contains(&source.open_id),
        "group" => config.feishu().trusted_chat_ids.contains(&source.chat_id),
        _ => false,
    };
    if !trusted {
        return Err(denied("the original bot source trust has been revoked"));
    }
    Ok(())
}

fn denied(message: &str) -> FeishuError {
    FeishuError::new(FeishuErrorKind::Permission, message, false, None)
}

fn source_not_ready() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        "canonical source facts are not durable yet",
        true,
        None,
    )
}
