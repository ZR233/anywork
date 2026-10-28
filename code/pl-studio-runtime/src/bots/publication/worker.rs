//! A bounded observation cycle. Heartbeats run alongside *all* awaited work without dropping it.

use super::{attention, cards, eligibility, legacy, projection, scan, unavailable};
use crate::bots::owner::ManagedBot;
use crate::bots::protocol::error::{FeishuError, FeishuErrorKind};
use crate::bots::storage::PublicationFilePermit;
use crate::bots::storage::card::CardLifecycle;
use crate::bots::storage::publication::{
    DELIVERY_CLAIM_RENEW_SECONDS, DeliveryCandidate, DeliveryCandidateContent,
    DeliveryClaimOutcome, DeliveryClaimToken, DeliveryContent, DeliveryEntity, DeliveryEntityKey,
    DeliveryScope, DeliveryScopeKey, MergeOutcome, SavedArtifact, delivery_file_request_hash,
    file_block_reason,
};
use crate::bots::{BotRuntime, BotTurnRead};
use crate::studio::{
    StudioRuntime, TimelineContentReader, TimelineMetadataRead, TimelineTailStream,
};
use pl_protocol::studio::{BotItemPlatform, BotItemPresentation, BotPlatformResult};
use pl_protocol::{
    TimelineChange, TimelineLifecycle, TimelineTailUpdate, TurnCompletion, TurnState,
};
use std::collections::BTreeSet;
use std::sync::Arc;
use std::sync::atomic::Ordering;
use std::time::Duration;
use tokio::time::Instant;
use tokio_util::sync::CancellationToken;

pub(super) struct Cycle<'a> {
    pub runtime: &'a BotRuntime,
    pub managed: &'a ManagedBot,
    pub host: &'a StudioRuntime,
    pub scope: &'a DeliveryScope,
    pub token: &'a DeliveryClaimToken,
    pub cancel: &'a CancellationToken,
    pub deadline: Instant,
}

impl Cycle<'_> {
    pub fn active(&self) -> Result<(), FeishuError> {
        if self.cancel.is_cancelled()
            || Instant::now() >= self.deadline
            || self.runtime.inner.sealed.load(Ordering::Acquire) != 0
        {
            return Err(FeishuError::cancelled());
        }
        Ok(())
    }

    pub async fn renew(&self) -> Result<(), FeishuError> {
        match self.managed.store.renew_delivery_claim(self.token).await? {
            DeliveryClaimOutcome::Acquired(_) => Ok(()),
            _ => {
                self.cancel.cancel();
                Err(FeishuError::cancelled())
            }
        }
    }

    pub async fn diagnostic(&self, error: FeishuError) {
        *self.managed.diagnostic.lock().await = Some(error.diagnostic());
        self.runtime.request_publish();
    }

    pub fn changed(&self) {
        self.managed.audience_changed();
        self.runtime.request_publish();
    }
}

