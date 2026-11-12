//! Shared collection policy for release bundles.

use anyhow::{Context, Result, bail};
use std::fs;
use std::path::Path;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum BundleKind {
    Windows,
    PreserveAll,
}

/// Copies a release bundle using the platform's canonical runtime-file policy.
pub(crate) fn copy(source: &Path, destination: &Path, kind: BundleKind) -> Result<()> {
    if !source.is_dir() {
        bail!("build artifact directory not found: {}", source.display());
    }
    fs::create_dir_all(destination)
        .with_context(|| format!("failed to create {}", destination.display()))?;
    match kind {
        BundleKind::Windows => copy_windows_bundle(source, destination),
        BundleKind::PreserveAll => copy_tree(source, destination),
    }
}

fn copy_windows_bundle(source: &Path, destination: &Path) -> Result<()> {
    for entry in
        fs::read_dir(source).with_context(|| format!("failed to read {}", source.display()))?
    {
        let entry =
            entry.with_context(|| format!("failed to read entry in {}", source.display()))?;
        let source_path = entry.path();
        let file_type = entry
            .file_type()
            .with_context(|| format!("failed to inspect {}", source_path.display()))?;
        let is_data_directory = file_type.is_dir() && entry.file_name() == "data";
        let is_runtime_file = file_type.is_file()
            && (entry.file_name() == "anywork.exe"
                || source_path
                    .extension()
                    .is_some_and(|extension| extension.eq_ignore_ascii_case("dll")));
        if !is_data_directory && !is_runtime_file {
            continue;
        }

        let destination_path = destination.join(entry.file_name());
        if is_data_directory {
            copy_tree(&source_path, &destination_path)?;
        } else {
            copy_file(&source_path, &destination_path)?;
        }
    }
    Ok(())
}

fn copy_tree(source: &Path, destination: &Path) -> Result<()> {
    fs::create_dir_all(destination)
        .with_context(|| format!("failed to create {}", destination.display()))?;
    for entry in
        fs::read_dir(source).with_context(|| format!("failed to read {}", source.display()))?
    {
        let entry =
            entry.with_context(|| format!("failed to read entry in {}", source.display()))?;
        let source_path = entry.path();
        let destination_path = destination.join(entry.file_name());
        let file_type = entry
            .file_type()
            .with_context(|| format!("failed to inspect {}", source_path.display()))?;
        if file_type.is_symlink() {
            copy_symlink(&source_path, &destination_path)?;
        } else if file_type.is_dir() {
            copy_tree(&source_path, &destination_path)?;
        } else {
            copy_file(&source_path, &destination_path)?;
        }
    }
    fs::set_permissions(destination, fs::metadata(source)?.permissions())?;
    Ok(())
}

// macOS frameworks contain relative Versions/Current links. Following them
// duplicates framework trees and changes the structure covered by code signing.
fn copy_symlink(source: &Path, destination: &Path) -> Result<()> {
    #[cfg(unix)]
    {
        let target = fs::read_link(source)?;
        if destination.symlink_metadata().is_ok() {
            fs::remove_file(destination)?;
        }
        std::os::unix::fs::symlink(target, destination)
            .with_context(|| format!("failed to copy symlink {}", source.display()))
    }
    #[cfg(not(unix))]
    {
        copy_file(source, destination)
    }
}

fn copy_file(source: &Path, destination: &Path) -> Result<()> {
    fs::copy(source, destination).with_context(|| {
        format!(
            "failed to copy {} to {}",
            source.display(),
            destination.display()
        )
    })?;
    Ok(())
}

#[cfg(all(test, unix))]
mod tests {
    use super::{BundleKind, copy};
    use std::fs;
    use std::os::unix::fs::{PermissionsExt, symlink};

    /// A copied macOS framework must retain its version links and runnable binary.
    #[test]
    fn preserves_framework_links_and_executable_permissions() -> anyhow::Result<()> {
        let root = tempfile::tempdir()?;
        let source = root.path().join("source");
        let destination = root.path().join("copy");
        fs::create_dir_all(source.join("Versions/A"))?;
        fs::write(source.join("Versions/A/Engine"), b"native library")?;
        fs::set_permissions(
            source.join("Versions/A/Engine"),
            fs::Permissions::from_mode(0o755),
        )?;
        symlink("A", source.join("Versions/Current"))?;
        symlink("Versions/Current/Engine", source.join("Engine"))?;
        fs::set_permissions(source.join("Versions/A"), fs::Permissions::from_mode(0o750))?;
        // KeepExisting must also replace existing links without following them.
        for _ in 0..2 {
            copy(&source, &destination, BundleKind::PreserveAll)?;
            assert_eq!(
                fs::read_link(destination.join("Versions/Current"))?,
                std::path::Path::new("A")
            );
            assert_eq!(
                fs::read_link(destination.join("Engine"))?,
                std::path::Path::new("Versions/Current/Engine")
            );
            assert_eq!(fs::read(destination.join("Engine"))?, b"native library");
            assert_eq!(
                fs::metadata(destination.join("Versions/A"))?
                    .permissions()
                    .mode()
                    & 0o777,
                0o750
            );
            assert_eq!(
                fs::metadata(destination.join("Engine"))?
                    .permissions()
                    .mode()
                    & 0o777,
                0o755
            );
        }
        Ok(())
    }
}
