//! Read-only physical source validation. Completion and ordering belong to SeaORM, not this module.
//!
//! The pre-v3 compatibility columns come from a2ee7ccc's additive upgrader. Its initial v3
//! DDL did not contain performance_samples; fe748d74 introduced that table with format 4.
//! Formats 5/6 introduced the JSONL layout and detached performance projection; 981e2467
//! renamed its identity columns in format 7. Legacy tables may legitimately remain in 5..=7.
//! This boundary checks structure, constraints and SQL storage classes only. Payload/ref/hash
//! decoding and external blob verification belong to the named Atomic migration transaction.

use super::*;
use std::collections::BTreeMap;

// Frozen postconditions of the published fourth and fifth steps, not live-domain defaults.
const FINALIZED_FORMAT: i64 = 7;
const THROUGHPUT_EPOCH: i64 = 1;

struct Column {
    declaration: String,
    not_null: bool,
    primary_key: i64,
    default_value: Option<String>,
}
type Columns = BTreeMap<String, Column>;

pub(super) async fn validate(db: &impl ConnectionTrait, prefix: usize) -> Result<()> {
    let tables: BTreeSet<String> = db
        .query_all_raw(statement(
            "SELECT name FROM sqlite_schema WHERE type='table' AND name NOT GLOB 'sqlite_*'",
            vec![],
        ))
        .await?
        .into_iter()
        .map(|row| row.try_get("", "name").map_err(Into::into))
        .collect::<Result<_>>()?;
    if !tables.contains("calls_meta") {
        ensure!(
            prefix == 0
                && db.query_one_raw(statement(
                    "SELECT 1 FROM sqlite_schema WHERE name NOT GLOB 'sqlite_*' AND name<>'seaql_migrations' LIMIT 1",
                    vec![],
                )).await?.is_none(),
            "unversioned nonempty calls database; existing data preserved"
        );
        return Ok(());
    }
    for table in &tables {
        ensure!(
            matches!(
                table.as_str(),
                "calls_meta"
                    | "call_watermarks"
                    | "model_calls"
                    | "tool_calls"
                    | "call_bodies"
                    | "legacy_auxiliary_usage"
                    | "call_log_index"
                    | "call_usage_summary"
                    | "performance_samples"
                    | "seaql_migrations"
            ),
            "unknown calls source table {table}; existing data preserved"
        );
    }
    let meta = shape(db, "calls_meta", &["id"]).await?;
    columns(
        "calls_meta",
        &meta,
        &[
            ("id", "INTEGER"),
            ("schema_version", "INTEGER NOT NULL DEFAULT 0"),
        ],
        &[
            ("database_id", "TEXT"),
            ("pending_cleanup", "INTEGER NOT NULL DEFAULT 0"),
            ("throughput_epoch", "INTEGER NOT NULL DEFAULT 0"),
        ],
    )?;
    not_null("calls_meta", &meta, &["schema_version"])?;
    ensure!(
        db.query_one_raw(statement(
            "SELECT 1 FROM calls_meta WHERE id<>1 LIMIT 1",
            vec![]
        ))
        .await?
        .is_none(),
        "unexpected calls metadata identity; existing data preserved"
    );
    let version = format_version(db).await?;
    ensure!(
        (1..=FINALIZED_FORMAT).contains(&version),
        "unsupported calls schema {version}; existing data preserved"
    );
    if prefix >= 1 {
        for name in ["database_id", "pending_cleanup", "throughput_epoch"] {
            ensure!(
                meta.contains_key(name),
                "calls metadata column {name} is missing after schema migration; existing data preserved"
            );
        }
        let id: Option<String> = db
            .query_one_raw(statement(
                "SELECT database_id FROM calls_meta WHERE id=1",
                vec![],
            ))
            .await?
            .context("calls metadata is missing")?
            .try_get("", "database_id")?;
        ensure!(
            id.is_some_and(|id| !id.is_empty()),
            "calls database identity is missing after schema migration; existing data preserved"
        );
    }
    let epoch = if meta.contains_key("throughput_epoch") {
        db.query_one_raw(statement(
            "SELECT throughput_epoch FROM calls_meta WHERE id=1",
            vec![],
        ))
        .await?
        .context("calls metadata is missing")?
        .try_get::<i64>("", "throughput_epoch")?
    } else {
        0
    };
    ensure!(
        (0..=THROUGHPUT_EPOCH).contains(&epoch),
        "unknown calls throughput epoch {epoch}; existing data preserved"
    );
    ensure!(
        prefix < 4 || version == FINALIZED_FORMAT,
        "calls format conflicts with finalized migrations; existing data preserved"
    );
    ensure!(
        prefix < 5 || epoch == THROUGHPUT_EPOCH,
        "calls throughput epoch conflicts with completed migrations; existing data preserved"
    );

    // Before step 4 the published schema step preserves any supported existing format,
    // including an old export completed at format <5. Never infer export pending from it.
    let canonical = version >= 5 || prefix >= 1;
    let watermarks = shape(db, "call_watermarks", &["thread_id"]).await?;
    let watermark_fields = [
        ("admitted_write_seq", "INTEGER NOT NULL DEFAULT 0"),
        ("durable_write_seq", "INTEGER NOT NULL DEFAULT 0"),
    ];
    columns(
        "call_watermarks",
        &watermarks,
        &[("thread_id", "TEXT")],
        &watermark_fields,
    )?;
    if version >= 5 || prefix >= 3 {
        required("call_watermarks", &watermarks, &watermark_fields)?;
        not_null(
            "call_watermarks",
            &watermarks,
            &["admitted_write_seq", "durable_write_seq"],
        )?;
    }

    if version < 5 {
        // These are authoritative source tables, not disposable projections. Do not let
        // CREATE TABLE IF NOT EXISTS turn missing source data into a successful empty export.
        legacy_tables(db, &tables, prefix).await?;
    } else {
        // FinalizeLegacy only dropped these for inputs below 5; don't remove legal remnants.
        legacy_tables(db, &tables, 0).await?;
    }
    for (table, key, fields) in [
        (
            "legacy_auxiliary_usage",
            &["thread_id"][..],
            &[("thread_id", "TEXT"), ("payload", "TEXT")][..],
        ),
        (
            "call_log_index",
            &["thread_id", "call_id", "kind"][..],
            &[
                ("thread_id", "TEXT"),
                ("call_id", "TEXT"),
                ("kind", "TEXT"),
                ("revision", "INTEGER"),
                ("content_hash", "TEXT"),
                ("segment", "TEXT"),
                ("offset", "INTEGER"),
                ("length", "INTEGER"),
                ("truncated", "INTEGER"),
                ("recorded_at", "INTEGER"),
            ][..],
        ),
        (
            "call_usage_summary",
            &["root_thread_id", "thread_id", "purpose", "cost_currency"][..],
            &[
                ("root_thread_id", "TEXT"),
                ("thread_id", "TEXT"),
                ("purpose", "TEXT"),
                ("cost_currency", "TEXT"),
                ("amount", "REAL"),
                ("has_unpriced_usage", "INTEGER"),
                ("revision", "INTEGER"),
            ][..],
        ),
    ] {
        if canonical || tables.contains(table) {
            let actual = shape(db, table, key).await?;
            columns(table, &actual, fields, &[])?;
            let non_nullable: Vec<_> = fields
                .iter()
                .filter_map(|(name, _)| {
                    (*name != "content_hash"
                        && !(table == "legacy_auxiliary_usage" && *name == "thread_id"))
                        .then_some(*name)
                })
                .collect();
            not_null(table, &actual, &non_nullable)?;
        }
    }
    // v1..3 did not define this derived table. Missing it at those sources is legitimate.
    if version >= 4 || prefix >= 1 || tables.contains("performance_samples") {
        performance(db, version, prefix).await?;
    }
    for (name, table, keys) in [
        (
            "call_log_index_by_segment",
            "call_log_index",
            &[("segment", false)][..],
        ),
        (
            "call_usage_summary_by_root",
            "call_usage_summary",
            &[("root_thread_id", false)][..],
        ),
        (
            "performance_samples_by_completion",
            "performance_samples",
            &[
                ("completed_at", true),
                ("thread_id", true),
                ("call_id", true),
            ][..],
        ),
    ] {
        index(
            db,
            name,
            table,
            keys,
            canonical || version >= 4 && table == "performance_samples",
        )
        .await?;
    }
    Ok(())
}

