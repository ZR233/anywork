//! 执行开始与结束的最小持久化事实；没有正文、展示分组或进度快照。
use super::{integer, statement};
use anyhow::{Context, Result, ensure};
use pl_protocol::{
    ChatActiveStatus, ChatAtom, ChatAtomKind, ChatAtomLifecycle, ChatDeliveryKind,
    ChatFactPosition, ChatSourceId, ChatTerminalOutcome, ChatToolIdentity, ThreadTextChannel,
};
use sea_orm::{ConnectionTrait, QueryResult};

pub(super) const CREATE: &str = "
CREATE TABLE execution_lifecycle (
 identity TEXT PRIMARY KEY NOT NULL, kind TEXT NOT NULL,
 source_kind TEXT NOT NULL, source_identity TEXT NOT NULL,
 turn_id TEXT, attempt_id TEXT, call_id TEXT, tool_name TEXT, text_channel TEXT,
 delivery TEXT NOT NULL, source_order INTEGER, execution_order INTEGER CHECK(execution_order>0),
 started_effect INTEGER, started_suborder INTEGER, started_at INTEGER,
 ended_effect INTEGER, ended_suborder INTEGER, finished_at INTEGER, outcome TEXT,
 completion_item_id TEXT, last_write_seq INTEGER NOT NULL,
 CHECK ((started_effect IS NULL)=(started_suborder IS NULL)),
 CHECK ((ended_effect IS NULL)=(ended_suborder IS NULL)),
 CHECK (ended_effect IS NULL OR outcome IS NOT NULL),
 CHECK (completion_item_id IS NULL OR outcome IS NOT NULL)
) WITHOUT ROWID;
CREATE INDEX execution_lifecycle_active ON execution_lifecycle(identity)
 WHERE ended_effect IS NULL AND outcome IS NULL;
CREATE INDEX execution_lifecycle_turn ON execution_lifecycle(turn_id,source_order,identity);
CREATE INDEX execution_lifecycle_call ON execution_lifecycle(call_id,identity)
 WHERE call_id IS NOT NULL;
";

#[derive(Debug, Clone, PartialEq, Eq)]
pub(in crate::studio) struct ExecutionLifecycle {
    pub identity: String,
    pub kind: ChatAtomKind,
    pub source: ChatSourceId,
    pub turn_id: Option<String>,
    pub attempt_id: Option<String>,
    pub tool: Option<ChatToolIdentity>,
    pub text_channel: Option<ThreadTextChannel>,
    pub delivery: ChatDeliveryKind,
    pub source_order: Option<u64>,
    /// Runtime 自身的执行位置，区别于消息来源的顺序。
    pub execution_order: Option<u64>,
    pub started: Option<ChatFactPosition>,
    pub started_at: Option<i64>,
    pub ended: Option<ChatFactPosition>,
    pub finished_at: Option<i64>,
    pub outcome: Option<ChatTerminalOutcome>,
    pub completion_item_id: Option<String>,
    pub last_write_seq: u64,
}

impl ExecutionLifecycle {
    pub(in crate::studio) fn from_atom(atom: &ChatAtom, effect: u64) -> Result<Self> {
        let (started, ended, outcome) = match atom.lifecycle {
            ChatAtomLifecycle::Active { started, .. } => (started, None, None),
            ChatAtomLifecycle::Terminal {
                started,
                ended,
                outcome,
            } => (started, ended, Some(outcome)),
        };
        ensure!(!atom.id.is_empty(), "lifecycle identity is empty");
        ensure!(
            started.is_none_or(|at| at.effect_seq <= effect)
                && ended.is_none_or(|at| at.effect_seq <= effect),
            "lifecycle exceeds its effect"
        );
        ensure!(
            started.zip(ended).is_none_or(|(start, end)| start <= end),
            "lifecycle ended before its start"
        );
        ensure!(
            outcome.is_some() || atom.completion_item_id.is_none(),
            "active lifecycle has a completion"
        );
        Ok(Self {
            identity: atom.id.clone(),
            kind: if atom.tool.is_some() {
                ChatAtomKind::ToolCall
            } else {
                atom.kind
            },
            source: atom.source.clone(),
            turn_id: atom.turn_id.clone(),
            attempt_id: atom.attempt_id.clone(),
            tool: atom.tool.clone(),
            text_channel: atom.text_channel,
            delivery: atom.delivery,
            source_order: atom.source_order,
            execution_order: None,
            started,
            started_at: atom.started_at,
            ended,
            finished_at: atom.finished_at,
            outcome,
            completion_item_id: atom.completion_item_id.clone(),
            last_write_seq: effect,
        })
    }

