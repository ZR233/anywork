//! Durable proof that the first authorization cut precedes the first Turn start.
//!
//! Reaching a provider gate only shows that the model request was served; it does
//! not order the cut against the execution. This reader therefore consumes the
//! isolated acceptance database read-only: the immutable `audience-start` and
//! `turn-start` fact receipts written in the original history transaction, fenced
//! by the same `history_meta` identity and watermark. It never writes a row, never
//! fabricates a receipt, and does not call a production private decision helper;
//! the digest is recomputed locally.

use super::super::sqlite;
use super::Authorized;
use crate::http;
use anyhow::{Context, Result, bail, ensure};
use pl_protocol::BotAuthorizationId;
use serde::Deserialize;
use std::path::Path;
use std::time::Instant;

const AUDIENCE_START_KIND: &str = "audience-start";
const TURN_START_KIND: &str = "turn-start";
/// One immutable identity describes exactly one cut/start, never a progress row.
const RECEIPT_REVISION: u64 = 1;
/// The receipt identity keeps the byte length so colons stay unambiguous.
fn receipt_id(kind: &str, id: &str) -> String {
    format!("{kind}:{}:{id}", id.len())
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct AudienceStartIntent {
    operation_id: String,
    thread_id: String,
    authorization: BotAuthorizationId,
    binding_revision: u64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct AudienceStartReceipt {
    version: u32,
    intent: AudienceStartIntent,
    extension_revision: u64,
    sequence: u64,
    excluded_turn_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct TurnStartReceipt {
    version: u32,
    thread_id: String,
    turn_id: String,
    input_id: Option<String>,
    sequence: u64,
}

/// Ordered, verified start facts of one Thread.
#[derive(Debug, Clone)]
pub(super) struct StartProof {
    pub cut_sequence: u64,
    pub turn_start_sequence: u64,
    pub excluded_turn_id: Option<String>,
    pub operation_id: String,
    pub database_id: String,
    pub applied_write_sequence: u64,
}

/// Waits (bounded, polling real durable facts) for the exact start proof.
///
/// A missing or unreadable receipt is never treated as "not yet executed"; the
/// caller sees the explicit failure and must keep the auto-init range unproven.
pub(super) async fn first_start_proof(
    home: &Path,
    thread_id: &str,
    authorized: &Authorized,
    first_turn_id: &str,
    expected_input_id: &str,
) -> Result<StartProof> {
    let deadline = Instant::now() + http::PREDICATE_TIMEOUT;
    let mut last;
    loop {
        match read_proof(
            home,
            thread_id,
            authorized,
            first_turn_id,
            expected_input_id,
        )
        .await
        {
            Ok(Some(proof)) => return Ok(proof),
            Ok(None) => last = "the durable start receipts are not committed yet".to_owned(),
            Err(error) => last = format!("{error:#}"),
        }
        if Instant::now() >= deadline {
            bail!(
                "Thread {thread_id} has no durable first-start proof (first authorization cut before the first Turn start): {last}"
            );
        }
        tokio::time::sleep(http::POLL).await;
    }
}

async fn read_proof(
    home: &Path,
    thread_id: &str,
    authorized: &Authorized,
    first_turn_id: &str,
    expected_input_id: &str,
) -> Result<Option<StartProof>> {
    // One read snapshot: the identity and every receipt below come from the same
    // SELECT, so no proof is assembled across two connections.
    let snapshot = sqlite::history_receipt_snapshot(home, thread_id).await?;
    let identity = snapshot.identity;
    ensure!(
        identity.thread_id == thread_id,
        "the read snapshot belongs to another Thread"
    );
    let receipts = snapshot.receipts;
    let mut audience = None;
    let mut turn = None;
    for row in receipts {
        ensure!(
            row.revision == RECEIPT_REVISION,
            "receipt {} has revision {}, expected {RECEIPT_REVISION}",
            row.item_id,
            row.revision
        );
        ensure!(
            row.digest == format!("sha256:{}", super::sha256(row.payload.as_bytes())),
            "receipt {} payload digest does not match its durable bytes",
            row.item_id
        );
        ensure!(
            row.sequence > 0 && row.sequence <= identity.applied_write_sequence,
            "receipt {} is not covered by the durable history watermark",
            row.item_id
        );
        match row.kind.as_str() {
            AUDIENCE_START_KIND => {
                let receipt: AudienceStartReceipt = serde_json::from_str(&row.payload)
                    .with_context(|| {
                        format!("audience-start receipt {} is not decodable", row.item_id)
                    })?;
                if receipt.intent.thread_id != thread_id
                    || receipt.intent.authorization != authorized.id
                {
                    continue;
                }
                ensure!(
                    row.item_id == receipt_id(AUDIENCE_START_KIND, &receipt.intent.operation_id),
                    "audience-start receipt identity does not match its operation identity"
                );
                ensure!(
                    receipt.version == 1
                        && receipt.extension_revision > 0
                        && !receipt.intent.operation_id.is_empty()
                        && receipt.intent.binding_revision > 0
                        && !receipt.intent.authorization.bot_id.is_empty()
                        && !receipt.intent.authorization.chat_id.is_empty()
                        && receipt.intent.authorization.generation > 0,
                    "audience-start receipt {} has an incomplete durable identity",
                    row.item_id
                );
                ensure!(
                    receipt.sequence == row.sequence,
                    "audience-start receipt sequence disagrees with its durable write sequence"
                );
                ensure!(
                    audience.is_none(),
                    "more than one audience-start receipt matches this authorization"
                );
                audience = Some(receipt);
            }
            TURN_START_KIND => {
                let receipt: TurnStartReceipt =
                    serde_json::from_str(&row.payload).with_context(|| {
                        format!("turn-start receipt {} is not decodable", row.item_id)
                    })?;
                if receipt.turn_id != first_turn_id {
                    continue;
                }
                ensure!(
                    row.item_id == receipt_id(TURN_START_KIND, &receipt.turn_id),
                    "turn-start receipt identity does not match its Turn identity"
                );
                ensure!(
                    receipt.version == 1 && receipt.thread_id == thread_id,
                    "turn-start receipt {} does not belong to this Thread",
                    row.item_id
                );
                ensure!(
                    receipt.sequence == row.sequence,
                    "turn-start receipt sequence disagrees with its durable write sequence"
                );
                ensure!(
                    turn.is_none(),
                    "more than one turn-start receipt matches the first Turn"
                );
                turn = Some(receipt);
            }
            other => bail!("unexpected start receipt kind {other:?}"),
        }
    }
    let (Some(audience), Some(turn)) = (audience, turn) else {
        return Ok(None);
    };
    ensure!(
        audience.sequence < turn.sequence,
        "the first authorization cut (sequence {}) must precede the first Turn start (sequence {})",
        audience.sequence,
        turn.sequence
    );
    ensure!(
        audience.excluded_turn_id.as_deref() != Some(first_turn_id),
        "the first authorization cut must not exclude the very Turn it authorizes"
    );
    ensure!(
        turn.input_id.as_deref() == Some(expected_input_id),
        "the first Turn start must name the first reliable inbound input, got {:?}",
        turn.input_id
    );
    Ok(Some(StartProof {
        cut_sequence: audience.sequence,
        turn_start_sequence: turn.sequence,
        excluded_turn_id: audience.excluded_turn_id,
        operation_id: audience.intent.operation_id,
        database_id: identity.database_id,
        applied_write_sequence: identity.applied_write_sequence,
    }))
}
