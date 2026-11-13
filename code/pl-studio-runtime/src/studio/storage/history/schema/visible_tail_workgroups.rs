//! Schema 20 -> 21: retain one legal tail and preserve every other old display cut.
use super::*;
use crate::studio::thread_projection::presentation::{
    DisplayHeader, DisplayMemberWrite, member_key,
};
use pl_protocol::{ChatAtomLifecycle, DisplayBlockBody, DisplayContentSource, DisplayRecord};

pub(super) struct VisibleTailWorkgroups;
impl MigrationName for VisibleTailWorkgroups {
    fn name(&self) -> &str {
        VISIBLE_TAIL_WORKGROUPS
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for VisibleTailWorkgroups {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        upgrade(manager.get_connection()).await.map_err(conversion)
    }
}

fn convert(old: display_observations::legacy::DisplayHeader) -> Result<DisplayHeader> {
    ensure!(
        old.version == 2,
        "visible-tail migration requires a version-2 header"
    );
    let mut value = serde_json::to_value(old)?;
    value["version"] = 3.into();
    value["first_content_at"] = serde_json::Value::Null;
    if value["body"]["kind"] == "single" {
        value["body"]["visibility"] = "content".into();
    }
    Ok(serde_json::from_value(value)?)
}

fn unavailable(record: &mut DisplayRecord) {
    // Only the real identity and start evidence survive an unknown RAM prefix.
    record.atom.payload = None;
    record.atom.contents.clear();
    record.atom.wait = None;
    record.atom.source_state = None;
    record.atom.content_present = None;
    record.content_source = DisplayContentSource::FrozenObservation {
        captured_at: None,
        available: false,
    };
}

async fn verify_record(db: &impl ConnectionTrait, record: &DisplayRecord) -> Result<()> {
    if let DisplayContentSource::CompletedOriginal { completion_id } = &record.content_source {
        let original = db
            .query_one_raw(statement(
                "SELECT metadata FROM conversation_items WHERE item_id=?",
                vec![completion_id.clone().into()],
            ))
            .await?
            .context("display original is missing; original history preserved")?;
        let original: pl_protocol::ChatAtom =
            serde_json::from_slice(&original.try_get::<Vec<u8>>("", "metadata")?)?;
        ensure!(
            record.atom.completion_item_id.as_ref() == Some(completion_id)
                && original.id == record.atom.id
                && original.source == record.atom.source
                && original.kind == record.atom.kind
                && original.lifecycle == record.atom.lifecycle
                && original.tool == record.atom.tool,
            "display original ownership differs; original history preserved"
        );
    }
    Ok(())
}

async fn members(
    db: &impl ConnectionTrait,
    header: &mut DisplayHeader,
    freeze: bool,
) -> Result<()> {
    let mut after = 0u64;
    let mut unfinished = 0u64;
    loop {
        let rows = db.query_all_raw(statement(
            "SELECT member_order,member_key,association_key,terminal,completion_id,metadata
             FROM conversation_display_members WHERE block_id=? AND member_order>? ORDER BY member_order LIMIT 128",
            vec![header.id.clone().into(), integer(after)?.into()],
        )).await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let mut member: DisplayMemberWrite =
                serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
            after = after
                .checked_add(1)
                .context("display member order exhausted")?;
            ensure!(
                member.block_id == header.id
                    && member.head.member_order == after
                    && integer(after)? == row.try_get::<i64>("", "member_order")?
                    && member.head.member_key == row.try_get::<String>("", "member_key")?
                    && member.association_key == row.try_get::<String>("", "association_key")?
                    && member.association_key == member_key(&member.head.record.atom)?
                    && member.terminal == (row.try_get::<i64>("", "terminal")? == 1)
                    && member.terminal
                        == matches!(
                            member.head.record.atom.lifecycle,
                            ChatAtomLifecycle::Terminal { .. }
                        ),
                "visible-tail member index or ownership differs; original history preserved"
            );
            verify_record(db, &member.head.record).await?;
            let completion = match &member.head.record.content_source {
                DisplayContentSource::CompletedOriginal { completion_id } => {
                    Some(completion_id.as_str())
                }
                _ => None,
            };
            ensure!(
                completion
                    == row
                        .try_get::<Option<String>>("", "completion_id")?
                        .as_deref(),
                "visible-tail original index differs"
            );
            if !member.terminal {
                unfinished = unfinished
                    .checked_add(1)
                    .context("unfinished display count exhausted")?;
            }
            if freeze
                && matches!(
                    member.head.record.content_source,
                    DisplayContentSource::CurrentAtom
                )
            {
                ensure!(
                    !member.terminal,
                    "terminal display row has a mutable content source"
                );
                if let DisplayBlockBody::Work { summary, .. } = &mut header.body {
                    match member.head.record.atom.lifecycle {
                        ChatAtomLifecycle::Active {
                            status: pl_protocol::ChatActiveStatus::Waiting,
                            ..
                        } => {
                            summary.waiting = summary
                                .waiting
                                .checked_sub(1)
                                .context("legacy waiting count differs")?;
                        }
                        _ => {
                            summary.running = summary
                                .running
                                .checked_sub(1)
                                .context("legacy running count differs")?;
                        }
                    }
                    summary.unavailable = summary
                        .unavailable
                        .checked_add(1)
                        .context("legacy unavailable count exhausted")?;
                    summary.thinking_summary = None;
                    summary.thinking_content = None;
                    summary.duration_ms = None;
                    summary.elapsed_ms = None;
                }
                unavailable(&mut member.head.record);
                if let DisplayBlockBody::Single { record, .. } = &mut header.body {
                    ensure!(
                        record.atom.id == member.head.record.atom.id,
                        "legacy Single member differs"
                    );
                    **record = member.head.record.clone();
                }
                db.execute_raw(statement(
                    "UPDATE conversation_display_members SET metadata=? WHERE block_id=? AND member_order=?",
                    vec![serde_json::to_vec(&member)?.into(), header.id.clone().into(), integer(after)?.into()],
                )).await?;
            }
        }
    }
    ensure!(
        after == header.next_member && unfinished == header.unfinished,
        "visible-tail header/member counts differ; original history preserved"
    );
    Ok(())
}

