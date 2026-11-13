//! One real shutdown with live MCP, LSP and command subtrees.
//! The existing native launcher owns cleanup; this test fails if it had to
//! reclaim a leftover or any recorded process still exists after normal exit.

use super::{FixtureReady, LspServerSpec, OwnedProcess};
use anyhow::{Context, Result, ensure};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::fs::{self, File};
use std::path::Path;
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

pub(super) struct ShutdownScenario<'a> {
    pub(super) workspace: &'a Path,
    pub(super) home: &'a Path,
    pub(super) working: &'a Path,
    pub(super) output: &'a Path,
    pub(super) fixture_log: &'a Path,
    pub(super) requests_file: &'a Path,
    pub(super) fixture_executable: &'a Path,
    pub(super) interrupt: &'a mpsc::Receiver<()>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ProcessIdentity {
    pid: u32,
    start_ticks: u64,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct NativeExit {
    schema: String,
    pid: u32,
    exit_code: Option<i32>,
    signal: Option<i32>,
    cancelled: bool,
    reclaimed_descendants: Vec<u32>,
}

pub(super) fn tool_command(executable: &Path, coord: &Path) -> String {
    use pl_tool::environment::{ExecutionEnvironment, ShellDialect};

    let executable = executable.to_string_lossy();
    let coord = coord.to_string_lossy();
    match ExecutionEnvironment::detect_local().shell {
        ShellDialect::Pwsh | ShellDialect::PowerShell => format!(
            "& '{}' --tool-peer --coord-file '{}'",
            executable.replace('\'', "''"),
            coord.replace('\'', "''")
        ),
        ShellDialect::Cmd => format!("\"\"{executable}\" --tool-peer --coord-file \"{coord}\"\""),
        ShellDialect::Bash | ShellDialect::Sh => format!(
            "{} --tool-peer --coord-file {}",
            pl_tool::shell::shell_quote_word(&executable),
            pl_tool::shell::shell_quote_word(&coord)
        ),
    }
}

