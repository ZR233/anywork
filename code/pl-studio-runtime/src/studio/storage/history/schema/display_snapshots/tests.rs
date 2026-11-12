use super::*;
use sea_orm::{Database, DatabaseConnection};
use sea_orm_migration::MigratorTraitSelf;

const THREAD: &str = "display-snapshot-migration";
struct Published18;
impl MigratorTraitSelf for Published18 {
    fn migrations(&self) -> Vec<Box<dyn MigrationTrait>> {
        Migrator {
            thread_id: THREAD.into(),
            execution_identity: None,
            bot_root: None,
        }
        .migrations()
        .into_iter()
        .take_while(|m| m.name() != DISPLAY_SNAPSHOTS)
        .collect()
    }
}
pub(in crate::studio::storage::history) async fn fixture()
-> Result<(tempfile::TempDir, DatabaseConnection)> {
    let dir = tempfile::tempdir()?;
    let mut options = sea_orm::ConnectOptions::new(format!(
        "sqlite://{}?mode=rwc",
        dir.path().join("history.sqlite").display()
    ));
    options
        .max_connections(1)
        .min_connections(1)
        .sqlx_logging(false);
    let db = Database::connect(options).await?;
    Published18.up(&db, None).await?;
    Ok((dir, db))
}
async fn migrate(db: &DatabaseConnection) -> Result<()> {
    prepare(db, THREAD, Preparation::Schema, None).await
}
async fn seed(db: &impl ConnectionTrait) -> Result<Vec<Vec<u8>>> {
    let mut original = Vec::new();
    for seq in 1..=260u64 {
        let mut atom: ChatAtom =
            serde_json::from_slice(&conversation::tests::metadata(&format!("original-{seq}")))?;
        atom.source = pl_protocol::ChatSourceId::ForegroundTurn {
            turn_id: "前台:real".into(),
        };
        atom.kind = if seq == 130 {
            pl_protocol::ChatAtomKind::Inference
        } else if seq == 131 {
            pl_protocol::ChatAtomKind::Text
        } else {
            pl_protocol::ChatAtomKind::ToolCall
        };
        atom.delivery = pl_protocol::ChatDeliveryKind::Foreground;
        let (start, ordinal) = if seq == 130 {
            (None, None)
        } else if seq == 131 {
            (Some(131), Some(1))
        } else if seq < 130 {
            (Some(1), Some(seq))
        } else {
            (Some(132), Some(seq - 131))
        };
        let payload = vec![255, 0, seq as u8, 13, 10];
        let metadata = serde_json::to_vec(&atom)?;
        original.push(metadata.clone());
        db.execute_raw(statement(
            "INSERT INTO conversation_items(seq,item_id,query_class,parent_id,payload,metadata,display_run_start,display_run_ordinal)
             VALUES(?,?,'conversation',NULL,?,?,?,?)",
            vec![integer(seq)?.into(), format!("original-{seq}").into(), payload.into(), metadata.into(),
                start.map(integer).transpose()?.into(), ordinal.map(integer).transpose()?.into()]
        )).await?;
    }
    Ok(original)
}

