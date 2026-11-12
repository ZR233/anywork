//! Studio runtime 的 remote helper 来源：桌面随包压缩资源或外部安装。

use std::{
    fs,
    path::{Path, PathBuf},
    sync::{Arc, OnceLock},
};

use pl_tool::remote::{RemoteHelperAssets, RemoteHelperTarget, SshError, SshManager};
use serde::Deserialize;
use sha2::{Digest, Sha256};

/// One decompressed helper must stay far below this bound; it only guards against
/// unbounded decompression of a corrupted or replaced resource.
const MAX_HELPER_BYTES: usize = 64 * 1024 * 1024;
const BUNDLED_HELPER_ARCHIVE: &str = "pl-remote-helper.zst";
const BUNDLED_HELPER_METADATA: &str = "pl-remote-helper.metadata.json";

/// Explicit origin of `pl-remote-helper` bytes for one Studio runtime.
///
/// `Bundled` points at the desktop bundle's `data/remote-helper/` directory and is
/// resolved by the packaged bridge from the application executable location.
/// `External` is the explicit mode of unpackaged servers, development and
/// observation entries; SSH assets must be supplied explicitly by their host.
#[derive(Debug, Clone)]
pub enum RemoteHelperSource {
    Bundled(PathBuf),
    External,
}

/// Metadata shipped beside the compressed helper; binds it to one original executable.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct BundledHelperMetadata {
    target: String,
    worker_protocol_version: u32,
    remote_protocol_version: u32,
    sha256: String,
}

pub(crate) fn ssh_manager(source: &RemoteHelperSource) -> SshManager {
    match source {
        RemoteHelperSource::Bundled(root) => {
            SshManager::with_helper_assets(Arc::new(BundledHelperAssets::new(root.clone())))
        }
        RemoteHelperSource::External => SshManager::new(None, None),
    }
}

#[derive(Debug)]
struct BundledHelperAssets {
    root: PathBuf,
    aarch64: OnceLock<Arc<[u8]>>,
    x86_64: OnceLock<Arc<[u8]>>,
}

impl BundledHelperAssets {
    fn new(root: PathBuf) -> Self {
        Self {
            root,
            aarch64: OnceLock::new(),
            x86_64: OnceLock::new(),
        }
    }
}

impl RemoteHelperAssets for BundledHelperAssets {
    fn load(&self, target: RemoteHelperTarget) -> Result<Arc<[u8]>, SshError> {
        let cache = match target {
            RemoteHelperTarget::Aarch64Musl => &self.aarch64,
            RemoteHelperTarget::X8664Musl => &self.x86_64,
        };
        if let Some(bytes) = cache.get() {
            return Ok(bytes.clone());
        }
        let loaded = load_bundled_helper(&self.root, target).map_err(SshError::Protocol)?;
        if cache.set(loaded.clone()).is_ok() {
            return Ok(loaded);
        }
        cache.get().cloned().ok_or_else(|| {
            SshError::Protocol("bundled helper cache initialization failed".to_string())
        })
    }
}

/// Reads, verifies and decompresses one bundled helper resource.
///
/// Errors report the offending resource path and the failed check so callers can
/// surface an actionable repair message; there is no fallback to `PATH` or the
/// network in bundled mode.
fn load_bundled_helper(root: &Path, target: RemoteHelperTarget) -> Result<Arc<[u8]>, String> {
    let directory = root.join(target.triple());
    let archive_path = directory.join(BUNDLED_HELPER_ARCHIVE);
    let metadata_path = directory.join(BUNDLED_HELPER_METADATA);
    let archive = fs::read(&archive_path)
        .map_err(|error| format!("read bundled helper {}: {error}", archive_path.display()))?;
    let metadata_bytes = fs::read(&metadata_path).map_err(|error| {
        format!(
            "read bundled helper metadata {}: {error}",
            metadata_path.display()
        )
    })?;
    let metadata: BundledHelperMetadata =
        serde_json::from_slice(&metadata_bytes).map_err(|error| {
            format!(
                "parse bundled helper metadata {}: {error}",
                metadata_path.display()
            )
        })?;
    if metadata.target != target.triple() {
        return Err(format!(
            "bundled helper metadata {} declares target '{}', expected '{}'",
            metadata_path.display(),
            metadata.target,
            target.triple()
        ));
    }
    if metadata.worker_protocol_version
        != pl_remote_helper::process_worker_protocol::PROCESS_WORKER_PROTOCOL_VERSION
    {
        return Err(format!(
            "bundled helper metadata {} declares worker protocol {}, expected {}; rebuild the \
             application bundle",
            metadata_path.display(),
            metadata.worker_protocol_version,
            pl_remote_helper::process_worker_protocol::PROCESS_WORKER_PROTOCOL_VERSION
        ));
    }
    if metadata.remote_protocol_version != pl_remote_helper::EXECUTOR_WIRE_VERSION {
        return Err(format!(
            "bundled helper metadata {} declares remote protocol {}, expected {}; rebuild the \
             application bundle",
            metadata_path.display(),
            metadata.remote_protocol_version,
            pl_remote_helper::EXECUTOR_WIRE_VERSION
        ));
    }
    let executable = zstd::bulk::decompress(&archive, MAX_HELPER_BYTES).map_err(|error| {
        format!(
            "decompress bundled helper {}: {error}",
            archive_path.display()
        )
    })?;
    let digest = hex::encode(Sha256::digest(&executable));
    if !digest.eq_ignore_ascii_case(&metadata.sha256) {
        return Err(format!(
            "bundled helper {} content digest {digest} does not match metadata {}",
            archive_path.display(),
            metadata.sha256
        ));
    }
    Ok(Arc::from(executable.into_boxed_slice()))
}
