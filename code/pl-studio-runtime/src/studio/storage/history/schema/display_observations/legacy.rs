//! Frozen schema-20 encoding consumed only by published migrations.
use pl_protocol::{ChatFactPosition, ChatSourceId, DisplayBlockRef, DisplayRecord, WorkSummary};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(in crate::studio::storage::history::schema) struct DisplayHeader {
    pub version: u32,
    pub legacy: bool,
    pub id: String,
    pub source: ChatSourceId,
    pub block_order: u64,
    pub history_pos: Option<u64>,
    pub boundary: Option<ChatFactPosition>,
    pub sealed: bool,
    pub unfinished: u64,
    pub next_member: u64,
    pub revision: u64,
    pub skip_display: bool,
    pub active_since: Option<i64>,
    pub duration_known: bool,
    pub body: DisplayBlockBody,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub(in crate::studio::storage::history::schema) enum DisplayBlockBody {
    Work {
        summary: Box<WorkSummary>,
        members: DisplayBlockRef,
    },
    Single {
        record: Box<DisplayRecord>,
    },
}

// The published schema-20 classification stays independent of later product rules.
pub(in crate::studio::storage::history::schema) fn work(atom: &pl_protocol::ChatAtom) -> bool {
    use pl_protocol::{ChatAtomKind, ChatDeliveryKind, ChatSourceId};
    (atom.kind == ChatAtomKind::ToolCall
        && matches!(atom.source, ChatSourceId::BackgroundResult { .. })
        && atom
            .tool
            .as_ref()
            .is_some_and(|tool| tool.name != pl_tool::file_display::TOOL_SHOW_FILES))
        || (matches!(
            atom.kind,
            ChatAtomKind::Reasoning
                | ChatAtomKind::ToolCall
                | ChatAtomKind::FileChange
                | ChatAtomKind::Skill
        ) && matches!(atom.source, ChatSourceId::ForegroundTurn { .. })
            && atom.delivery != ChatDeliveryKind::Independent)
}

pub(super) async fn latest_published(db: &impl sea_orm::ConnectionTrait) -> anyhow::Result<u64> {
    use crate::studio::storage::history::{integer, statement};
    use anyhow::{Context, ensure};
    let row = db.query_one_raw(statement(
        "SELECT block_id,source_key,block_order,history_pos,sealed,header FROM conversation_display_blocks
         WHERE history_pos IS NOT NULL ORDER BY history_pos DESC LIMIT 1", vec![],
    )).await?;
    let Some(row) = row else { return Ok(0) };
    let header: DisplayHeader = serde_json::from_slice(&row.try_get::<Vec<u8>>("", "header")?)?;
    let position = header
        .history_pos
        .context("published display position is missing")?;
    ensure!(
        header.version == 2
            && !header.id.is_empty()
            && header.block_order > 0
            && position > 0
            && (header.legacy || header.boundary.is_some())
            && header.sealed
            && !header.skip_display
            && header.id == row.try_get::<String>("", "block_id")?
            && integer(header.block_order)? == row.try_get::<i64>("", "block_order")?
            && integer(position)? == row.try_get::<i64>("", "history_pos")?
            && row.try_get::<i64>("", "sealed")? == 1
            && serde_json::to_string(&header.source)? == row.try_get::<String>("", "source_key")?,
        "display header differs from indexed identity; original history preserved"
    );
    if let DisplayBlockBody::Single { record } = &header.body {
        ensure!(
            !matches!(
                record.atom.payload,
                Some(pl_protocol::PayloadData::Inline { .. })
            ),
            "display header retains inline completion payload"
        );
        let id = match &record.content_source {
            pl_protocol::DisplayContentSource::CompletedOriginal { completion_id } => {
                Some(completion_id.as_str())
            }
            _ => None,
        };
        ensure!(
            id == record.atom.completion_item_id.as_deref(),
            "display Single completion differs"
        );
    }
    if let DisplayBlockBody::Work { summary, members } = &header.body {
        ensure!(
            members.block_id == header.id
                && summary.total == header.next_member
                && summary.total
                    == summary
                        .terminal
                        .checked_add(header.unfinished)
                        .context("display counter overflow")?
                && header.unfinished
                    == summary
                        .running
                        .checked_add(summary.waiting)
                        .and_then(|n| n.checked_add(summary.unavailable))
                        .context("display counter overflow")?,
            "display summary/member counters differ"
        );
    }
    Ok(position)
}
