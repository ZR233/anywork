//! Literal typed conversion; official constructors build inputs, no payload JSON parser.
mod config;
pub(crate) mod content;
mod json;
mod notification;
#[cfg(test)]
mod tests;

use crate::api::studio::types::*;
pub(crate) use config::{protocol_config_value, protocol_list};
pub(crate) use content::{content, protocol_content};
use pl_protocol::studio::{self as p, acp_schema as s};
pub(crate) type R<T> = Result<T, BridgeAcpBusinessError>;

pub(super) fn unsupported(name: &str) -> BridgeAcpBusinessError {
    BridgeAcpBusinessError::Unsupported {
        type_name: name.to_owned(),
    }
}
pub(super) fn many<T, U>(values: Vec<T>, f: impl FnMut(T) -> R<U>) -> R<Vec<U>> {
    values.into_iter().map(f).collect()
}
pub(super) fn path(value: std::path::PathBuf) -> R<String> {
    value
        .into_os_string()
        .into_string()
        .map_err(|_| unsupported("non-Unicode ACP path"))
}
impl From<BridgeAcpSessionTarget> for p::AcpSessionTarget {
    fn from(v: BridgeAcpSessionTarget) -> Self {
        Self {
            session_id: v.session_id,
            agent_id: v.agent_id,
            thread_id: v.thread_id,
            instance: v.instance,
        }
    }
}
impl From<p::AcpSessionTarget> for BridgeAcpSessionTarget {
    fn from(v: p::AcpSessionTarget) -> Self {
        Self {
            session_id: v.session_id,
            agent_id: v.agent_id,
            thread_id: v.thread_id,
            instance: v.instance,
        }
    }
}
impl From<BridgeAcpRunId> for p::AcpRunId {
    fn from(v: BridgeAcpRunId) -> Self {
        Self {
            instance: v.instance,
            sequence: v.sequence,
        }
    }
}
impl From<p::AcpRunId> for BridgeAcpRunId {
    fn from(v: p::AcpRunId) -> Self {
        Self {
            instance: v.instance,
            sequence: v.sequence,
        }
    }
}
impl From<BridgeAcpPermissionId> for p::AcpPermissionId {
    fn from(v: BridgeAcpPermissionId) -> Self {
        Self {
            instance: v.instance,
            sequence: v.sequence,
        }
    }
}
impl From<BridgeOpenAcpSessionRequest> for p::OpenAcpSessionRequest {
    fn from(v: BridgeOpenAcpSessionRequest) -> Self {
        Self {
            account_id: v.account_id,
            expected_connection_revision: v.expected_connection_revision,
            workspace_id: v.workspace_id,
            thread_id: v.thread_id,
            intent: match v.intent {
                BridgeAcpOpenIntent::New => p::AcpOpenIntent::New,
                BridgeAcpOpenIntent::Load { session_id } => {
                    p::AcpOpenIntent::Load(session_id.value)
                }
                BridgeAcpOpenIntent::Resume { session_id } => {
                    p::AcpOpenIntent::Resume(session_id.value)
                }
            },
        }
    }
}
pub(crate) fn failure(v: p::AcpBusinessFailure) -> R<BridgeAcpBusinessFailure> {
    Ok(BridgeAcpBusinessFailure {
        kind: match v.kind {
            p::AcpBusinessFailureKind::Busy => BridgeAcpBusinessFailureKind::Busy,
            p::AcpBusinessFailureKind::Stale => BridgeAcpBusinessFailureKind::Stale,
            p::AcpBusinessFailureKind::NotReady => BridgeAcpBusinessFailureKind::NotReady,
            p::AcpBusinessFailureKind::Closed => BridgeAcpBusinessFailureKind::Closed,
            p::AcpBusinessFailureKind::Unsupported => BridgeAcpBusinessFailureKind::Unsupported,
            p::AcpBusinessFailureKind::UnsupportedVersion => {
                BridgeAcpBusinessFailureKind::UnsupportedVersion
            }
            p::AcpBusinessFailureKind::ServerVersionMismatch => {
                BridgeAcpBusinessFailureKind::ServerVersionMismatch
            }
            p::AcpBusinessFailureKind::InvalidOption => BridgeAcpBusinessFailureKind::InvalidOption,
            p::AcpBusinessFailureKind::Rpc => BridgeAcpBusinessFailureKind::Rpc,
            p::AcpBusinessFailureKind::InstallRequired => {
                BridgeAcpBusinessFailureKind::InstallRequired
            }
            p::AcpBusinessFailureKind::InstallationInvalid => {
                BridgeAcpBusinessFailureKind::InstallationInvalid
            }
            p::AcpBusinessFailureKind::UnsupportedPlatform => {
                BridgeAcpBusinessFailureKind::UnsupportedPlatform
            }
            p::AcpBusinessFailureKind::MissingExecutable => {
                BridgeAcpBusinessFailureKind::MissingExecutable
            }
            p::AcpBusinessFailureKind::InvalidWorkingDirectory => {
                BridgeAcpBusinessFailureKind::InvalidWorkingDirectory
            }
            p::AcpBusinessFailureKind::InvalidDefinition => {
                BridgeAcpBusinessFailureKind::InvalidDefinition
            }
            p::AcpBusinessFailureKind::Io => BridgeAcpBusinessFailureKind::Io,
            p::AcpBusinessFailureKind::Cancelled => BridgeAcpBusinessFailureKind::Cancelled,
            p::AcpBusinessFailureKind::Preparation => BridgeAcpBusinessFailureKind::Preparation,
            p::AcpBusinessFailureKind::Publication => BridgeAcpBusinessFailureKind::Publication,
        },
        rpc_code: v.rpc_code,
        message: v.message,
        rpc_data: v.rpc_data.map(|v| json::json(*v)).transpose()?,
        auth_methods: v
            .auth_methods
            .into_iter()
            .map(super::acp::bridge_acp_auth_method)
            .collect(),
    })
}
pub(crate) fn business_error(v: p::AcpBusinessFailure) -> BridgeAcpBusinessError {
    match failure(v) {
        Ok(value) => BridgeAcpBusinessError::Business(Box::new(value)),
        Err(error) => error,
    }
}
pub(crate) fn runtime_error(v: anyhow::Error) -> BridgeAcpBusinessError {
    match v.downcast::<p::AcpBusinessFailure>() {
        Ok(value) => business_error(value),
        Err(value) => BridgeAcpBusinessError::Runtime(value.into()),
    }
}
fn gap(v: p::AcpObservationGap) -> BridgeAcpObservationGap {
    match v {
        p::AcpObservationGap::WindowExceeded => BridgeAcpObservationGap::WindowExceeded,
        p::AcpObservationGap::Disconnected => BridgeAcpObservationGap::Disconnected,
        p::AcpObservationGap::Encoding => BridgeAcpObservationGap::Encoding,
    }
}
fn prompt_response(v: s::PromptResponse) -> R<BridgeAcpPromptResponse> {
    Ok(BridgeAcpPromptResponse {
        stop_reason: match v.stop_reason {
            s::StopReason::EndTurn => BridgeAcpStopReason::EndTurn,
            s::StopReason::MaxTokens => BridgeAcpStopReason::MaxTokens,
            s::StopReason::MaxTurnRequests => BridgeAcpStopReason::MaxTurnRequests,
            s::StopReason::Refusal => BridgeAcpStopReason::Refusal,
            s::StopReason::Cancelled => BridgeAcpStopReason::Cancelled,
            _ => return Err(unsupported("StopReason")),
        },
        meta: json::opt_meta(v.meta)?,
    })
}
fn completed(v: p::AcpCompletedRun) -> R<BridgeAcpCompletedRun> {
    Ok(BridgeAcpCompletedRun {
        run: v.run.into(),
        completion_sequence: v.completion_sequence,
        result: match v.result {
            Ok(v) => BridgeAcpPromptResult::Succeeded {
                response: prompt_response(v)?,
            },
            Err(v) => BridgeAcpPromptResult::Failed {
                failure: failure(v)?,
            },
        },
        summary: v.summary,
        truncated: v.truncated,
    })
}
pub(crate) fn list(v: s::ListSessionsResponse) -> R<BridgeAcpListResponse> {
    Ok(BridgeAcpListResponse {
        sessions: many(v.sessions, |v| {
            Ok(BridgeAcpSessionInfo {
                session_id: BridgeAcpRemoteSessionId {
                    value: v.session_id.to_string(),
                },
                cwd: path(v.cwd)?,
                additional_directories: many(v.additional_directories, path)?,
                title: v.title,
                updated_at: v.updated_at,
                meta: json::opt_meta(v.meta)?,
            })
        })?,
        next_cursor: v.next_cursor,
        meta: json::opt_meta(v.meta)?,
    })
}
pub(crate) fn snapshot(v: p::AcpBusinessSnapshot) -> R<BridgeAcpBusinessSnapshot> {
    Ok(BridgeAcpBusinessSnapshot {
        target: v.target.into(),
        acp_session_id: v
            .acp_session_id
            .map(|value| BridgeAcpRemoteSessionId { value }),
        ready: v.ready,
        closing: v.closing,
        config_pending: v.config_pending,
        config_options: v
            .config_options
            .map(|v| many(v, config::config))
            .transpose()?,
        modes: v.modes.map(config::modes).transpose()?,
        active_run: v.active_run.map(Into::into),
        last_completed: v.last_completed.map(completed).transpose()?,
        observation_gap: v.observation_gap.map(gap),
        auth_methods: v
            .auth_methods
            .into_iter()
            .map(super::acp::bridge_acp_auth_method)
            .collect(),
    })
}
pub(crate) fn close(v: p::AcpBusinessClose) -> R<BridgeAcpBusinessClose> {
    Ok(BridgeAcpBusinessClose {
        local_complete: v.local_complete,
        sdk_finished: v.sdk_finished,
        cleanup_timed_out: v.cleanup_timed_out,
        remote_close_error: v.remote_close_error.map(failure).transpose()?,
        sdk_error: v.sdk_error.map(failure).transpose()?,
        worker_error: v.worker_error,
        driver_error: v.driver_error,
        unfinished_prompt: v.unfinished_prompt.map(Into::into),
        unfinished_controls: v.unfinished_controls,
        last_completed: v.last_completed.map(completed).transpose()?,
        owner_failures: v
            .owner_failures
            .into_iter()
            .map(|v| BridgeAcpMemberCloseFailure {
                thread_id: v.thread_id,
                message: v.message,
            })
            .collect(),
    })
}
pub(crate) fn frame(v: p::AcpSessionFrame) -> R<BridgeAcpSessionFrame> {
    Ok(match v {
        p::AcpSessionFrame::Accepted {
            target,
            has_observation,
        } => BridgeAcpSessionFrame::Accepted {
            target: target.into(),
            has_observation,
        },
        p::AcpSessionFrame::Settled { result } => BridgeAcpSessionFrame::Settled {
            result: match result {
                Ok(()) => BridgeAcpSettlement::Succeeded,
                Err(v) => BridgeAcpSettlement::Failed {
                    failure: failure(v)?,
                },
            },
        },
        p::AcpSessionFrame::Event { event } => BridgeAcpSessionFrame::Event {
            event: Box::new(match *event {
                p::AcpSessionEvent::Update { update } => BridgeAcpSessionEvent::Update {
                    update: notification::notification(update)?,
                },
                p::AcpSessionEvent::Ready { response: v } => BridgeAcpSessionEvent::Ready {
                    response: BridgeAcpNewSessionResponse {
                        session_id: BridgeAcpRemoteSessionId {
                            value: v.session_id.to_string(),
                        },
                        modes: v.modes.map(config::modes).transpose()?,
                        config_options: v
                            .config_options
                            .map(|v| many(v, config::config))
                            .transpose()?,
                        meta: json::opt_meta(v.meta)?,
                    },
                },
                p::AcpSessionEvent::Failed { error } => BridgeAcpSessionEvent::Failed {
                    failure: failure(error)?,
                },
                p::AcpSessionEvent::Permission { id, request } => {
                    BridgeAcpSessionEvent::Permission {
                        id: BridgeAcpPermissionId {
                            instance: id.instance,
                            sequence: id.sequence,
                        },
                        request: notification::permission(request)?,
                    }
                }
                p::AcpSessionEvent::Configured { response } => BridgeAcpSessionEvent::Configured {
                    config_options: many(response.config_options, config::config)?,
                    meta: json::opt_meta(response.meta)?,
                },
                p::AcpSessionEvent::ModeSet { mode_id } => BridgeAcpSessionEvent::ModeSet {
                    mode_id: BridgeAcpModeId {
                        value: mode_id.to_string(),
                    },
                },
                p::AcpSessionEvent::Completed { completed: v } => {
                    BridgeAcpSessionEvent::Completed {
                        completed: completed(v)?,
                    }
                }
                p::AcpSessionEvent::Gap { gap: v } => BridgeAcpSessionEvent::Gap { gap: gap(v) },
            }),
        },
    })
}
