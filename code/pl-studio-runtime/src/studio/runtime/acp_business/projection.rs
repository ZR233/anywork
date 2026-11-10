use pl_acp::session as sdk;
use pl_protocol::studio::*;

pub(super) fn failure(error: sdk::Error) -> AcpBusinessFailure {
    let kind = match &error {
        sdk::Error::Busy => AcpBusinessFailureKind::Busy,
        sdk::Error::Stale => AcpBusinessFailureKind::Stale,
        sdk::Error::NotReady => AcpBusinessFailureKind::NotReady,
        sdk::Error::Closed => AcpBusinessFailureKind::Closed,
        sdk::Error::Unsupported => AcpBusinessFailureKind::Unsupported,
        sdk::Error::UnsupportedVersion => AcpBusinessFailureKind::UnsupportedVersion,
        sdk::Error::ServerVersionMismatch => AcpBusinessFailureKind::ServerVersionMismatch,
        sdk::Error::InvalidOption => AcpBusinessFailureKind::InvalidOption,
        sdk::Error::Rpc(_) => AcpBusinessFailureKind::Rpc,
    };
    let message = error.to_string();
    let (rpc_code, rpc_data, message) = match error {
        sdk::Error::Rpc(error) => (
            Some(i32::from(error.code)),
            error.data.map(Box::new),
            error.message,
        ),
        _ => (None, None, message),
    };
    AcpBusinessFailure {
        kind,
        rpc_code,
        rpc_data,
        message,
        auth_methods: Vec::new(),
    }
}

pub(super) fn preparation(message: &str) -> AcpBusinessFailure {
    AcpBusinessFailure {
        kind: AcpBusinessFailureKind::Preparation,
        rpc_code: None,
        rpc_data: None,
        message: message.into(),
        auth_methods: Vec::new(),
    }
}

pub(super) fn launch_failure(
    error: super::super::acp_launch::AcpLaunchError,
) -> AcpBusinessFailure {
    use super::super::{acp_install::PrepareFailure, acp_launch::AcpLaunchError};
    use AcpBusinessFailureKind as Kind;
    let (kind, message) = match error {
        AcpLaunchError::Template(PrepareFailure::PreparationRequired) => {
            (Kind::InstallRequired, "ACP installation is required")
        }
        AcpLaunchError::Template(PrepareFailure::InstallationInvalid) => {
            (Kind::InstallationInvalid, "ACP installation is invalid")
        }
        AcpLaunchError::Template(PrepareFailure::UnsupportedPlatform) => (
            Kind::UnsupportedPlatform,
            "ACP installation does not support this platform",
        ),
        AcpLaunchError::Template(PrepareFailure::Io) => {
            (Kind::Io, "ACP installation verification failed")
        }
        AcpLaunchError::Template(PrepareFailure::Cancelled) | AcpLaunchError::Cancelled => {
            (Kind::Cancelled, "ACP launch was cancelled")
        }
        AcpLaunchError::MissingExecutable => {
            (Kind::MissingExecutable, "ACP executable was not found")
        }
        AcpLaunchError::InvalidWorkingDirectory => (
            Kind::InvalidWorkingDirectory,
            "ACP working directory is invalid",
        ),
        AcpLaunchError::InvalidDefinition => (Kind::InvalidDefinition, "ACP definition is invalid"),
    };
    AcpBusinessFailure {
        kind,
        message: message.into(),
        rpc_code: None,
        rpc_data: None,
        auth_methods: Vec::new(),
    }
}

pub(super) fn run(run: sdk::RunId) -> AcpRunId {
    AcpRunId {
        instance: run.instance,
        sequence: run.sequence,
    }
}
pub(super) fn completed(completed: sdk::Completed) -> AcpCompletedRun {
    AcpCompletedRun {
        run: run(completed.run),
        completion_sequence: completed.completion_sequence,
        result: completed
            .result
            .map_err(|error| failure(sdk::Error::Rpc(error))),
        summary: completed.summary,
        truncated: completed.truncated,
    }
}
pub(super) fn gap(gap: sdk::Gap) -> AcpObservationGap {
    match gap {
        sdk::Gap::WindowExceeded => AcpObservationGap::WindowExceeded,
        sdk::Gap::Disconnected => AcpObservationGap::Disconnected,
        sdk::Gap::Encoding => AcpObservationGap::Encoding,
    }
}
pub(super) fn methods(methods: Vec<pl_acp::auth::AuthMethod>) -> Vec<AcpAuthMethod> {
    methods
        .into_iter()
        .map(|method| AcpAuthMethod {
            id: method.id,
            name: method.name,
            description: method.description,
            kind: match method.kind {
                pl_acp::auth::AuthMethodKind::Agent => AcpAuthMethodKind::Agent,
                pl_acp::auth::AuthMethodKind::Terminal => AcpAuthMethodKind::Terminal,
                pl_acp::auth::AuthMethodKind::Unsupported => AcpAuthMethodKind::Unsupported,
            },
        })
        .collect()
}

pub(super) fn snapshot(target: AcpSessionTarget, snapshot: sdk::Snapshot) -> AcpBusinessSnapshot {
    AcpBusinessSnapshot {
        target,
        acp_session_id: snapshot.session_id.map(|id| id.to_string()),
        ready: snapshot.ready,
        closing: snapshot.closing,
        config_pending: snapshot.config_pending,
        config_options: snapshot.config_options,
        modes: snapshot.modes,
        active_run: snapshot.active_run.map(run),
        last_completed: snapshot.last_completed.map(completed),
        observation_gap: snapshot.observation_gap.map(gap),
        auth_methods: methods(snapshot.auth_methods),
    }
}

pub(super) fn close(outcome: super::AcpCloseOutcome) -> AcpBusinessClose {
    let exit = outcome.exit;
    AcpBusinessClose {
        local_complete: outcome.local_complete,
        sdk_finished: exit.as_ref().is_some_and(|exit| exit.sdk_finished),
        cleanup_timed_out: exit.as_ref().is_some_and(|exit| exit.cleanup_timed_out),
        remote_close_error: exit
            .as_ref()
            .and_then(|exit| exit.close_error.clone())
            .map(failure),
        sdk_error: exit
            .as_ref()
            .and_then(|exit| exit.sdk_error.clone())
            .map(|error| failure(sdk::Error::Rpc(error))),
        worker_error: outcome.worker_error,
        driver_error: outcome.driver_error,
        unfinished_prompt: exit
            .as_ref()
            .and_then(|exit| exit.unfinished_prompt)
            .map(run),
        unfinished_controls: exit.as_ref().is_some_and(|exit| exit.unfinished_controls),
        last_completed: exit.and_then(|exit| exit.last_completed).map(completed),
        owner_failures: Vec::new(),
    }
}
