//! 输入提交入口：内容校验、持久资源准备与 core 的原子路由受理。

use anyhow::{Context, Result, bail};

use crate::studio::ThreadRecord;

use super::super::{
    StudioRuntime, StudioSubmitPromptOptions, StudioSubmitPromptRequest, StudioSubmitPromptResponse,
};
use super::{UserThreadAction, ensure_thread_not_archived, ensure_user_root_target};

/// How one product admission treats a Turn that is already running on the same Thread.
///
/// This is an explicit product decision, not a tuning flag: the desktop UI and explicit
/// interaction continuation keep replacing the current Turn, while a platform message identity
/// becomes its own queued input so two messages of the same conversation never interrupt or merge
/// each other.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum AdmissionMode {
    /// Explicit user submission: interrupt the running Turn and continue.
    InterruptAndContinue,
    /// Platform message identity: enqueue a separate input without interrupting the Turn.
    Queued,
}

fn ensure_submission_not_cancelled(
    cancel: Option<&tokio_util::sync::CancellationToken>,
) -> Result<()> {
    if cancel.is_some_and(tokio_util::sync::CancellationToken::is_cancelled) {
        return Err(pl_core::thread::ThreadError::Cancelled.into());
    }
    Ok(())
}

impl StudioRuntime {
    /// Atomically starts or interrupts and continues the canonical Thread.
    pub async fn submit_prompt_command(
        &self,
        thread_id: String,
        request: crate::SubmitPromptRequest,
    ) -> Result<StudioSubmitPromptResponse> {
        self.submit_prompt(StudioSubmitPromptRequest {
            thread_id,
            input: request.input,
            options: StudioSubmitPromptOptions {
                expected_model_route_revision: Some(request.expected_model_route_revision),
                ..StudioSubmitPromptOptions::default()
            },
        })
        .await
    }

    pub async fn submit_prompt(
        &self,
        request: StudioSubmitPromptRequest,
    ) -> Result<StudioSubmitPromptResponse> {
        self.submit_owned_prompt(request, AdmissionMode::InterruptAndContinue, None)
            .await
    }

    /// 非打断准入：平台消息作为独立输入排队，不中断同一 Thread 正在运行的 Turn。
    ///
    /// 与 [`Self::submit_prompt`] 共享全部内容校验、生命周期栅栏、正文身份、当前回执、route
    /// CAS、附件准备、预算与事件；只有最终的 core 准入不同——排队输入由 actor 串行消费，因此
    /// 同一会话的两条平台消息各自形成独立输入与 Turn，不会互相打断或合并。
    pub(crate) async fn submit_queued_prompt(
        &self,
        request: StudioSubmitPromptRequest,
        cancel: &tokio_util::sync::CancellationToken,
    ) -> Result<StudioSubmitPromptResponse> {
        self.submit_owned_prompt(request, AdmissionMode::Queued, Some(cancel))
            .await
    }

    async fn submit_owned_prompt(
        &self,
        request: StudioSubmitPromptRequest,
        mode: AdmissionMode,
        cancel: Option<&tokio_util::sync::CancellationToken>,
    ) -> Result<StudioSubmitPromptResponse> {
        validate_prompt_content(&request.input)?;
        let started = std::time::Instant::now();
        // Serialize turn registration with the shared shutdown admission fence.
        // Cancellation may stop admission, never abandon a started resource operation.
        let _lifecycle_guard = match cancel {
            Some(cancel) => tokio::select! {
                biased;
                _ = cancel.cancelled() => return Err(pl_core::thread::ThreadError::Cancelled.into()),
                guard = self.lifecycle_lock.lock() => guard,
            },
            None => self.lifecycle_lock.lock().await,
        };
        tracing::debug!(
            target: "prompt_submission",
            thread_id = request.thread_id,
            input_id = request.input.input_id,
            lifecycle_wait_us = started.elapsed().as_micros() as u64,
            "prompt lifecycle admission acquired"
        );
        ensure_submission_not_cancelled(cancel)?;
        let thread_record = self.read_owned_thread(&request.thread_id).await?;
        // The user-facing submission stops here for a child target: the trusted association proves
        // the parent, so this runs before the owner is activated, before attachment drafts resolve
        // and before any route or prompt work. Only the parent agent schedules child work.
        ensure_user_root_target(&thread_record, UserThreadAction::Submit)?;
        self.submit_owned_prompt_with_admission(request, thread_record, mode, cancel)
            .await
    }

    pub(in crate::studio::runtime) async fn submit_prompt_for_owned_thread_with_lifecycle_lock(
        &self,
        request: StudioSubmitPromptRequest,
        thread_record: ThreadRecord,
    ) -> Result<StudioSubmitPromptResponse> {
        self.submit_owned_prompt_with_admission(
            request,
            thread_record,
            AdmissionMode::InterruptAndContinue,
            None,
        )
        .await
    }

