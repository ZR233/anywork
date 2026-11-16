//! 流事件累积器：把 canonical `ModelStreamEvent` 序列累积为 `CompletionResponse`。
//!
//! 累积器同时驱动 trace 投影（`TraceProjection`）并把投影事件发布到宿主
//! `AgentEventSender`；生命周期合法性与工具调用增量分别由 `lifecycle` 与
//! `tool_stream` 子状态机保证。

use crate::runtime::model_part_identity::{
    PartKey, observation, observed_part_kind, part_key, provider_observation, text_channel,
};
use pl_core::model::{AggregateChannel, ObservedItemKind, ObservedPartIdentity, ObservedPartKind};
use std::collections::HashMap;
use std::sync::Arc;

use pl_protocol::trace::{AgentEvent, AgentEventSender, TraceEventSink, TraceTextChannel};
use pl_protocol::{
    InferenceModelObservation, InferenceOrchestrationMetrics, PureError, ResponsesContextItem,
    ResponsesContextItemKind, Result, ToolCallCaller, UsageReport,
};

use crate::completion::{
    CompletionPresentationItem, CompletionPresentationPart, CompletionResponse,
    CompletionTraceContext, ToolCall,
};

use super::current::{
    ModelCallIdentity, ModelStreamBlock, ModelStreamContentPart, ModelStreamCurrent,
    ModelStreamCurrentState, ModelStreamMember,
};
use super::event::{
    ModelBlockContent, ModelBlockField, ModelBlockKind, ModelStreamEvent, ToolInputDeltaPayload,
    WebSearchAction,
};
use super::lifecycle::{self, StreamLifecycle};
use super::state::{CompletedStream, FailedStream, StreamAccumulatorState};
use super::tool_stream::{self, ToolStream};
use super::trace_projection::TraceProjection;
use crate::completion::CompletionPresentationPartKind;

use super::MAX_COMPLETION_OUTPUT_BYTES as MAX_OUTPUT_BYTES;

pub(crate) struct StreamCompletionAccumulator {
    content_parts: Vec<ModelStreamContentPart>,
    content_indexes: HashMap<String, usize>,
    blocks: Vec<ModelStreamBlock>,
    /// Bounded shallow block relationships; native bodies remain owned/charged by replay.
    block_bytes: usize,
    tool_calls: Vec<ToolCall>,
    tool_call_callers: HashMap<String, ToolCallCaller>,
    responses_context_items: Vec<ResponsesContextItem>,
    replay: super::replay::ReplayCollector,
    presentation_items: Vec<CompletionPresentationItem>,
    presentation_indexes: HashMap<String, usize>,
    presentation_bytes: usize,
    completed_member: Option<(usize, crate::runtime::ModelMemberState)>,
    presentation_states: HashMap<String, crate::runtime::ModelMemberState>,
    started_members: std::collections::BTreeMap<PartKey, StartedPart>,
    pending_starts: Vec<ObservedPartIdentity>,
    pending_content_available: Vec<ObservedPartIdentity>,
    /// Only identities still owned by the pending handoff queue consume this charge.
    pending_content_available_bytes: usize,
    text_output_bytes: usize,
    /// Charged high-water of each tool call's argument bytes, keyed by the accumulator identity the
    /// stream resolves an event to.
    ///
    /// Tool arguments join the same `MAX_OUTPUT_BYTES` domain as text and reasoning, so one provider
    /// response cannot accumulate unbounded text *and* unbounded tool input. The high-water is kept
    /// per call rather than recomputed from the stream: an equal-length `completed` that re-sends
    /// the arguments must not charge a second time, and a later append after a shorter replacement
    /// must not be under-charged because the resident body shrank.
    tool_output_bytes: HashMap<String, usize>,
    tool_stream: ToolStream,
    lifecycle: StreamLifecycle,
    final_usage: Option<UsageReport>,
    response_id: Option<String>,
    model_observation: Option<InferenceModelObservation>,
    reported_model_is_terminal: bool,
    state: StreamAccumulatorState,
    trace: Option<TraceProjection>,
}

struct StartedPart {
    identity: ObservedPartIdentity,
    content_available: bool,
}

impl StreamCompletionAccumulator {
    /// Capture at a normalized-event safe point, before any `finish`/`take_*` handoff.
    /// The supplied attempt belongs to Core; the generation distinguishes transparent retries.
    pub(crate) fn current(&self, attempt_id: &str, generation: u32) -> ModelStreamCurrent {
        let tool_inputs = self.tool_stream.current(attempt_id);
        let mut call_bindings = self
            .tool_calls
            .iter()
            .map(|call| ModelCallIdentity::new(attempt_id, &call.call_id, &call.id))
            .collect::<Vec<_>>();
        for input in &tool_inputs {
            let binding = ModelCallIdentity::new(
                attempt_id,
                input.provider_call_id.as_deref().unwrap_or(&input.item_id),
                &input.item_id,
            );
            if !call_bindings.iter().any(|old| old == &binding) {
                call_bindings.push(binding);
            }
        }
        ModelStreamCurrent {
            attempt_id: attempt_id.into(),
            generation,
            previous_generations: Vec::new(),
            state: match &self.state {
                StreamAccumulatorState::Open(_) => ModelStreamCurrentState::Open,
                StreamAccumulatorState::Completed(_) => ModelStreamCurrentState::Completed,
                StreamAccumulatorState::Failed(failed) => ModelStreamCurrentState::Failed {
                    message: failed.message().into(),
                },
            },
            response_id: self.response_id.clone(),
            model_observation: self.model_observation.clone(),
            reported_model_is_terminal: self.reported_model_is_terminal,
            content_parts: self.content_parts.clone(),
            blocks: self
                .blocks
                .iter()
                .map(|block| {
                    let mut saved = block.clone();
                    if saved.provider_metadata.is_none() {
                        saved.provider_metadata = block
                            .provider_item_id
                            .as_deref()
                            .and_then(|id| self.replay.native_item(id))
                            .cloned();
                    }
                    saved
                })
                .collect(),
            reasoning_summary_parts: self
                .reasoning_parts(CompletionPresentationPartKind::SummaryText),
            raw_reasoning_parts: self
                .reasoning_parts(CompletionPresentationPartKind::ReasoningText),
            tool_inputs,
            tool_calls: self.tool_calls.clone(),
            tool_call_callers: self
                .tool_call_callers
                .iter()
                .map(|(id, caller)| (id.clone(), caller.clone()))
                .collect(),
            call_bindings,
            responses_context_items: self.responses_context_items.clone(),
            replay: self.replay.current(),
            presentation_items: self.presentation_items.clone(),
            members: self
                .started_members
                .values()
                .map(|part| ModelStreamMember {
                    identity: part.identity.clone(),
                    content_available: part.content_available,
                })
                .collect(),
            presentation_states: self
                .presentation_states
                .iter()
                .map(|(id, state)| (id.clone(), *state))
                .collect(),
            final_usage: self.final_usage.clone(),
            usage_is_terminal: matches!(self.state, StreamAccumulatorState::Completed(_)),
        }
    }

    pub(crate) fn with_model_observation(
        trace: Option<CompletionTraceContext>,
        trace_sink: Option<Arc<dyn TraceEventSink>>,
        model_observation: Option<InferenceModelObservation>,
    ) -> Self {
        Self {
            content_parts: Vec::new(),
            content_indexes: HashMap::new(),
            blocks: Vec::new(),
            block_bytes: 0,
            tool_calls: Vec::new(),
            tool_call_callers: HashMap::new(),
            responses_context_items: Vec::new(),
            replay: Default::default(),
            presentation_items: Vec::new(),
            presentation_indexes: HashMap::new(),
            presentation_bytes: 0,
            completed_member: None,
            presentation_states: HashMap::new(),
            started_members: Default::default(),
            pending_starts: Vec::new(),
            pending_content_available: Vec::new(),
            pending_content_available_bytes: 0,
            text_output_bytes: 0,
            tool_output_bytes: HashMap::new(),
            tool_stream: ToolStream::new(),
            lifecycle: StreamLifecycle::new(),
            final_usage: None,
            response_id: None,
            model_observation,
            reported_model_is_terminal: false,
            state: StreamAccumulatorState::open(),
            trace: trace.map(|trace| TraceProjection::with_sink(trace, trace_sink)),
        }
    }

    pub(crate) fn set_model_observation(&mut self, observation: InferenceModelObservation) {
        self.model_observation = Some(observation);
    }

    #[cfg(test)]
    pub(crate) fn apply(
        &mut self,
        stream_event: ModelStreamEvent,
        event_tx: &AgentEventSender,
    ) -> Result<()> {
        for event in self.normalize(stream_event)? {
            self.apply_normalized(event, event_tx)?;
        }
        Ok(())
    }

    pub(crate) fn normalize(
        &mut self,
        stream_event: ModelStreamEvent,
    ) -> Result<Vec<ModelStreamEvent>> {
        match &self.state {
            StreamAccumulatorState::Open(_) => {}
            StreamAccumulatorState::Completed(_) => {
                return Err(PureError::LlmError(
                    "provider stream emitted event after completion".to_string(),
                ));
            }
            StreamAccumulatorState::Failed(failed) => {
                return Err(PureError::LlmError(format!(
                    "provider stream emitted event after failure: {}",
                    failed.message()
                )));
            }
        }
        self.lifecycle.normalize(stream_event)
    }

