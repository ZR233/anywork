//! Structural validation shared by the snapshot codec and the recovery migration.
//!
//! One source of truth for which role sources a snapshot may carry. The frozen identity decides
//! the expected shape: a root owns exactly one Mode source, a child owns exactly one Agent source
//! and no Mode source, and the built-in bot definition owns one Agent source while the generic
//! built-in and migrated roots carry none. Duplicates, a role source in the wrong region base/user
//! or an empty role block are rejected instead of being projected as defaults.

use pl_protocol::PureError;

use super::{InstructionBlock, InstructionSnapshot, InstructionSourceKind};
use crate::agent::definition::{AgentDefinitionOrigin, AgentDefinitionScope, FEISHU_ROOT_ID};

pub(super) fn validate(snapshot: &InstructionSnapshot) -> Result<(), PureError> {
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
    let agents = role_blocks(snapshot, InstructionSourceKind::AgentDefinition)?;
    let modes = role_blocks(snapshot, InstructionSourceKind::ModeDefinition)?;
    match snapshot.agent.scope {
        AgentDefinitionScope::Root => {
            if modes.len() != 1 {
                return Err(invalid(
                    "a root snapshot must contain exactly one Mode source",
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
                    "the Agent sources do not match the frozen root identity",
                ));
            }
        }
        AgentDefinitionScope::Child => {
            if !modes.is_empty() {
                return Err(invalid("a child snapshot cannot carry a Mode source"));
            }
            if agents.len() != 1 {
                return Err(invalid(
                    "a child snapshot must contain exactly one Agent source",
                ));
            }
        }
    }
    Ok(())
}

fn role_blocks(
    snapshot: &InstructionSnapshot,
    kind: InstructionSourceKind,
) -> Result<Vec<&InstructionBlock>, PureError> {
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
