//! Runtime 关闭报告及其原诊断桥接。

use crate::api::studio::types::*;
use pl_studio_runtime::*;

/// Converts the runtime shutdown report into its FRB mirror without reinterpreting success.
pub(crate) fn bridge_shutdown_report(report: StudioShutdownReport) -> BridgeShutdownReport {
    BridgeShutdownReport {
        outcome: match report.outcome {
            StudioShutdownOutcome::NotStarted => BridgeShutdownOutcome::NotStarted,
            StudioShutdownOutcome::Clean => BridgeShutdownOutcome::Clean,
            StudioShutdownOutcome::Degraded => BridgeShutdownOutcome::Degraded,
        },
        issues: report
            .issues
            .into_iter()
            .map(|issue| BridgeShutdownIssue {
                stage: issue.stage,
                code: issue.code,
                message: issue.message,
                retryable: issue.retryable,
                correlation_id: issue.correlation_id,
            })
            .collect(),
        persistence: match report.persistence {
            StudioPendingPersistence::Unknown => BridgePendingPersistence::Unknown,
            StudioPendingPersistence::Pending { count } => {
                BridgePendingPersistence::Pending { count }
            }
            StudioPendingPersistence::Drained => BridgePendingPersistence::Drained,
        },
    }
}

/// Converts one bridge-side shutdown issue into the runtime protocol shape.
///
/// The two shapes are identical; the conversion only crosses the crate boundary so the bridge's
/// already-observed failures can seed the same runtime orchestration (single coordinator, no
/// post-hoc merge or second shutdown source of truth).
pub(crate) fn runtime_shutdown_issue(issue: BridgeShutdownIssue) -> StudioShutdownIssue {
    StudioShutdownIssue {
        stage: issue.stage,
        code: issue.code,
        message: issue.message,
        retryable: issue.retryable,
        correlation_id: issue.correlation_id,
    }
}