    pub(crate) fn apply_normalized(
        &mut self,
        stream_event: ModelStreamEvent,
        event_tx: &AgentEventSender,
    ) -> Result<()> {
        let starts = self.started_identities(&stream_event)?;
        let content_available = self.content_available_identities(&stream_event)?;
        self.record_block_state(&stream_event)?;
        match stream_event {
            ModelStreamEvent::BlockOpened {
                id,
                kind: ModelBlockKind::Text { channel },
                ..
            } => {
                self.record_text_started(&id, channel, event_tx);
            }
            ModelStreamEvent::BlockOpened {
                id,
                kind: ModelBlockKind::ReasoningSummary,
                ..
            } => {
                let _ = id;
            }
            ModelStreamEvent::BlockDelta {
                id,
                kind: ModelBlockKind::Text { channel },
                field: ModelBlockField::Text,
                delta,
                provider,
                ..
            } => {
                let identity = observation(ModelBlockKind::Text { channel }, provider.as_ref())?.1;
                self.append_content_part(
                    &format!("text:{}:{id}", channel.as_str()),
                    &id,
                    CompletionPresentationPartKind::OutputText,
                    identity,
                    provider.as_ref().map_or(0, |part| part.content_index),
                    &delta,
                )?;
                self.record_text_delta(&id, delta, event_tx, channel);
            }
            ModelStreamEvent::BlockDelta {
                id,
                kind: ModelBlockKind::ReasoningSummary,
                field: ModelBlockField::ReasoningSummary,
                delta,
                section_index,
                provider,
                ..
            } => {
                let identity = observation(ModelBlockKind::ReasoningSummary, provider.as_ref())?.1;
                // The provider part identity is authoritative. `section_index` also serves trace
                // grouping, and must not create a second, contradictory persisted identity.
                let index = provider
                    .as_ref()
                    .map_or(section_index.unwrap_or_default(), |part| part.content_index);
                self.append_content_part(
                    &format!("summary:{id}:{index}"),
                    &id,
                    CompletionPresentationPartKind::SummaryText,
                    identity,
                    index,
                    &delta,
                )?;
                self.record_thinking_delta(&id, section_index.unwrap_or_default(), delta, event_tx);
            }
            ModelStreamEvent::BlockDelta {
                kind: ModelBlockKind::Text { .. },
                ..
            }
            | ModelStreamEvent::BlockDelta {
                kind: ModelBlockKind::ReasoningSummary,
                ..
            } => {}
            ModelStreamEvent::BlockClosed {
                id,
                kind: ModelBlockKind::Text { channel },
                authoritative_content,
                provider,
                ..
            } => {
                let authoritative_text = match authoritative_content {
                    Some(ModelBlockContent::Text(text)) => Some(text),
                    Some(ModelBlockContent::ReasoningSummary(_)) | None => None,
                };
                if let Some(text) = authoritative_text.as_deref() {
                    let identity =
                        observation(ModelBlockKind::Text { channel }, provider.as_ref())?.1;
                    self.complete_content_part(
                        &format!("text:{}:{id}", channel.as_str()),
                        &id,
                        CompletionPresentationPartKind::OutputText,
                        identity,
                        provider.as_ref().map_or(0, |part| part.content_index),
                        text,
                    )?;
                }
                self.record_text_completed(&id, channel, authoritative_text, event_tx);
            }
            ModelStreamEvent::BlockClosed {
                id,
                kind: ModelBlockKind::ReasoningSummary,
                authoritative_content,
                provider,
                ..
            } => {
                let authoritative_summary =
                    if let Some(ModelBlockContent::ReasoningSummary(summary)) =
                        authoritative_content
                    {
                        let old = self
                            .content_parts
                            .iter()
                            .filter(|part| {
                                part.block_id == id
                                    && part.kind == CompletionPresentationPartKind::SummaryText
                            })
                            .map(|part| part.text.len())
                            .sum();
                        let new = summary.iter().map(String::len).sum();
                        self.charge_text_output(old, new)?;
                        // Replace only this reasoning member, never a previously completed member.
                        self.remove_summary_parts(&id);
                        for (index, text) in summary.iter().enumerate() {
                            let mut identity =
                                observation(ModelBlockKind::ReasoningSummary, provider.as_ref())?.1;
                            if let ObservedPartIdentity::Provider(part) = &mut identity {
                                part.content_index = index as u32;
                            }
                            let key = format!("summary:{id}:{index}");
                            let slot = self.content_part_slot(
                                &key,
                                &id,
                                CompletionPresentationPartKind::SummaryText,
                                identity,
                                index as u32,
                            );
                            self.content_parts[slot].text = text.clone();
                        }
                        Some(summary)
                    } else {
                        None
                    };
                self.record_thinking_completed(&id, authoritative_summary, event_tx);
            }
            ModelStreamEvent::ReasoningRawDelta {
                id,
                content_index,
                delta,
                provider,
            } => {
                let identity = match provider.as_ref() {
                    Some(part) => {
                        provider_observation(
                            &part.item_id,
                            ObservedItemKind::Reasoning,
                            ObservedPartKind::ReasoningText,
                            part.content_index,
                        )
                        .1
                    }
                    None => ObservedPartIdentity::Aggregate {
                        channel: AggregateChannel::Reasoning,
                    },
                };
                self.append_content_part(
                    &format!("raw:{id}:{content_index}"),
                    &id,
                    CompletionPresentationPartKind::ReasoningText,
                    identity,
                    content_index,
                    &delta,
                )?;
                self.record_reasoning_content_delta(&id, content_index, delta, event_tx);
            }
            ModelStreamEvent::ToolInputStarted {
                stream_id,
                item_id,
                call_id,
                name,
                payload_kind,
            } => {
                // A start carries no argument bytes (its payload kind only names the shape), so it
                // reserves the identity but nothing is charged until the first real delta arrives.
                let snapshot = self.tool_stream.start_input(
                    stream_id.as_ref(),
                    item_id,
                    call_id.as_ref(),
                    name,
                    lifecycle::tool_start_payload(payload_kind),
                );
                self.record_tool_started(&snapshot.tool, event_tx);
            }
            ModelStreamEvent::ToolInputDelta {
                stream_id,
                item_id,
                call_id,
                name,
                payload_delta,
            } => {
                // Charge the incoming argument bytes against the same output domain as text and
                // reasoning *before* they are appended, so a response that overruns the domain is
                // refused with exactly the arguments already accepted instead of after copying the
                // new chunk in. The model stream path already charged the live reservation first;
                // this is the collector's own ceiling for a caller driving it without that sender.
                let key =
                    self.tool_stream
                        .resolved_key(stream_id.as_ref(), call_id.as_ref(), &item_id);
                let next = self
                    .tool_output_bytes
                    .get(&key)
                    .copied()
                    .unwrap_or_default()
                    .saturating_add(payload_delta.text().len());
                self.charge_tool_output(&key, next)?;
                let snapshot = self.tool_stream.append_delta(
                    stream_id.as_ref(),
                    item_id,
                    call_id.as_ref(),
                    name,
                    payload_delta,
                );
                self.record_tool_delta(&snapshot.tool, snapshot.delta, event_tx);
            }
            ModelStreamEvent::ToolInputCompleted {
                stream_id,
                item_id,
                call_id,
                name,
                payload,
            } => {
                self.charge_tool_payload(&stream_id, &call_id, &item_id, payload.as_ref())?;
                self.tool_stream.complete_input(
                    stream_id.as_ref(),
                    call_id.as_ref(),
                    &item_id,
                    name,
                    payload,
                );
            }
            ModelStreamEvent::ToolCallReady {
                stream_id,
                item_id,
                call_id,
                name,
                payload,
            } => {
                self.charge_tool_payload(&stream_id, &call_id, &item_id, payload.as_ref())?;
                if let Some(mut call) = self.tool_stream.finish_ready(
                    stream_id.as_ref(),
                    call_id.as_ref(),
                    &item_id,
                    name,
                    payload,
                )? {
                    self.attach_tool_caller(&mut call);
                    self.update_tool_trace(&call, event_tx);
                    self.tool_calls.push(call);
                }
            }
            ModelStreamEvent::ToolCallCaller { item_id, caller } => {
                if let Some(call) = self
                    .tool_calls
                    .iter_mut()
                    .find(|call| call.id == item_id || call.call_id == item_id)
                {
                    call.caller = Some(caller);
                } else {
                    self.tool_call_callers.insert(item_id, caller);
                }
            }
            ModelStreamEvent::ResponsesContextItem { item } => {
                self.responses_context_items.push(item);
            }
            ModelStreamEvent::PresentationItem { item, state } => {
                let state = state.ok_or_else(|| {
                    PureError::LlmError(
                        "response.output_item.done has contradictory item status".into(),
                    )
                })?;
                let id = item.provider_item_id.clone();
                if self
                    .presentation_states
                    .get(&id)
                    .is_some_and(|old| *old != state)
                {
                    return Err(PureError::LlmError("conflicting model member state".into()));
                }
                let duplicate = self.presentation_indexes.contains_key(&id);
                self.record_presentation_item(item)?;
                for block in &mut self.blocks {
                    if block.provider_item_id.as_deref() == Some(id.as_str()) {
                        block.closed = true;
                    }
                }
                self.presentation_states.insert(id.clone(), state);
                if !duplicate {
                    self.completed_member = Some((
                        *self.presentation_indexes.get(&id).expect("recorded item"),
                        state,
                    ));
                }
            }
            ModelStreamEvent::Replay(update) => self.replay.apply(update)?,
            ModelStreamEvent::WebSearchStarted { item_id, action } => {
                self.record_web_search_started(&item_id, action, event_tx);
            }
            ModelStreamEvent::WebSearchCompleted {
                item_id,
                action,
                results,
            } => {
                self.record_web_search_completed(&item_id, action, results, event_tx);
            }
            ModelStreamEvent::Usage(usage) => {
                self.final_usage = Some(usage);
            }
            ModelStreamEvent::Completed { response_id } => {
                for mut call in self.tool_stream.finish_all(&self.tool_calls)? {
                    self.attach_tool_caller(&mut call);
                    self.update_tool_trace(&call, event_tx);
                    self.tool_calls.push(call);
                }
                if response_id.is_some() {
                    self.response_id = response_id;
                }
                for block in &mut self.blocks {
                    block.closed = true;
                }
                self.state = StreamAccumulatorState::Completed(CompletedStream::new());
            }
            ModelStreamEvent::Failed {
                request_id,
                code,
                http_status,
                retry_after_ms,
                message,
            } => {
                let mut error = crate::runtime::provider_stream_failure(
                    code.as_deref(),
                    http_status,
                    retry_after_ms,
                    message,
                );
                if let PureError::Provider(failure) = &mut error {
                    failure.context.request_id = request_id;
                }
                self.state = StreamAccumulatorState::Failed(FailedStream::new(error.to_string()));
                return Err(error);
            }
            ModelStreamEvent::ResponseStarted { response_id } => {
                if self.response_id.is_none() {
                    self.response_id = response_id;
                }
            }
            ModelStreamEvent::ResponseModelObserved { model, terminal } => {
                self.observe_reported_model(&model, terminal);
            }
        }

        self.ensure_trace_sink()?;
        // Only validated events may create reliable beginnings. The collector drains these before
        // applying the next normalized event, including multiple events from one provider input.
        for identity in starts {
            self.record_member_start(identity)?;
        }
        for identity in content_available {
            self.record_content_available(identity)?;
        }
        Ok(())
    }

