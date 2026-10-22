//! 启动准备：capture 策略、解释器描述符与物理 worker 提交。
//!
//! 物理进程仍由既有监督器创建，这里只决定用哪个解释器、继承哪些环境变量，并在提交前后检查
//! 取消信号，避免已经要求终止的启动继续创建进程。

use pl_protocol::remote::{
    RemoteError, RemoteErrorCode, RemoteShellDescriptor, RemoteShellDialect, RemoteSpawnRequest,
};

use super::super::path::{Target, io_error, remote_error};
use super::super::tasks::BlockingTasks;
use super::CwdCapability;
use super::Reservation;
use super::capture::Capture;
use crate::client::{ManagedWorker, ProcessCommand};

pub(super) async fn start(
    request: &RemoteSpawnRequest,
    cwd: &CwdCapability,
    capture: Option<&Target>,
    shell: &RemoteShellDescriptor,
    reservation: &Reservation,
    tasks: &BlockingTasks,
) -> Result<(ManagedWorker, Capture), RemoteError> {
    if reservation.is_cancelled() {
        return Err(cancelled());
    }
    // capture 目标能力自带本进程操作的预算：头部写入与之后每段输出都在同一份预算内。
    let capture = Capture::prepare(
        &request.capture,
        capture,
        &request.command,
        cwd.display(),
        tasks,
    )
    .await?;
    let option = match shell.dialect {
        RemoteShellDialect::Bash | RemoteShellDialect::Sh => "-c",
        RemoteShellDialect::Pwsh | RemoteShellDialect::PowerShell => "-Command",
        RemoteShellDialect::Cmd => "/C",
    };
    let mut command = ProcessCommand::new(&shell.path);
    if shell.dialect == RemoteShellDialect::Bash {
        // SSH 环境变量可能让 bash -c 重新读取 .bashrc。连接已经拥有初始化后的环境，
        // 单个命令不得再次加载配置；显式请求仍可用自己的环境变量覆盖该行为。
        command = command.args(["--noprofile", "--norc"]);
    }
    let mut command = command
        .args([option, &request.command])
        .current_dir(cwd.path())
        .env_remove("BASH_ENV")
        .env_remove("ENV");
    for (key, value) in &request.environment {
        command = command.env(key, value);
    }
    if reservation.is_cancelled() {
        return Err(cancelled());
    }
    let executable =
        std::env::current_exe().map_err(|error| io_error("locate process worker", error))?;
    // 这个 future 属于进程 job，不是可取消的 Spawn 请求等待者。
    let worker = ManagedWorker::spawn(&executable, command)
        .await
        .map_err(|error| remote_error(RemoteErrorCode::Io, error.to_string()))?;
    Ok((worker, capture))
}

fn cancelled() -> RemoteError {
    remote_error(
        RemoteErrorCode::RemoteDisconnected,
        "remote helper is closing",
    )
}