pub(super) async fn run(
    runtime: BotRuntime,
    managed: Arc<ManagedBot>,
    scope: DeliveryScope,
    cancel: CancellationToken,
) -> Result<(), FeishuError> {
    let Some(host) = runtime.studio_host() else {
        return Err(unavailable("publication Studio host is unavailable"));
    };
    let owner_id = crate::studio::new_id("bot-publication");
    let token = match managed
        .store
        .claim_delivery_scope(&scope.key, &owner_id)
        .await?
    {
        DeliveryClaimOutcome::Acquired(token) => token,
        DeliveryClaimOutcome::Busy { .. }
        | DeliveryClaimOutcome::Stopped { .. }
        | DeliveryClaimOutcome::Missing
        | DeliveryClaimOutcome::LostClaim => return Ok(()),
    };
    let finished = CancellationToken::new();
    let cycle = Cycle {
        runtime: &runtime,
        managed: &managed,
        host: &host,
        scope: &scope,
        token: &token,
        cancel: &cancel,
        deadline: Instant::now() + Duration::from_secs(60),
    };
    let work = async {
        let result = observe(&cycle).await;
        finished.cancel();
        result
    };
    let heartbeat = async {
        let mut stopped_new_work = false;
        loop {
            tokio::select! {
                _ = finished.cancelled() => return,
                _ = tokio::time::sleep_until(cycle.deadline), if !stopped_new_work => {
                    cancel.cancel();
                    stopped_new_work = true;
                    continue;
                }
                _ = tokio::time::sleep(Duration::from_secs(DELIVERY_CLAIM_RENEW_SECONDS as u64)) => {}
            }
            // Renewal continues during source/rate/HTTP/local-result saves, including shutdown.
            // Failure cancels new actions, never selects away or drops the work future.
            if !matches!(
                managed.store.renew_delivery_claim(&token).await,
                Ok(DeliveryClaimOutcome::Acquired(_))
            ) {
                cancel.cancel();
            }
        }
    };
    let (mut result, ()) = tokio::join!(work, heartbeat);
    if let Some(error) = result.as_ref().err().cloned()
        && error.kind() != FeishuErrorKind::Cancelled
    {
        if !error.retryable() {
            match managed.store.renew_delivery_claim(&token).await {
                Ok(DeliveryClaimOutcome::Acquired(_)) => {
                    managed
                        .store
                        .stop_delivery_scope(&scope.key, &error.diagnostic().message)
                        .await?;
                    cycle.changed();
                }
                Ok(_) => {
                    // Fenced local CAS/Intent can mean Pause or a successor control revision.
                    // Neither is proof of permanent closure. Stop only this old cycle, never
                    // convert a temporarily unclaimable scope into a persistent stop.
                    cancel.cancel();
                    result = Err(FeishuError::cancelled());
                }
                Err(_) => {
                    // Without a provable current claim this owner cannot write a durable stop.
                    // Keep the original error and recovery obligation visible instead.
                }
            }
        }
        if !result
            .as_ref()
            .is_err_and(|error| error.kind() == FeishuErrorKind::Cancelled)
        {
            cycle.diagnostic(error).await;
        }
    }
    managed.store.release_delivery_claim(&token).await?;
    match result {
        Err(error) if error.kind() == FeishuErrorKind::Cancelled => Ok(()),
        result => result,
    }
}

/// Only authoritative notifications owned by this live observation, not a durable deletion queue.
struct ObservedRemovals {
    items: BTreeSet<String>,
    bytes: usize,
}

impl ObservedRemovals {
    fn new() -> Self {
        Self {
            items: BTreeSet::new(),
            bytes: 0,
        }
    }

    fn apply(&mut self, changes: Vec<TimelineChange>) -> Result<(), FeishuError> {
        for change in changes {
            match change {
                TimelineChange::Remove { item_id } if !self.items.contains(&item_id) => {
                    let bytes = self
                        .bytes
                        .checked_add(128)
                        .and_then(|bytes| bytes.checked_add(item_id.len()))
                        .filter(|bytes| *bytes <= super::tasks::IDENTITY_BYTES)
                        .ok_or_else(|| {
                            attention("publication removal identity budget exhausted")
                        })?;
                    if self.items.len() >= scan::MAX_ITEMS {
                        return Err(attention("publication removal count budget exhausted"));
                    }
                    self.items.insert(item_id);
                    self.bytes = bytes;
                }
                TimelineChange::Add { item } => self.supersede(&item.preview.id)?,
                TimelineChange::UpdateItem { item_id, .. } => self.supersede(&item_id)?,
                TimelineChange::Remove { .. } => {}
            }
        }
        Ok(())
    }

    fn supersede(&mut self, id: &str) -> Result<(), FeishuError> {
        if let Some(id) = self.items.take(id) {
            self.bytes = self
                .bytes
                .checked_sub(128)
                .and_then(|bytes| bytes.checked_sub(id.len()))
                .ok_or_else(|| attention("publication removal identity accounting mismatch"))?;
        }
        Ok(())
    }

    fn clear(&mut self) {
        self.items.clear();
        self.bytes = 0;
    }
}

async fn observe(cycle: &Cycle<'_>) -> Result<(), FeishuError> {
    cycle.active()?;
    eligibility::guard(cycle.runtime, cycle.managed, cycle.scope, cycle.token).await?;
    let reader = cycle
        .host
        .timeline_reader(&cycle.scope.thread_id)
        .await
        .map_err(|e| super::content_error("open publication content reader", e))?;
    let mut tail = reader
        .open_tail()
        .await
        .map_err(|e| super::content_error("open publication tail", e))?;
    // Required before next(): the initial page is a bounded baseline, NOT a forward/full log.
    drop(
        tail.initial()
            .map_err(|e| super::content_error("read publication tail baseline", e))?,
    );
    let mut removals = ObservedRemovals::new();
    let result = observe_until_yield(cycle, &reader, tail, &mut removals).await;
    if !removals.items.is_empty()
        && (result.is_ok()
            || result
                .as_ref()
                .is_err_and(|error| error.kind() == FeishuErrorKind::Cancelled))
    {
        return Err(unavailable(
            "authoritative removals remain unpersisted at observation end; original ledger requires recovery",
        ));
    }
    result
}

