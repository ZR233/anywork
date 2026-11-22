#![recursion_limit = "256"]

use clap::Parser;
use pl_studio_cli::{Cli, Command, PreparedAcp, PreparedExec, SignalListener};
use std::{io::Write, process::ExitCode};
use tracing_subscriber::EnvFilter;

const CLI_STACK_BYTES: usize = 8 * 1024 * 1024;

fn main() -> ExitCode {
    let Cli { command } = Cli::parse();
    tracing_subscriber::fmt()
        .with_writer(std::io::stderr)
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .init();
    let request = std::env::current_dir()
        .map_err(anyhow::Error::from)
        .and_then(|cwd| match command {
            Command::Exec(args) => args
                .prepare(&cwd, std::io::stdin().lock())
                .map(Box::new)
                .map(Prepared::Native),
            Command::AcpOptions(args) => args.prepare(&cwd).map(Box::new).map(Prepared::Acp),
            Command::ExecAcp(args) => args
                .prepare(&cwd, std::io::stdin().lock())
                .map(Box::new)
                .map(Prepared::Acp),
        });
    let request = match request {
        Ok(request) => request,
        Err(error) => {
            eprintln!("anywk: {error:#}");
            return ExitCode::from(2);
        }
    };
    let handle = match std::thread::Builder::new()
        .name("anywk-main".into())
        .stack_size(CLI_STACK_BYTES)
        .spawn(move || run_prepared(request))
    {
        Ok(handle) => handle,
        Err(error) => {
            eprintln!("anywk: 无法创建执行线程: {error}");
            return ExitCode::from(11);
        }
    };
    match handle.join() {
        Ok(code) => code,
        Err(_) => {
            eprintln!("anywk: 执行线程异常终止");
            ExitCode::from(11)
        }
    }
}

fn run_prepared(request: Prepared) -> ExitCode {
    let runtime = match tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .thread_stack_size(CLI_STACK_BYTES)
        .build()
    {
        Ok(runtime) => runtime,
        Err(error) => {
            eprintln!("anywk: 无法创建执行环境: {error}");
            return ExitCode::from(11);
        }
    };
    match request {
        Prepared::Native(request) => run_native(&runtime, *request),
        Prepared::Acp(request) => run_acp(&runtime, *request),
    }
}

enum Prepared {
    Native(Box<PreparedExec>),
    Acp(Box<PreparedAcp>),
}

fn run_native(runtime: &tokio::runtime::Runtime, request: PreparedExec) -> ExitCode {
    let report = runtime.block_on(async {
        let mut signals = SignalListener::new()?;
        Ok::<_, std::io::Error>(pl_studio_cli::execute(request, signals.recv()).await)
    });
    let report = match report {
        Ok(report) => report,
        Err(error) => {
            eprintln!("anywk: 无法监听退出信号: {error}");
            return ExitCode::from(11);
        }
    };
    let code = report.exit_code();
    if let Some(error) = &report.error {
        eprintln!("anywk: {error}");
    }
    if let Some(pl_studio_cli::InputObservation::Terminal(turn)) = &report.observation
        && !matches!(&turn.state, pl_studio_runtime::TurnState::Completed(_))
    {
        eprintln!("anywk: 任务终态 {:?}", turn.state);
    }
    if matches!(
        &report.observation,
        Some(pl_studio_cli::InputObservation::WaitingForInteraction)
    ) {
        eprintln!("anywk: 等待用户输入");
    }
    if let Some(export_error) = &report.export_error {
        eprintln!(
            "anywk: 导出失败 {} ({})",
            export_error.message, export_error.code
        );
    } else if let Some(export) = &report.export
        && let Some(failure) = &export.failure
    {
        eprintln!("anywk: 导出失败 {} ({})", failure.message, failure.code);
    }
    for issue in &report.shutdown.issues {
        eprintln!("anywk: 关闭失败 {} ({})", issue.stage, issue.code);
    }
    if !report.final_text.is_empty()
        && let Err(error) = writeln!(std::io::stdout().lock(), "{}", report.final_text)
    {
        eprintln!("anywk: 无法写入最终文本: {error}");
        return ExitCode::from(if code == 13 { 13 } else { 11 });
    }
    ExitCode::from(code)
}

fn run_acp(runtime: &tokio::runtime::Runtime, request: PreparedAcp) -> ExitCode {
    let report = runtime.block_on(async {
        let mut signals = SignalListener::new()?;
        Ok::<_, std::io::Error>(pl_studio_cli::execute_acp(request, signals.recv()).await)
    });
    let report = match report {
        Ok(report) => report,
        Err(error) => {
            eprintln!("anywk: 无法监听退出信号: {error}");
            return ExitCode::from(11);
        }
    };
    let code = report.exit_code();
    if let Some(error) = &report.error {
        eprintln!("anywk: {error}");
    }
    for issue in &report.shutdown.issues {
        eprintln!("anywk: 关闭失败 {} ({})", issue.stage, issue.code);
    }
    if code == 0
        && !report.output.is_empty()
        && let Err(error) = writeln!(std::io::stdout().lock(), "{}", report.output)
    {
        eprintln!("anywk: 无法写入 ACP 输出: {error}");
        return ExitCode::from(11);
    }
    ExitCode::from(code)
}
