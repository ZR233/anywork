//! Owner-controlled interruption followed by a fresh Turn; admission receipts are not completions.
use super::*;

impl Owner {
    pub(super) fn continue_input(
        &mut self,
        input: input::ThreadInput,
        options: input::InputDriverOptions,
    ) -> Result<input::InputRecord, ThreadError> {
        // Duplicate submissions must not revive a manually paused driver or cancel a newer Turn.
        // Terminal identities stay resident even after their input body is pruned, so the receipt
        // is answered from bounded state instead of reviving a paused driver.
        if let Some(receipt) = input::duplicate_input_receipt(&self.state, &input)? {
            return Ok(receipt);
        }
        self.validate_continuation_admission()?;
        // A content submission carries the claim itself instead of manufacturing a control input:
        // the real message becomes the fact that authorises this continuation, and only the
        // association is recorded next to the already admitted body.
        let continuation = self
            .claimable_continuation()
            .or_else(|| self.replaceable_continuation())
            .map(|point| input::InputContinuation {
                point_id: point.id.clone(),
                source_turn_id: point.source_turn_id.clone(),
            });
        let record =
            self.accept_input_with_policy(input, input::InputPolicy::StartOrQueue, continuation)?;
        self.input_batch_through = Some(record.ordinal);
        self.request_continuation(options);
        Ok(record)
    }

    /// Accepts the body-less control that continues work this Thread already owes.
    ///
    /// The operation identity is the control input's own identity, so a repeat answers exactly like
    /// the original submission: the same admission is returned, the point is not claimed a second
    /// time and execution is not woken again. Claiming and admission are one commit, and the
    /// durable watermark the claim owes is named in that same commit.
    pub(super) fn continue_thread(
        &mut self,
        input_id: String,
        options: input::InputDriverOptions,
    ) -> Result<input::InputRecord, ThreadError> {
        if input_id.is_empty() {
            return Err(ThreadError::InvalidIdentity);
        }
        // A still-pending operation keeps its full record; an operation whose body already left the
        // resident queue is answered from its bounded identity. Both happen before any admission
        // check, so a repeat is never refused for a pause it did not cause and never cancels work.
        // The repeat must be the same control operation, though: an ordinary message that happens to
        // use the identity, or a control body that is not the one this operation would submit, is an
        // identity conflict instead of a receipt for work it never authorized.
        if let Some(previous) = self
            .state
            .inputs
            .iter()
            .find(|record| record.input.id == input_id)
        {
            return Self::resident_control_receipt(previous, &input_id);
        }
        if let Some(identity) = self
            .state
            .terminal_inputs
            .iter()
            .find(|identity| identity.id == input_id)
        {
            return identity
                .control_receipt(self.state.commit_sequence)
                .ok_or(ThreadError::InvalidIdentity);
        }
        self.validate_continuation_admission()?;
        // A newer explicit continuation may take over a point that an unconsumed placeholder still
        // holds: the placeholder is voided in the same commit, so only the newest authorization stands
        // and the user never has to stop first to authorize the same work again.
        let Some(point) = self
            .claimable_continuation()
            .or_else(|| self.takeoverable_continuation())
        else {
            return Err(ThreadError::NoContinuation);
        };
        let input = input::ThreadInput::for_continuation(
            input_id,
            &point.id,
            point.source_turn_id.as_deref(),
        );
        let continuation = input::InputContinuation {
            point_id: point.id.clone(),
            source_turn_id: point.source_turn_id.clone(),
        };
        // Admission records the claim and the durable watermark it owes in one commit; a refusal
        // leaves neither behind, so a failed continuation can never look authorized.
        let record = self.accept_input_with_policy(
            input,
            input::InputPolicy::StartOrQueue,
            Some(continuation),
        )?;
        self.input_batch_through = Some(record.ordinal);
        self.request_continuation(options);
        Ok(record)
    }

