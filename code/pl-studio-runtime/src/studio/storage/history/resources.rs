//! Strict, bounded reads of resource facts already committed by this exact Thread.
use super::{HistoryStore, statement};
use anyhow::{Result, ensure};
use pl_core::{
    context::{ContextContent, ContextRecord, ResourceReference},
    thread::ToolDelivery,
};
use sea_orm::ConnectionTrait;

#[derive(Clone, Debug)]
pub(crate) struct ResourceFact {
    pub(crate) reference: ResourceReference,
    pub(crate) filename: Option<String>,
}

fn merge(found: &mut Option<ResourceFact>, fact: ResourceFact, id: &str) -> Result<()> {
    fact.reference.validate()?;
    if fact.reference.id() != id {
        return Ok(());
    }
    if let Some(previous) = found {
        ensure!(
            previous.reference == fact.reference,
            "conflicting canonical metadata for resource {id}"
        );
        if previous.filename.is_none() {
            previous.filename = fact.filename;
        }
    } else {
        *found = Some(fact);
    }
    Ok(())
}

pub(crate) fn context_resources(context: &[ContextContent]) -> Result<Vec<ResourceFact>> {
    let mut facts = Vec::new();
    for part in context {
        match part {
            ContextContent::Resource { reference } => facts.push(ResourceFact {
                reference: reference.clone(),
                filename: None,
            }),
            ContextContent::Opaque { payload } => {
                if let Some(attachment) = pl_model::runtime::decode_attachment(payload)? {
                    // Only the model-owned, already validated v2 boundary carries this optional
                    // display metadata. It never selects bytes or grants filesystem access.
                    let filename = if payload.version() == 2 {
                        serde_json::from_str::<serde_json::Value>(payload.content())?
                            .get("filename")
                            .and_then(serde_json::Value::as_str)
                            .map(str::to_owned)
                    } else {
                        None
                    };
                    facts.push(ResourceFact {
                        reference: attachment.reference,
                        filename,
                    });
                }
            }
            ContextContent::Text { .. } => {}
        }
    }
    Ok(facts)
}

pub(crate) fn delivery_resources(delivery: &ToolDelivery) -> Result<Vec<ResourceFact>> {
    let mut facts = context_resources(&delivery.delivered_context)?;
    // Failed/cancelled results may still have real observed originals. They are references, NOT
    // public intent. The trusted publication projection has a separate producer-proof check.
    facts.extend(context_resources(delivery.output.context())?);
    if let Some(receipt) = pl_tool::image::saved_view_image_receipt(delivery.output.payload())? {
        facts.push(ResourceFact {
            reference: receipt.original,
            filename: None,
        });
    }
    if let Some(receipt) = pl_tool::image_card::saved_image_card_receipt(delivery.output.payload())?
    {
        facts.push(ResourceFact {
            reference: receipt.image,
            filename: None,
        });
    }
    if let Some(receipt) =
        pl_tool::image_generation::saved_image_generation_receipt(delivery.output.payload())?
    {
        facts.push(ResourceFact {
            reference: receipt.original,
            filename: None,
        });
    }
    facts.extend(
        pl_tool::mcp::thread::saved_mcp_resource_references(delivery.output.payload())?
            .into_iter()
            .map(|reference| ResourceFact {
                reference,
                filename: None,
            }),
    );
    Ok(facts)
}

impl HistoryStore {
    pub(crate) async fn public_artifact_reference(
        &self,
        id: &str,
    ) -> Result<Option<ResourceReference>> {
        let Some(connection) = self.reader().await? else {
            return Ok(None);
        };
        let mut found = None;
        let mut after = String::new();
        loop {
            let rows = connection.db.query_all_raw(statement(
                "SELECT item_id,CASE WHEN length(CAST(payload AS BLOB))<=67108864 THEN payload END AS payload FROM history_items WHERE kind='publicArtifact' AND item_id>? AND instr(payload,?)>0 ORDER BY item_id LIMIT 1",
                vec![after.clone().into(), id.to_owned().into()],
            )).await?;
            if rows.is_empty() {
                break;
            }
            for row in rows {
                after = row.try_get("", "item_id")?;
                let payload: Option<String> = row.try_get("", "payload")?;
                let payload = payload.ok_or_else(|| {
                    anyhow::anyhow!("public artifact exceeds reliable metadata query budget")
                })?;
                let item: pl_protocol::ThreadItem = serde_json::from_str(&payload)?;
                ensure!(
                    item.thread_id == self.thread_id() && item.id == after,
                    "public artifact canonical identity mismatch"
                );
                let pl_protocol::ThreadItemState::PublicArtifact(artifact) = item.state() else {
                    anyhow::bail!("public artifact row has a different kind");
                };
                let resource = &artifact.resource;
                merge(
                    &mut found,
                    ResourceFact {
                        reference: ResourceReference::new(
                            resource.id.clone(),
                            resource.content_digest.clone(),
                            resource.byte_len,
                            resource.media_type.clone(),
                        )?,
                        filename: Some(artifact.display_name.clone()),
                    },
                    id,
                )?;
            }
        }
        Ok(found.map(|fact| fact.reference))
    }

