//! Producer representation migration. Frozen history projections and accounting are not replayed.
use super::*;
use crate::studio::producer_migration::{RawObject, edit, field, replace_payload};
use pl_core::context::{ContextContent, content_hash};

pub(super) async fn migrate(db: &impl ConnectionTrait, thread_id: &str) -> Result<()> {
    // The canonical reader validates all hashes, ordinals, identities, revisions and the fence
    // before a producer decoder sees any saved content. SeaORM owns the surrounding transaction.
    let Some(original) = checkpoint::read(db, thread_id).await? else {
        return Ok(());
    };
    let mut current = original.clone();
    crate::studio::producer_migration::checkpoint(&mut current)?;
    ensure!(
        current.state.extension_sequence == original.state.extension_sequence,
        "producer migration changed extension sequence"
    );
    if current.state.extensions != original.state.extensions {
        let row = db
            .query_one_raw(statement(
                "SELECT payload FROM session_checkpoint WHERE id=1",
                vec![],
            ))
            .await?
            .context("checkpoint absent")?;
        let mut raw: RawObject = serde_json::from_str(&row.try_get::<String>("", "payload")?)?;
        edit(&mut raw, "state", |state| {
            edit(state, "extensions", |extensions| {
                for (id, record) in &current.state.extensions {
                    let previous = original
                        .state
                        .extensions
                        .get(id)
                        .context("producer extension absent")?;
                    ensure!(
                        previous.revision == record.revision,
                        "producer migration changed extension revision"
                    );
                    if previous.payload != record.payload {
                        edit(extensions, id, |saved| {
                            edit(saved, "payload", |saved| {
                                replace_payload(saved, &record.payload)
                            })
                        })?;
                    }
                }
                Ok(())
            })
        })?;
        let encoded = serde_json::to_string(&raw)?;
        db.execute_raw(statement(
            "UPDATE session_checkpoint SET payload=?,payload_hash=? WHERE id=1",
            vec![
                encoded.clone().into(),
                content_hash(encoded.as_bytes()).into(),
            ],
        ))
        .await?;
    }
    for (ordinal, (old, new)) in original
        .state
        .context
        .records
        .iter()
        .zip(current.state.context.records.iter())
        .enumerate()
    {
        if old == new {
            continue;
        }
        ensure!(
            old.id == new.id && old.content.len() == new.content.len(),
            "producer migration changed context identity or shape"
        );
        let row = db
            .query_one_raw(statement(
                "SELECT payload FROM current_context WHERE ordinal=? AND record_id=?",
                vec![integer(ordinal)?.into(), old.id.clone().into()],
            ))
            .await?
            .context("producer context record is absent")?;
        let mut raw: RawObject = serde_json::from_str(&row.try_get::<String>("", "payload")?)?;
        if old.source != new.source {
            raw.insert(
                "source".into(),
                serde_json::value::to_raw_value(&new.source)?,
            );
        }
        let mut content: Vec<Box<serde_json::value::RawValue>> =
            serde_json::from_str(field(&raw, "content")?.get())?;
        for (index, (previous, migrated)) in old.content.iter().zip(&new.content).enumerate() {
            if previous == migrated {
                continue;
            }
            let (ContextContent::Opaque { .. }, ContextContent::Opaque { payload }) =
                (previous, migrated)
            else {
                anyhow::bail!("producer migration changed nonopaque context content");
            };
            let mut saved = serde_json::from_str(content[index].get())?;
            edit(&mut saved, "payload", |saved| {
                replace_payload(saved, payload)
            })?;
            content[index] = serde_json::value::to_raw_value(&saved)?;
        }
        raw.insert("content".into(), serde_json::value::to_raw_value(&content)?);
        let encoded = serde_json::to_string(&raw)?;
        db.execute_raw(statement(
            "UPDATE current_context SET payload=?,payload_hash=? WHERE ordinal=? AND record_id=?",
            vec![
                encoded.clone().into(),
                content_hash(encoded.as_bytes()).into(),
                integer(ordinal)?.into(),
                old.id.clone().into(),
            ],
        ))
        .await?;
    }
    Ok(())
}
