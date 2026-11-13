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
        .take_while(|m| m.name() != WORK_SNAPSHOTS)
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

#[tokio::test]
async fn fresh_store_initializes_current_snapshots_without_legacy_conversion() -> Result<()> {
    let (_dir, db) = fixture().await?;
    super::initialize(&db).await?;
    assert_eq!(version(&db).await?, HISTORY_SCHEMA_VERSION);
    super::validate(&db).await?;
    assert_eq!(conversation::display::watermarks(&db).await?, (0, 0));
    Ok(())
}

#[tokio::test]
async fn unsupported_snapshots_are_rejected_without_modifying_the_store() -> Result<()> {
    let (_dir, db) = fixture().await?;
    super::initialize(&db).await?;
    db.execute_unprepared("UPDATE history_meta SET schema_version=21 WHERE id=1")
        .await?;
    let error = super::super::preflight(&db, THREAD).await.unwrap_err();
    assert!(error.to_string().contains("unsupported old Work snapshots"));
    assert_eq!(version(&db).await?, 21);
    assert!(
        db.query_one_raw(statement(
            "SELECT 1 FROM sqlite_schema WHERE type='table' AND name='conversation_display_blocks'",
            vec![],
        ))
        .await?
        .is_some()
    );
    assert!(
        db.query_one_raw(statement(
            "SELECT 1 FROM seaql_migrations WHERE version=?",
            vec![WORK_SNAPSHOTS.into()],
        ))
        .await?
        .is_none()
    );
    Ok(())
}
