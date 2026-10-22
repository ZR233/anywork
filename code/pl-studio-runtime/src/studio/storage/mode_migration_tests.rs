//! Saved representation migration (Mode, model access, compaction sources) through the actual
//! SQLite checkpoint, history writer and history schema-upgrade paths.
use std::collections::{BTreeMap, BTreeSet};

use super::history::{EffectCommit, HistoryStore};
use crate::mode::{ThreadModeManager, ThreadModeSource, ThreadModeSourceId};
use anyhow::{Context, Result};
use pl_core::{
    context::{ContextContent, ContextRecord, ContextSnapshot, ContextSource, OpaquePayload},
    thread::{
        ThreadCheckpoint, ThreadEffectBatch, ThreadSnapshot,
        extensions::{ExtensionChange, ExtensionRecord},
        journal::ContextChange,
    },
};
use sea_orm::ConnectionTrait;

fn legacy_state(manager: &ThreadModeManager) -> Result<ThreadSnapshot> {
    let mut definition = crate::studio::thread::task::REGISTRATION.to_registration()?;
    definition.id = pl_protocol::ThreadModeId::new("mode.migration")?;
    let source = ThreadModeSource::external(ThreadModeSourceId::new("migration-fixture")?);
    let registry = manager.replace_source(source, [definition])?;
    let mode = registry
        .mode(&pl_protocol::ThreadModeId::new("mode.migration")?)
        .context("registered mode")?;
    let workflow = crate::mode::reconcile_workflow_for_turn(None, &mode, "migration", 1)?
        .context("workflow")?;
    let source = |kind, content: &str| crate::instruction::InstructionBlock {
        source: crate::instruction::InstructionSource {
            kind,
            label: "保留的模式名称".into(),
            path: None,
        },
        content: content.into(),
    };
    let instructions = crate::instruction::InstructionSnapshot {
        base: source(crate::instruction::InstructionSourceKind::ModelBase, "base"),
        developer: vec![source(
            crate::instruction::InstructionSourceKind::ExecutionProfile,
            "保存的原始 Prompt",
        )],
        user: vec![],
    };
    let extensions = BTreeMap::from([
        (
            "studio.mode".into(),
            ExtensionRecord {
                revision: 1,
                payload: OpaquePayload::new(
                    "pl.studio.mode",
                    1,
                    serde_json::to_string(&mode.descriptor().id)?,
                )?,
            },
        ),
        (
            "studio.workflow".into(),
            ExtensionRecord {
                revision: 2,
                payload: crate::workflow_tool::encode_workflow_state(&workflow)?,
            },
        ),
        (
            "studio.instructions".into(),
            ExtensionRecord {
                revision: 3,
                payload: OpaquePayload::new(
                    "pl.studio.instructions",
                    1,
                    serde_json::to_string(&instructions)?,
                )?,
            },
        ),
    ]);
    Ok(ThreadSnapshot {
        commit_sequence: 1,
        extension_sequence: 3,
        extensions,
        context: ContextSnapshot {
            revision: 1,
            records: vec![ContextRecord {
                id: "preserved-user-history".into(),
                turn_id: None,
                source: ContextSource::User,
                content: vec![ContextContent::Text {
                    text: "必须保留的用户历史".into(),
                }],
                tool_calls: vec![],
            }]
            .into(),
        },
        ..Default::default()
    })
}

async fn persist(store: &HistoryStore, state: ThreadSnapshot, append: bool) -> Result<()> {
    let sequence = state.commit_sequence;
    let empty = BTreeSet::new();
    let effect = ThreadEffectBatch {
        thread_id: "migration".into(),
        sequence,
        context: append.then(|| ContextChange::Append {
            revision: state.context.revision,
            records: state.context.records.clone(),
        }),
        extensions: state
            .extensions
            .iter()
            .map(|(id, record)| ExtensionChange::Put {
                id: id.clone(),
                record: record.clone(),
            })
            .collect::<Vec<_>>()
            .into(),
        ..Default::default()
    };
    let checkpoint = ThreadCheckpoint::capture("migration".into(), sequence, state);
    store
        .commit_checkpoint_effect(
            &checkpoint,
            &effect,
            EffectCommit {
                items: &[],
                rolled_back_turns: &empty,
                identities: &[],
                messages: &[],
                receipts: &[],
                tasks: &[],
                deliveries: &[],
                delivery_repairs: &[],
                attempt: None,
            },
        )
        .await
}