pub(super) fn run(context: &ShutdownScenario<'_>, mut fixture: OwnedProcess) -> Result<()> {
    let ready: FixtureReady =
        serde_json::from_slice(&fs::read(context.working.join("fixture-ready.json"))?)?;
    let mcp_coord = context.working.join("shutdown-mcp-coord.json");
    let lsp_coord = context.working.join("shutdown-lsp-coord.json");
    let tool_coord = context.working.join("shutdown-tool-coord.json");
    super::write_config_with_mcp_server(
        context.home,
        &ready,
        "shutdown-fixture",
        context.fixture_executable,
        &[
            "--mcp-stdio".into(),
            "--coord-file".into(),
            mcp_coord.display().to_string(),
        ],
    )?;
    super::write_config_with_lsp_server(
        context.home,
        &ready,
        &LspServerSpec {
            id: "shutdown-fixture",
            command: context.fixture_executable,
            args: &[
                "--lsp-stdio".into(),
                "--coord-file".into(),
                lsp_coord.display().to_string(),
            ],
            language_id: "anywork-shutdown-fixture",
            detection: &[],
            extensions: &[],
        },
    )?;
    let project = context.working.join("project");
    fs::create_dir(&project)?;
    ensure!(
        Command::new("git")
            .args(["init", "-q"])
            .arg(&project)
            .status()?
            .success(),
        "initialize shutdown project"
    );

    let log_path = context.working.join("shutdown-gui.log");
    let report_path = context.output.join("shutdown-native-exit.json");
    let log = File::create(&log_path)?;
    let mut command = super::xtask_command(context.workspace)?;
    command
        .current_dir(context.workspace)
        .args([
            "run-gui",
            "--native-launch",
            "--native-launch-target",
            "tool/native_shutdown_main.dart",
            "--native-exit-report",
        ])
        .arg(&report_path)
        .env("ANYWORK_HOME", context.home)
        .env("ANYWORK_NATIVE_SHUTDOWN_COORD", context.working)
        .env("ANYWORK_NATIVE_SHUTDOWN_PROJECT", project)
        .env(
            "ANYWORK_NATIVE_SHUTDOWN_PROMPT",
            pl_provider_fixture::GUI_SHUTDOWN_PROMPT,
        )
        .stdout(Stdio::from(log.try_clone()?))
        .stderr(Stdio::from(log));
    let mut gui = OwnedProcess::start(&mut command, false)?;
    let result = (|| -> Result<()> {
        let setup = context.working.join("shutdown-ready.json");
        wait_until(
            context,
            &mut gui,
            &mut fixture,
            Duration::from_secs(300),
            || {
                Ok(setup.is_file()
                    && mcp_coord.is_file()
                    && lsp_coord.is_file()
                    && tool_coord.is_file())
            },
        )?;
        let setup: Value = serde_json::from_slice(&fs::read(setup)?)?;
        let pid = u32::try_from(
            setup["pid"]
                .as_u64()
                .context("shutdown setup lost native pid")?,
        )?;
        let mut processes = vec![identity(pid)?];
        for (path, parent, parent_ticks) in [
            (&mcp_coord, "mcpPid", "mcpStartTicks"),
            (&lsp_coord, "lspPid", "lspStartTicks"),
            (&tool_coord, "toolPid", "toolStartTicks"),
        ] {
            let coord: Value = serde_json::from_slice(&fs::read(path)?)?;
            let pid = u32::try_from(
                coord[parent]
                    .as_u64()
                    .with_context(|| format!("shutdown fixture lost {parent}"))?,
            )?;
            let process = ProcessIdentity {
                pid,
                start_ticks: coord[parent_ticks]
                    .as_u64()
                    .with_context(|| format!("shutdown fixture lost {parent_ticks}"))?,
            };
            ensure!(
                start_ticks(pid) == Some(process.start_ticks),
                "shutdown setup process {pid} is no longer alive"
            );
            processes.push(process);
        }
        fs::write(
            context.output.join("shutdown-processes-before.json"),
            serde_json::to_vec_pretty(&processes)?,
        )?;
        fs::write(context.working.join("shutdown-close"), b"close\n")?;
        wait_until(
            context,
            &mut gui,
            &mut fixture,
            Duration::from_secs(60),
            || Ok(report_path.is_file()),
        )?;
        // Reap the launcher before inspecting leftovers. Its own exit code
        // cannot stand in for the native program's report.
        let deadline = Instant::now() + Duration::from_secs(20);
        while gui.child.try_wait()?.is_none() {
            ensure!(
                Instant::now() < deadline,
                "shutdown launcher did not finish"
            );
            thread::sleep(Duration::from_millis(50));
        }
        gui.mark_reaped();
        let report: Value = serde_json::from_slice(&fs::read(&report_path)?)?;
        let native: NativeExit = serde_json::from_value(report.clone())?;
        let remaining: Vec<_> = processes
            .iter()
            .filter(|process| start_ticks(process.pid) == Some(process.start_ticks))
            .collect();
        fs::write(
            context.output.join("shutdown-processes.json"),
            serde_json::to_vec_pretty(
                &json!({"nativeExit":report,"remainingProcesses":remaining}),
            )?,
        )?;
        ensure!(
            native.schema == "anywork-native-exit/1"
                && native.pid == pid
                && native.exit_code == Some(0)
                && native.signal.is_none()
                && !native.cancelled,
            "application did not exit normally: {report}"
        );
        ensure!(
            remaining.is_empty() && native.reclaimed_descendants.is_empty(),
            "application left processes after exit: {report}; remaining={}",
            serde_json::to_string(&remaining)?
        );
        Ok(())
    })();
    drop(gui);
    let _ = fixture.stop(context.requests_file);
    super::write_fixture_log(context.fixture_log, &context.output.join("fixture.log"))?;
    super::write_sanitized_log(&log_path, &context.output.join("shutdown-gui.log"))?;
    if context.requests_file.is_file() {
        super::sanitize_requests(context.requests_file, &context.output.join("requests.json"))?;
    }
    result
}

fn wait_until(
    context: &ShutdownScenario<'_>,
    gui: &mut OwnedProcess,
    fixture: &mut OwnedProcess,
    timeout: Duration,
    mut ready: impl FnMut() -> Result<bool>,
) -> Result<()> {
    let deadline = Instant::now() + timeout;
    loop {
        if ready()? {
            return Ok(());
        }
        let failure = context.working.join("shutdown-failure.json");
        ensure!(
            !failure.is_file(),
            "shutdown setup failed: {}",
            fs::read_to_string(&failure).unwrap_or_default()
        );
        ensure!(
            !gui.exited()?,
            "GUI exited before shutdown observation completed"
        );
        ensure!(!fixture.exited()?, "shutdown provider exited during setup");
        ensure!(
            context.interrupt.try_recv().is_err(),
            "shutdown acceptance cancelled"
        );
        ensure!(
            Instant::now() < deadline,
            "shutdown observation timed out after {timeout:?}"
        );
        thread::sleep(Duration::from_millis(50));
    }
}

fn identity(pid: u32) -> Result<ProcessIdentity> {
    Ok(ProcessIdentity {
        pid,
        start_ticks: start_ticks(pid)
            .with_context(|| format!("shutdown setup process {pid} is not alive"))?,
    })
}

fn start_ticks(pid: u32) -> Option<u64> {
    pl_provider_fixture::proc_start_ticks(pid)
}
