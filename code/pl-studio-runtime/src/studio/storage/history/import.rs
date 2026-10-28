//! One read-only v2 snapshot imported and checked inside the official current-history step.

use super::*;
use futures::FutureExt;
use pl_core::{context::content_hash, thread::ThreadCheckpoint};
use sea_orm::QueryResult;

pub(super) async fn from_v2(
    target: &impl ConnectionTrait,
    thread_id: &str,
    source_path: &Path,
    legacy_state: &super::super::state::StateStore,
    identity: &initialization::ExecutionIdentityMigration,
    #[cfg(test)] fault: &std::sync::atomic::AtomicU8,
) -> Result<()> {
    let source = connect_read_only(source_path).await?;
    let snapshot = match source.begin().await {
        Ok(snapshot) => snapshot,
        Err(error) => {
            source
                .close()
                .await
                .context("close v2 source after snapshot failure")?;
            return Err(error.into());
        }
    };
    let result = std::panic::AssertUnwindSafe(import_snapshot(
        target,
        &snapshot,
        thread_id,
        legacy_state,
        identity,
        #[cfg(test)]
        fault,
    ))
    .catch_unwind()
    .await;
    let ended = snapshot.rollback().await;
    let closed = source.close().await;
    let result = match result {
        Ok(result) => result,
        Err(panic) => {
            // Source is read-only, but its transaction/pool still have explicit close responsibility.
            let _ = ended;
            let _ = closed;
            std::panic::resume_unwind(panic);
        }
    };
    result?;
    ended?;
    closed?;
    Ok(())
}

