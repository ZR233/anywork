//! Directory identity and the runtime's one OS-lock lease, shared with native desktop startup.

use std::path::Path;
use std::sync::Arc;

use pl_protocol::studio::{StudioError, StudioResult};
use sha2::{Digest, Sha256};

use super::runtime_lock::{ResolvedRuntimeOptions, RuntimeLock, StudioRuntimeOptions};

/// A resolved Studio home and its physical identity. Preparation creates only directories;
/// configuration, migrations and databases remain untouched until a lease is acquired.
#[derive(Debug)]
pub struct StudioInstance {
    resolved: Arc<ResolvedRuntimeOptions>,
    key: String,
}

/// An opaque reference to the same exclusive OS file lock used by every Studio host.
///
/// A desktop host retains one clone until process exit. Runtime shutdown releases only its
/// own reference, including when startup is cancelled or fails before a runtime is installed.
#[derive(Debug, Clone)]
pub struct StudioInstanceLease {
    pub(super) resolved: Arc<ResolvedRuntimeOptions>,
    pub(super) lock: Arc<RuntimeLock>,
}

impl StudioInstance {
    /// Resolves the existing home rules and identifies the directory, following filesystem aliases.
    ///
    /// # Errors
    /// Returns a typed path or storage error if the home cannot be resolved, created or identified.
    pub fn prepare(options: StudioRuntimeOptions) -> StudioResult<Self> {
        let resolved = options.resolve()?;
        std::fs::create_dir_all(resolved.paths.home()).map_err(identity_error)?;
        let key = directory_key(resolved.paths.home()).map_err(identity_error)?;
        Ok(Self {
            resolved: Arc::new(resolved),
            key,
        })
    }

    /// Stable, non-reversible routing key; never use it instead of the OS lock to infer ownership.
    pub fn key(&self) -> &str {
        &self.key
    }

    /// Attempts the existing runtime file lock without waiting or starting any business resources.
    ///
    /// # Errors
    /// Returns `instanceBusy` while another host owns the home, or the original typed storage error.
    pub fn try_acquire(&self) -> StudioResult<StudioInstanceLease> {
        let lock = RuntimeLock::acquire(&self.resolved.paths.runtime_lock(), self.resolved.host)?;
        Ok(StudioInstanceLease {
            resolved: self.resolved.clone(),
            lock: Arc::new(lock),
        })
    }
}

fn identity_error(error: std::io::Error) -> StudioError {
    tracing::error!(error = %error, "failed to identify Studio home directory");
    StudioError::storage()
}

fn directory_key(path: &Path) -> std::io::Result<String> {
    let mut hash = Sha256::new();
    hash.update(b"anywork-studio-instance-v1\0");
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        let metadata = std::fs::metadata(path)?;
        hash.update(metadata.dev().to_le_bytes());
        hash.update(metadata.ino().to_le_bytes());
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::OpenOptionsExt;
        use std::os::windows::io::AsRawHandle;
        use windows_sys::Win32::Storage::FileSystem::{
            FILE_FLAG_BACKUP_SEMANTICS, FILE_ID_INFO, FileIdInfo, GetFileInformationByHandleEx,
        };
        let directory = std::fs::OpenOptions::new()
            .read(true)
            .custom_flags(FILE_FLAG_BACKUP_SEMANTICS)
            .open(path)?;
        let mut identity = std::mem::MaybeUninit::<FILE_ID_INFO>::uninit();
        // SAFETY: the owned directory handle stays open for the call, and the output points to
        // suitably aligned storage with exactly the size required by FileIdInfo. The OS follows
        // reparse points because FILE_FLAG_OPEN_REPARSE_POINT is deliberately absent.
        let success = unsafe {
            GetFileInformationByHandleEx(
                directory.as_raw_handle(),
                FileIdInfo,
                identity.as_mut_ptr().cast(),
                std::mem::size_of::<FILE_ID_INFO>() as u32,
            )
        };
        if success == 0 {
            return Err(std::io::Error::last_os_error());
        }
        // SAFETY: a successful FileIdInfo call initialized the entire FILE_ID_INFO above.
        let identity = unsafe { identity.assume_init() };
        hash.update(identity.VolumeSerialNumber.to_le_bytes());
        hash.update(identity.FileId.Identifier);
    }
    Ok(hex::encode(hash.finalize()))
}
