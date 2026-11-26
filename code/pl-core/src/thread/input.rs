//! Durable input admission, separate from model-request admission and execution.
use super::*;

/// Immutable host-authored input. Only `context` is placed in the user context record.
///
/// Only Message is admitted. The historical Continuation discriminator is decoded for old
/// stored observations; new execution intent is an explicit Resume owner command.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ThreadInput {
    pub id: String,
    #[serde(default)]
    pub purpose: InputPurpose,
    pub payload: OpaquePayload,
    pub context: Vec<ContextContent>,
}

/// Historical input discriminator; current admission accepts only Message.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum InputPurpose {
    /// Ordinary host message; its context becomes user context.
    #[default]
    Message,
    /// Historical control record, rejected by current admission.
    Continuation,
}

/// Opaque payload identity of the control input a continuation is submitted with.
///
/// Its content names the point and the Turn the continuation came from, so the control input stays
/// inspectable without carrying task content of its own.
pub const CONTINUATION_PAYLOAD_FORMAT: &str = "pl.core.thread-continuation";

/// Historical version of [`CONTINUATION_PAYLOAD_FORMAT`] accepted by display decoders.
pub const CONTINUATION_PAYLOAD_VERSION: u32 = 1;

impl ThreadInput {
    /// Rejects a purpose and a payload that contradict each other.
    ///
    /// Historical control discriminators and their reserved payload are never accepted as new
    /// messages. History display decodes those old observations at its own boundary.
    pub fn validate_purpose(&self) -> Result<(), ThreadError> {
        let control_payload = self.payload.format() == CONTINUATION_PAYLOAD_FORMAT;
        match self.purpose {
            // Framework control is never content: context would make it indistinguishable from a
            // user message, and a different payload would make the control unverifiable later.
            InputPurpose::Continuation => return Err(ThreadError::InvalidControlInput),
            InputPurpose::Message => {
                if control_payload {
                    return Err(ThreadError::InvalidControlInput);
                }
            }
        }
        Ok(())
    }

    /// Content digest used by the bounded identity ledger for duplicate submission checks.
    ///
    /// The digest covers the immutable host-authored body, never the framework routing receipt and
    /// never `purpose`: a purpose is framework intent, and changing how an already admitted body is
    /// routed must not read as a conflicting body.
    pub fn digest(&self) -> String {
        use sha2::{Digest, Sha256};
        let mut hasher = Sha256::new();
        hasher.update(self.id.as_bytes());
        hasher.update([0]);
        hasher.update(self.payload.format().as_bytes());
        hasher.update([0]);
        hasher.update(self.payload.content().as_bytes());
        for content in &self.context {
            hasher.update([0]);
            hasher.update(serde_json::to_vec(content).unwrap_or_default());
        }
        format!("sha256:{}", hex::encode(hasher.finalize()))
    }
}

/// Consumption is a framework fact, never inferred from the input's opaque payload.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(
    rename_all = "camelCase",
    tag = "kind",
    rename_all_fields = "camelCase"
)]
pub enum InputState {
    Pending,
    Consumed { turn_id: String, attempt_id: String },
    Discarded,
}

/// Input identity, FIFO ordinal and latest immutable state revision.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InputRecord {
    /// Commit that first admitted this input; retained unchanged after consumption.
    pub accepted_sequence: u64,
    pub input: ThreadInput,
    pub ordinal: u64,
    pub revision: u64,
    pub state: InputState,
}

/// Minimal resident identity of an admitted input that already reached a terminal state.
///
/// The live owner retains a bounded tail of these receipts after dropping terminal input bodies.
/// Duplicate detection ends when an identity leaves that window; admission never queries History.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InputIdentity {
    /// Content digest of the originally accepted body.
    pub digest: String,
    pub id: String,
    pub ordinal: u64,
    /// Purpose the original admission had, so a control operation stays recognisable after its body
    /// left the resident queue.
    #[serde(default)]
    pub purpose: InputPurpose,
    pub revision: u64,
    pub state: InputState,
}

