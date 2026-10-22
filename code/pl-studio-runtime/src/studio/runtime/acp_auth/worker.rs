//! 官方 ACP server 的物理进程 owner。
//!
//! 这里只做三件事：按平台用**现有**后台进程工厂启动官方程序、交出三路 stdio、在关闭时确认
//! 整棵进程与管道真实退出。它不是协议客户端，也不解释 stdout（stdout 只交给 ACP codec）；
//! stderr 独立有界排空，绝不转发原始内容、绝不从中解析 URL 或状态（见 design/27 §27.1）。
//!
//! 收尾结果刻意分三态：[`Reclaim::Stopped`] 已确认停止、[`Reclaim::Settled`] 等待结果已交付
//! 且失败（`ManagedWorker::wait` 只在监督者真实退出后才交付错误，之后绝不再 wait）、
//! [`Reclaim::Pending`] 期限内未确认停止（owner 保留，可再次尝试，不是终态）。

#[cfg(target_os = "linux")]
use std::ffi::OsStr;
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::time::Duration;

use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite};
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

use crate::worker_assets::RemoteHelperSource;

/// 首次收尾等待上限；超过后升级为更强终止并继续等待真实退出。
pub(super) const PROCESS_CLEANUP_LIMIT: Duration = Duration::from_secs(5);
/// 强制终止后的第二次等待上限。
pub(super) const PROCESS_KILL_LIMIT: Duration = Duration::from_secs(5);
/// stderr 有界排空的字节预算；超过预算后继续读到 EOF 但不再保存。
pub(super) const STDERR_BUDGET_BYTES: usize = 8 * 1024;
const STDERR_CHUNK_BYTES: usize = 1024;

/// 交给 ACP codec 的写入半边。
pub(super) type ChildWriter = Pin<Box<dyn AsyncWrite + Send>>;
/// 交给 ACP codec 的读取半边。
pub(super) type ChildReader = Pin<Box<dyn AsyncRead + Send>>;

/// 官方程序需要的宿主环境变量白名单。
///
/// 只有这些键会被显式转交；**其余继承来的环境一律显式删除**（`env_remove`），因此宿主进程
/// 的其它变量（尤其是凭据类）不会进入官方程序。凭据始终由官方程序自行管理，产品的日志与
/// 状态里不出现任何环境值。
const ENV_ALLOWLIST: [&str; 22] = [
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
];

/// 启动官方程序的进程内请求；只含已校验的绝对程序路径与字面 argv。
pub(super) struct AcpSpawnRequest {
    pub program: PathBuf,
    pub args: Vec<String>,
    pub cwd: PathBuf,
}

/// 物理启动失败的步骤分类；只作为安全诊断标签，不含路径、命令或原始错误文本。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum AcpSpawnStep {
    /// 准备本账号私有的探测目录。
    ProbeDirectory,
    /// 解析并缓存受监督 worker 的可执行镜像。
    WorkerAsset,
    /// 启动官方程序并接管其 stdio。
    Process,
}

impl AcpSpawnStep {
    /// 稳定的诊断标签；与 `Debug` 输出不同，它不随内部重构或平台变化。
    pub(super) const fn label(self) -> &'static str {
        match self {
            Self::ProbeDirectory => "probeDirectory",
            Self::WorkerAsset => "workerAsset",
            Self::Process => "process",
        }
    }
}

/// 物理启动失败的安全类别；原始原因只作内部诊断。
pub(super) enum AcpSpawnError {
    /// 程序路径不是绝对路径、不是文件或不可执行。
    MissingExecutable,
    /// 启动步骤失败：`step` 是可公开的安全类别，`source` 只在进程内做有界诊断，
    /// 绝不进入产品状态、日志正文或 UI（见 design/27 §27.1）。
    Startup { step: AcpSpawnStep, source: String },
    /// 启动前已经收到取消：不派生任何进程。
    Cancelled,
}