    fn started_identities(&self, event: &ModelStreamEvent) -> Result<Vec<ObservedPartIdentity>> {
        Ok(match event {
            ModelStreamEvent::BlockOpened {
                kind: kind @ ModelBlockKind::Text { .. },
                provider,
                ..
            } => {
                vec![observation(*kind, provider.as_ref())?.1]
            }
            // Responses currently opens one summary block for the entire reasoning item,
            // synthesizing index zero even when no summary part was reported. It is not a
            // reliable part boundary. The first accepted summary delta or a validated terminal
            // part supplies the real identity instead.
            ModelStreamEvent::BlockOpened {
                kind: ModelBlockKind::ReasoningSummary,
                ..
            } => Vec::new(),
            ModelStreamEvent::BlockDelta {
                kind: kind @ ModelBlockKind::ReasoningSummary,
                field: ModelBlockField::ReasoningSummary,
                provider,
                ..
            } => vec![observation(*kind, provider.as_ref())?.1],
            ModelStreamEvent::ReasoningRawDelta { provider, .. } => {
                vec![match provider {
                    Some(provider) => {
                        provider_observation(
                            &provider.item_id,
                            ObservedItemKind::Reasoning,
                            ObservedPartKind::ReasoningText,
                            provider.content_index,
                        )
                        .1
                    }
                    None => ObservedPartIdentity::Aggregate {
                        channel: AggregateChannel::Reasoning,
                    },
                }]
            }
            ModelStreamEvent::PresentationItem { item, .. } => {
                let kind = match item.kind {
                    crate::completion::CompletionPresentationItemKind::Text(channel) => {
                        ObservedItemKind::Text(text_channel(channel))
                    }
                    crate::completion::CompletionPresentationItemKind::Reasoning => {
                        ObservedItemKind::Reasoning
                    }
                };
                item.parts
                    .iter()
                    .map(|part| {
                        let mut identity = provider_observation(
                            &item.provider_item_id,
                            kind,
                            observed_part_kind(part.kind),
                            part.content_index,
                        )
                        .1;
                        if let ObservedPartIdentity::Provider(provider) = &mut identity {
                            provider.output_index = item.output_index;
                        }
                        identity
                    })
                    .collect()
            }
            _ => Vec::new(),
        })
    }

    fn record_member_start(&mut self, identity: ObservedPartIdentity) -> Result<()> {
        let key = part_key(&identity);
        if let ObservedPartIdentity::Provider(provider) = &identity
            && provider.item_id.is_empty()
        {
            return Err(PureError::LlmError("empty provider part identity".into()));
        }
        if let Some(part) = self.started_members.get_mut(&key) {
            let old = &mut part.identity;
            if let (ObservedPartIdentity::Provider(old), ObservedPartIdentity::Provider(new)) =
                (&*old, &identity)
                && (std::mem::discriminant(&old.item_kind)
                    != std::mem::discriminant(&new.item_kind)
                    || (old.output_index.is_some()
                        && new.output_index.is_some()
                        && old.output_index != new.output_index))
            {
                return Err(PureError::LlmError("conflicting model part start".into()));
            }
            if let (ObservedPartIdentity::Provider(old), ObservedPartIdentity::Provider(new)) =
                (old, &identity)
            {
                old.output_index = old.output_index.or(new.output_index);
                // A Text channel can be supplied/corrected by the authoritative terminal item.
                // It is metadata, not a second part or an authorization to send a final answer.
                old.item_kind = new.item_kind;
            }
            return Ok(());
        }
        let bytes = serde_json::to_vec(&identity)
            .map_err(|error| PureError::LlmError(error.to_string()))?
            .len()
            .saturating_mul(2)
            .saturating_add(std::mem::size_of::<StartedPart>() + 128);
        self.presentation_bytes = self
            .presentation_bytes
            .checked_add(bytes)
            .filter(|&bytes| bytes <= MAX_OUTPUT_BYTES)
            .ok_or_else(|| {
                PureError::MemoryError("provider presentation output exceeds 16 MiB".into())
            })?;
        self.started_members.insert(
            key,
            StartedPart {
                identity: identity.clone(),
                content_available: false,
            },
        );
        self.pending_starts.push(identity);
        Ok(())
    }

    pub(crate) fn take_started_members(&mut self) -> Vec<ObservedPartIdentity> {
        std::mem::take(&mut self.pending_starts)
    }

    fn content_available_identities(
        &self,
        event: &ModelStreamEvent,
    ) -> Result<Vec<ObservedPartIdentity>> {
        Ok(match event {
            ModelStreamEvent::BlockDelta {
                kind: kind @ ModelBlockKind::Text { .. },
                field: ModelBlockField::Text,
                delta,
                provider,
                ..
            }
            | ModelStreamEvent::BlockDelta {
                kind: kind @ ModelBlockKind::ReasoningSummary,
                field: ModelBlockField::ReasoningSummary,
                delta,
                provider,
                ..
            } if !delta.is_empty() => vec![observation(*kind, provider.as_ref())?.1],
            ModelStreamEvent::BlockClosed {
                kind: kind @ ModelBlockKind::Text { .. },
                authoritative_content: Some(ModelBlockContent::Text(text)),
                provider,
                ..
            } if !text.is_empty() => vec![observation(*kind, provider.as_ref())?.1],
            // A reasoning close contains an item-wide summary list, not one part. Its validated
            // PresentationItem supplies the real per-part identities just as it does for starts.
            ModelStreamEvent::ReasoningRawDelta { delta, .. } if !delta.is_empty() => {
                self.started_identities(event)?
            }
            ModelStreamEvent::PresentationItem { item, .. } => self
                .started_identities(event)?
                .into_iter()
                .zip(&item.parts)
                .filter_map(|(identity, part)| (!part.text.is_empty()).then_some(identity))
                .collect(),
            _ => Vec::new(),
        })
    }

