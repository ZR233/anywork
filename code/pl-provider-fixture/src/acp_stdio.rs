//! 场景自有的 ACP 模拟 Agent（`--acp-stdio`）。
//!
//! 它是真正的 ACP 对端：用官方 SDK 的 Agent 角色与 `ByteStreams` 在 stdin/stdout 上完成
//! `initialize`、`authenticate`、`session/new`、`session/close` 与 prompt 拒绝，不在产品代码里
//! 增加假登录或内存凭据开关。模拟凭据以状态目录中的标记文件表示，行为由 `behavior.json`
//! 控制，证据写入有界的 `events.jsonl`。
//!
//! 约定（与验收共享）：
//! - `authenticated` 标记存在才允许 `session/new` 成功；否则返回 `AuthRequired`。
//! - `auth-started` 标记在 `authenticate` 真正被受理后写入。
//! - `authentication: "wait"` 时等待 `auth-release` 标记或对端取消/断线，不用任意 sleep 证明状态。
//! - `disconnect: true` 表示模拟对端崩溃：记录证据后结束进程，客户端只会观察到 EOF。
//!
//! 这个模拟器绝不访问网络、浏览器或用户配置，也不写产品凭据。

use std::fs;
use std::io::{self, BufRead, BufReader, Write};
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use agent_client_protocol::schema::ProtocolVersion;
use agent_client_protocol::schema::v1::{
    AgentCapabilities, AuthMethod, AuthMethodAgent, AuthenticateRequest, AuthenticateResponse,
    CloseSessionRequest, CloseSessionResponse, Implementation, InitializeRequest,
    InitializeResponse, NewSessionRequest, NewSessionResponse, PromptRequest, PromptResponse,
    SessionCapabilities, SessionCloseCapabilities,
};
use agent_client_protocol::{
    Agent, ByteStreams, Client, ConnectionTo, Error as RpcError, Responder,
};
use anyhow::{Context, Result, ensure};
use serde::{Deserialize, Serialize};
use tokio_util::compat::{TokioAsyncReadCompatExt, TokioAsyncWriteCompatExt};

/// 模拟 Agent 唯一声明的方法 ID。
pub const ACP_AUTH_METHOD_ID: &str = "antigravity-fixture-login";
/// 行为控制文件；缺失表示使用默认行为。
pub const ACP_BEHAVIOR_FILE: &str = "behavior.json";
/// 有界协议证据文件。
pub const ACP_EVENTS_FILE: &str = "events.jsonl";
/// 模拟自身凭据：只有登录成功后写入。
pub const ACP_AUTHENTICATED_MARKER: &str = "authenticated";
/// `authenticate` 已被真正受理的标记。
pub const ACP_AUTH_STARTED_MARKER: &str = "auth-started";
/// 解除 `authentication: "wait"` 的控制标记。
pub const ACP_AUTH_RELEASE_MARKER: &str = "auth-release";

/// 成功握手时报出的 server 版本。
///
/// 产品要求实际 server 精确为固定 1.4.1；fixture 的默认身份必须与官方一致，
/// 否则“成功”本身就成了产品策略的反例。
pub const ACP_SERVER_VERSION: &str = crate::acp_install::fixed::SERVER_VERSION;

/// 合成 server 身份。
///
/// 缺失 `serverInfo` 表示产品要求的固定 1.4.1 身份；显式给出空 `version` 表示
/// 省略 agent 信息，用于“版本缺失”负例，不给产品增加任何开关。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpFixtureServerInfo {
    /// 报出的版本；`None` 表示 initialize 不带 agent 信息。
    #[serde(default)]
    pub version: Option<String>,
}

/// 单次运行最多追加的证据记录数，避免证据文件无界增长。
const MAX_EVENT_RECORDS: usize = 512;
/// 等待释放标记的轮询间隔；这是测试环境的控制点，不用于证明生产同步关系。
const RELEASE_POLL: Duration = Duration::from_millis(25);

/// `--acp-stdio` 的选项。
pub struct AcpStdioOptions {
    /// 绝对状态目录：模拟凭据标记、行为控制与证据文件都写在这里。
    pub state_dir: PathBuf,
}

/// 模拟 Agent 的登录行为。
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AcpFixtureAuthentication {
    /// 立即成功并写入模拟凭据。
    #[default]
    Success,
    /// 受理后等待 `auth-release` 标记或对端取消。
    Wait,
    /// 受理后以协议错误失败，不写入模拟凭据。
    Fail,
}