impl std::fmt::Debug for AcpSpawnError {
    /// 手写 `Debug`：只呈现安全类别与来源长度。
    ///
    /// 派生实现会把 `source` 的原始文本带进任何 `{:?}` 输出（包括失败上下文的调试打印），
    /// 与本类型"原始原因绝不进入日志正文或 UI"的约定冲突；`source` 因此只在
    /// [`super::operation`] 的启动失败边界被读取。本类型不实现 `Error`，不参与错误链公开。
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
    stderr_task: Option<JoinHandle<()>>,
    /// 已交付的物理退出结果；一旦交付就绝不再 `wait`。
    ///
    /// 只有"退出已确认"或"监督者在真实退出后交付了错误"才会写入；非 Linux 的普通 `wait`
    /// 系统调用错误不是退出证明，因此不会进入这里。
    settled: Option<Result<(), String>>,
    /// stderr 排空任务的终态失败；跨 `Pending` 轮次粘滞保留，不能因进程仍待收束而丢失。
    stderr_failure: Option<String>,
    /// 取消是否已经发出（避免重复发送同一控制指令）。
    cancel_requested: bool,
    #[cfg(target_os = "linux")]
    supervisor: Option<pl_remote_helper::client::ManagedWorker>,
    #[cfg(not(target_os = "linux"))]
    child: Option<Box<dyn process_wrap::tokio::ChildWrapper>>,
}

impl AcpWorker {
    /// 启动官方 server 并交出业务管道。
    ///
    /// Linux 复用与本地工具执行、MCP stdio 相同的 bundled supervised worker：GUI 被强杀时整个
    /// 进程树仍由内核/监督者回收。其他平台复用统一后台进程工厂（process-wrap）。
    ///
    /// 取消检查发生在**准备探测目录前**、异步解析受监督 worker 之后、以及真正 spawn 之前。
    /// 一旦开始 `spawn`，调用方直接 await 并接管返回的 worker，绝不用 `select!` 丢弃可能已持有
    /// 进程的 future。
    pub(super) async fn spawn(
        request: AcpSpawnRequest,
        source: &WorkerSource,
        cancellation: &CancellationToken,
    ) -> Result<Self, AcpSpawnError> {
        if cancellation.is_cancelled() {
            return Err(AcpSpawnError::Cancelled);
        }
        validate_executable(&request.program)?;
        std::fs::create_dir_all(&request.cwd).map_err(|error| AcpSpawnError::Startup {
            step: AcpSpawnStep::ProbeDirectory,
            source: error.to_string(),
        })?;
        if cancellation.is_cancelled() {
            return Err(AcpSpawnError::Cancelled);
        }
        #[cfg(target_os = "linux")]
        {
            Self::spawn_supervised(request, source, cancellation).await
        }
        #[cfg(not(target_os = "linux"))]
        {
            source.resolve().await?;
            if cancellation.is_cancelled() {
                return Err(AcpSpawnError::Cancelled);
            }
            Self::spawn_wrapped(request, cancellation).await
        }
    }

    /// 交出业务 stdout/stdin；两路各自只能取一次。
    pub(super) fn take_streams(&mut self) -> Option<(ChildWriter, ChildReader)> {
        Some((self.stdin.take()?, self.stdout.take()?))
    }

    /// 请求终止并观察收尾结果；只有 `Stopped` 表示已确认回收。
    pub(super) async fn reclaim(&mut self) -> Reclaim {
        let process = self.reclaim_process().await;
        let stderr = self.reclaim_stderr().await;
        combine(process, stderr)
    }

    async fn reclaim_process(&mut self) -> Reclaim {
        if let Some(settled) = self.settled.as_ref() {
            return match settled {
                Ok(()) => Reclaim::Stopped,
                Err(issue) => Reclaim::Settled(issue.clone()),
            };
        }
        #[cfg(target_os = "linux")]
        {
            let Some(supervisor) = self.supervisor.as_mut() else {
                self.settled = Some(Ok(()));
                return Reclaim::Stopped;
            };
            if !self.cancel_requested {
                let control = supervisor.control();
                if control.cancel().await.is_err() {
                    // 控制通道已经不可写：封闭租约后仍然等待真实退出，不把通道错误当成已回收。
                    control.close();
                }
                self.cancel_requested = true;
            }
            match tokio::time::timeout(PROCESS_CLEANUP_LIMIT, supervisor.wait()).await {
                Ok(Ok(_termination)) => {
                    self.settled = Some(Ok(()));
                    Reclaim::Stopped
                }
                Ok(Err(error)) => {
                    // wait 只在监督者真实退出后交付错误；记录已交付，后续绝不再 wait。
                    let issue = format!("ACP supervisor wait failed: {error}");
                    self.settled = Some(Err(issue.clone()));
                    Reclaim::Settled(issue)
                }
                Err(_) => {
                    // 超时保留 supervisor 与 lease 供再次 wait；先升级一次更强终止。
                    let control = supervisor.control();
                    let _ = control.retry_cleanup().await;
                    match tokio::time::timeout(PROCESS_KILL_LIMIT, supervisor.wait()).await {
                        Ok(Ok(_termination)) => {
                            self.settled = Some(Ok(()));
                            Reclaim::Stopped
                        }
                        Ok(Err(error)) => {
                            let issue = format!("ACP supervisor wait failed: {error}");
                            self.settled = Some(Err(issue.clone()));
                            Reclaim::Settled(issue)
                        }
                        Err(_) => Reclaim::Pending(
                            "ACP supervisor did not exit within the cleanup budget".to_string(),
                        ),
                    }
                }
            }
        }
        #[cfg(not(target_os = "linux"))]
        {
            use process_wrap::tokio::ChildWrapper;

            let Some(child) = self.child.as_mut() else {
                self.settled = Some(Ok(()));
                return Reclaim::Stopped;
            };
            if !self.cancel_requested {
                // 终止请求成功才记为已请求；失败保留可重试的 kill/wait 责任。
                if Pin::from(child.kill()).await.is_ok() {
                    self.cancel_requested = true;
                }
            }
            match tokio::time::timeout(PROCESS_KILL_LIMIT, child.wait()).await {
                Ok(Ok(_status)) => {
                    self.settled = Some(Ok(()));
                    Reclaim::Stopped
                }
                // 普通 wait 系统调用错误不是退出证明：保留 child owner 与错误摘要，仍可重试。
                Ok(Err(error)) => Reclaim::Pending(format!("ACP process wait failed: {error}")),
                Err(_) => Reclaim::Pending(
                    "ACP process did not exit within the cleanup budget".to_string(),
                ),
            }
        }
    }

