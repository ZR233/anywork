//! Explicit native Host MCP executable source and invocation-owned image lease.
use serde::Deserialize;
use std::{
    fs,
    path::{Path, PathBuf},
    sync::Arc,
};

/// Origin of the standalone `pl-studio-mcp` executable. Bundled never uses PATH.
#[derive(Debug, Clone)]
pub enum HostMcpSource {
    /// Explicit desktop `data/host-mcp` resource directory.
    Bundled(PathBuf),
    /// Unpackaged execution: require `pl-studio-mcp` on PATH.
    External,
}

const ARCHIVE: &str = "pl-studio-mcp.zst";
const METADATA: &str = "pl-studio-mcp.metadata.json";

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Metadata {
    target: String,
    sha256: String,
}

fn load_bundled(root: &Path, target: &str) -> Result<Arc<[u8]>, String> {
    let directory = root.join(target);
    let archive_path = directory.join(ARCHIVE);
    let metadata_path = directory.join(METADATA);
    let archive = fs::read(&archive_path)
        .map_err(|error| format!("read Host MCP {}: {error}", archive_path.display()))?;
    let metadata: Metadata =
        serde_json::from_slice(&fs::read(&metadata_path).map_err(|error| {
            format!(
                "read Host MCP metadata {}: {error}",
                metadata_path.display()
            )
        })?)
        .map_err(|error| {
            format!(
                "parse Host MCP metadata {}: {error}",
                metadata_path.display()
            )
        })?;
    if metadata.target != target {
        return Err(format!(
            "Host MCP metadata {} declares target '{}', expected '{target}'",
            metadata_path.display(),
            metadata.target
        ));
    }
    crate::executable_assets::decompress_verified(&archive_path, &archive, &metadata.sha256)
}

/// Strong executable-image lease. ACP must retain this until its entire process
/// tree joins: the command path alone does not own the image.
#[derive(Clone, Debug)]
pub(crate) struct HostMcpAsset {
    image: Arc<ExecutableImage>,
}

#[derive(Debug)]
struct ExecutableImage {
    // Close the read handle before removing a named image (required on Windows).
    _file: Arc<fs::File>,
    path: PathBuf,
    #[cfg(not(target_os = "linux"))]
    _directory: tempfile::TempDir,
}

impl AsRef<Path> for HostMcpAsset {
    fn as_ref(&self) -> &Path {
        &self.image.path
    }
}

pub(crate) async fn prepare(source: HostMcpSource) -> crate::Result<HostMcpAsset> {
    tokio::task::spawn_blocking(move || materialize_host_mcp(&source))
        .await
        .map_err(|error| {
            crate::PureError::ConfigError(format!("Host MCP preparation failed: {error}"))
        })?
}

fn host_target() -> crate::Result<&'static str> {
    match (std::env::consts::OS, std::env::consts::ARCH) {
        ("linux", "x86_64") => Ok("x86_64-unknown-linux-gnu"),
        ("linux", "aarch64") => Ok("aarch64-unknown-linux-gnu"),
        ("windows", "x86_64") => Ok("x86_64-pc-windows-msvc"),
        ("windows", "aarch64") => Ok("aarch64-pc-windows-msvc"),
        ("macos", "x86_64") => Ok("x86_64-apple-darwin"),
        ("macos", "aarch64") => Ok("aarch64-apple-darwin"),
        (os, arch) => Err(crate::PureError::ConfigError(format!(
            "unsupported Host MCP host {os}/{arch}"
        ))),
    }
}

fn executable_bytes(source: &HostMcpSource) -> crate::Result<Arc<[u8]>> {
    let target = host_target()?;
    let bytes = match source {
        HostMcpSource::Bundled(root) => {
            load_bundled(root, target).map_err(crate::PureError::ConfigError)?
        }
        HostMcpSource::External => {
            let executable = which::which("pl-studio-mcp").map_err(|error| {
                crate::PureError::ConfigError(format!(
                    "find native pl-studio-mcp on PATH for external Host MCP: {error}"
                ))
            })?;
            Arc::from(fs::read(&executable).map_err(|error| {
                crate::PureError::ConfigError(format!(
                    "read external Host MCP {}: {error}",
                    executable.display()
                ))
            })?)
        }
    };
    validate_native_image(&bytes)?;
    Ok(bytes)
}

