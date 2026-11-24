//! Current Work snapshots and the one-time legacy display upgrade.
use super::v24_presentation_types::DisplayBlockBody;
use super::*;
mod legacy;
use crate::{ChatFactPosition, ChatSourceId};
use serde::{Deserialize, Serialize};
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(super) struct DisplayHeader {
    pub version: u32,
    pub id: String,
    pub source: ChatSourceId,
    pub block_order: u64,
    pub history_pos: Option<u64>,
    pub boundary: Option<ChatFactPosition>,
    pub first_content_at: Option<ChatFactPosition>,
    pub sealed: bool,
    pub unfinished: u64,
    pub next_member: u64,
    pub revision: u64,
    pub skip_display: bool,
    #[serde(skip)]
    pub thinking_summary: Option<String>,
    pub body: DisplayBlockBody,
}

/// Published migration identities remain registered; conversion is owned by WorkSnapshots.
pub(super) struct LegacyDisplayMarker(pub &'static str);
impl MigrationName for LegacyDisplayMarker {
    fn name(&self) -> &str {
        self.0
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for LegacyDisplayMarker {
    async fn up(&self, _: &SchemaManager) -> Result<(), DbErr> {
        Ok(())
    }
}
pub(super) fn is_legacy_marker(name: &str) -> bool {
    matches!(
        name,
        "m20261109_000001_display_snapshots"
            | "m20261111_000001_display_observations"
            | "m20261112_000001_history_tool_work"
            | "m20261112_000001_visible_tail_workgroups"
    )
}

pub(super) struct WorkSnapshots;
impl MigrationName for WorkSnapshots {
    fn name(&self) -> &str {
        WORK_SNAPSHOTS
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for WorkSnapshots {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        initialize(manager.get_connection())
            .await
            .map_err(conversion)
    }
}

pub(in crate::studio::storage::history) async fn initialize(
    db: &impl ConnectionTrait,
) -> Result<()> {
    let existing = db
        .query_one_raw(statement(
            "SELECT 1 FROM sqlite_schema WHERE type='table' AND name='conversation_display_blocks'",
            vec![],
        ))
        .await?;
    if existing.is_some() {
        legacy::upgrade(db).await?;
        return validate(db).await;
    }
    db.execute_unprepared(
        "CREATE TABLE conversation_display_blocks(
         block_id TEXT NOT NULL PRIMARY KEY,source_key TEXT NOT NULL,
         block_order INTEGER NOT NULL UNIQUE CHECK(block_order>0),
         history_pos INTEGER UNIQUE CHECK(history_pos IS NULL OR history_pos>0),
         sealed INTEGER NOT NULL CHECK(sealed IN (0,1)),updated_effect INTEGER NOT NULL,header BLOB NOT NULL);
         CREATE INDEX conversation_display_open ON conversation_display_blocks(block_order) WHERE history_pos IS NULL;
         CREATE UNIQUE INDEX conversation_display_current_work ON conversation_display_blocks((1))
         WHERE history_pos IS NULL AND sealed=0 AND json_extract(header,'$.body.kind')='work';
         CREATE TABLE conversation_display_members(
         block_id TEXT NOT NULL,member_order INTEGER NOT NULL CHECK(member_order>0),
         member_key TEXT NOT NULL UNIQUE,association_key TEXT NOT NULL,
         terminal INTEGER NOT NULL CHECK(terminal IN (0,1)),completion_id TEXT,
         updated_effect INTEGER NOT NULL,metadata BLOB NOT NULL,
         PRIMARY KEY(block_id,member_order),
         FOREIGN KEY(block_id) REFERENCES conversation_display_blocks(block_id)) WITHOUT ROWID;
         CREATE INDEX conversation_display_unfinished ON conversation_display_members(block_id,member_order) WHERE terminal=0;
         ALTER TABLE history_meta ADD COLUMN display_published_through INTEGER NOT NULL DEFAULT 0 CHECK(display_published_through>=0);
         ALTER TABLE history_meta ADD COLUMN display_applied_effect INTEGER NOT NULL DEFAULT 0 CHECK(display_applied_effect>=0);
         UPDATE history_meta SET schema_version=22 WHERE id=1;"
    ).await?;
    legacy::backfill(db).await?;
    validate(db).await
}

pub(super) async fn validate_preserved(db: &impl ConnectionTrait) -> Result<()> {
    immutable_completion_runs::validate_preserved(db).await?;
    super::validate_keys(
        db,
        "conversation_display_blocks",
        &["block_id"],
        false,
        &["block_order"],
    )
    .await?;
    let indexes = db
        .query_all_raw(statement(
            "SELECT * FROM pragma_index_list('conversation_display_blocks', 'main')",
            vec![],
        ))
        .await?;
    ensure!(
        super::has_unique_key(db, &indexes, &["history_pos"], false, false).await?,
        "display history position requires a unique index"
    );
    super::validate_keys(
        db,
        "conversation_display_members",
        &["block_id", "member_order"],
        false,
        &["member_key"],
    )
    .await?;
    db.query_all_raw(statement(
        "SELECT block_id,source_key,block_order,history_pos,updated_effect,header FROM conversation_display_blocks LIMIT 0", vec![]
    )).await?;
    db.query_all_raw(statement(
        "SELECT block_id,member_order,member_key,terminal,completion_id,updated_effect,metadata FROM conversation_display_members LIMIT 0", vec![]
    )).await?;
    for name in [
        "conversation_display_open",
        "conversation_display_unfinished",
    ] {
        ensure!(
            db.query_one_raw(statement(
                "SELECT 1 FROM sqlite_master WHERE type='index' AND name=?",
                vec![name.into()]
            ))
            .await?
            .is_some(),
            "display snapshot index missing; original history preserved"
        );
    }
    let (published, effect) = watermarks(db).await?;
    let meta = db
        .query_one_raw(statement(
            "SELECT applied_write_seq FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .context("history identity missing")?;
    ensure!(
        effect <= u64::try_from(meta.try_get::<i64>("", "applied_write_seq")?)?,
        "display effect is ahead of original commit"
    );
    let last = db.query_one_raw(statement(
        "SELECT history_pos FROM conversation_display_blocks WHERE history_pos IS NOT NULL ORDER BY history_pos DESC LIMIT 1",
        vec![],
    )).await?;
    ensure!(
        last.map(|row| row.try_get::<i64>("", "history_pos"))
            .transpose()?
            .unwrap_or(0)
            == integer(published)?,
        "display published head is missing; original history preserved"
    );
    Ok(())
}

pub(super) async fn validate(db: &impl ConnectionTrait) -> Result<()> {
    ensure!(
        version(db).await? == 22,
        "work snapshot format is not current"
    );
    validate_preserved(db).await?;
    super::validate_keys(
        db,
        "conversation_display_blocks",
        &["block_id"],
        false,
        &["block_order"],
    )
    .await?;
    super::validate_keys(
        db,
        "conversation_display_members",
        &["block_id", "member_order"],
        false,
        &["member_key"],
    )
    .await?;
    ensure!(db.query_one_raw(statement(
        "SELECT 1 FROM sqlite_schema WHERE type='index' AND name='conversation_display_current_work'", vec![],
    )).await?.is_some(), "unique display tail index is missing; original history preserved");
    let (published, _) = watermarks(db).await?;
    let _ = published;
    Ok(())
}

async fn watermarks(db: &impl ConnectionTrait) -> Result<(u64, u64)> {
    let row = db
        .query_one_raw(statement(
            "SELECT display_published_through,display_applied_effect FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .context("schema22 display metadata missing")?;
    Ok((
        u64::try_from(row.try_get::<i64>("", "display_published_through")?)?,
        u64::try_from(row.try_get::<i64>("", "display_applied_effect")?)?,
    ))
}

#[cfg(test)]
pub(in crate::studio::storage::history) mod tests {
    use super::*;
    use sea_orm::{Database, DatabaseConnection};
    use sea_orm_migration::MigratorTraitSelf;

    const THREAD: &str = "display-snapshot-migration";
    struct Published18;
    impl MigratorTraitSelf for Published18 {
        fn migrations(&self) -> Vec<Box<dyn MigrationTrait>> {
            Migrator {
                thread_id: THREAD.into(),
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
    async fn published_legacy_snapshot_bookkeeping_upgrades_and_reopens() -> Result<()> {
        let (_dir, db) = fixture().await?;
        super::initialize(&db).await?;
        db.execute_unprepared("UPDATE history_meta SET schema_version=21 WHERE id=1")
            .await?;
        super::super::prepare(&db, THREAD, Preparation::Schema).await?;
        assert_eq!(version(&db).await?, HISTORY_SCHEMA_VERSION);
        super::super::execution_facts::validate(&db).await?;
        super::super::prepare(&db, THREAD, Preparation::Schema).await?;
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
            .is_some()
        );
        Ok(())
    }
}
