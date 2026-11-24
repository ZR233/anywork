//! 当前指令快照的身份与结构校验。
//!
//! 这些检查直接调用指令 owner 的编码、解码和已保存表示迁移，不打开历史库。

use std::collections::BTreeMap;

use anyhow::Result;
use pl_core::{
    context::{ContextContent, ContextRecord, ContextSnapshot, ContextSource, OpaquePayload},
    thread::{ThreadSnapshot, extensions::ExtensionRecord},
};

use crate::agent::definition::{
    AgentDefinitionOrigin, AgentDefinitionScope, VerifiedAgentIdentity,
};

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

fn instruction_state(payload: OpaquePayload) -> ThreadSnapshot {
    saved_state(BTreeMap::from([(
        "studio.instructions".into(),
        ExtensionRecord {
            revision: 3,
            payload,
        },
    )]))
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

fn current_instruction_state(
    agent: crate::agent::definition::AgentDefinitionIdentity,
) -> Result<ThreadSnapshot> {
    Ok(instruction_state(snapshot_payload(&compliant_snapshot(
        agent,
    ))?))
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

/// 缺少指令事实时失败闭锁：不清空已有上下文，也不补默认指令正文。
#[test]
fn missing_instruction_snapshot_fails_without_rewriting_or_defaulting() -> Result<()> {
    let mut state = saved_state(BTreeMap::new());
    let before = serde_json::to_vec(&state)?;
    assert!(
        crate::instruction::migrate_saved_representation(
            &mut state,
            &VerifiedAgentIdentity::GenericRoot,
        )
        .is_err(),
        "缺必需指令身份不能通过"
    );
    assert_eq!(serde_json::to_vec(&state)?, before);
    assert!(!state.extensions.contains_key("studio.instructions"));
    assert_eq!(
        state.context.records[0].id.as_str(),
        "preserved-user-history"
    );
    Ok(())
}
