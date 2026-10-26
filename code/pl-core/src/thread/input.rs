//! Durable input admission, separate from model-request admission and execution.
use super::*;

/// Immutable host-authored input. Only `context` is placed in the user context record.
///
/// `purpose` separates a normal message from the body-less control a trusted host submits to
/// continue already claimed work. The distinction is a typed field, never a fixed payload text, an
/// empty string or a payload flag, so nothing downstream has to guess intent from content.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ThreadInput {
    pub id: String,
    #[serde(default)]
    pub purpose: InputPurpose,
    pub payload: OpaquePayload,
    pub context: Vec<ContextContent>,
}

/// What an input is for. A control input carries framework intent and no user content.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum InputPurpose {
    /// Ordinary host message; its context becomes user context.
    #[default]
    Message,
    /// Framework control that authorises continuing already owed work; it has no context and
    /// never becomes user context.
    Continuation,
}

/// Opaque payload identity of the control input a continuation is submitted with.
///
/// Its content names the point and the Turn the continuation came from, so the control input stays
/// inspectable without carrying task content of its own.
pub const CONTINUATION_PAYLOAD_FORMAT: &str = "pl.core.thread-continuation";

/// Version of [`CONTINUATION_PAYLOAD_FORMAT`] this build writes.
pub const CONTINUATION_PAYLOAD_VERSION: u32 = 1;

impl ThreadInput {
    /// Builds the body-less control input that authorises one already claimed continuation.
    ///
    /// This is the only trusted constructor for a control input: the context is empty by
    /// construction, so a caller can never smuggle user content into framework control.
    pub fn for_continuation(
        id: impl Into<String>,
        point_id: &str,
        source_turn_id: Option<&str>,
    ) -> Self {
        Self {
            id: id.into(),
            purpose: InputPurpose::Continuation,
            payload: OpaquePayload::new(
                CONTINUATION_PAYLOAD_FORMAT,
                CONTINUATION_PAYLOAD_VERSION,
                serde_json::json!({
                    "pointId": point_id,
                    "sourceTurnId": source_turn_id,
                })
                .to_string(),
            )
            .expect("static nonempty format and nonzero version"),
            context: Vec::new(),
        }
    }

    /// Rejects a purpose and a payload that contradict each other.
    ///
    /// The purpose is the typed fact and the payload is only its encoding, so the two must agree:
    /// a `Continuation` carries the control payload and no user content, while an ordinary `Message`
    /// never claims the control format. The constraint is enforced where the input is admitted, so
    /// the reserved format only ever enters history as the control input it names; readers trust the
    /// stored facts and never re-interpret a payload.
    pub fn validate_purpose(&self) -> Result<(), ThreadError> {
        let control_payload = self.payload.format() == CONTINUATION_PAYLOAD_FORMAT;
        match self.purpose {
            // Framework control is never content: context would make it indistinguishable from a
            // user message, and a different payload would make the control unverifiable later.
            InputPurpose::Continuation => {
                if !self.context.is_empty()
                    || !control_payload
                    || self.payload.version() != CONTINUATION_PAYLOAD_VERSION
                {
                    return Err(ThreadError::InvalidControlInput);
                }
            }
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
    /// Continuation this input carries, when it was admitted to continue already owed work.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub continuation: Option<InputContinuation>,
    #[serde(default)]
    pub delivery: InputDelivery,
    pub input: ThreadInput,
    pub ordinal: u64,
    pub revision: u64,
    pub state: InputState,
}

/// Frozen association between one admitted input and the continuation point it carries.
///
/// It records the reference, not the point's content: the point itself stays the single fact that
/// says what work is owed, and the admission commit is what clears it.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InputContinuation {
    pub point_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_turn_id: Option<String>,
}

/// Minimal resident identity of an admitted input that already reached a terminal state.
///
/// The body and framework routing facts stay in the durable effect history; this record is the
/// only thing the live owner keeps so a repeated submission can still be answered idempotently.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InputIdentity {
    /// Content digest of the originally accepted body.
    pub digest: String,
    /// Continuation this input carried, retained so a repeated operation still answers with the same
    /// association instead of a body-less receipt.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub continuation: Option<InputContinuation>,
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
    /// Projects one terminal input record into its minimal durable identity.
    ///
    /// The Studio runtime persists this record in the per-Thread history identity index so a
    /// repeated submission can be answered after the resident terminal input has left core state.
    pub fn from_record(record: &InputRecord) -> Self {
        Self {
            digest: record.input.digest(),
            continuation: record.continuation.clone(),
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
            continuation: self.continuation.clone(),
            delivery: self.delivery.clone(),
            input,
            ordinal: self.ordinal,
            revision: self.revision,
            state: self.state.clone(),
        }
    }

