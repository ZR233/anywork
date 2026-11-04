//! Rebuildable, metadata-only display index, written by the original effect transaction.
#[cfg(test)]
#[path = "timeline/read_work_tests.rs"]
mod read_work_tests;
#[cfg(test)]
#[path = "timeline/tests.rs"]
mod tests;
use super::current::{PreparedCurrent, PreparedTimelineItem};
use super::*;
use crate::studio::thread_projection::{
    TimelineProjection,
    timeline::{TimelineUpdate, lightweight},
};
use pl_protocol::{
    ChatActiveStatus, ChatAtom, ChatAtomKind, ChatAtomLifecycle, ChatDeliveryKind, ChatSourceId,
    ContentRef, ContentTarget, CurrentProjection, PayloadData, TIMELINE_PROJECTION_VERSION,
    TimelineItem, TimelineMembersRef,
};

#[derive(Debug, thiserror::Error)]
#[error("timeline derived row is inconsistent; maintenance required")]
pub(in crate::studio) struct ProjectionFault;

pub(in crate::studio) fn validate_item(
    item: &TimelineItem,
    database: &str,
    generation: &str,
) -> Result<()> {
    ensure!(!item.id.is_empty(), ProjectionFault);
    if item.is_work_group() {
        ensure!(
            item.summary.is_some()
                && item.payload.is_none()
                && item.contents.is_empty()
                && item.content_item_id.is_none()
                && item.outcome.is_none(),
            ProjectionFault
        );
        let reference = item.members.as_ref().ok_or(ProjectionFault)?;
        ensure!(
            reference.database_id == database
                && reference.item_id == item.id
                && reference.projection_version == TIMELINE_PROJECTION_VERSION
                && reference.projection_generation == generation,
            ProjectionFault
        );
    } else {
        ensure!(
            item.summary.is_none() && item.members.is_none(),
            ProjectionFault
        );
    }
    Ok(())
}