async fn legacy_tables(
    db: &impl ConnectionTrait,
    tables: &BTreeSet<String>,
    prefix: usize,
) -> Result<()> {
    let active = format_version(db).await? < 5;
    for table in ["model_calls", "tool_calls", "call_bodies"] {
        if !active && !tables.contains(table) {
            continue;
        }
        let keys = if table == "call_bodies" {
            &["body_ref"][..]
        } else {
            &["thread_id", "call_id"][..]
        };
        let actual = shape(db, table, keys).await?;
        if active && prefix < 3 {
            // Published inline/reference columns contain JSON text or a sha256 text
            // reference, never opaque SQL BLOB values. The historical reader tolerated
            // absent columns with try_get(...).ok(); reject wrong stored value types here
            // instead of letting that tolerance silently erase an existing payload.
            let payload_columns = [
                "body_ref",
                "billing_ref",
                "body",
                "body_text",
                "body_json",
                "billing_body",
                "billing_json",
            ];
            let invalid: Vec<_> = payload_columns
                .into_iter()
                .filter(|column| actual.contains_key(*column))
                .map(|column| format!("typeof({column}) NOT IN ('null','text')"))
                .collect();
            if !invalid.is_empty() {
                ensure!(
                    db.query_one_raw(statement(
                        &format!(
                            "SELECT 1 FROM {table} WHERE {} LIMIT 1",
                            invalid.join(" OR ")
                        ),
                        vec![],
                    ))
                    .await?
                    .is_none(),
                    "invalid legacy calls payload storage in {table}; existing data preserved"
                );
            }
        }
        if table != "call_bodies" {
            not_null(table, &actual, keys)?;
            // Conversion is rowid-paged; a WITHOUT ROWID table is not the published source.
            db.query_all_raw(statement(
                &format!("SELECT rowid FROM {table} LIMIT 0"),
                vec![],
            ))
            .await?;
        }
        match table {
            "model_calls" => {
                let mut compatible = LEGACY_MODEL_COLUMNS.to_vec();
                compatible.extend([
                    ("body", "TEXT"),
                    ("body_text", "TEXT"),
                    ("body_json", "TEXT"),
                    ("billing_body", "TEXT"),
                    ("billing_json", "TEXT"),
                ]);
                columns(
                    table,
                    &actual,
                    &[("thread_id", "TEXT"), ("call_id", "TEXT")],
                    &compatible,
                )?;
                if prefix >= 1 {
                    required(table, &actual, LEGACY_MODEL_COLUMNS)?;
                }
            }
            "tool_calls" => {
                columns(
                    table,
                    &actual,
                    &[("thread_id", "TEXT"), ("call_id", "TEXT")],
                    &[
                        ("body_ref", "TEXT"),
                        ("turn_id", "TEXT"),
                        ("tool_id", "TEXT"),
                        ("revision", "INTEGER NOT NULL DEFAULT 0"),
                        ("admitted_at", "INTEGER NOT NULL DEFAULT 0"),
                        ("started_at", "INTEGER NOT NULL DEFAULT 0"),
                        ("finished_at", "INTEGER"),
                        ("status", "TEXT"),
                        ("terminal", "INTEGER NOT NULL DEFAULT 0"),
                        ("cancel_requested", "INTEGER NOT NULL DEFAULT 0"),
                        ("body", "TEXT"),
                        ("body_text", "TEXT"),
                        ("body_json", "TEXT"),
                    ],
                )?;
                if prefix >= 3 {
                    required(
                        table,
                        &actual,
                        &[
                            ("body_ref", "TEXT"),
                            ("turn_id", "TEXT"),
                            ("revision", "INTEGER"),
                            ("started_at", "INTEGER"),
                            ("finished_at", "INTEGER"),
                        ],
                    )?;
                }
            }
            "call_bodies" => {
                columns(
                    table,
                    &actual,
                    &[
                        ("body_ref", "TEXT"),
                        ("byte_length", "INTEGER"),
                        ("created_at", "INTEGER"),
                    ],
                    &[
                        ("body", "TEXT"),
                        ("body_text", "TEXT"),
                        ("body_json", "TEXT"),
                    ],
                )?;
                not_null(table, &actual, &["byte_length", "created_at"])?;
            }
            _ => unreachable!(),
        }
    }
    Ok(())
}