/// 探测会话（`session/new`）的行为。
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AcpFixtureProbe {
    /// 凭据已存在时返回会话，否则返回 `AuthRequired`。
    #[default]
    Normal,
    /// 直接以协议错误失败。
    Fail,
}

/// 行为控制。每次受理请求时按类型重新读取，便于验收在显式场景之间切换。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AcpFixtureBehavior {
    /// 登录行为。
    #[serde(default)]
    pub authentication: AcpFixtureAuthentication,
    /// 探测行为。
    #[serde(default)]
    pub probe: AcpFixtureProbe,
    /// 是否模拟对端断线。
    #[serde(default)]
    pub disconnect: bool,
    /// 合成 server 身份；缺失表示固定 1.4.1。
    #[serde(default)]
    pub server_info: Option<AcpFixtureServerInfo>,
}

/// 有界协议证据记录；只含方法名与 PID，不含用户内容或凭据。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "event", rename_all = "camelCase")]
pub enum AcpFixtureEvent {
    /// 收到 `initialize`。
    Initialize {
        /// 模拟 Agent 的进程号。
        pid: u32,
    },
    /// 收到 `authenticate`。
    Authenticate {
        /// 模拟 Agent 的进程号。
        pid: u32,
    },
    /// 收到 `session/new`。
    SessionNew {
        /// 模拟 Agent 的进程号。
        pid: u32,
    },
    /// 收到 `session/close`。
    Close {
        /// 模拟 Agent 的进程号。
        pid: u32,
    },
    /// 意外收到 prompt，模拟器明确拒绝。
    NoPrompt {
        /// 模拟 Agent 的进程号。
        pid: u32,
    },
    /// 等待中的登录被释放或取消。
    AuthenticateReleased {
        /// 模拟 Agent 的进程号。
        pid: u32,
    },
    /// 模拟对端断线。
    Disconnect {
        /// 模拟 Agent 的进程号。
        pid: u32,
        /// 断线时正在处理的方法名。
        method: String,
    },
}

/// 运行状态：状态目录、进程身份与有界证据写入器。
struct AcpFixtureState {
    state_dir: PathBuf,
    pid: u32,
    sessions: AtomicU64,
    events: Mutex<EventLog>,
}

impl AcpFixtureState {
    fn load(state_dir: PathBuf) -> io::Result<Self> {
        let events = EventLog::load(state_dir.join(ACP_EVENTS_FILE))?;
        Ok(Self {
            state_dir,
            pid: std::process::id(),
            sessions: AtomicU64::new(0),
            events: Mutex::new(events),
        })
    }

    /// 按类型读取行为；缺失使用默认值，损坏则报错而不是静默放行。
    fn behavior(&self) -> io::Result<AcpFixtureBehavior> {
        match fs::read(self.state_dir.join(ACP_BEHAVIOR_FILE)) {
            Ok(bytes) => serde_json::from_slice(&bytes).map_err(io::Error::other),
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                Ok(AcpFixtureBehavior::default())
            }
            Err(error) => Err(error),
        }
    }

    /// 模拟凭据是否已存在。
    fn authenticated(&self) -> bool {
        self.state_dir.join(ACP_AUTHENTICATED_MARKER).exists()
    }

    fn mark(&self, marker: &str) -> io::Result<()> {
        fs::write(self.state_dir.join(marker), b"")
    }

    fn record(&self, event: AcpFixtureEvent) -> io::Result<()> {
        let mut events = match self.events.lock() {
            Ok(events) => events,
            Err(poisoned) => poisoned.into_inner(),
        };
        events.append(&event)
    }

    /// 生成稳定、可区分的模拟会话 ID。
    fn next_session_id(&self) -> String {
        let index = self.sessions.fetch_add(1, Ordering::Relaxed);
        format!("fixture-session-{}-{index}", self.pid)
    }

    /// 等待释放标记；连接结束会取消所在任务，因此不会无限等待。
    async fn wait_for_release(&self) {
        let marker = self.state_dir.join(ACP_AUTH_RELEASE_MARKER);
        let mut ticker = tokio::time::interval(RELEASE_POLL);
        loop {
            if marker.exists() {
                return;
            }
            ticker.tick().await;
        }
    }
}

