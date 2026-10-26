//! Read-only source validation shared by ledger adoption and the atomic task-index migration.
use sea_orm::ConnectionTrait;

use super::{SessionStoreError, history, migration, sqlite, thread_checkpoint, thread_history};
use crate::{
    storage::{SessionEntry, SessionEntryChange},
    thread::ThreadEffectBatch,
};

const EFFECT_PREFIX: &str = "pl.resource.thread-commit.";
const EFFECT_UPPER: &str = "pl.resource.thread-commit/";

/// Validates stored facts without executing callbacks, rewriting envelopes or creating a ledger.
/// `format` identifies the source layout; it does not dispatch any migration.
pub(super) async fn validate(
    db: &impl ConnectionTrait,
    format: i64,
) -> Result<(), SessionStoreError> {
    let has_checkpoints = db
        .query_one_raw(sqlite::statement(
            "SELECT 1 FROM sqlite_schema WHERE type='table' AND name='thread_checkpoints'",
            vec![],
        ))
        .await?
        .is_some();
    let mut sources = "SELECT session_id AS thread_id FROM session_entries \
        UNION SELECT session_id AS thread_id FROM session_history_heads \
        UNION SELECT session_id AS thread_id FROM session_entry_history"
        .to_owned();
    if has_checkpoints {
        sources.push_str(" UNION SELECT thread_id FROM thread_checkpoints");
    }
    let query = format!(
        "SELECT thread_id FROM ({sources}) WHERE (? IS NULL OR thread_id>?) ORDER BY thread_id LIMIT 128"
    );
    let mut after: Option<String> = None;
    loop {
        let rows = db
            .query_all_raw(sqlite::statement(
                &query,
                vec![after.clone().into(), after.clone().into()],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let thread_id: String = row.try_get("", "thread_id")?;
            if thread_id.is_empty() {
                return Err(SessionStoreError::Invalid("empty source Thread identity".into()));
            }
            validate_thread(db, &thread_id, format, has_checkpoints).await?;
            after = Some(thread_id);
        }
    }
    Ok(())
}

async fn validate_thread(
    db: &impl ConnectionTrait,
    thread_id: &str,
    format: i64,
    has_checkpoints: bool,
) -> Result<(), SessionStoreError> {
    let checkpoint = if has_checkpoints {
        db.query_one_raw(sqlite::statement(
            "SELECT * FROM thread_checkpoints WHERE thread_id=?",
            vec![thread_id.into()],
        ))
        .await?
        .map(|row| thread_checkpoint::decode_migration_checkpoint(row, thread_id))
        .transpose()?
    } else {
        None
    };
    if let Some(checkpoint) = &checkpoint
        && format >= 9
        && checkpoint.state.usage_summary.applied_sequence != checkpoint.state_revision
    {
        return Err(SessionStoreError::Invalid(
            "Thread checkpoint usage summary is behind its revision".into(),
        ));
    }

    // The history head counts storage commits, not Thread effects: independent resources can add
    // commits too. Visit the original validated history to obtain its actual effect watermark.
    let mut history_through = 0_u64;
    history::visit(db, thread_id, None, |commit| {
        history_through = history_through.max(commit.thread_revision().unwrap_or(0));
        for change in commit.changes {
            match change {
                SessionEntryChange::Put { entry } if entry.id.starts_with(EFFECT_PREFIX) => {
                    let effect = decode_source_effect(entry, thread_id, format)?;
                    history_through = history_through.max(effect.sequence);
                }
                SessionEntryChange::Delete { entry_id } if entry_id.starts_with(EFFECT_PREFIX) => {
                    return Err(SessionStoreError::Invalid(
                        "immutable Thread effect was deleted from history".into(),
                    ));
                }
                SessionEntryChange::Put { .. } | SessionEntryChange::Delete { .. } => {}
            }
        }
        Ok(())
    })
    .await?;

    let mut after: Option<String> = None;
    let mut through = 0_u64;
    loop {
        let rows = db
            .query_all_raw(sqlite::statement(
                "SELECT * FROM session_entries WHERE session_id=? AND id>=? AND id<? AND (? IS NULL OR id>?) ORDER BY id LIMIT 128",
                vec![thread_id.into(), EFFECT_PREFIX.into(), EFFECT_UPPER.into(), after.clone().into(), after.clone().into()],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let entry = sqlite::decode_row(row)?;
            after = Some(entry.id.clone());
            let effect = decode_source_effect(entry, thread_id, format)?;
            let expected = through.checked_add(1).ok_or_else(|| {
                SessionStoreError::Invalid("Thread effect sequence overflow".into())
            })?;
            if effect.sequence != expected {
                return Err(SessionStoreError::Invalid(format!(
                    "Thread {thread_id} effect history has a sequence gap at {expected}"
                )));
            }
            through = expected;
        }
    }
    if through != history_through {
        return Err(SessionStoreError::Invalid(format!(
            "Thread {thread_id} effect tail differs from its committed history watermark"
        )));
    }
    if let Some(checkpoint) = checkpoint
        && (checkpoint.history_fence == 0
            || checkpoint.history_fence > through
            || checkpoint.state_revision > through)
    {
        return Err(SessionStoreError::Invalid(format!(
            "Thread {thread_id} checkpoint fence/revision has no saved effect"
        )));
    }
    Ok(())
}

fn decode_source_effect(
    mut entry: SessionEntry,
    thread_id: &str,
    format: i64,
) -> Result<ThreadEffectBatch, SessionStoreError> {
    if format == 6 {
        // Reuse the explicit legacy boundary with a no-op transform on this owned in-memory copy.
        // The caller's migration callback is never invoked during read-only source validation.
        migration::convert(&mut entry, &|_| Ok(()))?;
    }
    thread_history::decode_entry(entry, thread_id)
}