    pub(super) fn continue_message(
        &mut self,
        message: inbox::ThreadMessage,
        options: input::InputDriverOptions,
    ) -> Result<u64, ThreadError> {
        // An already accepted identity is answered from its original receipt before any new
        // admission check or continuation action: a repeat is not new work, so it must not be
        // refused because the owner is closing, is waiting for an interaction or is under storage
        // pressure, and it must not interrupt the Turn that is currently running. Only a genuinely
        // new message takes the admission path, which is what warms the driver and interrupts.
        if let Some(sequence) = self.accepted_message_receipt(&message)? {
            return Ok(sequence);
        }
        self.validate_continuation_admission()?;
        // A parent message that explicitly continues owed work is itself the authorization, so it
        // carries the claim instead of a manufactured control input. Like real user content it may
        // also take over a claim that only an unconsumed body-less control holds as a placeholder.
        let claim = self
            .claimable_continuation()
            .or_else(|| self.takeoverable_continuation())
            .map(|point| point.id.clone());
        if let Some(point_id) = &claim
            && !self.may_claim_continuation(point_id)
        {
            return Err(ThreadError::NoContinuation);
        }
        let sequence = self.receive_message(message, Some(options), claim.as_deref())?;
        self.request_continuation(options);
        Ok(sequence)
    }

    fn validate_continuation_admission(&mut self) -> Result<(), ThreadError> {
        if self.state.lifecycle != ThreadLifecycle::Open || self.interrupt.is_closing() {
            return Err(ThreadError::Closed);
        }
        if self
            .state
            .interactions
            .values()
            .any(|record| record.state == interactions::InteractionState::Pending)
            || self
                .state
                .permissions
                .values()
                .any(|record| record.state == permissions::PermissionState::Pending)
        {
            return Err(ThreadError::PendingInteraction);
        }
        self.refresh_storage_pressure();
        if self.state.persistence.pressure_paused {
            return Err(ThreadError::StoragePressure);
        }
        if let Some(error) = &self.cold_error {
            return Err(ThreadError::Storage(error.clone()));
        }
        Ok(())
    }

    /// The point a new continuation may claim: it exists and nothing carries it yet.
    pub(super) fn claimable_continuation(&self) -> Option<&ContinuationPoint> {
        self.state
            .continuation
            .as_ref()
            .filter(|point| point.claim.is_none())
    }

    /// The point a real message may take over from an unconsumed body-less control.
    ///
    /// Only a control input is replaceable. A user message, attachment or parent message is never
    /// discarded by a later continuation, so it can never be the claim that gets replaced.
    fn replaceable_continuation(&self) -> Option<&ContinuationPoint> {
        self.state.continuation.as_ref().filter(|point| {
            point.claimed_input().is_some_and(|previous| {
                self.state.inputs.iter().any(|record| {
                    record.input.id == previous
                        && record.state == input::InputState::Pending
                        && record.input.purpose == input::InputPurpose::Continuation
                })
            })
        })
    }

    /// Answers a repeated control operation from the record that is still resident.
    ///
    /// Only the canonical control operation is a receipt: the same identity carrying an ordinary
    /// message purpose, an association this submission would not produce, or any other body is an
    /// identity conflict, exactly like a repeated body with different content.
    fn resident_control_receipt(
        previous: &input::InputRecord,
        input_id: &str,
    ) -> Result<input::InputRecord, ThreadError> {
        let Some(continuation) = previous.continuation.as_ref() else {
            return Err(ThreadError::InvalidIdentity);
        };
        let canonical = input::ThreadInput::for_continuation(
            input_id,
            &continuation.point_id,
            continuation.source_turn_id.as_deref(),
        );
        if previous.input.purpose != input::InputPurpose::Continuation
            || previous.input != canonical
        {
            return Err(ThreadError::InvalidIdentity);
        }
        Ok(previous.clone())
    }

    /// Whether a new submission may take the claim of `point_id`.
    ///
    /// A free claim is always available. A claim an **unconsumed body-less control** only holds as a
    /// placeholder may be taken over by any newer explicit authorization, and so may an **unconsumed
    /// parent message**: both are references to work nobody has executed yet. A real user input is
    /// never a placeholder, so it keeps its own authorization and is never silently replaced. The
    /// replaced fact is what decides, not who replaces it.
    pub(super) fn may_claim_continuation(&self, point_id: &str) -> bool {
        let Some(point) = self.state.continuation.as_ref() else {
            return false;
        };
        if point.id != point_id {
            return false;
        }
        match &point.claim {
            None => true,
            Some(ContinuationClaim::Input { input_id }) => self.state.inputs.iter().any(|record| {
                record.input.id == *input_id
                    && record.state == input::InputState::Pending
                    // A body-less control is only a placeholder, so a newer authorization replaces it. A
                    // real input keeps its own admitted fact and is consumed by the very batch the new
                    // authorization freezes, so only the claim reference moves and nothing is deleted.
                    && matches!(
                        record.input.purpose,
                        input::InputPurpose::Continuation | input::InputPurpose::Message
                    )
            }),
            Some(ContinuationClaim::InboxMessage { sequence, .. }) => {
                self.state.consumed_messages < *sequence
            }
        }
    }