    /// 收束 stderr 排空任务；超时借用 JoinHandle 并放回，绝不因超时丢句柄。
    async fn reclaim_stderr(&mut self) -> Reclaim {
        if let Some(issue) = self.stderr_failure.as_ref() {
            // 已交付的终态失败跨轮次粘滞：进程仍 Pending 时也不能丢失。
            return Reclaim::Settled(issue.clone());
        }
        let Some(mut task) = self.stderr_task.take() else {
            return Reclaim::Stopped;
        };
        let deadline = tokio::time::sleep(PROCESS_CLEANUP_LIMIT);
        tokio::pin!(deadline);
        let outcome = tokio::select! {
            result = &mut task => Some(result),
            _ = &mut deadline => None,
        };
        match outcome {
            Some(Ok(())) => Reclaim::Stopped,
            Some(Err(error)) => {
                let issue = format!("ACP stderr drain task failed: {error}");
                self.stderr_failure = Some(issue.clone());
                Reclaim::Settled(issue)
            }
            None => {
                // 句柄放回 owner：任务仍在运行，下一次收尾继续 join 同一任务。
                self.stderr_task = Some(task);
                Reclaim::Pending("ACP stderr drain did not finish".to_string())
            }
        }
    }

    #[cfg(target_os = "linux")]
    async fn spawn_supervised(
        request: AcpSpawnRequest,
        source: &WorkerSource,
        cancellation: &CancellationToken,
    ) -> Result<Self, AcpSpawnError> {
        use pl_remote_helper::client::{ManagedWorker, ProcessCommand};

        let worker = source.resolve().await?;
        // 异步解析之后、真正 spawn 之前必须再检查一次取消。
        if cancellation.is_cancelled() {
            return Err(AcpSpawnError::Cancelled);
        }
        let specification = ProcessCommand::new(request.program.into_os_string())
            .args(request.args.iter().cloned())
            .current_dir(request.cwd);
        let specification = with_business_environment(specification);
        let mut supervisor = ManagedWorker::spawn(worker.as_ref(), specification)
            .await
            .map_err(|error| AcpSpawnError::Startup {
                step: AcpSpawnStep::Process,
                source: error.to_string(),
            })?;
        let stdin = supervisor.take_stdin();
        let stdout = supervisor.take_stdout();
        let stderr = supervisor.take_stderr();
        // 进程一旦创建就由本 owner 持有：缺管道也不在这里收尾，交给统一的 reclaim 循环。
        Ok(Self {
            stdin: stdin.map(|stdin| Box::pin(stdin) as ChildWriter),
            stdout: stdout.map(|stdout| Box::pin(stdout) as ChildReader),
            stderr_task: stderr.map(drain_stderr),
            settled: None,
            stderr_failure: None,
            cancel_requested: false,
            supervisor: Some(supervisor),
        })
    }

