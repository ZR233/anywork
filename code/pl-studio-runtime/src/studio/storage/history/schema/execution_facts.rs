//! Schema 23 -> 24：先核实事实去向和原件字节，再在原事务删除旧执行副本。
use super::*;
use crate::studio::storage::history::{execution_lifecycle, turns};
use crate::{ExecutionItem, ExecutionShape};
use pl_protocol::{ChatAtom, ChatSourceId};
use sha2::{Digest, Sha256};

pub(super) struct ExecutionFacts;
impl MigrationName for ExecutionFacts {
    fn name(&self) -> &str {
        EXECUTION_FACTS
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for ExecutionFacts {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        upgrade(manager.get_connection()).await.map_err(conversion)
    }
}

const RECORDS: &str = "
CREATE TABLE conversation_items_v2 (
 seq INTEGER PRIMARY KEY CHECK(seq>0), item_id TEXT NOT NULL UNIQUE,
 query_class TEXT NOT NULL, parent_id TEXT, payload BLOB NOT NULL, metadata BLOB NOT NULL
);
INSERT INTO conversation_items_v2(seq,item_id,query_class,parent_id,payload,metadata)
 SELECT seq,item_id,query_class,parent_id,payload,metadata FROM conversation_items;
";

/// Only this named migration uses dynamic table names; every input is a local constant.
async fn digest(
    db: &impl ConnectionTrait,
    table: &str,
    keys: &[(&str, bool)],
    evidence: &str,
) -> Result<String> {
    let columns = keys
        .iter()
        .map(|(key, _)| *key)
        .collect::<Vec<_>>()
        .join(",");
    let placeholders = vec!["?"; keys.len()].join(",");
    let mut after = Vec::new();
    let mut hash = Sha256::new();
    loop {
        let condition = if after.is_empty() {
            String::new()
        } else if keys.len() == 1 {
            format!(" WHERE {columns}>?")
        } else {
            format!(" WHERE ({columns})>({placeholders})")
        };
        let rows = db.query_all_raw(statement(&format!(
            "SELECT {columns},{evidence} AS evidence FROM {table}{condition} ORDER BY {columns} LIMIT 128"
        ), after)).await?;
        if rows.is_empty() {
            break;
        }
        for row in &rows {
            let evidence: String = row.try_get("", "evidence")?;
            hash.update((evidence.len() as u64).to_le_bytes());
            hash.update(evidence.as_bytes());
        }
        let last = rows.last().expect("nonempty page");
        after = keys
            .iter()
            .map(|(name, number)| -> Result<sea_orm::Value> {
                Ok(if *number {
                    last.try_get::<i64>("", name)?.into()
                } else {
                    last.try_get::<String>("", name)?.into()
                })
            })
            .collect::<Result<_>>()?;
    }
    Ok(hex::encode(hash.finalize()))
}

async fn originals(db: &impl ConnectionTrait) -> Result<Vec<String>> {
    let mut hashes = Vec::new();
    for (table, keys, evidence) in [
        (
            "conversation_items",
            &[("seq", true)][..],
            "json_array(seq,item_id,query_class,parent_id,hex(payload),hex(metadata))",
        ),
        (
            "(SELECT * FROM conversation_contents WHERE owner_key NOT GLOB '23:legacy-execution-record*')",
            &[("owner_key", false), ("content_key", false)][..],
            "json_array(owner_key,content_key,hex(payload))",
        ),
        (
            "(SELECT * FROM conversation_content_chunks WHERE owner_key NOT GLOB '23:legacy-execution-record*')",
            &[
                ("owner_key", false),
                ("content_key", false),
                ("byte_offset", true),
            ][..],
            "json_array(owner_key,content_key,byte_offset,hex(data))",
        ),
        (
            "history_input_identities",
            &[("item_id", false)][..],
            "json_array(item_id,ordinal,revision,digest,request_digest,presentation,payload,last_write_seq)",
        ),
        (
            "(SELECT * FROM history_fact_receipts WHERE kind<>'legacy_execution_record')",
            &[("item_id", false), ("revision", true)][..],
            "json_array(item_id,revision,kind,digest,payload,last_write_seq)",
        ),
        (
            "current_context",
            &[("ordinal", true)][..],
            "json_array(ordinal,record_id,payload,payload_hash)",
        ),
        (
            "session_checkpoint",
            &[("id", true)][..],
            "json_array(id,revision,context_revision,context_count,payload,payload_hash,legacy_cleanup)",
        ),
    ] {
        hashes.push(digest(db, table, keys, evidence).await?);
    }
    Ok(hashes)
}

async fn archive(
    db: &impl ConnectionTrait,
    origin: &str,
    id: &str,
    revision: u64,
    kind: &str,
    bytes: &[u8],
    source_row: &serde_json::Value,
) -> Result<()> {
    let effect = source_row
        .get("lastWriteSeq")
        .or_else(|| source_row.get("effectSeq"))
        .and_then(serde_json::Value::as_i64)
        .context("legacy source effect is missing")?;
    let identity = pl_core::chat::ChatKey::new(
        "legacy-execution-record",
        &format!("{}:{origin}{id}", origin.len()),
    )?;
    let content = pl_core::chat::ChatContent {
        descriptor: pl_core::chat::ContentDescriptor {
            key: pl_core::chat::ChatContentKey {
                owner: identity.clone(),
                key: "original".into(),
            },
            byte_length: bytes.len() as u64,
            generation: 1,
            media_type: Some("application/octet-stream".into()),
        },
        data: pl_core::chat::ContentData::Bytes(Arc::from(bytes)),
    };
    conversation::content::write_content(db, &content, true).await?;
    let payload = serde_json::to_string(&serde_json::json!({
        "sourceSchema":23,"sourceTable":origin,"sourceRow":source_row,"recordId":id,"revision":revision,"kind":kind,
        "byteLength":bytes.len(),"rawDigest":pl_core::context::content_hash(bytes),
        "originalOwner":identity.as_str(),"originalKey":"original",
    }))?;
    super::super::write_fact_receipt(
        db,
        effect,
        &super::super::FactReceiptWrite {
            item_id: identity.as_str().into(),
            revision,
            kind: "legacy_execution_record",
            payload,
        },
    )
    .await
}

async fn lifecycle(db: &impl ConnectionTrait) -> Result<()> {
    let mut after = (String::new(), String::new());
    loop {
        let rows = db.query_all_raw(statement(
            "SELECT atom_id,phase,effect_seq,suborder,fact_order,metadata FROM conversation_atom_facts WHERE (atom_id,phase)>(?,?) ORDER BY atom_id,phase LIMIT 128",
            vec![after.0.clone().into(),after.1.clone().into()],
        )).await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let id: String = row.try_get("", "atom_id")?;
            let phase: String = row.try_get("", "phase")?;
            let effect: i64 = row.try_get("", "effect_seq")?;
            let bytes: Vec<u8> = row.try_get("", "metadata")?;
            let source_row = serde_json::json!({"effectSeq":effect,"suborder":row.try_get::<i64>("","suborder")?,"factOrder":row.try_get::<i64>("","fact_order")?,"phase":phase});
            let atom: ChatAtom = match serde_json::from_slice(&bytes) {
                Ok(atom) => atom,
                Err(_) => {
                    archive(
                        db,
                        &format!("conversation_atom_facts:{phase}"),
                        &id,
                        1,
                        "unsupported_atom",
                        &bytes,
                        &source_row,
                    )
                    .await?;
                    after = (id, phase);
                    continue;
                }
            };
            ensure!(
                atom.id == id
                    && match atom.lifecycle {
                        pl_protocol::ChatAtomLifecycle::Active { .. } =>
                            matches!(phase.as_str(), "start" | "legacyAdmission"),
                        pl_protocol::ChatAtomLifecycle::Terminal { .. } =>
                            matches!(phase.as_str(), "terminal" | "legacyAdmission"),
                    },
                "legacy lifecycle phase identity conflict"
            );
            let fact =
                execution_lifecycle::ExecutionLifecycle::from_atom(&atom, u64::try_from(effect)?)?;
            execution_lifecycle::apply(db, &[fact]).await?;
            if serde_json::from_slice::<serde_json::Value>(&bytes)? != serde_json::to_value(&atom)?
            {
                archive(
                    db,
                    &format!("conversation_atom_facts:{phase}"),
                    &id,
                    1,
                    "unknown_atom_fields",
                    &bytes,
                    &source_row,
                )
                .await?;
            }
            after = (id, phase);
        }
    }
    Ok(())
}

