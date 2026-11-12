//! Content-only schema-20 migration: preserve every published identity and immutable member.
use super::display_observations::legacy::{DisplayBlockBody, DisplayHeader, work};
use super::*;
use crate::studio::thread_projection::presentation::DisplayMemberWrite;
use pl_protocol::{
    ChatAtom, ChatAtomKind, ChatAtomLifecycle, ChatSourceId, ChatTerminalOutcome, DisplayBlockRef,
    DisplayContentSource, WorkSummary,
};

pub(super) struct ToolWork;
impl MigrationName for ToolWork {
    fn name(&self) -> &str {
        TOOL_WORK
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for ToolWork {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        upgrade(manager.get_connection()).await.map_err(conversion)
    }
}

async fn upgrade(db: &impl ConnectionTrait) -> Result<()> {
    display_observations::validate(db).await?;
    let database: String = db
        .query_one_raw(statement(
            "SELECT database_id FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .context("tool Work migration database identity missing")?
        .try_get("", "database_id")?;
    let mut after = 0i64;
    loop {
        let rows = db
            .query_all_raw(statement(
                "SELECT block_id,block_order,header FROM conversation_display_blocks
             WHERE block_order>? ORDER BY block_order LIMIT 128",
                vec![after.into()],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            after = row.try_get("", "block_order")?;
            let id: String = row.try_get("", "block_id")?;
            let mut header: DisplayHeader =
                serde_json::from_slice(&row.try_get::<Vec<u8>>("", "header")?)?;
            let DisplayBlockBody::Single { record } = &header.body else {
                continue;
            };
            let atom = &record.atom;
            if atom.kind != ChatAtomKind::ToolCall {
                continue;
            }
            // Independent foreground outputs retain their original producer contract.
            // Background delivery overwrote that flag, but retained the typed tool identity.
            if matches!(atom.source, ChatSourceId::BackgroundResult { .. }) {
                ensure!(
                    atom.tool.is_some(),
                    "tool Work migration lacks producer identity: {id}"
                );
            }
            if !work(atom) {
                continue;
            }
            ensure!(
                header.id == id
                    && header.block_order == u64::try_from(after)?
                    && header.source == atom.source
                    && header.sealed
                    && header.history_pos.is_some()
                    && header.unfinished == 0
                    && header.version == 2
                    && header.next_member == 1,
                "tool Work migration found inconsistent Single header: {id}"
            );
            let members = db
                .query_all_raw(statement(
                    "SELECT member_key,completion_id,metadata FROM conversation_display_members
                 WHERE block_id=? ORDER BY member_order LIMIT 2",
                    vec![id.clone().into()],
                ))
                .await?;
            ensure!(
                members.len() == 1,
                "tool Single must have exactly one member: {id}"
            );
            let member: DisplayMemberWrite =
                serde_json::from_slice(&members[0].try_get::<Vec<u8>>("", "metadata")?)?;
            ensure!(
                member.block_id == id
                    && member.terminal
                    && member.head.record == **record
                    && member.head.member_key == members[0].try_get::<String>("", "member_key")?,
                "tool Single member conflicts with header: {id}"
            );
            let atom = &member.head.record.atom;
            let DisplayContentSource::CompletedOriginal { completion_id } =
                &member.head.record.content_source
            else {
                anyhow::bail!("tool Single lacks a completed original: {id}");
            };
            ensure!(
                atom.completion_item_id.as_ref() == Some(completion_id)
                    && members[0]
                        .try_get::<Option<String>>("", "completion_id")?
                        .as_ref()
                        == Some(completion_id),
                "tool Single original identity conflicts: {id}"
            );
            // Read metadata only: payload, contents, facts and execution recovery are never rewritten.
            let original = db
                .query_one_raw(statement(
                    "SELECT metadata FROM conversation_items WHERE item_id=?",
                    vec![completion_id.clone().into()],
                ))
                .await?
                .context("tool Single original is missing")?;
            let original: ChatAtom =
                serde_json::from_slice(&original.try_get::<Vec<u8>>("", "metadata")?)?;
            ensure!(
                original.id == atom.id
                    && original.kind == atom.kind
                    && original.source == atom.source
                    && original.tool == atom.tool
                    && original.lifecycle == atom.lifecycle
                    && original.tool.is_some(),
                "tool Single original cannot prove producer classification: {id}"
            );
            let ChatAtomLifecycle::Terminal { outcome, .. } = atom.lifecycle else {
                anyhow::bail!("tool Single member is not terminal: {id}");
            };
            let duration_ms = atom
                .started_at
                .zip(atom.finished_at)
                .and_then(|(start, end)| end.checked_sub(start))
                .and_then(|duration| u64::try_from(duration).ok());
            header.body = DisplayBlockBody::Work {
                summary: Box::new(WorkSummary {
                    total: 1,
                    terminal: 1,
                    failed: u64::from(outcome == ChatTerminalOutcome::Failed),
                    cancelled: u64::from(outcome == ChatTerminalOutcome::Cancelled),
                    transferred: u64::from(outcome == ChatTerminalOutcome::Transferred),
                    started_at: atom.started_at,
                    finished_at: atom.finished_at,
                    duration_ms,
                    // Execution timestamps do not prove the old block's admission time or
                    // display interval. Preserve them above, but do not invent display timing.
                    created_at: None,
                    elapsed_ms: None,
                    ..Default::default()
                }),
                members: DisplayBlockRef {
                    database_id: database.clone(),
                    block_id: id.clone(),
                },
            };
            db.execute_raw(statement(
                "UPDATE conversation_display_blocks SET header=? WHERE block_id=?",
                vec![serde_json::to_vec(&header)?.into(), id.into()],
            ))
            .await?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests;
