//! Saved representation migration (Mode, model access, compaction sources) through the actual
//! SQLite checkpoint, history writer and history schema-upgrade paths.
use std::collections::{BTreeMap, BTreeSet};

use super::history::{EffectCommit, HistoryStore};
use crate::agent::definition::{
    AgentDefinitionOrigin, AgentDefinitionScope, ResolvedAgentDefinition, VerifiedAgentIdentity,
};
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
    let instructions = legacy_instructions(
        legacy_block("modelBase", "保留的模式名称", "base"),
        vec![legacy_block(
            "executionProfile",
            "保留的模式名称",
            "保存的原始 Prompt",
        )],
        Vec::new(),
    )?;
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
                payload: instructions,
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
        thread_id: store.thread_id().into(),
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
    let checkpoint = ThreadCheckpoint::capture(store.thread_id().into(), sequence, state);
    store
        .commit_checkpoint_effect(
            &checkpoint,
            &effect,
            EffectCommit {
                completions: &[],
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
            crate::studio::storage::history::AccountingCommit {
                facts: &crate::studio::thread_projection::PreparedAccounting::prepare(&effect)?,
                material_changed: true,
            },
        )
        .await
        .map(|_| ())
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
    let legacy = store
        .prepare_model_access()
        .await?
        .context("legacy checkpoint")?;
    let faults = raw_database(&path).await?;
    faults.execute_unprepared("CREATE TRIGGER block_execution_identity BEFORE UPDATE ON session_checkpoint BEGIN SELECT RAISE(ABORT,'injected execution identity write fault'); END").await?;
    assert!(
        store
            .prepare_execution_identity(|state| {
                crate::mode::migrate_mode_snapshot(state, &manager)?;
                Ok(())
            })
            .await
            .is_err()
    );
    assert_eq!(
        serde_json::to_value(store.checkpoint().await?.context("preserved Mode")?)?,
        serde_json::to_value(&legacy)?
    );
    assert!(faults.query_one_raw(sea_orm::Statement::from_string(sea_orm::DatabaseBackend::Sqlite,
        "SELECT version FROM seaql_migrations WHERE version='m20261026_000008_history_execution_identity'")).await?.is_none(), "failed Mode migration cannot publish its completion record");
    faults
        .execute_unprepared("DROP TRIGGER block_execution_identity")
        .await?;
    faults.close().await?;
    let migrated = store
        .prepare_execution_identity(|state| {
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
            .prepare_execution_identity(|state| {
                crate::mode::migrate_mode_snapshot(state, &manager)?;
                Ok(())
            })
            .await
            .is_ok(),
        "an applied official migration is idempotent"
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
    let checkpoint = store.prepare_model_access().await?.context("checkpoint")?;
    let before = serde_json::to_vec(&checkpoint)?;
    assert!(
        store
            .prepare_execution_identity(|state| {
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

// ── 指令快照的 Agent/Mode 来源迁移 ──

/// 旧版实际写出的 v1 指令块：`executionProfile` 同时承载 Mode 与 child Profile 的角色正文。
fn legacy_block(kind: &str, label: &str, content: &str) -> serde_json::Value {
    serde_json::json!({
        "source": { "kind": kind, "label": label },
        "content": content,
    })
}

/// 旧版带 `path` 的指令块（项目文档、显式 base 覆盖等来源会携带路径）。
fn legacy_block_with_path(kind: &str, label: &str, path: &str, content: &str) -> serde_json::Value {
    serde_json::json!({
        "source": { "kind": kind, "label": label, "path": path },
        "content": content,
    })
}

/// 供逐项比对的当前结构指令块。
fn expected_block(
    kind: crate::instruction::InstructionSourceKind,
    label: &str,
    path: Option<&str>,
    content: &str,
) -> crate::instruction::InstructionBlock {
    crate::instruction::InstructionBlock {
        source: crate::instruction::InstructionSource {
            kind,
            label: label.into(),
            path: path.map(str::to_owned),
        },
        content: content.into(),
    }
}

fn legacy_instructions(
    base: serde_json::Value,
    developer: Vec<serde_json::Value>,
    user: Vec<serde_json::Value>,
) -> Result<OpaquePayload> {
    Ok(OpaquePayload::new(
        "pl.studio.instructions",
        1,
        serde_json::to_string(&serde_json::json!({
            "base": base,
            "developer": developer,
            "user": user,
        }))?,
    )?)
}

fn migration_child_profile() -> pl_protocol::AgentProfileSnapshot {
    pl_protocol::AgentProfileSnapshot {
        profile_id: "reviewer".into(),
        display_name: "Reviewer".into(),
        description: String::new(),
        when_to_use: String::new(),
        system_instructions: "保存的原始 Prompt".into(),
        account_id: "deepseek".into(),
        model_id: "deepseek-flash".into(),
        effort: Some("high".into()),
        source: "config".into(),
        revision: "7".into(),
        content_hash: String::new(),
        system: true,
        enabled: true,
        workspace_mode: pl_protocol::AgentWorkspaceMode::Unrestricted,
    }
}

fn instruction_state(payload: OpaquePayload) -> ThreadSnapshot {
    saved_state(BTreeMap::from([(
        "studio.instructions".into(),
        ExtensionRecord {
            revision: 3,
            payload,
        },
    )]))
}

/// 根会话的旧角色正文归 Mode 来源；原正文、其他来源与历史经真实持久化往返保留。
#[tokio::test]
async fn legacy_root_instruction_source_becomes_the_mode_source_and_survives_a_reopen() -> Result<()>
{
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("history.sqlite");
    let store = HistoryStore::open(&path, "migration").await?;
    // 旧版显式 base 覆盖带 label/path/正文：迁移必须逐项保留，不能被 base 丢弃或改写。
    let original = instruction_state(legacy_instructions(
        legacy_block_with_path(
            "profileBaseOverride",
            "迁移前显式基础提示词",
            "/legacy/base.md",
            "旧版显式覆盖的 base 正文",
        ),
        vec![
            legacy_block("executionProfile", "保留的模式名称", "保存的原始 Prompt"),
            legacy_block_with_path(
                "delegationPreference",
                "历史自动分发偏好",
                "/legacy/delegation.md",
                "  保存的经济偏好正文\n不从当前配置重建  ",
            ),
            legacy_block("platform", "platform: linux/bash", "保留的平台事实"),
        ],
        vec![
            legacy_block("configUser", "config user", "保留的用户上下文"),
            legacy_block_with_path(
                "projectDoc",
                "AGENTS.md",
                "/legacy/AGENTS.md",
                "保留的项目文档",
            ),
        ],
    )?);
    persist(&store, original.clone(), true).await?;
    // 没有可验证渠道归属的旧根会话迁移到明确渠道未指定的 legacy-root，而不是当前普通根。
    let root = VerifiedAgentIdentity::GenericRoot;
    let migrated = store
        .prepare_execution_identity(|state| {
            crate::instruction::migrate_saved_representation(state, &root)
        })
        .await?;
    let payload = &migrated.state.extensions["studio.instructions"].payload;
    assert_eq!(payload.version(), 3);
    let snapshot = crate::instruction::decode_snapshot(payload)?;
    assert_eq!(snapshot.agent.id, "root:legacy");
    assert_ne!(snapshot.agent.id, "root:main");
    assert_eq!(snapshot.agent.scope, AgentDefinitionScope::Root);
    assert_eq!(snapshot.agent.origin, AgentDefinitionOrigin::Migrated);
    assert_eq!(snapshot.agent.revision, "legacy");
    // base 与未被转换的指令块按完整对象比对：来源种类、label、path 与正文都必须逐项保留。
    assert_eq!(
        snapshot.base,
        expected_block(
            crate::instruction::InstructionSourceKind::ProfileBaseOverride,
            "迁移前显式基础提示词",
            Some("/legacy/base.md"),
            "旧版显式覆盖的 base 正文",
        )
    );
    assert_eq!(
        snapshot.developer,
        vec![
            expected_block(
                crate::instruction::InstructionSourceKind::ModeDefinition,
                "保留的模式名称",
                None,
                "保存的原始 Prompt",
            ),
            expected_block(
                crate::instruction::InstructionSourceKind::DelegationPreference,
                "历史自动分发偏好",
                Some("/legacy/delegation.md"),
                "  保存的经济偏好正文\n不从当前配置重建  ",
            ),
            expected_block(
                crate::instruction::InstructionSourceKind::Platform,
                "platform: linux/bash",
                None,
                "保留的平台事实",
            ),
        ]
    );
    let instruction_records = snapshot
        .context_records("migration")
        .into_iter()
        .filter(|record| record.source == ContextSource::Instruction)
        .collect::<Vec<_>>();
    assert_eq!(
        instruction_records.len(),
        1,
        "受信正文应折叠为单条 Instruction record"
    );
    let trusted = snapshot.trusted_text();
    assert_eq!(
        instruction_records[0].content,
        vec![ContextContent::Text {
            text: trusted.clone().into(),
        }]
    );
    assert!(
        trusted.contains("保存的经济偏好正文"),
        "历史自动分发偏好正文不得在折叠受信正文时丢失"
    );
    assert_eq!(
        snapshot.user,
        vec![
            expected_block(
                crate::instruction::InstructionSourceKind::ConfigUser,
                "config user",
                None,
                "保留的用户上下文",
            ),
            expected_block(
                crate::instruction::InstructionSourceKind::ProjectDoc,
                "AGENTS.md",
                Some("/legacy/AGENTS.md"),
                "保留的项目文档",
            ),
        ]
    );
    assert!(
        snapshot
            .developer
            .iter()
            .all(|block| block.source.kind
                != crate::instruction::InstructionSourceKind::AgentDefinition),
        "旧飞书/普通根会话不补入新的 Agent 角色正文"
    );
    assert_eq!(migrated.state.context, original.context);
    // 有效的 bot 归属证明迁移为飞书 legacy 身份，同样保留原正文。
    let mut bot_proven = instruction_state(legacy_instructions(
        legacy_block("modelBase", "model base", "base"),
        vec![legacy_block(
            "executionProfile",
            "保留的模式名称",
            "保存的原始 Prompt",
        )],
        Vec::new(),
    )?);
    crate::instruction::migrate_saved_representation(
        &mut bot_proven,
        &VerifiedAgentIdentity::BotRoot,
    )?;
    let bot_snapshot =
        crate::instruction::decode_snapshot(&bot_proven.extensions["studio.instructions"].payload)?;
    assert_eq!(bot_snapshot.agent.id, "root:feishu");
    assert_eq!(bot_snapshot.agent.revision, "legacy");
    assert_eq!(
        bot_snapshot.base,
        expected_block(
            crate::instruction::InstructionSourceKind::ModelBase,
            "model base",
            None,
            "base",
        )
    );
    assert_eq!(bot_snapshot.developer.len(), 1);
    assert_eq!(
        bot_snapshot.developer[0],
        expected_block(
            crate::instruction::InstructionSourceKind::ModeDefinition,
            "保留的模式名称",
            None,
            "保存的原始 Prompt",
        )
    );

    drop(store);
    let reopened = HistoryStore::open(&path, "migration").await?;
    let durable = reopened
        .checkpoint()
        .await?
        .context("durable instructions")?;
    assert_eq!(
        durable.state.extensions["studio.instructions"],
        migrated.state.extensions["studio.instructions"]
    );
    // 重开的持久库同样按保存事实校验 base，而不是只与迁移输出自身比较。
    let durable_snapshot = crate::instruction::decode_snapshot(
        &durable.state.extensions["studio.instructions"].payload,
    )?;
    assert_eq!(
        durable_snapshot.base,
        expected_block(
            crate::instruction::InstructionSourceKind::ProfileBaseOverride,
            "迁移前显式基础提示词",
            Some("/legacy/base.md"),
            "旧版显式覆盖的 base 正文",
        )
    );
    assert_eq!(durable.state.context, original.context);
    assert_eq!(durable_snapshot.developer, snapshot.developer);
    Ok(())
}

/// Version 2 is validated with its old root-ID shape, then migrated using only frozen blocks.
/// The real SQLite recovery writer preserves the legacy root's missing Agent source and stable
/// user fact IDs across a process-style reopen.
#[tokio::test]
async fn v2_generic_root_migration_preserves_shape_content_and_user_source_ids() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("history.sqlite");
    let store = HistoryStore::open(&path, "migration").await?;
    let previous = crate::instruction::InstructionSnapshot {
        agent: agent_identity(
            "root:main",
            AgentDefinitionScope::Root,
            "root-revision-before-shape-freeze",
            AgentDefinitionOrigin::Builtin,
        ),
        agent_shape: crate::instruction::AgentInstructionShape::Absent,
        base: expected_block(
            crate::instruction::InstructionSourceKind::ConfigBaseOverride,
            "legacy explicit base",
            Some("/frozen/base.md"),
            "  preserved v2 base  ",
        ),
        developer: vec![
            expected_block(
                crate::instruction::InstructionSourceKind::ModeDefinition,
                "Frozen Task Mode",
                None,
                "Do the saved task, not the current catalog task.",
            ),
            expected_block(
                crate::instruction::InstructionSourceKind::DelegationPreference,
                "saved dispatch policy",
                Some("/frozen/dispatch.md"),
                "preserve the saved preference",
            ),
            expected_block(
                crate::instruction::InstructionSourceKind::Platform,
                "platform: frozen-v2",
                None,
                "Preserve this platform instruction.",
            ),
        ],
        user: vec![expected_block(
            crate::instruction::InstructionSourceKind::ProjectDoc,
            "AGENTS.md",
            Some("/frozen/AGENTS.md"),
            "Preserve the original project document.",
        )],
    };
    let previous_payload = previous_snapshot_payload(&previous)?;
    let original = instruction_state(previous_payload.clone());
    persist(&store, original.clone(), true).await?;
    let checkpoint = store
        .prepare_model_access()
        .await?
        .context("v2 root checkpoint")?;
    let prior_user_records = previous
        .context_records("migration")
        .into_iter()
        .filter(|record| matches!(record.source, ContextSource::RuntimeFact { .. }))
        .collect::<Vec<_>>();
    assert_eq!(prior_user_records.len(), 1);

    let migrated = store
        .prepare_execution_identity(|state| {
            crate::instruction::migrate_saved_representation(
                state,
                &VerifiedAgentIdentity::GenericRoot,
            )
        })
        .await?;
    let record = &migrated.state.extensions["studio.instructions"];
    assert_eq!(
        record.revision,
        checkpoint.state.extensions["studio.instructions"].revision
    );
    assert_eq!(record.payload.version(), 3);
    let current = crate::instruction::decode_snapshot(&record.payload)?;
    assert_eq!(
        current.agent,
        agent_identity(
            "root:main",
            AgentDefinitionScope::Root,
            "root-revision-before-shape-freeze",
            AgentDefinitionOrigin::Builtin,
        )
    );
    assert_eq!(
        current.agent_shape,
        crate::instruction::AgentInstructionShape::Absent
    );
    assert!(current.developer.iter().all(|block| {
        block.source.kind != crate::instruction::InstructionSourceKind::AgentDefinition
    }));
    assert_eq!(current.base, previous.base);
    assert_eq!(current.developer, previous.developer);
    assert_eq!(current.user, previous.user);
    assert_eq!(current.trusted_text(), previous.trusted_text());
    let current_user_records = current
        .context_records("migration")
        .into_iter()
        .filter(|record| matches!(record.source, ContextSource::RuntimeFact { .. }))
        .collect::<Vec<_>>();
    assert_eq!(current_user_records, prior_user_records);
    assert_eq!(migrated.state.context, original.context);

    let mut frozen_system_profile = migration_child_profile();
    frozen_system_profile.system = true;
    let frozen_child = VerifiedAgentIdentity::child(&frozen_system_profile)?;
    let previous_child = crate::instruction::InstructionSnapshot {
        agent: agent_identity(
            &frozen_system_profile.profile_id,
            AgentDefinitionScope::Child,
            &frozen_system_profile.revision,
            AgentDefinitionOrigin::Profile,
        ),
        agent_shape: crate::instruction::AgentInstructionShape::Absent,
        base: base_block(),
        developer: vec![expected_block(
            crate::instruction::InstructionSourceKind::AgentDefinition,
            &frozen_system_profile.display_name,
            None,
            &frozen_system_profile.system_instructions,
        )],
        user: Vec::new(),
    };
    let mut child_state = instruction_state(previous_snapshot_payload(&previous_child)?);
    crate::instruction::migrate_saved_representation(&mut child_state, &frozen_child)?;
    let child_snapshot = crate::instruction::decode_snapshot(
        &child_state.extensions["studio.instructions"].payload,
    )?;
    assert_eq!(child_snapshot.agent.id, frozen_system_profile.profile_id);
    assert_eq!(child_snapshot.agent.scope, AgentDefinitionScope::Child);
    assert_eq!(child_snapshot.agent.origin, AgentDefinitionOrigin::Builtin);
    assert_eq!(
        child_snapshot.agent.revision,
        frozen_system_profile.revision
    );
    assert_eq!(child_snapshot.developer, previous_child.developer);
    assert_eq!(
        child_snapshot.agent_shape,
        crate::instruction::AgentInstructionShape::Present {
            content_hash: pl_core::context::content_hash(
                frozen_system_profile.system_instructions.as_bytes()
            ),
        }
    );

    drop(store);
    let reopened = HistoryStore::open(&path, "migration").await?;
    let durable = reopened
        .checkpoint()
        .await?
        .context("reopened v3 root checkpoint")?;
    assert_eq!(durable.state.extensions["studio.instructions"], *record);
    let durable_snapshot = crate::instruction::decode_snapshot(
        &durable.state.extensions["studio.instructions"].payload,
    )?;
    assert_eq!(
        durable_snapshot.agent_shape,
        crate::instruction::AgentInstructionShape::Absent
    );
    assert_eq!(durable_snapshot.trusted_text(), previous.trusted_text());
    assert_eq!(durable.state.context, original.context);
    Ok(())
}

/// Historically legal v2 identities survive real SQLite migration with their frozen origin and
/// revision intact; the new usage binding records independently verified host facts.
#[tokio::test]
async fn v2_root_identity_contract_round_trips_without_reselecting_current_entry() -> Result<()> {
    let cases = [
        (
            "generic-main",
            "root:main",
            "root-revision-9",
            AgentDefinitionOrigin::Builtin,
            false,
            false,
        ),
        (
            "generic-feishu",
            "root:feishu",
            "old-feishu-revision",
            AgentDefinitionOrigin::Builtin,
            true,
            false,
        ),
        (
            "generic-migrated-feishu",
            "root:feishu",
            "legacy",
            AgentDefinitionOrigin::Migrated,
            false,
            false,
        ),
        (
            "generic-migrated-legacy",
            "root:legacy",
            "legacy",
            AgentDefinitionOrigin::Migrated,
            false,
            false,
        ),
        (
            "bot-feishu",
            "root:feishu",
            "old-bot-revision",
            AgentDefinitionOrigin::Builtin,
            true,
            true,
        ),
        (
            "bot-migrated-feishu",
            "root:feishu",
            "legacy",
            AgentDefinitionOrigin::Migrated,
            false,
            true,
        ),
        (
            "bot-migrated-legacy",
            "root:legacy",
            "legacy",
            AgentDefinitionOrigin::Migrated,
            false,
            true,
        ),
    ];
    for (case, id, revision, origin, has_agent, is_bot) in cases {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let store = HistoryStore::open(&path, "migration").await?;
        let mut developer = Vec::new();
        if has_agent {
            developer.push(instruction_block(
                crate::instruction::InstructionSourceKind::AgentDefinition,
                "Frozen legacy Agent",
                "Keep this saved role body exactly.",
            ));
        }
        developer.push(instruction_block(
            crate::instruction::InstructionSourceKind::ModeDefinition,
            "Saved Mode",
            "Keep this saved Mode body exactly.",
        ));
        let previous = crate::instruction::InstructionSnapshot {
            agent: agent_identity(id, AgentDefinitionScope::Root, revision, origin),
            agent_shape: crate::instruction::AgentInstructionShape::Absent,
            base: base_block(),
            developer,
            user: vec![instruction_block(
                crate::instruction::InstructionSourceKind::ProjectDoc,
                "AGENTS.md",
                "Frozen user context.",
            )],
        };
        let original = instruction_state(previous_snapshot_payload(&previous)?);
        persist(&store, original.clone(), true).await?;
        let verified = if is_bot {
            VerifiedAgentIdentity::BotRoot
        } else {
            VerifiedAgentIdentity::GenericRoot
        };
        let migrated = store
            .prepare_execution_identity(|state| {
                crate::instruction::migrate_saved_representation(state, &verified)
            })
            .await?;
        let payload = &migrated.state.extensions["studio.instructions"].payload;
        assert_eq!(payload.version(), 3, "{case}");
        let snapshot = crate::instruction::decode_snapshot(payload)?;
        let usage_binding = if is_bot {
            crate::agent::definition::AgentUsageBinding::RootEntry(
                crate::agent::definition::AgentRootEntry::Bot,
            )
        } else {
            crate::agent::definition::AgentUsageBinding::LegacyUnspecifiedRoot { source_version: 2 }
        };
        assert_eq!(
            snapshot.agent,
            agent_identity_with_binding(
                id,
                AgentDefinitionScope::Root,
                revision,
                origin,
                usage_binding,
            ),
            "{case}: migration must preserve the complete frozen identity"
        );
        assert_eq!(snapshot.developer, previous.developer, "{case}");
        assert_eq!(snapshot.base, previous.base, "{case}");
        assert_eq!(snapshot.user, previous.user, "{case}");
        assert_eq!(snapshot.trusted_text(), previous.trusted_text(), "{case}");
        assert_eq!(migrated.state.context, original.context, "{case}");

        drop(store);
        let reopened = HistoryStore::open(&path, "migration").await?;
        let durable = reopened
            .checkpoint()
            .await?
            .context("reopened v3 root checkpoint")?;
        let durable_snapshot = crate::instruction::decode_snapshot(
            &durable.state.extensions["studio.instructions"].payload,
        )?;
        assert_eq!(durable_snapshot.agent, snapshot.agent, "{case}");
        assert_eq!(durable_snapshot.developer, previous.developer, "{case}");
        assert_eq!(durable.state.context, original.context, "{case}");
    }
    Ok(())
}

/// The v2 decoder must reject the old malformed shape and identity before replacing durable bytes.
#[tokio::test]
async fn v2_bad_shape_or_untrusted_root_identity_preserves_sqlite_checkpoint() -> Result<()> {
    let malformed_shape = crate::instruction::InstructionSnapshot {
        agent: agent_identity(
            "root:main",
            AgentDefinitionScope::Root,
            "old-root-revision",
            AgentDefinitionOrigin::Builtin,
        ),
        agent_shape: crate::instruction::AgentInstructionShape::Absent,
        base: base_block(),
        developer: vec![
            instruction_block(
                crate::instruction::InstructionSourceKind::AgentDefinition,
                "Injected Agent",
                "not allowed in this v2 root shape",
            ),
            instruction_block(
                crate::instruction::InstructionSourceKind::ModeDefinition,
                "Saved Mode",
                "saved Mode body",
            ),
        ],
        user: Vec::new(),
    };
    let untrusted_root = crate::instruction::InstructionSnapshot {
        agent: agent_identity(
            "root:other",
            AgentDefinitionScope::Root,
            "old-root-revision",
            AgentDefinitionOrigin::Builtin,
        ),
        agent_shape: crate::instruction::AgentInstructionShape::Absent,
        base: base_block(),
        developer: vec![instruction_block(
            crate::instruction::InstructionSourceKind::ModeDefinition,
            "Saved Mode",
            "saved Mode body",
        )],
        user: Vec::new(),
    };
    let bot_owner_conflict = crate::instruction::InstructionSnapshot {
        agent: agent_identity(
            "root:main",
            AgentDefinitionScope::Root,
            "old-root-revision",
            AgentDefinitionOrigin::Builtin,
        ),
        agent_shape: crate::instruction::AgentInstructionShape::Absent,
        base: base_block(),
        developer: vec![instruction_block(
            crate::instruction::InstructionSourceKind::ModeDefinition,
            "Saved Mode",
            "saved Mode body",
        )],
        user: Vec::new(),
    };

    for (case, previous, is_bot) in [
        ("malformed-root-shape", malformed_shape, false),
        ("unsupported-root-id", untrusted_root, false),
        ("bot-owner-root-conflict", bot_owner_conflict, true),
    ] {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let store = HistoryStore::open(&path, "migration").await?;
        let original = instruction_state(previous_snapshot_payload(&previous)?);
        persist(&store, original.clone(), true).await?;
        let checkpoint = store
            .prepare_model_access()
            .await?
            .context("v2 checkpoint")?;
        let before = serde_json::to_vec(&checkpoint)?;
        let verified = if is_bot {
            VerifiedAgentIdentity::BotRoot
        } else {
            VerifiedAgentIdentity::GenericRoot
        };
        assert!(
            store
                .prepare_execution_identity(|state| {
                    crate::instruction::migrate_saved_representation(state, &verified)
                })
                .await
                .is_err(),
            "{case} must be rejected"
        );
        assert_eq!(
            serde_json::to_vec(
                &store
                    .checkpoint()
                    .await?
                    .context("retained v2 checkpoint")?
            )?,
            before,
            "{case} must leave the original checkpoint intact"
        );
        drop(store);
        let reopened = HistoryStore::open(&path, "migration").await?;
        let durable = reopened
            .checkpoint()
            .await?
            .context("reopened v2 checkpoint")?;
        assert_eq!(durable.state.context, original.context);
        assert_eq!(
            durable.state.extensions["studio.instructions"].payload,
            original.extensions["studio.instructions"].payload,
            "{case} must remain v2 after reopen"
        );
    }
    Ok(())
}

/// A v2 checkpoint written before trusted instructions were folded into one record must be
/// normalized by the production ContextPreparer, then remain unchanged on the next preparation.
#[tokio::test]
async fn restored_v2_multi_record_instructions_are_normalized_once() -> Result<()> {
    use crate::instruction::{InstructionSnapshot, InstructionSourceKind};
    use pl_core::{
        model::ModelFactory,
        thread::{StepInput, ThreadHandle},
    };
    use pl_model::{
        completion::OpenAiCompactionMode,
        config::{AccountId, ResolvedModelRoute},
        model::ModelInfo,
        protocol::ProtocolEndpoint,
        runtime::{ModelRuntime, ThreadModel},
    };
    use std::sync::Arc;

    let manager = ThreadModeManager::default();
    let registry = crate::studio::thread::register_builtins(&manager)?;
    let mode = registry
        .mode(&pl_protocol::ThreadModeId::simple())
        .context("built-in simple Mode")?;
    let mut model_info = ModelInfo::compatible("migration-model");
    model_info.base_instructions = "frozen migration base".into();
    let endpoint = ProtocolEndpoint::compatible("migration fixture", "http://127.0.0.1:0");
    let route = ResolvedModelRoute {
        pricing_mode: Default::default(),
        role: crate::config::root_agent_route_id(),
        account_id: AccountId::new("migration-account")?,
        endpoint,
        context: model_info.resolve_context(None),
        model: model_info,
        effort: None,
    };
    let model = ThreadModel::new(ModelRuntime::from_route(&route)?, None);
    let snapshot = InstructionSnapshot {
        agent: agent_identity(
            "root:main",
            AgentDefinitionScope::Root,
            "1",
            AgentDefinitionOrigin::Builtin,
        ),
        agent_shape: crate::instruction::AgentInstructionShape::Present {
            content_hash: pl_core::context::content_hash("主智能体职责".as_bytes()),
        },
        base: expected_block(
            InstructionSourceKind::ModelBase,
            "model base",
            None,
            "frozen migration base",
        ),
        developer: vec![
            expected_block(
                InstructionSourceKind::AgentDefinition,
                "主智能体",
                None,
                "主智能体职责",
            ),
            expected_block(
                InstructionSourceKind::ModeDefinition,
                &mode.descriptor().display_name,
                None,
                mode.prompt(),
            ),
            expected_block(
                InstructionSourceKind::Platform,
                "platform: migration-test",
                None,
                "Preserve this frozen platform instruction.",
            ),
        ],
        user: vec![expected_block(
            InstructionSourceKind::ConfigUser,
            "config user",
            None,
            "Preserve this user instruction fact.",
        )],
    };
    let instruction_payload = snapshot_payload(&snapshot)?;
    let mode_payload =
        crate::mode::encode_mode_snapshot(&crate::mode::SavedThreadMode::capture(&mode, None))?;
    let binding_payload = OpaquePayload::new(
        "pl.studio.instruction-binding",
        1,
        serde_json::to_string(&serde_json::json!({
            "routeIdentity": model.route_identity(),
            "appendSnapshots": false,
        }))?,
    )?;
    let format_block = |block: &crate::instruction::InstructionBlock| {
        format!("# {}\n{}", block.source.label, block.content)
    };
    let mut records = std::iter::once(&snapshot.base)
        .chain(snapshot.developer.iter())
        .enumerate()
        .map(|(index, block)| ContextRecord {
            id: format!("instruction:migration:{index}"),
            turn_id: None,
            source: ContextSource::Instruction,
            content: vec![ContextContent::Text {
                text: Arc::from(format_block(block)),
            }],
            tool_calls: Vec::new(),
        })
        .collect::<Vec<_>>();
    // The record shape matches the original v2 projection: base and each developer source were
    // independent Instruction records, while user/runtime facts had separate stable identities.
    records.extend([
        ContextRecord {
            id: "preserved-user-history".into(),
            turn_id: None,
            source: ContextSource::User,
            content: vec![ContextContent::Text {
                text: "Keep this historical user fact.".into(),
            }],
            tool_calls: Vec::new(),
        },
        ContextRecord {
            id: "instruction:migration:4".into(),
            turn_id: None,
            source: ContextSource::RuntimeFact {
                source_id: "studio.instructions:4".into(),
            },
            content: vec![ContextContent::Text {
                text: Arc::from(format_block(&snapshot.user[0])),
            }],
            tool_calls: Vec::new(),
        },
        ContextRecord {
            id: "preserved-runtime-fact".into(),
            turn_id: None,
            source: ContextSource::RuntimeFact {
                source_id: "fixture.runtime".into(),
            },
            content: vec![ContextContent::Text {
                text: "Keep this runtime fact.".into(),
            }],
            tool_calls: Vec::new(),
        },
    ]);
    let original = ThreadSnapshot {
        commit_sequence: 1,
        extension_sequence: 3,
        extensions: BTreeMap::from([
            (
                "studio.mode".into(),
                ExtensionRecord {
                    revision: 1,
                    payload: mode_payload,
                },
            ),
            (
                "studio.instructions".into(),
                ExtensionRecord {
                    revision: 2,
                    payload: instruction_payload,
                },
            ),
            (
                "studio.instructions.binding".into(),
                ExtensionRecord {
                    revision: 3,
                    payload: binding_payload,
                },
            ),
        ]),
        context: ContextSnapshot {
            revision: 1,
            records: records.into(),
        },
        runtime_facts: vec![pl_core::thread::RuntimeFact {
            source_id: "fixture.runtime".into(),
            content: vec![ContextContent::Text {
                text: "Keep this runtime fact.".into(),
            }],
        }]
        .into(),
        ..Default::default()
    };
    let original_instruction_text = original
        .context
        .records
        .iter()
        .filter(|record| record.source == ContextSource::Instruction)
        .flat_map(|record| &record.content)
        .filter_map(|content| match content {
            ContextContent::Text { text } => Some(text.as_ref()),
            _ => None,
        })
        .collect::<Vec<_>>()
        .join("\n");
    assert_eq!(original_instruction_text, snapshot.trusted_text());

    let directory = tempfile::tempdir()?;
    let history_path = directory.path().join("history.sqlite");
    let store = HistoryStore::open(&history_path, "migration").await?;
    persist(&store, original, true).await?;
    let checkpoint = store
        .checkpoint()
        .await?
        .context("v2 multi-record checkpoint")?;
    let thread = ThreadHandle::resume(
        "migration".into(),
        ModelFactory::new(model.clone()).open_session().await?,
        Some(checkpoint),
    )?;
    thread
        .set_context_preparation(crate::compaction::preparer(
            &route,
            model,
            OpenAiCompactionMode::Local,
            manager,
        )?)
        .await?;

    let step = |attempt: &str| StepInput {
        turn_id: "restore-instructions".into(),
        attempt_id: attempt.into(),
        content: Vec::new(),
        cancellation: Default::default(),
    };
    assert!(thread.step(step("normalize-once")).await.is_err());
    let normalized = thread.snapshot().context;
    let instruction_records = normalized
        .records
        .iter()
        .filter(|record| {
            matches!(
                record.source,
                ContextSource::Instruction | ContextSource::InstructionSnapshot { .. }
            )
        })
        .collect::<Vec<_>>();
    assert_eq!(instruction_records.len(), 1);
    assert!(matches!(
        instruction_records[0].source,
        ContextSource::InstructionSnapshot { .. }
    ));
    assert_eq!(
        instruction_records[0].content,
        vec![ContextContent::Text {
            text: Arc::from(snapshot.trusted_text()),
        }]
    );
    if let ContextSource::InstructionSnapshot { content_hash, .. } = &instruction_records[0].source
    {
        assert_eq!(
            content_hash,
            &pl_core::context::content_hash(snapshot.trusted_text().as_bytes())
        );
    }
    assert!(normalized.records.iter().any(|record| {
        record.id == "preserved-user-history"
            && record.source == ContextSource::User
            && record.content.iter().any(|content| {
                matches!(content, ContextContent::Text { text } if text.as_ref() == "Keep this historical user fact.")
            })
    }));
    assert!(normalized.records.iter().any(|record| {
        record.id == "instruction:migration:4"
            && record.source
                == (ContextSource::RuntimeFact {
                    source_id: "studio.instructions:4".into(),
                })
            && record.content.iter().any(|content| {
                matches!(content, ContextContent::Text { text } if text.as_ref() == format_block(&snapshot.user[0]))
            })
    }));
    assert!(normalized.records.iter().any(|record| {
        record.id == "preserved-runtime-fact"
            && record.source
                == (ContextSource::RuntimeFact {
                    source_id: "fixture.runtime".into(),
                })
    }));

    assert!(thread.step(step("prepare-again")).await.is_err());
    assert_eq!(thread.snapshot().context, normalized);
    thread.close().await?;
    Ok(())
}

/// Mode reconfiguration treats a missing route binding as unknown: canonical initial context may
/// only bind without an instruction revision, while a restored snapshot must be replaced.
#[tokio::test]
async fn mode_binding_recovery_replaces_unknown_snapshot_and_keeps_initial_context_noop()
-> Result<()> {
    use crate::config::{ConfigPaths, ConfigStore, StudioConfig};
    use crate::studio::paths::StudioPaths;
    use crate::{StudioHostKind, StudioRuntimeOptions};
    use pl_model::{
        config::{AccountConfig, AccountId, ModelRouteConfig},
        model::{ModelInfo, ModelTransportProfile},
        protocol::{HistoryInstructionRole, ProtocolEndpoint},
    };

    let temp = tempfile::tempdir()?;
    let home = temp.path().join("home");
    let workspace = temp.path().join("workspace");
    tokio::fs::create_dir_all(&workspace).await?;

    let account_id = AccountId::new("mode-migration")?;
    let route = ModelRouteConfig {
        account_id: account_id.clone(),
        model_id: "mode-migration-model".into(),
        effort: None,
    };
    let mut model = ModelInfo::compatible(&route.model_id);
    model
        .binding
        .set_transport(ModelTransportProfile::responses_http());
    model.capabilities.instruction_snapshot_overrides = true;
    model.base_instructions = "frozen mode migration base".into();
    let mut endpoint = ProtocolEndpoint::compatible("mode migration", "http://127.0.0.1:0");
    endpoint.service_capabilities.history_instruction_role = HistoryInstructionRole::Developer;
    let mut config = StudioConfig::default_config()?;
    config.models.accounts.clear();
    config.models.accounts.insert(
        account_id,
        AccountConfig::from_explicit_models(endpoint, vec![model]),
    );
    for selected in config
        .models
        .routes
        .values_mut()
        .chain(config.mode_model_routes.values_mut())
    {
        *selected = route.clone();
    }
    ConfigStore::new(ConfigPaths::from_config_dir(&home)).save(&config)?;
    let options = || StudioRuntimeOptions {
        studio_home: Some(home.clone()),
        host: StudioHostKind::Test,
        ..StudioRuntimeOptions::desktop()
    };
    let runtime = crate::StudioRuntime::initialize(options()).await?;
    let project = runtime.open_project(&workspace).await?;
    let thread = runtime
        .create_thread(&project.id, "Mode binding recovery")
        .await?;
    runtime.shutdown_runtime().await?;

    let paths = StudioPaths::resolve(Some(home.clone()))?;
    let history_path = paths
        .session_paths(&project.id, &thread.id)?
        .history_database();
    let history = HistoryStore::open(&history_path, &thread.id).await?;
    let initial = history.checkpoint().await?.context("initial checkpoint")?;
    assert_eq!(
        initial
            .state
            .context
            .records
            .iter()
            .filter(|record| record.source == ContextSource::Instruction)
            .count(),
        1
    );
    assert!(
        initial
            .state
            .context
            .records
            .iter()
            .all(|record| { !matches!(record.source, ContextSource::InstructionSnapshot { .. }) })
    );
    assert!(
        !initial
            .state
            .extensions
            .contains_key("studio.instructions.binding")
    );
    let initial_instructions = initial.state.extensions["studio.instructions"].clone();
    let initial_instruction_records = initial
        .state
        .context
        .records
        .iter()
        .filter(|record| {
            matches!(
                record.source,
                ContextSource::Instruction | ContextSource::InstructionSnapshot { .. }
            )
        })
        .cloned()
        .collect::<Vec<_>>();
    drop(history);

    let runtime = crate::StudioRuntime::initialize(options()).await?;
    runtime
        .set_thread_mode(
            "same-mode-without-binding".into(),
            &thread.id,
            pl_protocol::ThreadModeId::simple(),
        )
        .await?;
    runtime.shutdown_runtime().await?;
    let history = HistoryStore::open(&history_path, &thread.id).await?;
    let same_mode = history
        .checkpoint()
        .await?
        .context("same-Mode checkpoint")?;
    assert_eq!(
        same_mode.state.extensions["studio.instructions"], initial_instructions,
        "binding a canonical initial prompt must not advance its instruction revision"
    );
    let same_mode_instruction_records = same_mode
        .state
        .context
        .records
        .iter()
        .filter(|record| {
            matches!(
                record.source,
                ContextSource::Instruction | ContextSource::InstructionSnapshot { .. }
            )
        })
        .cloned()
        .collect::<Vec<_>>();
    assert_eq!(same_mode_instruction_records, initial_instruction_records);
    let saved_binding = crate::compaction::decode_instruction_binding(
        &same_mode.state.extensions["studio.instructions.binding"],
    )?;
    assert!(saved_binding.append_snapshots);
    drop(history);

    let history = HistoryStore::open(&history_path, &thread.id).await?;
    let checkpoint = history
        .checkpoint()
        .await?
        .context("checkpoint before restoring the old snapshot")?;
    let instruction_record = checkpoint.state.extensions["studio.instructions"].clone();
    let instructions = crate::instruction::decode_snapshot(&instruction_record.payload)?;
    let text = instructions.trusted_text();
    let restored_snapshot = ContextRecord {
        id: format!("instruction:{}:restored-v2", thread.id),
        turn_id: None,
        source: ContextSource::InstructionSnapshot {
            revision: instruction_record.revision,
            content_hash: pl_core::context::content_hash(text.as_bytes()),
            replaces: None,
        },
        content: vec![ContextContent::Text { text: text.into() }],
        tool_calls: Vec::new(),
    };
    let context_revision = checkpoint
        .state
        .context
        .revision
        .checked_add(1)
        .context("context revision exhausted")?;
    let extension_revision = checkpoint
        .state
        .extension_sequence
        .checked_add(1)
        .context("extension revision exhausted")?;
    let sequence = checkpoint
        .state
        .commit_sequence
        .checked_add(1)
        .context("Thread commit sequence exhausted")?;
    anyhow::ensure!(
        checkpoint
            .state
            .extensions
            .contains_key("studio.instructions.binding"),
        "binding to remove from restored checkpoint"
    );
    let extension_change = ExtensionChange::Delete {
        id: "studio.instructions.binding".into(),
        revision: extension_revision,
    };
    let mut state = checkpoint.state.clone();
    state.extensions.remove("studio.instructions.binding");
    state.extension_sequence = extension_revision;
    let mut extension_changes = state.extension_changes.to_vec();
    extension_changes.push(extension_change.clone());
    state.extension_changes = extension_changes.into();
    state.commit_sequence = sequence;
    let mut records = state.context.records.to_vec();
    records.push(restored_snapshot.clone());
    state.context = ContextSnapshot {
        revision: context_revision,
        records: records.into(),
    };
    let effect = ThreadEffectBatch {
        thread_id: thread.id.clone(),
        sequence,
        context: Some(ContextChange::Append {
            revision: context_revision,
            records: vec![restored_snapshot].into(),
        }),
        extensions: vec![extension_change].into(),
        ..Default::default()
    };
    let checkpoint = ThreadCheckpoint::capture(thread.id.clone(), sequence, state);
    let empty = BTreeSet::new();
    history
        .commit_checkpoint_effect(
            &checkpoint,
            &effect,
            EffectCommit {
                completions: &[],
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
            crate::studio::storage::history::AccountingCommit {
                facts: &crate::studio::thread_projection::PreparedAccounting::prepare(&effect)?,
                material_changed: true,
            },
        )
        .await?;
    drop(history);

    let runtime = crate::StudioRuntime::initialize(options()).await?;
    runtime
        .set_thread_mode(
            "changed-mode-with-unknown-binding".into(),
            &thread.id,
            pl_protocol::ThreadModeId::task(),
        )
        .await?;
    runtime.shutdown_runtime().await?;

    let history = HistoryStore::open(&history_path, &thread.id).await?;
    let changed = history
        .checkpoint()
        .await?
        .context("changed-Mode checkpoint")?;
    let current_instruction_records = changed
        .state
        .context
        .records
        .iter()
        .filter(|record| {
            matches!(
                record.source,
                ContextSource::Instruction | ContextSource::InstructionSnapshot { .. }
            )
        })
        .collect::<Vec<_>>();
    assert_eq!(current_instruction_records.len(), 1);
    assert!(matches!(
        current_instruction_records[0].source,
        ContextSource::InstructionSnapshot { .. }
    ));
    let instructions = crate::instruction::decode_snapshot(
        &changed.state.extensions["studio.instructions"].payload,
    )?;
    assert_eq!(
        current_instruction_records[0].content,
        vec![ContextContent::Text {
            text: instructions.trusted_text().into(),
        }]
    );
    crate::compaction::decode_instruction_binding(
        &changed.state.extensions["studio.instructions.binding"],
    )?;
    Ok(())
}

/// child 的旧角色正文归其冻结 Profile 的 Agent 来源，身份与修订来自该快照。
#[tokio::test]
async fn legacy_child_instruction_source_becomes_the_agent_source_of_its_frozen_profile()
-> Result<()> {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("history.sqlite");
    let store = HistoryStore::open(&path, "migration").await?;
    let original = instruction_state(legacy_instructions(
        legacy_block("modelBase", "model base", "base"),
        vec![legacy_block(
            "executionProfile",
            "Reviewer",
            "保存的原始 Prompt",
        )],
        vec![legacy_block_with_path(
            "projectDoc",
            "AGENTS.md",
            "/legacy/AGENTS.md",
            "保留的项目文档",
        )],
    )?);
    persist(&store, original.clone(), true).await?;
    let child = VerifiedAgentIdentity::child(&migration_child_profile())?;
    let migrated = store
        .prepare_execution_identity(|state| {
            crate::instruction::migrate_saved_representation(state, &child)
        })
        .await?;
    let snapshot = crate::instruction::decode_snapshot(
        &migrated.state.extensions["studio.instructions"].payload,
    )?;
    assert_eq!(snapshot.agent.id, "reviewer");
    assert_eq!(snapshot.agent.scope, AgentDefinitionScope::Child);
    assert_eq!(snapshot.agent.origin, AgentDefinitionOrigin::Migrated);
    // 迁移保留旧正文，因此修订明确标为 legacy；冻结 Profile 自己的修订仍在其扩展里。
    assert_eq!(snapshot.agent.revision, "legacy");
    assert_ne!(
        snapshot.agent.revision,
        ResolvedAgentDefinition::from_profile(&migration_child_profile())?
            .identity()
            .revision
    );
    // 角色块与未被转换的其他块都按完整对象比对，来源种类、label、path 与正文逐项保留。
    assert_eq!(
        snapshot.base,
        expected_block(
            crate::instruction::InstructionSourceKind::ModelBase,
            "model base",
            None,
            "base",
        )
    );
    assert_eq!(
        snapshot.developer,
        vec![expected_block(
            crate::instruction::InstructionSourceKind::AgentDefinition,
            "Reviewer",
            None,
            "保存的原始 Prompt",
        )]
    );
    assert_eq!(
        snapshot.user,
        vec![expected_block(
            crate::instruction::InstructionSourceKind::ProjectDoc,
            "AGENTS.md",
            Some("/legacy/AGENTS.md"),
            "保留的项目文档",
        )]
    );
    assert!(
        snapshot
            .developer
            .iter()
            .all(|block| block.source.kind
                != crate::instruction::InstructionSourceKind::ModeDefinition),
        "child 不获得 root Mode 指令来源"
    );
    assert_eq!(migrated.state.context, original.context);
    Ok(())
}

/// 无法归属的旧来源与冲突的 Agent 范围都失败闭锁：不清空快照，也不部分重写持久化数据。
#[tokio::test]
async fn conflicting_saved_instruction_identity_fails_without_rewriting_the_checkpoint()
-> Result<()> {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("history.sqlite");
    let store = HistoryStore::open(&path, "migration").await?;
    let original = instruction_state(legacy_instructions(
        legacy_block("modelBase", "model base", "base"),
        vec![
            legacy_block("executionProfile", "first", "第一段角色正文"),
            legacy_block("executionProfile", "second", "第二段角色正文"),
        ],
        Vec::new(),
    )?);
    persist(&store, original.clone(), true).await?;
    let checkpoint = store
        .prepare_model_access()
        .await?
        .context("legacy checkpoint")?;
    let root = VerifiedAgentIdentity::GenericRoot;
    let before = serde_json::to_vec(&checkpoint)?;
    assert!(
        store
            .prepare_execution_identity(|state| {
                crate::instruction::migrate_saved_representation(state, &root)
            })
            .await
            .is_err(),
        "两个混用角色来源无法判断归属"
    );
    assert_eq!(
        serde_json::to_vec(&store.checkpoint().await?.context("retained checkpoint")?)?,
        before
    );
    assert_eq!(checkpoint.state.context, original.context);

    // 旧格式必须有且仅有一个混用来源，且只能出现在 developer 区。
    for (label, payload) in [
        (
            "missing role source",
            legacy_instructions(
                legacy_block("modelBase", "model base", "base"),
                Vec::new(),
                Vec::new(),
            )?,
        ),
        (
            "role source in user context",
            legacy_instructions(
                legacy_block("modelBase", "model base", "base"),
                Vec::new(),
                vec![legacy_block(
                    "executionProfile",
                    "保留的模式名称",
                    "保存的原始 Prompt",
                )],
            )?,
        ),
        (
            "role source in base",
            legacy_instructions(
                legacy_block("executionProfile", "保留的模式名称", "保存的原始 Prompt"),
                Vec::new(),
                Vec::new(),
            )?,
        ),
    ] {
        let mut state = instruction_state(payload);
        let before = serde_json::to_vec(&state)?;
        assert!(
            crate::instruction::migrate_saved_representation(&mut state, &root).is_err(),
            "{label}"
        );
        assert_eq!(serde_json::to_vec(&state)?, before, "{label}");
    }
    Ok(())
}

fn agent_identity(
    id: &str,
    scope: AgentDefinitionScope,
    revision: &str,
    origin: AgentDefinitionOrigin,
) -> crate::agent::definition::AgentDefinitionIdentity {
    let usage_binding = match scope {
        AgentDefinitionScope::Root => {
            crate::agent::definition::AgentUsageBinding::LegacyUnspecifiedRoot { source_version: 2 }
        }
        AgentDefinitionScope::Child => crate::agent::definition::AgentUsageBinding::Child,
    };
    agent_identity_with_binding(id, scope, revision, origin, usage_binding)
}

fn agent_identity_with_binding(
    id: &str,
    scope: AgentDefinitionScope,
    revision: &str,
    origin: AgentDefinitionOrigin,
    usage_binding: crate::agent::definition::AgentUsageBinding,
) -> crate::agent::definition::AgentDefinitionIdentity {
    crate::agent::definition::AgentDefinitionIdentity {
        id: id.into(),
        scope,
        usage_binding,
        revision: revision.into(),
        origin,
    }
}

fn current_instruction_state(
    agent: crate::agent::definition::AgentDefinitionIdentity,
) -> Result<ThreadSnapshot> {
    Ok(instruction_state(snapshot_payload(&compliant_snapshot(
        agent,
    ))?))
}

fn instruction_block(
    kind: crate::instruction::InstructionSourceKind,
    label: &str,
    content: &str,
) -> crate::instruction::InstructionBlock {
    crate::instruction::InstructionBlock {
        source: crate::instruction::InstructionSource {
            kind,
            label: label.into(),
            path: None,
        },
        content: content.into(),
    }
}

fn base_block() -> crate::instruction::InstructionBlock {
    instruction_block(
        crate::instruction::InstructionSourceKind::ModelBase,
        "model base",
        "base",
    )
}

/// Current roots and children all carry one builtin/Profile Agent source; migrated Agent-less roots are the sole absence case.
fn compliant_role_blocks(
    agent: &crate::agent::definition::AgentDefinitionIdentity,
) -> Vec<crate::instruction::InstructionBlock> {
    use crate::instruction::InstructionSourceKind;
    match agent.scope {
        AgentDefinitionScope::Root => {
            let mut blocks = Vec::new();
            if agent.origin == AgentDefinitionOrigin::Builtin {
                blocks.push(instruction_block(
                    InstructionSourceKind::AgentDefinition,
                    "root agent",
                    "root Agent instructions",
                ));
            }
            blocks.push(instruction_block(
                InstructionSourceKind::ModeDefinition,
                "保留的模式名称",
                "保存的模式 Prompt",
            ));
            blocks
        }
        AgentDefinitionScope::Child => vec![instruction_block(
            InstructionSourceKind::AgentDefinition,
            "Reviewer",
            "保存的原始 Prompt",
        )],
    }
}

fn compliant_snapshot(
    agent: crate::agent::definition::AgentDefinitionIdentity,
) -> crate::instruction::InstructionSnapshot {
    let developer = compliant_role_blocks(&agent);
    let agent_shape = crate::instruction::AgentInstructionShape::from_agent_blocks(&developer)
        .expect("compliant role blocks have a unique Agent source");
    crate::instruction::InstructionSnapshot {
        agent,
        agent_shape,
        base: base_block(),
        developer,
        user: Vec::new(),
    }
}

fn snapshot_payload(snapshot: &crate::instruction::InstructionSnapshot) -> Result<OpaquePayload> {
    Ok(crate::instruction::encode_snapshot(snapshot)?)
}

fn previous_snapshot_payload(
    snapshot: &crate::instruction::InstructionSnapshot,
) -> Result<OpaquePayload> {
    let mut value = serde_json::to_value(snapshot)?;
    let object = value
        .as_object_mut()
        .context("serialized instruction snapshot is not an object")?;
    object
        .remove("agentShape")
        .context("current instruction snapshot omitted agentShape")?;
    object
        .get_mut("agent")
        .and_then(serde_json::Value::as_object_mut)
        .context("current instruction snapshot omitted its Agent identity")?
        .remove("usageBinding")
        .context("current instruction snapshot omitted its usage binding")?;
    Ok(OpaquePayload::new(
        crate::instruction::SNAPSHOT_FORMAT,
        2,
        serde_json::to_string(&value)?,
    )?)
}

/// 共享结构校验必须同时约束编码与解码，而不是只在某个调用点检查。
fn assert_structure_rejected(
    snapshot: crate::instruction::InstructionSnapshot,
    reason: &str,
) -> Result<()> {
    assert!(
        crate::instruction::encode_snapshot(&snapshot).is_err(),
        "encoder must reject {reason}"
    );
    let payload = OpaquePayload::new(
        "pl.studio.instructions",
        crate::instruction::SNAPSHOT_VERSION,
        serde_json::to_string(&snapshot)?,
    )?;
    assert!(
        crate::instruction::decode_snapshot(&payload).is_err(),
        "decoder must reject {reason}"
    );
    Ok(())
}

/// 当前快照按冻结使用绑定、scope 与来源/修订组合校验；不按 root ID 逐个分支。
#[test]
fn current_instruction_identity_is_validated_against_verified_facts() -> Result<()> {
    let generic = VerifiedAgentIdentity::GenericRoot;
    let bot = VerifiedAgentIdentity::BotRoot;
    let child = VerifiedAgentIdentity::child(&migration_child_profile())?;
    for (id, scope, revision, origin) in [
        (
            "root:main",
            AgentDefinitionScope::Root,
            "1",
            AgentDefinitionOrigin::Builtin,
        ),
        // 旧内置修订必须继续可恢复，不能要求等于当前定义版本。
        (
            "root:main",
            AgentDefinitionScope::Root,
            "0",
            AgentDefinitionOrigin::Builtin,
        ),
        (
            "root:legacy",
            AgentDefinitionScope::Root,
            "legacy",
            AgentDefinitionOrigin::Migrated,
        ),
    ] {
        let mut state = current_instruction_state(agent_identity(id, scope, revision, origin))?;
        let before = state.extensions["studio.instructions"].clone();
        crate::instruction::migrate_saved_representation(&mut state, &generic)?;
        assert_eq!(
            state.extensions["studio.instructions"], before,
            "已保存身份不重写"
        );
    }
    // 已核实 bot 渠道接受飞书内置身份（含旧内置版本）与飞书迁移身份。
    for saved in [
        agent_identity_with_binding(
            "root:feishu",
            AgentDefinitionScope::Root,
            "0",
            AgentDefinitionOrigin::Builtin,
            crate::agent::definition::AgentUsageBinding::RootEntry(
                crate::agent::definition::AgentRootEntry::Bot,
            ),
        ),
        agent_identity_with_binding(
            "root:feishu",
            AgentDefinitionScope::Root,
            "legacy",
            AgentDefinitionOrigin::Migrated,
            crate::agent::definition::AgentUsageBinding::RootEntry(
                crate::agent::definition::AgentRootEntry::Bot,
            ),
        ),
    ] {
        let mut state = current_instruction_state(saved)?;
        crate::instruction::migrate_saved_representation(&mut state, &bot)?;
    }
    let mut accepted = current_instruction_state(agent_identity(
        "reviewer",
        AgentDefinitionScope::Child,
        "7",
        AgentDefinitionOrigin::Builtin,
    ))?;
    crate::instruction::migrate_saved_representation(&mut accepted, &child)?;
    let mut accepted = current_instruction_state(agent_identity(
        "reviewer",
        AgentDefinitionScope::Child,
        "legacy",
        AgentDefinitionOrigin::Migrated,
    ))?;
    crate::instruction::migrate_saved_representation(&mut accepted, &child)?;

    for saved in [
        // 同 scope 但错 ID、错修订或非法来源。
        agent_identity(
            "other",
            AgentDefinitionScope::Child,
            "7",
            AgentDefinitionOrigin::Profile,
        ),
        agent_identity(
            "reviewer",
            AgentDefinitionScope::Child,
            "8",
            AgentDefinitionOrigin::Profile,
        ),
        agent_identity(
            "reviewer",
            AgentDefinitionScope::Child,
            "7",
            AgentDefinitionOrigin::Profile,
        ),
        agent_identity(
            "reviewer",
            AgentDefinitionScope::Child,
            "",
            AgentDefinitionOrigin::Profile,
        ),
        // root 身份不允许未绑定的 ID 或错误的来源修订组合。
        agent_identity_with_binding(
            "root:legacy",
            AgentDefinitionScope::Root,
            "1",
            AgentDefinitionOrigin::Builtin,
            crate::agent::definition::AgentUsageBinding::RootEntry(
                crate::agent::definition::AgentRootEntry::Bot,
            ),
        ),
        agent_identity(
            "root:main",
            AgentDefinitionScope::Root,
            "",
            AgentDefinitionOrigin::Builtin,
        ),
        agent_identity_with_binding(
            "not-a-root-id",
            AgentDefinitionScope::Root,
            "1",
            AgentDefinitionOrigin::Builtin,
            crate::agent::definition::AgentUsageBinding::RootEntry(
                crate::agent::definition::AgentRootEntry::Studio,
            ),
        ),
    ] {
        let mut state = current_instruction_state(saved)?;
        let before = serde_json::to_vec(&state)?;
        assert!(
            crate::instruction::migrate_saved_representation(&mut state, &generic).is_err(),
            "非法已保存身份必须失败"
        );
        assert_eq!(serde_json::to_vec(&state)?, before);
    }
    // 已核实 bot 渠道与内置普通根身份矛盾，必须失败而不是沿用。
    let mut contradicting = current_instruction_state(agent_identity_with_binding(
        "root:main",
        AgentDefinitionScope::Root,
        "1",
        AgentDefinitionOrigin::Builtin,
        crate::agent::definition::AgentUsageBinding::RootEntry(
            crate::agent::definition::AgentRootEntry::Studio,
        ),
    ))?;
    assert!(crate::instruction::migrate_saved_representation(&mut contradicting, &bot).is_err());
    let mut future_root = current_instruction_state(agent_identity_with_binding(
        "root:future-product-agent",
        AgentDefinitionScope::Root,
        "future-revision",
        AgentDefinitionOrigin::Builtin,
        crate::agent::definition::AgentUsageBinding::RootEntry(
            crate::agent::definition::AgentRootEntry::Studio,
        ),
    ))?;
    crate::instruction::migrate_saved_representation(&mut future_root, &generic)?;
    // child 快照不能作为根会话身份，反之亦然。
    let mut child_as_root = current_instruction_state(agent_identity(
        "reviewer",
        AgentDefinitionScope::Child,
        "legacy",
        AgentDefinitionOrigin::Migrated,
    ))?;
    assert!(
        crate::instruction::migrate_saved_representation(&mut child_as_root, &generic).is_err()
    );
    let mut root_as_child = current_instruction_state(agent_identity(
        "root:legacy",
        AgentDefinitionScope::Root,
        "legacy",
        AgentDefinitionOrigin::Migrated,
    ))?;
    assert!(crate::instruction::migrate_saved_representation(&mut root_as_child, &child).is_err());
    Ok(())
}

/// 结构违规在编码与解码共用的边界拒绝：重复、缺失、错区与空角色块都不当作默认值。
#[test]
fn instruction_snapshot_structure_is_validated_by_the_shared_codec() -> Result<()> {
    use crate::instruction::InstructionSourceKind as Kind;
    let main = agent_identity(
        "root:main",
        AgentDefinitionScope::Root,
        "1",
        AgentDefinitionOrigin::Builtin,
    );
    let feishu = agent_identity(
        "root:feishu",
        AgentDefinitionScope::Root,
        "1",
        AgentDefinitionOrigin::Builtin,
    );
    let child = agent_identity(
        "reviewer",
        AgentDefinitionScope::Child,
        "7",
        AgentDefinitionOrigin::Profile,
    );
    for agent in [main.clone(), feishu.clone(), child.clone()] {
        let snapshot = compliant_snapshot(agent);
        let payload = snapshot_payload(&snapshot)?;
        assert_eq!(crate::instruction::decode_snapshot(&payload)?, snapshot);
    }

    let mut duplicate_mode = compliant_snapshot(main.clone());
    duplicate_mode.developer.push(instruction_block(
        Kind::ModeDefinition,
        "second",
        "第二段 Mode 正文",
    ));
    assert_structure_rejected(duplicate_mode, "duplicate Mode source")?;

    let mut missing_mode = compliant_snapshot(main.clone());
    missing_mode
        .developer
        .retain(|block| block.source.kind != Kind::ModeDefinition);
    assert_structure_rejected(missing_mode, "missing Mode source")?;

    let mut unexpected_agent = compliant_snapshot(main.clone());
    unexpected_agent.developer.insert(
        0,
        instruction_block(Kind::AgentDefinition, "root agent", "额外角色正文"),
    );
    assert_structure_rejected(unexpected_agent, "duplicate root Agent source")?;

    let mut missing_feishu_agent = compliant_snapshot(feishu);
    missing_feishu_agent
        .developer
        .retain(|block| block.source.kind != Kind::AgentDefinition);
    assert_structure_rejected(missing_feishu_agent, "missing bot Agent source")?;

    let mut migrated_root_agent = compliant_snapshot(agent_identity(
        "root:legacy",
        AgentDefinitionScope::Root,
        "legacy",
        AgentDefinitionOrigin::Migrated,
    ));
    migrated_root_agent.developer.insert(
        0,
        instruction_block(Kind::AgentDefinition, "legacy", "旧角色正文"),
    );
    assert_structure_rejected(migrated_root_agent, "Agent source on a migrated root")?;

    let mut child_mode = compliant_snapshot(child.clone());
    child_mode.developer.push(instruction_block(
        Kind::ModeDefinition,
        "simple",
        "Mode 正文",
    ));
    assert_structure_rejected(child_mode, "Mode source on a child")?;

    let mut duplicate_agent = compliant_snapshot(child.clone());
    duplicate_agent.developer.push(instruction_block(
        Kind::AgentDefinition,
        "second",
        "第二段角色正文",
    ));
    assert_structure_rejected(duplicate_agent, "duplicate Agent source")?;

    let mut missing_agent = compliant_snapshot(child.clone());
    missing_agent.developer.clear();
    assert_structure_rejected(missing_agent, "missing Agent source")?;

    let mut empty_agent = compliant_snapshot(child);
    empty_agent.developer[0].content = "  ".into();
    assert_structure_rejected(empty_agent, "empty Agent body")?;

    let mut stale_agent_hash = compliant_snapshot(main.clone());
    stale_agent_hash.developer[0].content = "different non-empty Agent source".into();
    assert_structure_rejected(stale_agent_hash, "Agent content hash mismatch")?;

    let mut base_role = compliant_snapshot(main.clone());
    base_role.base = instruction_block(Kind::ModeDefinition, "simple", "Mode 正文");
    assert_structure_rejected(base_role, "role source in base")?;

    let mut user_role = compliant_snapshot(main);
    user_role.user.push(instruction_block(
        Kind::ModeDefinition,
        "simple",
        "Mode 正文",
    ));
    assert_structure_rejected(user_role, "role source in user context")?;
    Ok(())
}

/// bot 归属必须解码校验；没有正向证明时不推断普通渠道，而是明确渠道未指定的 legacy-root。
#[test]
fn bot_ownership_is_verified_by_decoding_not_by_extension_presence() -> Result<()> {
    use crate::studio::model_route::{BOT_OWNER_EXTENSION, encode_bot_owner, verified_bot_owner};

    let owned = |payload: OpaquePayload| {
        let mut state = ThreadSnapshot::default();
        state.extensions.insert(
            BOT_OWNER_EXTENSION.into(),
            ExtensionRecord {
                revision: 1,
                payload,
            },
        );
        state
    };
    let frozen = owned(encode_bot_owner("bot-1a2b3c4d-0")?);
    assert_eq!(
        verified_bot_owner(None, Some(&frozen))?,
        Some("bot-1a2b3c4d-0".to_owned())
    );
    assert_eq!(
        verified_bot_owner(Some("bot-1a2b3c4d-0"), Some(&frozen))?,
        Some("bot-1a2b3c4d-0".to_owned())
    );
    assert_eq!(
        verified_bot_owner(Some("bot-1a2b3c4d-1"), None)?,
        Some("bot-1a2b3c4d-1".to_owned())
    );
    assert_eq!(verified_bot_owner(None, None)?, None);
    assert!(
        verified_bot_owner(Some("bot-ffffffff-9"), Some(&frozen)).is_err(),
        "运行期绑定与冻结 owner 冲突"
    );
    for damaged in [
        OpaquePayload::new("pl.studio.bot-owner", 1, "\"\"")?,
        OpaquePayload::new("pl.studio.bot-owner", 1, "\"has space\"")?,
        OpaquePayload::new("pl.studio.bot-owner", 2, "\"bot-1a2b3c4d-0\"")?,
        OpaquePayload::new("pl.studio.bot-owner.other", 1, "\"bot-1a2b3c4d-0\"")?,
        OpaquePayload::new("pl.studio.bot-owner", 1, "not json")?,
    ] {
        assert!(
            verified_bot_owner(None, Some(&owned(damaged))).is_err(),
            "损坏 owner 不能被忽略"
        );
    }
    // canonical 校验器的最小长度 8 与字符集不能被同构副本放宽。
    for short in ["bot", "bot-123", "bot 1a2b3c"] {
        assert!(
            verified_bot_owner(None, Some(&owned(encode_bot_owner(short)?))).is_err(),
            "短或非法 bot owner `{short}` 必须失败"
        );
        assert!(
            verified_bot_owner(Some(short), None).is_err(),
            "短或非法运行期绑定 `{short}` 必须失败"
        );
    }
    assert_eq!(
        VerifiedAgentIdentity::GenericRoot.migrated_identity().id,
        "root:legacy"
    );
    assert_eq!(
        VerifiedAgentIdentity::BotRoot.migrated_identity().id,
        "root:feishu"
    );
    Ok(())
}

/// 已有 checkpoint 缺少指令事实时失败闭锁，不清空、不补默认正文，重开库仍保持原事实。
#[tokio::test]
async fn missing_instruction_snapshot_fails_without_rewriting_or_defaulting() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("history.sqlite");
    let store = HistoryStore::open(&path, "migration").await?;
    let original = saved_state(BTreeMap::new());
    persist(&store, original.clone(), true).await?;
    let checkpoint = store.prepare_model_access().await?.context("checkpoint")?;
    let before = serde_json::to_vec(&checkpoint)?;
    assert!(
        store
            .prepare_execution_identity(|state| {
                crate::instruction::migrate_saved_representation(
                    state,
                    &VerifiedAgentIdentity::GenericRoot,
                )
            })
            .await
            .is_err(),
        "缺必需指令身份不能通过"
    );
    assert_eq!(
        serde_json::to_vec(&store.checkpoint().await?.context("retained checkpoint")?)?,
        before
    );
    drop(store);
    let reopened = HistoryStore::open(&path, "migration").await?;
    let durable = reopened.checkpoint().await?.context("durable checkpoint")?;
    assert!(!durable.state.extensions.contains_key("studio.instructions"));
    assert_eq!(durable.state.context, original.context);
    Ok(())
}

/// 恢复 child 只消费冻结 Profile：缺失时明确失败，不读当前 catalog、不造空正文或修订。
#[tokio::test]
async fn missing_frozen_child_profile_fails_without_writing_anything() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("history.sqlite");
    let store = HistoryStore::open(&path, "migration").await?;
    let original = saved_state(BTreeMap::from([(
        "studio.workspace".into(),
        record(2, "pl.studio.workspace", 1, "\"receipt\"")?,
    )]));
    persist(&store, original.clone(), true).await?;
    let checkpoint = store.checkpoint().await?.context("child checkpoint")?;
    let before = serde_json::to_vec(&checkpoint)?;
    assert!(
        crate::studio::model_route::saved_profile(&checkpoint.state)?.is_none(),
        "该 checkpoint 没有冻结 Profile"
    );
    let error =
        crate::studio::model_route::required_saved_profile(&checkpoint.state, "child-missing")
            .expect_err("缺冻结 Profile 必须失败");
    assert!(
        error.to_string().contains("has no frozen Agent Profile"),
        "{error}"
    );
    assert_eq!(
        serde_json::to_vec(&store.checkpoint().await?.context("retained checkpoint")?)?,
        before
    );
    drop(store);
    let reopened = HistoryStore::open(&path, "migration").await?;
    let durable = reopened.checkpoint().await?.context("durable checkpoint")?;
    assert!(
        !durable
            .state
            .extensions
            .contains_key(crate::studio::model_route::AGENT_PROFILE_EXTENSION)
    );
    assert_eq!(durable.state.context, original.context);
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

#[tokio::test]
async fn standalone_project_kind_migration_preserves_legacy_checkpoint_and_reopens() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("history.sqlite");
    let history = HistoryStore::open(&path, "migration").await?;
    let original = saved_state(BTreeMap::from([
        (
            "studio.project".into(),
            record(
                4,
                "pl.studio.project",
                1,
                r#"{"id":"project-test","name":"保留","path":"/workspace","sshAlias":null,"updatedAt":19}"#,
            )?,
        ),
        (
            "studio.delegation".into(),
            record(
                5,
                "pl.studio.delegation",
                1,
                r#"{"mode":"profile","preference":"balanced"}"#,
            )?,
        ),
    ]));
    persist(&history, original, true).await?;
    let before = history.checkpoint().await?.context("legacy checkpoint")?;
    // Model an existing database whose earlier official steps have already completed.
    let raw = raw_database(&path).await?;
    raw.execute_unprepared(
        "DELETE FROM seaql_migrations WHERE version='m20261027_000004_history_project_kind'",
    )
    .await?;
    raw.close().await?;
    drop(history);
    let reopened = HistoryStore::open(&path, "migration").await?;
    let migrated = migrate_model_access(&reopened).await?;
    let project: crate::studio::WorkspaceRecord = serde_json::from_str(
        migrated.state.extensions["studio.project"]
            .payload
            .content(),
    )?;
    assert_eq!(project.kind, pl_protocol::studio::WorkspaceKind::Project);
    assert_eq!(project.path, "/workspace");
    assert_eq!(project.updated_at, 19);
    let mut expected = before;
    expected
        .state
        .extensions
        .get_mut("studio.project")
        .unwrap()
        .payload = migrated.state.extensions["studio.project"].payload.clone();
    assert_eq!(
        serde_json::to_value(&expected)?,
        serde_json::to_value(&migrated)?
    );
    assert_eq!(migrated.state.extensions["studio.project"].revision, 4);
    drop(reopened);
    let reopened = HistoryStore::open(&path, "migration").await?;
    assert_eq!(
        serde_json::to_value(migrate_model_access(&reopened).await?)?,
        serde_json::to_value(migrated)?
    );
    Ok(())
}

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

async fn migrate_model_access(store: &HistoryStore) -> Result<ThreadCheckpoint> {
    store
        .prepare_model_access()
        .await?
        .context("prepared model access")
}

#[tokio::test]
async fn workspace_receipt_upgrade_preserves_nested_ownership_and_rejects_corruption() -> Result<()>
{
    use sea_orm::{DbBackend, Statement};
    async fn applied_migrations(db: &impl ConnectionTrait) -> Result<Vec<String>> {
        db.query_all_raw(Statement::from_string(
            DbBackend::Sqlite,
            "SELECT json_array(version,applied_at) AS fact FROM seaql_migrations ORDER BY version",
        ))
        .await?
        .into_iter()
        .map(|row| Ok(row.try_get("", "fact")?))
        .collect()
    }

    for mode in ["directory", "worktree", "review"] {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let store = HistoryStore::open(&path, "migration").await?;
        let mut receipt = serde_json::json!({
            "mode": mode, "projectRoot": "/repo", "root": "/repo",
            "writablePaths": ["/repo/src"]
        });
        if mode != "directory" {
            receipt["root"] = "/repo/.anywork/worktrees/root/target".into();
            receipt["worktree"] = serde_json::json!({
                "repositoryRoot": "/repo", "path": "/repo/.anywork/worktrees/root/target",
                "branch": "pure-agent-target", "baseCommit": "base"
            });
        }
        if mode == "review" {
            receipt["reviewTarget"] = serde_json::json!({"agentId": "target"});
        }
        let mut extensions = BTreeMap::from([(
            "studio.workspace".into(),
            record(23, "pl.studio.workspace", 1, &receipt.to_string())?,
        )]);
        // Close facts and frozen Profiles are independent and must remain byte-for-byte unchanged.
        extensions.insert(
            crate::studio::agent_close::EXTENSION.into(),
            ExtensionRecord {
                revision: 24,
                payload: crate::studio::agent_close::encode()?,
            },
        );
        let mut state = saved_state(extensions);
        crate::studio::delegation::migrate(&mut state)?;
        persist(&store, state, true).await?;
        let original = store.checkpoint().await?.context("original")?;
        assert!(
            crate::studio::workspace_receipt::from_snapshot(&original.state).is_err(),
            "normal reads must not silently decode retired receipts"
        );
        let db = raw_database(&path).await?;
        let content_prepared = applied_migrations(&db).await?;
        let (read_only, _) = store
            .read_only_checkpoint_with_latest_turn()
            .await?
            .context("prepared content is readable before lifecycle recovery")?;
        assert_eq!(
            serde_json::to_value(read_only)?,
            serde_json::to_value(&original)?,
            "content reads retain the pending lifecycle representation and checkpoint facts"
        );
        assert_eq!(
            applied_migrations(&db).await?,
            content_prepared,
            "a content read cannot advance lifecycle preparation"
        );
        db.close().await?;
        let migrated = migrate_model_access(&store).await?;
        let saved = &migrated.state.extensions["studio.workspace"];
        assert_eq!(saved.revision, 23);
        assert_eq!(saved.payload.version(), 3);
        if let Some(worktree) = receipt.get_mut("worktree") {
            worktree
                .as_object_mut()
                .context("worktree object")?
                .remove("branch");
        }
        assert_eq!(
            serde_json::from_str::<serde_json::Value>(saved.payload.content())?,
            receipt
        );
        let mut expected = original.clone();
        expected
            .state
            .extensions
            .get_mut("studio.workspace")
            .context("receipt")?
            .payload = saved.payload.clone();
        assert_eq!(
            serde_json::to_value(&migrated)?,
            serde_json::to_value(expected)?,
            "history fence, close intent and all unrelated checkpoint facts survive"
        );
        // Emulate a released database which has already completed 008, before the new 007a
        // maintenance step existed. Only its workspace representation and that step are retired.
        store.prepare_execution_identity(|_| Ok(())).await?;
        let db = raw_database(&path).await?;
        let execution = db.query_one_raw(Statement::from_sql_and_values(DbBackend::Sqlite,
            "SELECT applied_at FROM seaql_migrations WHERE version='m20261026_000008_history_execution_identity'",
            vec![],
        )).await?.context("applied execution-identity migration")?.try_get::<i64>("", "applied_at")?;
        let mut legacy = original.clone();
        // SQLite stores context separately; preserve its normalized envelope instead of embedding
        // the materialized reader view back into the checkpoint row.
        legacy.state.context.records = Default::default();
        let legacy = serde_json::to_string(&legacy)?;
        db.execute_raw(Statement::from_sql_and_values(
            DbBackend::Sqlite,
            "UPDATE session_checkpoint SET payload=?,payload_hash=? WHERE id=1",
            vec![
                legacy.clone().into(),
                pl_core::context::content_hash(legacy.as_bytes()).into(),
            ],
        ))
        .await?;
        db.execute_unprepared("DELETE FROM seaql_migrations WHERE version='m20261026_000007a_history_workspace_receipt'").await?;
        let pending_workspace = applied_migrations(&db).await?;
        db.close().await?;
        drop(store);
        let reopened = HistoryStore::open(&path, "migration").await?;
        let (read_only, _) = reopened
            .read_only_checkpoint_with_latest_turn()
            .await?
            .context("pending workspace lifecycle does not invalidate prepared content")?;
        assert_eq!(
            serde_json::to_value(read_only)?,
            serde_json::to_value(&original)?
        );
        let db = raw_database(&path).await?;
        assert_eq!(
            applied_migrations(&db).await?,
            pending_workspace,
            "cold reads do not complete pending workspace recovery"
        );
        reopened.prepare_history_access().await?;
        assert_eq!(
            applied_migrations(&db).await?,
            pending_workspace,
            "Schema must not advance workspace lifecycle after ModelAccess was applied"
        );
        let (read_only, _) = reopened
            .read_only_checkpoint_with_latest_turn()
            .await?
            .context("content preparation retains the existing checkpoint")?;
        assert_eq!(
            serde_json::to_value(read_only)?,
            serde_json::to_value(&original)?,
            "Schema preparation must preserve the original receipt, state and history fence"
        );
        db.close().await?;
        assert_eq!(
            serde_json::to_value(migrate_model_access(&reopened).await?)?,
            serde_json::to_value(&migrated)?,
            "a missing 007a still runs after a previously completed 008"
        );
        let db = raw_database(&path).await?;
        assert_eq!(db.query_one_raw(Statement::from_sql_and_values(DbBackend::Sqlite,
            "SELECT applied_at FROM seaql_migrations WHERE version='m20261026_000008_history_execution_identity'", vec![]
        )).await?.context("retained execution migration")?.try_get::<i64>("", "applied_at")?, execution);
        db.close().await?;
        drop(reopened);
        let reopened = HistoryStore::open(&path, "migration").await?;
        assert_eq!(
            serde_json::to_value(migrate_model_access(&reopened).await?)?,
            serde_json::to_value(migrated)?,
            "reopening the upgraded database is idempotent"
        );
    }
    for (version, receipt) in [
        (
            1,
            serde_json::json!({"mode":"worktree","projectRoot":"/repo","root":"/tree",
            "worktree":{"repositoryRoot":"/repo","path":"/tree","branch":17,"baseCommit":"base"}}),
        ),
        (
            1,
            serde_json::json!({"mode":"directory","projectRoot":"/repo","root":"/repo","unknown":true}),
        ),
        (
            99,
            serde_json::json!({"mode":"directory","projectRoot":"/repo","root":"/repo"}),
        ),
    ] {
        let directory = tempfile::tempdir()?;
        let store =
            HistoryStore::open(&directory.path().join("history.sqlite"), "migration").await?;
        let mut state = saved_state(BTreeMap::from([(
            "studio.workspace".into(),
            record(23, "pl.studio.workspace", version, &receipt.to_string())?,
        )]));
        crate::studio::delegation::migrate(&mut state)?;
        persist(&store, state, true).await?;
        let original = store.checkpoint().await?.context("original")?;
        assert!(migrate_model_access(&store).await.is_err());
        assert_eq!(
            serde_json::to_value(store.checkpoint().await?.context("retained")?)?,
            serde_json::to_value(original)?
        );
    }
    Ok(())
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
    thread.workspace_id = "project-test".into();
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
            id: thread.workspace_id.clone(),
            kind: pl_protocol::studio::WorkspaceKind::Project,
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
    store.history_for(&thread.workspace_id, &thread.id).await
}

/// These fixtures seed only checkpoint/context data using the current writer. The published
/// pre-framework v5/v8 tables have the same shape, but no atomic-timeline output or SeaORM ledger.
/// Never discard a completion when restoring that older boundary.
async fn restore_pre_timeline_history_fixture(
    db: &sea_orm::DatabaseConnection,
    version: i64,
) -> Result<()> {
    use sea_orm::{DatabaseBackend, Statement};
    assert!(matches!(version, 5 | 8));
    let row = db
        .query_one_raw(Statement::from_string(
            DatabaseBackend::Sqlite,
            "SELECT COUNT(*) AS count FROM timeline_records",
        ))
        .await?
        .context("fixture timeline output")?;
    assert_eq!(
        row.try_get::<i64>("", "count")?,
        0,
        "legacy fixture must not discard completed history"
    );
    db.execute_unprepared("DROP TABLE timeline_records; DROP TABLE seaql_migrations")
        .await?;
    db.execute_raw(Statement::from_sql_and_values(
        DatabaseBackend::Sqlite,
        "UPDATE history_meta SET schema_version=? WHERE id=1",
        [version.into()],
    ))
    .await?;
    Ok(())
}

async fn downgrade_checkpoint_to_schema_five(path: &std::path::Path) -> Result<String> {
    use sea_orm::{DatabaseBackend, Statement};
    let db = raw_database(path).await?;
    let row = db
        .query_one_raw(Statement::from_string(
            DatabaseBackend::Sqlite,
            "SELECT payload FROM session_checkpoint WHERE id=1",
        ))
        .await?
        .context("saved checkpoint")?;
    let mut legacy: serde_json::Value =
        serde_json::from_str(&row.try_get::<String>("", "payload")?)?;
    super::history::legacy_usage::flatten(&mut legacy);
    legacy["schemaVersion"] = serde_json::json!(5);
    let encoded = serde_json::to_string(&legacy)?;
    db.execute_raw(Statement::from_sql_and_values(
        DatabaseBackend::Sqlite,
        "UPDATE session_checkpoint SET payload=?,payload_hash=? WHERE id=1",
        vec![
            encoded.clone().into(),
            pl_core::context::content_hash(encoded.as_bytes()).into(),
        ],
    ))
    .await?;
    restore_pre_timeline_history_fixture(&db, 8).await?;
    db.close().await?;
    Ok(encoded)
}

/// A table-current v2 database can still contain a retired checkpoint envelope. Opening it must
/// migrate atomically, preserve proven provenance, and leave ordinary cold reads strictly read-only.
#[tokio::test]
async fn checkpoint_envelope_upgrade_is_atomic_and_preserves_v2_history() -> Result<()> {
    use pl_core::{model::ModelUsageBinding, thread::ModelUsageOrigin};
    use sea_orm::{DatabaseBackend, Statement};

    let directory = tempfile::tempdir()?;
    let path = directory.path().join("history.sqlite");
    let history = HistoryStore::open(&path, "migration").await?;
    let mut state = saved_state(BTreeMap::from([(
        "vendor.unknown".into(),
        record(6, "vendor.unknown", 7, "opaque bytes must survive")?,
    )]));
    state.last_attempt_usage_origin = Some(ModelUsageOrigin {
        binding: ModelUsageBinding {
            route_identity: None,
            model: "saved-model".into(),
            context_window: Some(4096),
            max_context_window: Some(8192),
            auto_compact_limit: Some(3000),
        },
        input_revision: 1,
        context_revision: 1,
        input_record_count: 1,
        input_hash: Some("saved-input-hash".into()),
    });
    persist(&history, state, true).await?;
    let before = history.checkpoint().await?.context("saved checkpoint")?;
    drop(history);

    let encoded = downgrade_checkpoint_to_schema_five(&path).await?;
    let db = raw_database(&path).await?;
    db.execute_unprepared(
        "CREATE TRIGGER reject_envelope_upgrade BEFORE UPDATE ON session_checkpoint
        BEGIN SELECT RAISE(ABORT,'injected envelope migration failure'); END;",
    )
    .await?;
    db.close().await?;

    let cold = HistoryStore::open(&path, "migration").await?;
    assert!(
        cold.checkpoint().await.is_err(),
        "cold queries must not convert legacy state"
    );
    let failure = cold
        .prepare_activation()
        .await
        .expect_err("the explicit upgrade must reach the checkpoint transaction");
    assert!(format!("{failure:#}").contains("m20261026_000006_history_checkpoint_v5"));
    assert!(format!("{failure:#}").contains("injected envelope migration failure"));
    assert_eq!(
        crate::studio::startup::StudioStartupError::input("history", failure).kind,
        crate::studio::startup::StudioStartupErrorKind::Migration
    );
    drop(cold);
    let db = raw_database(&path).await?;
    let row = db.query_one_raw(Statement::from_string(DatabaseBackend::Sqlite,
        "SELECT schema_version,payload FROM history_meta,session_checkpoint WHERE history_meta.id=1 AND session_checkpoint.id=1"))
        .await?.context("preserved source")?;
    assert_eq!(row.try_get::<i64>("", "schema_version")?, 8);
    assert_eq!(row.try_get::<String>("", "payload")?, encoded);
    assert!(db.query_one_raw(Statement::from_string(DatabaseBackend::Sqlite,
        "SELECT version FROM seaql_migrations WHERE version='m20261026_000006_history_checkpoint_v5'"))
        .await?.is_none(), "failed conversion cannot publish its completion record");
    db.execute_unprepared("DROP TRIGGER reject_envelope_upgrade")
        .await?;
    db.close().await?;

    let reopened = HistoryStore::open(&path, "migration").await?;
    reopened.prepare_activation().await?;
    let after = reopened
        .checkpoint()
        .await?
        .context("upgraded checkpoint")?;
    let mut expected = before.clone();
    expected.state.usage_summary.diagnostics.legacy_unknown = true;
    assert_eq!(
        serde_json::to_value(&after)?,
        serde_json::to_value(&expected)?
    );
    let bytes = serde_json::to_vec(&after)?;
    reopened.prepare_activation().await?;
    assert_eq!(
        serde_json::to_vec(
            &reopened
                .checkpoint()
                .await?
                .context("idempotent checkpoint")?
        )?,
        bytes
    );
    drop(reopened);
    let cold = HistoryStore::open(&path, "migration").await?;
    assert_eq!(
        serde_json::to_value(
            cold.read_only_checkpoint_with_latest_turn()
                .await?
                .context("cold checkpoint after upgrade")?
                .0
        )?,
        serde_json::to_value(expected)?
    );
    Ok(())
}

#[tokio::test]
async fn cold_child_open_and_parent_recovery_prepare_checkpoint_envelopes() -> Result<()> {
    use crate::config::{ConfigPaths, ConfigStore, StudioConfig};
    use crate::studio::store::directory::DirectoryDelta;
    use crate::{StudioHostKind, StudioRuntimeOptions};
    use pl_model::{
        config::{AccountConfig, AccountId, ModelRouteConfig},
        model::ModelInfo,
        protocol::ProtocolEndpoint,
    };
    let directory = tempfile::tempdir()?;
    let home = directory.path().join("home");
    let workspace = directory.path().join("workspace");
    tokio::fs::create_dir(&workspace).await?;
    let account_id = AccountId::new("storage-fixture")?;
    let route = ModelRouteConfig {
        account_id: account_id.clone(),
        model_id: "storage-model".into(),
        effort: None,
    };
    let mut config = StudioConfig::default_config()?;
    config.models.accounts.clear();
    config.models.accounts.insert(
        account_id,
        AccountConfig::from_explicit_models(
            ProtocolEndpoint::compatible("Storage fixture", "http://127.0.0.1:0"),
            vec![ModelInfo::compatible(&route.model_id)],
        ),
    );
    for selected in config
        .models
        .routes
        .values_mut()
        .chain(config.mode_model_routes.values_mut())
    {
        *selected = route.clone();
    }
    ConfigStore::new(ConfigPaths::from_config_dir(&home)).save(&config)?;
    let options = || StudioRuntimeOptions {
        studio_home: Some(home.clone()),
        host: StudioHostKind::Test,
        ..StudioRuntimeOptions::desktop()
    };
    let runtime = crate::StudioRuntime::initialize(options()).await?;
    let project = runtime.open_project(&workspace).await?;
    let root = runtime.create_thread(&project.id, "Legacy root").await?;
    runtime.shutdown_runtime().await?;
    let store = crate::studio::StudioStore::open(&home.join("data/studio.sqlite")).await?;
    let mut children = Vec::new();
    for (id, role) in [
        ("retired-child", crate::config::ROOT_AGENT_ROUTE_KEY),
        ("cold-child", "executor"),
        ("timeline-child", "executor"),
        ("turn-page-child", "executor"),
    ] {
        let mut child = bound_thread(id);
        child.workspace_id = project.id.clone();
        child.parent_thread_id = Some(root.id.clone());
        child.root_thread_id = root.id.clone();
        child.role = role.into();
        store
            .persist_directory_summaries(&DirectoryDelta {
                thread_upserts: vec![child.clone()],
                ..Default::default()
            })
            .await?;
        let history = store.history_for(&project.id, id).await?;
        persist(&history, saved_state(BTreeMap::new()), true).await?;
        let path = store.session_paths(&project.id, id)?.history_database();
        drop(history);
        downgrade_checkpoint_to_schema_five(&path).await?;
        children.push((child, path));
    }
    let root_path = store
        .session_paths(&project.id, &root.id)?
        .history_database();
    downgrade_checkpoint_to_schema_five(&root_path).await?;
    drop(store);
    let runtime = crate::StudioRuntime::initialize(options()).await?;
    let result = async {
        // These children have no execution owner. Both independent content entrypoints must
        // prepare only SQLite content before querying, leaving model/instruction recovery pending.
        for (child, path) in children.iter().skip(2) {
            assert!(HistoryStore::open(path, &child.id).await?.checkpoint().await.is_err());
            if child.id == "timeline-child" {
                assert!(runtime.timeline_page(&child.id, &pl_protocol::TimelinePageQuery {
                    before: None, limit: Some(10),
                }).await?.items.is_empty());
            } else {
                assert!(runtime.list_thread_turns(&child.id, None, 10).await?.turns.is_empty());
            }
            let checkpoint = HistoryStore::open(path, &child.id).await?.checkpoint().await?.context("prepared content checkpoint")?;
            assert_eq!(checkpoint.state.context, saved_state(BTreeMap::new()).context);
            assert!(checkpoint.state.extensions.is_empty(), "content access must not regenerate instructions");
            let db = raw_database(path).await?;
            assert!(db.query_one_raw(sea_orm::Statement::from_string(sea_orm::DatabaseBackend::Sqlite,
                "SELECT version FROM seaql_migrations WHERE version IN ('m20261026_000007_history_model_access','m20261026_000008_history_execution_identity')"
            )).await?.is_none(), "content access must not advance execution recovery");
            db.close().await?;
        }
        // The retired child's first saved-state lookup decides whether an owner may be installed.
        // It must happen after migration even when that lookup proves the child is not sealed.
        let child = &children[0].0;
        let mut subscription = runtime
            .subscribe_thread(pl_protocol::ThreadSubscriptionRequest {
                thread_id: child.id.clone(),
            })
            .await?;
        anyhow::ensure!(
            subscription.recv().await?.is_some(),
            "missing retired child baseline"
        );
        drop(subscription);
        // The composer can ask for child interactions while the root subscription is opening.
        // That read must wait for storage preparation, without activating a child itself.
        let (subscription, interactions) = tokio::join!(
            runtime.subscribe_thread(pl_protocol::ThreadSubscriptionRequest {
                thread_id: root.id.clone(),
            }),
            runtime.read_child_interactions(&root.id),
        );
        let mut subscription = subscription?;
        interactions?;
        anyhow::ensure!(
            subscription.recv().await?.is_some(),
            "missing root baseline"
        );
        drop(subscription);
        for (child, path) in children {
            let saved = HistoryStore::open(&path, &child.id)
                .await?
                .checkpoint()
                .await?
                .context("current child checkpoint")?;
            anyhow::ensure!(
                saved.schema_version == ThreadCheckpoint::SCHEMA_VERSION,
                "child envelope was not upgraded"
            );
            anyhow::ensure!(
                runtime.thread_snapshot(&child.id).await?.thread.id == child.id,
                "child snapshot unavailable after opening"
            );
        }
        anyhow::Ok(())
    }
    .await;
    let shutdown = runtime.shutdown_runtime().await;
    result?;
    shutdown?;
    Ok(())
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
    let mut original = saved_state(BTreeMap::from([
        (
            "studio.model-route".into(),
            record(2, "pl.studio.model-route", 1, LEGACY_ROUTE)?,
        ),
        ("studio.plan".into(), plan.clone()),
    ]));
    crate::studio::delegation::migrate(&mut original)?;
    persist(&store, original.clone(), true).await?;
    let legacy = store.checkpoint().await?.context("legacy checkpoint")?;
    assert_eq!(
        legacy.state.extensions["studio.model-route"]
            .payload
            .version(),
        1
    );

    let migrated = migrate_model_access(&store).await?;
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
    let again = migrate_model_access(&reopened).await?;
    assert_eq!(serde_json::to_vec(&again)?, before_retry, "第二次没有变化");
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
    let database_path = directory.path().join("data/studio.sqlite");
    let store = crate::studio::StudioStore::open(&database_path).await?;
    let thread = bound_thread("migration");
    let history = registered_history(&store, &thread).await?;
    let mut original = saved_state(BTreeMap::from([
        (
            "studio.model-route".into(),
            record(2, "pl.studio.model-route", 1, LEGACY_ROUTE)?,
        ),
        (
            "studio.agent-profile".into(),
            record(3, "pl.studio.agent-profile", 1, LEGACY_PROFILE)?,
        ),
    ]));
    original.lifecycle = pl_core::thread::ThreadLifecycle::Closed;
    persist(&history, original.clone(), true).await?;

    let before = history
        .checkpoint()
        .await?
        .context("pre-migration checkpoint")?;
    let faults = raw_database(
        &store
            .session_paths(&thread.workspace_id, &thread.id)?
            .history_database(),
    )
    .await?;
    faults
        .execute_unprepared(
            "CREATE TRIGGER block_delegation_migration BEFORE UPDATE ON session_checkpoint
        BEGIN SELECT RAISE(ABORT,'injected delegation migration write fault'); END",
        )
        .await?;
    assert!(
        crate::studio::thread_factory::recovery::load_checkpoint_for_recovery(&store, &thread)
            .await
            .is_err()
    );
    let preserved = history
        .checkpoint()
        .await?
        .context("preserved checkpoint")?;
    assert_eq!(
        serde_json::to_vec(&preserved)?,
        serde_json::to_vec(&before)?,
        "failed extension migration preserves the full old checkpoint"
    );
    assert!(
        !preserved
            .state
            .extensions
            .contains_key(crate::studio::delegation::EXTENSION)
    );
    faults
        .execute_unprepared("DROP TRIGGER block_delegation_migration")
        .await?;
    drop(faults);

    let recovered =
        crate::studio::thread_factory::recovery::load_checkpoint_for_recovery(&store, &thread)
            .await?
            .context("recovered checkpoint")?;
    assert_eq!(recovered.state_revision, original.commit_sequence);
    assert_eq!(
        recovered.state.lifecycle,
        pl_core::thread::ThreadLifecycle::Closed
    );
    assert!(
        !crate::studio::agent_close::is_explicitly_closed(&recovered.state)?,
        "old owner closure must retain its original recoverable meaning"
    );
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
    assert_eq!(
        crate::studio::delegation::saved(&recovered.state)?,
        Some(pl_protocol::DelegationSettings::default())
    );
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
    let history = reopened
        .history_for(&thread.workspace_id, &thread.id)
        .await?;
    let saved = history.checkpoint().await?.context("reopened checkpoint")?;
    assert_eq!(
        crate::studio::delegation::saved(&saved.state)?,
        Some(pl_protocol::DelegationSettings::default())
    );
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
async fn unknown_close_intent_encoding_preserves_checkpoint_and_history() -> Result<()> {
    for (format, version, content) in [
        ("pl.studio.unrecognized-close", 1, "{}"),
        ("pl.studio.agent-close", 2, "{}"),
        ("pl.studio.agent-close", 1, r#"{"closed":false}"#),
    ] {
        let directory = tempfile::tempdir()?;
        let store =
            crate::studio::StudioStore::open(directory.path().join("data/studio.sqlite")).await?;
        let thread = bound_thread("migration");
        let history = registered_history(&store, &thread).await?;
        let state = saved_state(BTreeMap::from([(
            crate::studio::agent_close::EXTENSION.into(),
            record(8, format, version, content)?,
        )]));
        persist(&history, state, true).await?;
        let before = history.checkpoint().await?.context("original checkpoint")?;
        assert!(
            crate::studio::thread_factory::recovery::load_checkpoint_for_recovery(&store, &thread)
                .await
                .is_err()
        );
        let after = history.checkpoint().await?.context("retained checkpoint")?;
        assert_eq!(serde_json::to_vec(&after)?, serde_json::to_vec(&before)?);
        assert_eq!(history.watermark().await?, before.history_fence);
        store.close().await?;
    }
    Ok(())
}

#[tokio::test]
async fn legacy_child_profile_representation_is_committed_once_before_recovery() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("history.sqlite");
    let store = HistoryStore::open(&path, "migration").await?;
    let mut original = saved_state(BTreeMap::from([(
        "studio.agent-profile".into(),
        record(3, "pl.studio.agent-profile", 1, LEGACY_PROFILE)?,
    )]));
    crate::studio::delegation::migrate(&mut original)?;
    persist(&store, original, true).await?;
    let legacy = store.checkpoint().await?.context("legacy checkpoint")?;
    assert_eq!(
        legacy.state.extensions["studio.agent-profile"]
            .payload
            .version(),
        1
    );

    let migrated = migrate_model_access(&store).await?;
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
    assert_eq!(
        serde_json::from_str::<serde_json::Value>(saved.payload.content())?,
        serde_json::to_value(&profile)?,
    );
    expected
        .state
        .extensions
        .get_mut("studio.agent-profile")
        .context("saved profile")?
        .payload = saved.payload.clone();
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
    let again = migrate_model_access(&reopened).await?;
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
    let row = faults
        .query_one_raw(sea_orm::Statement::from_sql_and_values(
            sea_orm::DatabaseBackend::Sqlite,
            "SELECT payload FROM session_checkpoint WHERE id=1",
            vec![],
        ))
        .await?
        .context("source checkpoint")?;
    let mut encoded: serde_json::Value =
        serde_json::from_str(&row.try_get::<String>("", "payload")?)?;
    encoded["state"]["producerState"] = serde_json::json!(["keep", 9]);
    encoded["state"]["extensions"]["studio.model-route"]["producerRecord"] = true.into();
    encoded["state"]["extensions"]["studio.model-route"]["payload"]["producerCodec"] =
        "keep".into();
    let encoded = serde_json::to_string(&encoded)?;
    faults
        .execute_raw(sea_orm::Statement::from_sql_and_values(
            sea_orm::DatabaseBackend::Sqlite,
            "UPDATE session_checkpoint SET payload=?,payload_hash=? WHERE id=1",
            vec![
                encoded.clone().into(),
                pl_core::context::content_hash(encoded.as_bytes()).into(),
            ],
        ))
        .await?;
    faults
        .execute_unprepared(
            "CREATE TRIGGER block_checkpoint_update BEFORE UPDATE ON session_checkpoint \
             BEGIN SELECT RAISE(ABORT,'injected checkpoint write fault'); END",
        )
        .await?;
    assert!(migrate_model_access(&store).await.is_err());
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
    let migrated = migrate_model_access(&store).await?;
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
    let row = faults
        .query_one_raw(sea_orm::Statement::from_string(
            sea_orm::DatabaseBackend::Sqlite,
            "SELECT payload FROM session_checkpoint WHERE id=1",
        ))
        .await?
        .context("migrated raw checkpoint")?;
    let raw: serde_json::Value = serde_json::from_str(&row.try_get::<String>("", "payload")?)?;
    assert_eq!(
        raw["state"]["producerState"],
        serde_json::json!(["keep", 9])
    );
    assert_eq!(
        raw["state"]["extensions"]["studio.model-route"]["producerRecord"],
        true
    );
    assert_eq!(
        raw["state"]["extensions"]["studio.model-route"]["payload"]["producerCodec"],
        "keep"
    );
    assert!(faults.query_one_raw(sea_orm::Statement::from_string(sea_orm::DatabaseBackend::Sqlite, "SELECT version FROM seaql_migrations WHERE version='m20261026_000007_history_model_access'")).await?.is_some(), "successful retry commits the completion record");
    faults.close().await?;
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

/// Seed an earlier producer representation directly; current live effect writers reject it.
async fn persist_legacy_producer(
    store: &HistoryStore,
    path: &std::path::Path,
    state: ThreadSnapshot,
) -> Result<()> {
    let original = state.extensions.clone();
    let mut seed = state;
    for record in seed.extensions.values_mut() {
        if let Some(current) = crate::studio::producer_migration::normalize(&record.payload)? {
            record.payload = current;
        }
    }
    persist(store, seed, true).await?;
    let db = raw_database(path).await?;
    let row = db
        .query_one_raw(sea_orm::Statement::from_string(
            sea_orm::DatabaseBackend::Sqlite,
            "SELECT payload FROM session_checkpoint WHERE id=1",
        ))
        .await?
        .context("seed checkpoint")?;
    let mut raw: serde_json::Value = serde_json::from_str(&row.try_get::<String>("", "payload")?)?;
    raw["state"]["extensions"] = serde_json::to_value(original)?;
    let encoded = serde_json::to_string(&raw)?;
    db.execute_raw(sea_orm::Statement::from_sql_and_values(
        sea_orm::DatabaseBackend::Sqlite,
        "UPDATE session_checkpoint SET payload=?,payload_hash=? WHERE id=1",
        [
            encoded.clone().into(),
            pl_core::context::content_hash(encoded.as_bytes()).into(),
        ],
    ))
    .await?;
    db.close().await?;
    Ok(())
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
    let database_path = directory.path().join("data/studio.sqlite");
    let store = crate::studio::StudioStore::open(&database_path).await?;
    let thread = bound_thread("migration");
    let history = registered_history(&store, &thread).await?;
    let history_path = store
        .session_paths(&thread.workspace_id, &thread.id)?
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
    persist_legacy_producer(&history, &history_path, state.clone()).await?;
    let before = history.checkpoint().await?.context("legacy checkpoint")?;
    let db = raw_database(&history_path).await?;
    restore_pre_timeline_history_fixture(&db, 5).await?;
    db.close().await?;
    drop(history);
    drop(store);

    // 真实共同恢复入口：旧库结构升级必须能从 v1 原生回执恢复来源而不是先硬失败。
    let reopened = crate::studio::StudioStore::open(&database_path).await?;
    let upgraded = reopened
        .history_for(&thread.workspace_id, &thread.id)
        .await?;
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
    let receipt = &checkpoint.state.extensions[crate::compaction::LATEST_RECEIPT];
    assert_eq!(
        receipt.revision,
        before.state.extensions[crate::compaction::LATEST_RECEIPT].revision
    );
    assert_eq!(receipt.payload.version(), 4);
    let decoded = crate::compaction::decode_receipt(4, receipt.payload.content())?;
    assert_eq!(decoded.inference_id, "compact-call");
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
    assert_eq!(payload.version(), 4, "原生 checkpoint 升级到当前结构");
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
    persist_legacy_producer(&store, &path, state).await?;
    let db = raw_database(&path).await?;
    restore_pre_timeline_history_fixture(&db, 5).await?;
    db.close().await?;
    drop(store);

    let failed = HistoryStore::open(&path, "migration").await?;
    let failure = failed
        .prepare_activation()
        .await
        .expect_err("unusable source must fail inside context migration");
    assert!(format!("{failure:#}").contains("m20261026_000004_history_context_sources"));
    assert!(
        failed.prepare_activation().await.is_err(),
        "升级步骤没有被标记完成，仍可重试"
    );
    drop(failed);
    // 普通读取拒绝未准备格式；直接检查原始迁移输入证明失败没有部分提交。
    let retryable = HistoryStore::open(&path, "migration").await?;
    assert!(retryable.checkpoint().await.is_err());
    let inspect = raw_database(&path).await?;
    let row = inspect.query_one_raw(sea_orm::Statement::from_string(sea_orm::DatabaseBackend::Sqlite,
        "SELECT schema_version,revision FROM history_meta,session_checkpoint WHERE history_meta.id=1 AND session_checkpoint.id=1"
    )).await?.context("preserved checkpoint")?;
    assert_eq!(row.try_get::<i64>("", "schema_version")?, 5);
    assert_eq!(row.try_get::<i64>("", "revision")?, 1);
    let row = inspect
        .query_one_raw(sea_orm::Statement::from_string(
            sea_orm::DatabaseBackend::Sqlite,
            "SELECT payload FROM current_context WHERE record_id='compaction:compact-call'",
        ))
        .await?
        .context("preserved compaction record")?;
    let compaction: ContextRecord = serde_json::from_str(&row.try_get::<String>("", "payload")?)?;
    let [ContextContent::Opaque { payload }] = compaction.content.as_slice() else {
        anyhow::bail!("preserved compaction record is not opaque");
    };
    assert_eq!(payload.version(), 1, "失败不升级来源结构");
    assert_eq!(payload.content(), unusable, "原正文逐字保留");
    inspect.close().await?;

    // 单一解码边界本身拒绝未知旧适配值与未来版本。
    let unsafe_receipt = LEGACY_NATIVE_RECEIPT.replace("\"deepSeek\"", "\"mysteryVendor\"");
    assert!(crate::compaction::decode_receipt(1, &unsafe_receipt).is_err());
    assert!(crate::studio::producer_migration::compaction_receipt(1, &unsafe_receipt).is_err());
    assert!(crate::compaction::decode_receipt(3, LEGACY_NATIVE_RECEIPT).is_err());
    Ok(())
}

/// 共享 history 入口必须让 checkpoint 冷读等到 writer 完成 identity，而不是另开半初始化库。
#[tokio::test]
async fn shared_history_checkpoint_waits_for_identity_and_keeps_cold_reads_empty() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let database_path = directory.path().join("data/studio.sqlite");
    let store = crate::studio::StudioStore::open(&database_path).await?;
    let thread_id = "migration";
    let thread = bound_thread(thread_id);
    let history = registered_history(&store, &thread).await?;
    let history_path = store
        .session_paths(&thread.workspace_id, thread_id)?
        .history_database();

    let missing =
        crate::studio::thread_factory::recovery::load_checkpoint_read_only(&store, &thread).await?;
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
        .state_for(&thread.workspace_id, "other-thread")?
        .prepare_recovery(&history)
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
    let error =
        crate::studio::thread_factory::recovery::load_checkpoint_read_only(&damaged, &thread)
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
            crate::studio::thread_factory::recovery::load_checkpoint_read_only(
                &waiting,
                &waiting_thread,
            )
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

/// All Studio-owned database families reject unknown future formats and migration names before
/// a writer changes the SQLite file. This also covers takeover of supported pre-framework files.
#[tokio::test]
async fn studio_databases_adopt_current_files_and_refuse_future_writes() -> Result<()> {
    use crate::studio::{StudioStore, paths::StudioPaths, storage::calls::CallsStore};
    use sea_orm::{DatabaseBackend, Statement};
    for family in ["product", "history", "calls"] {
        for fault in ["format", "migration", "missing_table", "checkpoint"] {
            if fault == "checkpoint" && family != "history" {
                continue;
            }
            let directory = tempfile::tempdir()?;
            let paths = StudioPaths::resolve(Some(directory.path().to_path_buf()))?;
            let path = match family {
                "product" => paths.database(),
                "calls" => paths.calls_database(),
                _ => directory.path().join("history.sqlite"),
            };
            for generation in 0..2 {
                match family {
                    "product" => StudioStore::open(&path).await?.close().await?,
                    "calls" => CallsStore::prepare(&path).await?.close().await?,
                    _ => {
                        let history = HistoryStore::open(&path, "adoption").await?;
                        if generation == 0 {
                            history.commit(1, &[], &[]).await?;
                        } else {
                            history.prepare_activation().await?;
                        }
                    }
                }
                if generation == 0 {
                    let db = raw_database(&path).await?;
                    if family == "history" {
                        restore_pre_timeline_history_fixture(&db, 8).await?;
                    } else {
                        if family == "calls" {
                            // v9 requires its ledger; restore the actual published v8 shape.
                            db.execute_unprepared(
                                "ALTER TABLE legacy_call_fences RENAME TO call_watermarks;
                                 UPDATE calls_meta SET schema_version=8 WHERE id=1;",
                            )
                            .await?;
                        }
                        db.execute_unprepared("DROP TABLE seaql_migrations").await?;
                    }
                    db.close().await?;
                }
            }
            let db = raw_database(&path).await?;
            let completed = db
                .query_all_raw(Statement::from_string(
                    DatabaseBackend::Sqlite,
                    "SELECT version FROM seaql_migrations",
                ))
                .await?;
            assert!(!completed.is_empty(), "current {family} must be enrolled");
            if fault == "migration" {
                db.execute_unprepared(
                    "INSERT INTO seaql_migrations(version,applied_at) VALUES('m99999999_future',1)",
                )
                .await?;
            } else if fault == "missing_table" {
                db.execute_unprepared(match family {
                    "product" => "DROP TABLE seaql_migrations; DROP TABLE studio_objects",
                    "calls" => "DROP TABLE seaql_migrations; DROP TABLE call_usage_summary",
                    _ => "DROP TABLE history_items",
                })
                .await?;
            } else if fault == "checkpoint" {
                let mut checkpoint =
                    ThreadCheckpoint::capture("adoption".into(), 0, ThreadSnapshot::default());
                checkpoint.schema_version = ThreadCheckpoint::SCHEMA_VERSION + 1;
                let payload = serde_json::to_string(&checkpoint)?;
                db.execute_raw(Statement::from_sql_and_values(DatabaseBackend::Sqlite,
                    "INSERT INTO session_checkpoint(id,revision,context_revision,context_count,payload,payload_hash) VALUES(1,0,0,0,?,?)",
                    vec![payload.clone().into(), pl_core::context::content_hash(payload.as_bytes()).into()])).await?;
            } else {
                db.execute_unprepared(match family {
                    "product" => "PRAGMA user_version=999",
                    "calls" => "UPDATE calls_meta SET schema_version=999",
                    _ => "UPDATE history_meta SET schema_version=999",
                })
                .await?;
            }
            db.close().await?;
            let before = tokio::fs::read(&path).await?;
            let failure = match family {
                "product" => StudioStore::open(&path).await.map(|_| ()),
                "calls" => CallsStore::prepare(&path).await.map(|_| ()),
                _ => {
                    HistoryStore::open(&path, "adoption")
                        .await?
                        .prepare_activation()
                        .await
                }
            };
            assert!(failure.is_err(), "future {family} {fault} was accepted");
            assert_eq!(
                tokio::fs::read(&path).await?,
                before,
                "future {family} changed"
            );
        }
    }
    Ok(())
}
