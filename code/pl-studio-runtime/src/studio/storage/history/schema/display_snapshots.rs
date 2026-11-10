//! Schema 18 -> 19. One-time lightweight legacy-run snapshot, in the original migration transaction.
use super::*;
use crate::studio::thread_projection::presentation::{lightweight, member_key};
pub(super) mod legacy;
use legacy::{DisplayBlockBody, DisplayHeader, DisplayMemberHead, DisplayMemberWrite};
use pl_core::chat::ChatReadHint;
use pl_protocol::{ChatAtom, ChatAtomLifecycle, ChatTerminalOutcome, DisplayBlockRef};

pub(super) struct DisplaySnapshots;
impl MigrationName for DisplaySnapshots {
    fn name(&self) -> &str {
        DISPLAY_SNAPSHOTS
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for DisplaySnapshots {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        upgrade(manager.get_connection()).await.map_err(conversion)
    }
}

pub(in crate::studio::storage::history) const CREATE: &str = "
CREATE TABLE conversation_display_blocks(
 block_id TEXT NOT NULL PRIMARY KEY, source_key TEXT NOT NULL,
 block_order INTEGER NOT NULL UNIQUE CHECK(block_order>0),
 history_pos INTEGER UNIQUE CHECK(history_pos IS NULL OR history_pos>0),
 updated_effect INTEGER NOT NULL, header BLOB NOT NULL);
CREATE INDEX conversation_display_open ON conversation_display_blocks(block_order) WHERE history_pos IS NULL;
CREATE TABLE conversation_display_members(
 block_id TEXT NOT NULL, member_order INTEGER NOT NULL CHECK(member_order>0),
 member_key TEXT NOT NULL UNIQUE, terminal INTEGER NOT NULL CHECK(terminal IN (0,1)),
 completion_id TEXT, updated_effect INTEGER NOT NULL, metadata BLOB NOT NULL,
 PRIMARY KEY(block_id,member_order),
 FOREIGN KEY(block_id) REFERENCES conversation_display_blocks(block_id)) WITHOUT ROWID;
CREATE INDEX conversation_display_unfinished ON conversation_display_members(block_id,member_order) WHERE terminal=0;
ALTER TABLE history_meta ADD COLUMN display_published_through INTEGER NOT NULL DEFAULT 0 CHECK(display_published_through>=0);
ALTER TABLE history_meta ADD COLUMN display_applied_effect INTEGER NOT NULL DEFAULT 0 CHECK(display_applied_effect>=0);
";

async fn write_head(
    db: &impl ConnectionTrait,
    header: &DisplayHeader,
    effect: i64,
    insert: bool,
) -> Result<()> {
    if insert {
        db.execute_raw(statement(
            "INSERT INTO conversation_display_blocks(block_id,source_key,block_order,history_pos,updated_effect,header) VALUES(?,?,?,?,?,?)",
            vec![header.id.clone().into(), serde_json::to_string(&header.source)?.into(),
                integer(header.block_order)?.into(), header.history_pos.map(integer).transpose()?.into(),
                effect.into(), serde_json::to_vec(header)?.into()]
        )).await?;
    } else {
        db.execute_raw(statement(
            "UPDATE conversation_display_blocks SET header=? WHERE block_id=?",
            vec![serde_json::to_vec(header)?.into(), header.id.clone().into()],
        ))
        .await?;
    }
    Ok(())
}

pub(in crate::studio::storage::history) async fn upgrade(db: &impl ConnectionTrait) -> Result<()> {
    immutable_completion_runs::validate(db).await?;
    let meta = db
        .query_one_raw(statement(
            "SELECT database_id,applied_write_seq FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .context("legacy display identity missing")?;
    let database: String = meta.try_get("", "database_id")?;
    let effect: i64 = meta.try_get("", "applied_write_seq")?;
    db.execute_unprepared(CREATE).await?;
    let mut after = 0u64;
    let mut published = 0u64;
    let mut current: Option<(u64, DisplayHeader)> = None;
    loop {
        let rows = db.query_all_raw(statement(
            "SELECT seq,item_id,query_class,metadata,length(payload) AS byte_length,display_run_start,display_run_ordinal
             FROM conversation_items WHERE seq>? ORDER BY seq LIMIT 128",
            vec![integer(after)?.into()]
        )).await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            after = u64::try_from(row.try_get::<i64>("", "seq")?)?;
            let mut atom: ChatAtom =
                serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
            let class: String = row.try_get("", "query_class")?;
            let hint = crate::studio::runtime::chat_item::native_read_hint_v1(&class, &atom);
            let start: Option<i64> = row.try_get("", "display_run_start")?;
            let ordinal: Option<i64> = row.try_get("", "display_run_ordinal")?;
            if matches!(hint, ChatReadHint::Hidden) {
                ensure!(
                    start.is_none() && ordinal.is_none(),
                    "hidden legacy record has a display run"
                );
                continue;
            }
            let start = u64::try_from(start.context("visible legacy record lacks a run")?)?;
            let ordinal =
                u64::try_from(ordinal.context("visible legacy record lacks an ordinal")?)?;
            let is_work = matches!(hint, ChatReadHint::Adjacent { .. });
            atom.completion_item_id = Some(row.try_get("", "item_id")?);
            atom.completion_seq = Some(after);
            atom.payload = Some(pl_protocol::PayloadData::Deferred {
                reference: pl_protocol::ContentRef {
                    database_id: database.clone(),
                    target: pl_protocol::ContentTarget::ItemPayload {
                        item_id: atom.completion_item_id.clone().expect("original identity"),
                    },
                },
                byte_length: u64::try_from(row.try_get::<i64>("", "byte_length")?)?,
            });
            // Original metadata may carry a payload of its own; keep only its original reference.
            atom = lightweight(atom, &database);
            ensure!(
                matches!(atom.lifecycle, ChatAtomLifecycle::Terminal { .. }),
                "legacy completion is not terminal"
            );
            if current.as_ref().is_none_or(|(run, _)| *run != start) {
                if let Some((_, header)) = current.take() {
                    write_head(db, &header, effect, false).await?;
                }
                ensure!(
                    ordinal == 1 && start == after,
                    "legacy display run start is inconsistent"
                );
                published = published
                    .checked_add(1)
                    .context("legacy display position exhausted")?;
                let id = serde_json::to_string(&("legacy-run", &database, start))?;
                let header = DisplayHeader {
                    version: 1,
                    legacy: true,
                    id: id.clone(),
                    source: atom.source.clone(),
                    block_order: published,
                    history_pos: Some(published),
                    boundary: None,
                    unfinished: 0,
                    next_member: 0,
                    revision: 0,
                    skip_display: false,
                    active_since: None,
                    duration_known: false,
                    body: if is_work {
                        DisplayBlockBody::Work {
                            summary: Box::default(),
                            members: DisplayBlockRef {
                                database_id: database.clone(),
                                block_id: id,
                            },
                        }
                    } else {
                        DisplayBlockBody::Single {
                            atom: Box::new(atom.clone()),
                            completion_id: atom.completion_item_id.clone(),
                        }
                    },
                };
                write_head(db, &header, effect, true).await?;
                current = Some((start, header));
            }
            let (_, header) = current.as_mut().expect("created legacy head");
            ensure!(
                ordinal == header.next_member + 1
                    && matches!(header.body, DisplayBlockBody::Work { .. }) == is_work,
                "legacy run membership differs"
            );
            header.next_member = ordinal;
            header.revision = ordinal;
            if let DisplayBlockBody::Work { summary, .. } = &mut header.body {
                summary.total += 1;
                summary.terminal += 1;
                summary.started_at = match (summary.started_at, atom.started_at) {
                    (None, at) if summary.total == 1 => at,
                    (Some(a), Some(b)) => Some(a.min(b)),
                    _ => None,
                };
                summary.finished_at = match (summary.finished_at, atom.finished_at) {
                    (None, at) if summary.total == 1 => at,
                    (Some(a), Some(b)) => Some(a.max(b)),
                    _ => None,
                };
                // v18 did not save work-interval unions. Do not invent a duration from idle time.
                if let ChatAtomLifecycle::Terminal { outcome, .. } = atom.lifecycle {
                    match outcome {
                        ChatTerminalOutcome::Failed => summary.failed += 1,
                        ChatTerminalOutcome::Cancelled => summary.cancelled += 1,
                        ChatTerminalOutcome::Transferred => summary.transferred += 1,
                        ChatTerminalOutcome::Completed => {}
                    }
                }
            } else {
                ensure!(ordinal == 1, "legacy Single contains multiple members");
            }
            let member = DisplayMemberWrite {
                block_id: header.id.clone(),
                terminal: true,
                head: DisplayMemberHead {
                    member_key: member_key(&atom)?,
                    member_order: ordinal,
                    completion_id: atom.completion_item_id.clone(),
                    atom,
                },
            };
            db.execute_raw(statement(
                "INSERT INTO conversation_display_members(block_id,member_order,member_key,terminal,completion_id,updated_effect,metadata) VALUES(?,?,?,1,?,?,?)",
                vec![member.block_id.clone().into(), integer(ordinal)?.into(), member.head.member_key.clone().into(),
                    member.head.completion_id.clone().into(), effect.into(), serde_json::to_vec(&member)?.into()]
            )).await?;
        }
    }
    if let Some((_, header)) = current {
        write_head(db, &header, effect, false).await?;
    }
    ensure!(db.query_one_raw(statement(
        "SELECT 1 FROM conversation_display_members m LEFT JOIN conversation_display_blocks b ON m.block_id=b.block_id
         LEFT JOIN conversation_items i ON m.completion_id=i.item_id WHERE b.block_id IS NULL OR i.item_id IS NULL LIMIT 1", vec![]
    )).await?.is_none(), "legacy display references are incomplete");
    db.execute_raw(statement(
        "UPDATE history_meta SET display_published_through=?,display_applied_effect=?,schema_version=19 WHERE id=1",
        vec![integer(published)?.into(), effect.into()]
    )).await?;
    validate(db).await
}

/// Normal open checks schema/index gates and prefix endpoints, not all original/member rows.
pub(super) async fn validate(db: &impl ConnectionTrait) -> Result<()> {
    ensure!(version(db).await? == 19, "display history format is not 19");
    validate_preserved(db).await?;
    if let Some(row) = db.query_one_raw(statement(
        "SELECT history_pos,header FROM conversation_display_blocks WHERE history_pos IS NOT NULL ORDER BY history_pos DESC LIMIT 1",
        vec![],
    )).await? {
        let header: DisplayHeader = serde_json::from_slice(&row.try_get::<Vec<u8>>("", "header")?)?;
        ensure!(header.version == 1 && header.history_pos == Some(u64::try_from(row.try_get::<i64>("","history_pos")?)?)
            && header.unfinished == 0 && (header.legacy || header.boundary.is_some()) && !header.skip_display,
            "legacy published display header is not ready");
    }
    Ok(())
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

#[cfg(test)]
pub(in crate::studio::storage::history) mod tests;
