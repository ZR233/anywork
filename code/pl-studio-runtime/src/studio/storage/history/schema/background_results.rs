//! Correct the published atom-metadata representation using durable inbox identities.
//! Original completions, task deliveries, checkpoints and source positions are not rewritten.
use super::*;
use crate::studio::storage::history::conversation::timeline;
use crate::studio::thread_projection::{order, timeline::lightweight};
use pl_protocol::{ChatAtom, ChatDeliveryKind, ChatSourceId};
use serde::Deserialize;

#[cfg(test)]
mod tests;

pub(super) struct BackgroundResults;

impl MigrationName for BackgroundResults {
    fn name(&self) -> &str {
        BACKGROUND_RESULTS
    }
}

#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for BackgroundResults {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }

    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        correct(manager.get_connection()).await.map_err(conversion)
    }
}

// Frozen ToolDeliveryTarget: rename_all applies to variants, not the Inbox field.
#[derive(Deserialize)]
#[serde(tag = "kind", content = "value", rename_all = "camelCase")]
enum PublishedTarget {
    CallResult,
    Inbox { message_id: String },
}

async fn correct(db: &impl ConnectionTrait) -> Result<()> {
    let format = version(db).await?;
    ensure!(
        matches!(format, 14 | 15 | 16),
        "background result correction requires schema 14 through 16"
    );
    let mut after = 0_i64;
    let mut changed = false;
    loop {
        let rows = db
            .query_all_raw(statement(
                "SELECT c.seq,c.item_id,c.metadata,t.call_id,
                    json_extract(t.delivery_payload,'$.callId') AS delivered_call,
                    json_extract(t.delivery_payload,'$.target') AS target
             FROM conversation_items c JOIN history_tool_tasks t
               ON t.call_id=json_extract(c.metadata,'$.tool.callId')
             WHERE c.seq>? AND c.query_class<>'diagnostic'
               AND json_extract(c.metadata,'$.lifecycle.kind')='terminal'
               AND json_extract(c.metadata,'$.lifecycle.outcome')<>'transferred'
               AND json_extract(t.delivery_payload,'$.target.kind')='inbox'
             ORDER BY c.seq LIMIT 128",
                vec![after.into()],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            after = row.try_get("", "seq")?;
            let completion: String = row.try_get("", "item_id")?;
            let original: Vec<u8> = row.try_get("", "metadata")?;
            let atom: ChatAtom = serde_json::from_slice(&original)?;
            let call: String = row.try_get("", "call_id")?;
            ensure!(
                row.try_get::<Option<String>>("", "delivered_call")?
                    .as_deref()
                    == Some(call.as_str()),
                "background delivery differs from its saved tool call"
            );
            let PublishedTarget::Inbox { message_id } =
                serde_json::from_str(&row.try_get::<String>("", "target")?)?
            else {
                anyhow::bail!("background result has no saved inbox target");
            };
            ensure!(
                !message_id.is_empty(),
                "background result has an empty saved message identity"
            );
            let identity = db
                .query_one_raw(statement(
                    "SELECT item_id,sequence FROM history_message_identities WHERE message_id=?",
                    vec![message_id.clone().into()],
                ))
                .await?
                .context(
                    "background result has no durable message identity; original data preserved",
                )?;
            let id: String = identity.try_get("", "item_id")?;
            let sequence = u64::try_from(identity.try_get::<i64>("", "sequence")?)?;
            ensure!(
                id == order::message_id(&message_id) && sequence > 0,
                "background result has conflicting durable message identity"
            );
            let source = ChatSourceId::BackgroundResult { message_id };
            if atom.id == id
                && atom.source == source
                && atom.delivery == ChatDeliveryKind::Independent
                && atom.source_order == Some(sequence)
            {
                continue;
            }
            ensure!(
                atom.id == order::tool_id(&call) || atom.id == id,
                "background result has a conflicting saved atom identity"
            );
            if matches!(atom.source, ChatSourceId::BackgroundResult { .. }) {
                ensure!(
                    atom.source == source,
                    "background result refers to another saved message"
                );
            }
            ensure!(
                atom.completion_item_id.as_deref() == Some(completion.as_str()),
                "background result differs from its original completion owner"
            );
            let mut corrected = atom.clone();
            corrected.id = id;
            corrected.source = source;
            corrected.delivery = ChatDeliveryKind::Independent;
            corrected.source_order = Some(sequence);
            let bytes = serde_json::to_vec(&corrected)?;
            let updated = db.execute_raw(statement(
                "UPDATE conversation_items SET metadata=? WHERE seq=? AND item_id=? AND metadata=?",
                vec![bytes.into(), after.into(), completion.clone().into(), original.into()],
            )).await?;
            ensure!(
                updated.rows_affected() == 1,
                "background result metadata changed during migration"
            );
            if format >= 15 {
                correct_facts(db, &atom, &corrected, &completion).await?;
            }
            changed = true;
        }
    }
    if format >= 15 && changed {
        let identity = db
            .query_one_raw(statement(
                "SELECT database_id FROM history_meta WHERE id=1",
                vec![],
            ))
            .await?
            .context("background result correction has no history identity")?;
        let database: String = identity.try_get("", "database_id")?;
        timeline::rebuild_published(db, &database).await?;
    }
    Ok(())
}

async fn correct_facts(
    db: &impl ConnectionTrait,
    original: &ChatAtom,
    corrected: &ChatAtom,
    completion: &str,
) -> Result<()> {
    let facts = db
        .query_all_raw(statement(
            "SELECT phase,metadata FROM conversation_atom_facts WHERE atom_id=?",
            vec![original.id.clone().into()],
        ))
        .await?;
    let mut terminal = false;
    for row in facts {
        let phase: String = row.try_get("", "phase")?;
        let bytes: Vec<u8> = row.try_get("", "metadata")?;
        let mut atom: ChatAtom = serde_json::from_slice(&bytes)?;
        // A different completion (including the original handoff) is never this migration's fact.
        ensure!(
            atom.completion_item_id.as_deref() == Some(completion),
            "background result fact belongs to another completion; original fact preserved"
        );
        if phase == "legacyAdmission" {
            db.execute_raw(statement(
                "DELETE FROM conversation_atom_facts WHERE atom_id=? AND phase='legacyAdmission' AND metadata=?",
                vec![original.id.clone().into(), bytes.into()],
            )).await?;
        } else {
            ensure!(
                phase == "terminal",
                "background result has an unexpected canonical start fact"
            );
            atom.id = corrected.id.clone();
            atom.source = corrected.source.clone();
            atom.delivery = corrected.delivery;
            atom.source_order = corrected.source_order;
            let unknown = matches!(
                atom.lifecycle,
                pl_protocol::ChatAtomLifecycle::Terminal {
                    started: None,
                    ended: None,
                    ..
                }
            );
            let completion_sequence = atom
                .completion_seq
                .context("background terminal has no completion sequence")?;
            let updated = db
                .execute_raw(statement(
                    "UPDATE conversation_atom_facts SET atom_id=?,metadata=?,
                   effect_seq=CASE WHEN ? THEN 0 ELSE effect_seq END,
                   suborder=CASE WHEN ? THEN 0 ELSE suborder END,
                   fact_order=CASE WHEN ? THEN ? ELSE fact_order END
                 WHERE atom_id=? AND phase='terminal' AND metadata=?",
                    vec![
                        atom.id.clone().into(),
                        serde_json::to_vec(&lightweight(&atom))?.into(),
                        unknown.into(),
                        unknown.into(),
                        unknown.into(),
                        integer(completion_sequence)?.into(),
                        original.id.clone().into(),
                        bytes.into(),
                    ],
                ))
                .await?;
            ensure!(
                updated.rows_affected() == 1,
                "background terminal changed during migration"
            );
            terminal = true;
        }
    }
    ensure!(
        terminal,
        "background result is missing its canonical terminal fact"
    );
    Ok(())
}
