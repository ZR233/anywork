//! Saved Mode format migration and deletion recovery, through the actual SQLite checkpoint path.
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
    let migrated = store.migrate_mode_checkpoint(&legacy, &manager).await?;
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
            .migrate_mode_checkpoint(&legacy, &manager)
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
            .migrate_mode_checkpoint(&checkpoint, &manager)
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
