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
        if entry
            .file_type()
            .with_context(|| format!("failed to inspect {}", source_path.display()))?
            .is_dir()
        {
            copy_tree(&source_path, &destination_path)?;
        } else {
            copy_file(&source_path, &destination_path)?;
        }
    }
    Ok(())
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