#[tokio::test]
async fn mode_definition_migration_preserves_history_and_restores_after_source_deletion()
-> Result<()> {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("history.sqlite");
    let manager = ThreadModeManager::default();
    let original = legacy_state(&manager)?;
    let workflow = original.extensions["studio.workflow"].clone();
    let store = HistoryStore::open(&path, "migration").await?;
    persist(&store, original.clone(), true).await?;
    let legacy = store.checkpoint().await?.context("legacy checkpoint")?;
    let migrated = store
        .migrate_recovery_checkpoint(&legacy, |state| {
            crate::mode::migrate_mode_snapshot(state, &manager)?;
            Ok(())
        })
        .await?;
    assert_eq!(migrated.state_revision, legacy.state_revision);
    assert_eq!(migrated.history_fence, legacy.history_fence);
    let recovered = migrated.state;
    assert_eq!(recovered.context, original.context);
    assert_eq!(recovered.extensions["studio.workflow"], workflow);
    let saved = crate::mode::decode_mode_snapshot(&recovered.extensions["studio.mode"].payload)?;
    assert_eq!(saved.definition.prompt, "保存的原始 Prompt");
    assert_eq!(saved.definition.display_name, "保留的模式名称");
    assert_eq!(saved.frozen_turn_id, None);
    let durable = store
        .checkpoint()
        .await?
        .context("durable Mode migration")?;
    assert_eq!(
        durable.state.extensions["studio.mode"],
        recovered.extensions["studio.mode"]
    );
    let before_retry = serde_json::to_vec(&durable)?;
    assert!(
        store
            .migrate_recovery_checkpoint(&legacy, |state| {
                crate::mode::migrate_mode_snapshot(state, &manager)?;
                Ok(())
            })
            .await
            .is_err(),
        "a stale recovery candidate must not overwrite the migrated checkpoint"
    );
    assert_eq!(
        serde_json::to_vec(&store.checkpoint().await?.context("unchanged checkpoint")?)?,
        before_retry
    );
    drop(store);
    manager.remove_source(&ThreadModeSourceId::new("migration-fixture")?);
    assert!(manager.snapshot().modes().next().is_none());
    let reopened = HistoryStore::open(&path, "migration").await?;
    let mut checkpoint = reopened
        .checkpoint()
        .await?
        .context("reopened checkpoint")?;
    crate::mode::migrate_mode_snapshot(&mut checkpoint.state, &manager)?;
    let restored =
        crate::mode::saved_registered_mode(&checkpoint.state)?.context("saved full definition")?;
    assert_eq!(restored.prompt(), "保存的原始 Prompt");
    assert_eq!(restored.definition(), saved.definition);
    assert_eq!(checkpoint.state.extensions["studio.workflow"], workflow);
    assert_eq!(checkpoint.state.context, original.context);
    assert!(
        manager.snapshot().modes().next().is_none(),
        "restoration cannot re-register a deleted Mode"
    );
    Ok(())
}

#[tokio::test]
async fn unavailable_legacy_mode_definition_never_resets_or_rewrites_the_checkpoint() -> Result<()>
{
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("history.sqlite");
    let manager = ThreadModeManager::default();
    let original = legacy_state(&manager)?;
    let store = HistoryStore::open(&path, "migration").await?;
    persist(&store, original.clone(), true).await?;
    manager.remove_source(&ThreadModeSourceId::new("migration-fixture")?);
    let checkpoint = store.checkpoint().await?.context("checkpoint")?;
    let before = serde_json::to_vec(&checkpoint)?;
    assert!(
        store
            .migrate_recovery_checkpoint(&checkpoint, |state| {
                crate::mode::migrate_mode_snapshot(state, &manager)?;
                Ok(())
            })
            .await
            .is_err()
    );
    assert_eq!(serde_json::to_vec(&checkpoint)?, before);
    assert_eq!(
        serde_json::to_vec(&store.checkpoint().await?.context("retained checkpoint")?)?,
        before
    );
    assert_eq!(checkpoint.state.context, original.context);
    Ok(())
}

#[tokio::test]
async fn legacy_mode_graph_or_prompt_mismatch_preserves_the_original_recovery_data() -> Result<()> {
    for fault in ["prompt", "promptWithoutWorkflow", "graph", "mode"] {
        let manager = ThreadModeManager::default();
        let mut state = legacy_state(&manager)?;
        if fault == "prompt" || fault == "promptWithoutWorkflow" {
            state.extensions.remove("studio.instructions");
            if fault == "promptWithoutWorkflow" {
                state.extensions.remove("studio.workflow");
            }
        } else if fault == "mode" {
            state.extensions.remove("studio.mode");
        } else {
            let mut definition = manager
                .snapshot()
                .mode(&pl_protocol::ThreadModeId::new("mode.migration")?)
                .context("mode")?
                .definition();
            definition.workflow.as_mut().unwrap().goal =
                "changed graph without an original persisted definition".into();
            manager.replace_source(
                ThreadModeSource::external(ThreadModeSourceId::new("migration-fixture")?),
                [definition],
            )?;
        }
        let before = serde_json::to_vec(&state)?;
        assert!(crate::mode::migrate_mode_snapshot(&mut state, &manager).is_err());
        assert_eq!(serde_json::to_vec(&state)?, before);
    }
    Ok(())
}

