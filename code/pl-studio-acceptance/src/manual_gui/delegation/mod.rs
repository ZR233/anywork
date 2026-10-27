//! Native manual journeys over real bridge, Runtime and Thread-owned tools.
//! The only fake is the loopback provider. Human verdict always stays pending.

mod config;
mod recovery;

use super::*;
use pl_provider_fixture::delegation::{LiveState, Scenario};

pub(super) struct ScenarioContext<'a> {
    pub workspace: &'a Path,
    pub app_dir: &'a Path,
    pub home: &'a Path,
    pub working: &'a Path,
    pub output: &'a Path,
    pub fixture_log: &'a Path,
    pub requests_file: &'a Path,
    pub interrupt: &'a mpsc::Receiver<()>,
    pub driver: Option<&'a Path>,
    pub scenario: Scenario,
}

pub(super) fn validate(options: &ManualGuiOptions) -> Result<()> {
    let scenario = Scenario::parse(&options.scenario);
    ensure!(
        options.delegation_driver.is_none() || scenario.is_some(),
        "--delegation-driver requires a delegation scenario"
    );
    if let Some(path) = &options.delegation_driver {
        ensure!(
            path.is_file(),
            "delegation Driver script does not exist: {}",
            path.display()
        );
    }
    if scenario.is_some() {
        ensure!(
            options.model_catalog_url.is_none(),
            "delegation scenarios own their synthetic inventory; --model-catalog-url is not allowed"
        );
        ensure!(
            cfg!(target_os = "linux"),
            "delegation native acceptance is currently Linux-only; other platforms remain unverified"
        );
    }
    Ok(())
}

pub(super) fn write_config(home: &Path, ready: &FixtureReady) -> Result<()> {
    config::write(home, ready)
}

