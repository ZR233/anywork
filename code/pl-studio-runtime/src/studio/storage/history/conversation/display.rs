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
        header.version == 4 && header.block_order > 0 && !header.id.is_empty(),
        "invalid display header"
    );
    if let Some(pos) = header.history_pos {
        ensure!(
            pos > 0 && header.sealed && !header.skip_display,
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
        let mut snapshot = self
            .conversation_snapshot()
            .await?
            .context("display database is missing")?;
        snapshot.pin(&self.state.thread_id).await?;
        snapshot
            .display_member_page(database, block_id, before, limit)
            .await
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

impl super::super::ConversationSnapshot {
    pub(in crate::studio) async fn display_cut(
        self,
        database: &str,
        before_order: Option<u64>,
        limit: usize,
    ) -> Result<StoredDisplayCut> {
        ensure!(self.database_id == database, "stale display database");
        let (published, effect) = watermarks(&self.tx).await?;
        let open: Vec<_> = open_heads(&self.tx, before_order, limit)
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
        self.tx.commit().await?;
        Ok(StoredDisplayCut {
            published,
            effect,
            current_work_id,
            open,
        })
    }

    pub(in crate::studio) async fn display_member_page(
        self,
        database: &str,
        block_id: &str,
        before: Option<u64>,
        limit: usize,
    ) -> Result<StoredDisplayMembers> {
        ensure!(self.database_id == database, "stale display database");
        let row = self
            .tx
            .query_one_raw(statement(
                &format!("SELECT {HEAD} FROM conversation_display_blocks WHERE block_id=?"),
                vec![block_id.into()],
            ))
            .await?
            .context("display block reference is missing")?;
        let header = Arc::new(decode_header(&row)?);
        let entries = member_page(&self.tx, block_id, before, limit).await?;
        validate_original_references(&self.tx, &entries).await?;
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
        self.tx.commit().await?;
        Ok(StoredDisplayMembers { header, entries })
    }
}

#[cfg(test)]
mod cost_tests {
    //! Actual production display SQL, sampled only after fixture setup finishes.
    use super::super::run_read_tests::sqlite_work::{Sampler, Work};
    use super::*;
    use crate::studio::thread_projection::presentation::PresentationState;
    use pl_protocol::{
        ChatAtomKind, ChatAtomLifecycle, ChatDeliveryKind, ChatFactPosition, ChatSourceId,
        ChatTerminalOutcome, DisplayMemberHead, LiveDisplayBlock,
    };

    fn report(case: &str, history: u64, members: u64, encoded: usize, work: &Work) {
        eprintln!(
            "DISPLAY_SQL_COST {}",
            serde_json::json!({
                "query":case, "frozen_history":history, "group_members":members,
                "statements":work.statements, "selected_heads":work.candidates,
                "selected_members":work.member_rows, "selected_reference_rows":work.reference_rows,
                "selected_rows":work.candidates + work.member_rows + work.reference_rows,
                "vm_steps":work.vm_steps, "fullscan_steps":work.fullscan_steps,
                "encoded_head_or_member_bytes":encoded, "denied_reads":work.denied_reads,
                "original_payload_authorizations":work.payload_column_authorizations,
            })
        );
    }

    async fn seed_history(
        db: &impl ConnectionTrait,
        base: &DisplayHeader,
        member: &DisplayMemberWrite,
        after: u64,
        through: u64,
    ) -> Result<()> {
        db.execute_raw(statement(
        "WITH RECURSIVE n(i) AS (SELECT ? UNION ALL SELECT i+1 FROM n WHERE i<?)
         INSERT INTO conversation_display_blocks(block_id,source_key,block_order,history_pos,sealed,updated_effect,header)
         SELECT 'history-'||i,?,i+CASE WHEN i>20 THEN 1 ELSE 0 END,i,1,2,
             CAST(json_set(?,'$.id','history-'||i,'$.block_order',i+CASE WHEN i>20 THEN 1 ELSE 0 END,
                 '$.history_pos',i,'$.body.members.blockId','history-'||i) AS BLOB) FROM n",
        vec![integer(after+1)?.into(), integer(through)?.into(),
            serde_json::to_string(&base.source)?.into(), serde_json::to_string(base)?.into()]
    )).await?;
        db.execute_raw(statement(
        "INSERT INTO conversation_display_members(block_id,member_order,member_key,association_key,terminal,completion_id,updated_effect,metadata)
         SELECT block_id,1,block_id||':member:1',block_id||':association:1',1,NULL,2,
             CAST(json_set(?,'$.block_id',block_id,'$.head.memberOrder',1,
                 '$.head.memberKey',block_id||':member:1','$.association_key',block_id||':association:1','$.head.record.atom.id','tool-'||block_id) AS BLOB)
         FROM conversation_display_blocks WHERE history_pos>? AND history_pos<=? AND block_id<>'history-20'",
        vec![serde_json::to_string(member)?.into(), integer(after)?.into(), integer(through)?.into()]
    )).await?;
        db.execute_raw(statement("UPDATE history_meta SET applied_write_seq=2,display_applied_effect=2,display_published_through=? WHERE id=1",
        vec![integer(through)?.into()])).await?;
        Ok(())
    }

    async fn seed_members(
        db: &impl ConnectionTrait,
        base: &DisplayMemberWrite,
        headers: &mut [DisplayHeader; 2],
        after: u64,
        through: u64,
    ) -> Result<()> {
        db.execute_raw(statement(
        "WITH RECURSIVE n(i) AS (SELECT ? UNION ALL SELECT i+1 FROM n WHERE i<?)
         INSERT INTO conversation_display_members(block_id,member_order,member_key,association_key,terminal,completion_id,updated_effect,metadata)
         SELECT b.block_id,i,b.block_id||':member:'||i,b.block_id||':association:'||i,1,NULL,2,
             CAST(json_set(?,'$.block_id',b.block_id,'$.head.memberOrder',i,
                 '$.head.memberKey',b.block_id||':member:'||i,'$.association_key',b.block_id||':association:'||i,'$.head.record.atom.id','tool-'||i,
                 '$.head.record.atom.source',json_extract(b.header,'$.source')) AS BLOB)
         FROM n CROSS JOIN conversation_display_blocks b WHERE b.block_id IN ('history-20','open-work')",
        vec![integer(after+1)?.into(), integer(through)?.into(), serde_json::to_string(base)?.into()]
    )).await?;
        for header in headers {
            header.next_member = through;
            header.revision = through;
            db.execute_raw(statement(
                "UPDATE conversation_display_blocks SET header=? WHERE block_id=?",
                vec![serde_json::to_vec(header)?.into(), header.id.clone().into()],
            ))
            .await?;
        }
        Ok(())
    }

    #[tokio::test]
    async fn display_sql_cost_is_bounded_across_frozen_history_and_hundred_thousand_members()
    -> Result<()> {
        let (_dir, db) =
            crate::studio::storage::history::schema::work_snapshots::tests::fixture().await?;
        crate::studio::storage::history::schema::work_snapshots::initialize(&db).await?;

        let database: String = db
            .query_one_raw(statement(
                "SELECT database_id FROM history_meta WHERE id=1",
                vec![],
            ))
            .await?
            .context("database")?
            .try_get("", "database_id")?;
        let mut owner = PresentationState::default();
        owner.bind(&database)?;
        let mut atom: pl_protocol::ChatAtom =
            serde_json::from_slice(&super::super::tests::metadata("cost-seed"))?;
        atom.completion_item_id = None;
        atom.source = ChatSourceId::ForegroundTurn {
            turn_id: "history-turn".into(),
        };
        atom.kind = ChatAtomKind::ToolCall;
        atom.delivery = ChatDeliveryKind::Foreground;
        atom.lifecycle = ChatAtomLifecycle::Terminal {
            started: None,
            ended: Some(ChatFactPosition {
                effect_seq: 1,
                suborder: 0,
            }),
            outcome: ChatTerminalOutcome::Cancelled,
        };
        let seed = owner.prepare(1, 10, &[atom], &[], &[])?;
        let mut frozen = seed.blocks[0].header.as_ref().clone();
        frozen.id = "history-20".into();
        frozen.block_order = 20;
        frozen.history_pos = Some(20);
        frozen.sealed = true;
        frozen.boundary = Some(ChatFactPosition {
            effect_seq: 2,
            suborder: 0,
        });
        if let DisplayBlockBody::Work { timing, members } = &mut frozen.body {
            timing.finished_at = Some(20);
            members.block_id = frozen.id.clone();
        }
        seed_history(&db, &frozen, &seed.members[0], 0, 20).await?;
        let mut open = frozen.clone();
        open.id = "open-work".into();
        open.source = ChatSourceId::ForegroundTurn {
            turn_id: "open-turn".into(),
        };
        open.block_order = 21;
        open.history_pos = None;
        open.boundary = None;
        open.sealed = false;
        if let DisplayBlockBody::Work { timing, members } = &mut open.body {
            timing.finished_at = None;
            members.block_id = open.id.clone();
        }
        db.execute_raw(statement(
        "INSERT INTO conversation_display_blocks(block_id,source_key,block_order,history_pos,sealed,updated_effect,header) VALUES(?,?,21,NULL,0,2,?)",
        vec![open.id.clone().into(), serde_json::to_string(&open.source)?.into(), serde_json::to_vec(&open)?.into()]
    )).await?;
        let mut headers = [frozen.clone(), open];
        let mut previous_members = 0;
        let mut previous_history = 20;
        let mut baseline: Option<[u64; 3]> = None;
        for (history, members) in [(20, 20), (20, 100_000), (100_000, 100_000)] {
            // All setup is outside native sampling windows. This fixture contains lightweight
            // saved rows only; it does not reproduce the production SELECT implementation.
            if history > previous_history {
                seed_history(&db, &frozen, &seed.members[0], previous_history, history).await?;
            }
            if members > previous_members {
                seed_members(
                    &db,
                    &seed.members[0],
                    &mut headers,
                    previous_members,
                    members,
                )
                .await?;
            }
            previous_history = history;
            previous_members = members;

            let sampler = Sampler::display_heads(&db).await?;
            let outcome = history_heads(&db, 20, Some(21), 20).await;
            let work = sampler.finish(&db).await?;
            let heads = outcome?;
            assert_eq!(heads.len(), 20);
            assert_eq!(
                (
                    work.statements,
                    work.candidates,
                    work.member_rows,
                    work.reference_rows
                ),
                (1, 20, 0, 0)
            );
            assert_eq!(
                (
                    work.denied_reads,
                    work.payload_column_authorizations,
                    work.fullscan_steps
                ),
                (0, 0, 0)
            );
            let history_vm = work.vm_steps;
            report(
                "history_heads",
                history,
                members,
                serde_json::to_vec(&heads)?.len(),
                &work,
            );

            let sampler = Sampler::display_heads(&db).await?;
            let outcome = open_heads(&db, None, 1).await;
            let work = sampler.finish(&db).await?;
            let heads = outcome?;
            assert_eq!(
                (
                    work.statements,
                    work.candidates,
                    work.member_rows,
                    work.reference_rows
                ),
                (1, 1, 0, 0)
            );
            assert_eq!(
                (
                    work.denied_reads,
                    work.payload_column_authorizations,
                    work.fullscan_steps
                ),
                (0, 0, 0)
            );
            let live = heads
                .into_iter()
                .map(|header| LiveDisplayBlock {
                    has_unfinished_members: false,
                    thinking_summary: None,
                    id: header.id,
                    block_order: header.block_order,
                    source: Some(header.source),
                    body: header.body,
                    state: if header.sealed {
                        pl_protocol::DisplayBlockState::Sealed
                    } else {
                        pl_protocol::DisplayBlockState::Open
                    },
                })
                .collect::<Vec<_>>();
            assert_eq!(live.len(), 1);
            let open_vm = work.vm_steps;
            report(
                "open_heads",
                history,
                members,
                serde_json::to_vec(&live)?.len(),
                &work,
            );

            let sampler = Sampler::display_members(&db).await?;
            let outcome = member_page(&db, "history-20", None, 20).await;
            let work = sampler.finish(&db).await?;
            let page = outcome?;
            assert_eq!(
                (
                    work.statements,
                    work.candidates,
                    work.member_rows,
                    work.reference_rows
                ),
                (2, 0, 20, 1)
            );
            assert_eq!(
                (
                    work.denied_reads,
                    work.payload_column_authorizations,
                    work.fullscan_steps
                ),
                (0, 0, 0)
            );
            let page = page
                .into_iter()
                .map(|member| member.head)
                .collect::<Vec<DisplayMemberHead>>();
            assert_eq!(page.len(), 20);
            assert!(page.iter().all(|member| !matches!(
                member.record.atom.payload,
                Some(PayloadData::Inline { .. })
            )));
            report(
                "member_page",
                history,
                members,
                serde_json::to_vec(&page)?.len(),
                &work,
            );
            let measured = [history_vm, open_vm, work.vm_steps];
            if let Some(baseline) = baseline {
                for (actual, initial) in measured.into_iter().zip(baseline) {
                    assert!(
                        actual <= initial + 128,
                        "VM work grew with unselected history/members: {measured:?} vs {baseline:?}"
                    );
                }
            } else {
                baseline = Some(measured);
            }
        }
        db.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn v364_hundred_thousand_terminal_rows_commit_and_release_before_any_boundary()
    -> Result<()> {
        let (_dir, db) =
            crate::studio::storage::history::schema::work_snapshots::tests::fixture().await?;
        crate::studio::storage::history::schema::work_snapshots::initialize(&db).await?;

        let database: String = db
            .query_one_raw(statement(
                "SELECT database_id FROM history_meta WHERE id=1",
                vec![],
            ))
            .await?
            .unwrap()
            .try_get("", "database_id")?;
        let mut owner = PresentationState::default();
        owner.bind(&database)?;
        let mut tail_id = None;
        let mut last = None;
        for batch in 0..400u64 {
            let effect = batch + 1;
            let mut facts = Vec::new();
            for offset in 0..250u32 {
                let index = batch * 250 + u64::from(offset) + 1;
                let mut atom: pl_protocol::ChatAtom = serde_json::from_slice(
                    &super::super::tests::metadata(&format!("long-tail-{index}")),
                )?;
                atom.kind = ChatAtomKind::ToolCall;
                atom.tool = Some(pl_protocol::ChatToolIdentity {
                    call_id: format!("call-{index}"),
                    name: "exec".into(),
                });
                atom.source = if index % 2 == 0 {
                    ChatSourceId::BackgroundResult {
                        message_id: format!("result-{index}"),
                    }
                } else {
                    ChatSourceId::ForegroundTurn {
                        turn_id: "long-tail".into(),
                    }
                };
                atom.delivery = if index % 2 == 0 {
                    ChatDeliveryKind::Independent
                } else {
                    ChatDeliveryKind::Foreground
                };
                atom.completion_item_id = None;
                atom.completion_seq = None;
                atom.contents.clear();
                atom.payload = None;
                atom.lifecycle = ChatAtomLifecycle::Terminal {
                    started: None,
                    ended: Some(ChatFactPosition {
                        effect_seq: effect,
                        suborder: offset,
                    }),
                    outcome: ChatTerminalOutcome::Cancelled,
                };
                facts.push(atom);
            }
            let measured = matches!(batch, 0 | 39 | 399);
            if measured {
                owner.begin_cost_observation();
            }
            let delta = owner.prepare(effect, effect as i64, &facts, &[], &[])?;
            assert_eq!(delta.blocks.len(), 1);
            assert_eq!(delta.members.len(), 250);
            let id = &delta.blocks[0].header.id;
            assert!(tail_id.as_ref().is_none_or(|previous| previous == id));
            tail_id = Some(id.clone());
            assert!(!delta.blocks[0].header.sealed);
            assert_eq!(delta.published_through, 0);
            let tx = db.begin().await?;
            apply(&tx, &delta).await?;
            tx.execute_raw(statement(
                "UPDATE history_meta SET applied_write_seq=? WHERE id=1",
                vec![integer(effect)?.into()],
            ))
            .await?;
            tx.commit().await?;
            owner.confirm(effect);
            assert_eq!(owner.resident_member_count(), 0);
            if measured {
                let visits = owner.finish_cost_observation();
                assert_eq!(visits.members.keys.len(), 250);
                assert_eq!(visits.heads.keys.len(), 1);
                assert!(
                    visits
                        .members
                        .keys
                        .iter()
                        .all(|(_, position)| *position > batch * 250 && *position <= effect * 250)
                );
                eprintln!(
                    "TAIL_COMMIT_COST {}",
                    serde_json::json!({
                        "durable_members": effect * 250, "resident_members": owner.resident_member_count(),
                        "retained_bytes": owner.retained_bytes(), "member_reads": visits.members.reads,
                        "member_writes": visits.members.writes, "unique_members": visits.members.keys.len(),
                        "unique_heads": visits.heads.keys.len(), "head_reads": visits.heads.reads,
                        "head_writes": visits.heads.writes,
                    })
                );
            }
            last = facts.pop();
        }
        let duplicate = last.unwrap();
        let duplicate_delta =
            owner.prepare(401, 1_000_000, std::slice::from_ref(&duplicate), &[], &[])?;
        assert!(
            duplicate_delta.members.is_empty(),
            "released terminal replay must not create a row"
        );
        assert!(duplicate_delta.blocks.is_empty());
        let tx = db.begin().await?;
        apply(&tx, &duplicate_delta).await?;
        tx.execute_unprepared("UPDATE history_meta SET applied_write_seq=401 WHERE id=1")
            .await?;
        tx.commit().await?;
        owner.confirm(401);
        let recovery = recovery(&db).await?;
        assert_eq!(recovery.open.len(), 1);
        assert!(recovery.unfinished.is_empty());
        assert_eq!(recovery.open[0].next_member, 100_000);
        let mut cold = PresentationState::default();
        cold.restore(
            &database,
            recovery.published,
            recovery.last_order,
            recovery.effect,
            recovery.open,
            recovery.unfinished,
        )?;
        assert_eq!(cold.resident_member_count(), 0);
        assert!(cold.retained_bytes() < 4096);
        let id = tail_id.unwrap();
        let sampler = Sampler::display_heads(&db).await?;
        let heads = open_heads(&db, None, 1).await;
        let work = sampler.finish(&db).await?;
        let heads = heads?;
        assert_eq!(heads[0].id, id);
        assert_eq!(
            (
                work.candidates,
                work.member_rows,
                work.fullscan_steps,
                work.denied_reads
            ),
            (1, 0, 0, 0)
        );
        report(
            "long_open_tail_head",
            0,
            100_000,
            serde_json::to_vec(&heads)?.len(),
            &work,
        );
        let sampler = Sampler::display_members(&db).await?;
        let page = member_page(&db, &id, None, 2).await;
        let work = sampler.finish(&db).await?;
        let page = page?;
        assert_eq!(
            page.iter().map(|m| m.head.member_order).collect::<Vec<_>>(),
            [99_999, 100_000]
        );
        assert_eq!(
            (work.member_rows, work.fullscan_steps, work.denied_reads),
            (2, 0, 0)
        );
        report(
            "long_open_tail_members",
            0,
            100_000,
            serde_json::to_vec(&page)?.len(),
            &work,
        );
        let mut next = duplicate;
        next.id = "after-cold".into();
        next.source = ChatSourceId::BackgroundResult {
            message_id: "after-cold".into(),
        };
        next.tool = Some(pl_protocol::ChatToolIdentity {
            call_id: "after-cold".into(),
            name: "exec".into(),
        });
        next.lifecycle = ChatAtomLifecycle::Terminal {
            started: None,
            ended: Some(ChatFactPosition {
                effect_seq: 402,
                suborder: 0,
            }),
            outcome: ChatTerminalOutcome::Cancelled,
        };
        let delta = cold.prepare(402, 2_000_000, &[next], &[], &[])?;
        assert_eq!(delta.blocks[0].header.id, id);
        assert_eq!(delta.members[0].head.member_order, 100_001);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::studio::thread_projection::presentation::PresentationState;

    #[tokio::test]
    async fn observation_chunks_rollback_and_replay_with_the_original_display_transaction()
    -> Result<()> {
        use pl_core::{
            chat::{ChatContent, ChatContentKey, ContentData, ContentDescriptor},
            model::ContentBlock,
        };
        use pl_protocol::*;
        let (_dir, db) = super::super::super::schema::work_snapshots::tests::fixture().await?;
        crate::studio::storage::history::schema::work_snapshots::initialize(&db).await?;

        let database: String = db
            .query_one_raw(statement(
                "SELECT database_id FROM history_meta WHERE id=1",
                vec![],
            ))
            .await?
            .unwrap()
            .try_get("", "database_id")?;
        let mut owner = PresentationState::default();
        owner.bind(&database)?;
        let mut atom: ChatAtom =
            serde_json::from_slice(&super::super::tests::metadata("active-cut"))?;
        atom.kind = ChatAtomKind::ToolCall;
        atom.source = ChatSourceId::ForegroundTurn {
            turn_id: "turn".into(),
        };
        atom.delivery = ChatDeliveryKind::Foreground;
        atom.completion_item_id = None;
        atom.finished_at = None;
        atom.lifecycle = ChatAtomLifecycle::Active {
            started: Some(ChatFactPosition {
                effect_seq: 1,
                suborder: 0,
            }),
            status: ChatActiveStatus::Running,
        };
        let item_owner = ContentOwner::Item {
            item_id: atom.id.clone(),
        };
        atom.contents = vec![ChatAtomContent {
            role: ChatContentRole::ToolOutput,
            reference: ContentRef {
                database_id: database.clone(),
                target: ContentTarget::Body {
                    owner: item_owner.clone(),
                    key: "tool.result".into(),
                },
            },
        }];
        let content = Arc::new(ChatContent {
            descriptor: ContentDescriptor {
                key: ChatContentKey {
                    owner: crate::studio::conversation_identity::content_owner_key(&item_owner)?,
                    key: "tool.result".into(),
                },
                byte_length: 6,
                generation: 1,
                media_type: None,
            },
            data: ContentData::text(ContentBlock::from_text("prefix")),
        });
        let begin = owner.prepare(1, 10, &[atom.clone()], &[], &[])?;
        let tx = db.begin().await?;
        apply(&tx, &begin).await?;
        tx.execute_unprepared("UPDATE history_meta SET applied_write_seq=1")
            .await?;
        tx.commit().await?;
        let mut body = atom.clone();
        body.id = "new-body".into();
        body.kind = ChatAtomKind::Text;
        body.content_present = Some(true);
        body.contents.clear();
        body.lifecycle = ChatAtomLifecycle::Active {
            started: Some(ChatFactPosition {
                effect_seq: 2,
                suborder: 0,
            }),
            status: ChatActiveStatus::Running,
        };
        let cut = owner.prepare_capturing(2, 20, &[body], &[], &[], |_| {
            Ok(
                crate::studio::thread_projection::presentation::ObservationInput::for_test(
                    atom.clone(),
                    vec![content.clone()],
                ),
            )
        })?;
        assert_eq!(
            cut.contents.len(),
            2,
            "body and canonical observation payload"
        );
        db.execute_unprepared("CREATE TRIGGER reject_cut BEFORE INSERT ON conversation_contents BEGIN SELECT RAISE(ABORT,'chunk failure'); END").await?;
        let tx = db.begin().await?;
        assert!(apply(&tx, &cut).await.is_err());
        tx.rollback().await?;
        assert_eq!(watermarks(&db).await?, (0, 1));
        assert!(history_heads(&db, 1, None, 8).await?.is_empty());
        db.execute_unprepared("DROP TRIGGER reject_cut").await?;
        let tx = db.begin().await?;
        apply(&tx, &cut).await?;
        tx.execute_unprepared("UPDATE history_meta SET applied_write_seq=2")
            .await?;
        tx.commit().await?;
        verify(&db, &cut).await?;
        // A lost acknowledgement repeats only the original frozen material.
        apply(&db, &cut).await?;
        let body_index = cut
            .contents
            .iter()
            .position(|content| content.descriptor.key.key == "tool.result")
            .context("frozen tool result")?;
        let key = &cut.contents[body_index].descriptor.key;
        assert_eq!(
            super::super::content::read_body_bytes(&db, key, 0, 6).await?,
            b"prefix"
        );
        let payload = cut
            .contents
            .iter()
            .find(|content| content.descriptor.key.key == "display.payload")
            .context("canonical observation payload")?;
        let bytes = super::super::content::read_body_bytes(
            &db,
            &payload.descriptor.key,
            0,
            payload.descriptor.byte_length as usize,
        )
        .await?;
        let envelope: serde_json::Value = serde_json::from_slice(&bytes)?;
        assert_eq!(envelope["contract"], "anywork.chat/1");
        assert_eq!(envelope["bodies"][0]["key"], "tool.result");
        let reference: ContentRef =
            serde_json::from_value(envelope["bodies"][0]["reference"].clone())?;
        assert_eq!(
            reference,
            cut.members[0].head.record.atom.contents[0].reference
        );
        let mut conflict = cut.as_ref().clone();
        conflict.contents[body_index] = Arc::new(ChatContent {
            descriptor: cut.contents[body_index].descriptor.clone(),
            data: ContentData::text(ContentBlock::from_text("OTHER!")),
        });
        assert!(
            verify(&db, &conflict).await.is_err(),
            "same length/generation cannot prove an observation"
        );
        let mut changed = cut.as_ref().clone();
        changed.effect_seq = 3;
        changed.blocks.clear();
        changed.contents.clear();
        let member = Arc::make_mut(&mut changed.members[0]);
        member.head.record.atom.wait = None;
        assert!(
            apply(&db, &changed).await.is_err(),
            "sealed block rejects even nonterminal updates"
        );
        assert_eq!(
            super::super::content::read_body_bytes(&db, key, 0, 6).await?,
            b"prefix"
        );
        Ok(())
    }

    #[tokio::test]
    async fn visible_text_final_empty_is_atomic_and_keeps_the_frozen_boundary_on_cold_read()
    -> Result<()> {
        use pl_protocol::{
            ChatAtomKind, ChatAtomLifecycle, ChatFactPosition, ChatSourceId, ChatTerminalOutcome,
        };
        let (_dir, db) = super::super::super::schema::work_snapshots::tests::fixture().await?;
        crate::studio::storage::history::schema::work_snapshots::initialize(&db).await?;

        let database: String = db
            .query_one_raw(statement(
                "SELECT database_id FROM history_meta WHERE id=1",
                vec![],
            ))
            .await?
            .unwrap()
            .try_get("", "database_id")?;
        let mut owner = PresentationState::default();
        owner.bind(&database)?;
        let mut started: pl_protocol::ChatAtom =
            serde_json::from_slice(&super::super::tests::metadata("empty-text"))?;
        started.kind = ChatAtomKind::Text;
        started.source = ChatSourceId::ForegroundTurn {
            turn_id: "turn".into(),
        };
        started.completion_item_id = None;
        started.content_present = Some(true);
        started.finished_at = None;
        started.lifecycle = ChatAtomLifecycle::Active {
            started: Some(ChatFactPosition {
                effect_seq: 1,
                suborder: 0,
            }),
            status: pl_protocol::ChatActiveStatus::Running,
        };
        let begin = owner.prepare(1, 10, &[started.clone()], &[], &[])?;
        let tx = db.begin().await?;
        apply(&tx, &begin).await?;
        tx.execute_unprepared("UPDATE history_meta SET applied_write_seq=1")
            .await?;
        tx.commit().await?;
        let block_id = begin.blocks[0].header.id.clone();
        let mut ended = started;
        ended.completion_item_id = Some("empty-text".into());
        ended.content_present = Some(false);
        ended.finished_at = Some(20);
        ended.lifecycle = ChatAtomLifecycle::Terminal {
            started: Some(ChatFactPosition {
                effect_seq: 1,
                suborder: 0,
            }),
            ended: Some(ChatFactPosition {
                effect_seq: 2,
                suborder: 0,
            }),
            outcome: ChatTerminalOutcome::Completed,
        };
        let mut draft = pl_core::chat::ChatDraft::new(
            "empty-text",
            "conversation",
            Arc::<[u8]>::from(b"{}".as_slice()),
        );
        draft.metadata = serde_json::to_vec(&ended)?.into();
        draft.read_hint =
            crate::studio::runtime::chat_item::native_read_hint_v1("conversation", &ended);
        let original = Arc::new(ChatItem::complete(draft, 1, None));
        let finish = owner.prepare(2, 20, &[ended], &[], std::slice::from_ref(&original))?;
        assert!(finish.remove_empty.is_empty());
        assert_eq!(finish.published_through, 1);
        db.execute_unprepared(
            "CREATE TRIGGER reject_empty_finish BEFORE UPDATE ON conversation_display_blocks
        BEGIN SELECT RAISE(ABORT,'final empty update rejection'); END;",
        )
        .await?;
        let tx = db.begin().await?;
        super::super::append_records(&tx, [original.as_ref()], true).await?;
        assert!(apply(&tx, &finish).await.is_err());
        tx.rollback().await?;
        assert!(super::super::read_item(&db, "empty-text").await?.is_none());
        assert_eq!(member_page(&db, &block_id, None, 8).await?.len(), 1);
        assert_eq!(recovery(&db).await?.open.len(), 1);
        db.execute_unprepared("DROP TRIGGER reject_empty_finish")
            .await?;
        let tx = db.begin().await?;
        super::super::append_records(&tx, [original.as_ref()], true).await?;
        apply(&tx, &finish).await?;
        tx.execute_unprepared("UPDATE history_meta SET applied_write_seq=2")
            .await?;
        tx.commit().await?;
        verify(&db, &finish).await?;
        assert!(super::super::read_item(&db, "empty-text").await?.is_some());
        let heads = history_heads(&db, 1, None, 8).await?;
        assert_eq!(heads.len(), 1);
        assert_eq!(heads[0].id, block_id);
        assert!(matches!(
            heads[0].body,
            DisplayBlockBody::Single {
                visibility: pl_protocol::SingleVisibility::FinalEmptyAfterContent,
                ..
            }
        ));
        assert!(recovery(&db).await?.open.is_empty());
        assert_eq!(member_page(&db, &block_id, None, 8).await?.len(), 1);
        Ok(())
    }

    #[tokio::test]
    async fn display_delta_rolls_back_with_original_completion_and_exact_replay_has_a_receipt()
    -> Result<()> {
        use sea_orm::TransactionTrait;
        let (_dir, db) = super::super::super::schema::work_snapshots::tests::fixture().await?;
        crate::studio::storage::history::schema::work_snapshots::initialize(&db).await?;

        let database: String = db
            .query_one_raw(statement(
                "SELECT database_id FROM history_meta WHERE id=1",
                vec![],
            ))
            .await?
            .unwrap()
            .try_get("", "database_id")?;
        let mut owner = PresentationState::default();
        owner.bind(&database)?;
        let mut atom: pl_protocol::ChatAtom =
            serde_json::from_slice(&super::super::tests::metadata("original"))?;
        atom.kind = pl_protocol::ChatAtomKind::ToolCall;
        atom.source = pl_protocol::ChatSourceId::ForegroundTurn {
            turn_id: "turn".into(),
        };
        atom.delivery = pl_protocol::ChatDeliveryKind::Foreground;
        atom.lifecycle = pl_protocol::ChatAtomLifecycle::Terminal {
            started: None,
            ended: Some(pl_protocol::ChatFactPosition {
                effect_seq: 1,
                suborder: 0,
            }),
            outcome: pl_protocol::ChatTerminalOutcome::Completed,
        };
        let mut draft = pl_core::chat::ChatDraft::new(
            "original",
            "conversation",
            Arc::<[u8]>::from(b"saved original".as_slice()),
        );
        draft.metadata = serde_json::to_vec(&atom)?.into();
        draft.read_hint =
            crate::studio::runtime::chat_item::native_read_hint_v1("conversation", &atom);
        let item = Arc::new(ChatItem::complete(
            draft,
            1,
            Some(pl_core::chat::ChatRunPosition {
                start_seq: 1,
                ordinal: 1,
            }),
        ));
        let ended = pl_protocol::ChatSourceState {
            source: atom.source.clone(),
            lifecycle: pl_protocol::ChatSourceLifecycle::Ended {
                outcome: pl_protocol::ChatTerminalOutcome::Completed,
            },
            started: None,
            ended: Some(pl_protocol::ChatFactPosition {
                effect_seq: 1,
                suborder: 1,
            }),
        };
        let delta = owner.prepare(1, 10, &[atom], &[ended], std::slice::from_ref(&item))?;
        assert!(
            matches!(&delta.blocks[0].header.body, DisplayBlockBody::Work { timing: summary, .. }
        if summary.started_at == Some(10) && summary.finished_at.is_none())
        );
        db.execute_unprepared("CREATE TRIGGER reject_display BEFORE INSERT ON conversation_display_members BEGIN SELECT RAISE(ABORT,'display rejection'); END;").await?;
        let tx = db.begin().await?;
        super::super::append_records(&tx, [item.as_ref()], true).await?;
        assert!(apply(&tx, &delta).await.is_err());
        tx.rollback().await?;
        assert!(super::super::read_item(&db, "original").await?.is_none());
        assert!(history_heads(&db, 1, None, 8).await?.is_empty());
        assert_eq!(watermarks(&db).await?, (0, 0));
        db.execute_unprepared("DROP TRIGGER reject_display").await?;
        let tx = db.begin().await?;
        super::super::append_records(&tx, [item.as_ref()], true).await?;
        apply(&tx, &delta).await?;
        tx.execute_unprepared("UPDATE history_meta SET applied_write_seq=1")
            .await?;
        tx.commit().await?;
        verify(&db, &delta).await?; // Lost local acknowledgement: no rewrite/recalculation.
        apply(&db, &delta).await?;
        let heads = open_heads(&db, None, 8).await?;
        assert_eq!(heads[0].body, delta.blocks[0].header.body);
        let mut wrong_time = delta.as_ref().clone();
        let header = Arc::make_mut(&mut wrong_time.blocks[0].header);
        let DisplayBlockBody::Work {
            timing: summary, ..
        } = &mut header.body
        else {
            unreachable!("created Work above");
        };
        summary.started_at = Some(11);
        summary.finished_at = Some(12);
        assert!(verify(&db, &wrong_time).await.is_err());
        let mut contradictory = delta.as_ref().clone();
        contradictory.published_through = 1;
        assert!(verify(&db, &contradictory).await.is_err());
        assert_eq!(watermarks(&db).await?, (0, 1));
        // Snapshot reads are independent of original payload tables.
        db.execute_unprepared("ALTER TABLE conversation_items RENAME TO originals_not_available")
            .await?;
        assert_eq!(open_heads(&db, None, 8).await?.len(), 1);
        assert_eq!(
            member_page(&db, &delta.blocks[0].header.id, None, 8)
                .await?
                .len(),
            1
        );
        assert_eq!(recovery(&db).await?.open.len(), 1);
        Ok(())
    }
}
