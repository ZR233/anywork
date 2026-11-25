//! Studio runtime 的 remote helper 来源：桌面随包压缩资源或外部安装。

use std::{
    path::{Path, PathBuf},
    sync::{Arc, OnceLock},
};

use pl_tool::remote::{RemoteHelperAssets, RemoteHelperTarget, SshError, SshManager};
use serde::Deserialize;

use crate::executable_assets::{BundleMetadata, load_bundled_archive};

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

impl BundleMetadata for BundledHelperMetadata {
    const STEM: &'static str = "pl-remote-helper";
    const DESCRIPTION: &'static str = "bundled helper";

    fn target(&self) -> &str {
        &self.target
    }

    fn sha256(&self) -> &str {
        &self.sha256
    }

    fn validate(&self, path: &Path) -> Result<(), String> {
        let expected = pl_remote_helper::process_worker_protocol::PROCESS_WORKER_PROTOCOL_VERSION;
        if self.worker_protocol_version != expected {
            return Err(format!(
                "bundled helper metadata {} declares worker protocol {}, expected {expected}; rebuild the application bundle",
                path.display(),
                self.worker_protocol_version,
            ));
        }
        let expected = pl_remote_helper::EXECUTOR_WIRE_VERSION;
        if self.remote_protocol_version != expected {
            return Err(format!(
                "bundled helper metadata {} declares remote protocol {}, expected {expected}; rebuild the application bundle",
                path.display(),
                self.remote_protocol_version,
            ));
        }
        Ok(())
    }
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
        let loaded = load_bundled_archive::<BundledHelperMetadata>(&self.root, target.triple())
            .map_err(SshError::Protocol)?;
        if cache.set(loaded.clone()).is_ok() {
            return Ok(loaded);
        }
        cache.get().cloned().ok_or_else(|| {
            SshError::Protocol("bundled helper cache initialization failed".to_string())
        })
    }
}
