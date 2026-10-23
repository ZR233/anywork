//! Saved instruction snapshot migration.
//!
//! Version 1 recorded one execution-profile source for both the root Mode text and the child
//! Agent text. Recovery separates them by the saved Thread scope: a root snapshot keeps its
//! original Mode text as the Mode source, a child snapshot keeps its original Profile text as the
//! Agent source. Neither text is re-rendered from the current catalogs, so an upgraded session
//! never claims to use the newest role, and old bot sessions are not given the new channel
//! guidance. Missing or conflicting identities fail without rewriting the checkpoint.

use anyhow::{Context, Result, bail};
use pl_core::context::OpaquePayload;
use pl_core::thread::ThreadSnapshot;
use serde::Deserialize;

use crate::agent::definition::{AgentDefinitionScope, VerifiedAgentIdentity};

use super::{
    InstructionBlock, InstructionSnapshot, InstructionSource, InstructionSourceKind,
    SNAPSHOT_FORMAT, SNAPSHOT_VERSION,
};

/// Instruction snapshot version that mixed Mode and child Profile role text.
const LEGACY_SNAPSHOT_VERSION: u32 = 1;

/// Upgrades a saved instruction snapshot to the current structure.
///
/// `identity` carries the facts verified for this Thread: it supplies the identity to freeze for
/// legacy payloads and validates every payload's frozen id, scope and origin/revision combination.
/// Current payloads are never rewritten, so a session keeps the built-in revision it was created
/// with. A saved Thread without any instruction snapshot fails instead of adopting an empty or
/// default role.
pub(crate) fn migrate_saved_representation(
    state: &mut ThreadSnapshot,
    identity: &VerifiedAgentIdentity,
) -> Result<()> {
    let Some(record) = state.extensions.get_mut("studio.instructions") else {
        bail!("saved Thread has no instruction snapshot; original checkpoint preserved");
    };
    if record.payload.format() != SNAPSHOT_FORMAT {
        bail!(
            "unsupported saved instruction snapshot format {}",
            record.payload.format()
        );
    }
    match record.payload.version() {
        SNAPSHOT_VERSION => {
            let snapshot = super::decode_snapshot(&record.payload)?;
            identity.validate(&snapshot.agent)?;
            Ok(())
        }
        LEGACY_SNAPSHOT_VERSION => {
            let snapshot = upgrade_legacy_snapshot(&record.payload, identity)?;
            record.payload = super::encode_snapshot(&snapshot)?;
            Ok(())
        }
        version => bail!("unsupported saved instruction snapshot version {version}"),
    }
}

/// Returns the saved Mode instruction text of a v1 or current snapshot.
///
/// This is the only place where Mode recovery reads a payload predating the current structure;
/// the ordinary decoders reject obsolete versions. A payload without a Mode source returns
/// `None`, and the caller decides whether that Mode can be recovered at all.
pub(crate) fn saved_mode_instruction(payload: &OpaquePayload) -> Result<Option<(String, String)>> {
    if payload.format() != SNAPSHOT_FORMAT {
        bail!(
            "unsupported saved instruction snapshot format {}",
            payload.format()
        );
    }
    match payload.version() {
        SNAPSHOT_VERSION => {
            let snapshot = super::decode_snapshot(payload)?;
            Ok(snapshot
                .developer
                .iter()
                .find(|block| block.source.kind == InstructionSourceKind::ModeDefinition)
                .map(|block| (block.source.label.clone(), block.content.clone())))
        }
        LEGACY_SNAPSHOT_VERSION => {
            let legacy = decode_legacy(payload)?;
            Ok(legacy
                .developer
                .into_iter()
                .find(|block| block.source.kind == LegacySourceKind::ExecutionProfile)
                .map(|block| (block.source.label, block.content)))
        }
        version => bail!("unsupported saved instruction snapshot version {version}"),
    }
}