pub(in crate::studio::storage::history) async fn upgrade(db: &impl ConnectionTrait) -> Result<()> {
    display_observations::validate(db).await?;
    let last = db
        .query_one_raw(statement(
            "SELECT block_id FROM conversation_display_blocks ORDER BY block_order DESC LIMIT 1",
            vec![],
        ))
        .await?
        .map(|row| row.try_get::<String>("", "block_id"))
        .transpose()?;
    let (mut published, _) = conversation::display::watermarks(db).await?;
    let mut after = 0u64;
    loop {
        let rows = db.query_all_raw(statement(
            "SELECT block_id,source_key,block_order,history_pos,sealed,header FROM conversation_display_blocks
             WHERE block_order>? ORDER BY block_order LIMIT 128", vec![integer(after)?.into()],
        )).await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let old = serde_json::from_slice(&row.try_get::<Vec<u8>>("", "header")?)?;
            let mut header = convert(old)?;
            after = header.block_order;
            ensure!(
                header.id == row.try_get::<String>("", "block_id")?
                    && integer(after)? == row.try_get::<i64>("", "block_order")?
                    && header.history_pos.map(integer).transpose()?
                        == row.try_get::<Option<i64>>("", "history_pos")?
                    && header.sealed == (row.try_get::<i64>("", "sealed")? == 1)
                    && serde_json::to_string(&header.source)?
                        == row.try_get::<String>("", "source_key")?,
                "visible-tail header index differs; original history preserved"
            );
            let retain = last.as_ref() == Some(&header.id)
                && !header.sealed
                && header.history_pos.is_none()
                && header.boundary.is_none()
                && !header.skip_display
                && matches!(header.body, DisplayBlockBody::Work { .. });
            let unpublished = header.history_pos.is_none();
            members(db, &mut header, unpublished && !retain).await?;
            if unpublished && !retain {
                header.legacy = true;
                header.sealed = true;
                header.skip_display = false;
                header.active_since = None;
                header.duration_known = false;
                published = published
                    .checked_add(1)
                    .filter(|n| *n <= i64::MAX as u64)
                    .context("display history exhausted during migration")?;
                header.history_pos = Some(published);
            }
            conversation::display::validate_header(&header)?;
            db.execute_raw(statement(
                "UPDATE conversation_display_blocks SET header=?,history_pos=?,sealed=? WHERE block_id=?",
                vec![serde_json::to_vec(&header)?.into(), header.history_pos.map(integer).transpose()?.into(),
                    i64::from(header.sealed).into(), header.id.clone().into()],
            )).await?;
        }
    }
    db.execute_raw(statement(
        "UPDATE history_meta SET display_published_through=?,schema_version=21 WHERE id=1",
        vec![integer(published)?.into()],
    ))
    .await?;
    db.execute_unprepared(
        "CREATE UNIQUE INDEX conversation_display_current_work ON conversation_display_blocks((1))
         WHERE history_pos IS NULL AND sealed=0 AND json_extract(header,'$.body.kind')='work';",
    )
    .await?;
    validate(db).await
}

pub(super) async fn validate(db: &impl ConnectionTrait) -> Result<()> {
    ensure!(
        version(db).await? == 21,
        "visible-tail history format is not 21"
    );
    display_snapshots::validate_preserved(db).await?;
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
mod tests;
