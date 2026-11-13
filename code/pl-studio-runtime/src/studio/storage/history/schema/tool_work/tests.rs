use super::*;
use crate::studio::thread_projection::presentation::record;
use pl_protocol::{ChatDeliveryKind, ChatFactPosition, ChatToolIdentity, DisplayMemberHead};
use sea_orm::{Database, DatabaseConnection};

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
        .take_while(|m| m.name() != TOOL_WORK)
        .collect()
    }
}

async fn fixture() -> Result<(tempfile::TempDir, DatabaseConnection)> {
    let (dir, db) = display_snapshots::tests::fixture().await?;
    Published20.up(&db, None).await?;
    let checkpoint = pl_core::thread::ThreadCheckpoint::capture(
        THREAD.into(),
        7,
        pl_core::thread::ThreadSnapshot::default(),
    )?;
    write_published_checkpoint(&db, &checkpoint).await?;
    Ok((dir, db))
}

async fn seed(db: &impl ConnectionTrait, index: u64, name: Option<&str>) -> Result<()> {
    let id = format!("block-{index}");
    let completion = format!("completion-{index}");
    let mut atom: ChatAtom = serde_json::from_slice(&conversation::tests::metadata(&completion))?;
    atom.kind = ChatAtomKind::ToolCall;
    atom.source = ChatSourceId::BackgroundResult {
        message_id: format!("inbox-{index}"),
    };
    atom.delivery = ChatDeliveryKind::Independent;
    atom.tool = name.map(|name| ChatToolIdentity {
        call_id: format!("call-{index}"),
        name: name.into(),
    });
    atom.completion_item_id = Some(completion.clone());
    atom.completion_seq = Some(index);
    atom.started_at = (index == 2).then_some(10);
    atom.finished_at = Some(40);
    atom.lifecycle = ChatAtomLifecycle::Terminal {
        started: None,
        ended: Some(ChatFactPosition {
            effect_seq: 1,
            suborder: u32::try_from(index)?,
        }),
        outcome: if index == 2 {
            ChatTerminalOutcome::Failed
        } else {
            ChatTerminalOutcome::Completed
        },
    };
    let metadata = serde_json::to_vec(&atom)?;
    db.execute_raw(statement(
        "INSERT INTO conversation_items(seq,item_id,query_class,parent_id,payload,metadata,display_run_start,display_run_ordinal)
         VALUES(?,?,'conversation',NULL,?,?,?,1)",
        vec![integer(index)?.into(),completion.clone().into(),vec![255u8,0,4].into(),metadata.clone().into(),integer(index)?.into()],
    )).await?;
    db.execute_raw(statement(
        "INSERT INTO conversation_atom_facts(effect_seq,suborder,atom_id,phase,fact_order,metadata)
         VALUES(1,?,?,'terminal',?,?)",
        vec![
            integer(index)?.into(),
            atom.id.clone().into(),
            integer(index)?.into(),
            metadata.into(),
        ],
    ))
    .await?;
    let record = record(atom.clone(), None);
    let head = DisplayHeader {
        version: 2,
        legacy: true,
        id: id.clone(),
        source: atom.source.clone(),
        block_order: index,
        history_pos: Some(index),
        boundary: Some(ChatFactPosition {
            effect_seq: 1,
            suborder: 10,
        }),
        sealed: true,
        unfinished: 0,
        next_member: 1,
        revision: 9,
        skip_display: false,
        active_since: None,
        duration_known: false,
        body: DisplayBlockBody::Single {
            record: Box::new(record.clone()),
        },
    };
    let member = DisplayMemberWrite {
        block_id: id.clone(),
        association_key: crate::studio::thread_projection::presentation::member_key(&atom)?,
        terminal: true,
        head: DisplayMemberHead {
            member_key: format!("member-{index}"),
            member_order: 1,
            record,
        },
    };
    db.execute_raw(statement(
        "INSERT INTO conversation_display_blocks(block_id,source_key,block_order,history_pos,updated_effect,header,sealed)
         VALUES(?,?,?,?,1,?,1)",
        vec![id.clone().into(),serde_json::to_string(&atom.source)?.into(),integer(index)?.into(),integer(index)?.into(),serde_json::to_vec(&head)?.into()],
    )).await?;
    db.execute_raw(statement(
        "INSERT INTO conversation_display_members(block_id,member_order,member_key,terminal,completion_id,updated_effect,metadata,association_key)
         VALUES(?,1,?,1,?,1,?,?)",
        vec![id.into(),member.head.member_key.clone().into(),completion.into(),serde_json::to_vec(&member)?.into(),member.association_key.into()],
    )).await?;
    db.execute_raw(statement(
        "UPDATE history_meta SET display_published_through=?,display_applied_effect=1,applied_write_seq=1 WHERE id=1",
        vec![integer(index)?.into()],
    )).await?;
    Ok(())
}

