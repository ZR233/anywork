//! A noninteractive adapter of the production Studio lifecycle, without a second agent loop.
mod args;
mod signals;
mod text;

pub use args::{Cli, Command, ExecArgs, PreparedExec, PreparedExport};
pub use signals::SignalListener;

use anyhow::{Context, Result};
use pl_protocol::{
    ThreadNotification, ThreadSubscriptionUpdate, ThreadWorkspaceMode, Turn, TurnCompletion,
    TurnState, studio::StudioPromptInput,
};
use pl_studio_runtime::{
    BuildInfoV1, ExecutionErrorStage, ExecutionErrorV1, ExecutionOutcome, RESULT_SCHEMA_VERSION,
    ResultOutcome, ResultV1, RunExportOptions, RunExportReport, RunExporter,
    StudioPendingPersistence, StudioRuntime, StudioShutdownOutcome, StudioShutdownReport,
    StudioStartNewThreadRequest, StudioStartupError, StudioStartupErrorKind,
    StudioSubmitPromptOptions, TimingReportV1, format_export_utc_rfc3339,
};
use std::future::Future;
use std::time::{Instant, SystemTime};

pub const SHUTDOWN_BUDGET_MS: u32 = 30_000;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CancellationSignal {
    Interrupt,
    Terminate,
}

impl CancellationSignal {
    pub const fn exit_code(self) -> u8 {
        match self {
            Self::Interrupt => 130,
            Self::Terminate => 143,
        }
    }
}

