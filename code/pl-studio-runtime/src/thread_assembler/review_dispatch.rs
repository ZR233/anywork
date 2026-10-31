//! Managed terminal-to-feedback handoff. The projection registers, but never waits on this job.
use super::{
    StudioThreadAssembler,
    agent_review::{
        ReviewDeliverySource, ReviewFeedbackDelivery, ReviewForward, ReviewForwardReason,
    },
    review_delivery::ReviewDeliveryException,
};
use crate::studio::HistoryChannel;
use anyhow::{Context, Result, ensure};
use pl_core::thread::{ThreadSnapshot, TurnRecord};
use pl_tool::finish_turn::{ReviewDisposition, SavedFinishTurn};
use std::sync::{
    Arc,
    atomic::{AtomicU64, Ordering},
};

/// One shared prepared-material charge. The callback captures only weak owners, so an admitted
/// batch cannot create an owner -> queue -> batch -> owner cycle.
pub(crate) struct TerminalMaterialRetention(Option<Box<dyn FnOnce() + Send + Sync>>);
impl TerminalMaterialRetention {
    pub(crate) fn new(release: impl FnOnce() + Send + Sync + 'static) -> Self {
        Self(Some(Box::new(release)))
    }
}
impl std::fmt::Debug for TerminalMaterialRetention {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("TerminalMaterialRetention")
    }
}
impl Drop for TerminalMaterialRetention {
    fn drop(&mut self) {
        if let Some(release) = self.0.take() {
            release();
        }
    }
}