    fn record_content_available(&mut self, identity: ObservedPartIdentity) -> Result<()> {
        let part = self
            .started_members
            .get_mut(&part_key(&identity))
            .ok_or_else(|| PureError::LlmError("content without a model part start".into()))?;
        if part.content_available {
            return Ok(());
        }
        // The flag belongs to the original call-local start entry. Charge only the transient
        // handoff identity here; no text or second identity registry is retained.
        let bytes = serde_json::to_vec(&identity)
            .map_err(|error| PureError::LlmError(error.to_string()))?
            .len()
            .saturating_add(std::mem::size_of::<ObservedPartIdentity>() + 128);
        self.presentation_bytes = self
            .presentation_bytes
            .checked_add(bytes)
            .filter(|&bytes| bytes <= MAX_OUTPUT_BYTES)
            .ok_or_else(|| {
                PureError::MemoryError("provider presentation output exceeds 16 MiB".into())
            })?;
        self.pending_content_available_bytes += bytes;
        part.content_available = true;
        self.pending_content_available.push(identity);
        Ok(())
    }

    pub(crate) fn take_content_available_members(&mut self) -> Vec<ObservedPartIdentity> {
        // The collector completes this handoff before accepting another normalized event.
        // Its receiver funds accepted facts; the accumulator retains only the once flag.
        self.presentation_bytes -= std::mem::take(&mut self.pending_content_available_bytes);
        std::mem::take(&mut self.pending_content_available)
    }

    pub(crate) fn take_presentation_items(&mut self) -> Vec<CompletionPresentationItem> {
        std::mem::take(&mut self.presentation_items)
    }

    fn charge_text_output(&mut self, old: usize, new: usize) -> Result<()> {
        let next = self.text_output_bytes - old;
        let next = next
            .checked_add(new)
            .filter(|&bytes| bytes <= MAX_OUTPUT_BYTES)
            .ok_or_else(|| {
                PureError::MemoryError(
                    "provider output (text, reasoning and tool input) exceeds 16 MiB".into(),
                )
            })?;
        self.text_output_bytes = next;
        Ok(())
    }

    /// Charges one tool call's argument high-water against the shared output domain.
    ///
    /// Tool arguments are part of the same `MAX_OUTPUT_BYTES` total as text and reasoning: the
    /// charge is the difference between the call's previously charged high-water and its new total,
    /// so a repeated or shorter `completed` adds nothing and a later append after a shorter
    /// replacement still advances the total by exactly the new bytes.
    fn charge_tool_output(&mut self, key: &str, next: usize) -> Result<()> {
        let previous = self.tool_output_bytes.get(key).copied().unwrap_or_default();
        if next <= previous {
            return Ok(());
        }
        self.charge_text_output(previous, next)?;
        self.tool_output_bytes.insert(key.to_string(), next);
        Ok(())
    }

    /// Charges the authoritative argument payload of a completed/ready tool call under its identity.
    ///
    /// A `None` payload leaves the call's charged total unchanged, and a payload that does not exceed
    /// the already-accepted high-water (a re-sent `completed`, or a shorter replacement) is a no-op.
    fn charge_tool_payload(
        &mut self,
        stream_id: &Option<String>,
        call_id: &Option<String>,
        item_id: &str,
        payload: Option<&ToolInputDeltaPayload>,
    ) -> Result<()> {
        let Some(payload) = payload else {
            return Ok(());
        };
        let key = self
            .tool_stream
            .resolved_key(stream_id.as_ref(), call_id.as_ref(), item_id);
        let next = self
            .tool_output_bytes
            .get(&key)
            .copied()
            .unwrap_or_default()
            .max(payload.text().len());
        self.charge_tool_output(&key, next)
    }

    fn record_presentation_item(&mut self, item: CompletionPresentationItem) -> Result<()> {
        use crate::completion::{
            CompletionPresentationItemKind as ItemKind, CompletionPresentationPartKind as PartKind,
        };
        let mut indexes = std::collections::HashSet::new();
        let mut ids = std::collections::HashSet::new();
        if item.provider_item_id.is_empty()
            || item.parts.iter().any(|part| {
                !indexes.insert((std::mem::discriminant(&part.kind), part.content_index))
                    || part
                        .provider_part_id
                        .as_ref()
                        .is_some_and(|id| id.is_empty() || !ids.insert(id))
                    || !matches!(
                        (item.kind, part.kind),
                        (ItemKind::Text(_), PartKind::OutputText)
                            | (
                                ItemKind::Reasoning,
                                PartKind::ReasoningText | PartKind::SummaryText
                            )
                    )
            })
        {
            return Err(PureError::LlmError(
                "invalid model member identity or part kind".into(),
            ));
        }
        let key = item.provider_item_id.clone();
        if let Some(&index) = self.presentation_indexes.get(&key) {
            return if self.presentation_items[index] == item {
                Ok(())
            } else {
                Err(PureError::LlmError(
                    "conflicting frozen model member".into(),
                ))
            };
        }
        let size = presentation_item_bytes(&item).ok_or_else(|| {
            PureError::MemoryError("provider presentation output exceeds 16 MiB".into())
        })?;
        let next = self
            .presentation_bytes
            .checked_add(size)
            .filter(|&bytes| bytes <= MAX_OUTPUT_BYTES)
            .ok_or_else(|| {
                PureError::MemoryError("provider presentation output exceeds 16 MiB".into())
            })?;
        self.presentation_indexes
            .insert(key, self.presentation_items.len());
        self.presentation_items.push(item);
        self.presentation_bytes = next;
        Ok(())
    }

    pub(crate) fn take_completed_member(
        &mut self,
    ) -> Option<(
        &CompletionPresentationItem,
        crate::runtime::ModelMemberState,
    )> {
        self.completed_member
            .take()
            .map(|(index, state)| (&self.presentation_items[index], state))
    }

    pub(crate) fn finish(&mut self, event_tx: &AgentEventSender) -> Result<CompletionResponse> {
        self.finish_inner(event_tx)
    }

    fn finish_inner(&mut self, event_tx: &AgentEventSender) -> Result<CompletionResponse> {
        let terminal_error = match &self.state {
            StreamAccumulatorState::Open(_) => Some(PureError::transient_model_transport(
                "provider stream ended before completion",
            )),
            StreamAccumulatorState::Completed(_) => None,
            StreamAccumulatorState::Failed(failed) => {
                Some(PureError::LlmError(failed.message().to_string()))
            }
        };
        if let Some(error) = terminal_error {
            self.fail_attempt(&error, event_tx);
            return Err(error);
        }

        for mut call in self.tool_stream.finish_all(&self.tool_calls)? {
            self.attach_tool_caller(&mut call);
            self.update_tool_trace(&call, event_tx);
            self.tool_calls.push(call);
        }
        if let Some(trace) = self.trace.as_mut() {
            for event in trace.complete_streaming_items() {
                let _ = event_tx.send(event);
            }
        }
        self.ensure_trace_sink()?;

        let final_parts = self
            .content_parts
            .iter()
            .filter(|part| {
                part.kind == CompletionPresentationPartKind::OutputText
                    && self.blocks.iter().any(|block| {
                        block.id == part.block_id && block.channel == Some(TraceTextChannel::Final)
                    })
            })
            .collect::<Vec<_>>();
        let content = if final_parts.is_empty() {
            None
        } else {
            Some(
                final_parts
                    .iter()
                    .map(|part| part.text.as_str())
                    .collect::<String>(),
            )
        };
        let raw_reasoning_parts =
            self.reasoning_parts(CompletionPresentationPartKind::ReasoningText);
        let reasoning_content = if raw_reasoning_parts.is_empty() {
            None
        } else {
            Some(raw_reasoning_parts.join(""))
        };
        let orchestration =
            stream_orchestration_metrics(&self.responses_context_items, &self.tool_calls);
        let model = self
            .model_observation
            .as_ref()
            .and_then(|observation| observation.reported_model.clone())
            .unwrap_or_default();
        let replay = self.replay.finish()?;
        if let Some(crate::completion::AssistantReplay::Chat { content }) = &replay {
            for item in super::chat_presentation::completed_chat_presentation(
                content,
                reasoning_content.as_deref(),
            )? {
                self.record_presentation_item(item)?;
            }
        }
        let mut response = CompletionResponse {
            response_id: self.response_id.take(),
            content,
            replay,
            reasoning_content,
            tool_calls: std::mem::take(&mut self.tool_calls),
            responses_context_items: std::mem::take(&mut self.responses_context_items),
            presentation_items: self.take_presentation_items(),
            orchestration,
            timing: None,
            accounting: pl_protocol::InferenceAccounting {
                usage: self.final_usage.take().unwrap_or_default(),
                ..Default::default()
            },
            model,
            model_observation: self.model_observation.take(),
            observation: Default::default(),
        };
        if let Some(crate::completion::AssistantReplay::Responses { output }) = &response.replay {
            let call_order = output
                .iter()
                .filter(|item| {
                    matches!(
                        item.get("type").and_then(serde_json::Value::as_str),
                        Some("function_call" | "custom_tool_call")
                    )
                })
                .filter_map(|item| {
                    item.get("call_id")
                        .or_else(|| item.get("id"))
                        .and_then(serde_json::Value::as_str)
                })
                .collect::<Vec<_>>();
            response.tool_calls.sort_by_key(|call| {
                call_order
                    .iter()
                    .position(|id| *id == call.call_id)
                    .unwrap_or(usize::MAX)
            });
        }
        if let Some(replay) = &response.replay {
            replay.semantic_input(&response)?;
        }
        Ok(response)
    }

