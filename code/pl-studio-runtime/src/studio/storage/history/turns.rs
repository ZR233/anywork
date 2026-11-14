//! Turn 的业务索引；执行顺序不定义展示成员范围。
use super::{integer, statement};
use anyhow::{Context, Result, ensure};
use pl_protocol::{ThreadContextDisposition, Turn};
use sea_orm::{ConnectionTrait, QueryResult};
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct PageCursor {
    version: u32,
    thread_id: String,
    database_id: String,
    through: u64,
    ceiling: u64,
    turn_order: u64,
    turn_id: String,
    record_before: Option<u64>,
}

pub(super) async fn page(
    db: &impl ConnectionTrait,
    thread: &str,
    database: &str,
    token: Option<&str>,
    limit: usize,
) -> Result<pl_protocol::ThreadTurnPage> {
    use crate::studio::runtime::conversation_reader::{JsonBudget, entries};
    use pl_core::chat::{ChatBudget, ChatHistoryRequest, ChatKey, ChatQuery, ReadDemand};
    let through = u64::try_from(super::applied_write_seq(db).await?)?;
    let ceiling = super::conversation::latest_append_seq(db).await?;
    let mut cursor = token.map(serde_json::from_str::<PageCursor>).transpose()?;
    if let Some(cursor) = &cursor {
        ensure!(
            cursor.version == 3
                && cursor.thread_id == thread
                && cursor.database_id == database
                && cursor.through <= through
                && cursor.ceiling <= ceiling,
            "Turn cursor belongs to another database, owner or durable cut"
        );
    }
    let fixed_through = cursor.as_ref().map_or(through, |cursor| cursor.through);
    let fixed_ceiling = cursor.as_ref().map_or(ceiling, |cursor| cursor.ceiling);
    let mut result = pl_protocol::ThreadTurnPage {
        turns: vec![],
        next_cursor: None,
    };
    let mut remaining = super::PAGE_BYTE_BUDGET;
    for _ in 0..limit.clamp(1, super::TURN_PAGE_ROW_LIMIT) {
        let row = match &cursor {
            Some(cursor) if cursor.record_before.is_some() => db.query_one_raw(statement(
                "SELECT * FROM history_turns WHERE turn_id=? AND turn_order=?",
                vec![cursor.turn_id.clone().into(),integer(cursor.turn_order)?.into()],
            )).await?,
            Some(cursor) => db.query_one_raw(statement(
                "SELECT * FROM history_turns WHERE (turn_order,turn_id)<(?,?) ORDER BY turn_order DESC,turn_id DESC LIMIT 1",
                vec![integer(cursor.turn_order)?.into(),cursor.turn_id.clone().into()],
            )).await?,
            None => db.query_one_raw(statement("SELECT * FROM history_turns ORDER BY turn_order DESC,turn_id DESC LIMIT 1",vec![])).await?,
        };
        let Some(row) = row else { break };
        let turn = decode(&row)?;
        ensure!(
            turn.updated_effect
                .is_none_or(|effect| effect <= fixed_through),
            "Turn changed after this fixed history cut; restart the page"
        );
        let before = cursor.as_ref().and_then(|cursor| cursor.record_before);
        let mut history = pl_protocol::ThreadTurnHistory {
            turn: turn.turn,
            items: vec![],
            context_disposition: turn.context_disposition,
        };
        let mut next = PageCursor {
            version: 3,
            thread_id: thread.into(),
            database_id: database.into(),
            through: fixed_through,
            ceiling: fixed_ceiling,
            turn_order: turn.turn_order,
            turn_id: history.turn.id.clone(),
            record_before: Some(i64::MAX as u64),
        };
        let reserve = serde_json::to_vec(&history)?
            .len()
            .saturating_add(serde_json::to_vec(&next)?.len().saturating_mul(6))
            .saturating_add(256);
        let budget = JsonBudget::new(database.into(), String::new()).headers_only();
        let available = remaining
            .saturating_sub(reserve)
            .saturating_sub(budget.fixed_bytes());
        if available == 0 {
            ensure!(
                !result.turns.is_empty(),
                "Turn metadata exceeds history page byte budget"
            );
            break;
        }
        let page = super::conversation::page(
            db,
            &ChatHistoryRequest {
                query: Some(ChatQuery {
                    query_class: None,
                    parent_id: Some(ChatKey::new("turn", &history.turn.id)?),
                }),
                after: 0,
                before,
                ceiling: fixed_ceiling,
                demand: ReadDemand::new(super::TURN_PAGE_ITEM_LIMIT, available),
            },
            &budget,
            false,
        )
        .await?;
        ensure!(
            page.exhausted || !page.items.is_empty(),
            "Turn record cannot fit history page demand"
        );
        next.record_before = (!page.exhausted).then(|| {
            page.items
                .first()
                .expect("checked nonempty page")
                .header
                .append_seq
        });
        history.items = entries(page.items, database)?;
        let bytes = serde_json::to_vec(&history)?.len();
        remaining = remaining
            .checked_sub(bytes)
            .context("Turn record exceeded history byte budget")?;
        result.turns.push(history);
        let records_remain = next.record_before.is_some();
        result.next_cursor = Some(serde_json::to_string(&next)?);
        cursor = Some(next);
        if records_remain {
            break;
        }
        // One index seek proves whether a strictly older Turn exists.
        let next = cursor.as_ref().expect("recorded current Turn");
        let older = db
            .query_one_raw(statement(
                "SELECT 1 AS present FROM history_turns WHERE (turn_order,turn_id)<(?,?) LIMIT 1",
                vec![
                    integer(next.turn_order)?.into(),
                    next.turn_id.clone().into(),
                ],
            ))
            .await?;
        if older.is_none() {
            result.next_cursor = None;
            break;
        }
    }
    ensure!(
        serde_json::to_vec(&result)?.len() <= super::PAGE_BYTE_BUDGET,
        "encoded Turn page exceeds its byte budget"
    );
    Ok(result)
}

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

impl TurnWrite {
    pub(in crate::studio) fn retained_bytes(&self) -> u64 {
        // Turn 只含状态、输入身份和错误；不保留其全部完成成员。
        serde_json::to_vec(&self.turn)
            .map_or(u64::MAX, |bytes| bytes.len() as u64)
            .saturating_add(std::mem::size_of::<Self>() as u64)
    }
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

pub(super) async fn terminal(db: &impl ConnectionTrait) -> Result<Option<Turn>> {
    db.query_one_raw(statement("SELECT * FROM history_turns WHERE terminal_effect IS NOT NULL ORDER BY terminal_effect DESC,turn_order DESC,turn_id DESC LIMIT 1", vec![]))
        .await?.as_ref().map(|row| Ok(decode(row)?.turn)).transpose()
}

pub(super) async fn rollback(
    db: &impl ConnectionTrait,
    ids: &std::collections::BTreeSet<String>,
) -> Result<()> {
    let disposition = serde_json::to_string(&ThreadContextDisposition::RolledBack)?;
    for id in ids {
        let written = db
            .execute_raw(statement(
                "UPDATE history_turns SET context_disposition=? WHERE turn_id=?",
                vec![disposition.clone().into(), id.clone().into()],
            ))
            .await?;
        ensure!(written.rows_affected() == 1, "rolled-back Turn is missing");
    }
    Ok(())
}

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
