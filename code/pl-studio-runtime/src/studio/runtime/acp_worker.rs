//! 通用 ACP 程序的物理进程 owner。
//!
//! 这里只通过公共执行器启动已准备的程序、交出三路 stdio，并在关闭时观察根进程和读取任务结束。它不是协议客户端，也不解释 stdout（stdout 只交给 ACP codec）；
//! stderr 独立有界排空，绝不转发原始内容、绝不从中解析 URL 或状态（见 design/28 §28.1）。
//!
//! 收尾结果刻意分三态：[`Reclaim::Stopped`] 已确认停止、[`Reclaim::Settled`] 等待结果已交付
//! 且失败、
//! [`Reclaim::Pending`] 等待系统调用报错但未确认停止（owner 保留，不是终态）。

use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::Arc;
use std::time::Duration;

use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite};
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

use pl_remote_helper::Executor;

/// 连接资源统一关闭预算；耗尽后报告失败并继续等待真实退出。
pub(super) const PROCESS_CLEANUP_LIMIT: Duration = Duration::from_secs(5);
const STDERR_CHUNK_BYTES: usize = 1024;

/// 交给 ACP codec 的写入半边。
pub(super) type ChildWriter = Pin<Box<dyn AsyncWrite + Send>>;
/// 交给 ACP codec 的读取半边。
pub(super) type ChildReader = Pin<Box<dyn AsyncRead + Send>>;
/// Short, non-blocking in-process observation for bounded probe output accounting.
pub(super) type StderrObserver = Arc<dyn Fn(&[u8]) + Send + Sync>;

/// 官方程序需要的宿主环境变量白名单。
///
/// 只有这些键会被显式转交；其余继承来的环境通过 `env_clear` 或 `env_remove` 删除，因此宿主进程
/// 的其它变量（尤其是凭据类）不会进入官方程序。凭据始终由官方程序自行管理，产品的日志与
/// 状态里不出现任何环境值。
const ENV_ALLOWLIST: &[&str] = &[
    "HOME",
    "USER",
    "LOGNAME",
    "SHELL",
    "PATH",
    "TMPDIR",
    "TMP",
    "TEMP",
    "LANG",
    "LC_ALL",
    "LC_CTYPE",
    // 官方网络库可能只读取环境代理；清空这些值会让已配置的登录/onboarding 请求改为直连。
    // 原样透传地址与绕过规则，代理选择仍由宿主配置和官方网络库负责，值不进入日志。
    "HTTP_PROXY",
    "HTTPS_PROXY",
    "ALL_PROXY",
    "NO_PROXY",
    #[cfg(not(windows))]
    "http_proxy",
    #[cfg(not(windows))]
    "https_proxy",
    #[cfg(not(windows))]
    "all_proxy",
    #[cfg(not(windows))]
    "no_proxy",
    "XDG_CONFIG_HOME",
    "XDG_DATA_HOME",
    "XDG_CACHE_HOME",
    "XDG_STATE_HOME",
    "XDG_RUNTIME_DIR",
    // 桌面会话身份：官方程序按这两个宿主值选择显示平台与桌面集成，丢弃它们会让子进程
    // 误判宿主桌面（例如把 Wayland 会话当成 X11）。这里只转发宿主已有取值，不合成、
    // 不覆盖，也不据此强制浏览器平台或凭据后端。
    "XDG_SESSION_TYPE",
    "XDG_CURRENT_DESKTOP",
    // 显示认证上下文：X11 需要 `DISPLAY` 与指向既有 authority 文件的 `XAUTHORITY` 配对，
    // 否则官方程序的浏览器登录无法打开显示。这里只转发宿主已存在的路径，不读取、不记录
    // authority 内容，也不放宽任何 X 访问控制。
    "DISPLAY",
    "XAUTHORITY",
    "WAYLAND_DISPLAY",
    "DBUS_SESSION_BUS_ADDRESS",
    // Windows 的系统与用户目录是原生运行时和官方凭据定位所需的宿主上下文；尤其不能清掉
    // SystemRoot，否则官方 Python server 导入 asyncio 时会因 Winsock 10106 直接退出。
    // std::env::var_os 在 Windows 按原生大小写无关规则读取，不合成任何缺省值。
    #[cfg(windows)]
    "SYSTEMROOT",
    #[cfg(windows)]
    "WINDIR",
    #[cfg(windows)]
    "USERPROFILE",
    #[cfg(windows)]
    "HOMEDRIVE",
    #[cfg(windows)]
    "HOMEPATH",
    #[cfg(windows)]
    "APPDATA",
    #[cfg(windows)]
    "LOCALAPPDATA",
    #[cfg(windows)]
    "USERNAME",
    #[cfg(windows)]
    "COMSPEC",
    #[cfg(windows)]
    "PATHEXT",
];

