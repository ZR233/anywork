//! Native GUI skill activity and context-compaction coordination.
//!
//! Two owned GUI lifecycles share one isolated home. The first loads real
//! synthetic skills, forces one failing and one succeeding manual compaction and
//! reloads a skill. An additional same-Turn journey mutates project Skill files
//! through real product tools and observes dynamic discovery. The second
//! reopens the same home with a one-token automatic
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

/// The synthetic skills seeded into the isolated standard user skills directory.
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

/// One synthetic skill written into the isolated standard user skills directory.
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
    let first_log = working.join("skill-activity-first-gui.log");
    let reopen_log = working.join("skill-activity-reopen-gui.log");
    // Synthetic Skills never live inside the evidence directory: production
    // discovery walks every Skill root with a git-aware walker, and the
    // evidence directory sits in the repository's ignored `target/` tree, where
    // such a root is skipped without a warning. The seeds therefore own a
    // temporary root under the system temp directory and the isolated process
    // home points at it. The guard lives in this scope, so the
    // seeds outlive both GUI lifecycles and are released only after every owned
    // process has been reaped.
    let seeds = tempfile::Builder::new()
        .prefix("skill-activity-skills-")
        .tempdir()
        .context("failed to create the synthetic skill seed directory")?;
    let skills_dir = home.join(".agents/skills");
    // Project discovery must not inherit the evidence directory's ignored
    // `target/` ancestor either. This same guard owns both synthetic roots and
    // outlives both GUI lifecycles; only product file tools mutate project Skills.
    let project = seeds.path().join("project");
    let journey = (|| -> Result<()> {
        seed_skills(&skills_dir)?;
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
        // compaction, then the reload Turn. Capture+exit reaps every owned
        // process before the same home is reopened below.
        {
            let mut gui = start_recovery_gui(workspace, home, &first_log)?;
            let vm_url = wait_for_vm(&first_log, &mut gui, &mut fixture, interrupt)?;
            observe_capture_exit(
                app_dir,
                &vm_url,
                output,
                interrupt,
                &mut gui,
                Some(&mut fixture),
                &format!(
                    "skill-activity first: open {}, load seeded skills, run failing then succeeding compaction, reload a skill, then type done.",
                    project.display()
                ),
            )?;
            let _ = wait_for_gui_exit(&mut gui, Duration::from_secs(180), "first")?;
        }
        verify_dynamic_mutations(&project)?;

        // 2. The reopened lifecycle cold-reopens the same home with a one-token
        // automatic threshold: its first Turn must commit an automatic compaction
        // that clears the restored activation, and the last Turn really loads a
        // Skill again before its post-load compaction is cancelled through the
        // normal stop entry. Nothing is submitted after that stop.
        enable_automatic_compaction(home)?;
        {
            let mut gui = start_recovery_gui(workspace, home, &reopen_log)?;
            let vm_url = wait_for_vm(&reopen_log, &mut gui, &mut fixture, interrupt)?;
            observe_capture_exit(
                app_dir,
                &vm_url,
                output,
                interrupt,
                &mut gui,
                Some(&mut fixture),
                "skill-activity reopen: reopen the same home, confirm automatic compaction, load a skill, cancel the post-load compaction, then type done.",
            )?;
            let _ = wait_for_gui_exit(&mut gui, Duration::from_secs(180), "reopen")?;
        }
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

/// Confirms that the real product mutations persisted, without synthesizing a
/// discovery result or removing the invalid Skill on the product's behalf.
fn verify_dynamic_mutations(project: &Path) -> Result<()> {
    let root = project.join(".agents/skills");
    ensure!(
        !root
            .join(pl_provider_fixture::SKILL_ACTIVITY_DYNAMIC_DELETED)
            .exists(),
        "the same-Turn file tools did not delete the synthetic Skill directory"
    );
    let invalid = fs::read_to_string(
        root.join(pl_provider_fixture::SKILL_ACTIVITY_DYNAMIC_INVALID)
            .join("SKILL.md"),
    )
    .context("the invalid synthetic Skill must remain on disk")?;
    ensure!(
        invalid.contains(pl_provider_fixture::SKILL_ACTIVITY_DYNAMIC_INVALID_MARKER)
            && invalid.contains("disable-model-invocation: not-a-boolean"),
        "the same-Turn file tools did not persist the invalid Skill document"
    );
    Ok(())
}

/// Proves production discovery uses the standard user skills path and the
/// persisted config no longer selects a private user directory.
fn verify_seeded_skills(home: &Path, skills_dir: &Path) -> Result<()> {
    let file = home.join("config.toml");
    let document: toml::Value = toml::from_str(
        &fs::read_to_string(&file)
            .with_context(|| format!("failed to read isolated config: {}", file.display()))?,
    )?;
    let user_dir = document
        .get("skills")
        .and_then(|skills| skills.get("user_dir"))
        .and_then(toml::Value::as_str);
    ensure!(
        user_dir.is_none(),
        "the isolated config still contains retired `[skills].user_dir`"
    );
    ensure!(
        skills_dir == home.join(".agents/skills"),
        "synthetic user skills are not in the standard isolated home directory"
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
