//! Native bundles owned by the existing live test preparation, never a cross-run cache.

use super::{DesktopTestPreparation, file_digest};
use crate::release_bundle::{self, BundleKind};
use anyhow::{Context, Result, ensure};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs::{self, File};
use std::path::{Path, PathBuf};

#[derive(Serialize, Deserialize)]
struct Receipt {
    arguments: Vec<String>,
    entries: Vec<Entry>,
}

#[derive(Debug, PartialEq, Eq, Serialize, Deserialize)]
struct Entry {
    path: PathBuf,
    permissions: u32,
    content: Content,
}

#[derive(Debug, PartialEq, Eq, Serialize, Deserialize)]
enum Content {
    Directory,
    File(String),
    Symlink(PathBuf),
}

impl DesktopTestPreparation {
    /// Builds each exact Flutter invocation once, snapshots its complete bundle,
    /// and validates it again before every fresh native process is launched.
    pub(crate) fn native_bundle(
        &self,
        arguments: &[&str],
        tools: &str,
        build: impl FnOnce() -> Result<PathBuf>,
    ) -> Result<PathBuf> {
        let started = std::time::Instant::now();
        self.validate()?;
        // Flutter writes shared checkout output. Only preparation holds this lock;
        // running applications never prevent a different configuration's build.
        let preparation = File::options()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(self.directory.join("native-build.lock"))?;
        preparation
            .try_lock()
            .context("another native bundle preparation is using this invocation")?;
        let toolchain = self.directory.join("native-toolchain");
        if toolchain.try_exists()? {
            ensure!(
                fs::read_to_string(&toolchain)? == tools,
                "native preparation toolchain changed; start a new suite"
            );
        } else {
            fs::write(&toolchain, tools)?;
        }
        let arguments: Vec<String> = arguments.iter().map(|value| (*value).to_owned()).collect();
        let key = hex::encode(Sha256::digest(serde_json::to_vec(&arguments)?));
        let directory = self.directory.join(format!("native-{key}"));
        let bundle = directory.join("bundle");
        if directory.symlink_metadata().is_ok() {
            let receipt: Receipt =
                serde_json::from_slice(&fs::read(directory.join("receipt.json"))?)
                    .context("native bundle preparation is incomplete")?;
            ensure!(
                receipt.arguments == arguments,
                "native bundle configuration changed"
            );
            ensure!(
                receipt.entries == tree_identity(&bundle)?,
                "native bundle artifact changed"
            );
            println!(
                "startup_stage=reuse_native_bundle elapsed_ms={}",
                started.elapsed().as_millis()
            );
        } else {
            fs::create_dir(&directory)?;
            let source = build()?;
            let entries = tree_identity(&source)?;
            release_bundle::copy(&source, &bundle, BundleKind::PreserveAll)?;
            ensure!(
                entries == tree_identity(&bundle)?,
                "native bundle changed while copying"
            );
            self.validate()?;
            fs::write(
                directory.join("receipt.json"),
                serde_json::to_vec(&Receipt { arguments, entries })?,
            )?;
            println!(
                "startup_stage=prepare_native_bundle elapsed_ms={}",
                started.elapsed().as_millis()
            );
        }
        Ok(bundle)
    }
}

/// Includes names, directory topology, permissions, link targets and every file's
/// bytes. Framework links stay inside the copied bundle and are never flattened.
fn tree_identity(root: &Path) -> Result<Vec<Entry>> {
    fn visit(root: &Path, path: &Path, entries: &mut Vec<Entry>) -> Result<()> {
        let metadata = path.symlink_metadata()?;
        #[cfg(unix)]
        let permissions = {
            use std::os::unix::fs::PermissionsExt;
            metadata.permissions().mode()
        };
        #[cfg(not(unix))]
        let permissions = u32::from(metadata.permissions().readonly());
        let content = if metadata.is_symlink() {
            ensure!(
                path.canonicalize()?.starts_with(root),
                "native bundle link escapes its bundle"
            );
            Content::Symlink(fs::read_link(path)?)
        } else if metadata.is_dir() {
            Content::Directory
        } else {
            ensure!(metadata.is_file(), "native bundle contains a special file");
            Content::File(file_digest(path)?)
        };
        entries.push(Entry {
            path: path.strip_prefix(root)?.to_owned(),
            permissions,
            content,
        });
        if metadata.is_dir() {
            let mut children = fs::read_dir(path)?.collect::<std::io::Result<Vec<_>>>()?;
            children.sort_by_key(|entry| entry.file_name());
            for child in children {
                visit(root, &child.path(), entries)?;
            }
        }
        Ok(())
    }
    ensure!(
        root.symlink_metadata()?.is_dir(),
        "native bundle is not a directory"
    );
    let root = root.canonicalize()?;
    let mut entries = Vec::new();
    visit(&root, &root, &mut entries)?;
    Ok(entries)
}