impl InputIdentity {
    /// Projects one terminal input into its bounded owner receipt.
    /// Saving Current may preserve this window; no permanent input identity index is required.
    pub fn from_record(record: &InputRecord) -> Self {
        Self {
            digest: record.input.digest(),
            id: record.input.id.clone(),
            ordinal: record.ordinal,
            purpose: record.input.purpose,
            revision: record.revision,
            state: record.state.clone(),
        }
    }

    /// Rebuilds the framework receipt for a repeated, content-identical submission.
    pub fn receipt(&self, input: ThreadInput, accepted_sequence: u64) -> InputRecord {
        InputRecord {
            accepted_sequence,
            input,
            ordinal: self.ordinal,
            revision: self.revision,
            state: self.state.clone(),
        }
    }
}

/// Builds the minimal receipt of a terminal input record.
/// The receipt is serializable for explicit storage or upgrade consumers, but grants no
/// History lookup or permanent deduplication contract to normal input admission.
pub fn input_identity(record: &InputRecord) -> InputIdentity {
    InputIdentity::from_record(record)
}

/// Rebuilds one framework receipt from an already available identity.
///
/// The caller supplies the identity and its acceptance watermark; this helper performs no lookup
/// and does not admit or execute an input.
pub fn input_receipt(
    identity: &InputIdentity,
    input: ThreadInput,
    accepted_sequence: u64,
) -> InputRecord {
    identity.receipt(input, accepted_sequence)
}

pub(super) fn immediate_context_record_id(input_id: &str) -> String {
    format!("input:{input_id}")
}

impl InputRecord {
    /// Returns the framework context identity used when this input was actually admitted to a
    /// model call. A pending or metadata-only input has no model-visible record. Compaction may
    /// remove the record from current context while the original request and journal retain it.
    pub fn context_record_id(&self) -> Option<String> {
        let InputState::Consumed { .. } = &self.state else {
            return None;
        };
        (!self.input.context.is_empty()).then(|| immediate_context_record_id(&self.input.id))
    }
}

/// Input log operation. Consumption references the original identity instead of copying content again.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(
    rename_all = "camelCase",
    tag = "kind",
    content = "value",
    rename_all_fields = "camelCase"
)]
pub enum InputChange {
    Accepted(InputRecord),
    Transition {
        id: String,
        #[serde(default)]
        ordinal: u64,
        revision: u64,
        state: InputState,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        context_record_id: Option<String>,
        #[serde(default)]
        injected_mid_turn: bool,
    },
}

/// Host-selected bounds for execution, frozen separately for each Turn.
#[derive(Debug, Clone, Copy)]
pub struct InputDriverOptions {
    pub max_model_steps: crate::thread::ModelStepLimit,
}

/// Live execution observation. Restored history always begins paused.
#[derive(Debug, Clone, Default)]
pub enum InputExecution {
    #[default]
    Paused,
    Ready,
    Interrupting {
        turn_id: String,
    },
    Failed {
        error: Arc<ThreadError>,
    },
    Running {
        input_id: String,
    },
}

/// Execution authorization is independent from physical cancellation and pending input facts.
/// Notifications may wake an idle driver, but explicit stop/failure stays paused until resumed.
#[derive(Debug)]
pub(super) enum ExecutionDriver {
    Idle,
    Active(InputDriverOptions),
    Stopped,
    Failed(Arc<ThreadError>),
}

impl ExecutionDriver {
    pub(super) fn options(&self) -> Option<InputDriverOptions> {
        match self {
            Self::Active(options) => Some(*options),
            Self::Idle | Self::Stopped | Self::Failed(_) => None,
        }
    }

    pub(super) fn error(&self) -> Option<&Arc<ThreadError>> {
        match self {
            Self::Failed(error) => Some(error),
            _ => None,
        }
    }

