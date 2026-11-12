//! Windows kernel scopes with the actual manual-session cleanup coordinator.
use super::*;

const FIXTURE: &str = "manual_gui::windows_cleanup_tests::preparation_fixture";

#[test]
fn preparation_fixture() -> Result<()> {
    let Some(directory) = env::var_os("PL_PREPARATION_FIXTURE") else {
        return Ok(());
    };
    let directory = PathBuf::from(directory);
    let mode = env::var("PL_PREPARATION_MODE")?;
    if mode == "worker" || mode == "cancel" {
        fs::write(directory.join("ready"), "ready")?;
        let deadline = Instant::now() + Duration::from_secs(20);
        while Instant::now() < deadline {
            thread::sleep(Duration::from_millis(10));
        }
        bail!("fixture was not reclaimed");
    }
    if mode == "orphan" {
        let _child = Command::new(env::current_exe()?)
            .args(["--exact", FIXTURE, "--nocapture"])
            .env("PL_PREPARATION_MODE", "worker")
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()?;
    } else {
        // Model a launcher which crosses the boundary just before exiting.
        fs::write(directory.join("gui.log"), NATIVE_LAUNCH_BOUNDARY)?;
        fs::write(directory.join("ready"), "ready")?;
    }
    Ok(())
}

#[test]
fn preparation_cleanup_retains_first_error_and_native_report_barrier() -> Result<()> {
    for mode in ["orphan", "cancel", "native-missing"] {
        let directory = tempfile::tempdir()?;
        let log = directory.path().join("gui.log");
        let report = directory.path().join("native-exit.json");
        fs::write(&log, "preparing\n")?;
        let mut command = Command::new(env::current_exe()?);
        command
            .args(["--exact", FIXTURE, "--nocapture"])
            .env("PL_PREPARATION_FIXTURE", directory.path())
            .env("PL_PREPARATION_MODE", mode)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null());
        let mut gui = OwnedProcess::start(&mut command, false)?;
        let deadline = Instant::now() + Duration::from_secs(10);
        while !directory.path().join("ready").exists()
            || (mode != "cancel" && gui.exit_status()?.is_none())
        {
            ensure!(
                Instant::now() < deadline,
                "fixture readiness timed out: {mode}"
            );
            thread::sleep(Duration::from_millis(10));
        }
        if mode == "orphan" {
            assert!(!gui.tree_exited()?);
        }
        let result = finish_manual_gui_session(
            Err(anyhow::anyhow!("original startup failure")),
            &mut gui,
            Some(&report),
            Duration::from_secs(1),
            Some(&log),
        );
        let error = format!("{:#}", result.unwrap_err());
        assert!(error.contains("original startup failure"), "{error}");
        if mode == "native-missing" {
            assert!(!gui.stopped);
            assert!(error.contains("cleanup timed out"), "{error}");
        } else {
            assert!(gui.stopped, "{mode}: {error}");
            assert!(gui.tree_exited()?);
            assert!(!error.contains("cleanup timed out"), "{error}");
        }
    }
    Ok(())
}
