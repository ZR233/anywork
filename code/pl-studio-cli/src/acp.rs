//! Noninteractive ACP adapter over the original Studio session owner and observation.
use std::{
    future::Future,
    io::Read,
    path::{Path, PathBuf},
    pin::Pin,
};

use anyhow::{Context, Result, ensure};
use clap::Args;
use pl_studio_runtime::{
    AcpBusinessFailure, AcpBusinessFailureKind, AcpBusinessSnapshot, AcpCompletedRun,
    AcpOpenIntent, AcpRunId, AcpSessionEvent, AcpSessionObservation, AcpSessionTarget,
    OpenAcpSessionRequest, SessionConfigId, SessionConfigOptionValue, SkillSearchOptions,
    StudioPendingPersistence, StudioRuntime, StudioRuntimeOptions, StudioShutdownOutcome,
    StudioShutdownReport, StudioStartupErrorKind, ThreadWorkspaceMode,
    acp_schema::{
        ContentBlock, SessionConfigKind, SessionConfigSelectOptions, SessionUpdate, StopReason,
        TextContent,
    },
};

use crate::{CancellationSignal, SHUTDOWN_BUDGET_MS, latch_during};

#[derive(Args)]
pub struct AcpOptionsArgs {
    /// 显式 Studio 数据根，必须已有有效 config.toml。
    #[arg(long, value_name = "PATH")]
    pub studio_home: PathBuf,
    /// 已存在的本地任务目录，允许非 Git 目录。
    #[arg(long, value_name = "PATH")]
    pub cwd: PathBuf,
    /// 已配置的 ACP 账号 ID，不是显示名。
    #[arg(long, value_name = "ACP_ID")]
    pub account: String,
}

#[derive(Args)]
pub struct ExecAcpArgs {
    #[command(flatten)]
    pub session: AcpOptionsArgs,
    /// UTF-8 任务文件；- 从标准输入读取至结束。
    #[arg(long, value_name = "PATH")]
    pub prompt_file: PathBuf,
    /// 对端声明的配置 ID=值 ID；可重复，按出现顺序设置并回读。
    #[arg(long, value_name = "ID=VALUE", value_parser = parse_config)]
    pub config: Vec<(String, String)>,
    /// 关闭隐式用户技能来源，不影响显式目录。
    #[arg(long)]
    pub no_default_user_skills: bool,
    /// 追加只读技能集合根，可重复。
    #[arg(long, value_name = "PATH")]
    pub skill_dir: Vec<PathBuf>,
}

fn parse_config(value: &str) -> std::result::Result<(String, String), String> {
    let (id, value) = value.split_once('=').ok_or("配置必须为 ID=VALUE")?;
    if id.is_empty() || value.is_empty() {
        return Err("配置 ID 和值不能为空".into());
    }
    Ok((id.into(), value.into()))
}

pub struct PreparedAcp {
    runtime: StudioRuntimeOptions,
    cwd: PathBuf,
    account: String,
    prompt: Option<String>,
    config: Vec<(String, String)>,
}

impl AcpOptionsArgs {
    pub fn prepare(self, startup_cwd: &Path) -> Result<PreparedAcp> {
        let resolve = |path: &Path| pl_tool::workspace::resolve_absolute_path(startup_cwd, path);
        let studio_home = resolve(&self.studio_home)?;
        let cwd = resolve(&self.cwd)?;
        ensure!(
            std::fs::metadata(&cwd)
                .context("无法访问任务目录")?
                .is_dir(),
            "任务路径不是目录"
        );
        std::fs::read_dir(&cwd)
            .context("无法读取任务目录")?
            .next()
            .transpose()?;
        std::fs::File::open(studio_home.join("config.toml"))
            .context("必须提供已有的 config.toml")?;
        ensure!(!self.account.trim().is_empty(), "ACP 账号 ID 不能为空");
        Ok(PreparedAcp {
            runtime: StudioRuntimeOptions::cli(studio_home),
            cwd,
            account: self.account,
            prompt: None,
            config: Vec::new(),
        })
    }
}

impl ExecAcpArgs {
    pub fn prepare(self, startup_cwd: &Path, stdin: impl Read) -> Result<PreparedAcp> {
        let mut prepared = self.session.prepare(startup_cwd)?;
        let mut input: Box<dyn Read + '_> = if self.prompt_file == Path::new("-") {
            Box::new(stdin)
        } else {
            let path = pl_tool::workspace::resolve_absolute_path(startup_cwd, &self.prompt_file)?;
            Box::new(std::fs::File::open(path).context("无法打开任务文件")?)
        };
        let mut prompt = String::new();
        input
            .read_to_string(&mut prompt)
            .context("任务必须为有效 UTF-8 文本")?;
        ensure!(!prompt.trim().is_empty(), "任务正文不能为空白");
        prepared.runtime.skill_search =
            SkillSearchOptions::resolve(!self.no_default_user_skills, self.skill_dir, startup_cwd)?;
        prepared.prompt = Some(prompt);
        prepared.config = self.config;
        Ok(prepared)
    }
}

