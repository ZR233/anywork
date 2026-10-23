//! Native GUI skill activity and context-compaction coordination.
//!
//! Two owned GUI lifecycles share one isolated home. The first loads real
//! synthetic skills, forces one failing and one succeeding manual compaction and
//! reloads a skill; the second reopens the same home with a one-token automatic
//! threshold, proves that an automatic compaction really commits and clears the
//! restored activation, and finally cancels the last Turn while its post-load
//! compaction is streaming. Nothing is submitted after that stop.
//! Isolation, fixture, process ownership and evidence writing follow the
//! existing recovery harness; the human verdict stays pending.

use super::*;

pub(super) struct SkillActivityScenario<'a> {
    pub workspace: &'a Path,
    pub app_dir: &'a Path,
    pub home: &'a Path,
    pub working: &'a Path,
    pub output: &'a Path,
    pub fixture_log: &'a Path,
    pub requests_file: &'a Path,
    pub status_file: &'a Path,
    pub interrupt: &'a mpsc::Receiver<()>,
}

/// The synthetic skills seeded into the isolated `[skills].user_dir`.
///
/// Only the short skill carries a support file: reading it must stay an ordinary
/// successful tool row instead of a second activation.
const SEEDED_SKILLS: [SeededSkill; 2] = [
    SeededSkill {
        name: pl_provider_fixture::SKILL_ACTIVITY_SHORT_NAME,
        description: "Synthetic short skill for the native skill activity acceptance.",
        body_marker: pl_provider_fixture::SKILL_ACTIVITY_BODY_SHORT,
        support: true,
    },
    SeededSkill {
        name: pl_provider_fixture::SKILL_ACTIVITY_LONG_NAME,
        description: "Synthetic long skill name for narrow-window layout review.",
        body_marker: pl_provider_fixture::SKILL_ACTIVITY_BODY_LONG,
        support: false,
    },
];

/// One synthetic skill written into the isolated `[skills].user_dir`.
///
/// Only one of them carries a support file, because reading it must stay an
/// ordinary successful tool row instead of a second activation.
struct SeededSkill {
    name: &'static str,
    description: &'static str,
    body_marker: &'static str,
    support: bool,
}

