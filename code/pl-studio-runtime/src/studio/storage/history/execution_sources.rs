//! Actual source lifecycle only. Each source has at most one start/end, not a member ledger.
use super::*;
use pl_protocol::{
    ChatFactPosition, ChatSourceId, ChatSourceLifecycle, ChatSourceState, ChatTerminalOutcome,
};
use sea_orm::QueryResult;

pub(in crate::studio::storage::history) const CREATE_SCHEMA: &str = "
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
mod tests {
    use super::*;
    use sea_orm::{ConnectOptions, Database, TransactionTrait};
    fn origin() -> ChatSourceId {
        ChatSourceId::ForegroundTurn {
            turn_id: "turn".into(),
        }
    }
    fn at(effect_seq: u64) -> ChatFactPosition {
        ChatFactPosition {
            effect_seq,
            suborder: 0,
        }
    }
    async fn fixture() -> Result<sea_orm::DatabaseConnection> {
        let mut options = ConnectOptions::new("sqlite::memory:");
        options
            .max_connections(1)
            .min_connections(1)
            .sqlx_logging(false);
        let db = Database::connect(options).await?;
        db.execute_unprepared(CREATE_SCHEMA).await?;
        Ok(db)
    }
    #[tokio::test]
    async fn late_writer_end_preserves_the_start_at_an_earlier_cut() -> Result<()> {
        let db = fixture().await?;
        let start = ChatSourceState {
            source: origin(),
            lifecycle: ChatSourceLifecycle::Active,
            started: Some(at(1)),
            ended: None,
        };
        apply(&db, 1, std::slice::from_ref(&start)).await?;
        let end = ChatSourceState {
            source: origin(),
            lifecycle: ChatSourceLifecycle::Ended {
                outcome: ChatTerminalOutcome::Failed,
            },
            started: Some(at(1)),
            ended: Some(at(3)),
        };
        apply(&db, 3, std::slice::from_ref(&end)).await?;
        assert_eq!(
            read(&db, &[origin()], 1).await?.as_slice(),
            std::slice::from_ref(&start)
        );
        assert_eq!(
            read(&db, &[origin()], 3).await?.as_slice(),
            std::slice::from_ref(&end)
        );
        assert!(matches!(
            read(&db, &[origin()], 0).await?[0].lifecycle,
            ChatSourceLifecycle::Unknown
        ));
        verify(&db, 1, &[start]).await?;
        verify(&db, 3, std::slice::from_ref(&end)).await?;
        let mut changed = end;
        changed.ended = Some(at(4));
        assert!(apply(&db, 4, &[changed]).await.is_err());
        assert!(matches!(
            read(
                &db,
                &[ChatSourceId::Receipt {
                    receipt_id: "missing".into()
                }],
                99
            )
            .await?[0]
                .lifecycle,
            ChatSourceLifecycle::Unknown
        ));
        Ok(())
    }
    #[tokio::test]
    async fn legacy_unknown_start_is_not_fabricated_and_source_transaction_rolls_back() -> Result<()>
    {
        let db = fixture().await?;
        let old = ChatSourceState {
            source: origin(),
            lifecycle: ChatSourceLifecycle::Active,
            started: None,
            ended: None,
        };
        apply(&db, 7, std::slice::from_ref(&old)).await?;
        let tx = db.begin().await?;
        apply(
            &tx,
            9,
            &[ChatSourceState {
                source: origin(),
                lifecycle: ChatSourceLifecycle::Ended {
                    outcome: ChatTerminalOutcome::Cancelled,
                },
                started: None,
                ended: Some(at(9)),
            }],
        )
        .await?;
        tx.rollback().await?;
        assert_eq!(read(&db, &[origin()], 8).await?, [old]);
        assert!(matches!(
            read(&db, &[origin()], 6).await?[0].lifecycle,
            ChatSourceLifecycle::Unknown
        ));
        Ok(())
    }