fn upgrade_legacy_snapshot(
    payload: &OpaquePayload,
    identity: &VerifiedAgentIdentity,
) -> Result<InstructionSnapshot> {
    let legacy = decode_legacy(payload)?;
    let role_kind = match identity.scope() {
        AgentDefinitionScope::Root => InstructionSourceKind::ModeDefinition,
        AgentDefinitionScope::Child => InstructionSourceKind::AgentDefinition,
    };
    let base_kind = legacy
        .base
        .source
        .kind
        .current()
        .context("saved instruction base has no current source")?;
    let base = into_block(legacy.base, base_kind);
    let mut role_sources = 0_usize;
    let developer = legacy
        .developer
        .into_iter()
        .map(|block| {
            let kind = match block.source.kind.current() {
                Some(kind) => kind,
                None => {
                    role_sources += 1;
                    role_kind
                }
            };
            into_block(block, kind)
        })
        .collect::<Vec<_>>();
    if role_sources != 1 {
        bail!(
            "saved instructions must contain exactly one execution-profile source; found {role_sources}"
        );
    }
    let user = legacy
        .user
        .into_iter()
        .map(|block| {
            let kind = block
                .source
                .kind
                .current()
                .context("saved instruction user context has no current source")?;
            Ok(into_block(block, kind))
        })
        .collect::<Result<Vec<_>>>()?;
    Ok(InstructionSnapshot {
        agent: identity.migrated_identity(),
        base,
        developer,
        user,
    })
}

fn into_block(block: LegacyBlock, kind: InstructionSourceKind) -> InstructionBlock {
    InstructionBlock {
        source: InstructionSource {
            kind,
            label: block.source.label,
            path: block.source.path,
        },
        content: block.content,
    }
}

fn decode_legacy(payload: &OpaquePayload) -> Result<LegacySnapshot> {
    serde_json::from_str(payload.content()).context("decode legacy instruction snapshot")
}

/// Version 1 shape; only this migration boundary reads it.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct LegacySnapshot {
    base: LegacyBlock,
    #[serde(default)]
    developer: Vec<LegacyBlock>,
    #[serde(default)]
    user: Vec<LegacyBlock>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct LegacyBlock {
    source: LegacySource,
    content: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct LegacySource {
    kind: LegacySourceKind,
    label: String,
    #[serde(default)]
    path: Option<String>,
}

#[derive(Debug, Clone, Copy, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
enum LegacySourceKind {
    BuiltInBase,
    ModelBase,
    ConfigBaseOverride,
    ProfileBaseOverride,
    /// The mixed Mode/child-Profile role source that the current structure splits apart.
    ExecutionProfile,
    DelegationPreference,
    Platform,
    ConfigDeveloper,
    ProfileDeveloper,
    Skills,
    ToolGroup,
    SubagentConstraint,
    SubagentForce,
    ConfigUser,
    ProfileUser,
    ProjectDoc,
    WorkspaceFallback,
    SkillInvocation,
    SkillSuggestions,
}

impl LegacySourceKind {
    /// Maps a legacy source that has no special handling; `None` is the mixed role source.
    fn current(self) -> Option<InstructionSourceKind> {
        Some(match self {
            Self::ExecutionProfile => return None,
            Self::DelegationPreference => InstructionSourceKind::DelegationPreference,
            Self::BuiltInBase => InstructionSourceKind::BuiltInBase,
            Self::ModelBase => InstructionSourceKind::ModelBase,
            Self::ConfigBaseOverride => InstructionSourceKind::ConfigBaseOverride,
            Self::ProfileBaseOverride => InstructionSourceKind::ProfileBaseOverride,
            Self::Platform => InstructionSourceKind::Platform,
            Self::ConfigDeveloper => InstructionSourceKind::ConfigDeveloper,
            Self::ProfileDeveloper => InstructionSourceKind::ProfileDeveloper,
            Self::Skills => InstructionSourceKind::Skills,
            Self::ToolGroup => InstructionSourceKind::ToolGroup,
            Self::SubagentConstraint => InstructionSourceKind::SubagentConstraint,
            Self::SubagentForce => InstructionSourceKind::SubagentForce,
            Self::ConfigUser => InstructionSourceKind::ConfigUser,
            Self::ProfileUser => InstructionSourceKind::ProfileUser,
            Self::ProjectDoc => InstructionSourceKind::ProjectDoc,
            Self::WorkspaceFallback => InstructionSourceKind::WorkspaceFallback,
            Self::SkillInvocation => InstructionSourceKind::SkillInvocation,
            Self::SkillSuggestions => InstructionSourceKind::SkillSuggestions,
        })
    }
}