#[test]
fn restored_mode_snapshot_keeps_graph_revision_when_a_new_catalog_assigns_a_different_one()
-> Result<()> {
    let original_manager = ThreadModeManager::default();
    let mut state = legacy_state(&original_manager)?;
    crate::mode::migrate_mode_snapshot(&mut state, &original_manager)?;
    let mut saved = crate::mode::decode_mode_snapshot(&state.extensions["studio.mode"].payload)?;
    saved.graph_revision = 42;
    let restored_manager = ThreadModeManager::default();
    crate::studio::thread::register_builtins(&restored_manager)?;
    let mut updated_definition = saved.definition.clone();
    updated_definition.prompt = "updated Prompt after process restart".into();
    let catalog = restored_manager.replace_source(
        ThreadModeSource::external(ThreadModeSourceId::new("reopened-config")?),
        [updated_definition],
    )?;
    let mode = catalog
        .mode(&saved.definition.id)
        .context("reopened Mode")?;
    assert_ne!(mode.graph_revision(), saved.graph_revision);
    let next = saved.updated_for_turn(&mode, "next-root-turn".into())?;
    assert_eq!(next.graph_revision, 42);
    assert_eq!(
        next.definition.prompt,
        "updated Prompt after process restart"
    );
    assert_eq!(
        next.registered()?.graph_hash(),
        saved.registered()?.graph_hash()
    );
    Ok(())
}

// ── 模型接入扩展表示迁移与压缩来源恢复 ──

const LEGACY_ROUTE: &str = r#"{"provider":"deepseek","model":"deepseek-flash","effort":"high"}"#;
/// 旧版实际写出的 v1 冻结 Profile 载荷（camelCase，含 `providerId`/`model`）。
const LEGACY_PROFILE: &str = r#"{
    "profileId":"reviewer","displayName":"Reviewer","description":"","whenToUse":"",
    "systemInstructions":"","providerId":"deepseek","model":"deepseek-flash","effort":"high",
    "source":"config","revision":"1","contentHash":"","system":true,"enabled":true,
    "workspaceMode":"unrestricted"
}"#;
/// HEAD 真实 v1 原生压缩回执（camelCase binding：providerInstanceId/requestedModel/adapter/protocol）。
const LEGACY_NATIVE_RECEIPT: &str = r#"{
    "inferenceId": "compact-call",
    "binding": {
        "providerInstanceId": "deepseek",
        "requestedModel": "deepseek-flash",
        "adapter": "deepSeek",
        "protocol": "responses",
        "isolation": "binding-namespace",
        "purpose": "compaction",
        "contextWindow": 128000,
        "maxContextWindow": 200000,
        "autoCompactLimit": 115200
    },
    "reasoningEffort": "high",
    "contextWindow": 128000,
    "turnId": "turn",
    "accounting": {
        "usage": { "inputTokens": 1, "outputTokens": 2, "cacheReadTokens": 0, "cacheWriteTokens": 0, "reasoningTokens": 0, "totalTokens": 3 },
        "pricing": { "kind": "estimated", "cost": { "currency": "USD", "amount": 0.25 }, "cacheSavings": null },
        "priceSnapshot": null,
        "requestStartedAt": null
    },
    "modelObservation": null,
    "implementation": "native",
    "error": null
}"#;

fn record(revision: u64, format: &str, version: u32, content: &str) -> Result<ExtensionRecord> {
    Ok(ExtensionRecord {
        revision,
        payload: OpaquePayload::new(format, version, content.to_owned())?,
    })
}

fn saved_state(extensions: BTreeMap<String, ExtensionRecord>) -> ThreadSnapshot {
    ThreadSnapshot {
        commit_sequence: 1,
        extension_sequence: 6,
        extensions,
        context: ContextSnapshot {
            revision: 1,
            records: vec![ContextRecord {
                id: "preserved-user-history".into(),
                turn_id: None,
                source: ContextSource::User,
                content: vec![ContextContent::Text {
                    text: "必须保留的用户历史".into(),
                }],
                tool_calls: vec![],
            }]
            .into(),
        },
        ..Default::default()
    }
}

async fn migrate_model_access(
    store: &HistoryStore,
    checkpoint: &ThreadCheckpoint,
) -> Result<ThreadCheckpoint> {
    store
        .migrate_recovery_checkpoint(
            checkpoint,
            crate::studio::model_route::migrate_saved_representation,
        )
        .await
}

/// 故障注入与结构降级只通过真实 SQLite 文件完成，不使用生产句柄的私有入口。
async fn raw_database(path: &std::path::Path) -> Result<sea_orm::DatabaseConnection> {
    Ok(sea_orm::Database::connect(
        crate::studio::paths::sqlite_file_options(
            path,
            crate::studio::paths::SqliteFileMode::Create,
            |options| options,
        )
        .await?,
    )
    .await?)
}

fn bound_thread(thread_id: &str) -> pl_protocol::Thread {
    let mut thread = pl_protocol::Thread::placeholder(thread_id);
    thread.project_id = "project-test".into();
    thread.agent_path = thread_id.to_owned();
    thread.root_thread_id = thread_id.to_owned();
    thread
}

