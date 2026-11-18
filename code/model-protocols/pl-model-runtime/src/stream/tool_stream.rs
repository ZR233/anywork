use super::tool_identity::{ToolIdentity, resolve_key};
use std::collections::HashMap;

use pl_protocol::{PureError, Result};

use crate::completion::ToolCall;
use crate::completion::tool_arguments::function_tool_call_from_raw;

use super::current::{ModelStreamToolInput, ModelStreamToolInputPhase, scoped_call_id};
use super::event::ToolInputDeltaPayload;

pub(crate) struct ToolStream {
    accumulators: HashMap<String, ToolCallAccumulator>,
}

impl ToolStream {
    pub(crate) fn new() -> Self {
        Self {
            accumulators: HashMap::new(),
        }
    }

    pub(crate) fn append_delta(
        &mut self,
        stream_id: Option<&String>,
        item_id: String,
        call_id: Option<&String>,
        name: Option<String>,
        payload_delta: ToolInputDeltaPayload,
    ) {
        let key = self.resolve_key(stream_id, call_id, &item_id);
        let acc = self.get_or_insert_accumulator(&key, call_id, &item_id, || {
            ToolCallPayloadAccumulator::FunctionArguments(String::new())
        });
        acc.merge_metadata(stream_id, &item_id, call_id, name);
        acc.push_delta(payload_delta);
        acc.phase = ModelStreamToolInputPhase::Streaming;
    }

    pub(crate) fn start_input(
        &mut self,
        stream_id: Option<&String>,
        item_id: String,
        call_id: Option<&String>,
        name: Option<String>,
        payload: ToolInputDeltaPayload,
    ) {
        let key = self.resolve_key(stream_id, call_id, &item_id);
        let acc = self.get_or_insert_accumulator(&key, call_id, &item_id, || {
            ToolCallPayloadAccumulator::from_payload(payload)
        });
        acc.merge_metadata(stream_id, &item_id, call_id, name);
    }

    pub(crate) fn finish_ready(
        &mut self,
        stream_id: Option<&String>,
        call_id: Option<&String>,
        item_id: &str,
        name: Option<String>,
        payload: Option<ToolInputDeltaPayload>,
    ) -> Result<Option<ToolCall>> {
        let key = self.resolve_key(stream_id, call_id, item_id);
        let acc = self.get_or_insert_accumulator(&key, call_id, item_id, || {
            ToolCallPayloadAccumulator::FunctionArguments(String::new())
        });
        acc.merge_metadata(stream_id, item_id, call_id, name);
        if let Some(payload) = payload {
            acc.replace_payload(payload);
        }
        acc.validate_identity()?;
        Ok(Some(
            self.remove_accumulator(&key)
                .expect("validated tool input")
                .into_tool_call()?,
        ))
    }

    pub(crate) fn complete_input(
        &mut self,
        stream_id: Option<&String>,
        call_id: Option<&String>,
        item_id: &str,
        name: Option<String>,
        payload: Option<ToolInputDeltaPayload>,
    ) {
        let key = self.resolve_key(stream_id, call_id, item_id);
        let acc = self.get_or_insert_accumulator(&key, call_id, item_id, || {
            ToolCallPayloadAccumulator::FunctionArguments(String::new())
        });
        acc.merge_metadata(stream_id, item_id, call_id, name);
        if let Some(payload) = payload {
            acc.replace_payload(payload);
        }
        acc.phase = ModelStreamToolInputPhase::InputCompleted;
    }

    pub(crate) fn finish_all(&mut self, existing: &[ToolCall]) -> Result<Vec<ToolCall>> {
        // Check before moving accepted strings out, so a failed terminal remains capturable.
        for acc in self.accumulators.values() {
            if existing
                .iter()
                .any(|call| acc.matches_tool_call_identity(call))
            {
                continue;
            }
            acc.validate_identity()?;
        }
        let mut calls = Vec::new();
        for acc in std::mem::take(&mut self.accumulators).into_values() {
            if !existing
                .iter()
                .any(|call| acc.matches_tool_call_identity(call))
            {
                calls.push(acc.into_tool_call()?);
            }
        }
        Ok(calls)
    }

    /// Stable accumulator key one tool-input event resolves to, without mutating the stream.
    ///
    /// The model stream charges the incoming argument bytes against its reliable output domain
    /// *before* they are appended, so it needs the exact identity the append will land on rather
    /// than a second guess that could double-charge a Responses call whose `added` event exposes an
    /// item id while its deltas carry the call id.
    pub(crate) fn resolved_key(
        &self,
        stream_id: Option<&String>,
        call_id: Option<&String>,
        item_id: &str,
    ) -> String {
        self.resolve_key(stream_id, call_id, item_id)
    }