async fn import_snapshot(
    target: &impl ConnectionTrait,
    source: &impl ConnectionTrait,
    thread_id: &str,
    legacy_state: &super::super::state::StateStore,
    identity: &initialization::ExecutionIdentityMigration,
    #[cfg(test)] fault: &std::sync::atomic::AtomicU8,
) -> Result<()> {
    let format = schema::source_format(source, thread_id).await?;
    let meta = source
        .query_one_raw(statement(
            "SELECT database_id,thread_id,applied_write_seq FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .context("v2 source identity is absent")?;
    let database_id: String = meta.try_get("", "database_id")?;
    let fence: i64 = meta.try_get("", "applied_write_seq")?;
    ensure!(fence >= 0, "v2 source has a negative history watermark");
    target.execute_raw(statement(
        "INSERT INTO history_meta(id,schema_version,database_id,thread_id,applied_write_seq) VALUES(1,?,?,?,?)",
        vec![HISTORY_SCHEMA_VERSION.into(), database_id.clone().into(), thread_id.into(), fence.into()],
    )).await?;
    for table in schema::tables().filter(|name| *name != "history_meta") {
        copy_table(source, target, table, &format.missing_input_columns).await?;
    }
    // Validate exact raw rows before any conversion: identity, storage classes, optional NULLs,
    // implicit rowids and receipt order all crossed the source snapshot unchanged.
    compare_copied(source, target, &format).await?;
    let has_checkpoint = target
        .query_one_raw(statement(
            "SELECT 1 FROM session_checkpoint WHERE id=1",
            vec![],
        ))
        .await?
        .is_some();
    if !has_checkpoint {
        ensure!(
            target
                .query_one_raw(statement("SELECT 1 FROM current_context LIMIT 1", vec![]))
                .await?
                .is_none(),
            "v2 source has orphan current context without a checkpoint"
        );
        if let Some((checkpoint, costs, raw)) =
            legacy_state.load_legacy_for_import(thread_id).await?
        {
            ensure!(
                integer(checkpoint.history_fence)? == fence,
                "legacy checkpoint fence differs from v2 history"
            );
            ensure!(
                target
                    .query_one_raw(statement("SELECT 1 FROM session_costs LIMIT 1", vec![]))
                    .await?
                    .is_none(),
                "v2 SQLite costs without checkpoint cannot be combined with legacy accounting"
            );
            #[cfg(test)]
            current::inject_fault(target, fault, current::MigrationFault::LegacyInsert).await?;
            checkpoint::import_legacy(target, thread_id, &checkpoint, &costs).await?;
            #[cfg(test)]
            current::clear_fault(target, fault, current::MigrationFault::LegacyInsert).await?;
            preserve_legacy_raw(target, thread_id, &raw).await?;
        } else {
            validation::prove_empty(target).await?;
        }
    }
    // These are codecs of the old declared format, not additional target migrations or a second
    // progress ledger. The one enclosing official step owns all of them and their verification.
    if format.version < 3 {
        schema::import_hidden_inputs(target).await?;
    }
    if format.version < 4 {
        schema::import_input_bindings(target).await?;
    }
    if format.version < 6 {
        schema::import_context_sources(target, thread_id).await?;
    }
    if format.version < 8 {
        #[cfg(test)]
        current::inject_fault(target, fault, current::MigrationFault::ToolAnswerUpdate).await?;
        schema::import_tool_answers(target, thread_id).await?;
        #[cfg(test)]
        current::clear_fault(target, fault, current::MigrationFault::ToolAnswerUpdate).await?;
    }
    if has_checkpoint {
        #[cfg(test)]
        current::inject_fault(target, fault, current::MigrationFault::EnvelopeUpdate).await?;
        checkpoint::migrate_envelope(target, thread_id).await?;
        #[cfg(test)]
        current::clear_fault(target, fault, current::MigrationFault::EnvelopeUpdate).await?;
    }
    if !format.model_access_completed {
        if let Some(original) = checkpoint::read(target, thread_id).await? {
            #[cfg(test)]
            current::inject_fault(target, fault, current::MigrationFault::ModelAccessUpdate)
                .await?;
            let mut migrated = original.clone();
            crate::studio::agent_close::is_explicitly_closed(&migrated.state)?;
            crate::studio::model_route::migration::upgrade(&mut migrated.state)?;
            crate::studio::delegation::migrate(&mut migrated.state)?;
            checkpoint::write_representation(target, &original, &migrated).await?;
            #[cfg(test)]
            current::clear_fault(target, fault, current::MigrationFault::ModelAccessUpdate).await?;
        }
    }
    if !format.execution_identity_completed {
        if let Some(original) = checkpoint::read(target, thread_id).await? {
            #[cfg(test)]
            current::inject_fault(target, fault, current::MigrationFault::IdentityUpdate).await?;
            let mut migrated = original.clone();
            identity(&mut migrated.state)?;
            verify_identity_scope(&original, &migrated)?;
            checkpoint::write_representation(target, &original, &migrated).await?;
            #[cfg(test)]
            current::clear_fault(target, fault, current::MigrationFault::IdentityUpdate).await?;
        } else {
            // Empty legacy files are valid only when *all* authoritative facts prove emptiness.
            // No checkpoint or completion of the old m8 is invented.
            validation::prove_empty(target).await?;
        }
    }
    verify_after_conversion(source, target, thread_id, &format, has_checkpoint).await?;
    let current = target
        .query_one_raw(statement(
            "SELECT database_id,thread_id,applied_write_seq FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .context("target identity vanished")?;
    ensure!(
        current.try_get::<String>("", "database_id")? == database_id
            && current.try_get::<String>("", "thread_id")? == thread_id
            && current.try_get::<i64>("", "applied_write_seq")? == fence,
        "history import changed the logical identity or watermark"
    );
    Ok(())
}

fn verify_identity_scope(original: &ThreadCheckpoint, migrated: &ThreadCheckpoint) -> Result<()> {
    let mut unchanged = migrated.clone();
    unchanged.state.extensions = original.state.extensions.clone();
    unchanged.state.extension_sequence = original.state.extension_sequence;
    ensure!(
        serde_json::to_vec(&unchanged)? == serde_json::to_vec(original)?,
        "execution identity conversion changed business state or fence"
    );
    for key in original
        .state
        .extensions
        .keys()
        .chain(migrated.state.extensions.keys())
    {
        if original.state.extensions.get(key) != migrated.state.extensions.get(key) {
            ensure!(
                matches!(
                    key.as_str(),
                    "studio.mode"
                        | "studio.instructions"
                        | "studio.agent"
                        | "studio.agent-profile"
                        | "studio.model-route"
                        | "studio.bot-owner"
                ),
                "execution identity conversion changed unrelated extension {key}"
            );
        }
    }
    Ok(())
}

async fn copy_table(
    source: &impl ConnectionTrait,
    target: &impl ConnectionTrait,
    table: &str,
    missing: &[&str],
) -> Result<()> {
    let columns = schema::columns(table);
    let mut cursor = None;
    while let Some(row) = next_row(source, table, cursor).await? {
        let rowid: i64 = row.try_get("", "__source_rowid")?;
        let mut values = vec![rowid.into()];
        for (name, kind) in &columns {
            values.push(
                if table == "history_input_identities" && missing.contains(name) {
                    Value::String(None)
                } else {
                    column_value(&row, name, kind)?
                },
            );
        }
        let names = columns
            .iter()
            .map(|(name, _)| *name)
            .collect::<Vec<_>>()
            .join(",");
        let parameters = std::iter::repeat_n("?", values.len())
            .collect::<Vec<_>>()
            .join(",");
        target
            .execute_raw(statement(
                &format!("INSERT INTO {table}(rowid,{names}) VALUES({parameters})"),
                values,
            ))
            .await?;
        cursor = Some(rowid);
    }
    Ok(())
}

#[cfg(test)]
pub(super) async fn copy_fixture_facts(
    source: &impl ConnectionTrait,
    target: &impl ConnectionTrait,
) -> Result<()> {
    for table in schema::tables().filter(|table| *table != "history_meta") {
        copy_table(source, target, table, &[]).await?;
    }
    let row = source
        .query_one_raw(statement(
            "SELECT database_id,thread_id,applied_write_seq FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .context("fixture current identity")?;
    target
        .execute_raw(statement(
            "UPDATE history_meta SET database_id=?,thread_id=?,applied_write_seq=? WHERE id=1",
            vec![
                row.try_get::<String>("", "database_id")?.into(),
                row.try_get::<String>("", "thread_id")?.into(),
                row.try_get::<i64>("", "applied_write_seq")?.into(),
            ],
        ))
        .await?;
    Ok(())
}

pub(super) async fn next_row(
    db: &impl ConnectionTrait,
    table: &str,
    cursor: Option<i64>,
) -> Result<Option<QueryResult>> {
    // All identifiers come from the frozen schema, never from user content. One row bounds memory
    // independently of total history length and never truncates a large individual body.
    ensure!(
        schema::tables().any(|known| known == table),
        "unknown history table"
    );
    let (filter, values) = match cursor {
        Some(cursor) => ("WHERE rowid>?", vec![cursor.into()]),
        None => ("", vec![]),
    };
    Ok(db
        .query_one_raw(statement(
            &format!(
                "SELECT rowid AS __source_rowid,* FROM {table} {filter} ORDER BY rowid LIMIT 1"
            ),
            values,
        ))
        .await?)
}

fn column_value(row: &QueryResult, name: &str, kind: &str) -> Result<Value> {
    Ok(match kind {
        "INTEGER" => row.try_get::<Option<i64>>("", name)?.into(),
        "TEXT" => row.try_get::<Option<String>>("", name)?.into(),
        "REAL" => row.try_get::<Option<f64>>("", name)?.into(),
        _ => anyhow::bail!("unrecognized frozen history column type"),
    })
}

async fn compare_copied(
    source: &impl ConnectionTrait,
    target: &impl ConnectionTrait,
    format: &schema::SourceFormat,
) -> Result<()> {
    for table in schema::tables().filter(|name| *name != "history_meta") {
        compare_table(source, target, table, &format.missing_input_columns, &[]).await?;
    }
    Ok(())
}

async fn compare_table(
    source: &impl ConnectionTrait,
    target: &impl ConnectionTrait,
    table: &str,
    missing: &[&str],
    allowed: &[&str],
) -> Result<()> {
    let mut cursor = None;
    loop {
        let before = next_row(source, table, cursor).await?;
        let after = next_row(target, table, cursor).await?;
        let (Some(before), Some(after)) = (&before, &after) else {
            ensure!(
                before.is_none() && after.is_none(),
                "history import changed row membership in {table}"
            );
            break;
        };
        let rowid: i64 = before.try_get("", "__source_rowid")?;
        ensure!(
            rowid == after.try_get::<i64>("", "__source_rowid")?,
            "history import changed row identity in {table}"
        );
        for (name, kind) in schema::columns(table) {
            if allowed.contains(&name) {
                continue;
            }
            let old = if table == "history_input_identities" && missing.contains(&name) {
                Value::String(None)
            } else {
                column_value(before, name, kind)?
            };
            ensure!(
                old == column_value(after, name, kind)?,
                "history import changed {table}.{name} outside its conversion"
            );
        }
        cursor = Some(rowid);
    }
    Ok(())
}

async fn verify_after_conversion(
    source: &impl ConnectionTrait,
    target: &impl ConnectionTrait,
    thread_id: &str,
    format: &schema::SourceFormat,
    sqlite_checkpoint: bool,
) -> Result<()> {
    for table in [
        "history_fact_receipts",
        "history_message_identities",
        "history_tool_tasks",
    ] {
        compare_table(source, target, table, &format.missing_input_columns, &[]).await?;
    }
    compare_table(
        source,
        target,
        "history_input_identities",
        &format.missing_input_columns,
        if format.version < 3 {
            &["presentation"]
        } else {
            &[]
        },
    )
    .await?;
    compare_table(
        source,
        target,
        "history_turns",
        &[],
        if format.version < 4 {
            &["first_ordinal"]
        } else {
            &[]
        },
    )
    .await?;
    if sqlite_checkpoint {
        compare_table(source, target, "session_costs", &[], &[]).await?;
        compare_table(
            source,
            target,
            "session_checkpoint",
            &[],
            &["payload", "payload_hash"],
        )
        .await?;
        compare_table(
            source,
            target,
            "current_context",
            &[],
            if format.version < 6 {
                &["payload", "payload_hash"]
            } else {
                &[]
            },
        )
        .await?;
    }
    let mut cursor = None;
    while let Some(before) = next_row(source, "history_items", cursor).await? {
        let rowid: i64 = before.try_get("", "__source_rowid")?;
        let after = target
            .query_one_raw(statement(
                "SELECT * FROM history_items WHERE rowid=?",
                vec![rowid.into()],
            ))
            .await?
            .context("imported history item disappeared")?;
        let old: String = before.try_get("", "payload")?;
        let new: String = after.try_get("", "payload")?;
        let mut expected = old.clone();
        let old_item: pl_protocol::ThreadItem = serde_json::from_str(&old)?;
        let current: pl_protocol::ThreadItem = serde_json::from_str(&new)?;
        if format.version < 4 && old_item.turn_id != current.turn_id {
            ensure!(
                current.turn_id.is_empty()
                    && current.revision
                        == old_item
                            .revision
                            .checked_add(1)
                            .context("input revision overflow")?,
                "input binding migration changed more than the published revision"
            );
            expected = raw_json::replace(&expected, &["turnId"], &serde_json::json!(""))?;
            expected = raw_json::replace(
                &expected,
                &["revision"],
                &serde_json::json!(current.revision),
            )?;
        }
        if format.version < 8
            && old_item.tool().and_then(|tool| tool.user_input())
                != current.tool().and_then(|tool| tool.user_input())
        {
            ensure!(
                old_item.tool().is_some() && current.tool().is_some(),
                "tool migration changed item variant"
            );
            expected = raw_json::replace(
                &expected,
                &["state", "data", "userInput"],
                &serde_json::to_value(current.tool().and_then(|tool| tool.user_input()))?,
            )?;
        }
        ensure!(
            new == expected,
            "history payload changed outside directed import fields"
        );
        ensure!(
            current.thread_id == thread_id,
            "imported item belongs to another Thread"
        );
        for (name, kind) in schema::columns("history_items") {
            if matches!(name, "payload" | "revision" | "turn_id") {
                continue;
            }
            ensure!(
                column_value(&before, name, kind)? == column_value(&after, name, kind)?,
                "history import changed item {name}"
            );
        }
        cursor = Some(rowid);
    }
    Ok(())
}

async fn preserve_legacy_raw(
    target: &impl ConnectionTrait,
    thread_id: &str,
    raw: &str,
) -> Result<()> {
    let current = checkpoint::read(target, thread_id)
        .await?
        .context("legacy import has no checkpoint")?;
    let mut envelope = raw.to_owned();
    let root: serde_json::Value = serde_json::from_str(raw)?;
    if root.get("externalBodies").is_some() {
        envelope = raw_json::replace(&envelope, &["externalBodies"], &serde_json::json!([]))?;
    }
    // Materialized context bodies live in current_context, not in the lightweight envelope.
    if let Some(records) = root
        .pointer("/state/context/records")
        .and_then(serde_json::Value::as_array)
    {
        ensure!(
            records.len() == current.state.context.records.len(),
            "legacy context shape changed during import"
        );
        for (index, (before, record)) in records
            .iter()
            .zip(current.state.context.records.iter())
            .enumerate()
        {
            let raw_record = raw_json::overlay(
                &serde_json::to_string(before)?,
                &serde_json::to_value(record)?,
            )?;
            target.execute_raw(statement("UPDATE current_context SET payload=?,payload_hash=? WHERE ordinal=? AND record_id=?",
                vec![raw_record.clone().into(), content_hash(raw_record.as_bytes()).into(), integer(index)?.into(), record.id.clone().into()])).await?;
        }
    }
    envelope = raw_json::replace(
        &envelope,
        &["state", "context", "records"],
        &serde_json::json!([]),
    )?;
    let mut known = current.clone();
    known.state.context.records = Default::default();
    if root["schemaVersion"]
        .as_u64()
        .is_some_and(|version| version < 3)
    {
        // Published envelope-1/2 conversion retires full frozen request snapshots; their bodies
        // were already checked by StateStore and their identity ledger is kept in current state.
        envelope = raw_json::replace(
            &envelope,
            &["state", "attempts"],
            &serde_json::to_value(&known.state.attempts)?,
        )?;
    }
    if let Some(extensions) = root
        .pointer("/state/extensions")
        .and_then(serde_json::Value::as_object)
    {
        for key in extensions
            .keys()
            .filter(|key| !known.state.extensions.contains_key(*key))
        {
            let raw_extensions = raw_json::at(&envelope, &["state", "extensions"])?;
            let updated = raw_json::remove(raw_extensions, key)?;
            envelope = raw_json::replace_encoded(&envelope, &["state", "extensions"], &updated)?;
        }
    }
    envelope = raw_json::overlay(&envelope, &serde_json::to_value(&known)?)?;
    target
        .execute_raw(statement(
            "UPDATE session_checkpoint SET payload=?,payload_hash=? WHERE id=1",
            vec![
                envelope.clone().into(),
                content_hash(envelope.as_bytes()).into(),
            ],
        ))
        .await?;
    Ok(())
}
