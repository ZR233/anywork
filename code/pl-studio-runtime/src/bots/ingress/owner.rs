//! 一次受管交接拥有全部在途操作和附件草稿，直到真实返回与异步清理完成。

use super::error::{attention, failure, history, retry, submit_absent};
use super::watch::InputWatch;
use crate::bots::owner::{BotRuntime, ManagedBot};
use crate::bots::send::SendSource;
use crate::bots::storage::{ClaimLease, FrozenInbound, InboundRetryWait};
use crate::bots::{BotInputRead, InboundWorkOutcome};
use crate::studio::{StudioRuntime, StudioSubmitPromptOptions, StudioSubmitPromptRequest};
use std::sync::Arc;
use std::sync::atomic::Ordering;
use std::time::Duration;
use tokio_util::sync::CancellationToken;

pub(super) const CLAIM_RENEW_INTERVAL: Duration = Duration::from_secs(15);

pub(super) struct IngressRun {
    pub(super) inbound: FrozenInbound,
    pub(super) worker_id: String,
    pub(super) input_id: String,
    pub(super) thread_id: Option<String>,
    /// None means not prepared, including a text-only request whose prepared batch is empty.
    drafts: Option<Vec<String>>,
    /// Ok/NotReady is accepted even if a later durable read is temporarily Absent.
    accepted: bool,
}

impl IngressRun {
    fn new(inbound: FrozenInbound, worker_id: &str) -> Self {
        Self {
            input_id: format!(
                "bot:{}:{}:{}",
                inbound.bot_id, inbound.chat_id, inbound.message_id
            ),
            inbound,
            worker_id: worker_id.to_string(),
            thread_id: None,
            drafts: None,
            accepted: false,
        }
    }

    pub(super) fn source(&self, thread_id: &str) -> SendSource {
        SendSource {
            bot_id: self.inbound.bot_id.clone(),
            chat_id: self.inbound.chat_id.clone(),
            app_id: self.inbound.app_id.clone(),
            project_id: self.inbound.project_id.clone(),
            thread_id: thread_id.to_string(),
            input_id: self.input_id.clone(),
            original_input_id: self.input_id.clone(),
            message_id: self.inbound.message_id.clone(),
            open_id: self.inbound.open_id.clone(),
            chat_kind: self.inbound.chat_kind.clone(),
            creation_id: self.inbound.creation_id.clone(),
            binding_revision: self.inbound.binding_revision,
        }
    }

    pub(super) fn watch_input(&self) -> &str {
        if self.inbound.watch_input.is_empty() {
            &self.input_id
        } else {
            &self.inbound.watch_input
        }
    }

    async fn release_drafts(&mut self, runtime: &StudioRuntime) {
        if let Some(drafts) = self.drafts.take() {
            for draft in drafts {
                if let Err(error) = runtime.remove_attachment_draft(draft).await {
                    // Canonical resources have their own owner. Staging cleanup cannot turn an
                    // already proven durable admission into a retry of the model input.
                    tracing::warn!(kind=?crate::studio::startup::StudioStartupError::input("bot attachment staging cleanup", error).kind, "bot attachment draft cleanup failed");
                }
            }
        }
    }
}

pub(super) struct IngressControl {
    cancel: CancellationToken,
    lost: CancellationToken,
}

impl IngressControl {
    pub(super) fn stopped(&self, runtime: &BotRuntime) -> Option<InboundWorkOutcome> {
        if self.lost.is_cancelled() {
            Some(InboundWorkOutcome::LostClaim)
        } else if self.cancel.is_cancelled() || runtime.inner.sealed.load(Ordering::SeqCst) != 0 {
            Some(InboundWorkOutcome::Interrupted)
        } else {
            None
        }
    }

    pub(super) fn resource_cancel(&self) -> CancellationToken {
        // The dispatch driver cancels this child on either shutdown or lost lease. It never
        // drops a resource-admission/submit future to accomplish cancellation.
        self.cancel.clone()
    }

