use crate::protocol::*;
use pl_acp::session as sdk;

pub(super) fn failure(error: sdk::Error) -> AcpBusinessFailure {
    let kind = match &error {
        sdk::Error::Busy => AcpBusinessFailureKind::Busy,
        sdk::Error::Stale => AcpBusinessFailureKind::Stale,
        sdk::Error::NotReady => AcpBusinessFailureKind::NotReady,
        sdk::Error::Preparation(_) => AcpBusinessFailureKind::Preparation,
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

pub(super) fn run(run: sdk::RunId) -> AcpRunId {
    AcpRunId {
        instance: run.instance,
        sequence: run.sequence,
    }
}
pub(super) fn text_performance(value: sdk::TextPerformance) -> AcpTextPerformance {
    AcpTextPerformance {
        estimated_output_tokens: pl_model::completion::estimate_text_tokens(value.characters),
        response_millis: value.response_millis,
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
        text_performance: completed.text_performance.map(text_performance),
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
    super::super::acp_ops::map_auth_methods(methods)
}

pub(super) fn server_info(info: sdk::schema::Implementation) -> AcpServerInfoSnapshot {
    AcpServerInfoSnapshot {
        name: info.name,
        version: info.version,
        title: info.title,
    }
}

fn stop_reason_label(reason: sdk::schema::StopReason) -> String {
    match reason {
        sdk::schema::StopReason::EndTurn => "endTurn".into(),
        sdk::schema::StopReason::MaxTokens => "maxTokens".into(),
        sdk::schema::StopReason::MaxTurnRequests => "maxTurnRequests".into(),
        sdk::schema::StopReason::Refusal => "refusal".into(),
        sdk::schema::StopReason::Cancelled => "cancelled".into(),
        other => format!("{other:?}"),
    }
}

fn category_label(category: &sdk::schema::SessionConfigOptionCategory) -> String {
    match category {
        sdk::schema::SessionConfigOptionCategory::Mode => "mode".into(),
        sdk::schema::SessionConfigOptionCategory::Model => "model".into(),
        sdk::schema::SessionConfigOptionCategory::ModelConfig => "modelConfig".into(),
        sdk::schema::SessionConfigOptionCategory::ThoughtLevel => "thoughtLevel".into(),
        sdk::schema::SessionConfigOptionCategory::Other(value) => value.clone(),
        other => format!("{other:?}"),
    }
}

fn active_config_items(
    config_options: Option<&[sdk::schema::SessionConfigOption]>,
    modes: Option<&sdk::schema::SessionModeState>,
) -> Vec<AcpConfigItemSnapshot> {
    const MAX_ITEMS: usize = 16;
    if let Some(options) = config_options {
        return options
            .iter()
            .take(MAX_ITEMS)
            .filter_map(|option| {
                let (value_id, value_label) = match &option.kind {
                    sdk::schema::SessionConfigKind::Select(select) => {
                        let id = select.current_value.to_string();
                        let label = match &select.options {
                            sdk::schema::SessionConfigSelectOptions::Ungrouped(items) => items
                                .iter()
                                .find(|item| item.value == select.current_value)
                                .map(|item| item.name.clone()),
                            sdk::schema::SessionConfigSelectOptions::Grouped(groups) => groups
                                .iter()
                                .flat_map(|group| group.options.iter())
                                .find(|item| item.value == select.current_value)
                                .map(|item| item.name.clone()),
                            _ => None,
                        }
                        .unwrap_or_else(|| id.clone());
                        (id, label)
                    }
                    sdk::schema::SessionConfigKind::Boolean(boolean) => {
                        let label = if boolean.current_value {
                            "true"
                        } else {
                            "false"
                        };
                        (label.to_owned(), label.to_owned())
                    }
                    _ => return None,
                };
                Some(AcpConfigItemSnapshot {
                    id: option.id.to_string(),
                    name: option.name.clone(),
                    category: option.category.as_ref().map(category_label),
                    value_id,
                    value_label,
                })
            })
            .collect();
    }
    if let Some(modes) = modes {
        let value_id = modes.current_mode_id.to_string();
        let value_label = modes
            .available_modes
            .iter()
            .find(|mode| mode.id == modes.current_mode_id)
            .map_or_else(|| value_id.clone(), |mode| mode.name.clone());
        return vec![AcpConfigItemSnapshot {
            id: "mode".into(),
            name: "Mode".into(),
            category: Some("mode".into()),
            value_id,
            value_label,
        }];
    }
    Vec::new()
}

pub(super) fn info_snapshot(snapshot: &sdk::Snapshot) -> Option<AcpSessionInfoSnapshot> {
    let usage = snapshot.latest_usage.map(|u| AcpUsageSnapshot {
        used: u.used,
        size: u.size,
        updated_at: u.updated_at,
    });
    let cost = snapshot.latest_cost.as_ref().map(|c| AcpCostSnapshot {
        amount: c.amount,
        currency: c.currency.clone(),
        updated_at: c.updated_at,
    });
    let text_performance = snapshot
        .latest_text_performance
        .map(|p| AcpTextPerformanceSnapshot {
            estimated_output_tokens: pl_model::completion::estimate_text_tokens(
                p.performance.characters,
            ),
            response_millis: p.performance.response_millis,
            updated_at: p.updated_at,
        });
    let last_stop_reason = snapshot
        .last_completed
        .as_ref()
        .and_then(|completed| completed.result.as_ref().ok())
        .map(|response| stop_reason_label(response.stop_reason));
    let server = snapshot.server_info.clone().map(server_info);
    let active_config =
        active_config_items(snapshot.config_options.as_deref(), snapshot.modes.as_ref());
    let completed_turns = (snapshot.completed_turns > 0).then_some(snapshot.completed_turns);
    if usage.is_none()
        && cost.is_none()
        && text_performance.is_none()
        && last_stop_reason.is_none()
        && server.is_none()
        && active_config.is_empty()
        && completed_turns.is_none()
    {
        return None;
    }
    let updated_at = snapshot
        .updated_at
        .or_else(|| usage.as_ref().map(|u| u.updated_at))
        .or_else(|| cost.as_ref().map(|c| c.updated_at))
        .or_else(|| text_performance.as_ref().map(|p| p.updated_at))
        .unwrap_or(0);
    Some(AcpSessionInfoSnapshot {
        usage,
        cost,
        text_performance,
        last_stop_reason,
        server_info: server,
        active_config,
        completed_turns,
        updated_at,
    })
}

pub(super) fn snapshot(
    target: AcpSessionTarget,
    snapshot: sdk::Snapshot,
    workflow_state: Option<AcpWorkflowStateSnapshot>,
) -> AcpBusinessSnapshot {
    let info = info_snapshot(&snapshot);
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
        info_snapshot: info,
        workflow_state,
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

#[cfg(test)]
mod tests {
    use super::*;
    use sdk::schema::{
        AgentCapabilities, Implementation, PromptResponse, SessionConfigBoolean, SessionConfigKind,
        SessionConfigOption, SessionConfigOptionCategory, SessionConfigSelect,
        SessionConfigSelectOption, SessionConfigSelectOptions, SessionMode, SessionModeState,
        StopReason,
    };

    fn empty_sdk_snapshot() -> sdk::Snapshot {
        sdk::Snapshot {
            session_id: None,
            capabilities: AgentCapabilities::default(),
            ready: false,
            closing: false,
            config_pending: false,
            config_options: None,
            modes: None,
            active_run: None,
            last_completed: None,
            observation_gap: None,
            server_info: None,
            auth_methods: Vec::new(),
            latest_usage: None,
            latest_cost: None,
            latest_text_performance: None,
            completed_turns: 0,
            updated_at: None,
        }
    }

    #[test]
    fn info_snapshot_returns_none_when_empty_and_projects_metrics_and_configs() {
        assert!(info_snapshot(&empty_sdk_snapshot()).is_none());

        let mut sdk_snap = empty_sdk_snapshot();
        sdk_snap.server_info =
            Some(Implementation::new("claude-code", "1.4.5").title("Claude Code"));
        sdk_snap.latest_usage = Some(sdk::UsageSnapshot {
            used: 48_000,
            size: 200_000,
            updated_at: 1_700_000_010,
        });
        sdk_snap.latest_cost = Some(sdk::CostSnapshot {
            amount: 0.42,
            currency: "USD".into(),
            updated_at: 1_700_000_010,
        });
        sdk_snap.latest_text_performance = Some(sdk::TimedTextPerformance {
            performance: sdk::TextPerformance {
                characters: 160,
                response_millis: 1_000,
            },
            updated_at: 1_700_000_012,
        });
        sdk_snap.completed_turns = 3;
        sdk_snap.updated_at = Some(1_700_000_012);
        sdk_snap.last_completed = Some(sdk::Completed {
            run: sdk::RunId {
                instance: 1,
                sequence: 3,
            },
            completion_sequence: 3,
            result: Ok(PromptResponse::new(StopReason::EndTurn)),
            summary: String::new(),
            truncated: false,
            text_performance: None,
        });
        sdk_snap.config_options = Some(vec![
            SessionConfigOption::new(
                "model",
                "Model",
                SessionConfigKind::Select(SessionConfigSelect::new(
                    "sonnet",
                    SessionConfigSelectOptions::Ungrouped(vec![SessionConfigSelectOption::new(
                        "sonnet",
                        "Claude Sonnet",
                    )]),
                )),
            )
            .category(SessionConfigOptionCategory::Model),
            SessionConfigOption::new(
                "safe",
                "Safe Mode",
                SessionConfigKind::Boolean(SessionConfigBoolean::new(true)),
            ),
        ]);

        let info = info_snapshot(&sdk_snap).expect("populated snapshot");
        assert_eq!(
            info.usage.as_ref().map(|u| (u.used, u.size)),
            Some((48_000, 200_000))
        );
        assert_eq!(
            info.cost.as_ref().map(|c| (c.amount, c.currency.as_str())),
            Some((0.42, "USD"))
        );
        assert_eq!(
            info.text_performance
                .as_ref()
                .map(|p| (p.estimated_output_tokens, p.response_millis)),
            Some((pl_model::completion::estimate_text_tokens(160), 1_000))
        );
        assert_eq!(info.last_stop_reason.as_deref(), Some("endTurn"));
        assert_eq!(info.completed_turns, Some(3));
        assert_eq!(info.updated_at, 1_700_000_012);
        assert_eq!(
            info.server_info.as_ref().map(|s| s.version.as_str()),
            Some("1.4.5")
        );
        assert_eq!(info.active_config.len(), 2);
        assert_eq!(info.active_config[0].value_label, "Claude Sonnet");
        assert_eq!(info.active_config[1].value_label, "true");
    }

    #[test]
    fn info_snapshot_falls_back_to_legacy_modes_when_config_options_is_none() {
        let mut sdk_snap = empty_sdk_snapshot();
        sdk_snap.modes = Some(SessionModeState::new(
            "act",
            vec![
                SessionMode::new("ask", "Ask Mode"),
                SessionMode::new("act", "Act Mode"),
            ],
        ));
        let info = info_snapshot(&sdk_snap).expect("legacy modes snapshot");
        assert_eq!(info.active_config.len(), 1);
        assert_eq!(info.active_config[0].id, "mode");
        assert_eq!(info.active_config[0].value_id, "act");
        assert_eq!(info.active_config[0].value_label, "Act Mode");
    }
}
