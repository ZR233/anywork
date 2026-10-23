use pl_protocol::products::feed as protocol;
use super::super::feed as bridge;

impl From<protocol::project_directory::ProjectDirectoryHeader> for bridge::project_directory::BridgeProjectDirectoryHeader {
    fn from(value: protocol::project_directory::ProjectDirectoryHeader) -> Self {
        let protocol::project_directory::ProjectDirectoryHeader { source, reference } = value;
        Self { source: source.into(), reference: reference.map(Into::into) }
    }
}
impl From<protocol::agent_directory::AgentDirectoryHeader> for bridge::agent_directory::BridgeAgentDirectoryHeader {
    fn from(value: protocol::agent_directory::AgentDirectoryHeader) -> Self {
        let protocol::agent_directory::AgentDirectoryHeader { source, reference } = value;
        Self { source: source.into(), reference: reference.map(Into::into) }
    }
}
impl From<protocol::account_usage::AccountUsageHeader> for bridge::account_usage::BridgeAccountUsageHeader {
    fn from(value: protocol::account_usage::AccountUsageHeader) -> Self {
        let protocol::account_usage::AccountUsageHeader { source, reference } = value;
        Self { source: source.into(), reference: reference.map(Into::into) }
    }
}
impl From<protocol::recovery::RecoveryHeader> for bridge::recovery::BridgeRecoveryHeader {
    fn from(value: protocol::recovery::RecoveryHeader) -> Self {
        let protocol::recovery::RecoveryHeader { source, reference } = value;
        Self { source: source.into(), reference: reference.map(Into::into) }
    }
}
impl From<protocol::mcp::McpHeader> for bridge::mcp::BridgeMcpHeader {
    fn from(value: protocol::mcp::McpHeader) -> Self {
        let protocol::mcp::McpHeader { source, reference } = value;
        Self { source: source.into(), reference: reference.map(Into::into) }
    }
}
impl From<protocol::lsp::LspHeader> for bridge::lsp::BridgeLspHeader {
    fn from(value: protocol::lsp::LspHeader) -> Self {
        let protocol::lsp::LspHeader { source, reference } = value;
        Self { source: source.into(), reference: reference.map(Into::into) }
    }
}

impl From<protocol::thread_directory::ThreadDirectoryHeader> for bridge::thread_directory::BridgeThreadDirectoryHeader {
    fn from(value: protocol::thread_directory::ThreadDirectoryHeader) -> Self {
        let protocol::thread_directory::ThreadDirectoryHeader { source, reference, directory_revision,
            search_project_revision, has_more, next_cursor } = value;
        Self { source: source.into(), reference: reference.map(Into::into), directory_revision,
            search_project_revision, has_more, next_cursor: next_cursor.map(Into::into) }
    }
}
impl From<protocol::configuration::ConfigurationHeader> for bridge::configuration::BridgeConfigurationHeader {
    fn from(value: protocol::configuration::ConfigurationHeader) -> Self {
        let protocol::configuration::ConfigurationHeader { source, configuration_revision, updated_at, reference } = value;
        Self { source: source.into(), configuration_revision, updated_at, reference: reference.map(Into::into) }
    }
}
impl From<protocol::model_catalog::ModelCatalogHeader> for bridge::model_catalog::BridgeModelCatalogHeader {
    fn from(value: protocol::model_catalog::ModelCatalogHeader) -> Self {
        let protocol::model_catalog::ModelCatalogHeader { source, catalog_revision, updated_at, reference } = value;
        Self { source: source.into(), catalog_revision, updated_at, reference: reference.map(Into::into) }
    }
}
impl From<protocol::agent_profiles::AgentProfilesHeader> for bridge::agent_profiles::BridgeAgentProfilesHeader {
    fn from(value: protocol::agent_profiles::AgentProfilesHeader) -> Self {
        let protocol::agent_profiles::AgentProfilesHeader { source, profiles_revision, reference } = value;
        Self { source: source.into(), profiles_revision, reference: reference.map(Into::into) }
    }
}
impl From<protocol::skills::SkillsHeader> for bridge::skills::BridgeSkillsHeader {
    fn from(value: protocol::skills::SkillsHeader) -> Self {
        let protocol::skills::SkillsHeader { source, reference, catalog_revision, complete } = value;
        Self { source: source.into(), reference: reference.map(Into::into), catalog_revision, complete }
    }
}

impl From<protocol::account_templates::AccountTemplatesHeader> for bridge::account_templates::BridgeAccountTemplatesHeader {
    fn from(value: protocol::account_templates::AccountTemplatesHeader) -> Self {
        let protocol::account_templates::AccountTemplatesHeader { schema_version, reference } = value;
        Self { schema_version, reference: reference.into() }
    }
}
impl From<protocol::mode_catalog::ModeCatalogHeader> for bridge::mode_catalog::BridgeModeCatalogHeader {
    fn from(value: protocol::mode_catalog::ModeCatalogHeader) -> Self {
        let protocol::mode_catalog::ModeCatalogHeader { revision, reference } = value;
        Self { revision, reference: reference.into() }
    }
}

