//! Normal completion-boundary writes and independent checkpoint-backed cold reads.
use super::current::PreparedCurrent;
use super::*;
use crate::studio::thread_projection::CurrentState;
use pl_core::thread::ThreadSnapshot;

pub(in super::super) async fn apply(
    db: &impl ConnectionTrait,
    effect: u64,
    prepared: &PreparedCurrent,
) -> Result<()> {
    ensure!(
        prepared.projection().source_effect_seq == effect,
        "prepared facts belong to another effect"
    );
    for write in prepared.contents.iter() {
        ensure!(write.sealed, "independent documents must be complete");
        super::content::write_content(db, &write.content, true).await?;
    }
    super::sources::apply(db, effect, &prepared.source_changes).await?;
    super::facts::apply(db, &prepared.atom_facts, effect).await?;
    if let Some(display) = &prepared.display {
        ensure!(
            display.effect_seq == effect,
            "display delta belongs to another effect"
        );
        super::display::apply(db, display).await?;
    }
    Ok(())
}

pub(in super::super) async fn verify(
    db: &impl ConnectionTrait,
    prepared: &PreparedCurrent,
) -> Result<()> {
    super::sources::verify(
        db,
        prepared.projection().source_effect_seq,
        &prepared.source_changes,
    )
    .await?;
    super::facts::verify(db, &prepared.atom_facts).await?;
    if let Some(display) = &prepared.display {
        super::display::verify(db, display).await?;
    }
    for write in prepared.contents.iter() {
        let manifest = super::content::validate_content(db, &write.content)
            .await?
            .context("retried complete document is missing")?;
        ensure!(manifest.sealed, "retried complete document is not sealed");
    }
    Ok(())
}

/// Read only independent domain fields. Neither context nor active product collections are read.
pub(in super::super) async fn cold(db: &impl ConnectionTrait) -> Result<Arc<CurrentState>> {
    let row = db
        .query_one_raw(statement(
            "SELECT thread_id,database_id,applied_write_seq FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .context("history identity is missing")?;
    let mut state = ThreadSnapshot::default();
    if let Some(fields) = db
        .query_one_raw(statement(
            "SELECT json_extract(payload,'$.state.extensions.\"studio.plan\"') AS plan,
                json_extract(payload,'$.state.permissions') AS permissions,
                json_extract(payload,'$.state.interactions') AS interactions,
                payload -> '$.state.interactionCollectionRevision' AS interaction_collection_revision,
                json_extract(payload,'$.state.turns') AS turns,
                json_extract(payload,'$.state.tasks') AS tasks,
                json_extract(payload,'$.state.attempts') AS attempts,
                json_extract(payload,'$.state.lifecycle') AS lifecycle
         FROM session_checkpoint WHERE id=1",
            vec![],
        ))
        .await?
    {
        macro_rules! domain {
            ($field:ident) => {
                if let Some(value) = fields.try_get::<Option<String>>("", stringify!($field))? {
                    state.$field = serde_json::from_str(&value)?;
                }
            };
        }
        if let Some(value) = fields.try_get::<Option<String>>("", "plan")? {
            state.extensions.insert(
                crate::plan_tool::PLAN_EXTENSION.into(),
                serde_json::from_str(&value)?,
            );
        }
        domain!(permissions);
        domain!(interactions);
        if let Some(revision) = fields.try_get::<Option<String>>("", "interaction_collection_revision")? {
            state.interaction_collection_revision = serde_json::from_str(&revision)?;
        }
        domain!(turns);
        domain!(tasks);
        domain!(attempts);
        if let Some(value) = fields.try_get::<Option<String>>("", "lifecycle")? {
            state.lifecycle = serde_json::from_str(&value)?;
        }
    }
    // Keep content-only reads on their narrow domain-field path.
    cold_from_state(
        db,
        row.try_get("", "database_id")?,
        row.try_get("", "thread_id")?,
        u64::try_from(row.try_get::<i64>("", "applied_write_seq")?)?,
        &state,
    )
    .await
}

pub(in super::super) async fn cold_from_state(
    db: &impl ConnectionTrait,
    database: String,
    thread: String,
    effect: u64,
    snapshot: &ThreadSnapshot,
) -> Result<Arc<CurrentState>> {
    let state = CurrentState::cold(database.clone(), thread, effect, snapshot)?;
    validate_business_refs(db, state.projection(), &database).await?;
    Ok(state)
}

/// The header and its sealed document directory are checked in the caller's same short snapshot.
/// Chunks remain range-read responsibilities; no completed body is reconstructed here.
async fn validate_business_refs(
    db: &impl ConnectionTrait,
    projection: &pl_protocol::CurrentProjection,
    database: &str,
) -> Result<()> {
    use pl_protocol::{ContentOwner, ContentTarget};
    let refs = crate::studio::thread_projection::project_business_refs(projection);
    if let Some(reference) = &refs.interactions {
        ensure!(
            reference.database_id == database && reference.collection == "interactions",
            pl_core::chat::ChatError::StaleContent
        );
    }
    let Some(plan) = refs.plan else {
        return Ok(());
    };
    let Some(document) = plan.document else {
        return Ok(());
    };
    ensure!(
        document.database_id == database,
        pl_core::chat::ChatError::StaleContent
    );
    let ContentTarget::Body { owner, key } = &document.target else {
        anyhow::bail!("current Plan document is not a body reference");
    };
    ensure!(
        matches!(owner, ContentOwner::Current { domain, id, revision }
        if domain == "plan" && id == "document" && *revision == plan.revision)
            && key == "document",
        pl_core::chat::ChatError::StaleContent
    );
    let owner = crate::studio::conversation_identity::content_owner_key(owner)?;
    let row = db
        .query_one_raw(statement(
            "SELECT payload FROM conversation_contents WHERE owner_key=? AND content_key=?",
            vec![owner.as_str().into(), key.clone().into()],
        ))
        .await?
        .context("current Plan document manifest is missing; original history preserved")?;
    let manifest = super::content::manifest(&row.try_get::<Vec<u8>>("", "payload")?)?;
    ensure!(
        manifest.sealed && manifest.generation > 0,
        "current Plan document is not a sealed content resource"
    );
    Ok(())
}
