//! Frozen schema-22/23 display validation used only inside the schema-24 migration transaction.
use super::*;
use crate::PayloadData;
use crate::studio::storage::history::schema::v24_presentation::{
    DisplayHeader, DisplayMemberWrite,
};
use crate::studio::storage::history::schema::v24_presentation_types::{
    DisplayBlockBody, DisplayContentSource, DisplayRecord,
};

pub(in crate::studio::storage::history) fn validate_header(header: &DisplayHeader) -> Result<()> {
    ensure!(
        header.version == 5
            && header.block_order.get() > 0
            && header.next_member <= i64::MAX as u64
            && !header.id.is_empty(),
        "invalid display header"
    );
    if let DisplayBlockBody::Single { record, .. } = &header.body {
        ensure!(
            !matches!(record.atom.payload, Some(PayloadData::Inline { .. })),
            "display header retains inline completion payload"
        );
        ensure!(
            completion_id(record) == record.atom.completion_item_id.as_deref(),
            "display Single completion differs"
        );
    }
    if let DisplayBlockBody::Work { timing, members } = &header.body {
        ensure!(
            members.block_id == header.id,
            "display member owner differs"
        );
        ensure!(
            header.sealed == timing.finished_at.is_some()
                || (header.sealed && timing.started_at.is_none()),
            "display timing and boundary differ"
        );
        ensure!(
            header.unfinished <= header.next_member,
            "display unfinished count exceeds members"
        );
    }
    Ok(())
}

pub(in crate::studio::storage::history) fn decode_member(
    row: &QueryResult,
) -> Result<DisplayMemberWrite> {
    let member: DisplayMemberWrite =
        serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
    ensure!(
        member.block_id == row.try_get::<String>("", "block_id")?
            && member.head.member_order == u64::try_from(row.try_get::<i64>("", "member_order")?)?
            && member.head.member_key == row.try_get::<String>("", "member_key")?
            && member.terminal == (row.try_get::<i64>("", "terminal")? == 1)
            && member.association_key == row.try_get::<String>("", "association_key")?
            && completion_id(&member.head.record)
                == row
                    .try_get::<Option<String>>("", "completion_id")?
                    .as_deref()
            && !matches!(
                member.head.record.atom.payload,
                Some(PayloadData::Inline { .. })
            ),
        "display member differs from indexed identity; original history preserved"
    );
    Ok(member)
}

fn completion_id(record: &DisplayRecord) -> Option<&str> {
    match &record.content_source {
        DisplayContentSource::CompletedOriginal { completion_id } => Some(completion_id),
        _ => None,
    }
}

fn validate_original(atom: &crate::ChatAtom, original: &crate::ChatAtom) -> Result<()> {
    ensure!(
        atom.id == original.id
            && atom.source == original.source
            && atom.kind == original.kind
            && atom.lifecycle == original.lifecycle
            && atom.tool == original.tool,
        "display original ownership differs; original history preserved"
    );
    Ok(())
}

pub(in crate::studio::storage::history) async fn validate_original_references(
    db: &impl ConnectionTrait,
    members: &[DisplayMemberWrite],
) -> Result<()> {
    let ids = members
        .iter()
        .filter_map(|member| completion_id(&member.head.record))
        .collect::<std::collections::BTreeSet<_>>();
    if ids.is_empty() {
        return Ok(());
    }
    let placeholders = vec!["?"; ids.len()].join(",");
    let rows = db
        .query_all_raw(statement(
            &format!(
                "SELECT item_id,metadata FROM conversation_items WHERE item_id IN ({placeholders})"
            ),
            ids.iter().map(|id| (*id).into()).collect(),
        ))
        .await?;
    let mut originals = std::collections::HashMap::new();
    for row in rows {
        let atom: crate::ChatAtom =
            serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
        originals.insert(row.try_get::<String>("", "item_id")?, atom);
    }
    for member in members {
        if let Some(id) = completion_id(&member.head.record) {
            let original = originals
                .get(id)
                .context("display original reference is missing; original history preserved")?;
            validate_original(&member.head.record.atom, original)?;
        }
    }
    Ok(())
}