/// 启动官方程序的进程内请求；只含已校验的绝对程序路径与字面 argv。
pub(super) struct AcpSpawnRequest {
    pub program: PathBuf,
    pub args: Vec<String>,
    pub cwd: PathBuf,
    /// Final environment frozen at launch preparation (host whitelist followed by overrides).
    pub env: std::collections::BTreeMap<std::ffi::OsString, std::ffi::OsString>,
}

/// 物理启动失败的步骤分类；只作为安全诊断标签，不含路径、命令或原始错误文本。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum AcpSpawnStep {
    /// 启动官方程序并接管其 stdio。
    Process,
}

impl AcpSpawnStep {
    /// 稳定的诊断标签；与 `Debug` 输出不同，它不随内部重构或平台变化。
    pub(super) const fn label(self) -> &'static str {
        match self {
            Self::Process => "process",
        }
    }
}

/// 物理启动失败的安全类别；原始原因只作内部诊断。
pub(super) enum AcpSpawnError {
    /// 程序路径不是绝对路径、不是文件或不可执行。
    MissingExecutable,
    /// 启动步骤失败：`step` 是可公开的安全类别，`source` 只在进程内做有界诊断，
    /// 绝不进入产品状态、日志正文或 UI（见 design/28 §28.1）。
    Startup { step: AcpSpawnStep, source: String },
    /// 启动前已经收到取消：不派生任何进程。
    Cancelled,
}

impl std::fmt::Debug for AcpSpawnError {
    /// 手写 `Debug`：只呈现安全类别与来源长度。
    ///
    /// 派生实现会把 `source` 的原始文本带进任何 `{:?}` 输出（包括失败上下文的调试打印），
    /// 与本类型"原始原因绝不进入日志正文或 UI"的约定冲突；`source` 因此只在
    /// 认证或业务启动失败边界读取该字段。本类型不实现 `Error`，不参与错误链公开。
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::MissingExecutable => formatter.write_str("MissingExecutable"),
            Self::Cancelled => formatter.write_str("Cancelled"),
            Self::Startup { step, source } => formatter
                .debug_struct("Startup")
                .field("step", step)
                .field("source_bytes", &source.len())
                .finish(),
        }
    }
}

/// 一次收尾观察的三态结果。
pub(super) enum Reclaim {
    /// 已确认进程与管道停止。
    Stopped,
    /// 等待结果已交付且失败：资源不再由本 owner 等待，可安全呈现失败。
    Settled(String),
    /// 期限内未确认停止：owner 保留，可再次尝试（不是终态）。
    Pending(String),
}

/// 一条 ACP 操作的进程 owner：独占进程、两条业务管道与 stderr 排空任务。
pub(super) struct AcpWorker {
    stdin: Option<ChildWriter>,
    stdout: Option<ChildReader>,
    stderr_task: Option<JoinHandle<std::io::Result<()>>>,
    /// Cached root exit; a wait syscall failure is not evidence of reaping.
    settled: Option<Result<(), String>>,
    /// Actual main-program status, independent of supervisor or cleanup success.
    exit_success: Option<bool>,
    /// stderr 排空任务的终态失败；跨 `Pending` 轮次粘滞保留，不能因进程仍待收束而丢失。
    stderr_failure: Option<String>,
    /// 取消是否已经发出（避免重复发送同一控制指令）。
    cancel_requested: bool,
    child: Option<pl_remote_helper::Child>,
    stderr_stop: CancellationToken,
}

impl AcpWorker {
    /// 启动官方 server 并交出业务管道。
    ///
    /// All supported hosts use the same Executor process owner. A completed spawn is
    /// transferred to this owner even when its caller was cancelled during startup.
    pub(super) async fn spawn(
        request: AcpSpawnRequest,
        source: &Executor,
        cancellation: &CancellationToken,
    ) -> Result<Self, AcpSpawnError> {
        Self::spawn_observed(request, source, cancellation, None).await
    }