pub(in crate::flutter) fn tool_identity() -> Result<String> {
    let mut hash = Sha256::new();
    hash.update(file_digest(&std::env::current_exe()?)?);
    for (program, args) in [
        ("rustc", &["-Vv"][..]),
        ("cargo", &["-V"][..]),
        ("flutter", &["--version", "--machine"][..]),
        ("cmake", &["--version"][..]),
    ] {
        let args: Vec<_> = args.iter().map(std::ffi::OsString::from).collect();
        let output = pl_dev_support::process::path_command(program, &args).output()?;
        ensure!(
            output.status.success(),
            "native tool identity failed for {program}: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        hash.update(program);
        hash.update(output.stdout);
    }
    Ok(hex::encode(hash.finalize()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use anyhow::bail;
    use std::cell::Cell;

    #[test]
    fn native_bundles_survive_configuration_switches_and_reject_tampering() -> Result<()> {
        let (_temp, owner) = super::super::tests::fixture()?;
        let source = owner.workspace().join("target/flutter-output");
        fs::create_dir_all(source.join("data"))?;
        fs::write(source.join("anywork"), b"native executable")?;
        #[cfg(unix)]
        std::os::unix::fs::symlink("kernel", source.join("data/current"))?;
        let builds = Cell::new(0);
        let build = |payload: &[u8]| {
            builds.set(builds.get() + 1);
            fs::write(source.join("data/kernel"), payload)?;
            Ok(source.clone())
        };
        let shutdown = ["build", "--debug", "-t", "tool/native_shutdown_main.dart"];
        let main = [
            "build",
            "--debug",
            "-t",
            "lib/main.dart",
            "--dart-define=ANYWORK_CAPTURE=true",
        ];
        let first = owner.native_bundle(&shutdown, "tools", || build(b"shutdown entrypoint"))?;
        let second = owner.native_bundle(&main, "tools", || build(b"capture entrypoint"))?;
        assert_ne!(first, second);
        for _ in 0..2 {
            owner.native_bundle(&shutdown, "tools", || {
                panic!("rebuilt shutdown configuration")
            })?;
            owner.native_bundle(&main, "tools", || panic!("rebuilt main configuration"))?;
        }
        assert_eq!(builds.get(), 2);
        assert_eq!(fs::read(first.join("data/kernel"))?, b"shutdown entrypoint");
        assert_eq!(fs::read(second.join("data/kernel"))?, b"capture entrypoint");
        assert!(
            owner
                .native_bundle(&shutdown, "changed tools", || unreachable!())
                .unwrap_err()
                .to_string()
                .contains("toolchain changed")
        );
        fs::write(first.join("data/kernel"), b"tampered")?;
        assert!(
            owner
                .native_bundle(&shutdown, "tools", || unreachable!())
                .unwrap_err()
                .to_string()
                .contains("artifact changed")
        );
        fs::remove_file(second.join("anywork"))?;
        assert!(
            owner
                .native_bundle(&main, "tools", || unreachable!())
                .is_err()
        );
        Ok(())
    }

    #[test]
    fn incomplete_preparation_cannot_fall_back_to_rebuilding() -> Result<()> {
        let (_temp, owner) = super::super::tests::fixture()?;
        let arguments = ["build", "--debug"];
        assert!(
            owner
                .native_bundle(&arguments, "tools", || bail!("build failed"))
                .is_err()
        );
        assert!(
            owner
                .native_bundle(&arguments, "tools", || panic!("retried incomplete build"))
                .is_err()
        );
        owner._owner.as_ref().unwrap().0.unlock()?;
        assert!(
            owner
                .native_bundle(&["other target"], "tools", || unreachable!())
                .unwrap_err()
                .to_string()
                .contains("owner has exited")
        );
        Ok(())
    }
}
