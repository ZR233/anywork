//! Turn 的业务索引；执行顺序不定义展示成员范围。
use super::{integer, statement};
use crate::{ThreadContextDisposition, Turn};
#[cfg(test)]
use anyhow::Context;
use anyhow::{Result, ensure};
use sea_orm::{ConnectionTrait, QueryResult};

pub(super) const CREATE: &str = "
CREATE TABLE history_turns (
 turn_id TEXT PRIMARY KEY NOT NULL, turn_order INTEGER NOT NULL,
 admitted_effect INTEGER, updated_effect INTEGER, terminal_effect INTEGER,
 payload TEXT NOT NULL CHECK(json_valid(payload)), context_disposition TEXT NOT NULL,
 CHECK(turn_order>0), CHECK(admitted_effect IS NULL OR admitted_effect>0),
 CHECK(updated_effect IS NULL OR updated_effect>0),
 CHECK(terminal_effect IS NULL OR terminal_effect>0)
) WITHOUT ROWID;
CREATE INDEX history_turns_order ON history_turns(turn_order,turn_id);
CREATE INDEX history_turns_terminal ON history_turns(terminal_effect,turn_order,turn_id)
 WHERE terminal_effect IS NOT NULL;
";

#[derive(Debug, Clone, PartialEq)]
pub(in crate::studio) struct TurnWrite {
    pub turn: Turn,
    pub turn_order: u64,
    pub admitted_effect: Option<u64>,
    pub updated_effect: Option<u64>,
    pub terminal_effect: Option<u64>,
    pub context_disposition: ThreadContextDisposition,
}

pub(super) fn decode(row: &QueryResult) -> Result<TurnWrite> {
    let optional = |field| -> Result<Option<u64>> {
        Ok(row
            .try_get::<Option<i64>>("", field)?
            .map(u64::try_from)
            .transpose()?)
    };
    let value = TurnWrite {
        turn: serde_json::from_str(&row.try_get::<String>("", "payload")?)?,
        turn_order: u64::try_from(row.try_get::<i64>("", "turn_order")?)?,
        admitted_effect: optional("admitted_effect")?,
        updated_effect: optional("updated_effect")?,
        terminal_effect: optional("terminal_effect")?,
        context_disposition: serde_json::from_str(
            &row.try_get::<String>("", "context_disposition")?,
        )?,
    };
    ensure!(
        value.turn.id == row.try_get::<String>("", "turn_id")?,
        "Turn identity differs from its index"
    );
    ensure!(
        value.terminal_effect.is_none() || value.turn.state.is_terminal(),
        "nonterminal Turn carries a terminal effect"
    );
    Ok(value)
}

pub(super) async fn read(db: &impl ConnectionTrait, id: &str) -> Result<Option<TurnWrite>> {
    db.query_one_raw(statement(
        "SELECT * FROM history_turns WHERE turn_id=?",
        vec![id.into()],
    ))
    .await?
    .as_ref()
    .map(decode)
    .transpose()
}