async fn performance(db: &impl ConnectionTrait, version: i64, prefix: usize) -> Result<()> {
    let table = "performance_samples";
    let actual = shape(db, table, &["thread_id", "call_id"]).await?;
    let identities = [
        ("provider_instance_id", "account_id"),
        ("provider_display_name", "account_display_name"),
        ("configured_model", "model_id"),
        ("reasoning_effort", "effort"),
    ];
    let mut compatible = vec![
        ("sent_model", "TEXT"),
        ("reported_model", "TEXT"),
        ("output_tokens", "INTEGER"),
        ("ttft_millis", "INTEGER"),
        ("decode_millis", "INTEGER"),
        ("response_millis", "INTEGER"),
    ];
    for (old, new) in identities {
        ensure!(
            !(actual.contains_key(old) && actual.contains_key(new)),
            "mixed calls performance identity columns {old}/{new}; existing data preserved"
        );
        compatible.extend([(old, "TEXT"), (new, "TEXT")]);
        if prefix >= 1 || version >= 7 {
            ensure!(
                !actual.contains_key(old),
                "old calls performance identity {old} conflicts with current schema; existing data preserved"
            );
            required(table, &actual, &[(new, "TEXT")])?;
        }
    }
    columns(
        table,
        &actual,
        &[
            ("thread_id", "TEXT"),
            ("call_id", "TEXT"),
            ("completed_at", "INTEGER"),
        ],
        &compatible,
    )?;
    not_null(table, &actual, &["thread_id", "call_id", "completed_at"])?;
    if prefix >= 1 || version >= 7 {
        required(table, &actual, &compatible[..6])?;
    }
    let foreign_keys = db
        .query_all_raw(statement(
            "PRAGMA foreign_key_list(performance_samples)",
            vec![],
        ))
        .await?;
    if foreign_keys.is_empty() {
        return Ok(());
    }
    ensure!(
        version <= 5 && prefix < 4 && foreign_keys.len() == 2,
        "unexpected calls performance foreign key; existing data preserved"
    );
    let id: i64 = foreign_keys[0].try_get("", "id")?;
    for (seq, key) in [(0i64, "thread_id"), (1, "call_id")] {
        let row = foreign_keys
            .iter()
            .find(|row| {
                row.try_get::<i64>("", "seq")
                    .is_ok_and(|value| value == seq)
            })
            .context("incomplete calls performance foreign key")?;
        ensure!(
            row.try_get::<i64>("", "id")? == id
                && row.try_get::<String>("", "table")? == "model_calls"
                && row.try_get::<String>("", "from")? == key
                && row.try_get::<String>("", "to")? == key
                && row.try_get::<String>("", "on_delete")? == "CASCADE"
                && row.try_get::<String>("", "on_update")? == "NO ACTION",
            "unknown calls performance foreign key; existing data preserved"
        );
    }
    Ok(())
}

