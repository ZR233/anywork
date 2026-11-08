//! Named content upgrade; original payloads and reliable fact positions are immutable.
use super::super::conversation::timeline;
use super::*;
use pl_protocol::{ChatAtom, ChatAtomKind};

pub(super) struct SourceClassification;

impl MigrationName for SourceClassification {
    fn name(&self) -> &str {
        SOURCE_CLASSIFICATION
    }
}

#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for SourceClassification {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }

    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        async {
            let db = manager.get_connection();
            ensure!(
                version(db).await? == 16,
                "source classification requires schema 16"
            );
            // Applied-but-missing structures/heads are corruption, not upgrade inputs.
            validate_schema16_structure(db).await?;
            normalize(db).await?;
            let row = db
                .query_one_raw(statement(
                    "SELECT database_id FROM history_meta WHERE id=1",
                    vec![],
                ))
                .await?
                .context("source classification has no database identity")?;
            timeline::rebuild_schema16(db, &row.try_get::<String>("", "database_id")?).await?;
            Ok::<_, anyhow::Error>(())
        }
        .await
        .map_err(conversion)
    }
}

fn target(kind: &str) -> Option<ChatAtomKind> {
    match kind {
        "raw" => Some(ChatAtomKind::Raw),
        "agent" => Some(ChatAtomKind::Agent),
        "inference" => Some(ChatAtomKind::Inference),
        _ => None,
    }
}

fn known(kind: &str) -> bool {
    matches!(
        kind,
        "raw"
            | "agent"
            | "inference"
            | "text"
            | "thinking"
            | "tool"
            | "plan"
            | "file"
            | "skill"
            | "contextCompaction"
            | "turn"
    )
}

fn agrees(kind: ChatAtomKind, evidence: &str) -> bool {
    match kind {
        ChatAtomKind::Unknown => true,
        ChatAtomKind::Raw => evidence == "raw",
        ChatAtomKind::Agent => evidence == "agent",
        ChatAtomKind::Inference => evidence == "inference",
        ChatAtomKind::Input | ChatAtomKind::Text => evidence == "text",
        ChatAtomKind::Reasoning => evidence == "thinking",
        ChatAtomKind::ToolCall | ChatAtomKind::Interaction => evidence == "tool",
        ChatAtomKind::Plan => matches!(evidence, "tool" | "plan"),
        ChatAtomKind::FileChange => evidence == "file",
        ChatAtomKind::Skill => evidence == "skill",
        ChatAtomKind::Compaction => evidence == "contextCompaction",
        ChatAtomKind::TurnReceipt => evidence == "turn",
        // AtomMetadata's published raw/agent mapping used Receipt. This is
        // the explicit old representation accepted by this named upgrade.
        ChatAtomKind::Receipt => matches!(evidence, "raw" | "agent"),
    }
}

/// Read only small, explicit type tags in SQLite. Bodies, images and raw payload
/// bytes are never materialized or re-encoded by this migration.
async fn classify(
    db: &impl ConnectionTrait,
    atom: &mut ChatAtom,
    completion: Option<&str>,
) -> Result<()> {
    let history = if let Some(row) = db.query_one_raw(statement(
        "SELECT kind,json_valid(payload) AS valid,
                CASE WHEN json_valid(payload) THEN json_type(payload,'$.state') END AS state_shape,
                CASE WHEN json_valid(payload) THEN json_extract(payload,'$.state.kind') END AS descriptor
         FROM history_items WHERE item_id=?", vec![atom.id.clone().into()],
    )).await? {
        let kind: String = row.try_get("", "kind")?;
        ensure!(row.try_get::<i64>("", "valid")? == 1,
            "typed history JSON is damaged for {}", atom.id);
        let descriptor: Option<String> = row.try_get("", "descriptor")?;
        if let Some(shape) = row.try_get::<Option<String>>("", "state_shape")? {
            ensure!(shape == "object" && descriptor.as_deref() == Some(kind.as_str()),
                "typed history descriptor conflicts for {}", atom.id);
        }
        Some(kind)
    } else {
        None
    };
    let mut envelope = None;
    if let Some(id) = completion {
        let row = db.query_one_raw(statement(
            "SELECT CASE WHEN json_valid(payload) THEN
                        CASE WHEN json_type(payload,'$.contract')='text' THEN json_extract(payload,'$.contract') END
                    END AS contract,
                    CASE WHEN json_valid(payload) THEN json_type(payload,'$.type') END AS type_shape,
                    CASE WHEN json_valid(payload) THEN json_extract(payload,'$.type') END AS type,
                    CASE WHEN json_valid(payload) THEN json_type(payload,'$.data') END AS data_shape
             FROM conversation_items WHERE item_id=?",
            vec![id.into()],
        )).await?.context("classification completion owner is missing")?;
        if row.try_get::<Option<String>>("", "contract")?.as_deref() == Some("anywork.chat/1") {
            ensure!(
                row.try_get::<Option<String>>("", "type_shape")?.as_deref() == Some("text"),
                "supported completion {id} has malformed type"
            );
            envelope = row.try_get::<Option<String>>("", "type")?;
            if envelope.as_deref().is_some_and(known) {
                ensure!(
                    row.try_get::<Option<String>>("", "data_shape")?.as_deref() == Some("object"),
                    "supported completion {id} has malformed data"
                );
            }
        }
    }
    // A plan is a specialized public tool descriptor, not a contradictory type.
    if let (Some(history), Some(envelope)) = (&history, &envelope)
        && known(history)
        && known(envelope)
    {
        ensure!(
            history == envelope || (history == "tool" && envelope == "plan"),
            "typed history and completion disagree for {}",
            atom.id
        );
    }
    for evidence in [history.as_deref(), envelope.as_deref()]
        .into_iter()
        .flatten()
    {
        // Only a known original type proves a metadata conflict. An unsupported
        // public format/type is not a malformed known format or a guessed source.
        if known(evidence) {
            ensure!(
                agrees(atom.kind, evidence),
                "classification metadata conflicts for {}",
                atom.id
            );
            if matches!(atom.kind, ChatAtomKind::Unknown | ChatAtomKind::Receipt)
                && let Some(kind) = target(evidence)
            {
                atom.kind = kind;
            }
        }
    }
    Ok(())
}

