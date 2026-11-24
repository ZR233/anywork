//! The production CLI is a native desktop resource; Harbor remains a local optional consumer.

use anyhow::{Context, Result, bail, ensure};
use pl_dev_support::{paths, process};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct BuildInfo {
    version: String,
    git_commit: Option<String>,
    target: String,
    build_environment: String,
    binary_sha256: String,
    result_schema_versions: Vec<u32>,
    event_schema_versions: Vec<u32>,
}

fn binary_name(target: &str) -> &'static str {
    if target.contains("windows") {
        "anywk.exe"
    } else {
        "anywk"
    }
}

fn host_target(os: &str, arch: &str) -> Result<&'static str> {
    match (os, arch) {
        ("linux", "x86_64") => Ok("x86_64-unknown-linux-gnu"),
        ("linux", "aarch64") => Ok("aarch64-unknown-linux-gnu"),
        ("windows", "x86_64") => Ok("x86_64-pc-windows-msvc"),
        ("windows", "aarch64") => Ok("aarch64-pc-windows-msvc"),
        ("macos", "x86_64") => Ok("x86_64-apple-darwin"),
        ("macos", "aarch64") => Ok("aarch64-apple-darwin"),
        _ => bail!("unsupported anywk host {os}/{arch}"),
    }
}

pub(crate) fn build_for_gui(workspace: &Path, bundle: &Path, version: &str) -> Result<()> {
    let commit = std::env::var("PL_GIT_COMMIT")
        .ok()
        .or_else(|| current_commit(workspace).ok())
        .map(|value| value.trim().to_owned())
        .filter(|value| is_commit_sha(value));
    build_and_stage(workspace, &gui_cli_directory(bundle), version, commit)?;
    sign_gui(bundle)
}

pub(crate) fn build_release(destination: &Path) -> Result<()> {
    let workspace = paths::workspace_root()?;
    let version = crate::studio_version::read(&paths::studio_app_dir(&workspace))?;
    let commit = current_commit(&workspace)?;
    ensure!(
        !destination.try_exists()?,
        "anywk output already exists: {}",
        destination.display()
    );
    build_and_stage(&workspace, destination, &version.to_string(), Some(commit))
}

pub(crate) fn assemble_gui(bundle: &Path, source: &Path, source_sha: &str) -> Result<()> {
    let workspace = paths::workspace_root()?;
    ensure!(
        is_commit_sha(source_sha) && current_commit(&workspace)? == source_sha,
        "assembly checkout does not match the requested source commit {source_sha}"
    );
    let version = crate::studio_version::read(&paths::studio_app_dir(&workspace))?;
    let executable = if cfg!(target_os = "macos") {
        "anywork.app/Contents/MacOS/anywork"
    } else if cfg!(windows) {
        "anywork.exe"
    } else {
        "anywork"
    };
    ensure!(
        bundle.join(executable).is_file(),
        "missing GUI executable in {}",
        bundle.display()
    );
    let target = host_target(std::env::consts::OS, std::env::consts::ARCH)?;
    install_prebuilt(
        source,
        &gui_cli_directory(bundle),
        target,
        &version.to_string(),
        source_sha,
        &build_environment(target),
    )?;
    sign_gui(bundle)
}

fn gui_cli_directory(bundle: &Path) -> PathBuf {
    if cfg!(target_os = "macos") {
        bundle.join("anywork.app/Contents/Resources/bin")
    } else {
        bundle.join("bin")
    }
}

fn sign_gui(_bundle: &Path) -> Result<()> {
    #[cfg(target_os = "macos")]
    process::run_checked(
        Command::new("/usr/bin/codesign")
            .args([
                "--force",
                "--sign",
                "-",
                "--preserve-metadata=entitlements,flags,runtime",
            ])
            .arg(_bundle.join("anywork.app")),
        "codesign app with bundled anywk",
    )?;
    Ok(())
}

fn current_commit(workspace: &Path) -> Result<String> {
    let output = Command::new("git")
        .args(["rev-parse", "--verify", "HEAD"])
        .current_dir(workspace)
        .output()
        .context("read checkout source commit")?;
    ensure!(
        output.status.success(),
        "git rev-parse --verify HEAD failed: {}",
        String::from_utf8_lossy(&output.stderr).trim()
    );
    let commit = String::from_utf8(output.stdout)?.trim().to_owned();
    ensure!(
        is_commit_sha(&commit),
        "invalid checkout source commit: {commit}"
    );
    Ok(commit)
}

