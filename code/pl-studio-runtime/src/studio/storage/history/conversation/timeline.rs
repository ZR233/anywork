//! Rebuildable, metadata-only display index, written by the original effect transaction.
#[cfg(test)]
#[path = "timeline/tests.rs"]
mod tests;
use super::*;
use super::current::{PreparedCurrent, PreparedTimelineItem};
use crate::studio::thread_projection::{TimelineProjection, timeline::{TimelineUpdate, lightweight}};
use pl_protocol::{ChatAtom, ChatAtomKind, ChatAtomLifecycle, ChatActiveStatus, ChatSourceId, ChatDeliveryKind, CurrentProjection, PayloadData, ContentRef, ContentTarget, TimelineItem, TimelineMembersRef, TIMELINE_PROJECTION_VERSION};

pub(in super::super) const CREATE_SCHEMA: &str = "
CREATE TABLE conversation_atom_facts (
 effect_seq INTEGER NOT NULL, suborder INTEGER NOT NULL, atom_id TEXT NOT NULL,
 phase TEXT NOT NULL, fact_order INTEGER NOT NULL, metadata BLOB NOT NULL,
 PRIMARY KEY(effect_seq,suborder,atom_id,phase), UNIQUE(atom_id,phase)
) WITHOUT ROWID;
CREATE INDEX conversation_atom_facts_by_admission ON conversation_atom_facts(effect_seq,suborder,fact_order,atom_id,phase);
CREATE INDEX conversation_sources_by_timeline_end ON conversation_sources(ended_observed,source_key);
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
 next_position INTEGER NOT NULL, source_effect_seq INTEGER NOT NULL, recovery BLOB NOT NULL
);
";
pub(in super::super) async fn validate_tables(db: &impl ConnectionTrait) -> Result<()> {
    for sql in [
        "SELECT effect_seq,suborder,atom_id,phase,fact_order,metadata FROM conversation_atom_facts LIMIT 0",
        "SELECT item_id,kind,location,position,commit_seq,metadata,projection_version FROM timeline_items LIMIT 0",
        "SELECT item_id,member_order,member_id,completion_item_id,admitted_effect,metadata FROM timeline_item_members LIMIT 0",
        "SELECT projection_version,next_position,source_effect_seq,recovery FROM timeline_projection_state LIMIT 0",
    ] { db.query_all_raw(statement(sql, vec![])).await.context("timeline projection requires explicit maintenance; original facts preserved")?; }
    Ok(())
}
pub(in super::super) async fn state(db: &impl ConnectionTrait) -> Result<Option<(u32,u64)>> {
    let row = db.query_one_raw(statement("SELECT projection_version,next_position FROM timeline_projection_state WHERE singleton_id=1",vec![])).await?;
    row.map(|row| Ok((u32::try_from(row.try_get::<i64>("","projection_version")?)?,u64::try_from(row.try_get::<i64>("","next_position")?)?))).transpose()
}
pub(in super::super) async fn next_position(db: &impl ConnectionTrait) -> Result<u64> {
    let (version,next) = state(db).await?.context("timeline recovery is missing; maintenance required")?;
    ensure!(version == TIMELINE_PROJECTION_VERSION,"timeline projection version requires maintenance");
    Ok(next)
}
pub(in super::super) async fn recovery(db: &impl ConnectionTrait) -> Result<Vec<u8>> {
    next_position(db).await?;
    Ok(db.query_one_raw(statement("SELECT recovery FROM timeline_projection_state WHERE singleton_id=1",vec![])).await?.context("timeline recovery missing")?.try_get("","recovery")?)
}
pub(in crate::studio) fn deferred_item(database: &str, item: &TimelineItem) -> TimelineItem {
    let mut value = item.clone();
    if let Some(PayloadData::Inline { bytes }) = &item.payload {
        value.payload = Some(PayloadData::Deferred { reference: ContentRef { database_id: database.into(), target: ContentTarget::ItemPayload { item_id: item.content_item_id.clone().unwrap_or_else(|| item.id.clone()) } }, byte_length: bytes.len() as u64 });
    }
    value
}
async fn save_item(db: &impl ConnectionTrait, database: &str, item: &TimelineItem, effect: u64) -> Result<()> {
    let item = deferred_item(database,item);
    let bytes = serde_json::to_vec(&item)?;
    let old = db.query_one_raw(statement("SELECT location,metadata,position FROM timeline_items WHERE item_id=?",vec![item.id.clone().into()])).await?;
    if let Some(old) = old {
        if old.try_get::<String>("","location")? == "history" {
            ensure!(old.try_get::<Vec<u8>>("","metadata")? == bytes,"immutable timeline item conflict");
            return Ok(());
        }
    }
    db.execute_raw(statement("INSERT INTO timeline_items(item_id,kind,location,position,commit_seq,metadata,projection_version) VALUES(?,?,?,?,?,?,?) ON CONFLICT(item_id) DO UPDATE SET location=excluded.location,position=excluded.position,commit_seq=excluded.commit_seq,metadata=excluded.metadata,projection_version=excluded.projection_version",vec![item.id.clone().into(),item.kind.as_str().into(),if item.position.is_some(){"history"}else{"current"}.into(),item.position.map(integer).transpose()?.into(),item.position.map(|_| integer(effect)).transpose()?.into(),bytes.into(),i64::from(TIMELINE_PROJECTION_VERSION).into()])).await?;
    Ok(())
}
async fn save_fact(db: &impl ConnectionTrait, atom: &ChatAtom, fallback: u64) -> Result<()> {
    let (at, phase) = match atom.lifecycle {
        ChatAtomLifecycle::Active { started,.. } => (started,"start"),
        ChatAtomLifecycle::Terminal { ended,.. } => (ended,"terminal"),
    };
    let bytes = serde_json::to_vec(&lightweight(atom))?;
    let old = db.query_one_raw(statement("SELECT metadata FROM conversation_atom_facts WHERE atom_id=? AND phase=?",vec![atom.id.clone().into(),phase.into()])).await?;
    if let Some(old) = old { ensure!(old.try_get::<Vec<u8>>("","metadata")? == bytes,"canonical atom phase changed"); return Ok(()); }
    db.execute_raw(statement("INSERT INTO conversation_atom_facts(effect_seq,suborder,atom_id,phase,fact_order,metadata) VALUES(?,?,?,?,?,?)",vec![integer(at.map_or(fallback,|at|at.effect_seq))?.into(),i64::from(at.map_or(0,|at|at.suborder)).into(),atom.id.clone().into(),phase.into(),integer(atom.source_order.or(atom.completion_seq).unwrap_or(0))?.into(),bytes.into()])).await?;
    Ok(())
}
async fn save_update(db: &impl ConnectionTrait, database: &str, update: &TimelineUpdate, committed: &[PreparedTimelineItem], effect: u64, facts: bool) -> Result<()> {
    if facts { for atom in &update.facts { save_fact(db,atom,effect).await?; } }
    for member in &update.members {
        let bytes = serde_json::to_vec(&member.atom)?;
        let written = db.execute_raw(statement("INSERT INTO timeline_item_members(item_id,member_order,member_id,completion_item_id,admitted_effect,metadata) VALUES(?,?,?,?,?,?) ON CONFLICT(item_id,member_order) DO UPDATE SET completion_item_id=excluded.completion_item_id,metadata=excluded.metadata WHERE timeline_item_members.member_id=excluded.member_id AND (timeline_item_members.completion_item_id IS NULL OR timeline_item_members.completion_item_id=excluded.completion_item_id)",vec![member.item_id.clone().into(),integer(member.member_order)?.into(),member.atom.id.clone().into(),member.atom.completion_item_id.clone().into(),integer(effect)?.into(),bytes.into()])).await?;
        ensure!(written.rows_affected() == 1, "timeline member identity/completion conflict");
    }
    for item in &update.current { save_item(db,database,item,effect).await?; }
    for entry in committed { save_item(db,database,&entry.item,effect).await?; }
    // Empty text remains a boundary in the source facts, not an empty display row.
    db.execute_raw(statement("DELETE FROM timeline_items WHERE location='current' AND item_id NOT IN (SELECT value FROM json_each(?))",vec![serde_json::to_string(&update.current.iter().map(|item| &item.id).collect::<Vec<_>>())?.into()])).await?;
    db.execute_raw(statement("INSERT INTO timeline_projection_state(singleton_id,projection_version,next_position,source_effect_seq,recovery) VALUES(1,?,?,?,?) ON CONFLICT(singleton_id) DO UPDATE SET projection_version=excluded.projection_version,next_position=excluded.next_position,source_effect_seq=excluded.source_effect_seq,recovery=excluded.recovery",vec![i64::from(TIMELINE_PROJECTION_VERSION).into(),integer(update.next_position)?.into(),integer(effect)?.into(),update.recovery.clone().into()])).await?;
    Ok(())
}
pub(in super::super) async fn apply(db: &impl ConnectionTrait, database: &str, current: &PreparedCurrent) -> Result<()> {
    ensure!(current.timeline.is_empty() || current.timeline_commit == current.projection.source_effect_seq,
        "timeline publication is not bound to its source effect");
    let mut expected = next_position(db).await?;
    for entry in current.timeline.iter() {
        ensure!(entry.item.position == Some(expected), "timeline history prefix is not contiguous");
        expected = expected.checked_add(1).context("timeline order overflow")?;
    }
    ensure!(current.timeline_update.next_position == expected, "timeline recovery order differs from history prefix");
    save_update(db,database,&current.timeline_update,&current.timeline,current.projection.source_effect_seq,true).await
}
pub(in super::super) async fn verify(db: &impl ConnectionTrait, database: &str, current: &PreparedCurrent) -> Result<()> {
    for entry in current.timeline.iter() {
        let row = db.query_one_raw(statement("SELECT metadata FROM timeline_items WHERE item_id=? AND location='history'",vec![entry.item.id.clone().into()])).await?.context("retried timeline item missing")?;
        ensure!(row.try_get::<Vec<u8>>("","metadata")? == serde_json::to_vec(&deferred_item(database,&entry.item))?,"retried timeline item differs");
    }
    for atom in &current.timeline_update.facts {
        let phase = if matches!(atom.lifecycle,ChatAtomLifecycle::Active{..}) {"start"} else {"terminal"};
        let row = db.query_one_raw(statement("SELECT metadata FROM conversation_atom_facts WHERE atom_id=? AND phase=?",vec![atom.id.clone().into(),phase.into()])).await?.context("retried canonical atom fact missing")?;
        ensure!(row.try_get::<Vec<u8>>("","metadata")? == serde_json::to_vec(&lightweight(atom))?,"retried canonical atom fact differs");
    }
    for member in &current.timeline_update.members {
        if let Some(completion) = &member.atom.completion_item_id {
            let row = db.query_one_raw(statement(
                "SELECT member_id,completion_item_id FROM timeline_item_members WHERE item_id=? AND member_order=?",
                vec![member.item_id.clone().into(), integer(member.member_order)?.into()],
            )).await?.context("retried terminal member missing")?;
            ensure!(row.try_get::<String>("", "member_id")? == member.atom.id
                && row.try_get::<String>("", "completion_item_id")? == *completion,
                "retried terminal member differs");
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
        if rows.is_empty(){break;}
        for row in rows {
            after = row.try_get("","seq")?;
            let mut atom: ChatAtom = serde_json::from_slice(&row.try_get::<Vec<u8>>("","metadata")?)?;
            atom.completion_seq = Some(u64::try_from(after)?);
            let started = match atom.lifecycle {ChatAtomLifecycle::Terminal{started,..}|ChatAtomLifecycle::Active{started,..}=>started};
            if let Some(started) = started {
                let mut active = lightweight(&atom);
                active.lifecycle = ChatAtomLifecycle::Active{started:Some(started),status:ChatActiveStatus::Running};
                active.completion_item_id=None;active.completion_seq=None;active.finished_at=None;active.contents.clear();
                save_fact(db,&active,0).await?;
            } else if atom.source_order.is_none() && !matches!(atom.kind,ChatAtomKind::Text|ChatAtomKind::Input) {
                atom.delivery=ChatDeliveryKind::Independent;
            }
            save_fact(db,&atom,0).await?;
        }
    }
    let current = super::current::read(db).await?;
    for atom in &current.atoms { if matches!(atom.lifecycle,ChatAtomLifecycle::Active{..}) {save_fact(db,atom,current.source_effect_seq).await?;} }
    Ok(())
}
/// Caller owns the sole writer's durable maintenance boundary and a transaction.
/// SQL merges indexed tiny source facts; only one bounded batch and the small
/// active accumulator exist in RAM. Rollback preserves old derived rows and facts.
pub(in crate::studio) async fn rebuild(db: &impl ConnectionTrait, database: &str) -> Result<()> {
    let mut current: CurrentProjection = super::current::read(db).await?;
    db.execute_unprepared("DELETE FROM timeline_item_members; DELETE FROM timeline_items;").await?;
    let mut projection = TimelineProjection::new(database.into(),0);
    let mut cursor = (-1i64,-1i64,-1i64,String::new(),String::new());
    let mut previous_effect = None;
    loop {
        let rows = db.query_all_raw(statement("SELECT effect,sub,ordering,identity,phase,metadata,source_key FROM (
          SELECT effect_seq AS effect,suborder AS sub,fact_order AS ordering,atom_id AS identity,phase,metadata,NULL AS source_key FROM conversation_atom_facts
          UNION ALL SELECT ended_observed,4294967295,9223372036854775807,source_key,'source',NULL,source_key FROM conversation_sources WHERE ended_observed IS NOT NULL
        ) WHERE (effect,sub,ordering,identity,phase)>(?,?,?,?,?) ORDER BY effect,sub,ordering,identity,phase LIMIT 128",vec![cursor.0.into(),cursor.1.into(),cursor.2.into(),cursor.3.clone().into(),cursor.4.clone().into()])).await?;
        if rows.is_empty(){break;}
        for row in rows {
            let effect:i64=row.try_get("","effect")?;
            if previous_effect.is_some_and(|old|old!=effect){ drain_rebuild(db,database,&mut projection,current.source_effect_seq).await?; }
            previous_effect=Some(effect);
            cursor=(effect,row.try_get("","sub")?,row.try_get("","ordering")?,row.try_get("","identity")?,row.try_get("","phase")?);
            if let Some(source) = row.try_get::<Option<String>>("","source_key")? {
                projection.end_source(&serde_json::from_str::<ChatSourceId>(&source)?);
            } else {
                let mut atom:ChatAtom=serde_json::from_slice(&row.try_get::<Vec<u8>>("","metadata")?)?;
                if matches!(atom.lifecycle,ChatAtomLifecycle::Active{..}) {projection.observe(&atom,None)?;}
                else {
                    let seq=atom.completion_seq.unwrap_or(0);
                    // Payload stays in the original completion. Its length is a
                    // metadata-only indexed lookup, never a body read.
                    let payload=if let Some(id)=&atom.completion_item_id {
                        let row=db.query_one_raw(statement("SELECT length(payload) AS bytes FROM conversation_items WHERE item_id=?",vec![id.clone().into()])).await?.context("atom completion reference missing")?;
                        Some(PayloadData::Deferred{reference:ContentRef{database_id:database.into(),target:ContentTarget::ItemPayload{item_id:id.clone()}},byte_length:u64::try_from(row.try_get::<i64>("","bytes")?)?})
                    }else{None};
                    atom.payload=None;
                    projection.complete(atom,seq,payload)?;
                }
            }
            drain_rebuild(db,database,&mut projection,current.source_effect_seq).await?;
        }
    }
    drain_rebuild(db,database,&mut projection,current.source_effect_seq).await?;
    current.items=projection.current_items();
    let bytes=serde_json::to_vec(&current)?;
    ensure!(bytes.len()<=pl_protocol::CHAT_BATCH_MAX_BYTES as usize,"rebuilt current exceeds budget");
    db.execute_raw(statement("UPDATE conversation_view_state SET payload=? WHERE singleton_id=1",vec![bytes.into()])).await?;
    Ok(())
}
async fn drain_rebuild(db:&impl ConnectionTrait,database:&str,projection:&mut TimelineProjection,effect:u64)->Result<()> {
    projection.commit_ready()?;
    let committed:Vec<_>=projection.take_committed().into_iter().map(|item|PreparedTimelineItem{item}).collect();
    let update=projection.take_update()?;
    save_update(db,database,&update,&committed,effect,false).await
}

pub(in crate::studio) async fn validate_members_ref(db:&impl ConnectionTrait,database:&str,reference:&TimelineMembersRef)->Result<()> {
    ensure!(reference.database_id==database && reference.projection_version==TIMELINE_PROJECTION_VERSION,pl_core::chat::ChatError::StaleContent);
    next_position(db).await?;
    ensure!(db.query_one_raw(statement("SELECT 1 FROM timeline_items WHERE item_id=? AND kind='workGroup' AND projection_version=?",vec![reference.item_id.clone().into(),i64::from(reference.projection_version).into()])).await?.is_some(),pl_core::chat::ChatError::StaleContent);
    Ok(())
}
pub(in crate::studio) fn entry_bytes(entry: &pl_protocol::ChatEntry) -> Result<usize> {
    let mut entry = entry.clone();
    if let pl_protocol::ChatEntry::Atom(atom) = &mut entry {
        let at = Some(pl_protocol::ChatFactPosition { effect_seq: u64::MAX, suborder: u32::MAX });
        atom.source_state = Some(pl_protocol::ChatSourceState {
            source: atom.source.clone(),
            lifecycle: pl_protocol::ChatSourceLifecycle::Ended { outcome: pl_protocol::ChatTerminalOutcome::Transferred },
            started: at, ended: at,
        });
    }
    Ok(serde_json::to_vec(&entry)?.len() + 1)
}
/// Descending lightweight item/member metadata. No aggregate, member scan or payload read on Main.
pub(in crate::studio) async fn page_rows(db:&impl ConnectionTrait,scope:&pl_protocol::ChatScope,before:Option<u64>,ceiling:u64,effect_cut:u64,limit:usize)->Result<Vec<(u64,pl_protocol::ChatEntry)>> {
    let (sql,values)=match scope {
        pl_protocol::ChatScope::Main=>("SELECT position AS ordering,metadata FROM timeline_items WHERE location='history' AND position<? AND position<? AND commit_seq<=? ORDER BY position DESC LIMIT ?",vec![integer(before.unwrap_or(ceiling))?.into(),integer(ceiling)?.into(),integer(effect_cut)?.into(),i64::try_from(limit)?.into()]),
        pl_protocol::ChatScope::GroupMembers{reference}=>("SELECT member_order AS ordering,metadata FROM timeline_item_members WHERE item_id=? AND member_order<? AND member_order<? AND admitted_effect<=? ORDER BY member_order DESC LIMIT ?",vec![reference.item_id.clone().into(),integer(before.unwrap_or(ceiling))?.into(),integer(ceiling)?.into(),integer(effect_cut)?.into(),i64::try_from(limit)?.into()]),
        pl_protocol::ChatScope::Children{..}=>anyhow::bail!("business children use the original atomic reader"),
    };
    let mut result=Vec::new();
    for row in db.query_all_raw(statement(sql,values)).await? {
        let bytes:Vec<u8>=row.try_get("","metadata")?;
        let entry=if matches!(scope,pl_protocol::ChatScope::Main){pl_protocol::ChatEntry::Item(Box::new(serde_json::from_slice(&bytes)?))}else{
            let mut atom:ChatAtom=serde_json::from_slice(&bytes)?;
            let fact=db.query_one_raw(statement("SELECT metadata FROM conversation_atom_facts WHERE atom_id=? AND effect_seq<=? ORDER BY CASE phase WHEN 'terminal' THEN 0 ELSE 1 END LIMIT 1",vec![atom.id.clone().into(),integer(effect_cut)?.into()])).await?.context("member has no source fact at the captured cut")?;
            atom=serde_json::from_slice(&fact.try_get::<Vec<u8>>("","metadata")?)?;
            if let Some(id)=&atom.completion_item_id {
                let payload=db.query_one_raw(statement("SELECT length(payload) AS bytes FROM conversation_items WHERE item_id=?",vec![id.clone().into()])).await?.context("member completion missing")?;
                atom.payload=Some(PayloadData::Deferred{reference:ContentRef{database_id:match scope{pl_protocol::ChatScope::GroupMembers{reference}=>reference.database_id.clone(),_=>unreachable!()},target:ContentTarget::ItemPayload{item_id:id.clone()}},byte_length:u64::try_from(payload.try_get::<i64>("","bytes")?)?});
            }
            pl_protocol::ChatEntry::Atom(Box::new(atom))
        };
        result.push((u64::try_from(row.try_get::<i64>("","ordering")?)?,entry));
    }
    Ok(result)
}