async fn register_test_thread(
    store: &crate::studio::StudioStore,
    thread: &pl_protocol::Thread,
) -> Result<()> {
    let mut delta = crate::studio::store::directory::DirectoryDelta::upsert_project(
        crate::studio::store::directory::ProjectDirectoryRecord {
            id: thread.project_id.clone(),
            name: "Test".into(),
            path: "/tmp/project-test".into(),
            ssh_alias: None,
            created_at: 1,
            updated_at: 1,
            last_opened_at: None,
            closed: false,
        },
    );
    delta.thread_upserts = vec![thread.clone()];
    store.persist_directory_summaries(&delta).await
}

async fn registered_history(
    store: &crate::studio::StudioStore,
    thread: &pl_protocol::Thread,
) -> Result<HistoryStore> {
    register_test_thread(store, thread).await?;
    store.history_for(&thread.project_id, &thread.id).await
}

#[tokio::test]
async fn legacy_root_route_representation_is_committed_once_before_recovery() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("history.sqlite");
    let store = HistoryStore::open(&path, "migration").await?;
    let plan = ExtensionRecord {
        revision: 5,
        payload: crate::plan_tool::encode_plan_state(&Default::default())?,
    };
    let original = saved_state(BTreeMap::from([
        (
            "studio.model-route".into(),
            record(2, "pl.studio.model-route", 1, LEGACY_ROUTE)?,
        ),
        ("studio.plan".into(), plan.clone()),
    ]));
    persist(&store, original.clone(), true).await?;
    let legacy = store.checkpoint().await?.context("legacy checkpoint")?;
    assert_eq!(
        legacy.state.extensions["studio.model-route"]
            .payload
            .version(),
        1
    );

    let migrated = migrate_model_access(&store, &legacy).await?;
    assert_eq!(migrated.state_revision, legacy.state_revision);
    assert_eq!(migrated.history_fence, legacy.history_fence);
    assert_eq!(
        migrated.state.extension_sequence,
        legacy.state.extension_sequence
    );
    assert_eq!(migrated.state.context, original.context);
    assert_eq!(
        serde_json::to_value(&migrated.state.usage_summary)?,
        serde_json::to_value(&original.usage_summary)?
    );
    let saved = &migrated.state.extensions["studio.model-route"];
    assert_eq!(saved.revision, 2, "表示迁移不改变扩展 revision");
    assert_eq!(saved.payload.version(), 2);
    let route = crate::studio::model_route::saved(&migrated.state)?
        .context("migrated route")?
        .route;
    assert_eq!(route.account_id.as_str(), "deepseek");
    assert_eq!(route.model_id, "deepseek-flash");
    assert_eq!(
        route.effort.as_ref().map(|value| value.as_str()),
        Some("high")
    );
    assert_eq!(
        migrated.state.extensions["studio.plan"], plan,
        "其它产品扩展原样保留"
    );

    let durable = store
        .checkpoint()
        .await?
        .context("durable route representation")?;
    assert_eq!(
        serde_json::to_vec(&durable)?,
        serde_json::to_vec(&migrated)?
    );
    drop(store);

    let reopened = HistoryStore::open(&path, "migration").await?;
    let durable = reopened
        .checkpoint()
        .await?
        .context("reopened checkpoint")?;
    assert_eq!(
        durable.state.extensions["studio.model-route"]
            .payload
            .version(),
        2,
        "重开后持久化为当前版本"
    );
    let before_retry = serde_json::to_vec(&durable)?;
    let again = migrate_model_access(&reopened, &durable).await?;
    assert_eq!(serde_json::to_vec(&again)?, before_retry, "第二次没有变化");
    assert!(
        migrate_model_access(&reopened, &legacy).await.is_err(),
        "旧候选不得覆盖已提交的表示"
    );
    assert_eq!(
        serde_json::to_vec(
            &reopened
                .checkpoint()
                .await?
                .context("unchanged checkpoint")?
        )?,
        before_retry
    );
    Ok(())
}

#[tokio::test]
async fn shared_recovery_entry_commits_saved_representations_before_publishing() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let database_path = directory.path().join("studio/v2/studio.sqlite");
    let store = crate::studio::StudioStore::open(&database_path).await?;
    let thread = bound_thread("migration");
    let history = registered_history(&store, &thread).await?;
    let original = saved_state(BTreeMap::from([
        (
            "studio.model-route".into(),
            record(2, "pl.studio.model-route", 1, LEGACY_ROUTE)?,
        ),
        (
            "studio.agent-profile".into(),
            record(3, "pl.studio.agent-profile", 1, LEGACY_PROFILE)?,
        ),
    ]));
    persist(&history, original.clone(), true).await?;

    let recovered =
        crate::studio::thread_factory::recovery::load_checkpoint_for_recovery(&store, &thread)
            .await?
            .context("recovered checkpoint")?;
    assert_eq!(recovered.state_revision, original.commit_sequence);
    assert_eq!(
        recovered.state.extensions["studio.model-route"]
            .payload
            .version(),
        2
    );
    assert_eq!(
        recovered.state.extensions["studio.agent-profile"]
            .payload
            .version(),
        2
    );
    assert_eq!(
        recovered.state.extensions["studio.model-route"].revision, 2,
        "表示迁移保留扩展 revision"
    );
    assert_eq!(recovered.state.context, original.context);
    let durable = history.checkpoint().await?.context("durable checkpoint")?;
    assert_eq!(
        serde_json::to_vec(&durable)?,
        serde_json::to_vec(&recovered)?,
        "恢复返回前已经持久化当前表示"
    );

    let again =
        crate::studio::thread_factory::recovery::load_checkpoint_for_recovery(&store, &thread)
            .await?
            .context("second recovery")?;
    assert_eq!(serde_json::to_vec(&again)?, serde_json::to_vec(&recovered)?);
    drop(history);
    drop(store);

    let reopened = crate::studio::StudioStore::open(&database_path).await?;
    let history = reopened.history_for(&thread.project_id, &thread.id).await?;
    let saved = history.checkpoint().await?.context("reopened checkpoint")?;
    assert_eq!(
        saved.state.extensions["studio.model-route"]
            .payload
            .version(),
        2
    );
    let route = crate::studio::model_route::saved(&saved.state)?
        .context("reopened route")?
        .route;
    assert_eq!(route.account_id.as_str(), "deepseek");
    assert_eq!(route.model_id, "deepseek-flash");
    Ok(())
}