    /// Rebuilds the receipt of a control operation whose body cannot be re-derived from current
    /// state.
    ///
    /// A body-less continuation names the point it was admitted for, so its immutable body is
    /// recomputed from the association this identity retained. That keeps a repeated operation a
    /// pure receipt: it neither re-claims the point nor wakes execution again.
    pub fn control_receipt(&self, accepted_sequence: u64) -> Option<InputRecord> {
        if self.purpose != InputPurpose::Continuation {
            return None;
        }
        let continuation = self.continuation.clone()?;
        let input = ThreadInput::for_continuation(
            self.id.clone(),
            &continuation.point_id,
            continuation.source_turn_id.as_deref(),
        );
        // The receipt must be the operation this identity was really admitted with: a synthesized
        // control body whose digest differs from the recorded one is a different operation, not a
        // repeat, so it is refused exactly like a conflicting body.
        if input.digest() != self.digest {
            return None;
        }
        Some(self.receipt(input, accepted_sequence))
    }
}

/// Builds the minimal durable identity of a terminal input record.
///
/// Host layers use this to persist the identity index entry alongside the effect that settled the
/// input; core keeps only the pending queue and never re-reads the durable history.
pub fn input_identity(record: &InputRecord) -> InputIdentity {
    InputIdentity::from_record(record)
}

/// Rebuilds one framework receipt from a stored identity.
///
/// The caller passes the watermark that answers the repeat (the current commit for a live owner,
/// or the durable write sequence for a cold Thread), so a repeated submission returns a receipt
/// without re-admission.
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
    /// The owner already took the next Turn (or its message wake-up) out of the queue, but the Turn
    /// admission gate is closed, so the Turn has not started: nothing was consumed and no Turn
    /// record exists yet. Releasing the gate admits exactly this Turn.
    Blocked,
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
pub(super) enum InputDriver {
    Dormant,
    Enabled(InputDriverOptions),
    Paused,
    Failed(Arc<ThreadError>),
}

impl InputDriver {
    pub(super) fn options(&self) -> Option<InputDriverOptions> {
        match self {
            Self::Enabled(options) => Some(*options),
            _ => None,
        }
    }
    pub(super) fn error(&self) -> Option<&Arc<ThreadError>> {
        match self {
            Self::Failed(error) => Some(error),
            _ => None,
        }
    }
    pub(super) fn enable(&mut self, options: InputDriverOptions) {
        *self = Self::Enabled(options);
    }
    pub(super) fn wake(&mut self, options: InputDriverOptions) {
        match self {
            Self::Dormant | Self::Enabled(_) => self.enable(options),
            Self::Paused | Self::Failed(_) => {}
        }
    }
    pub(super) fn pause(&mut self) {
        if !matches!(self, Self::Failed(_)) {
            *self = Self::Paused;
        }
    }
    pub(super) fn fail(&mut self, error: Arc<ThreadError>) {
        if !matches!(self, Self::Failed(_)) {
            *self = Self::Failed(error);
        }
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
        if self.input_driver.options().is_none() {
            self.authorized_stops = None;
        }
        self.input_driver.enable(options);
        self.publish_snapshot();
        Ok(())
    }

    pub(super) fn pause_inputs(&mut self) {
        self.input_driver.pause();
        self.publish_snapshot();
    }

