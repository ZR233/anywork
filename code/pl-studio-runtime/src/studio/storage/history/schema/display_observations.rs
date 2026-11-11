//! Schema 19 -> 20: explicit display cuts, without inventing a missing boundary observation.
use super::*;
use crate::studio::thread_projection::presentation::{
    DisplayHeader, DisplayMemberWrite, display_member_key, member_key, record,
};
use pl_protocol::{
    ChatAtom, ChatAtomLifecycle, ChatFactPosition, DisplayBlockBody, DisplayContentSource,
    DisplayMemberHead, WorkSummary,
};

pub(super) struct DisplayObservations;
impl MigrationName for DisplayObservations {
    fn name(&self) -> &str {
        DISPLAY_OBSERVATIONS
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for DisplayObservations {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        upgrade(manager.get_connection()).await.map_err(conversion)
    }
}

fn reliable(at: Option<ChatFactPosition>) -> Option<ChatFactPosition> {
    at.filter(|at| at.effect_seq > 0)
}

async fn phase(db: &impl ConnectionTrait, id: &str, name: &str) -> Result<Option<ChatAtom>> {
    db.query_one_raw(statement(
        "SELECT effect_seq,suborder,metadata FROM conversation_atom_facts WHERE atom_id=? AND phase=?",
        vec![id.into(), name.into()],
    ))
    .await?
    .map(|row| {
        let atom: ChatAtom = serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
        ensure!(atom.id == id, "legacy phase atom identity differs");
        let at = match (&atom.lifecycle, name) {
            (ChatAtomLifecycle::Active { started, .. }, "start") => *started,
            (ChatAtomLifecycle::Terminal { ended, .. }, "terminal") => *ended,
            _ => anyhow::bail!("legacy phase lifecycle differs"),
        };
        if let Some(at) = reliable(at) {
            ensure!(integer(at.effect_seq)? == row.try_get::<i64>("","effect_seq")?
                && i64::from(at.suborder) == row.try_get::<i64>("","suborder")?,
                "legacy phase position differs from its indexed evidence");
        }
        Ok(atom)
    })
    .transpose()
}

async fn original_terminal(db: &impl ConnectionTrait, terminal: &ChatAtom) -> Result<ChatAtom> {
    let Some(id) = &terminal.completion_item_id else {
        ensure!(
            terminal.contents.is_empty(),
            "unreceipted terminal has no provable content cut"
        );
        return Ok(terminal.clone());
    };
    let row = db.query_one_raw(statement(
        "SELECT i.seq,i.metadata,length(i.payload) AS n,m.database_id FROM conversation_items i CROSS JOIN history_meta m WHERE i.item_id=? AND m.id=1",
        vec![id.clone().into()],
    )).await?.context("display original terminal is missing")?;
    let mut atom: ChatAtom = serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
    ensure!(
        atom.id == terminal.id
            && atom.source == terminal.source
            && atom.lifecycle == terminal.lifecycle,
        "display original terminal provenance conflicts"
    );
    atom.completion_item_id = Some(id.clone());
    atom.completion_seq = Some(u64::try_from(row.try_get::<i64>("", "seq")?)?);
    atom.payload = Some(pl_protocol::PayloadData::Deferred {
        reference: pl_protocol::ContentRef {
            database_id: row.try_get("", "database_id")?,
            target: pl_protocol::ContentTarget::ItemPayload {
                item_id: id.clone(),
            },
        },
        byte_length: u64::try_from(row.try_get::<i64>("", "n")?)?,
    });
    Ok(atom)
}

async fn boundary_time(
    db: &impl ConnectionTrait,
    at: Option<ChatFactPosition>,
) -> Result<Option<i64>> {
    let Some(at) = reliable(at) else {
        return Ok(None);
    };
    let rows = db
        .query_all_raw(statement(
            "SELECT metadata FROM conversation_atom_facts WHERE effect_seq=? AND suborder=?",
            vec![
                integer(at.effect_seq)?.into(),
                i64::from(at.suborder).into(),
            ],
        ))
        .await?;
    let mut time = None;
    for row in rows {
        let atom: ChatAtom = serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
        let candidate = match atom.lifecycle {
            ChatAtomLifecycle::Active { started, .. } if reliable(started) == Some(at) => {
                atom.started_at
            }
            ChatAtomLifecycle::Terminal { ended, .. } if reliable(ended) == Some(at) => {
                atom.finished_at
            }
            _ => None,
        };
        if let Some(candidate) = candidate {
            ensure!(
                time.is_none_or(|old| old == candidate),
                "display boundary time conflicts"
            );
            time = Some(candidate);
        }
    }
    Ok(time)
}

fn converted_summary(old: display_snapshots::legacy::WorkSummary) -> Result<Box<WorkSummary>> {
    let mut value = serde_json::to_value(old)?;
    value
        .as_object_mut()
        .context("legacy summary is not an object")?
        .insert("unavailable".into(), 0.into());
    Ok(Box::new(serde_json::from_value(value)?))
}

pub(in crate::studio::storage::history) async fn upgrade(db: &impl ConnectionTrait) -> Result<()> {
    display_snapshots::validate(db).await?;
    db.execute_unprepared(
        "ALTER TABLE conversation_display_blocks ADD COLUMN sealed INTEGER NOT NULL DEFAULT 0 CHECK(sealed IN (0,1));
         ALTER TABLE conversation_display_members ADD COLUMN association_key TEXT NOT NULL DEFAULT '';"
    ).await?;
    let mut after = 0;
    let mut late = Vec::new();
    let mut unpublished = Vec::new();
    loop {
        let rows = db.query_all_raw(statement(
            "SELECT block_id,block_order,header FROM conversation_display_blocks WHERE block_order>? ORDER BY block_order LIMIT 128",
            vec![integer(after)?.into()],
        )).await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let old: display_snapshots::legacy::DisplayHeader =
                serde_json::from_slice(&row.try_get::<Vec<u8>>("", "header")?)?;
            ensure!(
                old.version == 1 && old.id == row.try_get::<String>("", "block_id")?,
                "legacy display identity differs"
            );
            after = old.block_order;
            let closing = old.history_pos.is_none()
                && old.boundary.is_some()
                && matches!(
                    old.body,
                    display_snapshots::legacy::DisplayBlockBody::Work { .. }
                );
            let captured_at = if closing {
                boundary_time(db, old.boundary).await?
            } else {
                None
            };
            let body = match old.body {
                display_snapshots::legacy::DisplayBlockBody::Work { summary, members } => {
                    let mut summary = converted_summary(*summary)?;
                    if closing {
                        // Neither a later summary nor initial Running proves the boundary cut.
                        summary.terminal = 0;
                        summary.running = 0;
                        summary.waiting = 0;
                        summary.failed = 0;
                        summary.cancelled = 0;
                        summary.transferred = 0;
                        summary.unavailable = 0;
                        summary.finished_at = None;
                        summary.duration_ms = None;
                        summary.thinking_summary = None;
                        summary.thinking_content = None;
                        summary.elapsed_ms = summary
                            .created_at
                            .zip(captured_at)
                            .and_then(|(start, end)| end.checked_sub(start))
                            .and_then(|seconds| u64::try_from(seconds).ok())
                            .and_then(|seconds| seconds.checked_mul(1000));
                    }
                    DisplayBlockBody::Work { summary, members }
                }
                display_snapshots::legacy::DisplayBlockBody::Single {
                    atom,
                    completion_id,
                } => {
                    ensure!(
                        atom.completion_item_id == completion_id,
                        "legacy Single completion differs"
                    );
                    let start =
                        phase(db, &atom.id, "start")
                            .await?
                            .and_then(|atom| match atom.lifecycle {
                                ChatAtomLifecycle::Active { started, .. } => reliable(started),
                                _ => None,
                            });
                    DisplayBlockBody::Single {
                        record: Box::new(record(*atom, start)),
                    }
                }
            };
            let mut header = DisplayHeader {
                version: 2,
                legacy: old.legacy,
                id: old.id,
                source: old.source,
                block_order: old.block_order,
                history_pos: old.history_pos,
                boundary: old.boundary,
                sealed: old.legacy || old.history_pos.is_some() || old.boundary.is_some(),
                unfinished: if closing { 0 } else { old.unfinished },
                next_member: old.next_member,
                revision: old.revision,
                skip_display: old.skip_display,
                active_since: old.active_since,
                duration_known: old.duration_known,
                body,
            };
            let mut before = 0;
            let mut first_fact = None;
            loop {
                let members = db.query_all_raw(statement(
                    "SELECT metadata FROM conversation_display_members WHERE block_id=? AND member_order>? ORDER BY member_order LIMIT 128",
                    vec![header.id.clone().into(), integer(before)?.into()],
                )).await?;
                if members.is_empty() {
                    break;
                }
                for row in members {
                    let old: display_snapshots::legacy::DisplayMemberWrite =
                        serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
                    before = old.head.member_order;
                    let mut atom = old.head.atom;
                    ensure!(
                        old.block_id == header.id
                            && old.head.completion_id == atom.completion_item_id,
                        "legacy display member ownership differs"
                    );
                    let start = phase(db, &atom.id, "start").await?;
                    let start_fact = start.as_ref().and_then(|atom| match atom.lifecycle {
                        ChatAtomLifecycle::Active { started, .. } => reliable(started),
                        _ => None,
                    });
                    let end = if closing {
                        phase(db, &atom.id, "terminal").await?
                    } else {
                        None
                    };
                    let end_fact = end.as_ref().and_then(|atom| match atom.lifecycle {
                        ChatAtomLifecycle::Terminal { ended, .. } => reliable(ended),
                        _ => None,
                    });
                    ensure!(
                        start
                            .iter()
                            .chain(end.iter())
                            .all(|fact| fact.source == header.source && fact.kind == atom.kind),
                        "legacy display phase source or responsibility conflicts"
                    );
                    let created = start_fact.or_else(|| match atom.lifecycle {
                        ChatAtomLifecycle::Terminal { ended, .. } => {
                            reliable(ended).filter(|end| {
                                !closing
                                    || reliable(header.boundary)
                                        .is_some_and(|boundary| *end <= boundary)
                            })
                        }
                        _ => None,
                    });
                    if let Some(at) = created {
                        first_fact =
                            Some(first_fact.map_or(at, |old: ChatFactPosition| old.min(at)));
                    }
                    let mut content_source = None;
                    let mut accepted_end = None;
                    if closing {
                        if let Some(end_atom) = end.as_ref().filter(|_| {
                            end_fact
                                .zip(reliable(header.boundary))
                                .is_some_and(|(end, boundary)| end <= boundary)
                        }) {
                            // The indexed canonical terminal proves this original was complete at cut.
                            atom = original_terminal(db, end_atom).await?;
                            content_source = Some(record(atom.clone(), start_fact).content_source);
                            accepted_end = end_fact;
                        } else {
                            if end_fact
                                .zip(reliable(header.boundary))
                                .is_some_and(|(end, boundary)| end > boundary)
                            {
                                // Preserve the immutable completion, but never backfill the old cut.
                                late.push((
                                    header.id.clone(),
                                    end_fact.context("terminal position")?,
                                    original_terminal(
                                        db,
                                        end.as_ref().context("late terminal fact is missing")?,
                                    )
                                    .await?,
                                ));
                            }
                            let start_atom = start.as_ref();
                            if let Some(start) = start_atom {
                                atom = start.clone();
                            }
                            atom.completion_item_id = None;
                            atom.completion_seq = None;
                            atom.finished_at = None;
                            atom.payload = None;
                            atom.contents.clear();
                            atom.wait = None;
                            atom.source_state = None;
                            atom.content_present = None;
                            atom.lifecycle = ChatAtomLifecycle::Active {
                                started: start_fact,
                                status: pl_protocol::ChatActiveStatus::Running,
                            };
                            if start_atom.is_none() {
                                atom.started_at = None;
                            }
                            content_source = Some(DisplayContentSource::FrozenObservation {
                                captured_at,
                                available: false,
                            });
                        }
                    }
                    let mut record = record(atom, start_fact);
                    if let Some(source) = content_source {
                        record.content_source = source;
                        record.end_fact = accepted_end;
                    }
                    let terminal =
                        matches!(record.atom.lifecycle, ChatAtomLifecycle::Terminal { .. });
                    if closing {
                        if let DisplayBlockBody::Work { summary, .. } = &mut header.body {
                            if terminal {
                                summary.terminal += 1;
                                if let ChatAtomLifecycle::Terminal { outcome, .. } =
                                    record.atom.lifecycle
                                {
                                    match outcome {
                                        pl_protocol::ChatTerminalOutcome::Failed => {
                                            summary.failed += 1
                                        }
                                        pl_protocol::ChatTerminalOutcome::Cancelled => {
                                            summary.cancelled += 1
                                        }
                                        pl_protocol::ChatTerminalOutcome::Transferred => {
                                            summary.transferred += 1
                                        }
                                        pl_protocol::ChatTerminalOutcome::Completed => {}
                                    }
                                }
                            } else {
                                summary.unavailable += 1;
                                header.unfinished += 1;
                            }
                        }
                        header.revision = header
                            .revision
                            .checked_add(1)
                            .context("migration revision exhausted")?;
                    }
                    let member = DisplayMemberWrite {
                        block_id: header.id.clone(),
                        association_key: member_key(&record.atom)?,
                        terminal,
                        head: DisplayMemberHead {
                            member_key: old.head.member_key,
                            member_order: before,
                            record,
                        },
                    };
                    db.execute_raw(statement(
                        "UPDATE conversation_display_members SET terminal=?,completion_id=?,association_key=?,metadata=? WHERE block_id=? AND member_order=?",
                        vec![i64::from(terminal).into(), member.head.record.atom.completion_item_id.clone().into(),
                            member.association_key.clone().into(), serde_json::to_vec(&member)?.into(),
                            header.id.clone().into(), integer(before)?.into()],
                    )).await?;
                }
            }
            db.execute_raw(statement(
                "UPDATE conversation_display_blocks SET sealed=?,header=? WHERE block_id=?",
                vec![
                    i64::from(header.sealed).into(),
                    serde_json::to_vec(&header)?.into(),
                    header.id.clone().into(),
                ],
            ))
            .await?;
            if header.history_pos.is_none() {
                unpublished.push((header, first_fact));
            }
        }
    }
    migrate_late_ends(db, &mut unpublished, late).await?;
    db.execute_unprepared("UPDATE history_meta SET schema_version=20 WHERE id=1")
        .await?;
    validate(db).await
}

