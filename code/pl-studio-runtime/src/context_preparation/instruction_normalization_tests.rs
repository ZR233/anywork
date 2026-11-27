//! 多条 v2 指令记录由生产 ContextPreparer 折叠一次。
//!
//! 恢复输入直接使用当前 checkpoint 捕获，不经过冻结 schema-24 历史库。

use std::collections::BTreeMap;

use anyhow::{Context, Result};
use pl_core::{
    context::{ContextContent, ContextRecord, ContextSnapshot, ContextSource, OpaquePayload},
    thread::{
        ThreadSnapshot,
        current::{RuntimeEpoch, ThreadCurrent, ThreadCurrentState},
        extensions::ExtensionRecord,
    },
};

use crate::agent::definition::{AgentDefinitionOrigin, AgentDefinitionScope};
use crate::mode::ThreadModeManager;

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

fn snapshot_payload(snapshot: &crate::instruction::InstructionSnapshot) -> Result<OpaquePayload> {
    Ok(crate::instruction::encode_snapshot(snapshot)?)
}

/// A v2 checkpoint written before trusted instructions were folded into one record must be
/// normalized by the production ContextPreparer, then remain unchanged on the next preparation.
#[tokio::test]
async fn restored_v2_multi_record_instructions_are_normalized_once() -> Result<()> {
    use crate::instruction::{InstructionSnapshot, InstructionSourceKind};
    use pl_core::{model::ModelFactory, thread::ThreadHandle};
    use pl_model::{
        completion::OpenAiCompactionMode,
        config::{AccountId, ResolvedModelRoute},
        model::ModelDefinition,
        runtime::ThreadModel,
    };
    use std::sync::Arc;

    let manager = ThreadModeManager::default();
    let registry = crate::studio::thread::register_builtins(&manager)?;
    let mode = registry
        .mode(&crate::mode::ThreadModeId::auto())
        .context("built-in auto Mode")?;
    let mut model_info = ModelDefinition::compatible("migration-model");
    model_info.base.model_messages.instructions_template = "frozen migration base".into();
    let endpoint = pl_model::protocol::providers::openai::compatible_endpoint(
        "migration fixture",
        "http://127.0.0.1:0",
    );
    let route = ResolvedModelRoute {
        pricing_mode: Default::default(),
        role: crate::config::root_agent_route_id(),
        account_id: AccountId::new("migration-account")?,
        endpoint,
        context: model_info
            .resolve_context(None, pl_model::model::AutoCompactDefaultPolicy::Bundled),
        model: model_info,
        effort: None,
        service_tier: None,
    };
    let model = ThreadModel::new(pl_model::runtime::from_route(&route)?, None);
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
            tool_data: Default::default(),
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
            tool_data: Default::default(),
            id: "preserved-user-history".into(),
            turn_id: None,
            source: ContextSource::User,
            content: vec![ContextContent::Text {
                text: "Keep this historical user fact.".into(),
            }],
            tool_calls: Vec::new(),
        },
        ContextRecord {
            tool_data: Default::default(),
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
            tool_data: Default::default(),
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

    let epoch = RuntimeEpoch::new();
    let mut current = ThreadCurrent::new("migration".into(), epoch);
    current.state = ThreadCurrentState::from_snapshot(&original, epoch)?;
    let thread = ThreadHandle::restore_current(
        current,
        Some(ModelFactory::new(model.clone()).open_session().await?),
    )?;
    thread
        .set_context_preparation(Some(crate::context_preparation::preparer(
            &route,
            model,
            OpenAiCompactionMode::Local,
            manager,
            &Default::default(),
        )))
        .await?;

    assert!(
        thread
            .resume_current(
                "restore-instructions".into(),
                pl_core::thread::ModelStepLimit::Limited(std::num::NonZeroU32::new(1).unwrap()),
                Default::default(),
            )
            .await
            .is_err()
    );
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
            content_hash.as_str(),
            pl_core::context::content_hash(snapshot.trusted_text().as_bytes()).as_str()
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

    assert!(
        thread
            .resume_current(
                "prepare-again".into(),
                pl_core::thread::ModelStepLimit::Limited(std::num::NonZeroU32::new(1).unwrap()),
                Default::default(),
            )
            .await
            .is_err()
    );
    assert_eq!(thread.snapshot().context, normalized);
    thread.close().await?;
    Ok(())
}
