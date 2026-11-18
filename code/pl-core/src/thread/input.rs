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

/// Host-selected input routing policy, evaluated atomically by the Thread owner.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum InputPolicy {
    #[default]
    StartOrSteer,
    StartOrQueue,
    StartOnly,
    SteerOnly,
}

/// Original routing decision. An unconsumed steer is retained for later recovery like any input.
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    tag = "kind",
    content = "value"
)]
pub enum InputDelivery {
    #[default]
    NextTurn,
    CurrentTurn {
        turn_id: String,
    },
}

/// One input and its execution intent. Duplicate IDs retain their original routing receipt.
#[derive(Debug)]
pub struct InputSubmission {
    pub input: ThreadInput,
    pub policy: InputPolicy,
    pub drive: Option<InputDriverOptions>,
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
    #[serde(default)]
    pub delivery: InputDelivery,
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
    pub delivery: InputDelivery,
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
            delivery: record.delivery.clone(),
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
            delivery: self.delivery.clone(),
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

impl InputRecord {
    /// Returns the framework context identity used when this input was actually admitted to a
    /// model call. A queued or metadata-only input has no model-visible record. Compaction may
    /// remove the record from current context while the original request and journal retain it.
    pub fn context_record_id(&self) -> Option<String> {
        let InputState::Consumed {
            turn_id,
            attempt_id,
        } = &self.state
        else {
            return None;
        };
        if self.input.context.is_empty() {
            return None;
        }
        Some(
            if matches!(&self.delivery, InputDelivery::CurrentTurn { turn_id: target } if target == turn_id)
            {
                steering_record_id(turn_id, &self.input.id)
            } else {
                format!("{attempt_id}:input")
            },
        )
    }
}

/// Queue log operation. Consumption references the original content instead of copying it again.
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
        revision: u64,
        state: InputState,
    },
}

/// Execution parameters for the oldest pending input; these do not alter its saved content.
#[derive(Debug)]
pub struct QueuedTurn {
    pub turn_id: String,
    pub attempt_prefix: String,
    pub max_model_steps: crate::thread::ModelStepLimit,
    pub cancellation: CancellationToken,
}

/// Host-selected bounds for serial queue execution, frozen separately for each Turn.
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
/// Notifications may wake a dormant driver, but only explicit continuation can leave a pause.
#[derive(Debug)]
pub(super) enum ExecutionPolicy {
    Enabled(InputDriverOptions),
    Paused(PauseReason),
}
#[derive(Debug)]
pub(super) enum PauseReason {
    Initial,
    User,
    Failed(Arc<ThreadError>),
}

impl ExecutionPolicy {
    pub(super) fn options(&self) -> Option<InputDriverOptions> {
        match self {
            Self::Enabled(options) => Some(*options),
            Self::Paused(_) => None,
        }
    }
    pub(super) fn error(&self) -> Option<&Arc<ThreadError>> {
        match self {
            Self::Paused(PauseReason::Failed(error)) => Some(error),
            _ => None,
        }
    }
    pub(super) fn enable(&mut self, options: InputDriverOptions) {
        *self = Self::Enabled(options);
    }
    pub(super) fn wake(&mut self, options: InputDriverOptions) {
        if matches!(self, Self::Paused(PauseReason::Initial) | Self::Enabled(_)) {
            self.enable(options);
        }
    }
    pub(super) fn pause(&mut self) {
        if !matches!(self, Self::Paused(PauseReason::Failed(_))) {
            *self = Self::Paused(PauseReason::User);
        }
    }
    pub(super) fn fail(&mut self, error: Arc<ThreadError>) {
        *self = Self::Paused(PauseReason::Failed(error));
    }
}

impl Owner {
    pub(super) fn resume_inputs(&mut self, options: InputDriverOptions) -> Result<(), ThreadError> {
        if self.state.lifecycle != ThreadLifecycle::Open || self.interrupt.is_closing() {
            return Err(ThreadError::Closed);
        }
        // An explicit resume of a queue that had stopped is a fresh authorization, so the stop
        // generation an earlier cancellation armed for the queue's next Turn is spent: the resumed
        // queue runs under the stop count it now has, not under one a stop already overtook.
        self.policy.enable(options);
        self.publish_snapshot();
        Ok(())
    }

