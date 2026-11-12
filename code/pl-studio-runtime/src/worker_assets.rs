//! Studio runtime 的 remote helper 来源：桌面随包压缩资源或外部安装。

use std::{
    fs,
    path::{Path, PathBuf},
    sync::{Arc, OnceLock},
};

use pl_tool::remote::{RemoteClientError, RemoteHelperAssets, RemoteHelperTarget, SshManager};
use serde::Deserialize;

const BUNDLED_HELPER_ARCHIVE: &str = "pl-remote-helper.zst";
const BUNDLED_HELPER_METADATA: &str = "pl-remote-helper.metadata.json";

/// Explicit origin of `pl-remote-helper` bytes for one Studio runtime.
///
/// `Bundled` points at the desktop bundle's `data/remote-helper/` directory and is
/// resolved by the packaged bridge from the application executable location.
/// `External` is the explicit mode of unpackaged servers, development and
/// observation entries; on Linux the local worker is then looked up on `PATH`.
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
    fn load(&self, target: RemoteHelperTarget) -> Result<Arc<[u8]>, RemoteClientError> {
        let cache = match target {
            RemoteHelperTarget::Aarch64Musl => &self.aarch64,
            RemoteHelperTarget::X8664Musl => &self.x86_64,
        };
        if let Some(bytes) = cache.get() {
            return Ok(bytes.clone());
        }
        let loaded =
            load_bundled_helper(&self.root, target).map_err(RemoteClientError::Protocol)?;
        if cache.set(loaded.clone()).is_ok() {
            return Ok(loaded);
        }
        cache.get().cloned().ok_or_else(|| {
            RemoteClientError::Protocol("bundled helper cache initialization failed".to_string())
        })
    }
}

/// Reads, verifies and decompresses one bundled helper resource.
///
/// Errors report the offending resource path and the failed check so callers can
/// surface an actionable repair message; there is no fallback to `PATH` or the
/// network in bundled mode.
fn load_bundled_helper(root: &Path, target: RemoteHelperTarget) -> Result<Arc<[u8]>, String> {
    load_bundled_target(root, target.triple())
}

fn load_bundled_target(root: &Path, target: &str) -> Result<Arc<[u8]>, String> {
    let directory = root.join(target);
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
    if metadata.target != target {
        return Err(format!(
            "bundled helper metadata {} declares target '{}', expected '{}'",
            metadata_path.display(),
            metadata.target,
            target
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
    if metadata.remote_protocol_version != pl_protocol::remote::REMOTE_PROTOCOL_VERSION {
        return Err(format!(
            "bundled helper metadata {} declares remote protocol {}, expected {}; rebuild the \
             application bundle",
            metadata_path.display(),
            metadata.remote_protocol_version,
            pl_protocol::remote::REMOTE_PROTOCOL_VERSION
        ));
    }
    crate::executable_assets::decompress_verified(&archive_path, &archive, &metadata.sha256)
}

/// Immutable host executable lease retained by session executors, including old generations.
#[cfg(target_os = "linux")]
#[derive(Clone)]
pub(crate) struct LocalWorkerAsset {
    image: std::sync::Arc<std::fs::File>,
    path: std::path::PathBuf,
}

#[cfg(target_os = "linux")]
impl std::fmt::Debug for LocalWorkerAsset {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("LocalWorkerAsset")
            .field("image", &self.image)
            .finish_non_exhaustive()
    }
}

#[cfg(target_os = "linux")]
impl AsRef<std::path::Path> for LocalWorkerAsset {
    fn as_ref(&self) -> &std::path::Path {
        &self.path
    }
}

#[cfg(target_os = "linux")]
pub(crate) async fn local_worker(source: RemoteHelperSource) -> crate::Result<LocalWorkerAsset> {
    tokio::task::spawn_blocking(move || materialize_local_worker(&source))
        .await
        .map_err(|error| {
            crate::PureError::ConfigError(format!("local worker preparation failed: {error}"))
        })?
}

#[cfg(target_os = "linux")]
fn materialize_local_worker(source: &RemoteHelperSource) -> crate::Result<LocalWorkerAsset> {
    match source {
        RemoteHelperSource::Bundled(root) => {
            let target = host_helper_target()?;
            let executable =
                load_bundled_helper(root, target).map_err(crate::PureError::ConfigError)?;
            materialize_anonymous_worker(&executable)
        }
        RemoteHelperSource::External => open_external_worker(),
    }
}

#[cfg(target_os = "linux")]
fn host_helper_target() -> crate::Result<RemoteHelperTarget> {
    match std::env::consts::ARCH {
        "x86_64" => Ok(RemoteHelperTarget::X8664Musl),
        "aarch64" => Ok(RemoteHelperTarget::Aarch64Musl),
        architecture => Err(crate::PureError::ConfigError(format!(
            "unsupported local worker architecture {architecture}"
        ))),
    }
}

/// Writes the verified bytes into an anonymous executable image and reopens it
/// read-only, so later resource replacements cannot mutate a running image.
#[cfg(target_os = "linux")]
fn materialize_anonymous_worker(bytes: &[u8]) -> crate::Result<LocalWorkerAsset> {
    use std::os::fd::AsRawFd;
    let image = crate::executable_assets::anonymous_image(bytes)?;
    let path = PathBuf::from(format!("/proc/self/fd/{}", image.as_raw_fd()));
    Ok(LocalWorkerAsset { image, path })
}

#[cfg(target_os = "linux")]
fn open_external_worker() -> crate::Result<LocalWorkerAsset> {
    use std::os::fd::AsRawFd;
    use std::os::unix::fs::PermissionsExt;

    let path = std::env::var_os("PATH")
        .and_then(|paths| {
            std::env::split_paths(&paths)
                .map(|directory| directory.join("pl-remote-helper"))
                .find(|candidate| {
                    candidate.metadata().is_ok_and(|metadata| {
                        metadata.is_file() && metadata.permissions().mode() & 0o111 != 0
                    })
                })
        })
        .ok_or_else(|| {
            crate::PureError::ConfigError(
                "install pl-remote-helper on PATH for non-bundled Studio execution".into(),
            )
        })?;
    let image = std::fs::File::open(&path).map_err(|error| {
        crate::PureError::ConfigError(format!("open local worker {}: {error}", path.display()))
    })?;
    let path = std::path::PathBuf::from(format!("/proc/self/fd/{}", image.as_raw_fd()));
    Ok(LocalWorkerAsset {
        image: std::sync::Arc::new(image),
        path,
    })
}
