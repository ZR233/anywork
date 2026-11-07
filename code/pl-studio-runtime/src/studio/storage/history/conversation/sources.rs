//! Actual source lifecycle only. Each source has at most one start/end, not a member ledger.
use super::*;
use pl_protocol::{
    ChatFactPosition, ChatSourceId, ChatSourceLifecycle, ChatSourceState, ChatTerminalOutcome,
};

pub(in super::super) const CREATE_SCHEMA: &str = "
CREATE TABLE conversation_sources (
 source_key TEXT PRIMARY KEY NOT NULL,
 started_effect INTEGER, started_suborder INTEGER,
 ended_effect INTEGER, ended_suborder INTEGER,
 active_observed INTEGER, ended_observed INTEGER, outcome TEXT,
 CHECK ((started_effect IS NULL)=(started_suborder IS NULL)),
 CHECK ((ended_effect IS NULL)=(ended_suborder IS NULL)),
 CHECK ((ended_observed IS NULL)=(outcome IS NULL))
) WITHOUT ROWID;
";

fn source_key(source: &ChatSourceId) -> Result<String> {
    Ok(serde_json::to_string(source)?)
}
#[derive(Default)]
struct Stored {
    started: Option<ChatFactPosition>,
    ended: Option<ChatFactPosition>,
    active_observed: Option<u64>,
    ended_observed: Option<u64>,
    outcome: Option<ChatTerminalOutcome>,
}
fn optional_position(row: &QueryResult, prefix: &str) -> Result<Option<ChatFactPosition>> {
    let effect: Option<i64> = row.try_get("", &format!("{prefix}_effect"))?;
    let sub: Option<i64> = row.try_get("", &format!("{prefix}_suborder"))?;
    match (effect, sub) {
        (None, None) => Ok(None),
        (Some(effect), Some(sub)) => Ok(Some(ChatFactPosition {
            effect_seq: u64::try_from(effect)?,
            suborder: u32::try_from(sub)?,
        })),
        _ => anyhow::bail!("stored source position is incomplete"),
    }
}
async fn stored(db: &impl ConnectionTrait, source: &ChatSourceId) -> Result<Option<Stored>> {
    let Some(row)=db.query_one_raw(statement("SELECT started_effect,started_suborder,ended_effect,ended_suborder,active_observed,ended_observed,outcome FROM conversation_sources WHERE source_key=?",vec![source_key(source)?.into()])).await? else {return Ok(None)};
    let optional = |name: &str| -> Result<Option<u64>> {
        row.try_get::<Option<i64>>("", name)?
            .map(u64::try_from)
            .transpose()
            .map_err(Into::into)
    };
    let value = Stored {
        started: optional_position(&row, "started")?,
        ended: optional_position(&row, "ended")?,
        active_observed: optional("active_observed")?,
        ended_observed: optional("ended_observed")?,
        outcome: row
            .try_get::<Option<String>>("", "outcome")?
            .map(|s| serde_json::from_str(&s))
            .transpose()?,
    };
    ensure!(
        value.ended_observed.is_some() == value.outcome.is_some(),
        "stored source outcome lacks end evidence"
    );
    Ok(Some(value))
}
fn at_cut(source: ChatSourceId, value: Stored, cut: u64) -> ChatSourceState {
    let started = value.started.filter(|at| at.effect_seq <= cut);
    let ended = value.ended.filter(|at| at.effect_seq <= cut);
    let end_known = ended.is_some() || value.ended_observed.is_some_and(|at| at <= cut);
    let active_known = started.is_some() || value.active_observed.is_some_and(|at| at <= cut);
    let lifecycle = if end_known {
        value
            .outcome
            .map(|outcome| ChatSourceLifecycle::Ended { outcome })
            .unwrap_or(ChatSourceLifecycle::Unknown)
    } else if active_known {
        ChatSourceLifecycle::Active
    } else {
        ChatSourceLifecycle::Unknown
    };
    ChatSourceState {
        source,
        lifecycle,
        started,
        ended,
    }
}

/// One row lookup per caller-provided source, sharing the caller's read transaction.
pub(crate) async fn read(
    db: &impl ConnectionTrait,
    sources: &[ChatSourceId],
    cut: u64,
) -> Result<Vec<ChatSourceState>> {
    if sources.is_empty() {
        return Ok(Vec::new());
    }
    pl_core::chat::ReadDemand::new(sources.len(), 1).validate()?;
    let mut result = Vec::with_capacity(sources.len());
    let mut seen = std::collections::BTreeSet::new();
    for source in sources {
        if seen.insert(source.clone()) {
            result.push(at_cut(
                source.clone(),
                stored(db, source).await?.unwrap_or_default(),
                cut,
            ));
        }
    }
    Ok(result)
}

