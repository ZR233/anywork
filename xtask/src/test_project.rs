//! Project-integration runner for desktop `integration_test` and native lifecycle.
//!
//! The command discovers cases, prepares the existing Flutter or acceptance
//! environment, and records a machine-readable report. It does not invent a
//! second test DSL or link Studio/database into xtask.

use std::ffi::OsString;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{Context, Result, bail, ensure};
use pl_dev_support::paths;
use serde::Serialize;

use crate::cli::{ProjectSet, ProjectSuite, TestProjectOptions};
use crate::flutter;
use crate::studio_acceptance;

/// Desktop smoke is the unique subset of the discovered full set.
const DESKTOP_SMOKE_IDS: &[&str] = &["wait_events"];
/// Native smoke covers the current automatic exit/reopen preset.
const NATIVE_SMOKE_IDS: &[&str] = &["shutdown"];

#[derive(Debug, Clone, PartialEq, Eq)]
struct DiscoveredCase {
    id: String,
    target: CaseTarget,
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum CaseTarget {
    Desktop { relative_path: String },
    Native { preset: &'static str },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
enum AutomaticVerdict {
    Passed,
    Failed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
enum ManualVerdict {
    NotRequired,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
enum CleanupVerdict {
    Confirmed,
    Unknown,
}

#[derive(Debug, Serialize)]
struct ProjectReport {
    source: ReportSource,
    automatic: AutomaticVerdict,
    manual: ManualVerdict,
    cleanup: CleanupVerdict,
    cases: Vec<CaseRecord>,
    artifacts: Vec<String>,
}

#[derive(Debug, Serialize)]
struct ReportSource {
    sha: String,
    os: String,
    architecture: String,
    sdk: String,
    features: String,
    run: String,
}

#[derive(Debug, Serialize)]
struct CaseRecord {
    id: String,
    result: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    reason: Option<String>,
}

/// Discovers and runs or lists the selected project-integration cases.
///
/// # Errors
/// Returns an error when discovery is empty, a requested case is missing, a
/// case fails, the report directory already exists, or the report cannot be
/// written after a run that requested `--output`.
pub(crate) fn run(options: TestProjectOptions) -> Result<()> {
    let workspace_root = paths::workspace_root()?;
    let app_dir = paths::studio_app_dir(&workspace_root);
    let discovered = match options.suite {
        ProjectSuite::Desktop => discover_desktop_cases(&app_dir)?,
        ProjectSuite::Native => native_cases(),
    };
    let selected = select_cases(
        &discovered,
        options.suite,
        options.set,
        options.case.as_deref(),
    )?;
    if options.list {
        for case in &selected {
            println!("{}", case.id);
        }
        return Ok(());
    }

    let output = match options.output.as_deref() {
        Some(path) => Some(prepare_output_dir(path)?),
        None => None,
    };
    let native_executable = if matches!(options.suite, ProjectSuite::Native) {
        Some(studio_acceptance::build_acceptance_tool(&workspace_root)?)
    } else {
        None
    };
    let mut records = Vec::new();
    let mut artifacts = Vec::new();
    let mut failed = false;
    let mut cleanup = CleanupVerdict::Confirmed;
    for case in &selected {
        let case_output = output
            .as_ref()
            .map(|root| root.join("cases").join(&case.id));
        match run_case(case, case_output.as_deref(), native_executable.as_deref()) {
            Ok(()) => records.push(CaseRecord {
                id: case.id.clone(),
                result: "passed",
                reason: None,
            }),
            Err(error) => {
                failed = true;
                if case_output.is_none() {
                    cleanup = CleanupVerdict::Unknown;
                }
                if let Some(path) = &case_output
                    && path.exists()
                {
                    artifacts.push(path.display().to_string());
                }
                records.push(CaseRecord {
                    id: case.id.clone(),
                    result: "failed",
                    reason: Some(error.to_string()),
                });
            }
        }
    }
    let automatic = if failed {
        AutomaticVerdict::Failed
    } else {
        AutomaticVerdict::Passed
    };
    if let Some(output) = output {
        write_report(
            &output,
            ProjectReport {
                source: report_source(&workspace_root, options.suite, options.set)?,
                automatic,
                manual: ManualVerdict::NotRequired,
                cleanup,
                cases: records,
                artifacts,
            },
        )?;
    }
    ensure!(!failed, "{} {} suite failed", options.suite, options.set);
    Ok(())
}

fn run_case(
    case: &DiscoveredCase,
    output: Option<&Path>,
    native_executable: Option<&Path>,
) -> Result<()> {
    match case.target {
        CaseTarget::Desktop { ref relative_path } => {
            if let Some(preset) = desktop_harness_preset(&case.id)
                && !desktop_env_ready(&case.id)
            {
                let workspace = paths::workspace_root()?;
                let executable = studio_acceptance::build_acceptance_tool(&workspace)?;
                return wait_acceptance_preset(&executable, preset, output);
            }
            flutter::run_desktop_integration_test(Path::new(relative_path))
        }
        CaseTarget::Native { preset } => {
            let executable =
                native_executable.context("native acceptance executable is missing")?;
            wait_acceptance_preset(executable, preset, output)
        }
    }
}

/// Names the unique acceptance preset that prepares one desktop case.
///
/// The id is the discovered Flutter file stem; the preset is the existing
/// `manual-gui` environment owner. Assertions stay in Flutter.
fn desktop_harness_preset(id: &str) -> Option<&'static str> {
    match id {
        "wait_events" => Some("wait-events"),
        "conversation_read_work" => Some("conversation-read-work"),
        _ => None,
    }
}

fn desktop_env_ready(id: &str) -> bool {
    match id {
        "wait_events" => env_present("ANYWORK_WAIT_PROJECTS"),
        "conversation_read_work" => {
            env_present("ANYWORK_READ_CASES")
                && env_present("ANYWORK_READ_REPORT")
                && env_present("ANYWORK_HOME")
        }
        _ => true,
    }
}

fn env_present(name: &str) -> bool {
    std::env::var_os(name).is_some_and(|value| !value.is_empty())
}

fn wait_acceptance_preset(executable: &Path, preset: &str, output: Option<&Path>) -> Result<()> {
    let mut args = vec![OsString::from("--preset"), OsString::from(preset)];
    if let Some(output) = output {
        args.push(OsString::from("--output"));
        args.push(output.as_os_str().to_os_string());
    }
    studio_acceptance::wait_acceptance_tool(executable, &args)
}

fn discover_desktop_cases(app_dir: &Path) -> Result<Vec<DiscoveredCase>> {
    let integration_root = app_dir.join("integration_test");
    ensure!(
        integration_root.is_dir(),
        "desktop integration_test directory is missing: {}",
        integration_root.display()
    );
    let functional = integration_root.join("functional");
    let search_root = if dart_test_files(&functional)?.is_empty() {
        integration_root
    } else {
        functional
    };
    let files = dart_test_files(&search_root)?;
    let mut cases = Vec::new();
    for path in files {
        let id = desktop_case_id(&path)?;
        let relative_path = path
            .strip_prefix(app_dir)
            .with_context(|| {
                format!(
                    "desktop integration test is outside the app directory: {}",
                    path.display()
                )
            })?
            .to_string_lossy()
            .replace('\\', "/");
        if cases.iter().any(|case: &DiscoveredCase| case.id == id) {
            bail!("duplicate desktop case id `{id}`");
        }
        cases.push(DiscoveredCase {
            id,
            target: CaseTarget::Desktop { relative_path },
        });
    }
    Ok(cases)
}

fn dart_test_files(dir: &Path) -> Result<Vec<PathBuf>> {
    if !dir.is_dir() {
        return Ok(Vec::new());
    }
    let mut files = Vec::new();
    for entry in fs::read_dir(dir).with_context(|| format!("failed to read {}", dir.display()))? {
        let path = entry
            .with_context(|| format!("failed to read {}", dir.display()))?
            .path();
        let name = path
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or_default();
        if path.is_file() && name.ends_with("_test.dart") {
            files.push(path);
        }
    }
    files.sort();
    Ok(files)
}

fn desktop_case_id(path: &Path) -> Result<String> {
    let name = path
        .file_name()
        .and_then(|name| name.to_str())
        .with_context(|| {
            format!(
                "desktop integration test name is not UTF-8: {}",
                path.display()
            )
        })?;
    let Some(id) = name.strip_suffix("_test.dart") else {
        bail!("desktop integration test must end with _test.dart: {name}");
    };
    ensure!(
        !id.is_empty(),
        "desktop integration test has an empty case id"
    );
    Ok(id.to_owned())
}

fn native_cases() -> Vec<DiscoveredCase> {
    ["shutdown", "single-instance"]
        .into_iter()
        .map(|preset| DiscoveredCase {
            id: preset.to_owned(),
            target: CaseTarget::Native { preset },
        })
        .collect()
}

fn select_cases(
    discovered: &[DiscoveredCase],
    suite: ProjectSuite,
    set: ProjectSet,
    requested: Option<&str>,
) -> Result<Vec<DiscoveredCase>> {
    let smoke_ids = match suite {
        ProjectSuite::Desktop => DESKTOP_SMOKE_IDS,
        ProjectSuite::Native => NATIVE_SMOKE_IDS,
    };
    let mut selected: Vec<DiscoveredCase> = discovered
        .iter()
        .filter(|case| match set {
            ProjectSet::Full => true,
            ProjectSet::Smoke => smoke_ids.contains(&case.id.as_str()),
        })
        .cloned()
        .collect();
    if let Some(id) = requested {
        ensure!(
            discovered.iter().any(|case| case.id == id),
            "unknown {suite} case `{id}`; discovered: {}",
            discovered
                .iter()
                .map(|case| case.id.as_str())
                .collect::<Vec<_>>()
                .join(", ")
        );
        selected.retain(|case| case.id == id);
        ensure!(
            !selected.is_empty(),
            "{suite} {set} does not include `{id}`"
        );
    }
    ensure!(!selected.is_empty(), "{suite} {set} discovery is empty");
    Ok(selected)
}

fn prepare_output_dir(path: &Path) -> Result<PathBuf> {
    ensure!(
        !path.exists(),
        "test-project output directory already exists: {}",
        path.display()
    );
    fs::create_dir_all(path).with_context(|| format!("failed to create {}", path.display()))?;
    path.canonicalize()
        .with_context(|| format!("failed to resolve {}", path.display()))
}

fn write_report(output: &Path, report: ProjectReport) -> Result<()> {
    let path = output.join("report.json");
    let body =
        serde_json::to_vec_pretty(&report).context("failed to serialize test-project report")?;
    fs::write(&path, body).with_context(|| format!("failed to write {}", path.display()))?;
    Ok(())
}

fn report_source(
    workspace_root: &Path,
    suite: ProjectSuite,
    set: ProjectSet,
) -> Result<ReportSource> {
    Ok(ReportSource {
        sha: source_sha(workspace_root)?,
        os: std::env::consts::OS.to_owned(),
        architecture: std::env::consts::ARCH.to_owned(),
        sdk: rustc_version()?,
        features: format!("{suite}/{set}"),
        run: "test-project".to_owned(),
    })
}

fn source_sha(workspace_root: &Path) -> Result<String> {
    let output = Command::new("git")
        .args(["rev-parse", "HEAD"])
        .current_dir(workspace_root)
        .output()
        .context("failed to start git rev-parse HEAD")?;
    ensure!(
        output.status.success(),
        "git rev-parse HEAD failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    let sha = String::from_utf8(output.stdout).context("git rev-parse HEAD is not UTF-8")?;
    let sha = sha.trim();
    ensure!(!sha.is_empty(), "git rev-parse HEAD returned an empty SHA");
    Ok(sha.to_owned())
}

fn rustc_version() -> Result<String> {
    let output = Command::new("rustc")
        .arg("--version")
        .output()
        .context("failed to start rustc --version")?;
    ensure!(
        output.status.success(),
        "rustc --version failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    let version = String::from_utf8(output.stdout).context("rustc --version is not UTF-8")?;
    Ok(version.trim().to_owned())
}

#[cfg(test)]
mod tests {
    use super::{
        CaseTarget, DESKTOP_SMOKE_IDS, DiscoveredCase, ProjectSet, ProjectSuite,
        desktop_harness_preset, discover_desktop_cases, native_cases, select_cases,
    };
    use std::fs;
    use std::path::Path;

    #[test]
    fn desktop_discovery_uses_integration_root_until_functional_exists() -> anyhow::Result<()> {
        let root = tempfile::tempdir()?;
        let app = root.path().join("app");
        write_test(&app.join("integration_test/wait_events_test.dart"))?;
        write_test(&app.join("integration_test/conversation_read_work_test.dart"))?;
        write_test(&app.join("integration_test/performance/ignored_test.dart"))?;
        let cases = discover_desktop_cases(&app)?;
        assert_eq!(case_ids(&cases), ["conversation_read_work", "wait_events"]);
        Ok(())
    }

    #[test]
    fn desktop_discovery_prefers_functional_when_present() -> anyhow::Result<()> {
        let root = tempfile::tempdir()?;
        let app = root.path().join("app");
        write_test(&app.join("integration_test/wait_events_test.dart"))?;
        write_test(&app.join("integration_test/functional/wait_events_test.dart"))?;
        write_test(&app.join("integration_test/functional/session_open_test.dart"))?;
        let cases = discover_desktop_cases(&app)?;
        assert_eq!(case_ids(&cases), ["session_open", "wait_events"]);
        match &cases[0].target {
            CaseTarget::Desktop { relative_path } => {
                assert_eq!(
                    relative_path,
                    "integration_test/functional/session_open_test.dart"
                );
            }
            CaseTarget::Native { .. } => panic!("desktop discovery returned a native case"),
        }
        Ok(())
    }

    #[test]
    fn smoke_is_the_named_subset_of_full() -> anyhow::Result<()> {
        let discovered = vec![
            desktop_case("conversation_read_work"),
            desktop_case("wait_events"),
        ];
        let full = select_cases(&discovered, ProjectSuite::Desktop, ProjectSet::Full, None)?;
        let smoke = select_cases(&discovered, ProjectSuite::Desktop, ProjectSet::Smoke, None)?;
        assert_eq!(case_ids(&full), ["conversation_read_work", "wait_events"]);
        assert_eq!(case_ids(&smoke), DESKTOP_SMOKE_IDS);
        Ok(())
    }

    #[test]
    fn unknown_case_fails_without_running_a_fallback() {
        let discovered = native_cases();
        let error = select_cases(
            &discovered,
            ProjectSuite::Native,
            ProjectSet::Full,
            Some("wait_events"),
        )
        .expect_err("unknown native case must fail");
        assert!(
            error
                .to_string()
                .contains("unknown native case `wait_events`")
        );
    }

    #[test]
    fn empty_discovery_fails() {
        let error = select_cases(&[], ProjectSuite::Desktop, ProjectSet::Full, None)
            .expect_err("empty discovery must fail");
        assert!(
            error
                .to_string()
                .contains("desktop full discovery is empty")
        );
    }

    #[test]
    fn desktop_harness_names_the_unique_preset() {
        assert_eq!(desktop_harness_preset("wait_events"), Some("wait-events"));
        assert_eq!(
            desktop_harness_preset("conversation_read_work"),
            Some("conversation-read-work")
        );
        assert_eq!(desktop_harness_preset("session_open"), None);
    }

    #[test]
    fn smoke_rejects_a_full_only_case() {
        let discovered = vec![
            desktop_case("conversation_read_work"),
            desktop_case("wait_events"),
        ];
        let error = select_cases(
            &discovered,
            ProjectSuite::Desktop,
            ProjectSet::Smoke,
            Some("conversation_read_work"),
        )
        .expect_err("a full-only case must fail smoke selection");
        assert!(
            error
                .to_string()
                .contains("desktop smoke does not include `conversation_read_work`")
        );
    }

    fn desktop_case(id: &str) -> DiscoveredCase {
        DiscoveredCase {
            id: id.to_owned(),
            target: CaseTarget::Desktop {
                relative_path: format!("integration_test/{id}_test.dart"),
            },
        }
    }

    fn case_ids(cases: &[DiscoveredCase]) -> Vec<&str> {
        cases.iter().map(|case| case.id.as_str()).collect()
    }

    fn write_test(path: &Path) -> anyhow::Result<()> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(path, "void main() {}\n")?;
        Ok(())
    }
}
