//! The production CLI is a native desktop resource; Harbor remains a local optional consumer.

use anyhow::{Context, Result, bail, ensure};
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

pub(crate) fn build_and_stage(workspace: &Path, destination: &Path, version: &str) -> Result<()> {
    let target = host_target(std::env::consts::OS, std::env::consts::ARCH)?;
    let commit = std::env::var("PL_GIT_COMMIT")
        .ok()
        .or_else(|| {
            Command::new("git")
                .args(["rev-parse", "HEAD"])
                .current_dir(workspace)
                .output()
                .ok()
                .filter(|output| output.status.success())
                .and_then(|output| String::from_utf8(output.stdout).ok())
        })
        .map(|value| value.trim().to_owned())
        .filter(|value| {
            value.len() == 40
                && value
                    .bytes()
                    .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
        });
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
    pl_dev_support::process::run_checked(&mut command, "build bundled anywk")?;
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
    pl_dev_support::process::run_checked(
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
        build_environment: std::env::var("LINUX_BUILD_IMAGE")
            .unwrap_or_else(|_| format!("native-{target}")),
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
    let info: BuildInfo = serde_json::from_slice(&fs::read(directory.join("build-info.json"))?)?;
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
}