/// ACP identities and terminal facts are not Native Turns or execution exports.
#[derive(Debug)]
pub struct AcpExecutionReport {
    pub run: Option<AcpRunId>,
    pub completed: Option<AcpCompletedRun>,
    pub output: String,
    pub signal: Option<CancellationSignal>,
    pub error: Option<String>,
    pub shutdown: StudioShutdownReport,
    failure_code: u8,
    runtime_started: bool,
}

impl AcpExecutionReport {
    pub fn exit_code(&self) -> u8 {
        if (self.runtime_started && self.shutdown.outcome != StudioShutdownOutcome::Clean)
            || self.shutdown.persistence != StudioPendingPersistence::Drained
        {
            13
        } else if let Some(signal) = self.signal {
            signal.exit_code()
        } else {
            self.failure_code
        }
    }
}

struct Failure {
    code: u8,
    message: String,
}
impl Failure {
    fn input(message: impl Into<String>) -> Self {
        Self {
            code: 2,
            message: message.into(),
        }
    }
    fn runtime(message: impl Into<String>) -> Self {
        Self {
            code: 11,
            message: message.into(),
        }
    }
    fn business(error: AcpBusinessFailure) -> Self {
        Self {
            code: match error.kind {
                AcpBusinessFailureKind::InvalidOption
                | AcpBusinessFailureKind::InvalidDefinition
                | AcpBusinessFailureKind::InvalidWorkingDirectory => 2,
                AcpBusinessFailureKind::InstallRequired
                | AcpBusinessFailureKind::InstallationInvalid
                | AcpBusinessFailureKind::UnsupportedPlatform
                | AcpBusinessFailureKind::MissingExecutable
                | AcpBusinessFailureKind::Io => 11,
                _ => 10,
            },
            message: format!("{error:?}"),
        }
    }

    fn environment(error: anyhow::Error) -> Self {
        if let Some(failure) = error.downcast_ref::<AcpBusinessFailure>() {
            Self::business(failure.clone())
        } else {
            Self::runtime(format!("{error:?}"))
        }
    }
}

pub async fn execute_acp(
    request: PreparedAcp,
    signal: impl Future<Output = CancellationSignal>,
) -> AcpExecutionReport {
    let mut signal = std::pin::pin!(signal);
    let mut report = AcpExecutionReport {
        run: None,
        completed: None,
        output: String::new(),
        signal: None,
        error: None,
        shutdown: StudioShutdownReport::not_started(),
        failure_code: 0,
        runtime_started: false,
    };
    let runtime = match latch_during(
        StudioRuntime::initialize_acp_cli(request.runtime),
        signal.as_mut(),
        &mut report.signal,
    )
    .await
    {
        Ok(runtime) => runtime,
        Err(error) => {
            report.failure_code = match error.kind {
                StudioStartupErrorKind::Configuration
                | StudioStartupErrorKind::RecoveryRequired
                | StudioStartupErrorKind::PersistentData
                | StudioStartupErrorKind::Migration => 2,
                _ => 11,
            };
            report.error = Some(format!("{error:?}"));
            return report;
        }
    };
    report.runtime_started = true;
    if report.signal.is_none()
        && let Err(error) = run_session(
            &runtime,
            request.cwd,
            request.account,
            request.prompt,
            request.config,
            signal.as_mut(),
            &mut report,
        )
        .await
    {
        report.failure_code = error.code;
        report.error = Some(error.message);
    }
    report.shutdown = latch_during(
        runtime.shutdown_runtime_for_exit(SHUTDOWN_BUDGET_MS, Vec::new()),
        signal.as_mut(),
        &mut report.signal,
    )
    .await;
    if report.exit_code() != 0 {
        report.output.clear();
    }
    report
}

