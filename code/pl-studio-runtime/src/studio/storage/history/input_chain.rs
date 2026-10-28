//! One read-only observation batch of Turn inputs and canonical continuation ancestors.
//!
//! A continuation input is the input a resolved interaction produces; the parent edge exists only
//! in the committed interaction receipt (`InteractionRecord::continuation_id`) and the Turn that
//! raised it (`InteractionScope::turn_id`). This module proves a Turn's chain inside one read
//! snapshot: the receipt ledger is scanned to its end under a real row/byte budget, so the absence
//! of a parent is only reported after a complete, budgeted scan — never from an unscanned prefix,
//! an input-id naming format or a preserved body.
//!
//! The proof never writes: a cold read opens the existing database read-only, never creates a
//! writer, never runs a schema upgrade and never falls back to a mutable activation path. Missing
//! proof and budget exhaustion are typed unavailable results; I/O, decode, digest, ownership and
//! contradictory-field failures stay errors with their source.
//!
//! A trusted parent edge comes from the committed interaction receipt itself — its kind, identity,
//! payload digest, revision and resolved terminal shape are all validated inside the same snapshot.
//! The causality of that edge is proven by the immutable Turn start receipts and by the admitted
//! input sequences, never by `history_fact_receipts.last_write_seq`: that column is a re-writable
//! watermark (a content-identical re-save moves it), so it cannot stand for the first persistence
//! order of a fact. The current schema cannot prove that first order, and this port does not claim
//! to. The audience cut is likewise never derived from this chain: only the requested Turn's own
//! start receipt speaks for when that Turn began.

use super::{HISTORY_SCHEMA_VERSION, HistoryStore, integer, statement};
use crate::studio::audience_start::{
    AUDIENCE_START_RECEIPT, FORMAT_VERSION, RECEIPT_REVISION, TURN_START_RECEIPT, TurnStartReceipt,
};
use crate::studio::storage::state::InputIdentityEntry;
use crate::studio::thread_projection::order::receipt_id;
use anyhow::{Context, Result, ensure};
use pl_core::thread::input::{InputContinuation, InputPurpose, InputState};
use pl_core::thread::interactions::InteractionRequest;
use pl_core::thread::decisions::{DecisionSummary, DecisionState, InteractionDecisionState};
use pl_core::thread::permissions::{PermissionRecord, PermissionState};
use serde_json::value::RawValue;
use sea_orm::{ConnectionTrait, TransactionTrait};
use std::collections::{BTreeMap, BTreeSet};

mod decisions;
use decisions::{ParsedDecision, decision_identity_bytes, receipt_decision, reserve_record_identities};
pub(super) use decisions::{checkpoint_decision, each_raw};

/// 每个观察批次最多核验的历史行数，全部 Turn 的回执扫描、起点与逐跳输入共用预算。
///
/// 与 [29](../../../../../../../design/29-conversation-publication.md) 的首次输入资格预算同一口径：
/// 覆盖实际依赖的来源记录，且不把“匹配查询只返回一行”当作扫描成本上限。
const ROW_BUDGET: u64 = 16_384;
/// 因果 JSON 载荷的累计 UTF-8 字节预算；先核 `length(CAST(payload AS BLOB))` 再取值。
const BYTE_BUDGET: u64 = 8 * 1024 * 1024;
const IDENTITY_BUDGET: u64 = 4 * 1024 * 1024;
/// 一页回执元数据行数。按既有 (item_id,revision) 主键推进，仅取数值元数据与载荷长度。
const PAGE_ROWS: u64 = 256;
const HIDDEN_PRESENTATION: &str = "hidden";

/// The receipt kinds this build writes that can never carry a continuation edge.
///
/// `thread_writer::fact_receipts` writes the interaction and permission facts, and
/// `audience_start::receipt_writes` writes the immutable start facts; only the interaction receipt
/// names a continuation (`InteractionRecord::continuation_id`). Every other kind is uninterpreted
/// here, however self-consistent its identity looks, and the proof fails closed instead of skipping
/// a row that might be a parent.
const NON_PARENT_RECEIPT_KINDS: &[&str] = &[TURN_START_RECEIPT, AUDIENCE_START_RECEIPT];

/// The immutable admission proof of one body-less control input.
///
/// It is written by the same history save that accepted the control record and names the continuation
/// point and source Turn frozen at that admission, so a reader never re-derives them from the current
/// snapshot, a later input state or the terminal identity index.
pub(crate) const CONTROL_ADMISSION_RECEIPT: &str = "control-admission";
/// Payload version of [`CONTROL_ADMISSION_RECEIPT`]; a reader refuses any other version.
pub(crate) const CONTROL_ADMISSION_VERSION: u32 = 1;
/// One admission is one fact: the same payload is idempotent, a different one conflicts.
pub(crate) const CONTROL_ADMISSION_REVISION: u64 = 1;

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct ControlAdmissionReceipt {
    pub version: u32,
    pub thread_id: String,
    pub input_id: String,
    pub admission_sequence: u64,
    pub admission_revision: u64,
    pub point_id: String,
    pub source_turn_id: Option<String>,
}

impl ControlAdmissionReceipt {
    pub(crate) fn receipt_id(&self) -> String {
        receipt_id(CONTROL_ADMISSION_RECEIPT, &self.input_id)
    }
}

/// One proven originating input plus its complete canonical continuation ancestors.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct TurnInputChain {
    pub turn_id: String,
    /// The requested Turn's own immutable start receipt, never an ancestor's admission or start.
    pub start_sequence: u64,
    /// The input whose execution opened this Turn (the immutable start receipt's input).
    pub input_id: String,
    /// Parent inputs, nearest first. Each one is a proven, admitted input of an ancestor Turn.
    pub continuation_ancestors: Vec<String>,
}

