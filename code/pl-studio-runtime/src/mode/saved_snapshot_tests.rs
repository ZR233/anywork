//! 已保存 Mode 快照的失败关闭与图修订保留。
//!
//! 这些检查直接调用当前 Mode owner，不经过冻结的 schema-24 历史库。

use std::collections::BTreeMap;

use anyhow::{Context, Result};
use pl_core::{
    context::{ContextContent, ContextRecord, ContextSnapshot, ContextSource, OpaquePayload},
    thread::{ThreadSnapshot, extensions::ExtensionRecord},
};

use super::{ThreadModeManager, ThreadModeSource, ThreadModeSourceId};

/// 旧版实际写出的 v1 指令块：`executionProfile` 同时承载 Mode 与 child Profile 的角色正文。
fn legacy_block(kind: &str, label: &str, content: &str) -> serde_json::Value {
    serde_json::json!({
        "source": { "kind": kind, "label": label },
        "content": content,
    })
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
                .mode(&crate::mode::ThreadModeId::new("mode.migration")?)
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