fn is_commit_sha(value: &str) -> bool {
    value.len() == 40
        && value
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

fn build_environment(target: &str) -> String {
    std::env::var("LINUX_BUILD_IMAGE").unwrap_or_else(|_| format!("native-{target}"))
}

fn build_and_stage(
    workspace: &Path,
    destination: &Path,
    version: &str,
    commit: Option<String>,
) -> Result<()> {
    let target = host_target(std::env::consts::OS, std::env::consts::ARCH)?;
    let mut command = Command::new("cargo");
    command.current_dir(workspace).args([
        "build",
        "--release",
        "--locked",
        "-p",
        "pl-studio-cli",
        "--bin",
        "anywk",
    ]);
    process::run_checked(&mut command, "build bundled anywk")?;
    let target_dir = std::env::var_os("CARGO_TARGET_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("target"));
    let binary = workspace
        .join(target_dir)
        .join("release")
        .join(binary_name(target));
    let output = Command::new(&binary).arg("--version").output()?;
    ensure!(
        output.status.success()
            && String::from_utf8_lossy(&output.stdout).trim() == format!("anywk {version}"),
        "bundled anywk version differs from desktop version"
    );
    #[cfg(target_os = "macos")]
    process::run_checked(
        Command::new("/usr/bin/codesign")
            .args(["--force", "--sign", "-"])
            .arg(&binary),
        "codesign bundled anywk",
    )?;
    stage(&binary, destination, version, target, commit)?;
    validate(destination, target, version)
}

fn stage(
    binary: &Path,
    destination: &Path,
    version: &str,
    target: &str,
    git_commit: Option<String>,
) -> Result<()> {
    let bytes = fs::read(binary).with_context(|| format!("read anywk {}", binary.display()))?;
    crate::remote_helper::verify_target_image(&bytes, target)?;
    fs::create_dir_all(destination)?;
    let executable = destination.join(binary_name(target));
    fs::copy(binary, &executable)?;
    let bytes = fs::read(&executable)?;
    let info = BuildInfo {
        version: version.to_owned(),
        git_commit,
        target: target.to_owned(),
        build_environment: build_environment(target),
        binary_sha256: hex::encode(Sha256::digest(&bytes)),
        result_schema_versions: vec![2],
        event_schema_versions: vec![2],
    };
    fs::write(
        destination.join("build-info.json"),
        serde_json::to_vec_pretty(&info)?,
    )?;
    Ok(())
}

pub(crate) fn validate(directory: &Path, target: &str, version: &str) -> Result<()> {
    validated_build_info(directory, target, version).map(|_| ())
}

fn validated_build_info(directory: &Path, target: &str, version: &str) -> Result<BuildInfo> {
    let path = directory.join("build-info.json");
    ensure!(
        fs::symlink_metadata(&path)?.is_file(),
        "anywk build-info.json must be a regular file"
    );
    let info: BuildInfo = serde_json::from_slice(&fs::read(path)?)?;
    ensure!(
        info.target == target && info.version == version,
        "bundled anywk build identity mismatch"
    );
    ensure!(
        info.result_schema_versions == [2] && info.event_schema_versions == [2],
        "bundled anywk export schema mismatch"
    );
    let binary = directory.join(binary_name(target));
    ensure!(
        fs::symlink_metadata(&binary)?.is_file(),
        "bundled anywk must be a regular file"
    );
    let bytes = fs::read(&binary)?;
    ensure!(
        hex::encode(Sha256::digest(&bytes)) == info.binary_sha256,
        "bundled anywk digest mismatch"
    );
    crate::remote_helper::verify_target_image(&bytes, target)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        ensure!(
            fs::metadata(binary)?.permissions().mode() & 0o111 != 0,
            "bundled anywk is not executable"
        );
    }
    Ok(info)
}

fn install_prebuilt(
    source: &Path,
    destination: &Path,
    target: &str,
    version: &str,
    commit: &str,
    environment: &str,
) -> Result<()> {
    let info = validated_build_info(source, target, version)
        .with_context(|| format!("validate prebuilt anywk in {}", source.display()))?;
    ensure!(
        info.git_commit.as_deref() == Some(commit),
        "prebuilt anywk source commit mismatch: expected {commit}, got {:?}",
        info.git_commit
    );
    ensure!(
        info.build_environment == environment,
        "prebuilt anywk environment mismatch: expected {environment}, got {}",
        info.build_environment
    );
    ensure!(
        !destination.try_exists()?,
        "GUI already contains CLI resources at {}",
        destination.display()
    );
    let parent = destination
        .parent()
        .context("anywk bundle directory has no parent")?;
    let staging = tempfile::tempdir_in(parent)?;
    let resources = staging.path().join("bin");
    fs::create_dir(&resources)?;
    for file in [binary_name(target), "build-info.json"] {
        fs::copy(source.join(file), resources.join(file))?;
    }
    fs::rename(resources, destination)
        .with_context(|| format!("install anywk resources at {}", destination.display()))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cli_targets_match_native_desktop_targets() -> Result<()> {
        for (os, arch, target) in [
            ("linux", "x86_64", "x86_64-unknown-linux-gnu"),
            ("linux", "aarch64", "aarch64-unknown-linux-gnu"),
            ("windows", "x86_64", "x86_64-pc-windows-msvc"),
            ("windows", "aarch64", "aarch64-pc-windows-msvc"),
            ("macos", "x86_64", "x86_64-apple-darwin"),
            ("macos", "aarch64", "aarch64-apple-darwin"),
        ] {
            assert_eq!(host_target(os, arch)?, target);
        }
        assert!(host_target("linux", "riscv64").is_err());
        Ok(())
    }

    #[test]
    fn resource_checks_reject_changed_bytes_target_version_and_missing_cli() -> Result<()> {
        let root = tempfile::tempdir()?;
        let binary = root.path().join("binary");
        let destination = root.path().join("bin");
        let target = "x86_64-unknown-linux-gnu";
        let mut bytes = vec![0; 64];
        bytes[..6].copy_from_slice(b"\x7fELF\x02\x01");
        bytes[18] = 62;
        fs::write(&binary, bytes)?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&binary, fs::Permissions::from_mode(0o755))?;
        }
        stage(&binary, &destination, "1.2.3", target, None)?;
        validate(&destination, target, "1.2.3")?;
        assert!(validate(&destination, "aarch64-unknown-linux-gnu", "1.2.3").is_err());
        assert!(validate(&destination, target, "1.2.4").is_err());
        fs::write(destination.join("anywk"), b"corrupt")?;
        assert!(validate(&destination, target, "1.2.3").is_err());
        fs::remove_file(destination.join("anywk"))?;
        assert!(validate(&destination, target, "1.2.3").is_err());
        Ok(())
    }

    #[test]
    fn assembly_installs_only_matching_cli_artifacts() -> Result<()> {
        let root = tempfile::tempdir()?;
        let binary = root.path().join("binary");
        let source = root.path().join("source");
        let destination = root.path().join("bin");
        let target = "x86_64-unknown-linux-gnu";
        let version = "1.2.3";
        let commit = "0123456789abcdef0123456789abcdef01234567";
        let mut bytes = vec![0; 64];
        bytes[..6].copy_from_slice(b"\x7fELF\x02\x01");
        bytes[18] = 62;
        fs::write(&binary, &bytes)?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&binary, fs::Permissions::from_mode(0o755))?;
        }
        stage(&binary, &source, version, target, Some(commit.to_owned()))?;
        let environment = build_environment(target);

        for (version, target, commit, environment, reason) in [
            (
                "1.2.4",
                target,
                commit,
                environment.as_str(),
                "build identity mismatch",
            ),
            (
                version,
                "aarch64-unknown-linux-gnu",
                commit,
                environment.as_str(),
                "build identity mismatch",
            ),
            (
                version,
                target,
                "another commit",
                environment.as_str(),
                "source commit mismatch",
            ),
            (
                version,
                target,
                commit,
                "another image",
                "environment mismatch",
            ),
        ] {
            let error =
                install_prebuilt(&source, &destination, target, version, commit, environment)
                    .expect_err(reason);
            assert!(format!("{error:#}").contains(reason));
            assert!(!destination.exists());
        }

        let executable = source.join("anywk");
        fs::write(&executable, b"changed")?;
        let error = install_prebuilt(&source, &destination, target, version, commit, &environment)
            .expect_err("changed bytes");
        assert!(format!("{error:#}").contains("digest mismatch"));
        fs::remove_file(&executable)?;
        assert!(
            install_prebuilt(&source, &destination, target, version, commit, &environment).is_err()
        );
        assert!(!destination.exists());

        fs::copy(&binary, executable)?;
        install_prebuilt(&source, &destination, target, version, commit, &environment)?;
        validate(&destination, target, version)?;
        assert_eq!(fs::read(destination.join("anywk"))?, bytes);
        assert!(
            install_prebuilt(&source, &destination, target, version, commit, &environment).is_err()
        );
        Ok(())
    }
}
