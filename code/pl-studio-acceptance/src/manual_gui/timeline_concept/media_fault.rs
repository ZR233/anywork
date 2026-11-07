//! Missing-media fault injection for this harness's stopped, isolated runtime.
//! Never accepts an arbitrary host path from a GUI report or removes user bytes.

use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    path::{Path, PathBuf},
};

use anyhow::{Context, Result, ensure};
use serde_json::{Value, json};

pub(super) fn inject(working: &Path, home: &Path, project: &Path, output: &Path) -> Result<()> {
    let working = fs::canonicalize(working)?;
    let home = owned_directory(&working, home)?;
    let project = owned_directory(&working, project)?;
    ensure!(
        home.parent() == Some(working.as_path()),
        "media fault requires this harness's immediate isolated home"
    );
    ensure!(
        project.parent() == Some(working.as_path()) && project != home,
        "media fault project is not owned by this isolated run"
    );
    let report: Value = serde_json::from_slice(&fs::read(output.join("timeline-concept.json"))?)?;
    let reopened: Value =
        serde_json::from_slice(&fs::read(output.join("timeline-concept-reopen.json"))?)?;
    for report in [&report, &reopened] {
        ensure!(
            report["pass"] == true && report["shutdown"] == "completed",
            "media fault must follow successful native runs and clean owner shutdown"
        );
    }
    let ids = report["readImageResourceIds"]
        .as_array()
        .context("journey did not record real image attachment resource identities")?;
    ensure!(
        ids.len() == 3,
        "expected three actual image tool attachments"
    );
    let mut hashes = BTreeSet::new();
    for id in ids {
        let id = id.as_str().context("resource identity is not text")?;
        let hash = id
            .strip_prefix(pl_studio_runtime::resource_store::RESOURCE_ID_PREFIX)
            .context("image attachment is not an archived product resource")?;
        ensure!(
            hash.len() == 64 && hash.bytes().all(|byte| byte.is_ascii_hexdigit()),
            "invalid resource identity"
        );
        hashes.insert(hash.to_owned());
    }
    let source = project.join("concept-image-a.png");
    let metadata = fs::symlink_metadata(&source)?;
    ensure!(
        metadata.is_file() && !metadata.file_type().is_symlink(),
        "owned fixture image is not a regular file"
    );
    let source_bytes = fs::read(&source)?;
    let data = owned_directory(&home, &home.join("data"))?;
    let mut candidates = BTreeMap::<String, Vec<PathBuf>>::new();
    let mut remaining = 4096usize;
    locate(
        &home,
        &data,
        &hashes,
        &source_bytes,
        &mut candidates,
        &mut remaining,
    )?;
    // Validate the entire plan before the first mutation. Ambiguous shared or
    // unexpected resources never become a best-effort destructive operation.
    for hash in &hashes {
        ensure!(
            candidates.get(hash).is_some_and(|paths| paths.len() == 1),
            "owned image resource is missing or ambiguous: {hash}"
        );
    }
    let backup = output.join("media-fault-originals");
    fs::create_dir(&backup).context("media fault originals directory already exists")?;
    let mut evidence = Vec::new();
    for hash in hashes {
        let target = &candidates[&hash][0];
        validate_target(&home, target, &hash)?;
        let retained = target.with_extension("timeline-concept-original");
        ensure!(
            !retained.try_exists()?,
            "refusing to overwrite retained fault bytes"
        );
        let result = (|| -> Result<()> {
            fs::copy(target, backup.join(&hash))?;
            // Rename within the same isolated resource directory: missing at
            // the real locator, original bytes retained for failed-run evidence.
            fs::rename(target, &retained)?;
            ensure!(
                !target.try_exists()?,
                "resource locator is not actually missing"
            );
            ensure!(
                fs::read(&retained)? == source_bytes,
                "retained original changed"
            );
            Ok(())
        })();
        evidence.push(json!({
            "resourceId": format!("{}{hash}", pl_studio_runtime::resource_store::RESOURCE_ID_PREFIX),
            "missingPath": target.strip_prefix(&home)?,
            "retainedPath": retained.strip_prefix(&home)?,
            "byteLength": source_bytes.len(),
            "injected": result.is_ok(),
            "error": result.as_ref().err().map(|error| format!("{error:#}")),
        }));
        fs::write(
            output.join("media-fault-injection.json"),
            serde_json::to_vec_pretty(&json!({
                "fault": "archived-resource-missing",
                "scope": "stopped-harness-owned-home",
                "originalsVerified": evidence.iter().all(|record| record["injected"] == true),
                "records": evidence,
            }))?,
        )?;
        result?;
    }
    Ok(())
}

fn owned_directory(owner: &Path, path: &Path) -> Result<PathBuf> {
    let metadata = fs::symlink_metadata(path)?;
    ensure!(
        metadata.is_dir() && !metadata.file_type().is_symlink(),
        "owned directory is missing, linked or not a directory"
    );
    let canonical = fs::canonicalize(path)?;
    ensure!(
        canonical.starts_with(owner) && canonical != owner,
        "path is outside this harness's owned scope"
    );
    Ok(canonical)
}

fn validate_target(home: &Path, path: &Path, hash: &str) -> Result<()> {
    let metadata = fs::symlink_metadata(path)?;
    ensure!(
        metadata.is_file() && !metadata.file_type().is_symlink(),
        "resource target is not a regular owned file"
    );
    let canonical = fs::canonicalize(path)?;
    ensure!(
        canonical.starts_with(home) && canonical == path,
        "resource target escaped isolated home or crossed a link"
    );
    ensure!(
        path.parent()
            .and_then(Path::file_name)
            .is_some_and(|name| name == "resources")
            && path.file_name().is_some_and(|name| name == hash),
        "resource target is not the actual resource-store locator"
    );
    Ok(())
}

