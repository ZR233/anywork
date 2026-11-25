use super::test_support::{v3_database, work_status};
use super::*;

#[tokio::test]
async fn failed_migrations_preserve_legacy_rows_and_report_the_pending_step() -> anyhow::Result<()>
{
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("bot-state.sqlite");
    let legacy = v3_database(&path).await;
    legacy.execute_unprepared("CREATE TRIGGER reject_ledger_migration BEFORE UPDATE ON bot_meta BEGIN SELECT RAISE(ABORT,'injected ledger migration failure'); END").await?;
    legacy.close().await?;

    let failed = BotStateStore::new(path.clone());
    let failure = failed
        .list_due_inbound("legacy")
        .await
        .expect_err("ledger migration must fail");
    assert!(
        failure
            .to_string()
            .contains("m20261026_000001_bot_ledger_schema")
    );
    assert!(
        failure
            .to_string()
            .contains("injected ledger migration failure")
    );
    drop(failed);
    let probe = Database::connect(
        sqlite_file_options(&path, SqliteFileMode::ReadWrite, |options| options).await?,
    )
    .await?;
    assert_eq!(
        probe
            .query_one_raw(statement(
                "SELECT schema_version FROM bot_meta WHERE id=1",
                vec![]
            ))
            .await?
            .unwrap()
            .try_get::<i64>("", "schema_version")?,
        3
    );
    assert!(
        probe
            .query_one_raw(statement("SELECT version FROM seaql_migrations", vec![]))
            .await?
            .is_none()
    );
    assert_eq!(
        probe
            .query_one_raw(statement(
                "SELECT text FROM inbound_work WHERE identity='legacy:chat:m1'",
                vec![]
            ))
            .await?
            .unwrap()
            .try_get::<String>("", "text")?,
        "question"
    );
    probe
        .execute_unprepared("DROP TRIGGER reject_ledger_migration")
        .await?;
    probe
        .execute_unprepared(
            "CREATE TRIGGER reject_workspace_migration BEFORE UPDATE ON bot_meta
         WHEN NEW.schema_version=7
         BEGIN SELECT RAISE(ABORT,'injected ownership migration failure'); END",
        )
        .await?;
    probe.close().await?;

    let failed_ownership = BotStateStore::new(path.clone());
    let ownership_failure = failed_ownership
        .list_due_inbound("legacy")
        .await
        .expect_err("ownership migration must roll back")
        .to_string();
    assert!(
        ownership_failure.contains("injected ownership migration failure"),
        "{ownership_failure}"
    );
    // 失败步骤来自迁移后的真实待执行列表，而非硬编码的首条迁移名。
    assert!(
        ownership_failure.contains("m20261030_000002_bot_workspace_ownership"),
        "{ownership_failure}"
    );
    assert!(
        !ownership_failure.contains("m20261026_000001_bot_ledger_schema"),
        "{ownership_failure}"
    );
    let probe = Database::connect(
        sqlite_file_options(&path, SqliteFileMode::ReadWrite, |options| options).await?,
    )
    .await?;
    let manager = sea_orm_migration::SchemaManager::new(&probe);
    for table in ["inbound_work", "thread_bindings"] {
        assert!(manager.has_column(table, "project_id").await?);
        assert!(!manager.has_column(table, "workspace_id").await?);
    }
    let version: i64 = probe
        .query_one_raw(statement(
            "SELECT schema_version FROM bot_meta WHERE id=1",
            vec![],
        ))
        .await?
        .unwrap()
        .try_get("", "schema_version")?;
    assert_eq!(version, 6, "only the prior official migration committed");
    probe
        .execute_unprepared("DROP TRIGGER reject_workspace_migration")
        .await?;
    probe.close().await?;

    let store = BotStateStore::new(path);
    assert_eq!(store.list_due_inbound("legacy").await?.len(), 1);
    Ok(())
}