async fn migrate_late_ends(
    db: &impl ConnectionTrait,
    blocks: &mut Vec<(DisplayHeader, Option<ChatFactPosition>)>,
    mut late: Vec<(String, ChatFactPosition, ChatAtom)>,
) -> Result<()> {
    late.sort_by_key(|(_, at, _)| *at);
    let meta = db
        .query_one_raw(statement(
            "SELECT database_id,applied_write_seq FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .context("display migration identity missing")?;
    let database: String = meta.try_get("", "database_id")?;
    let effect: i64 = meta.try_get("", "applied_write_seq")?;
    let had_late = !late.is_empty();
    let mut added = Vec::new();
    for (parent, at, mut atom) in late {
        let parent_index = blocks
            .iter()
            .position(|(h, _)| h.id == parent)
            .context("late end lost its old block")?;
        let insertion = blocks
            .iter()
            .enumerate()
            .skip(parent_index + 1)
            .find(|(_, (_, first))| first.is_some_and(|first| first > at))
            .map_or(blocks.len(), |(index, _)| index);
        ensure!(
            blocks[parent_index + 1..insertion]
                .iter()
                .filter(|(h, _)| h.source == atom.source)
                .all(|(_, first)| first.is_some()),
            "late terminal cannot cross an unproved display creation position; source preserved"
        );
        let mut target = blocks[..insertion]
            .iter()
            .enumerate()
            .rev()
            .find(|(_, (h, _))| h.source == atom.source)
            .map(|(index, (h, first))| -> Result<Option<usize>> {
                if !matches!(h.body, DisplayBlockBody::Work { .. }) {
                    return Ok(None);
                }
                let first =
                    first.context("late terminal target lacks a reliable creation position")?;
                ensure!(first <= at, "late terminal precedes its candidate Work");
                let boundary = h
                    .boundary
                    .map(|at| {
                        reliable(Some(at))
                            .context("late terminal target lacks a reliable boundary position")
                    })
                    .transpose()?;
                // Migration may enrich a converted, unpublished sealed group: the
                // terminal belonged to it before its real boundary, not after it.
                Ok(boundary
                    .is_none_or(|boundary| at < boundary)
                    .then_some(index))
            })
            .transpose()?
            .flatten();
        if target.is_none()
            && let Some((index, (candidate, first))) = blocks
                .iter()
                .enumerate()
                .skip(insertion)
                .find(|(_, (h, _))| h.source == atom.source)
        {
            let first =
                first.context("late terminal cannot cross an unproved next display creation")?;
            if matches!(candidate.body, DisplayBlockBody::Work { .. }) && first > at {
                let boundary = candidate
                    .boundary
                    .map(|at| {
                        reliable(Some(at))
                            .context("late terminal next Work has an unproved boundary")
                    })
                    .transpose()?;
                if boundary.is_none_or(|boundary| at < boundary) {
                    // No real boundary separates the new earlier information from this
                    // existing Work. Preserve its ID, rather than creating an extra group.
                    target = Some(index);
                    let boundary_time = boundary_time(db, boundary).await?;
                    let (header, first) = &mut blocks[index];
                    *first = Some(at);
                    if let DisplayBlockBody::Work { summary, .. } = &mut header.body {
                        summary.created_at = atom.finished_at;
                        summary.elapsed_ms = summary
                            .created_at
                            .zip(boundary_time)
                            .and_then(|(start, end)| end.checked_sub(start))
                            .and_then(|seconds| u64::try_from(seconds).ok())
                            .and_then(|seconds| seconds.checked_mul(1000));
                    }
                }
            }
        }
        let index = if let Some(index) = target {
            index
        } else {
            let id = serde_json::to_string(&(
                "display-v2",
                &database,
                &atom.source,
                Some(at),
                member_key(&atom)?,
            ))?;
            let created_at = atom.finished_at;
            let next_boundary = blocks[insertion..]
                .iter()
                .find(|(h, _)| h.source == atom.source)
                .and_then(|(h, first)| match &h.body {
                    DisplayBlockBody::Single { record } => record.start_fact.or(record.end_fact),
                    DisplayBlockBody::Work { .. } => h.boundary.or(*first).filter(|_| h.sealed),
                });
            let elapsed_ms = created_at
                .zip(boundary_time(db, next_boundary).await?)
                .and_then(|(start, end)| end.checked_sub(start))
                .and_then(|seconds| u64::try_from(seconds).ok())
                .and_then(|seconds| seconds.checked_mul(1000));
            let header = DisplayHeader {
                version: 2,
                legacy: false,
                id: id.clone(),
                source: atom.source.clone(),
                block_order: 0,
                history_pos: None,
                boundary: next_boundary,
                sealed: next_boundary.is_some(),
                unfinished: 0,
                next_member: 0,
                revision: 0,
                skip_display: false,
                active_since: None,
                duration_known: false,
                body: DisplayBlockBody::Work {
                    summary: Box::new(WorkSummary {
                        created_at,
                        elapsed_ms: if next_boundary.is_some() {
                            elapsed_ms
                        } else {
                            created_at.map(|_| 0)
                        },
                        ..Default::default()
                    }),
                    members: pl_protocol::DisplayBlockRef {
                        database_id: database.clone(),
                        block_id: id.clone(),
                    },
                },
            };
            blocks.insert(insertion, (header, Some(at)));
            insertion
        };
        let header = &mut blocks[index].0;
        // Canonical original metadata may omit its transport payload reference.
        if let Some(id) = &atom.completion_item_id {
            let row = db
                .query_one_raw(statement(
                    "SELECT length(payload) AS n FROM conversation_items WHERE item_id=?",
                    vec![id.clone().into()],
                ))
                .await?
                .context("late display original is missing")?;
            atom.payload = Some(pl_protocol::PayloadData::Deferred {
                reference: pl_protocol::ContentRef {
                    database_id: database.clone(),
                    target: pl_protocol::ContentTarget::ItemPayload {
                        item_id: id.clone(),
                    },
                },
                byte_length: u64::try_from(row.try_get::<i64>("", "n")?)?,
            });
        }
        let member_order = insert_member_order(db, header, at).await?;
        header.next_member = header
            .next_member
            .checked_add(1)
            .context("display member order exhausted")?;
        header.revision = header
            .revision
            .checked_add(1)
            .context("display revision exhausted")?;
        let member = DisplayMemberWrite {
            block_id: header.id.clone(),
            association_key: member_key(&atom)?,
            terminal: true,
            head: DisplayMemberHead {
                member_key: display_member_key(&header.id, &atom)?,
                member_order,
                record: record(atom, None),
            },
        };
        if let DisplayBlockBody::Work { summary, .. } = &mut header.body {
            summary.total += 1;
            summary.terminal += 1;
            if let ChatAtomLifecycle::Terminal { outcome, .. } = member.head.record.atom.lifecycle {
                match outcome {
                    pl_protocol::ChatTerminalOutcome::Failed => summary.failed += 1,
                    pl_protocol::ChatTerminalOutcome::Cancelled => summary.cancelled += 1,
                    pl_protocol::ChatTerminalOutcome::Transferred => summary.transferred += 1,
                    pl_protocol::ChatTerminalOutcome::Completed => {}
                }
            }
        }
        // Insert after all new headers have their final ordering keys.
        added.push(member);
    }
    if had_late {
        let row = db
            .query_one_raw(statement(
                "SELECT coalesce(max(block_order),0) AS n FROM conversation_display_blocks",
                vec![],
            ))
            .await?
            .context("display order query failed")?;
        let mut order = u64::try_from(row.try_get::<i64>("", "n")?)?;
        for (header, _) in blocks.iter_mut() {
            order = order.checked_add(1).context("display order exhausted")?;
            header.block_order = order;
            db.execute_raw(statement(
                "INSERT INTO conversation_display_blocks(block_id,source_key,block_order,history_pos,sealed,updated_effect,header)
                 VALUES(?,?,?,NULL,?,?,?) ON CONFLICT(block_id) DO UPDATE SET block_order=excluded.block_order,header=excluded.header",
                vec![header.id.clone().into(),serde_json::to_string(&header.source)?.into(),integer(order)?.into(),
                    i64::from(header.sealed).into(),effect.into(),serde_json::to_vec(header)?.into()],
            )).await?;
        }
        for member in added {
            db.execute_raw(statement(
                "INSERT INTO conversation_display_members(block_id,member_order,member_key,association_key,terminal,completion_id,updated_effect,metadata) VALUES(?,?,?,?,1,?,?,?)",
                vec![member.block_id.clone().into(),integer(member.head.member_order)?.into(),member.head.member_key.clone().into(),
                    member.association_key.clone().into(),member.head.record.atom.completion_item_id.clone().into(),
                    effect.into(),serde_json::to_vec(&member)?.into()],
            )).await?;
        }
    }
    Ok(())
}

async fn insert_member_order(
    db: &impl ConnectionTrait,
    header: &DisplayHeader,
    at: ChatFactPosition,
) -> Result<u64> {
    let mut before = 0;
    let mut insertion = None;
    loop {
        let rows = db.query_all_raw(statement(
            "SELECT member_order,metadata FROM conversation_display_members WHERE block_id=? AND member_order>? ORDER BY member_order LIMIT 128",
            vec![header.id.clone().into(), integer(before)?.into()],
        )).await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            before = u64::try_from(row.try_get::<i64>("", "member_order")?)?;
            let member: DisplayMemberWrite =
                serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
            let first = reliable(
                member
                    .head
                    .record
                    .start_fact
                    .or(member.head.record.end_fact),
            )
            .context("late terminal target member has no reliable acceptance position")?;
            if first > at {
                insertion = Some(before);
                break;
            }
        }
        if insertion.is_some() {
            break;
        }
    }
    let Some(insertion) = insertion else {
        return header
            .next_member
            .checked_add(1)
            .context("display member order exhausted");
    };
    let mut upper = u64::MAX;
    loop {
        let rows = db.query_all_raw(statement(
            "SELECT member_order,metadata FROM conversation_display_members WHERE block_id=? AND member_order>=? AND member_order<? ORDER BY member_order DESC LIMIT 128",
            vec![header.id.clone().into(),integer(insertion)?.into(),integer(upper.min(i64::MAX as u64))?.into()],
        )).await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let old = u64::try_from(row.try_get::<i64>("", "member_order")?)?;
            upper = old;
            let mut member: DisplayMemberWrite =
                serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
            member.head.member_order = old
                .checked_add(1)
                .context("display member order exhausted")?;
            db.execute_raw(statement(
                "UPDATE conversation_display_members SET member_order=?,metadata=? WHERE block_id=? AND member_order=?",
                vec![integer(member.head.member_order)?.into(),serde_json::to_vec(&member)?.into(),
                    header.id.clone().into(),integer(old)?.into()],
            )).await?;
        }
    }
    Ok(insertion)
}

