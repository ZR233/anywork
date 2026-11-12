//! Host-derived execution-side session paths for one Thread.
//!
//! The layout is product-agnostic: callers pass the original Thread identity, and
//! every environment (local, SSH, worktree, directory) consumes the same relative
//! mapping. Do not concatenate this layout at individual call sites.

use std::path::PathBuf;

use sha2::{Digest, Sha256};

/// Execution-side session directories derived from a host-specified Thread identity.
///
/// Construct with [`Self::new`] using the **original** Thread id. Hashing an already
/// hashed task key (`task-{sha256}`) would disagree with host facts, command capture
/// paths, and directory write allowances.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct SessionFiles {
    thread_key: String,
}

impl SessionFiles {
    /// Derives the session layout from the original Thread identity.
    ///
    /// The Thread key is the lowercase hex SHA-256 of the raw id. The raw id never
    /// appears as a path component. Distinct Thread identities produce distinct keys.
    pub fn new(thread_id: impl AsRef<str>) -> Self {
        let digest = Sha256::digest(thread_id.as_ref().as_bytes());
        Self {
            thread_key: hex::encode(digest),
        }
    }

    /// Hex SHA-256 of the original Thread identity.
    pub fn thread_key(&self) -> &str {
        &self.thread_key
    }

    /// Portable relative spelling also used by a Windows host's Linux executor.
    /// Native filesystem APIs on each supported host accept these separators.
    fn relative(&self, suffix: &str) -> PathBuf {
        let root = format!(".anywork/sessions/{}", self.thread_key);
        PathBuf::from(if suffix.is_empty() {
            root
        } else {
            format!("{root}/{suffix}")
        })
    }
    /// `.anywork/sessions/<thread-key>` relative to the workspace root.
    pub fn root(&self) -> PathBuf {
        self.relative("")
    }
    /// Disposable execution files; artifacts live outside this directory.
    pub fn temp(&self) -> PathBuf {
        self.relative("temp")
    }
    pub fn scratch(&self) -> PathBuf {
        self.temp()
    }
    pub fn artifacts(&self) -> PathBuf {
        self.relative("artifacts")
    }
    pub fn commands(&self) -> PathBuf {
        self.relative("temp/commands")
    }
    pub fn uploads(&self) -> PathBuf {
        self.relative("temp/uploads")
    }
    /// An optional lazily created Python environment. Existing environments are not relocated.
    pub fn python_environment(&self) -> PathBuf {
        self.relative("temp/.venv")
    }
    /// Model-readable raw stdout for this call. Opaque keys are reused without rehashing.
    pub fn command_output(&self, call_id: &str) -> PathBuf {
        self.relative(&format!(
            "temp/commands/{}/stdout.log",
            opaque_call_key(call_id)
        ))
    }
    pub fn command_stderr_output(&self, call_id: &str) -> PathBuf {
        self.relative(&format!(
            "temp/commands/{}/stderr.log",
            opaque_call_key(call_id)
        ))
    }
}

/// Reuses the existing opaque `task-{sha256}` call key; otherwise derives it.
pub(crate) fn opaque_call_key(call_id: &str) -> String {
    const PREFIX: &str = "task-";
    if let Some(digest) = call_id.strip_prefix(PREFIX)
        && digest.len() == 64
        && digest.bytes().all(|byte| byte.is_ascii_hexdigit())
    {
        return call_id.to_string();
    }
    format!("task-{}", hex::encode(Sha256::digest(call_id.as_bytes())))
}