async fn observe_until_yield(
    cycle: &Cycle<'_>,
    reader: &TimelineContentReader,
    mut tail: TimelineTailStream,
    removals: &mut ObservedRemovals,
) -> Result<(), FeishuError> {
    let mut last_work = Instant::now();
    loop {
        cycle.active()?;
        // The received tail batch and its recovery/interaction reads form one round. Deletions
        // are settled before that round can save a watermark; they never get a per-item budget.
        let mut budget = scan::RecoveryBudget::new();
        budget.retain_identity(removals.bytes)?;
        let changed = match &cycle.scope.key {
            DeliveryScopeKey::Frontend { .. } => {
                frontend_pass(cycle, reader, &mut budget, removals).await?
            }
            DeliveryScopeKey::LegacyFinal { .. } => {
                legacy::advance(cycle, reader, &mut budget).await?
            }
        };
        if changed {
            last_work = Instant::now();
        }
        tokio::select! {
            _ = cycle.cancel.cancelled() => return Ok(()),
            _ = tokio::time::sleep_until(cycle.deadline) => return Ok(()),
            _ = tokio::time::sleep_until(last_work + Duration::from_secs(15)) => return Ok(()),
            _ = tokio::time::sleep(Duration::from_secs(1)), if !removals.items.is_empty() => {}
            update = tail.next() => {
                match update.map_err(|e| super::content_error("observe publication content tail", e))? {
                    Some(TimelineTailUpdate::Patch { changes, .. }) => {
                        // Removal is authoritative only here, never inferred from Missing/eviction.
                        if cycle.scope.key.is_frontend() {
                            removals.apply(changes)?;
                        }
                    }
                    Some(TimelineTailUpdate::Resync { .. }) => {}
                    None => return Ok(()),
                }
                // Coalesce current canonical revisions; do not replay patch body fragments.
                tokio::select! {
                    _ = cycle.cancel.cancelled() => return Ok(()),
                    _ = tokio::time::sleep(Duration::from_millis(200)) => {}
                }
            }
        }
    }
}

async fn frontend_pass(
    cycle: &Cycle<'_>,
    reader: &TimelineContentReader,
    budget: &mut scan::RecoveryBudget,
    removals: &mut ObservedRemovals,
) -> Result<bool, FeishuError> {
    let coverage = scan::recover(cycle, reader, budget, &removals.items).await?;
    let Some(facts) =
        eligibility::prepare_facts(cycle, reader, &coverage, &removals.items, budget).await?
    else {
        return Ok(false);
    };
    let mut complete = facts.complete;
    let mut removals_complete = true;
    let mut changed = false;
    for target in &facts.removals {
        cycle.active()?;
        match removed(cycle, target, &facts, budget).await {
            Ok(Some(work)) => changed |= work,
            Ok(None) => removals_complete = false,
            Err(error) if error.retryable() => {
                removals_complete = false;
                cycle.diagnostic(error).await;
            }
            Err(error) => return Err(error),
        }
    }
    if removals_complete {
        removals.clear();
    }
    complete &= removals_complete;
    for item in &facts.candidates {
        cycle.active()?;
        match process(cycle, reader, item, &facts, budget).await {
            Ok(Some(work)) => changed |= work,
            Ok(None) => complete = false,
            Err(error) if error.retryable() => {
                complete = false;
                cycle.diagnostic(error).await;
            }
            Err(error) => return Err(error),
        }
    }
    if complete {
        cycle
            .managed
            .store
            .save_delivery_watermark(cycle.token, coverage.watermark)
            .await?;
    }
    Ok(changed)
}