async fn shape(db: &impl ConnectionTrait, table: &str, key: &[&str]) -> Result<Columns> {
    let rows = db
        .query_all_raw(statement(&format!("PRAGMA table_xinfo({table})"), vec![]))
        .await?;
    ensure!(
        !rows.is_empty(),
        "calls source table {table} is missing; existing data preserved"
    );
    let actual: Columns = rows
        .into_iter()
        .map(|row| {
            ensure!(
                row.try_get::<i64>("", "hidden")? == 0,
                "unexpected hidden calls source column on {table}; existing data preserved"
            );
            Ok((
                row.try_get("", "name")?,
                Column {
                    declaration: row.try_get::<String>("", "type")?.to_ascii_uppercase(),
                    not_null: row.try_get::<i64>("", "notnull")? != 0,
                    primary_key: row.try_get("", "pk")?,
                    default_value: row.try_get("", "dflt_value")?,
                },
            ))
        })
        .collect::<Result<_>>()?;
    let mut actual_key: Vec<_> = actual
        .iter()
        .filter(|(_, column)| column.primary_key > 0)
        .collect();
    actual_key.sort_by_key(|(_, column)| column.primary_key);
    ensure!(
        actual_key
            .iter()
            .map(|(name, _)| name.as_str())
            .eq(key.iter().copied()),
        "calls source table {table} has an unknown primary key; existing data preserved"
    );
    for row in db
        .query_all_raw(statement(&format!("PRAGMA index_list({table})"), vec![]))
        .await?
    {
        let origin: String = row.try_get("", "origin")?;
        ensure!(
            origin == "pk" || row.try_get::<i64>("", "unique")? == 0,
            "unexpected calls source unique constraint on {table}; existing data preserved"
        );
        if origin == "pk" {
            let name: String = row.try_get("", "name")?;
            // SQLite owns autoindex names. Quote them before inspecting the actual PK
            // collation and direction, which table_xinfo alone cannot expose.
            let quoted = name.replace('"', "\"\"");
            for key in db
                .query_all_raw(statement(
                    &format!("PRAGMA index_xinfo(\"{quoted}\")"),
                    vec![],
                ))
                .await?
            {
                if key.try_get::<i64>("", "key")? == 1 {
                    ensure!(
                        key.try_get::<i64>("", "desc")? == 0
                            && key.try_get::<String>("", "coll")? == "BINARY",
                        "unknown calls source primary key semantics on {table}; existing data preserved"
                    );
                }
            }
        }
    }
    let invalid = key
        .iter()
        .map(|key| format!("{key} IS NULL"))
        .collect::<Vec<_>>()
        .join(" OR ");
    ensure!(
        db.query_one_raw(statement(
            &format!("SELECT 1 FROM {table} WHERE {invalid} LIMIT 1"),
            vec![]
        ))
        .await?
        .is_none(),
        "calls source table {table} has a null identity; existing data preserved"
    );
    if table != "performance_samples" {
        ensure!(
            db.query_all_raw(statement(
                &format!("PRAGMA foreign_key_list({table})"),
                vec![]
            ))
            .await?
            .is_empty(),
            "unexpected calls source foreign key on {table}; existing data preserved"
        );
    }
    Ok(actual)
}