    fn observe_reported_model(&mut self, model: &str, terminal: bool) {
        if self.reported_model_is_terminal {
            return;
        }
        let Some(model) = valid_reported_model(model) else {
            return;
        };
        let Some(observation) = self.model_observation.as_mut() else {
            return;
        };
        if terminal || observation.reported_model.is_none() {
            observation.reported_model = Some(model);
        }
        if terminal {
            self.reported_model_is_terminal = true;
        }
    }

    pub(super) fn model_observation(&self) -> Option<InferenceModelObservation> {
        self.model_observation.clone()
    }

    fn attach_tool_caller(&mut self, call: &mut ToolCall) {
        call.caller = self
            .tool_call_callers
            .remove(&call.id)
            .or_else(|| self.tool_call_callers.remove(&call.call_id));
    }

    pub(super) fn accounting(&self) -> pl_protocol::InferenceAccounting {
        pl_protocol::InferenceAccounting {
            usage: self.final_usage.clone().unwrap_or_default(),
            ..Default::default()
        }
    }

    pub(crate) fn fail_attempt(&mut self, error: &PureError, event_tx: &AgentEventSender) {
        self.state = StreamAccumulatorState::Failed(FailedStream::new(error.to_string()));
        self.publish_trace(event_tx, |trace| trace.fail_attempt(&error.to_string()));
    }

    pub(super) fn cancel_attempt(&mut self, reason: &str, event_tx: &AgentEventSender) {
        self.state = StreamAccumulatorState::Failed(FailedStream::new(reason));
        self.publish_trace(event_tx, |trace| trace.cancel_attempt(reason));
    }

    fn ensure_trace_sink(&mut self) -> Result<()> {
        let Some(trace) = self.trace.as_mut() else {
            return Ok(());
        };
        match trace.take_trace_error() {
            Some(error) => Err(PureError::Protocol(format!(
                "canonical trace publication failed: {error}"
            ))),
            None => Ok(()),
        }
    }

    fn record_text_started(
        &mut self,
        item_id: &str,
        text_channel: TraceTextChannel,
        event_tx: &AgentEventSender,
    ) {
        self.publish_trace(event_tx, |trace| trace.start_text(item_id, text_channel));
    }

    fn record_web_search_started(
        &mut self,
        item_id: &str,
        action: WebSearchAction,
        event_tx: &AgentEventSender,
    ) {
        self.publish_trace(event_tx, |trace| trace.start_web_search(item_id, action));
    }

    fn record_web_search_completed(
        &mut self,
        item_id: &str,
        action: WebSearchAction,
        results: Option<Vec<serde_json::Value>>,
        event_tx: &AgentEventSender,
    ) {
        self.publish_trace(event_tx, |trace| {
            trace.complete_web_search(item_id, action, results)
        });
    }

    fn record_text_delta(
        &mut self,
        item_id: &str,
        delta: String,
        event_tx: &AgentEventSender,
        text_channel: TraceTextChannel,
    ) {
        self.publish_trace(event_tx, |trace| {
            trace.append_text_delta(item_id, text_channel, delta)
        });
    }

    fn record_text_completed(
        &mut self,
        item_id: &str,
        text_channel: TraceTextChannel,
        authoritative_text: Option<String>,
        event_tx: &AgentEventSender,
    ) {
        self.publish_trace(event_tx, |trace| {
            trace.complete_text(item_id, text_channel, authoritative_text)
        });
    }

    fn append_content_part(
        &mut self,
        key: &str,
        id: &str,
        kind: CompletionPresentationPartKind,
        identity: ObservedPartIdentity,
        content_index: u32,
        delta: &str,
    ) -> Result<()> {
        self.charge_text_output(0, delta.len())?;
        let index = self.content_part_slot(key, id, kind, identity, content_index);
        self.content_parts[index].text.push_str(delta);
        Ok(())
    }

    fn complete_content_part(
        &mut self,
        key: &str,
        id: &str,
        kind: CompletionPresentationPartKind,
        identity: ObservedPartIdentity,
        content_index: u32,
        text: &str,
    ) -> Result<()> {
        let old = self
            .content_indexes
            .get(key)
            .map_or(0, |&index| self.content_parts[index].text.len());
        self.charge_text_output(old, text.len())?;
        let index = self.content_part_slot(key, id, kind, identity, content_index);
        self.content_parts[index].text = text.to_string();
        Ok(())
    }

    /// 返回 item 对应的 content part 下标，缺失时追加空 part。
    fn content_part_slot(
        &mut self,
        key: &str,
        id: &str,
        kind: CompletionPresentationPartKind,
        identity: ObservedPartIdentity,
        content_index: u32,
    ) -> usize {
        *self
            .content_indexes
            .entry(key.to_string())
            .or_insert_with(|| {
                self.content_parts.push(ModelStreamContentPart {
                    block_id: id.into(),
                    content_index,
                    identity,
                    kind,
                    text: String::new(),
                });
                self.content_parts.len() - 1
            })
    }

    fn remove_summary_parts(&mut self, id: &str) {
        let mut positions = Vec::with_capacity(self.content_parts.len());
        let mut next = 0;
        self.content_parts.retain(|part| {
            let keep =
                part.block_id != id || part.kind != CompletionPresentationPartKind::SummaryText;
            positions.push(keep.then_some(next));
            next += usize::from(keep);
            keep
        });
        self.content_indexes.retain(|_, index| {
            if let Some(new) = positions[*index] {
                *index = new;
                true
            } else {
                false
            }
        });
    }

    fn reasoning_parts(&self, kind: CompletionPresentationPartKind) -> Vec<String> {
        self.content_parts
            .iter()
            .filter(|part| part.kind == kind)
            .map(|part| part.text.clone())
            .collect()
    }

    fn record_block_state(&mut self, event: &ModelStreamEvent) -> Result<()> {
        let (id, kind, channel, provider, metadata, closed) = match event {
            ModelStreamEvent::BlockOpened {
                id,
                kind,
                provider,
                provider_metadata,
            }
            | ModelStreamEvent::BlockClosed {
                id,
                kind,
                provider,
                provider_metadata,
                ..
            } => (
                id,
                match kind {
                    ModelBlockKind::Text { .. } => CompletionPresentationPartKind::OutputText,
                    ModelBlockKind::ReasoningSummary => CompletionPresentationPartKind::SummaryText,
                },
                match kind {
                    ModelBlockKind::Text { channel } => Some(*channel),
                    _ => None,
                },
                provider.as_ref(),
                provider_metadata.as_ref(),
                matches!(event, ModelStreamEvent::BlockClosed { .. }),
            ),
            ModelStreamEvent::ReasoningRawDelta { id, provider, .. } => (
                id,
                CompletionPresentationPartKind::ReasoningText,
                None,
                provider.as_ref(),
                None,
                false,
            ),
            ModelStreamEvent::PresentationItem { .. } => return Ok(()),
            _ => return Ok(()),
        };
        // The decoder already admitted the raw item to replay before its normalized block. Do not
        // clone or charge that same item again as presentation metadata. A canonical-only producer
        // without a native item retains its metadata here under the same native-output quota.
        let shared_metadata = provider
            .and_then(|part| self.replay.native_item(&part.item_id))
            .is_some_and(|item| Some(item) == metadata);
        let owned_metadata = metadata.filter(|_| !shared_metadata);
        if let Some(index) = self
            .blocks
            .iter()
            .position(|block| block.id == *id && block.kind == kind && block.channel == channel)
        {
            if metadata.is_some() {
                self.replay.replace_block_metadata(
                    self.blocks[index].provider_metadata.as_ref(),
                    owned_metadata,
                )?;
            }
            let block = &mut self.blocks[index];
            block.closed |= closed;
            if metadata.is_some() {
                block.provider_metadata = owned_metadata.cloned();
            }
            return Ok(());
        }
        let bytes = std::mem::size_of::<ModelStreamBlock>()
            + id.len()
            + provider.map_or(0, |provider| provider.item_id.len());
        let next = self
            .block_bytes
            .checked_add(bytes)
            .filter(|bytes| *bytes <= MAX_OUTPUT_BYTES)
            .ok_or_else(|| {
                PureError::MemoryError("provider block identities exceed 16 MiB".into())
            })?;
        self.replay.replace_block_metadata(None, owned_metadata)?;
        self.blocks.push(ModelStreamBlock {
            id: id.clone(),
            kind,
            channel,
            provider_item_id: provider.map(|part| part.item_id.clone()),
            provider_metadata: owned_metadata.cloned(),
            closed,
        });
        self.block_bytes = next;
        Ok(())
    }

    fn record_thinking_delta(
        &mut self,
        item_id: &str,
        chunk_index: u32,
        delta: String,
        event_tx: &AgentEventSender,
    ) {
        self.publish_trace(event_tx, |trace| {
            trace.append_thinking_delta(item_id, chunk_index, delta)
        });
    }

    fn record_reasoning_content_delta(
        &mut self,
        item_id: &str,
        chunk_index: u32,
        delta: String,
        event_tx: &AgentEventSender,
    ) {
        self.publish_trace(event_tx, |trace| {
            trace.append_reasoning_content_delta(item_id, chunk_index, delta)
        });
    }