async fn process(
    cycle: &Cycle<'_>,
    reader: &TimelineContentReader,
    item: &eligibility::CandidateIdentity,
    facts: &eligibility::FrontendFacts,
    budget: &mut scan::RecoveryBudget,
) -> Result<Option<bool>, FeishuError> {
    budget.inspect(1)?;
    let mut reads = reader
        .read_metadata(std::slice::from_ref(&item.item_id))
        .await
        .map_err(|e| super::content_error("read publication item metadata", e))?;
    if reads.len() != 1 {
        return Err(attention("publication metadata batch is incomplete"));
    }
    let metadata = match reads.pop() {
        Some(TimelineMetadataRead::Present(metadata)) => metadata,
        Some(TimelineMetadataRead::Missing { item_id }) if item_id == item.item_id => {
            // A source gap alone is still incomplete. Only a fresh durable removal covering
            // the highest revision already observed by this round can close this candidate.
            return match &item.removed {
                Some(removed) => Ok(scan::removal_covers_revision(
                    cycle,
                    &removed.key,
                    removed.observed_revision.max(item.revision),
                    budget,
                )
                .await?
                .then_some(false)),
                None => Ok(None),
            };
        }
        _ => return Err(attention("publication metadata identity mismatch")),
    };
    let shell = &metadata.shell;
    if shell.id != item.item_id
        || shell.thread_id != cycle.scope.thread_id
        || shell.turn_id != item.turn_id
        || shell.revision != item.revision
        || shell.ordinal != item.order
        || eligibility::PublicKind::read(shell.state()) != Some(item.kind)
    {
        // A later Turn/revision has no proof in this prepared item set. Do not issue another
        // batch request or apply the old fact to it; a later observation round must recollect it.
        return Ok(None);
    }
    if let Some(removed) = &item.removed {
        let required = removed.observed_revision.max(shell.revision);
        if scan::removal_covers_revision(cycle, &removed.key, required, budget).await? {
            return Ok(Some(false));
        }
        if shell.revision < removed.observed_revision {
            return Ok(None);
        }
    }
    let Some(chain) = eligibility::frontend_chain(
        cycle.managed,
        cycle.scope,
        &shell.turn_id,
        facts.proof(&shell.turn_id)?,
    )
    .await?
    else {
        return Ok(Some(false));
    };
    let (key, content, lifecycle) = if let eligibility::PublicKind::Text(channel) = item.kind {
        let mut text = projection::text_from_projection(
            projection::read(reader, &metadata).await?,
            channel,
            shell.revision,
            metadata.saved,
        );
        let key = DeliveryEntityKey::TextItem {
            item_id: item.item_id.clone(),
        };
        let lifecycle = goal(cycle, reader, &shell.turn_id, budget).await?;
        if text.body.trim().is_empty()
            && projection::host_region(text.integrity, lifecycle).is_empty()
            && cycle
                .managed
                .store
                .delivery_entity(&cycle.scope.key, &key)
                .await?
                .is_none()
        {
            // A genuine empty item with no safe status has no platform presentation obligation.
            // Do not manufacture an answer/card or a permanently pending empty ledger entity.
            return Ok(Some(false));
        }
        if text.body.is_empty() {
            projection::reserve_host_request(&mut text)?;
        }
        (
            key,
            DeliveryCandidateContent::Text {
                channel,
                revision: text.revision,
                integrity: text.integrity,
                saved: text.saved,
                body: text.body,
                request_bytes: text.request_bytes,
            },
            Some(lifecycle),
        )
    } else {
        if !metadata.saved || metadata.lifecycle != TimelineLifecycle::Terminal {
            return Ok(None);
        }
        let artifact = SavedArtifact::from_metadata(&metadata)?;
        (
            artifact.entity_key(),
            DeliveryCandidateContent::File { artifact },
            None,
        )
    };
    let candidate = DeliveryCandidate {
        entity: key.clone(),
        turn_id: shell.turn_id.clone(),
        item_order: shell.ordinal,
        input_chain: chain,
        content,
    };
    match cycle
        .managed
        .store
        .merge_delivery_candidate(cycle.token, &candidate)
        .await?
    {
        MergeOutcome::Applied { .. } => cycle.changed(),
        MergeOutcome::Unchanged { .. } => {}
        MergeOutcome::Stale { .. } => {
            return Ok(
                scan::removal_covers_revision(cycle, &key, shell.revision, budget)
                    .await?
                    .then_some(false),
            );
        }
        MergeOutcome::Conflict => {
            return Err(attention(
                "canonical publication revision conflicts with the original ledger",
            ));
        }
        MergeOutcome::Fenced => return Err(FeishuError::cancelled()),
        MergeOutcome::NotCanonical => return Ok(Some(false)),
    }
    let entity = cycle
        .managed
        .store
        .delivery_entity(&cycle.scope.key, &key)
        .await?
        .ok_or_else(|| attention("merged publication entity is missing"))?;
    match &entity.state.content {
        DeliveryContent::Text { text } => {
            let goal =
                lifecycle.ok_or_else(|| attention("public text lacks its canonical safe state"))?;
            cards::drive(
                cycle,
                &key,
                text,
                goal,
                metadata.lifecycle == TimelineLifecycle::Terminal,
            )
            .await
            .map(Some)
        }
        DeliveryContent::File { file }
            if file_block_reason(file).is_none() && entity.state.halt.is_none() =>
        {
            if matches!(entity.state.accepted, pl_protocol::studio::BotItemPresentation::File { revision } if revision == file.artifact.revision())
            {
                return Ok(Some(false));
            }
            let Some(operation) = artifact_operation(cycle, &entity, &file.artifact).await? else {
                // A replacement cannot change the identity of an unfinished original send.
                return Ok(Some(false));
            };
            let result = cycle
                .runtime
                .send_public_artifact(
                    operation.clone(),
                    cycle.scope.clone(),
                    PublicationFilePermit {
                        token: cycle.token.clone(),
                        entity: key.clone(),
                        expected_ledger_version: entity.ledger_version,
                        artifact: file.artifact.clone(),
                    },
                    cycle.cancel.clone(),
                )
                .await;
            match result {
                Ok(result) if result.receipt.durable => {
                    cycle.changed();
                    Ok(Some(true))
                }
                Ok(_) => Err(unavailable(
                    "public artifact owner has not confirmed durable settlement",
                )),
                Err(error) => {
                    // F has its own occupancy-owned result retention. O does not read/archive the
                    // resource again or treat a non-durable observed receipt as completion.
                    cycle.diagnostic(error).await;
                    Ok(Some(false))
                }
            }
        }
        _ => Ok(Some(false)),
    }
}