    /// The point a new explicit continuation takes over from an unconsumed placeholder.
    fn takeoverable_continuation(&self) -> Option<&ContinuationPoint> {
        self.state
            .continuation
            .as_ref()
            .filter(|point| point.claim.is_some() && self.may_claim_continuation(&point.id))
    }

    /// The single boundary that records one continuation claim and the durability it owes.
    ///
    /// Every way a continuation can be authorized — a body-less control input, real user content or a
    /// parent message — ends up here, so "claimed" and "the durable watermark this claim owes" can
    /// never disagree: the requirement always names the very commit that carries the claim
    /// (`accepted_sequence`), because a later one would be a moving target and an earlier one would
    /// need a commit of its own. Claiming never deletes the point and never creates a second queue; it
    /// only names an already admitted fact, and the commit that really consumes that fact is what
    /// clears the point again.
    pub(super) fn record_claim(
        &mut self,
        point_id: &str,
        claim: ContinuationClaim,
        accepted_sequence: u64,
    ) {
        if let Some(point) = self.state.continuation.as_mut()
            && point.id == point_id
        {
            point.claim = Some(claim);
        }
        self.state.required_durable_sequence = Some(accepted_sequence);
    }

    /// Records the claim an admitted input carries.
    pub(super) fn record_input_claim(&mut self, carrier: &input::InputRecord) {
        let continuation = carrier
            .continuation
            .clone()
            .expect("a claim is recorded only for an input that carries one");
        self.record_claim(
            &continuation.point_id,
            ContinuationClaim::Input {
                input_id: carrier.input.id.clone(),
            },
            carrier.accepted_sequence,
        );
    }

    /// Settles the fact a new claim replaced and re-freezes the batch it was replacing.
    ///
    /// A replaced body-less control is voided in this same commit, so no admission can consume an input
    /// whose authorization was just withdrawn. A replaced parent message keeps its accepted fact and
    /// only loses the claim reference, so its body and delivery are untouched.
    ///
    /// A batch that is frozen but **not admitted yet** is cancelled instead of patched: its content was
    /// copied when it froze, so consuming the new carrier there would mark real content consumed without
    /// ever putting it in the request. The driver then freezes a fresh batch from the new authorization,
    /// which is why a replacement still produces exactly one Turn.
    pub(super) fn settle_replaced_carrier(
        &mut self,
        previous: &ContinuationClaim,
        carrier: Option<&str>,
    ) -> Result<(), ThreadError> {
        let re_freeze = self.execution_preparing();
        if let ContinuationClaim::Input { input_id } = previous {
            let input_id = input_id.clone();
            let seat = if re_freeze { None } else { carrier };
            self.void_superseded_control(&input_id, seat)?;
        }
        if re_freeze && let Some(turn) = self.frozen_turn.clone() {
            // The owner cancels its own preparing generation here and remembers the stop generation that
            // cancellation produced. Any later stop makes the count differ, so an external stop is never
            // read as the replacement it did not cause.
            self.interrupt.interrupt();
            self.superseded_batch = Some((turn, self.interrupt.stops()));
            return Ok(());
        }
        // Only a body-less control may join a batch that is already running: seating real content in a
        // batch whose request was built without it would mark that content consumed without sending it.
        // Real content always waits for the next freeze, which `input_batch_through` already covers.
        if let Some(carrier) = carrier
            && self.state.execution.is_some()
            && !self.active_inputs.iter().any(|active| active == carrier)
            && self.state.inputs.iter().any(|record| {
                record.input.id == carrier
                    && record.input.purpose == input::InputPurpose::Continuation
            })
        {
            self.active_inputs.push(carrier.to_owned());
        }
        Ok(())
    }