pub(super) fn run(
    context: &ScenarioContext<'_>,
    mut fixture: OwnedProcess,
    ready: &FixtureReady,
) -> Result<()> {
    let project = context.working.join("delegation-project");
    let host = ready
        .base_url
        .strip_suffix("/v1")
        .context("fixture URL lacks /v1")?;
    let mut states = Vec::new();
    let journey = (|| -> Result<()> {
        fs::create_dir_all(project.join("work"))?;
        run_fixture_git(&project, &["init", "-q"])?;
        fs::write(project.join(".gitignore"), ".anywork/\n")?;
        fs::write(
            project.join("fixture-base.txt"),
            "Synthetic delegation acceptance project base.\n",
        )?;
        run_fixture_git(&project, &["add", "--", ".gitignore", "fixture-base.txt"])?;
        run_fixture_git(&project, &["commit", "-q", "-m", "fixture base"])?;
        let head = run_fixture_git(&project, &["rev-parse", "--verify", "HEAD"])?;
        ensure!(
            !String::from_utf8_lossy(&head.stdout).trim().is_empty(),
            "isolated delegation project has no initial commit"
        );
        let status = run_fixture_git(&project, &["status", "--porcelain"])?;
        ensure!(
            status.stdout.is_empty(),
            "isolated delegation project is not clean after its initial commit"
        );
        fs::write(
            context.output.join("delegation-runbook.md"),
            include_str!("../../../DELEGATION.md"),
        )?;
        fs::write(
            context.output.join("delegation-environment.json"),
            serde_json::to_vec_pretty(&serde_json::json!({
                "scenario":context.scenario.name(), "home":context.home, "project":project,
                "fixtureOrigin":host, "statePath":pl_provider_fixture::delegation::STATE_PATH,
                "releasePath":pl_provider_fixture::delegation::RELEASE_PATH,
                "accountEndpointAliases":{"a":"/v1/delegation-a/responses","b":"/v1/delegation-b/responses"},
                "humanVerdict":"pending", "platform":"linux",
            }))?,
        )?;
        let phases: &[&str] = if matches!(
            context.scenario,
            Scenario::Lifecycle | Scenario::Window | Scenario::Recovery | Scenario::Worktree
        ) {
            &["first", "reopen"]
        } else {
            &["first"]
        };
        for phase in phases {
            let phase_output = context.output.join(phase);
            fs::create_dir(&phase_output)?;
            let gui_log_path = context.working.join(format!("delegation-gui-{phase}.log"));
            let phase_result = run_phase(
                context,
                &project,
                &phase_output,
                &gui_log_path,
                phase,
                host,
                &mut fixture,
            );
            let log_result = write_sanitized_log(&gui_log_path, &phase_output.join("gui.log"));
            bots_fixture::with_cleanup(phase_result, log_result)?;
            let state = read_state(host)?;
            ensure!(
                state.failures.is_empty(),
                "delegation provider rejected a request: {:?}",
                state.failures
            );
            fs::write(
                phase_output.join("provider-observations.json"),
                serde_json::to_vec_pretty(&state)?,
            )?;
            if context.scenario == Scenario::Recovery {
                if let Some(first) = states.first() {
                    recovery::check_reopened(first, &state)?;
                } else {
                    recovery::check_first(&state)?;
                }
            }
            states.push(state);
        }
        if matches!(context.scenario, Scenario::Lifecycle | Scenario::Window) {
            let child_requests = |state: &LiveState| {
                state
                    .observations
                    .iter()
                    .filter(|row| row.marker.starts_with("[[delegation:child:"))
                    .count()
            };
            ensure!(
                child_requests(&states[0]) == child_requests(&states[1]),
                "cold list/detail/close/reopen unexpectedly invoked a child model"
            );
        }
        if context.scenario == Scenario::Enablement {
            let state = states.last().context("no provider state recorded")?;
            ensure!(
                state.inflight_arrived && state.inflight_released,
                "enablement scene did not exercise its real completion gate"
            );
            ensure!(
                state
                    .observations
                    .iter()
                    .all(|row| !row.marker.starts_with("[[delegation:disabled-next]]")),
                "disabled next Turn reached the supplier"
            );
            ensure!(
                state
                    .observations
                    .iter()
                    .all(|row| !row.marker.starts_with("[[delegation:child:")),
                "enablement rejected spawn started child provider work or a fallback"
            );
        }
        Ok(())
    })();

    // Capture the latest wire evidence even after a Driver/GUI failure, before
    // shutting down its sole listener owner. Failure remains non-zero.
    let final_state = read_state(host).and_then(|state| {
        fs::write(
            context.output.join("provider-observations.json"),
            serde_json::to_vec_pretty(&state)?,
        )?;
        Ok(())
    });
    let stopped = fixture.stop(context.requests_file).and_then(|status| {
        ensure!(status.success(), "delegation provider fixture exited with {status}; main flow incomplete or rejected (see fixture.log)");
        Ok(())
    });
    drop(fixture);
    let logs = write_fixture_log(context.fixture_log, &context.output.join("fixture.log"));
    let requests = if context.requests_file.is_file() {
        sanitize_requests(context.requests_file, &context.output.join("requests.json"))
    } else {
        Err(anyhow::anyhow!(
            "delegation fixture did not publish its final request evidence"
        ))
    };
    fs::write(
        context.output.join("delegation-result.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "scenario":context.scenario.name(),"platform":"linux","humanVerdict":"pending",
            "journeyCompleted":journey.is_ok(),"providerStoppedSuccessfully":stopped.is_ok(),
            "error":journey.as_ref().err().map(|error| format!("{error:#}")),
            "fixtureError":stopped.as_ref().err().map(|error| format!("{error:#}")),
            "unprovedConcurrency":["evaluate/send/close lock ordering","spawn/archive interleaving","cancelled write waiter commit/cleanup failure"],
        }))?,
    )?;
    println!(
        "Evidence: {} (human verdict pending; not a live-provider compatibility result)",
        context.output.display()
    );
    let result = bots_fixture::with_cleanup(journey, final_state);
    let result = bots_fixture::with_cleanup(result, stopped);
    bots_fixture::with_cleanup(bots_fixture::with_cleanup(result, logs), requests)
}

fn run_fixture_git(project: &Path, args: &[&str]) -> Result<std::process::Output> {
    let output = Command::new("git")
        .current_dir(project)
        .args([
            "-c",
            "core.hooksPath=/dev/null",
            "-c",
            "credential.helper=",
            "-c",
            "commit.gpgsign=false",
            "-c",
            "user.name=Anywork Fixture",
            "-c",
            "user.email=fixture@example.invalid",
        ])
        .args(args)
        .output()
        .context("run isolated delegation project Git command")?;
    ensure!(
        output.status.success(),
        "isolated delegation project Git command {:?} failed: {}",
        args,
        String::from_utf8_lossy(&output.stderr)
    );
    Ok(output)
}

