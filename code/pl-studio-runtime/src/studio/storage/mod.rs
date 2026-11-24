pub(crate) mod calls;
pub(crate) mod coordinator;
mod current_file;
pub(crate) use current_file::{read_for_upgrade, verify_for_upgrade};
pub(crate) mod current_writer;
pub(crate) mod history;
pub(crate) mod state;
pub(crate) mod thread_writer;
pub(in crate::studio) mod tool_task;

#[cfg(test)]
mod mode_migration_tests {
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
        let mut definition = crate::studio::thread::auto::REGISTRATION.to_registration()?;
        definition.id = crate::mode::ThreadModeId::new("mode.migration")?;
        let source = ThreadModeSource::external(ThreadModeSourceId::new("migration-fixture")?);
        let registry = manager.replace_source(source, [definition])?;
        let mode = registry
            .mode(&crate::mode::ThreadModeId::new("mode.migration")?)
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
        let checkpoint = ThreadCheckpoint::capture(store.thread_id().into(), sequence, state)?;
        store
            .commit_checkpoint_effects(&[crate::studio::storage::history::CheckpointEffect {
                checkpoint: &checkpoint,
                effect: &effect,
                history: EffectCommit {
                    current: &crate::studio::storage::history::test_current(effect.sequence),
                    completions: &[],
                    turns: &[],
                    execution_order: 0,
                    rolled_back_turns: &empty,
                    identities: &[],
                    messages: &[],
                    receipts: &[],
                    tasks: &[],
                    deliveries: &[],
                    delivery_repairs: &[],
                    attempt: None,
                },
                accounting: crate::studio::storage::history::AccountingCommit {
                    facts: &crate::studio::thread_projection::PreparedAccounting::prepare(&effect)?,
                    material_changed: true,
                },
            }])
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
        let saved =
            crate::mode::decode_mode_snapshot(&recovered.extensions["studio.mode"].payload)?;
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
        let restored = crate::mode::saved_registered_mode(&checkpoint.state)?
            .context("saved full definition")?;
        assert_eq!(restored.prompt(), "保存的原始 Prompt");
        assert_eq!(restored.definition(), saved.definition);
        assert_eq!(checkpoint.state.extensions["studio.workflow"], workflow);
        assert_eq!(checkpoint.state.context, original.context);
        assert!(
            manager.snapshot().modes().next().is_none(),
            "restoration cannot re-register a deleted Mode"
        );
        drop(reopened);
        let current =
            upgrade_legacy_history_to_current(&path, "migration", directory.path()).await?;
        assert_eq!(current.state.extensions["studio.workflow"], workflow);
        assert_eq!(current.state.context, original.context);
        let restored = crate::mode::saved_registered_mode(&current.state.to_paused_snapshot())?
            .context("current saved Mode")?;
        assert_eq!(restored.prompt(), "保存的原始 Prompt");
        assert_eq!(restored.definition(), saved.definition);
        Ok(())
    }

    #[tokio::test]
    async fn unavailable_legacy_mode_definition_never_resets_or_rewrites_the_checkpoint()
    -> Result<()> {
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

    // ── 指令快照的 Agent/Mode 来源迁移 ──

    /// 旧版实际写出的 v1 指令块：`executionProfile` 同时承载 Mode 与 child Profile 的角色正文。
    fn legacy_block(kind: &str, label: &str, content: &str) -> serde_json::Value {
        serde_json::json!({
            "source": { "kind": kind, "label": label },
            "content": content,
        })
    }

    /// 旧版带 `path` 的指令块（项目文档、显式 base 覆盖等来源会携带路径）。
    fn legacy_block_with_path(
        kind: &str,
        label: &str,
        path: &str,
        content: &str,
    ) -> serde_json::Value {
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

    fn migration_child_profile() -> crate::AgentProfileSnapshot {
        crate::AgentProfileSnapshot {
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
            workspace_mode: crate::AgentWorkspaceMode::Unrestricted,
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
    async fn legacy_root_instruction_source_becomes_the_mode_source_and_survives_a_reopen()
    -> Result<()> {
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
            snapshot.developer.iter().all(|block| block.source.kind
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
        let bot_snapshot = crate::instruction::decode_snapshot(
            &bot_proven.extensions["studio.instructions"].payload,
        )?;
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
    async fn v2_root_identity_contract_round_trips_without_reselecting_current_entry() -> Result<()>
    {
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
                crate::agent::definition::AgentUsageBinding::LegacyUnspecifiedRoot {
                    source_version: 2,
                }
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
            snapshot.developer.iter().all(|block| block.source.kind
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
                crate::agent::definition::AgentUsageBinding::LegacyUnspecifiedRoot {
                    source_version: 2,
                }
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

    // ── 模型接入扩展表示迁移与压缩来源恢复 ──

    const LEGACY_ROUTE: &str =
        r#"{"provider":"deepseek","model":"deepseek-flash","effort":"high"}"#;
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
    async fn standalone_project_kind_migration_preserves_legacy_checkpoint_and_reopens()
    -> Result<()> {
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
        assert_eq!(project.kind, crate::WorkspaceKind::Project);
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
    async fn workspace_receipt_upgrade_preserves_nested_ownership_and_rejects_corruption()
    -> Result<()> {
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
                .legacy_test_checkpoint_with_latest_turn()
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
                .legacy_test_checkpoint_with_latest_turn()
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
                .legacy_test_checkpoint_with_latest_turn()
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

    fn bound_thread(thread_id: &str) -> crate::Thread {
        let mut thread = crate::Thread::placeholder(thread_id);
        thread.workspace_id = "project-test".into();
        thread.agent_path = thread_id.to_owned();
        thread.root_thread_id = thread_id.to_owned();
        thread
    }

    async fn register_test_thread(
        store: &crate::studio::StudioStore,
        thread: &crate::Thread,
    ) -> Result<()> {
        let mut delta = crate::studio::store::directory::DirectoryDelta::upsert_project(
            crate::studio::store::directory::ProjectDirectoryRecord {
                id: thread.workspace_id.clone(),
                kind: crate::WorkspaceKind::Project,
                name: "Test".into(),
                path: "/tmp/project-test".into(),
                ssh_alias: None,
                created_at: 1,
                updated_at: 1,
                last_opened_at: None,
                closed: false,
            },
        );
        let (session, agent) = crate::studio::records::directory_facts_from_thread(thread);
        if let Some(session) = session {
            delta.session_upserts = vec![session];
        }
        delta.agent_upserts = vec![agent];
        store.persist_directory_summaries(&delta).await
    }

    async fn registered_history(
        store: &crate::studio::StudioStore,
        thread: &crate::Thread,
    ) -> Result<HistoryStore> {
        register_test_thread(store, thread).await?;
        let path = store
            .session_paths(&thread.workspace_id, &thread.id)?
            .history_database();
        HistoryStore::open(&path, &thread.id).await
    }

    async fn upgrade_legacy_history_to_current(
        path: &std::path::Path,
        thread_id: &str,
        session_dir: &std::path::Path,
    ) -> Result<pl_core::thread::current::ThreadCurrent> {
        crate::history::upgrade_history(path, thread_id, session_dir).await?;
        crate::studio::storage::state::StateStore::new(session_dir.to_owned(), thread_id)
            .load_current()
            .await?
            .context("upgraded current")
    }

    /// These fixtures seed only checkpoint/context data using the current writer. The published
    /// pre-framework v5/v8 tables have no route-head columns, atomic-timeline output or SeaORM ledger.
    /// Never discard a completion when restoring that older boundary.
    async fn restore_pre_timeline_history_fixture(
        db: &sea_orm::DatabaseConnection,
        version: i64,
    ) -> Result<()> {
        use sea_orm::{DatabaseBackend, Statement};
        assert!(matches!(version, 5 | 8));
        super::history::discard_empty_demand_fixture(db).await?;
        db.execute_unprepared(
            "DROP TABLE IF EXISTS timeline_records;
         DROP TABLE seaql_migrations",
        )
        .await?;
        db.execute_raw(Statement::from_sql_and_values(
            DatabaseBackend::Sqlite,
            "UPDATE history_meta SET schema_version=? WHERE id=1",
            [version.into()],
        ))
        .await?;
        Ok(())
    }

    /// Recreate the published schema12 boundary without asking the current writer to accept v1.
    /// Only the ordinary checkpoint/context facts are seeded through that writer; the frozen old
    /// extension payloads are installed after removing later projection outputs and completion records.
    async fn persist_schema12_fixture(
        path: &std::path::Path,
        thread_id: &str,
        original: ThreadSnapshot,
    ) -> Result<ThreadCheckpoint> {
        use sea_orm::{DatabaseBackend, Statement, TransactionTrait};
        let seed = HistoryStore::open(path, thread_id).await?;
        let mut state = original.clone();
        state.extensions.remove("studio.model-route");
        state.extensions.remove("studio.agent-profile");
        persist(&seed, state, true).await?;
        let mut checkpoint = seed.checkpoint().await?.context("seed checkpoint")?;
        checkpoint.state.extensions = original.extensions;
        let mut metadata = checkpoint.pruned()?;
        metadata.state.context.records = Default::default();
        let payload = serde_json::to_string(&metadata)?;
        drop(seed);

        let db = raw_database(path).await?;
        let tx = db.begin().await?;
        super::history::restore_empty_pre_completion_fixture(&tx).await?;
        let facts = tx
            .query_one_raw(Statement::from_string(
                DatabaseBackend::Sqlite,
                "SELECT (SELECT COUNT(*) FROM conversation_atom_facts)
                  + (SELECT COUNT(*) FROM conversation_sources) AS count",
            ))
            .await?
            .context("fixture canonical metadata output")?;
        assert_eq!(
            facts.try_get::<i64>("", "count")?,
            0,
            "schema12 fixture must not discard canonical lifecycle facts"
        );
        tx.execute_unprepared(
            "DROP TABLE IF EXISTS timeline_item_members;
         DROP TABLE IF EXISTS timeline_items;
         DROP TABLE IF EXISTS timeline_projection_state;
         DROP TABLE conversation_atom_facts;
         DROP TABLE conversation_sources;
         ALTER TABLE conversation_items DROP COLUMN metadata;
         ALTER TABLE history_meta DROP COLUMN model_route_json;
         ALTER TABLE history_meta DROP COLUMN model_route_hash;
         DELETE FROM seaql_migrations
             WHERE version IN ('m20261101_000010_history_model_route_head',
                               'm20261102_000001_history_atom_metadata',
                               'm20261104_000001_history_background_results',
                               'm20261107_000001_history_member_read_metadata',
                               'm20261103_000001_history_timeline_items',
                               'm20261108_000001_history_timeline_thinking_summary',
                               'm20261108_000001_history_source_classification',
                               'm20261109_000001_history_timeline_background_tail',
                               'm20261109_000001_history_completion_boundary');
         UPDATE history_meta SET schema_version=12 WHERE id=1",
        )
        .await?;
        tx.execute_raw(Statement::from_sql_and_values(
            DatabaseBackend::Sqlite,
            "UPDATE session_checkpoint SET payload=?,payload_hash=? WHERE id=1",
            vec![
                payload.clone().into(),
                pl_core::context::content_hash(payload.as_bytes()).into(),
            ],
        ))
        .await?;
        tx.commit().await?;
        let boundary = db
            .query_one_raw(Statement::from_string(
                DatabaseBackend::Sqlite,
                "SELECT schema_version,
                (SELECT COUNT(*) FROM pragma_table_info('history_meta')
                 WHERE name IN ('model_route_json','model_route_hash')) AS head_columns,
                (SELECT COUNT(*) FROM seaql_migrations
                 WHERE version='m20261101_000010_history_model_route_head') AS head_completed,
                (SELECT COUNT(*) FROM pragma_table_info('conversation_items')
                 WHERE name='metadata') AS metadata_columns,
                (SELECT COUNT(*) FROM sqlite_schema
                 WHERE name='conversation_sources') AS source_tables,
                (SELECT COUNT(*) FROM seaql_migrations
                 WHERE version='m20261102_000001_history_atom_metadata') AS metadata_completed,
                (SELECT COUNT(*) FROM sqlite_schema
                 WHERE type='table' AND name IN ('timeline_items','timeline_item_members',
                       'timeline_projection_state','conversation_atom_facts')) AS timeline_tables,
                (SELECT COUNT(*) FROM seaql_migrations
                 WHERE version='m20261103_000001_history_timeline_items') AS timeline_completed,
                (SELECT COUNT(*) FROM seaql_migrations
                 WHERE version IN ('m20261108_000001_history_timeline_thinking_summary',
                                   'm20261108_000001_history_source_classification',
                                   'm20261104_000001_history_background_results',
                                   'm20261107_000001_history_member_read_metadata',
                                   'm20261109_000001_history_timeline_background_tail',
                                   'm20261109_000001_history_completion_boundary',
                                   'm20261110_000001_history_immutable_completion_runs'))
                    AS later_projection_completed
             FROM history_meta WHERE id=1",
            ))
            .await?
            .context("schema12 fixture boundary")?;
        assert_eq!(boundary.try_get::<i64>("", "schema_version")?, 12);
        assert_eq!(boundary.try_get::<i64>("", "head_columns")?, 0);
        assert_eq!(boundary.try_get::<i64>("", "head_completed")?, 0);
        assert_eq!(boundary.try_get::<i64>("", "metadata_columns")?, 0);
        assert_eq!(boundary.try_get::<i64>("", "source_tables")?, 0);
        assert_eq!(boundary.try_get::<i64>("", "metadata_completed")?, 0);
        assert_eq!(boundary.try_get::<i64>("", "timeline_tables")?, 0);
        assert_eq!(boundary.try_get::<i64>("", "timeline_completed")?, 0);
        assert_eq!(
            boundary.try_get::<i64>("", "later_projection_completed")?,
            0
        );
        assert_eq!(saved_checkpoint_payload(&db).await?, payload);
        db.close().await?;
        Ok(checkpoint)
    }

    async fn saved_checkpoint_payload(db: &sea_orm::DatabaseConnection) -> Result<String> {
        db.query_one_raw(sea_orm::Statement::from_string(
            sea_orm::DatabaseBackend::Sqlite,
            "SELECT payload FROM session_checkpoint WHERE id=1",
        ))
        .await?
        .context("saved checkpoint")?
        .try_get("", "payload")
        .map_err(Into::into)
    }

    /// Old-schema failure assertions inspect physical facts, not a cached current-schema reader.
    async fn schema12_fixture_facts(db: &sea_orm::DatabaseConnection) -> Result<Vec<String>> {
        let mut facts = Vec::new();
        for sql in [
            "SELECT json_array(type,name,tbl_name,rootpage,sql) AS fact FROM sqlite_schema ORDER BY type,name",
            "SELECT json_array(id,schema_version,database_id,thread_id,applied_write_seq) AS fact FROM history_meta ORDER BY id",
            "SELECT json_array(version,applied_at) AS fact FROM seaql_migrations ORDER BY version",
            "SELECT json_array(id,revision,context_revision,context_count,payload,payload_hash) AS fact FROM session_checkpoint ORDER BY id",
            "SELECT json_array(ordinal,record_id,payload,payload_hash) AS fact FROM current_context ORDER BY ordinal",
            "SELECT json_array(append_seq,record_id,typeof(payload),hex(payload)) AS fact FROM timeline_records ORDER BY append_seq",
            "SELECT json_array(seq,item_id,typeof(payload),hex(payload)) AS fact FROM conversation_items ORDER BY seq",
        ] {
            for row in db
                .query_all_raw(sea_orm::Statement::from_string(
                    sea_orm::DatabaseBackend::Sqlite,
                    sql,
                ))
                .await?
            {
                facts.push(row.try_get("", "fact")?);
            }
        }
        Ok(facts)
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
        let failure_chain: Vec<_> = failure.chain().map(|cause| format!("{cause:?}")).collect();
        assert_eq!(
            crate::studio::startup::StudioStartupError::input("history", failure).kind,
            crate::studio::startup::StudioStartupErrorKind::Migration,
            "original migration failure chain: {failure_chain:#?}"
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
                cold.legacy_test_checkpoint_with_latest_turn()
                    .await?
                    .context("cold checkpoint after upgrade")?
                    .0
            )?,
            serde_json::to_value(&expected)?
        );
        drop(cold);
        let current =
            upgrade_legacy_history_to_current(&path, "migration", directory.path()).await?;
        assert!(current.state.usage_summary.diagnostics.legacy_unknown);
        assert_eq!(
            current.state.extensions["vendor.unknown"].payload.content(),
            "opaque bytes must survive"
        );
        assert_eq!(
            current.state.last_attempt_usage_origin,
            expected.state.last_attempt_usage_origin
        );
        Ok(())
    }

    #[tokio::test]
    async fn legacy_root_route_representation_is_committed_once_before_recovery() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
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
        let legacy = persist_schema12_fixture(&path, "migration", original.clone()).await?;
        let store = HistoryStore::open(&path, "migration").await?;
        assert_eq!(
            legacy.state.extensions["studio.model-route"]
                .payload
                .version(),
            1
        );

        store.prepare_history_access().await?;
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
        assert_eq!(route.model.account_id.as_str(), "deepseek");
        assert_eq!(route.model.model_id, "deepseek-flash");
        assert_eq!(
            route.model.effort.as_ref().map(|value| value.as_str()),
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
        drop(reopened);
        let current =
            upgrade_legacy_history_to_current(&path, "migration", directory.path()).await?;
        assert_eq!(
            current.state.extensions["studio.model-route"]
                .payload
                .version(),
            2
        );
        assert_eq!(current.state.extensions["studio.plan"], plan);
        let route = crate::studio::model_route::saved(&current.state.to_paused_snapshot())?
            .context("current route")?
            .route;
        assert_eq!(route.model.account_id.as_str(), "deepseek");
        assert_eq!(route.model.model_id, "deepseek-flash");
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
                crate::studio::StudioStore::open(directory.path().join("data/studio.sqlite"))
                    .await?;
            let thread = bound_thread("migration");
            let history = registered_history(&store, &thread).await?;
            let state = saved_state(BTreeMap::from([(
                crate::studio::agent_close::EXTENSION.into(),
                record(8, format, version, content)?,
            )]));
            persist(&history, state, true).await?;
            let before = history.checkpoint().await?.context("original checkpoint")?;
            assert!(history.prepare_model_access().await.is_err());
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
        let mut original = saved_state(BTreeMap::from([(
            "studio.agent-profile".into(),
            record(3, "pl.studio.agent-profile", 1, LEGACY_PROFILE)?,
        )]));
        crate::studio::delegation::migrate(&mut original)?;
        let legacy = persist_schema12_fixture(&path, "migration", original).await?;
        let store = HistoryStore::open(&path, "migration").await?;
        assert_eq!(
            legacy.state.extensions["studio.agent-profile"]
                .payload
                .version(),
            1
        );

        store.prepare_history_access().await?;
        let migrated = migrate_model_access(&store).await?;
        let saved = &migrated.state.extensions["studio.agent-profile"];
        assert_eq!(saved.revision, 3);
        assert_eq!(saved.payload.version(), 2);
        let (profile, revision) = crate::studio::model_route::saved_profile(&migrated.state)?
            .context("migrated profile")?;
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
        drop(reopened);
        let current =
            upgrade_legacy_history_to_current(&path, "migration", directory.path()).await?;
        let (current_profile, current_revision) =
            crate::studio::model_route::saved_profile(&current.state.to_paused_snapshot())?
                .context("current migrated profile")?;
        assert_eq!(current_revision, 3);
        assert_eq!(current_profile, profile);
        Ok(())
    }

    #[tokio::test]
    async fn failed_representation_write_preserves_the_saved_version_and_retries() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let original = saved_state(BTreeMap::from([(
            "studio.model-route".into(),
            record(2, "pl.studio.model-route", 1, LEGACY_ROUTE)?,
        )]));
        let legacy = persist_schema12_fixture(&path, "migration", original).await?;
        let store = HistoryStore::open(&path, "migration").await?;
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
        let before_facts = schema12_fixture_facts(&faults).await?;
        let failure = store
            .prepare_history_access()
            .await
            .expect_err("the injected checkpoint fault must block RootHead preparation");
        assert!(format!("{failure:#}").contains("injected checkpoint write fault"));
        assert_eq!(schema12_fixture_facts(&faults).await?, before_facts);
        assert!(
            store.checkpoint().await.is_err(),
            "failed RootHead preparation leaves the old schema unreadable to current cold readers"
        );
        let preserved: ThreadCheckpoint =
            serde_json::from_str(&saved_checkpoint_payload(&faults).await?)?;
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
        store.prepare_history_access().await?;
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
        drop(store);
        let current =
            upgrade_legacy_history_to_current(&path, "migration", directory.path()).await?;
        assert_eq!(
            current.state.extensions["studio.model-route"]
                .payload
                .version(),
            2
        );
        Ok(())
    }

    fn legacy_native_context(inference_id: &str, sealed: &str) -> Result<ContextRecord> {
        let item = crate::ModelContextItem::Compaction {
            encrypted_content: sealed.into(),
        };
        Ok(ContextRecord {
            id: format!("compaction:{inference_id}"),
            turn_id: None,
            source: ContextSource::Runtime {
                source_id: "model.compaction".into(),
            },
            content: vec![ContextContent::Opaque {
                payload: OpaquePayload::new(
                    "pl.model.compaction",
                    1,
                    serde_json::to_string(&item)?,
                )?,
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
        let mut raw: serde_json::Value =
            serde_json::from_str(&row.try_get::<String>("", "payload")?)?;
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
        // Producer normalization precedes schema 24. The 24 -> 25 boundary must preserve
        // these producer bytes, rather than repeat the old codec migration in normal reads.
        let mut normalized =
            ThreadCheckpoint::capture(thread.id.clone(), state.commit_sequence, state)?;
        crate::studio::producer_migration::checkpoint(&mut normalized)?;
        let state = normalized.state;
        persist_legacy_producer(&history, &history_path, state.clone()).await?;
        let before = history.checkpoint().await?.context("legacy checkpoint")?;
        drop(history);
        drop(store);

        // 真实共同恢复入口：旧库结构升级必须能从 v1 原生回执恢复来源而不是先硬失败。
        let reopened = crate::studio::StudioStore::open(&database_path).await?;
        let upgraded = reopened
            .history_for(&thread.workspace_id, &thread.id)
            .await?;
        let current =
            crate::studio::thread_factory::recovery::load_current_for_recovery(&reopened, &thread)
                .await?
                .context("upgraded current")?;
        assert_eq!(current.snapshot_revision, 0, "Current has its own revision");
        assert_eq!(
            current.state.context.revision,
            before.state.context.revision
        );
        let receipt = &current.state.extensions[crate::compaction::LATEST_RECEIPT];
        assert_eq!(
            receipt.revision,
            before.state.extensions[crate::compaction::LATEST_RECEIPT].revision
        );
        assert_eq!(receipt.payload.version(), 4);
        let decoded = crate::compaction::decode_receipt(4, receipt.payload.content())?;
        assert_eq!(decoded.inference_id, "compact-call");
        assert!(upgraded.reader().head().await? > 0);
        assert_eq!(current.state.context, before.state.context);

        let compaction = current
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
            current
                .state
                .context
                .records
                .iter()
                .find(|record| record.id == "unrelated-opaque")
                .context("unrelated record")?,
            &opaque_record("unrelated-opaque", "不可改写的用户/厂商正文")?,
            "无关 opaque 正文保持原字节"
        );

        let unchanged = serde_json::to_vec(&current.state)?;
        let again =
            crate::studio::thread_factory::recovery::load_current_for_recovery(&reopened, &thread)
                .await?
                .context("stable current")?;
        assert_eq!(
            serde_json::to_vec(&again.state)?,
            unchanged,
            "再次读取 current 没有变化"
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
        let compaction: ContextRecord =
            serde_json::from_str(&row.try_get::<String>("", "payload")?)?;
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

    /// All Studio-owned database families reject unknown future formats and migration names before
    /// a writer changes the SQLite file. This also covers takeover of supported pre-framework files.
    #[tokio::test]
    async fn studio_databases_adopt_current_files_and_refuse_future_writes() -> Result<()> {
        use crate::studio::{StudioStore, paths::StudioPaths, storage::calls::CallsStore};
        use sea_orm::{DatabaseBackend, Statement};
        // Schema 26 has no session_checkpoint, so the old future-checkpoint fault is not copied.
        for family in ["product", "history", "calls"] {
            for fault in ["format", "migration", "missing_table"] {
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
                            crate::history::HistoryStore::open(
                                &path,
                                "adoption",
                                crate::history::HistoryLimits::default(),
                            )
                            .await?
                            .close()
                            .await?;
                        }
                    }
                    if generation == 0 && family != "history" {
                        let db = raw_database(&path).await?;
                        if family == "calls" {
                            // Restore the published v8 shape, before fence retirement and request tiers.
                            db.execute_unprepared(
                                "ALTER TABLE performance_samples DROP COLUMN requested_service_tier;
                                 ALTER TABLE legacy_call_fences RENAME TO call_watermarks;
                                 UPDATE calls_meta SET schema_version=8 WHERE id=1;",
                            )
                            .await?;
                        }
                        db.execute_unprepared("DROP TABLE seaql_migrations").await?;
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
                        _ => "DROP TABLE history_events",
                    })
                    .await?;
                } else {
                    db.execute_unprepared(match family {
                        "product" => "PRAGMA user_version=999",
                        "calls" => "UPDATE calls_meta SET schema_version=999",
                        _ => "UPDATE history_store_meta SET schema_version=999",
                    })
                    .await?;
                }
                db.close().await?;
                let before = tokio::fs::read(&path).await?;
                let failure = match family {
                    "product" => StudioStore::open(&path).await.map(|_| ()),
                    "calls" => CallsStore::prepare(&path).await.map(|_| ()),
                    _ => crate::history::HistoryStore::open(
                        &path,
                        "adoption",
                        crate::history::HistoryLimits::default(),
                    )
                    .await
                    .map(|_| ()),
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
}