    /// Voids the body-less control a newer explicit continuation replaced.
    ///
    /// Only a body-less control is ever voided here, so no user input, attachment or parent message is
    /// deleted or rewritten.
    fn void_superseded_control(
        &mut self,
        id: &str,
        carrier: Option<&str>,
    ) -> Result<(), ThreadError> {
        let replaceable = self.state.inputs.iter().any(|record| {
            record.input.id == id
                && record.state == input::InputState::Pending
                && record.input.purpose == input::InputPurpose::Continuation
        });
        if !replaceable {
            return Ok(());
        }
        self.change_input(id, input::InputState::Discarded)?;
        // A batch that is still preparing keeps exactly one admission: the authorization that replaced
        // the voided control takes its place, so the replacement never opens an empty Turn for a batch
        // whose only input was voided. A message carrier needs no seat — it is delivered by the same
        // admission through the message watermark.
        if let Some(index) = self.active_inputs.iter().position(|active| active == id) {
            match carrier {
                Some(carrier) => self.active_inputs[index] = carrier.to_owned(),
                None => {
                    self.active_inputs.remove(index);
                }
            }
        }
        Ok(())
    }

    /// Drops the unconsumed control input a new explicit continuation replaces.
    ///
    /// Only a body-less control may be discarded here. Ordinary user input, attachments and parent
    /// messages keep their own admitted facts, so an explicit re-authorization never deletes real
    /// content. A control already frozen into the batch of a Turn that is still preparing is left to
    /// that Turn's settlement, which is the one place that knows whether it was really consumed.
    pub(super) fn discard_superseded_control_inputs(
        &mut self,
        keep: Option<&str>,
    ) -> Result<(), ThreadError> {
        let superseded = self
            .state
            .inputs
            .iter()
            .filter(|record| {
                record.state == input::InputState::Pending
                    && record.input.purpose == input::InputPurpose::Continuation
                    && Some(record.input.id.as_str()) != keep
                    && !self.active_inputs.contains(&record.input.id)
            })
            .map(|record| record.input.id.clone())
            .collect::<Vec<_>>();
        for id in superseded {
            self.change_input(&id, input::InputState::Discarded)?;
        }
        Ok(())
    }

    /// Settles the body-less controls that can no longer authorize anything.
    ///
    /// A pending control that is not the point's claim can never drive a Turn again, whether its
    /// batch is still preparing or the point it belonged to has already been served. Keeping it would
    /// leave phantom owed work that recovery would later report as interrupted. This runs inside the
    /// commit that publishes the Turn's terminal state, so "that work is over" and "this control is
    /// void" are the same fact.
    pub(super) fn settle_replaced_controls(&mut self) -> Result<(), ThreadError> {
        let claimed = self
            .state
            .continuation
            .as_ref()
            .and_then(ContinuationPoint::claimed_input)
            .map(str::to_owned);
        let replaced = self
            .state
            .inputs
            .iter()
            .filter(|record| {
                record.state == input::InputState::Pending
                    && record.input.purpose == input::InputPurpose::Continuation
                    && Some(record.input.id.as_str()) != claimed.as_deref()
            })
            .map(|record| record.input.id.clone())
            .collect::<Vec<_>>();
        for id in replaced {
            self.change_input(&id, input::InputState::Discarded)?;
        }
        Ok(())
    }

    /// Clears the point whose work this admission really served.
    ///
    /// Consumption, the message watermark and the point's removal are one commit: the point only
    /// disappears together with the fact that carried it, so a preparation failure or a stop right
    /// before admission leaves the owed work exactly as it was. `ran_queued_work` names the third way
    /// the owed work is served — a point nothing claimed any more, executed by the queued input or
    /// message this very admission consumed. Without it a stop during preparation would leave a point
    /// behind after the work it named had already run, and continuing again would open an empty Turn.
    pub(super) fn settle_continuation_claim(&mut self, ran_queued_work: bool) -> bool {
        let Some(point) = self.state.continuation.as_ref() else {
            return false;
        };
        let consumed = match point.claimed_input() {
            Some(input_id) => self.active_inputs.iter().any(|id| id == input_id),
            None => match point.claimed_message() {
                Some(sequence) => self.state.consumed_messages >= sequence,
                None => ran_queued_work,
            },
        };
        if consumed {
            self.state.continuation = None;
        }
        consumed
    }

