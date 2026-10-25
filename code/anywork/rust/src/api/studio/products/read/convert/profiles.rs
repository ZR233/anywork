//! Mechanical field moves only; raw text, None and Some("") remain distinct.
use super::super::profile_values::*;
use pl_protocol::products::read::agent_profiles as protocol;
impl From<protocol::AgentProfilesReadHeader> for BridgeAgentProfilesReadHeader {
    fn from(value: protocol::AgentProfilesReadHeader) -> Self {
        Self {
            profiles: value.profiles.into(),
            diagnostics: value.diagnostics.into(),
        }
    }
}
impl From<protocol::AgentProfileRead> for BridgeAgentProfileRead {
    fn from(value: protocol::AgentProfileRead) -> Self {
        Self {
            profile_id: value.profile_id.into(),
            display_name: value.display_name.into(),
            description: value.description.into(),
            when_to_use: value.when_to_use.into(),
            system_instructions: value.system_instructions.into(),
            account_id: value.account_id.into(),
            model_id: value.model_id.into(),
            effort: value.effort.map(Into::into),
            source: value.source.into(),
            revision: value.revision.into(),
            content_hash: value.content_hash.into(),
            system: value.system,
            enabled: value.enabled,
            workspace_mode: value.workspace_mode.into(),
        }
    }
}
impl From<protocol::ProfileDiagnosticRead> for BridgeProfileDiagnosticRead {
    fn from(value: protocol::ProfileDiagnosticRead) -> Self {
        Self {
            path: value.path.into(),
            message: value.message.into(),
        }
    }
}
impl From<protocol::AgentProfilesEntryPage> for BridgeAgentProfilesEntryPage {
    fn from(value: protocol::AgentProfilesEntryPage) -> Self {
        Self {
            collection: value.collection.into(),
            offset: value.offset,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}
impl From<protocol::AgentProfilesEntityRead> for BridgeAgentProfilesEntityRead {
    fn from(value: protocol::AgentProfilesEntityRead) -> Self {
        Self {
            reference: value.reference.into(),
            value: value.value.into(),
        }
    }
}
impl From<protocol::AgentProfileReadPage> for BridgeAgentProfileReadPage {
    fn from(value: protocol::AgentProfileReadPage) -> Self {
        Self {
            list_id: value.list_id,
            offset: value.offset,
            total: value.total,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}
impl From<protocol::ProfileDiagnosticReadPage> for BridgeProfileDiagnosticReadPage {
    fn from(value: protocol::ProfileDiagnosticReadPage) -> Self {
        Self {
            list_id: value.list_id,
            offset: value.offset,
            total: value.total,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}
