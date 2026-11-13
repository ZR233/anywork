//! Decode retired formats only inside the official migration transaction.
use super::*;
use crate::studio::thread_projection::presentation::{
    DisplayHeader, DisplayMemberWrite, lightweight, member_key, record,
};
use pl_protocol::{ChatAtom, DisplayBlockBody, SingleVisibility};
use serde_json::{Value, json};

pub(super) async fn upgrade(db: &impl ConnectionTrait) -> Result<()> {
    ensure!(
        (19..=21).contains(&version(db).await?),
        "unexpected legacy display version"
    );
    // Preserve the original snapshot bytes as well as all immutable completions.
    db.execute_unprepared("CREATE TABLE work_snapshot_migration_headers AS SELECT * FROM conversation_display_blocks;
        CREATE TABLE work_snapshot_migration_members AS SELECT * FROM conversation_display_members;").await?;
    let columns = db
        .query_all_raw(statement(
            "PRAGMA table_info(conversation_display_blocks)",
            vec![],
        ))
        .await?;
    if !columns
        .iter()
        .any(|r| r.try_get::<String>("", "name").ok().as_deref() == Some("sealed"))
    {
        db.execute_unprepared(
            "ALTER TABLE conversation_display_blocks ADD COLUMN sealed INTEGER NOT NULL DEFAULT 1",
        )
        .await?;
    }
    let columns = db
        .query_all_raw(statement(
            "PRAGMA table_info(conversation_display_members)",
            vec![],
        ))
        .await?;
    if !columns
        .iter()
        .any(|r| r.try_get::<String>("", "name").ok().as_deref() == Some("association_key"))
    {
        db.execute_unprepared("ALTER TABLE conversation_display_members ADD COLUMN association_key TEXT NOT NULL DEFAULT ''").await?;
    }
    let mut after = 0i64;
    loop {
        let rows = db.query_all_raw(statement("SELECT block_order,header FROM conversation_display_blocks WHERE block_order>? ORDER BY block_order LIMIT 128", vec![after.into()])).await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            after = row.try_get("", "block_order")?;
            let mut value: Value = serde_json::from_slice(&row.try_get::<Vec<u8>>("", "header")?)?;
            ensure!(
                matches!(value["version"].as_u64(), Some(1..=3)),
                "unsupported legacy display header"
            );
            value["version"] = 4.into();
            value["first_content_at"] = value
                .get("first_content_at")
                .cloned()
                .unwrap_or(Value::Null);
            match value["body"]["kind"].as_str() {
                Some("work") => {
                    // Member activity timestamps do not prove group creation or its boundary.
                    // Historical intervals remain unknown rather than fabricating elapsed time.
                    value["body"]
                        .as_object_mut()
                        .context("legacy Work body")?
                        .remove("summary");
                    value["body"]["timing"] = json!({"startedAt":null,"finishedAt":null});
                }
                Some("single") => {
                    if value["body"].get("record").is_none() {
                        let mut atom: ChatAtom =
                            serde_json::from_value(value["body"]["atom"].clone())?;
                        if let Some(id) = value["body"]["completion_id"].as_str() {
                            atom.completion_item_id = Some(id.into());
                        }
                        value["body"]["record"] = serde_json::to_value(record(atom, None))?;
                    }
                    if value["body"].get("visibility").is_none() {
                        value["body"]["visibility"] = "content".into();
                    }
                }
                _ => anyhow::bail!("unknown legacy display body"),
            }
            // Old source-local open groups become frozen cuts; only new facts create a new tail.
            value["sealed"] = true.into();
            let header: DisplayHeader = serde_json::from_value(value)?;
            db.execute_raw(statement(
                "UPDATE conversation_display_blocks SET sealed=1,header=? WHERE block_order=?",
                vec![serde_json::to_vec(&header)?.into(), after.into()],
            ))
            .await?;
        }
    }
    let mut after = String::new();
    loop {
        let rows = db.query_all_raw(statement("SELECT member_key,metadata FROM conversation_display_members WHERE member_key>? ORDER BY member_key LIMIT 128", vec![after.into()])).await?;
        if rows.is_empty() {
            break;
        }
        after = String::new();
        for row in rows {
            after = row.try_get("", "member_key")?;
            let mut value: Value =
                serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
            if value.get("association_key").is_none() {
                value["association_key"] = after.clone().into();
            }
            if value["head"].get("record").is_none() {
                let mut atom: ChatAtom = serde_json::from_value(value["head"]["atom"].clone())?;
                if let Some(id) = value["head"]["completionId"].as_str() {
                    atom.completion_item_id = Some(id.into());
                }
                value["head"]["record"] = serde_json::to_value(record(atom, None))?;
                let head = value["head"]
                    .as_object_mut()
                    .context("legacy member head")?;
                head.remove("atom");
                head.remove("completionId");
            }
            let member: crate::studio::thread_projection::presentation::DisplayMemberWrite =
                serde_json::from_value(value)?;
            db.execute_raw(statement("UPDATE conversation_display_members SET association_key=?,metadata=? WHERE member_key=?", vec![member.association_key.clone().into(),serde_json::to_vec(&member)?.into(),after.clone().into()])).await?;
        }
    }
    db.execute_unprepared("CREATE UNIQUE INDEX IF NOT EXISTS conversation_display_current_work ON conversation_display_blocks((1)) WHERE history_pos IS NULL AND sealed=0 AND json_extract(header,'$.body.kind')='work'; UPDATE history_meta SET schema_version=22 WHERE id=1").await?;
    Ok(())
}

