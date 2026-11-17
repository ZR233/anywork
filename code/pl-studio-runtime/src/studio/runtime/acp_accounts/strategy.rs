//! 供应商差异只选择领域策略；进程、SDK、认证和关闭始终走账户所有者。
use crate::{AcpAuthAction, AcpUsageState};

use crate::config::{AcpLaunch, AcpProvider, AcpServiceDefinition};

mod antigravity;

#[derive(Clone, Copy)]
pub(super) enum AcpAgentStrategy {
    Generic,
    Antigravity,
}

impl AcpAgentStrategy {
    pub(super) fn for_definition(definition: &AcpServiceDefinition) -> Self {
        match definition.launch {
            AcpLaunch::Command { .. } => Self::Generic,
            AcpLaunch::Template(AcpProvider::Antigravity) => Self::Antigravity,
        }
    }

    pub(super) fn supports_usage(self) -> bool {
        matches!(self, Self::Antigravity)
    }

    pub(super) fn action(self, action: &AcpAuthAction) -> Option<pl_acp::auth::AuthAction> {
        match (self, action) {
            (_, AcpAuthAction::Check) => Some(pl_acp::auth::AuthAction::Check),
            (Self::Antigravity, AcpAuthAction::QueryUsage) => Some(
                pl_acp::auth::AuthAction::Probe(pl_acp::auth::ProbeRequest {
                    prompt: "/usage".into(),
                    budget: std::time::Duration::from_secs(60),
                    max_bytes: 256 * 1024,
                }),
            ),
            (Self::Generic, AcpAuthAction::QueryUsage) => None,
        }
    }

    pub(super) fn report(self, report: pl_acp::auth::ProbeReport) -> Option<AcpUsageState> {
        match self {
            Self::Antigravity => Some(antigravity::map_report(report)),
            Self::Generic => None,
        }
    }
}
