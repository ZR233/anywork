//! Saved representation migration (Mode, model access, compaction sources) through the actual
//! SQLite checkpoint, history writer and history schema-upgrade paths.
use std::collections::{BTreeMap, BTreeSet};

use super::history::test_support::{
    assert_current, assert_pending, import_origin, import_source, seed_legacy_installation,
    source_checkpoint, source_evidence,
};
use super::history::{EffectCommit, HistoryInitialization, HistoryStore, MigrationFault};
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

/// Source/target ownership for representation fixtures. The source is generated through the real
/// current writer, then explicitly describes a pre-official v2 input. No source is renamed to a
/// target and no completion rows are forged. The tested import always uses the real Migrator.
struct HistoryFixture {
    source: HistoryStore,
    target: HistoryStore,
    path: std::path::PathBuf,
    imported: std::sync::atomic::AtomicBool,
    attempted: std::sync::atomic::AtomicBool,
    frozen: std::sync::atomic::AtomicBool,
}

#[derive(Debug, Clone)]
struct FixtureIdentityFailure(std::sync::Arc<anyhow::Error>);

impl std::fmt::Display for FixtureIdentityFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "trusted fixture identity conversion failed: {}", self.0)
    }
}

impl std::error::Error for FixtureIdentityFailure {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        Some(self.0.as_ref().as_ref())
    }
}

impl std::ops::Deref for HistoryFixture {
    type Target = HistoryStore;
    fn deref(&self) -> &Self::Target {
        if self.imported.load(std::sync::atomic::Ordering::Acquire) {
            &self.target
        } else {
            &self.source
        }
    }
}

async fn existing_history(path: &std::path::Path, thread_id: &str) -> Result<HistoryFixture> {
    let target_path = path.with_file_name("history-current.sqlite");
    let source = HistoryStore::open(path, thread_id).await?;
    let target = HistoryStore::open(&target_path, thread_id).await?;
    let imported = tokio::fs::try_exists(&target_path).await?;
    if imported {
        target.prepare_activation().await?;
    } else {
        source.initialize(HistoryInitialization::New).await?;
    }
    Ok(HistoryFixture {
        source,
        target,
        path: path.into(),
        imported: imported.into(),
        attempted: false.into(),
        frozen: false.into(),
    })
}

async fn import_bound_source(path: &std::path::Path, thread_id: &str) -> Result<HistoryStore> {
    let history =
        HistoryStore::open(&path.with_file_name("history-current.sqlite"), thread_id).await?;
    history
        .initialize(HistoryInitialization::ImportV2 {
            source_database: path.into(),
            legacy_state: super::state::StateStore::new(
                path.parent().context("source parent")?.into(),
                thread_id,
            ),
            migrate_execution_identity: std::sync::Arc::new(|_| Ok(())),
        })
        .await?;
    Ok(history)
}

impl HistoryFixture {
    async fn freeze_source(&self) -> Result<()> {
        if !self.frozen.swap(true, std::sync::atomic::Ordering::AcqRel) {
            let db = raw_database(&self.path).await?;
            db.execute_unprepared(
                "DELETE FROM seaql_migrations; UPDATE history_meta SET schema_version=8",
            )
            .await?;
            db.close().await?;
        }
        Ok(())
    }

    async fn import_identity(
        &self,
        migrate: impl FnOnce(&mut ThreadSnapshot) -> Result<()>,
    ) -> Result<ThreadCheckpoint> {
        if self.imported.load(std::sync::atomic::Ordering::Acquire) {
            return self
                .target
                .checkpoint()
                .await?
                .context("completed target checkpoint");
        }
        self.freeze_source().await?;
        let source = source_evidence(&self.path).await?;
        let result = if !self
            .attempted
            .swap(true, std::sync::atomic::Ordering::AcqRel)
        {
            let checkpoint = self.source.checkpoint().await;
            // Precompute only the trusted pure callback's result. Even a conversion error is
            // returned by the real target migration, not before its transaction begins. Retrying
            // the owner reuses exactly these frozen input facts and the original error chain.
            let converted = (|| -> Result<(ThreadSnapshot, ThreadSnapshot)> {
                let mut candidate = checkpoint?.context("source checkpoint")?.state;
                crate::studio::agent_close::is_explicitly_closed(&candidate)?;
                crate::studio::model_route::migration::upgrade(&mut candidate)?;
                crate::studio::delegation::migrate(&mut candidate)?;
                let expected = candidate.clone();
                migrate(&mut candidate)?;
                Ok((expected, candidate))
            })()
            .map_err(|error| FixtureIdentityFailure(std::sync::Arc::new(error)));
            let thread_id = self.source.thread_id().to_owned();
            self.target
                .initialize(HistoryInitialization::ImportV2 {
                    source_database: self.path.clone(),
                    legacy_state: super::state::StateStore::new(
                        self.path.parent().context("source parent")?.into(),
                        &thread_id,
                    ),
                    migrate_execution_identity: std::sync::Arc::new(move |state| {
                        let (expected, candidate) = converted.as_ref().map_err(Clone::clone)?;
                        anyhow::ensure!(
                            serde_json::to_value(&*state)? == serde_json::to_value(&expected)?,
                            "identity callback input changed"
                        );
                        *state = candidate.clone();
                        Ok(())
                    }),
                })
                .await
        } else {
            self.target.retry_initialization().await
        };
        assert_eq!(
            source_evidence(&self.path).await?,
            source,
            "representation import must not modify any original source fact or byte"
        );
        if result.is_err() {
            assert_pending(&self.path.with_file_name("history-current.sqlite")).await?;
        }
        result?;
        self.imported
            .store(true, std::sync::atomic::Ordering::Release);
        self.target
            .checkpoint()
            .await?
            .context("imported checkpoint")
    }
}