async fn turn_index(db: &impl ConnectionTrait) -> Result<()> {
    db.execute_unprepared("ALTER TABLE history_turns RENAME TO legacy_history_turns")
        .await?;
    db.execute_unprepared(turns::CREATE).await?;
    let mut after = String::new();
    loop {
        let rows = db.query_all_raw(statement("SELECT turn_id,payload FROM legacy_history_turns WHERE turn_id>? ORDER BY turn_id LIMIT 128",vec![after.as_str().into()])).await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let id: String = row.try_get("", "turn_id")?;
            let bytes: String = row.try_get("", "payload")?;
            let old: crate::LegacyTurn = serde_json::from_str(&bytes)?;
            let original = db.query_one_raw(statement(
                "SELECT ordinal,last_write_seq,payload FROM history_items WHERE item_id=? AND kind='turn'",
                vec![crate::studio::thread_projection::order::turn_id(&id).into()],
            )).await?.context("legacy Turn has no execution placement; original database preserved")?;
            let item: ExecutionItem = super::legacy_execution_item::decode(
                original.try_get::<String>("", "payload")?.as_bytes(),
            )?;
            let ExecutionShape::Turn(turn) = item.state() else {
                anyhow::bail!("legacy Turn payload kind conflict")
            };
            ensure!(
                old.turn.id == id
                    && old.turn.thread_id == item.thread_id
                    && old.turn.state == *turn.state(),
                "legacy Turn business fact conflicts"
            );
            let effect = u64::try_from(original.try_get::<i64>("", "last_write_seq")?)?;
            let source = super::super::execution_sources::read(
                db,
                &[ChatSourceId::ForegroundTurn {
                    turn_id: id.clone(),
                }],
                effect,
            )
            .await?;
            let write = turns::TurnWrite {
                turn: old.turn,
                turn_order: u64::try_from(original.try_get::<i64>("", "ordinal")?)?,
                admitted_effect: source
                    .first()
                    .and_then(|source| source.started)
                    .map(|at| at.effect_seq),
                updated_effect: Some(effect),
                terminal_effect: turn.state().is_terminal().then_some(effect),
                context_disposition: old.context_disposition,
            };
            turns::apply(db, &write, &item.thread_id).await?;
            after = id;
        }
    }
    Ok(())
}