    /// 恢复当前执行的局部投影，没有完成原件时不生成空正文或完成项。
    pub(in crate::studio) fn active_atom(self) -> Result<ChatAtom> {
        ensure!(
            self.outcome.is_none() && self.ended.is_none(),
            "terminal lifecycle is not active"
        );
        Ok(ChatAtom {
            id: self.identity,
            completion_item_id: None,
            completion_seq: None,
            source: self.source,
            source_state: None,
            source_order: self.source_order,
            kind: self.kind,
            delivery: self.delivery,
            lifecycle: ChatAtomLifecycle::Active {
                started: self.started,
                status: ChatActiveStatus::Running,
            },
            turn_id: self.turn_id,
            attempt_id: self.attempt_id,
            tool: self.tool,
            wait: None,
            text_channel: self.text_channel,
            started_at: self.started_at,
            finished_at: None,
            content_present: None,
            contents: vec![],
            payload: None,
        })
    }

    pub(in crate::studio) fn retained_bytes(&self) -> u64 {
        let source = match &self.source {
            ChatSourceId::ForegroundTurn { turn_id } => turn_id.len(),
            ChatSourceId::Input { input_id } => input_id.len(),
            ChatSourceId::InboxMessage {
                source_id,
                message_id,
            } => source_id.len() + message_id.len(),
            ChatSourceId::BackgroundResult { message_id } => message_id.len(),
            ChatSourceId::Operation { operation_id } => operation_id.len(),
            ChatSourceId::Receipt { receipt_id } => receipt_id.len(),
        };
        let strings = self.identity.len()
            + source
            + self.turn_id.as_ref().map_or(0, String::len)
            + self.attempt_id.as_ref().map_or(0, String::len)
            + self
                .tool
                .as_ref()
                .map_or(0, |tool| tool.call_id.len() + tool.name.len())
            + self.completion_item_id.as_ref().map_or(0, String::len);
        (std::mem::size_of::<Self>() as u64).saturating_add(strings as u64)
    }
}

fn merge_optional<T: PartialEq>(old: &mut Option<T>, new: Option<T>) -> Result<()> {
    if let Some(new) = new {
        match old {
            Some(old) => ensure!(*old == new, "immutable lifecycle evidence conflict"),
            None => *old = Some(new),
        }
    }
    Ok(())
}

fn merge(old: &mut ExecutionLifecycle, new: ExecutionLifecycle) -> Result<()> {
    ensure!(
        old.identity == new.identity && old.kind == new.kind && old.source == new.source,
        "lifecycle identity/classification conflict"
    );
    merge_optional(&mut old.turn_id, new.turn_id)?;
    merge_optional(&mut old.attempt_id, new.attempt_id)?;
    merge_optional(&mut old.tool, new.tool)?;
    merge_optional(&mut old.text_channel, new.text_channel)?;
    merge_optional(&mut old.source_order, new.source_order)?;
    merge_optional(&mut old.execution_order, new.execution_order)?;
    merge_optional(&mut old.started, new.started)?;
    merge_optional(&mut old.started_at, new.started_at)?;
    merge_optional(&mut old.ended, new.ended)?;
    merge_optional(&mut old.finished_at, new.finished_at)?;
    merge_optional(&mut old.completion_item_id, new.completion_item_id)?;
    if old.outcome.is_none() && new.outcome.is_some() {
        old.delivery = new.delivery;
    } else if old.outcome.is_some() == new.outcome.is_some() {
        ensure!(
            old.delivery == new.delivery,
            "immutable lifecycle delivery conflict"
        );
    }
    merge_optional(&mut old.outcome, new.outcome)?;
    ensure!(
        old.started
            .zip(old.ended)
            .is_none_or(|(start, end)| start <= end),
        "lifecycle order conflict"
    );
    old.last_write_seq = old.last_write_seq.max(new.last_write_seq);
    Ok(())
}