    /// Candidate SQL never authorizes access: each matching row is decoded as its actual canonical
    /// type and all exact references are compared, including after model-context compaction.
    pub(crate) async fn resource_reference(&self, id: &str) -> Result<Option<ResourceFact>> {
        let Some(connection) = self.reader().await? else {
            return Ok(None);
        };
        let mut found = None;
        // An accepted, still-pending input is already a durable reference even before model
        // admission adds it to current_context. Hidden inputs need not have a visible User item.
        // Read the original checkpoint metadata, not a second input/resource index; the fence is
        // selected in the SAME SQLite statement so a concurrent writer cannot tear this proof.
        if let Some(row) = connection.db.query_one_raw(statement(
            "SELECT revision,context_revision,payload_hash,CASE WHEN length(CAST(payload AS BLOB))<=67108864 THEN payload END AS body,(SELECT applied_write_seq FROM history_meta WHERE id=1) AS fence FROM session_checkpoint WHERE id=1 AND instr(payload,?)>0",
            vec![id.to_owned().into()],
        )).await? {
            let body: Option<String> = row.try_get("", "body")?;
            let body = body.ok_or_else(|| anyhow::anyhow!("checkpoint resource proof exceeds reliable metadata query budget"))?;
            ensure!(
                pl_core::context::content_hash(body.as_bytes()) == row.try_get::<String>("", "payload_hash")?,
                "checkpoint resource proof hash mismatch"
            );
            let checkpoint: pl_core::thread::ThreadCheckpoint = serde_json::from_str(&body)?;
            ensure!(
                checkpoint.thread_id == self.thread_id()
                    && pl_core::thread::ThreadCheckpoint::supports_schema(checkpoint.schema_version)
                    && checkpoint.is_materialized()
                    && checkpoint.state.context.records.is_empty()
                    && checkpoint.state_revision == checkpoint.state.commit_sequence
                    && i64::try_from(checkpoint.state_revision)? == row.try_get::<i64>("", "revision")?
                    && i64::try_from(checkpoint.state.context.revision)? == row.try_get::<i64>("", "context_revision")?
                    && i64::try_from(checkpoint.history_fence)? == row.try_get::<i64>("", "fence")?,
                "checkpoint resource proof identity or history fence mismatch"
            );
            for record in checkpoint.state.inputs.iter() {
                ensure!(
                    !record.input.id.is_empty() && record.accepted_sequence > 0
                        && record.accepted_sequence <= checkpoint.state_revision,
                    "checkpoint input has no valid canonical admission proof"
                );
                for fact in context_resources(&record.input.context)? {
                    merge(&mut found, fact, id)?;
                }
            }
        }
        for (table, key, payload) in [
            ("current_context", "record_id", "payload"),
            ("history_tool_tasks", "call_id", "delivery_payload"),
            ("history_items", "item_id", "payload"),
        ] {
            let mut after = String::new();
            loop {
                let hash = if table == "current_context" {
                    ",payload_hash AS hash"
                } else {
                    ""
                };
                let sql = format!(
                    "SELECT {key} AS identity,CASE WHEN length(CAST({payload} AS BLOB))<=67108864 THEN {payload} END AS body{hash} FROM {table} WHERE {key}>? AND {payload} IS NOT NULL AND instr({payload},?)>0 ORDER BY {key} LIMIT 1"
                );
                let rows = connection
                    .db
                    .query_all_raw(statement(
                        &sql,
                        vec![after.clone().into(), id.to_owned().into()],
                    ))
                    .await?;
                if rows.is_empty() {
                    break;
                }
                for row in rows {
                    after = row.try_get("", "identity")?;
                    let body: Option<String> = row.try_get("", "body")?;
                    let body = body.ok_or_else(|| {
                        anyhow::anyhow!(
                            "canonical resource candidate exceeds reliable metadata budget"
                        )
                    })?;
                    ensure!(
                        body.len() <= 64 * 1024 * 1024,
                        "canonical resource candidate exceeds reliable metadata budget"
                    );
                    match table {
                        "current_context" => {
                            ensure!(
                                pl_core::context::content_hash(body.as_bytes())
                                    == row.try_get::<String>("", "hash")?,
                                "canonical context resource hash mismatch"
                            );
                            let record: ContextRecord = serde_json::from_str(&body)?;
                            ensure!(
                                record.id == after,
                                "canonical context resource identity mismatch"
                            );
                            for fact in context_resources(&record.content)? {
                                merge(&mut found, fact, id)?;
                            }
                        }
                        "history_tool_tasks" => {
                            let delivery: ToolDelivery = serde_json::from_str(&body)?;
                            ensure!(
                                delivery.call_id == after,
                                "canonical delivery resource identity mismatch"
                            );
                            for fact in delivery_resources(&delivery)? {
                                merge(&mut found, fact, id)?;
                            }
                        }
                        _ => {
                            let item: pl_protocol::ThreadItem = serde_json::from_str(&body)?;
                            ensure!(
                                item.thread_id == self.thread_id() && item.id == after,
                                "resource item belongs to another Thread"
                            );
                            if let pl_protocol::ThreadItemState::PublicArtifact(artifact) =
                                item.state()
                            {
                                let resource = &artifact.resource;
                                merge(
                                    &mut found,
                                    ResourceFact {
                                        reference: ResourceReference::new(
                                            resource.id.clone(),
                                            resource.content_digest.clone(),
                                            resource.byte_len,
                                            resource.media_type.clone(),
                                        )?,
                                        filename: Some(artifact.display_name.clone()),
                                    },
                                    id,
                                )?;
                            }
                        }
                    }
                }
            }
        }
        // A compacted user input no longer contributes a context record. The existing attachment
        // catalog supplies exact original metadata, but only its matching canonical USER item grants
        // the reference: a promoted/rejected draft alone cannot keep an orphan alive.
        if let Some(archive) = self.state.resources.get() {
            use tokio::io::AsyncReadExt;
            let file = match tokio::fs::File::open(archive.attachments()).await {
                Ok(file) => Some(file),
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => None,
                Err(error) => return Err(error.into()),
            };
            if let Some(file) = file {
                let mut bytes = Vec::new();
                file.take(64 * 1024 * 1024 + 1)
                    .read_to_end(&mut bytes)
                    .await?;
                ensure!(
                    bytes.len() <= 64 * 1024 * 1024,
                    "attachment ownership query exceeds reliable metadata budget; archive preserved"
                );
                let catalog: crate::studio::store::attachment::AttachmentCatalog =
                    toml::from_str(std::str::from_utf8(&bytes)?)?;
                ensure!(
                    catalog.schema_version
                        == crate::studio::store::attachment::ATTACHMENT_CATALOG_SCHEMA_VERSION
                        && catalog.thread_id == self.thread_id(),
                    "attachment catalog identity/version mismatch"
                );
                for record in catalog.records {
                    ensure!(
                        record.thread_id == self.thread_id(),
                        "attachment record belongs to another Thread"
                    );
                    let reference = ResourceReference::new(
                        format!(
                            "{}{}",
                            crate::resource_store::RESOURCE_ID_PREFIX,
                            record.content_sha256
                        ),
                        format!("sha256:{}", record.content_sha256),
                        record.byte_size,
                        record.media_type.clone(),
                    )?;
                    if reference.id() != id {
                        continue;
                    }
                    let mut after = String::new();
                    loop {
                        let rows = connection.db.query_all_raw(statement(
                            "SELECT item_id,CASE WHEN length(CAST(payload AS BLOB))<=67108864 THEN payload END AS payload FROM history_items WHERE kind='text' AND item_id>? AND instr(payload,?)>0 ORDER BY item_id LIMIT 1",
                            vec![after.clone().into(), record.id.clone().into()],
                        )).await?;
                        if rows.is_empty() {
                            break;
                        }
                        for row in rows {
                            after = row.try_get("", "item_id")?;
                            let payload: Option<String> = row.try_get("", "payload")?;
                            let payload = payload.ok_or_else(|| anyhow::anyhow!("input resource candidate exceeds reliable metadata query budget"))?;
                            let item: pl_protocol::ThreadItem = serde_json::from_str(&payload)?;
                            ensure!(
                                item.thread_id == self.thread_id() && item.id == after,
                                "input item canonical identity mismatch"
                            );
                            if let pl_protocol::ThreadItemState::Text(text) = item.state()
                                && text.channel() == pl_protocol::ThreadTextChannel::User
                                && let Some(attachment) = text
                                    .attachments()
                                    .iter()
                                    .find(|attachment| attachment.id == record.id)
                            {
                                ensure!(
                                    attachment.byte_size == record.byte_size
                                        && attachment.media_type == record.media_type,
                                    "canonical input attachment conflicts with its original metadata"
                                );
                                merge(
                                    &mut found,
                                    ResourceFact {
                                        reference: reference.clone(),
                                        filename: record.filename.clone(),
                                    },
                                    id,
                                )?;
                            }
                        }
                    }
                }
            }
        }
        Ok(found)
    }
}