async fn old_items(db: &impl ConnectionTrait) -> Result<()> {
    let mut after = 0_i64;
    loop {
        let rows = db.query_all_raw(statement(
            "SELECT ordinal,item_id,turn_id,revision,kind,lifecycle,created_at,updated_at,last_write_seq,CAST(payload AS BLOB) AS bytes FROM history_items WHERE ordinal>? ORDER BY ordinal LIMIT 128",
            vec![after.into()],
        )).await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let id: String = row.try_get("", "item_id")?;
            let bytes: Vec<u8> = row.try_get("", "bytes")?;
            let effect: i64 = row.try_get("", "last_write_seq")?;
            let revision = u64::try_from(row.try_get::<i64>("", "revision")?)?;
            let source_row = serde_json::json!({"ordinal":row.try_get::<i64>("","ordinal")?,"turnId":row.try_get::<String>("","turn_id")?,"revision":revision,"kind":row.try_get::<String>("","kind")?,"lifecycle":row.try_get::<String>("","lifecycle")?,"createdAt":row.try_get::<i64>("","created_at")?,"updatedAt":row.try_get::<i64>("","updated_at")?,"lastWriteSeq":effect});
            let item = schema::legacy_execution_item::decode(&bytes).ok();
            let mut covered = false;
            if let Some(item) = item {
                ensure!(
                    item.id == id
                        && item.ordinal == u64::try_from(row.try_get::<i64>("", "ordinal")?)?
                        && item.revision == revision
                        && item.turn_id == row.try_get::<String>("", "turn_id")?
                        && item.created_at == row.try_get::<i64>("", "created_at")?
                        && item.updated_at == row.try_get::<i64>("", "updated_at")?,
                    "legacy execution columns conflict with the original payload"
                );
                if let Some(mut life) = execution_lifecycle::read(db, &id).await? {
                    if let Some(order) = life.execution_order {
                        ensure!(order == item.ordinal, "legacy execution order conflicts");
                    }
                    life.execution_order = Some(item.ordinal);
                    if !item.turn_id.is_empty() {
                        if let Some(turn) = life.turn_id.as_ref() {
                            ensure!(
                                turn == &item.turn_id,
                                "legacy execution Turn binding conflicts"
                            );
                        }
                        life.turn_id = Some(item.turn_id.clone());
                    }
                    execution_lifecycle::apply(db, &[life]).await?;
                }

                if let ExecutionShape::Tool(tool) = item.state() {
                    preserve_invocation(db, &item, tool).await?;
                }
                let exact_shape = serde_json::from_slice::<serde_json::Value>(&bytes).ok()
                    == Some(serde_json::to_value(&item)?);
                if let ExecutionShape::Turn(turn) = item.state() {
                    covered = exact_shape
                        && turns::read(db, &item.turn_id).await?.is_some_and(|stored| {
                            stored.turn.state == *turn.state()
                                && stored.turn.input_id.as_deref() == turn.input_id()
                        });
                } else if let Some(original) = conversation::read_item(db, &id).await?
                    && item.is_terminal()
                {
                    let value: serde_json::Value = serde_json::from_slice(&original.payload)?;
                    let effect = value["sourceEffectSeq"].as_u64();
                    let database = db
                        .query_one_raw(statement(
                            "SELECT database_id FROM history_meta WHERE id=1",
                            vec![],
                        ))
                        .await?
                        .context("history database identity missing")?
                        .try_get::<String>("", "database_id")?;
                    if let Some(effect) = effect
                        && let Ok(draft) =
                            crate::studio::runtime::chat_item::completion_draft_reusing(
                                &item,
                                effect,
                                &database,
                                &original.contents,
                            )
                    {
                        let expected: serde_json::Value = serde_json::from_slice(&draft.payload)?;
                        covered = exact_shape
                            && expected["type"] == value["type"]
                            && expected["data"] == value["data"]
                            && draft.contents == original.contents;
                        if let ExecutionShape::Tool(tool) = item.state() {
                            // Plan completions intentionally carry the document, not the invocation.
                            // Only a real saved task can prove that those original arguments survive.
                            let arguments_owned = original.contents.values().any(|content| {
                                content.descriptor.key.key
                                    == crate::studio::runtime::chat_item::TOOL_ARGUMENTS_FIELD
                            });
                            if !arguments_owned {
                                covered = false;
                            }
                            ensure!(
                                !tool.invocation().tool_call_id().is_empty(),
                                "legacy tool call identity is empty"
                            );
                        }
                    }
                }
                if let Some(message_id) =
                    crate::studio::thread_projection::order::business_id("message", &id)
                {
                    db.execute_raw(statement(
                        "INSERT INTO history_message_identities(message_id,item_id,sequence,digest,last_write_seq) VALUES(?,?,?,NULL,?) ON CONFLICT(message_id) DO NOTHING",
                        vec![message_id.into(),id.clone().into(),effect.into(),effect.into()],
                    )).await?;
                }
            }
            if !covered {
                archive(
                    db,
                    "history_items",
                    &id,
                    revision,
                    &row.try_get::<String>("", "kind")?,
                    &bytes,
                    &source_row,
                )
                .await?;
            }
            after = row.try_get("", "ordinal")?;
        }
    }
    Ok(())
}