fn source_parts(source: &ChatSourceId) -> Result<(&'static str, String)> {
    Ok(match source {
        ChatSourceId::ForegroundTurn { turn_id } => ("foregroundTurn", turn_id.clone()),
        ChatSourceId::Input { input_id } => ("input", input_id.clone()),
        ChatSourceId::InboxMessage {
            source_id,
            message_id,
        } => (
            "inboxMessage",
            serde_json::to_string(&(source_id, message_id))?,
        ),
        ChatSourceId::BackgroundResult { message_id } => ("backgroundResult", message_id.clone()),
        ChatSourceId::Operation { operation_id } => ("operation", operation_id.clone()),
        ChatSourceId::Receipt { receipt_id } => ("receipt", receipt_id.clone()),
    })
}

fn source(kind: &str, identity: String) -> Result<ChatSourceId> {
    Ok(match kind {
        "foregroundTurn" => ChatSourceId::ForegroundTurn { turn_id: identity },
        "input" => ChatSourceId::Input { input_id: identity },
        "inboxMessage" => {
            let (source_id, message_id) = serde_json::from_str(&identity)?;
            ChatSourceId::InboxMessage {
                source_id,
                message_id,
            }
        }
        "backgroundResult" => ChatSourceId::BackgroundResult {
            message_id: identity,
        },
        "operation" => ChatSourceId::Operation {
            operation_id: identity,
        },
        "receipt" => ChatSourceId::Receipt {
            receipt_id: identity,
        },
        _ => anyhow::bail!("unsupported lifecycle source kind: {kind}"),
    })
}

fn position(row: &QueryResult, prefix: &str) -> Result<Option<ChatFactPosition>> {
    let effect: Option<i64> = row.try_get("", &format!("{prefix}_effect"))?;
    let suborder: Option<i64> = row.try_get("", &format!("{prefix}_suborder"))?;
    match (effect, suborder) {
        (None, None) => Ok(None),
        (Some(effect), Some(suborder)) => Ok(Some(ChatFactPosition {
            effect_seq: u64::try_from(effect)?,
            suborder: u32::try_from(suborder)?,
        })),
        _ => anyhow::bail!("incomplete lifecycle position"),
    }
}

fn decode(row: &QueryResult) -> Result<ExecutionLifecycle> {
    let call_id: Option<String> = row.try_get("", "call_id")?;
    let tool_name: Option<String> = row.try_get("", "tool_name")?;
    let tool = match (call_id, tool_name) {
        (None, None) => None,
        (Some(call_id), Some(name)) => Some(ChatToolIdentity { call_id, name }),
        _ => anyhow::bail!("incomplete lifecycle tool identity"),
    };
    Ok(ExecutionLifecycle {
        identity: row.try_get("", "identity")?,
        kind: serde_json::from_str(&row.try_get::<String>("", "kind")?)?,
        source: source(
            &row.try_get::<String>("", "source_kind")?,
            row.try_get("", "source_identity")?,
        )?,
        turn_id: row.try_get("", "turn_id")?,
        attempt_id: row.try_get("", "attempt_id")?,
        tool,
        text_channel: row
            .try_get::<Option<String>>("", "text_channel")?
            .map(|v| serde_json::from_str(&v))
            .transpose()?,
        delivery: serde_json::from_str(&row.try_get::<String>("", "delivery")?)?,
        source_order: row
            .try_get::<Option<i64>>("", "source_order")?
            .map(u64::try_from)
            .transpose()?,
        execution_order: row
            .try_get::<Option<i64>>("", "execution_order")?
            .map(u64::try_from)
            .transpose()?,
        started: position(row, "started")?,
        started_at: row.try_get("", "started_at")?,
        ended: position(row, "ended")?,
        finished_at: row.try_get("", "finished_at")?,
        outcome: row
            .try_get::<Option<String>>("", "outcome")?
            .map(|v| serde_json::from_str(&v))
            .transpose()?,
        completion_item_id: row.try_get("", "completion_item_id")?,
        last_write_seq: u64::try_from(row.try_get::<i64>("", "last_write_seq")?)?,
    })
}

