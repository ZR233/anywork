//! Current configuration, immutable target, original authorization and canonical input ownership.

use super::worker::Cycle;
use super::{attention, scan, unavailable};
use crate::bots::BotRuntime;
use crate::bots::owner::ManagedBot;
use crate::bots::protocol::error::FeishuError;
use crate::bots::storage::publication::{
    DeliveryClaimToken, DeliveryContent, DeliveryEntityKey, DeliveryInputChain, DeliveryScope,
    DeliveryScopeKey, DeliveryScopeOrigin, DeliveryTurnIdentity, DeliveryTurnOwner,
};
use crate::bots::storage::target::{TargetKind, TargetProof};
use crate::studio::{
    InputChainBatchRead, InputChainProof, InputChainUnavailable, TimelineContentReader,
    TimelineMetadataRead,
};
use pl_protocol::studio::{BotAuthorizationPhase, BotPublicTextChannel};
use pl_protocol::{ThreadItemState, ThreadTextChannel, TimelineLifecycle};
use std::collections::{BTreeMap, BTreeSet};

#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum PublicKind {
    Text(BotPublicTextChannel),
    Artifact,
}

impl PublicKind {
    pub fn read(state: &ThreadItemState) -> Option<Self> {
        match state {
            ThreadItemState::Text(text) => match text.channel() {
                ThreadTextChannel::Commentary => Some(Self::Text(BotPublicTextChannel::Commentary)),
                ThreadTextChannel::Final => Some(Self::Text(BotPublicTextChannel::Final)),
                ThreadTextChannel::User | ThreadTextChannel::ParentAgent => None,
            },
            ThreadItemState::PublicArtifact(_) => Some(Self::Artifact),
            _ => None,
        }
    }
}

pub(super) struct CandidateIdentity {
    pub item_id: String,
    pub turn_id: String,
    pub revision: u64,
    pub order: u64,
    pub kind: PublicKind,
    pub removed: Option<scan::RemovedCandidate>,
}

pub(super) struct RemovalIdentity {
    pub key: DeliveryEntityKey,
    pub turn_id: String,
    pub revision: u64,
    pub order: u64,
}

/// Only this round's source facts, never a cached mutable authorization or a live SQL snapshot.
pub(super) struct FrontendFacts {
    pub candidates: Vec<CandidateIdentity>,
    pub removals: Vec<RemovalIdentity>,
    pub complete: bool,
    by_turn: BTreeMap<String, InputChainProof>,
}

impl FrontendFacts {
    pub fn proof(&self, turn: &str) -> Result<&InputChainProof, FeishuError> {
        self.by_turn
            .get(turn)
            .ok_or_else(|| unavailable("publication Turn was not part of this round's proof batch"))
    }
}