async fn preserve_invocation(
    db: &impl ConnectionTrait,
    item: &ExecutionItem,
    tool: &pl_protocol::ThreadToolItem,
) -> Result<()> {
    let call = tool.invocation();
    let Some(row) = db
        .query_one_raw(statement(
            "SELECT task_payload FROM history_tool_tasks WHERE call_id=?",
            vec![call.tool_call_id().into()],
        ))
        .await?
    else {
        return Ok(());
    };
    let mut payload: serde_json::Value =
        serde_json::from_str(&row.try_get::<String>("", "task_payload")?)?;
    for (field, expected) in [
        ("callId", call.tool_call_id()),
        ("toolId", call.name()),
        ("turnId", item.turn_id.as_str()),
    ] {
        ensure!(
            payload
                .get(field)
                .is_none_or(|value| value.as_str() == Some(expected)),
            "legacy tool invocation conflicts with its real task"
        );
    }
    if let Some(value) = payload.get("invocation").filter(|value| !value.is_null()) {
        let invocation: pl_core::model::ModelToolCall = serde_json::from_value(value.clone())?;
        ensure!(
            invocation.call_id == call.tool_call_id()
                && invocation.tool_id == call.name()
                && invocation.arguments.content() == call.arguments(),
            "legacy task arguments conflict"
        );
        return Ok(());
    }
    // The old projection retained argument text, not the original OpaquePayload format.
    // This explicit import tag records that limit; it does not claim a provider JSON format.
    let invocation = pl_core::model::ModelToolCall {
        call_id: call.tool_call_id().into(),
        tool_id: call.name().into(),
        arguments: pl_core::context::OpaquePayload::new(
            "anywork.legacy-tool-arguments",
            1,
            call.arguments(),
        )?,
        presentation_contract: call
            .presentation_contract()
            .map(pl_core::model::ToolPresentationContract::new),
        rejection: None,
    };
    payload["invocation"] = serde_json::to_value(invocation)?;
    db.execute_raw(statement(
        "UPDATE history_tool_tasks SET task_payload=? WHERE call_id=?",
        vec![
            serde_json::to_string(&payload)?.into(),
            call.tool_call_id().into(),
        ],
    ))
    .await?;
    Ok(())
}