async fn run_session<S: Future<Output = CancellationSignal>>(
    runtime: &StudioRuntime,
    cwd: PathBuf,
    account: String,
    prompt: Option<String>,
    configs: Vec<(String, String)>,
    mut signal: Pin<&mut S>,
    report: &mut AcpExecutionReport,
) -> std::result::Result<(), Failure> {
    let settings = runtime.read_settings().map_err(Failure::environment)?;
    let account = settings
        .config
        .settings
        .acp_accounts
        .iter()
        .find(|a| a.account_id == account)
        .ok_or_else(|| Failure::input("ACP 账号 ID 不存在"))?;
    if !account.enabled {
        return Err(Failure::input("ACP 账号未启用"));
    }
    let project = latch_during(
        runtime.open_project(&cwd),
        signal.as_mut(),
        &mut report.signal,
    )
    .await
    .map_err(Failure::environment)?;
    if report.signal.is_some() {
        return Ok(());
    }
    let open = latch_during(
        runtime.open_acp_session(OpenAcpSessionRequest {
            account_id: account.account_id.clone(),
            expected_connection_revision: account.connection_revision,
            workspace_id: project.id,
            thread_id: None,
            // Discovery must not publish an empty conversation; execution uses normal membership.
            intent: if prompt.is_some() {
                AcpOpenIntent::New
            } else {
                AcpOpenIntent::Draft {
                    workspace_mode: ThreadWorkspaceMode::Local,
                    delegation_mode: None,
                    delegation_preference: None,
                    mode: None,
                }
            },
        }),
        signal.as_mut(),
        &mut report.signal,
    )
    .await
    .map_err(Failure::environment)?;
    if report.signal.is_some() {
        return Ok(());
    }
    let target = open.target;
    let mut observation = open
        .observation
        .ok_or_else(|| Failure::runtime("新 ACP 会话没有原始观察流"))?;
    let mut capabilities = None;
    loop {
        let Some(event) = next_event(&mut observation, signal.as_mut(), report).await? else {
            return Ok(());
        };
        match event {
            AcpSessionEvent::Initialized {
                capabilities: value,
                ..
            } => capabilities = Some(value),
            AcpSessionEvent::Ready { .. } => break,
            event => check_event(runtime, &target, event).await?,
        }
    }
    let initial = snapshot(runtime, &target).await?;
    if prompt.is_none() {
        let capabilities = capabilities.ok_or_else(|| Failure::runtime("ACP 未声明初始化能力"))?;
        report.output = serde_json::to_string_pretty(&serde_json::json!({
            "capabilities": capabilities,
            "configOptions": initial.config_options,
            "modes": initial.modes,
            "acpSessionId": initial.acp_session_id,
        }))
        .map_err(|e| Failure::runtime(e.to_string()))?;
        return Ok(());
    }
    let mut requested = Vec::new();
    for (id, value) in configs {
        let before = snapshot(runtime, &target).await?;
        let option = before
            .config_options
            .as_ref()
            .and_then(|options| options.iter().find(|option| option.id.to_string() == id))
            .ok_or_else(|| Failure::input(format!("对端未声明配置 ID {id:?}")))?;
        let value = validate_value(&option.kind, &value)?;
        // This future observes a configuration already owned by the ACP driver. A signal must
        // stop observing and enter the runtime's close/join path, not await a stuck peer here.
        tokio::select! { biased;
            caught = signal.as_mut() => {
                report.signal = Some(caught);
                return Ok(());
            }
            result = runtime.configure_acp_session(
                target.clone(),
                SessionConfigId::new(id.clone()),
                value.clone(),
            ) => result.map_err(Failure::business)?,
        }
        if report.signal.is_some() {
            return Ok(());
        }
        let after = snapshot(runtime, &target).await?;
        let confirmed = after
            .config_options
            .as_ref()
            .and_then(|options| options.iter().find(|option| option.id.to_string() == id))
            .is_some_and(|option| current_value(&option.kind).as_ref() == Some(&value));
        if !confirmed {
            return Err(Failure::input(format!("ACP 配置 {id:?} 回读与请求不一致")));
        }
        requested.retain(|(previous, _)| previous != &id);
        requested.push((id, value));
    }
    if report.signal.is_some() {
        return Ok(());
    }
    let final_config = snapshot(runtime, &target).await?;
    for (id, value) in requested {
        let confirmed = final_config
            .config_options
            .as_ref()
            .and_then(|options| options.iter().find(|option| option.id.to_string() == id))
            .is_some_and(|option| current_value(&option.kind).as_ref() == Some(&value));
        if !confirmed {
            return Err(Failure::input(format!(
                "ACP 后续配置改变了已请求的 {id:?}，未提交任务"
            )));
        }
    }
    let Some(prompt) = prompt else {
        return Err(Failure::input("缺少 ACP 任务正文"));
    };
    let run = tokio::select! { biased;
        caught = signal.as_mut() => {
            report.signal = Some(caught);
            return Ok(());
        }
        result = runtime.prompt_acp_session(
            target.clone(),
            vec![ContentBlock::Text(TextContent::new(prompt))],
        ) => result.map_err(Failure::business)?,
    };
    report.run = Some(run);
    if report.signal.is_some() {
        return Ok(());
    }
    loop {
        let Some(event) = next_event(&mut observation, signal.as_mut(), report).await? else {
            return Ok(());
        };
        match event {
            AcpSessionEvent::Update { update, .. } => {
                if let SessionUpdate::AgentMessageChunk(chunk) = update.update
                    && let ContentBlock::Text(text) = chunk.content
                {
                    report.output.push_str(&text.text);
                }
            }
            AcpSessionEvent::Completed { completed } => {
                if completed.run != run {
                    return Err(Failure::runtime("ACP 终态运行身份不匹配"));
                }
                let result = completed.result.clone();
                report.completed = Some(completed);
                let response = result.map_err(Failure::business)?;
                if response.stop_reason != StopReason::EndTurn {
                    return Err(Failure {
                        code: 10,
                        message: format!("ACP 非正常停止: {:?}", response.stop_reason),
                    });
                }
                snapshot(runtime, &target).await?;
                return Ok(());
            }
            event => check_event(runtime, &target, event).await?,
        }
    }
}