// Validate the native image format and architecture, without executing a helper
// capability probe or interpreting any additional protocol/configuration.
fn validate_native_image(bytes: &[u8]) -> crate::Result<()> {
    let arch = std::env::consts::ARCH;
    let valid = match std::env::consts::OS {
        "linux" => {
            bytes.get(..6) == Some(b"\x7fELF\x02\x01")
                && bytes.get(18..20)
                    == Some(if arch == "aarch64" {
                        &[183, 0]
                    } else {
                        &[62, 0]
                    })
        }
        "windows" => {
            let pe = bytes.get(60..64).map(|offset| {
                u32::from_le_bytes(offset.try_into().expect("four-byte PE offset")) as usize
            });
            bytes.starts_with(b"MZ")
                && pe.is_some_and(|pe| {
                    bytes.get(pe..pe.saturating_add(4)) == Some(b"PE\0\0")
                        && bytes.get(pe.saturating_add(4)..pe.saturating_add(6))
                            == Some(if arch == "aarch64" {
                                &[0x64, 0xaa]
                            } else {
                                &[0x64, 0x86]
                            })
                })
        }
        "macos" => {
            bytes.starts_with(&[0xcf, 0xfa, 0xed, 0xfe])
                && bytes.get(4..8)
                    == Some(if arch == "aarch64" {
                        &[12, 0, 0, 1]
                    } else {
                        &[7, 0, 0, 1]
                    })
        }
        _ => false,
    };
    if !valid {
        return Err(crate::PureError::ConfigError(format!(
            "Host MCP is not a native {} executable for {arch}",
            std::env::consts::OS
        )));
    }
    Ok(())
}

#[cfg(target_os = "linux")]
fn materialize_host_mcp(source: &HostMcpSource) -> crate::Result<HostMcpAsset> {
    use std::os::fd::AsRawFd;

    let bytes = executable_bytes(source)?;
    let image = crate::executable_assets::anonymous_image(&bytes)?;
    // /proc/self would name agy's fd table after it launches a grandchild.
    // Naming Studio's actual PID keeps the read-only image addressable instead.
    let path = PathBuf::from(format!(
        "/proc/{}/fd/{}",
        std::process::id(),
        image.as_raw_fd()
    ));
    Ok(HostMcpAsset {
        image: Arc::new(ExecutableImage { _file: image, path }),
    })
}

#[cfg(not(target_os = "linux"))]
fn materialize_host_mcp(source: &HostMcpSource) -> crate::Result<HostMcpAsset> {
    use std::io::Write;

    let bytes = executable_bytes(source)?;
    let prepare = || -> std::io::Result<ExecutableImage> {
        // The private OS temporary directory and read-only handle are retained
        // together. No writer is left open when a descendant executes the file.
        let directory = tempfile::Builder::new().prefix("anywork-mcp-").tempdir()?;
        let path = directory
            .path()
            .canonicalize()?
            .join(format!("pl-studio-mcp{}", std::env::consts::EXE_SUFFIX));
        let mut writer = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&path)?;
        writer.write_all(&bytes)?;
        writer.flush()?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            writer.set_permissions(fs::Permissions::from_mode(0o500))?;
        }
        drop(writer);
        // macOS signatures are part of the verified executable bytes, preserved
        // by extraction. Build-time signing precedes the metadata/hash creation.
        #[cfg(windows)]
        let image = {
            use std::os::windows::fs::OpenOptionsExt;
            // Permit descendant execution/read handles while rejecting mutation
            // and deletion until the final lease closes this handle.
            fs::OpenOptions::new()
                .read(true)
                .share_mode(windows_sys::Win32::Storage::FileSystem::FILE_SHARE_READ)
                .open(&path)?
        };
        #[cfg(not(windows))]
        let image = fs::File::open(&path)?;
        Ok(ExecutableImage {
            _file: Arc::new(image),
            path,
            _directory: directory,
        })
    };
    prepare()
        .map(|image| HostMcpAsset {
            image: Arc::new(image),
        })
        .map_err(|error| crate::PureError::ConfigError(format!("materialize Host MCP: {error}")))
}