#[tokio::test]
async fn nonempty_v18_is_preserved_and_reopens_directly_from_frozen_snapshots() -> Result<()> {
    let (_dir, db) = fixture().await?;
    let original = seed(&db).await?;
    migrate(&db).await?;
    assert_eq!(version(&db).await?, 21);
    let rows = db
        .query_all_raw(statement(
            "SELECT seq,item_id,metadata,payload FROM conversation_items ORDER BY seq",
            vec![],
        ))
        .await?;
    for (index, row) in rows.iter().enumerate() {
        let seq = index as u64 + 1;
        assert_eq!(row.try_get::<i64>("", "seq")?, seq as i64);
        assert_eq!(
            row.try_get::<String>("", "item_id")?,
            format!("original-{seq}")
        );
        assert_eq!(row.try_get::<Vec<u8>>("", "metadata")?, original[index]);
        assert_eq!(
            row.try_get::<Vec<u8>>("", "payload")?,
            vec![255, 0, seq as u8, 13, 10]
        );
    }
    let history = conversation::display::history_heads(&db, 3, None, 8).await?;
    assert_eq!(history.len(), 3);
    assert_eq!(
        history[0].id,
        serde_json::to_string(&(
            "legacy-run",
            db.query_one_raw(statement(
                "SELECT database_id FROM history_meta WHERE id=1",
                vec![]
            ))
            .await?
            .unwrap()
            .try_get::<String>("", "database_id")?,
            1
        ))?
    );
    assert!(
        matches!(&history[0].body, pl_protocol::DisplayBlockBody::Work { summary, .. }
            if summary.total == 129 && summary.created_at.is_none() && summary.elapsed_ms.is_none())
    );
    let members = conversation::display::member_page(&db, &history[2].id, Some(129), 2).await?;
    assert_eq!(
        members
            .iter()
            .map(|m| m.head.member_order)
            .collect::<Vec<_>>(),
        vec![127, 128]
    );
    assert!(matches!(
        members[0].head.record.atom.payload,
        Some(pl_protocol::PayloadData::Deferred { .. })
    ));
    db.execute_unprepared("CREATE TRIGGER no_rewrite BEFORE UPDATE ON conversation_items BEGIN SELECT RAISE(ABORT,'must not rebuild'); END;").await?;
    super::super::visible_tail_workgroups::validate(&db).await?;
    assert_eq!(
        conversation::display::history_heads(&db, 3, None, 8).await?,
        history
    );
    assert!(
        SchemaManager::new(&db)
            .has_table("completion_boundary_archive_contents")
            .await?
    );
    Ok(())
}

#[tokio::test]
async fn migration_failures_rollback_tables_rows_version_and_applied() -> Result<()> {
    for failure in ["version", "applied", "bad-reference"] {
        let (_dir, db) = fixture().await?;
        let original = seed(&db).await?;
        if failure == "bad-reference" {
            db.execute_unprepared(
                "UPDATE conversation_items SET display_run_ordinal=999 WHERE seq=129",
            )
            .await?;
        } else {
            let sql = if failure == "version" {
                "CREATE TRIGGER injected BEFORE UPDATE ON history_meta WHEN NEW.schema_version=19 BEGIN SELECT RAISE(ABORT,'version failure'); END;"
            } else {
                "CREATE TRIGGER injected BEFORE INSERT ON seaql_migrations WHEN NEW.version='m20261109_000001_display_snapshots' BEGIN SELECT RAISE(ABORT,'Applied failure'); END;"
            };
            db.execute_unprepared(sql).await?;
        }
        assert!(migrate(&db).await.is_err(), "{failure}");
        assert_eq!(version(&db).await?, 18);
        assert!(
            !SchemaManager::new(&db)
                .has_table("conversation_display_blocks")
                .await?
        );
        assert!(
            db.query_one_raw(statement(
                "SELECT 1 FROM seaql_migrations WHERE version=?",
                vec![DISPLAY_SNAPSHOTS.into()]
            ))
            .await?
            .is_none()
        );
        let rows = db
            .query_all_raw(statement(
                "SELECT metadata FROM conversation_items ORDER BY seq",
                vec![],
            ))
            .await?;
        assert_eq!(
            rows.iter()
                .map(|r| r.try_get::<Vec<u8>>("", "metadata"))
                .collect::<std::result::Result<Vec<_>, _>>()?,
            original
        );
    }
    Ok(())
}

#[tokio::test]
async fn applied_snapshot_loss_fails_closed_and_runner_keeps_explicit_order() -> Result<()> {
    let migrations = Migrator {
        thread_id: THREAD.into(),
        execution_identity: None,
        bot_root: None,
    }
    .migrations();
    let names = migrations.iter().map(|m| m.name()).collect::<Vec<_>>();
    let previous = names
        .iter()
        .position(|n| *n == IMMUTABLE_COMPLETION_RUNS)
        .unwrap();
    assert_eq!(names[previous + 1], DISPLAY_SNAPSHOTS);
    let (_dir, db) = fixture().await?;
    seed(&db).await?;
    migrate(&db).await?;
    db.execute_unprepared("DELETE FROM conversation_display_members WHERE block_id=(SELECT block_id FROM conversation_display_blocks WHERE history_pos=3);
        DELETE FROM conversation_display_blocks WHERE history_pos=3;").await?;
    assert!(validate(&db).await.is_err());
    assert!(preflight(&db, THREAD).await.is_err());
    Ok(())
}