#[tokio::test]
async fn legacy_ledger_migration_preserves_work_binding_and_send() -> anyhow::Result<()> {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("bot-state.sqlite");
    v3_database(&path).await.close().await?;
    let store = BotStateStore::new(path.clone());
    // 旧 claimed 行与绑定、发送事实仍在，schema 升到当前版本。
    let due = store.list_due_inbound("legacy").await?;
    assert_eq!(due.len(), 1);
    assert_eq!(due[0].message_id, "m1");
    assert_eq!(due[0].text, "question");
    assert!(due[0].attachments.is_empty());
    assert_eq!(due[0].watch_input, "");
    let db = store.db().await?;
    assert!(
        db.query_one_raw(statement(
            "SELECT thread_id FROM thread_bindings WHERE chat_id='chat' AND thread_id='thread-1'",
            vec![],
        ))
        .await?
        .is_some(),
        "migrated binding survives"
    );
    assert!(
        db.query_one_raw(statement(
            "SELECT status FROM send_operations WHERE operation_id='op-1' AND status='succeeded'",
            vec![],
        ))
        .await?
        .is_some(),
        "migrated send fact survives"
    );
    let version: i64 = db
        .query_one_raw(statement(
            "SELECT schema_version FROM bot_meta WHERE id=1",
            vec![],
        ))
        .await?
        .unwrap()
        .try_get("", "schema_version")?;
    assert_eq!(version, BOT_STATE_SCHEMA_VERSION);
    for table in ["inbound_work", "thread_bindings"] {
        let row = db
            .query_one_raw(statement(
                &format!("SELECT workspace_id FROM {table} LIMIT 1"),
                vec![],
            ))
            .await?
            .unwrap();
        assert_eq!(row.try_get::<String>("", "workspace_id")?, "project");
    }

    let sent = store.load_send("op-1").await?.expect("preserved send");
    assert_eq!(sent.platform_message_ids, ["pm-1"]);
    assert!(!sent.facts_complete);
    assert_eq!(
        sent.segments[0].platform_message_id.as_deref(),
        Some("pm-1")
    );
    Ok(())
}

#[tokio::test]
async fn expired_legacy_claim_is_fenced_and_successor_can_complete() -> anyhow::Result<()> {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("bot-state.sqlite");
    v3_database(&path).await.close().await?;
    let store = BotStateStore::new(path);
    // 过期旧身份不得自认续权：迁移前 crash 的 worker 的租约已过期，
    // renew/finish 都被有效 lease 条件拒绝，行不被旧持有者改写。
    assert_eq!(
        store
            .renew_inbound_claim("legacy", "chat", "m1", "crashed-worker")
            .await?,
        ClaimLease::LostClaim
    );
    assert_eq!(
        store
            .finish_inbound_work(
                "legacy",
                "chat",
                "m1",
                "crashed-worker",
                WorkFinish::Completed
            )
            .await?,
        MarkOutcome::LostClaim
    );
    let (status, claimed_by) = work_status(&store, "legacy:chat:m1").await;
    assert_eq!(status, "claimed");
    assert_eq!(claimed_by, "crashed-worker");

    // 后继新 worker 对到期槽竞争接管成功，且在有效租约内可续约与收束。
    assert_eq!(
        store
            .claim_inbound_work("legacy", "chat", "m1", "w1")
            .await?,
        InboundClaim::Claimed
    );
    assert_eq!(
        store
            .renew_inbound_claim("legacy", "chat", "m1", "w1")
            .await?,
        ClaimLease::Renewed
    );
    assert_eq!(
        store
            .finish_inbound_work("legacy", "chat", "m1", "w1", WorkFinish::Completed)
            .await?,
        MarkOutcome::Applied
    );
    let (status, claimed_by) = work_status(&store, "legacy:chat:m1").await;
    assert_eq!(status, "completed");
    assert_eq!(claimed_by, "");
    Ok(())
}

