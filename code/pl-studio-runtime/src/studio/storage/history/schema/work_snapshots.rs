//! Current-only Work snapshots. Existing aggregate snapshots are unsupported.
use super::*;
use pl_protocol::DisplayBlockBody;

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
    ensure!(
        existing.is_none(),
        "unsupported old Work snapshots; existing data preserved"
    );
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
    let (published, effect) = conversation::display::watermarks(db).await?;
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
    let (published, _) = conversation::display::watermarks(db).await?;
    let last = conversation::display::history_heads(db, i64::MAX as u64, None, 1).await?;
    ensure!(
        last.first().map_or(0, |head| head.history_pos) == published,
        "display published head is missing"
    );
    let recovery = conversation::display::recovery(db).await?;
    let mut current = None;
    for header in &recovery.open {
        if !header.sealed && matches!(header.body, DisplayBlockBody::Work { .. }) {
            ensure!(
                current.replace(header.block_order).is_none()
                    && header.block_order == recovery.last_order,
                "open Work is not the unique latest display block"
            );
        }
    }
    Ok(())
}

#[cfg(test)]
pub(in crate::studio::storage::history) mod tests;
