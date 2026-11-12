use super::{NATIVE_LAUNCH_BOUNDARY, VmStartupBudget, VmStartupPhase, native_launch_started};
use std::time::{Duration, Instant};

#[test]
fn preparation_does_not_spend_or_reset_the_vm_budget() {
    let start = Instant::now();
    let timeout = Duration::from_millis(20);
    let prepared = start + Duration::from_secs(6000);
    let mut budget = VmStartupBudget::new(VmStartupPhase::NativePreparation, timeout, start);
    budget.observe("startup_stage=build_bridge elapsed_ms=6000000\n", prepared);
    assert_eq!(budget.deadline, None);
    assert!(!native_launch_started(NATIVE_LAUNCH_BOUNDARY.trim_end()));
    assert!(!native_launch_started(&format!(
        "compiler: {NATIVE_LAUNCH_BOUNDARY}"
    )));
    budget.observe(NATIVE_LAUNCH_BOUNDARY, prepared);
    assert_eq!(budget.deadline, Some(prepared + timeout));
    let expired = prepared + timeout + Duration::from_millis(1);
    budget.observe(NATIVE_LAUNCH_BOUNDARY, expired);
    budget.observe("additional startup output\n", expired);
    assert!(budget.deadline.unwrap() < expired);
    // Existing resident/specialized callers keep their spawn-relative budget.
    let immediate = VmStartupBudget::new(VmStartupPhase::Immediate, timeout, start);
    assert_eq!(immediate.deadline, Some(start + timeout));
}

#[cfg(unix)]
#[test]
fn waiter_allows_preparation_longer_than_its_short_vm_window() -> anyhow::Result<()> {
    use super::{OwnedProcess, wait_for_vm_in_phase};
    use std::{fs, process::Command, sync::mpsc, thread};

    let directory = tempfile::tempdir()?;
    let path = directory.path().join("gui.log");
    fs::write(&path, "building native inputs\n")?;
    let writer_path = path.clone();
    let writer = thread::spawn(move || -> std::io::Result<()> {
        thread::sleep(Duration::from_millis(650));
        fs::write(
            writer_path,
            format!(
                "{NATIVE_LAUNCH_BOUNDARY}The Dart VM service is listening on http://127.0.0.1:1234/synthetic/\n"
            ),
        )
    });
    let mut gui = OwnedProcess::start(Command::new("sh").args(["-c", "exec sleep 60"]), false)?;
    let mut fixture = OwnedProcess::start(Command::new("sh").args(["-c", "exec sleep 60"]), true)?;
    let (tx, rx) = mpsc::channel();
    let result = wait_for_vm_in_phase(
        &path,
        &mut gui,
        &mut fixture,
        &rx,
        VmStartupPhase::NativePreparation,
        Duration::from_millis(100),
    );
    writer.join().unwrap()?;
    assert_eq!(result?, "http://127.0.0.1:1234/synthetic/");
    fs::write(
        &path,
        format!("{NATIVE_LAUNCH_BOUNDARY}{NATIVE_LAUNCH_BOUNDARY}ordinary startup output\n"),
    )?;
    let error = wait_for_vm_in_phase(
        &path,
        &mut gui,
        &mut fixture,
        &rx,
        VmStartupPhase::NativePreparation,
        Duration::from_millis(20),
    )
    .unwrap_err();
    assert!(
        error.to_string().contains("VM service startup timed out"),
        "{error:#}"
    );
    tx.send(())?;
    let cancelled = wait_for_vm_in_phase(
        &path,
        &mut gui,
        &mut fixture,
        &rx,
        VmStartupPhase::NativePreparation,
        Duration::ZERO,
    )
    .unwrap_err();
    assert!(
        cancelled.to_string().contains("manual GUI cancelled"),
        "{cancelled:#}"
    );
    Ok(())
}