/// Pre-display stores already have immutable completions: expose each original once, in order.
pub(super) async fn backfill(db: &impl ConnectionTrait) -> Result<()> {
    let meta = db
        .query_one_raw(statement(
            "SELECT database_id,applied_write_seq FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .context("history identity")?;
    let database: String = meta.try_get("", "database_id")?;
    let effect: i64 = meta.try_get("", "applied_write_seq")?;
    let mut after = 0i64;
    let mut position = 0u64;
    let mut current: Option<(i64, DisplayHeader)> = None;
    loop {
        let rows = db
            .query_all_raw(statement(
                "SELECT seq,item_id,query_class,display_run_start,display_run_ordinal,metadata,length(payload) AS byte_length FROM conversation_items WHERE seq>? AND display_run_start IS NOT NULL ORDER BY seq LIMIT 128",
                vec![after.into()],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            after = row.try_get("", "seq")?;
            let mut atom: ChatAtom =
                serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
            let item_id: String = row.try_get("", "item_id")?;
            atom.completion_item_id = Some(item_id.clone());
            atom.completion_seq = Some(u64::try_from(after)?);
            atom.payload = Some(pl_protocol::PayloadData::Deferred {
                reference: pl_protocol::ContentRef {
                    database_id: database.clone(),
                    target: pl_protocol::ContentTarget::ItemPayload { item_id },
                },
                byte_length: u64::try_from(row.try_get::<i64>("", "byte_length")?)?,
            });
            let run: i64 = row.try_get("", "display_run_start")?;
            let ordinal = u64::try_from(row.try_get::<i64>("", "display_run_ordinal")?)?;
            let is_work = matches!(
                crate::studio::runtime::chat_item::native_read_hint_v1(
                    &row.try_get::<String>("", "query_class")?,
                    &atom
                ),
                pl_core::chat::ChatReadHint::Adjacent { .. }
            );
            let atom = lightweight(atom, &database);
            if current.as_ref().is_none_or(|(start, _)| *start != run) {
                ensure!(ordinal == 1, "legacy run must start with its first member");
                position += 1;
                let id = serde_json::to_string(&("legacy-run", &database, run))?;
                let header = DisplayHeader {
                    version: 4,
                    id: id.clone(),
                    source: atom.source.clone(),
                    block_order: position,
                    history_pos: Some(position),
                    boundary: None,
                    first_content_at: None,
                    sealed: true,
                    unfinished: 0,
                    next_member: 0,
                    revision: 1,
                    skip_display: false,
                    thinking_summary: None,
                    body: if is_work {
                        DisplayBlockBody::Work {
                            timing: pl_protocol::WorkTiming::default(),
                            members: pl_protocol::DisplayBlockRef {
                                database_id: database.clone(),
                                block_id: id.clone(),
                            },
                        }
                    } else {
                        DisplayBlockBody::Single {
                            record: Box::new(record(atom.clone(), None)),
                            visibility: SingleVisibility::Content,
                        }
                    },
                };
                db.execute_raw(statement("INSERT INTO conversation_display_blocks(block_id,source_key,block_order,history_pos,sealed,updated_effect,header) VALUES(?,?,?,?,1,?,?)",vec![id.into(),serde_json::to_string(&header.source)?.into(),integer(position)?.into(),integer(position)?.into(),effect.into(),serde_json::to_vec(&header)?.into()])).await?;
                current = Some((run, header));
            }
            let (_, header) = current.as_mut().context("legacy display run")?;
            ensure!(
                ordinal == header.next_member + 1
                    && is_work == matches!(header.body, DisplayBlockBody::Work { .. }),
                "legacy run membership differs"
            );
            header.next_member = ordinal;
            header.revision = ordinal;
            let association = member_key(&atom)?;
            let member = DisplayMemberWrite {
                block_id: header.id.clone(),
                association_key: association.clone(),
                terminal: true,
                head: pl_protocol::DisplayMemberHead {
                    member_key: association.clone(),
                    member_order: ordinal,
                    record: record(atom, None),
                },
            };
            let completion = member.head.record.atom.completion_item_id.clone();
            db.execute_raw(statement("INSERT INTO conversation_display_members(block_id,member_order,member_key,association_key,terminal,completion_id,updated_effect,metadata) VALUES(?,?,?,?,1,?,?,?)",vec![header.id.clone().into(),integer(ordinal)?.into(),association.clone().into(),association.into(),completion.into(),effect.into(),serde_json::to_vec(&member)?.into()])).await?;
            db.execute_raw(statement(
                "UPDATE conversation_display_blocks SET header=? WHERE block_id=?",
                vec![serde_json::to_vec(header)?.into(), header.id.clone().into()],
            ))
            .await?;
        }
    }
    db.execute_raw(statement(
        "UPDATE history_meta SET display_published_through=?,display_applied_effect=? WHERE id=1",
        vec![integer(position)?.into(), effect.into()],
    ))
    .await?;
    Ok(())
}
