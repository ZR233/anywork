//! Producer representation migration. Frozen history projections and accounting are not replayed.
use super::*;
use crate::studio::producer_migration::{RawObject, edit, field, replace_payload};
use pl_core::context::{ContextContent, content_hash};

pub(super) async fn migrate(db: &impl ConnectionTrait, thread_id: &str) -> Result<()> {
    // The canonical reader validates all hashes, ordinals, identities, revisions and the fence
    // before a producer decoder sees any saved content. SeaORM owns the surrounding transaction.
    let Some(original) = checkpoint::read(db, thread_id).await? else {
        return Ok(());
    };
    let mut current = original.clone();
    crate::studio::producer_migration::checkpoint(&mut current)?;
    ensure!(
        current.state.extension_sequence == original.state.extension_sequence,
        "producer migration changed extension sequence"
    );
    if current.state.extensions != original.state.extensions {
        let row = db
            .query_one_raw(statement(
                "SELECT payload FROM session_checkpoint WHERE id=1",
                vec![],
            ))
            .await?
            .context("checkpoint absent")?;
        let mut raw: RawObject = serde_json::from_str(&row.try_get::<String>("", "payload")?)?;
        edit(&mut raw, "state", |state| {
            edit(state, "extensions", |extensions| {
                for (id, record) in &current.state.extensions {
                    let previous = original
                        .state
                        .extensions
                        .get(id)
                        .context("producer extension absent")?;
                    ensure!(
                        previous.revision == record.revision,
                        "producer migration changed extension revision"
                    );
                    if previous.payload != record.payload {
                        edit(extensions, id, |saved| {
                            edit(saved, "payload", |saved| {
                                replace_payload(saved, &record.payload)
                            })
                        })?;
                    }
                }
                Ok(())
            })
        })?;
        let encoded = serde_json::to_string(&raw)?;
        db.execute_raw(statement(
            "UPDATE session_checkpoint SET payload=?,payload_hash=? WHERE id=1",
            vec![
                encoded.clone().into(),
                content_hash(encoded.as_bytes()).into(),
            ],
        ))
        .await?;
    }
    for (ordinal, (old, new)) in original
        .state
        .context
        .records
        .iter()
        .zip(current.state.context.records.iter())
        .enumerate()
    {
        if old == new {
            continue;
        }
        ensure!(
            old.id == new.id && old.content.len() == new.content.len(),
            "producer migration changed context identity or shape"
        );
        let row = db
            .query_one_raw(statement(
                "SELECT payload FROM current_context WHERE ordinal=? AND record_id=?",
                vec![integer(ordinal)?.into(), old.id.clone().into()],
            ))
            .await?
            .context("producer context record is absent")?;
        let mut raw: RawObject = serde_json::from_str(&row.try_get::<String>("", "payload")?)?;
        if old.source != new.source {
            raw.insert(
                "source".into(),
                serde_json::value::to_raw_value(&new.source)?,
            );
        }
        let mut content: Vec<Box<serde_json::value::RawValue>> =
            serde_json::from_str(field(&raw, "content")?.get())?;
        for (index, (previous, migrated)) in old.content.iter().zip(&new.content).enumerate() {
            if previous == migrated {
                continue;
            }
            let (ContextContent::Opaque { .. }, ContextContent::Opaque { payload }) =
                (previous, migrated)
            else {
                anyhow::bail!("producer migration changed nonopaque context content");
            };
            let mut saved = serde_json::from_str(content[index].get())?;
            edit(&mut saved, "payload", |saved| {
                replace_payload(saved, payload)
            })?;
            content[index] = serde_json::value::to_raw_value(&saved)?;
        }
        raw.insert("content".into(), serde_json::value::to_raw_value(&content)?);
        let encoded = serde_json::to_string(&raw)?;
        db.execute_raw(statement(
            "UPDATE current_context SET payload=?,payload_hash=? WHERE ordinal=? AND record_id=?",
            vec![
                encoded.clone().into(),
                content_hash(encoded.as_bytes()).into(),
                integer(ordinal)?.into(),
                old.id.clone().into(),
            ],
        ))
        .await?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use pl_core::{
        context::{ContextRecord, ContextSource, OpaquePayload},
        thread::{ThreadCheckpoint, ThreadSnapshot, extensions::ExtensionRecord},
    };
    use serde_json::json;

    fn legacy_checkpoint() -> Result<ThreadCheckpoint> {
        let binding = json!({"providerInstanceId":"frozen-account", "requestedModel":"frozen-model",
            "adapter":"deepSeek", "protocol":"responses", "isolation":"frozen-isolation", "purpose":"turn"});
        let accounting = json!({"usage":{"inputTokens":17,"outputTokens":3,"totalTokens":20},
            "pricing":{"kind":"estimated","cost":{"currency":"CNY","amount":0.12345678901234567},"cacheSavings":null}});
        let assistant = json!({"receipt":{"binding":binding,"response":{"content":null,"model":"sent-model",
            "accounting":accounting,"vendorExtension":"{ \"native\": 9007199254740993 }"}},"bindings":[],"futureField":true});
        let aux = json!({"billing":{"inferenceId":"title-id","purpose":"title","providerInstanceId":"frozen-account",
            "provider":"Frozen display", "model":"sent-model", "modelObservation":{"configuredModel":"frozen-model","sentModel":"sent-model"},
            "accounting":accounting,"recordedAt":123},"succeeded":true,"futureField":"untouched"});
        let compact = json!({"inferenceId":"compact-id","binding":binding,"turnId":"turn", "accounting":accounting,
            "reasoningEffort":null,"contextWindow":null,"implementation":null,"error":null});
        let mut state = ThreadSnapshot::default();
        state.context.revision = 19;
        state.context.records = vec![ContextRecord {
            id: "assistant-id".into(),
            turn_id: Some("turn".into()),
            source: ContextSource::Assistant,
            content: vec![ContextContent::Opaque {
                payload: OpaquePayload::new("pl.model.assistant", 2, assistant.to_string())?,
            }],
            tool_calls: vec![],
        }]
        .into();
        for (id, format, content) in [
            (
                "studio.auxiliary-billing.title",
                "pl.studio.auxiliary-billing",
                aux,
            ),
            (
                crate::compaction::LATEST_RECEIPT,
                "pl.studio.compaction",
                compact,
            ),
        ] {
            state.extensions.insert(
                id.into(),
                ExtensionRecord {
                    revision: 7,
                    payload: OpaquePayload::new(format, 1, content.to_string())?,
                },
            );
        }
        state.extension_sequence = 7;
        state.usage_summary.inference_count = 5;
        state
            .usage_summary
            .estimated_costs
            .push(pl_core::thread::UsageCost {
                currency: "CNY".into(),
                amount: 8.25,
            });
        Ok(ThreadCheckpoint::capture("producer".into(), 0, state))
    }

    async fn raw(db: &impl ConnectionTrait) -> Result<(String, String, String, String)> {
        let cp = db
            .query_one_raw(statement(
                "SELECT payload,payload_hash FROM session_checkpoint",
                vec![],
            ))
            .await?
            .context("checkpoint")?;
        let cx = db
            .query_one_raw(statement(
                "SELECT payload,payload_hash FROM current_context",
                vec![],
            ))
            .await?
            .context("context")?;
        Ok((
            cp.try_get("", "payload")?,
            cp.try_get("", "payload_hash")?,
            cx.try_get("", "payload")?,
            cx.try_get("", "payload_hash")?,
        ))
    }

    #[tokio::test]
    async fn producer_content_preparation_is_atomic_preserving_and_shared_with_toml_import()
    -> Result<()> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let store = HistoryStore::open(&path, "producer").await?;
        let connection = store.writer().await?;
        let db = &connection.db;
        let old = legacy_checkpoint()?;
        checkpoint::write(db, &old, None).await?;
        db.execute_unprepared("INSERT INTO session_costs VALUES('null','CNY',8.25);
            DELETE FROM seaql_migrations WHERE version='m20261027_000002_history_producer_payloads';").await?;
        // Unknown envelope extensions and exact numeric tokens survive known-field replacement.
        let mut saved = raw(db).await?;
        let mut metadata: serde_json::Value = serde_json::from_str(&saved.0)?;
        metadata["state"]["futureNumber"] = json!(0);
        metadata["state"]["extensions"]["studio.auxiliary-billing.title"]["payload"]["futureEnvelope"] =
            json!(true);
        saved.0 = serde_json::to_string(&metadata)?.replace(
            "\"futureNumber\":0",
            "\"futureNumber\":12345678901234567890.123456789",
        );
        db.execute_raw(statement(
            "UPDATE session_checkpoint SET payload=?,payload_hash=?",
            vec![
                saved.0.clone().into(),
                content_hash(saved.0.as_bytes()).into(),
            ],
        ))
        .await?;
        let before = raw(db).await?;
        assert!(
            store.read_only_checkpoint_with_latest_turn().await.is_err(),
            "normal reads cannot repair pending producer content"
        );
        // Unknown required producer versions fail closed, retaining the exact source bytes.
        let mut unsupported: RawObject = serde_json::from_str(&before.0)?;
        edit(&mut unsupported, "state", |state| {
            edit(state, "extensions", |extensions| {
                edit(extensions, "studio.auxiliary-billing.title", |record| {
                    edit(record, "payload", |payload| {
                        payload.insert("version".into(), serde_json::value::to_raw_value(&99)?);
                        Ok(())
                    })
                })
            })
        })?;
        let unsupported = serde_json::to_string(&unsupported)?;
        db.execute_raw(statement(
            "UPDATE session_checkpoint SET payload=?,payload_hash=?",
            vec![
                unsupported.clone().into(),
                content_hash(unsupported.as_bytes()).into(),
            ],
        ))
        .await?;
        let rejected = raw(db).await?;
        assert!(
            schema::prepare(db, "producer", schema::Preparation::Schema, None)
                .await
                .is_err()
        );
        assert_eq!(raw(db).await?, rejected);
        db.execute_raw(statement(
            "UPDATE session_checkpoint SET payload=?,payload_hash=?",
            vec![before.0.clone().into(), before.1.clone().into()],
        ))
        .await?;
        db.execute_unprepared("CREATE TRIGGER reject_producer BEFORE UPDATE ON current_context BEGIN SELECT RAISE(ABORT,'producer fault'); END").await?;
        assert!(
            schema::prepare(db, "producer", schema::Preparation::Schema, None)
                .await
                .is_err()
        );
        assert_eq!(
            raw(db).await?,
            before,
            "all payload/hash updates roll back together"
        );
        assert!(db.query_one_raw(statement("SELECT 1 FROM seaql_migrations WHERE version='m20261027_000002_history_producer_payloads'",vec![])).await?.is_none());
        db.execute_unprepared("DROP TRIGGER reject_producer")
            .await?;
        schema::prepare(db, "producer", schema::Preparation::Schema, None).await?;
        let current = store.checkpoint().await?.context("prepared checkpoint")?;
        assert_eq!(current.state_revision, old.state_revision);
        assert_eq!(current.history_fence, old.history_fence);
        assert_eq!(current.state.context.revision, 19);
        assert_eq!(current.state.extension_sequence, 7);
        assert_eq!(
            serde_json::to_value(&current.state.usage_summary)?,
            serde_json::to_value(&old.state.usage_summary)?
        );
        assert_eq!(current.state.context.records[0].id, "assistant-id");
        let ContextContent::Opaque { payload } = &current.state.context.records[0].content[0]
        else {
            anyhow::bail!("assistant")
        };
        assert_eq!(payload.version(), 4);
        let assistant: serde_json::Value = serde_json::from_str(payload.content())?;
        assert_eq!(
            assistant["receipt"]["response"]["vendorExtension"],
            "{ \"native\": 9007199254740993 }"
        );
        for record in current.state.extensions.values() {
            assert_eq!(record.revision, 7);
            assert_eq!(record.payload.version(), 3);
            assert!(crate::studio::producer_migration::normalize(&record.payload)?.is_none());
        }
        let auxiliary = &current.state.extensions["studio.auxiliary-billing.title"].payload;
        let receipt: crate::studio::thread_projection::AuxiliaryBillingReceipt =
            serde_json::from_str(auxiliary.content())?;
        assert_eq!(receipt.billing.inference_id, "title-id");
        assert_eq!(receipt.billing.account_id, "frozen-account");
        assert_eq!(receipt.billing.recorded_at, 123);
        assert_eq!(
            receipt.billing.accounting.estimated_costs()[0].currency,
            "CNY"
        );
        let prepared = raw(db).await?;
        let after: serde_json::Value = serde_json::from_str(&prepared.0)?;
        assert!(prepared.0.contains("12345678901234567890.123456789"));
        assert_eq!(
            after["state"]["extensions"]["studio.auxiliary-billing.title"]["payload"]["futureEnvelope"],
            true
        );
        crate::studio::thread_projection::project_runtime(
            "producer",
            &current.state,
            123,
            &current.state.usage_summary,
        )?;
        db.execute_unprepared("DELETE FROM seaql_migrations WHERE version='m20261027_000002_history_producer_payloads';
            CREATE TRIGGER no_current_checkpoint_rewrite BEFORE UPDATE ON session_checkpoint BEGIN SELECT RAISE(ABORT,'current checkpoint rewritten'); END;
            CREATE TRIGGER no_current_context_rewrite BEFORE UPDATE ON current_context BEGIN SELECT RAISE(ABORT,'current context rewritten'); END;").await?;
        schema::prepare(db, "producer", schema::Preparation::Schema, None).await?;
        assert_eq!(
            raw(db).await?,
            prepared,
            "already-current bytes and hashes are not rewritten"
        );
        for step in [
            schema::EXECUTION_IDENTITY,
            "m20261026_000007_history_model_access",
        ] {
            assert!(
                db.query_one_raw(statement(
                    "SELECT 1 FROM seaql_migrations WHERE version=?",
                    vec![step.into()]
                ))
                .await?
                .is_none(),
                "content preparation must not advance lifecycle"
            );
        }
        assert_eq!(
            db.query_one_raw(statement(
                "SELECT amount FROM session_costs WHERE currency='CNY'",
                vec![]
            ))
            .await?
            .unwrap()
            .try_get::<f64>("", "amount")?,
            8.25
        );

        // New empty SQLite preparation records the step before the later TOML import.
        let import_dir = tempfile::tempdir()?;
        let imported =
            HistoryStore::open(&import_dir.path().join("history.sqlite"), "producer").await?;
        imported.prepare_activation().await?;
        let mut legacy =
            serde_json::to_value(toml::from_str::<toml::Value>(&toml::to_string(&old)?)?)?;
        legacy["schemaVersion"] = json!(4);
        tokio::fs::write(
            import_dir.path().join("state.toml"),
            toml::to_string(&legacy)?,
        )
        .await?;
        let state =
            super::super::super::state::StateStore::new(import_dir.path().to_owned(), "producer");
        let result = state
            .prepare_recovery(&imported)
            .await?
            .context("imported")?;
        assert_eq!(result.state.context, current.state.context);
        assert_eq!(result.state.extensions, current.state.extensions);
        assert_eq!(result.history_fence, old.history_fence);
        assert_eq!(
            result.state.extension_sequence,
            old.state.extension_sequence
        );
        assert!(!import_dir.path().join("state.toml").exists());
        Ok(())
    }
}