fn columns(
    table: &str,
    actual: &Columns,
    fixed: &[(&str, &str)],
    compatible: &[(&str, &str)],
) -> Result<()> {
    required(table, actual, fixed)?;
    for (name, column) in actual {
        let declaration = fixed
            .iter()
            .chain(compatible)
            .find_map(|(field, declaration)| (*field == name.as_str()).then_some(*declaration))
            .with_context(|| {
                format!("unknown calls source column {table}.{name}; existing data preserved")
            })?;
        // Legacy declarations may include the published additive default, but their SQL
        // affinity must still match; missing columns are only filled by that known rule.
        ensure!(
            column.declaration == declaration.split_whitespace().next().unwrap_or_default(),
            "unknown calls source column type {table}.{name}; existing data preserved"
        );
        // These are frozen published declarations, not SQL parsed from the database.
        // ADD COLUMN only repairs absence: an existing contradictory constraint must
        // fail preflight, even before the schema/summary steps can commit.
        ensure!(
            !declaration.contains("NOT NULL") || column.not_null,
            "calls source column {table}.{name} lacks its NOT NULL constraint; existing data preserved"
        );
        let allowed: &[Option<&str>] = match (table, name.as_str()) {
            ("calls_meta", "schema_version")
            | ("call_watermarks", "admitted_write_seq" | "durable_write_seq")
            | (
                "model_calls" | "tool_calls",
                "revision" | "admitted_at" | "started_at" | "terminal",
            ) => {
                // Fresh v3/v4 DDL omitted DEFAULT; the published v1/v2 additive
                // upgrader used DEFAULT 0. Both survive later formats/prefixes.
                &[None, Some("0")]
            }
            ("calls_meta", "pending_cleanup" | "throughput_epoch")
            | ("model_calls", "has_unpriced_usage")
            | ("tool_calls", "cancel_requested")
            | ("call_log_index", "truncated")
            | ("call_usage_summary", "amount" | "has_unpriced_usage" | "revision") => &[Some("0")],
            ("call_usage_summary", "purpose" | "cost_currency") => &[Some("''")],
            (
                "model_calls" | "tool_calls" | "call_bodies",
                "body" | "body_text" | "body_json" | "billing_body" | "billing_json",
            ) => {
                // Earlier inline layouts are supported by the published reader,
                // without a published constraint/default declaration to invent here.
                continue;
            }
            _ => &[None],
        };
        ensure!(
            allowed.contains(&column.default_value.as_deref()),
            "calls source column {table}.{name} has an unsupported DEFAULT; existing data preserved"
        );
    }
    Ok(())
}