async fn upgrade(db: &impl ConnectionTrait) -> Result<()> {
    ensure!(
        version(db).await? == 23,
        "execution facts require schema 23"
    );
    display_block_order::validate(db).await?;
    ensure!(db.query_one_raw(statement(
        "SELECT 1 AS occupied FROM conversation_contents WHERE owner_key GLOB '23:legacy-execution-record*'
         UNION ALL SELECT 1 FROM conversation_content_chunks WHERE owner_key GLOB '23:legacy-execution-record*'
         UNION ALL SELECT 1 FROM history_fact_receipts WHERE kind='legacy_execution_record' LIMIT 1", vec![])).await?.is_none(),
        "reserved legacy evidence namespace is already occupied; original database preserved");
    ensure!(db.query_one_raw(statement("SELECT 1 AS invalid FROM history_items WHERE ordinal<=0 OR item_id='' UNION ALL SELECT 1 FROM conversation_atom_facts WHERE atom_id='' LIMIT 1",vec![])).await?.is_none(),
        "legacy execution identity/order is invalid; original database preserved");
    let before = originals(db).await?;
    let identity = db
        .query_one_raw(statement(
            "SELECT thread_id,applied_write_seq FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .context("history identity missing")?;
    let thread: String = identity.try_get("", "thread_id")?;
    let cut = u64::try_from(identity.try_get::<i64>("", "applied_write_seq")?)?;
    super::super::checkpoint::read(db, &thread).await?;

    let legacy_high = db
        .query_one_raw(statement(
            "SELECT COALESCE(MAX(ordinal),0) AS value FROM history_items",
            vec![],
        ))
        .await?
        .context("execution watermark missing")?
        .try_get::<i64>("", "value")?;
    db.execute_unprepared(execution_lifecycle::CREATE).await?;
    lifecycle(db).await?;
    let mut after = 0;
    loop {
        let rows=db.query_all_raw(statement("SELECT seq,item_id,metadata FROM conversation_items WHERE seq>? ORDER BY seq LIMIT 128",vec![after.into()])).await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            after = row.try_get::<i64>("", "seq")?;
            let id: String = row.try_get("", "item_id")?;
            if execution_lifecycle::read(db, &id).await?.is_none() {
                let atom: ChatAtom =
                    serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
                execution_lifecycle::apply(
                    db,
                    &[execution_lifecycle::ExecutionLifecycle::from_atom(
                        &atom, cut,
                    )?],
                )
                .await?;
            }
        }
    }
    turn_index(db).await?;
    old_items(db).await?;
    let high = db
        .query_one_raw(statement(
            "SELECT MAX(?,COALESCE(MAX(execution_order),0)) AS value FROM execution_lifecycle",
            vec![legacy_high.into()],
        ))
        .await?
        .context("execution lifecycle watermark missing")?
        .try_get::<i64>("", "value")?;

    db.execute_unprepared(RECORDS).await?;
    db.execute_unprepared("DROP TABLE conversation_items;
        ALTER TABLE conversation_items_v2 RENAME TO conversation_items;
        CREATE INDEX conversation_items_by_class ON conversation_items(query_class,seq);
        CREATE INDEX conversation_items_by_parent_class ON conversation_items(parent_id,query_class,seq);
        CREATE INDEX conversation_items_by_parent ON conversation_items(parent_id,seq);
        CREATE INDEX conversation_items_tool ON conversation_items(parent_id,json_extract(metadata,'$.tool.name'),seq);
        CREATE INDEX conversation_items_text ON conversation_items(seq) WHERE json_extract(metadata,'$.kind') IN ('text','input');
        ALTER TABLE history_meta ADD COLUMN execution_order INTEGER NOT NULL DEFAULT 0 CHECK(execution_order>=0);").await?;
    ensure!(
        before == originals(db).await?,
        "canonical original bytes, identities, context or checkpoint changed; original database preserved"
    );
    db.execute_raw(statement(
        "UPDATE history_meta SET execution_order=?,schema_version=24 WHERE id=1",
        vec![high.into()],
    ))
    .await?;
    db.execute_unprepared("DROP TABLE history_items; DROP TABLE conversation_atom_facts; DROP TABLE legacy_history_turns;").await?;
    validate(db).await
}

pub(super) async fn validate(db: &impl ConnectionTrait) -> Result<()> {
    ensure!(
        version(db).await? == 24,
        "execution facts format is not current"
    );
    validate_business_tables(db).await?;
    model_route_head::validate_tables(db).await?;
    completion_boundary::validate_originals(db).await?;
    display_block_order::validate_display(db).await?;
    for query in [
        "SELECT seq,item_id,query_class,parent_id,payload,metadata FROM conversation_items LIMIT 0",
        "SELECT identity,kind,source_kind,source_identity,turn_id,attempt_id,call_id,tool_name,text_channel,delivery,source_order,execution_order,started_effect,started_suborder,started_at,ended_effect,ended_suborder,finished_at,outcome,completion_item_id,last_write_seq FROM execution_lifecycle LIMIT 0",
        "SELECT turn_id,turn_order,admitted_effect,updated_effect,terminal_effect,payload,context_disposition FROM history_turns LIMIT 0",
        "SELECT execution_order,applied_write_seq,database_id,thread_id FROM history_meta LIMIT 0",
    ] {
        db.query_all_raw(statement(query, vec![])).await?;
    }
    for (table, primary, integer_primary, unique) in [
        ("conversation_items", &["seq"][..], true, &["item_id"][..]),
        ("execution_lifecycle", &["identity"][..], false, &[][..]),
        ("history_turns", &["turn_id"][..], false, &[][..]),
    ] {
        validate_keys(db, table, primary, integer_primary, unique).await?;
    }
    for (table, index, columns, predicate, expression) in [
        (
            "execution_lifecycle",
            "execution_lifecycle_active",
            &[Some("identity")][..],
            Some("ended_effect IS NULL AND outcome IS NULL"),
            None,
        ),
        (
            "execution_lifecycle",
            "execution_lifecycle_turn",
            &[Some("turn_id"), Some("source_order"), Some("identity")][..],
            None,
            None,
        ),
        (
            "execution_lifecycle",
            "execution_lifecycle_call",
            &[Some("call_id"), Some("identity")][..],
            Some("call_id IS NOT NULL"),
            None,
        ),
        (
            "history_turns",
            "history_turns_order",
            &[Some("turn_order"), Some("turn_id")][..],
            None,
            None,
        ),
        (
            "history_turns",
            "history_turns_terminal",
            &[Some("terminal_effect"), Some("turn_order"), Some("turn_id")][..],
            Some("terminal_effect IS NOT NULL"),
            None,
        ),
        (
            "conversation_items",
            "conversation_items_by_class",
            &[Some("query_class"), Some("seq")][..],
            None,
            None,
        ),
        (
            "conversation_items",
            "conversation_items_by_parent_class",
            &[Some("parent_id"), Some("query_class"), Some("seq")][..],
            None,
            None,
        ),
        (
            "conversation_items",
            "conversation_items_by_parent",
            &[Some("parent_id"), Some("seq")][..],
            None,
            None,
        ),
        (
            "conversation_items",
            "conversation_items_tool",
            &[Some("parent_id"), None, Some("seq")][..],
            None,
            Some("json_extract(metadata,'$.tool.name')"),
        ),
        (
            "conversation_items",
            "conversation_items_text",
            &[Some("seq")][..],
            Some("json_extract(metadata,'$.kind') IN ('text','input')"),
            None,
        ),
    ] {
        validate_index(db, table, index, columns, predicate, expression).await?;
    }
    for old in [
        "history_items",
        "conversation_atom_facts",
        "legacy_history_turns",
    ] {
        ensure!(
            db.query_one_raw(statement(
                "SELECT 1 AS present FROM sqlite_schema WHERE type='table' AND name=?",
                vec![old.into()]
            ))
            .await?
            .is_none(),
            "retired execution table remains in current format"
        );
    }
    Ok(())
}

/// 只检查 SQLite 的索引结构，不扫描原件或执行恢复正文。
async fn validate_index(
    db: &impl ConnectionTrait,
    table: &str,
    index: &str,
    expected: &[Option<&str>],
    predicate: Option<&str>,
    expression: Option<&str>,
) -> Result<()> {
    let row = db
        .query_one_raw(statement(
            "SELECT sql FROM sqlite_schema WHERE type='index' AND tbl_name=? AND name=?",
            vec![table.into(), index.into()],
        ))
        .await?
        .with_context(|| format!("history index {index} is missing"))?;
    let normalize = |value: &str| {
        value
            .chars()
            .filter(|value| !value.is_whitespace())
            .flat_map(char::to_lowercase)
            .collect::<String>()
    };
    let sql = normalize(&row.try_get::<String>("", "sql")?);
    ensure!(
        (predicate.is_some() == sql.contains("where"))
            && predicate
                .map(normalize)
                .is_none_or(|predicate| sql.ends_with(&format!("where{predicate}")))
            && expression
                .map(normalize)
                .is_none_or(|expression| sql.contains(&expression)),
        "history index {index} has a different predicate or expression"
    );
    let columns=db.query_all_raw(statement(r#"SELECT name,coll,"desc" AS descending FROM pragma_index_xinfo(?) WHERE key=1 ORDER BY seqno"#,vec![index.into()])).await?;
    ensure!(
        columns.len() == expected.len(),
        "history index {index} has different columns"
    );
    for (actual, expected) in columns.iter().zip(expected) {
        ensure!(
            actual.try_get::<Option<String>>("", "name")?.as_deref() == *expected
                && actual.try_get::<String>("", "coll")? == "BINARY"
                && actual.try_get::<i64>("", "descending")? == 0,
            "history index {index} has different order or comparison semantics"
        );
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use sea_orm::{Database, DatabaseConnection};
    const THREAD: &str = "execution-migration";

    /// Explicit manual fixture import. The source is read-only and is copied before migration.
    #[tokio::test]
    #[ignore = "manual nonempty production-shaped history migration measurement"]
    async fn measure_existing_history_migration() -> Result<()> {
        let source = std::env::var("ANYWORK_MIGRATION_SOURCE")?;
        let output = std::env::var("ANYWORK_MIGRATION_OUTPUT")?;
        ensure!(
            !std::path::Path::new(&output).exists(),
            "measurement output already exists"
        );
        std::fs::copy(&source, &output)?;
        let probe = Database::connect(format!("sqlite://{output}?mode=ro")).await?;
        let row = probe
            .query_one_raw(statement("SELECT thread_id FROM history_meta", vec![]))
            .await?
            .context("missing fixture identity")?;
        let id: String = row.try_get("", "thread_id")?;
        let original = originals(&probe).await?;
        probe.close().await?;
        let history =
            crate::studio::storage::history::HistoryStore::open(std::path::Path::new(&output), &id)
                .await?;
        let started = std::time::Instant::now();
        history.prepare_history_access().await?;
        let db = &history.writer().await?.db;
        assert_eq!(originals(db).await?, original);
        validate(db).await?;
        let counts = db.query_one_raw(statement(
            "SELECT (SELECT count(*) FROM conversation_items) AS originals,(SELECT count(*) FROM execution_lifecycle) AS lifecycle,(SELECT count(*) FROM history_turns) AS turns,(SELECT count(*) FROM history_fact_receipts WHERE kind='legacy_execution_record') AS legacy",
            vec![],
        )).await?.context("missing migrated counts")?;
        eprintln!(
            "HISTORY_MIGRATION_METRICS {}",
            serde_json::json!({
                "threadId":id,"elapsedMs":started.elapsed().as_millis(),
                "originals":counts.try_get::<i64>("", "originals")?,
                "lifecycle":counts.try_get::<i64>("", "lifecycle")?,
                "turns":counts.try_get::<i64>("", "turns")?,
                "legacy":counts.try_get::<i64>("", "legacy")?,
            })
        );
        Ok(())
    }

    async fn fixture() -> Result<(tempfile::TempDir, DatabaseConnection)> {
        let dir = tempfile::tempdir()?;
        let mut options = sea_orm::ConnectOptions::new(format!(
            "sqlite://{}?mode=rwc",
            dir.path().join("history.sqlite").display()
        ));
        options
            .max_connections(1)
            .min_connections(1)
            .sqlx_logging(false);
        let db = Database::connect(options).await?;
        let migrator = Migrator {
            thread_id: THREAD.into(),
            bot_root: None,
            execution_identity: None,
        };
        let steps = migrator
            .migrations()
            .iter()
            .take_while(|step| step.name() != EXECUTION_FACTS)
            .count();
        migrator.up(&db, Some(u32::try_from(steps)?)).await?;
        assert_eq!(version(&db).await?, 23);
        Ok((dir, db))
    }
    async fn old_table(db: &impl ConnectionTrait) -> Result<bool> {
        Ok(db.query_one_raw(statement("SELECT 1 AS present FROM sqlite_schema WHERE type='table' AND name='history_items'",vec![])).await?.is_some())
    }
    async fn seed(db: &impl ConnectionTrait) -> Result<(Vec<u8>, Vec<u8>)> {
        let metadata = super::super::super::conversation::tests::metadata("raw-original");
        let mut draft = pl_core::chat::ChatDraft::new(
            "raw-original",
            "diagnostic",
            Arc::from([0u8, 255, 1, 240]),
        );
        draft.metadata = metadata;
        conversation::append_records(db, [&pl_core::chat::ChatItem::complete(draft, 1)], true)
            .await?;
        let old =
            br#"{"futureKind":"vendor","opaque":[0,255],"nested":{"unrecognized":true}}"#.to_vec();
        db.execute_raw(statement("INSERT INTO history_items(ordinal,item_id,turn_id,kind,revision,lifecycle,created_at,updated_at,payload,last_write_seq) VALUES(7,'same-id','','unsupported',3,'open',1,2,?,2)",vec![String::from_utf8(old.clone())?.into()])).await?;
        let phase = br#"{"futureAtom":true}"#.to_vec();
        db.execute_raw(statement("INSERT INTO conversation_atom_facts(effect_seq,suborder,atom_id,phase,fact_order,metadata) VALUES(1,0,'same-id','start',0,?)",vec![phase.clone().into()])).await?;
        db.execute_unprepared("UPDATE history_meta SET applied_write_seq=2")
            .await?;
        Ok((old, phase))
    }
    #[tokio::test]
    async fn failed_real_migration_rolls_back_and_retry_exports_unknown_bytes_without_fake_completion()
    -> Result<()> {
        let (dir, db) = fixture().await?;
        let (old, phase) = seed(&db).await?;
        let before = originals(&db).await?;
        db.execute_unprepared("CREATE TRIGGER reject_legacy_evidence BEFORE INSERT ON history_fact_receipts WHEN NEW.kind='legacy_execution_record' BEGIN SELECT RAISE(ABORT,'injected evidence save failure'); END;").await?;
        assert!(
            super::super::prepare(&db, THREAD, Preparation::Schema, None)
                .await
                .is_err()
        );
        assert_eq!(version(&db).await?, 23);
        assert!(old_table(&db).await?);
        assert_eq!(originals(&db).await?, before);
        assert!(db.query_one_raw(statement("SELECT 1 AS present FROM sqlite_schema WHERE type='table' AND name='execution_lifecycle'",vec![])).await?.is_none());
        db.execute_unprepared("DROP TRIGGER reject_legacy_evidence")
            .await?;
        super::super::prepare(&db, THREAD, Preparation::Schema, None).await?;
        assert_eq!(version(&db).await?, 24);
        assert!(!old_table(&db).await?);
        assert_eq!(originals(&db).await?, before);
        super::super::prepare(&db, THREAD, Preparation::Schema, None).await?;
        let store = HistoryStore::open(&dir.path().join("history.sqlite"), THREAD).await?;
        let heads = store.legacy_evidence_heads(None, 10).await?;
        assert_eq!(
            heads.len(),
            2,
            "same old identity in different source tables must not collide"
        );
        for head in &heads {
            assert_eq!(head.record_id, "same-id");
            let expected = if head.kind == "unsupported_atom" {
                &phase
            } else {
                &old
            };
            assert_eq!(head.raw_digest, pl_core::context::content_hash(expected));
            let mut bytes = Vec::new();
            while bytes.len() < head.byte_length as usize {
                let window = store
                    .read_legacy_evidence(
                        &head.evidence_id,
                        head.revision,
                        pl_protocol::ContentRange {
                            offset: bytes.len() as u64,
                            max_bytes: 2,
                        },
                    )
                    .await?;
                assert!(window.sealed && !window.bytes.is_empty());
                bytes.extend(window.bytes);
            }
            assert_eq!(&bytes, expected);
        }
        assert!(
            store.recovery_atom_starts(None, 128).await?.is_empty(),
            "unknown raw start must not become a fabricated active/completed item"
        );
        let original = store
            .read_chat_item("raw-original")
            .await?
            .context("opaque original")?;
        assert_eq!(original.payload.as_ref(), [0u8, 255, 1, 240]);
        assert_eq!(store.latest_execution_ordinal().await?, 7);
        store.close_for_deletion().await?;
        db.close().await?;
        Ok(())
    }
    #[tokio::test]
    async fn current_admission_rejects_missing_or_changed_execution_indexes_without_repair()
    -> Result<()> {
        for damage in [
            "DROP INDEX execution_lifecycle_active".to_owned(),
            "DROP INDEX conversation_items_by_parent".to_owned(),
            "DROP INDEX execution_lifecycle_active; CREATE INDEX execution_lifecycle_active ON execution_lifecycle(identity) WHERE outcome IS NULL".to_owned(),
            "DROP INDEX conversation_items_tool; CREATE INDEX conversation_items_tool ON conversation_items(seq,parent_id)".to_owned(),
            "CREATE TABLE replacement AS SELECT * FROM execution_lifecycle; DROP TABLE execution_lifecycle; ALTER TABLE replacement RENAME TO execution_lifecycle".to_owned(),
            format!("DROP TABLE execution_lifecycle;{}",execution_lifecycle::CREATE.replace("kind TEXT NOT NULL","kind TEXT COLLATE NOCASE NOT NULL")),
        ] {
            let (dir,db)=fixture().await?;seed(&db).await?;
            super::super::prepare(&db,THREAD,Preparation::Schema,None).await?;
            let originals=originals(&db).await?;
            db.execute_unprepared(&damage).await?;
            let schema=| |statement("SELECT json_group_array(sql) AS definition FROM (SELECT sql FROM sqlite_schema ORDER BY type,name)",vec![]);
            let before:String=db.query_one_raw(schema()).await?.context("schema")?.try_get("","definition")?;
            let cold=HistoryStore::open(&dir.path().join("history.sqlite"),THREAD).await?;
            assert!(pl_core::chat::ChatHistory::publication_seed(&cold).await.is_err(),"{damage}");
            assert!(cold.state.reader.get().is_none());
            assert_eq!(db.query_one_raw(schema()).await?.context("schema")?.try_get::<String>("","definition")?,before,"failed admission cannot repair the source");
            assert_eq!(super::originals(&db).await?,originals);
            db.close().await?;
        }
        Ok(())
    }

    #[tokio::test]
    async fn reserved_evidence_collision_preserves_the_old_database() -> Result<()> {
        let (_dir, db) = fixture().await?;
        seed(&db).await?;
        db.execute_unprepared("INSERT INTO history_fact_receipts(item_id,revision,kind,digest,payload,last_write_seq) VALUES('occupied',1,'legacy_execution_record','uninterpreted','{}',1)").await?;
        let before = originals(&db).await?;
        assert!(
            super::super::prepare(&db, THREAD, Preparation::Schema, None)
                .await
                .is_err()
        );
        assert_eq!(version(&db).await?, 23);
        assert!(old_table(&db).await?);
        assert_eq!(originals(&db).await?, before);
        db.close().await?;
        Ok(())
    }
    #[tokio::test]
    async fn a_checkpoint_from_another_history_cut_fails_before_deleting_any_old_fact() -> Result<()>
    {
        let (_dir, db) = fixture().await?;
        seed(&db).await?;
        let checkpoint = pl_core::thread::ThreadCheckpoint::capture(
            THREAD.into(),
            1,
            pl_core::thread::ThreadSnapshot {
                commit_sequence: 1,
                ..Default::default()
            },
        )?;
        super::super::write_published_checkpoint(&db, &checkpoint).await?;
        let before = originals(&db).await?;
        let error = super::super::prepare(&db, THREAD, Preparation::Schema, None)
            .await
            .unwrap_err();
        assert!(format!("{error:#}").contains("history fence"), "{error:#}");
        assert_eq!(version(&db).await?, 23);
        assert!(old_table(&db).await?);
        assert_eq!(originals(&db).await?, before);
        db.close().await?;
        Ok(())
    }
}
