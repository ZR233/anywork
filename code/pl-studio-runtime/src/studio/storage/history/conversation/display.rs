//! Display row IO. The caller owns the original history transaction.
use super::*;
use crate::studio::thread_projection::presentation::{
    DisplayHeader, DisplayMemberWrite, PreparedDisplayDelta,
};
use pl_protocol::{DisplayBlock, DisplayBlockBody, DisplayContentSource, PayloadData};
use sea_orm::TransactionTrait;

pub(in crate::studio) struct DisplayRecovery {
    pub published: u64,
    pub last_order: u64,
    pub effect: u64,
    pub open: Vec<DisplayHeader>,
    pub unfinished: Vec<DisplayMemberWrite>,
}

pub(in crate::studio) struct StoredDisplayCut {
    pub published: u64,
    pub effect: u64,
    pub current_work_id: Option<String>,
    pub open: Vec<Arc<DisplayHeader>>,
}

pub(in crate::studio) struct StoredDisplayMembers {
    pub header: Arc<DisplayHeader>,
    pub entries: Vec<DisplayMemberWrite>,
}
pub(in crate::studio) async fn watermarks(db: &impl ConnectionTrait) -> Result<(u64, u64)> {
    let row = db
        .query_one_raw(statement(
            "SELECT display_published_through,display_applied_effect FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .context("display watermarks are missing; original history preserved")?;
    Ok((
        u64::try_from(row.try_get::<i64>("", "display_published_through")?)?,
        u64::try_from(row.try_get::<i64>("", "display_applied_effect")?)?,
    ))
}

pub(in crate::studio::storage::history) fn validate_header(header: &DisplayHeader) -> Result<()> {
    ensure!(
        header.version == 3 && header.block_order > 0 && !header.id.is_empty(),
        "invalid display header"
    );
    if let Some(pos) = header.history_pos {
        ensure!(
            pos > 0
                && (header.legacy || header.boundary.is_some())
                && header.sealed
                && !header.skip_display,
            "published display header is not ready"
        );
    }
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
    Ok(())
}

fn decode_header(row: &QueryResult) -> Result<DisplayHeader> {
    let header: DisplayHeader = serde_json::from_slice(&row.try_get::<Vec<u8>>("", "header")?)?;
    validate_header(&header)?;
    ensure!(
        header.id == row.try_get::<String>("", "block_id")?
            && header.block_order == u64::try_from(row.try_get::<i64>("", "block_order")?)?
            && header.history_pos
                == row
                    .try_get::<Option<i64>>("", "history_pos")?
                    .map(u64::try_from)
                    .transpose()?
            && header.sealed == (row.try_get::<i64>("", "sealed")? == 1)
            && serde_json::to_string(&header.source)? == row.try_get::<String>("", "source_key")?,
        "display header differs from indexed identity; original history preserved"
    );
    Ok(header)
}

fn decode_member(row: &QueryResult) -> Result<DisplayMemberWrite> {
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

fn completion_id(record: &pl_protocol::DisplayRecord) -> Option<&str> {
    match &record.content_source {
        DisplayContentSource::CompletedOriginal { completion_id } => Some(completion_id),
        _ => None,
    }
}

fn validate_original(atom: &pl_protocol::ChatAtom, original: &pl_protocol::ChatAtom) -> Result<()> {
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

async fn validate_original_references(
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
        let atom: pl_protocol::ChatAtom =
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

const HEAD: &str = "block_id,source_key,block_order,history_pos,sealed,updated_effect,header";
const MEMBER: &str = "block_id,member_order,member_key,association_key,terminal,completion_id,updated_effect,metadata";
const RECEIPT: &str = "studio.display-delta:v2";

pub(in crate::studio) async fn verify(
    db: &impl ConnectionTrait,
    delta: &PreparedDisplayDelta,
) -> Result<()> {
    let row = db.query_one_raw(statement(
        "SELECT kind,payload,digest,last_write_seq FROM history_fact_receipts WHERE item_id=? AND revision=?",
        vec![RECEIPT.into(), integer(delta.effect_seq)?.into()]
    )).await?.context("display replay has no original commit receipt")?;
    let digest = delta.digest()?;
    let payload = serde_json::to_string(&digest)?;
    ensure!(
        row.try_get::<String>("", "kind")? == "displayDelta"
            && row.try_get::<String>("", "payload")? == payload
            && row.try_get::<String>("", "digest")?
                == pl_core::context::content_hash(payload.as_bytes())
            && row.try_get::<i64>("", "last_write_seq")? == integer(delta.effect_seq)?,
        "display replay differs from frozen commit receipt"
    );
    let (published, effect) = watermarks(db).await?;
    ensure!(
        effect >= delta.effect_seq && published >= delta.published_through,
        "display replay is not covered by durable watermarks"
    );
    Ok(())
}

pub(in crate::studio) async fn apply(
    db: &impl ConnectionTrait,
    delta: &PreparedDisplayDelta,
) -> Result<()> {
    let (old_published, old_effect) = watermarks(db).await?;
    if delta.effect_seq <= old_effect {
        return verify(db, delta).await;
    }
    ensure!(
        delta.published_through >= old_published,
        "display published prefix regressed"
    );
    let mut expected_pos = old_published;
    // Creation order need not equal cross-source publication order.
    let mut positions = delta
        .blocks
        .iter()
        .filter_map(|w| w.header.history_pos)
        .collect::<Vec<_>>();
    positions.sort_unstable();
    for pos in positions {
        expected_pos = expected_pos
            .checked_add(1)
            .context("display prefix exhausted")?;
        ensure!(pos == expected_pos, "display published prefix has a hole");
    }
    ensure!(
        expected_pos == delta.published_through,
        "display prefix lacks frozen heads"
    );
    let mut previously_sealed = std::collections::BTreeSet::new();
    let mut owners = std::collections::HashMap::new();
    for write in &delta.blocks {
        let h = &write.header;
        validate_header(h)?;
        ensure!(
            write.published.as_deref() == h.frozen().as_ref(),
            "frozen display Arc differs"
        );
        let existing = db
            .query_one_raw(statement(
                &format!("SELECT {HEAD} FROM conversation_display_blocks WHERE block_id=?"),
                vec![h.id.clone().into()],
            ))
            .await?;
        let values = vec![
            serde_json::to_string(&h.source)?.into(),
            integer(h.block_order)?.into(),
            h.history_pos.map(integer).transpose()?.into(),
            i64::from(h.sealed).into(),
            integer(delta.effect_seq)?.into(),
            serde_json::to_vec(h.as_ref())?.into(),
            h.id.clone().into(),
        ];
        if let Some(row) = existing {
            let old = decode_header(&row)?;
            if old.sealed {
                previously_sealed.insert(old.id.clone());
                let mut published = old.clone();
                published.history_pos = h.history_pos;
                ensure!(
                    published == **h && h.history_pos.is_some(),
                    "sealed display header changed beyond initial publication"
                );
            }
            ensure!(
                old.history_pos.is_none()
                    && old.source == h.source
                    && old.block_order == h.block_order
                    && old.revision <= h.revision
                    && row.try_get::<i64>("", "updated_effect")? < integer(delta.effect_seq)?,
                "display head conflicts with immutable ownership"
            );
            db.execute_raw(statement(
                "UPDATE conversation_display_blocks SET source_key=?,block_order=?,history_pos=?,sealed=?,updated_effect=?,header=? WHERE block_id=?",
                values
            )).await?;
        } else {
            db.execute_raw(statement(
                "INSERT INTO conversation_display_blocks(source_key,block_order,history_pos,sealed,updated_effect,header,block_id) VALUES(?,?,?,?,?,?,?)",
                values
            )).await?;
        }
    }
    for write in &delta.blocks {
        owners.insert(
            write.header.id.clone(),
            (write.header.sealed, delta.effect_seq),
        );
    }
    let mut originals = std::collections::HashMap::new();
    for member in &delta.members {
        ensure!(
            member.head.member_order > 0
                && !member.head.member_key.is_empty()
                && member.association_key
                    == crate::studio::thread_projection::presentation::member_key(
                        &member.head.record.atom
                    )?
                && member.terminal
                    == matches!(
                        member.head.record.atom.lifecycle,
                        pl_protocol::ChatAtomLifecycle::Terminal { .. }
                    )
                && completion_id(&member.head.record)
                    == member.head.record.atom.completion_item_id.as_deref()
                && !matches!(
                    member.head.record.atom.payload,
                    Some(PayloadData::Inline { .. })
                ),
            "invalid lightweight display member"
        );
        if !owners.contains_key(&member.block_id) {
            let owner = db.query_one_raw(statement(
                "SELECT sealed,updated_effect FROM conversation_display_blocks WHERE block_id=?",
                vec![member.block_id.clone().into()],
            ))
            .await?
            .context("display member has no owner")?;
            owners.insert(
                member.block_id.clone(),
                (
                    owner.try_get::<i64>("", "sealed")? == 1,
                    u64::try_from(owner.try_get::<i64>("", "updated_effect")?)?,
                ),
            );
        }
        let (sealed, updated_effect) = owners[&member.block_id];
        ensure!(
            !previously_sealed.contains(&member.block_id)
                && (!sealed || updated_effect == delta.effect_seq),
            "sealed block rejects member updates"
        );
        if let Some(completion) = completion_id(&member.head.record) {
            if !originals.contains_key(completion) {
                let row = db
                    .query_one_raw(statement(
                        "SELECT metadata FROM conversation_items WHERE item_id=?",
                        vec![completion.into()],
                    ))
                    .await?
                    .context("display member references missing original completion")?;
                let original: pl_protocol::ChatAtom =
                    serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
                originals.insert(completion.to_owned(), original);
            }
            validate_original(&member.head.record.atom, &originals[completion])?;
        }
        let existing = db
            .query_one_raw(statement(
                &format!("SELECT {MEMBER} FROM conversation_display_members WHERE member_key=?"),
                vec![member.head.member_key.clone().into()],
            ))
            .await?;
        let values = vec![
            i64::from(member.terminal).into(),
            completion_id(&member.head.record).map(str::to_owned).into(),
            member.association_key.clone().into(),
            integer(delta.effect_seq)?.into(),
            serde_json::to_vec(member.as_ref())?.into(),
            member.block_id.clone().into(),
            integer(member.head.member_order)?.into(),
            member.head.member_key.clone().into(),
        ];
        if let Some(row) = existing {
            let old = decode_member(&row)?;
            ensure!(
                old.block_id == member.block_id
                    && old.head.member_order == member.head.member_order
                    && old.association_key == member.association_key
                    && (!old.terminal || old.head == member.head)
                    && row.try_get::<i64>("", "updated_effect")? < integer(delta.effect_seq)?,
                "display member conflicts with immutable terminal or ownership"
            );
            db.execute_raw(statement(
                "UPDATE conversation_display_members SET terminal=?,completion_id=?,association_key=?,updated_effect=?,metadata=? WHERE block_id=? AND member_order=? AND member_key=?",
                values
            )).await?;
        } else {
            db.execute_raw(statement(
                "INSERT INTO conversation_display_members(terminal,completion_id,association_key,updated_effect,metadata,block_id,member_order,member_key) VALUES(?,?,?,?,?,?,?,?)",
                values
            )).await?;
        }
    }
    for removed in &delta.remove_empty {
        ensure!(
            removed.history_pos.is_none()
                && removed.skip_display
                && removed.unfinished == 0
                && matches!(&removed.body, DisplayBlockBody::Single { record, .. }
                if record.atom.kind == pl_protocol::ChatAtomKind::Text && record.atom.content_present == Some(false)
                && matches!(record.atom.lifecycle, pl_protocol::ChatAtomLifecycle::Terminal { .. })),
            "RemoveEmpty requires reliable empty terminal text"
        );
        let existing = db
            .query_one_raw(statement(
                &format!("SELECT {HEAD} FROM conversation_display_blocks WHERE block_id=?"),
                vec![removed.id.clone().into()],
            ))
            .await?;
        if let Some(row) = existing {
            let old = decode_header(&row)?;
            ensure!(
                old.history_pos.is_none()
                    && old.id == removed.id
                    && old.source == removed.source
                    && old.block_order == removed.block_order
                    && matches!((&old.body, &removed.body),
                        (DisplayBlockBody::Single { record: before, .. }, DisplayBlockBody::Single { record: after, .. })
                        if before.atom.id == after.atom.id && before.atom.kind == pl_protocol::ChatAtomKind::Text
                            && before.atom.content_present != Some(true)),
                "cannot remove a published display"
            );
            db.execute_raw(statement(
                "DELETE FROM conversation_display_members WHERE block_id=?",
                vec![removed.id.clone().into()],
            ))
            .await?;
            db.execute_raw(statement(
                "DELETE FROM conversation_display_blocks WHERE block_id=? AND history_pos IS NULL",
                vec![removed.id.clone().into()],
            ))
            .await?;
        }
    }
    let mut observation_keys = std::collections::BTreeSet::new();
    for member in &delta.members {
        if matches!(
            member.head.record.content_source,
            DisplayContentSource::FrozenObservation {
                available: true,
                ..
            }
        ) {
            let atom = &member.head.record.atom;
            for reference in atom.contents.iter().map(|body| &body.reference).chain(
                atom.payload.iter().filter_map(|payload| match payload {
                    PayloadData::Deferred { reference, .. } => Some(reference),
                    _ => None,
                }),
            ) {
                let pl_protocol::ContentTarget::Body { owner, key } = &reference.target else {
                    anyhow::bail!("frozen observation does not reference a Body");
                };
                ensure!(
                    matches!(owner, pl_protocol::ContentOwner::DisplayObservation { block_id, member_key }
                    if block_id == &member.block_id && member_key == &member.head.member_key),
                    "frozen observation content escaped its display owner"
                );
                observation_keys.insert(pl_core::chat::ChatContentKey {
                    owner: crate::studio::conversation_identity::content_owner_key(owner)?,
                    key: key.clone(),
                });
            }
        }
    }
    for content in &delta.contents {
        ensure!(
            observation_keys.remove(&content.descriptor.key),
            "unowned or duplicate observation content"
        );
        super::content::write_content(db, content, true).await?;
    }
    ensure!(
        observation_keys.is_empty(),
        "frozen observation content is missing from its effect"
    );
    super::super::write_fact_receipt(
        db,
        integer(delta.effect_seq)?,
        &super::super::FactReceiptWrite {
            item_id: RECEIPT.into(),
            revision: delta.effect_seq,
            kind: "displayDelta",
            payload: serde_json::to_string(&delta.digest()?)?,
        },
    )
    .await?;
    db.execute_raw(statement(
        "UPDATE history_meta SET display_published_through=?,display_applied_effect=? WHERE id=1",
        vec![
            integer(delta.published_through)?.into(),
            integer(delta.effect_seq)?.into(),
        ],
    ))
    .await?;
    Ok(())
}

/// History main reads only indexed small headers; never JOINs/counts members or reads bodies.
pub(in crate::studio) async fn history_heads(
    db: &impl ConnectionTrait,
    ceiling: u64,
    before: Option<u64>,
    limit: usize,
) -> Result<Vec<Arc<DisplayBlock>>> {
    let upper = ceiling.min(before.map_or(ceiling, |value| value.saturating_sub(1)));
    let rows = db.query_all_raw(statement(
        &format!("SELECT {HEAD} FROM conversation_display_blocks WHERE history_pos<=? ORDER BY history_pos DESC LIMIT ?"),
        vec![integer(upper)?.into(), integer(limit)?.into()]
    )).await?;
    let mut heads = rows
        .iter()
        .map(|row| {
            Ok(Arc::new(
                decode_header(row)?
                    .frozen()
                    .context("history head has no position")?,
            ))
        })
        .collect::<Result<Vec<_>>>()?;
    heads.reverse();
    Ok(heads)
}

pub(in crate::studio) async fn open_heads(
    db: &impl ConnectionTrait,
    before_order: Option<u64>,
    limit: usize,
) -> Result<Vec<DisplayHeader>> {
    let upper = before_order.map_or(i64::MAX as u64, |value| value.saturating_sub(1));
    let rows = db.query_all_raw(statement(
        &format!("SELECT {HEAD} FROM conversation_display_blocks WHERE history_pos IS NULL AND block_order<=? ORDER BY block_order DESC LIMIT ?"),
        vec![integer(upper)?.into(), integer(limit)?.into()]
    )).await?;
    let mut heads = rows.iter().map(decode_header).collect::<Result<Vec<_>>>()?;
    heads.reverse();
    Ok(heads)
}

pub(in crate::studio) async fn member_page(
    db: &impl ConnectionTrait,
    block_id: &str,
    before: Option<u64>,
    limit: usize,
) -> Result<Vec<DisplayMemberWrite>> {
    ensure!(
        db.query_one_raw(statement(
            "SELECT 1 FROM conversation_display_blocks WHERE block_id=?",
            vec![block_id.into()]
        ))
        .await?
        .is_some(),
        "display block reference is missing"
    );
    let upper = before.map_or(i64::MAX as u64, |value| value.saturating_sub(1));
    let rows = db.query_all_raw(statement(
        &format!("SELECT {MEMBER} FROM conversation_display_members WHERE block_id=? AND member_order<=? ORDER BY member_order DESC LIMIT ?"),
        vec![block_id.into(), integer(upper)?.into(), integer(limit)?.into()]
    )).await?;
    let mut members = rows.iter().map(decode_member).collect::<Result<Vec<_>>>()?;
    members.reverse();
    Ok(members)
}

pub(in crate::studio) async fn recovery(db: &impl ConnectionTrait) -> Result<DisplayRecovery> {
    let (published, effect) = watermarks(db).await?;
    let row = db
        .query_one_raw(statement(
            "SELECT block_order FROM conversation_display_blocks ORDER BY block_order DESC LIMIT 1",
            vec![],
        ))
        .await?;
    let last_order = row
        .map(|r| r.try_get::<i64>("", "block_order"))
        .transpose()?
        .unwrap_or(0);
    let open = open_heads(db, None, i64::MAX as usize).await?;
    let mut unfinished = Vec::new();
    for header in &open {
        if header.sealed {
            continue;
        }
        let rows = db.query_all_raw(statement(
            &format!("SELECT {MEMBER} FROM conversation_display_members WHERE block_id=? AND terminal=0 ORDER BY member_order"),
            vec![header.id.clone().into()]
        )).await?;
        let members = rows.iter().map(decode_member).collect::<Result<Vec<_>>>()?;
        ensure!(
            members.len() as u64 == header.unfinished,
            "open display unfinished index differs"
        );
        unfinished.extend(members);
    }
    Ok(DisplayRecovery {
        published,
        effect,
        last_order: u64::try_from(last_order)?,
        open,
        unfinished,
    })
}

impl super::super::HistoryStore {
    pub(in crate::studio) async fn display_cut(
        &self,
        database: &str,
        before_order: Option<u64>,
        limit: usize,
    ) -> Result<StoredDisplayCut> {
        let connection = self
            .reader()
            .await?
            .context("display database is missing")?;
        ensure!(connection.database_id == database, "stale display database");
        let tx = connection.db.begin().await?;
        let (published, effect) = watermarks(&tx).await?;
        let open: Vec<_> = open_heads(&tx, before_order, limit)
            .await?
            .into_iter()
            .map(Arc::new)
            .collect();
        let current_work_id = if before_order.is_none() {
            open.iter()
                .find(|header| {
                    !header.sealed && matches!(header.body, DisplayBlockBody::Work { .. })
                })
                .map(|header| header.id.clone())
        } else {
            None
        };
        tx.commit().await?;
        Ok(StoredDisplayCut {
            published,
            effect,
            current_work_id,
            open,
        })
    }

    /// Fresh SQLite snapshot is established only after the caller captured P/Dp.
    pub(in crate::studio) async fn display_history_heads(
        &self,
        database: &str,
        after_pos: u64,
        through_pos: u64,
        before_pos: Option<u64>,
        limit: usize,
        ascending: bool,
    ) -> Result<Vec<Arc<DisplayBlock>>> {
        let connection = self
            .reader()
            .await?
            .context("display database is missing")?;
        ensure!(connection.database_id == database, "stale display database");
        let tx = connection.db.begin().await?;
        let (published, _) = watermarks(&tx).await?;
        ensure!(
            through_pos <= published,
            "display durable prefix not available"
        );
        let direction = if ascending { "ASC" } else { "DESC" };
        let upper =
            through_pos.min(before_pos.map_or(through_pos, |value| value.saturating_sub(1)));
        let rows = tx.query_all_raw(statement(
            &format!("SELECT {HEAD} FROM conversation_display_blocks WHERE history_pos>? AND history_pos<=? ORDER BY history_pos {direction} LIMIT ?"),
            vec![integer(after_pos)?.into(), integer(upper)?.into(), integer(limit)?.into()]
        )).await?;
        let mut result = rows
            .iter()
            .map(|row| {
                Ok(Arc::new(
                    decode_header(row)?
                        .frozen()
                        .context("display history head missing position")?,
                ))
            })
            .collect::<Result<Vec<_>>>()?;
        if !ascending {
            result.reverse();
        }
        let expected = upper.saturating_sub(after_pos).min(limit as u64);
        ensure!(
            result.len() as u64 == expected
                && result.first().is_none_or(|head| head.history_pos
                    == if ascending {
                        after_pos + 1
                    } else {
                        upper - expected + 1
                    }),
            "display history prefix has missing heads; original history preserved"
        );
        // A sparse history prefix is corruption, not an invitation to reconstruct old groups.
        for pair in result.windows(2) {
            ensure!(
                pair[0].history_pos.checked_add(1) == Some(pair[1].history_pos),
                "display history prefix has a hole"
            );
        }
        tx.commit().await?;
        Ok(result)
    }

    pub(in crate::studio) async fn display_member_page(
        &self,
        database: &str,
        block_id: &str,
        before: Option<u64>,
        limit: usize,
    ) -> Result<StoredDisplayMembers> {
        let connection = self
            .reader()
            .await?
            .context("display database is missing")?;
        ensure!(connection.database_id == database, "stale display database");
        let tx = connection.db.begin().await?;
        let row = tx
            .query_one_raw(statement(
                &format!("SELECT {HEAD} FROM conversation_display_blocks WHERE block_id=?"),
                vec![block_id.into()],
            ))
            .await?
            .context("display block reference is missing")?;
        let header = Arc::new(decode_header(&row)?);
        let entries = member_page(&tx, block_id, before, limit).await?;
        validate_original_references(&tx, &entries).await?;
        let upper = header
            .next_member
            .min(before.unwrap_or(u64::MAX).saturating_sub(1));
        let expected = upper.min(limit as u64);
        ensure!(
            entries.len() as u64 == expected
                && entries
                    .first()
                    .is_none_or(|member| member.head.member_order == upper - expected + 1)
                && entries
                    .windows(2)
                    .all(|pair| pair[0].head.member_order + 1 == pair[1].head.member_order),
            "display member page has missing rows; original history preserved"
        );
        tx.commit().await?;
        Ok(StoredDisplayMembers { header, entries })
    }

    pub(in crate::studio) async fn display_recovery(&self) -> Result<Option<DisplayRecovery>> {
        let Some(connection) = self.reader().await? else {
            return Ok(None);
        };
        let tx = connection.db.begin().await?;
        let result = recovery(&tx).await?;
        tx.commit().await?;
        Ok(Some(result))
    }
}

#[cfg(test)]
mod cost_tests;
#[cfg(test)]
mod tests;
