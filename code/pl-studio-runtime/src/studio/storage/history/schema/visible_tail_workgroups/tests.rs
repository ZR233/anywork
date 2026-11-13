use super::*;
use crate::studio::thread_projection::presentation::{PresentationState, record};
use pl_protocol::{
    ChatActiveStatus, ChatAtomKind, ChatDeliveryKind, ChatFactPosition, ChatSourceId,
    ChatTerminalOutcome, DisplayBlockRef, DisplayMemberHead, WorkSummary,
};

const THREAD: &str = "display-snapshot-migration";
struct Published20;
impl MigratorTraitSelf for Published20 {
    fn migrations(&self) -> Vec<Box<dyn MigrationTrait>> {
        Migrator {
            thread_id: THREAD.into(),
            execution_identity: None,
            bot_root: None,
        }
        .migrations()
        .into_iter()
        .take_while(|step| step.name() != VISIBLE_TAIL_WORKGROUPS)
        .collect()
    }
}
struct Published21;
impl MigratorTraitSelf for Published21 {
    fn migrations(&self) -> Vec<Box<dyn MigrationTrait>> {
        Migrator {
            thread_id: THREAD.into(),
            execution_identity: None,
            bot_root: None,
        }
        .migrations()
        .into_iter()
        .take_while(|step| step.name() != PROJECT_KIND)
        .collect()
    }
}
async fn fixture() -> Result<(tempfile::TempDir, DatabaseConnection)> {
    let (dir, db) = display_snapshots::tests::fixture().await?;
    Published20.up(&db, None).await?;
    Ok((dir, db))
}
fn at(effect_seq: u64) -> ChatFactPosition {
    ChatFactPosition {
        effect_seq,
        suborder: 1,
    }
}

