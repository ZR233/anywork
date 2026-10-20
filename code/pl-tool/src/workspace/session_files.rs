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

    /// `.anywork/sessions/<thread-key>` relative to the workspace root.
    pub fn root(&self) -> PathBuf {
        PathBuf::from(".anywork")
            .join("sessions")
            .join(&self.thread_key)
    }

    /// Temporary scripts, probes, and intermediate files for this Thread.
    pub fn scratch(&self) -> PathBuf {
        self.root().join("scratch")
    }

    /// Outputs that are not yet at a user-specified location.
    pub fn artifacts(&self) -> PathBuf {
        self.root().join("artifacts")
    }

    /// Command capture directories for this Thread.
    pub fn commands(&self) -> PathBuf {
        self.root().join("commands")
    }

    /// Model-readable command capture path for one call.
    ///
    /// `call_id` is the opaque call physical key (`task-` plus SHA-256) or any call
    /// identity. Raw call/process identifiers never appear as path components, and an
    /// already opaque `task-{hex}` key is reused rather than hashed again.
    pub fn command_output(&self, call_id: &str) -> PathBuf {
        self.commands()
            .join(opaque_call_key(call_id))
            .join("output.log")
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