    #[tokio::test]
    async fn original_pages_do_not_query_unrelated_or_current_source_rows() -> Result<()> {
        use crate::studio::storage::history::{HistoryStore, conversation};
        use pl_core::chat::{ChatDraft, ChatItem, ChatKey, ChatQuery, ReadDemand};
        let dir = tempfile::tempdir()?;
        let store =
            HistoryStore::open(&dir.path().join("history.sqlite"), "source-snapshot").await?;
        store.prepare_write().await?;
        let writer = store.writer().await?;
        let parent = ChatKey::new("turn", "actual-parent")?;
        let mut draft = ChatDraft::new("selected", "conversation", Arc::from([255; 8192]));
        draft.metadata = conversation::tests::metadata("selected");
        draft.parent_id = Some(parent.clone());
        let item = ChatItem::complete(draft, 1);
        let mut draft = ChatDraft::new("not-selected", "diagnostic", Arc::from([]));
        draft.metadata = Arc::from(br#"{"unrecognized":"opaque"}"#.as_slice());
        let skipped = ChatItem::complete(draft, 2);
        conversation::append_records(&writer.db, [&item, &skipped], true).await?;
        let started = ChatSourceState {
            source: origin(),
            lifecycle: ChatSourceLifecycle::Active,
            started: Some(at(1)),
            ended: None,
        };
        apply(&writer.db, 1, std::slice::from_ref(&started)).await?;
        writer
            .db
            .execute_unprepared("UPDATE history_meta SET applied_write_seq=2")
            .await?;
        let snapshot = writer.db.begin().await?;
        assert_eq!(read(&snapshot, &[origin()], 1).await?, [started.clone()]);
        snapshot.commit().await?;
        writer.db.execute_raw(statement("UPDATE conversation_sources SET ended_observed=2,outcome='invalid lifecycle JSON' WHERE source_key=?",vec![source_key(&origin())?.into()])).await?;
        assert!(store.conversation_sources(&[origin()], 2).await.is_err());
        let cold = store
            .cold_conversation(
                ChatQuery::new("conversation", Some(parent)),
                ReadDemand::new(10, 4096),
                &conversation::tests::Budget,
            )
            .await?
            .context("original cut")?;
        assert_eq!(cold.head, 2);
        assert_eq!(cold.page.items.len(), 1);
        assert_eq!(cold.page.items[0].header.item_id, "selected");
        store.close_for_deletion().await?;
        Ok(())
    }

    #[tokio::test]
    async fn older_effect_retry_verifies_source_identity_position_and_lifecycle_after_later_end()
    -> Result<()> {
        use crate::studio::storage::history::{EffectCommit, HistoryStore, test_current};
        fn commit<'a>(
            current: &'a super::conversation::current::PreparedCurrent,
            empty: &'a std::collections::BTreeSet<String>,
        ) -> EffectCommit<'a> {
            EffectCommit {
                turns: &[],
                execution_order: 0,
                completions: &[],
                current,
                rolled_back_turns: empty,
                identities: &[],
                messages: &[],
                receipts: &[],
                tasks: &[],
                deliveries: &[],
                delivery_repairs: &[],
                attempt: None,
            }
        }
        let dir = tempfile::tempdir()?;
        let store =
            HistoryStore::open(&dir.path().join("history.sqlite"), "old-source-retry").await?;
        let empty = std::collections::BTreeSet::new();
        let start = ChatSourceState {
            source: origin(),
            lifecycle: ChatSourceLifecycle::Active,
            started: Some(at(1)),
            ended: None,
        };
        let mut first = test_current(1);
        first.source_changes = Arc::from([start.clone()]);
        store.commit_effect(1, commit(&first, &empty)).await?;
        let end = ChatSourceState {
            source: origin(),
            lifecycle: ChatSourceLifecycle::Ended {
                outcome: ChatTerminalOutcome::Completed,
            },
            started: Some(at(1)),
            ended: Some(at(2)),
        };
        let mut second = test_current(2);
        second.source_changes = Arc::from([end.clone()]);
        store.commit_effect(2, commit(&second, &empty)).await?;
        store.commit_effect(1, commit(&first, &empty)).await?;
        let mut changed_identity = start.clone();
        changed_identity.source = ChatSourceId::ForegroundTurn {
            turn_id: "different".into(),
        };
        let mut changed_position = start.clone();
        changed_position.started.as_mut().unwrap().suborder = 9;
        let mut changed_lifecycle = start;
        changed_lifecycle.lifecycle = ChatSourceLifecycle::Unknown;
        for changed in [changed_identity, changed_position, changed_lifecycle] {
            let mut conflicting = first.clone();
            conflicting.source_changes = Arc::from([changed]);
            assert!(
                store
                    .commit_effect(1, commit(&conflicting, &empty))
                    .await
                    .is_err()
            );
        }
        assert_eq!(store.watermark().await?, 2);
        assert_eq!(store.conversation_sources(&[origin()], 2).await?, [end]);
        Ok(())
    }
}
