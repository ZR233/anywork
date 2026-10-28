//! Frozen Thread ownership for local bot audience queries. No global binding scan is a fallback.

use anyhow::{Result, ensure};
use pl_core::thread::ThreadSnapshot;
use pl_protocol::{Thread, ThreadAudienceUnavailableReason};

use crate::agent::definition::{
    AgentRootEntry, FEISHU_ROOT_ID, ResolvedAgentDefinition, STUDIO_ROOT_ID, VerifiedAgentIdentity,
};

/// A single frozen bot owner, validated against the Thread's frozen channel/Agent identity.
/// The bot still has to prove that all current and historical target rows agree on one chat.
pub(crate) struct VerifiedBotAudienceOwner {
    bot_id: String,
}

/// Local input readiness derived from the original bot creation/authorization facts.
/// Ready does not authorize platform input or output; failed proof remains a read error.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum BotThreadInputReadiness {
    Ready,
    Preparing,
}

/// Latest-only invalidation for one managed bot; not a binding or delivery CAS identity.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct BotAudienceWatchVersion {
    pub owner_epoch: String,
    pub version: u64,
}

impl VerifiedBotAudienceOwner {
    pub(crate) fn bot_id(&self) -> &str {
        &self.bot_id
    }
}

pub(crate) enum ThreadAudienceOwner {
    Unbound,
    Bot(VerifiedBotAudienceOwner),
    Unavailable(ThreadAudienceUnavailableReason),
}

pub(crate) fn supports_public_frontend(state: &ThreadSnapshot) -> Result<bool> {
    let Some(record) = state.extensions.get("studio.instructions") else {
        return Ok(false);
    };
    let frozen = crate::instruction::decode_snapshot(&record.payload)?;
    let supported = ResolvedAgentDefinition::root(AgentRootEntry::Bot)?;
    let identity = supported.identity();
    // The catalog revision also covers labels and metadata. Publication eligibility depends on
    // the trusted root binding and exact frozen role body, not a second numeric revision scheme.
    // decode_snapshot already checked this digest against the unique frozen Agent source.
    Ok(frozen.agent.id == identity.id
        && frozen.agent.scope == identity.scope
        && frozen.agent.origin == identity.origin
        && frozen.agent.usage_binding == identity.usage_binding
        && frozen.agent_shape
            == crate::instruction::AgentInstructionShape::Present {
                content_hash: pl_core::context::content_hash(supported.instructions().as_bytes()),
            })
}

/// This consumes only already-read local facts. Missing ownership is not proof of a normal Thread,
/// and a child must carry its own frozen Profile rather than inheriting a root's bot identity.
pub(crate) fn frozen_owner(thread: &Thread, state: &ThreadSnapshot) -> Result<ThreadAudienceOwner> {
    let bot_id = super::model_route::verified_bot_owner(None, Some(state))?;
    let Some(instructions) = state.extensions.get("studio.instructions") else {
        return Ok(ThreadAudienceOwner::Unavailable(
            ThreadAudienceUnavailableReason::OwnershipUnproven,
        ));
    };
    let frozen = crate::instruction::decode_snapshot(&instructions.payload)?;
    if thread.parent_thread_id.is_some() {
        ensure!(
            bot_id.is_none(),
            "child carries a conflicting root bot ownership"
        );
        let Some((profile, _)) = super::model_route::saved_profile(state)? else {
            return Ok(ThreadAudienceOwner::Unavailable(
                ThreadAudienceUnavailableReason::OwnershipUnproven,
            ));
        };
        VerifiedAgentIdentity::child(&profile)?.validate(&frozen.agent)?;
        return Ok(ThreadAudienceOwner::Unbound);
    }
    ensure!(
        thread.root_thread_id == thread.id,
        "root Thread identity is inconsistent"
    );
    match bot_id {
        Some(bot_id) => {
            VerifiedAgentIdentity::BotRoot.validate(&frozen.agent)?;
            ensure!(
                frozen.agent.id == FEISHU_ROOT_ID,
                "bot Thread channel is inconsistent"
            );
            Ok(ThreadAudienceOwner::Bot(VerifiedBotAudienceOwner {
                bot_id,
            }))
        }
        None if frozen.agent.id == STUDIO_ROOT_ID => {
            VerifiedAgentIdentity::GenericRoot.validate(&frozen.agent)?;
            Ok(ThreadAudienceOwner::Unbound)
        }
        None => Ok(ThreadAudienceOwner::Unavailable(
            ThreadAudienceUnavailableReason::OwnershipUnproven,
        )),
    }
}
