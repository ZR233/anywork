//! A noninteractive adapter of the production Studio lifecycle, without a second agent loop.
mod args;
mod signals;
mod text;

pub use args::{Cli, Command, ExecArgs, PreparedExec};
pub use signals::SignalListener;

use anyhow::{Context, Result};
use pl_protocol::{
    ThreadNotification, ThreadSubscriptionUpdate, ThreadWorkspaceMode, Turn, TurnCompletion,
    TurnState, studio::StudioPromptInput,
};
use pl_studio_runtime::{
    StudioPendingPersistence, StudioRuntime, StudioShutdownOutcome, StudioShutdownReport,
    StudioStartNewThreadRequest, StudioStartupError, StudioStartupErrorKind,
    StudioSubmitPromptOptions,
};
use std::future::Future;

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

/// Retains the actual task identity, native terminal and shutdown report for later exporters.
#[derive(Debug)]
pub struct ExecutionReport {
    pub submission: Option<pl_studio_runtime::StudioSubmitPromptResponse>,
    pub turn: Option<Turn>,
    pub final_text: String,
    pub signal: Option<CancellationSignal>,
    pub error: Option<ExecutionError>,
    pub shutdown: StudioShutdownReport,
}

impl ExecutionReport {
    pub fn exit_code(&self) -> u8 {
        if self.shutdown.outcome != StudioShutdownOutcome::Clean
            && !(self.submission.is_none()
                && matches!(self.error, Some(ExecutionError::Startup(_)))
                && self.shutdown.outcome == StudioShutdownOutcome::NotStarted)
            || self.shutdown.persistence != StudioPendingPersistence::Drained
        {
            return 13;
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
    request: PreparedExec,
    signal: impl Future<Output = CancellationSignal>,
    observer: std::sync::Arc<dyn Fn(pl_studio_runtime::StudioStartupStage) + Send + Sync>,
) -> ExecutionReport {
    let mut signal = std::pin::pin!(signal);
    let mut report = ExecutionReport {
        submission: None,
        turn: None,
        final_text: String::new(),
        signal: None,
        error: None,
        shutdown: StudioShutdownReport::not_started(),
    };
    let runtime = match latch_during(
        StudioRuntime::initialize_with_observer(request.runtime, observer),
        signal.as_mut(),
        &mut report.signal,
    )
    .await
    {
        Ok(runtime) => runtime,
        Err(error) => {
            report.error = Some(error.into());
            return report;
        }
    };
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
        tokio::select! { biased;
            caught = signal.as_mut() => report.signal = Some(caught),
            result = task => match result {
                Ok(turn) => report.turn = Some(turn),
                Err(error) => report.error = Some(ExecutionError::Runtime(error)),
            }
        }
    }
    if report.signal.is_none()
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
    report.shutdown = latch_during(
        runtime.shutdown_runtime_for_exit(SHUTDOWN_BUDGET_MS, Vec::new()),
        signal.as_mut(),
        &mut report.signal,
    )
    .await;
    report
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
}