fn run_phase(
    context: &ScenarioContext<'_>,
    project: &Path,
    output: &Path,
    gui_log_path: &Path,
    phase: &str,
    host: &str,
    fixture: &mut OwnedProcess,
) -> Result<()> {
    let log = File::create(gui_log_path)?;
    let mut command = Command::new("cargo");
    command
        .current_dir(context.workspace)
        .args(["xtask", "run-gui", "--driver"])
        .env("ANYWORK_HOME", context.home)
        .stdout(Stdio::from(log.try_clone()?))
        .stderr(Stdio::from(log));
    let mut gui = OwnedProcess::start(&mut command, false)?;
    let vm = wait_for_vm(gui_log_path, &mut gui, fixture, context.interrupt)?;
    println!(
        "{} {phase}: native GUI ready. Runbook: {}. Runtime log: {}",
        context.scenario.name(),
        context.output.join("delegation-runbook.md").display(),
        gui_log_path.display()
    );
    if let Some(driver) = context.driver {
        let driver = driver.canonicalize()?;
        let driver_log = File::create(output.join("journey-driver.log"))?;
        let mut command = driver_command(
            context.app_dir,
            driver.to_str().context("Driver path is not UTF-8")?,
        );
        command
            .arg(&vm)
            .arg(project)
            .arg(output)
            .arg(context.working)
            .arg(phase)
            .arg(host)
            .env("ANYWORK_HOME", context.home)
            .stdout(Stdio::from(driver_log.try_clone()?))
            .stderr(Stdio::from(driver_log));
        let mut driver = OwnedProcess::start(&mut command, false)?;
        let deadline = Instant::now() + Duration::from_secs(1800);
        loop {
            if let Some(status) = driver.child.try_wait()? {
                driver.stopped = true;
                ensure!(
                    status.success(),
                    "delegation {phase} Driver failed with {status}; see journey-driver.log"
                );
                break;
            }
            ensure!(
                !gui.exited()? && !fixture.exited()?,
                "GUI/provider exited during delegation Driver"
            );
            ensure!(
                context.interrupt.try_recv().is_err(),
                "delegation Driver cancelled"
            );
            ensure!(
                Instant::now() < deadline,
                "delegation Driver exceeded bounded phase deadline"
            );
            thread::sleep(Duration::from_millis(100));
        }
    } else {
        manual_phase(context, &mut gui, fixture, phase)?;
    }
    // Existing canonical capture saves the actual screenshot and asks the app
    // to shut down. Await both shutdown_completed and the real process exit.
    capture(
        context.app_dir,
        context.home,
        &vm,
        output,
        context.interrupt,
    )?;
    ensure!(
        fs::read_to_string(output.join("capture-stage.txt"))?.trim() == "shutdown_completed",
        "capture did not observe native Runtime shutdown_completed"
    );
    let exit = wait_for_gui_exit(&mut gui, Duration::from_secs(120), phase)?;
    ensure!(exit.success(), "delegation native GUI exited with {exit}");
    ensure!(
        count_gui_errors(gui_log_path)? == 0,
        "delegation native GUI reported unhandled errors"
    );
    Ok(())
}

fn manual_phase(
    context: &ScenarioContext<'_>,
    gui: &mut OwnedProcess,
    fixture: &mut OwnedProcess,
    phase: &str,
) -> Result<()> {
    println!(
        "Observe {phase} using Flutter Driver. Type action codes to record; done captures and shuts down this phase. Lifecycle/window/recovery reopen the SAME environment automatically. Ctrl-C fails and cleans up."
    );
    let (tx, rx) = mpsc::channel();
    thread::spawn(move || {
        loop {
            let mut line = String::new();
            match io::stdin().read_line(&mut line) {
                Ok(0) | Err(_) => {
                    let _ = tx.send(InputEvent::Eof);
                    break;
                }
                Ok(_) if line.trim() == "done" => {
                    let _ = tx.send(InputEvent::Done);
                    break;
                }
                Ok(_) => {
                    if tx.send(InputEvent::Line(line)).is_err() {
                        break;
                    }
                }
            }
        }
    });
    let mut operations = Vec::new();
    let deadline = Instant::now() + Duration::from_secs(3600);
    loop {
        match rx.try_recv() {
            Ok(InputEvent::Done) => return Ok(()),
            Ok(InputEvent::Eof) | Err(mpsc::TryRecvError::Disconnected) => {
                bail!("delegation input closed before done")
            }
            Ok(InputEvent::Line(line)) => {
                operations.push(ManualOperation {
                    at_unix_ms: SystemTime::now().duration_since(UNIX_EPOCH)?.as_millis(),
                    action: safe_action(&line),
                    outcome: None,
                });
                fs::write(
                    context.output.join(format!("operations-{phase}.json")),
                    serde_json::to_vec_pretty(&operations)?,
                )?;
            }
            Err(mpsc::TryRecvError::Empty) => {}
        }
        ensure!(
            !gui.exited()? && !fixture.exited()?,
            "GUI/provider exited before delegation manual phase completed"
        );
        ensure!(
            context.interrupt.try_recv().is_err(),
            "delegation manual phase cancelled"
        );
        ensure!(
            Instant::now() < deadline,
            "delegation manual phase exceeded deadline"
        );
        thread::sleep(Duration::from_millis(100));
    }
}

fn read_state(host: &str) -> Result<LiveState> {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    runtime.block_on(async {
        reqwest::Client::builder()
            .timeout(Duration::from_secs(5))
            .build()?
            .get(format!(
                "{host}{}",
                pl_provider_fixture::delegation::STATE_PATH
            ))
            .send()
            .await?
            .error_for_status()?
            .json()
            .await
            .context("read fresh delegation provider observations")
    })
}
