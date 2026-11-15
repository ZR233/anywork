//! 已发布旧执行条目的冻结解码器，仅用于正式数据升级。
use crate::{ExecutionItem, ExecutionShape};
use serde::{Deserialize, Serialize};
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LegacyExecutionItem {
    id: String,
    thread_id: String,
    turn_id: String,
    ordinal: u64,
    revision: u64,
    created_at: i64,
    updated_at: i64,
    state: ExecutionShape,
}
pub(in crate::studio::storage::history) fn decode(
    bytes: &[u8],
) -> serde_json::Result<ExecutionItem> {
    let old: LegacyExecutionItem = serde_json::from_slice(bytes)?;
    Ok(ExecutionItem::new(
        old.id,
        old.thread_id,
        old.turn_id,
        old.ordinal,
        old.revision,
        old.created_at,
        old.updated_at,
        old.state,
    ))
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct LegacyTurn {
    pub turn: pl_protocol::Turn,
    pub last_item_id: String,
    pub context_disposition: pl_protocol::ThreadContextDisposition,
}

/// 旧迁移测试从正式只读导出读取证据，不让正常恢复重新启用旧解码器。
#[cfg(test)]
pub(in crate::studio::storage::history) async fn fixture_seeds(
    store: &super::super::HistoryStore,
    ids: impl IntoIterator<Item = String>,
) -> anyhow::Result<std::collections::BTreeMap<String, ExecutionItem>> {
    use anyhow::{Context, ensure};
    use sea_orm::ConnectionTrait;
    let mut result = std::collections::BTreeMap::new();
    for id in ids {
        let connection = store
            .reader()
            .await?
            .context("prepared fixture connection")?;
        let row = connection.db.query_one_raw(super::statement("SELECT item_id,revision FROM history_fact_receipts WHERE kind='legacy_execution_record' AND json_extract(payload,'$.sourceTable')='history_items' AND json_extract(payload,'$.recordId')=? ORDER BY revision DESC LIMIT 1",vec![id.clone().into()])).await?;
        let Some(row) = row else { continue };
        let owner: String = row.try_get("", "item_id")?;
        let revision = u64::try_from(row.try_get::<i64>("", "revision")?)?;
        let mut bytes = Vec::new();
        loop {
            let window = store
                .read_legacy_evidence(
                    &owner,
                    revision,
                    pl_protocol::ContentRange {
                        offset: bytes.len() as u64,
                        max_bytes: 32768,
                    },
                )
                .await?;
            bytes.extend(window.bytes);
            if bytes.len() as u64 == window.available_through {
                break;
            }
            ensure!(!bytes.is_empty(), "fixture export did not advance");
        }
        result.insert(id, decode(&bytes)?);
    }
    Ok(result)
}

/// 对比被正式归档的旧行；只供旧迁移测试核实源列和原 payload，正常产品不使用。
#[cfg(test)]
pub(in crate::studio::storage::history) async fn fixture_facts(
    db: &impl sea_orm::ConnectionTrait,
    columns: &[&str],
    raw: bool,
) -> anyhow::Result<Vec<String>> {
    use super::{statement, version};
    use anyhow::{Context, ensure};
    if version(db).await? < 24 {
        let projection = if raw {
            columns[0].to_owned()
        } else {
            format!("json_array({})", columns.join(","))
        };
        return db
            .query_all_raw(statement(
                &format!("SELECT {projection} AS fact FROM history_items ORDER BY ordinal"),
                vec![],
            ))
            .await?
            .into_iter()
            .map(|row| Ok(row.try_get("", "fact")?))
            .collect();
    }
    let rows=db.query_all_raw(statement("SELECT payload FROM history_fact_receipts WHERE kind='legacy_execution_record' AND json_extract(payload,'$.sourceTable')='history_items'",vec![])).await?;
    let mut values = std::collections::BTreeMap::new();
    for row in rows {
        let head: serde_json::Value = serde_json::from_str(&row.try_get::<String>("", "payload")?)?;
        let chunks=db.query_all_raw(statement("SELECT byte_offset,data FROM conversation_content_chunks WHERE owner_key=? AND content_key=? ORDER BY byte_offset",vec![head["originalOwner"].as_str().context("owner")?.into(),head["originalKey"].as_str().context("key")?.into()])).await?;
        let mut bytes = Vec::new();
        for chunk in chunks {
            ensure!(
                chunk.try_get::<i64>("", "byte_offset")? == i64::try_from(bytes.len())?,
                "export chunk gap"
            );
            bytes.extend(chunk.try_get::<Vec<u8>>("", "data")?);
        }
        ensure!(
            Some(bytes.len() as u64) == head["byteLength"].as_u64()
                && pl_core::context::content_hash(&bytes)
                    == head["rawDigest"].as_str().context("digest")?,
            "old fixture export differs"
        );
        let payload = String::from_utf8(bytes)?;
        let row = &head["sourceRow"];
        let field = |column: &str| -> anyhow::Result<serde_json::Value> {
            Ok(match column {
                "item_id" => head["recordId"].clone(),
                "payload" => payload.clone().into(),
                "hex(payload)" => hex::encode_upper(payload.as_bytes()).into(),
                "turn_id" => row["turnId"].clone(),
                "created_at" => row["createdAt"].clone(),
                "updated_at" => row["updatedAt"].clone(),
                "last_write_seq" => row["lastWriteSeq"].clone(),
                column => row[column].clone(),
            })
        };
        let value = if raw {
            payload
        } else {
            serde_json::to_string(
                &columns
                    .iter()
                    .map(|column| field(column))
                    .collect::<anyhow::Result<Vec<_>>>()?,
            )?
        };
        values.insert(row["ordinal"].as_u64().context("old ordinal")?, value);
    }
    Ok(values.into_values().collect())
}