    /// Forms (or keeps) the durable point that says this Thread still owes work.
    ///
    /// An equivalent point keeps its identity, so re-settling the same fact never renumbers it; a
    /// claim taken for the execution that is being interrupted is always dropped, because that
    /// authorization cannot survive the interruption it was used for.
    pub(super) fn form_continuation(
        &mut self,
        reason: ContinuationReason,
        source_turn_id: Option<String>,
        source: &str,
    ) {
        let equivalent = self
            .state
            .continuation
            .as_ref()
            .is_some_and(|point| point.same_fact(source_turn_id.as_deref(), Some(reason)));
        if let Some(point) = self.state.continuation.as_mut() {
            point.claim = None;
            if equivalent {
                return;
            }
        }
        self.state.continuation = Some(ContinuationPoint::new(
            self.state.commit_sequence,
            source,
            source_turn_id,
            Some(reason),
        ));
    }

    fn request_continuation(&mut self, options: input::InputDriverOptions) {
        self.input_driver.enable(options);
        if let Some(turn) = self
            .state
            .turns
            .iter()
            .rev()
            .find(|turn| turn.state == TurnState::Running)
        {
            let turn_id = turn.turn_id.clone();
            self.interrupted_turn = Some(turn_id.clone());
            // The receipt remains successful after admission even if cancellation cannot be committed.
            if let Err(error) = self.cancel_turn_tasks(&turn_id) {
                self.input_driver.fail(Arc::new(error));
                self.pause_inputs();
            }
            // Keeping the queue enabled for the continuation is authorized by this exact cancellation: a
            // later external stop produces a newer stop generation and pauses the queue instead.
            let (_, generation) = self.interrupt.interrupt_generation();
            self.continuation_cancel = Some(generation);
        }
        self.publish_snapshot();
    }

    pub(super) fn cancel_turn_tasks(&mut self, turn_id: &str) -> Result<(), ThreadError> {
        let tasks: Vec<_> = self
            .state
            .tasks
            .values()
            .filter(|task| task.turn_id == turn_id && task.status == task::TaskStatus::Running)
            .map(|task| task.id.clone())
            .collect();
        for task in tasks {
            self.cancel_task(&task)?;
        }
        Ok(())
    }

    pub(super) async fn settle_turn_cancellation(&mut self, turn_id: &str) {
        while self
            .state
            .tasks
            .values()
            .any(|task| task.turn_id == turn_id && task.status == task::TaskStatus::Running)
        {
            if self
                .uncommitted_tools
                .values()
                .any(|completion| completion.call.turn_id == turn_id)
            {
                self.input_driver
                    .fail(Arc::new(ThreadError::PendingToolCommit));
                self.pause_inputs();
                break;
            }
            tokio::select! {
                Some(completion) = futures::StreamExt::next(&mut self.background), if !self.background.is_empty() => self.finish_background(completion),
                message = self.mailbox.recv(), if !self.mailbox.is_closed() || !self.mailbox.is_empty() => {
                    if let Some(message) = message { self.dispatch_mailbox(message).await; }
                }
            }
        }
    }

    /// Wait in the owner loop for physical task completion, servicing the mailbox throughout.
    pub(super) fn continuation_ready(&mut self) -> bool {
        let Some(turn_id) = &self.interrupted_turn else {
            return true;
        };
        if self
            .state
            .turns
            .iter()
            .any(|turn| &turn.turn_id == turn_id && turn.state == TurnState::Running)
            || self
                .state
                .tasks
                .values()
                .any(|task| &task.turn_id == turn_id && task.status == task::TaskStatus::Running)
        {
            if self
                .uncommitted_tools
                .values()
                .any(|completion| &completion.call.turn_id == turn_id)
            {
                self.input_driver
                    .fail(Arc::new(ThreadError::PendingToolCommit));
                self.pause_inputs();
            }
            return false;
        }
        self.interrupted_turn = None;
        self.publish_snapshot();
        true
    }

    /// Whether one pending input is allowed to start a Turn.
    ///
    /// A body-less control only drives the continuation it currently carries. After an interruption
    /// an older control is retained for truthful history, but starting a Turn from it would execute
    /// work nobody authorized again, so it waits to be replaced by the next explicit continuation.
    pub(super) fn driveable(&self, record: &input::InputRecord) -> bool {
        record.state == input::InputState::Pending
            && match record.input.purpose {
                input::InputPurpose::Message => true,
                input::InputPurpose::Continuation => {
                    self.state
                        .continuation
                        .as_ref()
                        .and_then(ContinuationPoint::claimed_input)
                        == Some(record.input.id.as_str())
                }
            }
    }
}