    pub(super) async fn cancelled(&self) {
        tokio::select! {
            _ = self.cancel.cancelled() => {}
            _ = self.lost.cancelled() => {}
        }
    }
}

impl BotRuntime {
    /// Finishes only after canonical input persistence (or a typed stop/failure), never a Turn.
    /// The caller owns this future in its JoinSet and must drain it rather than abort it.
    pub(crate) async fn dispatch_inbound(
        &self,
        inbound: FrozenInbound,
        worker_id: &str,
        cancel: CancellationToken,
    ) -> InboundWorkOutcome {
        let managed = match self.managed(&inbound.bot_id).await {
            Ok(managed) => managed,
            Err(error) => return failure("bot runtime unavailable before input handoff", error),
        };
        let control = IngressControl {
            cancel: cancel.child_token(),
            lost: CancellationToken::new(),
        };
        let bot_id = inbound.bot_id.clone();
        let chat_id = inbound.chat_id.clone();
        let message_id = inbound.message_id.clone();
        let run = self.run_inbound(managed.clone(), inbound, worker_id, &control);
        tokio::pin!(run);
        loop {
            tokio::select! {
                outcome = &mut run => return outcome,
                _ = tokio::time::sleep(CLAIM_RENEW_INTERVAL) => {}
            }
            // Keep polling the run while renewing: it may own the transaction/connection that
            // renewal needs. Neither future may be dropped with an in-flight database action.
            let renewal =
                managed
                    .store
                    .renew_inbound_claim(&bot_id, &chat_id, &message_id, worker_id);
            tokio::pin!(renewal);
            let lease = tokio::select! {
                outcome = &mut run => {
                    let _settled = renewal.await;
                    return outcome;
                }
                lease = &mut renewal => lease,
            };
            match lease {
                Ok(ClaimLease::Renewed) => {}
                Ok(ClaimLease::LostClaim) | Err(_) => {
                    control.lost.cancel();
                    control.cancel.cancel();
                    let _settled = run.await;
                    return InboundWorkOutcome::LostClaim;
                }
            }
        }
    }

    async fn run_inbound(
        &self,
        managed: Arc<ManagedBot>,
        inbound: FrozenInbound,
        worker_id: &str,
        control: &IngressControl,
    ) -> InboundWorkOutcome {
        let mut run = IngressRun::new(inbound, worker_id);
        if let Some(outcome) = control.stopped(self) {
            return outcome;
        }
        if crate::bots::inbound::unsupported_only(&run.inbound.text, &run.inbound.attachments) {
            return self.unsupported_inbound(&managed, &run, control).await;
        }
        let Some(runtime) = self.studio_host() else {
            return retry("studio runtime host is unavailable for input handoff");
        };
        let outcome = self
            .handoff_inbound(&managed, &runtime, &mut run, control)
            .await;
        // No in-flight submit or resource operation survives this point. Cleanup is awaited even
        // after cancellation/lost claim; removing staging never removes canonical resources.
        run.release_drafts(&runtime).await;
        outcome
    }

