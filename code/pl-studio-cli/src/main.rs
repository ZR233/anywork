use clap::Parser;
use pl_studio_cli::{Cli, Command, SignalListener};
use std::{io::Write, process::ExitCode};
use tracing_subscriber::EnvFilter;

fn main() -> ExitCode {
    let Cli {
        command: Command::Exec(args),
    } = Cli::parse();
    tracing_subscriber::fmt()
        .with_writer(std::io::stderr)
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .init();
    let request = std::env::current_dir()
        .map_err(anyhow::Error::from)
        .and_then(|cwd| args.prepare(&cwd, std::io::stdin().lock()));
    let request = match request {
        Ok(request) => request,
        Err(error) => {
            eprintln!("anywk: {error:#}");
            return ExitCode::from(2);
        }
    };
    let runtime = match tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
    {
        Ok(runtime) => runtime,
        Err(error) => {
            eprintln!("anywk: 无法创建执行环境: {error}");
            return ExitCode::from(11);
        }
    };
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
    if let Some(turn) = &report.turn
        && !matches!(&turn.state, pl_protocol::TurnState::Completed(_))
    {
        eprintln!("anywk: 任务终态 {:?}", turn.state);
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