#[tokio::test]
async fn migrated_ledger_reopens_media_without_duplicate_admission() -> anyhow::Result<()> {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("bot-state.sqlite");
    v3_database(&path).await.close().await?;
    let store = BotStateStore::new(path.clone());
    let seed = store.list_due_inbound("legacy").await?.remove(0);
    assert_eq!(
        store
            .claim_inbound_work("legacy", "chat", "m1", "w1")
            .await?,
        InboundClaim::Claimed
    );
    assert_eq!(
        store
            .finish_inbound_work("legacy", "chat", "m1", "w1", WorkFinish::Completed)
            .await?,
        MarkOutcome::Applied
    );
    // New media work must survive a process boundary alongside the migrated text row.
    let mut media = seed;
    media.message_id = "media-after-migration".into();
    media.content_hash = "media-content".into();
    media.attachments = vec![
        crate::bots::inbound::InboundAttachment::File {
            key: "file-key".into(),
            filename: "中文证据.txt".into(),
        },
        crate::bots::inbound::InboundAttachment::Image {
            key: "image-key".into(),
        },
    ];
    assert!(matches!(
        store.admit_inbound(media.clone()).await?,
        InboundAdmit::Fresh(_)
    ));
    drop(store);
    let reopened = BotStateStore::new(path);
    let restored = reopened.list_due_inbound("legacy").await?;
    assert_eq!(restored, vec![media.clone()]);
    assert_eq!(
        reopened.admit_inbound(media.clone()).await?,
        InboundAdmit::DuplicateResume(media)
    );
    assert_eq!(reopened.list_due_inbound("legacy").await?.len(), 1);
    Ok(())
}

#[tokio::test]
async fn ledger_adopts_current_file_and_refuses_future_writes() -> anyhow::Result<()> {
    for fault in ["format", "migration", "missing_table"] {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("ledger.sqlite");
        let original = open_bot_state(&path).await?;
        original.execute_unprepared(
            "INSERT INTO inbound_work(identity,workspace_id,text,status,diagnostic,updated_at)
             VALUES('current-inbound','current-workspace','preserved input','replied','preserved diagnostic',42);
             INSERT INTO thread_bindings(chat_id,thread_id,workspace_id,created_at)
             VALUES('current-chat','current-thread','current-workspace',42)",
        ).await?;
        original
            .execute_unprepared("DROP TABLE seaql_migrations")
            .await?;
        original.close().await?;
        let adopted = open_bot_state(&path).await?;
        assert!(
            adopted
                .query_one_raw(statement("SELECT version FROM seaql_migrations", vec![]))
                .await?
                .is_some()
        );
        let inbound = adopted
            .query_one_raw(statement(
                "SELECT workspace_id,text,diagnostic FROM inbound_work WHERE identity='current-inbound'",
                vec![],
            ))
            .await?
            .expect("current inbound survived migration record adoption");
        assert_eq!(
            inbound.try_get::<String>("", "workspace_id")?,
            "current-workspace"
        );
        assert_eq!(inbound.try_get::<String>("", "text")?, "preserved input");
        assert_eq!(
            inbound.try_get::<String>("", "diagnostic")?,
            "preserved diagnostic"
        );
        let binding = adopted
            .query_one_raw(statement(
                "SELECT workspace_id,thread_id FROM thread_bindings WHERE chat_id='current-chat'",
                vec![],
            ))
            .await?
            .expect("current binding survived migration record adoption");
        assert_eq!(
            binding.try_get::<String>("", "workspace_id")?,
            "current-workspace"
        );
        assert_eq!(
            binding.try_get::<String>("", "thread_id")?,
            "current-thread"
        );
        for table in ["inbound_work", "thread_bindings"] {
            assert!(
                !sea_orm_migration::SchemaManager::new(&adopted)
                    .has_column(table, "project_id")
                    .await?,
                "current adoption must not recreate retired ownership columns"
            );
        }
        if fault == "format" {
            adopted
                .execute_unprepared("UPDATE bot_meta SET schema_version=999")
                .await?;
        } else if fault == "missing_table" {
            adopted
                .execute_unprepared("DROP TABLE seaql_migrations; DROP TABLE inbound_work")
                .await?;
        } else {
            adopted
                .execute_unprepared(
                    "INSERT INTO seaql_migrations(version,applied_at) VALUES('m99999999_future',1)",
                )
                .await?;
        }
        adopted.close().await?;
        let before = tokio::fs::read(&path).await?;
        assert!(open_bot_state(&path).await.is_err());
        assert_eq!(tokio::fs::read(&path).await?, before);
    }
    Ok(())
}