pub(super) async fn apply(
    db: &impl ConnectionTrait,
    write: &TurnWrite,
    thread_id: &str,
) -> Result<()> {
    ensure!(
        write.turn.thread_id == thread_id && !write.turn.id.is_empty() && write.turn_order > 0,
        "Turn write does not belong to its execution owner"
    );
    let mut value = write.clone();
    if let Some(old) = read(db, &write.turn.id).await? {
        ensure!(
            old.turn_order == write.turn_order,
            "stable Turn execution order changed"
        );
        if let (Some(old), Some(new)) = (old.admitted_effect, write.admitted_effect) {
            ensure!(old == new, "Turn admission evidence changed");
        }
        value.admitted_effect = old.admitted_effect.or(write.admitted_effect);
        if old.turn.state.is_terminal() {
            ensure!(
                old.turn.state == write.turn.state && old.turn.input_id == write.turn.input_id,
                "terminal Turn business fact changed"
            );
            value.turn = old.turn;
            value.updated_effect = old.updated_effect;
            value.terminal_effect = old.terminal_effect;
        } else if old.updated_effect > write.updated_effect {
            anyhow::bail!("Turn update effect moved backwards");
        } else if old.updated_effect == write.updated_effect {
            ensure!(old.turn == write.turn, "Turn changed under the same effect");
        }
        if old.context_disposition == ThreadContextDisposition::RolledBack {
            value.context_disposition = old.context_disposition;
        }
    }
    db.execute_raw(statement(
        "INSERT INTO history_turns(turn_id,turn_order,admitted_effect,updated_effect,terminal_effect,payload,context_disposition)
         VALUES(?,?,?,?,?,?,?) ON CONFLICT(turn_id) DO UPDATE SET
         admitted_effect=excluded.admitted_effect,updated_effect=excluded.updated_effect,terminal_effect=excluded.terminal_effect,payload=excluded.payload,context_disposition=excluded.context_disposition",
        vec![value.turn.id.clone().into(), integer(value.turn_order)?.into(), value.admitted_effect.map(integer).transpose()?.into(),
            value.updated_effect.map(integer).transpose()?.into(), value.terminal_effect.map(integer).transpose()?.into(),
            serde_json::to_string(&value.turn)?.into(),serde_json::to_string(&value.context_disposition)?.into()],
    )).await?;
    Ok(())
}

#[cfg(test)]
pub(super) async fn latest_at(
    db: &impl ConnectionTrait,
    thread: &str,
    fence: u64,
) -> Result<Option<Turn>> {
    ensure!(
        u64::try_from(super::applied_write_seq(db).await?)? == fence,
        "child history changed or does not cover the evaluation fence"
    );
    let row = db
        .query_one_raw(statement(
            "SELECT * FROM history_turns ORDER BY turn_order DESC,turn_id DESC LIMIT 1",
            vec![],
        ))
        .await?;
    let Some(row) = row else { return Ok(None) };
    let value = decode(&row)?;
    ensure!(
        value.turn.thread_id == thread && value.updated_effect.is_none_or(|effect| effect <= fence),
        "Turn does not match its committed owner or fence"
    );
    Ok(Some(value.turn))
}

#[cfg(test)]
pub(super) async fn rollback(
    db: &impl ConnectionTrait,
    ids: &std::collections::BTreeSet<String>,
    effect: u64,
) -> Result<()> {
    let effect = integer(effect)?;
    let active = serde_json::to_string(&ThreadContextDisposition::Active)?;
    let disposition = serde_json::to_string(&ThreadContextDisposition::RolledBack)?;
    for id in ids {
        let written = db
            .execute_raw(statement(
                "UPDATE history_turns SET updated_effect=CASE WHEN context_disposition=? THEN ? ELSE updated_effect END,
                 context_disposition=? WHERE turn_id=? AND (context_disposition=? OR
                 (context_disposition=? AND (updated_effect IS NULL OR updated_effect<=?)))",
                vec![active.clone().into(), effect.into(), disposition.clone().into(), id.clone().into(),
                    disposition.clone().into(), active.clone().into(), effect.into()],
            ))
            .await?;
        if written.rows_affected() == 0 {
            let old = read(db, id).await?.context("rolled-back Turn is missing")?;
            ensure!(
                old.context_disposition == ThreadContextDisposition::Active,
                "rolled-back Turn has invalid context disposition"
            );
            anyhow::bail!("Turn rollback effect moved backwards");
        }
    }
    Ok(())
}

#[cfg(test)]
pub(super) async fn verify(db: &impl ConnectionTrait, writes: &[TurnWrite]) -> Result<()> {
    for write in writes {
        let old = read(db, &write.turn.id)
            .await?
            .context("retried Turn is missing")?;
        ensure!(
            old.turn_order == write.turn_order
                && old.turn == write.turn
                && write
                    .admitted_effect
                    .is_none_or(|effect| old.admitted_effect == Some(effect))
                && write
                    .terminal_effect
                    .is_none_or(|effect| old.terminal_effect == Some(effect)),
            "retried Turn differs from durable evidence"
        );
    }
    Ok(())
}
