//! One transactional upgrade from the published schema22 display index.
use super::*;
use crate::studio::storage::history::conversation::display::validate_header;
use crate::studio::thread_projection::presentation::DisplayHeader;

pub(super) struct DisplayBlockOrder;
impl MigrationName for DisplayBlockOrder {
    fn name(&self) -> &str {
        DISPLAY_BLOCK_ORDER
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for DisplayBlockOrder {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        upgrade(manager.get_connection()).await.map_err(conversion)
    }
}

async fn upgrade(db: &impl ConnectionTrait) -> Result<()> {
    ensure!(
        version(db).await? == 22,
        "display order migration requires schema22"
    );
    work_snapshots::validate_preserved(db).await?;
    db.execute_unprepared("CREATE TABLE conversation_display_blocks_v23(
        block_id TEXT NOT NULL PRIMARY KEY,source_key TEXT NOT NULL,
        block_order INTEGER NOT NULL UNIQUE CHECK(block_order>0),
        sealed INTEGER NOT NULL CHECK(sealed IN (0,1)),updated_effect INTEGER NOT NULL,header BLOB NOT NULL);
        CREATE TABLE conversation_display_members_v23(
        block_id TEXT NOT NULL,member_order INTEGER NOT NULL CHECK(member_order>0),
        member_key TEXT NOT NULL UNIQUE,association_key TEXT NOT NULL,
        terminal INTEGER NOT NULL CHECK(terminal IN (0,1)),completion_id TEXT,
        updated_effect INTEGER NOT NULL,metadata BLOB NOT NULL,
        PRIMARY KEY(block_id,member_order),
        FOREIGN KEY(block_id) REFERENCES conversation_display_blocks_v23(block_id)) WITHOUT ROWID;").await?;
    let mut last_order = 0u64;
    let mut first_open = None;
    // Published order is authoritative even when it differs from original creation order.
    for published in [true, false] {
        let column = if published {
            "history_pos"
        } else {
            "block_order"
        };
        let condition = if published {
            "history_pos IS NOT NULL"
        } else {
            "history_pos IS NULL"
        };
        let mut after = 0i64;
        loop {
            let rows=db.query_all_raw(statement(&format!("SELECT block_id,source_key,block_order,history_pos,sealed,updated_effect,header FROM conversation_display_blocks WHERE {condition} AND {column}>? ORDER BY {column} LIMIT 128"),vec![after.into()])).await?;
            if rows.is_empty() {
                break;
            }
            for row in rows {
                after = row.try_get("", column)?;
                let mut value: serde_json::Value =
                    serde_json::from_slice(&row.try_get::<Vec<u8>>("", "header")?)?;
                ensure!(
                    value["version"] == 4 && value["skip_display"] == false,
                    "invalid schema22 display header; original history preserved"
                );
                ensure!(
                    value["id"].as_str() == Some(row.try_get::<String>("", "block_id")?.as_str())
                        && value["block_order"].as_u64()
                            == Some(u64::try_from(row.try_get::<i64>("", "block_order")?)?)
                        && value["history_pos"].as_u64()
                            == row
                                .try_get::<Option<i64>>("", "history_pos")?
                                .map(u64::try_from)
                                .transpose()?,
                    "schema22 display identity differs"
                );
                last_order = last_order
                    .checked_add(1)
                    .filter(|order| *order <= i64::MAX as u64)
                    .context("display order exhausted")?;
                value["version"] = 5.into();
                value["block_order"] = last_order.into();
                let object = value
                    .as_object_mut()
                    .context("display header must be an object")?;
                object.remove("history_pos");
                object.remove("skip_display");
                let header: DisplayHeader = serde_json::from_value(value)?;
                validate_header(&header)?;
                ensure!(
                    header.sealed == (row.try_get::<i64>("", "sealed")? == 1)
                        && serde_json::to_string(&header.source)?
                            == row.try_get::<String>("", "source_key")?,
                    "schema22 display indexed values differ"
                );
                ensure!(
                    !published || header.sealed,
                    "published display is not frozen"
                );
                if !header.sealed && first_open.is_none() {
                    first_open = Some(last_order);
                }
                db.execute_raw(statement("INSERT INTO conversation_display_blocks_v23(block_id,source_key,block_order,sealed,updated_effect,header) VALUES(?,?,?,?,?,?)",vec![header.id.clone().into(),serde_json::to_string(&header.source)?.into(),integer(last_order)?.into(),i64::from(header.sealed).into(),row.try_get::<i64>("","updated_effect")?.into(),serde_json::to_vec(&header)?.into()])).await?;
            }
        }
    }
    let mut block = String::new();
    let mut member = 0i64;
    loop {
        let rows=db.query_all_raw(statement("SELECT * FROM conversation_display_members WHERE (block_id,member_order)>(?,?) ORDER BY block_id,member_order LIMIT 128",vec![block.clone().into(),member.into()])).await?;
        if rows.is_empty() {
            break;
        }
        let decoded = rows
            .iter()
            .map(conversation::display::decode_member)
            .collect::<Result<Vec<_>>>()?;
        conversation::display::validate_original_references(db, &decoded).await?;
        let last = rows.last().expect("nonempty page");
        let next_block: String = last.try_get("", "block_id")?;
        let next_member: i64 = last.try_get("", "member_order")?;
        db.execute_raw(statement("INSERT INTO conversation_display_members_v23 SELECT * FROM conversation_display_members WHERE (block_id,member_order)>(?,?) AND (block_id,member_order)<=(?,?)",vec![block.into(),member.into(),next_block.clone().into(),next_member.into()])).await?;
        block = next_block;
        member = next_member;
    }
    for (old, new, keys) in [
        (
            "conversation_display_blocks",
            "conversation_display_blocks_v23",
            "block_id,source_key,sealed,updated_effect",
        ),
        (
            "conversation_display_members",
            "conversation_display_members_v23",
            "*",
        ),
    ] {
        for (left, right) in [(old, new), (new, old)] {
            ensure!(
                db.query_one_raw(statement(
                    &format!("SELECT {keys} FROM {left} EXCEPT SELECT {keys} FROM {right} LIMIT 1"),
                    vec![]
                ))
                .await?
                .is_none(),
                "display migration changed preserved identities or member bytes"
            );
        }
    }
    ensure!(
        db.query_one_raw(statement(
            "PRAGMA foreign_key_check(conversation_display_members_v23)",
            vec![]
        ))
        .await?
        .is_none(),
        "display migration has invalid member owners"
    );
    db.execute_unprepared("DROP TABLE conversation_display_members;
        DROP TABLE conversation_display_blocks;
        ALTER TABLE conversation_display_blocks_v23 RENAME TO conversation_display_blocks;
        ALTER TABLE conversation_display_members_v23 RENAME TO conversation_display_members;
        CREATE INDEX conversation_display_open ON conversation_display_blocks(block_order) WHERE sealed=0;
        CREATE UNIQUE INDEX conversation_display_current_work ON conversation_display_blocks((1)) WHERE sealed=0 AND json_extract(header,'$.body.kind')='work';
        CREATE INDEX conversation_display_unfinished ON conversation_display_members(block_id,member_order) WHERE terminal=0;
        ALTER TABLE history_meta RENAME COLUMN display_published_through TO display_ready_frontier;
        ALTER TABLE history_meta ADD COLUMN display_last_order INTEGER NOT NULL DEFAULT 0 CHECK(display_last_order>=0);").await?;
    let frontier = first_open.map_or(last_order, |order| order - 1);
    db.execute_raw(statement("UPDATE history_meta SET schema_version=23,display_ready_frontier=?,display_last_order=? WHERE id=1",vec![integer(frontier)?.into(),integer(last_order)?.into()])).await?;
    validate(db).await
}

pub(super) async fn validate(db: &impl ConnectionTrait) -> Result<()> {
    ensure!(
        version(db).await? == 23,
        "display block order format is not current"
    );
    immutable_completion_runs::validate_preserved(db).await?;
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
    db.query_all_raw(statement("SELECT block_id,source_key,block_order,sealed,updated_effect,header FROM conversation_display_blocks LIMIT 0",vec![])).await?;
    let row=db.query_one_raw(statement("SELECT display_ready_frontier,display_last_order,display_applied_effect,applied_write_seq FROM history_meta WHERE id=1",vec![])).await?.context("display metadata missing")?;
    let frontier: i64 = row.try_get("", "display_ready_frontier")?;
    ensure!(
        frontier >= 0
            && frontier <= row.try_get::<i64>("", "display_last_order")?
            && row.try_get::<i64>("", "display_applied_effect")?
                <= row.try_get::<i64>("", "applied_write_seq")?,
        "invalid display metadata cut"
    );
    for name in [
        "conversation_display_open",
        "conversation_display_current_work",
        "conversation_display_unfinished",
    ] {
        ensure!(
            db.query_one_raw(statement(
                "SELECT 1 FROM sqlite_schema WHERE type='index' AND name=?",
                vec![name.into()]
            ))
            .await?
            .is_some(),
            "display index missing"
        );
    }
    Ok(())
}