/// 有界证据写入器；达到上限后停止追加，不覆盖已有记录。
struct EventLog {
    path: PathBuf,
    written: usize,
}

impl EventLog {
    fn load(path: PathBuf) -> io::Result<Self> {
        let written = match fs::File::open(&path) {
            Ok(file) => BufReader::new(file)
                .lines()
                .take(MAX_EVENT_RECORDS)
                .filter(|line| line.as_ref().is_ok_and(|line| !line.trim().is_empty()))
                .count(),
            Err(error) if error.kind() == io::ErrorKind::NotFound => 0,
            Err(error) => return Err(error),
        };
        Ok(Self { path, written })
    }

    fn append(&mut self, event: &AcpFixtureEvent) -> io::Result<()> {
        if self.written >= MAX_EVENT_RECORDS {
            return Ok(());
        }
        let line = serde_json::to_string(event).map_err(io::Error::other)?;
        let mut file = fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&self.path)?;
        writeln!(file, "{line}")?;
        self.written += 1;
        Ok(())
    }
}

/// 运行模拟 Agent 直到对端关闭 stdin。
pub async fn run_acp_stdio(options: AcpStdioOptions) -> Result<()> {
    ensure!(
        options.state_dir.is_absolute(),
        "--acp-state-dir must be an absolute directory"
    );
    fs::create_dir_all(&options.state_dir)
        .with_context(|| format!("failed to create {}", options.state_dir.display()))?;
    let state = Arc::new(AcpFixtureState::load(options.state_dir)?);
    let transport = ByteStreams::new(
        tokio::io::stdout().compat_write(),
        tokio::io::stdin().compat(),
    );
    Agent
        .builder()
        .name("anywork-acp-fixture")
        .on_receive_request(
            {
                let state = Arc::clone(&state);
                async move |
                    _request: InitializeRequest,
                    responder: Responder<InitializeResponse>,
                    _connection: ConnectionTo<Client>,
                | {
                    state
                        .record(AcpFixtureEvent::Initialize { pid: state.pid })
                        .map_err(|error| state_failure("failed to record initialize", error))?;
                    let behavior = state
                        .behavior()
                        .map_err(|error| state_failure("failed to read behavior", error))?;
                    abort_if_disconnected(&state, &behavior, responder.method())?;
                    // 只协商 v1，并声明一个 agent 方法与会话关闭能力。
                    let mut response = InitializeResponse::new(ProtocolVersion::V1)
                            .agent_capabilities(AgentCapabilities::new().session_capabilities(
                                SessionCapabilities::new().close(SessionCloseCapabilities::new()),
                            ))
                            .auth_methods(vec![AuthMethod::Agent(
                                AuthMethodAgent::new(ACP_AUTH_METHOD_ID, "Fixture login")
                                    .description("Synthetic Antigravity login flow"),
                        )]);
                    // 产品要求 server 版本精确为 1.4.1：默认报固定版本，显式负例
                    // 可报别的版本或干脆省略 agent 信息。
                    let version = match behavior.server_info.as_ref() {
                        None => Some(ACP_SERVER_VERSION),
                        Some(info) => info.version.as_deref(),
                    };
                    if let Some(version) = version {
                        response = response.agent_info(
                            Implementation::new("antigravity-fixture", version)
                                    .title("Antigravity fixture"),
                        );
                    }
                    responder.respond(response)
                }
            },
            agent_client_protocol::on_receive_request!(),
        )
        .on_receive_request(
            {
                let state = Arc::clone(&state);
                async move |
                    request: AuthenticateRequest,
                    responder: Responder<AuthenticateResponse>,
                    connection: ConnectionTo<Client>,
                | {
                    let method_id = request.method_id.to_string();
                    state
                        .record(AcpFixtureEvent::Authenticate { pid: state.pid })
                        .map_err(|error| state_failure("failed to record authenticate", error))?;
                    let behavior = state
                        .behavior()
                        .map_err(|error| state_failure("failed to read behavior", error))?;
                    abort_if_disconnected(&state, &behavior, responder.method())?;
                    if method_id != ACP_AUTH_METHOD_ID {
                        return responder
                            .respond_with_error(fixture_failure("unknown authentication method"));
                    }
                    // 只有核验通过、真正进入登录流程时才写受理标记。
                    state
                        .mark(ACP_AUTH_STARTED_MARKER)
                        .map_err(|error| state_failure("failed to mark auth start", error))?;
                    match behavior.authentication {
                        AcpFixtureAuthentication::Fail => responder
                            .respond_with_error(fixture_failure("simulated authentication failure")),
                        AcpFixtureAuthentication::Success => {
                            state.mark(ACP_AUTHENTICATED_MARKER).map_err(|error| {
                                state_failure("failed to persist fixture credential", error)
                            })?;
                            responder.respond(AuthenticateResponse::default())
                        }
                        AcpFixtureAuthentication::Wait => {
                            // 等待交给连接持有的任务，让 dispatch 继续接收取消与 EOF。
                            let cancellation = responder.cancellation();
                            let state = Arc::clone(&state);
                            connection.spawn(async move {
                                tokio::select! {
                                    biased;
                                    () = cancellation.cancelled() => {
                                        state
                                            .record(AcpFixtureEvent::AuthenticateReleased {
                                                pid: state.pid,
                                            })
                                            .map_err(|error| {
                                                state_failure("failed to record cancellation", error)
                                            })?;
                                        responder.respond_with_error(RpcError::request_cancelled())
                                    }
                                    () = state.wait_for_release() => {
                                        state.mark(ACP_AUTHENTICATED_MARKER).map_err(|error| {
                                            state_failure(
                                                "failed to persist fixture credential",
                                                error,
                                            )
                                        })?;
                                        state
                                            .record(AcpFixtureEvent::AuthenticateReleased {
                                                pid: state.pid,
                                            })
                                            .map_err(|error| {
                                                state_failure("failed to record release", error)
                                            })?;
                                        responder.respond(AuthenticateResponse::default())
                                    }
                                }
                            })
                        }
                    }
                }
            },
            agent_client_protocol::on_receive_request!(),
        )
        .on_receive_request(
            {
                let state = Arc::clone(&state);
                async move |
                    _request: NewSessionRequest,
                    responder: Responder<NewSessionResponse>,
                    _connection: ConnectionTo<Client>,
                | {
                    state
                        .record(AcpFixtureEvent::SessionNew { pid: state.pid })
                        .map_err(|error| state_failure("failed to record session/new", error))?;
                    let behavior = state
                        .behavior()
                        .map_err(|error| state_failure("failed to read behavior", error))?;
                    abort_if_disconnected(&state, &behavior, responder.method())?;
                    if behavior.probe == AcpFixtureProbe::Fail {
                        return responder
                            .respond_with_error(fixture_failure("simulated probe failure"));
                    }
                    if !state.authenticated() {
                        // 没有模拟凭据时只报告“需要登录”，不伪造会话。
                        return responder.respond_with_error(RpcError::auth_required());
                    }
                    responder.respond(NewSessionResponse::new(state.next_session_id()))
                }
            },
            agent_client_protocol::on_receive_request!(),
        )
        .on_receive_request(
            {
                let state = Arc::clone(&state);
                async move |
                    _request: CloseSessionRequest,
                    responder: Responder<CloseSessionResponse>,
                    _connection: ConnectionTo<Client>,
                | {
                    state
                        .record(AcpFixtureEvent::Close { pid: state.pid })
                        .map_err(|error| state_failure("failed to record session/close", error))?;
                    responder.respond(CloseSessionResponse::default())
                }
            },
            agent_client_protocol::on_receive_request!(),
        )
        .on_receive_request(
            {
                let state = Arc::clone(&state);
                async move |
                    _request: PromptRequest,
                    responder: Responder<PromptResponse>,
                    _connection: ConnectionTo<Client>,
                | {
                    state
                        .record(AcpFixtureEvent::NoPrompt { pid: state.pid })
                        .map_err(|error| state_failure("failed to record prompt", error))?;
                    // 本阶段不提供任何模型回合：意外 prompt 一律拒绝，绝不访问网络或浏览器。
                    responder.respond_with_error(fixture_failure("fixture rejects prompt turns"))
                }
            },
            agent_client_protocol::on_receive_request!(),
        )
        .connect_to(transport)
        .await
        .map_err(|error| anyhow::anyhow!("ACP fixture connection failed: {error}"))
}

