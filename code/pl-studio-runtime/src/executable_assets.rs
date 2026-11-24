//! Stateless executable resource helpers shared by worker and Host MCP assets.
use serde::de::DeserializeOwned;
use sha2::{Digest, Sha256};
use std::{fs, path::Path, sync::Arc};

pub(crate) trait BundleMetadata: DeserializeOwned {
    const STEM: &'static str;
    const DESCRIPTION: &'static str;

    fn target(&self) -> &str;
    fn sha256(&self) -> &str;

    fn validate(&self, _path: &Path) -> Result<(), String> {
        Ok(())
    }
}

pub(crate) fn load_bundled_archive<M: BundleMetadata>(
    root: &Path,
    target: &str,
) -> Result<Arc<[u8]>, String> {
    let directory = root.join(target);
    let archive_path = directory.join(format!("{}.zst", M::STEM));
    let metadata_path = directory.join(format!("{}.metadata.json", M::STEM));
    let label = M::DESCRIPTION;
    let archive = fs::read(&archive_path)
        .map_err(|error| format!("read {label} {}: {error}", archive_path.display()))?;
    let metadata_bytes = fs::read(&metadata_path)
        .map_err(|error| format!("read {label} metadata {}: {error}", metadata_path.display()))?;
    let metadata: M = serde_json::from_slice(&metadata_bytes).map_err(|error| {
        format!(
            "parse {label} metadata {}: {error}",
            metadata_path.display()
        )
    })?;
    if metadata.target() != target {
        return Err(format!(
            "{label} metadata {} declares target '{}', expected '{target}'",
            metadata_path.display(),
            metadata.target(),
        ));
    }
    metadata.validate(&metadata_path)?;
    decompress_verified(&archive_path, &archive, metadata.sha256())
}

pub(crate) fn decompress_verified(
    archive_path: &Path,
    archive: &[u8],
    expected: &str,
) -> Result<Arc<[u8]>, String> {
    let bytes = zstd::bulk::decompress(archive, 64 * 1024 * 1024)
        .map_err(|error| format!("decompress executable {}: {error}", archive_path.display()))?;
    let digest = hex::encode(Sha256::digest(&bytes));
    if !digest.eq_ignore_ascii_case(expected) {
        return Err(format!(
            "executable {} content digest {digest} does not match metadata {expected}",
            archive_path.display()
        ));
    }
    Ok(Arc::from(bytes.into_boxed_slice()))
}

#[cfg(target_os = "linux")]
pub(crate) fn anonymous_image(bytes: &[u8]) -> crate::Result<Arc<fs::File>> {
    use std::io::Write;
    use std::os::fd::AsRawFd;
    use std::os::unix::fs::PermissionsExt;

    let mut file = tempfile::tempfile().map_err(|error| {
        crate::PureError::ConfigError(format!("create executable image: {error}"))
    })?;
    file.write_all(bytes)
        .and_then(|()| file.flush())
        .map_err(|error| {
            crate::PureError::ConfigError(format!("materialize executable image: {error}"))
        })?;
    file.set_permissions(std::fs::Permissions::from_mode(0o700))
        .map_err(|error| {
            crate::PureError::ConfigError(format!(
                "configure executable image permissions: {error}"
            ))
        })?;
    // Reopen read-only before releasing the writer, otherwise exec can fail ETXTBSY.
    // The anonymous inode has no directory entry to leak if the GUI is killed.
    let image =
        std::fs::File::open(format!("/proc/self/fd/{}", file.as_raw_fd())).map_err(|error| {
            crate::PureError::ConfigError(format!("retain executable image: {error}"))
        })?;
    drop(file);
    Ok(Arc::new(image))
}