    /// Uses the same supervision and drain; the observer must neither block nor publish raw bytes.
    pub(super) async fn spawn_with_stderr_observer(
        request: AcpSpawnRequest,
        source: &Executor,
        cancellation: &CancellationToken,
        observer: StderrObserver,
    ) -> Result<Self, AcpSpawnError> {
        Self::spawn_observed(request, source, cancellation, Some(observer)).await
    }

    async fn spawn_observed(
        request: AcpSpawnRequest,
        source: &Executor,
        cancellation: &CancellationToken,
        stderr_observer: Option<StderrObserver>,
    ) -> Result<Self, AcpSpawnError> {
        if cancellation.is_cancelled() {
            return Err(AcpSpawnError::Cancelled);
        }
        validate_executable(&request.program)?;
        if cancellation.is_cancelled() {
            return Err(AcpSpawnError::Cancelled);
        }
        let program = request
            .program
            .to_str()
            .ok_or(AcpSpawnError::MissingExecutable)?;
        let cwd = request
            .cwd
            .to_str()
            .ok_or(AcpSpawnError::MissingExecutable)?;
        let mut command = source.command(program);
        command
            .args(request.args)
            .current_dir(cwd)
            .env_clear()
            .stdin(pl_remote_helper::Stdio::Piped)
            .stdout(pl_remote_helper::Stdio::Piped)
            .stderr(pl_remote_helper::Stdio::Piped);
        for (key, value) in request.env {
            let key = key.into_string().map_err(|_| AcpSpawnError::Startup {
                step: AcpSpawnStep::Process,
                source: "environment name is not UTF-8".into(),
            })?;
            let value = value.into_string().map_err(|_| AcpSpawnError::Startup {
                step: AcpSpawnStep::Process,
                source: "environment value is not UTF-8".into(),
            })?;
            command.env(key, value);
        }
        let mut child = command
            .spawn()
            .await
            .map_err(|error| AcpSpawnError::Startup {
                step: AcpSpawnStep::Process,
                source: error.to_string(),
            })?;
        let stderr_stop = CancellationToken::new();
        let owner = Self {
            stdin: child.stdin.take().map(|pipe| Box::pin(pipe) as ChildWriter),
            stdout: child
                .stdout
                .take()
                .map(|pipe| Box::pin(pipe) as ChildReader),
            stderr_task: child
                .stderr
                .take()
                .map(|pipe| drain_stderr(pipe, stderr_observer, stderr_stop.clone())),
            child: Some(child),
            stderr_stop,
            settled: None,
            exit_success: None,
            stderr_failure: None,
            cancel_requested: false,
        };
        // A completed spawn is always transferred to an owner, even if cancellation arrived
        // while it was in flight. Its caller's reclaim path owns the actual wait.
        Ok(owner)
    }

    /// 交出业务 stdout/stdin；两路各自只能取一次。
    pub(super) fn take_streams(&mut self) -> Option<(ChildWriter, ChildReader)> {
        Some((self.stdin.take()?, self.stdout.take()?))
    }

    /// Available only after the actual main process has been observed exiting.
    pub(super) fn exit_success(&self) -> Option<bool> {
        self.exit_success
    }

    /// 观察真实退出；future 可取消，句柄和已交付结果始终留在 owner 内。
    pub(super) async fn observe_exit(&mut self) -> Result<(), String> {
        if let Some(settled) = &self.settled {
            return settled.clone();
        }
        let result = match self.child.as_mut() {
            Some(child) => child
                .wait()
                .await
                .map(|status| {
                    self.exit_success = Some(status.success());
                })
                .map_err(|_| "ACP root process wait failed".to_owned()),
            None => Ok(()),
        };
        if result.is_ok() {
            self.settled = Some(result.clone());
        }
        result
    }

    /// Request termination and retain the root/reader owners until their actual completion.
    pub(super) async fn reclaim(&mut self) -> Reclaim {
        let process = self.reclaim_process().await;
        let stderr = self.reclaim_stderr().await;
        combine(process, stderr)
    }