pub(super) fn run(context: &SkillActivityScenario<'_>, mut fixture: OwnedProcess) -> Result<()> {
    let SkillActivityScenario {
        workspace,
        app_dir,
        home,
        working,
        output,
        fixture_log,
        requests_file,
        status_file,
        interrupt,
    } = context;
    let project = working.join("skill-activity-project");
    let stage = working.join("skill-activity-stage");
    let first_log = working.join("skill-activity-first-gui.log");
    let reopen_log = working.join("skill-activity-reopen-gui.log");
    let mut driver_exits: BTreeMap<&'static str, Option<std::process::ExitStatus>> =
        BTreeMap::new();
    // Synthetic Skills never live inside the evidence directory: production
    // discovery walks every Skill root with a git-aware walker, and the
    // evidence directory sits in the repository's ignored `target/` tree, where
    // such a root is skipped without a warning. The seeds therefore own a
    // temporary root under the system temp directory and the isolated config
    // points `[skills].user_dir` at it. The guard lives in this scope, so the
    // seeds outlive both GUI lifecycles and are released only after every owned
    // process has been reaped.
    let seeds = tempfile::Builder::new()
        .prefix("skill-activity-skills-")
        .tempdir()
        .context("failed to create the synthetic skill seed directory")?;
    let skills_dir = seeds.path().join("skills");
    let journey = (|| -> Result<()> {
        seed_skills(&skills_dir)?;
        point_user_skills_dir(home, &skills_dir)?;
        verify_seeded_skills(home, &skills_dir)?;
        fs::create_dir(&project)?;
        ensure!(
            Command::new("git")
                .args(["init", "-q"])
                .arg(&project)
                .status()?
                .success(),
            "failed to initialize the isolated skill-activity project"
        );

        // 1. First lifecycle: real loads, one failing and one succeeding manual
        // compaction, then the reload Turn. The Driver shuts the GUI down through
        // the normal request, so this scope reaps every owned process before the
        // same home is reopened below.
        {
            let mut gui = start_recovery_gui(workspace, home, &first_log)?;
            let vm_url = wait_for_vm(&first_log, &mut gui, &mut fixture, interrupt)?;
            let mut driver = start_skill_activity_driver(context, "first", &vm_url, &project)?;
            let exit = wait_for_skill_activity_driver(
                "first",
                &stage,
                &mut driver,
                &mut gui,
                &mut fixture,
                interrupt,
            )?;
            driver_exits.insert("first", Some(exit));
        }
        ensure_summary(output, "first")?;
        let observed: serde_json::Value = serde_json::from_slice(
            &fs::read(working.join("skill-activity-observed.json"))
                .context("the first lifecycle did not record its observations")?,
        )?;
        ensure!(
            observed["threadId"].is_string() && observed["skillNames"].is_array(),
            "the first lifecycle observations are incomplete: {observed}"
        );

        // 2. The reopened lifecycle cold-reopens the same home with a one-token
        // automatic threshold: its first Turn must commit an automatic compaction
        // that clears the restored activation, and the last Turn really loads a
        // Skill again before its post-load compaction is cancelled through the
        // normal stop entry. Nothing is submitted after that stop.
        enable_automatic_compaction(home)?;
        {
            let mut gui = start_recovery_gui(workspace, home, &reopen_log)?;
            let vm_url = wait_for_vm(&reopen_log, &mut gui, &mut fixture, interrupt)?;
            let mut driver = start_skill_activity_driver(context, "reopen", &vm_url, &project)?;
            let exit = wait_for_skill_activity_driver(
                "reopen",
                &stage,
                &mut driver,
                &mut gui,
                &mut fixture,
                interrupt,
            )?;
            driver_exits.insert("reopen", Some(exit));
        }
        ensure_summary(output, "reopen")?;
        Ok(())
    })();

    for (source, destination) in [
        (&first_log, "skill-activity-first-gui.log"),
        (&reopen_log, "skill-activity-reopen-gui.log"),
    ] {
        if source.is_file() {
            write_sanitized_log(source, &output.join(destination))?;
        }
    }
    let redactions = [
        (app_dir.to_string_lossy().into_owned(), "<app>"),
        (workspace.to_string_lossy().into_owned(), "<workspace>"),
        (home.to_string_lossy().into_owned(), "<home>"),
        (working.to_string_lossy().into_owned(), "<coord>"),
    ];
    for phase in ["first", "reopen"] {
        write_process_evidence(
            &working.join(format!("skill-activity-{phase}-driver.log")),
            output,
            &format!("skill-activity-{phase}"),
            "driver",
            driver_exits.get(phase).copied().flatten(),
            journey.as_ref().err(),
            &redactions,
        )?;
    }
    if stage.is_file() {
        let value = fs::read_to_string(&stage)?;
        if value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'.' | b'-'))
        {
            fs::write(output.join("skill-activity-stage.txt"), value)?;
        }
    }

    let fixture_result = fixture.stop(requests_file);
    drop(fixture);
    write_fixture_log(fixture_log, &output.join("fixture.log"))?;
    let requests = if requests_file.is_file() {
        sanitize_requests(requests_file, &output.join("requests.json"))?;
        serde_json::from_slice::<Vec<serde_json::Value>>(&fs::read(requests_file)?)?
    } else {
        Vec::new()
    };
    let accepted = requests
        .iter()
        .filter(|row| row["accepted"] == true)
        .count();
    let rejected = requests
        .iter()
        .filter(|row| row["accepted"] == false)
        .count();
    let notes: Vec<String> = requests
        .iter()
        .filter_map(|row| {
            row.pointer("/diagnostic/category")
                .and_then(serde_json::Value::as_str)
                .map(str::to_owned)
        })
        .collect();
    let live = if status_file.is_file() {
        serde_json::from_slice::<pl_provider_fixture::FixtureLiveStatus>(&fs::read(status_file)?)
            .ok()
    } else {
        None
    };
    fs::write(
        output.join("fixture-status.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "scenario": "skill-activity",
            "acceptedRequests": accepted,
            "rejectedRequests": rejected,
            "notes": notes,
            "consumedSteps": live.as_ref().map(|live| live.consumed_steps),
            "expectedSteps": live.as_ref().map(|live| live.expected_steps),
            "remainingOptionalOnly": live.as_ref().map(|live| live.remaining_optional),
            "completed": fixture_result.as_ref().is_ok_and(|status| status.success()),
        }))?,
    )?;
    let mut errors = 0;
    for log in [&first_log, &reopen_log] {
        if log.is_file() {
            errors += count_gui_errors(log)?;
        }
    }
    fs::write(
        output.join("gui-health.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "unhandledErrors": errors, "humanVerdict": "pending"
        }))?,
    )?;
    println!("Evidence: {} (human verdict pending)", output.display());

    journey?;
    ensure!(
        rejected == 0,
        "skill-activity fixture rejected {rejected} request(s): {notes:?}"
    );
    ensure!(
        live.as_ref().is_none_or(|live| live.remaining_optional),
        "skill-activity fixture left a required script step unconsumed: {live:?}"
    );
    // A Thread that never compacted, never reloaded or never reopened fails in
    // the journey checks instead of presenting a green summary from fixture
    // traffic alone.
    ensure!(
        fixture_result.is_ok_and(|status| status.success()) && errors == 0,
        "skill-activity fixture or GUI health incomplete; human verdict pending"
    );
    Ok(())
}