impl From<protocol::performance_summaries::PerformanceSummariesHeader> for bridge::performance_summaries::BridgePerformanceSummariesHeader {
    fn from(value: protocol::performance_summaries::PerformanceSummariesHeader) -> Self {
        let protocol::performance_summaries::PerformanceSummariesHeader { revision, updated_at, statistics_pending,
            statistics_gap, read_failed, reference } = value;
        Self { revision, updated_at, statistics_pending, statistics_gap, read_failed, reference: reference.into() }
    }
}
impl From<protocol::performance_history::PerformanceHistoryHeader> for bridge::performance_history::BridgePerformanceHistoryHeader {
    fn from(value: protocol::performance_history::PerformanceHistoryHeader) -> Self {
        let protocol::performance_history::PerformanceHistoryHeader { revision, updated_at, statistics_pending,
            statistics_gap, read_failed, reference } = value;
        Self { revision, updated_at, statistics_pending, statistics_gap, read_failed, reference: reference.into() }
    }
}
impl From<protocol::session_costs::SessionCostsHeader> for bridge::session_costs::BridgeSessionCostsHeader {
    fn from(value: protocol::session_costs::SessionCostsHeader) -> Self {
        let protocol::session_costs::SessionCostsHeader { revision, updated_at, statistics_pending,
            statistics_gap, read_failed, has_cost, has_unpriced_usage, reference } = value;
        Self { revision, updated_at, statistics_pending, statistics_gap, read_failed,
            has_cost, has_unpriced_usage, reference: reference.into() }
    }
}

impl From<protocol::persistence_queue::PersistenceQueueHeader> for bridge::persistence_queue::BridgePersistenceQueueHeader {
    fn from(value: protocol::persistence_queue::PersistenceQueueHeader) -> Self {
        let protocol::persistence_queue::PersistenceQueueHeader { reference, revision, updated_at,
            statistics_gap, pending_operations, pending_bytes, in_flight_bytes, oldest_pending_age_millis,
            pressure_paused, has_last_error } = value;
        Self { reference: reference.into(), revision, updated_at, statistics_gap, pending_operations,
            pending_bytes, in_flight_bytes, oldest_pending_age_millis, pressure_paused, has_last_error }
    }
}

impl From<protocol::persistence::PersistenceHeader> for bridge::persistence::BridgePersistenceHeader {
    fn from(value: protocol::persistence::PersistenceHeader) -> Self {
        let protocol::persistence::PersistenceHeader { reference, revision, state } = value;
        Self { reference: reference.into(), revision, state: state.into() }
    }
}
impl From<protocol::persistence::PersistenceBrief> for bridge::persistence::BridgePersistenceBrief {
    fn from(value: protocol::persistence::PersistenceBrief) -> Self {
        match value {
            protocol::persistence::PersistenceBrief::Ready { pending_commits } => Self::Ready { pending_commits },
            protocol::persistence::PersistenceBrief::Flushing { pending_commits, oldest_pending_revision } =>
                Self::Flushing { pending_commits, oldest_pending_revision },
            protocol::persistence::PersistenceBrief::Degraded { pending_commits, oldest_pending_revision, first_failed_at } =>
                Self::Degraded { pending_commits, oldest_pending_revision, first_failed_at },
            protocol::persistence::PersistenceBrief::Recovering { pending_commits, oldest_pending_revision, first_failed_at } =>
                Self::Recovering { pending_commits, oldest_pending_revision, first_failed_at },
            protocol::persistence::PersistenceBrief::Blocked { pending_commits, oldest_pending_revision, first_failed_at } =>
                Self::Blocked { pending_commits, oldest_pending_revision, first_failed_at },
        }
    }
}

impl From<protocol::updates::UpdatesHeader> for bridge::updates::BridgeUpdatesHeader {
    fn from(value: protocol::updates::UpdatesHeader) -> Self {
        let protocol::updates::UpdatesHeader { reference, brief, summary, operation, error, details } = value;
        Self { reference: reference.into(), brief: brief.into(), summary: summary.map(Into::into),
            operation: operation.map(Into::into), error: error.map(Into::into), details: details.map(Into::into) }
    }
}
impl From<protocol::updates::UpdatesBrief> for bridge::updates::BridgeUpdatesBrief {
    fn from(value: protocol::updates::UpdatesBrief) -> Self {
        match value {
            protocol::updates::UpdatesBrief::Disabled { revision, updated_at } => Self::Disabled { revision, updated_at },
            protocol::updates::UpdatesBrief::Idle { revision, updated_at } => Self::Idle { revision, updated_at },
            protocol::updates::UpdatesBrief::Checking { revision, started_at } => Self::Checking { revision, started_at },
            protocol::updates::UpdatesBrief::UpToDate { revision, checked_at } => Self::UpToDate { revision, checked_at },
            protocol::updates::UpdatesBrief::Available { revision, checked_at } => Self::Available { revision, checked_at },
            protocol::updates::UpdatesBrief::Downloading { revision, updated_at, downloaded, total } =>
                Self::Downloading { revision, updated_at, downloaded, total },
            protocol::updates::UpdatesBrief::Verifying { revision, updated_at, downloaded, total } =>
                Self::Verifying { revision, updated_at, downloaded, total },
            protocol::updates::UpdatesBrief::Ready { revision, ready_at } => Self::Ready { revision, ready_at },
            protocol::updates::UpdatesBrief::InstallerLaunched { revision, launched_at } => Self::InstallerLaunched { revision, launched_at },
            protocol::updates::UpdatesBrief::CheckFailed { revision, failed_at, retryable } => Self::CheckFailed { revision, failed_at, retryable },
            protocol::updates::UpdatesBrief::InstallFailed { revision, failed_at, retryable } => Self::InstallFailed { revision, failed_at, retryable },
        }
    }
}