fn required(table: &str, actual: &Columns, fields: &[(&str, &str)]) -> Result<()> {
    for (name, _) in fields {
        ensure!(
            actual.contains_key(*name),
            "calls source column {table}.{name} is missing; existing data preserved"
        );
    }
    Ok(())
}

fn not_null(table: &str, actual: &Columns, fields: &[&str]) -> Result<()> {
    for name in fields {
        ensure!(
            actual.get(*name).is_some_and(|column| column.not_null),
            "calls source column {table}.{name} lacks its NOT NULL constraint; existing data preserved"
        );
    }
    Ok(())
}

async fn index(
    db: &impl ConnectionTrait,
    name: &str,
    table: &str,
    keys: &[(&str, bool)],
    required: bool,
) -> Result<()> {
    let rows = db
        .query_all_raw(statement(&format!("PRAGMA index_list({table})"), vec![]))
        .await?;
    let existing = rows.iter().find(|row| {
        row.try_get::<String>("", "name")
            .is_ok_and(|value| value == name)
    });
    let Some(existing) = existing else {
        ensure!(
            !required,
            "calls source index {name} is missing; existing data preserved"
        );
        return Ok(());
    };
    ensure!(
        existing.try_get::<i64>("", "unique")? == 0 && existing.try_get::<i64>("", "partial")? == 0,
        "unknown calls source index {name}; existing data preserved"
    );
    let actual = db
        .query_all_raw(statement(&format!("PRAGMA index_xinfo({name})"), vec![]))
        .await?;
    let actual: Vec<_> = actual
        .into_iter()
        .filter(|row| row.try_get::<i64>("", "key").is_ok_and(|key| key == 1))
        .collect();
    ensure!(
        actual.len() == keys.len(),
        "unknown calls source index keys {name}; existing data preserved"
    );
    for (row, (key, descending)) in actual.iter().zip(keys) {
        ensure!(
            row.try_get::<String>("", "name")? == *key
                && (row.try_get::<i64>("", "desc")? != 0) == *descending
                && row.try_get::<String>("", "coll")? == "BINARY",
            "unknown calls source index order {name}; existing data preserved"
        );
    }
    Ok(())
}