fn seed_skills(skills_dir: &Path) -> Result<()> {
    for skill in SEEDED_SKILLS {
        let SeededSkill {
            name,
            description,
            body_marker,
            support,
        } = skill;
        let directory = skills_dir.join(name);
        fs::create_dir_all(&directory)?;
        let document = format!(
            "---\nname: {name}\ndescription: {description}\n---\n\n\
             # {name}\n\nSynthetic skill body marker: {body_marker}.\n\n\
             This body belongs to the native skill activity acceptance only.\n"
        );
        fs::write(directory.join("SKILL.md"), document)?;
        if support {
            let references = directory.join("references");
            fs::create_dir_all(&references)?;
            fs::write(
                references.join(
                    pl_provider_fixture::SKILL_ACTIVITY_SUPPORT_FILE
                        .trim_start_matches("references/"),
                ),
                format!(
                    "{}\n\nSynthetic support note for {name}.\n",
                    pl_provider_fixture::SKILL_ACTIVITY_SUPPORT_MARKER
                ),
            )?;
        }
    }
    Ok(())
}

/// Proves the isolated home really points production discovery at the seeded
/// Skills before any GUI process starts.
///
/// The check reads the persisted `config.toml` instead of re-deriving the value
/// from the in-memory config, so a lane that silently drops `[skills]` fails
/// here with its own message rather than as an unexplained failing `skill_view`.
fn verify_seeded_skills(home: &Path, skills_dir: &Path) -> Result<()> {
    let file = home.join("config.toml");
    let document: toml::Value = toml::from_str(
        &fs::read_to_string(&file)
            .with_context(|| format!("failed to read isolated config: {}", file.display()))?,
    )?;
    let expected = skills_dir.to_string_lossy().into_owned();
    let user_dir = document
        .get("skills")
        .and_then(|skills| skills.get("user_dir"))
        .and_then(toml::Value::as_str)
        .context("the isolated config has no `[skills].user_dir`")?;
    ensure!(
        user_dir == expected,
        "the isolated config discovers Skills from `{user_dir}` instead of `{expected}`"
    );
    for skill in SEEDED_SKILLS {
        let document = skills_dir.join(skill.name).join("SKILL.md");
        ensure!(
            document.is_file(),
            "the seeded skill document is missing: {}",
            document.display()
        );
    }
    Ok(())
}

/// Points the isolated config's `[skills].user_dir` at the seeded Skill root.
///
/// Only that one field changes: every other user-visible setting written by the
/// shared fixture config stays untouched.
fn point_user_skills_dir(home: &Path, skills_dir: &Path) -> Result<()> {
    let file = home.join("config.toml");
    let text = fs::read_to_string(&file)
        .with_context(|| format!("failed to read isolated config: {}", file.display()))?;
    let mut config: StudioConfig = toml::from_str(&text)
        .with_context(|| format!("failed to parse isolated config: {}", file.display()))?;
    config.skills.user_dir = skills_dir.to_string_lossy().into_owned();
    persist_config(home, &config)
}

