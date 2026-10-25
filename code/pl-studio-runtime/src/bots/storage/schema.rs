//! Validation of the finite SQLite schemas this bot ledger has actually owned.
//! PRAGMA metadata supplies columns and conflict targets. SQLite exposes no
//! CHECK-expression metadata, so the two CHECK-bearing tables must retain their
//! declared DDL (ignoring whitespace/case, not parsing arbitrary SQL).

use super::statement;
use sea_orm::ConnectionTrait;

pub(super) const META_TABLE: &str = "CREATE TABLE bot_meta (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    schema_version INTEGER NOT NULL
)";

pub(super) const CARD_TABLE: &str = "CREATE TABLE bot_card_streams (
    identity TEXT PRIMARY KEY,
    bot_id TEXT NOT NULL, chat_id TEXT NOT NULL, message_id TEXT NOT NULL,
    thread_id TEXT NOT NULL, original_input TEXT NOT NULL,
    watch_input TEXT NOT NULL, turn_id TEXT NOT NULL,
    version INTEGER NOT NULL CHECK(version>0), state_json TEXT NOT NULL,
    updated_at INTEGER NOT NULL
)";

/// For pre6 only, declared migrations may establish missing tables/columns and
/// the pairing index. Existing identities/definitions are never repaired.
pub(super) async fn validate<C: ConnectionTrait>(db: &C, version: i64) -> anyhow::Result<()> {
    for (table, key) in [
        ("bot_meta", "id"),
        ("inbound_identities", "identity"),
        ("inbound_work", "identity"),
        ("thread_bindings", "chat_id"),
        ("observed_directs", "chat_id"),
        ("pairing_requests", "request_id"),
        ("send_operations", "operation_id"),
        ("binding_operations", "operation_id"),
        ("bot_card_streams", "identity"),
    ] {
        let columns = db
            .query_all_raw(statement(
                "SELECT name,type,\"notnull\",pk,hidden,dflt_value FROM pragma_table_xinfo(?)",
                vec![table.into()],
            ))
            .await?;
        if columns.is_empty() && version < 6 {
            continue;
        }
        // Historical file6/7 legitimately have no card table. The caller's
        // source classifier separately rejects unknown card/file hybrids.
        if columns.is_empty() && table == "bot_card_streams" {
            continue;
        }
        let mut primary_key = Vec::new();
        for column in columns {
            let name: String = column.try_get("", "name")?;
            let kind: String = column.try_get("", "type")?;
            let not_null: i64 = column.try_get("", "notnull")?;
            let pk: i64 = column.try_get("", "pk")?;
            let hidden: i64 = column.try_get("", "hidden")?;
            let default: Option<String> = column.try_get("", "dflt_value")?;
            let expected_type = if matches!(
                name.as_str(),
                "id" | "schema_version"
                    | "admitted_at"
                    | "generation"
                    | "binding_revision"
                    | "claimed_at"
                    | "updated_at"
                    | "revision"
                    | "created_at"
                    | "last_observed_at"
                    | "expected_revision"
                    | "attempt_count"
                    | "next_attempt_at"
                    | "version"
            ) {
                "INTEGER"
            } else {
                "TEXT"
            };
            if !kind.eq_ignore_ascii_case(expected_type)
                || hidden != 0
                || name != key && not_null != 1
                || default.as_deref() != column_default(table, &name)
            {
                return Err(incompatible(table));
            }
            if pk != 0 {
                primary_key.push((name, pk));
            }
        }
        if primary_key != [(key.to_string(), 1)] {
            return Err(incompatible(table));
        }
        if table != "bot_meta" && !unique_key(db, table, key, true).await? {
            return Err(incompatible(table));
        }
        if table == "pairing_requests" && !unique_key(db, table, "open_id", false).await? {
            let declared_index = db
                .query_one_raw(statement(
                    "SELECT name FROM pragma_index_list(?) WHERE name='pairing_open_id'",
                    vec![table.into()],
                ))
                .await?
                .is_some();
            // Pre6 may legitimately establish the index during migration, but
            // an incompatible existing declaration must not hide behind IF NOT EXISTS.
            if version >= 6 || declared_index {
                return Err(incompatible(table));
            }
        }
        let expected = match table {
            "bot_meta" => Some(META_TABLE),
            "bot_card_streams" => Some(CARD_TABLE),
            _ => None,
        };
        if let Some(expected) = expected {
            let row = db
                .query_one_raw(statement(
                    "SELECT sql FROM sqlite_schema WHERE type='table' AND name=?",
                    vec![table.into()],
                ))
                .await?
                .ok_or_else(|| incompatible(table))?;
            let ddl: String = row.try_get("", "sql")?;
            if normalized_ddl(&ddl) != normalized_ddl(expected) {
                return Err(incompatible(table));
            }
        }
    }
    Ok(())
}

