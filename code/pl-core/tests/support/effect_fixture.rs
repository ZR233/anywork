//! Test-owned v2 fixture editing; all production migration work goes through its public entrypoint.
use pl_core::{context::content_hash, storage::SessionEntry};
use sea_orm::{ConnectionTrait, DatabaseBackend, DatabaseConnection, Statement};

pub async fn rewrite_effects(db: &DatabaseConnection, rewrite: impl Fn(&mut SessionEntry)) {
    for row in db
        .query_all_raw(Statement::from_string(
            DatabaseBackend::Sqlite,
            "SELECT * FROM session_entries ORDER BY session_id,id",
        ))
        .await
        .unwrap()
    {
        let encoded: String = row.try_get("", "envelope").unwrap();
        let mut entry: SessionEntry = serde_json::from_str(&encoded).unwrap();
        if !entry.id.starts_with("pl.resource.thread-commit.") {
            continue;
        }
        let original_id = entry.id.clone();
        rewrite(&mut entry);
        let envelope = serde_json::to_string(&entry).unwrap();
        db.execute_raw(Statement::from_sql_and_values(DatabaseBackend::Sqlite,
            "UPDATE session_entries SET id=?,type_id=?,envelope=?,payload_hash=? WHERE session_id=? AND id=?",
            vec![entry.id.into(), entry.type_id.into(), envelope.clone().into(), content_hash(envelope.as_bytes()).into(), entry.session_id.into(), original_id.into()])).await.unwrap();
    }
    for row in db
        .query_all_raw(Statement::from_string(
            DatabaseBackend::Sqlite,
            "SELECT * FROM session_entry_history ORDER BY session_id,sequence",
        ))
        .await
        .unwrap()
    {
        let encoded: String = row.try_get("", "envelope").unwrap();
        let mut batch: serde_json::Value = serde_json::from_str(&encoded).unwrap();
        for change in batch["changes"].as_array_mut().unwrap() {
            if change["kind"] == "put" {
                let mut entry: SessionEntry =
                    serde_json::from_value(change["entry"].clone()).unwrap();
                if entry.id.starts_with("pl.resource.thread-commit.") {
                    rewrite(&mut entry);
                    change["entry"] = serde_json::to_value(entry).unwrap();
                }
            }
        }
        let envelope = serde_json::to_string(&batch).unwrap();
        let hash = content_hash(envelope.as_bytes());
        let sequence = row.try_get::<i64>("", "sequence").unwrap();
        let session_id = row.try_get::<String>("", "session_id").unwrap();
        db.execute_raw(Statement::from_sql_and_values(DatabaseBackend::Sqlite,
            "UPDATE session_entry_history SET envelope=?,payload_hash=? WHERE session_id=? AND sequence=?",
            vec![envelope.into(), hash.clone().into(), session_id.clone().into(), sequence.into()])).await.unwrap();
        db.execute_raw(Statement::from_sql_and_values(
            DatabaseBackend::Sqlite,
            "UPDATE session_history_heads SET payload_hash=? WHERE session_id=? AND sequence=?",
            vec![hash.into(), session_id.into(), sequence.into()],
        ))
        .await
        .unwrap();
    }
}
