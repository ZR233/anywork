//! Transactional schema-5 → 6 accounting conversion. No effect replay or data reset.
use sea_orm::ConnectionTrait;

use super::{SessionStoreError, sqlite};
use crate::thread::ThreadCheckpoint;

pub(super) async fn convert_checkpoints(
    tx: &impl ConnectionTrait,
) -> Result<(), SessionStoreError> {
    let mut after = String::new();
    loop {
        let rows = tx
            .query_all_raw(sqlite::statement(
                "SELECT * FROM thread_checkpoints WHERE thread_id>? ORDER BY thread_id LIMIT 128",
                vec![after.clone().into()],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let thread_id: String = row.try_get("", "thread_id")?;
            after.clone_from(&thread_id);
            let indexed: i64 = row.try_get("", "schema_version")?;
            if indexed == i64::from(ThreadCheckpoint::SCHEMA_VERSION) {
                super::thread_checkpoint::decode_checkpoint(row, &thread_id)?;
                continue;
            }
            if indexed != 5 {
                return Err(SessionStoreError::Invalid(
                    "schema-6 migration requires the completed schema-5 boundary".into(),
                ));
            }
            // Validates hash, ownership, index and commit fences before rewriting any field.
            let envelope: String = row.try_get("", "envelope")?;
            let converted =
                super::thread_checkpoint::decode_checkpoint_at_schema(row, &thread_id, 5)?;
            let mut root: serde_json::Value = serde_json::from_str(&envelope)?;
            root["schemaVersion"] = serde_json::json!(ThreadCheckpoint::SCHEMA_VERSION);
            root["state"]["usageSummary"] = serde_json::to_value(converted.state.usage_summary)?;
            // Retain every other field, including bodies, identities and extension payloads.
            let envelope = serde_json::to_string(&root)?;
            let hash = crate::context::content_hash(envelope.as_bytes());
            tx.execute_raw(sqlite::statement(
                "UPDATE thread_checkpoints SET schema_version=6,envelope=?,payload_hash=? WHERE thread_id=?",
                vec![envelope.into(), hash.into(), thread_id.into()],
            ))
            .await?;
        }
    }
    Ok(())
}