pub(in super::super) const CREATE_SCHEMA: &str = "
CREATE TABLE conversation_atom_facts (
 effect_seq INTEGER NOT NULL, suborder INTEGER NOT NULL, atom_id TEXT NOT NULL,
 phase TEXT NOT NULL, fact_order INTEGER NOT NULL, metadata BLOB NOT NULL,
 PRIMARY KEY(effect_seq,suborder,atom_id,phase), UNIQUE(atom_id,phase)
) WITHOUT ROWID;
CREATE INDEX conversation_atom_facts_by_admission ON conversation_atom_facts(effect_seq,suborder,fact_order,CASE WHEN phase='legacySourceEnd' THEN 9223372036854775807 WHEN effect_seq=0 THEN COALESCE(json_extract(metadata,'$.sourceOrder'),json_extract(metadata,'$.completionSeq'),0) ELSE COALESCE(json_extract(metadata,'$.completionSeq'),0) END,atom_id,phase);
CREATE INDEX conversation_sources_by_timeline_end ON conversation_sources(COALESCE(ended_effect,ended_observed),COALESCE(ended_suborder,4294967295),source_key);
";
pub(in super::super) const CREATE_DERIVED_SCHEMA: &str = "
CREATE TABLE timeline_items (
 item_id TEXT NOT NULL PRIMARY KEY, kind TEXT NOT NULL, location TEXT NOT NULL,
 position INTEGER UNIQUE, commit_seq INTEGER, metadata BLOB NOT NULL, projection_version INTEGER NOT NULL
);
CREATE INDEX timeline_items_by_commit ON timeline_items(commit_seq,position);
CREATE INDEX timeline_items_by_location_position ON timeline_items(location,position);
CREATE TABLE timeline_item_members (
 item_id TEXT NOT NULL, member_order INTEGER NOT NULL, member_id TEXT NOT NULL,
 completion_item_id TEXT, admitted_effect INTEGER NOT NULL, metadata BLOB NOT NULL,
 PRIMARY KEY(item_id,member_order), UNIQUE(item_id,member_id)
) WITHOUT ROWID;
CREATE TABLE timeline_projection_state (
 singleton_id INTEGER PRIMARY KEY CHECK(singleton_id=1), projection_version INTEGER NOT NULL,
 next_position INTEGER NOT NULL, source_effect_seq INTEGER NOT NULL, projection_generation TEXT NOT NULL, recovery BLOB NOT NULL
);
CREATE INDEX timeline_members_by_member ON timeline_item_members(member_id);
";
pub(in super::super) async fn validate_tables(db: &impl ConnectionTrait) -> Result<()> {
    for sql in [
        "SELECT effect_seq,suborder,atom_id,phase,fact_order,metadata FROM conversation_atom_facts LIMIT 0",
        "SELECT item_id,kind,location,position,commit_seq,metadata,projection_version FROM timeline_items LIMIT 0",
        "SELECT item_id,member_order,member_id,completion_item_id,admitted_effect,metadata FROM timeline_item_members LIMIT 0",
        "SELECT projection_version,next_position,source_effect_seq,projection_generation,recovery FROM timeline_projection_state LIMIT 0",
    ] {
        db.query_all_raw(statement(sql, vec![])).await.context(
            "timeline projection requires explicit maintenance; original facts preserved",
        )?;
    }
    Ok(())
}
pub(in super::super) async fn state(db: &impl ConnectionTrait) -> Result<Option<(u32, u64)>> {
    let row = db.query_one_raw(statement("SELECT projection_version,next_position FROM timeline_projection_state WHERE singleton_id=1",vec![])).await?;
    row.map(|row| {
        Ok((
            u32::try_from(
                row.try_get::<i64>("", "projection_version")
                    .map_err(|_| ProjectionFault)?,
            )
            .map_err(|_| ProjectionFault)?,
            u64::try_from(
                row.try_get::<i64>("", "next_position")
                    .map_err(|_| ProjectionFault)?,
            )
            .map_err(|_| ProjectionFault)?,
        ))
    })
    .transpose()
}
pub(in super::super) async fn next_position(db: &impl ConnectionTrait) -> Result<u64> {
    let (version, next) = state(db)
        .await?
        .context("timeline recovery is missing; maintenance required")?;
    ensure!(
        version == TIMELINE_PROJECTION_VERSION,
        "timeline projection version requires maintenance"
    );
    Ok(next)
}
pub(in super::super) async fn recovery(db: &impl ConnectionTrait) -> Result<Vec<u8>> {
    next_position(db).await?;
    Ok(db
        .query_one_raw(statement(
            "SELECT recovery FROM timeline_projection_state WHERE singleton_id=1",
            vec![],
        ))
        .await?
        .ok_or(ProjectionFault)?
        .try_get("", "recovery")
        .map_err(|_| ProjectionFault)?)
}
pub(in crate::studio) async fn generation(db: &impl ConnectionTrait) -> Result<String> {
    let row = db
        .query_one_raw(statement(
            "SELECT projection_generation FROM timeline_projection_state WHERE singleton_id=1",
            vec![],
        ))
        .await?
        .ok_or(ProjectionFault)?;
    let value: String = row
        .try_get("", "projection_generation")
        .map_err(|_| ProjectionFault)?;
    ensure!(!value.is_empty(), ProjectionFault);
    Ok(value)
}
pub(in crate::studio) async fn apply_facts(
    db: &impl ConnectionTrait,
    current: &PreparedCurrent,
) -> Result<()> {
    for atom in current.timeline_update.facts() {
        save_fact(db, atom, current.projection().source_effect_seq).await?;
    }
    Ok(())
}
pub(in crate::studio) fn deferred_item(database: &str, item: &TimelineItem) -> TimelineItem {
    let mut value = item.clone();
    if let Some(PayloadData::Inline { bytes }) = &item.payload {
        value.payload = Some(PayloadData::Deferred {
            reference: ContentRef {
                database_id: database.into(),
                target: ContentTarget::ItemPayload {
                    item_id: item
                        .content_item_id
                        .clone()
                        .unwrap_or_else(|| item.id.clone()),
                },
            },
            byte_length: bytes.len() as u64,
        });
    }
    value
}
async fn save_item(
    db: &impl ConnectionTrait,
    database: &str,
    item: &TimelineItem,
    effect: u64,
) -> Result<()> {
    let item = deferred_item(database, item);
    let bytes = serde_json::to_vec(&item)?;
    let old = db
        .query_one_raw(statement(
            "SELECT location,metadata,position FROM timeline_items WHERE item_id=?",
            vec![item.id.clone().into()],
        ))
        .await?;
    if let Some(old) = old
        && old.try_get::<String>("", "location")? == "history"
    {
        ensure!(
            old.try_get::<Vec<u8>>("", "metadata")? == bytes,
            "immutable timeline item conflict"
        );
        return Ok(());
    }
    db.execute_raw(statement("INSERT INTO timeline_items(item_id,kind,location,position,commit_seq,metadata,projection_version) VALUES(?,?,?,?,?,?,?) ON CONFLICT(item_id) DO UPDATE SET location=excluded.location,position=excluded.position,commit_seq=excluded.commit_seq,metadata=excluded.metadata,projection_version=excluded.projection_version",vec![item.id.clone().into(),item.kind.as_str().into(),if item.position.is_some(){"history"}else{"current"}.into(),item.position.map(integer).transpose()?.into(),item.position.map(|_| integer(effect)).transpose()?.into(),bytes.into(),i64::from(TIMELINE_PROJECTION_VERSION).into()])).await?;
    Ok(())
}
async fn save_fact(db: &impl ConnectionTrait, atom: &ChatAtom, fallback: u64) -> Result<()> {
    let (at, phase) = match atom.lifecycle {
        ChatAtomLifecycle::Active { started, .. } => (started, "start"),
        ChatAtomLifecycle::Terminal { ended, .. } => (ended, "terminal"),
    };
    let bytes = serde_json::to_vec(&lightweight(atom))?;
    let old = db
        .query_one_raw(statement(
            "SELECT metadata FROM conversation_atom_facts WHERE atom_id=? AND phase=?",
            vec![atom.id.clone().into(), phase.into()],
        ))
        .await?;
    if let Some(old) = old {
        ensure!(
            old.try_get::<Vec<u8>>("", "metadata")? == bytes,
            "canonical atom phase changed for {} ({phase}); original fact preserved",
            atom.id
        );
        return Ok(());
    }
    db.execute_raw(statement("INSERT INTO conversation_atom_facts(effect_seq,suborder,atom_id,phase,fact_order,metadata) VALUES(?,?,?,?,?,?)",vec![integer(at.map_or(fallback,|at|at.effect_seq))?.into(),i64::from(at.map_or(0,|at|at.suborder)).into(),atom.id.clone().into(),phase.into(),integer(atom.source_order.or(atom.completion_seq).unwrap_or(0))?.into(),bytes.into()])).await?;
    Ok(())
}
async fn save_update(
    db: &impl ConnectionTrait,
    database: &str,
    update: &TimelineUpdate,
    committed: &[PreparedTimelineItem],
    effect: u64,
    facts: bool,
) -> Result<()> {
    if facts {
        for atom in update.facts() {
            save_fact(db, atom, effect).await?;
        }
    }
    for member in update.members() {
        let bytes = serde_json::to_vec(&member.atom)?;
        let written = db.execute_raw(statement("INSERT INTO timeline_item_members(item_id,member_order,member_id,completion_item_id,admitted_effect,metadata) VALUES(?,?,?,?,?,?) ON CONFLICT(item_id,member_order) DO UPDATE SET completion_item_id=excluded.completion_item_id,metadata=excluded.metadata WHERE timeline_item_members.member_id=excluded.member_id AND (timeline_item_members.completion_item_id IS NULL OR timeline_item_members.completion_item_id=excluded.completion_item_id)",vec![member.item_id.clone().into(),integer(member.member_order)?.into(),member.atom.id.clone().into(),member.atom.completion_item_id.clone().into(),integer(effect)?.into(),bytes.into()])).await?;
        ensure!(
            written.rows_affected() == 1,
            "timeline member identity/completion conflict"
        );
    }
    for item in update.current() {
        save_item(db, database, item, effect).await?;
    }
    for entry in committed {
        save_item(db, database, &entry.item, effect).await?;
    }
    // Empty text remains a boundary in the source facts, not an empty display row.
    db.execute_raw(statement("DELETE FROM timeline_items WHERE location='current' AND item_id NOT IN (SELECT value FROM json_each(?))",vec![serde_json::to_string(&update.current().iter().map(|item| &item.id).collect::<Vec<_>>())?.into()])).await?;
    db.execute_raw(statement("INSERT INTO timeline_projection_state(singleton_id,projection_version,next_position,source_effect_seq,projection_generation,recovery) VALUES(1,?,?,?,?,?) ON CONFLICT(singleton_id) DO UPDATE SET projection_version=excluded.projection_version,next_position=excluded.next_position,source_effect_seq=excluded.source_effect_seq,projection_generation=excluded.projection_generation,recovery=excluded.recovery",vec![i64::from(TIMELINE_PROJECTION_VERSION).into(),integer(update.next_position())?.into(),integer(effect)?.into(),update.generation().to_owned().into(),update.recovery().to_vec().into()])).await?;
    Ok(())
}
pub(in super::super) async fn apply(
    db: &impl ConnectionTrait,
    database: &str,
    current: &PreparedCurrent,
) -> Result<()> {
    ensure!(
        current.timeline.is_empty()
            || current.timeline_commit == current.projection().source_effect_seq,
        "timeline publication is not bound to its source effect"
    );
    if current.timeline_update.generation().is_empty() {
        ensure!(
            current.timeline.is_empty()
                && current.timeline_update.facts().is_empty()
                && current.timeline_update.members().is_empty(),
            "unqualified derived write"
        );
        return Ok(());
    }
    ensure!(
        generation(db).await? == current.timeline_update.generation(),
        "retired timeline generation cannot write"
    );
    let mut expected = next_position(db).await?;
    for entry in current.timeline.iter() {
        ensure!(
            entry.item.position == Some(expected),
            "timeline history prefix is not contiguous"
        );
        expected = expected.checked_add(1).context("timeline order overflow")?;
    }
    ensure!(
        current.timeline_update.next_position() == expected,
        "timeline recovery order differs from history prefix"
    );
    save_update(
        db,
        database,
        &current.timeline_update,
        &current.timeline,
        current.projection().source_effect_seq,
        true,
    )
    .await
}
pub(in super::super) async fn verify(
    db: &impl ConnectionTrait,
    database: &str,
    current: &PreparedCurrent,
) -> Result<()> {
    for entry in current.timeline.iter() {
        let row = db
            .query_one_raw(statement(
                "SELECT metadata FROM timeline_items WHERE item_id=? AND location='history'",
                vec![entry.item.id.clone().into()],
            ))
            .await?
            .context("retried timeline item missing")?;
        ensure!(
            row.try_get::<Vec<u8>>("", "metadata")?
                == serde_json::to_vec(&deferred_item(database, &entry.item))?,
            "retried timeline item differs"
        );
    }
    for atom in current.timeline_update.facts() {
        let phase = if matches!(atom.lifecycle, ChatAtomLifecycle::Active { .. }) {
            "start"
        } else {
            "terminal"
        };
        let row = db
            .query_one_raw(statement(
                "SELECT metadata FROM conversation_atom_facts WHERE atom_id=? AND phase=?",
                vec![atom.id.clone().into(), phase.into()],
            ))
            .await?
            .context("retried canonical atom fact missing")?;
        ensure!(
            row.try_get::<Vec<u8>>("", "metadata")? == serde_json::to_vec(&lightweight(atom))?,
            "retried canonical atom fact differs"
        );
    }
    for member in current.timeline_update.members() {
        if let Some(completion) = &member.atom.completion_item_id {
            let row = db.query_one_raw(statement(
                "SELECT member_id,completion_item_id FROM timeline_item_members WHERE item_id=? AND member_order=?",
                vec![member.item_id.clone().into(), integer(member.member_order)?.into()],
            )).await?.context("retried terminal member missing")?;
            ensure!(
                row.try_get::<String>("", "member_id")? == member.atom.id
                    && row.try_get::<String>("", "completion_item_id")? == *completion,
                "retried terminal member differs"
            );
        }
    }
    Ok(())
}
/// Formal one-time preparation of legacy metadata. No payload/body/media is read.
/// Unknown positions remain unknown in metadata; completion seq is only the
/// deterministic admission fallback, never represented as a real source position.
pub(in super::super) async fn normalize_legacy(db: &impl ConnectionTrait) -> Result<()> {
    let mut after = 0i64;
    loop {
        let rows = db.query_all_raw(statement("SELECT seq,metadata FROM conversation_items WHERE query_class<>'diagnostic' AND seq>? ORDER BY seq LIMIT 128",vec![after.into()])).await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            after = row.try_get("", "seq")?;
            let mut atom: ChatAtom =
                serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
            atom.completion_seq = Some(u64::try_from(after)?);
            let started = match atom.lifecycle {
                ChatAtomLifecycle::Terminal { started, .. }
                | ChatAtomLifecycle::Active { started, .. } => started,
            };
            if started.is_none()
                && matches!(atom.source, ChatSourceId::ForegroundTurn { .. })
                && let Some(order) = atom.source_order
            {
                // The frozen ordinal proves structural admission, not a start.
                // Retain the original terminal metadata under an explicit
                // normalization phase, never invent a started position/time.
                db.execute_raw(statement(
                    "INSERT INTO conversation_atom_facts(effect_seq,suborder,atom_id,phase,fact_order,metadata)
                     VALUES(0,0,?,'legacyAdmission',?,?)",
                    vec![atom.id.clone().into(),integer(order)?.into(),serde_json::to_vec(&lightweight(&atom))?.into()],
                )).await?;
            }
            if let Some(started) = started {
                let mut active = lightweight(&atom);
                active.lifecycle = ChatAtomLifecycle::Active {
                    started: Some(started),
                    status: ChatActiveStatus::Running,
                };
                active.completion_item_id = None;
                active.completion_seq = None;
                active.finished_at = None;
                active.contents.clear();
                save_fact(db, &active, 0).await?;
            } else if atom.source_order.is_none()
                && !matches!(atom.kind, ChatAtomKind::Text | ChatAtomKind::Input)
            {
                atom.delivery = ChatDeliveryKind::Independent;
            }
            save_fact(db, &atom, 0).await?;
            if matches!(
                atom.lifecycle,
                ChatAtomLifecycle::Terminal { ended: None, .. }
            ) {
                let start = match atom.lifecycle {
                    ChatAtomLifecycle::Terminal { started, .. } => started,
                    _ => None,
                };
                db.execute_raw(statement(
                    "UPDATE conversation_atom_facts SET effect_seq=?,suborder=?,fact_order=? WHERE atom_id=? AND phase='terminal'",
                    vec![integer(start.map_or(0,|at|at.effect_seq))?.into(),
                        i64::from(if start.is_some() { u32::MAX } else { 1 }).into(),after.into(),atom.id.clone().into()],
                )).await?;
            }
        }
    }
    let current = super::current::read(db).await?;
    for atom in &current.atoms {
        if let ChatAtomLifecycle::Active { started, .. } = atom.lifecycle {
            if started.is_some() {
                save_fact(db, atom, current.source_effect_seq).await?;
            } else {
                db.execute_raw(statement("INSERT INTO conversation_atom_facts(effect_seq,suborder,atom_id,phase,fact_order,metadata) VALUES(0,0,?,'legacyAdmission',?,?)",
                    vec![atom.id.clone().into(),integer(atom.source_order.unwrap_or(0))?.into(),serde_json::to_vec(&lightweight(atom))?.into()])).await?;
            }
        }
    }
    // This is a one-time ordering normalization, not fabricated source events.
    // Pair each wholly unknown completed member's admission/terminal instead of
    // keeping every old member active until the whole database has been read.
    // Source-prefix MAX completion order respects known ordinals even when a
    // later text completed first; independent results retain completion order.
    // Known start/terminal positions are never updated by this statement.
    db.execute_unprepared("
      WITH atoms AS (
        SELECT atom_id,metadata FROM conversation_atom_facts f WHERE phase='terminal'
          OR (phase='start' AND NOT EXISTS(SELECT 1 FROM conversation_atom_facts t WHERE t.atom_id=f.atom_id AND t.phase='terminal'))
          OR (phase='legacyAdmission' AND json_extract(metadata,'$.lifecycle.kind')='active')
      ), ordered AS (
        SELECT atom_id,metadata,
          COALESCE(json_extract(metadata,'$.completionSeq'),0) AS completion,
          COALESCE(json_extract(metadata,'$.sourceOrder'),json_extract(metadata,'$.completionSeq'),0) AS ordinal,
          CASE WHEN json_extract(metadata,'$.source.kind')='foregroundTurn' AND json_extract(metadata,'$.sourceOrder') IS NOT NULL
            THEN json_extract(metadata,'$.source') ELSE atom_id END AS source,
          CASE WHEN json_extract(metadata,'$.lifecycle.ended') IS NOT NULL OR json_extract(metadata,'$.lifecycle.started') IS NOT NULL
            THEN printf('%020d:%010d',COALESCE(json_extract(metadata,'$.lifecycle.ended.effectSeq'),json_extract(metadata,'$.lifecycle.started.effectSeq')),
              COALESCE(json_extract(metadata,'$.lifecycle.ended.suborder'),json_extract(metadata,'$.lifecycle.started.suborder'))) END AS known,
          CASE WHEN json_extract(metadata,'$.lifecycle.ended') IS NOT NULL
            THEN printf('%020d:%010d',json_extract(metadata,'$.lifecycle.ended.effectSeq'),json_extract(metadata,'$.lifecycle.ended.suborder')) END AS known_end
        FROM atoms
      ), windows AS (
        SELECT atom_id,ordinal,
          MAX(completion) OVER(PARTITION BY source ORDER BY ordinal,completion,atom_id ROWS UNBOUNDED PRECEDING) AS slot,
          COALESCE(MAX(known) OVER(PARTITION BY source ORDER BY ordinal,completion,atom_id ROWS UNBOUNDED PRECEDING),'00000000000000000000:0000000000') AS floor,
          MIN(known_end) OVER(PARTITION BY source ORDER BY ordinal,completion,atom_id ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) AS suffix_end
        FROM ordered
      ), normalized AS (
        SELECT f.atom_id,f.phase,w.slot,w.ordinal,
          CASE WHEN f.phase='legacyAdmission' AND json_extract(f.metadata,'$.lifecycle.ended') IS NOT NULL
            THEN w.suffix_end ELSE w.floor END AS anchor
        FROM conversation_atom_facts f JOIN windows w ON f.atom_id=w.atom_id
        WHERE f.phase='legacyAdmission' OR (f.phase='terminal'
          AND json_extract(f.metadata,'$.lifecycle.started') IS NULL AND json_extract(f.metadata,'$.lifecycle.ended') IS NULL)
      )
      UPDATE conversation_atom_facts AS f SET
        effect_seq=(SELECT CAST(substr(anchor,1,20) AS INTEGER) FROM normalized n WHERE n.atom_id=f.atom_id AND n.phase=f.phase),
        suborder=(SELECT CAST(substr(anchor,22,10) AS INTEGER) FROM normalized n WHERE n.atom_id=f.atom_id AND n.phase=f.phase),
        fact_order=(SELECT CASE WHEN substr(anchor,1,20)='00000000000000000000' THEN slot ELSE ordinal END FROM normalized n WHERE n.atom_id=f.atom_id AND n.phase=f.phase)
      WHERE EXISTS(SELECT 1 FROM normalized n WHERE n.atom_id=f.atom_id AND n.phase=f.phase);
    ").await?;
    // Only an old source with no known end position and wholly normalized atoms
    // needs this explicit legacy boundary. The canonical source row is untouched.
    db.execute_unprepared("
      INSERT INTO conversation_atom_facts(effect_seq,suborder,atom_id,phase,fact_order,metadata)
      SELECT 0,0,'legacy-source:'||s.source_key,'legacySourceEnd',MAX(f.fact_order),CAST(s.source_key AS BLOB)
      FROM conversation_sources s JOIN conversation_atom_facts f ON json_extract(f.metadata,'$.source')=s.source_key
      WHERE s.ended_observed IS NOT NULL AND s.ended_effect IS NULL
      GROUP BY s.source_key HAVING MAX(f.effect_seq)=0;
    ").await?;
    Ok(())
}
/// Caller owns the sole writer's durable maintenance boundary and a transaction.
/// SQL merges indexed tiny source facts; only one bounded batch and the small
/// active accumulator exist in RAM. Rollback preserves old derived rows and facts.
pub(in crate::studio) async fn rebuild(
    db: &impl ConnectionTrait,
    database: &str,
) -> Result<String> {
    rebuild_batched(db, database, 128).await
}
pub(in crate::studio) async fn rebuild_batched(
    db: &impl ConnectionTrait,
    database: &str,
    batch_size: usize,
) -> Result<String> {
    ensure!(
        (1..=128).contains(&batch_size),
        "timeline replay batch is outside its bounded window"
    );
    let mut current: CurrentProjection = super::current::read(db).await?;
    db.execute_unprepared("DELETE FROM timeline_item_members; DELETE FROM timeline_items;")
        .await?;
    let candidate = uuid::Uuid::new_v4().to_string();
    let mut projection = TimelineProjection::new(database.into(), candidate.clone(), 0);
    let mut cursor = (-1i64, -1i64, -1i64, -1i64, String::new(), String::new());
    let mut previous_effect = None;
    loop {
        let rows = db.query_all_raw(statement("SELECT effect,sub,ordering,completion_order,identity,phase,metadata,source_key FROM (
          SELECT effect_seq AS effect,suborder AS sub,fact_order AS ordering,CASE WHEN phase='legacySourceEnd' THEN 9223372036854775807 WHEN effect_seq=0 THEN COALESCE(json_extract(metadata,'$.sourceOrder'),json_extract(metadata,'$.completionSeq'),0) ELSE COALESCE(json_extract(metadata,'$.completionSeq'),0) END AS completion_order,atom_id AS identity,phase,metadata,CASE WHEN phase='legacySourceEnd' THEN CAST(metadata AS TEXT) END AS source_key FROM conversation_atom_facts
          UNION ALL SELECT COALESCE(ended_effect,ended_observed),COALESCE(ended_suborder,4294967295),9223372036854775807,0,source_key,'source',NULL,source_key FROM conversation_sources s WHERE ended_observed IS NOT NULL AND NOT EXISTS(SELECT 1 FROM conversation_atom_facts f WHERE f.atom_id='legacy-source:'||s.source_key AND f.phase='legacySourceEnd')
        ) WHERE (effect,sub,ordering,completion_order,identity,phase)>(?,?,?,?,?,?) ORDER BY effect,sub,ordering,completion_order,identity,phase LIMIT ?",vec![cursor.0.into(),cursor.1.into(),cursor.2.into(),cursor.3.into(),cursor.4.clone().into(),cursor.5.clone().into(),i64::try_from(batch_size)?.into()])).await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let effect: i64 = row.try_get("", "effect")?;
            if previous_effect.is_some_and(|old| old != effect) {
                drain_rebuild(db, database, &mut projection, current.source_effect_seq).await?;
            }
            previous_effect = Some(effect);
            cursor = (
                effect,
                row.try_get("", "sub")?,
                row.try_get("", "ordering")?,
                row.try_get("", "completion_order")?,
                row.try_get("", "identity")?,
                row.try_get("", "phase")?,
            );
            if let Some(source) = row.try_get::<Option<String>>("", "source_key")? {
                projection.end_source(&serde_json::from_str::<ChatSourceId>(&source)?);
            } else {
                let mut atom: ChatAtom =
                    serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
                if row.try_get::<String>("", "phase")? == "legacyAdmission" {
                    projection.admit_legacy_header(&atom)?;
                } else if matches!(atom.lifecycle, ChatAtomLifecycle::Active { .. }) {
                    projection.observe(&atom, None)?;
                } else {
                    let seq = atom.completion_seq.unwrap_or(0);
                    if matches!(atom.lifecycle,ChatAtomLifecycle::Terminal {started:None,..})
                        && let Some(member)=db.query_one_raw(statement(
                            "SELECT item_id,member_order FROM timeline_item_members WHERE member_id=? AND completion_item_id IS NULL LIMIT 1",
                            vec![atom.id.clone().into()])).await? {
                        projection.restore_legacy_member(member.try_get("","item_id")?,u64::try_from(member.try_get::<i64>("","member_order")?)?,&atom)?;
                    }
                    // Payload stays in the original completion. Its length is a
                    // metadata-only indexed lookup, never a body read.
                    let payload = if let Some(id) = &atom.completion_item_id {
                        let row=db.query_one_raw(statement("SELECT length(payload) AS bytes FROM conversation_items WHERE item_id=?",vec![id.clone().into()])).await?.context("atom completion reference missing")?;
                        Some(PayloadData::Deferred {
                            reference: ContentRef {
                                database_id: database.into(),
                                target: ContentTarget::ItemPayload {
                                    item_id: id.clone(),
                                },
                            },
                            byte_length: u64::try_from(row.try_get::<i64>("", "bytes")?)?,
                        })
                    } else {
                        None
                    };
                    atom.payload = None;
                    projection.complete(atom, seq, payload)?;
                }
            }
            drain_rebuild(db, database, &mut projection, current.source_effect_seq).await?;
        }
    }
    for atom in &current.atoms {
        if matches!(atom.lifecycle, ChatAtomLifecycle::Active { .. }) {
            projection.refresh_current(atom)?;
        }
    }
    drain_rebuild(db, database, &mut projection, current.source_effect_seq).await?;
    let mut restored =
        TimelineProjection::new(database.into(), candidate.clone(), next_position(db).await?);
    restored.restore_recovery(&recovery(db).await?)?;
    current.items = projection.current_items();
    let bytes = serde_json::to_vec(&current)?;
    ensure!(
        bytes.len() <= pl_protocol::CHAT_BATCH_MAX_BYTES as usize,
        "rebuilt current exceeds budget"
    );
    db.execute_raw(statement(
        "UPDATE conversation_view_state SET payload=? WHERE singleton_id=1",
        vec![bytes.into()],
    ))
    .await?;
    Ok(candidate)
}
async fn drain_rebuild(
    db: &impl ConnectionTrait,
    database: &str,
    projection: &mut TimelineProjection,
    effect: u64,
) -> Result<()> {
    projection.commit_ready()?;
    let committed: Vec<_> = projection
        .take_committed()
        .into_iter()
        .map(|item| PreparedTimelineItem { item })
        .collect();
    let update = projection.take_update()?;
    save_update(db, database, &update, &committed, effect, false).await
}

pub(in crate::studio) async fn validate_members_ref(
    db: &impl ConnectionTrait,
    database: &str,
    reference: &TimelineMembersRef,
) -> Result<()> {
    ensure!(
        reference.database_id == database
            && reference.projection_version == TIMELINE_PROJECTION_VERSION,
        pl_core::chat::ChatError::StaleContent
    );
    next_position(db).await?;
    ensure!(
        generation(db).await? == reference.projection_generation,
        pl_core::chat::ChatError::StaleContent
    );
    ensure!(db.query_one_raw(statement("SELECT 1 FROM timeline_items WHERE item_id=? AND kind='workGroup' AND projection_version=?",vec![reference.item_id.clone().into(),i64::from(reference.projection_version).into()])).await?.is_some(),pl_core::chat::ChatError::StaleContent);
    Ok(())
}
pub(in crate::studio) fn entry_bytes(entry: &pl_protocol::ChatEntry) -> Result<usize> {
    let mut entry = entry.clone();
    if let pl_protocol::ChatEntry::Atom(atom) = &mut entry {
        let at = Some(pl_protocol::ChatFactPosition {
            effect_seq: u64::MAX,
            suborder: u32::MAX,
        });
        atom.source_state = Some(pl_protocol::ChatSourceState {
            source: atom.source.clone(),
            lifecycle: pl_protocol::ChatSourceLifecycle::Ended {
                outcome: pl_protocol::ChatTerminalOutcome::Transferred,
            },
            started: at,
            ended: at,
        });
    }
    Ok(serde_json::to_vec(&entry)?.len() + 1)
}
/// Header-only upper bound, using the same four-byte JSON byte-array expansion
/// as JsonBudget. The original completion owner is read only after this fits.
pub(in crate::studio) fn inline_entry_bytes(
    entry: &pl_protocol::ChatEntry,
) -> Result<Option<usize>> {
    let pl_protocol::ChatEntry::Item(item) = entry else {
        return Ok(None);
    };
    if item.is_work_group() {
        return Ok(None);
    }
    let Some(PayloadData::Deferred { byte_length, .. }) = &item.payload else {
        return Ok(None);
    };
    if *byte_length > u64::from(pl_protocol::CONTENT_WINDOW_MAX_BYTES) {
        return Ok(None);
    }
    let mut inline = item.as_ref().clone();
    inline.payload = Some(PayloadData::Inline { bytes: Vec::new() });
    Ok(Some(
        serde_json::to_vec(&pl_protocol::ChatEntry::Item(Box::new(inline)))?
            .len()
            .saturating_add(1)
            .saturating_add((*byte_length as usize).saturating_mul(4)),
    ))
}
/// Prefer a transport-inline envelope; if it cannot fit, keep this same item
/// deferred rather than skipping it for an older row.
pub(in crate::studio) fn delivery_entry_bytes(
    entry: &pl_protocol::ChatEntry,
    remaining: usize,
) -> Result<usize> {
    if let Some(inline) = inline_entry_bytes(entry)?
        && inline <= remaining
    {
        return Ok(inline);
    }
    entry_bytes(entry)
}
/// Descending lightweight item/member metadata. No aggregate, member scan or payload read on Main.
pub(in crate::studio) async fn page_rows(
    db: &impl ConnectionTrait,
    scope: &pl_protocol::ChatScope,
    before: Option<u64>,
    ceiling: u64,
    effect_cut: u64,
    limit: usize,
) -> Result<Vec<(u64, pl_protocol::ChatEntry)>> {
    let (sql, values) = match scope {
        pl_protocol::ChatScope::Main => (
            "SELECT position AS ordering,item_id,kind,projection_version,metadata FROM timeline_items WHERE location='history' AND position<? AND position<? AND commit_seq<=? ORDER BY position DESC LIMIT ?",
            vec![
                integer(before.unwrap_or(ceiling))?.into(),
                integer(ceiling)?.into(),
                integer(effect_cut)?.into(),
                i64::try_from(limit)?.into(),
            ],
        ),
        pl_protocol::ChatScope::GroupMembers { reference } => (
            "SELECT member_order AS ordering,metadata FROM timeline_item_members WHERE item_id=? AND member_order<? AND member_order<? AND admitted_effect<=? ORDER BY member_order DESC LIMIT ?",
            vec![
                reference.item_id.clone().into(),
                integer(before.unwrap_or(ceiling))?.into(),
                integer(ceiling)?.into(),
                integer(effect_cut)?.into(),
                i64::try_from(limit)?.into(),
            ],
        ),
        pl_protocol::ChatScope::Children { .. } => {
            anyhow::bail!("business children use the original atomic reader")
        }
    };
    let mut result = Vec::new();
    for row in db.query_all_raw(statement(sql, values)).await? {
        let bytes: Vec<u8> = row.try_get("", "metadata")?;
        let entry = if matches!(scope, pl_protocol::ChatScope::Main) {
            let item: TimelineItem = serde_json::from_slice(&bytes)?;
            ensure!(
                item.id == row.try_get::<String>("", "item_id")?
                    && item.kind.as_str() == row.try_get::<String>("", "kind")?
                    && item.position == Some(u64::try_from(row.try_get::<i64>("", "ordering")?)?)
                    && item.admission_closed
                    && row.try_get::<i64>("", "projection_version")?
                        == i64::from(TIMELINE_PROJECTION_VERSION),
                ProjectionFault
            );
            pl_protocol::ChatEntry::Item(Box::new(item))
        } else {
            let mut atom: ChatAtom = serde_json::from_slice(&bytes)?;
            let fact=db.query_one_raw(statement("SELECT metadata FROM conversation_atom_facts WHERE atom_id=? AND effect_seq<=? AND phase IN ('start','terminal','legacyAdmission') ORDER BY CASE phase WHEN 'terminal' THEN 0 ELSE 1 END LIMIT 1",vec![atom.id.clone().into(),integer(effect_cut)?.into()])).await?.context("member has no source fact at the captured cut")?;
            atom = serde_json::from_slice(&fact.try_get::<Vec<u8>>("", "metadata")?)?;
            if let Some(id) = &atom.completion_item_id {
                let payload = db
                    .query_one_raw(statement(
                        "SELECT length(payload) AS bytes FROM conversation_items WHERE item_id=?",
                        vec![id.clone().into()],
                    ))
                    .await?
                    .context("member completion missing")?;
                atom.payload = Some(PayloadData::Deferred {
                    reference: ContentRef {
                        database_id: match scope {
                            pl_protocol::ChatScope::GroupMembers { reference } => {
                                reference.database_id.clone()
                            }
                            _ => unreachable!(),
                        },
                        target: ContentTarget::ItemPayload {
                            item_id: id.clone(),
                        },
                    },
                    byte_length: u64::try_from(payload.try_get::<i64>("", "bytes")?)?,
                });
            }
            pl_protocol::ChatEntry::Atom(Box::new(atom))
        };
        result.push((u64::try_from(row.try_get::<i64>("", "ordering")?)?, entry));
    }
    Ok(result)
}
