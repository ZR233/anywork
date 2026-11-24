use crate::{PureError, Result};
use pl_core::context::OpaquePayload;

use super::{
    AgentInstructionShape, InstructionBlock, InstructionSnapshot, InstructionSourceKind,
    SNAPSHOT_FORMAT, SNAPSHOT_VERSION,
};
use crate::agent::definition::{
    AgentDefinitionOrigin, AgentDefinitionScope, AgentUsageBinding, FEISHU_ROOT_ID,
    usage_binding_matches_scope,
};

/// Decodes the current instruction snapshot.
///
/// Obsolete versions are rejected here; only the recovery migration interprets them, so normal
/// model preparation never runs two decoders for the same source of truth. The decoded snapshot
/// must also have the structure its frozen identity implies.
pub(crate) fn decode_snapshot(payload: &OpaquePayload) -> Result<InstructionSnapshot> {
    if payload.format() != SNAPSHOT_FORMAT || payload.version() != SNAPSHOT_VERSION {
        return Err(PureError::ConfigError(format!(
            "unsupported saved instruction snapshot {} version {}; recovery migration required",
            payload.format(),
            payload.version()
        )));
    }
    let snapshot: InstructionSnapshot =
        serde_json::from_str(payload.content()).map_err(|error| {
            PureError::ConfigError(format!("decode saved instruction snapshot: {error}"))
        })?;
    validate(&snapshot)?;
    Ok(snapshot)
}

/// Encodes the current instruction snapshot; the format, version and structure stay owned here.
pub(crate) fn encode_snapshot(snapshot: &InstructionSnapshot) -> Result<OpaquePayload> {
    validate(snapshot)?;
    let content = serde_json::to_string(snapshot)
        .map_err(|error| PureError::ConfigError(format!("encode instruction snapshot: {error}")))?;
    OpaquePayload::new(SNAPSHOT_FORMAT, SNAPSHOT_VERSION, content)
        .map_err(|error| PureError::ConfigError(error.to_string()))
}

/// Structural validation shared by the snapshot codec and the recovery migration.
///
/// Current snapshots freeze the Agent-source shape, content hash, usage binding and scope. A new
/// root or child owns one Agent source; roots also own exactly one Mode source, while children have
/// no Mode source. The sole Agent-less root shape is preserved historical state, represented
/// explicitly in the frozen shape and accepted only for migration/legacy usage bindings.
/// At the v2 migration boundary, the saved root ID and v2 Agent-block shape are validated before
/// deriving this representation. Version 1 had no independent Agent ID: migration derives its
/// identity from verified Thread facts and preserves the execution-profile body. Duplicates, role
/// sources in the wrong region, and empty role blocks fail closed instead of being projected as
/// defaults.
pub(super) fn validate(snapshot: &InstructionSnapshot) -> Result<()> {
    if !usage_binding_matches_scope(&snapshot.agent) {
        return Err(invalid(
            "the frozen Agent usage binding does not match its allowed scope",
        ));
    }
    reject_misplaced_role_sources(snapshot)?;
    let agents = role_blocks(snapshot, InstructionSourceKind::AgentDefinition)?;
    let modes = role_blocks(snapshot, InstructionSourceKind::ModeDefinition)?;
    match (&snapshot.agent.scope, &snapshot.agent_shape) {
        (AgentDefinitionScope::Root, AgentInstructionShape::Present { content_hash }) => {
            if snapshot.agent.origin != AgentDefinitionOrigin::Builtin {
                return Err(invalid(
                    "a root Agent instruction must have a builtin identity",
                ));
            }
            validate_agent_hash(&agents, content_hash)?;
        }
        (AgentDefinitionScope::Root, AgentInstructionShape::Absent) => {
            let preserved_legacy_context = snapshot.agent.origin == AgentDefinitionOrigin::Migrated
                || matches!(
                    &snapshot.agent.usage_binding,
                    AgentUsageBinding::LegacyUnspecifiedRoot { .. }
                );
            if !preserved_legacy_context || !agents.is_empty() {
                return Err(invalid(
                    "an Agent-less root must preserve a migrated or channel-unspecified snapshot",
                ));
            }
        }
        (AgentDefinitionScope::Child, AgentInstructionShape::Present { content_hash }) => {
            validate_agent_hash(&agents, content_hash)?;
        }
        (AgentDefinitionScope::Child, AgentInstructionShape::Absent) => {
            return Err(invalid(
                "a child snapshot must freeze one Agent instruction",
            ));
        }
    }
    match snapshot.agent.scope {
        AgentDefinitionScope::Root => {
            if modes.len() != 1 {
                return Err(invalid(
                    "a root snapshot must contain exactly one Mode source",
                ));
            }
        }
        AgentDefinitionScope::Child => {
            if !modes.is_empty() {
                return Err(invalid("a child snapshot cannot carry a Mode source"));
            }
        }
    }
    Ok(())
}

