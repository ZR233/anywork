//! Apple ditto preserves signed app bundles, framework symlinks and executable modes.

use super::manifest::sha256_file;
use anyhow::{Context, Result, ensure};
use semver::Version;
use std::collections::BTreeSet;
use std::fs;
use std::path::Path;
use std::process::Command;

fn asset_name(version: &Version) -> String {
    format!("anywork-{version}-macos-arm64.zip")
}

pub(super) fn stage(release_dir: &Path, version: &Version, bundle: &Path) -> Result<()> {
    ensure!(
        cfg!(target_arch = "aarch64"),
        "macOS releases support arm64 only"
    );
    ensure!(
        fs::symlink_metadata(release_dir).is_err(),
        "release staging directory already exists; refusing to overwrite {}",
        release_dir.display()
    );
    let app = bundle.join("anywork.app");
    validate_app(&app, version)?;
    let temp = tempfile::Builder::new()
        .prefix("anywork-macos-")
        .tempdir()?;
    let name = asset_name(version);
    let archive = temp.path().join(&name);
    checked(
        Command::new("/usr/bin/ditto")
            .args(["-c", "-k", "--sequesterRsrc", "--keepParent"])
            .arg(&app)
            .arg(&archive),
    )?;
    fs::create_dir_all(
        release_dir
            .parent()
            .context("release directory has no parent")?,
    )?;
    fs::create_dir(release_dir)?;
    fs::copy(&archive, release_dir.join(&name))?;
    fs::write(
        release_dir.join(format!("{name}.sha256")),
        checksum(&archive, &name)?,
    )?;
    println!("Staged macOS release: {}", release_dir.display());
    Ok(())
}

pub(super) fn verify(release_dir: &Path, version: &Version) -> Result<()> {
    let name = asset_name(version);
    let expected = BTreeSet::from([name.clone(), format!("{name}.sha256")]);
    let mut actual = BTreeSet::new();
    for entry in fs::read_dir(release_dir)? {
        let entry = entry?;
        ensure!(
            entry.file_type()?.is_file(),
            "release contains non-file entry"
        );
        actual.insert(
            entry
                .file_name()
                .into_string()
                .map_err(|_| anyhow::anyhow!("release contains a non-UTF-8 filename"))?,
        );
    }
    ensure!(
        actual == expected,
        "macOS release file set mismatch: expected {expected:?}, got {actual:?}"
    );
    let archive = release_dir.join(&name);
    ensure!(
        fs::read_to_string(release_dir.join(format!("{name}.sha256")))?
            == checksum(&archive, &name)?,
        "macOS release checksum mismatch"
    );
    let temp = tempfile::Builder::new()
        .prefix("anywork-macos-verify-")
        .tempdir()?;
    checked(
        Command::new("/usr/bin/ditto")
            .args(["-x", "-k"])
            .arg(&archive)
            .arg(temp.path()),
    )?;
    validate_app(&temp.path().join("anywork.app"), version)?;
    println!("Verified macOS release: {}", release_dir.display());
    Ok(())
}

fn checksum(archive: &Path, name: &str) -> Result<String> {
    Ok(format!("{}  {name}\n", sha256_file(archive)?))
}

fn validate_app(app: &Path, version: &Version) -> Result<()> {
    for file in [
        "Contents/MacOS/anywork",
        "Contents/Info.plist",
        "Contents/Frameworks/libpl_studio_bridge.dylib",
        "Contents/Frameworks/App.framework/Resources/flutter_assets/AssetManifest.bin",
        "Contents/Resources/licenses/LICENSE.anywork",
        "Contents/Resources/licenses/LICENSE.flutter",
        "Contents/Resources/licenses/THIRD_PARTY_NOTICES.md",
    ] {
        let path = app.join(file);
        ensure!(
            path.is_file() && fs::metadata(&path)?.len() > 0,
            "missing or empty macOS input: {file}"
        );
    }
    for target in ["x86_64-unknown-linux-musl", "aarch64-unknown-linux-musl"] {
        for file in ["pl-remote-helper.zst", "pl-remote-helper.metadata.json"] {
            let path = app
                .join("Contents/Resources/data/remote-helper")
                .join(target)
                .join(file);
            ensure!(
                path.is_file() && fs::metadata(&path)?.len() > 0,
                "missing or empty helper: {}",
                path.display()
            );
        }
    }
    crate::host_mcp::validate_bundle_resources(
        &app.join("Contents/Resources/data/host-mcp"),
        "aarch64-apple-darwin",
    )?;
    let actual = checked(
        Command::new("/usr/libexec/PlistBuddy")
            .args(["-c", "Print :CFBundleShortVersionString"])
            .arg(app.join("Contents/Info.plist")),
    )?;
    ensure!(
        actual.trim() == version.to_string(),
        "macOS bundle version mismatch: expected {version}, got {actual:?}"
    );
    for file in [
        "Contents/MacOS/anywork",
        "Contents/Frameworks/libpl_studio_bridge.dylib",
    ] {
        let arch = checked(
            Command::new("/usr/bin/lipo")
                .arg("-archs")
                .arg(app.join(file)),
        )?;
        ensure!(
            arch.trim() == "arm64",
            "macOS payload must be arm64: {file}: {arch:?}"
        );
    }
    checked(
        Command::new("/usr/bin/codesign")
            .args(["--verify", "--deep", "--strict"])
            .arg(app),
    )?;
    Ok(())
}

fn checked(command: &mut Command) -> Result<String> {
    let output = command
        .output()
        .with_context(|| format!("failed to execute {command:?}"))?;
    ensure!(
        output.status.success(),
        "{command:?} failed ({}):\n{}\n{}",
        output.status,
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    Ok(String::from_utf8(output.stdout)?)
}
