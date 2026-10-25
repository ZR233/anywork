//! 显式人工观察：公开 HTTP → 生产 `pl-studio-server` → 独立飞书 peer + 模型 fixture。
//!
//! 父进程只用工程 `run_resident_reporting` 监督 `--worker`；worker 负责异步
//! 有序退出。不进入常规自动测试门禁。场景失败传到非零退出。
//!
//! 平台边界（design/27 观察契约）：该观察环境依赖 Linux 私有 D-Bus/Secret
//! Service 隔离与 Unix 进程组，业务模块只在 Linux 编译；非 Linux 仅保留
//! 一个纯 std 的拒绝入口，保证 Windows all-targets 可编译且永不冒充通过。

#[cfg(target_os = "linux")]
mod cases;
#[cfg(target_os = "linux")]
mod env;
#[cfg(target_os = "linux")]
mod http;
#[cfg(target_os = "linux")]
mod report;
#[cfg(target_os = "linux")]
mod server;
#[cfg(target_os = "linux")]
mod sqlite;
#[cfg(target_os = "linux")]
mod thread_watch;
#[cfg(target_os = "linux")]
mod topic;

#[cfg(target_os = "linux")]
use anyhow::{Context, Result, bail};
#[cfg(target_os = "linux")]
use clap::Parser;
#[cfg(target_os = "linux")]
use pl_dev_support::process;
#[cfg(target_os = "linux")]
use std::path::PathBuf;
#[cfg(target_os = "linux")]
use std::process::Command;
use std::process::ExitCode;

#[derive(Debug, Parser)]
#[command(
    name = "bots_protocol_observe",
    about = "Drive production Studio HTTP against an isolated Feishu peer and model fixture"
)]
#[cfg(target_os = "linux")]
struct Options {
    /// Directory for redacted evidence. Defaults to target/bots-protocol-observe/<stamp>-<pid>.
    #[arg(long, value_name = "DIR")]
    output: Option<PathBuf>,
    /// Run only these cases (repeatable). Default: first-batch smoke plus 1–4.
    #[arg(long = "case", value_name = "NAME")]
    cases: Vec<String>,
    /// Keep the isolated Studio home after a successful run.
    #[arg(long)]
    retain_environment: bool,
    /// Use an already-built Studio server instead of compiling the current workspace.
    #[arg(long = "server-binary", value_name = "PATH")]
    server_binary: Option<PathBuf>,
    /// Private worker boundary. Parent owns resident supervision; do not invoke directly.
    #[arg(long, hide = true)]
    worker: bool,
}

#[cfg(target_os = "linux")]
fn main() -> ExitCode {
    match run() {
        Ok(code) => code,
        Err(error) => {
            eprintln!("bots_protocol_observe failed: {error:#}");
            ExitCode::from(1)
        }
    }
}

/// 非 Linux 拒绝入口：只依赖 std。观察环境（私有 D-Bus/Secret Service 隔离、
/// Unix 进程组）只在 Linux 存在；这里不启动任何东西、不触碰任何凭据，
/// stderr 给出明确原因并以非零退出，任何平台都不能把拒绝当成通过。
#[cfg(not(target_os = "linux"))]
fn main() -> ExitCode {
    eprintln!(
        "bots_protocol_observe requires Linux: the isolated D-Bus/Secret Service observation \
         environment does not exist on this platform; nothing was run"
    );
    ExitCode::from(1)
}

#[cfg(target_os = "linux")]
fn run() -> Result<ExitCode> {
    let options = Options::parse();
    // Reject quarantined/unknown selectors before output, worker or product
    // environment creation. The worker keeps its own validation as a guard.
    cases::selected(&options.cases)?;
    if options.worker {
        return run_worker(options);
    }
    if let Err(error) = process::own_current_process_tree() {
        eprintln!("failed to own the process tree: {error:#}");
        return Ok(ExitCode::from(1));
    }
    run_parent(options)
}