async fn artifact_operation(
    cycle: &Cycle<'_>,
    entity: &DeliveryEntity,
    artifact: &SavedArtifact,
) -> Result<Option<String>, FeishuError> {
    if let Some(binding) = &entity.state.file_operation {
        if binding.artifact == *artifact {
            return Ok(Some(binding.operation_id.clone()));
        }
        if binding.artifact.revision() >= artifact.revision() {
            return Err(attention(
                "replacement public artifact does not advance its original bound revision",
            ));
        }
        let accepted = BotItemPresentation::File {
            revision: binding.artifact.revision(),
        };
        if entity.state.halt.is_some() || entity.state.accepted != accepted {
            return Ok(None);
        }
        let DeliveryScopeKey::Frontend { authorization } = &cycle.scope.key else {
            return Err(attention(
                "public artifact requires its original frontend scope",
            ));
        };
        // This existing storage read derives the exact message stage from the original send
        // ledger. It is not a permission: F/S recheck the binding and CAS in their transaction.
        let observed = cycle
            .managed
            .store
            .delivery_observation(authorization, entity.entity.item_id())
            .await?
            .ok_or_else(|| {
                unavailable("original artifact delivery stage is temporarily missing")
            })?;
        if observed.thread_id != cycle.scope.thread_id
            || observed.item_id != entity.entity.item_id()
            || observed.authorization != *authorization
            || observed.removed
            || observed.ledger.observed_revision != artifact.revision()
            || observed.ledger.accepted != accepted
        {
            return Err(unavailable(
                "artifact binding changed before replacement preparation",
            ));
        }
        if !matches!(
            observed.ledger.platform,
            BotItemPlatform::File {
                operation_id,
                content_revision,
                message: BotPlatformResult::Accepted {},
                ..
            } if operation_id == binding.operation_id
                && content_revision == binding.artifact.revision()
        ) {
            return Ok(None);
        }
    }
    // The existing typed hash includes the whole SavedArtifact (revision, producer, resource,
    // digest and display name) plus the full scope/entity identity, not only the resource bytes.
    let hash = delivery_file_request_hash(cycle.scope, &entity.entity, artifact)?;
    Ok(Some(format!("bot-publication-file:{hash}")))
}