fn column_default(table: &str, column: &str) -> Option<&'static str> {
    match (table, column) {
        ("thread_bindings" | "binding_operations", "target_json") => {
            Some("'{\"kind\":\"unproven\"}'")
        }
        ("inbound_work", "attachments") => Some("'[]'"),
        (
            "inbound_work",
            "generation" | "binding_revision" | "claimed_at" | "attempt_count" | "next_attempt_at",
        )
        | ("thread_bindings", "revision" | "generation" | "updated_at") => Some("0"),
        ("inbound_identities" | "send_operations", "bot_id")
        | (
            "inbound_work",
            "bot_id" | "chat_id" | "message_id" | "content_hash" | "text" | "open_id" | "chat_kind"
            | "app_id" | "project_id" | "creation_id" | "claimed_by" | "watch_input",
        )
        | ("thread_bindings", "creation_id" | "project_id" | "diagnostic")
        | ("send_operations", "segment_facts")
        | ("binding_operations", "thread_id") => Some("''"),
        ("thread_bindings", "status") => Some("'bound'"),
        ("send_operations", "send_identity") => Some("'{\"kind\":\"legacyText\"}'"),
        ("send_operations", "send_source") => Some("'null'"),
        _ => None,
    }
}

async fn unique_key<C: ConnectionTrait>(
    db: &C,
    table: &str,
    column: &str,
    primary: bool,
) -> anyhow::Result<bool> {
    let indexes = db
        .query_all_raw(statement(
            "SELECT name,\"unique\",origin,partial FROM pragma_index_list(?)",
            vec![table.into()],
        ))
        .await?;
    for index in indexes {
        if index.try_get::<i64>("", "unique")? != 1
            || index.try_get::<i64>("", "partial")? != 0
            || primary && index.try_get::<String>("", "origin")? != "pk"
        {
            continue;
        }
        let name: String = index.try_get("", "name")?;
        let keys = db
            .query_all_raw(statement(
                "SELECT name,coll,cid FROM pragma_index_xinfo(?) WHERE key=1",
                vec![name.into()],
            ))
            .await?;
        if keys.len() == 1
            && keys[0].try_get::<i64>("", "cid")? >= 0
            && keys[0].try_get::<String>("", "name")? == column
            && keys[0]
                .try_get::<String>("", "coll")?
                .eq_ignore_ascii_case("BINARY")
        {
            return Ok(true);
        }
    }
    Ok(false)
}

fn normalized_ddl(ddl: &str) -> String {
    // These two declared statements contain no string literals or comments.
    // Require the entire declaration, not a CHECK-looking substring that could
    // appear inside a comment, default string, or a weaker OR expression.
    ddl.chars()
        .filter(|c| !c.is_ascii_whitespace())
        .flat_map(char::to_lowercase)
        .collect()
}

fn incompatible(table: &str) -> anyhow::Error {
    crate::studio::startup::data_error(anyhow::anyhow!(
        "persisted bot schema has incompatible definitions or constraints in {table}; local recovery required"
    ))
}