#[cfg(target_os = "linux")]
fn run_parent(options: Options) -> Result<ExitCode> {
    let output = env::prepare_output(options.output.as_deref())?;
    let server_binary = options
        .server_binary
        .as_deref()
        .map(env::canonicalize_executable)
        .transpose()?;
    let exe = std::env::current_exe().context("failed to locate observe executable")?;
    let mut command = Command::new(exe);
    command.arg("--worker").arg("--output").arg(&output);
    for name in &options.cases {
        command.arg("--case").arg(name);
    }
    if options.retain_environment {
        command.arg("--retain-environment");
    }
    if let Some(path) = &server_binary {
        command.arg("--server-binary").arg(path);
    }
    process::configure_background_command(&mut command);
    let resident = process::run_resident_reporting(&mut command, "bots_protocol_observe --worker")?;
    let process_ev = report::process_evidence(
        resident.pid,
        resident.status,
        resident.descendants_at_root_exit,
        resident.reclaimed_descendants.clone(),
        resident.cancelled,
    );
    let summary_path = output.join("summary.json");
    let mut failed = !resident.status.success()
        || !resident.reclaimed_descendants.is_empty()
        || resident.cancelled;
    if summary_path.is_file() {
        report::attach_process(&summary_path, &process_ev)?;
        failed |= report::summary_failed(&summary_path)?;
    } else {
        failed = true;
        eprintln!("worker left no summary at {}", summary_path.display());
    }
    if !resident.reclaimed_descendants.is_empty() {
        eprintln!(
            "supervisor reclaimed leaked descendants {:?}; product natural reclaim is not proven",
            resident.reclaimed_descendants
        );
    }
    if failed {
        eprintln!(
            "bots_protocol_observe: failed; evidence {}",
            summary_path.display()
        );
        Ok(ExitCode::from(1))
    } else {
        eprintln!(
            "bots_protocol_observe: cases passed; evidence {}",
            summary_path.display()
        );
        Ok(ExitCode::SUCCESS)
    }
}

#[cfg(target_os = "linux")]
fn run_worker(options: Options) -> Result<ExitCode> {
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .context("failed to start the observe runtime")?;
    let summary = runtime.block_on(observe(options))?;
    let failed = summary
        .cases
        .iter()
        .any(|case| case.verdict != report::Verdict::Passed)
        || summary.cleanup_error.is_some();
    if failed {
        eprintln!(
            "bots_protocol_observe worker: failed; evidence {}",
            summary.summary_path.display()
        );
        Ok(ExitCode::from(1))
    } else {
        eprintln!(
            "bots_protocol_observe worker: cases finished; evidence {}",
            summary.summary_path.display()
        );
        Ok(ExitCode::SUCCESS)
    }
}

#[cfg(target_os = "linux")]
async fn observe(options: Options) -> Result<report::RunSummary> {
    if !cfg!(target_os = "linux") {
        bail!(
            "bots_protocol_observe currently requires Linux private D-Bus/Secret Service isolation"
        );
    }
    let selected = cases::selected(&options.cases)?;
    let mut paths = env::prepare(options.output.as_deref())?;
    let server_binary = options
        .server_binary
        .as_deref()
        .map(env::canonicalize_executable)
        .transpose()?;
    let mut markers = Vec::new();
    let mut summary = match cases::Session::start(&paths, &selected, server_binary.as_deref()).await
    {
        Ok(mut session) => {
            let mut summary = match session.run(&selected).await {
                Ok(summary) => summary,
                Err(error) => {
                    let mut summary = report::RunSummary::for_paths(&paths.output, &paths.home);
                    summary.cleanup_error =
                        Some(report::one_line(&format!("observe run failed: {error:#}")));
                    summary
                }
            };
            match session.shutdown().await {
                Ok(collected) => markers = collected,
                Err(error) => {
                    let previous = summary.cleanup_error.take().unwrap_or_default();
                    summary.cleanup_error = Some(report::one_line(&format!(
                        "{previous}; shutdown: {error:#}"
                    )));
                }
            }
            summary
        }
        Err(error) => {
            let mut summary = report::RunSummary::for_paths(&paths.output, &paths.home);
            summary.cleanup_error = Some(report::one_line(&error.to_string()));
            summary
        }
    };
    if summary.observer.is_none() {
        summary.observer = env::observer_identity(&paths.workspace).ok();
    }
    if options.retain_environment {
        paths.retain()?;
        summary.retained_home = Some(paths.home.display().to_string());
    }
    // Single reporting point: gaps must reflect what this run's typed case
    // verdicts actually proved before any summary write.
    summary.finalize_gaps();
    report::copy_redacted_log(&paths)?;
    report::write(&paths, &summary)?;
    if summary.cleanup_error.is_none()
        && let Err(error) = cases::audit_final_evidence(&paths.home, &paths.output, &markers)
    {
        summary.cleanup_error = Some(report::one_line(&error.to_string()));
        report::write(&paths, &summary)?;
    }
    Ok(summary)
}