    pub(super) fn pause_inputs(&mut self) {
        self.policy.pause();
        self.publish_snapshot();
    }

    pub(super) fn start_queued_work(&mut self) -> Result<bool, ThreadError> {
        if self.state.lifecycle != ThreadLifecycle::Open
            || self.interrupt.is_closing()
            || !self.continuation_ready()
        {
            return Ok(false);
        }
        let Some(options) = self.policy.options() else {
            return Ok(false);
        };
        let source = if let Some(record) = self.state.inputs.iter().find(|r| self.driveable(r)) {
            format!("input:{}", record.input.id)
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
        } else {
            input.content = self.freeze_next_input_batch().unwrap_or_default();
        }
        self.start_run(input, super::execution::RunReply::Driver)
            .map_err(|(error, _)| error)?;
        self.active.as_mut().unwrap().restored = restored;
        Ok(true)
    }

    pub(super) fn accept_input(&mut self, input: ThreadInput) -> Result<InputRecord, ThreadError> {
        self.accept_input_with_policy(input, InputPolicy::StartOrQueue)
    }

    pub(super) fn accept_input_with_policy(
        &mut self,
        input: ThreadInput,
        policy: InputPolicy,
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
        let active_turn = self
            .state
            .turns
            .last()
            .filter(|turn| turn.state == TurnState::Running)
            .map(|turn| turn.turn_id.clone());
        let delivery = match policy {
            InputPolicy::StartOnly
                if active_turn.is_some()
                    || self
                        .state
                        .inputs
                        .iter()
                        .any(|input| input.state == InputState::Pending) =>
            {
                return Err(ThreadError::InputRequiresIdle);
            }
            InputPolicy::SteerOnly if active_turn.is_none() => {
                return Err(ThreadError::InputRequiresActiveTurn);
            }
            InputPolicy::StartOrSteer | InputPolicy::SteerOnly => active_turn
                .map_or(InputDelivery::NextTurn, |turn_id| {
                    InputDelivery::CurrentTurn { turn_id }
                }),
            InputPolicy::StartOnly | InputPolicy::StartOrQueue => InputDelivery::NextTurn,
        };
        let record = stage_input_with_delivery(&mut self.state, input, delivery)?;
        self.publish()?;
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
        if self.active_inputs.iter().any(|active| active == id) {
            return Err(ThreadError::InputInUse);
        }
        let record = self.change_input(id, InputState::Discarded)?;
        self.publish()?;
        Ok(record)
    }

    /// Freeze a batch without consuming it; ordinary admission later confirms consumption.
    pub(super) fn freeze_next_input_batch(&mut self) -> Option<Vec<ContextContent>> {
        let record = self
            .state
            .inputs
            .iter()
            .find(|record| self.driveable(record))
            .cloned()?;
        let through = self.input_batch_through.take().unwrap_or(record.ordinal);
        // The frozen batch is one commit's worth of work: every input it covers is consumed by the
        // admission that also advances the message watermark, so the next Turn never re-delivers an
        // already admitted input and a body-less control never starts a Turn of its own.
        let batch: Vec<_> = self
            .state
            .inputs
            .iter()
            .filter(|input| input.ordinal <= through && self.driveable(input))
            .cloned()
            .collect();
        self.active_inputs = batch.iter().map(|input| input.input.id.clone()).collect();
        Some(
            batch
                .into_iter()
                .flat_map(|input| input.input.context)
                .collect(),
        )
    }