    fn record_thinking_completed(
        &mut self,
        item_id: &str,
        authoritative_summary: Option<Vec<String>>,
        event_tx: &AgentEventSender,
    ) {
        self.publish_trace(event_tx, |trace| {
            trace.complete_thinking(item_id, authoritative_summary)
        });
    }

    fn record_tool_delta(
        &mut self,
        snapshot: &tool_stream::ToolCallAccumulatorSnapshot,
        delta: String,
        event_tx: &AgentEventSender,
    ) {
        self.publish_trace(event_tx, |trace| {
            trace.append_tool_arguments_delta(snapshot, delta)
        });
    }

    fn record_tool_started(
        &mut self,
        snapshot: &tool_stream::ToolCallAccumulatorSnapshot,
        event_tx: &AgentEventSender,
    ) {
        self.publish_trace(event_tx, |trace| trace.start_tool(snapshot));
    }

    fn update_tool_trace(&mut self, call: &ToolCall, event_tx: &AgentEventSender) {
        self.publish_trace(event_tx, |trace| trace.update_tool_trace(call));
    }

    /// 投影 trace 事件并发布到宿主事件通道；未挂载 trace 时静默跳过。
    fn publish_trace(
        &mut self,
        event_tx: &AgentEventSender,
        project: impl FnOnce(&mut TraceProjection) -> Vec<AgentEvent>,
    ) {
        let Some(trace) = self.trace.as_mut() else {
            return;
        };
        for event in project(trace) {
            let _ = event_tx.send(event);
        }
    }
}

fn presentation_item_bytes(item: &CompletionPresentationItem) -> Option<usize> {
    // Include fixed record and index costs so zero-length items cannot grow without a bound.
    let base = std::mem::size_of::<CompletionPresentationItem>()
        .checked_add(std::mem::size_of::<(String, Option<u32>)>())?
        .checked_add(std::mem::size_of::<(
            String,
            crate::runtime::ModelMemberState,
        )>())?
        .checked_add(item.provider_item_id.len().checked_mul(3)?)?;
    item.parts.iter().try_fold(base, |bytes, part| {
        bytes
            .checked_add(std::mem::size_of::<CompletionPresentationPart>())?
            .checked_add(part.provider_part_id.as_ref().map_or(0, String::len))?
            .checked_add(part.text.len())
    })
}

fn valid_reported_model(model: &str) -> Option<String> {
    let model = model.trim();
    (!model.is_empty() && model.len() <= 256 && !model.chars().any(char::is_control))
        .then(|| model.to_string())
}

fn stream_orchestration_metrics(
    context_items: &[ResponsesContextItem],
    tool_calls: &[ToolCall],
) -> InferenceOrchestrationMetrics {
    let program_count = context_items
        .iter()
        .filter(|item| item.kind == ResponsesContextItemKind::Program)
        .count() as u64;
    let program_tool_calls = tool_calls
        .iter()
        .filter(|call| call.caller.is_some())
        .count() as u64;

    InferenceOrchestrationMetrics {
        tool_calls: tool_calls.len() as u64,
        program_count,
        program_tool_calls,
        transport_attempts: 1,
        ..InferenceOrchestrationMetrics::default()
    }
}

#[cfg(test)]
mod current_tests {
    use super::*;
    use crate::runtime::openai::{VisibleOutputProtocol, sse::OpenAiStreamDecoder};
    use serde_json::json;

    fn feed(
        acc: &mut StreamCompletionAccumulator,
        decoder: &mut OpenAiStreamDecoder,
        wire: serde_json::Value,
    ) {
        let (events, _) = tokio::sync::broadcast::channel(16);
        for event in decoder.decode(&serde_json::from_value(wire).unwrap()) {
            acc.apply(event, &events).unwrap();
        }
    }

    fn round_trip(acc: &StreamCompletionAccumulator) -> ModelStreamCurrent {
        let payload = acc.current("source-attempt", 2).encode().unwrap();
        assert_eq!(payload.format(), "pl.model.stream-current");
        assert_eq!(payload.version(), 1);
        ModelStreamCurrent::decode(&payload).unwrap()
    }

    #[test]
    fn current_summary_uses_provider_part_index_not_trace_section_number() {
        use super::super::event::ProviderBlockIdentity;
        let mut acc = StreamCompletionAccumulator::with_model_observation(None, None, None);
        let (events, _) = tokio::sync::broadcast::channel(16);
        let provider = Some(ProviderBlockIdentity {
            item_id: "reasoning".into(),
            content_index: 7,
        });
        acc.apply(
            ModelStreamEvent::reasoning_summary_started("block".into(), None, provider.clone()),
            &events,
        )
        .unwrap();
        for (section, text) in [(0, "first"), (1, " second")] {
            acc.apply(
                ModelStreamEvent::reasoning_summary_delta(
                    "block".into(),
                    section,
                    text.into(),
                    provider.clone(),
                ),
                &events,
            )
            .unwrap();
        }
        let saved = round_trip(&acc);
        assert_eq!(
            saved.content_parts.len(),
            1,
            "trace numbering cannot split a real provider part"
        );
        assert_eq!(saved.content_parts[0].content_index, 7);
        let ObservedPartIdentity::Provider(identity) = &saved.content_parts[0].identity else {
            panic!("provider part");
        };
        assert_eq!(identity.content_index, 7);
        assert_eq!(saved.content_parts[0].text, "first second");
        assert_eq!(saved.members.len(), 1);
        assert_eq!(saved.members[0].identity, saved.content_parts[0].identity);
    }

    #[test]
    fn native_block_metadata_does_not_spend_presentation_budget_twice() {
        let mut acc = StreamCompletionAccumulator::with_model_observation(None, None, None);
        let mut decoder = OpenAiStreamDecoder::new(VisibleOutputProtocol::NativePhases);
        // Native replay and completed presentation each already have their own 16 MiB ceiling.
        // Charging this raw item again as block metadata used to reject this valid response.
        let text = "s".repeat(MAX_OUTPUT_BYTES / 2 + 4096);
        feed(
            &mut acc,
            &mut decoder,
            json!({"type":"response.output_item.added","output_index":0,
            "item":{"id":"reasoning","type":"reasoning","summary":[]}}),
        );
        feed(
            &mut acc,
            &mut decoder,
            json!({"type":"response.output_item.done","output_index":0,
            "item":{"id":"reasoning","type":"reasoning","status":"completed",
                "summary":[{"type":"summary_text","text":text}],"signature":"unchanged"}}),
        );
        assert!(acc.presentation_bytes < MAX_OUTPUT_BYTES);
        assert_eq!(acc.presentation_items[0].parts[0].text, text);
        assert!(
            acc.blocks
                .iter()
                .all(|block| block.provider_metadata.is_none()),
            "native body has only one resident metadata owner"
        );
        let saved = round_trip(&acc);
        assert_eq!(
            saved.blocks[0].provider_metadata.as_ref().unwrap()["signature"],
            "unchanged"
        );
        assert_eq!(saved.replay.items[0].item["summary"][0]["text"], text);
        let oversized = ModelStreamEvent::PresentationItem {
            item: CompletionPresentationItem {
                provider_item_id: "over-budget".into(),
                output_index: Some(1),
                kind: crate::completion::CompletionPresentationItemKind::Reasoning,
                parts: vec![CompletionPresentationPart {
                    content_index: 0,
                    provider_part_id: None,
                    kind: CompletionPresentationPartKind::SummaryText,
                    text: "s".repeat(MAX_OUTPUT_BYTES),
                }],
            },
            state: Some(crate::runtime::ModelMemberState::Completed),
        };
        let (events, _) = tokio::sync::broadcast::channel(16);
        assert!(
            acc.apply(oversized, &events).is_err(),
            "the existing presentation ceiling must still reject oversized output"
        );
        assert_eq!(acc.presentation_items.len(), 1);
    }

    #[test]
    fn current_tool_aliases_retain_only_actual_local_identity_upgrades() {
        use super::super::event::ToolInputPayloadKind;
        let mut acc = StreamCompletionAccumulator::with_model_observation(None, None, None);
        let (events, _) = tokio::sync::broadcast::channel(16);
        acc.apply(
            ModelStreamEvent::ToolInputStarted {
                stream_id: Some("stream".into()),
                item_id: "real-item".into(),
                call_id: Some("real-item".into()),
                name: Some("lookup".into()),
                payload_kind: ToolInputPayloadKind::FunctionArguments,
            },
            &events,
        )
        .unwrap();
        acc.apply(
            ModelStreamEvent::ToolInputDelta {
                stream_id: Some("stream".into()),
                item_id: "real-item".into(),
                call_id: Some("real-call".into()),
                name: None,
                payload_delta: ToolInputDeltaPayload::FunctionArguments("{\"q\":".into()),
            },
            &events,
        )
        .unwrap();
        for index in 0..2048 {
            acc.apply(
                ModelStreamEvent::ToolInputDelta {
                    stream_id: Some("stream".into()),
                    item_id: format!("unused-item-{index}"),
                    call_id: Some(format!("unused-call-{index}")),
                    name: None,
                    payload_delta: ToolInputDeltaPayload::FunctionArguments(String::new()),
                },
                &events,
            )
            .unwrap();
        }
        let saved = round_trip(&acc);
        let input = &saved.tool_inputs[0];
        assert_eq!(input.input, "{\"q\":");
        assert_eq!(input.stream_aliases, ["stream"]);
        assert_eq!(input.item_aliases, ["real-item"]);
        assert_eq!(input.call_aliases, ["real-item", "real-call"]);
        assert_eq!(input.provider_call_id.as_deref(), Some("real-call"));
        assert!(saved.tool_calls.is_empty());
    }