/// Only the already selected page and, for Main, bounded current participate in this snapshot.
/// Payloads, checkpoints and sources outside this selection are deliberately not read.
pub(in super::super) async fn read_selected(
    db: &impl ConnectionTrait,
    page: &ChatHistoryPage,
    current: &pl_protocol::CurrentProjection,
    include_current: bool,
) -> Result<Vec<ChatSourceState>> {
    let mut selected = std::collections::BTreeSet::new();
    for item in &page.items {
        let atom: pl_protocol::ChatAtom = serde_json::from_slice(&item.header.metadata)
            .with_context(|| format!("invalid atom metadata for {}", item.header.item_id))?;
        selected.insert(atom.source);
    }
    if include_current {
        selected.extend(current.sources.iter().map(|state| state.source.clone()));
        selected.extend(current.atoms.iter().map(|atom| atom.source.clone()));
        if let Some(turn) = &current.active_turn {
            selected.insert(ChatSourceId::ForegroundTurn {
                turn_id: turn.id.clone(),
            });
        }
    }
    // Each individual input is bounded already. Query one distinct source at a time so
    // the union of current and a full page is not mistaken for a new page demand.
    let mut result = Vec::with_capacity(selected.len());
    for source in selected {
        result.push(at_cut(
            source.clone(),
            stored(db, &source).await?.unwrap_or_default(),
            current.source_effect_seq,
        ));
    }
    Ok(result)
}

fn merge_position(
    old: &mut Option<ChatFactPosition>,
    new: Option<ChatFactPosition>,
    effect: u64,
) -> Result<()> {
    if let Some(at) = new {
        ensure!(
            at.effect_seq <= effect,
            "source position exceeds committing effect"
        );
        match old {
            Some(previous) => ensure!(*previous == at, "immutable source position conflict"),
            None => *old = Some(at),
        }
    }
    Ok(())
}

pub(crate) async fn apply(
    db: &impl ConnectionTrait,
    effect: u64,
    changes: &[ChatSourceState],
) -> Result<()> {
    for change in changes {
        let mut value = stored(db, &change.source).await?.unwrap_or_default();
        ensure!(
            value.started.is_none() || change.started.is_some(),
            "known source start cannot be omitted"
        );
        ensure!(
            value.ended.is_none() || change.ended.is_some(),
            "known source end cannot be omitted"
        );
        merge_position(&mut value.started, change.started, effect)?;
        merge_position(&mut value.ended, change.ended, effect)?;
        if let (Some(start), Some(end)) = (value.started, value.ended) {
            ensure!(start <= end, "source ended before its start");
        }
        match change.lifecycle {
            ChatSourceLifecycle::Unknown => {
                ensure!(
                    change.started.is_none() && change.ended.is_none(),
                    "unknown source carries a known lifecycle event"
                );
                ensure!(
                    value.started.is_none()
                        && value.ended.is_none()
                        && value.active_observed.is_none()
                        && value.ended_observed.is_none(),
                    "known source cannot become unknown"
                );
            }
            ChatSourceLifecycle::Active => {
                ensure!(
                    value.ended_observed.is_none(),
                    "ended source cannot become active again"
                );
                ensure!(change.ended.is_none(), "active source carries an end");
                value.active_observed = Some(value.active_observed.unwrap_or(effect));
            }
            ChatSourceLifecycle::Ended { outcome } => {
                if let Some(old) = value.outcome {
                    ensure!(old == outcome, "immutable source outcome conflict");
                }
                value.outcome = Some(outcome);
                value.ended_observed = Some(value.ended_observed.unwrap_or(effect));
            }
        }
        db.execute_raw(statement("INSERT INTO conversation_sources(source_key,started_effect,started_suborder,ended_effect,ended_suborder,active_observed,ended_observed,outcome) VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(source_key) DO UPDATE SET started_effect=excluded.started_effect,started_suborder=excluded.started_suborder,ended_effect=excluded.ended_effect,ended_suborder=excluded.ended_suborder,active_observed=excluded.active_observed,ended_observed=excluded.ended_observed,outcome=excluded.outcome",vec![
   source_key(&change.source)?.into(),value.started.map(|at|integer(at.effect_seq)).transpose()?.into(),value.started.map(|at|i64::from(at.suborder)).into(),
   value.ended.map(|at|integer(at.effect_seq)).transpose()?.into(),value.ended.map(|at|i64::from(at.suborder)).into(),
   value.active_observed.map(integer).transpose()?.into(),value.ended_observed.map(integer).transpose()?.into(),value.outcome.map(|outcome|serde_json::to_string(&outcome)).transpose()?.into(),
  ])).await?;
    }
    Ok(())
}

/// A retried effect can observe a later saved end, but must still prove its own start/end fields.
pub(crate) async fn verify(
    db: &impl ConnectionTrait,
    effect: u64,
    changes: &[ChatSourceState],
) -> Result<()> {
    for change in changes {
        let value = stored(db, &change.source)
            .await?
            .context("retried effect is missing source lifecycle")?;
        if let Some(start) = change.started {
            ensure!(
                value.started == Some(start),
                "retried effect changed source start"
            );
        }
        if let Some(end) = change.ended {
            ensure!(
                value.ended == Some(end),
                "retried effect changed source end"
            );
        }
        let snapshot = at_cut(change.source.clone(), value, effect);
        ensure!(
            snapshot == *change,
            "retried effect changed source lifecycle"
        );
    }
    Ok(())
}

#[cfg(test)]
mod tests;