async fn headers(db: &impl ConnectionTrait) -> Result<Vec<DisplayHeader>> {
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

// SQLite quote() captures exact BLOB bytes, NULLs and the row identities in a stable SQL value.
async fn preserved(db: &impl ConnectionTrait) -> Result<Vec<String>> {
    let mut rows = Vec::new();
    for sql in [
        "SELECT quote(seq)||quote(item_id)||quote(query_class)||quote(parent_id)||quote(payload)||quote(metadata)||quote(display_run_start)||quote(display_run_ordinal) AS snapshot FROM conversation_items ORDER BY seq",
        "SELECT quote(block_id)||quote(member_order)||quote(member_key)||quote(terminal)||quote(completion_id)||quote(updated_effect)||quote(metadata)||quote(association_key) AS snapshot FROM conversation_display_members ORDER BY block_id,member_order",
        "SELECT quote(effect_seq)||quote(suborder)||quote(atom_id)||quote(phase)||quote(fact_order)||quote(metadata) AS snapshot FROM conversation_atom_facts ORDER BY atom_id,phase",
        "SELECT quote(block_id)||quote(source_key)||quote(block_order)||quote(history_pos)||quote(updated_effect)||quote(sealed) AS snapshot FROM conversation_display_blocks ORDER BY block_order",
        "SELECT quote(payload)||quote(payload_hash) AS snapshot FROM session_checkpoint",
        "SELECT quote(database_id)||quote(thread_id)||quote(applied_write_seq)||quote(display_applied_effect)||quote(display_published_through) AS snapshot FROM history_meta",
    ] {
        for row in db.query_all_raw(statement(sql, vec![])).await? {
            rows.push(row.try_get("", "snapshot")?);
        }
    }
    Ok(rows)
}

async fn migrate(db: &DatabaseConnection) -> Result<()> {
    struct WithToolWork;
    impl MigratorTraitSelf for WithToolWork {
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
    WithToolWork.up(db, None).await?;
    Ok(())
}
async fn applied(db: &impl ConnectionTrait) -> Result<i64> {
    Ok(db
        .query_one_raw(statement(
            "SELECT count(*) AS n FROM seaql_migrations WHERE version=?",
            vec![TOOL_WORK.into()],
        ))
        .await?
        .context("migration ledger missing")?
        .try_get("", "n")?)
}

#[tokio::test]
async fn singles_upgrade_in_place_preserving_originals_members_and_reopen_identity() -> Result<()> {
    let (dir, db) = fixture().await?;
    seed(&db, 1, Some("exec")).await?;
    seed(&db, 2, Some("search")).await?;
    seed(&db, 3, Some(pl_tool::file_display::TOOL_SHOW_FILES)).await?;
    let original = headers(&db).await?;
    let facts = preserved(&db).await?;
    assert_eq!(applied(&db).await?, 0);
    migrate(&db).await?;
    assert_eq!(applied(&db).await?, 1);
    let converted = headers(&db).await?;
    for index in 0..2 {
        let mut expected = original[index].clone();
        expected.body = converted[index].body.clone();
        assert_eq!(converted[index], expected, "only the body changes");
        let DisplayBlockBody::Work { summary, members } = &converted[index].body else {
            panic!("Work")
        };
        assert_eq!(
            (summary.total, summary.terminal, summary.running),
            (1, 1, 0)
        );
        assert_eq!(summary.failed, u64::from(index == 1));
        assert_eq!(summary.duration_ms, (index == 1).then_some(30));
        assert_eq!(summary.elapsed_ms, None);
        assert_eq!(summary.created_at, None);
        assert_eq!(members.block_id, original[index].id);
        let page = conversation::display::member_page(&db, &members.block_id, None, 2).await?;
        assert_eq!(page.len(), 1);
        assert_eq!(page[0].head.member_key, format!("member-{}", index + 1));
    }
    assert_eq!(
        converted[2], original[2],
        "file display remains byte-equivalent"
    );
    assert_eq!(preserved(&db).await?, facts);
    migrate(&db).await?;
    assert_eq!(headers(&db).await?, converted);
    db.close().await?;
    let db = Database::connect(format!(
        "sqlite://{}?mode=rw",
        dir.path().join("history.sqlite").display()
    ))
    .await?;
    migrate(&db).await?;
    assert_eq!(headers(&db).await?, converted);
    assert_eq!(applied(&db).await?, 1);
    assert_eq!(preserved(&db).await?, facts);
    prepare(&db, THREAD, Preparation::Schema, None).await?;
    let history = conversation::display::history_heads(&db, 3, None, 8).await?;
    assert_eq!(history.len(), 3);
    assert_eq!(history[0].id, converted[0].id);
    assert!(
        conversation::display::open_heads(&db, None, 8)
            .await?
            .is_empty()
    );
    Ok(())
}

#[tokio::test]
async fn failed_conversion_and_unproved_producer_roll_back_headers_and_ledger() -> Result<()> {
    let (_dir, db) = fixture().await?;
    seed(&db, 1, Some("exec")).await?;
    seed(&db, 2, None).await?;
    let original = headers(&db).await?;
    let facts = preserved(&db).await?;
    let error = migrate(&db).await.unwrap_err();
    assert!(format!("{error:#}").contains("lacks producer identity"));
    assert_eq!(
        headers(&db).await?,
        original,
        "first converted row must roll back too"
    );
    assert_eq!(preserved(&db).await?, facts);
    assert_eq!(applied(&db).await?, 0);
    Ok(())
}

#[tokio::test]
async fn write_failure_is_atomic_and_retry_is_safe() -> Result<()> {
    let (_dir, db) = fixture().await?;
    seed(&db, 1, Some("exec")).await?;
    seed(&db, 2, Some("search")).await?;
    let original = headers(&db).await?;
    let facts = preserved(&db).await?;
    db.execute_unprepared(
        "CREATE TRIGGER reject_tool_work BEFORE UPDATE OF header ON conversation_display_blocks
         WHEN OLD.block_id='block-2' BEGIN SELECT RAISE(ABORT,'injected tool Work failure'); END",
    )
    .await?;
    assert!(migrate(&db).await.is_err());
    assert_eq!(headers(&db).await?, original);
    assert_eq!(preserved(&db).await?, facts);
    assert_eq!(applied(&db).await?, 0);
    db.execute_unprepared("DROP TRIGGER reject_tool_work")
        .await?;
    migrate(&db).await?;
    assert_eq!(applied(&db).await?, 1);
    assert!(
        headers(&db)
            .await?
            .iter()
            .all(|head| matches!(head.body, DisplayBlockBody::Work { .. }))
    );
    assert_eq!(preserved(&db).await?, facts);
    Ok(())
}
