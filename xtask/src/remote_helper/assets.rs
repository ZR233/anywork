//! Flutter bundle 资源 staging 前的 helper 资产准备、校验与压缩。

use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, ensure};
use sha2::{Digest, Sha256};

use super::bundle_staging_dir;
use super::{HELPER_FILE_NAME, SUPPORTED_TARGETS, local_helper_path};

const PREBUILT_DIR_ENV: &str = "PURE_REMOTE_HELPER_PREBUILT_DIR";
#[cfg(test)]
const BUNDLED_ARCHIVE_FILE: &str = "pl-remote-helper.zst";
#[cfg(test)]
const BUNDLED_METADATA_FILE: &str = "pl-remote-helper.metadata.json";
const ZSTD_COMPRESSION_LEVEL: i32 = 12;

pub(super) fn prepare(workspace_root: &Path) -> Result<PathBuf> {
    let targets = SUPPORTED_TARGETS;
    match std::env::var_os(PREBUILT_DIR_ENV).filter(|value| !value.is_empty()) {
        Some(source) => install_prebuilt(workspace_root, &PathBuf::from(source), &targets)?,
        None => super::build::build_targets(workspace_root, &targets)?,
    }
    for target in targets {
        let binary = local_helper_path(workspace_root, target);
        verify_local_asset(&binary, target)?;
        #[cfg(target_os = "linux")]
        if target.starts_with(std::env::consts::ARCH) {
            tokio::runtime::Builder::new_current_thread().enable_all().build()?.block_on(
                pl_remote_helper::client::ManagedWorker::probe(&binary)
            ).with_context(|| format!("helper preflight failed; rebuild with cargo xtask build-remote-helper --target {target}"))?;
        }
        stage_bundled_resource(workspace_root, target)?;
    }
    Ok(bundle_staging_dir(workspace_root))
}

fn install_prebuilt(workspace_root: &Path, source: &Path, targets: &[&str]) -> Result<()> {
    for target in targets {
        let source_binary = source.join(target).join(HELPER_FILE_NAME);
        verify_local_asset(&source_binary, target)?;
        let destination = local_helper_path(workspace_root, target);
        if source_binary == destination {
            continue;
        }
        let destination_dir = destination
            .parent()
            .context("remote helper destination has no parent")?;
        fs::create_dir_all(destination_dir)
            .with_context(|| format!("failed to create {}", destination_dir.display()))?;
        fs::copy(&source_binary, &destination).with_context(|| {
            format!(
                "failed to copy prebuilt helper from {} to {}",
                source_binary.display(),
                destination.display()
            )
        })?;
        fs::copy(
            source_binary.with_extension("metadata.json"),
            destination.with_extension("metadata.json"),
        )?;
        fs::copy(
            source_binary.with_extension("sha256"),
            destination.with_extension("sha256"),
        )?;
    }
    Ok(())
}

/// Compresses one verified helper into the bundle staging tree.
///
/// Files are only rewritten when their bytes change, so unchanged resources keep
/// their timestamps across repeated GUI builds.
fn stage_bundled_resource(workspace_root: &Path, target: &str) -> Result<()> {
    let binary = local_helper_path(workspace_root, target);
    let metadata = fs::read(binary.with_extension("metadata.json"))?;
    stage_executable_resource(
        &binary,
        &bundle_staging_dir(workspace_root).join(target),
        "pl-remote-helper",
        &metadata,
    )
}

/// Compress a verified executable and round-trip its staged bytes before use.
pub(crate) fn stage_executable_resource(
    binary: &Path,
    destination_dir: &Path,
    stem: &str,
    metadata: &[u8],
) -> Result<()> {
    fs::create_dir_all(destination_dir)?;
    let executable =
        fs::read(binary).with_context(|| format!("read executable {}", binary.display()))?;
    let archive_path = destination_dir.join(format!("{stem}.zst"));
    let archive = zstd::bulk::compress(&executable, ZSTD_COMPRESSION_LEVEL)?;
    write_if_changed(&archive_path, &archive)?;
    write_if_changed(
        &destination_dir.join(format!("{stem}.metadata.json")),
        metadata,
    )?;
    let restored = zstd::bulk::decompress(&fs::read(&archive_path)?, executable.len())?;
    ensure!(
        restored == executable,
        "staged executable {} does not round-trip to {}",
        archive_path.display(),
        binary.display()
    );
    println!("executable resource: {}", archive_path.display());
    Ok(())
}

fn write_if_changed(path: &Path, contents: &[u8]) -> Result<()> {
    if fs::read(path).is_ok_and(|existing| existing == contents) {
        return Ok(());
    }
    fs::write(path, contents).with_context(|| format!("failed to write {}", path.display()))
}

