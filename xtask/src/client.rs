use std::collections::BTreeMap;
use std::ffi::OsString;
use std::fs;
use std::path::Path;

use anyhow::{Context, Result, ensure};
use pl_dev_support::{paths, process};
use serde::Deserialize;

/// Both suites are mandatory: a missing package or adapter suite is an
/// incomplete migration, rather than a reason to turn this gate green.
pub(crate) fn verify() -> Result<()> {
    let workspace_root = paths::workspace_root()?;
    let client_dir = workspace_root.join("code/anywork_client");
    let app_dir = paths::studio_app_dir(&workspace_root);
    ensure_client_manifest(&client_dir)?;
    ensure_locked_suite(&client_dir, Path::new("test"))?;
    ensure_locked_suite(&app_dir, Path::new("test/client"))?;

    println!("Client package: {}", client_dir.display());
    println!("Client adapters: {}", app_dir.join("test/client").display());

    run("dart", &["pub", "get", "--enforce-lockfile"], &client_dir)?;
    run("flutter", &["pub", "get", "--enforce-lockfile"], &app_dir)?;
    run(
        "dart",
        &[
            "--packages=.dart_tool/package_config.json",
            "../../xtask/dart/client_boundary_check.dart",
            "../..",
        ],
        &app_dir,
    )?;
    run(
        "dart",
        &[
            "format",
            "--output=none",
            "--set-exit-if-changed",
            "lib",
            "test",
        ],
        &client_dir,
    )?;
    run("dart", &["analyze", "--fatal-infos"], &client_dir)?;
    run("dart", &["test", "--reporter=expanded"], &client_dir)?;
    // flutter_test loads dart:ui, so these adapter tests must use the Flutter
    // runner. The SDK and working directory are the same as cargo flutter.
    run(
        "flutter",
        &["test", "--no-pub", "--reporter=expanded", "test/client"],
        &app_dir,
    )
}

#[derive(Deserialize)]
struct ClientManifest {
    name: String,
    #[serde(default)]
    dependencies: BTreeMap<String, serde_norway::Value>,
}

fn ensure_client_manifest(client_dir: &Path) -> Result<()> {
    let manifest_path = client_dir.join("pubspec.yaml");
    let source = fs::read_to_string(&manifest_path)
        .with_context(|| format!("read required Client manifest {}", manifest_path.display()))?;
    let manifest: ClientManifest = serde_norway::from_str(&source)
        .with_context(|| format!("parse Client manifest {}", manifest_path.display()))?;
    ensure!(
        manifest.name == "anywork_client",
        "Client package must be named anywork_client: {}",
        manifest_path.display()
    );
    ensure!(
        manifest.dependencies.is_empty(),
        "anywork_client runtime dependencies must be Dart SDK only; remove: {}",
        manifest
            .dependencies
            .keys()
            .cloned()
            .collect::<Vec<_>>()
            .join(", ")
    );
    Ok(())
}

fn ensure_locked_suite(package_dir: &Path, suite: &Path) -> Result<()> {
    let lockfile = package_dir.join("pubspec.lock");
    ensure!(
        lockfile.is_file(),
        "required lockfile is missing: {}; resolve and review dependencies before verify-client",
        lockfile.display()
    );
    let suite_dir = package_dir.join(suite);
    ensure!(
        suite_dir.is_dir(),
        "required Client contract test suite is missing: {}",
        suite_dir.display()
    );
    ensure!(
        contains_test(&suite_dir)?,
        "required Client contract test suite has no *_test.dart files: {}",
        suite_dir.display()
    );
    Ok(())
}

fn contains_test(directory: &Path) -> Result<bool> {
    for entry in fs::read_dir(directory)
        .with_context(|| format!("read Client test directory {}", directory.display()))?
    {
        let entry = entry?;
        let file_type = entry.file_type()?;
        if file_type.is_dir() && contains_test(&entry.path())? {
            return Ok(true);
        }
        if file_type.is_file() && entry.file_name().to_string_lossy().ends_with("_test.dart") {
            return Ok(true);
        }
    }
    Ok(false)
}

fn run(program: &'static str, args: &[&str], directory: &Path) -> Result<()> {
    let args = args.iter().map(OsString::from).collect::<Vec<_>>();
    let mut command = process::path_command(program, &args);
    command.current_dir(directory);
    let display = process::display_command(program, &args);
    process::run_checked(&mut command, &display)
        .with_context(|| format!("Client verification failed in {}", directory.display()))
}