    /// Stages consumption just before request publication; no independently published watermark.
    pub(super) fn steering_context(&self, turn_id: &str) -> (Vec<ContextRecord>, Vec<String>) {
        let mut records = Vec::new();
        let mut ids = Vec::new();
        for input in self.state.inputs.iter().filter(|input| input.state == InputState::Pending
            && matches!(&input.delivery, InputDelivery::CurrentTurn { turn_id: target } if target == turn_id)
            && !self.active_inputs.contains(&input.input.id)) {
            ids.push(input.input.id.clone());
            if !input.input.context.is_empty() {
                records.push(ContextRecord { id: steering_record_id(turn_id, &input.input.id), turn_id: Some(turn_id.into()),
                    source: ContextSource::User, content: input.input.context.clone(), tool_calls: Vec::new() });
            }
        }
        (records, ids)
    }

    pub(super) fn validate_steering(&self, ids: &[String]) -> Result<(), ThreadError> {
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

    pub(super) fn consume_steering(
        &mut self,
        ids: &[String],
        turn_id: &str,
        attempt_id: &str,
    ) -> Result<(), ThreadError> {
        for id in ids {
            self.change_input(
                id,
                InputState::Consumed {
                    turn_id: turn_id.into(),
                    attempt_id: attempt_id.into(),
                },
            )?;
        }
        Ok(())
    }

    pub(super) fn consume_active_input(
        &mut self,
        turn_id: &str,
        attempt_id: &str,
    ) -> Result<(), ThreadError> {
        for id in self.active_inputs.clone() {
            let Some(previous) = self
                .state
                .inputs
                .iter()
                .find(|record| record.input.id == id)
            else {
                // The input already reached a terminal state and left the bounded resident queue
                // when an earlier step of this Turn consumed it. Its resident receipt stays the
                // authority: a consumption attributed to this Turn completes normally, while any
                // other terminal state stays an input conflict.
                if active_input_already_consumed(&self.state, &id, turn_id) {
                    continue;
                }
                return Err(ThreadError::InputConsumed);
            };
            match &previous.state {
                InputState::Pending => {
                    self.change_input(
                        &id,
                        InputState::Consumed {
                            turn_id: turn_id.into(),
                            attempt_id: attempt_id.into(),
                        },
                    )?;
                }
                InputState::Consumed {
                    turn_id: consumed_turn,
                    ..
                } if consumed_turn == turn_id => {}
                InputState::Consumed { .. } | InputState::Discarded => {
                    return Err(ThreadError::InputConsumed);
                }
            }
        }
        Ok(())
    }

    pub(super) fn change_input(
        &mut self,
        id: &str,
        state: InputState,
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
            revision: record.revision,
            state: record.state.clone(),
        });
        Ok(record)
    }

    fn append_input_change(&mut self, record: InputChange) {
        let mut changes = self.state.input_changes.to_vec();
        changes.push(record);
        self.state.input_changes = changes.into();
    }
}

fn steering_record_id(turn_id: &str, input_id: &str) -> String {
    format!("steer:{}:{turn_id}{input_id}", turn_id.len())
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

/// Reports whether bounded owner state already records `id` as consumed by `turn_id`.
///
/// A consumed input leaves the resident queue as soon as its commit publishes, so a later step of
/// the same Turn sees only its resident receipt. An identity that already left the bounded window is
/// accepted as this Turn's own admission receipt: the owner lists only inputs it admitted into the
/// active batch, discarding an in-use input is refused, and Turns are serial, so a listed input that
/// is no longer resident can only have been consumed by this Turn.
fn active_input_already_consumed(state: &ThreadSnapshot, id: &str, turn_id: &str) -> bool {
    state
        .terminal_inputs
        .iter()
        .find(|identity| identity.id == id)
        .is_none_or(|identity| {
            matches!(&identity.state, InputState::Consumed { turn_id: consumed, .. } if consumed == turn_id)
        })
}

/// Stages input as part of an already-admitted control transaction, without starting execution.
pub(super) fn stage_input(
    state: &mut ThreadSnapshot,
    input: ThreadInput,
) -> Result<InputRecord, ThreadError> {
    stage_input_with_delivery(state, input, InputDelivery::NextTurn)
}

/// Stages one input under the delivery it was routed to and the continuation it carries.
pub(super) fn stage_input_with_delivery(
    state: &mut ThreadSnapshot,
    input: ThreadInput,
    delivery: InputDelivery,
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
        delivery,
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