    #[test]
    fn producer_current_keeps_open_commentary_reasoning_and_inert_partial_input() {
        let mut acc = StreamCompletionAccumulator::with_model_observation(None, None, None);
        let mut decoder = OpenAiStreamDecoder::new(VisibleOutputProtocol::NativePhases);
        let commentary = "untrimmed commentary ".repeat(1024);
        feed(
            &mut acc,
            &mut decoder,
            json!({"type":"response.created","response":{"id":"response-1"}}),
        );
        feed(
            &mut acc,
            &mut decoder,
            json!({"type":"response.output_item.added","output_index":0,
            "item":{"id":"commentary","type":"message","role":"assistant","phase":"commentary","content":[]}}),
        );
        feed(
            &mut acc,
            &mut decoder,
            json!({"type":"response.output_text.delta","item_id":"commentary","content_index":0,"delta":commentary}),
        );
        let open = round_trip(&acc);
        assert_eq!(open.state, ModelStreamCurrentState::Open);
        assert_eq!(open.content_parts[0].text, commentary);
        assert!(
            open.blocks
                .iter()
                .any(|block| block.channel == Some(TraceTextChannel::Commentary) && !block.closed)
        );
        assert!(
            open.presentation_items.is_empty(),
            "an open item must not masquerade as a completed member"
        );

        for (index, id, summary, raw) in [
            (1, "reasoning-1", "first summary", "first raw"),
            (2, "reasoning-2", "second summary", "second raw"),
        ] {
            feed(
                &mut acc,
                &mut decoder,
                json!({"type":"response.output_item.added","output_index":index,
                "item":{"id":id,"type":"reasoning","summary":[],"encrypted_content":"cipher","signature":"opaque-signature"}}),
            );
            feed(
                &mut acc,
                &mut decoder,
                json!({"type":"response.reasoning_text.delta","item_id":id,"content_index":0,"delta":raw}),
            );
            feed(
                &mut acc,
                &mut decoder,
                json!({"type":"response.reasoning_summary_text.delta","item_id":id,"summary_index":0,"delta":"prefix"}),
            );
            feed(
                &mut acc,
                &mut decoder,
                json!({"type":"response.output_item.done","output_index":index,
                "item":{"id":id,"type":"reasoning","status":"completed",
                    "content":[{"type":"reasoning_text","text":raw}],
                    "summary":[{"type":"summary_text","text":summary}],
                    "encrypted_content":"cipher","signature":"opaque-signature","unknown":{"nested":[1,"untouched"]}}}),
            );
        }
        feed(
            &mut acc,
            &mut decoder,
            json!({"type":"response.output_item.added","output_index":3,
            "item":{"id":"tool-item","call_id":"call_0","type":"function_call","name":"read_file","arguments":"","signature":"native-tool-signature","unknown":{"x":true}}}),
        );
        let partial = "{\"path\":\"src/ma";
        feed(
            &mut acc,
            &mut decoder,
            json!({"type":"response.function_call_arguments.delta","item_id":"tool-item","call_id":"call_0","delta":partial}),
        );
        let (events, _) = tokio::sync::broadcast::channel(16);
        acc.apply(
            ModelStreamEvent::Usage(UsageReport {
                output_tokens: Some(17),
                ..Default::default()
            }),
            &events,
        )
        .unwrap();

        let saved = round_trip(&acc);
        assert_eq!(saved.response_id.as_deref(), Some("response-1"));
        assert_eq!(saved.attempt_id, "source-attempt");
        assert_eq!(saved.generation, 2);
        assert_eq!(
            saved.reasoning_summary_parts,
            ["first summary", "second summary"]
        );
        assert_eq!(saved.raw_reasoning_parts, ["first raw", "second raw"]);
        assert_eq!(saved.presentation_items.len(), 2);
        assert_eq!(saved.presentation_states.len(), 2);
        assert_eq!(
            saved
                .content_parts
                .iter()
                .find(|part| part.text == commentary)
                .unwrap()
                .text,
            commentary
        );
        assert_eq!(saved.tool_inputs.len(), 1);
        assert_eq!(saved.tool_inputs[0].input, partial);
        assert_eq!(
            saved.tool_inputs[0].provider_call_id.as_deref(),
            Some("call_0")
        );
        assert_eq!(saved.tool_inputs[0].item_id, "tool-item");
        assert_eq!(saved.tool_inputs[0].call_aliases, ["call_0"]);
        assert_eq!(
            saved.tool_inputs[0].phase,
            super::super::current::ModelStreamToolInputPhase::Streaming
        );
        assert!(
            saved.tool_calls.is_empty(),
            "capturing partial JSON must never construct a tool call"
        );
        assert_eq!(
            saved.replay.items[0].item["unknown"],
            json!({"nested":[1,"untouched"]})
        );
        assert_eq!(saved.replay.items[0].item["signature"], "opaque-signature");
        assert_eq!(
            saved.replay.pending_items.last().unwrap().item["signature"],
            "native-tool-signature"
        );
        assert_eq!(saved.final_usage.as_ref().unwrap().output_tokens, Some(17));
        assert!(!saved.usage_is_terminal);
        acc.cancel_attempt("cancelled while input incomplete", &events);
        let cancelled = round_trip(&acc);
        assert!(matches!(
            cancelled.state,
            ModelStreamCurrentState::Failed { .. }
        ));
        assert_eq!(cancelled.tool_inputs[0].input, partial);
        assert!(cancelled.tool_calls.is_empty());

        // Retry transport generations and new attempts each start with a fresh producer.
        let fresh = StreamCompletionAccumulator::with_model_observation(None, None, None);
        for (attempt, generation) in [("source-attempt", 3), ("next-attempt", 0)] {
            let view = fresh.current(attempt, generation);
            assert!(view.content_parts.is_empty());
            assert!(view.tool_inputs.is_empty());
            assert_ne!(
                (view.attempt_id.as_str(), view.generation),
                (saved.attempt_id.as_str(), saved.generation)
            );
        }
    }

    #[test]
    fn producer_current_preserves_late_tool_aliases_and_completed_native_replay() {
        let mut acc = StreamCompletionAccumulator::with_model_observation(None, None, None);
        let mut decoder = OpenAiStreamDecoder::new(VisibleOutputProtocol::NativePhases);
        feed(
            &mut acc,
            &mut decoder,
            json!({"type":"response.output_item.added","output_index":0,
            "item":{"id":"late-item","type":"function_call","name":"lookup"}}),
        );
        feed(
            &mut acc,
            &mut decoder,
            json!({"type":"response.function_call_arguments.delta","item_id":"late-item","call_id":"call_0","delta":"{\"q\":"}),
        );
        let pending = round_trip(&acc);
        assert_eq!(pending.tool_inputs.len(), 1);
        assert_eq!(
            pending.tool_inputs[0].provider_call_id.as_deref(),
            Some("call_0")
        );
        assert!(
            pending.tool_inputs[0]
                .call_aliases
                .contains(&"late-item".into())
        );
        assert!(
            pending.tool_inputs[0]
                .call_aliases
                .contains(&"call_0".into())
        );
        let item = json!({"id":"late-item","call_id":"call_0","type":"function_call","name":"lookup",
            "arguments":"{\"q\":1}","status":"completed","signature":"signed","future":{"flag":true}});
        feed(
            &mut acc,
            &mut decoder,
            json!({"type":"response.output_item.done","output_index":0,"item":item}),
        );
        feed(
            &mut acc,
            &mut decoder,
            json!({"type":"response.completed","response":{"id":"response-done","output":[item],"usage":{"output_tokens":3}}}),
        );
        let saved = round_trip(&acc);
        assert_eq!(saved.state, ModelStreamCurrentState::Completed);
        assert!(saved.usage_is_terminal);
        assert!(saved.tool_inputs.is_empty());
        assert_eq!(saved.tool_calls[0].call_id, "call_0");
        assert_eq!(saved.call_bindings[0].provider_item_id, "late-item");
        assert_ne!(saved.call_bindings[0].call_id, "call_0");
        assert_eq!(saved.replay.terminal.as_ref().unwrap()[0], item);
        let before = serde_json::to_value(acc.replay.current()).unwrap();
        acc.replay.finish().unwrap();
        acc.replay.finish().unwrap();
        assert_eq!(
            serde_json::to_value(acc.replay.current()).unwrap(),
            before,
            "completion validation must not consume the final handoff's native material"
        );
    }
}

