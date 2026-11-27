pub(crate) mod calls;
pub(crate) mod coordinator;
mod current_file;
pub(crate) use current_file::{read_for_upgrade, verify_for_upgrade};
pub(crate) mod current_writer;
pub(crate) mod history;
pub(crate) mod legacy_checkpoint;
pub(crate) mod sqlite_util;
pub(crate) mod state;
pub(crate) mod thread_writer;
pub(crate) mod tool_result_upgrade;
pub(crate) mod tool_task;
pub(in crate::studio) mod write_behind;

#[cfg(test)]
mod schema_admission_tests {
    use crate::studio::storage::legacy_checkpoint::ThreadCheckpoint;
    use anyhow::Result;
    use sea_orm::ConnectionTrait;

    async fn raw_database(path: &std::path::Path) -> Result<sea_orm::DatabaseConnection> {
        Ok(sea_orm::Database::connect(
            crate::studio::paths::sqlite_file_options(
                path,
                crate::studio::paths::SqliteFileMode::Create,
                |options| options,
            )
            .await?,
        )
        .await?)
    }

    #[tokio::test]
    async fn v2_toml_import_preserves_source_and_recovers_external_context() -> Result<()> {
        use pl_core::{
            context::{ContextContent, ContextRecord, ContextSnapshot, ContextSource},
            thread::{ThreadSnapshot, current::ThreadCurrent},
        };
        use std::sync::Arc;

        let directory = tempfile::tempdir()?;
        let root = directory.path();
        let thread = "v2-toml";
        let state = ThreadSnapshot {
            context: ContextSnapshot {
                revision: 1,
                records: vec![ContextRecord {
                    id: "saved-user".into(),
                    turn_id: None,
                    source: ContextSource::User,
                    content: vec![ContextContent::Text {
                        text: Arc::from("存量正文"),
                    }],
                    tool_calls: vec![],
                    tool_data: Default::default(),
                }]
                .into(),
            },
            ..Default::default()
        };
        let checkpoint = ThreadCheckpoint::capture(thread.into(), 0, state.clone())?;
        let (external, bodies) = checkpoint.externalize_bodies(1);
        assert_eq!(bodies.len(), 1);
        let manifest = toml::to_string(&external)?;
        let manifest_path = root.join("state.toml");
        tokio::fs::write(&manifest_path, &manifest).await?;
        let history_path = root.join("history.sqlite");
        let legacy = super::history::HistoryStore::open(&history_path, thread).await?;
        let state_store = super::state::StateStore::new(root.to_owned(), thread);
        assert!(state_store.legacy_prepare(&legacy).await.is_err());
        assert!(legacy.checkpoint().await?.is_none());
        let body = &bodies[0];
        let digest = body
            .entry
            .reference
            .digest()
            .strip_prefix("sha256:")
            .unwrap();
        let body_dir = root.join("blobs/checkpoint").join(&digest[..2]);
        tokio::fs::create_dir_all(&body_dir).await?;
        let body_path = body_dir.join(digest);
        tokio::fs::write(&body_path, &body.bytes).await?;
        assert_eq!(
            state_store
                .legacy_prepare(&legacy)
                .await?
                .unwrap()
                .state
                .context,
            state.context
        );
        legacy.close_for_deletion().await?;
        let report = crate::history::upgrade_history(&history_path, thread, root).await?;
        assert_eq!(report.status, crate::history::UpgradeStatus::Upgraded);
        let current =
            ThreadCurrent::from_json(&tokio::fs::read(root.join("current.json")).await?, thread)?;
        assert_eq!(current.state.context, state.context);
        assert_eq!(tokio::fs::read_to_string(&manifest_path).await?, manifest);
        assert_eq!(tokio::fs::read(&body_path).await?, body.bytes.as_slice());
        Ok(())
    }