    pub(super) async fn drive_one_input(&mut self) -> bool {
        if self.state.lifecycle != ThreadLifecycle::Open || self.interrupt.is_closing() {
            return false;
        }
        if !self.continuation_ready() {
            return false;
        }
        let Some(options) = self.input_driver.options() else {
            return false;
        };
        let pending_input = self
            .state
            .inputs
            .iter()
            .find(|record| self.driveable(record));
        let source = if let Some(record) = pending_input {
            format!("input:{}", record.input.id)
        } else if self.state.wake_messages_through > self.state.consumed_messages {
            format!("message:{}", self.state.wake_messages_through)
        } else {
            return false;
        };
        let has_input = pending_input.is_some();
        let mut suffix = self.state.commit_sequence;
        let turn_id = loop {
            let candidate = format!("{source}:{suffix}");
            if !self
                .state
                .turns
                .iter()
                .any(|turn| turn.turn_id == candidate)
                && !self
                    .state
                    .attempts
                    .iter()
                    .any(|attempt| attempt.turn_id == candidate)
            {
                break candidate;
            }
            let Some(next) = suffix.checked_add(1) else {
                self.input_driver
                    .fail(Arc::new(ThreadError::RevisionExhausted));
                self.pause_inputs();
                return false;
            };
            suffix = next;
        };
        // The execution identity exists before any Turn record or storage wait, so a stop can name
        // exactly this generation even while it is still preparing.
        if let Err(error) = self.begin_execution() {
            self.input_driver.fail(Arc::new(error));
            self.pause_inputs();
            return false;
        }
        let driven_turn = turn_id.clone();
        let request = QueuedTurn {
            attempt_prefix: turn_id.clone(),
            turn_id,
            max_model_steps: options.max_model_steps,
            cancellation: CancellationToken::new(),
        };
        let result = if has_input {
            self.run_next_input(request).await
        } else {
            let active = self
                .interrupt
                .activate(&request.cancellation, self.authorized_stops.take());
            // A message-only Turn also holds a frozen (empty) batch, so a replacement arriving while it
            // prepares must re-freeze here for the same reason the queue batch does.
            self.frozen_turn = Some(request.turn_id.clone());
            let result = self
                .run_turn(TurnInput {
                    turn_id: request.turn_id,
                    attempt_prefix: request.attempt_prefix,
                    max_model_steps: request.max_model_steps,
                    content: Vec::new(),
                    cancellation: active.token.clone(),
                })
                .await
                .map(Some);
            self.frozen_turn = None;
            result
        };
        // A replacement this owner caused itself is recognized by the exact Turn it cancelled **and** by
        // the stop generation that cancellation produced. Any later stop request — the public interrupt,
        // a Turn stop, an execution stop — changes the generation and therefore wins over the
        // replacement, and a closing owner is never re-frozen either.
        let re_freeze = match self.superseded_batch.take() {
            Some((turn, stops))
                if turn == driven_turn
                    && stops == self.interrupt.stops()
                    && !self.interrupt.is_closing()
                    && self.input_driver.options().is_some() =>
            {
                Some(stops)
            }
            _ => None,
        };
        // A continuation request that cancelled the running Turn keeps the queue enabled so the
        // continuation itself can run — but only while no later stop replaced that authorization. The
        // marker is always consumed, so a stale generation can never authorize a later cancellation.
        let continuation_cancel = self.continuation_cancel.take();
        let continuation_allowed =
            continuation_cancel.is_none_or(|generation| generation == self.interrupt.stops());
        // The stop generation that kept the queue running through this cancellation is exactly the
        // one the Turn it authorized may start under: a stop that arrives before that Turn activates
        // pauses the queue through it, instead of being silently consumed by a fresh generation the
        // stop never caused.
        let authorized_stops = re_freeze
            .or(continuation_cancel.filter(|generation| *generation == self.interrupt.stops()));
        match result {
            Ok(Some(TurnCompletion {
                outcome: TurnOutcome::Completed,
                ..
            })) => {}
            Ok(Some(TurnCompletion {
                outcome: TurnOutcome::WaitingInteraction | TurnOutcome::StepLimit,
                ..
            }))
            | Ok(None) => self.pause_inputs(),
            // The batch this Turn froze was replaced before it was ever admitted, so the content it
            // holds no longer matches what it would consume. It is dropped and the queue keeps running
            // with the new authorization instead of pausing or sending a request without that content.
            Err(ThreadError::Cancelled) if re_freeze.is_some() => {
                self.authorized_stops = authorized_stops;
            }
            Err(ThreadError::Cancelled)
                if self.interrupted_turn.is_some()
                    && self.input_driver.options().is_some()
                    && !self.interrupt.is_closing()
                    && continuation_allowed =>
            {
                self.authorized_stops = authorized_stops
            }
            Err(ThreadError::Cancelled) => self.pause_inputs(),
            Err(error) => {
                self.input_driver.fail(Arc::new(error));
                self.pause_inputs();
            }
        }
        true
    }

    pub(super) fn accept_input(&mut self, input: ThreadInput) -> Result<InputRecord, ThreadError> {
        self.accept_input_with_policy(input, InputPolicy::StartOrQueue, None)
    }

