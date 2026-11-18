//! One transport attempt, progress observation and canonical event collection.
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

impl ModelRuntime {
    pub(super) async fn run_stream_attempt(
        &self,
        request: CompletionRequest,
        context: &ModelInvocationContext,
        trace: Option<CompletionTraceContext>,
        inference_timer: &InferenceTimer,
        mut current: Option<&mut crate::runtime::current::CurrentProducer>,
        generation: u32,
    ) -> (
        std::result::Result<CompletionResponse, CompletionFailure>,
        bool,
    ) {
        if let Some(current) = current.as_deref_mut() {
            current.begin_generation(generation);
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
            Err(error) => return (Err(error.into()), true),
        };
        let opening = self.stream_events(
            body,
            context.session.clone(),
            trace.clone(),
            &context.purpose,
        );
        tokio::pin!(opening);
        let mut accumulator =
            crate::stream::StreamCompletionAccumulator::new(Some(model_observation.clone()));
        let open = async {
            match context.cancellation.as_ref() {
                Some(token) => tokio::select! {
                    result = &mut opening => (result, false),
                    _ = token.cancelled() => {
                        inference_timer.mark_terminal();
                        (Err(PureError::LlmError("model invocation cancelled".into())), true)
                    },
                },
                None => (opening.await, false),
            }
        };
        let (opened, opening_cancelled) = if let Some(current) = current.as_deref_mut() {
            current.wait(open, Some(&accumulator)).await
        } else {
            open.await
        };
        match opened {
            Ok(opened) => {
                model_observation.sent_model = opened.sent_model;
                accumulator.set_model_observation(model_observation.clone());
                let replay_unsafe = Arc::new(AtomicBool::new(false));
                let tracked_stream: CompletionEventStream = opened
                    .events
                    .map({
                        let replay_unsafe = Arc::clone(&replay_unsafe);
                        let inference_timer = inference_timer.clone();
                        let mut progress = crate::runtime::thread_model::progress::ProgressProjection::new(context.progress.clone());
                        move |event| {
                            if let Ok(event) = &event
                                && (has_hosted_tools
                                    || (is_compaction && matches!(event,
                                        crate::stream::event::ModelStreamEvent::ResponsesContextItem { .. }))
                                    || matches!(event,
                                    crate::stream::event::ModelStreamEvent::Usage(_)
                                    | crate::stream::event::ModelStreamEvent::Completed { .. }))
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
                        members: context.members.clone(),
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
                let retry_allowed = !replay_unsafe.load(Ordering::Acquire);
                (result, retry_allowed)
            }
            Err(error) => {
                inference_timer.mark_terminal();
                accumulator.fail_attempt(&error);
                if let Some(current) = current {
                    current.freeze(&accumulator);
                }
                if opening_cancelled {
                    return (
                        Err(CompletionFailure::cancelled(error, Box::default())
                            .with_model_observation(model_observation)),
                        false,
                    );
                }
                (
                    Err(CompletionFailure::from(error).with_model_observation(model_observation)),
                    true,
                )
            }
        }
    }
}