    async fn handoff_inbound(
        &self,
        managed: &Arc<ManagedBot>,
        runtime: &StudioRuntime,
        run: &mut IngressRun,
        control: &IngressControl,
    ) -> InboundWorkOutcome {
        run.thread_id = match self.known_inbound_thread(managed, runtime, run).await {
            Ok(thread) => thread,
            Err(outcome) => return outcome,
        };
        // Canonical facts win over later configuration, trust, archive and route changes.
        // In particular, accepted work must not be retrospectively rejected by a new gate.
        if let Some(thread) = &run.thread_id {
            match runtime.bot_input_fact(thread, &run.input_id).await {
                Ok(BotInputRead::Ready { .. }) => return InboundWorkOutcome::Completed,
                Ok(BotInputRead::NotReady) => run.accepted = true,
                Ok(BotInputRead::Absent) => {}
                Err(error) => return history("canonical inbound input read failed", error),
            }
        }
        if !run.accepted {
            run.thread_id = match self
                .resolve_inbound_thread(managed, runtime, run, control)
                .await
            {
                Ok(thread) => Some(thread),
                Err(outcome) => return outcome,
            };
        }
        let Some(thread_id) = run.thread_id.clone() else {
            return attention("inbound input has no provable original Thread");
        };
        let mut watch = InputWatch::new();
        let mut retry_at = None;
        loop {
            match runtime.bot_input_fact(&thread_id, &run.input_id).await {
                Ok(BotInputRead::Ready { .. }) => return InboundWorkOutcome::Completed,
                Ok(BotInputRead::NotReady) => run.accepted = true,
                Ok(BotInputRead::Absent) if !run.accepted => {
                    if let Some(outcome) = control.stopped(self) {
                        return outcome;
                    }
                    if retry_at.is_some_and(|at| at > crate::studio::unix_seconds()) {
                        if let Err(error) = watch
                            .wait_prepared(runtime, &thread_id, control, retry_at)
                            .await
                        {
                            return history("input submit retry observation failed", error);
                        }
                        continue;
                    }
                    if run.watch_input() != run.input_id {
                        return attention(
                            "legacy continuation has no provable original input receipt",
                        );
                    }
                    if let Err(outcome) = self.admit_inbound_input(managed, run, control).await {
                        if run.drafts.is_some()
                            && matches!(outcome, InboundWorkOutcome::Deferred { .. })
                        {
                            if let Err(error) = watch
                                .wait_prepared(runtime, &thread_id, control, None)
                                .await
                            {
                                return history(
                                    "prepared input readiness observation failed",
                                    error,
                                );
                            }
                            continue;
                        }
                        return outcome;
                    }
                    if run.drafts.is_none() {
                        let cancel = control.resource_cancel();
                        match self
                            .prepare_inbound_attachments(
                                runtime,
                                &run.inbound.bot_id,
                                &thread_id,
                                &run.inbound.message_id,
                                &run.inbound.attachments,
                                &cancel,
                            )
                            .await
                        {
                            Ok(drafts) => run.drafts = Some(drafts),
                            Err(error) => {
                                return control.stopped(self).unwrap_or_else(|| {
                                    failure("inbound attachment preparation failed", error)
                                });
                            }
                        }
                    }
                    // Download may have crossed a revoke/replace. Recheck immediately before
                    // submit, without holding admission across either network or Thread waits.
                    if let Err(outcome) = self.admit_inbound_input(managed, run, control).await {
                        if matches!(outcome, InboundWorkOutcome::Deferred { .. }) {
                            if let Err(error) = watch
                                .wait_prepared(runtime, &thread_id, control, None)
                                .await
                            {
                                return history(
                                    "prepared input readiness observation failed",
                                    error,
                                );
                            }
                            continue;
                        }
                        return outcome;
                    }
                    let Some(drafts) = &run.drafts else {
                        return attention("prepared inbound attachment ownership is missing");
                    };
                    let result = runtime
                        .submit_queued_prompt(StudioSubmitPromptRequest {
                            thread_id: thread_id.clone(),
                            input: pl_protocol::studio::StudioPromptInput {
                                input_id: run.input_id.clone(),
                                text: run.inbound.text.clone(),
                                attachment_draft_ids: drafts.clone(),
                            },
                            options: StudioSubmitPromptOptions::default(),
                        })
                        .await;
                    // Even Err may follow core acceptance. Read the SAME input first, including
                    // during shutdown, before using the typed failure's stage to decide anything.
                    let confirmed = loop {
                        match runtime.bot_input_fact(&thread_id, &run.input_id).await {
                            Ok(input) => break input,
                            Err(error) => {
                                if let Some(outcome) = control.stopped(self) {
                                    return outcome;
                                }
                                let outcome =
                                    history("input handoff persistence confirmation failed", error);
                                if !matches!(outcome, InboundWorkOutcome::Recoverable { .. }) {
                                    return outcome;
                                }
                                // A failed confirmation does not discard this actual attempt or
                                // make Unknown retryable. Keep its result/drafts until a fact can
                                // be read; only an explicit Absent may reach the retry classifier.
                                if let Err(error) = watch
                                    .wait_prepared(runtime, &thread_id, control, None)
                                    .await
                                {
                                    return history(
                                        "input handoff confirmation observation failed",
                                        error,
                                    );
                                }
                            }
                        }
                    };
                    match confirmed {
                        BotInputRead::Ready { .. } => return InboundWorkOutcome::Completed,
                        BotInputRead::NotReady => run.accepted = true,
                        BotInputRead::Absent => match result {
                            Ok(_) => run.accepted = true,
                            Err(error) => {
                                let outcome = control
                                    .stopped(self)
                                    .unwrap_or_else(|| submit_absent(error));
                                let InboundWorkOutcome::Recoverable { diagnostic } = &outcome
                                else {
                                    return outcome;
                                };
                                // Only a typed pre-acceptance failure reaches this point, after
                                // re-reading the SAME input as Absent. Debit the original budget
                                // without ending this claim or handing its drafts to a re-enqueue.
                                match managed
                                    .store
                                    .retain_inbound_retry(&run.inbound, &run.worker_id, diagnostic)
                                    .await
                                {
                                    Ok(InboundRetryWait::Until { retry_at: at }) => {
                                        retry_at = Some(at)
                                    }
                                    Ok(InboundRetryWait::BudgetExhausted) => return outcome,
                                    Ok(InboundRetryWait::LostClaim) => {
                                        return InboundWorkOutcome::LostClaim;
                                    }
                                    Err(error) => {
                                        return attention(format!(
                                            "input submit retry budget persistence is unconfirmed; local recovery required: {error}"
                                        ));
                                    }
                                }
                            }
                        },
                    }
                }
                Ok(BotInputRead::Absent) => {}
                Err(error) => {
                    if let Some(outcome) = control.stopped(self) {
                        return outcome;
                    }
                    let outcome = history("canonical inbound input read failed", error);
                    if retry_at.is_some()
                        && !run.accepted
                        && matches!(outcome, InboundWorkOutcome::Recoverable { .. })
                    {
                        if let Err(error) = watch
                            .wait_prepared(runtime, &thread_id, control, None)
                            .await
                        {
                            return history("input submit retry observation failed", error);
                        }
                        continue;
                    }
                    return outcome;
                }
            }
            if let Some(outcome) = control.stopped(self) {
                return outcome;
            }
            if run.accepted {
                // An accepted input is never submitted again, even when the old retry deadline
                // expires while its durable projection is still NotReady/temporarily Absent.
                retry_at = None;
            }
            // Awaiting persistence is not Preparing: it never enters the 900-second first-cut
            // budget or waits for model/platform completion. A retained pre-admission retry uses
            // the same owner/drafts and the store's original next_attempt_at instead.
            let wake = if run.drafts.is_some() {
                watch
                    .wait_prepared(runtime, &thread_id, control, retry_at)
                    .await
            } else {
                watch.wait(runtime, &thread_id, control, retry_at).await
            };
            if let Err(error) = wake {
                return history("input persistence observation failed", error);
            }
        }
    }

    pub(super) async fn hold_inbound_claim(
        &self,
        managed: &ManagedBot,
        run: &IngressRun,
        control: &IngressControl,
    ) -> Result<(), InboundWorkOutcome> {
        if let Some(outcome) = control.stopped(self) {
            return Err(outcome);
        }
        match managed
            .store
            .renew_inbound_claim(
                &run.inbound.bot_id,
                &run.inbound.chat_id,
                &run.inbound.message_id,
                &run.worker_id,
            )
            .await
        {
            Ok(ClaimLease::Renewed) => control.stopped(self).map_or(Ok(()), Err),
            Ok(ClaimLease::LostClaim) | Err(_) => Err(InboundWorkOutcome::LostClaim),
        }
    }
}
