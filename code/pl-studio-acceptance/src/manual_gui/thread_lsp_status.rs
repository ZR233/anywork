//! Supplies isolation and process supervision for the production LSP test.
//! Assertions and resource shutdown stay in the official Flutter test.

use super::*;

pub(super) fn run(
    workspace: &Path,
    working: &Path,
    output: &Path,
    interrupt: &mpsc::Receiver<()>,
) -> Result<()> {
    let fixture = build_fixture_executable(workspace)?;
    let sandbox = working.join("sandbox");
    fs::create_dir(&sandbox)?;
    let sandbox = fs::canonicalize(sandbox)?;
    let log_path = working.join("thread-lsp-status-integration.log");
    let mut runner_exit = None;
    let suite = (|| -> Result<()> {
        let log = File::create(&log_path)?;
        let mut command = desktop_test_command(workspace)?;
        command
            .args(["--suite", "desktop", "--case", "thread_lsp_status"])
            .env("ANYWORK_HOME", sandbox.join("studio-home"))
            .env("ANYWORK_THREAD_LSP_SANDBOX", &sandbox)
            .env("ANYWORK_THREAD_LSP_PROJECT_A", sandbox.join("project-a"))
            .env("ANYWORK_THREAD_LSP_PROJECT_B", sandbox.join("project-b"))
            .env("ANYWORK_THREAD_LSP_OUTPUT", sandbox.join("artifacts"))
            .env("ANYWORK_THREAD_LSP_FIXTURE", fixture)
            .stdout(Stdio::from(log.try_clone()?))
            .stderr(Stdio::from(log));
        let mut runner = OwnedProcess::start(&mut command, false)?;
        let deadline = Instant::now() + Duration::from_secs(1_200);
        loop {
            if let Some(status) = runner.child.try_wait()? {
                runner.stopped = true;
                runner_exit = Some(status);
                ensure!(status.success(), "Thread LSP integration failed: {status}");
                break;
            }
            ensure!(
                interrupt.try_recv().is_err(),
                "Thread LSP integration cancelled"
            );
            ensure!(
                Instant::now() < deadline,
                "Thread LSP integration timed out"
            );
            thread::sleep(Duration::from_millis(200));
        }
        Ok(())
    })();
    // Preserve bridge and shutdown evidence before releasing the environment,
    // including failures after Flutter created its output.
    let artifacts = sandbox.join("artifacts");
    if artifacts.is_dir() {
        fs::rename(&artifacts, output.join("thread-lsp-artifacts"))?;
    }
    write_realtime_driver_evidence(
        &log_path,
        output,
        "thread-lsp-status-integration",
        runner_exit,
        suite.as_ref().err(),
        &[(working.to_string_lossy().into_owned(), "<environment>")],
    )?;
    suite
}