    fn resolve_key(
        &self,
        stream_id: Option<&String>,
        call_id: Option<&String>,
        item_id: &str,
    ) -> String {
        resolve_key(
            &self.accumulators,
            ToolCallAccumulator::identity,
            stream_id,
            call_id,
            item_id,
        )
    }

    fn remove_accumulator(&mut self, key: &str) -> Option<ToolCallAccumulator> {
        self.accumulators.remove(key)
    }

    fn get_or_insert_accumulator(
        &mut self,
        key: &str,
        call_id: Option<&String>,
        item_id: &str,
        payload: impl FnOnce() -> ToolCallPayloadAccumulator,
    ) -> &mut ToolCallAccumulator {
        self.accumulators
            .entry(key.to_string())
            .or_insert_with(|| ToolCallAccumulator::new(key, call_id, item_id, payload()))
    }

    /// Reserves one tool-input event's identity and returns its stable accumulator key.
    ///
    /// The live progress projection charges the argument bytes of the same events the canonical
    /// accumulator copies, so it has to key them by the exact identity the append will land on. It
    /// keeps no payload here; reserving the identity is enough for the following `delta` that omits
    /// the call id, or the `completed` that only carries the call id, to resolve onto the one call
    /// the start opened instead of being charged as a second, unrelated one.
    pub(crate) fn reserve_identity(
        &mut self,
        stream_id: Option<&String>,
        call_id: Option<&String>,
        item_id: &str,
    ) -> String {
        let key = self.resolve_key(stream_id, call_id, item_id);
        self.get_or_insert_accumulator(&key, call_id, item_id, || {
            ToolCallPayloadAccumulator::FunctionArguments(String::new())
        })
        .merge_metadata(stream_id, item_id, call_id, None);
        key
    }

    pub(crate) fn current(&self, attempt_id: &str) -> Vec<ModelStreamToolInput> {
        let mut inputs = self
            .accumulators
            .values()
            .map(|acc| {
                let (kind, input) = match &acc.payload {
                    ToolCallPayloadAccumulator::FunctionArguments(text) => {
                        (crate::completion::ToolCallKind::Function, text)
                    }
                    ToolCallPayloadAccumulator::CustomInput(text) => {
                        (crate::completion::ToolCallKind::Custom, text)
                    }
                };
                ModelStreamToolInput {
                    stream_id: acc.stream_id.clone(),
                    item_id: acc.id.clone(),
                    provider_call_id: acc.call_id.clone(),
                    call_id: scoped_call_id(attempt_id, acc.call_id.as_deref().unwrap_or(&acc.id)),
                    name: acc.name.clone(),
                    kind,
                    input: input.clone(),
                    phase: acc.phase,
                    stream_aliases: acc.stream_id.iter().cloned().collect(),
                    item_aliases: unique_identities(Some(&acc.initial_item_id), Some(&acc.id)),
                    call_aliases: unique_identities(
                        acc.initial_call_id.as_ref(),
                        acc.call_id.as_ref(),
                    ),
                }
            })
            .collect::<Vec<_>>();
        inputs.sort_by(|a, b| {
            a.stream_id
                .cmp(&b.stream_id)
                .then_with(|| a.item_id.cmp(&b.item_id))
        });
        inputs
    }
}

fn unique_identities(first: Option<&String>, current: Option<&String>) -> Vec<String> {
    let mut result = first
        .filter(|id| !id.is_empty())
        .cloned()
        .into_iter()
        .collect::<Vec<_>>();
    if let Some(current) = current.filter(|id| !id.is_empty())
        && !result.contains(current)
    {
        result.push(current.clone());
    }
    result
}

struct ToolCallAccumulator {
    id: String,
    initial_item_id: String,
    has_stable_id: bool,
    call_id: Option<String>,
    name: String,
    payload: ToolCallPayloadAccumulator,
    phase: ModelStreamToolInputPhase,
    stream_id: Option<String>,
    initial_call_id: Option<String>,
}