async fn normalize(db: &impl ConnectionTrait) -> Result<()> {
    let mut after = 0i64;
    loop {
        let rows = db.query_all_raw(statement(
            "SELECT seq,item_id,metadata FROM conversation_items WHERE seq>? ORDER BY seq LIMIT 128",
            vec![after.into()],
        )).await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            after = row.try_get("", "seq")?;
            let id: String = row.try_get("", "item_id")?;
            let mut atom: ChatAtom =
                serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
            let old = atom.kind;
            classify(db, &mut atom, Some(&id)).await?;
            if atom.kind != old {
                db.execute_raw(statement(
                    "UPDATE conversation_items SET metadata=? WHERE seq=?",
                    vec![serde_json::to_vec(&atom)?.into(), after.into()],
                ))
                .await?;
            }
        }
    }
    // The unique (atom_id,phase) index makes this bounded keyset independent of
    // effect ordering. No fact identity, position or completion sequence changes.
    let mut cursor = (String::new(), String::new());
    loop {
        let rows = db
            .query_all_raw(statement(
                "SELECT atom_id,phase,metadata FROM conversation_atom_facts
             WHERE (atom_id,phase)>(?,?) ORDER BY atom_id,phase LIMIT 128",
                vec![cursor.0.clone().into(), cursor.1.clone().into()],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            cursor = (row.try_get("", "atom_id")?, row.try_get("", "phase")?);
            if cursor.1 == "legacySourceEnd" {
                continue;
            }
            let mut atom: ChatAtom =
                serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
            let completion = completion_owner(db, &atom).await?;
            let old = atom.kind;
            classify(db, &mut atom, completion.as_deref()).await?;
            if old != atom.kind {
                db.execute_raw(statement(
                    "UPDATE conversation_atom_facts SET metadata=? WHERE atom_id=? AND phase=?",
                    vec![
                        serde_json::to_vec(&atom)?.into(),
                        cursor.0.clone().into(),
                        cursor.1.clone().into(),
                    ],
                ))
                .await?;
            }
        }
    }
    let mut current = super::legacy_current::read(db).await?;
    let mut changed = false;
    for atom in &mut current.atoms {
        let completion = completion_owner(db, atom).await?;
        let old = atom.kind;
        classify(db, atom, completion.as_deref()).await?;
        changed |= old != atom.kind;
    }
    if changed {
        db.execute_raw(statement(
            "UPDATE conversation_view_state SET payload=? WHERE singleton_id=1",
            vec![serde_json::to_vec(&current)?.into()],
        ))
        .await?;
    }
    Ok(())
}

async fn completion_owner(db: &impl ConnectionTrait, atom: &ChatAtom) -> Result<Option<String>> {
    if atom.completion_item_id.is_some() {
        return Ok(atom.completion_item_id.clone());
    }
    Ok(db
        .query_one_raw(statement(
            "SELECT json_extract(metadata,'$.completionItemId') AS owner
         FROM conversation_atom_facts WHERE atom_id=? AND phase='terminal'",
            vec![atom.id.clone().into()],
        ))
        .await?
        .map(|row| row.try_get::<Option<String>>("", "owner"))
        .transpose()?
        .flatten())
}

#[cfg(test)]
mod tests;
