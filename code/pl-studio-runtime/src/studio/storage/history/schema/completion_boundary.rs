//! Named completion-boundary upgrade. Unique legacy material stays in managed archive tables.
use super::super::conversation;
use super::legacy_timeline_store as timeline;
use super::*;
#[cfg(test)]
mod tests;

pub(super) struct CompletionBoundary;
impl MigrationName for CompletionBoundary {
    fn name(&self) -> &str {
        COMPLETION_BOUNDARY
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for CompletionBoundary {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        async {
            let db = manager.get_connection();
            ensure!(version(db).await? == 17, "completion boundary requires schema 17");
            // This step runs after the published TimelineBackgroundTail step. Its layout and
            // recovery decoding are validated before moving any original material.
            demand_conversation::validate_tables(db).await?;
            timeline::validate_tables(db).await?;
            validate_saved_heads(db).await?;
            let row = db.query_one_raw(statement(
                "SELECT database_id,applied_write_seq FROM history_meta WHERE id=1",vec![],
            )).await?.context("completion boundary has no history identity")?;
            db.execute_unprepared("
                ALTER TABLE conversation_view_state RENAME TO completion_boundary_archive_view_state;
                ALTER TABLE conversation_view_entries RENAME TO completion_boundary_archive_view_entries;
                ALTER TABLE timeline_items RENAME TO completion_boundary_archive_timeline_items;
                ALTER TABLE timeline_item_members RENAME TO completion_boundary_archive_timeline_members;
                CREATE TABLE completion_boundary_archive_projection_state AS SELECT * FROM timeline_projection_state;
                DROP INDEX timeline_items_by_commit;
                DROP INDEX timeline_items_by_location_position;
                DROP INDEX timeline_members_by_member;
            ").await?;
            archive_unfinished_contents(db).await?;
            db.execute_unprepared(timeline::complete::CREATE).await?;
            timeline::complete::rebuild(db,
                &row.try_get::<String>("","database_id")?,
                uuid::Uuid::new_v4().to_string(),
                u64::try_from(row.try_get::<i64>("","applied_write_seq")?)?,
            ).await?;
            timeline::complete::validate(db).await?;
            let head = timeline::read_state(db).await?.context("completion boundary has no recovery cut")?;
            timeline::complete::restore(db, &row.try_get::<String>("","database_id")?, &head).await?;
            super::legacy_current::validate_cold_domains(db).await?;
            Ok::<_, anyhow::Error>(())
        }.await.map_err(conversion)
    }
}

pub(in crate::studio::storage::history) async fn applied(
    db: &impl ConnectionTrait,
) -> Result<bool> {
    Ok(Migrator {
        thread_id: String::new(),
        bot_root: None,
        execution_identity: None,
    }
    .get_applied_migrations_read_only(db)
    .await?
    .iter()
    .any(|step| step.name() == COMPLETION_BOUNDARY))
}

pub(super) async fn validate(db: &impl ConnectionTrait) -> Result<()> {
    ensure!(
        version(db).await? == 17,
        "completion boundary requires schema 17"
    );
    validate_preserved(db).await?;
    timeline::complete::validate(db).await
}

pub(super) async fn validate_preserved(db: &impl ConnectionTrait) -> Result<()> {
    super::validate_tables(db).await?;
    for sql in [
        "SELECT seq,item_id,query_class,parent_id,payload,metadata FROM conversation_items LIMIT 0",
        "SELECT owner_key,content_key,payload FROM conversation_contents LIMIT 0",
        "SELECT owner_key,content_key,byte_offset,data FROM conversation_content_chunks LIMIT 0",
        "SELECT singleton_id,payload FROM completion_boundary_archive_view_state LIMIT 0",
        "SELECT collection,position,entry_id,payload FROM completion_boundary_archive_view_entries LIMIT 0",
        "SELECT item_id,metadata FROM completion_boundary_archive_timeline_items LIMIT 0",
        "SELECT item_id,member_order,member_id,metadata FROM completion_boundary_archive_timeline_members LIMIT 0",
        "SELECT projection_generation,recovery FROM completion_boundary_archive_projection_state LIMIT 0",
        "SELECT owner_key,content_key,payload FROM completion_boundary_archive_contents LIMIT 0",
        "SELECT owner_key,content_key,byte_offset,data FROM completion_boundary_archive_content_chunks LIMIT 0",
    ] {
        db.query_all_raw(statement(sql, vec![])).await?;
    }
    for (table, primary, integer_primary, unique) in [
        ("conversation_items", &["seq"][..], true, &["item_id"][..]),
        (
            "conversation_contents",
            &["owner_key", "content_key"][..],
            false,
            &[][..],
        ),
        (
            "conversation_content_chunks",
            &["owner_key", "content_key", "byte_offset"][..],
            false,
            &[][..],
        ),
        (
            "completion_boundary_archive_contents",
            &["owner_key", "content_key"][..],
            false,
            &[][..],
        ),
        (
            "completion_boundary_archive_content_chunks",
            &["owner_key", "content_key", "byte_offset"][..],
            false,
            &[][..],
        ),
        (
            "completion_boundary_archive_view_entries",
            &["collection", "position"][..],
            false,
            &[][..],
        ),
    ] {
        validate_keys(db, table, primary, integer_primary, unique).await?;
        if !integer_primary {
            validate_ordered_unique_key(db, table, primary, true).await?;
        }
    }
    validate_ordered_unique_key(
        db,
        "completion_boundary_archive_view_entries",
        &["collection", "entry_id"],
        false,
    )
    .await?;
    model_route_head::validate_tables(db).await?;
    atom_metadata::validate_tables(db).await?;
    checkpoint::read_model_route_head(db).await?;
    Ok(())
}

/// Migration-only relocation. No normal writer can take over an unfinished body.
async fn archive_unfinished_contents(db: &impl ConnectionTrait) -> Result<()> {
    use conversation::content;
    use pl_core::chat::ChatKey;
    use pl_protocol::{ChatAtom, ContentTarget};

    db.execute_unprepared(
        "
        CREATE TABLE completion_boundary_archive_contents (
            owner_key TEXT NOT NULL, content_key TEXT NOT NULL, payload BLOB NOT NULL,
            PRIMARY KEY(owner_key,content_key)) WITHOUT ROWID;
        CREATE TABLE completion_boundary_archive_content_chunks (
            owner_key TEXT NOT NULL, content_key TEXT NOT NULL,
            byte_offset INTEGER NOT NULL, data BLOB NOT NULL,
            PRIMARY KEY(owner_key,content_key,byte_offset)) WITHOUT ROWID;
    ",
    )
    .await?;
    let mut after = (String::new(), String::new());
    loop {
        let rows = db
            .query_all_raw(statement(
                "SELECT owner_key,content_key,payload FROM conversation_contents
             WHERE (owner_key,content_key)>(?,?) ORDER BY owner_key,content_key LIMIT 32",
                vec![after.0.clone().into(), after.1.clone().into()],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let owner: String = row.try_get("", "owner_key")?;
            let key: String = row.try_get("", "content_key")?;
            after = (owner.clone(), key.clone());
            let payload: Vec<u8> = row.try_get("", "payload")?;
            let manifest = content::manifest(&payload)?;
            if manifest.sealed {
                continue;
            }
            let identity = ChatKey::from_encoded(owner.clone())?;
            ensure!(!key.is_empty(), "unfinished content has no key");
            if let Some(id) = owner.strip_prefix("4:item") {
                ensure!(
                    ChatKey::new("item", id)? == identity,
                    "invalid unfinished item owner"
                );
                ensure!(
                    db.query_one_raw(statement(
                        "SELECT 1 FROM conversation_items WHERE item_id=?",
                        vec![id.into()],
                    ))
                    .await?
                    .is_none(),
                    "unfinished content belongs to a completed item"
                );
                ensure!(
                    db.query_one_raw(statement(
                        "SELECT 1 FROM history_items WHERE item_id=?
                     UNION ALL SELECT 1 FROM conversation_atom_facts WHERE atom_id=? LIMIT 1",
                        vec![id.into(), id.into()],
                    ))
                    .await?
                    .is_some(),
                    "unfinished content has no original owner"
                );
            } else if let Some(encoded) = owner.strip_prefix("7:current") {
                let (domain, id, revision): (String, String, u64) = serde_json::from_str(encoded)?;
                ensure!(
                    crate::studio::conversation_identity::content_owner_key(
                        &pl_protocol::ContentOwner::Current {
                            domain,
                            id,
                            revision
                        },
                    )? == identity,
                    "invalid unfinished current owner"
                );
                let row = db.query_one_raw(statement(
                    "SELECT payload FROM completion_boundary_archive_view_state WHERE singleton_id=1",vec![],
                )).await?.context("unfinished current has no archived owner")?;
                let original: super::legacy_timeline_types::CurrentProjection =
                    serde_json::from_slice(&row.try_get::<Vec<u8>>("", "payload")?)?;
                let referenced = super::legacy_current::references(&original).any(|reference| {
                    matches!(&reference.target, ContentTarget::Body {owner: candidate,key: candidate_key}
                        if crate::studio::conversation_identity::content_owner_key(candidate).as_ref().ok()==Some(&identity)
                            && candidate_key==&key)
                });
                let entry = db
                    .query_one_raw(statement(
                        "SELECT 1 FROM completion_boundary_archive_view_entries
                     WHERE json_extract(CAST(payload AS TEXT),'$.owner')=?
                       AND json_extract(CAST(payload AS TEXT),'$.key')=? LIMIT 1",
                        vec![owner.clone().into(), key.clone().into()],
                    ))
                    .await?;
                ensure!(
                    referenced || entry.is_some(),
                    "unfinished current content has no original owner reference"
                );
            } else {
                anyhow::bail!("unfinished content has an unknown owner domain");
            }
            // Frozen references can name another owner. Check all completion envelopes in
            // bounded pages, rather than assuming the owning item's absence proves non-use.
            let mut seq = 0i64;
            loop {
                let records = db.query_all_raw(statement(
                    "SELECT seq,metadata FROM conversation_items WHERE seq>? ORDER BY seq LIMIT 128",
                    vec![seq.into()],
                )).await?;
                if records.is_empty() {
                    break;
                }
                for record in records {
                    seq = record.try_get("", "seq")?;
                    let atom: ChatAtom =
                        serde_json::from_slice(&record.try_get::<Vec<u8>>("", "metadata")?)?;
                    for body in atom.contents {
                        if let ContentTarget::Body {
                            owner: referenced,
                            key: referenced_key,
                        } = body.reference.target
                        {
                            ensure!(
                                crate::studio::conversation_identity::content_owner_key(
                                    &referenced
                                )? != identity
                                    || referenced_key != key,
                                "unfinished content is referenced by a completion"
                            );
                        }
                    }
                }
            }
            // Validate the entire old body before relocation; preserve the original payload
            // and every chunk byte/offset, not a re-encoded manifest or a sealed prefix.
            let mut offset = 0u64;
            let mut last_chunk = -1i64;
            ensure!(db.query_one_raw(statement(
                "SELECT 1 FROM conversation_content_chunks WHERE owner_key=? AND content_key=? AND byte_offset<0 LIMIT 1",
                vec![owner.clone().into(),key.clone().into()],
            )).await?.is_none(), "unfinished content has a negative chunk offset");
            loop {
                let chunks = db
                    .query_all_raw(statement(
                        "SELECT byte_offset,length(data) AS size FROM conversation_content_chunks
                     WHERE owner_key=? AND content_key=? AND byte_offset>?
                     ORDER BY byte_offset LIMIT 32",
                        vec![owner.clone().into(), key.clone().into(), last_chunk.into()],
                    ))
                    .await?;
                if chunks.is_empty() {
                    break;
                }
                for chunk in chunks {
                    last_chunk = chunk.try_get("", "byte_offset")?;
                    ensure!(
                        last_chunk == integer(offset)?,
                        "unfinished content chunks have a gap or overlap"
                    );
                    let size = u64::try_from(chunk.try_get::<i64>("", "size")?)?;
                    ensure!(size > 0, "unfinished content has an empty chunk");
                    offset = offset
                        .checked_add(size)
                        .context("unfinished content size overflow")?;
                }
            }
            ensure!(
                offset == manifest.byte_length,
                "unfinished content byte length differs"
            );
            for sql in [
                "INSERT INTO completion_boundary_archive_contents SELECT * FROM conversation_contents WHERE owner_key=? AND content_key=?",
                "INSERT INTO completion_boundary_archive_content_chunks SELECT * FROM conversation_content_chunks WHERE owner_key=? AND content_key=?",
                "DELETE FROM conversation_content_chunks WHERE owner_key=? AND content_key=?",
                "DELETE FROM conversation_contents WHERE owner_key=? AND content_key=?",
            ] {
                db.execute_raw(statement(
                    sql,
                    vec![owner.clone().into(), key.clone().into()],
                ))
                .await?;
            }
        }
    }
    Ok(())
}
