//! One transport attempt, progress observation and canonical event collection.
use super::AttemptDispatch;
use super::timing::InferenceTimer;
use crate::completion::{
    CompletionFailure, CompletionRequest, CompletionResponse, CompletionTraceContext,
};
use crate::runtime::invocation_context::InvocationPurpose;
use crate::runtime::{ModelInvocationContext, ModelRuntime};
use crate::stream::{CompletionEventStream, StreamCollectContext};
use futures::StreamExt;
use pl_protocol::PureError;
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};

pub(super) struct StreamAttempt {
    pub(super) result: std::result::Result<CompletionResponse, CompletionFailure>,
    pub(super) replay_safe: bool,
    pub(super) started: bool,
}

impl StreamAttempt {
    fn unsent(error: CompletionFailure) -> Self {
        Self {
            result: Err(error),
            replay_safe: false,
            started: false,
        }
    }
}

pub(super) struct StreamAttemptExecution<'a> {
    pub trace: Option<CompletionTraceContext>,
    pub inference_timer: &'a InferenceTimer,
    pub current: Option<&'a mut crate::runtime::current::CurrentProducer>,
    pub generation: u32,
    pub pending_reconnect: Option<(
        pl_core::model::ModelConnectionFact,
        std::time::Instant,
        &'a mut bool,
    )>,
}

impl ModelRuntime {
    pub(super) async fn run_stream_attempt(
        &self,
        request: CompletionRequest,
        context: &ModelInvocationContext,
        execution: StreamAttemptExecution<'_>,
    ) -> StreamAttempt {
        let StreamAttemptExecution {
            trace,
            inference_timer,
            mut current,
            generation,
            pending_reconnect,
        } = execution;
        if context
            .cancellation
            .as_ref()
            .is_some_and(|token| token.is_cancelled())
        {
            return StreamAttempt::unsent(CompletionFailure::cancelled(
                PureError::LlmError("model invocation cancelled before sending".into()),
                Box::default(),
            ));
        }
        let has_hosted_tools = request.tools.iter().any(|tool| match tool {
            crate::completion::ToolSpec::Function { .. }
            | crate::completion::ToolSpec::Custom { .. } => false,
            crate::completion::ToolSpec::ProgrammaticToolCalling
            | crate::completion::ToolSpec::WebSearch { .. } => true,
        });
        let is_compaction = matches!(&context.purpose, InvocationPurpose::RemoteCompaction { .. });
        let (body, mut model_observation) = match self
            .prompt_cache_key(context)
            .and_then(|key| self.prepare_request_body(request, key.as_deref(), &context.purpose))
        {
            Ok(prepared) => prepared,
            Err(error) => return StreamAttempt::unsent(error.into()),
        };
        let dispatch = AttemptDispatch::new(context.progress.as_ref());
        let opening = self.stream_events(
            body,
            context.session.clone(),
            trace.clone(),
            &context.purpose,
            context
                .cancellation
                .clone()
                .expect("complete installs cancellation"),
            &dispatch,
        );
        tokio::pin!(opening);
        let mut accumulator =
            crate::stream::StreamCompletionAccumulator::new(Some(model_observation.clone()));
        let open = async {
            match context.cancellation.as_ref() {
                Some(token) => tokio::select! {
                    biased;
                    _ = token.cancelled() => {
                        inference_timer.mark_terminal();
                        (Err(PureError::LlmError("model invocation cancelled".into())), true)
                    },
                    result = &mut opening => (result, false),
                },
                None => (opening.await, false),
            }
        };
        let (opened, opening_cancelled) = if let Some(current) = current.as_deref_mut() {
            current.wait(open, None).await
        } else {
            open.await
        };
        let started = dispatch.started();
        if started && let Some(current) = current.as_deref_mut() {
            current.begin_generation(generation);
        }
        match opened {
            Ok(opened) => {
                model_observation.sent_model = opened.sent_model;
                accumulator.set_model_observation(model_observation.clone());
                let replay_unsafe = Arc::new(AtomicBool::new(has_hosted_tools));
                let tracked_stream: CompletionEventStream = opened
                    .events
                    .map({
                        let replay_unsafe = Arc::clone(&replay_unsafe);
                        let inference_timer = inference_timer.clone();
                        let mut progress =
                            crate::runtime::thread_model::progress::ProgressProjection::new(
                                context.progress.clone(),
                            );
                        move |event| {
                            if let Ok(event) = &event
                                && ((is_compaction
                                    && matches!(
                                        event,
                                        crate::stream::event::ModelStreamEvent::NativeContext { .. }
                                    ))
                                    || matches!(
                                        event,
                                        crate::stream::event::ModelStreamEvent::Completed { .. }
                                    ))
                            {
                                replay_unsafe.store(true, Ordering::Release);
                            }
                            if let Ok(event) = &event {
                                inference_timer.observe(event);
                                // 终态事件先撤销 live 用量，再考虑发布耗时：失败尝试绝不能
                                // 先发布一个「失败前的词元 + 失败时钟」的完整 pair。
                                progress.observe(event)?;
                                progress.observe_response_millis(inference_timer.response_millis());
                            } else {
                                // 传输层直接以错误结束这次流，没有经过 Failed 事件。
                                inference_timer.mark_terminal();
                                progress.close_live_usage();
                            }
                            event
                        }
                    })
                    .boxed();
                let on_stream_end = || inference_timer.mark_terminal();
                let result = crate::stream::collect_completion_event_stream_with_idle_timeout(
                    tracked_stream,
                    StreamCollectContext {
                        observer: context.observer.as_ref(),
                        trace,
                        cancellation: context.cancellation.clone(),
                        model_observation: Some(model_observation),
                        on_stream_end: &on_stream_end,
                        members: (context.billing_purpose != "compaction")
                            .then(|| context.members.clone())
                            .flatten(),
                        pending_reconnect,
                        generation: context
                            .progress
                            .as_ref()
                            .map_or(0, |p| p.latest().observation().generation),
                    },
                    opened.idle_timeout,
                    Some(accumulator),
                    current.as_deref_mut(),
                )
                .await;
                StreamAttempt {
                    result,
                    replay_safe: !replay_unsafe.load(Ordering::Acquire),
                    started,
                }
            }
            Err(error) => {
                inference_timer.mark_terminal();
                accumulator.fail_attempt(&error);
                if started && let Some(current) = current {
                    current.freeze(&accumulator);
                }
                let cancelled = opening_cancelled
                    || context
                        .cancellation
                        .as_ref()
                        .is_some_and(|token| token.is_cancelled());
                let failure = if cancelled {
                    CompletionFailure::cancelled(error, Box::default())
                } else {
                    error.into()
                };
                StreamAttempt {
                    result: Err(failure.with_model_observation(model_observation)),
                    replay_safe: !cancelled && (!has_hosted_tools || !dispatch.submitted()),
                    started,
                }
            }
        }
    }
}