impl ToolCallAccumulator {
    fn identity(&self) -> ToolIdentity<'_> {
        ToolIdentity {
            item_id: &self.id,
            call_id: self.call_id.as_deref(),
            stable_item: self.has_stable_id,
        }
    }

    fn new(
        key: &str,
        call_id: Option<&String>,
        item_id: &str,
        payload: ToolCallPayloadAccumulator,
    ) -> Self {
        let initial_item_id = initial_item_id(call_id, item_id, key);
        Self {
            id: if item_id.is_empty() {
                key.to_string()
            } else {
                item_id.to_string()
            },
            initial_item_id,
            has_stable_id: !item_id.is_empty(),
            call_id: call_id
                .filter(|call_id| !call_id.is_empty())
                .map(ToOwned::to_owned),
            name: String::new(),
            payload,
            phase: ModelStreamToolInputPhase::Started,
            stream_id: None,
            initial_call_id: call_id.filter(|id| !id.is_empty()).cloned(),
        }
    }

    fn matches_tool_call_identity(&self, call: &ToolCall) -> bool {
        call.id == self.id
            || self
                .call_id
                .as_deref()
                .is_some_and(|call_id| call_id == call.call_id)
    }

    fn merge_metadata(
        &mut self,
        stream_id: Option<&String>,
        item_id: &str,
        call_id: Option<&String>,
        name: Option<String>,
    ) {
        // Preserve only identities actually used by the resolver: the first stream anchor, the
        // original trace/item fallback and the accepted canonical identity. Later unrelated
        // metadata which does not upgrade these fields is not an accepted alias or a seen-set.
        if self.stream_id.is_none() {
            self.stream_id = stream_id.filter(|id| !id.is_empty()).cloned();
        }
        if self.initial_call_id.is_none() {
            self.initial_call_id = call_id.filter(|id| !id.is_empty()).cloned();
        }
        let accepts_call_id = self.identity().accepts_call_id();
        if !item_id.is_empty() && !self.has_stable_id {
            self.id = item_id.to_string();
            self.has_stable_id = true;
        }
        if accepts_call_id && let Some(call_id) = call_id.filter(|call_id| !call_id.is_empty()) {
            self.call_id = Some(call_id.clone());
        }
        if let Some(name) = name
            && !name.is_empty()
        {
            self.name = name;
        }
    }

    fn push_delta(&mut self, payload_delta: ToolInputDeltaPayload) {
        match (&mut self.payload, payload_delta) {
            (
                ToolCallPayloadAccumulator::FunctionArguments(arguments),
                ToolInputDeltaPayload::FunctionArguments(delta),
            ) => arguments.push_str(&delta),
            (
                ToolCallPayloadAccumulator::CustomInput(input),
                ToolInputDeltaPayload::CustomInput(delta),
            ) => input.push_str(&delta),
            (_, ToolInputDeltaPayload::FunctionArguments(delta)) => {
                self.payload = ToolCallPayloadAccumulator::FunctionArguments(delta);
            }
            (_, ToolInputDeltaPayload::CustomInput(delta)) => {
                self.payload = ToolCallPayloadAccumulator::CustomInput(delta);
            }
        }
    }

    fn replace_payload(&mut self, payload: ToolInputDeltaPayload) {
        self.payload = match payload {
            ToolInputDeltaPayload::FunctionArguments(arguments) => {
                ToolCallPayloadAccumulator::FunctionArguments(arguments)
            }
            ToolInputDeltaPayload::CustomInput(input) => {
                ToolCallPayloadAccumulator::CustomInput(input)
            }
        };
    }

    fn validate_identity(&self) -> Result<()> {
        if self.name.is_empty() {
            return Err(PureError::LlmError(
                "provider emitted tool call without name".to_string(),
            ));
        }
        if !self.has_stable_id && self.call_id.as_ref().is_none_or(String::is_empty) {
            return Err(PureError::LlmError(
                "provider emitted tool call without stable id".to_string(),
            ));
        }
        Ok(())
    }

    fn into_tool_call(self) -> Result<ToolCall> {
        self.validate_identity()?;
        // call_id 必填：provider 只暴露 item id 时在解码边界确定性赋 call_id = item_id。
        let call_id = self
            .call_id
            .filter(|call_id| !call_id.is_empty())
            .unwrap_or_else(|| self.id.clone());
        match self.payload {
            ToolCallPayloadAccumulator::FunctionArguments(arguments) => Ok(
                function_tool_call_from_raw(self.id, self.name, arguments, call_id),
            ),
            ToolCallPayloadAccumulator::CustomInput(input) => {
                Ok(ToolCall::custom(self.id, self.name, input, call_id))
            }
        }
    }
}

enum ToolCallPayloadAccumulator {
    FunctionArguments(String),
    CustomInput(String),
}

impl ToolCallPayloadAccumulator {
    fn from_payload(payload: ToolInputDeltaPayload) -> Self {
        match payload {
            ToolInputDeltaPayload::FunctionArguments(arguments) => {
                Self::FunctionArguments(arguments)
            }
            ToolInputDeltaPayload::CustomInput(input) => Self::CustomInput(input),
        }
    }
}

fn initial_item_id(call_id: Option<&String>, id: &str, fallback_id: &str) -> String {
    if !id.is_empty() {
        return id.to_string();
    }
    call_id
        .filter(|call_id| !call_id.is_empty())
        .cloned()
        .unwrap_or_else(|| fallback_id.to_string())
}
