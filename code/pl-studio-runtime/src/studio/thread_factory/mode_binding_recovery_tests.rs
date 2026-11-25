//! Mode 重新绑定把缺失路由绑定视为未知，而不改写规范初始上下文。

use anyhow::{Context, Result};
use pl_core::context::{ContextContent, ContextRecord, ContextSnapshot, ContextSource};

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
        model::{ModelDefinition, ModelTransportProfile},
        protocol::HistoryInstructionRole,
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
    let mut model = ModelDefinition::compatible(&route.model_id);
    model
        .extra
        .binding
        .set_transport(ModelTransportProfile::responses_http());
    model.extra.capabilities.instruction_snapshot_overrides = true;
    model.base.model_messages.instructions_template = "frozen mode migration base".into();
    let mut endpoint = pl_model::protocol::providers::openai::compatible_endpoint(
        "mode migration",
        "http://127.0.0.1:0",
    );
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
    let session = paths.session_paths(&project.id, &thread.id)?;
    let state_directory = session.root().to_owned();
    let state = crate::studio::storage::state::StateStore::new(state_directory.clone(), &thread.id);
    let initial_current = state.load_current().await?.context("initial current")?;
    let initial = initial_current.state.to_paused_snapshot();
    assert_eq!(
        initial
            .context
            .records
            .iter()
            .filter(|record| record.source == ContextSource::Instruction)
            .count(),
        1
    );
    assert!(
        initial
            .context
            .records
            .iter()
            .all(|record| { !matches!(record.source, ContextSource::InstructionSnapshot { .. }) })
    );
    assert!(
        !initial
            .extensions
            .contains_key("studio.instructions.binding")
    );
    let initial_instructions = initial.extensions["studio.instructions"].clone();
    let initial_instruction_records = initial
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
    drop(state);

    let runtime = crate::StudioRuntime::initialize(options()).await?;
    runtime
        .set_thread_mode(
            "same-mode-without-binding".into(),
            &thread.id,
            crate::mode::ThreadModeId::auto(),
        )
        .await?;
    runtime.shutdown_runtime().await?;
    let state = crate::studio::storage::state::StateStore::new(state_directory.clone(), &thread.id);
    let same_mode = state
        .load_current()
        .await?
        .context("same-Mode current")?
        .state
        .to_paused_snapshot();
    assert_eq!(
        same_mode.extensions["studio.instructions"], initial_instructions,
        "binding a canonical initial prompt must not advance its instruction revision"
    );
    let same_mode_instruction_records = same_mode
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
        &same_mode.extensions["studio.instructions.binding"],
    )?;
    assert!(saved_binding.append_snapshots);
    drop(state);

    let state = crate::studio::storage::state::StateStore::new(state_directory.clone(), &thread.id);
    let checkpoint = state
        .load_current()
        .await?
        .context("current before restoring the old snapshot")?;
    let mut restored = checkpoint.clone();
    let instruction_record = restored.state.extensions["studio.instructions"].clone();
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
    let context_revision = restored
        .state
        .context
        .revision
        .checked_add(1)
        .context("context revision exhausted")?;
    let extension_revision = restored
        .state
        .extension_sequence
        .checked_add(1)
        .context("extension revision exhausted")?;
    anyhow::ensure!(
        restored
            .state
            .extensions
            .contains_key("studio.instructions.binding"),
        "binding to remove from restored checkpoint"
    );
    restored
        .state
        .extensions
        .remove("studio.instructions.binding");
    restored.state.extension_sequence = extension_revision;
    let mut records = restored.state.context.records.to_vec();
    records.push(restored_snapshot.clone());
    restored.state.context = ContextSnapshot {
        revision: context_revision,
        records: records.into(),
    };
    restored.snapshot_revision = restored
        .snapshot_revision
        .checked_add(1)
        .context("current snapshot revision exhausted")?;
    let restored = std::sync::Arc::new(restored);
    let source = crate::studio::storage::current_writer::CurrentSource::new(
        {
            let restored = restored.clone();
            move |epoch, _| {
                let restored = restored.clone();
                Box::pin(async move {
                    let mut current = (*restored).clone();
                    current.saved_runtime_epoch = epoch;
                    Ok(current)
                })
            }
        },
        {
            let restored = restored.clone();
            move |epoch| {
                let restored = restored.clone();
                Box::pin(async move {
                    let mut current = (*restored).clone();
                    current.saved_runtime_epoch = epoch;
                    Ok(current)
                })
            }
        },
    );
    let coordinator_store =
        crate::studio::StudioStore::open(&home.join("data/studio.sqlite")).await?;
    let epoch = pl_core::thread::current::RuntimeEpoch::new();
    let mut state =
        crate::studio::storage::state::StateStore::new(state_directory.clone(), &thread.id);
    state
        .attach_current(
            coordinator_store.thread_persistence().clone(),
            None,
            epoch,
            source,
        )
        .await?;
    state.flush_current(epoch).await?;
    state
        .close_current(epoch, crate::thread_assembler::ClosePurpose::Preserve)
        .await?;
    drop(state);
    coordinator_store.close().await?;

    let second_mode_id = crate::mode::ThreadModeId::new("mode.custom_check")?;
    tokio::fs::create_dir_all(home.join("modes")).await?;
    tokio::fs::write(
        home.join("modes/mode.custom_check.json"),
        serde_json::to_vec(&crate::mode::ThreadModeDocument::from_parts(
            crate::mode::ThreadModeDefinition {
                id: second_mode_id.clone(),
                display_name: "Custom Check".into(),
                description: "Mode change test".into(),
                order: 20,
                prompt: "Custom prompt".into(),
                workflow: None,
            },
            Default::default(),
        ))?,
    )
    .await?;
    let runtime = crate::StudioRuntime::initialize(options()).await?;
    runtime
        .set_thread_mode(
            "changed-mode-with-unknown-binding".into(),
            &thread.id,
            second_mode_id,
        )
        .await?;
    runtime.shutdown_runtime().await?;

    let reopened = crate::studio::StudioStore::open(&home.join("data/studio.sqlite")).await?;
    let changed = crate::studio::thread_factory::recovery::load_current_for_recovery(
        &reopened,
        &crate::Thread::from(thread.clone()),
    )
    .await?
    .context("changed-Mode current")?
    .state
    .to_paused_snapshot();
    let current_instruction_records = changed
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
    let instructions =
        crate::instruction::decode_snapshot(&changed.extensions["studio.instructions"].payload)?;
    assert_eq!(
        current_instruction_records[0].content,
        vec![ContextContent::Text {
            text: instructions.trusted_text().into(),
        }]
    );
    crate::compaction::decode_instruction_binding(
        &changed.extensions["studio.instructions.binding"],
    )?;
    reopened.close().await?;
    Ok(())
}
