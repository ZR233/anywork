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
    super::sources::apply(db, effect, &prepared.source_changes).await
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
        domain!(turns);
        domain!(tasks);
        domain!(attempts);
        if let Some(value) = fields.try_get::<Option<String>>("", "lifecycle")? {
            state.lifecycle = serde_json::from_str(&value)?;
        }
    }
    let state = CurrentState::cold(
        row.try_get("", "database_id")?,
        row.try_get("", "thread_id")?,
        u64::try_from(row.try_get::<i64>("", "applied_write_seq")?)?,
        &state,
    )?;
    let head = super::timeline::read_state(db)
        .await?
        .context("cold content has no recovery cut")?;
    let timeline =
        super::timeline::complete::restore(db, &row.try_get::<String>("", "database_id")?, &head)
            .await?;
    let mut projection = state.projection().clone();
    projection.items = timeline.current_items();
    projection.atoms = timeline.active_atoms();
    Ok(CurrentState::with_projection(
        state,
        crate::studio::thread_projection::FrozenCurrentProjection::new(projection),
    ))
}