pub(super) async fn goal(
    cycle: &Cycle<'_>,
    reader: &TimelineContentReader,
    turn: &str,
    budget: &mut scan::RecoveryBudget,
) -> Result<CardLifecycle, FeishuError> {
    budget.inspect(1)?;
    let state = cycle
        .host
        .bot_turn_fact(&cycle.scope.thread_id, turn)
        .await
        .map_err(|e| FeishuError::history_read("read publication Turn state", e))?;
    let result = match state {
        BotTurnRead::Absent => return Err(unavailable("publication Turn state is not saved yet")),
        BotTurnRead::Ready(TurnState::Completed(state))
            if state.completion() == TurnCompletion::InteractionRequested =>
        {
            CardLifecycle::Paused
        }
        BotTurnRead::Ready(TurnState::Completed(_)) => CardLifecycle::Completed,
        BotTurnRead::Ready(TurnState::Cancelled(_)) => CardLifecycle::Cancelled,
        BotTurnRead::Ready(TurnState::Failed(_)) => CardLifecycle::Failed,
        BotTurnRead::Ready(TurnState::BudgetLimited(_)) => CardLifecycle::BudgetLimited,
        BotTurnRead::Ready(TurnState::Queued(_) | TurnState::Running(_)) => {
            CardLifecycle::Streaming
        }
    };
    if result == CardLifecycle::Paused && cycle.scope.key.is_frontend() {
        return match legacy::continuation(cycle, reader, turn, budget).await? {
            legacy::Continuation::Next(_) | legacy::Continuation::Ended => {
                Ok(CardLifecycle::InteractionEnded)
            }
            legacy::Continuation::Waiting => Ok(CardLifecycle::Paused),
        };
    }
    if result == CardLifecycle::Streaming {
        let snapshot = cycle
            .host
            .thread_snapshot(&cycle.scope.thread_id)
            .await
            .map_err(|e| FeishuError::history_read("read publication safe interaction state", e))?;
        for interaction in snapshot
            .interactions
            .iter()
            .filter(|i| i.scope.turn_id == turn)
        {
            if interaction.status() == pl_protocol::InteractionStatus::Pending {
                return Ok(CardLifecycle::Paused);
            }
        }
    }
    Ok(result)
}

async fn removed(
    cycle: &Cycle<'_>,
    target: &eligibility::RemovalIdentity,
    facts: &eligibility::FrontendFacts,
    budget: &mut scan::RecoveryBudget,
) -> Result<Option<bool>, FeishuError> {
    cycle.active()?;
    // Even an exact lookup consumes this round's shared budget, before any store read.
    budget.inspect(1)?;
    let entity = cycle
        .managed
        .store
        .delivery_entity(&cycle.scope.key, &target.key)
        .await?
        .ok_or_else(|| unavailable("removed public entity changed after recovery coverage"))?;
    if entity.removed && matches!(&entity.state.content, DeliveryContent::Removed { .. }) {
        return Ok(Some(false));
    }
    if entity.turn_id.as_deref() != Some(target.turn_id.as_str())
        || entity.item_order != Some(target.order)
        || entity.revision() != target.revision
    {
        return Ok(None);
    }
    let Some(chain) = eligibility::frontend_chain(
        cycle.managed,
        cycle.scope,
        &target.turn_id,
        facts.proof(&target.turn_id)?,
    )
    .await?
    else {
        return Ok(Some(false));
    };
    let revision = entity
        .revision()
        .checked_add(1)
        .filter(|revision| *revision <= i64::MAX as u64)
        .ok_or_else(|| attention("authoritative removal revision exceeds the ledger range"))?;
    match cycle
        .managed
        .store
        .merge_delivery_candidate(
            cycle.token,
            &DeliveryCandidate {
                entity: target.key.clone(),
                turn_id: target.turn_id.clone(),
                item_order: target.order,
                input_chain: chain,
                content: DeliveryCandidateContent::Removed { revision },
            },
        )
        .await?
    {
        MergeOutcome::Applied { .. } => {
            cycle.changed();
            Ok(Some(true))
        }
        MergeOutcome::Unchanged { .. } => Ok(Some(false)),
        MergeOutcome::Stale { .. } => {
            Ok(
                scan::removal_covers_revision(cycle, &target.key, revision, budget)
                    .await?
                    .then_some(false),
            )
        }
        MergeOutcome::Fenced => Err(FeishuError::cancelled()),
        _ => Err(attention(
            "authoritative removal conflicts with its original delivery entity",
        )),
    }
}
