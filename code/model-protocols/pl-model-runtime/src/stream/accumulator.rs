//! 规范流事实、可靠成员边界与完整 Current 捕获的唯一累积器。

use crate::runtime::model_part_identity::{
    PartKey, observation, observed_part_kind, part_key, provider_observation,
};
use pl_core::model::{AggregateChannel, ObservedItemKind, ObservedPartIdentity, ObservedPartKind};
use std::collections::HashMap;

use crate::completion::ModelTextChannel;
use crate::completion::{
    InferenceModelObservation, InferenceOrchestrationMetrics, ResponsesContextItem,
    ResponsesContextItemKind, ToolCallCaller,
};
use crate::model::UsageReport;
use pl_protocol::{PureError, Result};

use crate::completion::{
    CompletionPresentationItem, CompletionPresentationPart, CompletionResponse, ToolCall,
};

use super::current::{
    ModelCallIdentity, ModelStreamBlock, ModelStreamContentPart, ModelStreamCurrent,
    ModelStreamCurrentState, ModelStreamMember,
};
use super::event::{
    ModelBlockContent, ModelBlockField, ModelBlockKind, ModelStreamEvent, ToolInputDeltaPayload,
};
use super::lifecycle::{self, StreamLifecycle};
use super::tool_stream::ToolStream;
use crate::completion::CompletionPresentationPartKind;

use super::MAX_COMPLETION_OUTPUT_BYTES as MAX_OUTPUT_BYTES;