/// `disconnect` 行为：记录证据后结束进程，客户端只能观察到对端断线。
fn abort_if_disconnected(
    state: &AcpFixtureState,
    behavior: &AcpFixtureBehavior,
    method: &str,
) -> Result<(), RpcError> {
    if !behavior.disconnect {
        return Ok(());
    }
    let _ = state.record(AcpFixtureEvent::Disconnect {
        pid: state.pid,
        method: method.to_owned(),
    });
    std::process::exit(0);
}

/// 面向对端的固定错误；不携带任意服务端内容。
fn fixture_failure(message: &'static str) -> RpcError {
    RpcError::internal_error().data(serde_json::json!({ "fixture": message }))
}

/// 状态目录故障：对端只看到固定的安全说明，细节留在 stderr。
fn state_failure(context: &'static str, error: io::Error) -> RpcError {
    eprintln!("anywork ACP fixture: {context}: {error}");
    fixture_failure(context)
}

/// 包内合成控制的成员名：与 peer 打包时写入的成员是同一个名字。
pub const ACP_PACKAGED_CONTROL_MEMBER: &str = crate::acp_install::fixed::AGENT_CONTROL_MEMBER;

/// packaged 模式下读取的合成控制。
///
/// 只携带一条事实：安装树之外的合成 state 目录。行为、标记与证据都由该目录里的
/// 文件控制，所以同一份安装字节可以反复用于不同负例，不需要重装。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpPackagedControl {
    /// 绝对合成 state 目录。
    pub state_dir: PathBuf,
}