pub(super) async fn read(
    db: &impl ConnectionTrait,
    identity: &str,
) -> Result<Option<ExecutionLifecycle>> {
    db.query_one_raw(statement(
        "SELECT * FROM execution_lifecycle WHERE identity=?",
        vec![identity.into()],
    ))
    .await?
    .as_ref()
    .map(decode)
    .transpose()
}

/// 补充真实接纳输入或父消息的执行归属，不改原件、来源、终态或已知顺序。
pub(super) async fn bind_turn(
    db: &impl ConnectionTrait,
    id: &str,
    turn: &str,
    effect: u64,
) -> Result<()> {
    let Some(mut known) = read(db, id).await? else {
        return Ok(());
    };
    if !matches!(
        known.source,
        ChatSourceId::Input { .. } | ChatSourceId::InboxMessage { .. }
    ) {
        return Ok(());
    }
    ensure!(!turn.is_empty(), "empty execution binding");
    if let Some(existing) = known.turn_id.as_deref() {
        ensure!(
            existing == turn,
            "accepted input/message has a conflicting Turn binding"
        );
        return Ok(());
    }
    known.turn_id = Some(turn.into());
    known.last_write_seq = effect;
    apply(db, &[known]).await
}

pub(super) async fn apply(db: &impl ConnectionTrait, facts: &[ExecutionLifecycle]) -> Result<()> {
    for fact in facts {
        let mut value = match read(db, &fact.identity).await? {
            Some(mut old) => {
                merge(&mut old, fact.clone())?;
                old
            }
            None => fact.clone(),
        };
        // A start/end pair in the same effect shares one row and one immutable identity.
        let (source_kind, source_identity) = source_parts(&value.source)?;
        db.execute_raw(statement(
            "INSERT INTO execution_lifecycle(identity,kind,source_kind,source_identity,turn_id,attempt_id,call_id,tool_name,text_channel,delivery,source_order,execution_order,started_effect,started_suborder,started_at,ended_effect,ended_suborder,finished_at,outcome,completion_item_id,last_write_seq)
             VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(identity) DO UPDATE SET
             turn_id=excluded.turn_id,attempt_id=excluded.attempt_id,call_id=excluded.call_id,tool_name=excluded.tool_name,text_channel=excluded.text_channel,delivery=excluded.delivery,source_order=excluded.source_order,execution_order=excluded.execution_order,
             started_effect=excluded.started_effect,started_suborder=excluded.started_suborder,started_at=excluded.started_at,
             ended_effect=excluded.ended_effect,ended_suborder=excluded.ended_suborder,finished_at=excluded.finished_at,outcome=excluded.outcome,completion_item_id=excluded.completion_item_id,last_write_seq=excluded.last_write_seq",
            vec![value.identity.into(), serde_json::to_string(&value.kind)?.into(), source_kind.into(), source_identity.into(),
                value.turn_id.take().into(),value.attempt_id.take().into(),value.tool.as_ref().map(|v|v.call_id.clone()).into(),value.tool.as_ref().map(|v|v.name.clone()).into(),
                value.text_channel.map(|v|serde_json::to_string(&v)).transpose()?.into(),serde_json::to_string(&value.delivery)?.into(),value.source_order.map(integer).transpose()?.into(),value.execution_order.map(integer).transpose()?.into(),
                value.started.map(|v|integer(v.effect_seq)).transpose()?.into(),value.started.map(|v|i64::from(v.suborder)).into(),value.started_at.into(),
                value.ended.map(|v|integer(v.effect_seq)).transpose()?.into(),value.ended.map(|v|i64::from(v.suborder)).into(),value.finished_at.into(),
                value.outcome.map(|v|serde_json::to_string(&v)).transpose()?.into(),value.completion_item_id.take().into(),integer(value.last_write_seq)?.into()],
        )).await?;
    }
    Ok(())
}

pub(super) async fn verify(db: &impl ConnectionTrait, facts: &[ExecutionLifecycle]) -> Result<()> {
    for fact in facts {
        let old = read(db, &fact.identity)
            .await?
            .context("retried lifecycle is missing")?;
        let mut merged = old.clone();
        merge(&mut merged, fact.clone())?;
        ensure!(
            merged == old,
            "retried lifecycle differs from durable facts"
        );
    }
    Ok(())
}