    pub(super) fn enable(&mut self, options: InputDriverOptions) {
        *self = Self::Active(options);
    }

    pub(super) fn wake(&mut self, options: InputDriverOptions) {
        if matches!(self, Self::Idle | Self::Active(_)) {
            self.enable(options);
        }
    }

    pub(super) fn stop(&mut self) {
        if !matches!(self, Self::Failed(_)) {
            *self = Self::Stopped;
        }
    }

    pub(super) fn fail(&mut self, error: Arc<ThreadError>) {
        *self = Self::Failed(error);
    }
}

impl Owner {
    pub(super) fn drive_pending(&mut self, options: InputDriverOptions) -> Result<(), ThreadError> {
        if self.state.lifecycle != ThreadLifecycle::Open || self.interrupt.is_closing() {
            return Err(ThreadError::Closed);
        }
        // An explicit enable is a fresh user authorization after an earlier stop or failure.
        self.driver.enable(options);
        self.publish_snapshot();
        Ok(())
    }

    pub(super) fn pause_execution(&mut self) {
        self.driver.stop();
        self.publish_snapshot();
    }

    pub(super) fn has_pending_immediate_inputs(&self) -> bool {
        self.state.inputs.iter().any(|record| self.driveable(record))
    }

    pub(super) fn first_pending_input_id(&self) -> Option<String> {
        self.state
            .inputs
            .iter()
            .filter(|record| self.driveable(record))
            .min_by_key(|record| record.ordinal)
            .map(|record| record.input.id.clone())
    }

    pub(super) fn start_immediate_work(&mut self) -> Result<bool, ThreadError> {
        if self.state.lifecycle != ThreadLifecycle::Open
            || self.interrupt.is_closing()
            || !self.continuation_ready()
        {
            return Ok(false);
        }
        let Some(options) = self.driver.options() else {
            return Ok(false);
        };
        let primary_input_id = self.first_pending_input_id();
        let source = if let Some(input_id) = &primary_input_id {
            format!("input:{input_id}")
        } else if self.state.wake_messages_through > self.state.consumed_messages {
            format!("message:{}", self.state.wake_messages_through)
        } else {
            return Ok(false);
        };
        let turn_id = format!("{source}:{}", uuid::Uuid::new_v4());
        let mut input = TurnInput {
            turn_id: turn_id.clone(),
            attempt_prefix: turn_id,
            content: Vec::new(),
            max_model_steps: options.max_model_steps,
            cancellation: CancellationToken::new(),
        };
        let restored = self.current_saved_lifecycle.is_some();
        if restored {
            input = self
                .prepare_current_resume(self.runtime_epoch, self.interrupt.stops(), input)
                .map_err(|e| ThreadError::CurrentResume(Arc::new(e)))?;
        }
        self.start_run(input, super::execution::RunReply::Driver, primary_input_id)
            .map_err(|(error, _)| error)?;
        self.active.as_mut().unwrap().restored = restored;
        Ok(true)
    }

    pub(super) fn submit_immediate_input(
        &mut self,
        input: ThreadInput,
        drive: Option<InputDriverOptions>,
    ) -> Result<InputRecord, ThreadError> {
        if input.id.is_empty() {
            return Err(ThreadError::InvalidIdentity);
        }
        input.validate_purpose()?;
        if let Some(receipt) = self.duplicate_input_receipt(&input)? {
            return Ok(receipt);
        }
        if self.state.lifecycle != ThreadLifecycle::Open || self.interrupt.is_closing() {
            return Err(ThreadError::Closed);
        }
        self.refresh_storage_pressure();
        self.publish_snapshot();
        if self.state.persistence.pressure_paused {
            return Err(ThreadError::StoragePressure);
        }
        if let Some(error) = &self.cold_error {
            return Err(ThreadError::Storage(error.clone()));
        }
        let record = stage_input(&mut self.state, input)?;
        if let Some(options) = drive {
            self.driver.enable(options);
        }
        if self.active.is_some() {
            if self.has_pending_model_switch()
                && !self.interrupt.is_closing()
                && self.stopping_turn.is_none()
            {
                let turn_id = self
                    .active
                    .as_ref()
                    .expect("active run checked above")
                    .input
                    .turn_id
                    .clone();
                self.stopping_turn = Some(turn_id.clone());
                if let Some(run) = self.active.as_ref() {
                    run.turn_cancel.cancel();
                }
                self.cancel_turn_tasks(&turn_id)?;
            } else {
                self.preempt_or_wake_active_run(&record.input.id, true);
            }
        }
        self.publish()?;
        self.publish_snapshot();
        Ok(record)
    }