async fn next_event<S: Future<Output = CancellationSignal>>(
    observation: &mut AcpSessionObservation,
    signal: Pin<&mut S>,
    report: &mut AcpExecutionReport,
) -> std::result::Result<Option<AcpSessionEvent>, Failure> {
    tokio::select! { biased;
        caught = signal => { report.signal = Some(caught); Ok(None) }
        event = observation.recv() => event.map(Some).ok_or_else(|| Failure::runtime("ACP 观察流断连")),
    }
}

async fn check_event(
    runtime: &StudioRuntime,
    target: &AcpSessionTarget,
    event: AcpSessionEvent,
) -> std::result::Result<(), Failure> {
    match event {
        AcpSessionEvent::Failed { error } => Err(Failure::business(error)),
        AcpSessionEvent::Gap { gap } => Err(Failure::runtime(format!("ACP 观察缺口: {gap:?}"))),
        AcpSessionEvent::Permission { id, .. } => {
            let rejected = runtime
                .answer_acp_permission(target.clone(), id, None)
                .await;
            Err(Failure {
                code: 3,
                message: match rejected {
                    Ok(()) => "ACP 等待权限，非交互执行已拒绝请求".into(),
                    Err(error) => format!("ACP 等待权限，拒绝请求失败: {error:?}"),
                },
            })
        }
        _ => Ok(()),
    }
}

async fn snapshot(
    runtime: &StudioRuntime,
    target: &AcpSessionTarget,
) -> std::result::Result<AcpBusinessSnapshot, Failure> {
    let snapshot = runtime
        .acp_session_snapshot(target.clone())
        .await
        .map_err(Failure::business)?;
    if snapshot.observation_gap.is_some()
        || !snapshot.ready
        || snapshot.closing
        || snapshot.config_pending
    {
        return Err(Failure::runtime(format!("ACP 会话不可执行: {snapshot:?}")));
    }
    Ok(snapshot)
}

fn validate_value(
    kind: &SessionConfigKind,
    value: &str,
) -> std::result::Result<SessionConfigOptionValue, Failure> {
    match kind {
        SessionConfigKind::Select(select) => {
            let accepted = match &select.options {
                SessionConfigSelectOptions::Ungrouped(options) => {
                    options.iter().any(|o| o.value.to_string() == value)
                }
                SessionConfigSelectOptions::Grouped(groups) => groups
                    .iter()
                    .any(|g| g.options.iter().any(|o| o.value.to_string() == value)),
                _ => false,
            };
            if !accepted {
                return Err(Failure::input(format!("对端未声明配置值 ID {value:?}")));
            }
            Ok(SessionConfigOptionValue::ValueId {
                value: value.to_owned().into(),
            })
        }
        SessionConfigKind::Boolean(_) => match value {
            "true" => Ok(SessionConfigOptionValue::Boolean { value: true }),
            "false" => Ok(SessionConfigOptionValue::Boolean { value: false }),
            _ => Err(Failure::input("布尔配置只接受 true 或 false")),
        },
        _ => Err(Failure::input("不支持的 ACP 配置类型")),
    }
}

fn current_value(kind: &SessionConfigKind) -> Option<SessionConfigOptionValue> {
    match kind {
        SessionConfigKind::Select(select) => Some(SessionConfigOptionValue::ValueId {
            value: select.current_value.clone(),
        }),
        SessionConfigKind::Boolean(boolean) => Some(SessionConfigOptionValue::Boolean {
            value: boolean.current_value,
        }),
        _ => None,
    }
}