#[cfg(all(test, target_os = "linux"))]
mod tests {
    use super::*;
    use sha2::{Digest, Sha256};

    fn bundle(root: &Path, executable: &[u8]) -> PathBuf {
        let directory = root.join(host_target().unwrap());
        fs::create_dir_all(&directory).unwrap();
        fs::write(
            directory.join(ARCHIVE),
            zstd::bulk::compress(executable, 1).unwrap(),
        )
        .unwrap();
        fs::write(
            directory.join(METADATA),
            serde_json::to_vec(&serde_json::json!({
                "target": host_target().unwrap(),
                "sha256": hex::encode(Sha256::digest(executable)),
            }))
            .unwrap(),
        )
        .unwrap();
        directory
    }

    #[tokio::test]
    async fn host_mcp_lease_executes_from_same_user_grandchild_and_releases_image() {
        fn assert_traits<T: Clone + Send + Sync + std::fmt::Debug>() {}
        assert_traits::<HostMcpAsset>();
        let root = tempfile::tempdir().unwrap();
        let executable = fs::read(which::which("true").unwrap()).unwrap();
        let directory = bundle(root.path(), &executable);
        let asset = prepare(HostMcpSource::Bundled(root.path().into()))
            .await
            .unwrap();
        let retained = asset.clone();
        let path = asset.as_ref().to_owned();
        assert!(path.is_absolute());
        assert!(path.starts_with(format!("/proc/{}/fd", std::process::id())));
        drop(asset);
        fs::remove_dir_all(directory).unwrap();
        // Python is the direct child, and starts the real ELF grandchild with
        // close_fds=True. It cannot accidentally rely on inheriting Studio's fd.
        let output = std::process::Command::new("python3")
            .args(["-c", "import os, subprocess, sys; assert os.geteuid() == os.stat(sys.argv[2]).st_uid; sys.exit(subprocess.run([sys.argv[1]], close_fds=True).returncode)"])
            .arg(&path)
            .arg(format!("/proc/{}", std::process::id()))
            .output()
            .unwrap();
        assert!(output.status.success(), "{output:?}");
        assert_eq!(fs::read(&path).unwrap(), executable);
        drop(retained);
        assert!(!path.exists(), "last lease must close the anonymous image");
    }

    #[tokio::test]
    async fn host_mcp_rejects_missing_corrupt_and_non_native_bundles() {
        let root = tempfile::tempdir().unwrap();
        assert!(
            prepare(HostMcpSource::Bundled(root.path().into()))
                .await
                .is_err()
        );
        let bytes = fs::read(which::which("true").unwrap()).unwrap();
        let directory = bundle(root.path(), &bytes);
        let metadata_path = directory.join(METADATA);
        let mut metadata: serde_json::Value =
            serde_json::from_slice(&fs::read(&metadata_path).unwrap()).unwrap();
        metadata["target"] = serde_json::json!("wrong-target");
        fs::write(&metadata_path, serde_json::to_vec(&metadata).unwrap()).unwrap();
        let error = prepare(HostMcpSource::Bundled(root.path().into()))
            .await
            .unwrap_err()
            .to_string();
        assert!(error.contains("declares target"), "{error}");
        bundle(root.path(), &bytes);
        fs::write(directory.join(ARCHIVE), b"not zstd").unwrap();
        let error = prepare(HostMcpSource::Bundled(root.path().into()))
            .await
            .unwrap_err()
            .to_string();
        assert!(error.contains("decompress"), "{error}");
        fs::write(
            directory.join(ARCHIVE),
            zstd::bulk::compress(b"replaced", 1).unwrap(),
        )
        .unwrap();
        let error = prepare(HostMcpSource::Bundled(root.path().into()))
            .await
            .unwrap_err()
            .to_string();
        assert!(error.contains("digest"), "{error}");
        bundle(root.path(), b"#!/bin/sh\nexit 0\n");
        let error = prepare(HostMcpSource::Bundled(root.path().into()))
            .await
            .unwrap_err()
            .to_string();
        assert!(error.contains("not a native"), "{error}");
    }
}