    async fn reclaim_process(&mut self) -> Reclaim {
        self.stdin.take();
        self.stdout.take();
        self.stderr_stop.cancel();
        if self.settled.is_none()
            && !self.cancel_requested
            && let Some(child) = self.child.as_mut()
        {
            match child.start_kill().await {
                Ok(()) => self.cancel_requested = true,
                Err(_) => {
                    return Reclaim::Pending("ACP termination request was not confirmed".into());
                }
            }
        }
        let result = self.observe_exit().await;
        match result {
            Ok(()) => Reclaim::Stopped,
            Err(issue) if self.settled.is_some() => Reclaim::Settled(issue),
            Err(issue) => Reclaim::Pending(issue),
        }
    }

    /// 借用真实 JoinHandle 等待 EOF；预算耗尽或取消等待不会丢失任务句柄。
    async fn reclaim_stderr(&mut self) -> Reclaim {
        if let Some(issue) = &self.stderr_failure {
            return Reclaim::Settled(issue.clone());
        }
        let Some(task) = self.stderr_task.as_mut() else {
            return Reclaim::Stopped;
        };
        let outcome = task.await;
        self.stderr_task = None;
        match outcome {
            Ok(Ok(())) => Reclaim::Stopped,
            Ok(Err(_)) | Err(_) => {
                let issue = "ACP stderr drain task failed".to_string();
                self.stderr_failure = Some(issue.clone());
                Reclaim::Settled(issue)
            }
        }
    }
}

/// 合并进程与管道的收尾观察：只要有一项仍待收束，整体就是 `Pending`。
fn combine(process: Reclaim, stderr: Reclaim) -> Reclaim {
    let mut pending = Vec::new();
    let mut settled = Vec::new();
    for outcome in [process, stderr] {
        match outcome {
            Reclaim::Stopped => {}
            Reclaim::Settled(issue) => settled.push(issue),
            Reclaim::Pending(issue) => pending.push(issue),
        }
    }
    if !pending.is_empty() {
        Reclaim::Pending(pending.join("; "))
    } else if !settled.is_empty() {
        Reclaim::Settled(settled.join("; "))
    } else {
        Reclaim::Stopped
    }
}

pub(super) fn launch_environment(
    overrides: &std::collections::BTreeMap<String, String>,
) -> std::collections::BTreeMap<std::ffi::OsString, std::ffi::OsString> {
    let mut environment = std::collections::BTreeMap::new();
    for key in ENV_ALLOWLIST {
        if let Some(value) = std::env::var_os(key) {
            environment.insert((*key).into(), value);
        }
    }
    for (key, value) in overrides {
        // Environment names are case-insensitive on Windows.
        #[cfg(windows)]
        environment.retain(|existing: &std::ffi::OsString, _| {
            !existing.to_string_lossy().eq_ignore_ascii_case(key)
        });
        environment.insert(key.into(), value.into());
    }
    environment
}

/// 校验程序是显式绝对路径且为普通文件；保存阶段不做这种检查。
fn validate_executable(program: &Path) -> Result<(), AcpSpawnError> {
    if !program.is_absolute() {
        return Err(AcpSpawnError::MissingExecutable);
    }
    match std::fs::metadata(program) {
        Ok(metadata) if metadata.is_file() => Ok(()),
        _ => Err(AcpSpawnError::MissingExecutable),
    }
}

/// 有界排空 stderr：只消费，不转发、不解析，也不让它阻塞业务管道。
fn drain_stderr(
    mut stderr: impl AsyncRead + Unpin + Send + 'static,
    observer: Option<StderrObserver>,
    stop: CancellationToken,
) -> JoinHandle<std::io::Result<()>> {
    tokio::spawn(async move {
        let mut buffer = [0u8; STDERR_CHUNK_BYTES];
        let mut total = 0usize;
        loop {
            let read = tokio::select! { result=stderr.read(&mut buffer)=>result,_=stop.cancelled()=>return Ok(()) };
            match read {
                Ok(0) => break,
                Ok(read) => {
                    total = total.saturating_add(read);
                    if let Some(observer) = &observer {
                        observer(&buffer[..read]);
                    }
                }
                Err(error) if error.kind() == std::io::ErrorKind::Interrupted => {}
                Err(error) => return Err(error),
            }
        }
        // 只有字节数进入诊断；原始 stderr 既不发布给 UI，也不写入日志。
        tracing::debug!(bytes = total, "ACP server stderr drained");
        Ok(())
    })
}