    /// Answers a repeated submission from bounded current state.
    ///
    /// A still-pending input keeps its full record; an already-consumed or discarded input is
    /// answered from its identity ledger entry by comparing the immutable content digest.
    fn duplicate_input_receipt(
        &self,
        input: &ThreadInput,
    ) -> Result<Option<InputRecord>, ThreadError> {
        duplicate_input_receipt(&self.state, input)
    }

    pub(super) fn discard_input(&mut self, id: &str) -> Result<InputRecord, ThreadError> {
        if self.state.lifecycle == ThreadLifecycle::Closed {
            return Err(ThreadError::Closed);
        }
        let previous = self
            .state
            .inputs
            .iter()
            .find(|record| record.input.id == id)
            .ok_or(ThreadError::InvalidIdentity)?;
        match previous.state {
            InputState::Discarded => return Ok(previous.clone()),
            InputState::Consumed { .. } => return Err(ThreadError::InputConsumed),
            InputState::Pending => {}
        }
        if self
            .active
            .as_ref()
            .is_some_and(|run| run.current_step_inputs.iter().any(|active| active == id))
        {
            return Err(ThreadError::InputInUse);
        }
        let record = self.change_input(id, InputState::Discarded, false)?;
        self.publish()?;
        Ok(record)
    }

    /// Projects every currently pending driveable input in strict FIFO ordinal order, keeping each
    /// message as its own `ContextSource::User` record without flattening boundaries.
    pub(super) fn pending_immediate_context(&self, turn_id: &str) -> (Vec<ContextRecord>, Vec<String>) {
        let mut pending: Vec<_> = self
            .state
            .inputs
            .iter()
            .filter(|record| self.driveable(record))
            .collect();
        pending.sort_by_key(|record| record.ordinal);
        let mut records = Vec::with_capacity(pending.len());
        let mut ids = Vec::with_capacity(pending.len());
        for record in pending {
            ids.push(record.input.id.clone());
            if !record.input.context.is_empty() {
                records.push(ContextRecord {
                    id: immediate_context_record_id(&record.input.id),
                    turn_id: Some(turn_id.into()),
                    source: ContextSource::User,
                    content: record.input.context.clone(),
                    tool_calls: Vec::new(),
                });
            }
        }
        (records, ids)
    }

    pub(super) fn validate_pending_inputs(&self, ids: &[String]) -> Result<(), ThreadError> {
        if ids.iter().any(|id| {
            !self
                .state
                .inputs
                .iter()
                .any(|record| &record.input.id == id && record.state == InputState::Pending)
        }) {
            return Err(ThreadError::InputConsumed);
        }
        Ok(())
    }

    pub(super) fn consume_pending_inputs(
        &mut self,
        ids: &[String],
        turn_id: &str,
        attempt_id: &str,
    ) -> Result<(), ThreadError> {
        let turn_step_zero = self.active.as_ref().is_some_and(|r| r.steps == 0);
        let primary_input_id = self
            .active
            .as_ref()
            .and_then(|r| r.primary_input_id.clone());
        for id in ids {
            let is_turn_initiator =
                turn_step_zero && primary_input_id.as_deref() == Some(id.as_str());
            self.change_input(
                id,
                InputState::Consumed {
                    turn_id: turn_id.into(),
                    attempt_id: attempt_id.into(),
                },
                !is_turn_initiator,
            )?;
        }
        Ok(())
    }