pub(crate) struct StreamCompletionAccumulator {
    content_parts: Vec<ModelStreamContentPart>,
    content_indexes: HashMap<String, usize>,
    blocks: Vec<ModelStreamBlock>,
    /// Derived lookup by block or provider item identity; the ordered blocks remain the source.
    block_indexes: HashMap<String, Vec<usize>>,
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
    latest_usage: Option<(UsageReport, bool)>,
    response_id: Option<String>,
    model_observation: Option<InferenceModelObservation>,
    reported_model_is_terminal: bool,
    state: ModelStreamCurrentState,
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
            settlement: None,
            attempt_id: attempt_id.into(),
            generation,
            previous_generations: Vec::new(),
            state: self.state.clone(),
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
            final_usage: self.latest_usage.as_ref().map(|(usage, _)| usage.clone()),
            usage_is_terminal: self.usage_is_terminal(),
        }
    }

    pub(crate) fn new(model_observation: Option<InferenceModelObservation>) -> Self {
        Self {
            content_parts: Vec::new(),
            content_indexes: HashMap::new(),
            blocks: Vec::new(),
            block_indexes: HashMap::new(),
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
            latest_usage: None,
            response_id: None,
            model_observation,
            reported_model_is_terminal: false,
            state: ModelStreamCurrentState::Open,
        }
    }

    pub(crate) fn set_model_observation(&mut self, observation: InferenceModelObservation) {
        self.model_observation = Some(observation);
    }

    pub(crate) fn normalize(
        &mut self,
        stream_event: ModelStreamEvent,
    ) -> Result<Vec<ModelStreamEvent>> {
        match &self.state {
            ModelStreamCurrentState::Open => {}
            ModelStreamCurrentState::Completed => {
                return Err(PureError::LlmError(
                    "provider stream emitted event after completion".to_string(),
                ));
            }
            ModelStreamCurrentState::Failed { message } => {
                return Err(PureError::LlmError(format!(
                    "provider stream emitted event after failure: {}",
                    message
                )));
            }
        }
        self.lifecycle.normalize(stream_event)
    }

    pub(crate) fn apply_normalized(&mut self, stream_event: ModelStreamEvent) -> Result<()> {
        let starts = self.started_identities(&stream_event)?;
        let content_available = self.content_available_identities(&stream_event)?;
        self.record_block_state(&stream_event)?;
        match stream_event {
            ModelStreamEvent::BlockOpened { .. } => {}
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
            }
            ModelStreamEvent::BlockClosed {
                id,
                kind: ModelBlockKind::ReasoningSummary,
                authoritative_content,
                provider,
                ..
            } => {
                if let Some(ModelBlockContent::ReasoningSummary(summary)) = authoritative_content {
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
                }
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
                self.tool_stream.start_input(
                    stream_id.as_ref(),
                    item_id,
                    call_id.as_ref(),
                    name,
                    lifecycle::tool_start_payload(payload_kind),
                );
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
                self.tool_stream.append_delta(
                    stream_id.as_ref(),
                    item_id,
                    call_id.as_ref(),
                    name,
                    payload_delta,
                );
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
            ModelStreamEvent::NativeContext { payload } => {
                self.responses_context_items.push(
                    crate::completion::ResponsesContextItem::from_payload(&payload)?,
                );
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
                if let Some(indexes) = self.block_indexes.get(&id) {
                    for &index in indexes {
                        let block = &mut self.blocks[index];
                        if block.provider_item_id.as_deref() == Some(id.as_str()) {
                            block.closed = true;
                        }
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
            ModelStreamEvent::WebSearchStarted { .. } => {}
            ModelStreamEvent::WebSearchCompleted { .. } => {}
            ModelStreamEvent::Usage { usage, terminal } => {
                self.latest_usage = Some((usage, terminal));
            }
            ModelStreamEvent::Completed { response_id } => {
                for mut call in self.tool_stream.finish_all(&self.tool_calls)? {
                    self.attach_tool_caller(&mut call);

                    self.tool_calls.push(call);
                }
                if response_id.is_some() {
                    self.response_id = response_id;
                }
                for block in &mut self.blocks {
                    block.closed = true;
                }
                self.state = ModelStreamCurrentState::Completed;
            }
            ModelStreamEvent::Failed { failure } => {
                self.state = ModelStreamCurrentState::Failed {
                    message: failure.message.clone(),
                };
                return Err(failure.into());
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
                        ObservedItemKind::Text(channel)
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

    pub(crate) fn finish(&mut self) -> Result<CompletionResponse> {
        self.finish_inner()
    }

    fn finish_inner(&mut self) -> Result<CompletionResponse> {
        let terminal_error = match &self.state {
            ModelStreamCurrentState::Open => Some(
                pl_model_wire::provider_error::transport_failure(
                    pl_protocol::ProviderFailureStage::Stream,
                    "provider stream ended before completion",
                )
                .into(),
            ),
            ModelStreamCurrentState::Completed => None,
            ModelStreamCurrentState::Failed { message } => {
                Some(PureError::LlmError(message.to_string()))
            }
        };
        if let Some(error) = terminal_error {
            self.fail_attempt(&error);
            return Err(error);
        }

        for mut call in self.tool_stream.finish_all(&self.tool_calls)? {
            self.attach_tool_caller(&mut call);

            self.tool_calls.push(call);
        }

        let final_parts = self
            .content_parts
            .iter()
            .filter(|part| {
                part.kind == CompletionPresentationPartKind::OutputText
                    && self
                        .block_indexes
                        .get(&part.block_id)
                        .is_some_and(|indexes| {
                            indexes.iter().any(|&index| {
                                let block = &self.blocks[index];
                                block.id == part.block_id
                                    && block.channel == Some(ModelTextChannel::Final)
                            })
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
        let (usage, usage_is_terminal) = self.latest_usage.take().unwrap_or_default();
        let mut response = CompletionResponse {
            settlements: Vec::new(),
            response_id: self.response_id.take(),
            content,
            replay,
            reasoning_content,
            tool_calls: std::mem::take(&mut self.tool_calls),
            responses_context_items: std::mem::take(&mut self.responses_context_items),
            presentation_items: self.take_presentation_items(),
            orchestration,
            timing: None,
            accounting: crate::model::InferenceAccounting {
                usage,
                ..Default::default()
            },
            usage_is_terminal,
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

    pub(super) fn accounting(&self) -> crate::model::InferenceAccounting {
        crate::model::InferenceAccounting {
            usage: self
                .latest_usage
                .as_ref()
                .map(|(usage, _)| usage.clone())
                .unwrap_or_default(),
            ..Default::default()
        }
    }

    pub(super) fn usage_is_terminal(&self) -> bool {
        self.latest_usage
            .as_ref()
            .is_some_and(|(_, terminal)| *terminal)
    }

    pub(crate) fn fail_attempt(&mut self, error: &PureError) {
        self.state = ModelStreamCurrentState::Failed {
            message: error.to_string(),
        };
    }

    pub(super) fn cancel_attempt(&mut self, reason: &str) {
        self.state = ModelStreamCurrentState::Failed {
            message: reason.to_string(),
        };
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
        let existing = self.block_indexes.get(id).and_then(|indexes| {
            indexes.iter().copied().find(|&index| {
                let block = &self.blocks[index];
                block.id == *id && block.kind == kind && block.channel == channel
            })
        });
        if let Some(index) = existing {
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
        let index_bytes = |key: &str| {
            std::mem::size_of::<usize>()
                + if self.block_indexes.contains_key(key) {
                    0
                } else {
                    std::mem::size_of::<(String, Vec<usize>)>() + key.len()
                }
        };
        let bytes = std::mem::size_of::<ModelStreamBlock>()
            + id.len()
            + provider.map_or(0, |provider| provider.item_id.len())
            + index_bytes(id)
            + provider
                .filter(|provider| provider.item_id != *id)
                .map_or(0, |provider| index_bytes(&provider.item_id));
        let next = self
            .block_bytes
            .checked_add(bytes)
            .filter(|bytes| *bytes <= MAX_OUTPUT_BYTES)
            .ok_or_else(|| {
                PureError::MemoryError("provider block identities exceed 16 MiB".into())
            })?;
        self.replay.replace_block_metadata(None, owned_metadata)?;
        let index = self.blocks.len();
        self.blocks.push(ModelStreamBlock {
            id: id.clone(),
            kind,
            channel,
            provider_item_id: provider.map(|part| part.item_id.clone()),
            provider_metadata: owned_metadata.cloned(),
            closed,
        });
        self.block_indexes
            .entry(id.clone())
            .or_default()
            .push(index);
        if let Some(provider) = provider
            && provider.item_id != *id
        {
            self.block_indexes
                .entry(provider.item_id.clone())
                .or_default()
                .push(index);
        }
        self.block_bytes = next;
        Ok(())
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
mod test_support {
    use super::*;

    pub(super) fn apply_event(
        accumulator: &mut StreamCompletionAccumulator,
        event: ModelStreamEvent,
    ) -> Result<()> {
        for event in accumulator.normalize(event)? {
            accumulator.apply_normalized(event)?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod current_tests {
    use super::test_support::apply_event;
    use super::*;
    use pl_model_openai_wire::OPENAI_WIRE_CODEC;
    use pl_model_wire::protocol::WireApi;
    use pl_model_wire::provider_error::{
        ErrorObservedAt, ProviderErrorContext, ProviderErrorEntry, StreamFrameContext,
    };
    use pl_model_wire::wire_codec::{WireCodec, WireStreamDecoder};
    use serde_json::json;

    fn feed(
        acc: &mut StreamCompletionAccumulator,
        decoder: &mut Box<dyn WireStreamDecoder>,
        wire: serde_json::Value,
    ) {
        let context = StreamFrameContext {
            policy: pl_model_openai::adapter::COMPATIBLE_ADAPTER.error_policy,
            entry: ProviderErrorEntry::Sse,
            event_name: None,
            wire_api: WireApi::Responses,
            endpoint: None,
            failure: ProviderErrorContext {
                stage: pl_protocol::ProviderFailureStage::Stream,
                request_id: None,
                http_status: None,
                observed_at: ErrorObservedAt::now(),
                header_retry: Default::default(),
                redact: &str::to_owned,
            },
        };
        for event in decoder
            .decode_frame(&wire.to_string(), &context)
            .unwrap()
            .events
        {
            apply_event(acc, event).unwrap();
        }
    }

    fn snapshot(acc: &StreamCompletionAccumulator) -> ModelStreamCurrent {
        acc.current("source-attempt", 2)
    }

    #[test]
    fn current_summary_uses_provider_part_index_not_trace_section_number() {
        use super::super::event::ProviderBlockIdentity;
        let mut acc = StreamCompletionAccumulator::new(None);

        let provider = Some(ProviderBlockIdentity {
            item_id: "reasoning".into(),
            content_index: 7,
        });
        apply_event(
            &mut acc,
            ModelStreamEvent::reasoning_summary_started("block".into(), None, provider.clone()),
        )
        .unwrap();
        for (section, text) in [(0, "first"), (1, " second")] {
            apply_event(
                &mut acc,
                ModelStreamEvent::reasoning_summary_delta(
                    "block".into(),
                    section,
                    text.into(),
                    provider.clone(),
                ),
            )
            .unwrap();
        }
        let saved = snapshot(&acc);
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
        let mut acc = StreamCompletionAccumulator::new(None);
        let mut decoder = OPENAI_WIRE_CODEC.new_stream_decoder(WireApi::Responses);
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
        let saved = snapshot(&acc);
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

        assert!(
            apply_event(&mut acc, oversized).is_err(),
            "the existing presentation ceiling must still reject oversized output"
        );
        assert_eq!(acc.presentation_items.len(), 1);
    }

    #[test]
    fn current_tool_aliases_retain_only_actual_local_identity_upgrades() {
        use super::super::event::ToolInputPayloadKind;
        let mut acc = StreamCompletionAccumulator::new(None);

        apply_event(
            &mut acc,
            ModelStreamEvent::ToolInputStarted {
                stream_id: Some("stream".into()),
                item_id: "real-item".into(),
                call_id: Some("real-item".into()),
                name: Some("lookup".into()),
                payload_kind: ToolInputPayloadKind::FunctionArguments,
            },
        )
        .unwrap();
        apply_event(
            &mut acc,
            ModelStreamEvent::ToolInputDelta {
                stream_id: Some("stream".into()),
                item_id: "real-item".into(),
                call_id: Some("real-call".into()),
                name: None,
                payload_delta: ToolInputDeltaPayload::FunctionArguments("{\"q\":".into()),
            },
        )
        .unwrap();
        for index in 0..2048 {
            apply_event(
                &mut acc,
                ModelStreamEvent::ToolInputDelta {
                    stream_id: Some("stream".into()),
                    item_id: format!("unused-item-{index}"),
                    call_id: Some(format!("unused-call-{index}")),
                    name: None,
                    payload_delta: ToolInputDeltaPayload::FunctionArguments(String::new()),
                },
            )
            .unwrap();
        }
        let saved = snapshot(&acc);
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
        let mut acc = StreamCompletionAccumulator::new(None);
        let mut decoder = OPENAI_WIRE_CODEC.new_stream_decoder(WireApi::Responses);
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
        let open = snapshot(&acc);
        assert_eq!(open.state, ModelStreamCurrentState::Open);
        assert_eq!(open.content_parts[0].text, commentary);
        assert!(
            open.blocks
                .iter()
                .any(|block| block.channel == Some(ModelTextChannel::Commentary) && !block.closed)
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

        apply_event(
            &mut acc,
            ModelStreamEvent::Usage {
                usage: UsageReport {
                    output_tokens: Some(17),
                    ..Default::default()
                },
                terminal: false,
            },
        )
        .unwrap();

        let saved = snapshot(&acc);
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
        acc.cancel_attempt("cancelled while input incomplete");
        let cancelled = snapshot(&acc);
        assert!(matches!(
            cancelled.state,
            ModelStreamCurrentState::Failed { .. }
        ));
        assert_eq!(cancelled.tool_inputs[0].input, partial);
        assert!(cancelled.tool_calls.is_empty());

        // Retry transport generations and new attempts each start with a fresh producer.
        let fresh = StreamCompletionAccumulator::new(None);
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
    fn latest_usage_replaces_both_the_cumulative_sample_and_its_terminal_marker() {
        let mut acc = StreamCompletionAccumulator::new(None);
        for (output_tokens, terminal) in [(2, true), (3, false)] {
            apply_event(
                &mut acc,
                ModelStreamEvent::Usage {
                    usage: UsageReport {
                        output_tokens: Some(output_tokens),
                        ..Default::default()
                    },
                    terminal,
                },
            )
            .unwrap();
            let snapshot = snapshot(&acc);
            assert_eq!(
                snapshot.final_usage.unwrap().output_tokens,
                Some(output_tokens)
            );
            assert_eq!(snapshot.usage_is_terminal, terminal);
        }
    }

    #[test]
    fn producer_current_preserves_late_tool_aliases_and_completed_native_replay() {
        let mut acc = StreamCompletionAccumulator::new(None);
        let mut decoder = OPENAI_WIRE_CODEC.new_stream_decoder(WireApi::Responses);
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
        let pending = snapshot(&acc);
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
        let saved = snapshot(&acc);
        assert_eq!(saved.state, ModelStreamCurrentState::Completed);
        assert!(saved.usage_is_terminal);
        assert_eq!(saved.final_usage.unwrap().output_tokens, Some(3));
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
    use super::test_support::apply_event;
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
        let mut acc = StreamCompletionAccumulator::new(None);

        apply_event(
            &mut acc,
            ModelStreamEvent::reasoning_summary_started(
                "open-reasoning".into(),
                None,
                Some(super::super::event::ProviderBlockIdentity {
                    item_id: member().provider_item_id,
                    content_index: 2,
                }),
            ),
        )
        .unwrap();
        assert!(
            apply_event(
                &mut acc,
                ModelStreamEvent::PresentationItem {
                    item: member(),
                    state: None
                }
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
        apply_event(
            acc,
            ModelStreamEvent::PresentationItem {
                item,
                state: Some(ModelMemberState::Interrupted),
            },
        )
    }

    #[test]
    fn authoritative_close_exposes_content_before_any_terminal_presentation_item() {
        let mut acc = StreamCompletionAccumulator::new(None);

        apply_event(
            &mut acc,
            ModelStreamEvent::text_started("text".into(), ModelTextChannel::Final, None),
        )
        .unwrap();
        let starts = acc.take_started_members();
        assert_eq!(starts.len(), 1);
        assert!(acc.take_content_available_members().is_empty());
        apply_event(
            &mut acc,
            ModelStreamEvent::text_completed(
                "text".into(),
                ModelTextChannel::Final,
                Some(" \n".into()),
                None,
            ),
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
        let mut acc = StreamCompletionAccumulator::new(None);
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

        for exhausted in [false, true] {
            let mut acc = StreamCompletionAccumulator::new(None);
            let provider = ProviderBlockIdentity {
                item_id: "real-reasoning".into(),
                content_index: 3,
            };
            apply_event(
                &mut acc,
                ModelStreamEvent::reasoning_summary_started(
                    "block".into(),
                    None,
                    Some(provider.clone()),
                ),
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
            let error = apply_event(
                &mut acc,
                ModelStreamEvent::reasoning_summary_delta("block".into(), 3, "x".into(), provider),
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
        let mut acc = StreamCompletionAccumulator::new(None);
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

        apply_event(
            &mut acc,
            ModelStreamEvent::Completed {
                response_id: Some("response".into()),
            },
        )
        .unwrap();
        assert_eq!(acc.finish().unwrap().presentation_items, vec![item]);
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
        item.kind = CompletionPresentationItemKind::Text(ModelTextChannel::Final);
        invalid.push(item);
        let mut item = base;
        item.parts[0].text = "x".repeat(MAX_OUTPUT_BYTES);
        invalid.push(item);
        for item in invalid {
            let mut acc = StreamCompletionAccumulator::new(None);
            assert!(apply(&mut acc, item).is_err());
            assert!(acc.take_started_members().is_empty());
            assert!(acc.take_content_available_members().is_empty());
            assert!(acc.take_completed_member().is_none());
            assert!(acc.presentation_items.is_empty());
        }
        let mut acc = StreamCompletionAccumulator::new(None);

        assert!(
            apply_event(
                &mut acc,
                ModelStreamEvent::PresentationItem {
                    item: member(),
                    state: None
                }
            )
            .is_err()
        );
        assert!(acc.take_completed_member().is_none());
        assert!(acc.take_started_members().is_empty());
        assert!(acc.take_content_available_members().is_empty());
        assert!(acc.presentation_items.is_empty());
    }
}