#[tokio::test]
async fn legacy_child_profile_representation_is_committed_once_before_recovery() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("history.sqlite");
    let store = HistoryStore::open(&path, "migration").await?;
    let original = saved_state(BTreeMap::from([(
        "studio.agent-profile".into(),
        record(3, "pl.studio.agent-profile", 1, LEGACY_PROFILE)?,
    )]));
    persist(&store, original, true).await?;
    let legacy = store.checkpoint().await?.context("legacy checkpoint")?;
    assert_eq!(
        legacy.state.extensions["studio.agent-profile"]
            .payload
            .version(),
        1
    );

    let migrated = migrate_model_access(&store, &legacy).await?;
    let saved = &migrated.state.extensions["studio.agent-profile"];
    assert_eq!(saved.revision, 3);
    assert_eq!(saved.payload.version(), 2);
    let (profile, revision) =
        crate::studio::model_route::saved_profile(&migrated.state)?.context("migrated profile")?;
    assert_eq!(revision, 3);
    assert_eq!(profile.profile_id, "reviewer");
    assert_eq!(profile.account_id, "deepseek");
    assert_eq!(profile.model_id, "deepseek-flash");
    assert_eq!(profile.effort.as_deref(), Some("high"));
    let mut expected = legacy.clone();
    expected
        .state
        .extensions
        .get_mut("studio.agent-profile")
        .context("saved profile")?
        .payload = crate::studio::model_route::encode_profile(&profile)?;
    assert_eq!(
        serde_json::to_vec(&migrated)?,
        serde_json::to_vec(&expected)?,
        "表示迁移只更新 Profile 编码，历史、业务状态和水位保持不变"
    );

    let durable = store.checkpoint().await?.context("durable profile")?;
    assert_eq!(
        serde_json::to_vec(&durable)?,
        serde_json::to_vec(&migrated)?,
        "恢复返回前持久化当前 Profile"
    );
    drop(store);

    let reopened = HistoryStore::open(&path, "migration").await?;
    let checkpoint = reopened.checkpoint().await?.context("reopened profile")?;
    let again = migrate_model_access(&reopened, &checkpoint).await?;
    assert_eq!(
        serde_json::to_vec(&again)?,
        serde_json::to_vec(&durable)?,
        "重开后再次迁移不改变已保存状态"
    );
    Ok(())
}

#[tokio::test]
async fn failed_representation_write_preserves_the_saved_version_and_retries() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("history.sqlite");
    let store = HistoryStore::open(&path, "migration").await?;
    let original = saved_state(BTreeMap::from([(
        "studio.model-route".into(),
        record(2, "pl.studio.model-route", 1, LEGACY_ROUTE)?,
    )]));
    persist(&store, original, true).await?;
    let legacy = store.checkpoint().await?.context("legacy checkpoint")?;
    // 真实故障注入：checkpoint 写入被 SQLite 触发器拒绝。
    let faults = raw_database(&path).await?;
    faults
        .execute_unprepared(
            "CREATE TRIGGER block_checkpoint_update BEFORE UPDATE ON session_checkpoint \
             BEGIN SELECT RAISE(ABORT,'injected checkpoint write fault'); END",
        )
        .await?;
    assert!(migrate_model_access(&store, &legacy).await.is_err());
    let preserved = store.checkpoint().await?.context("preserved checkpoint")?;
    assert_eq!(
        preserved.state.extensions["studio.model-route"],
        legacy.state.extensions["studio.model-route"],
        "写失败保留原 version 1 载荷"
    );
    assert_eq!(
        preserved.state.extensions["studio.model-route"]
            .payload
            .version(),
        1
    );

    faults
        .execute_unprepared("DROP TRIGGER block_checkpoint_update")
        .await?;
    drop(faults);
    let migrated = migrate_model_access(&store, &legacy).await?;
    assert_eq!(
        migrated.state.extensions["studio.model-route"]
            .payload
            .version(),
        2,
        "故障解除后可重试到当前版本"
    );
    assert_eq!(
        store
            .checkpoint()
            .await?
            .context("retried checkpoint")?
            .state
            .extensions["studio.model-route"],
        migrated.state.extensions["studio.model-route"]
    );
    Ok(())
}

