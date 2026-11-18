//! Workspace path discovery shared by the engineering tools.

use anyhow::{Context, bail};
use std::path::{Path, PathBuf};

pub use anyhow::Result;

/// Returns the Pure-Lang workspace root containing the current working directory.
///
/// Cached engineering binaries may have been compiled in another checkout.
/// Resolve the caller's checkout instead of embedding the compilation directory.
///
/// # Errors
/// Returns an error outside a workspace that passes [`ensure_workspace_shape`].
pub fn workspace_root() -> Result<PathBuf> {
    let working = std::env::current_dir().context("read engineering tool working directory")?;
    for root in working.ancestors() {
        if studio_app_dir(root).join("pubspec.yaml").is_file() {
            ensure_workspace_shape(root)?;
            return Ok(root.to_path_buf());
        }
    }
    bail!("no Pure-Lang workspace contains {}", working.display())
}

/// Returns the Studio (Flutter app) directory under [workspace_root].
pub fn studio_app_dir(workspace_root: &Path) -> PathBuf {
    workspace_root.join("code").join("anywork")
}

/// Returns the release staging directory under [workspace_root].
pub fn release_dist_dir(workspace_root: &Path) -> PathBuf {
    workspace_root.join("dist").join("anywork-release")
}

/// Validates that [workspace_root] looks like the Pure-Lang workspace.
///
/// # Errors
/// Returns an error when the root has no root `Cargo.toml` or when the Studio
/// app directory has no `pubspec.yaml`.
pub fn ensure_workspace_shape(workspace_root: &Path) -> Result<()> {
    let app_dir = studio_app_dir(workspace_root);
    if !workspace_root.join("Cargo.toml").is_file() {
        bail!(
            "workspace root does not contain Cargo.toml: {}",
            workspace_root.display()
        );
    }
    if !app_dir.join("pubspec.yaml").is_file() {
        bail!(
            "Studio app directory is invalid; workspace root: {}, Studio app dir: {}",
            workspace_root.display(),
            app_dir.display()
        );
    }
    Ok(())
}