/// Version-2 shape validation is migration-only: validate the old root-ID rule before deriving
/// the generic Agent block shape carried by the current representation.
pub(super) fn validate_v2(snapshot: &InstructionSnapshot) -> Result<()> {
    reject_misplaced_role_sources(snapshot)?;
    let agents = role_blocks(snapshot, InstructionSourceKind::AgentDefinition)?;
    let modes = role_blocks(snapshot, InstructionSourceKind::ModeDefinition)?;
    match snapshot.agent.scope {
        AgentDefinitionScope::Root => {
            if modes.len() != 1 {
                return Err(invalid(
                    "a version-2 root snapshot must contain exactly one Mode source",
                ));
            }
            let expected_agents = match snapshot.agent.origin {
                AgentDefinitionOrigin::Builtin if snapshot.agent.id == FEISHU_ROOT_ID => 1,
                AgentDefinitionOrigin::Builtin | AgentDefinitionOrigin::Migrated => 0,
                AgentDefinitionOrigin::Profile => {
                    return Err(invalid("a root identity cannot come from a Profile"));
                }
            };
            if agents.len() != expected_agents {
                return Err(invalid(
                    "the version-2 Agent sources do not match the frozen root identity",
                ));
            }
        }
        AgentDefinitionScope::Child => {
            if !modes.is_empty() {
                return Err(invalid("a child snapshot cannot carry a Mode source"));
            }
            if agents.len() != 1 {
                return Err(invalid(
                    "a version-2 child snapshot must contain exactly one Agent source",
                ));
            }
        }
    }
    Ok(())
}

fn reject_misplaced_role_sources(snapshot: &InstructionSnapshot) -> Result<()> {
    if is_role_source(snapshot.base.source.kind) {
        return Err(invalid("base instructions cannot carry a role source"));
    }
    if snapshot
        .user
        .iter()
        .any(|block| is_role_source(block.source.kind))
    {
        return Err(invalid("user context cannot carry a role source"));
    }
    Ok(())
}

fn validate_agent_hash(blocks: &[&InstructionBlock], expected_hash: &str) -> Result<()> {
    if expected_hash.trim().is_empty() || blocks.len() != 1 {
        return Err(invalid(
            "the frozen Agent content identity is missing or ambiguous",
        ));
    }
    let actual = pl_core::context::content_hash(blocks[0].content.as_bytes());
    if actual != expected_hash {
        return Err(invalid(
            "the Agent source disagrees with its frozen content identity",
        ));
    }
    Ok(())
}

fn role_blocks(
    snapshot: &InstructionSnapshot,
    kind: InstructionSourceKind,
) -> Result<Vec<&InstructionBlock>> {
    let blocks = snapshot
        .developer
        .iter()
        .filter(|block| block.source.kind == kind)
        .collect::<Vec<_>>();
    for block in &blocks {
        if block.source.label.trim().is_empty() || block.content.trim().is_empty() {
            return Err(invalid("a role source must have a label and a body"));
        }
    }
    Ok(blocks)
}

fn is_role_source(kind: InstructionSourceKind) -> bool {
    matches!(
        kind,
        InstructionSourceKind::AgentDefinition | InstructionSourceKind::ModeDefinition
    )
}

fn invalid(reason: &str) -> PureError {
    PureError::ConfigError(format!("invalid saved instruction snapshot: {reason}"))
}