/// Typed absence of proof. A caller must not read any of these as "no parent".
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum InputChainUnavailable {
    /// The Thread has no readable history database yet (cold session); this read did not make one.
    MissingHistory,
    /// A ledger kind or presentation marker has no supported proof interpretation.
    UnsupportedHistory,
    /// The Turn has no durable start receipt.
    NoTurnStart,
    /// The start receipt carries no usable input, or a required input identity cannot be proven.
    NoInput,
    /// A hidden (system-generated continuation) input has no provable parent receipt.
    UnprovenParent,
    /// Two different interactions claim the same continuation input, or one interaction's revisions
    /// disagree about it.
    Ambiguous,
    /// The parent chain loops back to an already visited Turn or input. Sequence monotonicity makes
    /// this unreachable for a consistent ledger; the guard keeps a corrupted one from looping.
    Cycle,
    /// The bounded scan or payload budget was exhausted before the ledger could be fully checked.
    BudgetExhausted,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum InputChainProof {
    Proven(TurnInputChain),
    Unavailable(InputChainUnavailable),
}

/// Per-observation limits cannot raise the production hard ceilings.
#[derive(Debug, Clone, Copy)]
pub(crate) struct InputFollowupReadLimits {
    rows: u64,
    bytes: u64,
    identity_bytes: u64,
}

impl InputFollowupReadLimits {
    pub(crate) fn new(rows: u64, bytes: u64, identity_bytes: u64) -> Result<Self> {
        ensure!(
            rows <= ROW_BUDGET && bytes <= BYTE_BUDGET && identity_bytes <= IDENTITY_BUDGET,
            "input followup limits exceed the production hard budget"
        );
        Ok(Self { rows, bytes, identity_bytes })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct DecisionReceiptSummary {
    pub decision: DecisionSummary,
    pub continuation_input: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum InputFollowupCheckpoint {
    Resident,
    Cold,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct InputFollowupBatch {
    pub by_turn: BTreeMap<String, InputChainProof>,
    pub decisions: Vec<DecisionReceiptSummary>,
    pub checkpoint_decisions: Option<Vec<DecisionSummary>>,
    /// Charged causal row reads, including bounded exact lookups; never reset per Turn.
    pub rows_read: u64,
    /// Charged UTF-8 payload bytes; schema readiness checks do not materialize history payloads.
    pub bytes_read: u64,
    /// Conservative peak of owned identities, including temporary and retained proof identities.
    pub identity_bytes: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum InputFollowupRead {
    Ready(InputFollowupBatch),
    Unavailable(InputChainUnavailable),
}

/// Cumulative work for one batch: ledger rows and exact-hop payload reads never reset per Turn.
#[derive(Debug, Clone, Copy)]
pub(super) struct ChainBudget {
    rows: u64,
    row_limit: u64,
    bytes: u64,
    byte_limit: u64,
    identity_current: u64,
    identity_peak: u64,
    identity_limit: u64,
    exhausted: bool,
}

impl ChainBudget {
    fn new(limits: InputFollowupReadLimits) -> Self {
        Self {
            rows: 0,
            row_limit: limits.rows,
            bytes: 0,
            byte_limit: limits.bytes,
            identity_current: 0,
            identity_peak: 0,
            identity_limit: limits.identity_bytes,
            exhausted: false,
        }
    }

    /// Charges `rows` before they are used. Returns the reason to hand back once the budget is
    /// spent, so callers stop before reading the row that would exceed it.
    pub(super) fn take_rows(&mut self, rows: u64) -> Option<InputChainUnavailable> {
        let next = self.rows.checked_add(rows);
        if next.is_none_or(|next| next > self.row_limit) {
            self.exhausted = true;
            return Some(InputChainUnavailable::BudgetExhausted);
        }
        self.rows = next.unwrap_or(self.row_limit);
        None
    }

    /// Charges interaction payload bytes before the payload is fetched.
    pub(super) fn take_bytes(&mut self, bytes: u64) -> Option<InputChainUnavailable> {
        let next = self.bytes.checked_add(bytes);
        if next.is_none_or(|next| next > self.byte_limit) {
            self.exhausted = true;
            return Some(InputChainUnavailable::BudgetExhausted);
        }
        self.bytes = next.unwrap_or(self.byte_limit);
        None
    }

    pub(super) fn own(&mut self, bytes: u64) -> Result<()> {
        let next = self.identity_current.checked_add(bytes);
        if next.is_none_or(|next| next > self.identity_limit) {
            self.exhausted = true;
            anyhow::bail!("input followup identity budget exhausted");
}
        self.identity_current = next.context("identity accounting overflow")?;
        self.identity_peak = self.identity_peak.max(self.identity_current);
        Ok(())
    }

    pub(super) fn mark(&self) -> u64 {
        self.identity_current
    }

    /// Only temporary identities are released; inspected rows and UTF-8 payload bytes never are.
    pub(super) fn retain(&mut self, mark: u64, retained: u64) -> Result<()> {
        let current = mark.checked_add(retained).context("identity accounting overflow")?;
        ensure!(current <= self.identity_current, "retained identities were not reserved before allocation");
        self.identity_current = current;
        Ok(())
    }

    fn copy(&mut self, value: &str) -> Result<String> {
        self.own(u64::try_from(value.len())?.checked_add(std::mem::size_of::<String>() as u64)
            .context("identity accounting overflow")?)?;
        Ok(value.to_owned())
    }

    fn receipt_id(&mut self, kind: &str, id: &str) -> Result<String> {
        // usize decimal width plus separators, String and the result; reserve before formatting.
        self.own((kind.len() as u64).checked_add(id.len() as u64)
            .and_then(|bytes| bytes.checked_add(24 + std::mem::size_of::<String>() as u64))
            .context("receipt identity size overflow")?)?;
        Ok(receipt_id(kind, id))
    }

    pub(super) fn remaining_rows(&self) -> u64 {
        self.row_limit - self.rows
    }

    pub(super) fn json_string(&mut self, value: &RawValue) -> Result<String> {
        // The encoded length bounds decoded UTF-8, including escaped identities. Two copies cover
        // the JSON decoder's transient scratch and the resulting owned string before either exists.
        self.own(u64::try_from(value.get().len())?.checked_mul(2)
            .and_then(|bytes| bytes.checked_add(std::mem::size_of::<String>() as u64))
            .context("identity accounting overflow")?)?;
        Ok(serde_json::from_str(value.get())?)
    }
}

/// One proved input identity, read from the durable identity index only.
struct ProvenInput {
    id: String,
    accepted_sequence: u64,
    state: InputState,
    /// The durable hidden marker: a system-generated continuation input carries it, while every
    /// other input (including a legacy row without the marker) does not.
    hidden: bool,
    /// The typed purpose the admission recorded. A root may only be proven as a plain message.
    purpose: InputPurpose,
    /// The continuation the admission recorded, if any. Kept and checked for consistency; it never
    /// establishes a parent edge by itself.
    continuation: Option<InputContinuation>,
    /// The identity row's own revision, compared with the immutable admission revision.
    revision: u64,
    /// The first revision frozen at control admission, not the current consumed-state revision.
    continuation_admission_revision: Option<u64>,
}

impl ProvenInput {
    /// Whether this input can only exist as a continuation of an interaction.
    ///
    /// A control input (framework resume) or a hidden one is never a root: without a committed
    /// interaction receipt naming it, its ancestry is unproven. Only a plain visible message may be
    /// proven as the root of a chain.
    fn requires_parent(&self) -> bool {
        self.hidden || self.purpose == InputPurpose::Continuation
    }
}

/// An interaction receipt that produced one continuation input.
struct ContinuationParent {
    turn_id: String,
}

/// Whether a stored receipt identity is exactly the one [`receipt_id`] builds for `kind`.
///
/// The stored identity is `"{kind}:{id length}:{id}"`; this re-derives that shape from the same
/// constructor instead of introducing a second string protocol. It validates storage integrity only:
/// no input origin is ever inferred from an identity.
fn receipt_identity_matches_kind(item_id: &str, kind: &str) -> bool {
    let Some((prefix, rest)) = item_id.split_once(':') else {
        return false;
    };
    let Some((length, id)) = rest.split_once(':') else {
        return false;
    };
    prefix == kind && !id.is_empty() && length.parse::<usize>().ok() == Some(id.len())
}

/// The immutable start receipt of one Turn: its input and the effect sequence that opened it.
struct TurnStartHop {
    input_id: String,
    write_sequence: u64,
}

pub(super) enum Hop<T> {
    Ready(T),
    Unavailable(InputChainUnavailable),
}

impl HistoryStore {
    /// One current readonly snapshot supplies the complete ledger, all requested chains and, only
    /// for a cold Thread, narrow checkpoint decisions. Cancellation drops only readonly resources.
    pub(crate) async fn input_followups(
        &self,
        turn_ids: &[String],
        checkpoint: InputFollowupCheckpoint,
        limits: InputFollowupReadLimits,
    ) -> Result<InputFollowupRead> {
        ensure!(turn_ids.iter().all(|turn| !turn.is_empty()), "Turn identity is empty for input followups");
        let mut budget = ChainBudget::new(limits);
        let mut requested = BTreeSet::new();
        let mut input_bytes = 0_u64;
        for turn in turn_ids {
            input_bytes = match input_bytes.checked_add(u64::try_from(turn.len())?) {
                Some(bytes) if bytes <= BYTE_BUDGET => bytes,
                _ => return Ok(InputFollowupRead::Unavailable(InputChainUnavailable::BudgetExhausted)),
            };
            if !requested.contains(turn.as_str()) {
                if requested.len() as u64 == ROW_BUDGET
                    || budget.own((std::mem::size_of::<&str>() as u64) * 4 + 64).is_err()
                {
                    return Ok(InputFollowupRead::Unavailable(InputChainUnavailable::BudgetExhausted));
                }
                requested.insert(turn.as_str());
            }
        }
        self.wait_for_initialization().await?;
        let _initializing = self.state.init.read().await;
        if !tokio::fs::try_exists(&self.state.path).await? {
            return Ok(InputFollowupRead::Unavailable(InputChainUnavailable::MissingHistory));
        }
        // A first bounded read cannot call the ordinary connection initializer: that initializer
        // owns database/thread strings before the caller's identity budget can check their lengths.
        // Open only the readonly pool here and establish/cache the same existing reader binding
        // after the budgeted snapshot has validated it. No second registry or writer is created.
        let existing = self.state.reader.get();
        let mut fresh = if existing.is_none() {
            Some(super::connect_read_only(&self.state.path).await?)
        } else { None };
        let db = match existing { Some(connection) => &connection.db,
            None => fresh.as_ref().context("readonly followup connection is absent")? };
        let expected = existing.map(|connection| connection.database_id.as_str())
            .or_else(|| self.state.writer.get().map(|connection| connection.database_id.as_str()));
        if let (Some(reader), Some(writer)) = (existing, self.state.writer.get()) {
            ensure!(reader.database_id == writer.database_id, "readonly history ownership changed");
        }
        let snapshot = match db.begin().await {
            Ok(snapshot) => snapshot,
            Err(error) => {
                if let Some(db) = fresh.take() { db.close().await?; }
                return Err(error.into());
            }
        };
        let mut binding = None;
        let result = prove_batch(&snapshot, &self.state.thread_id, expected, &requested,
            checkpoint, &mut budget, &mut binding).await;
        let released = snapshot.rollback().await;
        let mut pool_result = Ok(());
        if let Some(db) = fresh.take() {
            if let Some(database_id) = binding {
                let mut candidate = Some(super::HistoryConnection {
                    db, database_id, schema_version: HISTORY_SCHEMA_VERSION,
                });
                match self.state.reader.get_or_try_init(|| async {
                    candidate.take().context("readonly followup binding disappeared")
                }).await {
                    Ok(winner) => {
                        if let Some(loser) = candidate {
                            let agrees = winner.database_id == loser.database_id;
                            pool_result = loser.db.close().await.map_err(anyhow::Error::from)
                                .and_then(|()| { ensure!(agrees, "readonly history ownership changed"); Ok(()) });
                        }
                    }
                    Err(error) => { pool_result = Err(error); }
                }
            } else {
                pool_result = db.close().await.map_err(anyhow::Error::from);
            }
        }
        released?;
        pool_result?;
        if budget.exhausted {
            return Ok(InputFollowupRead::Unavailable(InputChainUnavailable::BudgetExhausted));
        }
        result
    }
}

async fn prove_batch<C: ConnectionTrait>(
    db: &C,
    thread_id: &str,
    database_id: Option<&str>,
    requested: &BTreeSet<&str>,
    checkpoint: InputFollowupCheckpoint,
    budget: &mut ChainBudget,
    binding: &mut Option<String>,
) -> Result<InputFollowupRead> {
    if let Some(reason) = budget.take_rows(1) { return Ok(InputFollowupRead::Unavailable(reason)); }
    let meta = db.query_one_raw(statement(
        "SELECT length(CAST(database_id AS BLOB)) AS database_bytes, length(CAST(thread_id AS BLOB)) AS thread_bytes, applied_write_seq FROM history_meta WHERE id=1", vec![]
    )).await?.context("history metadata is missing for input followups")?;
    let mark = budget.mark();
    let lengths = u64::try_from(meta.try_get::<i64>("", "database_bytes")?)?
        .checked_add(u64::try_from(meta.try_get::<i64>("", "thread_bytes")?)?)
        .context("history identity size overflow")?;
    budget.own(lengths.checked_mul(4).and_then(|bytes| bytes.checked_add(256))
        .context("history identity size overflow")?)?;
    // All H9 readiness checks remain inside this snapshot. The preceding lengths bound every
    // transient identity copy the existing validator makes before it returns the database binding.
    let (ready_id, _) = super::current::validate_readable(db, thread_id).await?;
    ensure!(database_id.is_none_or(|expected| expected == ready_id), "input followup history ownership changed");
    let bound_bytes = ready_id.len() as u64 + std::mem::size_of::<String>() as u64;
    *binding = Some(ready_id);
    budget.retain(mark, bound_bytes)?;
    let watermark = u64::try_from(meta.try_get::<i64>("", "applied_write_seq")?)?;
    let ledger = match scan_continuation_parents(db, thread_id, watermark, budget).await? {
        Hop::Ready(ledger) => ledger,
        Hop::Unavailable(reason) => return Ok(InputFollowupRead::Unavailable(reason)),
    };
    let checkpoint_decisions = match checkpoint {
        InputFollowupCheckpoint::Resident => None,
        InputFollowupCheckpoint::Cold => match super::checkpoint::read_followup_decisions(db, thread_id, watermark, budget).await? {
            Hop::Ready(decisions) => Some(decisions),
            Hop::Unavailable(reason) => return Ok(InputFollowupRead::Unavailable(reason)),
        },
    };
    let mut by_turn = BTreeMap::new();
    for turn_id in requested {
        let mark = budget.mark();
        let proof = prove_turn(db, thread_id, watermark, &ledger, turn_id, budget).await?;
        if matches!(&proof, InputChainProof::Unavailable(InputChainUnavailable::BudgetExhausted)) {
            return Ok(InputFollowupRead::Unavailable(InputChainUnavailable::BudgetExhausted));
        }
        budget.own((std::mem::size_of::<InputChainProof>() as u64) * 2 + 64)?;
        let key = budget.copy(turn_id)?;
        let retained = proof_identity_bytes(&proof)?.checked_add(key.len() as u64)
            .and_then(|bytes| bytes.checked_add((std::mem::size_of::<InputChainProof>() as u64) * 2 + 64))
            .context("proof identity size overflow")?;
        by_turn.insert(key, proof);
        budget.retain(mark, retained)?;
    }
    Ok(InputFollowupRead::Ready(InputFollowupBatch {
        by_turn, decisions: ledger.decisions, checkpoint_decisions,
        rows_read: budget.rows, bytes_read: budget.bytes, identity_bytes: budget.identity_peak,
    }))
}

fn proof_identity_bytes(proof: &InputChainProof) -> Result<u64> {
    let InputChainProof::Proven(chain) = proof else { return Ok(0) };
    let mut bytes = (chain.turn_id.len() as u64).checked_add(chain.input_id.len() as u64)
        .context("proof identity size overflow")?;
    for id in &chain.continuation_ancestors {
        bytes = bytes.checked_add(id.len() as u64)
            .and_then(|bytes| bytes.checked_add((std::mem::size_of::<String>() as u64) * 2))
            .context("proof identity size overflow")?;
    }
    Ok(bytes)
}

async fn prove_turn<C: ConnectionTrait>(
    db: &C,
    thread_id: &str,
    watermark: u64,
    ledger: &ContinuationLedger,
    turn_id: &str,
    budget: &mut ChainBudget,
) -> Result<InputChainProof> {
    let parents = &ledger.parents;
    let controls = &ledger.controls;

    let mut ancestors: Vec<String> = Vec::new();
    let mut visited_turns: BTreeSet<String> = BTreeSet::new();
    let mut visited_inputs: BTreeSet<String> = BTreeSet::new();
    let mut previous_accepted: Option<u64> = None;
    let mut hop_turn = budget.copy(turn_id)?;
    let mut hop = match turn_start(db, thread_id, watermark, &hop_turn, budget).await? {
        Hop::Ready(hop) => hop,
        Hop::Unavailable(reason) => return Ok(InputChainProof::Unavailable(reason)),
    };
    // The proven chain is anchored on the requested Turn's own input, never on the root it reaches.
    let origin_input = budget.copy(&hop.input_id)?;
    let start_sequence = hop.write_sequence;
    loop {
        budget.own(64)?;
        if !visited_turns.insert(budget.copy(&hop_turn)?) {
            return Ok(InputChainProof::Unavailable(InputChainUnavailable::Cycle));
        }
        let input = match input_identity(db, &hop.input_id, watermark, budget).await? {
            Hop::Ready(input) => input,
            Hop::Unavailable(reason) => return Ok(InputChainProof::Unavailable(reason)),
        };
        budget.own(64)?;
        if !visited_inputs.insert(budget.copy(&input.id)?) {
            return Ok(InputChainProof::Unavailable(InputChainUnavailable::Cycle));
        }
        check_input_state(&input, &hop_turn, previous_accepted.is_none())?;
        ensure!(
            input.accepted_sequence <= hop.write_sequence,
            "input {} was admitted after its Turn {} started",
            input.id,
            hop_turn
        );
        if let Some(child) = previous_accepted {
            ensure!(
                input.accepted_sequence < child,
                "continuation ancestor {} was not admitted before its child input",
                input.id
            );
        }

        let admission = controls.get(&input.id);
        let claimants = parents.get(&input.id);
        if admission.is_some() && claimants.is_some() {
            // Two different provenances cannot both own one input.
            return Ok(InputChainProof::Unavailable(
                InputChainUnavailable::Ambiguous,
            ));
        }
        let next_turn = if let Some(admission) = admission {
            // A control input is proven by its own admission receipt, never by a receipt that merely
            // names a point or a Turn, and never by looking like a plain message.
            ensure!(
                input.purpose == InputPurpose::Continuation,
                "control admission {} conflicts with a non-control input identity",
                input.id
            );
            let continuation = input
                .continuation
                .as_ref()
                .context("control admission input has no continuation identity")?;
            ensure!(
                continuation.point_id == admission.point_id
                    && continuation.source_turn_id == admission.source_turn_id,
                "control admission {} conflicts with its input identity",
                input.id
            );
            ensure!(
                input.accepted_sequence == admission.admission_sequence
                    && input.revision >= admission.admission_revision,
                "control admission {} disagrees with its admission sequence",
                input.id
            );
            ensure!(
                input.continuation_admission_revision == Some(admission.admission_revision),
                "control admission {} disagrees with its immutable first-admission revision",
                input.id
            );
            // A control authorises work that really started: it is consumed by this very Turn, never
            // pending or discarded.
            ensure!(
                matches!(&input.state, InputState::Consumed { turn_id, .. } if turn_id == &hop_turn),
                "control input {} was not consumed by Turn {hop_turn}",
                input.id
            );
            match &admission.source_turn_id {
                // A control that declares no source Turn has a legal admission but proves no
                // ancestry: it is neither a root nor a truncated proven chain.
                None => {
                    return Ok(InputChainProof::Unavailable(
                        InputChainUnavailable::UnprovenParent,
                    ));
                }
                Some(source_turn) => budget.copy(source_turn)?,
            }
        } else if let Some(claimants) = claimants {
            // Interaction receipts name the answers they produce, which are plain messages; a control
            // input is only ever proven by its own admission receipt.
            ensure!(
                input.purpose == InputPurpose::Message && input.continuation.is_none(),
                "interaction receipt claims control input {} without its admission",
                input.id
            );
            if claimants.len() > 1 {
                return Ok(InputChainProof::Unavailable(
                    InputChainUnavailable::Ambiguous,
                ));
            }
            let parent = &claimants[0];
            ensure!(
                parent.turn_id != hop_turn,
                "continuation parent Turn repeats its own child Turn {hop_turn}"
            );
            budget.copy(&parent.turn_id)?
        } else {
            if input.requires_parent() {
                return Ok(InputChainProof::Unavailable(
                    InputChainUnavailable::UnprovenParent,
                ));
            }
            // Only a complete, budgeted scan reaches this branch: the ledger ended within budget and
            // no receipt claims this input as a continuation.
            return Ok(InputChainProof::Proven(TurnInputChain {
                turn_id: budget.copy(turn_id)?,
                start_sequence,
                input_id: origin_input,
                continuation_ancestors: ancestors,
            }));
        };
        let parent_hop = match turn_start(db, thread_id, watermark, &next_turn, budget).await? {
            Hop::Ready(hop) => hop,
            Hop::Unavailable(reason) => return Ok(InputChainProof::Unavailable(reason)),
        };
        // Two different Turns cannot start in one commit, and a continuation can only follow the
        // Turn that raised it. Fact rows are idempotent upserts whose `last_write_seq` may advance on
        // a re-committed receipt, so the immutable start receipts — not that watermark — are the
        // ordering anchor that rules out a "future" parent edge.
        ensure!(
            parent_hop.write_sequence < hop.write_sequence,
            "continuation parent Turn {next_turn} did not start before its child Turn {hop_turn}",
        );
        previous_accepted = Some(input.accepted_sequence);
        budget.own((std::mem::size_of::<String>() as u64) * 2)?;
        ancestors.push(budget.copy(&parent_hop.input_id)?);
        hop_turn = next_turn;
        hop = parent_hop;
    }
}

enum Fetch<T> {
    Ready(T),
    Missing,
    Unavailable(InputChainUnavailable),
}

/// One exact fact receipt, read under the byte budget.
struct FactRow {
    kind: String,
    digest: String,
    write_sequence: u64,
    payload: String,
}

/// One input identity row, read under the byte budget.
struct IdentityRow {
    ordinal: u64,
    revision: u64,
    digest: String,
    request_digest: Option<String>,
    presentation: Option<String>,
    write_sequence: u64,
    payload: String,
}

/// Reads one exact fact receipt: its metadata row is the charged row, and the payload is fetched
/// only after `length(CAST(payload AS BLOB))` — the stored UTF-8 byte length, not a character count
/// — passes the byte budget. The payload read is the same record, so it is not charged twice.
async fn fact_row<C: ConnectionTrait>(
    db: &C,
    item_id: &str,
    revision: u64,
    budget: &mut ChainBudget,
) -> Result<Fetch<FactRow>> {
    if let Some(reason) = budget.take_rows(1) {
        return Ok(Fetch::Unavailable(reason));
    }
    // SQL bind ownership (including the cloned second lookup) is charged before either clone.
    budget.own((item_id.len() as u64 + std::mem::size_of::<String>() as u64) * 4)?;
    let values = vec![item_id.to_owned().into(), integer(revision)?.into()];
    let Some(row) = db
        .query_one_raw(statement(
            "SELECT length(CAST(kind AS BLOB))+length(CAST(digest AS BLOB)) AS identity_bytes, \
                    length(CAST(payload AS BLOB)) AS payload_bytes \
             FROM history_fact_receipts WHERE item_id=? AND revision=?",
            values.clone(),
        ))
        .await?
    else {
        return Ok(Fetch::Missing);
    };
    let payload_bytes = u64::try_from(row.try_get::<i64>("", "payload_bytes")?)?;
    if let Some(reason) = budget.take_bytes(payload_bytes) {
        return Ok(Fetch::Unavailable(reason));
    }
    budget.own(u64::try_from(row.try_get::<i64>("", "identity_bytes")?)?
        .checked_mul(2).and_then(|bytes| bytes.checked_add(256))
        .context("fact metadata identity size overflow")?)?;
    let row = db
        .query_one_raw(statement(
            "SELECT kind,digest,last_write_seq,payload FROM history_fact_receipts WHERE item_id=? AND revision=?",
            values,
        ))
        .await?
        .context("fact receipt payload disappeared inside one read snapshot")?;
    let payload = row.try_get::<String>("", "payload")?;
    Ok(Fetch::Ready(FactRow {
        kind: row.try_get("", "kind")?,
        digest: row.try_get("", "digest")?,
        write_sequence: u64::try_from(row.try_get::<i64>("", "last_write_seq")?)?,
        payload,
    }))
}

/// Reads one input identity row with the same byte-budget discipline as [`fact_row`].
async fn identity_row<C: ConnectionTrait>(
    db: &C,
    input_id: &str,
    budget: &mut ChainBudget,
) -> Result<Fetch<IdentityRow>> {
    if let Some(reason) = budget.take_rows(1) {
        return Ok(Fetch::Unavailable(reason));
    }
    budget.own((input_id.len() as u64 + std::mem::size_of::<String>() as u64) * 4)?;
    let values = vec![input_id.to_owned().into()];
    let Some(row) = db
        .query_one_raw(statement(
            "SELECT length(CAST(digest AS BLOB))+COALESCE(length(CAST(request_digest AS BLOB)),0) \
                    +COALESCE(length(CAST(presentation AS BLOB)),0) AS identity_bytes, \
                    length(CAST(payload AS BLOB)) AS payload_bytes \
             FROM history_input_identities WHERE item_id=?",
            values.clone(),
        ))
        .await?
    else {
        return Ok(Fetch::Missing);
    };
    let payload_bytes = u64::try_from(row.try_get::<i64>("", "payload_bytes")?)?;
    if let Some(reason) = budget.take_bytes(payload_bytes) {
        return Ok(Fetch::Unavailable(reason));
    }
    budget.own(u64::try_from(row.try_get::<i64>("", "identity_bytes")?)?
        .checked_mul(2).and_then(|bytes| bytes.checked_add(256))
        .context("input metadata identity size overflow")?)?;
    let row = db
        .query_one_raw(statement(
            "SELECT ordinal,revision,digest,request_digest,presentation,last_write_seq,payload FROM history_input_identities WHERE item_id=?",
            values,
        ))
        .await?
        .context("input identity payload disappeared inside one read snapshot")?;
    let payload = row.try_get::<String>("", "payload")?;
    Ok(Fetch::Ready(IdentityRow {
        ordinal: u64::try_from(row.try_get::<i64>("", "ordinal")?)?,
        revision: u64::try_from(row.try_get::<i64>("", "revision")?)?,
        digest: row.try_get("", "digest")?,
        request_digest: row.try_get("", "request_digest")?,
        presentation: row.try_get("", "presentation")?,
        write_sequence: u64::try_from(row.try_get::<i64>("", "last_write_seq")?)?,
        payload,
    }))
}

async fn turn_start<C: ConnectionTrait>(
    db: &C,
    thread_id: &str,
    watermark: u64,
    turn_id: &str,
    budget: &mut ChainBudget,
) -> Result<Hop<TurnStartHop>> {
    let item_id = budget.receipt_id(TURN_START_RECEIPT, turn_id)?;
    let row = match fact_row(db, &item_id, RECEIPT_REVISION, budget).await? {
        Fetch::Ready(row) => row,
        Fetch::Missing => return Ok(Hop::Unavailable(InputChainUnavailable::NoTurnStart)),
        Fetch::Unavailable(reason) => return Ok(Hop::Unavailable(reason)),
    };
    ensure!(
        row.kind == TURN_START_RECEIPT,
        "Turn start receipt {turn_id} carries another fact kind"
    );
    budget.own(96)?; // transient content hash
    ensure!(
        pl_core::context::content_hash(row.payload.as_bytes()) == row.digest,
        "Turn start receipt {turn_id} payload digest mismatch"
    );
    ensure!(
        row.write_sequence > 0 && row.write_sequence <= watermark,
        "Turn start receipt {turn_id} is not covered by durable history"
    );
    reserve_record_identities(&row.payload, budget, 0)?;
    let receipt: TurnStartReceipt = serde_json::from_str(&row.payload)
        .with_context(|| format!("Turn start receipt {turn_id} cannot be decoded"))?;
    // The start record is written exactly once: core rejects any later commit that re-carries an
    // existing Turn as `Running` and requires a new Turn to be `Running` with zero model steps
    // (`pl-core/src/thread/journal.rs:492-513`). Its payload `sequence` is the effect that persisted
    // it, so this equality stays exact — unlike the mutable watermark on any re-writable receipt.
    ensure!(
        receipt.version == FORMAT_VERSION
            && receipt.thread_id == thread_id
            && receipt.turn_id == turn_id
            && receipt.sequence == row.write_sequence,
        "Turn start receipt {turn_id} conflicts with its durable identity"
    );
    let Some(input_id) = receipt.input_id.filter(|id| !id.is_empty()) else {
        return Ok(Hop::Unavailable(InputChainUnavailable::NoInput));
    };
    Ok(Hop::Ready(TurnStartHop {
        input_id,
        write_sequence: row.write_sequence,
    }))
}

async fn input_identity<C: ConnectionTrait>(
    db: &C,
    input_id: &str,
    watermark: u64,
    budget: &mut ChainBudget,
) -> Result<Hop<ProvenInput>> {
    let row = match identity_row(db, input_id, budget).await? {
        Fetch::Ready(row) => row,
        Fetch::Missing => return Ok(Hop::Unavailable(InputChainUnavailable::NoInput)),
        Fetch::Unavailable(reason) => return Ok(Hop::Unavailable(reason)),
    };
    ensure!(
        row.write_sequence > 0 && row.write_sequence <= watermark,
        "input identity {input_id} is not covered by durable history"
    );
    reserve_record_identities(&row.payload, budget, 0)?;
    let entry: InputIdentityEntry = serde_json::from_str(&row.payload)
        .with_context(|| format!("input identity {input_id} cannot be decoded"))?;
    // Every duplicated column must agree with the decoded payload. `digest` is the content digest of
    // the originally admitted input body; it is checked for identity consistency here and is not
    // treated as an envelope over the identity row's state or admission sequence.
    ensure!(
        entry.id == input_id
            && entry.ordinal == row.ordinal
            && entry.revision == row.revision
            && entry.digest == row.digest
            && !entry.digest.is_empty(),
        "input identity {input_id} conflicts with its durable record"
    );
    ensure!(
        row.request_digest
            .as_deref()
            .is_none_or(|digest| !digest.is_empty()),
        "input identity {input_id} has an empty request digest"
    );
    // The durable hidden marker is the only positive evidence that an input was generated as a
    // continuation. An unknown marker fails closed instead of counting as a visible root input.
    let hidden = match row.presentation.as_deref() {
        Some(HIDDEN_PRESENTATION) => true,
        Some("visible") => false,
        None => {
            return Ok(Hop::Unavailable(InputChainUnavailable::UnsupportedHistory));
        }
        Some(other) => anyhow::bail!("input identity {input_id} has invalid presentation {other}"),
    };
    ensure!(
        entry.accepted_sequence > 0 && entry.ordinal > 0,
        "input identity {input_id} has no admission sequence"
    );
    // The typed purpose and the recorded continuation must describe one admission: a control input
    // always names the point it continues, and a continuation without a point is contradictory.
    ensure!(
        entry.purpose != InputPurpose::Continuation
            || entry
                .continuation
                .as_ref()
                .is_some_and(|continuation| !continuation.point_id.is_empty()),
        "control input {input_id} has no continuation identity"
    );
    Ok(Hop::Ready(ProvenInput {
        id: entry.id,
        accepted_sequence: entry.accepted_sequence,
        state: entry.state,
        hidden,
        purpose: entry.purpose,
        continuation: entry.continuation,
        revision: entry.revision,
        continuation_admission_revision: entry.continuation_admission_revision,
    }))
}

/// A consumed input must name the Turn this hop proves. The requested Turn may still be live, so its
/// own input is accepted while pending — the immutable start receipt already binds it. Every
/// ancestor Turn has ended, so its input must really have been consumed by it.
fn check_input_state(input: &ProvenInput, hop_turn: &str, is_origin: bool) -> Result<()> {
    ensure!(
        !matches!(input.state, InputState::Discarded),
        "input {} was discarded and cannot have opened Turn {hop_turn}",
        input.id
    );
    match &input.state {
        InputState::Consumed { turn_id, .. } => ensure!(
            turn_id == hop_turn,
            "input {} was consumed by another Turn",
            input.id
        ),
        InputState::Pending => ensure!(
            is_origin,
            "ancestor input {} was never consumed by Turn {hop_turn}",
            input.id
        ),
        InputState::Discarded => {}
    }
    Ok(())
}

/// The immutable admission of one body-less control input, taken from its own receipt.
#[derive(Debug, Clone, PartialEq, Eq)]
struct ControlAdmission {
    admission_sequence: u64,
    admission_revision: u64,
    point_id: String,
    source_turn_id: Option<String>,
}

/// Everything the receipt ledger proves about continuation ancestry.
struct ContinuationLedger {
    /// Interaction receipts that name a continuation input, by that input.
    parents: BTreeMap<String, Vec<ContinuationParent>>,
    /// Control inputs with their own admission proof, by input id.
    controls: BTreeMap<String, ControlAdmission>,
}

/// Scans every receipt row of this Thread to its end under the budget and returns the proven
/// continuation parents by child input.
///
/// The scan is deliberately not restricted to interaction rows: every receipt row costs budget, so
/// a large non-interaction ledger cannot hide an unscanned interaction parent behind a `WHERE` that
/// only counts matched rows.
async fn scan_continuation_parents<C: ConnectionTrait>(
    db: &C,
    thread_id: &str,
    watermark: u64,
    budget: &mut ChainBudget,
) -> Result<Hop<ContinuationLedger>> {
    /// One committed revision of one interaction identity.
    struct Revision {
        state: InteractionState,
        continuation: Option<String>,
        request: InteractionRequest,
        write_sequence: u64,
    }
    /// One interaction receipt row of the current page, already byte-budgeted.
    struct InteractionRow {
        rowid: i64,
        item_id: String,
        revision: u64,
        digest: String,
        write_sequence: u64,
    }
    // Revision order is the committed record's own contract, never the physical row order.
    let mut ledger: BTreeMap<String, BTreeMap<u64, Revision>> = BTreeMap::new();
    let mut controls: BTreeMap<String, ControlAdmission> = BTreeMap::new();
    let mut cursor: i64 = 0;
    loop {
        // Never materialise more rows than the budget can still pay for: the page is capped at the
        // remaining rows plus one probe row whose content is only used to report exhaustion.
        let probe = budget
            .row_limit
            .saturating_sub(budget.rows)
            .saturating_add(1);
        let limit = PAGE_ROWS.min(probe);
        let page = db
            .query_all_raw(statement(
                "SELECT rowid,item_id,revision,kind,digest,last_write_seq, \
                        length(CAST(payload AS BLOB)) AS payload_bytes \
                 FROM history_fact_receipts WHERE rowid>? ORDER BY rowid LIMIT ?",
                vec![cursor.into(), integer(limit)?.into()],
            ))
            .await?;
        if page.is_empty() {
            break;
        }
        let mut interaction_rows: Vec<InteractionRow> = Vec::new();
        let mut control_rows: Vec<InteractionRow> = Vec::new();
        for row in &page {
            // Every returned row is real scan work, whatever its kind.
            if let Some(reason) = budget.take_rows(1) {
                return Ok(Hop::Unavailable(reason));
            }
            cursor = row.try_get("", "rowid")?;
            let kind: String = row.try_get("", "kind")?;
            let item_id: String = row.try_get("", "item_id")?;
            // The stored identity and the stored kind must agree before this row is used for
            // anything: otherwise a corrupted `kind` would make a real interaction silently
            // skippable and turn a continued Turn into an unproven root. Only metadata is read here,
            // so non-interaction payloads still cost no payload budget.
            ensure!(
                receipt_identity_matches_kind(&item_id, &kind),
                "stored receipt {item_id} does not match its stored kind {kind}"
            );
            if kind != "interaction" {
                if kind == CONTROL_ADMISSION_RECEIPT {
                    // A control admission is ancestry-bearing: keep it for the same payload pass.
                    let payload_bytes = u64::try_from(row.try_get::<i64>("", "payload_bytes")?)?;
                    if let Some(reason) = budget.take_bytes(payload_bytes) {
                        return Ok(Hop::Unavailable(reason));
                    }
                    control_rows.push(InteractionRow {
                        rowid: cursor,
                        item_id,
                        revision: u64::try_from(row.try_get::<i64>("", "revision")?)?,
                        digest: row.try_get("", "digest")?,
                        write_sequence: u64::try_from(row.try_get::<i64>("", "last_write_seq")?)?,
                    });
                    continue;
                }
                if !NON_PARENT_RECEIPT_KINDS.contains(&kind.as_str()) {
                    return Ok(Hop::Unavailable(InputChainUnavailable::UnsupportedHistory));
                }
                continue;
            }
            let payload_bytes = u64::try_from(row.try_get::<i64>("", "payload_bytes")?)?;
            if let Some(reason) = budget.take_bytes(payload_bytes) {
                return Ok(Hop::Unavailable(reason));
            }
            interaction_rows.push(InteractionRow {
                rowid: cursor,
                item_id,
                revision: u64::try_from(row.try_get::<i64>("", "revision")?)?,
                digest: row.try_get("", "digest")?,
                write_sequence: u64::try_from(row.try_get::<i64>("", "last_write_seq")?)?,
            });
        }
        if interaction_rows.is_empty() && control_rows.is_empty() {
            continue;
        }
        let page_rows: Vec<&InteractionRow> =
            interaction_rows.iter().chain(control_rows.iter()).collect();
        let placeholders = vec!["?"; page_rows.len()].join(",");
        let payloads = db
            .query_all_raw(statement(
                &format!(
                    "SELECT rowid,payload FROM history_fact_receipts \
                     WHERE rowid IN ({placeholders}) ORDER BY rowid"
                ),
                page_rows.iter().map(|row| row.rowid.into()).collect(),
            ))
            .await?;
        ensure!(
            payloads.len() == page_rows.len(),
            "receipt payload page changed during one read snapshot"
        );
        let payload_of = |row: &InteractionRow| -> Result<String> {
            Ok(payloads
                .iter()
                .find(|stored| stored.try_get::<i64>("", "rowid").ok() == Some(row.rowid))
                .context("receipt payload row is missing in one read snapshot")?
                .try_get("", "payload")?)
        };
        for row in control_rows {
            let payload = payload_of(&row)?;
            ensure!(
                pl_core::context::content_hash(payload.as_bytes()) == row.digest,
                "control admission {} payload digest mismatch",
                row.item_id
            );
            let receipt: ControlAdmissionReceipt = serde_json::from_str(&payload)
                .with_context(|| format!("control admission {} cannot be decoded", row.item_id))?;
            ensure!(
                receipt.version == CONTROL_ADMISSION_VERSION
                    && receipt.thread_id == thread_id
                    && receipt.receipt_id() == row.item_id
                    && row.revision == CONTROL_ADMISSION_REVISION
                    && receipt.admission_sequence > 0
                    && receipt.admission_revision > 0
                    && !receipt.point_id.is_empty()
                    && receipt
                        .source_turn_id
                        .as_ref()
                        .is_none_or(|turn| !turn.is_empty())
                    && row.write_sequence > 0
                    && row.write_sequence <= watermark,
                "control admission {} conflicts with its durable identity",
                row.item_id
            );
            let admission = ControlAdmission {
                admission_sequence: receipt.admission_sequence,
                admission_revision: receipt.admission_revision,
                point_id: receipt.point_id,
                source_turn_id: receipt.source_turn_id,
            };
            let input_id = receipt.input_id;
            if let Some(previous) = controls.insert(input_id.clone(), admission.clone()) {
                ensure!(
                    previous == admission,
                    "control input {input_id} carries conflicting admissions"
                );
            }
        }
        for row in interaction_rows {
            let payload = payload_of(&row)?;
            // A receipt is a committed fact row: its digest covers this exact payload and its SQL
            // revision must be the payload's own revision, so a rewritten parent cannot pass as the
            // original (the Turn start digest does not protect this table).
            ensure!(
                pl_core::context::content_hash(payload.as_bytes()) == row.digest,
                "interaction receipt {} payload digest mismatch",
                row.item_id
            );
            let record: InteractionRecord = serde_json::from_str(&payload).with_context(|| {
                format!("interaction receipt {} cannot be decoded", row.item_id)
            })?;
            ensure!(
                record.revision == row.revision,
                "interaction receipt {} revision conflicts with its stored row",
                row.item_id
            );
            ensure!(
                receipt_id("interaction", &record.request.id) == row.item_id,
                "interaction receipt {} conflicts with its committed record",
                row.item_id
            );
            ensure!(
                row.write_sequence > 0 && row.write_sequence <= watermark,
                "interaction receipt {} is not covered by durable history",
                row.item_id
            );
            if let Some(continuation) = &record.continuation_id {
                ensure!(
                    matches!(record.state, InteractionState::Resolved(_)),
                    "interaction receipt {} claims a continuation without resolving",
                    row.item_id
                );
                ensure!(
                    !continuation.is_empty(),
                    "interaction receipt {} names an empty continuation",
                    row.item_id
                );
                ensure!(
                    !record.request.turn_id.is_empty(),
                    "interaction receipt {} has no origin Turn",
                    row.item_id
                );
            }
            ledger.entry(row.item_id).or_default().insert(
                row.revision,
                Revision {
                    state: record.state,
                    continuation: record.continuation_id,
                    request: record.request,
                    write_sequence: row.write_sequence,
                },
            );
        }
    }

    /// The legal terminal shape of one interaction revision.
    enum Terminal {
        Pending,
        Resolved(Option<String>),
        Cancelled,
    }
    let mut parents: BTreeMap<String, Vec<ContinuationParent>> = BTreeMap::new();
    for (item_id, revisions) in ledger {
        let mut request: Option<InteractionRequest> = None;
        let mut previous: Option<Terminal> = None;
        let mut newest: Option<(Option<String>, String, u64)> = None;
        // Fold the revisions in their own ascending order: a real interaction is written once as
        // pending and once as terminal, so the parent claim is the latest legal revision only.
        for revision in revisions.values() {
            if let Some(first) = &request {
                ensure!(
                    *first == revision.request,
                    "interaction receipt {item_id} changed its request identity"
                );
            } else {
                request = Some(revision.request.clone());
            }
            let terminal = match &revision.state {
                InteractionState::Pending => Terminal::Pending,
                InteractionState::Resolved(_) => Terminal::Resolved(revision.continuation.clone()),
                InteractionState::Cancelled => Terminal::Cancelled,
            };
            match &previous {
                None => {}
                Some(Terminal::Pending) => ensure!(
                    !matches!(&terminal, Terminal::Pending),
                    "interaction receipt {item_id} repeats a pending revision"
                ),
                Some(Terminal::Resolved(continuation)) => ensure!(
                    matches!(&terminal, Terminal::Resolved(next) if next == continuation),
                    "interaction receipt {item_id} reached conflicting terminal revisions"
                ),
                Some(Terminal::Cancelled) => {
                    anyhow::bail!("interaction receipt {item_id} has a revision after cancellation")
                }
            }
            newest = Some((
                revision.continuation.clone(),
                revision.request.turn_id.clone(),
                revision.write_sequence,
            ));
            previous = Some(terminal);
        }
        let Some((continuation, turn_id, _write_sequence)) = newest else {
            continue;
        };
        let Some(input_id) = continuation else {
            continue;
        };
        parents
            .entry(input_id)
            .or_default()
            .push(ContinuationParent { turn_id });
    }
    Ok(Hop::Ready(ContinuationLedger { parents, controls }))
}

#[cfg(test)]
mod tests {
    use super::super::{
        EffectCommit, FactReceiptWrite, HistoryStore, InputIdentityWrite, statement,
    };
    use super::{
        InputChainBatch, InputChainBatchRead, InputChainProof, InputChainReadLimits,
        InputChainUnavailable, TurnInputChain,
    };
    use crate::studio::audience_start::{RECEIPT_REVISION, TURN_START_RECEIPT, TurnStartReceipt};
    use crate::studio::storage::state::InputIdentityEntry;
    use crate::studio::thread_projection::order::receipt_id;
    use anyhow::{Context, Result};
    use pl_core::context::OpaquePayload;
    use pl_core::thread::input::{InputContinuation, InputIdentity, InputPurpose, InputState};
    use pl_core::thread::interactions::{
        InteractionRecord, InteractionRequest, InteractionResponse, InteractionState,
    };
    use sea_orm::{ConnectionTrait, TransactionTrait};
    use std::collections::{BTreeMap, BTreeSet};

    impl HistoryStore {
        // Test-only one-request view of the actual batch API; no obsolete production port remains.
        async fn single_input_chain(&self, turn: &str) -> Result<InputChainProof> {
            self.single_input_chain_within(
                turn,
                super::InputChainReadLimits::new(super::ROW_BUDGET, super::BYTE_BUDGET)?,
            )
            .await
        }

        async fn single_input_chain_within(
            &self,
            turn: &str,
            limits: super::InputChainReadLimits,
        ) -> Result<InputChainProof> {
            match self
                .input_chains_for_turns(&[turn.to_owned()], limits)
                .await?
            {
                super::InputChainBatchRead::Ready(mut batch) => batch
                    .by_turn
                    .remove(turn)
                    .context("batch omitted its requested Turn"),
                super::InputChainBatchRead::Unavailable(reason) => {
                    Ok(InputChainProof::Unavailable(reason))
                }
            }
        }
    }

    fn budget(rows: u64, bytes: u64) -> super::InputChainReadLimits {
        super::InputChainReadLimits::new(rows, bytes)
            .expect("fixture limits stay within production ceilings")
    }

    fn identity(input_id: &str, turn_id: &str, sequence: u64) -> InputIdentityWrite {
        identity_with(input_id, turn_id, sequence, InputPurpose::Message, None)
    }

    /// One identity write with the purpose and continuation the original admission really had.
    fn identity_with(
        input_id: &str,
        turn_id: &str,
        sequence: u64,
        purpose: InputPurpose,
        continuation: Option<InputContinuation>,
    ) -> InputIdentityWrite {
        let mut entry = InputIdentityEntry::new(
            InputIdentity {
                purpose,
                continuation,
                id: input_id.to_owned(),
                ordinal: sequence,
                revision: 1,
                digest: format!("digest-{input_id}"),
                delivery: Default::default(),
                state: InputState::Consumed {
                    turn_id: turn_id.to_owned(),
                    attempt_id: "attempt".into(),
                },
            },
            sequence,
        );
        // These fixtures own the original control admission at revision1, just like the real
        // control producer. Later lifecycle revisions must not replace that immutable fact.
        if entry.purpose == InputPurpose::Continuation {
            entry.continuation_admission_revision = Some(entry.revision);
        }
        InputIdentityWrite {
            entry,
            request_digest: Some(format!("request-{input_id}")),
            presentation: pl_protocol::MessagePresentation::Visible,
        }
    }

    /// The answer an interaction produces: an ordinary message body carrying the interaction's own
    /// opaque payload, admitted without a continuation of its own and hidden from the transcript.
    fn answer_identity(input_id: &str, turn_id: &str, sequence: u64) -> InputIdentityWrite {
        InputIdentityWrite {
            presentation: pl_protocol::MessagePresentation::Hidden,
            ..identity(input_id, turn_id, sequence)
        }
    }

    /// A framework control input that resumes an interaction: its own purpose, its own identity and
    /// the point it continues. Ancestry still comes only from the interaction receipt, never from
    /// these fields.
    fn control_identity(
        input_id: &str,
        turn_id: &str,
        sequence: u64,
        point_id: &str,
        source_turn: &str,
    ) -> InputIdentityWrite {
        identity_with(
            input_id,
            turn_id,
            sequence,
            InputPurpose::Continuation,
            Some(InputContinuation {
                point_id: point_id.to_owned(),
                source_turn_id: Some(source_turn.to_owned()),
            }),
        )
    }

    fn turn_start(
        thread_id: &str,
        turn_id: &str,
        input_id: &str,
        sequence: u64,
    ) -> FactReceiptWrite {
        FactReceiptWrite {
            item_id: receipt_id(TURN_START_RECEIPT, turn_id),
            revision: RECEIPT_REVISION,
            kind: TURN_START_RECEIPT,
            payload: serde_json::to_string(&TurnStartReceipt {
                version: 1,
                thread_id: thread_id.to_owned(),
                turn_id: turn_id.to_owned(),
                input_id: Some(input_id.to_owned()),
                sequence,
            })
            .expect("encode Turn start receipt"),
        }
    }

    fn interaction_receipt(
        thread_id: &str,
        interaction_id: &str,
        turn_id: &str,
        revision: u64,
        state: InteractionState,
        continuation: Option<&str>,
        question: &str,
    ) -> FactReceiptWrite {
        let request = InteractionRequest {
            id: interaction_id.to_owned(),
            turn_id: turn_id.to_owned(),
            payload: OpaquePayload::new(
                "pl.tool.user-input",
                1,
                serde_json::to_string(&serde_json::json!({
                    "threadId": thread_id,
                    "question": question,
                }))
                .expect("interaction request payload"),
            )
            .expect("interaction request"),
        };
        let record = InteractionRecord {
            created_at: 1,
            updated_at: 1,
            continuation_id: continuation.map(str::to_owned),
            request,
            revision,
            state,
            extension_mutations: Vec::new(),
        };
        FactReceiptWrite {
            item_id: receipt_id("interaction", interaction_id),
            revision: record.revision,
            kind: "interaction",
            payload: serde_json::to_string(&record).expect("encode interaction receipt"),
        }
    }

    fn pending_receipt(
        thread_id: &str,
        interaction_id: &str,
        turn_id: &str,
        revision: u64,
    ) -> FactReceiptWrite {
        interaction_receipt(
            thread_id,
            interaction_id,
            turn_id,
            revision,
            InteractionState::Pending,
            None,
            "question",
        )
    }

    fn resolved_receipt(
        thread_id: &str,
        interaction_id: &str,
        turn_id: &str,
        continuation: &str,
        revision: u64,
    ) -> FactReceiptWrite {
        resolved_receipt_with_question(
            thread_id,
            interaction_id,
            turn_id,
            continuation,
            revision,
            "question",
        )
    }

    fn resolved_receipt_with_question(
        thread_id: &str,
        interaction_id: &str,
        turn_id: &str,
        continuation: &str,
        revision: u64,
        question: &str,
    ) -> FactReceiptWrite {
        interaction_receipt(
            thread_id,
            interaction_id,
            turn_id,
            revision,
            resolved_state(),
            Some(continuation),
            question,
        )
    }

    fn resolved_state() -> InteractionState {
        InteractionState::Resolved(InteractionResponse {
            payload: OpaquePayload::new("pl.tool.user-input", 1, "{}".to_owned())
                .expect("interaction payload"),
            context: Vec::new(),
        })
    }

    fn continuation_receipt(
        thread_id: &str,
        interaction_id: &str,
        turn_id: &str,
        continuation: &str,
        revision: u64,
    ) -> FactReceiptWrite {
        resolved_receipt(thread_id, interaction_id, turn_id, continuation, revision)
    }

    /// Filler ledger rows of another kind: they are scan work without being interaction parents.
    fn filler_receipts(count: usize) -> Vec<FactReceiptWrite> {
        (0..count)
            .map(|index| FactReceiptWrite {
                item_id: receipt_id("permission", &format!("filler-{index}")),
                revision: 1,
                kind: "permission",
                payload: "{}".to_owned(),
            })
            .collect()
    }

    async fn commit(
        store: &HistoryStore,
        sequence: u64,
        identities: &[InputIdentityWrite],
        receipts: &[FactReceiptWrite],
    ) -> Result<()> {
        // This helper is the logical creator of these synthetic new-history fixtures. Production
        // commits never infer New from file existence.
        store
            .initialize(super::super::HistoryInitialization::New)
            .await?;
        store
            .commit_effect(
                sequence,
                EffectCommit {
                    items: &[],
                    rolled_back_turns: &Default::default(),
                    identities,
                    messages: &[],
                    receipts,
                    tasks: &[],
                    deliveries: &[],
                    delivery_repairs: &[],
                    attempt: None,
                },
            )
            .await
    }

    /// A plain GUI input is its own root, and proving it needs no body: this fixture never stores one.
    #[tokio::test]
    async fn gui_root_input_is_proven_without_any_stored_body() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let store = HistoryStore::open(&directory.path().join("history.sqlite"), "chain").await?;
        let identities = [identity("gui-1", "turn-1", 1)];
        commit(
            &store,
            1,
            &identities,
            &[turn_start("chain", "turn-1", "gui-1", 1)],
        )
        .await?;

        assert_eq!(
            store.single_input_chain("turn-1").await?,
            InputChainProof::Proven(TurnInputChain {
                turn_id: "turn-1".into(),
                start_sequence: 1,
                input_id: "gui-1".into(),
                continuation_ancestors: Vec::new(),
            })
        );
        let connection = store.writer().await?;
        let row = connection
            .db
            .query_one_raw(statement(
                "SELECT COUNT(*) AS total FROM history_items",
                vec![],
            ))
            .await?
            .context("item count")?;
        assert_eq!(
            row.try_get::<i64>("", "total")?,
            0,
            "chain proof must not depend on stored bodies"
        );
        Ok(())
    }

    /// Two continuation hops are listed nearest-first, and the root GUI input closes the chain.
    #[tokio::test]
    async fn continuation_ancestors_are_complete_and_ordered() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let store = HistoryStore::open(&directory.path().join("history.sqlite"), "chain").await?;
        commit(
            &store,
            1,
            &[identity("gui-1", "turn-1", 1)],
            &[turn_start("chain", "turn-1", "gui-1", 1)],
        )
        .await?;
        commit(
            &store,
            2,
            &[answer_identity("ask-1:continuation", "turn-2", 2)],
            &[
                continuation_receipt("chain", "ask-1", "turn-1", "ask-1:continuation", 2),
                turn_start("chain", "turn-2", "ask-1:continuation", 2),
            ],
        )
        .await?;
        commit(
            &store,
            3,
            &[answer_identity("ask-2:continuation", "turn-3", 3)],
            &[
                continuation_receipt("chain", "ask-2", "turn-2", "ask-2:continuation", 2),
                turn_start("chain", "turn-3", "ask-2:continuation", 3),
            ],
        )
        .await?;

        assert_eq!(
            store.single_input_chain("turn-3").await?,
            InputChainProof::Proven(TurnInputChain {
                turn_id: "turn-3".into(),
                start_sequence: 3,
                input_id: "ask-2:continuation".into(),
                continuation_ancestors: vec!["ask-1:continuation".into(), "gui-1".into()],
            })
        );
        Ok(())
    }

    #[tokio::test]
    async fn hidden_input_without_a_parent_receipt_is_unavailable() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let store = HistoryStore::open(&directory.path().join("history.sqlite"), "chain").await?;
        commit(
            &store,
            1,
            &[answer_identity("orphan:continuation", "turn-1", 1)],
            &[turn_start("chain", "turn-1", "orphan:continuation", 1)],
        )
        .await?;
        assert_eq!(
            store.single_input_chain("turn-1").await?,
            InputChainProof::Unavailable(InputChainUnavailable::UnprovenParent)
        );
        Ok(())
    }

    /// A visible control input is still never a root: without a committed interaction receipt that
    /// names it, its ancestry is unproven, and its own point/source fields never establish one.
    fn control_admission(
        thread_id: &str,
        input_id: &str,
        sequence: u64,
        revision: u64,
        point_id: &str,
        source_turn_id: Option<&str>,
    ) -> FactReceiptWrite {
        let receipt = super::ControlAdmissionReceipt {
            version: super::CONTROL_ADMISSION_VERSION,
            thread_id: thread_id.to_owned(),
            input_id: input_id.to_owned(),
            admission_sequence: sequence,
            admission_revision: revision,
            point_id: point_id.to_owned(),
            source_turn_id: source_turn_id.map(str::to_owned),
        };
        FactReceiptWrite {
            item_id: receipt.receipt_id(),
            revision: super::CONTROL_ADMISSION_REVISION,
            kind: super::CONTROL_ADMISSION_RECEIPT,
            payload: serde_json::to_string(&receipt).expect("encode control admission"),
        }
    }

    /// One store with a stopped Turn and the control input that continued it.
    async fn control_store() -> Result<(tempfile::TempDir, HistoryStore)> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let store = HistoryStore::open(&path, "chain").await?;
        commit(
            &store,
            1,
            &[identity("gui-1", "turn-0", 1)],
            &[turn_start("chain", "turn-0", "gui-1", 1)],
        )
        .await?;
        commit(
            &store,
            2,
            &[control_identity(
                "control-1",
                "turn-1",
                2,
                "control-point",
                "turn-0",
            )],
            &[
                turn_start("chain", "turn-1", "control-1", 2),
                control_admission("chain", "control-1", 2, 1, "control-point", Some("turn-0")),
            ],
        )
        .await?;
        Ok((directory, store))
    }

    /// A control input is proven by its own immutable admission: the chain walks back to the Turn the
    /// point came from, and a re-saved receipt (its re-writable watermark moves) changes nothing.
    #[tokio::test]
    async fn control_admission_receipt_proves_the_source_chain() -> Result<()> {
        let (directory, store) = control_store().await?;
        let expected = InputChainProof::Proven(TurnInputChain {
            turn_id: "turn-1".into(),
            start_sequence: 2,
            input_id: "control-1".into(),
            continuation_ancestors: vec!["gui-1".into()],
        });
        assert_eq!(store.single_input_chain("turn-1").await?, expected);
        raw_execute(
            &directory.path().join("history.sqlite"),
            "UPDATE history_fact_receipts SET last_write_seq=1 WHERE kind='control-admission'",
        )
        .await?;
        assert_eq!(store.single_input_chain("turn-1").await?, expected);
        Ok(())
    }

    /// A later consumed-state revision is legal, but it cannot substitute for the immutable first
    /// admission fact. Missing or contradictory first revisions reject the entire real batch.
    #[tokio::test]
    async fn control_first_admission_revision_is_required_and_immutable_in_batch_proofs()
    -> Result<()> {
        let (directory, store) = control_store().await?;
        let mut later = control_identity("control-1", "turn-1", 2, "control-point", "turn-0");
        later.entry.revision = 5;
        commit(&store, 3, &[later], &[]).await?;
        let turns = vec!["turn-0".to_owned(), "turn-1".to_owned()];
        let limits = InputChainReadLimits::new(super::ROW_BUDGET, super::BYTE_BUDGET)?;
        let expected = store.input_chains_for_turns(&turns, limits).await?;
        let InputChainBatchRead::Ready(batch) = &expected else {
            anyhow::bail!("legal later revision was not proven")
        };
        assert_eq!(
            batch.by_turn["turn-1"],
            InputChainProof::Proven(TurnInputChain {
                turn_id: "turn-1".into(),
                start_sequence: 2,
                input_id: "control-1".into(),
                continuation_ancestors: vec!["gui-1".into()],
            })
        );
        let db = &store.writer().await?.db;
        let original = db
            .query_one_raw(statement(
                "SELECT payload FROM history_input_identities WHERE item_id='control-1'",
                vec![],
            ))
            .await?
            .context("saved control identity")?
            .try_get::<String>("", "payload")?;
        let encoded: serde_json::Value = serde_json::from_str(&original)?;
        assert_eq!(encoded["revision"], 5);
        assert_eq!(encoded["continuationAdmissionRevision"], 1);
        for first in [None, Some(2_u64)] {
            let mut changed = encoded.clone();
            if let Some(first) = first {
                changed["continuationAdmissionRevision"] = first.into();
            } else {
                changed
                    .as_object_mut()
                    .context("identity object")?
                    .remove("continuationAdmissionRevision");
            }
            db.execute_raw(statement(
                "UPDATE history_input_identities SET payload=? WHERE item_id='control-1'",
                vec![serde_json::to_string(&changed)?.into()],
            ))
            .await?;
            let broken = super::super::test_support::source_evidence(
                &directory.path().join("history.sqlite"),
            )
            .await?;
            let failure = store
                .input_chains_for_turns(&turns, limits)
                .await
                .expect_err(
                    "current revision5 must not hide a missing or contradictory first revision",
                );
            assert!(
                format!("{failure:#}").contains("immutable first-admission revision"),
                "{failure:#}"
            );
            assert_eq!(
                super::super::test_support::source_evidence(
                    &directory.path().join("history.sqlite")
                )
                .await?,
                broken
            );
            db.execute_raw(statement(
                "UPDATE history_input_identities SET payload=? WHERE item_id='control-1'",
                vec![original.clone().into()],
            ))
            .await?;
            assert_eq!(
                store.input_chains_for_turns(&turns, limits).await?,
                expected
            );
        }
        Ok(())
    }

    /// A control that declares no source Turn keeps its legal admission but cannot prove ancestry:
    /// it is never reported as a root and never as a truncated proven chain.
    #[tokio::test]
    async fn control_admission_without_a_source_turn_is_unavailable() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let store = HistoryStore::open(&path, "chain").await?;
        commit(
            &store,
            1,
            // A control whose admission declared no source Turn keeps that same absence in its own
            // identity: the two facts must agree.
            &[identity_with(
                "control-1",
                "turn-1",
                1,
                InputPurpose::Continuation,
                Some(InputContinuation {
                    point_id: "control-point".into(),
                    source_turn_id: None,
                }),
            )],
            &[
                turn_start("chain", "turn-1", "control-1", 1),
                control_admission("chain", "control-1", 1, 1, "control-point", None),
            ],
        )
        .await?;
        assert_eq!(
            store.single_input_chain("turn-1").await?,
            InputChainProof::Unavailable(InputChainUnavailable::UnprovenParent)
        );
        Ok(())
    }

    /// A discarded control never opened its Turn.
    #[tokio::test]
    async fn discarded_control_input_is_refused() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let store = HistoryStore::open(&path, "chain").await?;
        commit(
            &store,
            1,
            &[identity("gui-1", "turn-0", 1)],
            &[turn_start("chain", "turn-0", "gui-1", 1)],
        )
        .await?;
        let mut discarded = control_identity("control-1", "turn-1", 2, "control-point", "turn-0");
        discarded.entry.state = InputState::Discarded;
        commit(
            &store,
            2,
            &[discarded],
            &[
                turn_start("chain", "turn-1", "control-1", 2),
                control_admission("chain", "control-1", 2, 1, "control-point", Some("turn-0")),
            ],
        )
        .await?;
        assert!(
            store.single_input_chain("turn-1").await.is_err(),
            "a discarded input cannot have opened its Turn"
        );
        Ok(())
    }

    /// A tampered admission payload is an integrity error, not a weaker proof.
    #[tokio::test]
    async fn damaged_control_admission_is_an_error() -> Result<()> {
        let (directory, store) = control_store().await?;
        raw_execute(
            &directory.path().join("history.sqlite"),
            "UPDATE history_fact_receipts SET payload=replace(payload,'control-point','other-point')              WHERE kind='control-admission'",
        )
        .await?;
        assert!(store.single_input_chain("turn-1").await.is_err());
        Ok(())
    }

    #[tokio::test]
    async fn control_input_without_a_parent_receipt_is_unavailable() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let store = HistoryStore::open(&directory.path().join("history.sqlite"), "chain").await?;
        commit(
            &store,
            1,
            &[identity("gui-1", "turn-0", 1)],
            &[turn_start("chain", "turn-0", "gui-1", 1)],
        )
        .await?;
        commit(
            &store,
            2,
            &[control_identity(
                "ask-1:control",
                "turn-1",
                2,
                "ask-1",
                "turn-0",
            )],
            &[turn_start("chain", "turn-1", "ask-1:control", 2)],
        )
        .await?;
        assert_eq!(
            store.single_input_chain("turn-1").await?,
            InputChainProof::Unavailable(InputChainUnavailable::UnprovenParent)
        );

        // An interaction receipt that merely names this input never proves a control: only the
        // control's own admission receipt can.
        commit(
            &store,
            3,
            &[],
            &[resolved_receipt(
                "chain",
                "ask-1",
                "turn-0",
                "ask-1:control",
                3,
            )],
        )
        .await?;
        assert!(
            store.single_input_chain("turn-1").await.is_err(),
            "an interaction claim must not stand in for a control admission"
        );
        Ok(())
    }

    /// A receipt whose identity and kind agree but whose kind this build never writes could be a
    /// parent edge this proof cannot interpret, so it fails closed instead of being skipped.
    #[tokio::test]
    async fn unknown_receipt_kind_is_unavailable() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let store = HistoryStore::open(&directory.path().join("history.sqlite"), "chain").await?;
        let receipt = FactReceiptWrite {
            item_id: receipt_id("watch", "watch-1"),
            revision: 1,
            kind: "watch",
            payload: "{\"state\":\"pending\"}".into(),
        };
        commit(
            &store,
            1,
            &[identity("gui-1", "turn-1", 1)],
            &[turn_start("chain", "turn-1", "gui-1", 1), receipt],
        )
        .await?;
        assert_eq!(
            store.single_input_chain("turn-1").await?,
            InputChainProof::Unavailable(InputChainUnavailable::UnsupportedHistory)
        );
        Ok(())
    }

    #[tokio::test]
    async fn two_interactions_claiming_one_continuation_are_ambiguous() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let store = HistoryStore::open(&directory.path().join("history.sqlite"), "chain").await?;
        commit(
            &store,
            1,
            &[identity("gui-1", "turn-1", 1)],
            &[turn_start("chain", "turn-1", "gui-1", 1)],
        )
        .await?;
        commit(
            &store,
            2,
            &[answer_identity("shared:continuation", "turn-2", 2)],
            &[
                continuation_receipt("chain", "ask-a", "turn-1", "shared:continuation", 1),
                continuation_receipt("chain", "ask-b", "turn-1", "shared:continuation", 1),
                turn_start("chain", "turn-2", "shared:continuation", 2),
            ],
        )
        .await?;
        assert_eq!(
            store.single_input_chain("turn-2").await?,
            InputChainProof::Unavailable(InputChainUnavailable::Ambiguous)
        );
        Ok(())
    }

    /// A real interaction is written once as pending and once as resolved: the latest legal revision
    /// is the single parent claim, a repeated identical terminal keeps that parent, and a terminal
    /// revision that later changes — or any revision after cancellation — is contradictory data.
    #[tokio::test]
    async fn interaction_lifecycle_normalises_revisions_into_one_parent() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let store = HistoryStore::open(&directory.path().join("history.sqlite"), "chain").await?;
        commit(
            &store,
            1,
            &[identity("gui-1", "turn-1", 1)],
            &[turn_start("chain", "turn-1", "gui-1", 1)],
        )
        .await?;
        commit(
            &store,
            2,
            &[],
            &[pending_receipt("chain", "ask-1", "turn-1", 1)],
        )
        .await?;
        commit(
            &store,
            3,
            &[],
            &[resolved_receipt(
                "chain",
                "ask-1",
                "turn-1",
                "ask-1:continuation",
                2,
            )],
        )
        .await?;
        commit(
            &store,
            4,
            &[answer_identity("ask-1:continuation", "turn-2", 4)],
            &[turn_start("chain", "turn-2", "ask-1:continuation", 4)],
        )
        .await?;
        let proven = InputChainProof::Proven(TurnInputChain {
            turn_id: "turn-2".into(),
            start_sequence: 4,
            input_id: "ask-1:continuation".into(),
            continuation_ancestors: vec!["gui-1".into()],
        });
        assert_eq!(store.single_input_chain("turn-2").await?, proven);
        // Re-committing the identical terminal revision keeps the same single parent.
        commit(
            &store,
            5,
            &[],
            &[resolved_receipt(
                "chain",
                "ask-1",
                "turn-1",
                "ask-1:continuation",
                2,
            )],
        )
        .await?;
        assert_eq!(store.single_input_chain("turn-2").await?, proven);
        // A content-identical re-save of the same revision moves the mutable watermark past the
        // child input's admission (4) while payload, digest and the proven edge stay identical. The
        // edge therefore comes from the receipt's own trusted content plus the immutable Turn
        // starts, not from `last_write_seq`.
        let moved = store
            .writer()
            .await?
            .db
            .query_one_raw(statement(
                "SELECT MAX(last_write_seq) AS moved FROM history_fact_receipts \
                 WHERE kind='interaction'",
                vec![],
            ))
            .await?
            .context("interaction watermark")?
            .try_get::<i64>("", "moved")?;
        assert!(
            moved > 4,
            "the re-saved receipt watermark must move past the child admission, got {moved}"
        );
        // A terminal revision that later claims another continuation is contradictory.
        commit(
            &store,
            6,
            &[],
            &[resolved_receipt(
                "chain",
                "ask-1",
                "turn-1",
                "other:continuation",
                3,
            )],
        )
        .await?;
        let error = store
            .single_input_chain("turn-2")
            .await
            .expect_err("a changed terminal continuation must not prove a parent");
        assert!(
            error.to_string().contains("conflicting terminal revisions"),
            "{error}"
        );

        let cancelled = tempfile::tempdir()?;
        let store = HistoryStore::open(&cancelled.path().join("history.sqlite"), "chain").await?;
        commit(
            &store,
            1,
            &[answer_identity("ask-9:continuation", "turn-2", 1)],
            &[
                pending_receipt("chain", "ask-9", "turn-1", 1),
                interaction_receipt(
                    "chain",
                    "ask-9",
                    "turn-1",
                    2,
                    InteractionState::Cancelled,
                    None,
                    "question",
                ),
                resolved_receipt("chain", "ask-9", "turn-1", "ask-9:continuation", 3),
                turn_start("chain", "turn-2", "ask-9:continuation", 1),
            ],
        )
        .await?;
        let error = store
            .single_input_chain("turn-2")
            .await
            .expect_err("a revision after cancellation must not prove a parent");
        assert!(
            error.to_string().contains("revision after cancellation"),
            "{error}"
        );

        // A later revision that renames the interaction's own request is a conflicting parent.
        let renamed = tempfile::tempdir()?;
        let store = HistoryStore::open(&renamed.path().join("history.sqlite"), "chain").await?;
        commit(
            &store,
            1,
            &[answer_identity("ask-7:continuation", "turn-2", 1)],
            &[
                resolved_receipt("chain", "ask-7", "turn-1", "ask-7:continuation", 1),
                interaction_receipt(
                    "chain",
                    "ask-7",
                    "turn-9",
                    2,
                    resolved_state(),
                    Some("ask-7:continuation"),
                    "question",
                ),
                turn_start("chain", "turn-2", "ask-7:continuation", 1),
            ],
        )
        .await?;
        let error = store
            .single_input_chain("turn-2")
            .await
            .expect_err("a renamed parent identity must not prove a parent");
        assert!(
            error.to_string().contains("changed its request identity"),
            "{error}"
        );
        Ok(())
    }

    /// A parent Turn that started after its child Turn is contradictory data, never a proven edge.
    #[tokio::test]
    async fn future_parent_edge_is_an_error() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let store = HistoryStore::open(&directory.path().join("history.sqlite"), "chain").await?;
        commit(
            &store,
            1,
            &[answer_identity("late:continuation", "turn-2", 1)],
            &[turn_start("chain", "turn-2", "late:continuation", 1)],
        )
        .await?;
        commit(
            &store,
            2,
            &[identity("gui-1", "turn-1", 2)],
            &[
                continuation_receipt("chain", "ask-1", "turn-1", "late:continuation", 2),
                turn_start("chain", "turn-1", "gui-1", 2),
            ],
        )
        .await?;
        let error = store
            .single_input_chain("turn-2")
            .await
            .expect_err("a future parent edge must not prove ownership");
        assert!(
            error
                .to_string()
                .contains("did not start before its child Turn"),
            "{error}"
        );
        Ok(())
    }

    #[tokio::test]
    async fn turn_without_start_receipt_is_unavailable() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let store = HistoryStore::open(&directory.path().join("history.sqlite"), "chain").await?;
        commit(&store, 1, &[identity("gui-1", "turn-1", 1)], &[]).await?;
        assert_eq!(
            store.single_input_chain("turn-1").await?,
            InputChainProof::Unavailable(InputChainUnavailable::NoTurnStart)
        );
        Ok(())
    }

    /// One store with a GUI root and one resolved continuation parent.
    async fn chain_store() -> Result<(tempfile::TempDir, HistoryStore)> {
        let directory = tempfile::tempdir()?;
        let store = HistoryStore::open(&directory.path().join("history.sqlite"), "chain").await?;
        commit(
            &store,
            1,
            &[identity("gui-1", "turn-1", 1)],
            &[turn_start("chain", "turn-1", "gui-1", 1)],
        )
        .await?;
        commit(
            &store,
            2,
            &[answer_identity("ask-1:continuation", "turn-2", 2)],
            &[
                resolved_receipt("chain", "ask-1", "turn-1", "ask-1:continuation", 2),
                turn_start("chain", "turn-2", "ask-1:continuation", 2),
            ],
        )
        .await?;
        Ok((directory, store))
    }

    /// Applies one statement through an independent connection, so the store handle keeps whatever
    /// structure version it already cached.
    async fn raw_execute(path: &std::path::Path, sql: &str) -> Result<()> {
        let db = sea_orm::Database::connect(
            crate::studio::paths::sqlite_file_options(
                path,
                crate::studio::paths::SqliteFileMode::Create,
                |options| options,
            )
            .await?,
        )
        .await?;
        db.execute_unprepared(sql).await?;
        db.close().await?;
        Ok(())
    }

    /// A damaged durable fact is a persistent-data failure, never "no proof": each receipt table
    /// carries its own digest and its own revision, and duplicated identity columns must agree with
    /// the payload they were written with.
    #[tokio::test]
    async fn damaged_receipt_digest_stays_an_error() -> Result<()> {
        let (_directory, store) = chain_store().await?;
        store
            .writer()
            .await?
            .db
            .execute_unprepared(
                "UPDATE history_fact_receipts SET digest='tampered' WHERE kind='turn-start'",
            )
            .await?;
        let error = store
            .single_input_chain("turn-2")
            .await
            .expect_err("a tampered start receipt must not become unavailable");
        assert!(
            error
                .to_string()
                .contains("Turn start receipt turn-2 payload digest mismatch"),
            "{error}"
        );

        let (_directory, store) = chain_store().await?;
        store
            .writer()
            .await?
            .db
            .execute_unprepared(
                "UPDATE history_fact_receipts SET digest='tampered' WHERE kind='interaction'",
            )
            .await?;
        let error = store
            .single_input_chain("turn-2")
            .await
            .expect_err("a rewritten parent receipt must not pass");
        assert!(
            error.to_string().contains("interaction receipt")
                && error.to_string().contains("payload digest mismatch")
                && error.to_string().contains("ask-1"),
            "{error}"
        );

        let (_directory, store) = chain_store().await?;
        store
            .writer()
            .await?
            .db
            .execute_unprepared(
                "UPDATE history_fact_receipts SET revision=7 WHERE kind='interaction'",
            )
            .await?;
        let error = store
            .single_input_chain("turn-2")
            .await
            .expect_err("a payload stored under another revision must not pass");
        assert!(
            error
                .to_string()
                .contains("revision conflicts with its stored row"),
            "{error}"
        );

        let (_directory, store) = chain_store().await?;
        store
            .writer()
            .await?
            .db
            .execute_unprepared(
                "UPDATE history_input_identities SET ordinal=99 WHERE item_id='ask-1:continuation'",
            )
            .await?;
        let error = store
            .single_input_chain("turn-2")
            .await
            .expect_err("identity columns must agree with their payload");
        assert!(
            error
                .to_string()
                .contains("conflicts with its durable record"),
            "{error}"
        );

        // A real chain is proven first; then only the parent receipt's `kind` is rewritten while its
        // payload and digest stay intact. A silently skipped interaction would turn a *visible*
        // continuation into an unproven root, so the tampered kind must surface as damage.
        let directory = tempfile::tempdir()?;
        let store = HistoryStore::open(&directory.path().join("history.sqlite"), "chain").await?;
        commit(
            &store,
            1,
            &[identity("gui-1", "turn-1", 1)],
            &[turn_start("chain", "turn-1", "gui-1", 1)],
        )
        .await?;
        commit(
            &store,
            2,
            // A continuation input may legally be visible, so it cannot be used as the marker.
            &[identity("ask-1:continuation", "turn-2", 2)],
            &[
                resolved_receipt("chain", "ask-1", "turn-1", "ask-1:continuation", 2),
                turn_start("chain", "turn-2", "ask-1:continuation", 2),
            ],
        )
        .await?;
        assert_eq!(
            store.single_input_chain("turn-2").await?,
            InputChainProof::Proven(TurnInputChain {
                turn_id: "turn-2".into(),
                start_sequence: 2,
                input_id: "ask-1:continuation".into(),
                continuation_ancestors: vec!["gui-1".into()],
            })
        );
        store
            .writer()
            .await?
            .db
            .execute_unprepared(
                "UPDATE history_fact_receipts SET kind='permission' WHERE kind='interaction'",
            )
            .await?;
        let error = store
            .single_input_chain("turn-2")
            .await
            .expect_err("a receipt stored under another kind must not become an absent parent");
        assert!(
            error.to_string().contains("does not match its stored kind"),
            "{error}"
        );
        Ok(())
    }

    /// Repeated candidates and different Turns share a single ledger scan. Exactly enough budget
    /// for that scan plus all hops succeeds; repeating the scan or resetting totals cannot pass.
    #[tokio::test]
    async fn batch_proofs_share_one_ledger_and_cumulative_limits_without_partial_ready()
    -> Result<()> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history-current.sqlite");
        let store = HistoryStore::open(&path, "chain").await?;
        commit(
            &store,
            1,
            &[identity("gui-1", "turn-1", 1)],
            &[turn_start("chain", "turn-1", "gui-1", 1)],
        )
        .await?;
        commit(
            &store,
            2,
            &[answer_identity("ask-1:continuation", "turn-2", 2)],
            &[
                resolved_receipt("chain", "ask-1", "turn-1", "ask-1:continuation", 2),
                turn_start("chain", "turn-2", "ask-1:continuation", 2),
            ],
        )
        .await?;
        commit(
            &store,
            3,
            &[identity("gui-3", "turn-3", 3)],
            &[turn_start("chain", "turn-3", "gui-3", 3)],
        )
        .await?;
        commit(&store, 4, &[], &filler_receipts(300)).await?;
        let db = &store.writer().await?.db;
        let sized = db.query_one_raw(statement(
            "SELECT (SELECT COUNT(*) FROM history_fact_receipts) AS ledger_rows,
              (SELECT COALESCE(SUM(length(CAST(payload AS BLOB))),0) FROM history_fact_receipts WHERE kind IN ('interaction','control-admission'))
              + (SELECT COALESCE(SUM(length(CAST(payload AS BLOB))*CASE WHEN item_id=? THEN 2 ELSE 1 END),0) FROM history_fact_receipts WHERE kind='turn-start')
              + (SELECT COALESCE(SUM(length(CAST(payload AS BLOB))*CASE WHEN item_id='gui-1' THEN 2 ELSE 1 END),0) FROM history_input_identities) AS payload_bytes",
            vec![receipt_id(TURN_START_RECEIPT, "turn-1").into()],
        )).await?.context("batch work sizes")?;
        let ledger = u64::try_from(sized.try_get::<i64>("", "ledger_rows")?)?;
        let bytes = u64::try_from(sized.try_get::<i64>("", "payload_bytes")?)?;
        // meta + whole ledger + root(2) + child including ancestor(4) + independent root(2).
        let rows = 1 + ledger + 8;
        assert!(ledger > super::PAGE_ROWS);
        let requests = ["turn-1", "turn-2", "turn-3"]
            .into_iter()
            .cycle()
            .take(100)
            .map(str::to_owned)
            .collect::<Vec<_>>();
        let expected = InputChainBatch {
            by_turn: BTreeMap::from([
                (
                    "turn-1".into(),
                    InputChainProof::Proven(TurnInputChain {
                        turn_id: "turn-1".into(),
                        start_sequence: 1,
                        input_id: "gui-1".into(),
                        continuation_ancestors: vec![],
                    }),
                ),
                (
                    "turn-2".into(),
                    InputChainProof::Proven(TurnInputChain {
                        turn_id: "turn-2".into(),
                        start_sequence: 2,
                        input_id: "ask-1:continuation".into(),
                        continuation_ancestors: vec!["gui-1".into()],
                    }),
                ),
                (
                    "turn-3".into(),
                    InputChainProof::Proven(TurnInputChain {
                        turn_id: "turn-3".into(),
                        start_sequence: 3,
                        input_id: "gui-3".into(),
                        continuation_ancestors: vec![],
                    }),
                ),
            ]),
            rows_read: rows,
            bytes_read: bytes,
        };
        assert_eq!(
            store
                .input_chains_for_turns(&requests, budget(rows, bytes))
                .await?,
            InputChainBatchRead::Ready(expected)
        );
        for limits in [
            budget(rows - 1, bytes),
            budget(rows, bytes - 1),
            budget(0, bytes),
            budget(rows, 0),
        ] {
            assert_eq!(
                store.input_chains_for_turns(&requests, limits).await?,
                InputChainBatchRead::Unavailable(InputChainUnavailable::BudgetExhausted),
                "no prefix map can escape after a later chain exhausts shared work"
            );
        }
        assert!(InputChainReadLimits::new(super::ROW_BUDGET + 1, super::BYTE_BUDGET).is_err());
        assert!(InputChainReadLimits::new(super::ROW_BUDGET, super::BYTE_BUDGET + 1).is_err());
        let too_many = (0..=super::ROW_BUDGET)
            .map(|index| format!("requested-{index}"))
            .collect::<Vec<_>>();
        assert_eq!(
            store
                .input_chains_for_turns(&too_many, budget(super::ROW_BUDGET, super::BYTE_BUDGET))
                .await?,
            InputChainBatchRead::Unavailable(InputChainUnavailable::BudgetExhausted)
        );
        let oversized_id = "x".repeat(usize::try_from(super::BYTE_BUDGET + 1)?);
        assert_eq!(
            store
                .input_chains_for_turns(
                    &[oversized_id],
                    budget(super::ROW_BUDGET, super::BYTE_BUDGET)
                )
                .await?,
            InputChainBatchRead::Unavailable(InputChainUnavailable::BudgetExhausted)
        );
        assert!(
            store
                .input_chains_for_turns(&[String::new()], budget(0, 0))
                .await
                .is_err()
        );
        assert_eq!(
            store.input_chains_for_turns(&[], budget(0, 0)).await?,
            InputChainBatchRead::Ready(InputChainBatch {
                by_turn: BTreeMap::new(),
                rows_read: 0,
                bytes_read: 0,
            })
        );
        Ok(())
    }

    /// A real writer commits a new continuation after the read snapshot is pinned. Every chain and
    /// its own start come from that snapshot; a later observation, not this batch, sees the new Turn.
    #[tokio::test]
    async fn batch_chains_and_own_starts_share_one_snapshot_during_a_real_commit() -> Result<()> {
        let (_directory, store) = control_store().await?;
        let connection = store
            .read_only_connection()
            .await?
            .context("current reader")?;
        let snapshot = connection.db.begin().await?;
        let (database_id, _) = super::super::current::validate_readable(&snapshot, "chain").await?;
        commit(
            &store,
            3,
            &[answer_identity("ask-2:continuation", "turn-2", 3)],
            &[
                resolved_receipt("chain", "ask-2", "turn-1", "ask-2:continuation", 2),
                turn_start("chain", "turn-2", "ask-2:continuation", 3),
            ],
        )
        .await?;
        let requested = BTreeSet::from(["turn-0", "turn-1", "turn-2"]);
        let result = super::prove_batch(
            &snapshot,
            "chain",
            &database_id,
            &requested,
            budget(super::ROW_BUDGET, super::BYTE_BUDGET),
        )
        .await;
        snapshot.rollback().await?;
        let InputChainBatchRead::Ready(old) = result? else {
            anyhow::bail!("pinned batch was unavailable")
        };
        let mut expected = BTreeMap::from([
            (
                "turn-0".into(),
                InputChainProof::Proven(TurnInputChain {
                    turn_id: "turn-0".into(),
                    start_sequence: 1,
                    input_id: "gui-1".into(),
                    continuation_ancestors: vec![],
                }),
            ),
            (
                "turn-1".into(),
                InputChainProof::Proven(TurnInputChain {
                    turn_id: "turn-1".into(),
                    start_sequence: 2,
                    input_id: "control-1".into(),
                    continuation_ancestors: vec!["gui-1".into()],
                }),
            ),
            (
                "turn-2".into(),
                InputChainProof::Unavailable(InputChainUnavailable::NoTurnStart),
            ),
        ]);
        assert_eq!(old.by_turn, expected);
        expected.insert(
            "turn-2".into(),
            InputChainProof::Proven(TurnInputChain {
                turn_id: "turn-2".into(),
                start_sequence: 3,
                input_id: "ask-2:continuation".into(),
                continuation_ancestors: vec!["control-1".into(), "gui-1".into()],
            }),
        );
        let turns = requested.into_iter().map(str::to_owned).collect::<Vec<_>>();
        let InputChainBatchRead::Ready(fresh) = store
            .input_chains_for_turns(&turns, budget(super::ROW_BUDGET, super::BYTE_BUDGET))
            .await?
        else {
            anyhow::bail!("fresh batch was unavailable")
        };
        assert_eq!(fresh.by_turn, expected);
        Ok(())
    }

    /// Every receipt row costs budget, and a page never materialises more rows than the budget can
    /// still pay for: a ledger that needs more rows than permitted is explicitly unavailable instead
    /// of concluding "no parent" from a prefix.
    #[tokio::test]
    async fn scan_budget_counts_every_receipt_row() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let store = HistoryStore::open(&directory.path().join("history.sqlite"), "chain").await?;
        commit(
            &store,
            1,
            &[identity("gui-1", "turn-1", 1)],
            &[turn_start("chain", "turn-1", "gui-1", 1)],
        )
        .await?;
        commit(&store, 2, &[], &filler_receipts(300)).await?;
        let root = InputChainProof::Proven(TurnInputChain {
            turn_id: "turn-1".into(),
            start_sequence: 1,
            input_id: "gui-1".into(),
            continuation_ancestors: Vec::new(),
        });
        // history_meta + every stored receipt row + the start receipt + the input identity.
        let ledger = store
            .writer()
            .await?
            .db
            .query_one_raw(statement(
                "SELECT COUNT(*) AS total FROM history_fact_receipts",
                vec![],
            ))
            .await?
            .context("ledger size")?
            .try_get::<i64>("", "total")?;
        let ledger = u64::try_from(ledger)?;
        assert!(ledger > super::PAGE_ROWS, "the ledger must cross one page");
        let rows = |limit| store.single_input_chain_within("turn-1", budget(limit, 1 << 20));

        // history_meta plus one ledger row, then the next row exhausts the budget.
        assert_eq!(
            rows(2).await?,
            InputChainProof::Unavailable(InputChainUnavailable::BudgetExhausted)
        );
        // Exactly one ledger row fits: the page still returns only the probe row, never 255 more.
        assert_eq!(
            rows(3).await?,
            InputChainProof::Unavailable(InputChainUnavailable::BudgetExhausted)
        );
        // A complete scan across the page boundary still proves the root.
        assert_eq!(rows(1 + ledger + 2).await?, root);
        // One row short of the complete ledger: the second page exhausts the budget.
        assert_eq!(
            rows(1 + ledger + 1).await?,
            InputChainProof::Unavailable(InputChainUnavailable::BudgetExhausted)
        );
        // A budget that dies inside the second page still reports exhaustion, never a partial root.
        assert_eq!(
            rows(1 + super::PAGE_ROWS + 1).await?,
            InputChainProof::Unavailable(InputChainUnavailable::BudgetExhausted)
        );
        // Exercise the real production ceiling as well as the small-page boundary. Existing
        // filler identities are idempotently re-saved, not counted as additional new rows.
        let mut maximum = filler_receipts(usize::try_from(super::ROW_BUDGET - 3)?);
        let extra = maximum
            .pop()
            .context("one row beyond the hard proof budget")?;
        commit(&store, 3, &[], &maximum).await?;
        assert_eq!(store.single_input_chain("turn-1").await?, root);
        assert_eq!(
            store
                .single_input_chain_within(
                    "turn-1",
                    budget(super::ROW_BUDGET - 1, super::BYTE_BUDGET)
                )
                .await?,
            InputChainProof::Unavailable(InputChainUnavailable::BudgetExhausted)
        );
        commit(&store, 4, &[], &[extra]).await?;
        assert_eq!(
            store.single_input_chain("turn-1").await?,
            InputChainProof::Unavailable(InputChainUnavailable::BudgetExhausted)
        );
        Ok(())
    }

    /// Payloads are budgeted in stored UTF-8 bytes and before they are fetched, including the exact
    /// lookups of the start receipt and the input identity — a multibyte payload cannot pass as its
    /// character count, and an oversized single receipt is refused without being read.
    #[tokio::test]
    async fn payload_budget_covers_every_json_read_in_utf8_bytes() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let store = HistoryStore::open(&path, "chain").await?;
        let question = "问题🙂".repeat(8);
        let start = turn_start("chain", "turn-2", "ask-1:continuation", 2);
        let interaction = resolved_receipt_with_question(
            "chain",
            "ask-1",
            "turn-1",
            "ask-1:continuation",
            2,
            &question,
        );
        commit(
            &store,
            1,
            &[identity("gui-1", "turn-1", 1)],
            &[turn_start("chain", "turn-1", "gui-1", 1)],
        )
        .await?;
        commit(
            &store,
            2,
            &[answer_identity("ask-1:continuation", "turn-2", 2)],
            &[interaction, start],
        )
        .await?;
        // Every payload this proof reads, measured exactly as stored: the Turn start receipt, the
        // input identity and the interaction receipt. `length(payload)` is a character count.
        let start_item = receipt_id(TURN_START_RECEIPT, "turn-2");
        let sized = store
            .writer()
            .await?
            .db
            .query_one_raw(statement(
                "SELECT \
                   (SELECT COALESCE(SUM(length(CAST(payload AS BLOB))),0) FROM history_fact_receipts WHERE kind='interaction') AS interaction_bytes, \
                   (SELECT COALESCE(SUM(length(payload)),0) FROM history_fact_receipts WHERE kind='interaction') AS interaction_chars, \
                   (SELECT COALESCE(SUM(length(CAST(payload AS BLOB))),0) FROM history_fact_receipts WHERE kind='turn-start') AS starts_bytes, \
                   (SELECT length(CAST(payload AS BLOB)) FROM history_fact_receipts WHERE item_id=? AND revision=1) AS start_bytes, \
                   (SELECT COALESCE(SUM(length(CAST(payload AS BLOB))),0) FROM history_input_identities) AS identity_bytes, \
                   (SELECT COALESCE(SUM(length(payload)),0) FROM history_input_identities) AS identity_chars",
                vec![start_item.clone().into()],
            ))
            .await?
            .context("payload sizes")?;
        let size =
            |column: &str| -> Result<u64> { Ok(u64::try_from(sized.try_get::<i64>("", column)?)?) };
        let interaction_bytes = size("interaction_bytes")?;
        let interaction_chars = size("interaction_chars")?;
        let starts_bytes = size("starts_bytes")?;
        let start_bytes = size("start_bytes")?;
        let identity_bytes = size("identity_bytes")?;
        let identity_chars = size("identity_chars")?;
        assert!(
            interaction_bytes > interaction_chars,
            "the question must carry multibyte content"
        );
        // Both Turn start receipts are read: the requested Turn and the ancestor it reaches.
        let exact = starts_bytes + identity_bytes + interaction_bytes;
        let as_characters = starts_bytes + identity_chars + interaction_chars;
        let proofs = |bytes| store.single_input_chain_within("turn-2", budget(64, bytes));

        assert!(matches!(proofs(exact).await?, InputChainProof::Proven(_)));
        // Character counting would have admitted this payload; UTF-8 bytes refuse it.
        assert_eq!(
            proofs(as_characters).await?,
            InputChainProof::Unavailable(InputChainUnavailable::BudgetExhausted)
        );
        // The exact start-receipt lookup alone is enough to exhaust one byte less.
        assert_eq!(
            proofs(interaction_bytes + start_bytes - 1).await?,
            InputChainProof::Unavailable(InputChainUnavailable::BudgetExhausted)
        );
        // A valid unrelated pending interaction fills the remaining *production* byte budget.
        // It has no parent edge but its complete payload is still mandatory ledger work.
        let mut pending: InteractionRecord =
            serde_json::from_str(&pending_receipt("chain", "budget-pending", "turn-1", 1).payload)?;
        pending.request.payload = OpaquePayload::text("");
        let overhead = u64::try_from(serde_json::to_string(&pending)?.len())?;
        let padding = usize::try_from(
            super::BYTE_BUDGET
                .checked_sub(exact + overhead)
                .context("fixture leaves production payload capacity")?,
        )?;
        pending.request.payload = OpaquePayload::text("x".repeat(padding));
        let payload = serde_json::to_string(&pending)?;
        assert_eq!(exact + u64::try_from(payload.len())?, super::BYTE_BUDGET);
        let padded_id = receipt_id("interaction", "budget-pending");
        commit(
            &store,
            3,
            &[],
            &[FactReceiptWrite {
                item_id: padded_id.clone(),
                revision: 1,
                kind: "interaction",
                payload,
            }],
        )
        .await?;
        assert!(matches!(
            store.single_input_chain("turn-2").await?,
            InputChainProof::Proven(_)
        ));
        assert_eq!(
            store
                .single_input_chain_within(
                    "turn-2",
                    budget(super::ROW_BUDGET, super::BYTE_BUDGET - 1)
                )
                .await?,
            InputChainProof::Unavailable(InputChainUnavailable::BudgetExhausted)
        );
        // Controlled fixture augmentation makes the same valid ledger exactly one byte too large.
        pending.request.payload = OpaquePayload::text("x".repeat(padding + 1));
        let payload = serde_json::to_string(&pending)?;
        assert_eq!(
            exact + u64::try_from(payload.len())?,
            super::BYTE_BUDGET + 1
        );
        store.writer().await?.db.execute_raw(statement(
            "UPDATE history_fact_receipts SET payload=?,digest=? WHERE item_id=? AND revision=1",
            vec![payload.clone().into(), pl_core::context::content_hash(payload.as_bytes()).into(), padded_id.into()],
        )).await?;
        assert_eq!(
            store.single_input_chain("turn-2").await?,
            InputChainProof::Unavailable(InputChainUnavailable::BudgetExhausted)
        );
        Ok(())
    }

    /// A cold read of a missing store proves nothing and creates nothing.
    #[tokio::test]
    async fn cold_read_never_creates_the_history_database() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let store = HistoryStore::open(&path, "chain").await?;
        assert_eq!(
            store.single_input_chain("turn-1").await?,
            InputChainProof::Unavailable(InputChainUnavailable::MissingHistory)
        );
        assert!(!path.exists(), "cold proof must not create history");
        Ok(())
    }

    /// The source is imported only by the explicit owner. A cold target proves nothing before
    /// publication. Thereafter its cached read-only connection must still inspect the format and
    /// hidden marker in each proof snapshot, not trust a cached version or infer a visible root.
    #[tokio::test]
    async fn structure_and_marker_facts_are_read_from_the_proof_snapshot() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let source_path = directory.path().join("history.sqlite");
        let path = directory.path().join("history-current.sqlite");
        let seed = HistoryStore::open(&source_path, "chain").await?;
        commit(
            &seed,
            1,
            &[identity("gui-1", "turn-1", 1)],
            &[turn_start("chain", "turn-1", "gui-1", 1)],
        )
        .await?;
        // This fixture describes a pre-official v2 source. The real import never upgrades it.
        raw_execute(
            &source_path,
            "DROP TABLE IF EXISTS seaql_migrations; UPDATE history_meta SET schema_version=2",
        )
        .await?;
        let source = super::super::test_support::source_evidence(&source_path).await?;

        let store = HistoryStore::open(&path, "chain").await?;
        assert_eq!(
            store.single_input_chain("turn-1").await?,
            InputChainProof::Unavailable(InputChainUnavailable::MissingHistory)
        );
        assert!(!path.exists());
        store
            .initialize(super::super::test_support::import_origin(
                &source_path,
                "chain",
            )?)
            .await?;
        super::super::test_support::assert_current(&path, "chain").await?;
        let expected = InputChainProof::Proven(TurnInputChain {
            turn_id: "turn-1".into(),
            start_sequence: 1,
            input_id: "gui-1".into(),
            continuation_ancestors: Vec::new(),
        });
        assert_eq!(store.single_input_chain("turn-1").await?, expected);
        // Keep this very read-only connection warm while invalidating its canonical readiness.
        // Restoring a corrupted fixture is not a migration or a forged new completion row.
        for (damage, restore) in [
            (
                "UPDATE history_meta SET schema_version=2",
                format!(
                    "UPDATE history_meta SET schema_version={}",
                    super::super::HISTORY_SCHEMA_VERSION
                ),
            ),
            (
                "UPDATE history_meta SET schema_version=9",
                format!(
                    "UPDATE history_meta SET schema_version={}",
                    super::super::HISTORY_SCHEMA_VERSION
                ),
            ),
            (
                "UPDATE seaql_migrations SET version='m99999999_forged_current'",
                format!(
                    "UPDATE seaql_migrations SET version='{}'",
                    super::super::current::CURRENT_STEP
                ),
            ),
            (
                "INSERT INTO seaql_migrations(version,applied_at) VALUES('m99999999_extra_marker',0)",
                "DELETE FROM seaql_migrations WHERE version='m99999999_extra_marker'".to_owned(),
            ),
            (
                "ALTER TABLE seaql_migrations RENAME TO retained_original_marker; CREATE TABLE seaql_migrations(version TEXT NOT NULL PRIMARY KEY,applied_at INTEGER NOT NULL)",
                "DROP TABLE seaql_migrations; ALTER TABLE retained_original_marker RENAME TO seaql_migrations".to_owned(),
            ),
            (
                "ALTER TABLE seaql_migrations RENAME TO retained_original_marker",
                "ALTER TABLE retained_original_marker RENAME TO seaql_migrations".to_owned(),
            ),
            (
                "CREATE TABLE sqlitex_unknown_authority(id INTEGER)",
                "DROP TABLE sqlitex_unknown_authority".to_owned(),
            ),
        ] {
            raw_execute(&path, damage).await?;
            let broken = super::super::test_support::source_evidence(&path).await?;
            assert!(
                store.single_input_chain("turn-1").await.is_err(),
                "warm proof accepted {damage}"
            );
            assert_eq!(
                super::super::test_support::source_evidence(&path).await?,
                broken,
                "a rejected cached read cannot repair or rewrite the bad current"
            );
            assert_eq!(
                super::super::test_support::source_evidence(&source_path).await?,
                source
            );
            raw_execute(&path, &restore).await?;
            super::super::test_support::assert_current(&path, "chain").await?;
            assert_eq!(store.single_input_chain("turn-1").await?, expected);
        }
        // An unknown hidden marker fails closed instead of becoming a visible root input.
        store
            .writer()
            .await?
            .db
            .execute_unprepared("UPDATE history_input_identities SET presentation=NULL")
            .await?;
        assert_eq!(
            store.single_input_chain("turn-1").await?,
            InputChainProof::Unavailable(InputChainUnavailable::UnsupportedHistory)
        );
        assert_eq!(
            super::super::test_support::source_evidence(&source_path).await?,
            source
        );
        Ok(())
    }
}