pub(super) async fn active(
    db: &impl ConnectionTrait,
    after: Option<&str>,
    limit: usize,
) -> Result<Vec<ChatAtom>> {
    ensure!(
        (1..=128).contains(&limit),
        "active lifecycle page limit must be 1..=128"
    );
    db.query_all_raw(statement(
        "SELECT * FROM execution_lifecycle INDEXED BY execution_lifecycle_active WHERE ended_effect IS NULL AND outcome IS NULL AND identity>? ORDER BY identity LIMIT ?",
        vec![after.unwrap_or("").into(), integer(limit)?.into()],
    )).await?.iter().map(|row| decode(row)?.active_atom()).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use sea_orm::{Database, TransactionTrait};

    fn started(id: &str) -> ExecutionLifecycle {
        ExecutionLifecycle {
            identity: id.into(),
            kind: ChatAtomKind::ToolCall,
            source: ChatSourceId::ForegroundTurn {
                turn_id: "turn".into(),
            },
            turn_id: Some("turn".into()),
            attempt_id: None,
            tool: Some(ChatToolIdentity {
                call_id: id.into(),
                name: "exec".into(),
            }),
            text_channel: None,
            delivery: ChatDeliveryKind::Foreground,
            source_order: Some(3),
            execution_order: Some(3),
            started: Some(ChatFactPosition {
                effect_seq: 7,
                suborder: 1,
            }),
            started_at: Some(100),
            ended: None,
            finished_at: None,
            outcome: None,
            completion_item_id: None,
            last_write_seq: 7,
        }
    }

    #[tokio::test]
    async fn one_row_survives_start_end_replay_and_conflicting_end_rolls_back() -> Result<()> {
        let db = Database::connect("sqlite::memory:").await?;
        db.execute_unprepared(CREATE).await?;
        let start = started("call");
        let mut end = start.clone();
        end.ended = Some(ChatFactPosition {
            effect_seq: 7,
            suborder: 2,
        });
        end.finished_at = Some(101);
        end.outcome = Some(ChatTerminalOutcome::Transferred);
        end.delivery = ChatDeliveryKind::BackgroundHandoff;
        // Transfer settles the foreground obligation; it does not fabricate a provider completion.
        let tx = db.begin().await?;
        apply(&tx, &[start.clone(), end.clone()]).await?;
        tx.commit().await?;
        verify(&db, &[start.clone(), end.clone()]).await?;
        apply(&db, &[start]).await?;
        assert_eq!(read(&db, "call").await?, Some(end.clone()));
        assert!(active(&db, None, 128).await?.is_empty());
        let tx = db.begin().await?;
        let mut changed = end.clone();
        changed.outcome = Some(ChatTerminalOutcome::Completed);
        assert!(apply(&tx, &[changed]).await.is_err());
        tx.rollback().await?;
        assert_eq!(read(&db, "call").await?, Some(end));
        Ok(())
    }

    #[tokio::test]
    async fn active_keyset_keeps_unknown_ends_out_and_restores_bodyless_starts() -> Result<()> {
        let db = Database::connect("sqlite::memory:").await?;
        db.execute_unprepared(CREATE).await?;
        let mut ended_unknown = started("b");
        ended_unknown.started = None;
        ended_unknown.started_at = None;
        ended_unknown.outcome = Some(ChatTerminalOutcome::Cancelled);
        apply(&db, &[started("a"), ended_unknown, started("c")]).await?;
        let first = active(&db, None, 1).await?;
        assert_eq!(first[0].id, "a");
        let rest = active(&db, Some("a"), 128).await?;
        assert_eq!(
            rest.iter().map(|atom| atom.id.as_str()).collect::<Vec<_>>(),
            ["c"]
        );
        assert!(
            rest[0].payload.is_none()
                && rest[0].contents.is_empty()
                && rest[0].completion_item_id.is_none()
        );
        assert!(active(&db, None, 129).await.is_err());
        let plan = db.query_all_raw(statement("EXPLAIN QUERY PLAN SELECT identity FROM execution_lifecycle WHERE ended_effect IS NULL AND outcome IS NULL AND identity>? ORDER BY identity LIMIT 128", vec!["a".into()])).await?;
        assert!(plan.iter().any(|row| {
            row.try_get::<String>("", "detail")
                .unwrap()
                .contains("execution_lifecycle_active")
        }));
        Ok(())
    }
}