    fn submit_owned_prompt_with_admission<'a>(
        &'a self,
        request: StudioSubmitPromptRequest,
        thread_record: ThreadRecord,
        mode: AdmissionMode,
        cancel: Option<&'a tokio_util::sync::CancellationToken>,
    ) -> impl std::future::Future<Output = Result<StudioSubmitPromptResponse>> + Send + 'a {
        // First input, ordinary submission and queued input share this admission state. Allocate
        // it before returning the future so callers do not inline its activation and snapshot
        // state through every startup layer. Polling, cancellation and the lifecycle lock remain
        // owned by the original caller; this does not spawn another task.
        Box::pin(async move {
            let StudioSubmitPromptRequest {
                thread_id,
                input,
                options,
            } = request;
            validate_prompt_content(&input)?;
            ensure_thread_not_archived(&thread_record, UserThreadAction::Submit)?;
            let started = std::time::Instant::now();
            let (thread_record, thread, _agent_operation) = self
                .prepare_prompt_admission(&thread_id, UserThreadAction::Submit, &input.input_id)
                .await?;
            // Look up the canonical receipt before resolving drafts, which admission may already have consumed.
            let snapshot = thread.snapshot();
            if let Some(previous) = snapshot
                .inputs
                .iter()
                .find(|record| record.input.id == input.input_id)
            {
                #[derive(serde::Deserialize)]
                struct AcceptedPrompt {
                    request: crate::StudioPromptInput,
                    presentation: crate::MessagePresentation,
                }
                let accepted: AcceptedPrompt =
                    serde_json::from_str(previous.input.payload.content())?;
                anyhow::ensure!(
                    accepted.request == input && accepted.presentation == options.presentation,
                    "input identity conflicts with an accepted prompt"
                );
                return Ok(StudioSubmitPromptResponse {
                    thread_id,
                    input_id: previous.input.id.clone(),
                    cursor: previous.accepted_sequence,
                });
            }
            drop(snapshot);
            // The caller's frozen route is a CAS against its canonical extension,
            // not a Thread revision or the current mode default. Both route writes
            // and input admission hold lifecycle_lock, so it cannot change between
            // this check and the core admission. An already accepted input above
            // keeps its original receipt even after a later route update.
            if let Some(expected) = options.expected_model_route_revision {
                let state = thread.snapshot();
                let (record, _) = crate::studio::model_route::route_record(
                    &state,
                    thread_record.parent_thread_id.is_some(),
                )?
                .context("Thread has no saved model route")?;
                if record.revision != expected {
                    return Err(crate::ConfigRuntimeError::StaleRevision {
                        expected,
                        actual: record.revision,
                    }
                    .into());
                }
            }
            // Validate the caller's observed revision before applying the bot's next-input
            // configuration; this admission's own update is not a stale desktop request.
            self.reconcile_bot_model(&thread_id, &thread).await?;
            let original_request = input.clone();
            let crate::StudioPromptInput {
                input_id,
                text: prompt,
                attachment_draft_ids,
            } = input;
            anyhow::ensure!(
                thread_record.id == thread_id,
                "prompt Thread does not match its canonical owner"
            );
            let drafts = self
                .attachment_drafts
                .resolve(&attachment_draft_ids)
                .await?;
            let route = self
                .require_session(&thread_id)?
                .prepare_native_input(&thread_id, &thread)
                .await?;
            self.attachment_drafts
                .validate_for_model(&route.model, &drafts)?;
            ensure_submission_not_cancelled(cancel)?;
            let attachments = self
                .store
                .promote_attachment_drafts(&thread_id, &drafts)
                .await?;
            let mut context = Vec::new();
            if !prompt.is_empty() {
                context.push(pl_core::context::ContextContent::Text {
                    text: prompt.clone().into(),
                });
            }
            for attachment in &attachments {
                let reference = self.store.retain_attachment_resource(attachment).await?;
                if let Some(filename) = &attachment.filename {
                    context.push(pl_core::context::ContextContent::Text {
                        text: format!("Attachment: {filename}").into(),
                    });
                }
                let modality = match attachment.modality {
                    crate::StudioAttachmentModality::Image => crate::AttachmentModality::Image,
                    crate::StudioAttachmentModality::Video => crate::AttachmentModality::Video,
                    crate::StudioAttachmentModality::File => crate::AttachmentModality::File,
                };
                context.push(pl_model::runtime::attachment_content(reference, modality)?);
            }
            #[derive(serde::Serialize)]
            #[serde(rename_all = "camelCase")]
            struct PromptPayload<'a> {
                text: &'a str,
                request: &'a crate::StudioPromptInput,
                presentation: crate::MessagePresentation,
                attachments: &'a [crate::studio::AttachmentRecord],
            }
            let payload = pl_core::context::OpaquePayload::new(
                "pl.studio.prompt",
                1,
                serde_json::to_string(&PromptPayload {
                    text: &prompt,
                    request: &original_request,
                    presentation: options.presentation,
                    attachments: &attachments,
                })?,
            )?;
            crate::studio::model_binding::validate_media(&context, &route.model)?;
            if let Some(suggestions) =
                self.thread_factory
                    .skill_suggestions(&thread_id, &prompt, &thread.snapshot())
            {
                context.push(pl_core::context::ContextContent::Text {
                    text: suggestions.into(),
                });
            }
            // Resource bytes are retained before admission; failures never delete user drafts or replay effects.
            self.agent_facility
                .product_events
                .record_attachments(attachments.clone())
                .await?;
            tracing::debug!(
                target: "prompt_submission",
                thread_id,
                input_id,
                preparation_elapsed_us = started.elapsed().as_micros() as u64,
                "prompt resources prepared"
            );
            let admission_started = std::time::Instant::now();
            let thread_input = pl_core::thread::input::ThreadInput {
                purpose: pl_core::thread::input::InputPurpose::Message,
                id: input_id,
                payload,
                context,
            };
            let driver = pl_core::thread::input::InputDriverOptions {
                max_model_steps: submission_step_limit(
                    options.max_model_steps,
                    thread_record.parent_thread_id.is_none(),
                ),
            };
            // The only semantic difference between the product admissions. `input_and_run` lets the
            // actor own the queued input and consume it after the current Turn, while
            // `input_and_continue` replaces the running Turn.
            // Resource preparation has reached its real terminal result. A cancelled
            // producer may stop here without abandoning I/O or starting a new input.
            // Once the actor request below starts, its acceptance is always awaited.
            ensure_submission_not_cancelled(cancel)?;
            let accepted = match mode {
                AdmissionMode::InterruptAndContinue => {
                    thread
                        .submit_input_and_continue(thread_input, driver)
                        .await?
                }
                AdmissionMode::Queued => thread.submit_input_and_run(thread_input, driver).await?,
            };
            tracing::debug!(
                target: "prompt_submission",
                thread_id,
                input_id = accepted.input.id,
                source_effect_seq = accepted.accepted_sequence,
                core_admission_us = admission_started.elapsed().as_micros() as u64,
                admission_elapsed_us = started.elapsed().as_micros() as u64,
                "prompt accepted"
            );
            // 用户消息已成功受理（含排队输入）：目录立即记录最近用户消息时间；后续模型、
            // 工具或保存失败都不回退该事实，拒绝的提交在上方 `?` 处直接返回、不记录。
            self.agent_facility
                .product_events
                .record_user_message(&thread_id, crate::studio::unix_seconds());
            // Session resources were retained before admission. Staging remains
            // immutable and reusable while a newer Client draft still references
            // these ids; only an explicit last-owner release removes staging.
            self.residency.touch(&thread_id).await;
            Ok(StudioSubmitPromptResponse {
                thread_id,
                input_id: accepted.input.id,
                cursor: accepted.accepted_sequence,
            })
        })
    }

    pub(in crate::studio::runtime) async fn ensure_prompt_runtime_ready(&self) -> Result<()> {
        if !self.runtime_state.snapshot().state.is_ready() {
            bail!("Studio runtime is not ready");
        }
        Ok(())
    }
}