#[cfg(test)]
mod member_tests {
    use super::*;
    use crate::completion::{CompletionPresentationItemKind, CompletionPresentationPartKind};
    use crate::runtime::ModelMemberState;

    fn member() -> CompletionPresentationItem {
        CompletionPresentationItem {
            provider_item_id: "real-provider-id".into(),
            output_index: Some(3),
            kind: CompletionPresentationItemKind::Reasoning,
            parts: vec![CompletionPresentationPart {
                content_index: 2,
                provider_part_id: Some("real-part-id".into()),
                kind: CompletionPresentationPartKind::SummaryText,
                text: "authoritative summary".into(),
            }],
        }
    }

    #[test]
    fn rejected_member_status_does_not_close_an_accepted_open_block() {
        let mut acc = StreamCompletionAccumulator::with_model_observation(None, None, None);
        let (events, _) = tokio::sync::broadcast::channel(16);
        acc.apply(
            ModelStreamEvent::reasoning_summary_started(
                "open-reasoning".into(),
                None,
                Some(super::super::event::ProviderBlockIdentity {
                    item_id: member().provider_item_id,
                    content_index: 2,
                }),
            ),
            &events,
        )
        .unwrap();
        assert!(
            acc.apply(
                ModelStreamEvent::PresentationItem {
                    item: member(),
                    state: None
                },
                &events
            )
            .is_err()
        );
        let saved = acc.current("source", 0);
        assert!(!saved.blocks[0].closed);
        assert!(saved.presentation_items.is_empty());
        assert!(saved.presentation_states.is_empty());
    }

    fn apply(
        acc: &mut StreamCompletionAccumulator,
        item: CompletionPresentationItem,
    ) -> Result<()> {
        let (events, _) = tokio::sync::broadcast::channel(16);
        acc.apply(
            ModelStreamEvent::PresentationItem {
                item,
                state: Some(ModelMemberState::Interrupted),
            },
            &events,
        )
    }

    #[test]
    fn authoritative_close_exposes_content_before_any_terminal_presentation_item() {
        let mut acc = StreamCompletionAccumulator::with_model_observation(None, None, None);
        let (events, _) = tokio::sync::broadcast::channel(16);
        acc.apply(
            ModelStreamEvent::text_started("text".into(), TraceTextChannel::Final, None),
            &events,
        )
        .unwrap();
        let starts = acc.take_started_members();
        assert_eq!(starts.len(), 1);
        assert!(acc.take_content_available_members().is_empty());
        acc.apply(
            ModelStreamEvent::text_completed(
                "text".into(),
                TraceTextChannel::Final,
                Some(" \n".into()),
                None,
            ),
            &events,
        )
        .unwrap();
        assert_eq!(acc.take_content_available_members(), starts);
        assert!(acc.take_content_available_members().is_empty());
        assert!(
            acc.take_completed_member().is_none(),
            "a block close does not invent an item terminal"
        );
    }

    #[test]
    fn complete_presentation_admits_content_once_per_nonempty_part() {
        let mut acc = StreamCompletionAccumulator::with_model_observation(None, None, None);
        let mut item = member();
        item.parts = ["", " ", "summary"]
            .into_iter()
            .enumerate()
            .map(|(index, text)| CompletionPresentationPart {
                content_index: index as u32,
                provider_part_id: None,
                kind: CompletionPresentationPartKind::SummaryText,
                text: text.into(),
            })
            .collect();
        apply(&mut acc, item.clone()).unwrap();
        assert_eq!(acc.take_started_members().len(), 3);
        let available = acc.take_content_available_members();
        let indexes: Vec<_> = available
            .iter()
            .map(|identity| {
                let ObservedPartIdentity::Provider(part) = identity else {
                    panic!("provider part");
                };
                part.content_index
            })
            .collect();
        assert_eq!(indexes, [1, 2]);
        apply(&mut acc, item).unwrap();
        assert!(acc.take_content_available_members().is_empty());
    }

    #[test]
    fn summary_delta_identity_and_budget_are_checked_before_start() {
        use super::super::event::ProviderBlockIdentity;
        let (events, _) = tokio::sync::broadcast::channel(16);
        for exhausted in [false, true] {
            let mut acc = StreamCompletionAccumulator::with_model_observation(None, None, None);
            let provider = ProviderBlockIdentity {
                item_id: "real-reasoning".into(),
                content_index: 3,
            };
            acc.apply(
                ModelStreamEvent::reasoning_summary_started(
                    "block".into(),
                    None,
                    Some(provider.clone()),
                ),
                &events,
            )
            .unwrap();
            assert!(
                acc.take_started_members().is_empty(),
                "an item placeholder has no real part"
            );
            let provider = if exhausted {
                acc.text_output_bytes = MAX_OUTPUT_BYTES;
                Some(provider)
            } else {
                None
            };
            let error = acc
                .apply(
                    ModelStreamEvent::reasoning_summary_delta(
                        "block".into(),
                        3,
                        "x".into(),
                        provider,
                    ),
                    &events,
                )
                .unwrap_err();
            if exhausted {
                assert!(matches!(error, PureError::MemoryError(_)));
            } else {
                assert!(
                    matches!(error, PureError::LlmError(message) if message.contains("no provider item identity"))
                );
            }
            assert!(acc.take_started_members().is_empty());
            assert!(acc.take_completed_member().is_none());
            assert!(
                acc.reasoning_parts(CompletionPresentationPartKind::SummaryText)
                    .is_empty()
            );
        }
    }

    #[test]
    fn validated_member_is_frozen_before_handoff_and_final_reuses_it() {
        let mut acc = StreamCompletionAccumulator::with_model_observation(None, None, None);
        let item = member();
        apply(&mut acc, item.clone()).unwrap();
        let starts = acc.take_started_members();
        assert_eq!(
            starts.len(),
            1,
            "only-final input starts its validated part before completion"
        );
        let ObservedPartIdentity::Provider(identity) = &starts[0] else {
            panic!("provider part");
        };
        assert_eq!(identity.item_id.as_ref(), item.provider_item_id);
        assert_eq!(identity.part, ObservedPartKind::SummaryText);
        assert_eq!(acc.take_content_available_members(), starts);
        let (completed, state) = acc.take_completed_member().unwrap();
        assert_eq!(completed, &item);
        assert_eq!(state, ModelMemberState::Interrupted);
        apply(&mut acc, item.clone()).unwrap();
        assert!(acc.take_started_members().is_empty());
        assert!(acc.take_content_available_members().is_empty());
        assert!(
            acc.take_completed_member().is_none(),
            "same authority does not resubmit"
        );
        let mut changed = item.clone();
        changed.parts[0].text = "overwrite".into();
        assert!(
            apply(&mut acc, changed)
                .unwrap_err()
                .to_string()
                .contains("conflicting")
        );
        assert_eq!(acc.presentation_items, vec![item.clone()]);
        let (events, _) = tokio::sync::broadcast::channel(16);
        acc.apply(
            ModelStreamEvent::Completed {
                response_id: Some("response".into()),
            },
            &events,
        )
        .unwrap();
        assert_eq!(acc.finish(&events).unwrap().presentation_items, vec![item]);
    }

    #[test]
    fn member_identity_parts_kind_and_budget_fail_without_handoff() {
        let base = member();
        let mut invalid = Vec::new();
        let mut item = base.clone();
        item.provider_item_id.clear();
        invalid.push(item);
        let mut item = base.clone();
        item.parts.push(item.parts[0].clone());
        invalid.push(item);
        let mut item = base.clone();
        let mut duplicate_index = item.parts[0].clone();
        duplicate_index.provider_part_id = Some("other-part-id".into());
        item.parts.push(duplicate_index);
        invalid.push(item);
        let mut item = base.clone();
        let mut duplicate_id = item.parts[0].clone();
        duplicate_id.content_index += 1;
        item.parts.push(duplicate_id);
        invalid.push(item);
        let mut item = base.clone();
        item.kind = CompletionPresentationItemKind::Text(TraceTextChannel::Final);
        invalid.push(item);
        let mut item = base;
        item.parts[0].text = "x".repeat(MAX_OUTPUT_BYTES);
        invalid.push(item);
        for item in invalid {
            let mut acc = StreamCompletionAccumulator::with_model_observation(None, None, None);
            assert!(apply(&mut acc, item).is_err());
            assert!(acc.take_started_members().is_empty());
            assert!(acc.take_content_available_members().is_empty());
            assert!(acc.take_completed_member().is_none());
            assert!(acc.presentation_items.is_empty());
        }
        let mut acc = StreamCompletionAccumulator::with_model_observation(None, None, None);
        let (events, _) = tokio::sync::broadcast::channel(16);
        assert!(
            acc.apply(
                ModelStreamEvent::PresentationItem {
                    item: member(),
                    state: None
                },
                &events
            )
            .is_err()
        );
        assert!(acc.take_completed_member().is_none());
        assert!(acc.take_started_members().is_empty());
        assert!(acc.take_content_available_members().is_empty());
        assert!(acc.presentation_items.is_empty());
    }
}
