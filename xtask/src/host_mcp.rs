//! Native standalone Host MCP executable preparation (not an SSH helper).
use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, bail, ensure};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::remote_helper::{native_binary, stage_executable_resource, verify_target_image};

pub(crate) const BUNDLE_DIR_ENV: &str = "ANYWORK_HOST_MCP_DIR";
const BINARY: &str = "pl-studio-mcp";
const ARCHIVE: &str = "pl-studio-mcp.zst";
const METADATA: &str = "pl-studio-mcp.metadata.json";

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Metadata {
    target: String,
    sha256: String,
}

fn host_target(os: &str, arch: &str) -> Result<&'static str> {
    match (os, arch) {
        ("linux", "x86_64") => Ok("x86_64-unknown-linux-gnu"),
        ("linux", "aarch64") => Ok("aarch64-unknown-linux-gnu"),
        ("windows", "x86_64") => Ok("x86_64-pc-windows-msvc"),
        ("windows", "aarch64") => Ok("aarch64-pc-windows-msvc"),
        ("macos", "x86_64") => Ok("x86_64-apple-darwin"),
        ("macos", "aarch64") => Ok("aarch64-apple-darwin"),
        _ => bail!("unsupported Host MCP host {os}/{arch}"),
    }
}

pub(crate) fn current_target() -> Result<&'static str> {
    host_target(std::env::consts::OS, std::env::consts::ARCH)
}

pub(crate) fn prepare_bundle_resources(workspace: &Path) -> Result<PathBuf> {
    let target = current_target()?;
    let executable = native_binary(workspace, BINARY, target)?;
    // Signing changes executable bytes: do it before metadata and compression.
    #[cfg(target_os = "macos")]
    pl_dev_support::process::run_checked(
        std::process::Command::new("/usr/bin/codesign")
            .args(["--force", "--sign", "-"])
            .arg(&executable),
        "codesign native Host MCP",
    )?;
    let bytes = fs::read(&executable)?;
    verify_target_image(&bytes, target)
        .with_context(|| format!("invalid Host MCP executable {}", executable.display()))?;
    let metadata = serde_json::to_vec_pretty(&Metadata {
        target: target.into(),
        sha256: hex::encode(Sha256::digest(&bytes)),
    })?;
    let root = workspace.join("dist/host-mcp-bundle");
    stage_executable_resource(&executable, &root.join(target), BINARY, &metadata)?;
    validate_bundle_resources(&root, target)?;
    Ok(root)
}

/// Validate release inputs without executing or rebuilding the supplied binary.
pub(crate) fn validate_bundle_resources(root: &Path, target: &str) -> Result<()> {
    let directory = root.join(target);
    let metadata_path = directory.join(METADATA);
    let metadata: Metadata = serde_json::from_slice(
        &fs::read(&metadata_path)
            .with_context(|| format!("read Host MCP metadata {}", metadata_path.display()))?,
    )?;
    ensure!(
        metadata.target == target,
        "Host MCP metadata {} declares target {}, expected {target}",
        metadata_path.display(),
        metadata.target
    );
    let archive = directory.join(ARCHIVE);
    let bytes = zstd::bulk::decompress(
        &fs::read(&archive).with_context(|| format!("read Host MCP {}", archive.display()))?,
        64 * 1024 * 1024,
    )?;
    ensure!(
        hex::encode(Sha256::digest(&bytes)).eq_ignore_ascii_case(&metadata.sha256),
        "Host MCP content digest mismatch: {}",
        archive.display()
    );
    verify_target_image(&bytes, target).context("Host MCP image format/architecture mismatch")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn native_target_is_independent_of_ssh_musl() {
        for (os, arch, expected) in [
            ("linux", "x86_64", "x86_64-unknown-linux-gnu"),
            ("linux", "aarch64", "aarch64-unknown-linux-gnu"),
            ("windows", "x86_64", "x86_64-pc-windows-msvc"),
            ("windows", "aarch64", "aarch64-pc-windows-msvc"),
            ("macos", "x86_64", "x86_64-apple-darwin"),
            ("macos", "aarch64", "aarch64-apple-darwin"),
        ] {
            assert_eq!(host_target(os, arch).unwrap(), expected);
        }
        assert!(host_target("linux", "riscv64").is_err());
    }

    #[test]
    fn staged_resources_reject_wrong_target_digest_and_image() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let binary = temp.path().join(BINARY);
        let target = "x86_64-unknown-linux-gnu";
        let root = temp.path().join("resources");
        let mut image = vec![0; 64];
        image[..6].copy_from_slice(b"\x7fELF\x02\x01");
        image[18] = 62;
        fs::write(&binary, &image)?;
        let stage = |bytes: &[u8], declared: &str, hash: String| -> Result<()> {
            fs::write(&binary, bytes)?;
            stage_executable_resource(
                &binary,
                &root.join(target),
                BINARY,
                &serde_json::to_vec(&Metadata {
                    target: declared.into(),
                    sha256: hash,
                })?,
            )
        };
        assert!(validate_bundle_resources(&root, target).is_err());
        stage(&image, target, hex::encode(Sha256::digest(&image)))?;
        validate_bundle_resources(&root, target)?;
        stage(
            &image,
            "aarch64-unknown-linux-gnu",
            hex::encode(Sha256::digest(&image)),
        )?;
        assert!(
            validate_bundle_resources(&root, target)
                .unwrap_err()
                .to_string()
                .contains("target")
        );
        stage(&image, target, "0".repeat(64))?;
        assert!(
            validate_bundle_resources(&root, target)
                .unwrap_err()
                .to_string()
                .contains("digest")
        );
        stage(
            b"not a binary",
            target,
            hex::encode(Sha256::digest(b"not a binary")),
        )?;
        assert!(
            validate_bundle_resources(&root, target)
                .unwrap_err()
                .to_string()
                .contains("image")
        );
        Ok(())
    }
}