async fn seed(db: &impl ConnectionTrait, order: u64, single: bool, terminal: bool) -> Result<()> {
    use display_observations::legacy::{DisplayBlockBody as Body20, DisplayHeader as Header20};
    let id = format!("old-{order}");
    let mut atom: pl_protocol::ChatAtom =
        serde_json::from_slice(&conversation::tests::metadata(&id))?;
    atom.id = format!("atom-{order}");
    atom.kind = if single {
        ChatAtomKind::Text
    } else {
        ChatAtomKind::ToolCall
    };
    atom.source = ChatSourceId::ForegroundTurn {
        turn_id: format!("turn-{order}"),
    };
    atom.delivery = ChatDeliveryKind::Foreground;
    atom.completion_item_id = None;
    atom.completion_seq = None;
    atom.payload = None;
    atom.contents.clear();
    atom.lifecycle = if terminal {
        ChatAtomLifecycle::Terminal {
            started: None,
            ended: Some(at(order)),
            outcome: ChatTerminalOutcome::Cancelled,
        }
    } else {
        ChatAtomLifecycle::Active {
            started: Some(at(order)),
            status: ChatActiveStatus::Running,
        }
    };
    let record = record(atom.clone(), (!terminal).then_some(at(order)));
    let member = DisplayMemberWrite {
        block_id: id.clone(),
        association_key: member_key(&atom)?,
        terminal,
        head: DisplayMemberHead {
            member_key: format!("old-key-{order}"),
            member_order: 1,
            record: record.clone(),
        },
    };
    let database: String = db
        .query_one_raw(statement(
            "SELECT database_id FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .unwrap()
        .try_get("", "database_id")?;
    let header = Header20 {
        version: 2,
        legacy: false,
        id: id.clone(),
        source: atom.source,
        block_order: order,
        history_pos: single.then_some(1),
        boundary: single.then_some(at(order)),
        sealed: single,
        unfinished: u64::from(!terminal),
        next_member: 1,
        revision: 1,
        skip_display: false,
        active_since: None,
        duration_known: false,
        body: if single {
            Body20::Single {
                record: Box::new(record),
            }
        } else {
            Body20::Work {
                summary: Box::new(WorkSummary {
                    total: 1,
                    terminal: u64::from(terminal),
                    running: u64::from(!terminal),
                    cancelled: u64::from(terminal),
                    ..Default::default()
                }),
                members: DisplayBlockRef {
                    database_id: database,
                    block_id: id.clone(),
                },
            }
        },
    };
    db.execute_raw(statement(
        "INSERT INTO conversation_display_blocks(block_id,source_key,block_order,history_pos,sealed,updated_effect,header)
         VALUES(?,?,?,?,?,10,?)",
        vec![id.clone().into(), serde_json::to_string(&header.source)?.into(), integer(order)?.into(),
            header.history_pos.map(integer).transpose()?.into(), i64::from(single).into(), serde_json::to_vec(&header)?.into()],
    )).await?;
    db.execute_raw(statement(
        "INSERT INTO conversation_display_members(block_id,member_order,member_key,association_key,terminal,completion_id,updated_effect,metadata)
         VALUES(?,1,?,?,?,NULL,10,?)",
        vec![id.into(), member.head.member_key.clone().into(), member.association_key.clone().into(),
            i64::from(terminal).into(), serde_json::to_vec(&member)?.into()],
    )).await?;
    db.execute_raw(statement(
        "UPDATE history_meta SET applied_write_seq=10,display_applied_effect=10,display_published_through=? WHERE id=1",
        vec![integer(u64::from(single).max(conversation::display::watermarks(db).await?.0))?.into()],
    )).await?;
    Ok(())
}

async fn heads(db: &impl ConnectionTrait) -> Result<Vec<DisplayHeader>> {
    db.query_all_raw(statement(
        "SELECT header FROM conversation_display_blocks ORDER BY block_order",
        vec![],
    ))
    .await?
    .into_iter()
    .map(|row| {
        Ok(serde_json::from_slice(
            &row.try_get::<Vec<u8>>("", "header")?,
        )?)
    })
    .collect()
}

#[tokio::test]
async fn v364_migration_uses_the_last_block_including_a_published_single_and_is_idempotent()
-> Result<()> {
    let (_dir, db) = fixture().await?;
    seed(&db, 1, false, false).await?;
    seed(&db, 2, false, false).await?;
    seed(&db, 3, true, true).await?;
    Published21.up(&db, None).await?;
    let converted = heads(&db).await?;
    assert_eq!(
        converted.iter().map(|h| h.history_pos).collect::<Vec<_>>(),
        [Some(2), Some(3), Some(1)]
    );
    assert!(
        converted
            .iter()
            .all(|h| h.sealed && h.version == 3 && h.first_content_at.is_none())
    );
    for header in &converted[..2] {
        let DisplayBlockBody::Work { summary, .. } = &header.body else {
            panic!("Work")
        };
        assert_eq!(
            (summary.unavailable, summary.running, summary.waiting),
            (1, 0, 0)
        );
        let page = conversation::display::member_page(&db, &header.id, None, 1).await?;
        assert_eq!(
            page[0].head.member_key,
            format!("old-key-{}", header.block_order)
        );
        assert!(matches!(
            page[0].head.record.content_source,
            DisplayContentSource::FrozenObservation {
                available: false,
                ..
            }
        ));
        assert!(page[0].head.record.atom.contents.is_empty());
        assert!(!page[0].terminal);
    }
    assert!(conversation::display::recovery(&db).await?.open.is_empty());
    Published21.up(&db, None).await?;
    assert_eq!(heads(&db).await?, converted);
    assert_eq!(version(&db).await?, 21);
    Ok(())
}

#[tokio::test]
async fn v364_migration_retains_only_the_legal_terminal_tail_and_cold_append_keeps_its_id()
-> Result<()> {
    let (_dir, db) = fixture().await?;
    seed(&db, 1, false, false).await?;
    seed(&db, 2, false, true).await?;
    Published21.up(&db, None).await?;
    let recovered = conversation::display::recovery(&db).await?;
    assert_eq!(recovered.open.len(), 1);
    assert_eq!(recovered.open[0].id, "old-2");
    assert!(!recovered.open[0].sealed);
    assert_eq!(recovered.open[0].unfinished, 0);
    assert!(recovered.unfinished.is_empty());
    let database: String = db
        .query_one_raw(statement(
            "SELECT database_id FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .unwrap()
        .try_get("", "database_id")?;
    let mut owner = PresentationState::default();
    owner.restore(
        &database,
        recovered.published,
        recovered.last_order,
        recovered.effect,
        recovered.open,
        recovered.unfinished,
    )?;
    let mut atom: pl_protocol::ChatAtom =
        serde_json::from_slice(&conversation::tests::metadata("resumed"))?;
    atom.kind = ChatAtomKind::ToolCall;
    atom.tool = Some(pl_protocol::ChatToolIdentity {
        call_id: "resumed".into(),
        name: "exec".into(),
    });
    atom.source = ChatSourceId::BackgroundResult {
        message_id: "new-background".into(),
    };
    atom.delivery = ChatDeliveryKind::Independent;
    atom.completion_item_id = None;
    atom.payload = None;
    atom.contents.clear();
    atom.lifecycle = ChatAtomLifecycle::Terminal {
        started: None,
        ended: Some(at(11)),
        outcome: ChatTerminalOutcome::Cancelled,
    };
    let delta = owner.prepare(11, 1_000_000, &[atom], &[], &[])?;
    assert_eq!(delta.blocks.len(), 1);
    assert_eq!(delta.blocks[0].header.id, "old-2");
    assert_eq!(
        owner.capture(None, 1, 0, 1).current_work_id.as_deref(),
        Some("old-2")
    );
    Ok(())
}

#[tokio::test]
async fn v364_migration_failure_rolls_back_headers_positions_schema_and_applied() -> Result<()> {
    let (_dir, db) = fixture().await?;
    seed(&db, 1, false, false).await?;
    seed(&db, 2, true, true).await?;
    let before = db
        .query_all_raw(statement(
            "SELECT header FROM conversation_display_blocks ORDER BY block_order",
            vec![],
        ))
        .await?
        .into_iter()
        .map(|r| r.try_get::<Vec<u8>>("", "header"))
        .collect::<std::result::Result<Vec<_>, _>>()?;
    db.execute_unprepared(
        "CREATE TRIGGER reject_tail BEFORE UPDATE OF schema_version ON history_meta
         WHEN NEW.schema_version=21 BEGIN SELECT RAISE(ABORT,'injected tail migration failure'); END;"
    ).await?;
    assert!(Published21.up(&db, None).await.is_err());
    assert_eq!(version(&db).await?, 20);
    let after = db
        .query_all_raw(statement(
            "SELECT header FROM conversation_display_blocks ORDER BY block_order",
            vec![],
        ))
        .await?
        .into_iter()
        .map(|r| r.try_get::<Vec<u8>>("", "header"))
        .collect::<std::result::Result<Vec<_>, _>>()?;
    assert_eq!(after, before);
    assert_eq!(conversation::display::watermarks(&db).await?, (1, 10));
    assert!(
        db.query_one_raw(statement(
            "SELECT 1 FROM seaql_migrations WHERE version=?",
            vec![VISIBLE_TAIL_WORKGROUPS.into()]
        ))
        .await?
        .is_none()
    );
    db.execute_unprepared("DROP TRIGGER reject_tail").await?;
    Published21.up(&db, None).await?;
    validate(&db).await?;
    Ok(())
}

#[tokio::test]
async fn v364_applied_missing_unfinished_member_is_rejected_without_reconstruction() -> Result<()> {
    let (_dir, db) = fixture().await?;
    seed(&db, 1, false, false).await?;
    Published21.up(&db, None).await?;
    let before = heads(&db).await?;
    db.execute_unprepared("DELETE FROM conversation_display_members WHERE block_id='old-1'")
        .await?;
    assert!(validate(&db).await.is_err());
    assert_eq!(heads(&db).await?, before);
    assert_eq!(version(&db).await?, 21);
    Ok(())
}