    #[cfg(not(target_os = "linux"))]
    async fn spawn_wrapped(
        request: AcpSpawnRequest,
        cancellation: &CancellationToken,
    ) -> Result<Self, AcpSpawnError> {
        use std::process::Stdio;

        use process_wrap::tokio::ChildWrapper;

        if cancellation.is_cancelled() {
            return Err(AcpSpawnError::Cancelled);
        }
        let mut command = tokio::process::Command::new(&request.program);
        command
            .args(request.args.iter().cloned())
            .current_dir(&request.cwd)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        // 只有白名单变量会进入官方程序；其余（含凭据类）不复制。
        command.env_clear();
        for key in ENV_ALLOWLIST {
            if let Some(value) = std::env::var_os(key) {
                command.env(key, value);
            }
        }
        let mut child = pl_remote_helper::process::wrap_background_command(command)
            .spawn()
            .map_err(|error| AcpSpawnError::Startup {
                step: AcpSpawnStep::Process,
                source: error.to_string(),
            })?;
        let stdin = child.stdin().take();
        let stdout = child.stdout().take();
        let stderr = child.stderr().take();
        // 进程一旦创建就由本 owner 持有：缺管道也不在这里收尾，交给统一的 reclaim 循环。
        Ok(Self {
            stdin: stdin.map(|stdin| Box::pin(stdin) as ChildWriter),
            stdout: stdout.map(|stdout| Box::pin(stdout) as ChildReader),
            stderr_task: stderr.map(drain_stderr),
            settled: None,
            stderr_failure: None,
            cancel_requested: false,
            child: Some(child),
        })
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

/// 一次性读取宿主环境快照，并把非白名单继承键显式删除、白名单值显式回填。
///
/// 不记录任何值；非 UTF-8 的变量名同样按“非白名单”处理并删除，不会被静默继承。
#[cfg(target_os = "linux")]
fn with_business_environment(
    mut specification: pl_remote_helper::client::ProcessCommand,
) -> pl_remote_helper::client::ProcessCommand {
    let snapshot: Vec<(std::ffi::OsString, std::ffi::OsString)> = std::env::vars_os().collect();
    for (key, _value) in &snapshot {
        if !is_allowed_key(key) {
            specification = specification.env_remove(key.clone());
        }
    }
    for (key, value) in &snapshot {
        if is_allowed_key(key) {
            specification = specification.env(key.clone(), value.clone());
        }
    }
    specification
}

#[cfg(target_os = "linux")]
fn is_allowed_key(key: &OsStr) -> bool {
    key.to_str().is_some_and(|key| ENV_ALLOWLIST.contains(&key))
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
fn drain_stderr(mut stderr: impl AsyncRead + Unpin + Send + 'static) -> JoinHandle<()> {
    tokio::spawn(async move {
        let mut buffer = [0u8; STDERR_CHUNK_BYTES];
        let mut total = 0usize;
        loop {
            match stderr.read(&mut buffer).await {
                Ok(0) => break,
                Ok(read) => total = total.saturating_add(read),
                Err(error) if error.kind() == std::io::ErrorKind::Interrupted => {}
                Err(_) => break,
            }
        }
        // 只有字节数进入诊断；原始 stderr 既不发布给 UI，也不写入日志。
        tracing::debug!(
            bytes = total,
            budget = STDERR_BUDGET_BYTES,
            "ACP server stderr drained"
        );
    })
}

/// 受监督 worker 的来源：桌面随包资源或显式外部安装。
pub(super) struct WorkerSource {
    #[cfg_attr(not(target_os = "linux"), allow(dead_code))]
    source: RemoteHelperSource,
    #[cfg(target_os = "linux")]
    cached: std::sync::Mutex<Option<crate::worker_assets::LocalWorkerAsset>>,
}

impl WorkerSource {
    pub(super) fn new(source: RemoteHelperSource) -> Self {
        Self {
            source,
            #[cfg(target_os = "linux")]
            cached: std::sync::Mutex::new(None),
        }
    }

    /// 解析一次并缓存受监督 worker 的可执行镜像；失败不缓存，下一次启动会重新尝试。
    #[cfg(target_os = "linux")]
    pub(super) async fn resolve(
        &self,
    ) -> Result<crate::worker_assets::LocalWorkerAsset, AcpSpawnError> {
        if let Some(worker) = self
            .cached
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
        {
            return Ok(worker);
        }
        let worker = crate::worker_assets::local_worker(self.source.clone())
            .await
            .map_err(|error| AcpSpawnError::Startup {
                step: AcpSpawnStep::WorkerAsset,
                source: error.to_string(),
            })?;
        *self
            .cached
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(worker.clone());
        Ok(worker)
    }

    #[cfg(not(target_os = "linux"))]
    pub(super) async fn resolve(&self) -> Result<(), AcpSpawnError> {
        Ok(())
    }
}