pub(super) async fn validate(db: &impl ConnectionTrait) -> Result<()> {
    ensure!(
        version(db).await? == 20,
        "display observations history format is not 20"
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
    db.query_all_raw(statement(
        "SELECT sealed FROM conversation_display_blocks LIMIT 0",
        vec![],
    ))
    .await?;
    db.query_all_raw(statement(
        "SELECT association_key FROM conversation_display_members LIMIT 0",
        vec![],
    ))
    .await?;
    let (published, effect) = conversation::display::watermarks(db).await?;
    let last = conversation::display::history_heads(db, i64::MAX as u64, None, 1).await?;
    ensure!(
        last.first().map_or(0, |h| h.history_pos) == published,
        "display published head is missing"
    );
    let row = db
        .query_one_raw(statement(
            "SELECT applied_write_seq FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .context("display identity is missing")?;
    ensure!(
        effect <= u64::try_from(row.try_get::<i64>("", "applied_write_seq")?)?,
        "display effect is ahead of history"
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(effect_seq: u64, suborder: u32) -> ChatFactPosition {
        ChatFactPosition {
            effect_seq,
            suborder,
        }
    }
    fn atom(id: &str, terminal: bool) -> Result<ChatAtom> {
        let mut atom: ChatAtom = serde_json::from_slice(&conversation::tests::metadata(id))?;
        atom.source = pl_protocol::ChatSourceId::ForegroundTurn {
            turn_id: "turn".into(),
        };
        atom.kind = pl_protocol::ChatAtomKind::ToolCall;
        atom.delivery = pl_protocol::ChatDeliveryKind::Foreground;
        atom.started_at = Some(10);
        atom.finished_at = terminal.then_some(80);
        atom.completion_item_id = terminal.then(|| id.into());
        atom.lifecycle = if terminal {
            ChatAtomLifecycle::Terminal {
                started: Some(at(1, 1)),
                ended: Some(at(8, 1)),
                outcome: pl_protocol::ChatTerminalOutcome::Cancelled,
            }
        } else {
            ChatAtomLifecycle::Active {
                started: Some(at(1, 1)),
                status: pl_protocol::ChatActiveStatus::Running,
            }
        };
        Ok(atom)
    }
    async fn fact(
        db: &impl ConnectionTrait,
        atom: &ChatAtom,
        phase: &str,
        at: ChatFactPosition,
    ) -> Result<()> {
        db.execute_raw(statement(
            "INSERT INTO conversation_atom_facts(effect_seq,suborder,atom_id,phase,fact_order,metadata) VALUES(?,?,?,?,1,?)",
            vec![integer(at.effect_seq)?.into(),i64::from(at.suborder).into(),atom.id.clone().into(),
                phase.into(),serde_json::to_vec(atom)?.into()],
        )).await?;
        Ok(())
    }

    #[tokio::test]
    async fn v19_late_terminal_joins_the_work_open_at_its_position_even_when_now_sealed()
    -> Result<()> {
        use display_snapshots::legacy as v19;
        let (_dir, db) = display_snapshots::tests::fixture().await?;
        Migrator {
            thread_id: "display-snapshot-migration".into(),
            execution_identity: None,
            bot_root: None,
        }
        .up(&db, Some(1))
        .await?;
        let make = |id: &str,
                    kind,
                    start: ChatFactPosition,
                    end: Option<ChatFactPosition>,
                    time: i64|
         -> Result<ChatAtom> {
            let mut value = atom(id, end.is_some())?;
            value.kind = kind;
            value.started_at = Some(time);
            value.finished_at = end.map(|at| at.effect_seq as i64 * 10);
            value.lifecycle = match end {
                Some(end) => ChatAtomLifecycle::Terminal {
                    started: Some(start),
                    ended: Some(end),
                    outcome: pl_protocol::ChatTerminalOutcome::Completed,
                },
                None => ChatAtomLifecycle::Active {
                    started: Some(start),
                    status: pl_protocol::ChatActiveStatus::Running,
                },
            };
            Ok(value)
        };
        let a = make(
            "A",
            pl_protocol::ChatAtomKind::ToolCall,
            at(1, 1),
            Some(at(6, 1)),
            10,
        )?;
        let r = make(
            "R",
            pl_protocol::ChatAtomKind::Reasoning,
            at(1, 2),
            None,
            10,
        )?;
        let t1 = make(
            "T1",
            pl_protocol::ChatAtomKind::Text,
            at(3, 1),
            Some(at(4, 1)),
            30,
        )?;
        let b = make(
            "B",
            pl_protocol::ChatAtomKind::ToolCall,
            at(5, 1),
            Some(at(8, 1)),
            50,
        )?;
        let t2 = make("T2", pl_protocol::ChatAtomKind::Text, at(7, 1), None, 70)?;
        for value in [&a, &r, &t1, &b, &t2] {
            let start = match value.lifecycle {
                ChatAtomLifecycle::Active { started, .. }
                | ChatAtomLifecycle::Terminal { started, .. } => started.unwrap(),
            };
            let mut begun = value.clone();
            begun.completion_item_id = None;
            begun.finished_at = None;
            begun.lifecycle = ChatAtomLifecycle::Active {
                started: Some(start),
                status: pl_protocol::ChatActiveStatus::Running,
            };
            fact(&db, &begun, "start", start).await?;
            if let ChatAtomLifecycle::Terminal {
                ended: Some(end), ..
            } = value.lifecycle
            {
                fact(&db, value, "terminal", end).await?;
            }
        }
        for (seq, value) in [(1, &t1), (2, &a), (3, &b)] {
            let mut draft = pl_core::chat::ChatDraft::new(
                value.id.clone(),
                "conversation",
                Arc::<[u8]>::from(format!("ORIGINAL_{}", value.id).into_bytes()),
            );
            draft.metadata = serde_json::to_vec(value)?.into();
            draft.read_hint =
                crate::studio::runtime::chat_item::native_read_hint_v1("conversation", value);
            let item = pl_core::chat::ChatItem::complete(
                draft,
                seq,
                Some(pl_core::chat::ChatRunPosition {
                    start_seq: if seq == 1 { 1 } else { 2 },
                    ordinal: if seq == 1 { 1 } else { seq - 1 },
                }),
            );
            conversation::append_records(&db, [&item], true).await?;
        }
        let database: String = db
            .query_one_raw(statement(
                "SELECT database_id FROM history_meta WHERE id=1",
                vec![],
            ))
            .await?
            .unwrap()
            .try_get("", "database_id")?;
        for (order, id, boundary, values, work) in [
            (1, "G1", Some(at(3, 1)), vec![a.clone(), r], true),
            (2, "T1", Some(at(4, 1)), vec![t1], false),
            (3, "G2", Some(at(7, 1)), vec![b], true),
            (4, "T2", None, vec![t2], false),
        ] {
            let unfinished = values
                .iter()
                .filter(|a| matches!(a.lifecycle, ChatAtomLifecycle::Active { .. }))
                .count() as u64;
            let header = v19::DisplayHeader {
                version: 1,
                legacy: false,
                id: id.into(),
                source: a.source.clone(),
                block_order: order,
                history_pos: None,
                boundary,
                unfinished,
                next_member: values.len() as u64,
                revision: 2,
                skip_display: false,
                active_since: None,
                duration_known: false,
                body: if work {
                    v19::DisplayBlockBody::Work {
                        summary: Box::new(v19::WorkSummary {
                            total: values.len() as u64,
                            terminal: values.len() as u64 - unfinished,
                            running: unfinished,
                            created_at: Some(if id == "G1" { 10 } else { 50 }),
                            elapsed_ms: Some(999_000),
                            thinking_summary: Some("LATEST_NOT_A_CUT".into()),
                            ..Default::default()
                        }),
                        members: pl_protocol::DisplayBlockRef {
                            database_id: database.clone(),
                            block_id: id.into(),
                        },
                    }
                } else {
                    v19::DisplayBlockBody::Single {
                        atom: Box::new(values[0].clone()),
                        completion_id: values[0].completion_item_id.clone(),
                    }
                },
            };
            db.execute_raw(statement(
                "INSERT INTO conversation_display_blocks(block_id,source_key,block_order,history_pos,updated_effect,header) VALUES(?,?,?,NULL,8,?)",
                vec![id.into(),serde_json::to_string(&a.source)?.into(),integer(order)?.into(),serde_json::to_vec(&header)?.into()],
            )).await?;
            for (index, atom) in values.into_iter().enumerate() {
                let member = v19::DisplayMemberWrite {
                    block_id: id.into(),
                    terminal: matches!(atom.lifecycle, ChatAtomLifecycle::Terminal { .. }),
                    head: v19::DisplayMemberHead {
                        member_key: format!("old-{id}-{}", atom.id),
                        member_order: index as u64 + 1,
                        completion_id: atom.completion_item_id.clone(),
                        atom,
                    },
                };
                db.execute_raw(statement(
                    "INSERT INTO conversation_display_members(block_id,member_order,member_key,terminal,completion_id,updated_effect,metadata) VALUES(?,?,?,?,?,8,?)",
                    vec![id.into(),integer(member.head.member_order)?.into(),member.head.member_key.clone().into(),
                        i64::from(member.terminal).into(),member.head.completion_id.clone().into(),serde_json::to_vec(&member)?.into()],
                )).await?;
            }
        }
        db.execute_unprepared(
            "UPDATE history_meta SET applied_write_seq=8,display_applied_effect=8",
        )
        .await?;
        prepare(&db, "display-snapshot-migration", Preparation::Schema, None).await?;
        let g1 = conversation::display::member_page(&db, "G1", None, 8).await?;
        let a_start = g1.iter().find(|m| m.head.record.atom.id == "A").unwrap();
        assert_eq!(a_start.head.member_key, "old-G1-A");
        assert_eq!(a_start.head.record.start_fact, Some(at(1, 1)));
        assert_eq!(a_start.head.record.end_fact, None);
        let g2 = conversation::display::member_page(&db, "G2", None, 8).await?;
        assert_eq!(g2.len(), 2);
        assert_eq!(g2[0].head.member_key, "old-G2-B");
        assert!(matches!(
            g2[0].head.record.content_source,
            DisplayContentSource::FrozenObservation {
                available: false,
                ..
            }
        ));
        assert_eq!(g2[0].head.record.atom.finished_at, None);
        assert_eq!(g2[1].head.record.atom.id, "A");
        assert_ne!(g2[1].head.member_key, a_start.head.member_key);
        assert_eq!(g2[1].head.record.start_fact, None);
        assert_eq!(g2[1].head.record.end_fact, Some(at(6, 1)));
        let recovery = conversation::display::recovery(&db).await?;
        let group = recovery.open.iter().find(|h| h.id == "G2").unwrap();
        assert!(group.sealed);
        assert_eq!(group.boundary, Some(at(7, 1)));
        let DisplayBlockBody::Work { summary, .. } = &group.body else {
            panic!()
        };
        assert_eq!(
            (summary.total, summary.terminal, summary.unavailable),
            (2, 1, 1)
        );
        assert_eq!(summary.elapsed_ms, Some(20_000));
        assert_eq!(summary.thinking_summary, None);
        let late_count=db.query_one_raw(statement(
            "SELECT count(*) AS n FROM conversation_display_members WHERE json_extract(metadata,'$.head.record.atom.id')='A' AND json_type(metadata,'$.head.record.endFact')='object'",vec![],
        )).await?.unwrap().try_get::<i64>("","n")?;
        assert_eq!(late_count, 1);
        assert_eq!(
            recovery
                .open
                .iter()
                .filter(|h| matches!(h.body, DisplayBlockBody::Work { .. }))
                .count(),
            3,
            "only B's end after Text2 needs an extra Work, not A's end within G2"
        );
        assert_eq!(recovery.published, 0);
        let old_order = recovery
            .open
            .iter()
            .filter(|h| ["G1", "T1", "G2", "T2"].contains(&h.id.as_str()))
            .map(|h| h.id.as_str())
            .collect::<Vec<_>>();
        assert_eq!(old_order, ["G1", "T1", "G2", "T2"]);
        Ok(())
    }

    #[tokio::test]
    async fn v19_closing_cut_preserves_ids_and_routes_late_terminal_without_latest_metadata()
    -> Result<()> {
        for boundary in [at(5, 2), at(8, 0)] {
            use display_snapshots::legacy as v19;
            let (_dir, db) = display_snapshots::tests::fixture().await?;
            let migrator = Migrator {
                thread_id: "display-snapshot-migration".into(),
                execution_identity: None,
                bot_root: None,
            };
            migrator.up(&db, Some(1)).await?;
            assert_eq!(version(&db).await?, 19);
            let start = atom("late", false)?;
            let terminal = atom("late", true)?;
            fact(&db, &start, "start", at(1, 1)).await?;
            fact(&db, &terminal, "terminal", at(8, 1)).await?;
            let mut text = atom("text", false)?;
            text.kind = pl_protocol::ChatAtomKind::Text;
            text.started_at = Some(50);
            text.lifecycle = ChatAtomLifecycle::Active {
                started: Some(boundary),
                status: pl_protocol::ChatActiveStatus::Running,
            };
            fact(&db, &text, "start", boundary).await?;
            conversation::sources::apply(
                &db,
                8,
                &[pl_protocol::ChatSourceState {
                    source: terminal.source.clone(),
                    lifecycle: pl_protocol::ChatSourceLifecycle::Ended {
                        outcome: pl_protocol::ChatTerminalOutcome::Cancelled,
                    },
                    started: Some(at(1, 0)),
                    ended: Some(boundary),
                }],
            )
            .await?;
            let mut draft = pl_core::chat::ChatDraft::new(
                "late",
                "conversation",
                Arc::<[u8]>::from(b"original-payload".as_slice()),
            );
            draft.metadata = serde_json::to_vec(&terminal)?.into();
            draft.read_hint =
                crate::studio::runtime::chat_item::native_read_hint_v1("conversation", &terminal);
            let item = pl_core::chat::ChatItem::complete(
                draft,
                1,
                Some(pl_core::chat::ChatRunPosition {
                    start_seq: 1,
                    ordinal: 1,
                }),
            );
            conversation::append_records(&db, [&item], true).await?;
            let original = db
                .query_one_raw(statement(
                    "SELECT payload,metadata FROM conversation_items WHERE item_id='late'",
                    vec![],
                ))
                .await?
                .unwrap();
            let source = terminal.source.clone();
            let database: String = db
                .query_one_raw(statement(
                    "SELECT database_id FROM history_meta WHERE id=1",
                    vec![],
                ))
                .await?
                .unwrap()
                .try_get("", "database_id")?;
            let mut other = start.clone();
            other.id = "other".into();
            let other_start = if boundary.suborder == 0 {
                at(8, 2)
            } else {
                at(6, 0)
            };
            other.started_at = Some(other_start.effect_seq as i64 * 10);
            other.lifecycle = ChatAtomLifecycle::Active {
                started: Some(other_start),
                status: pl_protocol::ChatActiveStatus::Running,
            };
            fact(&db, &other, "start", other_start).await?;
            let old_facts=db.query_all_raw(statement(
            "SELECT effect_seq,suborder,metadata FROM conversation_atom_facts ORDER BY effect_seq,suborder,atom_id",vec![],
        )).await?.into_iter().map(|row| Ok((row.try_get::<i64>("","effect_seq")?,
            row.try_get::<i64>("","suborder")?,row.try_get::<Vec<u8>>("","metadata")?)))
            .collect::<Result<Vec<_>>>()?;
            for (order, id, boundary, is_work, member_atom) in [
                (1, "closing", Some(boundary), true, terminal.clone()),
                (2, "body", None, false, text),
                (3, "open", None, true, other.clone()),
            ] {
                let head = v19::DisplayHeader {
                    version: 1,
                    legacy: false,
                    id: id.into(),
                    source: source.clone(),
                    block_order: order,
                    history_pos: None,
                    boundary,
                    unfinished: if id == "closing" { 0 } else { 1 },
                    next_member: 1,
                    revision: 3,
                    skip_display: false,
                    active_since: None,
                    duration_known: false,
                    body: if is_work {
                        v19::DisplayBlockBody::Work {
                            summary: Box::new(v19::WorkSummary {
                                total: 1,
                                terminal: if id == "closing" { 1 } else { 0 },
                                running: if id == "closing" { 0 } else { 1 },
                                created_at: Some(if id == "open" { 60 } else { 10 }),
                                elapsed_ms: Some(999_000),
                                thinking_summary: Some("AFTER_BOUNDARY".into()),
                                ..Default::default()
                            }),
                            members: pl_protocol::DisplayBlockRef {
                                database_id: database.clone(),
                                block_id: id.into(),
                            },
                        }
                    } else {
                        v19::DisplayBlockBody::Single {
                            atom: Box::new(member_atom.clone()),
                            completion_id: None,
                        }
                    },
                };
                let member = v19::DisplayMemberWrite {
                    block_id: id.into(),
                    terminal: id == "closing",
                    head: v19::DisplayMemberHead {
                        member_key: format!("old-{id}"),
                        member_order: 1,
                        completion_id: member_atom.completion_item_id.clone(),
                        atom: member_atom,
                    },
                };
                db.execute_raw(statement(
                "INSERT INTO conversation_display_blocks(block_id,source_key,block_order,history_pos,updated_effect,header) VALUES(?,?,?,NULL,8,?)",
                vec![id.into(),serde_json::to_string(&source)?.into(),integer(order)?.into(),serde_json::to_vec(&head)?.into()],
            )).await?;
                db.execute_raw(statement(
                "INSERT INTO conversation_display_members(block_id,member_order,member_key,terminal,completion_id,updated_effect,metadata) VALUES(?,1,?,?,?,?,?)",
                vec![id.into(),member.head.member_key.clone().into(),i64::from(member.terminal).into(),
                    member.head.completion_id.clone().into(),8i64.into(),serde_json::to_vec(&member)?.into()],
            )).await?;
            }
            db.execute_unprepared(
                "UPDATE history_meta SET applied_write_seq=8,display_applied_effect=8",
            )
            .await?;
            // A failed conversion cannot change either source rows or the Applied ledger.
            db.execute_unprepared("CREATE TRIGGER reject_v20 BEFORE UPDATE ON history_meta WHEN NEW.schema_version=20 BEGIN SELECT RAISE(ABORT,'injected'); END").await?;
            assert!(
                prepare(&db, "display-snapshot-migration", Preparation::Schema, None)
                    .await
                    .is_err()
            );
            assert_eq!(version(&db).await?, 19);
            db.execute_unprepared("DROP TRIGGER reject_v20").await?;
            db.execute_unprepared(
                "DELETE FROM conversation_atom_facts WHERE atom_id='other' AND phase='start'",
            )
            .await?;
            assert!(
                prepare(&db, "display-snapshot-migration", Preparation::Schema, None)
                    .await
                    .is_err(),
                "an unproved target creation must not be guessed from block order"
            );
            assert_eq!(version(&db).await?, 19);
            fact(&db, &other, "start", other_start).await?;
            prepare(&db, "display-snapshot-migration", Preparation::Schema, None).await?;
            assert_eq!(version(&db).await?, 20);
            let recovery = conversation::display::recovery(&db).await?;
            let closing = recovery.open.iter().find(|h| h.id == "closing").unwrap();
            assert!(closing.sealed);
            assert_eq!(closing.history_pos, None);
            let DisplayBlockBody::Work { summary, .. } = &closing.body else {
                panic!()
            };
            assert_eq!(
                (
                    summary.unavailable,
                    summary.running,
                    summary.waiting,
                    summary.terminal
                ),
                (1, 0, 0, 0)
            );
            assert_eq!(summary.elapsed_ms, Some(40_000));
            assert_eq!(summary.thinking_summary, None);
            let old = conversation::display::member_page(&db, "closing", None, 8).await?;
            assert_eq!(old[0].head.member_key, "old-closing");
            assert_eq!(old[0].head.record.start_fact, Some(at(1, 1)));
            assert_eq!(old[0].head.record.end_fact, None);
            assert!(matches!(
                old[0].head.record.content_source,
                DisplayContentSource::FrozenObservation {
                    available: false,
                    ..
                }
            ));
            let open = conversation::display::member_page(&db, "open", None, 8).await?;
            assert_eq!(open.len(), 2);
            assert!(open.iter().any(|m| m.head.member_key == "old-open"));
            let late = open
                .iter()
                .find(|m| m.head.record.atom.id == "late")
                .unwrap();
            assert_eq!(late.head.record.start_fact, None);
            assert_eq!(late.head.record.end_fact, Some(at(8, 1)));
            assert_ne!(late.head.member_key, old[0].head.member_key);
            assert!(
                recovery
                    .unfinished
                    .iter()
                    .all(|member| member.block_id != "closing")
            );
            let now = db
                .query_one_raw(statement(
                    "SELECT payload,metadata FROM conversation_items WHERE item_id='late'",
                    vec![],
                ))
                .await?
                .unwrap();
            for column in ["payload", "metadata"] {
                assert_eq!(
                    now.try_get::<Vec<u8>>("", column)?,
                    original.try_get::<Vec<u8>>("", column)?
                );
            }
            prepare(&db, "display-snapshot-migration", Preparation::Schema, None).await?;
            assert_eq!(
                conversation::display::member_page(&db, "open", None, 8)
                    .await?
                    .len(),
                2
            );
            let new_facts=db.query_all_raw(statement(
            "SELECT effect_seq,suborder,metadata FROM conversation_atom_facts ORDER BY effect_seq,suborder,atom_id",vec![],
        )).await?.into_iter().map(|row| Ok((row.try_get::<i64>("","effect_seq")?,
            row.try_get::<i64>("","suborder")?,row.try_get::<Vec<u8>>("","metadata")?)))
            .collect::<Result<Vec<_>>>()?;
            assert_eq!(
                new_facts, old_facts,
                "migration/reopen must not normalize old positions"
            );
            let source = db
                .query_one_raw(statement(
                    "SELECT ended_effect,ended_suborder FROM conversation_sources",
                    vec![],
                ))
                .await?
                .context("preserved source")?;
            assert_eq!(
                (
                    source.try_get::<i64>("", "ended_effect")?,
                    source.try_get::<i64>("", "ended_suborder")?
                ),
                (boundary.effect_seq as i64, i64::from(boundary.suborder))
            );
        }
        Ok(())
    }
}