/// Applies the automatic compaction threshold to the already written isolated
/// config, keeping every other user-visible setting untouched.
fn enable_automatic_compaction(home: &Path) -> Result<()> {
    let file = home.join("config.toml");
    let text = fs::read_to_string(&file)
        .with_context(|| format!("failed to read isolated config: {}", file.display()))?;
    let mut config: StudioConfig = toml::from_str(&text)
        .with_context(|| format!("failed to parse isolated config: {}", file.display()))?;
    for account in config.models.accounts.values_mut() {
        account.set_model_auto_compact_override("fixture-model", Some(1))?;
    }
    persist_config(home, &config)
}

/// Starts one phase of the Driver journey inside the current isolated run.
fn start_skill_activity_driver(
    context: &SkillActivityScenario<'_>,
    phase: &str,
    vm_url: &str,
    project: &Path,
) -> Result<OwnedProcess> {
    let log = File::create(
        context
            .working
            .join(format!("skill-activity-{phase}-driver.log")),
    )?;
    let mut command = driver_command(context.app_dir, "test_driver/skill_activity_journey.dart");
    command
        .arg(phase)
        .arg(vm_url)
        .arg(project)
        .arg(context.output)
        .arg(context.working)
        .arg(context.status_file)
        .env("ANYWORK_HOME", context.home)
        .stdout(Stdio::from(log.try_clone()?))
        .stderr(Stdio::from(log));
    OwnedProcess::start(&mut command, false)
}

fn wait_for_skill_activity_driver(
    phase: &str,
    stage: &Path,
    driver: &mut OwnedProcess,
    gui: &mut OwnedProcess,
    fixture: &mut OwnedProcess,
    interrupt: &mpsc::Receiver<()>,
) -> Result<std::process::ExitStatus> {
    let deadline = Instant::now() + Duration::from_secs(1200);
    loop {
        if let Some(status) = driver.child.try_wait()? {
            driver.stopped = true;
            ensure!(
                status.success(),
                "skill-activity {phase} Driver failed with {status} (last stage: {})",
                fs::read_to_string(stage).unwrap_or_else(|_| "connect".to_owned())
            );
            return Ok(status);
        }
        ensure!(
            !gui.exited()?,
            "GUI exited before the skill-activity {phase} journey completed"
        );
        ensure!(
            !fixture.exited()?,
            "account fixture exited during the skill-activity {phase} journey"
        );
        ensure!(
            interrupt.try_recv().is_err(),
            "skill-activity {phase} journey cancelled"
        );
        ensure!(
            Instant::now() < deadline,
            "skill-activity {phase} journey timed out (last stage: {})",
            fs::read_to_string(stage).unwrap_or_else(|_| "connect".to_owned())
        );
        thread::sleep(Duration::from_millis(200));
    }
}

/// Rejects a summary that is missing, failed, not pending, or has a false check.
fn ensure_summary(output: &Path, phase: &str) -> Result<()> {
    let path = output.join(format!("skill-activity-{phase}-summary.json"));
    let summary: serde_json::Value = serde_json::from_slice(
        &fs::read(&path)
            .with_context(|| format!("Flutter Driver wrote no summary: {}", path.display()))?,
    )?;
    ensure!(
        summary["scenario"] == "skill-activity" && summary["phase"] == phase,
        "skill-activity {phase} summary has the wrong identity: {summary}"
    );
    ensure!(
        summary["status"] == "complete" && summary["verdict"] == "pending",
        "skill-activity {phase} journey did not complete with a pending verdict: {summary}"
    );
    let checks = summary["checks"]
        .as_object()
        .with_context(|| format!("skill-activity {phase} summary recorded no checks"))?;
    ensure!(
        !checks.is_empty(),
        "skill-activity {phase} summary recorded no checks"
    );
    for (name, value) in checks {
        ensure!(
            value == &serde_json::Value::Bool(true),
            "skill-activity {phase} check {name} did not pass"
        );
    }
    Ok(())
}