fn legacy_native_context(inference_id: &str, sealed: &str) -> Result<ContextRecord> {
    let item = pl_protocol::ModelContextItem::Compaction {
        encrypted_content: sealed.into(),
    };
    Ok(ContextRecord {
        id: format!("compaction:{inference_id}"),
        turn_id: None,
        source: ContextSource::Runtime {
            source_id: "model.compaction".into(),
        },
        content: vec![ContextContent::Opaque {
            payload: OpaquePayload::new("pl.model.compaction", 1, serde_json::to_string(&item)?)?,
        }],
        tool_calls: vec![],
    })
}

fn opaque_record(id: &str, content: &str) -> Result<ContextRecord> {
    Ok(ContextRecord {
        id: id.into(),
        turn_id: None,
        source: ContextSource::User,
        content: vec![ContextContent::Opaque {
            payload: OpaquePayload::new("pl.test.opaque", 1, content.to_owned())?,
        }],
        tool_calls: vec![],
    })
}

/// 旧版历史库升级（schema < 6）必须能从真实 v1 原生压缩回执恢复来源，而不是先硬失败。
#[tokio::test]
async fn legacy_native_compaction_receipt_upgrades_sources_through_the_history_upgrade()
-> Result<()> {
    let directory = tempfile::tempdir()?;
    let database_path = directory.path().join("studio/v2/studio.sqlite");
    let store = crate::studio::StudioStore::open(&database_path).await?;
    let thread = bound_thread("migration");
    let history = registered_history(&store, &thread).await?;
    let history_path = store
        .session_paths(&thread.project_id, &thread.id)?
        .history_database();
    let mut state = saved_state(BTreeMap::from([(
        crate::compaction::LATEST_RECEIPT.into(),
        record(7, "pl.studio.compaction", 1, LEGACY_NATIVE_RECEIPT)?,
    )]));
    let mut records = state.context.records.to_vec();
    records.push(legacy_native_context(
        "compact-call",
        "sealed-checkpoint-bytes",
    )?);
    records.push(opaque_record(
        "unrelated-opaque",
        "不可改写的用户/厂商正文",
    )?);
    state.context.records = records.into();
    persist(&history, state.clone(), true).await?;
    let before = history.checkpoint().await?.context("legacy checkpoint")?;
    raw_database(&history_path)
        .await?
        .execute_unprepared("UPDATE history_meta SET schema_version=5")
        .await?;
    drop(history);
    drop(store);

    // 真实共同恢复入口：旧库结构升级必须能从 v1 原生回执恢复来源而不是先硬失败。
    let reopened = crate::studio::StudioStore::open(&database_path).await?;
    let upgraded = reopened.history_for(&thread.project_id, &thread.id).await?;
    let checkpoint =
        crate::studio::thread_factory::recovery::load_checkpoint_for_recovery(&reopened, &thread)
            .await?
            .context("upgraded checkpoint")?;
    assert_eq!(checkpoint.state_revision, before.state_revision);
    assert_eq!(checkpoint.history_fence, before.history_fence);
    assert_eq!(
        checkpoint.state.context.revision,
        before.state.context.revision
    );
    assert_eq!(
        checkpoint.state.extensions[crate::compaction::LATEST_RECEIPT],
        before.state.extensions[crate::compaction::LATEST_RECEIPT],
        "回执扩展本身按版本化解码，字节不变"
    );
    assert_eq!(upgraded.watermark().await?, 1);

    let compaction = checkpoint
        .state
        .context
        .records
        .iter()
        .find(|record| record.id == "compaction:compact-call")
        .context("migrated compaction record")?;
    let [ContextContent::Opaque { payload }] = compaction.content.as_slice() else {
        anyhow::bail!("migrated compaction record is not opaque");
    };
    assert_eq!(payload.format(), "pl.model.compaction");
    assert_eq!(payload.version(), 3, "原生 checkpoint 升级到当前结构");
    let native: serde_json::Value = serde_json::from_str(payload.content())?;
    assert_eq!(native["binding"]["accountId"], "deepseek");
    assert_eq!(native["binding"]["modelId"], "deepseek-flash");
    assert_eq!(native["binding"]["protocol"], "deep_seek");
    assert_eq!(native["binding"]["wireApi"], "responses");
    assert_eq!(native["binding"]["isolation"], "binding-namespace");
    assert_eq!(native["binding"]["purpose"], "compaction");
    assert_eq!(native["binding"]["autoCompactLimit"], 115_200);
    assert_eq!(native["compatibilityFamily"], serde_json::Value::Null);
    assert_eq!(
        native["item"]["encryptedContent"],
        "sealed-checkpoint-bytes"
    );
    assert_eq!(
        checkpoint
            .state
            .context
            .records
            .iter()
            .find(|record| record.id == "unrelated-opaque")
            .context("unrelated record")?,
        &opaque_record("unrelated-opaque", "不可改写的用户/厂商正文")?,
        "无关 opaque 正文保持原字节"
    );

    let unchanged = serde_json::to_vec(&checkpoint)?;
    upgraded.prepare_activation().await?;
    assert_eq!(
        serde_json::to_vec(&upgraded.checkpoint().await?.context("stable checkpoint")?)?,
        unchanged,
        "再次激活没有变化"
    );
    Ok(())
}