fn submission_step_limit(
    requested: Option<std::num::NonZeroU32>,
    is_root: bool,
) -> pl_core::thread::ModelStepLimit {
    use pl_core::thread::ModelStepLimit;
    let policy = if is_root {
        ModelStepLimit::Unlimited
    } else {
        crate::studio::thread_factory::StudioThreadFactory::CHILD_MODEL_STEP_LIMIT
    };
    match (policy, requested) {
        (policy, None) => policy,
        (ModelStepLimit::Unlimited, Some(limit)) => ModelStepLimit::Limited(limit),
        (ModelStepLimit::Limited(policy), Some(limit)) => {
            ModelStepLimit::Limited(policy.min(limit))
        }
    }
}

pub(in crate::studio::runtime) fn validate_prompt_content(
    input: &crate::StudioPromptInput,
) -> Result<()> {
    anyhow::ensure!(!input.input_id.trim().is_empty(), "inputId is empty");
    if input.text.trim().is_empty() && input.attachment_draft_ids.is_empty() {
        bail!("prompt is empty");
    }
    Ok(())
}

#[cfg(test)]
mod budget_tests {
    use super::submission_step_limit;
    use pl_core::thread::ModelStepLimit;
    use std::num::NonZeroU32;

    #[test]
    fn explicit_submission_budget_tightens_without_loosening_child_policy() {
        let short = NonZeroU32::new(3).unwrap();
        let large = NonZeroU32::new(1000).unwrap();
        let child_policy =
            crate::studio::thread_factory::StudioThreadFactory::CHILD_MODEL_STEP_LIMIT;
        assert_eq!(submission_step_limit(None, true), ModelStepLimit::Unlimited);
        assert_eq!(submission_step_limit(None, false), child_policy);
        assert_eq!(
            submission_step_limit(Some(short), true),
            ModelStepLimit::Limited(short)
        );
        assert_eq!(
            submission_step_limit(Some(short), false),
            ModelStepLimit::Limited(short)
        );
        assert_eq!(submission_step_limit(Some(large), false), child_policy);
    }
}