#[derive(Debug, thiserror::Error)]
pub enum ExecutionError {
    #[error("任务输入或路由无效: {0}")]
    Input(#[source] anyhow::Error),
    #[error(transparent)]
    Startup(#[from] StudioStartupError),
    #[error("任务运行环境失败: {0}")]
    Runtime(#[source] anyhow::Error),
}

/// Retains the actual task identity, native terminal, shutdown, and optional export report.
#[derive(Debug)]
pub struct ExecutionReport {
    pub submission: Option<pl_studio_runtime::StudioSubmitPromptResponse>,
    pub turn: Option<Turn>,
    pub final_text: String,
    pub signal: Option<CancellationSignal>,
    pub error: Option<ExecutionError>,
    pub shutdown: StudioShutdownReport,
    pub export: Option<RunExportReport>,
    pub export_error: Option<ExecutionErrorV1>,
}

impl ExecutionReport {
    fn shutdown_failed(&self) -> bool {
        let not_started_before_runtime = self.submission.is_none()
            && self.shutdown.outcome == StudioShutdownOutcome::NotStarted
            && (matches!(self.error, Some(ExecutionError::Startup(_)))
                || self.export_error.is_some());
        (self.shutdown.outcome != StudioShutdownOutcome::Clean && !not_started_before_runtime)
            || self.shutdown.persistence != StudioPendingPersistence::Drained
    }

    fn export_failed(&self) -> bool {
        if self.export_error.is_some() {
            return true;
        }
        let Some(exp) = &self.export else {
            return false;
        };
        if exp.failure.is_some() {
            return true;
        }
        // Keep pre-member StartupFailed / Cancelled / InvalidInput exit codes when no run root was created.
        let stopped_before_root =
            self.submission.is_none() && (self.signal.is_some() || self.error.is_some());
        !stopped_before_root && (!exp.trace_complete || !exp.trace.sealed)
    }

    pub fn exit_code(&self) -> u8 {
        if self.shutdown_failed() {
            return 13;
        }
        if self.export_failed() {
            return 12;
        }
        if let Some(signal) = self.signal {
            return signal.exit_code();
        }
        if let Some(error) = &self.error {
            return match error {
                ExecutionError::Input(_) => 2,
                ExecutionError::Startup(error) => match error.kind {
                    StudioStartupErrorKind::Configuration
                    | StudioStartupErrorKind::RecoveryRequired
                    | StudioStartupErrorKind::PersistentData
                    | StudioStartupErrorKind::Migration => 2,
                    StudioStartupErrorKind::Cancelled => 14,
                    StudioStartupErrorKind::Environment | StudioStartupErrorKind::Internal => 11,
                },
                ExecutionError::Runtime(_) => 11,
            };
        }
        match self.turn.as_ref().map(|turn| &turn.state) {
            Some(TurnState::Completed(state)) => match state.completion() {
                TurnCompletion::Normal => 0,
                TurnCompletion::InteractionRequested => 3,
            },
            Some(TurnState::BudgetLimited(_)) => 4,
            Some(TurnState::Failed(_)) => 10,
            Some(TurnState::Cancelled(_)) => 14,
            _ => 11,
        }
    }

    fn result_outcome(&self) -> ResultOutcome {
        if self.shutdown_failed() {
            return ResultOutcome::ShutdownFailed;
        }
        if self.export_failed() {
            return ResultOutcome::ExportFailed;
        }
        if self.signal.is_some() {
            return ResultOutcome::Cancelled;
        }
        if let Some(error) = &self.error {
            return match error {
                ExecutionError::Input(_) => ResultOutcome::InvalidInput,
                ExecutionError::Startup(err) => match err.kind {
                    StudioStartupErrorKind::Cancelled => ResultOutcome::Cancelled,
                    _ => ResultOutcome::StartupFailed,
                },
                ExecutionError::Runtime(_) => ResultOutcome::Failed,
            };
        }
        match self.turn.as_ref().map(|turn| &turn.state) {
            Some(TurnState::Completed(state)) => match state.completion() {
                TurnCompletion::Normal => ResultOutcome::Completed,
                TurnCompletion::InteractionRequested => ResultOutcome::BlockedOnInput,
            },
            Some(TurnState::BudgetLimited(_)) => ResultOutcome::BudgetExceeded,
            Some(TurnState::Failed(_)) => ResultOutcome::Failed,
            Some(TurnState::Cancelled(_)) => ResultOutcome::Cancelled,
            _ => ResultOutcome::Failed,
        }
    }

    fn execution_outcome(&self) -> Option<ExecutionOutcome> {
        if let Some(turn) = &self.turn {
            return match &turn.state {
                TurnState::Completed(state) => Some(match state.completion() {
                    TurnCompletion::Normal => ExecutionOutcome::Completed,
                    TurnCompletion::InteractionRequested => ExecutionOutcome::BlockedOnInput,
                }),
                TurnState::BudgetLimited(_) => Some(ExecutionOutcome::BudgetExceeded),
                TurnState::Failed(_) => Some(ExecutionOutcome::Failed),
                TurnState::Cancelled(_) => Some(ExecutionOutcome::Cancelled),
                TurnState::Queued(_) | TurnState::Running(_) => None,
            };
        }
        if self.submission.is_some() && self.signal.is_some() {
            return Some(ExecutionOutcome::Cancelled);
        }
        if self.submission.is_some() && matches!(self.error, Some(ExecutionError::Runtime(_))) {
            return Some(ExecutionOutcome::Failed);
        }
        None
    }

    fn native_execution_error(&self) -> Option<ExecutionErrorV1> {
        if let Some(error) = &self.error {
            return Some(match error {
                ExecutionError::Input(err) => ExecutionErrorV1 {
                    stage: ExecutionErrorStage::Startup,
                    code: "invalidInput".to_string(),
                    message: format!("{err:#}"),
                    turn_failure: None,
                },
                ExecutionError::Startup(err) => ExecutionErrorV1 {
                    stage: ExecutionErrorStage::Startup,
                    code: format!("{:?}", err.kind),
                    message: err.to_string(),
                    turn_failure: None,
                },
                ExecutionError::Runtime(err) => ExecutionErrorV1 {
                    stage: ExecutionErrorStage::Turn,
                    code: "runtimeError".to_string(),
                    message: format!("{err:#}"),
                    turn_failure: None,
                },
            });
        }
        if let Some(turn) = &self.turn
            && let TurnState::Failed(failed) = &turn.state
        {
            let failure = failed.failure();
            return Some(ExecutionErrorV1 {
                stage: ExecutionErrorStage::Turn,
                code: failure
                    .code
                    .clone()
                    .unwrap_or_else(|| "turnFailed".to_string()),
                message: failure.message.clone(),
                turn_failure: Some(failure.clone()),
            });
        }
        None
    }
}

/// A signal latches once. Initialization/admission/shutdown retain their original owner until return.
async fn latch_during<F: Future, S: Future<Output = CancellationSignal>>(
    work: F,
    signal: std::pin::Pin<&mut S>,
    caught: &mut Option<CancellationSignal>,
) -> F::Output {
    if caught.is_some() {
        return work.await;
    }
    let mut work = std::pin::pin!(work);
    tokio::select! { biased;
        value = signal => { *caught = Some(value); work.await }
        result = work.as_mut() => result,
    }
}

pub async fn execute(
    request: PreparedExec,
    signal: impl Future<Output = CancellationSignal>,
) -> ExecutionReport {
    execute_observed(request, signal, std::sync::Arc::new(|_| {})).await
}

async fn execute_observed(
    mut request: PreparedExec,
    signal: impl Future<Output = CancellationSignal>,
    observer: std::sync::Arc<dyn Fn(pl_studio_runtime::StudioStartupStage) + Send + Sync>,
) -> ExecutionReport {
    let run_start = Instant::now();
    let mut signal = std::pin::pin!(signal);
    let mut report = ExecutionReport {
        submission: None,
        turn: None,
        final_text: String::new(),
        signal: None,
        error: None,
        shutdown: StudioShutdownReport::not_started(),
        export: None,
        export_error: None,
    };
    let exporter = match request.export.take() {
        Some(export_cfg) => {
            let options = RunExportOptions {
                output_dir: export_cfg.output_dir,
                run_id: export_cfg.run_id,
                cwd: export_cfg.cwd,
                studio_home: export_cfg.studio_home,
                account_id: export_cfg.account_id,
                model_id: export_cfg.model_id,
                reasoning_effort: export_cfg.reasoning_effort,
                mode: export_cfg.mode,
                max_model_steps: export_cfg.max_model_steps,
                prompt_sha256: export_cfg.prompt_sha256,
                skill_search: export_cfg.skill_search,
                config: None,
            };
            match RunExporter::start(options).await {
                Ok(exp) => {
                    request.runtime = request.runtime.with_run_export(exp.clone());
                    Some(exp)
                }
                Err(error) => {
                    report.export_error = Some(ExecutionErrorV1 {
                        stage: ExecutionErrorStage::Export,
                        code: "exportStartFailed".to_string(),
                        message: format!("{error:#}"),
                        turn_failure: None,
                    });
                    return report;
                }
            }
        }
        None => None,
    };

    let init_start = Instant::now();
    let runtime = match latch_during(
        StudioRuntime::initialize_with_observer(request.runtime, observer),
        signal.as_mut(),
        &mut report.signal,
    )
    .await
    {
        Ok(runtime) => runtime,
        Err(error) => {
            let init_wall_ms = init_start.elapsed().as_millis() as u64;
            report.error = Some(error.into());
            if let Some(exp) = &exporter {
                finalize_and_write_export_result(
                    &mut report,
                    exp,
                    run_start,
                    Some(init_wall_ms),
                    None,
                    None,
                )
                .await;
            }
            return report;
        }
    };
    let init_wall_ms = init_start.elapsed().as_millis() as u64;

    let mut agent_start = None;
    if report.signal.is_none() {
        let project = latch_during(
            runtime.open_project(&request.cwd),
            signal.as_mut(),
            &mut report.signal,
        )
        .await;
        let project = match project {
            Ok(project) => Some(project),
            Err(error) => {
                report.error = Some(ExecutionError::Runtime(error));
                None
            }
        };
        if report.signal.is_none()
            && let Some(project) = project
        {
            agent_start = Some(Instant::now());
            let operation = async {
                let response = runtime
                    .start_new_thread(StudioStartNewThreadRequest {
                        workspace_id: project.id,
                        title: Some("anywk run".into()),
                        input: StudioPromptInput {
                            input_id: format!("anywk-{}", uuid::Uuid::new_v4()),
                            text: request.prompt,
                            attachment_draft_ids: Vec::new(),
                        },
                        mode: request.mode,
                        route: request.route,
                        delegation_mode: None,
                        delegation_preference: None,
                        workspace_mode: ThreadWorkspaceMode::Local,
                        options: StudioSubmitPromptOptions {
                            max_model_steps: request.max_model_steps,
                            ..Default::default()
                        },
                        preparation_observer: None,
                    })
                    .await
                    .map_err(|error| {
                        use pl_protocol::studio::StudioErrorCode;
                        match pl_studio_runtime::studio_error_from_anyhow_ref(&error).code {
                            StudioErrorCode::InvalidArgument | StudioErrorCode::NotFound => {
                                ExecutionError::Input(error)
                            }
                            _ => ExecutionError::Runtime(error),
                        }
                    })?;
                Ok::<_, ExecutionError>(response.submission)
            };
            match latch_during(operation, signal.as_mut(), &mut report.signal).await {
                Ok(submission) => report.submission = Some(submission),
                Err(error) => report.error = Some(error),
            }
        }
    }
    if report.signal.is_none()
        && let Some(submission) = &report.submission
    {
        let task = wait_for_input(
            &runtime,
            &submission.thread_id,
            &submission.input_id,
            submission.cursor,
        );
        let export_cancelled = async {
            match &exporter {
                Some(exp) => exp.cancellation().cancelled().await,
                None => std::future::pending::<()>().await,
            }
        };
        tokio::select! { biased;
            caught = signal.as_mut() => report.signal = Some(caught),
            _ = export_cancelled => {}
            result = task => match result {
                Ok(turn) => report.turn = Some(turn),
                Err(error) => report.error = Some(ExecutionError::Runtime(error)),
            }
        }
    }
    let agent_wall_ms = agent_start.map(|start| start.elapsed().as_millis() as u64);
    if report.signal.is_none()
        && !exporter
            .as_ref()
            .is_some_and(|exp| exp.cancellation().is_cancelled())
        && let Some(turn) = &report.turn
        && matches!(&turn.state, TurnState::Completed(state) if state.completion() == TurnCompletion::Normal)
    {
        tokio::select! { biased;
            caught = signal.as_mut() => report.signal = Some(caught),
            result = text::final_text(&runtime, turn) => match result {
                Ok(text) => report.final_text = text,
                Err(error) => report.error = Some(ExecutionError::Runtime(error)),
            }
        }
    }

    let shutdown_start = Instant::now();
    report.shutdown = latch_during(
        runtime.shutdown_runtime_for_exit(SHUTDOWN_BUDGET_MS, Vec::new()),
        signal.as_mut(),
        &mut report.signal,
    )
    .await;
    let shutdown_wall_ms = shutdown_start.elapsed().as_millis() as u64;

    if let Some(exp) = &exporter {
        finalize_and_write_export_result(
            &mut report,
            exp,
            run_start,
            Some(init_wall_ms),
            agent_wall_ms,
            Some(shutdown_wall_ms),
        )
        .await;
    }
    report
}

async fn finalize_and_write_export_result(
    report: &mut ExecutionReport,
    exporter: &RunExporter,
    run_start: Instant,
    initialize_wall_ms: Option<u64>,
    agent_wall_ms: Option<u64>,
    shutdown_wall_ms: Option<u64>,
) {
    let export_report = exporter.finish_report().await;
    let timing = TimingReportV1 {
        total_wall_ms: run_start.elapsed().as_millis() as u64,
        initialize_wall_ms,
        agent_wall_ms,
        shutdown_wall_ms,
        export_finalize_ms: export_report.export_finalize_ms,
    };
    let finished_at = format_export_utc_rfc3339(SystemTime::now());
    report.export = Some(export_report);
    let result_v1 = build_result_v1(
        report,
        report.export.as_ref().expect("just assigned"),
        timing,
        finished_at,
    );
    if let Err(err) = exporter.write_result(&result_v1) {
        report.export_error = Some(ExecutionErrorV1 {
            stage: ExecutionErrorStage::Export,
            code: "resultWriteFailed".to_string(),
            message: format!("{err:#}"),
            turn_failure: None,
        });
    }
}

fn shutdown_error_v1(shutdown: &StudioShutdownReport) -> ExecutionErrorV1 {
    if let Some(issue) = shutdown.issues.first() {
        ExecutionErrorV1 {
            stage: ExecutionErrorStage::Shutdown,
            code: issue.code.clone(),
            message: format!(
                "shutdown failed at stage {} ({}): {:?}",
                issue.stage, issue.code, shutdown.outcome
            ),
            turn_failure: None,
        }
    } else {
        ExecutionErrorV1 {
            stage: ExecutionErrorStage::Shutdown,
            code: "pendingPersistenceNotDrained".to_string(),
            message: format!(
                "shutdown did not drain persistence: {:?}",
                shutdown.persistence
            ),
            turn_failure: None,
        }
    }
}

fn build_result_v1(
    report: &ExecutionReport,
    export_report: &RunExportReport,
    timing: TimingReportV1,
    finished_at: String,
) -> ResultV1 {
    let outcome = report.result_outcome();
    let execution_outcome = report.execution_outcome();
    let exit_code = i32::from(report.exit_code());
    let execution_error = report.native_execution_error();
    let error = match outcome {
        ResultOutcome::ShutdownFailed => Some(shutdown_error_v1(&report.shutdown)),
        ResultOutcome::ExportFailed => export_report.failure.clone().or_else(|| {
            Some(ExecutionErrorV1 {
                stage: ExecutionErrorStage::Export,
                code: "exportFailed".to_string(),
                message: export_report
                    .trace
                    .reason
                    .clone()
                    .unwrap_or_else(|| "run export did not seal completely".to_string()),
                turn_failure: None,
            })
        }),
        _ => execution_error.clone(),
    };
    let final_text = if report.error.is_none()
        && report.signal.is_none()
        && matches!(
            report.turn.as_ref().map(|t| &t.state),
            Some(TurnState::Completed(state)) if state.completion() == TurnCompletion::Normal
        ) {
        Some(report.final_text.clone())
    } else {
        None
    };
    ResultV1 {
        schema_version: RESULT_SCHEMA_VERSION,
        run_id: export_report.run_id.clone(),
        root_thread_id: report
            .submission
            .as_ref()
            .map(|s| s.thread_id.clone())
            .or_else(|| export_report.root_thread_id.clone()),
        outcome,
        execution_outcome,
        exit_code,
        started_at: export_report.started_at.clone(),
        finished_at,
        build: BuildInfoV1::current(),
        timing,
        final_text,
        trace_complete: export_report.trace_complete,
        usage_complete: export_report.usage_complete,
        cost_complete: export_report.cost_complete,
        trace: export_report.trace.clone(),
        usage: export_report.usage.clone(),
        shutdown: report.shutdown.clone(),
        error,
        execution_error,
    }
}

async fn wait_for_input(
    runtime: &StudioRuntime,
    thread_id: &str,
    input_id: &str,
    cursor: u64,
) -> Result<Turn> {
    let mut feed = runtime.open_conversation_state_feed(thread_id).await?;
    let result = async {
        loop {
            let update = feed.recv().await?.context("任务状态流提前结束")?;
            match update {
                ThreadSubscriptionUpdate::Snapshot { snapshot, .. } => {
                    if let Some(turn) = snapshot.active_turn
                        && is_target_terminal(&turn, input_id, cursor)
                    {
                        return Ok(turn);
                    }
                }
                ThreadSubscriptionUpdate::Notification { notification } => {
                    match notification.notification {
                        ThreadNotification::TurnCompleted { turn }
                            if is_target_terminal(&turn, input_id, cursor) =>
                        {
                            return Ok(turn);
                        }
                        ThreadNotification::Lagged { .. } => anyhow::bail!("任务状态流丢失连续性"),
                        _ => {}
                    }
                }
            }
        }
    }
    .await;
    feed.close().await?;
    result
}

fn is_target_terminal(turn: &Turn, input_id: &str, cursor: u64) -> bool {
    turn.input_id.as_deref() == Some(input_id)
        && turn.revision >= cursor
        && turn.state.is_terminal()
}

#[cfg(test)]
mod tests {
    use super::*;
    use pl_model::{
        config::{AccountConfig, AccountId, ModelRouteConfig},
        model::{ModelInfo, ModelTransportProfile},
        protocol::ProtocolEndpoint,
    };

    #[tokio::test]
    async fn initialization_signal_waits_for_owner_and_never_submits_a_task() -> Result<()> {
        for cancellation in [CancellationSignal::Interrupt, CancellationSignal::Terminate] {
            let root = tempfile::tempdir()?;
            let home = root.path().join("profile");
            let task = root.path().join("task");
            std::fs::create_dir_all(&task)?;
            let server = pl_provider_fixture::FixtureServer::start(Vec::new()).await?;
            let mut config = pl_studio_runtime::StudioConfig::default_config()?;
            config.models.accounts.clear();
            let mut model = ModelInfo::compatible("startup-test");
            model
                .binding
                .set_transport(ModelTransportProfile::responses_http());
            config.models.accounts.insert(
                AccountId::new("fixture")?,
                AccountConfig::from_explicit_models(
                    ProtocolEndpoint::compatible("fixture", server.base_url()),
                    vec![model],
                ),
            );
            let route = ModelRouteConfig {
                account_id: AccountId::new("fixture")?,
                model_id: "startup-test".into(),
                effort: None,
            };
            for selected in config
                .models
                .routes
                .values_mut()
                .chain(config.mode_model_routes.values_mut())
            {
                *selected = route.clone();
            }
            config.runtime.tool_capabilities.mcp = false;
            config.skills.auto_learn = false;
            pl_studio_runtime::ConfigStore::new(pl_studio_runtime::ConfigPaths::from_config_dir(
                &home,
            ))
            .save(&config)?;
            let (sender, receiver) = tokio::sync::oneshot::channel();
            let sender = std::sync::Mutex::new(Some(sender));
            let observer = std::sync::Arc::new(move |stage| {
                if stage == pl_studio_runtime::StudioStartupStage::WaitingForSteps
                    && let Some(sender) = sender.lock().unwrap().take()
                {
                    let _ = sender.send(());
                }
            });
            let mut options = pl_studio_runtime::StudioRuntimeOptions::cli(&home);
            options.skill_search.include_default_user_dir = false;
            let request = PreparedExec {
                runtime: options,
                cwd: task,
                route: pl_studio_runtime::NewThreadModelRoute {
                    account_id: "fixture".into(),
                    model_id: "startup-test".into(),
                    effort: None,
                },
                mode: pl_studio_runtime::ThreadModeId::simple(),
                prompt: "must not run".into(),
                max_model_steps: None,
                export: None,
            };
            let report = tokio::time::timeout(
                std::time::Duration::from_secs(60),
                execute_observed(
                    request,
                    async {
                        receiver.await.unwrap();
                        cancellation
                    },
                    observer,
                ),
            )
            .await?;
            assert_eq!(report.exit_code(), cancellation.exit_code(), "{report:?}");
            assert_eq!(report.shutdown.outcome, StudioShutdownOutcome::Clean);
            assert_eq!(
                report.shutdown.persistence,
                StudioPendingPersistence::Drained
            );
            assert!(report.submission.is_none());
            assert!(report.error.is_none());
            assert!(server.recorded().is_empty());
            let reopened =
                StudioRuntime::initialize(pl_studio_runtime::StudioRuntimeOptions::cli(&home))
                    .await?;
            reopened.shutdown_runtime().await?;
            server.finish().await?;
        }
        Ok(())
    }

    #[test]
    fn terminal_filter_requires_the_accepted_input_and_shutdown_failure_overrides_success() {
        let turn = Turn {
            input_id: Some("accepted".into()),
            id: "turn".into(),
            thread_id: "thread".into(),
            revision: 12,
            state: TurnState::Completed(pl_protocol::CompletedTurnState::new(
                Some(1),
                2,
                TurnCompletion::Normal,
            )),
            updated_at: 2,
        };
        assert!(!is_target_terminal(&turn, "another-input", 1));
        assert!(!is_target_terminal(&turn, "accepted", 13));
        assert!(is_target_terminal(&turn, "accepted", 10));
        let mut report = ExecutionReport {
            submission: None,
            turn: Some(turn),
            final_text: "answer".into(),
            signal: None,
            error: None,
            shutdown: StudioShutdownReport {
                outcome: StudioShutdownOutcome::Clean,
                issues: Vec::new(),
                persistence: StudioPendingPersistence::Drained,
            },
            export: None,
            export_error: None,
        };
        assert_eq!(report.exit_code(), 0);
        report.shutdown.persistence = StudioPendingPersistence::Pending { count: 1 };
        assert_eq!(report.exit_code(), 13);
        report.signal = Some(CancellationSignal::Interrupt);
        assert_eq!(report.exit_code(), 13);
        report.shutdown.persistence = StudioPendingPersistence::Drained;
        report.shutdown.outcome = StudioShutdownOutcome::Degraded;
        assert_eq!(report.exit_code(), 13);
        report.turn = None;
        report.signal = None;
        report.error = Some(ExecutionError::Input(anyhow::anyhow!("invalid route")));
        report.shutdown = StudioShutdownReport::not_started();
        assert_eq!(report.exit_code(), 13, "an initialized runtime must close");
    }

    #[test]
    fn exit_code_and_outcome_respect_shutdown_gt_export_gt_execution_precedence() {
        let completed_turn = Turn {
            input_id: Some("accepted".into()),
            id: "turn".into(),
            thread_id: "thread".into(),
            revision: 12,
            state: TurnState::Completed(pl_protocol::CompletedTurnState::new(
                Some(1),
                2,
                TurnCompletion::Normal,
            )),
            updated_at: 2,
        };
        let clean_shutdown = StudioShutdownReport {
            outcome: StudioShutdownOutcome::Clean,
            issues: Vec::new(),
            persistence: StudioPendingPersistence::Drained,
        };
        let sample_export =
            |sealed: bool, failure: Option<ExecutionErrorV1>, usage_complete: bool| {
                RunExportReport {
                    run_id: "run-1".into(),
                    started_at: "2026-11-13T15:00:00.000Z".into(),
                    manifest_sha256: "a".repeat(64),
                    root_thread_id: Some("thread".into()),
                    trace_complete: sealed && failure.is_none(),
                    usage_complete,
                    cost_complete: usage_complete,
                    trace: pl_studio_runtime::TraceSummaryV1 {
                        events_path: "events.jsonl".into(),
                        events_sha256: Some("b".repeat(64)),
                        event_count: 5,
                        last_event_seq: Some(5),
                        sealed,
                        reason: (!sealed).then(|| "not sealed".into()),
                    },
                    usage: None,
                    export_finalize_ms: Some(1),
                    failure,
                }
            };

        // 1. Sealed trace with incomplete usage/cost keeps exit 0 + Completed.
        let mut report = ExecutionReport {
            submission: None,
            turn: Some(completed_turn),
            final_text: "ok".into(),
            signal: None,
            error: None,
            shutdown: clean_shutdown.clone(),
            export: Some(sample_export(true, None, false)),
            export_error: None,
        };
        assert_eq!(report.exit_code(), 0);
        assert_eq!(report.result_outcome(), ResultOutcome::Completed);

        // 2. Unsealed trace or export failure overrides Completed(0) -> ExportFailed(12).
        report.export = Some(sample_export(false, None, true));
        assert_eq!(report.exit_code(), 12);
        assert_eq!(report.result_outcome(), ResultOutcome::ExportFailed);
        assert_eq!(
            report.execution_outcome(),
            Some(ExecutionOutcome::Completed)
        );

        // 3. Export failure overrides Signal(143) -> 12.
        report.signal = Some(CancellationSignal::Terminate);
        report.export = Some(sample_export(
            false,
            Some(ExecutionErrorV1 {
                stage: ExecutionErrorStage::Export,
                code: "writeFailed".into(),
                message: "disk full".into(),
                turn_failure: None,
            }),
            false,
        ));
        assert_eq!(report.exit_code(), 12);
        assert_eq!(report.result_outcome(), ResultOutcome::ExportFailed);

        // 4. Shutdown failure overrides ExportFailed(12) -> ShutdownFailed(13).
        report.shutdown.outcome = StudioShutdownOutcome::Degraded;
        assert_eq!(report.exit_code(), 13);
        assert_eq!(report.result_outcome(), ResultOutcome::ShutdownFailed);

        // 5. Export start failure before runtime start exits 12 without tripping shutdownFailed(13).
        let start_fail_report = ExecutionReport {
            submission: None,
            turn: None,
            final_text: String::new(),
            signal: None,
            error: None,
            shutdown: StudioShutdownReport::not_started(),
            export: None,
            export_error: Some(ExecutionErrorV1 {
                stage: ExecutionErrorStage::Export,
                code: "exportStartFailed".into(),
                message: "cannot write run.json".into(),
                turn_failure: None,
            }),
        };
        assert_eq!(start_fail_report.exit_code(), 12);
        assert_eq!(
            start_fail_report.result_outcome(),
            ResultOutcome::ExportFailed
        );

        // 6. Cancellation before root creation with unsealed export (no failure) keeps 143 instead of 12.
        let pre_root_cancel_report = ExecutionReport {
            submission: None,
            turn: None,
            final_text: String::new(),
            signal: Some(CancellationSignal::Terminate),
            error: None,
            shutdown: clean_shutdown,
            export: Some(sample_export(false, None, false)),
            export_error: None,
        };
        assert_eq!(pre_root_cancel_report.exit_code(), 143);
        assert_eq!(
            pre_root_cancel_report.result_outcome(),
            ResultOutcome::Cancelled
        );
    }
}