/// 不可用的旧来源必须 fail-closed：升级失败保留原数据并可重试，不改写任何载荷。
#[tokio::test]
async fn unusable_legacy_compaction_source_fails_closed_without_rewriting() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("history.sqlite");
    let store = HistoryStore::open(&path, "migration").await?;
    let mut state = saved_state(BTreeMap::from([(
        crate::compaction::LATEST_RECEIPT.into(),
        record(7, "pl.studio.compaction", 1, LEGACY_NATIVE_RECEIPT)?,
    )]));
    let mut records = state.context.records.to_vec();
    // 旧来源正文无法恢复成可用的原生 checkpoint 项：迁移必须显式失败而不是猜测。
    let unusable = r#"{"type":"compaction"}"#;
    records.push(ContextRecord {
        id: "compaction:compact-call".into(),
        turn_id: None,
        source: ContextSource::Runtime {
            source_id: "model.compaction".into(),
        },
        content: vec![ContextContent::Opaque {
            payload: OpaquePayload::new("pl.model.compaction", 1, unusable)?,
        }],
        tool_calls: vec![],
    });
    state.context.records = records.into();
    persist(&store, state, true).await?;
    raw_database(&path)
        .await?
        .execute_unprepared("UPDATE history_meta SET schema_version=5")
        .await?;
    drop(store);

    let failed = HistoryStore::open(&path, "migration").await?;
    assert!(failed.prepare_activation().await.is_err());
    assert!(
        failed.prepare_activation().await.is_err(),
        "升级步骤没有被标记完成，仍可重试"
    );
    drop(failed);
    // 原数据与旧版本仍可重试读取，升级没有被部分提交。
    let retryable = HistoryStore::open(&path, "migration").await?;
    let checkpoint = retryable
        .checkpoint()
        .await?
        .context("preserved checkpoint")?;
    assert_eq!(checkpoint.state_revision, 1);
    let compaction = checkpoint
        .state
        .context
        .records
        .iter()
        .find(|record| record.id == "compaction:compact-call")
        .context("preserved compaction record")?;
    let [ContextContent::Opaque { payload }] = compaction.content.as_slice() else {
        anyhow::bail!("preserved compaction record is not opaque");
    };
    assert_eq!(payload.version(), 1, "失败不升级来源结构");
    assert_eq!(payload.content(), unusable, "原正文逐字保留");

    // 单一解码边界本身拒绝未知旧适配值与未来版本。
    let unsafe_receipt = LEGACY_NATIVE_RECEIPT.replace("\"deepSeek\"", "\"mysteryVendor\"");
    assert!(crate::compaction::decode_receipt(1, &unsafe_receipt).is_err());
    assert!(crate::compaction::decode_receipt(3, LEGACY_NATIVE_RECEIPT).is_err());
    Ok(())
}

/// 共享 history 入口必须让 checkpoint 冷读等到 writer 完成 identity，而不是另开半初始化库。
#[tokio::test]
async fn shared_history_checkpoint_waits_for_identity_and_keeps_cold_reads_empty() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let database_path = directory.path().join("studio/v2/studio.sqlite");
    let store = crate::studio::StudioStore::open(&database_path).await?;
    let thread_id = "migration";
    let thread = bound_thread(thread_id);
    let history = registered_history(&store, &thread).await?;
    let history_path = store
        .session_paths(&thread.project_id, thread_id)?
        .history_database();

    let missing = crate::studio::thread_factory::recovery::load_checkpoint(&store, &thread).await?;
    assert!(missing.is_none(), "缺库冷读必须为空且不创建文件");
    assert!(!tokio::fs::try_exists(&history_path).await?);

    let (entered, release) = history.arm_init_gate().await;
    let writer = history.clone();
    let mut drive_state = SharedHistoryDrive {
        persist: Some(tokio::spawn(async move {
            persist(&writer, saved_state(BTreeMap::new()), true).await
        })),
        checkpoint: None,
        release: Some(release),
    };
    let drive = drive_state
        .run(&store, &thread, thread_id, &history_path, entered)
        .await;
    let cleanup = drive_state.reclaim().await;
    let recovered = finish_shared_history_drive(drive, cleanup)?;
    assert_eq!(recovered.thread_id, thread_id);
    assert_eq!(recovered.state_revision, 1);
    let foreign = store
        .state_for(&thread.project_id, "other-thread")?
        .load(&history)
        .await
        .expect_err("错 Thread 的 history 句柄必须失败闭锁");
    assert!(
        foreign
            .to_string()
            .contains("history database belongs to another Thread"),
        "{foreign}"
    );

    drop(history);
    drop(store);
    let damaged = crate::studio::StudioStore::open(&database_path).await?;
    raw_database(&history_path)
        .await?
        .execute_unprepared("DELETE FROM history_meta")
        .await?;
    let error = crate::studio::thread_factory::recovery::load_checkpoint(&damaged, &thread)
        .await
        .expect_err("损坏 identity 必须失败闭锁");
    assert!(
        error
            .to_string()
            .contains("history database identity row is missing"),
        "{error}"
    );
    Ok(())
}