pub(super) async fn guard(
    runtime: &BotRuntime,
    managed: &ManagedBot,
    scope: &DeliveryScope,
    token: &DeliveryClaimToken,
) -> Result<(), FeishuError> {
    runtime.reject_closed_admission(managed)?;
    let target = match &scope.origin {
        DeliveryScopeOrigin::Frontend { authorization } => {
            let audience = managed
                .store
                .audience_scope(&scope.thread_id, &scope.bot_id)
                .await?
                .ok_or_else(|| attention("publication creation origin is unproven"))?;
            if audience.origin.requires_upgrade
                || audience.origin.thread_id != scope.thread_id
                || audience.origin.chat_id != scope.chat_id
                || audience.origin.project_id != scope.project_id
                || audience.origin.creation_id != scope.creation_id
                || audience.origin.binding_revision != scope.binding_revision
                || audience.head.as_ref().is_none_or(|head| {
                    head.intent.authorization != *authorization
                        || head.revision != token.authorization_revision
                        || head.phase != BotAuthorizationPhase::Active
                })
            {
                return Err(unavailable(
                    "publication authorization is no longer active at its original binding",
                ));
            }
            if let TargetProof::Created { evidence } = &audience.origin.target
                && (evidence.bot_id != scope.bot_id || evidence.app_id != scope.app_id)
            {
                return Err(attention(
                    "publication target belongs to another application",
                ));
            }
            audience.origin.target.kind().cloned()
        }
        DeliveryScopeOrigin::LegacyFinal { legacy } => {
            if !legacy.resumable || legacy.needs_recovery.is_some() {
                return Err(attention(
                    "finite legacy publication requires local recovery",
                ));
            }
            let source = legacy
                .source
                .as_ref()
                .ok_or_else(|| attention("legacy source is unproven"))?;
            let config = managed.config.lock().await;
            crate::bots::source::authorize_source_identity(&config, &scope.chat_id, source)?;
            legacy.target.kind().cloned()
        }
    }
    .ok_or_else(|| attention("publication target kind is unproven"))?;
    let config = managed.config.lock().await;
    if !config.enabled
        || config.id != scope.bot_id
        || config.project_id != scope.project_id
        || config.feishu().app_id != scope.app_id
        || scope.needs_recovery
        || token.scope != scope.key
    {
        return Err(unavailable(
            "publication configuration is disabled or changed",
        ));
    }
    let trusted = match target {
        TargetKind::Group => config.feishu().trusted_chat_ids.contains(&scope.chat_id),
        TargetKind::Direct { open_id } => config.feishu().trusted_open_ids.contains(&open_id),
    };
    if !trusted {
        return Err(unavailable("publication original target trust was revoked"));
    }
    drop(config);
    let binding = managed
        .store
        .binding_for_chat(&scope.chat_id, &scope.bot_id, &scope.project_id)
        .await?;
    if binding.status != "bound"
        || binding.thread_id.as_deref() != Some(&scope.thread_id)
        || binding.creation_id != scope.creation_id
        || binding.revision != scope.binding_revision
    {
        return Err(unavailable(
            "publication original binding was replaced or is unavailable",
        ));
    }
    Ok(())
}

/// Returns None only for an explicitly excluded/legacy-owned Turn, not for missing proof.
pub(super) async fn frontend_chain(
    managed: &ManagedBot,
    scope: &DeliveryScope,
    turn: &str,
    proof: &InputChainProof,
) -> Result<Option<DeliveryInputChain>, FeishuError> {
    let (chain, start_sequence) = match proof {
        InputChainProof::Proven(proof) if proof.turn_id == turn && proof.start_sequence > 0 => (
            DeliveryInputChain::Proven {
                input_id: proof.input_id.clone(),
                continuation_ancestors: proof.continuation_ancestors.clone(),
            },
            Some(proof.start_sequence),
        ),
        InputChainProof::Proven(_) => {
            return Err(attention("publication input chain Turn mismatch"));
        }
        InputChainProof::Unavailable(InputChainUnavailable::BudgetExhausted) => {
            return Err(attention(
                "publication input-chain proof budget exhausted; local recovery required",
            ));
        }
        InputChainProof::Unavailable(_) => (DeliveryInputChain::Unavailable, None),
    };
    let identity = DeliveryTurnIdentity {
        thread_id: scope.thread_id.clone(),
        turn_id: turn.to_owned(),
        input_chain: chain,
    };
    match managed.store.delivery_turn_owner(&identity).await? {
        DeliveryTurnOwner::LegacyFinal { .. } => return Ok(None),
        DeliveryTurnOwner::Unproven => {
            return Err(unavailable(
                "publication input-chain ownership is not yet provable",
            ));
        }
        DeliveryTurnOwner::Frontend => {}
    }
    let DeliveryScopeKey::Frontend {
        authorization: authorization_id,
    } = &scope.key
    else {
        return Err(attention("canonical publication requires a frontend scope"));
    };
    let authorization = managed
        .store
        .audience_authorization(authorization_id)
        .await?
        .ok_or_else(|| unavailable("publication original authorization is missing"))?;
    let cut = authorization
        .start
        .ok_or_else(|| unavailable("publication Saved cut is not ready"))?;
    let start_sequence = start_sequence
        .ok_or_else(|| unavailable("publication Turn start is not proven by this snapshot"))?;
    if authorization.intent.authorization != *authorization_id
        || authorization.intent.thread_id != scope.thread_id
        || cut.intent != authorization.intent
    {
        return Err(attention(
            "publication Turn start or original cut is inconsistent",
        ));
    }
    Ok(
        (start_sequence > cut.sequence && cut.excluded_turn_id.as_deref() != Some(turn))
            .then_some(identity.input_chain),
    )
}

