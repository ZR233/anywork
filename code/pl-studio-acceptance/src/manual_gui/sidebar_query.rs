//! Isolated home for the official sidebar production integration_test.
//!
//! The Flutter suite owns assertions and starts its own loopback provider.
//! This preset only supplies a closed synthetic home, a disposable project
//! root, and an artifacts directory.

use super::*;
use pl_studio_runtime::config::{ConfigPaths, ConfigStore, StudioConfig};

pub(super) struct SidebarQueryScenario<'a> {
    pub workspace: &'a Path,
    pub home: &'a Path,
    pub working: &'a Path,
    pub output: &'a Path,
    pub interrupt: &'a mpsc::Receiver<()>,
}

pub(super) fn run(context: &SidebarQueryScenario<'_>) -> Result<()> {
    let SidebarQueryScenario {
        workspace,
        home,
        working,
        output,
        interrupt,
    } = context;
    let projects = working.join("sidebar-projects");
    let artifacts = output.join("sidebar-artifacts");
    let log_path = working.join("sidebar-query-integration.log");
    let mut runner_exit = None;
    let suite = (|| -> Result<()> {
        fs::create_dir_all(&projects)?;
        fs::create_dir_all(&artifacts)?;
        write_home_config(home)?;
        let log = File::create(&log_path)?;
        let mut command = Command::new("cargo");
        command
            .current_dir(workspace)
            .args([
                "xtask",
                "test-project",
                "--suite",
                "desktop",
                "--case",
                "sidebar",
            ])
            .env("ANYWORK_HOME", home)
            .env("ANYWORK_SIDEBAR_PROJECTS", &projects)
            .env("ANYWORK_SIDEBAR_ARTIFACTS", &artifacts)
            .stdout(Stdio::from(log.try_clone()?))
            .stderr(Stdio::from(log));
        let mut runner = OwnedProcess::start(&mut command, false)?;
        let deadline = Instant::now() + Duration::from_secs(1_200);
        loop {
            if let Some(status) = runner.child.try_wait()? {
                runner.stopped = true;
                runner_exit = Some(status);
                ensure!(
                    status.success(),
                    "sidebar integration tests failed: {status}"
                );
                break;
            }
            ensure!(
                interrupt.try_recv().is_err(),
                "sidebar integration tests cancelled"
            );
            ensure!(
                Instant::now() < deadline,
                "sidebar integration tests timed out"
            );
            thread::sleep(Duration::from_millis(200));
        }
        Ok(())
    })();

    write_realtime_driver_evidence(
        &log_path,
        output,
        "sidebar-query-integration",
        runner_exit,
        suite.as_ref().err(),
        &[
            (workspace.to_string_lossy().into_owned(), "<workspace>"),
            (home.to_string_lossy().into_owned(), "<home>"),
            (working.to_string_lossy().into_owned(), "<environment>"),
        ],
    )?;
    fs::write(
        output.join("fixture-status.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "scenario": "sidebar-query",
            "runner": "flutter.integration_test",
            "runnerExitCode": runner_exit.and_then(|status| status.code()),
        }))?,
    )?;
    suite?;
    println!("sidebar integration evidence: {}", output.display());
    Ok(())
}

fn write_home_config(home: &Path) -> Result<()> {
    let config = StudioConfig::default_config()?;
    ConfigStore::new(ConfigPaths::from_config_dir(home)).save(&config)?;
    Ok(())
}