fn locate(
    home: &Path,
    directory: &Path,
    hashes: &BTreeSet<String>,
    bytes: &[u8],
    found: &mut BTreeMap<String, Vec<PathBuf>>,
    remaining: &mut usize,
) -> Result<()> {
    for entry in fs::read_dir(directory)? {
        ensure!(
            *remaining != 0,
            "owned media discovery exceeded its finite budget"
        );
        *remaining -= 1;
        let entry = entry?;
        let kind = entry.file_type()?;
        ensure!(
            !kind.is_symlink(),
            "owned media discovery refuses symbolic links"
        );
        let path = entry.path();
        if kind.is_dir() {
            let child = owned_directory(home, &path)?;
            locate(home, &child, hashes, bytes, found, remaining)?;
        } else if kind.is_file()
            && directory
                .file_name()
                .is_some_and(|name| name == "resources")
            && let Some(hash) = path.file_name().and_then(|name| name.to_str())
            && hashes.contains(hash)
        {
            validate_target(home, &path, hash)?;
            ensure!(
                entry.metadata()?.len() == bytes.len() as u64 && fs::read(&path)? == bytes,
                "candidate does not contain the fixture's actual archived image"
            );
            found.entry(hash.to_owned()).or_default().push(path);
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Ownership/fault-mechanism evidence only, not a production image-load or
    /// GUI verdict. Product bytes are first archived by the real native journey.
    struct OwnedFixture {
        working: tempfile::TempDir,
        home: PathBuf,
        project: PathBuf,
        output: PathBuf,
        resource: PathBuf,
        hash: String,
    }

    impl OwnedFixture {
        fn new() -> Result<Self> {
            let working = tempfile::tempdir()?;
            let home = working.path().join("home");
            let project = working.path().join("timeline-concept-project");
            let output = working.path().join("output");
            fs::create_dir(&home)?;
            fs::create_dir(&project)?;
            fs::create_dir(&output)?;
            let hash = "a".repeat(64);
            let resources = home.join("data/workspaces/owned/sessions/owned/resources");
            fs::create_dir_all(&resources)?;
            let resource = resources.join(&hash);
            fs::write(&resource, b"owned fixture bytes")?;
            fs::write(project.join("concept-image-a.png"), b"owned fixture bytes")?;
            let resource_id = format!(
                "{}{hash}",
                pl_studio_runtime::resource_store::RESOURCE_ID_PREFIX
            );
            fs::write(
                output.join("timeline-concept.json"),
                serde_json::to_vec(&json!({
                    "pass": true,
                    "shutdown": "completed",
                    "readImageResourceIds": [&resource_id, &resource_id, &resource_id],
                }))?,
            )?;
            fs::write(
                output.join("timeline-concept-reopen.json"),
                br#"{"pass":true,"shutdown":"completed"}"#,
            )?;
            Ok(Self {
                working,
                home,
                project,
                output,
                resource,
                hash,
            })
        }

        fn inject(&self) -> Result<()> {
            inject(self.working.path(), &self.home, &self.project, &self.output)
        }
    }

    #[test]
    fn missing_locator_preserves_original_and_archive_evidence() -> Result<()> {
        let fixture = OwnedFixture::new()?;
        fixture.inject()?;
        assert!(!fixture.resource.try_exists()?);
        assert_eq!(
            fs::read(fixture.resource.with_extension("timeline-concept-original"))?,
            b"owned fixture bytes"
        );
        assert_eq!(
            fs::read(
                fixture
                    .output
                    .join("media-fault-originals")
                    .join(&fixture.hash)
            )?,
            b"owned fixture bytes"
        );
        let evidence: Value = serde_json::from_slice(&fs::read(
            fixture.output.join("media-fault-injection.json"),
        )?)?;
        assert_eq!(evidence["originalsVerified"], true);
        assert_eq!(evidence["records"].as_array().unwrap().len(), 1);
        assert_eq!(evidence["records"][0]["injected"], true);
        Ok(())
    }

    #[test]
    fn ambiguous_archive_never_mutates_either_candidate() -> Result<()> {
        let fixture = OwnedFixture::new()?;
        let other = fixture
            .home
            .join("data/workspaces/other/sessions/other/resources");
        fs::create_dir_all(&other)?;
        fs::write(other.join(&fixture.hash), b"owned fixture bytes")?;
        assert!(fixture.inject().is_err());
        assert_eq!(fs::read(&fixture.resource)?, b"owned fixture bytes");
        assert_eq!(fs::read(other.join(&fixture.hash))?, b"owned fixture bytes");
        assert!(!fixture.output.join("media-fault-originals").try_exists()?);
        Ok(())
    }

    #[cfg(unix)]
    #[test]
    fn linked_archive_is_refused_without_touching_the_external_file() -> Result<()> {
        let fixture = OwnedFixture::new()?;
        let external = tempfile::tempdir()?;
        let external_file = external.path().join("user-owned");
        fs::write(&external_file, b"owned fixture bytes")?;
        // This is only the test's own disposable fixture file.
        fs::remove_file(&fixture.resource)?;
        std::os::unix::fs::symlink(&external_file, &fixture.resource)?;
        assert!(fixture.inject().is_err());
        assert_eq!(fs::read(&external_file)?, b"owned fixture bytes");
        assert!(
            fs::symlink_metadata(&fixture.resource)?
                .file_type()
                .is_symlink()
        );
        assert!(!fixture.output.join("media-fault-originals").try_exists()?);
        Ok(())
    }
}
