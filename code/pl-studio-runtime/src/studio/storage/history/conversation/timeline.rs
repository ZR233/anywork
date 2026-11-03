//! Derived, rebuildable Timeline read model. Atomic completions and their real
//! source lifecycle remain the only facts; these rows can be deleted and rebuilt
//! by replaying the same Studio projection.

use super::current::{PreparedCurrent, PreparedTimelineItem, PreparedTimelineMember};
use super::*;
use pl_protocol::{
    ChatAtom, ChatAtomLifecycle, ChatSourceId, ChatSourceLifecycle, ContentRef, ContentTarget,
    CurrentProjection, PayloadData, TIMELINE_PROJECTION_VERSION, TimelineItem,
};
use serde::{Deserialize, Serialize};

pub(in super::super) const CREATE_SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS timeline_items (
 position INTEGER PRIMARY KEY,
 item_id TEXT NOT NULL UNIQUE,
 kind TEXT NOT NULL,
 commit_seq INTEGER NOT NULL,
 metadata BLOB NOT NULL,
 projection_version INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS timeline_items_by_commit
 ON timeline_items(commit_seq, position);
CREATE TABLE IF NOT EXISTS timeline_item_members (
 item_id TEXT NOT NULL,
 member_order INTEGER NOT NULL,
 member_id TEXT NOT NULL,
 completion_item_id TEXT NOT NULL,
 PRIMARY KEY(item_id, member_order),
 UNIQUE(item_id, member_id)
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS timeline_projection_state (
 singleton_id INTEGER PRIMARY KEY CHECK(singleton_id=1),
 projection_version INTEGER NOT NULL,
 next_position INTEGER NOT NULL
);
";

/// Stored metadata keeps only the stable item envelope; the original completion
/// item owns the payload/contents bytes.
#[derive(Debug, Serialize, Deserialize)]
struct StoredItem {
    item: TimelineItem,
}

pub(in super::super) async fn validate_tables(db: &impl ConnectionTrait) -> Result<()> {
    db.query_all_raw(statement(
        "SELECT position,item_id,kind,commit_seq,metadata,projection_version FROM timeline_items LIMIT 0",
        vec![],
    ))
    .await
    .context("timeline item table or column is missing; existing data preserved")?;
    db.query_all_raw(statement(
        "SELECT item_id,member_order,member_id,completion_item_id FROM timeline_item_members LIMIT 0",
        vec![],
    ))
    .await
    .context("timeline member table or column is missing; existing data preserved")?;
    db.query_all_raw(statement(
        "SELECT singleton_id,projection_version,next_position FROM timeline_projection_state LIMIT 0",
        vec![],
    ))
    .await
    .context("timeline projection state is missing; existing data preserved")?;
    Ok(())
}

/// Current projection version and the next free history position.
pub(in super::super) async fn state(db: &impl ConnectionTrait) -> Result<Option<(u32, u64)>> {
    let Some(row) = db
        .query_one_raw(statement(
            "SELECT projection_version,next_position FROM timeline_projection_state WHERE singleton_id=1",
            vec![],
        ))
        .await?
    else {
        return Ok(None);
    };
    Ok(Some((
        u32::try_from(row.try_get::<i64>("", "projection_version")?)?,
        u64::try_from(row.try_get::<i64>("", "next_position")?)?,
    )))
}

pub(in super::super) async fn next_position(db: &impl ConnectionTrait) -> Result<u64> {
    Ok(state(db).await?.map_or(0, |(_, next)| next))
}

fn deferred_item(database_id: &str, item: &TimelineItem) -> TimelineItem {
    let mut stored = item.clone();
    stored.current_members.clear();
    if let Some(PayloadData::Inline { bytes }) = &item.payload {
        let target = item
            .content_item_id
            .clone()
            .unwrap_or_else(|| item.id.clone());
        stored.payload = Some(PayloadData::Deferred {
            reference: ContentRef {
                database_id: database_id.into(),
                target: ContentTarget::ItemPayload { item_id: target },
            },
            byte_length: bytes.len() as u64,
        });
    }
    stored
}

fn stored(item: &TimelineItem) -> Result<Vec<u8>> {
    Ok(serde_json::to_vec(&StoredItem { item: item.clone() })?)
}

/// Writes the effect's committed items in the caller's transaction. Positions and
/// identities are immutable; a retried effect verifies instead of rewriting them.
pub(in super::super) async fn apply(
    db: &impl ConnectionTrait,
    database_id: &str,
    current: &PreparedCurrent,
) -> Result<()> {
    if current.timeline.is_empty() {
        return Ok(());
    }
    ensure!(
        current.timeline_commit > 0,
        "committed timeline items have no publication sequence"
    );
    let mut expected = next_position(db).await?;
    for entry in current.timeline.iter() {
        ensure!(
            entry.item.position == Some(expected),
            "timeline item position {:?} is not the next history position {expected:?}",
            entry.item.position
        );
        expected = expected.checked_add(1).context("timeline order overflow")?;
    }
    for entry in current.timeline.iter() {
        insert_item(db, database_id, entry, current.timeline_commit).await?;
    }
    write_state(db, expected).await
}

async fn insert_item(
    db: &impl ConnectionTrait,
    database_id: &str,
    entry: &PreparedTimelineItem,
    commit_seq: u64,
) -> Result<()> {
    let item = deferred_item(database_id, &entry.item);
    let position = item
        .position
        .or(entry.item.position)
        .context("timeline item has no history position")?;
    ensure!(
        entry.item.id == item.id && !item.id.is_empty(),
        "timeline item identity is empty"
    );
    let existing = db
        .query_one_raw(statement(
            "SELECT position,kind,commit_seq,metadata FROM timeline_items WHERE item_id=?",
            vec![item.id.clone().into()],
        ))
        .await?;
    if let Some(row) = existing {
        ensure!(
            u64::try_from(row.try_get::<i64>("", "position")?)? == position
                && row.try_get::<String>("", "kind")? == item.kind.as_str()
                && u64::try_from(row.try_get::<i64>("", "commit_seq")?)? == commit_seq
                && row.try_get::<Vec<u8>>("", "metadata")? == stored(&item)?,
            "immutable timeline item conflict"
        );
        return Ok(());
    }
    db.execute_raw(statement(
        "INSERT INTO timeline_items(position,item_id,kind,commit_seq,metadata,projection_version)
         VALUES(?,?,?,?,?,?)",
        vec![
            integer(position)?.into(),
            item.id.clone().into(),
            item.kind.as_str().into(),
            integer(commit_seq)?.into(),
            stored(&item)?.into(),
            i64::from(TIMELINE_PROJECTION_VERSION).into(),
        ],
    ))
    .await?;
    for (order, member) in entry.members.iter().enumerate() {
        db.execute_raw(statement(
            "INSERT INTO timeline_item_members(item_id,member_order,member_id,completion_item_id)
             VALUES(?,?,?,?)",
            vec![
                item.id.clone().into(),
                i64::try_from(order)?.into(),
                member.member_id.clone().into(),
                member.completion_item_id.clone().into(),
            ],
        ))
        .await?;
    }
    Ok(())
}

/// A retried effect must find exactly the rows it already committed.
pub(in super::super) async fn verify(
    db: &impl ConnectionTrait,
    database_id: &str,
    current: &PreparedCurrent,
) -> Result<()> {
    if current.timeline.is_empty() {
        return Ok(());
    }
    for entry in current.timeline.iter() {
        let item = deferred_item(database_id, &entry.item);
        let position = entry
            .item
            .position
            .context("timeline item has no position")?;
        let row = db
            .query_one_raw(statement(
                "SELECT position,kind,commit_seq,metadata FROM timeline_items WHERE item_id=?",
                vec![item.id.clone().into()],
            ))
            .await?
            .context("retried effect is missing a committed timeline item")?;
        ensure!(
            u64::try_from(row.try_get::<i64>("", "position")?)? == position
                && row.try_get::<String>("", "kind")? == item.kind.as_str()
                && row.try_get::<Vec<u8>>("", "metadata")? == stored(&item)?,
            "retried effect changed a committed timeline item"
        );
        let members = db
            .query_all_raw(statement(
                "SELECT member_id,completion_item_id FROM timeline_item_members
                 WHERE item_id=? ORDER BY member_order",
                vec![item.id.clone().into()],
            ))
            .await?;
        ensure!(
            members.len() == entry.members.len()
                && members
                    .iter()
                    .zip(entry.members.iter())
                    .all(|(row, member)| {
                        row.try_get::<String>("", "member_id")
                            .is_ok_and(|id| id == member.member_id)
                            && row
                                .try_get::<String>("", "completion_item_id")
                                .is_ok_and(|id| id == member.completion_item_id)
                    }),
            "retried effect changed committed timeline members"
        );
        ensure!(
            u64::try_from(row.try_get::<i64>("", "commit_seq")?)? == current.timeline_commit,
            "retried effect changed the timeline publication sequence"
        );
    }
    Ok(())
}

async fn write_state(db: &impl ConnectionTrait, next: u64) -> Result<()> {
    db.execute_raw(statement(
        "INSERT INTO timeline_projection_state(singleton_id,projection_version,next_position)
         VALUES(1,?,?) ON CONFLICT(singleton_id) DO UPDATE SET
         projection_version=excluded.projection_version,next_position=excluded.next_position",
        vec![
            i64::from(TIMELINE_PROJECTION_VERSION).into(),
            integer(next)?.into(),
        ],
    ))
    .await?;
    Ok(())
}

/// Rebuilds the derived rows from preserved atomic facts and the saved current
/// cut. Used by the schema migration and explicit maintenance rebuild.
pub(in crate::studio) async fn rebuild(db: &impl ConnectionTrait, database_id: &str) -> Result<()> {
    let current_row = db
        .query_one_raw(statement(
            "SELECT payload FROM conversation_view_state WHERE singleton_id=1",
            vec![],
        ))
        .await?;
    let mut current: CurrentProjection = match current_row {
        Some(row) => serde_json::from_slice(&row.try_get::<Vec<u8>>("", "payload")?)?,
        None => CurrentProjection::empty(0, pl_protocol::ThreadStatus::Idle),
    };

    enum Event {
        Start(ChatAtom),
        End(ChatAtom, Option<Vec<u8>>),
        SourceEnd(ChatSourceId),
    }

    let mut events: Vec<(Option<u64>, u32, u64, u8, Event)> = Vec::new();
    let mut after = 0i64;
    loop {
        let rows = db
            .query_all_raw(statement(
                "SELECT seq,metadata,payload FROM conversation_items
                 WHERE query_class<>'diagnostic' AND seq>? ORDER BY seq LIMIT 128",
                vec![after.into()],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            after = row.try_get("", "seq")?;
            let metadata = row.try_get::<Vec<u8>>("", "metadata")?;
            if metadata.is_empty() {
                continue;
            }
            let atom: ChatAtom = serde_json::from_slice(&metadata)?;
            let sequence = u64::try_from(after)?;
            let (started, ended) = match &atom.lifecycle {
                ChatAtomLifecycle::Active { started, .. } => (*started, None),
                ChatAtomLifecycle::Terminal { started, ended, .. } => (*started, *ended),
            };
            let start_at = started.map(|at| (at.effect_seq, at.suborder));
            if let (Some((effect, suborder)), ChatAtomLifecycle::Terminal { .. }) =
                (start_at, &atom.lifecycle)
            {
                let mut active = atom.clone();
                active.lifecycle = ChatAtomLifecycle::Active {
                    started: Some(pl_protocol::ChatFactPosition {
                        effect_seq: effect,
                        suborder,
                    }),
                    status: pl_protocol::ChatActiveStatus::Running,
                };
                events.push((Some(effect), suborder, sequence, 0, Event::Start(active)));
                let (ended_effect, ended_suborder) = ended
                    .map(|at| (Some(at.effect_seq), at.suborder))
                    .unwrap_or((None, 0));
                events.push((
                    ended_effect,
                    ended_suborder,
                    sequence,
                    1,
                    Event::End(atom, Some(row.try_get::<Vec<u8>>("", "payload")?)),
                ));
            } else {
                events.push((
                    None,
                    0,
                    sequence,
                    1,
                    Event::End(atom, Some(row.try_get::<Vec<u8>>("", "payload")?)),
                ));
            }
        }
    }
    for row in db
        .query_all_raw(statement(
            "SELECT source_key,ended_observed FROM conversation_sources
             WHERE ended_observed IS NOT NULL",
            vec![],
        ))
        .await?
    {
        let source: ChatSourceId = serde_json::from_str(&row.try_get::<String>("", "source_key")?)?;
        let effect = u64::try_from(row.try_get::<i64>("", "ended_observed")?)?;
        events.push((Some(effect), u32::MAX, 0, 2, Event::SourceEnd(source)));
    }
    events.sort_by_key(|(effect, suborder, sequence, class, _)| {
        (effect.unwrap_or(u64::MAX), *suborder, *class, *sequence)
    });

    let mut projection =
        crate::studio::thread_projection::TimelineProjection::new(database_id.into(), 0);
    let mut prepared: Vec<PreparedTimelineItem> = Vec::new();
    let mut index = 0;
    while index < events.len() {
        let effect = events[index].0;
        while index < events.len() && events[index].0 == effect {
            match &events[index].4 {
                Event::Start(atom) => projection.observe(atom, None),
                Event::End(atom, payload) => projection.complete(
                    atom.clone(),
                    events[index].2,
                    payload.as_ref().map(|bytes| PayloadData::Inline {
                        bytes: bytes.clone(),
                    }),
                ),
                Event::SourceEnd(source) => projection.end_source(source),
            }
            index += 1;
        }
        projection.commit_ready();
        let committed = projection.take_committed();
        let members = projection.take_committed_members();
        for item in committed {
            let item_members = members.get(&item.id).cloned().unwrap_or_default();
            prepared.push(PreparedTimelineItem {
                item: deferred_item(database_id, &item),
                members: item_members
                    .into_iter()
                    .map(|(member_id, completion_item_id)| PreparedTimelineMember {
                        member_id,
                        completion_item_id,
                    })
                    .collect(),
            });
        }
    }
    drop(events);
    for atom in &current.atoms {
        projection.observe(atom, None);
    }
    for state in &current.sources {
        if matches!(state.lifecycle, ChatSourceLifecycle::Ended { .. }) {
            projection.end_source(&state.source);
        }
    }
    projection.commit_ready();
    let committed = projection.take_committed();
    let members = projection.take_committed_members();
    for item in committed {
        let item_members = members.get(&item.id).cloned().unwrap_or_default();
        prepared.push(PreparedTimelineItem {
            item: deferred_item(database_id, &item),
            members: item_members
                .into_iter()
                .map(|(member_id, completion_item_id)| PreparedTimelineMember {
                    member_id,
                    completion_item_id,
                })
                .collect(),
        });
    }

    db.execute_unprepared("DELETE FROM timeline_item_members; DELETE FROM timeline_items;")
        .await?;
    let sequence: std::collections::BTreeMap<String, u64> = db
        .query_all_raw(statement(
            "SELECT item_id,seq FROM conversation_items",
            vec![],
        ))
        .await?
        .into_iter()
        .map(|row| {
            Ok((
                row.try_get::<String>("", "item_id")?,
                u64::try_from(row.try_get::<i64>("", "seq")?)?,
            ))
        })
        .collect::<Result<_>>()?;
    for entry in &prepared {
        let commit_seq = entry
            .members
            .iter()
            .filter_map(|member| sequence.get(&member.completion_item_id).copied())
            .max()
            .unwrap_or(0);
        insert_item(db, database_id, entry, commit_seq).await?;
    }
    let next = projection.next_position();
    write_state(db, next).await?;

    current.items = projection.current_items();
    let bytes = serde_json::to_vec(&current)?;
    ensure!(
        bytes.len() <= pl_protocol::CHAT_BATCH_MAX_BYTES as usize,
        "rebuilt current projection exceeds product envelope budget"
    );
    db.execute_raw(statement(
        "UPDATE conversation_view_state SET payload=? WHERE singleton_id=1",
        vec![bytes.into()],
    ))
    .await?;
    Ok(())
}