/// 本交错测试每个阶段的静态预算。超时只用于失败闭锁，同步本体仍是 oneshot。
const SHARED_HISTORY_STAGE_BUDGET: std::time::Duration = std::time::Duration::from_secs(30);

fn missed_shared_history_init(stage: &str) -> anyhow::Error {
    anyhow::anyhow!(
        "{stage} exceeded {:?}: checkpoint/reader missed shared history initialization (`StudioStore::history` must install the handle so writer and checkpoint share one init lock)",
        SHARED_HISTORY_STAGE_BUDGET
    )
}

async fn wait_shared_history_stage<T>(
    stage: &'static str,
    future: impl std::future::Future<Output = T>,
) -> Result<T> {
    tokio::time::timeout(SHARED_HISTORY_STAGE_BUDGET, future)
        .await
        .map_err(|_| missed_shared_history_init(stage))
}

async fn join_shared_history_handle<T>(
    stage: &'static str,
    handle: &mut Option<tokio::task::JoinHandle<Result<T>>>,
) -> Result<T> {
    let task = handle
        .as_mut()
        .with_context(|| format!("{stage} handle missing"))?;
    let joined = wait_shared_history_stage(stage, task).await?;
    let _ = handle.take();
    joined.with_context(|| format!("{stage} join"))?
}

struct SharedHistoryDrive {
    persist: Option<tokio::task::JoinHandle<Result<()>>>,
    checkpoint: Option<tokio::task::JoinHandle<Result<Option<ThreadCheckpoint>>>>,
    release: Option<tokio::sync::oneshot::Sender<()>>,
}

impl SharedHistoryDrive {
    async fn run(
        &mut self,
        store: &crate::studio::StudioStore,
        thread: &pl_protocol::Thread,
        thread_id: &str,
        history_path: &std::path::Path,
        entered: tokio::sync::oneshot::Receiver<()>,
    ) -> Result<ThreadCheckpoint> {
        wait_shared_history_stage("writer gate arrived", entered).await??;
        assert!(
            tokio::fs::try_exists(history_path).await?,
            "writer connect 已创建文件，但 identity 尚未提交"
        );

        let waiting_history = store.history(thread_id).await?;
        let reader_waiting = waiting_history.arm_reader_before_init().await;
        let waiting = store.clone();
        let waiting_thread = thread.clone();
        self.checkpoint = Some(tokio::spawn(async move {
            crate::studio::thread_factory::recovery::load_checkpoint(&waiting, &waiting_thread)
                .await
        }));
        wait_shared_history_stage("reader waiting on shared init", reader_waiting).await??;
        self.release
            .take()
            .context("writer gate already released")?
            .send(())
            .map_err(|_| anyhow::anyhow!("writer dropped the init gate"))?;

        join_shared_history_handle("persist join", &mut self.persist).await?;
        join_shared_history_handle("checkpoint join", &mut self.checkpoint)
            .await?
            .context("shared checkpoint")
    }

    async fn reclaim(self) -> Result<()> {
        if let Some(release) = self.release {
            let _ = release.send(());
        }
        let persist = reclaim_shared_history_task("persist", self.persist).await;
        let checkpoint = reclaim_shared_history_task("checkpoint", self.checkpoint).await;
        match (persist, checkpoint) {
            (Ok(()), Ok(())) => Ok(()),
            (Err(error), Ok(())) | (Ok(()), Err(error)) => Err(error),
            (Err(persist), Err(checkpoint)) => Err(persist.context(checkpoint)),
        }
    }
}

async fn reclaim_shared_history_task<T>(
    name: &'static str,
    handle: Option<tokio::task::JoinHandle<Result<T>>>,
) -> Result<()> {
    let Some(handle) = handle else {
        return Ok(());
    };
    if !handle.is_finished() {
        handle.abort();
    }
    match handle.await {
        Ok(Ok(_)) => Ok(()),
        Ok(Err(error)) => Err(error.context(format!("{name} failed while reclaiming"))),
        Err(error) if error.is_cancelled() => Ok(()),
        Err(error) => Err(anyhow::anyhow!("{name} join failed: {error}")),
    }
}

fn finish_shared_history_drive<T>(drive: Result<T>, cleanup: Result<()>) -> Result<T> {
    match (drive, cleanup) {
        (Ok(value), Ok(())) => Ok(value),
        (Err(drive), Ok(())) => Err(drive),
        (Ok(_), Err(cleanup)) => Err(cleanup),
        (Err(drive), Err(cleanup)) => Err(drive.context(format!("cleanup: {cleanup:#}"))),
    }
}