    pub(super) fn accept_input_with_policy(
        &mut self,
        input: ThreadInput,
        policy: InputPolicy,
        continuation: Option<InputContinuation>,
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
        // Whether this submission may carry the point is decided before anything is admitted, so a
        // refused claim never leaves an input behind that would have to be withdrawn afterwards.
        if let Some(continuation) = &continuation
            && !self.may_claim_continuation(&continuation.point_id)
        {
            return Err(ThreadError::NoContinuation);
        }
        let record = stage_input_with_delivery(&mut self.state, input, delivery, continuation)?;
        if record.continuation.is_some() {
            // The claim this submission takes over from is captured before the new claim replaces it,
            // so the replaced placeholder is settled in the very commit that authorizes the new one.
            let previous = self
                .state
                .continuation
                .as_ref()
                .and_then(|point| point.claim.clone());
            // Admitting the claim and fixing the durable watermark it owes is one commit: the
            // requirement names the very sequence that records the claim, so no submission can claim
            // without owing its own durability and no unclaimed submission can leave a requirement.
            self.record_input_claim(&record);
            if let Some(previous) = previous {
                self.settle_replaced_carrier(&previous, Some(&record.input.id))?;
            }
            self.discard_superseded_control_inputs(Some(&record.input.id))?;
        }
        self.publish();
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
        self.publish();
        Ok(record)
    }