/// 当前平台的官方包内入口名。
pub fn official_program_name() -> &'static str {
    if cfg!(windows) {
        crate::acp_install::fixed::WINDOWS_PROGRAM_NAME
    } else {
        crate::acp_install::fixed::LINUX_PROGRAM_NAME
    }
}

/// `name` 是否是当前平台的官方包内入口。
///
/// Windows 的文件名不区分大小写，Unix 区分：比较语义跟随平台，而不是统一放宽。
pub fn is_official_program_name(name: &str) -> bool {
    if cfg!(windows) {
        name.eq_ignore_ascii_case(official_program_name())
    } else {
        name == official_program_name()
    }
}

/// 校验 packaged 模式的 argv 正好是固定官方 argv。
///
/// 官方 1.4.1 清单写的是 `["--uid="]`：Linux 只接受这一个**空值**参数，`--uid=<id>`
/// 这种带值形式也拒绝；Windows 不接受任何参数。其它参数组合（包括 `--version` 与
/// fixture 自有 flag）一律失败，不提供“看见 fixture flags 就切换模式”的旁路。
fn ensure_fixed_argv(argv: &[String]) -> Result<()> {
    if cfg!(windows) {
        ensure!(
            argv.is_empty(),
            "the packaged ACP agent accepts no arguments, got {argv:?}"
        );
        return Ok(());
    }
    ensure!(
        argv.len() == 1 && argv[0] == "--uid=",
        "the packaged ACP agent accepts exactly the fixed official argv `--uid=`, got {argv:?}"
    );
    Ok(())
}

/// 检测当前进程是否被产品以官方包内入口启动，并解析合成控制。
///
/// 返回 `None` 表示这是普通 fixture CLI：basename 不是官方入口时完全不改变原有命令
/// 集合。识别为 packaged 后，argv 必须是固定官方 argv，否则直接失败。
pub fn packaged_agent() -> Result<Option<AcpStdioOptions>> {
    let exe = std::env::current_exe().context("failed to resolve the running program")?;
    let name = exe
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or_default()
        .to_owned();
    if !is_official_program_name(&name) {
        return Ok(None);
    }
    let argv: Vec<String> = std::env::args().skip(1).collect();
    ensure_fixed_argv(&argv)?;
    let control_path = exe.with_file_name(ACP_PACKAGED_CONTROL_MEMBER);
    let bytes = fs::read(&control_path).with_context(|| {
        format!(
            "the packaged ACP agent carries no synthetic control member: {}",
            control_path.display()
        )
    })?;
    let control: AcpPackagedControl = serde_json::from_slice(&bytes).with_context(|| {
        format!(
            "invalid synthetic control member in the packaged agent: {}",
            control_path.display()
        )
    })?;
    ensure!(
        control.state_dir.is_absolute(),
        "the synthetic agent state directory must be absolute: {}",
        control.state_dir.display()
    );
    Ok(Some(AcpStdioOptions {
        state_dir: control.state_dir,
    }))
}