pub(super) async fn prepare_facts(
    cycle: &Cycle<'_>,
    reader: &TimelineContentReader,
    coverage: &scan::Coverage,
    removals: &BTreeSet<String>,
    budget: &mut scan::RecoveryBudget,
) -> Result<Option<FrontendFacts>, FeishuError> {
    let mut candidates = Vec::new();
    let mut removal_targets = Vec::new();
    let mut turns = BTreeSet::new();
    let mut complete = true;
    for id in removals {
        cycle.active()?;
        budget.inspect(1)?;
        let Some(key) = coverage.entity_keys.get(id) else {
            continue;
        };
        let entity = cycle
            .managed
            .store
            .delivery_entity(&cycle.scope.key, key)
            .await?
            .ok_or_else(|| unavailable("removed entity changed during proof preparation"))?;
        if entity.removed && matches!(&entity.state.content, DeliveryContent::Removed { .. }) {
            continue;
        }
        let turn = entity
            .turn_id
            .as_deref()
            .ok_or_else(|| attention("removed public item lacks its original Turn"))?;
        let order = entity
            .item_order
            .ok_or_else(|| attention("removed public item lacks its original order"))?;
        retain_record(budget, 192, &[key.item_id(), key.publication_id(), turn])?;
        remember_turn(&mut turns, turn, budget)?;
        removal_targets.push(RemovalIdentity {
            key: key.clone(),
            turn_id: turn.to_owned(),
            revision: entity.revision(),
            order,
        });
    }
    for (_, id) in &coverage.items {
        cycle.active()?;
        if removals.contains(id) {
            continue;
        }
        budget.inspect(1)?;
        let mut reads = reader
            .read_metadata(std::slice::from_ref(id))
            .await
            .map_err(|e| super::content_error("collect publication candidate metadata", e))?;
        if reads.len() != 1 {
            return Err(attention(
                "publication candidate metadata batch is incomplete",
            ));
        }
        let removed = coverage.removed_candidates.get(id);
        let metadata = match reads
            .pop()
            .ok_or_else(|| attention("publication candidate metadata is absent"))?
        {
            TimelineMetadataRead::Present(metadata) => metadata,
            TimelineMetadataRead::Missing { item_id } if item_id == *id => {
                let terminal = if let Some(removed) = removed {
                    scan::removal_covers_revision(
                        cycle,
                        &removed.key,
                        removed.observed_revision,
                        budget,
                    )
                    .await?
                } else {
                    false
                };
                complete &= terminal;
                continue;
            }
            _ => {
                return Err(attention(
                    "publication candidate metadata identity mismatch",
                ));
            }
        };
        let shell = &metadata.shell;
        if shell.thread_id != cycle.scope.thread_id || shell.id != *id {
            return Err(attention(
                "publication candidate belongs to another identity",
            ));
        }
        if let Some(removed) = removed {
            let required = removed.observed_revision.max(shell.revision);
            if scan::removal_covers_revision(cycle, &removed.key, required, budget).await? {
                continue;
            }
            if shell.revision < removed.observed_revision {
                complete = false;
                continue;
            }
        }
        let Some(kind) = PublicKind::read(shell.state()) else {
            continue;
        };
        if kind == PublicKind::Artifact
            && (!metadata.saved || metadata.lifecycle != TimelineLifecycle::Terminal)
        {
            complete = false;
            continue;
        }
        if shell.turn_id.is_empty() || shell.revision == 0 || shell.ordinal == 0 {
            return Err(attention(
                "public candidate lacks its canonical Turn/order/revision",
            ));
        }
        let (removed_id, publication) = removed.map_or(("", ""), |known| {
            (known.key.item_id(), known.key.publication_id())
        });
        retain_record(budget, 384, &[id, &shell.turn_id, removed_id, publication])?;
        remember_turn(&mut turns, &shell.turn_id, budget)?;
        candidates.push(CandidateIdentity {
            item_id: id.clone(),
            turn_id: shell.turn_id.clone(),
            revision: shell.revision,
            order: shell.ordinal,
            kind,
            removed: removed.map(|known| scan::RemovedCandidate {
                key: known.key.clone(),
                observed_revision: known.observed_revision,
            }),
        });
        // No complete shell, detail or entity body is retained across the proof/HTTP phases.
    }
    let Some(by_turn) = read_proofs(cycle, turns, budget).await? else {
        return Ok(None);
    };
    Ok(Some(FrontendFacts {
        candidates,
        removals: removal_targets,
        complete,
        by_turn,
    }))
}