    pub(super) async fn run_next_input(
        &mut self,
        request: QueuedTurn,
    ) -> Result<Option<TurnCompletion>, ThreadError> {
        let Some(record) = self
            .state
            .inputs
            .iter()
            .find(|record| self.driveable(record))
            .cloned()
        else {
            return Ok(None);
        };
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
        let content = batch
            .into_iter()
            .flat_map(|input| input.input.context)
            .collect();
        let active = self
            .interrupt
            .activate(&request.cancellation, self.authorized_stops.take());
        // The batch copies its content here, so this is the window in which a replacement has to
        // re-freeze instead of patching the queue.
        self.frozen_turn = Some(request.turn_id.clone());
        let result = self
            .run_turn(TurnInput {
                turn_id: request.turn_id,
                attempt_prefix: request.attempt_prefix,
                content,
                max_model_steps: request.max_model_steps,
                cancellation: active.token.clone(),
            })
            .await;
        self.frozen_turn = None;
        self.active_inputs.clear();
        self.publish_snapshot();
        result.map(Some)
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
                // when an earlier step of this Turn consumed it. Its durable receipt stays the
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

/// Validates queue changes against the same commit's request, without invoking a decoder or executor.
pub(super) fn replay(
    state: &mut ThreadSnapshot,
    commit: &ThreadEffectBatch,
    contexts: &std::collections::BTreeMap<u64, ContextSnapshot>,
) -> Result<(), ThreadError> {
    let mut inputs = state.inputs.to_vec();
    let mut changes = state.input_changes.to_vec();
    let mut identities = std::collections::BTreeSet::new();
    let mut consumed_context = Vec::new();
    let mut consumed_request = None;
    for change in commit.inputs.iter() {
        let record = match change {
            InputChange::Accepted(record) => {
                if record.accepted_sequence != commit.sequence
                    || record.ordinal != inputs.len() as u64 + 1
                    || record.revision != 1
                    || record.state != InputState::Pending
                    || inputs
                        .iter()
                        .any(|previous| previous.input.id == record.input.id)
                {
                    return Err(ThreadError::InvalidOutput);
                }
                if let InputDelivery::CurrentTurn { turn_id } = &record.delivery
                    && !state
                        .turns
                        .iter()
                        .any(|turn| &turn.turn_id == turn_id && turn.state == TurnState::Running)
                {
                    return Err(ThreadError::InvalidOutput);
                }
                inputs.push(record.clone());
                record.clone()
            }
            InputChange::Transition {
                id,
                revision,
                state: next,
            } => {
                let previous = inputs
                    .iter_mut()
                    .find(|previous| &previous.input.id == id)
                    .ok_or(ThreadError::InvalidIdentity)?;
                if previous.revision.checked_add(1) != Some(*revision)
                    || previous.state != InputState::Pending
                    || *next == InputState::Pending
                {
                    return Err(ThreadError::InvalidOutput);
                }
                previous.revision = *revision;
                previous.state = next.clone();
                previous.clone()
            }
        };
        if record.input.id.is_empty() || !identities.insert(record.input.id.clone()) {
            return Err(ThreadError::InvalidIdentity);
        }
        if let InputState::Consumed {
            turn_id,
            attempt_id,
        } = &record.state
        {
            let steering = matches!(&record.delivery, InputDelivery::CurrentTurn { turn_id: target } if target == turn_id);
            if !steering {
                consumed_context.extend(record.input.context.clone());
                consumed_request = Some((turn_id.clone(), attempt_id.clone()));
            }
            let attempt = commit
                .attempt
                .as_ref()
                .filter(|attempt| {
                    &attempt.turn_id == turn_id
                        && &attempt.attempt_id == attempt_id
                        && matches!(attempt.outcome, AttemptOutcome::Running)
                })
                .ok_or(ThreadError::InvalidOutput)?;
            let admitted = state
                .attempts
                .iter()
                .find(|item| item.attempt_id == attempt.attempt_id)
                .ok_or(ThreadError::InvalidOutput)?;
            if steering && !record.input.context.is_empty() {
                // The frozen input is no longer resident; the migration reducer still holds every
                // context revision this journal committed, so the steering record is validated
                // against the exact revision the attempt was admitted at.
                let frozen = contexts
                    .get(&admitted.input_revision)
                    .ok_or(ThreadError::InvalidOutput)?;
                let user = frozen
                    .records
                    .iter()
                    .find(|item| record.context_record_id().as_deref() == Some(item.id.as_str()))
                    .ok_or(ThreadError::InvalidOutput)?;
                if user.source != ContextSource::User
                    || user.turn_id.as_ref() != Some(turn_id)
                    || user.content != record.input.context
                {
                    return Err(ThreadError::InvalidOutput);
                }
            }
            if inputs.iter().any(|previous| {
                previous.ordinal < record.ordinal && previous.state == InputState::Pending
                    && (!steering || matches!(&previous.delivery, InputDelivery::CurrentTurn { turn_id: target } if target == turn_id))
            }) {
                return Err(ThreadError::InvalidOutput);
            }
        }
        changes.push(change.clone());
    }
    if let Some((turn_id, attempt_id)) = consumed_request {
        let admitted = state
            .attempts
            .iter()
            .find(|attempt| attempt.attempt_id == attempt_id)
            .ok_or(ThreadError::InvalidOutput)?;
        let frozen = contexts
            .get(&admitted.input_revision)
            .ok_or(ThreadError::InvalidOutput)?;
        let user = frozen
            .records
            .iter()
            .find(|record| record.id == format!("{attempt_id}:input"));
        match user {
            Some(record)
                if record.source == ContextSource::User
                    && record.turn_id.as_ref() == Some(&turn_id)
                    && record.content == consumed_context => {}
            None if consumed_context.is_empty() => {}
            _ => return Err(ThreadError::InvalidOutput),
        }
    }
    state.inputs = inputs.into();
    let newest_ordinal = state
        .inputs
        .iter()
        .map(|record| record.ordinal)
        .max()
        .unwrap_or(0);
    let watermark = state.input_ordinal;
    state.input_ordinal = watermark.max(newest_ordinal);
    state.input_changes = changes.into();
    Ok(())
}

fn steering_record_id(turn_id: &str, input_id: &str) -> String {
    format!("steer:{}:{turn_id}{input_id}", turn_id.len())
}

/// Answers a repeated input submission from bounded current state.
///
/// A still-pending input keeps its full record; a terminal input is answered from the bounded
/// identity window by comparing the immutable content digest. An identity older than that window
/// is answered by the host's durable identity index, so core never accumulates history.
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

/// Reports whether bounded durable state already records `id` as consumed by `turn_id`.
///
/// A consumed input leaves the resident queue as soon as its commit publishes, so a later step of
/// the same Turn sees only its durable receipt. An identity that already left the bounded window is
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
    stage_input_with_delivery(state, input, InputDelivery::NextTurn, None)
}

/// Stages one input under the delivery it was routed to and the continuation it carries.
pub(super) fn stage_input_with_delivery(
    state: &mut ThreadSnapshot,
    input: ThreadInput,
    delivery: InputDelivery,
    continuation: Option<InputContinuation>,
) -> Result<InputRecord, ThreadError> {
    if input.id.is_empty() {
        return Err(ThreadError::InvalidIdentity);
    }
    input.validate_purpose()?;
    if input.purpose == InputPurpose::Continuation {
        // Framework control is only ever the canonical operation body for its own association: a
        // hand-written control would let a caller mint an identity that later answers a receipt for
        // work it never authorized, so it is refused instead of admitted under a purpose it does not
        // really have.
        let canonical = continuation.as_ref().is_some_and(|continuation| {
            ThreadInput::for_continuation(
                input.id.clone(),
                &continuation.point_id,
                continuation.source_turn_id.as_deref(),
            ) == input
        });
        if !canonical {
            return Err(ThreadError::InvalidControlInput);
        }
    }
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
        continuation,
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