#[derive(Debug, thiserror::Error)]
#[error("terminal material byte reservation is unavailable")]
pub(crate) struct TerminalBudgetBlocked;
#[derive(Debug, thiserror::Error)]
#[error("terminal delivery integrity blocked: {0}")]
pub(crate) struct TerminalIntegrityError(pub(crate) &'static str);

#[derive(Clone)]
pub(crate) struct TerminalDelivery {
    pub thread: pl_protocol::Thread,
    pub sequence: u64,
    pub authority: Arc<TerminalAuthority>,
    pub original: Option<Arc<pl_core::thread::inbox::ThreadMessage>>,
    pub source: ReviewDeliverySource,
    pub revocation: Arc<AtomicU64>,
    pub channel: Option<Arc<HistoryChannel>>,
    pub wake: bool,
    pub _material: Option<Arc<TerminalMaterialRetention>>,
}
/// Frozen authority, not a partial ThreadSnapshot masquerading as a complete core state. The
/// workspace opaque record shares its original payload; the only Profile fact used by dispatch
/// is its validated workspace mode. Context, inbox, inputs and unrelated extensions never enter.
pub(crate) struct TerminalAuthority {
    workspace: Option<pl_core::thread::extensions::ExtensionRecord>,
    profile_mode: Option<pl_protocol::AgentWorkspaceMode>,
}
impl TerminalAuthority {
    pub(crate) fn capture(snapshot: &ThreadSnapshot) -> Result<Self> {
        let profile_mode = crate::studio::model_route::saved_profile(snapshot)?
            .map(|(profile, _)| profile.workspace_mode);
        Ok(Self {
            workspace: snapshot
                .extensions
                .get(crate::studio::workspace_receipt::EXTENSION)
                .cloned(),
            profile_mode,
        })
    }

    pub(crate) fn retained_bytes(&self) -> u64 {
        (std::mem::size_of::<Self>() as u64).saturating_add(self.workspace.as_ref().map_or(
            0,
            |record| {
                (record.payload.content().len() as u64)
                    .saturating_add(record.payload.format().len() as u64)
            },
        ))
    }

    fn assignment(&self) -> Result<Option<pl_protocol::AgentWorkspaceAssignmentSnapshot>> {
        self.workspace
            .as_ref()
            .map(|record| crate::studio::workspace_receipt::from_payload(&record.payload))
            .transpose()
    }
}

pub(crate) struct ReviewDispatch {
    pub reviewer: pl_protocol::Thread,
    pub turn: TurnRecord,
    pub terminal_sequence: u64,
    pub authority: Arc<TerminalAuthority>,
    pub finish: Option<SavedFinishTurn>,
    pub source: ReviewDeliverySource,
    pub revocation: Arc<AtomicU64>,
    pub channel: Option<Arc<HistoryChannel>>,
    pub original: pl_core::thread::inbox::ThreadMessage,
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct OriginalReport {
    child_id: String,
    commit_sequence: u64,
    turn: TurnRecord,
    turn_id: String,
    input_id: Option<String>,
    review: Option<OriginalReview>,
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct OriginalReview {
    target: Option<pl_protocol::AgentReviewTargetSnapshot>,
    disposition: ReviewDisposition,
    reason: Option<String>,
}

fn original_report(
    message: &pl_core::thread::inbox::ThreadMessage,
) -> Result<Option<OriginalReport>> {
    if message.payload.format() != "pl.studio.turn-report" || message.payload.version() != 3 {
        // Historical reports are original readable bytes, never a source of new authority.
        return Ok(None);
    }
    let original: OriginalReport = serde_json::from_str(message.payload.content())?;
    ensure!(
        message.id
            == crate::studio::agent_close::terminal_report_id(
                &original.child_id,
                original.commit_sequence
            )
            && message.source_id == format!("studio.child:{}", original.child_id)
            && original.turn.turn_id == original.turn_id
            && original.turn.input_id == original.input_id,
        TerminalIntegrityError("original review terminal identity mismatch")
    );
    Ok(Some(original))
}

struct TerminalResources {
    source: Option<Arc<HistoryChannel>>,
    parent: Option<Arc<HistoryChannel>>,
    source_mark: Option<(u64, u64, bool, u64, u64)>,
    parent_mark: Option<(u64, u64, bool, u64, u64)>,
    process_bytes: u64,
    source_incarnation: Option<Arc<()>>,
    parent_incarnation: Option<Arc<()>>,
}

impl TerminalResources {
    fn improved(&self, before: &Self, budget: bool) -> bool {
        fn replaced<T>(now: &Option<Arc<T>>, before: &Option<Arc<T>>) -> bool {
            match (now, before) {
                (Some(now), Some(before)) => !Arc::ptr_eq(now, before),
                (Some(_), None) => true,
                (None, Some(_)) => true,
                _ => false,
            }
        }
        fn progressed(
            now: Option<(u64, u64, bool, u64, u64)>,
            before: Option<(u64, u64, bool, u64, u64)>,
            budget: bool,
        ) -> bool {
            match (now, before) {
                (Some(now), Some(before)) if budget => now.3 < before.3,
                (Some(now), Some(before)) => {
                    now.0 > before.0 || (before.2 && !now.2) || now.1 > before.1
                }
                _ => false,
            }
        }
        if budget {
            // A failed speculative reservation releases its own bytes. Comparing with the mark
            // taken *before* the attempt, rather than an epoch alone, excludes that self-wakeup.
            self.process_bytes < before.process_bytes
                || progressed(self.source_mark, before.source_mark, true)
                || progressed(self.parent_mark, before.parent_mark, true)
        } else {
            progressed(self.source_mark, before.source_mark, false)
                || progressed(self.parent_mark, before.parent_mark, false)
                || replaced(&self.source, &before.source)
                || replaced(&self.parent, &before.parent)
                || replaced(&self.source_incarnation, &before.source_incarnation)
                || replaced(&self.parent_incarnation, &before.parent_incarnation)
        }
    }
}

impl StudioThreadAssembler {
    /// This is only the ownership acknowledgement. All IO, body copies and their fallible
    /// reservations occur in the retained operation after the real history handoff.
    pub(crate) async fn start_terminal_delivery(
        &self,
        terminal: Arc<TerminalDelivery>,
    ) -> Result<()> {
        let services = self
            .0
            .state()
            .agent_services
            .clone()
            .context("terminal services unavailable")?;
        let operations = services.operations.clone();
        let owner = self.clone();
        let key =
            crate::studio::agent_close::terminal_report_id(&terminal.thread.id, terminal.sequence);
        let caller = terminal.thread.id.clone();
        let registered_key = key.clone();
        operations.start(caller, key, || Ok(()), Box::pin(async move {
            let parent = terminal.thread.parent_thread_id.as_deref().context("terminal child has no parent")?;
            let mut capacity = services.store.thread_persistence().subscribe_delivery_capacity();
            let mut persistence = services.store.thread_persistence().subscribe();
            let mut first_failure = None;
            loop {
                let before = owner.terminal_resources(&services, &terminal, parent);
                let mut source_changes = before.source.as_ref().map(|channel| channel.subscribe());
                let mut parent_changes = before.parent.as_ref().map(|channel| channel.subscribe());
                match Box::pin(owner.deliver_terminal_once(&services, &terminal)).await {
                    Ok(()) => return Ok(()),
                    Err(error) => {
                        terminal.revocation.fetch_max(terminal.sequence, Ordering::AcqRel);
                        services.operations.block_terminal(&terminal.thread.id, &registered_key, &error, &mut first_failure);
                        let budget = error.downcast_ref::<TerminalBudgetBlocked>().is_some();
                        let permanent = error.downcast_ref::<TerminalIntegrityError>().is_some()
                            || error.downcast_ref::<serde_json::Error>().is_some();
                        loop {
                            let changed = owner.0.changed.notified();
                            tokio::pin!(changed);
                            changed.as_mut().enable();
                            let current = owner.terminal_resources(&services, &terminal, parent);
                            let explicit_retry = !services.operations.terminal_blocked(&terminal.thread.id, &registered_key);
                            if permanent && explicit_retry {
                                services.operations.block_terminal(&terminal.thread.id, &registered_key, &error, &mut first_failure);
                            }
                            if !permanent && (explicit_retry || current.improved(&before, budget)) {
                                services.operations.resume_terminal(&terminal.thread.id, &registered_key);
                                break;
                            }
                            // Watchers were installed before the attempt. Failed reservation rollback
                            // can wake this select, but cannot satisfy improved() against before.
                            let waiting = async { tokio::select! {
                                _ = capacity.changed() => {},
                                _ = persistence.changed() => {},
                                () = &mut changed => {},
                                _ = async { match source_changes.as_mut() { Some(receiver) => { let _ = receiver.changed().await; }, None => std::future::pending::<()>().await } } => {},
                                _ = async { match parent_changes.as_mut() { Some(receiver) => { let _ = receiver.changed().await; }, None => std::future::pending::<()>().await } } => {},
                            }};
                            #[cfg(test)]
                            {
                                tokio::pin!(waiting);
                                futures::future::poll_fn(|context| {
                                    let polled = std::future::Future::poll(waiting.as_mut(), context);
                                    if polled.is_pending() && let Some(channel) = &terminal.channel {
                                        // This signal runs only when ALL real wake sources returned
                                        // Pending. It cannot mask a missing capacity notification.
                                        channel.terminal_parked.send_replace(*channel.effects_released.borrow());
                            }
                                    polled
                                }).await;
                            }
                            #[cfg(not(test))]
                            waiting.await;
                        }
                    }
                }
            }
        })).await?;
        self.0.changed.notify_waiters();
        Ok(())
    }

    fn terminal_resources(
        &self,
        services: &super::agent_services::AgentServices,
        terminal: &TerminalDelivery,
        parent: &str,
    ) -> TerminalResources {
        let source = services
            .store
            .thread_persistence()
            .retained_history_channel(&terminal.thread.id)
            .or_else(|| terminal.channel.clone());
        let parent_channel = services
            .store
            .thread_persistence()
            .retained_history_channel(parent);
        let (source_incarnation, parent_incarnation) = {
            let state = self.0.state();
            (
                state
                    .entries
                    .get(&terminal.thread.id)
                    .map(|entry| entry.incarnation.clone()),
                state
                    .entries
                    .get(parent)
                    .map(|entry| entry.incarnation.clone()),
            )
        };
        TerminalResources {
            process_bytes: services.store.thread_persistence().delivery_process_bytes(),
            source_mark: source.as_ref().map(|channel| channel.delivery_retry_mark()),
            parent_mark: parent_channel
                .as_ref()
                .map(|channel| channel.delivery_retry_mark()),
            source,
            parent: parent_channel,
            parent_incarnation,
            source_incarnation,
        }
    }

    async fn deliver_terminal_once(
        &self,
        services: &super::agent_services::AgentServices,
        terminal: &TerminalDelivery,
    ) -> Result<()> {
        // A prior failed exception CAS may also have left a temporary source receiver to join.
        // A durable exception alone never discharges that retained physical cleanup obligation.
        self.finish_report_receiver(&terminal.thread.id).await?;
        if let Some(channel) = &terminal.channel {
            if channel.handoff_ticket() >= terminal.sequence {
                channel
                    .await_handoff_durable(&terminal.thread.id, terminal.sequence)
                    .await?;
            } else {
                ensure!(
                    channel.delivery_retry_mark().0 >= terminal.sequence,
                    "terminal operation has no handed history ticket"
                );
            }
        }
        let history = services.store.history(&terminal.thread.id).await?;
        let bytes = history.parent_report_bytes(terminal.sequence).await?;
        let extra = terminal.authority.retained_bytes();
        let _parent_copy = services.store.thread_persistence().retain_review_delivery(
            &terminal.thread.id,
            bytes
                .saturating_mul(4)
                .saturating_add(extra.saturating_mul(4))
                .saturating_add(8192),
        )?;
        let original =
            history
                .parent_report(terminal.sequence)
                .await?
                .ok_or(TerminalIntegrityError(
                    "original terminal message is missing",
                ))?;
        if let Some(expected) = &terminal.original {
            ensure!(
                expected.digest() == original.digest(),
                TerminalIntegrityError("prepared original differs from durable original")
            );
        }
        let parent = terminal
            .thread
            .parent_thread_id
            .as_deref()
            .context("terminal child has no parent")?;
        self.acknowledge_review_exception(parent, original.clone(), terminal.wake)
            .await?;
        let Some(report) = original_report(&original)?.filter(|report| report.review.is_some())
        else {
            return Ok(());
        };
        let finish_bytes = history.review_finish_bytes(&report.turn_id).await?;
        let _review_copy = services.store.thread_persistence().retain_review_delivery(
            &terminal.thread.id,
            finish_bytes.saturating_mul(4).saturating_add(128 * 1024),
        )?;
        let finish = if let Some(call) = history.review_finish_call(&report.turn_id).await? {
            history
                .tool_task(&call)
                .await?
                .filter(|saved| saved.task.turn_id == report.turn_id)
                .and_then(|saved| {
                    saved
                        .delivery
                        .as_ref()
                        .and_then(crate::studio::thread_projection::committed_finish)
                })
        } else {
            None
        };
        self.perform_review_delivery(ReviewDispatch {
            reviewer: terminal.thread.clone(),
            turn: report.turn,
            terminal_sequence: terminal.sequence,
            authority: terminal.authority.clone(),
            finish,
            source: if terminal.revocation.load(Ordering::Acquire) >= terminal.sequence {
                ReviewDeliverySource::Reconciliation
            } else {
                terminal.source
            },
            revocation: terminal.revocation.clone(),
            channel: None,
            original,
        })
        .await
    }
    /// Bounded history pages keep all old terminal obligations visible during close/restart.
    pub(crate) async fn recover_saved_review_deliveries(
        &self,
        reviewer: &pl_protocol::Thread,
    ) -> Result<()> {
        if reviewer.parent_thread_id.is_none() {
            return Ok(());
        }
        let services = self
            .0
            .state()
            .agent_services
            .clone()
            .context("review services unavailable")?;
        let Some(checkpoint) =
            crate::studio::thread_factory::recovery::load_checkpoint_for_recovery(
                &services.store,
                reviewer,
            )
            .await?
        else {
            return Ok(());
        };
        let history = services.store.history(&reviewer.id).await?;
        // The cold enumeration uses the same minimal authority carrier as live transfer. Drop the
        // source checkpoint before registering jobs, not at the end of the enumeration future.
        let authority = Arc::new(TerminalAuthority::capture(&checkpoint.state)?);
        drop(checkpoint);
        let bytes = authority.retained_bytes().saturating_add(4096);
        let material_channel = services
            .store
            .thread_persistence()
            .history_channel(&reviewer.id);
        let material = services
            .store
            .thread_persistence()
            .retain_terminal_material(&reviewer.id, &material_channel, bytes, None)?;
        let mut after = 0;
        loop {
            let sequences = history.terminal_report_sequences(after).await?;
            if sequences.is_empty() {
                return Ok(());
            }
            for sequence in sequences {
                self.start_terminal_delivery(Arc::new(TerminalDelivery {
                    thread: reviewer.clone(),
                    sequence,
                    authority: authority.clone(),
                    original: None,
                    source: ReviewDeliverySource::Reconciliation,
                    revocation: Arc::new(AtomicU64::new(u64::MAX)),
                    channel: None,
                    wake: false,
                    _material: Some(material.clone()),
                }))
                .await?;
                after = sequence;
            }
        }
    }

    pub(super) async fn acknowledge_review_exception(
        &self,
        parent: &str,
        message: pl_core::thread::inbox::ThreadMessage,
        wake: bool,
    ) -> Result<()> {
        use super::observation::DurableMessageIdentity;
        self.finish_report_receiver(parent).await?;
        if self
            .durable_message_identity(parent, &message.id)
            .await?
            .is_none()
        {
            if self.observed_thread(parent).is_some() {
                let _delivery = self.notify_parent(parent, message.clone(), wake).await?;
                self.synchronize_observation(parent).await?;
            }
            if self
                .durable_message_identity(parent, &message.id)
                .await?
                .is_none()
            {
                let services = self
                    .0
                    .state()
                    .agent_services
                    .clone()
                    .context("review services unavailable")?;
                services
                    .redeliver_parent_report(self, parent, message.clone())
                    .await?;
            }
        }
        match self.durable_message_identity(parent, &message.id).await? {
            Some(DurableMessageIdentity::Proven { digest, .. }) => ensure!(
                digest == message.digest(),
                TerminalIntegrityError("parent terminal message conflicts with durable original")
            ),
            Some(DurableMessageIdentity::Unverifiable) => {
                anyhow::bail!(TerminalIntegrityError(
                    "parent terminal receipt is unverifiable"
                ))
            }
            None => anyhow::bail!("parent review exception was not durably acknowledged"),
        }
        Ok(())
    }
    // Keep this owned handoff out of the much larger close/recovery future's inline state.
    // Otherwise nested cold close/ACK construction can overflow the default executor stack.
    fn perform_review_delivery(
        &self,
        request: ReviewDispatch,
    ) -> futures::future::BoxFuture<'_, Result<()>> {
        Box::pin(async move {
            let Some(original) = original_report(&request.original)? else {
                return Ok(());
            };
            let Some(review) = original.review else {
                return Ok(());
            };
            ensure!(
                original.child_id == request.reviewer.id
                    && original.commit_sequence == request.terminal_sequence
                    && original.turn_id == request.turn.turn_id
                    && original.input_id == request.turn.input_id,
                TerminalIntegrityError("review dispatch differs from its immutable terminal")
            );
            let Some(finish) = request.finish else {
                ensure!(
                    review.reason.is_some()
                        || review.disposition == ReviewDisposition::Inconclusive,
                    TerminalIntegrityError(
                        "immutable structured review has no successful committed finish receipt"
                    )
                );
                return Ok(());
            };
            let Some(conclusion) = finish.review else {
                return Ok(());
            };
            if conclusion.disposition == ReviewDisposition::Inconclusive
                || !matches!(
                    request.turn.state,
                    pl_core::thread::TurnState::Finished(pl_core::thread::TurnOutcome::Completed)
                )
                || review.reason.is_some()
                || review.disposition != conclusion.disposition
            {
                return Ok(());
            }
            let Some(assignment) = request.authority.assignment()? else {
                return Ok(());
            };
            if assignment.mode != pl_protocol::AgentWorkspaceMode::Review
                || request.authority.profile_mode != Some(pl_protocol::AgentWorkspaceMode::Review)
            {
                return Ok(());
            }
            let Some(target) = assignment.review_target.as_ref().filter(|target| {
                target.baseline.is_some() && target.agent_id != request.reviewer.id
            }) else {
                return Ok(());
            };
            ensure!(
                review.target.as_ref() == Some(target),
                TerminalIntegrityError("saved review target differs from frozen authority")
            );
            if conclusion.disposition == ReviewDisposition::NeedsChanges
                && target.feedback != Some(pl_protocol::AgentReviewFeedback::ToExecutor)
            {
                return Ok(());
            }
            let target_id = target.agent_id.clone();
            let body = if conclusion.disposition == ReviewDisposition::NeedsChanges {
                finish.feedback_message.ok_or(TerminalIntegrityError(
                    "typed review has no saved feedback wrapper",
                ))?
            } else {
                String::new()
            };
            let services = self
                .0
                .state()
                .agent_services
                .clone()
                .context("review services unavailable")?;
            let owner = self.clone();
            let reviewer = request.reviewer;
            let turn = request.turn;
            let sequence = request.terminal_sequence;
            let channel = request.channel;
            let revocation = request.revocation;
            let source = request.source;
            Box::pin(async move {
                if let Some(channel) = channel.filter(|channel| channel.handoff_ticket() >= sequence) {
                    channel
                        .await_handoff_durable(&reviewer.id, sequence)
                        .await?;
                }
                let history = services.store.history(&reviewer.id).await?;
                ensure!(
                    history.parent_report(sequence).await?.is_some(),
                    "review terminal has no durable original report"
                );
                let recovery = ReviewForward::Unconfirmed {
                    message_id: super::agent_review::review_message_id(
                        &reviewer.id,
                        &turn.turn_id,
                        sequence,
                    ),
                    reason: ReviewForwardReason::RecoveryRequiresScheduling,
                };
                let recovery_fact = ReviewDeliveryException::from_forward(
                    &reviewer.id,
                    &turn.turn_id,
                    turn.input_id.as_deref(),
                    sequence,
                    &target_id,
                    source,
                    &recovery,
                )
                .context("recovery exception identity missing")?
                .into_fact()?;
                let saved = history
                    .review_delivery_exception(&recovery_fact.message.id)
                    .await?;
                let fact = if let Some(saved) = saved {
                    Some(saved)
                } else {
                    // Terminal is observable before its execution residency is released. Wait only
                    // for this exact execution, not for a later incarnation to become idle again.
                    if source == ReviewDeliverySource::LiveTerminal
                        && let Some(thread) = owner.thread(&reviewer.id)
                    {
                        let mut updates = thread.subscribe();
                        while thread
                            .snapshot()
                            .execution
                            .as_ref()
                            .is_some_and(|execution| {
                                execution.turn_id.as_deref() == Some(turn.turn_id.as_str())
                            })
                        {
                            updates
                                .next()
                                .await
                                .context("review execution ended without cleanup observation")?;
                        }
                    }
                    let source = if revocation.load(Ordering::Acquire) >= sequence {
                        ReviewDeliverySource::Reconciliation
                    } else {
                        source
                    };
                    let forward = match conclusion.disposition {
                        ReviewDisposition::NeedsChanges => {
                            owner
                                .forward_review(ReviewFeedbackDelivery {
                                    reviewer: &reviewer.id,
                                    turn_id: &turn.turn_id,
                                    terminal_sequence: sequence,
                                    assignment: &assignment,
                                    body: &body,
                                    source,
                                    revocation: Some(&revocation),
                                })
                                .await
                        }
                        ReviewDisposition::Approved
                            if source == ReviewDeliverySource::LiveTerminal =>
                        {
                            let parent = reviewer
                                .parent_thread_id
                                .as_deref()
                                .context("reviewer has no parent")?;
                            match owner.review_baseline_current(parent, &assignment).await {
                                Ok(true) => ReviewForward::NotRequired,
                                Ok(false) => ReviewForward::Rejected {
                                    message_id: super::agent_review::review_message_id(
                                        &reviewer.id,
                                        &turn.turn_id,
                                        sequence,
                                    ),
                                    reason: ReviewForwardReason::TargetChanged,
                                },
                                Err(error) => {
                                    let message_id = super::agent_review::review_message_id(&reviewer.id, &turn.turn_id, sequence);
                                    match error.downcast::<crate::studio::thread_factory::ReviewWorkspaceError>() {
                                        Ok(error) if !error.is_unconfirmed() => ReviewForward::Rejected { message_id, reason: ReviewForwardReason::WorkspaceCheckRejected(Arc::new(error)) },
                                        Ok(error) => ReviewForward::Unconfirmed { message_id, reason: ReviewForwardReason::WorkspaceCheckRejected(Arc::new(error)) },
                                        Err(error) => ReviewForward::Unconfirmed { message_id, reason: ReviewForwardReason::AdmissionRejected(Arc::new(super::ThreadAssemblyError::Resource { operation: "verify submitted review applicability", source: error.into() })) },
                                    }
                                        },
                            }
                        }
                        ReviewDisposition::Approved | ReviewDisposition::Inconclusive => {
                            ReviewForward::NotRequired
                        }
                    };
                    match ReviewDeliveryException::from_forward(
                        &reviewer.id,
                        &turn.turn_id,
                        turn.input_id.as_deref(),
                        sequence,
                        &target_id,
                        source,
                        &forward,
                    ) {
                        Some(exception) => Some(
                            services
                                .persist_review_delivery(
                                    &owner,
                                    &reviewer.id,
                                    exception.into_fact()?,
                                )
                                .await?,
                        ),
                        None => None,
                    }
                };
                if let Some(fact) = fact {
                    let parent = reviewer
                        .parent_thread_id
                        .as_deref()
                        .context("reviewer has no parent")?;
                    // Receipt durability precedes the independent parent notification. Cold delivery
                    // uses the existing receive-only owner and never opens execution admission.
                    owner
                        .acknowledge_review_exception(
                            parent,
                            fact.message,
                            source == ReviewDeliverySource::LiveTerminal,
                        )
                        .await?;
                }
                Ok(())
            })
            .await
        })
    }

    /// Only the public synchronization boundary joins producers. The internal projection callback
    /// remains a fixed handoff wait so a producer cannot wait on itself through that callback.
    pub(crate) async fn join_review_delivery(&self, id: &str) -> Result<()> {
        self.join_root_operations(id).await
    }

    /// An explicit close retry may repair a failed producer, but never consumes its failure just
    /// to let shutdown pass. Recovery remains receipt-first/storage-only and uses the same key.
    pub(super) async fn retry_failed_review_deliveries(&self, id: &str) -> Result<()> {
        let Some(services) = self.0.state().agent_services.clone() else {
            return Ok(());
        };
        if services.operations.has_failed_producer(id) {
            let record = services.record(id).await?;
            Box::pin(self.recover_saved_review_deliveries(&record)).await?;
        }
        Ok(())
    }

    /// The existing public observation fence also settles child report producers. No additional
    /// query endpoint is needed to prove that an empty exception page has no in-flight producer.
    pub(crate) async fn settle_review_deliveries(&self, id: &str) -> Result<()> {
        let Some(services) = self.0.state().agent_services.clone() else {
            return Ok(());
        };
        let record = services.record(id).await?;
        let records = if record.parent_thread_id.is_none() {
            services
                .store
                .list_threads_for_root(id)
                .await?
                .into_iter()
                .map(pl_protocol::Thread::from)
                .collect()
        } else {
            vec![record]
        };
        for child in records {
            if child.parent_thread_id.is_none() {
                continue;
            }
            if self.observed_thread(&child.id).is_some() {
                self.synchronize_observation(&child.id).await?;
            }
            self.acknowledge_parent_reports(&services.store, &child)
                .await?;
        }
        self.join_review_delivery(id).await
    }
}