    pub(super) fn change_input(
        &mut self,
        id: &str,
        state: InputState,
        injected_mid_turn: bool,
    ) -> Result<InputRecord, ThreadError> {
        let mut inputs = self.state.inputs.to_vec();
        let record = inputs
            .iter_mut()
            .find(|record| record.input.id == id)
            .ok_or(ThreadError::InvalidIdentity)?;
        record.revision = record
            .revision
            .checked_add(1)
            .ok_or(ThreadError::RevisionExhausted)?;
        record.state = state;
        let record = record.clone();
        self.state.inputs = inputs.into();
        self.append_input_change(InputChange::Transition {
            id: record.input.id.clone(),
            ordinal: record.ordinal,
            revision: record.revision,
            state: record.state.clone(),
            context_record_id: record.context_record_id(),
            injected_mid_turn: matches!(record.state, InputState::Consumed { .. })
                && injected_mid_turn,
        });
        Ok(record)
    }

    fn append_input_change(&mut self, record: InputChange) {
        let mut changes = self.state.input_changes.to_vec();
        changes.push(record);
        self.state.input_changes = changes.into();
    }
}

/// Answers a repeated input submission from bounded current state.
///
/// A still-pending input keeps its full record; a terminal input is answered from the bounded
/// identity window by comparing the immutable content digest. An identity older than that window
/// is unknown to admission; the owner never asks a host or History to recover it.
/// A repeated id with a different body stays an identity conflict.
pub(super) fn duplicate_input_receipt(
    state: &ThreadSnapshot,
    input: &ThreadInput,
) -> Result<Option<InputRecord>, ThreadError> {
    if let Some(previous) = state
        .inputs
        .iter()
        .find(|record| record.input.id == input.id)
    {
        if previous.input != *input {
            return Err(ThreadError::InvalidIdentity);
        }
        return Ok(Some(previous.clone()));
    }
    let Some(identity) = state
        .terminal_inputs
        .iter()
        .find(|identity| identity.id == input.id)
    else {
        return Ok(None);
    };
    if identity.digest != input.digest() {
        return Err(ThreadError::InvalidIdentity);
    }
    Ok(Some(identity.receipt(input.clone(), state.commit_sequence)))
}

/// Stages input as part of an already-admitted control transaction, without starting execution.
pub(super) fn stage_input(
    state: &mut ThreadSnapshot,
    input: ThreadInput,
) -> Result<InputRecord, ThreadError> {
    if input.id.is_empty() {
        return Err(ThreadError::InvalidIdentity);
    }
    input.validate_purpose()?;
    if let Some(previous) = state
        .inputs
        .iter()
        .find(|record| record.input.id == input.id)
    {
        return if previous.input == input {
            Ok(previous.clone())
        } else {
            Err(ThreadError::InvalidIdentity)
        };
    }
    if state.lifecycle != ThreadLifecycle::Open {
        return Err(ThreadError::Closed);
    }
    let ordinal = state
        .input_ordinal
        .checked_add(1)
        .ok_or(ThreadError::RevisionExhausted)?;
    state.input_ordinal = ordinal;
    let record = InputRecord {
        accepted_sequence: state
            .commit_sequence
            .checked_add(1)
            .ok_or(ThreadError::RevisionExhausted)?,
        input,
        ordinal,
        revision: 1,
        state: InputState::Pending,
    };
    let mut inputs = state.inputs.to_vec();
    inputs.push(record.clone());
    state.inputs = inputs.into();
    let mut changes = state.input_changes.to_vec();
    changes.push(InputChange::Accepted(record.clone()));
    state.input_changes = changes.into();
    Ok(record)
}