    /// All Studio-owned database families reject unknown future formats and migration names before
    /// a writer changes the SQLite file. This also covers takeover of supported pre-framework files.
    #[tokio::test]
    async fn studio_databases_adopt_current_files_and_refuse_future_writes() -> Result<()> {
        use crate::studio::{StudioStore, paths::StudioPaths, storage::calls::CallsStore};
        use sea_orm::{DatabaseBackend, Statement};
        // Schema 26 has no session_checkpoint, so the old future-checkpoint fault is not copied.
        for family in ["product", "history", "calls"] {
            for fault in ["format", "migration", "missing_table"] {
                let directory = tempfile::tempdir()?;
                let paths = StudioPaths::resolve(Some(directory.path().to_path_buf()))?;
                let path = match family {
                    "product" => paths.database(),
                    "calls" => paths.calls_database(),
                    _ => directory.path().join("history.sqlite"),
                };
                for generation in 0..2 {
                    match family {
                        "product" => StudioStore::open(&path).await?.close().await?,
                        "calls" => CallsStore::prepare(&path).await?.close().await?,
                        _ => {
                            crate::history::HistoryStore::open(
                                &path,
                                "adoption",
                                crate::history::HistoryLimits::default(),
                            )
                            .await?
                            .close()
                            .await?;
                        }
                    }
                    if generation == 0 && family != "history" {
                        let db = raw_database(&path).await?;
                        if family == "calls" {
                            // Restore the published v8 shape, before fence retirement, request tiers and usage completeness.
                            db.execute_unprepared(
                                "ALTER TABLE call_usage_summary DROP COLUMN has_incomplete_usage;
                                 ALTER TABLE call_usage_summary DROP COLUMN legacy_import_eligible;
                                 ALTER TABLE performance_samples DROP COLUMN requested_service_tier;
                                 ALTER TABLE legacy_call_fences RENAME TO call_watermarks;
                                 UPDATE calls_meta SET schema_version=8 WHERE id=1;",
                            )
                            .await?;
                        }
                        db.execute_unprepared("DROP TABLE seaql_migrations").await?;
                        db.close().await?;
                    }
                }
                let db = raw_database(&path).await?;
                let completed = db
                    .query_all_raw(Statement::from_string(
                        DatabaseBackend::Sqlite,
                        "SELECT version FROM seaql_migrations",
                    ))
                    .await?;
                assert!(!completed.is_empty(), "current {family} must be enrolled");
                if fault == "migration" {
                    db.execute_unprepared(
                    "INSERT INTO seaql_migrations(version,applied_at) VALUES('m99999999_future',1)",
                )
                .await?;
                } else if fault == "missing_table" {
                    db.execute_unprepared(match family {
                        "product" => "DROP TABLE seaql_migrations; DROP TABLE studio_objects",
                        "calls" => "DROP TABLE seaql_migrations; DROP TABLE call_usage_summary",
                        _ => "DROP TABLE history_events",
                    })
                    .await?;
                } else {
                    db.execute_unprepared(match family {
                        "product" => "PRAGMA user_version=999",
                        "calls" => "UPDATE calls_meta SET schema_version=999",
                        _ => {
                            "PRAGMA ignore_check_constraints=ON;
                             UPDATE history_store_meta SET schema_version=999;
                             PRAGMA ignore_check_constraints=OFF;"
                        }
                    })
                    .await?;
                }
                db.close().await?;
                let before = tokio::fs::read(&path).await?;
                let failure = match family {
                    "product" => StudioStore::open(&path).await.map(|_| ()),
                    "calls" => CallsStore::prepare(&path).await.map(|_| ()),
                    _ => crate::history::HistoryStore::open(
                        &path,
                        "adoption",
                        crate::history::HistoryLimits::default(),
                    )
                    .await
                    .map(|_| ())
                    .map_err(anyhow::Error::from),
                };
                assert!(failure.is_err(), "future {family} {fault} was accepted");
                assert_eq!(
                    tokio::fs::read(&path).await?,
                    before,
                    "future {family} changed"
                );
            }
        }
        Ok(())
    }
}
