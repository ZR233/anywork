//! Read-only, same-run CI inputs restored by the existing quality handoff.
//! This is independent of the invocation-owned desktop preparation lease.

use std::collections::BTreeMap;
use std::fs::{self, File};
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{Context, Result, ensure};
use serde::Deserialize;
use sha2::{Digest, Sha256};

const INPUTS_ENV: &str = "ANYWORK_CI_TEST_INPUTS";

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Identity {
    source: String,
    workspace: PathBuf,
    environment: String,
    run: String,
    rustc: String,
    cargo: String,
    configuration: BTreeMap<String, String>,
    artifacts: BTreeMap<String, Artifact>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Artifact {
    profile: String,
    sha256: String,
}

/// An explicitly selected handoff must be valid; it never falls back to Cargo.
pub fn artifact(workspace: &Path, name: &str) -> Result<Option<PathBuf>> {
    let Some(directory) = std::env::var_os(INPUTS_ENV) else {
        return Ok(None);
    };
    let directory = PathBuf::from(directory);
    ensure!(
        directory.is_absolute(),
        "CI test input directory must be absolute"
    );
    let identity: Identity = serde_json::from_slice(&fs::read(directory.join("identity.json"))?)
        .context("read same-run CI test input identity")?;
    identity.validate(workspace, &directory)?;
    ensure!(
        identity.artifacts.contains_key(name),
        "unknown CI test input: {name}"
    );
    println!("startup_stage=reuse_ci_test_input artifact={name}");
    Ok(Some(directory.join(name)))
}

impl Identity {
    fn validate(&self, workspace: &Path, directory: &Path) -> Result<()> {
        ensure!(
            cfg!(all(target_os = "linux", target_arch = "x86_64")),
            "CI test inputs require Linux x86_64"
        );
        ensure!(
            self.workspace == workspace.canonicalize()?,
            "CI test input workspace mismatch"
        );
        ensure!(
            self.source == output(workspace, "git", &["rev-parse", "HEAD"])?,
            "CI test input source mismatch"
        );
        ensure!(
            output(
                workspace,
                "git",
                &["status", "--porcelain", "--untracked-files=normal"]
            )?
            .is_empty(),
            "CI test input source has local changes"
        );
        ensure!(
            !self.run.is_empty() && self.run == std::env::var("GITHUB_RUN_ID")?,
            "CI test input run mismatch"
        );
        ensure!(
            self.environment == std::env::var("LINUX_BUILD_IMAGE")?,
            "CI test input image mismatch"
        );
        ensure!(
            self.rustc == output(workspace, "rustc", &["-vV"])?,
            "CI test input Rust toolchain mismatch"
        );
        ensure!(
            self.cargo == output(workspace, "cargo", &["-V"])?,
            "CI test input Cargo toolchain mismatch"
        );
        ensure!(
            self.configuration == configuration(),
            "CI test input build configuration mismatch"
        );
        ensure!(
            self.artifacts.keys().map(String::as_str).eq([
                "libpl_studio_bridge.so",
                "pl-provider-fixture",
                "pl-studio-acceptance"
            ]),
            "CI test input artifact set mismatch"
        );
        for (name, expected) in &self.artifacts {
            let profile = if name == "pl-provider-fixture" {
                "release"
            } else {
                "dev"
            };
            ensure!(
                expected.profile == profile,
                "CI test input profile mismatch: {name}"
            );
            let path = directory.join(name);
            ensure!(
                path.symlink_metadata()?.is_file(),
                "CI test input is not a regular file: {name}"
            );
            ensure!(
                digest(&path)? == expected.sha256,
                "CI test input digest mismatch: {name}"
            );
        }
        Ok(())
    }
}

fn output(workspace: &Path, program: &str, arguments: &[&str]) -> Result<String> {
    let result = Command::new(program)
        .args(arguments)
        .current_dir(workspace)
        .output()?;
    ensure!(
        result.status.success(),
        "CI test input identity command {program} failed: {}",
        String::from_utf8_lossy(&result.stderr)
    );
    Ok(String::from_utf8(result.stdout)?.trim().to_owned())
}

fn configuration() -> BTreeMap<String, String> {
    std::env::vars()
        .filter(|(name, _)| {
            name.starts_with("CARGO_PROFILE_")
                || matches!(
                    name.as_str(),
                    "CARGO_HOME"
                        | "CARGO_TARGET_DIR"
                        | "CARGO_BUILD_TARGET"
                        | "CARGO_INCREMENTAL"
                        | "RUSTFLAGS"
                        | "CARGO_ENCODED_RUSTFLAGS"
                        | "RUSTUP_TOOLCHAIN"
                        | "CC"
                        | "CXX"
                        | "CFLAGS"
                        | "CXXFLAGS"
                        | "LDFLAGS"
                )
        })
        .collect()
}

fn digest(path: &Path) -> Result<String> {
    let mut file = File::open(path)?;
    let mut hash = Sha256::new();
    let mut buffer = [0; 64 * 1024];
    loop {
        let count = file.read(&mut buffer)?;
        if count == 0 {
            return Ok(hex::encode(hash.finalize()));
        }
        hash.update(&buffer[..count]);
    }
}

#[cfg(all(test, target_os = "linux", target_arch = "x86_64"))]
mod tests {
    use super::*;
    use serde_json::Value;

    #[test]
    fn python_handoff_is_consumed_and_rejects_changed_inputs() -> Result<()> {
        const CHILD: &str = "QUALITY_INPUT_TEST_WORKSPACE";
        if let Some(workspace) = std::env::var_os(CHILD) {
            let result = artifact(Path::new(&workspace), "pl-studio-acceptance");
            if let Ok(expected) = std::env::var("QUALITY_INPUT_TEST_ERROR") {
                let error = format!("{:#}", result.unwrap_err());
                assert!(error.contains(&expected), "{error}");
            } else {
                assert!(result?.unwrap().is_file());
                assert!(
                    artifact(Path::new(&workspace), "pl-provider-fixture")?
                        .unwrap()
                        .is_file()
                );
            }
            return Ok(());
        }
        let fixture = tempfile::tempdir()?;
        let workspace = fixture.path().canonicalize()?;
        for args in [
            vec!["init", "-q"],
            vec![
                "-c",
                "user.name=Test",
                "-c",
                "user.email=test@example.invalid",
                "commit",
                "--allow-empty",
                "-qm",
                "seed",
            ],
        ] {
            assert!(
                Command::new("git")
                    .args(args)
                    .current_dir(&workspace)
                    .status()?
                    .success()
            );
        }
        fs::write(
            workspace.join(".git/info/exclude"),
            "/target/\n/restored/\n/inputs.tar.gz\n",
        )?;
        fs::create_dir_all(workspace.join("target/debug"))?;
        fs::create_dir_all(workspace.join("target/release"))?;
        fs::write(
            workspace.join("target/release/pl-provider-fixture"),
            "fixture",
        )?;
        for name in ["pl-studio-acceptance", "libpl_studio_bridge.so"] {
            fs::write(workspace.join("target/debug").join(name), name)?;
        }
        let scripts = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../.github/scripts");
        let image = format!("sha256:{}", "a".repeat(64));
        let producer = Command::new("python3")
            .args(["-c", "import sys; from pathlib import Path; sys.path.insert(0, sys.argv[1]); import pr_quality_handoff as h; w=Path.cwd(); sha=h.subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(); h._pack(w,w/'inputs.tar.gz',sha,False,sys.argv[2],True); h._restore(w,w/'inputs.tar.gz',h._file_sha256(w/'inputs.tar.gz'),sha,w/'restored',False,str(w),sys.argv[2],sys.argv[2],True)"])
            .arg(scripts).arg(&image)
            .current_dir(&workspace).env("GITHUB_RUN_ID", "12345").env("PYTHONDONTWRITEBYTECODE", "1").output()?;
        ensure!(
            producer.status.success(),
            "{}",
            String::from_utf8_lossy(&producer.stderr)
        );
        let directory = workspace.join("restored");
        let manifest = directory.join("identity.json");
        let original = fs::read(&manifest)?;
        let consume = |expected: Option<&str>| -> Result<()> {
            let mut command = Command::new(std::env::current_exe()?);
            command
                .args([
                    "--exact",
                    "quality_inputs::tests::python_handoff_is_consumed_and_rejects_changed_inputs",
                    "--nocapture",
                ])
                .env(CHILD, &workspace)
                .env(INPUTS_ENV, &directory)
                .env("GITHUB_RUN_ID", "12345")
                .env("LINUX_BUILD_IMAGE", &image);
            if let Some(expected) = expected {
                command.env("QUALITY_INPUT_TEST_ERROR", expected);
            }
            let result = command.output()?;
            ensure!(
                result.status.success(),
                "{}{}",
                String::from_utf8_lossy(&result.stdout),
                String::from_utf8_lossy(&result.stderr)
            );
            Ok(())
        };
        consume(None)?;
        for (field, replacement, expected) in [
            ("run", Value::from("other-run"), "run mismatch"),
            ("source", Value::from("other-source"), "source mismatch"),
            (
                "workspace",
                Value::from("/other-workspace"),
                "workspace mismatch",
            ),
            ("environment", Value::from("other-image"), "image mismatch"),
            (
                "rustc",
                Value::from("other-rustc"),
                "Rust toolchain mismatch",
            ),
            (
                "cargo",
                Value::from("other-cargo"),
                "Cargo toolchain mismatch",
            ),
            (
                "configuration",
                serde_json::json!({"RUSTFLAGS": "changed"}),
                "build configuration mismatch",
            ),
        ] {
            let mut identity: Value = serde_json::from_slice(&original)?;
            identity[field] = replacement;
            fs::write(&manifest, serde_json::to_vec(&identity)?)?;
            consume(Some(expected))?;
        }
        let mut identity: Value = serde_json::from_slice(&original)?;
        identity["artifacts"]["pl-provider-fixture"]["profile"] = Value::from("dev");
        fs::write(&manifest, serde_json::to_vec(&identity)?)?;
        consume(Some("profile mismatch"))?;
        fs::write(&manifest, &original)?;
        fs::write(workspace.join("unexpected.rs"), "untracked source")?;
        consume(Some("source has local changes"))?;
        fs::remove_file(workspace.join("unexpected.rs"))?;
        let fixture = directory.join("pl-provider-fixture");
        fs::write(&fixture, "tampered fixture")?;
        consume(Some("digest mismatch: pl-provider-fixture"))?;
        fs::remove_file(&fixture)?;
        consume(Some("No such file"))?;
        fs::write(&fixture, "fixture")?;
        let library = directory.join("libpl_studio_bridge.so");
        fs::write(&library, "tampered")?;
        consume(Some("digest mismatch"))?;
        fs::remove_file(&library)?;
        consume(Some("No such file"))?;
        Ok(())
    }
}
