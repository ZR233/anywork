//! Stateless executable resource helpers shared by worker and Host MCP assets.
use sha2::{Digest, Sha256};
#[cfg(target_os = "linux")]
use std::fs;
use std::{path::Path, sync::Arc};

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