async fn persist(store: &HistoryStore, state: ThreadSnapshot, append: bool) -> Result<()> {
    store.initialize(HistoryInitialization::New).await?;
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

/// One isolated Studio host for restored-Thread scenarios.
///
/// The production factory assembles a restored root Thread and publishes its tool binding, so the
/// context-preparation hook resolves that Thread's live preparation owner exactly as the host
/// does. Nothing here substitutes a test-only owner: the services are the component types the
/// lifecycle builder wires, every byte of state lives under one temporary Studio home, and the
/// only model endpoint is a loopback address that is already closed.
struct MigrationHost {
    _temp: tempfile::TempDir,
    workspace: std::path::PathBuf,
    store: crate::studio::StudioStore,
    factory: crate::studio::StudioThreadFactory,
    assembler: crate::thread_assembler::StudioThreadAssembler,
    config_runtime: crate::config::ConfigRuntime,
    thread_modes: ThreadModeManager,
    route: pl_model::config::ModelRouteConfig,
}

impl MigrationHost {
    async fn open() -> Result<Self> {
        use crate::config::{ConfigPaths, ConfigStore, StudioConfig};
        use crate::studio::paths::StudioPaths;
        use pl_model::config::{AccountConfig, AccountId, ModelRouteConfig};
        use pl_model::model::ModelInfo;
        use pl_model::protocol::ProtocolEndpoint;

        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let workspace = temp.path().join("workspace");
        tokio::fs::create_dir_all(&workspace).await?;
        // The one durable route points at a loopback address that is already closed: preparation
        // must still run through the real hook, while the step's model call fails without any
        // external service or credential.
        let listener = std::net::TcpListener::bind("127.0.0.1:0")?;
        let endpoint = format!("http://{}", listener.local_addr()?);
        drop(listener);
        let mut model = ModelInfo::compatible("migration-model");
        model.base_instructions = "frozen migration base".into();
        let account_id = AccountId::new("migration-fixture")?;
        let route = ModelRouteConfig {
            account_id: account_id.clone(),
            model_id: model.model_id.clone(),
            effort: None,
        };
        let mut config = StudioConfig::default_config()?;
        config.models.accounts.clear();
        config.models.accounts.insert(
            account_id,
            AccountConfig::from_explicit_models(
                ProtocolEndpoint::compatible("Migration fixture", endpoint),
                vec![model],
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
        let paths = StudioPaths::resolve(Some(home.clone()))?;
        let config_paths = ConfigPaths::from_config_dir(&home);
        ConfigStore::new(config_paths.clone()).save(&config)?;
        let config_runtime =
            crate::config::ConfigRuntime::initialize(ConfigStore::new(config_paths))?;
        let thread_modes = config_runtime.thread_mode_manager();
        let store = crate::studio::StudioStore::open(paths.database()).await?;
        let writer = crate::studio::agent_host::ThreadWriteBehindWriter::new(store.clone());
        let product_events = crate::studio::ProductEventBus::new(store.clone(), writer.clone());
        let skills_dir = paths.system_skills_dir();
        tokio::fs::create_dir_all(&skills_dir).await?;
        let helper_source = crate::worker_assets::RemoteHelperSource::External;
        let bots = crate::bots::BotRuntime::new(
            paths.clone(),
            config_runtime.clone(),
            product_events.clone(),
        )?;
        let services = crate::studio::thread_factory::StudioThreadServices {
            store: store.clone(),
            worktrees: crate::studio::agent_host::worktree_lease::WorktreeLeaseOwner::new(writer),
            product_events: product_events.clone(),
            config_runtime: config_runtime.clone(),
            mcp_runtime: pl_tool::mcp::McpRuntime::new(pl_tool::mcp::McpConnector::default())
                .handle(),
            lsp_runtime: pl_lsp::runtime::LspRuntimeRegistry::new(),
            skills: crate::studio::runtime::SkillCatalogRuntime::new(product_events, skills_dir),
            thread_modes: thread_modes.clone(),
            ssh_manager: std::sync::Arc::new(crate::worker_assets::ssh_manager(&helper_source)),
            helper_source,
            bots,
        };
        Ok(Self {
            _temp: temp,
            workspace,
            store,
            factory: crate::studio::StudioThreadFactory::new(services),
            assembler: crate::thread_assembler::StudioThreadAssembler::default(),
            config_runtime,
            thread_modes,
            route,
        })
    }

    /// The exact route root preparation resolves for the restored Thread.
    fn resolved_route(&self) -> Result<pl_model::config::ResolvedModelRoute> {
        let config = self.config_runtime.read()?.config;
        let route = config
            .models
            .resolve_route(crate::config::root_agent_route_id(), &self.route)?;
        crate::studio::delegation::validate_credential(&route)?;
        Ok(route)
    }

    fn simple_mode(&self) -> Result<std::sync::Arc<crate::mode::RegisteredThreadMode>> {
        self.thread_modes
            .snapshot()
            .mode(&pl_protocol::ThreadModeId::simple())
            .context("built-in simple Mode")
    }

    fn legacy_simple_state(
        &self,
        mut extensions: BTreeMap<String, ExtensionRecord>,
    ) -> Result<ThreadSnapshot> {
        let mode = self.simple_mode()?;
        extensions.insert(
            "studio.mode".into(),
            record(
                4,
                "pl.studio.mode",
                1,
                &serde_json::to_string(&mode.descriptor().id)?,
            )?,
        );
        extensions.insert(
            "studio.instructions".into(),
            ExtensionRecord {
                revision: 5,
                payload: legacy_instructions(
                    legacy_block("modelBase", "base", "base"),
                    vec![legacy_block("executionProfile", "Simple", mode.prompt())],
                    Vec::new(),
                )?,
            },
        );
        Ok(saved_state(extensions))
    }

    /// Registers one restored Thread and commits its saved checkpoint through the product store.
    async fn persist_restored(
        &self,
        project_id: &str,
        thread_id: &str,
        state: ThreadSnapshot,
    ) -> Result<HistoryStore> {
        use crate::studio::store::directory::{DirectoryDelta, ProjectDirectoryRecord};
        let workspace = self.workspace.to_string_lossy().into_owned();
        let mut delta = DirectoryDelta::upsert_project(ProjectDirectoryRecord {
            id: project_id.into(),
            name: "Migration".into(),
            path: workspace.clone(),
            ssh_alias: None,
            created_at: 1,
            updated_at: 1,
            last_opened_at: None,
            closed: false,
        });
        let (registered, _) = DirectoryDelta::register_root_thread(
            thread_id.into(),
            project_id,
            thread_id,
            pl_protocol::ThreadModeId::simple(),
            pl_protocol::ThreadWorkspaceMode::Local,
            workspace,
        );
        delta.thread_upserts = registered.thread_upserts;
        self.store.persist_directory_summaries(&delta).await?;
        let paths = self.store.session_paths(project_id, thread_id)?;
        let history = HistoryStore::open(&paths.legacy_history_database(), thread_id).await?;
        persist(&history, state, true).await?;
        let db = raw_database(&paths.legacy_history_database()).await?;
        db.execute_unprepared(
            "DELETE FROM seaql_migrations; UPDATE history_meta SET schema_version=8",
        )
        .await?;
        db.close().await?;
        Ok(history)
    }

    /// Product root preparation publishes this Thread's tool binding; assembly then publishes the
    /// owner with the production context-preparation hook and the current-state checkpoint.
    async fn prepare_restored_root(
        &self,
        thread_id: &str,
        delegation: pl_protocol::DelegationSettings,
    ) -> Result<pl_core::thread::ThreadHandle> {
        self.factory.prepare_history_catalog().await?;
        let mut spec = self
            .factory
            .prepare_root_thread(crate::thread_assembler::ThreadPreparation {
                identity: crate::thread_assembler::ThreadActivation {
                    id: thread_id.to_owned(),
                    parent_id: None,
                },
                cancellation: tokio_util::sync::CancellationToken::new(),
                agent_controls: Vec::new(),
                delegation: Some(delegation),
            })
            .await?;
        // The durable writer has its own history fault-injection suite; this case protects the
        // preparation hook, so the owner is assembled without attaching a second storage
        // incarnation and its queue.
        spec.cold_store = None;
        Ok(self.assembler.assemble(spec).await?)
    }

    /// Real product close: the assembled owner settles its storage, then the factory seals the
    /// tool bindings it published for this Thread.
    async fn close(self, thread_id: &str) -> Result<()> {
        let closed = self.assembler.close(thread_id).await;
        self.factory.stop_all_tool_operations();
        closed?;
        Ok(())
    }
}

#[tokio::test]
async fn mode_definition_migration_preserves_history_and_restores_after_source_deletion()
-> Result<()> {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("history.sqlite");
    let manager = ThreadModeManager::default();
    let original = legacy_state(&manager)?;
    let workflow = original.extensions["studio.workflow"].clone();
    let store = existing_history(&path, "migration").await?;
    persist(&store, original.clone(), true).await?;
    let legacy = store.checkpoint().await?.context("legacy checkpoint")?;
    store.freeze_source().await?;
    let source = source_evidence(&path).await?;
    store
        .target
        .set_migration_fault(Some(MigrationFault::IdentityUpdate));
    let failure = store
        .import_identity(|state| {
            crate::mode::migrate_mode_snapshot(state, &manager)?;
            Ok(())
        })
        .await
        .expect_err("Mode conversion must reach the target checkpoint write");
    assert!(format!("{failure:#}").contains("injected target history migration write failure"));
    assert_pending(&path.with_file_name("history-current.sqlite")).await?;
    assert_eq!(
        serde_json::to_value(store.checkpoint().await?.context("preserved Mode")?)?,
        serde_json::to_value(&legacy)?
    );
    assert_eq!(source_evidence(&path).await?, source);
    store.target.set_migration_fault(None);
    let migrated = store
        .import_identity(|state| {
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
            .import_identity(|state| {
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
    assert_current(&path.with_file_name("history-current.sqlite"), "migration").await?;
    assert_eq!(source_evidence(&path).await?, source);
    drop(store);
    manager.remove_source(&ThreadModeSourceId::new("migration-fixture")?);
    assert!(manager.snapshot().modes().next().is_none());
    let reopened = existing_history(&path, "migration").await?;
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
    let store = existing_history(&path, "migration").await?;
    persist(&store, original.clone(), true).await?;
    manager.remove_source(&ThreadModeSourceId::new("migration-fixture")?);
    let checkpoint = store.checkpoint().await?.context("checkpoint")?;
    let before = serde_json::to_vec(&checkpoint)?;
    assert!(
        store
            .import_identity(|state| {
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
    let store = existing_history(&path, "migration").await?;
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
        .import_identity(|state| crate::instruction::migrate_saved_representation(state, &root))
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
    let reopened = existing_history(&path, "migration").await?;
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
    let store = existing_history(&path, "migration").await?;
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
    let checkpoint = store.checkpoint().await?.context("v2 root checkpoint")?;
    let prior_user_records = previous
        .context_records("migration")
        .into_iter()
        .filter(|record| matches!(record.source, ContextSource::RuntimeFact { .. }))
        .collect::<Vec<_>>();
    assert_eq!(prior_user_records.len(), 1);

    let migrated = store
        .import_identity(|state| {
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
    let reopened = existing_history(&path, "migration").await?;
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
        let store = existing_history(&path, "migration").await?;
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
            .import_identity(|state| {
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
        let reopened = existing_history(&path, "migration").await?;
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
        let store = existing_history(&path, "migration").await?;
        let original = instruction_state(previous_snapshot_payload(&previous)?);
        persist(&store, original.clone(), true).await?;
        let checkpoint = store.checkpoint().await?.context("v2 checkpoint")?;
        let before = serde_json::to_vec(&checkpoint)?;
        let verified = if is_bot {
            VerifiedAgentIdentity::BotRoot
        } else {
            VerifiedAgentIdentity::GenericRoot
        };
        assert!(
            store
                .import_identity(|state| {
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
        let reopened =
            HistoryStore::open(&path.with_file_name("history-current.sqlite"), "migration").await?;
        assert!(
            reopened.checkpoint().await.is_err(),
            "a cold current reader cannot fall back to the refused source"
        );
        let durable = source_checkpoint(&path, "migration")
            .await?
            .context("reopened immutable v2 source checkpoint")?;
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
    use pl_core::thread::StepInput;
    use pl_model::runtime::{ModelRuntime, ThreadModel};
    use std::sync::Arc;

    let thread_id = "migration";
    let project_id = "project-migration";
    let host = MigrationHost::open().await?;
    let mode = host.simple_mode()?;
    // The fixture must describe the same frozen route the host resolves for this Thread, so the
    // saved instruction base and the published binding describe real facts rather than copies.
    let route = host.resolved_route()?;
    let base_instructions = route.model.base_instructions.clone();
    let model = ThreadModel::new(ModelRuntime::from_route(&route)?, route.reasoning_config());
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
            &base_instructions,
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
    let mode_payload = crate::mode::encode_mode_snapshot(&crate::mode::SavedThreadMode::capture(
        mode.as_ref(),
        None,
    ))?;
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
    // Dispatch provenance belongs to the frozen root: saved delegation is required evidence for
    // root recovery and is orthogonal to the instruction migration this case protects.
    let delegation = pl_protocol::DelegationSettings::default();
    let delegation_payload = crate::studio::delegation::encode(delegation)?;
    let original = ThreadSnapshot {
        commit_sequence: 1,
        extension_sequence: 4,
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
            (
                crate::studio::delegation::EXTENSION.into(),
                ExtensionRecord {
                    revision: 4,
                    payload: delegation_payload,
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

    host.persist_restored(project_id, thread_id, original)
        .await?;
    // Opening saved history keeps the multi-record context exactly as it was saved. Only the
    // Thread's first real preparation may normalize it, through the hook that product assembly
    // installed from the same factory that published this Thread's tool binding.
    let thread = host.prepare_restored_root(thread_id, delegation).await?;

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
    host.close(thread_id).await?;
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
    let store = existing_history(&path, "migration").await?;
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
        .import_identity(|state| crate::instruction::migrate_saved_representation(state, &child))
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
    let store = existing_history(&path, "migration").await?;
    let original = instruction_state(legacy_instructions(
        legacy_block("modelBase", "model base", "base"),
        vec![
            legacy_block("executionProfile", "first", "第一段角色正文"),
            legacy_block("executionProfile", "second", "第二段角色正文"),
        ],
        Vec::new(),
    )?);
    persist(&store, original.clone(), true).await?;
    let checkpoint = store.checkpoint().await?.context("legacy checkpoint")?;
    let root = VerifiedAgentIdentity::GenericRoot;
    let before = serde_json::to_vec(&checkpoint)?;
    assert!(
        store
            .import_identity(|state| {
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
    let store = existing_history(&path, "migration").await?;
    let original = saved_state(BTreeMap::new());
    persist(&store, original.clone(), true).await?;
    let checkpoint = store.checkpoint().await?.context("checkpoint")?;
    let before = serde_json::to_vec(&checkpoint)?;
    assert!(
        store
            .import_identity(|state| {
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
    let reopened =
        HistoryStore::open(&path.with_file_name("history-current.sqlite"), "migration").await?;
    assert!(
        reopened.checkpoint().await.is_err(),
        "missing target must not read a legacy checkpoint"
    );
    let durable = source_checkpoint(&path, "migration")
        .await?
        .context("durable immutable source checkpoint")?;
    assert!(!durable.state.extensions.contains_key("studio.instructions"));
    assert_eq!(durable.state.context, original.context);
    Ok(())
}

/// 恢复 child 只消费冻结 Profile：缺失时明确失败，不读当前 catalog、不造空正文或修订。
#[tokio::test]
async fn missing_frozen_child_profile_fails_without_writing_anything() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("history.sqlite");
    let store = existing_history(&path, "migration").await?;
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
    let error = store
        .import_identity(|state| {
            let profile =
                crate::studio::model_route::required_saved_profile(state, "child-missing")?;
            let identity = VerifiedAgentIdentity::child(&profile)?;
            crate::instruction::migrate_saved_representation(state, &identity)
        })
        .await
        .expect_err("缺冻结 Profile 必须使真实目标导入失败");
    assert!(
        format!("{error:#}").contains("has no frozen Agent Profile"),
        "{error:#}"
    );
    assert_eq!(
        serde_json::to_vec(&store.checkpoint().await?.context("retained checkpoint")?)?,
        before
    );
    drop(store);
    let reopened =
        HistoryStore::open(&path.with_file_name("history-current.sqlite"), "migration").await?;
    assert!(
        reopened.checkpoint().await.is_err(),
        "a missing current target cannot default the frozen Profile"
    );
    let durable = source_checkpoint(&path, "migration")
        .await?
        .context("durable immutable source checkpoint")?;
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

fn record(revision: u64, format: &str, version: u32, content: &str) -> Result<ExtensionRecord> {
    Ok(ExtensionRecord {
        revision,
        payload: OpaquePayload::new(format, version, content.to_owned())?,
    })
}

fn saved_state(extensions: BTreeMap<String, ExtensionRecord>) -> ThreadSnapshot {
    ThreadSnapshot {
        commit_sequence: 1,
        extension_sequence: extensions
            .values()
            .map(|record| record.revision)
            .max()
            .unwrap_or(0)
            .max(6),
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

async fn migrate_model_access(store: &HistoryFixture) -> Result<ThreadCheckpoint> {
    store.import_identity(|_| Ok(())).await
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

async fn downgrade_checkpoint_to_schema_four(path: &std::path::Path) -> Result<String> {
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
    legacy["schemaVersion"] = serde_json::json!(4);
    let saved = legacy["state"].as_object_mut().context("saved state")?;
    for field in ["execution", "executionSequence", "continuation"] {
        saved.remove(field);
    }
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
    db.execute_unprepared(
        "DROP TABLE IF EXISTS seaql_migrations; UPDATE history_meta SET schema_version=8",
    )
    .await?;
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

    let encoded = downgrade_checkpoint_to_schema_four(&path).await?;
    let source = source_evidence(&path).await?;
    let target_path = directory.path().join("history-current.sqlite");
    let cold = HistoryStore::open(&target_path, "migration").await?;
    assert!(
        cold.checkpoint().await.is_err(),
        "cold queries must not convert legacy state"
    );
    cold.set_migration_fault(Some(MigrationFault::EnvelopeUpdate));
    let failure = cold
        .initialize(import_origin(&path, "migration")?)
        .await
        .expect_err("the explicit import must reach the target checkpoint transaction");
    assert!(format!("{failure:#}").contains("injected target history migration write failure"));
    assert!(format!("{failure:#}").contains("m20261026_100001_history_current"));
    assert_eq!(
        crate::studio::startup::StudioStartupError::input("history", failure).kind,
        crate::studio::startup::StudioStartupErrorKind::Migration
    );
    assert_pending(&target_path).await?;
    assert_eq!(source_evidence(&path).await?, source);
    let db = raw_database(&path).await?;
    let row = db.query_one_raw(Statement::from_string(DatabaseBackend::Sqlite,
        "SELECT schema_version,payload FROM history_meta,session_checkpoint WHERE history_meta.id=1 AND session_checkpoint.id=1"))
        .await?.context("preserved source")?;
    assert_eq!(row.try_get::<i64>("", "schema_version")?, 8);
    assert_eq!(row.try_get::<String>("", "payload")?, encoded);
    assert!(
        db.query_one_raw(Statement::from_string(
            DatabaseBackend::Sqlite,
            "SELECT 1 FROM sqlite_schema WHERE type='table' AND name='seaql_migrations'"
        ))
        .await?
        .is_none(),
        "target import cannot invent completion records in the source"
    );
    db.close().await?;
    cold.set_migration_fault(None);
    cold.retry_initialization().await?;
    let reopened = HistoryStore::open(&target_path, "migration").await?;
    reopened.prepare_activation().await?;
    let after = reopened
        .checkpoint()
        .await?
        .context("upgraded checkpoint")?;
    let mut expected = before.clone();
    crate::studio::model_route::migration::upgrade(&mut expected.state)?;
    crate::studio::delegation::migrate(&mut expected.state)?;
    assert_eq!(
        serde_json::to_value(&after)?,
        serde_json::to_value(&expected)?
    );
    assert_current(&target_path, "migration").await?;
    assert_eq!(source_evidence(&path).await?, source);
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
    let cold = HistoryStore::open(&target_path, "migration").await?;
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
    drop(runtime);
    let store = crate::studio::StudioStore::open(&home.join("studio/v2/studio.sqlite")).await?;
    let mut children = Vec::new();
    for (id, role) in [
        ("retired-child", crate::config::ROOT_AGENT_ROUTE_KEY),
        ("cold-child", "executor"),
        ("archived-child", "reviewer"),
    ] {
        let mut child = bound_thread(id);
        child.project_id = project.id.clone();
        child.parent_thread_id = Some(root.id.clone());
        child.root_thread_id = root.id.clone();
        child.role = role.into();
        child.archived = id == "archived-child";
        store
            .persist_directory_summaries(&DirectoryDelta {
                thread_upserts: vec![child.clone()],
                ..Default::default()
            })
            .await?;
        let paths = store.session_paths(&project.id, id)?;
        let path = paths.legacy_history_database();
        let history = HistoryStore::open(&path, id).await?;
        let mut profile: serde_json::Value = serde_json::from_str(LEGACY_PROFILE)?;
        profile["profileId"] = role.into();
        profile["displayName"] = id.into();
        profile["providerId"] = "storage-fixture".into();
        profile["model"] = "storage-model".into();
        profile["effort"] = serde_json::Value::Null;
        profile["systemInstructions"] = "Frozen child role text".into();
        let state = saved_state(BTreeMap::from([
            (
                "studio.agent-profile".into(),
                record(
                    2,
                    "pl.studio.agent-profile",
                    1,
                    &serde_json::to_string(&profile)?,
                )?,
            ),
            (
                "studio.instructions".into(),
                ExtensionRecord {
                    revision: 3,
                    payload: legacy_instructions(
                        legacy_block("modelBase", "model base", "base"),
                        vec![legacy_block(
                            "executionProfile",
                            id,
                            "Frozen child role text",
                        )],
                        Vec::new(),
                    )?,
                },
            ),
        ]));
        persist(&history, state, true).await?;
        drop(history);
        downgrade_checkpoint_to_schema_four(&path).await?;
        let evidence = source_evidence(&path).await?;
        assert!(!paths.history_database().exists());
        children.push((child, path, paths.history_database(), evidence));
    }
    let root_paths = store.session_paths(&project.id, &root.id)?;
    let root_path = root_paths.legacy_history_database();
    seed_legacy_installation(&root_paths.history_database(), &root_path, &root.id).await?;
    downgrade_checkpoint_to_schema_four(&root_path).await?;
    let root_evidence = source_evidence(&root_path).await?;
    store.close().await?;
    drop(store);
    let runtime = crate::StudioRuntime::initialize(options()).await?;
    let result = async {
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
        for (child, source, current, evidence) in children {
            let saved = HistoryStore::open(&current, &child.id)
                .await?
                .checkpoint()
                .await?
                .context("current child checkpoint")?;
            anyhow::ensure!(
                saved.schema_version == ThreadCheckpoint::SCHEMA_VERSION,
                "child envelope was not upgraded"
            );
            anyhow::ensure!(
                child.archived || runtime.thread_snapshot(&child.id).await?.thread.id == child.id,
                "child snapshot unavailable after opening"
            );
            assert_current(&current, &child.id).await?;
            assert_eq!(source_evidence(&source).await?, evidence);
        }
        assert_current(&root_paths.history_database(), &root.id).await?;
        assert_eq!(source_evidence(&root_path).await?, root_evidence);
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
    let store = existing_history(&path, "migration").await?;
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

    let reopened = existing_history(&path, "migration").await?;
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
    let host = MigrationHost::open().await?;
    let store = &host.store;
    let database_path = store.paths().database();
    let thread = bound_thread("migration");
    let mut original = host.legacy_simple_state(BTreeMap::from([
        (
            "studio.model-route".into(),
            record(2, "pl.studio.model-route", 1, LEGACY_ROUTE)?,
        ),
        (
            "studio.agent-profile".into(),
            record(3, "pl.studio.agent-profile", 1, LEGACY_PROFILE)?,
        ),
    ]))?;
    original.lifecycle = pl_core::thread::ThreadLifecycle::Closed;
    let source_history = host
        .persist_restored(&thread.project_id, &thread.id, original.clone())
        .await?;
    let paths = store.session_paths(&thread.project_id, &thread.id)?;
    let source_path = paths.legacy_history_database();
    let source = source_evidence(&source_path).await?;
    let history = store.history_for(&thread.project_id, &thread.id).await?;
    history.set_migration_fault(Some(MigrationFault::ModelAccessUpdate));

    let before = source_history
        .checkpoint()
        .await?
        .context("pre-migration checkpoint")?;
    let failure = host
        .factory
        .prepare_history_catalog()
        .await
        .expect_err("catalog import must reach the target model-access update");
    assert!(format!("{failure:#}").contains("injected target history migration write failure"));
    assert_pending(&paths.history_database()).await?;
    assert!(
        crate::studio::thread_factory::recovery::load_checkpoint_for_recovery(store, &thread)
            .await
            .is_err()
    );
    let preserved = source_history
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
    assert_eq!(source_evidence(&source_path).await?, source);
    history.set_migration_fault(None);
    assert!(
        host.factory.prepare_history_catalog().await.is_err(),
        "catalog preparation must retain the failed owner's result until explicit retry"
    );
    assert_pending(&paths.history_database()).await?;
    history.retry_initialization().await?;
    host.factory.prepare_history_catalog().await?;
    assert_current(&paths.history_database(), &thread.id).await?;

    let recovered =
        crate::studio::thread_factory::recovery::load_checkpoint_for_recovery(store, &thread)
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
        crate::studio::thread_factory::recovery::load_checkpoint_for_recovery(store, &thread)
            .await?
            .context("second recovery")?;
    assert_eq!(serde_json::to_vec(&again)?, serde_json::to_vec(&recovered)?);
    assert_eq!(source_evidence(&source_path).await?, source);
    drop(history);
    drop(source_history);
    store.close().await?;

    let reopened = crate::studio::StudioStore::open(&database_path).await?;
    let history = reopened.history_for(&thread.project_id, &thread.id).await?;
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
    reopened.close().await?;
    Ok(())
}

#[tokio::test]
async fn unknown_close_intent_encoding_preserves_checkpoint_and_history() -> Result<()> {
    for (format, version, content) in [
        ("pl.studio.unrecognized-close", 1, "{}"),
        ("pl.studio.agent-close", 2, "{}"),
        ("pl.studio.agent-close", 1, r#"{"closed":false}"#),
    ] {
        let host = MigrationHost::open().await?;
        let store = &host.store;
        let thread = bound_thread("migration");
        let state = host.legacy_simple_state(BTreeMap::from([(
            crate::studio::agent_close::EXTENSION.into(),
            record(8, format, version, content)?,
        )]))?;
        let source_history = host
            .persist_restored(&thread.project_id, &thread.id, state)
            .await?;
        let paths = store.session_paths(&thread.project_id, &thread.id)?;
        let source = source_evidence(&paths.legacy_history_database()).await?;
        let before = source_history
            .checkpoint()
            .await?
            .context("original checkpoint")?;
        let failure = host
            .factory
            .prepare_history_catalog()
            .await
            .expect_err("invalid old close encoding must fail target import");
        assert!(format!("{failure:#}").contains("m20261026_100001_history_current"));
        assert_pending(&paths.history_database()).await?;
        assert!(
            crate::studio::thread_factory::recovery::load_checkpoint_for_recovery(store, &thread)
                .await
                .is_err()
        );
        let after = source_history
            .checkpoint()
            .await?
            .context("retained checkpoint")?;
        assert_eq!(serde_json::to_vec(&after)?, serde_json::to_vec(&before)?);
        assert_eq!(source_history.watermark().await?, before.history_fence);
        assert_eq!(
            source_evidence(&paths.legacy_history_database()).await?,
            source
        );
        // This intentionally failed owner stays failed; closing still waits its real terminal job.
        assert!(store.close().await.is_err());
    }
    Ok(())
}

#[tokio::test]
async fn legacy_child_profile_representation_is_committed_once_before_recovery() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("history.sqlite");
    let store = existing_history(&path, "migration").await?;
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

    let reopened = existing_history(&path, "migration").await?;
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
    let store = existing_history(&path, "migration").await?;
    let original = saved_state(BTreeMap::from([(
        "studio.model-route".into(),
        record(2, "pl.studio.model-route", 1, LEGACY_ROUTE)?,
    )]));
    persist(&store, original, true).await?;
    let legacy = store.checkpoint().await?.context("legacy checkpoint")?;
    // Unknown source fields are import facts, not a projection reconstructed from typed state.
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
    faults.close().await?;
    store.freeze_source().await?;
    let source = source_evidence(&path).await?;
    store
        .target
        .set_migration_fault(Some(MigrationFault::ModelAccessUpdate));
    let failure = migrate_model_access(&store)
        .await
        .expect_err("target model-access write must fail");
    assert!(format!("{failure:#}").contains("injected target history migration write failure"));
    let target_path = path.with_file_name("history-current.sqlite");
    assert_pending(&target_path).await?;
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

    assert_eq!(source_evidence(&path).await?, source);
    store.target.set_migration_fault(None);
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
    let target = raw_database(&target_path).await?;
    let row = target
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
    target.close().await?;
    assert_current(&target_path, "migration").await?;
    assert_eq!(source_evidence(&path).await?, source);
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
    let host = MigrationHost::open().await?;
    let store = &host.store;
    let thread = bound_thread("migration");
    let mut state = host.legacy_simple_state(BTreeMap::from([(
        crate::compaction::LATEST_RECEIPT.into(),
        record(7, "pl.studio.compaction", 1, LEGACY_NATIVE_RECEIPT)?,
    )]))?;
    // A real saved source already includes this same receipt in its reliable cumulative summary.
    // Fold through the producer's accounting path before the checkpoint and SQL costs are saved.
    crate::studio::thread_projection::fold_effect_accounting(
        &mut state.usage_summary,
        &pl_core::thread::ThreadEffectBatch {
            sequence: state.commit_sequence,
            extensions: vec![pl_core::thread::extensions::ExtensionChange::Put {
                id: crate::compaction::LATEST_RECEIPT.into(),
                record: state.extensions[crate::compaction::LATEST_RECEIPT].clone(),
            }]
            .into(),
            ..Default::default()
        },
    )?;
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
    let source_history = host
        .persist_restored(&thread.project_id, &thread.id, state)
        .await?;
    let paths = store.session_paths(&thread.project_id, &thread.id)?;
    let source_path = paths.legacy_history_database();
    let before = source_history
        .checkpoint()
        .await?
        .context("legacy checkpoint")?;
    let source_db = raw_database(&source_path).await?;
    source_db
        .execute_unprepared(
            "DROP TABLE IF EXISTS seaql_migrations; UPDATE history_meta SET schema_version=5",
        )
        .await?;
    source_db.close().await?;
    let source = source_evidence(&source_path).await?;
    assert!(!tokio::fs::try_exists(paths.history_database()).await?);

    // 真实共同恢复入口：旧库结构升级必须能从 v1 原生回执恢复来源而不是先硬失败。
    host.factory.prepare_history_catalog().await?;
    let upgraded = store.history_for(&thread.project_id, &thread.id).await?;
    let checkpoint =
        crate::studio::thread_factory::recovery::load_checkpoint_for_recovery(store, &thread)
            .await?
            .context("upgraded checkpoint")?;
    assert_eq!(checkpoint.state_revision, before.state_revision);
    assert_eq!(checkpoint.history_fence, before.history_fence);
    assert_eq!(checkpoint.state.usage_summary, before.state.usage_summary);
    assert_eq!(checkpoint.state.usage_summary.inference_count, 1);
    assert_eq!(checkpoint.state.usage_summary.total_tokens, 3);
    assert_eq!(
        checkpoint.state.usage_summary.estimated_costs,
        vec![pl_core::thread::UsageCost {
            currency: "USD".into(),
            amount: 0.25,
        }]
    );
    assert_eq!(
        upgraded
            .accounting()
            .await?
            .context("saved compaction costs")?
            .purpose_costs,
        vec![(
            Some("compaction".into()),
            vec![pl_protocol::RuntimeCostAmount {
                currency: "USD".into(),
                amount: 0.25,
            }],
        )]
    );
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
    host.factory.prepare_history_catalog().await?;
    assert_eq!(
        serde_json::to_vec(
            &upgraded
                .checkpoint()
                .await?
                .context("stable catalog checkpoint")?
        )?,
        unchanged
    );
    assert_current(&paths.history_database(), &thread.id).await?;
    assert_eq!(source_evidence(&source_path).await?, source);
    store.close().await?;
    Ok(())
}

/// 不可用的旧来源必须 fail-closed：升级失败保留原数据并可重试，不改写任何载荷。
#[tokio::test]
async fn unusable_legacy_compaction_source_fails_closed_without_rewriting() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("history.sqlite");
    let store = existing_history(&path, "migration").await?;
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
    store.freeze_source().await?;
    let source_db = raw_database(&path).await?;
    source_db
        .execute_unprepared(
            "DROP TABLE IF EXISTS seaql_migrations; UPDATE history_meta SET schema_version=5",
        )
        .await?;
    source_db.close().await?;
    let source = source_evidence(&path).await?;

    let target_path = path.with_file_name("history-current.sqlite");
    let failed = &store.target;
    let failure = failed
        .initialize(import_origin(&path, "migration")?)
        .await
        .expect_err("unusable source must fail the official target step");
    assert!(format!("{failure:#}").contains("m20261026_100001_history_current"));
    assert_pending(&target_path).await?;
    assert!(
        failed
            .initialize(import_origin(&path, "migration")?)
            .await
            .is_err(),
        "失败结果保留，普通重复初始化不会偷偷重跑"
    );
    assert!(
        failed.retry_initialization().await.is_err(),
        "原始来源不变，显式重试仍然失败闭锁"
    );
    assert_pending(&target_path).await?;
    assert!(failed.checkpoint().await.is_err());
    // 原数据与旧版本仍可重试读取，升级没有被部分提交。
    let checkpoint = store
        .source
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
    assert_eq!(source_evidence(&path).await?, source);
    assert_eq!(stored_format(&path).await?, 5);

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

    let missing =
        crate::studio::thread_factory::recovery::load_checkpoint_read_only(&store, &thread)
            .await
            .expect_err("缺库冷读必须返回未就绪，而不是正常空历史");
    assert!(format!("{missing:#}").contains("explicit initialization is required"));
    assert!(!tokio::fs::try_exists(&history_path).await?);

    let (entered, release) = history.arm_init_gate().await;
    let writer = history.clone();
    let mut drive_state = SharedHistoryDrive {
        initialize: Some(tokio::spawn(async move {
            writer.initialize(HistoryInitialization::New).await
        })),
        checkpoint: None,
        recovery: None,
        release: Some(release),
    };
    let drive = drive_state
        .run(&store, &thread, thread_id, &history_path, entered)
        .await;
    let cleanup = drive_state.reclaim(&store).await;
    finish_shared_history_drive(drive, cleanup)?;
    assert_eq!(history.watermark().await?, 0);
    assert_current(&history_path, thread_id).await?;

    // The first actual save is ordered after complete empty New publication. No scheduler race
    // between initialization and a writer batch decides what the waiting readers may observe.
    persist(&history, saved_state(BTreeMap::new()), true).await?;
    let recovered =
        crate::studio::thread_factory::recovery::load_checkpoint_read_only(&store, &thread)
            .await?
            .context("saved checkpoint after New")?;
    assert_eq!(recovered.thread_id, thread_id);
    assert_eq!(recovered.state_revision, 1);
    assert_eq!(recovered.history_fence, 1);
    assert_eq!(history.watermark().await?, 1);
    let foreign = store
        .state_for(&thread.project_id, "other-thread")?
        .load_read_only(&history)
        .await
        .expect_err("错 Thread 的 history 句柄必须失败闭锁");
    assert!(
        foreign
            .to_string()
            .contains("history database belongs to another Thread"),
        "{foreign}"
    );

    drop(history);
    store.close().await?;
    drop(store);
    let damaged = crate::studio::StudioStore::open(&database_path).await?;
    let faults = raw_database(&history_path).await?;
    faults
        .execute_unprepared("DELETE FROM history_meta")
        .await?;
    faults.close().await?;
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
    damaged.close().await?;
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
    initialize: Option<tokio::task::JoinHandle<Result<()>>>,
    checkpoint: Option<tokio::task::JoinHandle<Result<Option<ThreadCheckpoint>>>>,
    recovery: Option<tokio::task::JoinHandle<Result<Option<ThreadCheckpoint>>>>,
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
    ) -> Result<()> {
        wait_shared_history_stage("initialization gate arrived", entered).await??;
        assert!(
            !tokio::fs::try_exists(history_path).await?,
            "未完成的目标仅属于准备owner，不得发布canonical名称"
        );
        let prefix = format!(
            ".{}.prepare-",
            history_path
                .file_name()
                .context("history filename")?
                .to_string_lossy()
        );
        let mut entries =
            tokio::fs::read_dir(history_path.parent().context("history parent")?).await?;
        let mut preparations = 0;
        while let Some(entry) = entries.next_entry().await? {
            if entry.file_name().to_string_lossy().starts_with(&prefix) {
                preparations += 1;
            }
        }
        assert_eq!(
            preparations, 1,
            "the blocked owner holds one unpublished preparation"
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
        assert!(
            !self
                .checkpoint
                .as_ref()
                .context("checkpoint task")?
                .is_finished()
        );
        let recovery_waiting = waiting_history.arm_reader_before_init().await;
        let waiting = store.clone();
        let waiting_thread = thread.clone();
        self.recovery = Some(tokio::spawn(async move {
            crate::studio::thread_factory::recovery::load_checkpoint_for_recovery(
                &waiting,
                &waiting_thread,
            )
            .await
        }));
        wait_shared_history_stage("recovery waiting on shared init", recovery_waiting).await??;
        assert!(
            !self
                .recovery
                .as_ref()
                .context("recovery task")?
                .is_finished()
        );
        self.release
            .take()
            .context("initialization gate already released")?
            .send(())
            .map_err(|_| anyhow::anyhow!("initialization owner dropped the init gate"))?;

        join_shared_history_handle("initialize join", &mut self.initialize).await?;
        assert!(
            join_shared_history_handle("checkpoint join", &mut self.checkpoint)
                .await?
                .is_none(),
            "completed empty New has no invented checkpoint"
        );
        assert!(
            join_shared_history_handle("recovery join", &mut self.recovery)
                .await?
                .is_none()
        );
        Ok(())
    }

    async fn reclaim(self, store: &crate::studio::StudioStore) -> Result<()> {
        if let Some(release) = self.release {
            let _ = release.send(());
        }
        let initialize = reclaim_shared_history_task("initialize", self.initialize).await;
        let checkpoint = reclaim_shared_history_task("checkpoint", self.checkpoint).await;
        let recovery = reclaim_shared_history_task("recovery", self.recovery).await;
        let preparation = store
            .thread_persistence()
            .drain_history_preparations()
            .await;
        finish_shared_history_drive(
            finish_shared_history_drive(
                finish_shared_history_drive(initialize, checkpoint),
                recovery,
            ),
            preparation,
        )
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
/// a writer changes the SQLite file. History imports a proven old source, but never adopts an
/// unproven current target. Product/calls retain their independent adoption contracts.
#[tokio::test]
async fn studio_databases_adopt_current_files_and_refuse_future_writes() -> Result<()> {
    use crate::studio::{StudioStore, paths::StudioPaths, storage::calls::CallsStore};
    use sea_orm::{DatabaseBackend, Statement};
    for family in ["product", "history", "calls"] {
        for fault in [
            "format",
            "migration",
            "missing_table",
            "checkpoint",
            "missing_ledger",
        ] {
            if matches!(fault, "checkpoint" | "missing_ledger") && family != "history" {
                continue;
            }
            let directory = tempfile::tempdir()?;
            if family == "history" {
                let source_path = directory.path().join("history.sqlite");
                let path = directory.path().join("history-current.sqlite");
                let producer = HistoryStore::open(&source_path, "adoption").await?;
                producer.commit(1, &[], &[]).await?;
                // ForwardNine was a released pre-framework source, not a current target with
                // its official completion removed. Preserve that distinction explicitly.
                let db = raw_database(&source_path).await?;
                db.execute_unprepared(
                    "DROP TABLE seaql_migrations; UPDATE history_meta SET schema_version=9",
                )
                .await?;
                db.close().await?;
                let source = source_evidence(&source_path).await?;
                let current = import_source(&source_path, &path, "adoption").await?;
                assert_eq!(current.watermark().await?, 1);
                let checkpoint = current.checkpoint().await?.context("imported checkpoint")?;
                let db = raw_database(&path).await?;
                match fault {
                    "format" => {
                        db.execute_unprepared("UPDATE history_meta SET schema_version=999")
                            .await?;
                    }
                    "migration" => {
                        db.execute_unprepared("INSERT INTO seaql_migrations(version,applied_at) VALUES('m99999999_future',1)").await?;
                    }
                    "missing_table" => {
                        db.execute_unprepared("DROP TABLE history_items").await?;
                    }
                    "missing_ledger" => {
                        db.execute_unprepared("DROP TABLE seaql_migrations").await?;
                    }
                    "checkpoint" => {
                        let mut checkpoint = checkpoint;
                        checkpoint.schema_version = ThreadCheckpoint::SCHEMA_VERSION + 1;
                        let payload = serde_json::to_string(&checkpoint)?;
                        db.execute_raw(Statement::from_sql_and_values(
                            DatabaseBackend::Sqlite,
                            "UPDATE session_checkpoint SET payload=?,payload_hash=? WHERE id=1",
                            vec![
                                payload.clone().into(),
                                pl_core::context::content_hash(payload.as_bytes()).into(),
                            ],
                        ))
                        .await?;
                    }
                    _ => unreachable!("fixed corruption fixture"),
                }
                db.close().await?;
                let before = source_evidence(&path).await?;
                let refused = HistoryStore::open(&path, "adoption").await?;
                assert!(
                    refused.prepare_activation().await.is_err(),
                    "unproven current {fault} was accepted"
                );
                assert!(
                    refused
                        .initialize(HistoryInitialization::New)
                        .await
                        .is_err(),
                    "New cannot repair an existing unproven target"
                );
                assert!(refused.checkpoint().await.is_err());
                assert_eq!(
                    source_evidence(&path).await?,
                    before,
                    "refused target {fault} changed"
                );
                assert_eq!(
                    source_evidence(&source_path).await?,
                    source,
                    "target rejection must not touch or fall back to source"
                );
                continue;
            }
            let paths = StudioPaths::resolve(Some(directory.path().to_path_buf()))?;
            let path = if family == "product" {
                paths.database()
            } else {
                paths.calls_database()
            };
            for generation in 0..2 {
                if family == "product" {
                    StudioStore::open(&path).await?.close().await?;
                } else {
                    CallsStore::prepare(&path).await?.close().await?;
                }
                if generation == 0 {
                    let db = raw_database(&path).await?;
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
                db.execute_unprepared(if family == "product" {
                    "DROP TABLE seaql_migrations; DROP TABLE studio_objects"
                } else {
                    "DROP TABLE seaql_migrations; DROP TABLE call_usage_summary"
                })
                .await?;
            } else {
                db.execute_unprepared(if family == "product" {
                    "PRAGMA user_version=999"
                } else {
                    "UPDATE calls_meta SET schema_version=999"
                })
                .await?;
            }
            db.close().await?;
            let before = tokio::fs::read(&path).await?;
            let failure = if family == "product" {
                StudioStore::open(&path).await.map(|_| ())
            } else {
                CallsStore::prepare(&path).await.map(|_| ())
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

/// Releases the steps a file written before this build could have recorded, in sequence order.
const RELEASED_STEPS: [&str; 8] = [
    "m20261026_000001_history_schema",
    "m20261026_000002_history_input_presentation",
    "m20261026_000003_history_input_bindings",
    "m20261026_000004_history_context_sources",
    "m20261026_000005_history_tool_answers",
    "m20261026_000006_history_checkpoint_v5",
    "m20261026_000007_history_model_access",
    "m20261026_000008_history_execution_identity",
];

/// A new Thread uses only the current target step. Its first real save is not a legacy import and
/// retains unknown producer payloads without running old representation conversions.
#[tokio::test]
async fn new_history_file_is_created_at_the_current_format() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("history.sqlite");
    let thread_id = "created-format";
    let store = HistoryStore::open(&path, thread_id).await?;
    persist(
        &store,
        saved_state(BTreeMap::from([(
            "vendor.unknown".into(),
            record(6, "vendor.unknown", 7, "opaque bytes must survive")?,
        )])),
        true,
    )
    .await?;
    assert_eq!(
        stored_format(&path).await?,
        10,
        "a created file reaches the current format"
    );
    let recorded = recorded_steps(&path).await?;
    assert_eq!(
        recorded,
        vec!["m20261026_100001_history_current".to_owned()],
        "a current target records only the step it actually executed"
    );
    let checkpoint = store.checkpoint().await?.context("saved checkpoint")?;
    assert_eq!(
        checkpoint.state.extensions["vendor.unknown"]
            .payload
            .content(),
        "opaque bytes must survive"
    );
    Ok(())
}

/// A synthetic prefix: the released step names recorded by hand plus format 8. It proves the prefix
/// rule and the appended conversion, but it is **not** evidence of a real previous-build execution —
/// `schema::lineage_tests::released_eight_file_upgrades_to_the_public_artifact_format` is.
#[tokio::test]
async fn synthetic_eight_prefix_advances_through_the_public_artifact_step() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("history.sqlite");
    let thread_id = "released-eight";
    let store = HistoryStore::open(&path, thread_id).await?;
    persist(
        &store,
        saved_state(BTreeMap::from([(
            "vendor.unknown".into(),
            record(6, "vendor.unknown", 7, "opaque bytes must survive")?,
        )])),
        true,
    )
    .await?;
    drop(store);

    // Hand-written forgeries of the released lineage: eight known names, no newer step, format 8.
    let db = raw_database(&path).await?;
    let rows = RELEASED_STEPS
        .iter()
        .enumerate()
        .map(|(index, name)| format!("('{name}',{})", index + 1))
        .collect::<Vec<_>>()
        .join(",");
    db.execute_unprepared(&format!(
        "DROP TABLE IF EXISTS seaql_migrations; \
         CREATE TABLE seaql_migrations (version TEXT NOT NULL PRIMARY KEY, applied_at INTEGER NOT NULL); \
         INSERT INTO seaql_migrations(version,applied_at) VALUES {rows}; \
         UPDATE history_meta SET schema_version=8"
    ))
    .await?;
    db.close().await?;

    let source = source_evidence(&path).await?;
    let advanced = import_bound_source(&path, thread_id).await?;
    assert_current(&path.with_file_name("history-current.sqlite"), thread_id).await?;
    assert_eq!(stored_format(&path).await?, 8);
    assert!(
        recorded_steps(&path.with_file_name("history-current.sqlite"))
            .await?
            .contains(&"m20261026_100001_history_current".to_owned()),
        "the target records its own completed import"
    );
    // The released records are still exactly the ones the file had: nothing was rewritten.
    let recorded = recorded_steps(&path).await?;
    for step in RELEASED_STEPS {
        assert!(
            recorded.contains(&step.to_owned()),
            "{step} must stay recorded"
        );
    }
    let checkpoint = advanced
        .checkpoint()
        .await?
        .context("preserved checkpoint")?;
    assert_eq!(
        checkpoint.state.extensions["vendor.unknown"]
            .payload
            .content(),
        "opaque bytes must survive"
    );
    assert_eq!(source_evidence(&path).await?, source);
    drop(advanced);
    Ok(())
}

/// A history file written by an earlier build may already declare format 9 without any official
/// migration record. Import verifies the whole promised structure, never lowers the source format
/// or invents old completion rows, and records only the actual current target step.
#[tokio::test]
async fn forward_format_nine_without_records_is_adopted_without_downgrade() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("history.sqlite");
    let thread_id = "forward-nine";
    let store = HistoryStore::open(&path, thread_id).await?;
    persist(
        &store,
        saved_state(BTreeMap::from([(
            "vendor.unknown".into(),
            record(6, "vendor.unknown", 7, "opaque bytes must survive")?,
        )])),
        true,
    )
    .await?;
    drop(store);

    let db = raw_database(&path).await?;
    db.execute_unprepared(
        "DROP TABLE IF EXISTS seaql_migrations; UPDATE history_meta SET schema_version=9",
    )
    .await?;
    db.close().await?;

    let source = source_evidence(&path).await?;
    let reopened = import_bound_source(&path, thread_id).await?;
    reopened.prepare_activation().await?;
    assert_eq!(
        stored_format(&path).await?,
        9,
        "adoption never lowers the declared format"
    );
    let current_path = path.with_file_name("history-current.sqlite");
    assert_current(&current_path, thread_id).await?;
    let recorded = recorded_steps(&current_path).await?;
    assert_eq!(
        recorded,
        vec!["m20261026_100001_history_current".to_owned()],
        "a forward source does not masquerade as target migration execution"
    );
    let checkpoint = reopened
        .checkpoint()
        .await?
        .context("preserved checkpoint")?;
    assert_eq!(
        checkpoint.state.extensions["vendor.unknown"]
            .payload
            .content(),
        "opaque bytes must survive"
    );
    drop(reopened);

    // Reopening fixes the lineage: the same records, the same format, nothing replayed.
    let stable = HistoryStore::open(&current_path, thread_id).await?;
    stable.prepare_activation().await?;
    assert_eq!(stored_format(&path).await?, 9);
    assert_eq!(recorded_steps(&current_path).await?, recorded);
    assert_eq!(source_evidence(&path).await?, source);
    Ok(())
}

/// Known step names recorded out of order are a mixed lineage: refused before any write, with the
/// file preserved and no completion record invented.
#[tokio::test]
async fn mixed_known_step_records_are_refused_without_writing() -> Result<()> {
    use sea_orm::{DatabaseBackend, Statement};

    let directory = tempfile::tempdir()?;
    let path = directory.path().join("history.sqlite");
    let thread_id = "mixed-lineage";
    let store = HistoryStore::open(&path, thread_id).await?;
    persist(&store, saved_state(BTreeMap::new()), true).await?;
    drop(store);

    let db = raw_database(&path).await?;
    db.execute_unprepared(
        "DROP TABLE IF EXISTS seaql_migrations; \
         CREATE TABLE seaql_migrations (version TEXT NOT NULL PRIMARY KEY, applied_at INTEGER NOT NULL); \
         INSERT INTO seaql_migrations(version,applied_at) VALUES \
           ('m20261026_000001_history_schema',1), \
           ('m20261026_000003_history_input_bindings',2); \
         UPDATE history_meta SET schema_version=8",
    )
    .await?;
    db.close().await?;

    let source = source_evidence(&path).await?;
    let target_path = path.with_file_name("history-current.sqlite");
    let target = HistoryStore::open(&target_path, thread_id).await?;
    let failure = target
        .initialize(import_origin(&path, thread_id)?)
        .await
        .expect_err("a mixed lineage must be refused");
    assert!(
        format!("{failure:#}").contains("legal prefix"),
        "unexpected failure: {failure:#}"
    );
    let db = raw_database(&path).await?;
    let rows = db
        .query_all_raw(Statement::from_string(
            DatabaseBackend::Sqlite,
            "SELECT version FROM seaql_migrations",
        ))
        .await?;
    assert_eq!(rows.len(), 2, "no completion record was invented");
    let format = db
        .query_one_raw(Statement::from_string(
            DatabaseBackend::Sqlite,
            "SELECT schema_version FROM history_meta WHERE id=1",
        ))
        .await?
        .context("preserved history identity")?
        .try_get::<i64>("", "schema_version")?;
    assert_eq!(format, 8, "the refused source keeps its own format");
    db.close().await?;
    assert_pending(&target_path).await?;
    assert_eq!(source_evidence(&path).await?, source);
    Ok(())
}

/// A forward format that only looks current is refused: a missing promised index or column is not
/// silently recreated by the create step, and no completion record is written for the refused file.
#[tokio::test]
async fn forward_format_nine_with_missing_structure_is_refused_without_writes() -> Result<()> {
    use sea_orm::{DatabaseBackend, Statement};

    for (breakage, fragment, repaired) in [
        (
            "DROP INDEX history_items_by_kind",
            "history_items_by_kind",
            "SELECT 1 FROM sqlite_schema WHERE type='index' AND name='history_items_by_kind'",
        ),
        (
            "ALTER TABLE history_fact_receipts DROP COLUMN last_write_seq",
            "history_fact_receipts",
            "SELECT 1 FROM pragma_table_info('history_fact_receipts') WHERE name='last_write_seq'",
        ),
        (
            "ALTER TABLE session_checkpoint RENAME TO broken_checkpoint;
             CREATE TABLE session_checkpoint (
               id INTEGER PRIMARY KEY CHECK (id=1), revision INTEGER NOT NULL,
               context_revision INTEGER NOT NULL, context_count INTEGER NOT NULL,
               payload TEXT NOT NULL CHECK (json_valid(payload)), payload_hash TEXT NOT NULL,
               legacy_cleanup INTEGER NOT NULL DEFAULT 1);
             INSERT INTO session_checkpoint SELECT * FROM broken_checkpoint;
             DROP TABLE broken_checkpoint",
            "session_checkpoint",
            "SELECT 1 FROM pragma_table_info('session_checkpoint') WHERE name='legacy_cleanup' AND dflt_value='0'",
        ),
        (
            "ALTER TABLE history_meta RENAME TO broken_meta;
             CREATE TABLE history_meta (
               id INTEGER PRIMARY KEY, schema_version INTEGER NOT NULL,
               database_id TEXT NOT NULL, thread_id TEXT NOT NULL, applied_write_seq INTEGER NOT NULL);
             INSERT INTO history_meta SELECT * FROM broken_meta;
             DROP TABLE broken_meta",
            "history_meta",
            "SELECT 1 FROM sqlite_schema WHERE name='history_meta' AND instr(lower(sql),'check')>0",
        ),
        (
            "ALTER TABLE current_context RENAME TO broken_context;
             CREATE TABLE current_context (
               ordinal INTEGER PRIMARY KEY, record_id TEXT NOT NULL,
               payload TEXT NOT NULL CHECK (json_valid(payload)), payload_hash TEXT NOT NULL);
             INSERT INTO current_context SELECT * FROM broken_context;
             DROP TABLE broken_context",
            "current_context",
            "SELECT 1 FROM pragma_index_list('current_context') WHERE [unique]=1 AND partial=0",
        ),
    ] {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let thread_id = "forward-broken";
        let store = HistoryStore::open(&path, thread_id).await?;
        persist(&store, saved_state(BTreeMap::new()), true).await?;
        drop(store);

        let db = raw_database(&path).await?;
        db.execute_unprepared(&format!(
            "{breakage}; DROP TABLE IF EXISTS seaql_migrations; \
             UPDATE history_meta SET schema_version=9"
        ))
        .await?;
        db.close().await?;

        let source = source_evidence(&path).await?;
        let target_path = path.with_file_name("history-current.sqlite");
        let target = HistoryStore::open(&target_path, thread_id).await?;
        let failure = target.initialize(import_origin(&path, thread_id)?).await
            .expect_err("an unproven forward format must be refused");
        assert!(
            format!("{failure:#}").contains(fragment),
            "the failure must name the missing structure ({fragment}): {failure:#}"
        );
        let db = raw_database(&path).await?;
        assert!(
            db.query_one_raw(Statement::from_string(
                DatabaseBackend::Sqlite,
                "SELECT 1 FROM sqlite_schema WHERE type='table' AND name='seaql_migrations'",
            ))
            .await?
            .is_none(),
            "a refused file gets no ledger"
        );
        assert!(
            db.query_one_raw(Statement::from_string(DatabaseBackend::Sqlite, repaired))
                .await?
                .is_none(),
            "the missing structure is not silently recreated"
        );
        db.close().await?;
        assert_pending(&target_path).await?;
        assert_eq!(stored_format(&path).await?, 9);
        assert_eq!(source_evidence(&path).await?, source);
    }
    Ok(())
}

/// The format the file declares, read on its own connection.
async fn stored_format(path: &std::path::Path) -> Result<i64> {
    use sea_orm::{DatabaseBackend, Statement};
    let db = raw_database(path).await?;
    let format = db
        .query_one_raw(Statement::from_string(
            DatabaseBackend::Sqlite,
            "SELECT schema_version FROM history_meta WHERE id=1",
        ))
        .await?
        .context("history format")?
        .try_get::<i64>("", "schema_version")?;
    db.close().await?;
    Ok(format)
}

/// The recorded step names, in the order the ledger stores them.
async fn recorded_steps(path: &std::path::Path) -> Result<Vec<String>> {
    use sea_orm::{DatabaseBackend, Statement};
    let db = raw_database(path).await?;
    let steps = db
        .query_all_raw(Statement::from_string(
            DatabaseBackend::Sqlite,
            "SELECT version FROM seaql_migrations ORDER BY applied_at,version",
        ))
        .await?
        .iter()
        .map(|row| row.try_get::<String>("", "version"))
        .collect::<Result<Vec<_>, _>>()?;
    db.close().await?;
    Ok(steps)
}