async fn read_proofs(
    cycle: &Cycle<'_>,
    turns: BTreeSet<String>,
    budget: &mut scan::RecoveryBudget,
) -> Result<Option<BTreeMap<String, InputChainProof>>, FeishuError> {
    if turns.is_empty() {
        // No public candidate means no H call and no synthetic proof.
        return Ok(Some(BTreeMap::new()));
    }
    cycle.active()?;
    let turn_ids: Vec<String> = turns.into_iter().collect();
    let limits = budget.proof_limits()?;
    let read = cycle
        .host
        .bot_turn_input_chains(&cycle.scope.thread_id, &turn_ids, limits)
        .await
        .map_err(|e| FeishuError::history_read("read bounded publication causal proof batch", e))?;
    match read {
        InputChainBatchRead::Unavailable(InputChainUnavailable::BudgetExhausted) => Err(attention(
            "publication causal batch exceeded this round's budget",
        )),
        InputChainBatchRead::Unavailable(_) => {
            cycle
                .diagnostic(unavailable("publication causal batch is not yet provable"))
                .await;
            Ok(None)
        }
        InputChainBatchRead::Ready(batch) => {
            budget.accept_proof_usage(batch.rows_read, batch.bytes_read)?;
            if batch.by_turn.len() != turn_ids.len()
                || batch
                    .by_turn
                    .keys()
                    .any(|turn| turn_ids.binary_search(turn).is_err())
            {
                return Err(attention(
                    "publication causal batch does not cover its requested Turns",
                ));
            }
            // Validate the whole batch and charge every retained identity before any write.
            // In particular, a budget failure cannot expose a successful prefix to callers.
            for (turn, proof) in &batch.by_turn {
                retain_record(budget, 256, &[turn])?;
                match proof {
                    InputChainProof::Proven(proof) => {
                        if proof.turn_id != *turn || proof.start_sequence == 0 {
                            return Err(attention("publication causal batch Turn/start mismatch"));
                        }
                        // The table survives while one converted candidate and S's fenced owner
                        // check own temporary chain copies. Reserve those copies here as well.
                        retain_record(
                            budget,
                            256,
                            &[
                                &proof.turn_id,
                                &proof.input_id,
                                &proof.input_id,
                                &proof.input_id,
                            ],
                        )?;
                        for ancestor in &proof.continuation_ancestors {
                            retain_record(budget, 144, &[ancestor, ancestor, ancestor])?;
                        }
                    }
                    InputChainProof::Unavailable(InputChainUnavailable::BudgetExhausted) => {
                        return Err(attention(
                            "publication causal batch returned a budget-limited prefix",
                        ));
                    }
                    InputChainProof::Unavailable(_) => {}
                }
            }
            Ok(Some(batch.by_turn))
        }
    }
}

fn remember_turn(
    turns: &mut BTreeSet<String>,
    turn: &str,
    budget: &mut scan::RecoveryBudget,
) -> Result<(), FeishuError> {
    if turn.is_empty() {
        return Err(attention("public Turn identity is empty"));
    }
    if !turns.contains(turn) {
        retain_record(budget, 128, &[turn])?;
        turns.insert(turn.to_owned());
    }
    Ok(())
}

fn retain_record(
    budget: &mut scan::RecoveryBudget,
    base: usize,
    ids: &[&str],
) -> Result<(), FeishuError> {
    let bytes = ids.iter().try_fold(base, |size, id| {
        size.checked_add(id.len())
            .ok_or_else(|| attention("publication candidate identity byte count overflow"))
    })?;
    budget.retain_identity(bytes)
}