fn verify_local_asset(binary: &Path, target: &str) -> Result<()> {
    ensure!(
        binary.is_file(),
        "remote helper artifact is missing: {}",
        binary.display()
    );
    let checksum_path = binary.with_extension("sha256");
    let checksum = fs::read_to_string(&checksum_path)
        .with_context(|| format!("failed to read {}", checksum_path.display()))?;
    let expected = checksum
        .split_whitespace()
        .next()
        .filter(|value| value.len() == 64 && value.bytes().all(|byte| byte.is_ascii_hexdigit()))
        .context("remote helper checksum is invalid")?;
    let executable = fs::read(binary)?;
    let actual = hex::encode(Sha256::digest(&executable));
    ensure!(
        actual.eq_ignore_ascii_case(expected),
        "remote helper SHA-256 mismatch: {}",
        binary.display()
    );
    let metadata: super::HelperMetadata = serde_json::from_slice(
        &fs::read(binary.with_extension("metadata.json")).with_context(|| {
            format!("helper build metadata missing for {target}; rebuild the application bundle or supply matching prebuilt assets")
        })?,
    )?;
    ensure!(
        metadata.target == target
            && metadata.worker_protocol_version
                == pl_remote_helper::process_worker_protocol::PROCESS_WORKER_PROTOCOL_VERSION
            && metadata.remote_protocol_version == pl_remote_helper::EXECUTOR_WIRE_VERSION
            && metadata.sha256 == actual,
        "helper build metadata mismatch for {target}; rebuild the application bundle or supply matching prebuilt assets"
    );
    verify_target_image(&executable, target)
        .with_context(|| format!("invalid helper executable {}", binary.display()))?;
    Ok(())
}

pub(crate) fn verify_target_image(bytes: &[u8], target: &str) -> Result<()> {
    let arm = target.starts_with("aarch64-");
    let valid = if target.ends_with("-linux-musl") || target.ends_with("-linux-gnu") {
        bytes.get(..6) == Some(b"\x7fELF\x02\x01")
            && bytes.get(18..20) == Some(if arm { &[183, 0] } else { &[62, 0] })
    } else if target.ends_with("-windows-msvc") {
        let pe = bytes.get(60..64).map(|offset| {
            u32::from_le_bytes(offset.try_into().expect("four-byte PE offset")) as usize
        });
        bytes.starts_with(b"MZ")
            && pe.is_some_and(|pe| {
                bytes.get(pe..pe.saturating_add(4)) == Some(b"PE\0\0")
                    && bytes.get(pe.saturating_add(4)..pe.saturating_add(6))
                        == Some(if arm { &[0x64, 0xaa] } else { &[0x64, 0x86] })
            })
    } else if target.ends_with("-apple-darwin") {
        bytes.starts_with(&[0xcf, 0xfa, 0xed, 0xfe])
            && bytes.get(4..8) == Some(if arm { &[12, 0, 0, 1] } else { &[7, 0, 0, 1] })
    } else {
        false
    };
    ensure!(
        valid,
        "helper image format/architecture does not match {target}"
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_wrong_native_image_even_with_matching_metadata_and_hash() {
        let root = tempfile::tempdir().unwrap();
        let target = "x86_64-pc-windows-msvc";
        let binary = root.path().join(HELPER_FILE_NAME);
        // Deliberately label Linux ELF bytes as a Windows asset, with correct
        // hashes, to prove metadata alone cannot smuggle a non-native image.
        let mut bytes = vec![0; 64];
        bytes[..6].copy_from_slice(b"\x7fELF\x02\x01");
        bytes[18] = 62;
        write_asset(&binary, target, &bytes);
        let error = verify_local_asset(&binary, target).unwrap_err();
        assert!(format!("{error:#}").contains("image format/architecture"));
        assert!(verify_target_image(&bytes, "x86_64-unknown-linux-musl").is_ok());
        assert!(verify_target_image(&bytes, "aarch64-unknown-linux-musl").is_err());
    }

    #[test]
    fn stages_verified_asset_and_rejects_modified_content() {
        let root = tempfile::tempdir().unwrap();
        let target = "x86_64-unknown-linux-musl";
        let binary = local_helper_path(root.path(), target);
        fs::create_dir_all(binary.parent().unwrap()).unwrap();
        let mut bytes = vec![0; 64];
        bytes[..6].copy_from_slice(b"\x7fELF\x02\x01");
        bytes[18] = 62;
        write_asset(&binary, target, &bytes);
        verify_local_asset(&binary, target).unwrap();
        stage_bundled_resource(root.path(), target).unwrap();
        let staged = bundle_staging_dir(root.path()).join(target);
        let archive = fs::read(staged.join(BUNDLED_ARCHIVE_FILE)).unwrap();
        assert_eq!(
            zstd::bulk::decompress(&archive, bytes.len()).unwrap(),
            bytes
        );
        let metadata: super::super::HelperMetadata =
            serde_json::from_slice(&fs::read(staged.join(BUNDLED_METADATA_FILE)).unwrap()).unwrap();
        assert_eq!(metadata.sha256, hex::encode(Sha256::digest(&bytes)));
        bytes[30] = 1;
        fs::write(&binary, bytes).unwrap();
        let error = verify_local_asset(&binary, target).unwrap_err();
        assert!(error.to_string().contains("SHA-256 mismatch"), "{error}");
    }

    fn write_asset(binary: &Path, target: &str, bytes: &[u8]) {
        let sha256 = hex::encode(Sha256::digest(bytes));
        fs::write(binary, bytes).unwrap();
        fs::write(
            binary.with_extension("sha256"),
            format!("{sha256}  helper\n"),
        )
        .unwrap();
        fs::write(
            binary.with_extension("metadata.json"),
            serde_json::to_vec(&super::super::HelperMetadata {
                target: target.into(),
                worker_protocol_version:
                    pl_remote_helper::process_worker_protocol::PROCESS_WORKER_PROTOCOL_VERSION,
                remote_protocol_version: pl_remote_helper::EXECUTOR_WIRE_VERSION,
                sha256,
            })
            .unwrap(),
        )
        .unwrap();
    }
}
