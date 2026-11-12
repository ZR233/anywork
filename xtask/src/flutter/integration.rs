//! Invocation-scoped handoff of prepared desktop inputs, never a build cache.

use std::ffi::OsStr;
use std::fs::{self, File, TryLockError};
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{Context, Result, bail, ensure};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tempfile::TempDir;

mod native;
pub(super) use native::tool_identity as native_tool_identity;

use super::{
    BridgeConfiguration, DemoMode, DesktopTarget, RustBridgeArtifacts,
    ensure_desktop_build_environment, ensure_flutter_dependencies_for_build, paths,
    prepare_bridge_artifacts, prepare_remote_helpers,
};

pub(crate) const PREPARATION_ENV: &str = "ANYWORK_DESKTOP_TEST_PREPARATION";
const XTASK_ENV: &str = "ANYWORK_DESKTOP_TEST_XTASK";

#[derive(Debug, Serialize, Deserialize)]
struct Inputs {
    workspace: PathBuf,
    xtask: PathBuf,
    host: String,
    source: String,
    configuration: String,
    bridge: RustBridgeArtifacts,
    helpers: PathBuf,
    artifacts: Vec<(PathBuf, String)>,
}

/// The parent owns the temporary directory and lock until every case has joined.
/// Borrowers only consume paths validated against this still-live owner.
pub(crate) struct DesktopTestPreparation {
    inputs: Inputs,
    directory: PathBuf,
    _owner: Option<(File, TempDir)>,
}

impl DesktopTestPreparation {
    pub(crate) fn prepare(workspace: &Path) -> Result<Self> {
        let workspace = workspace.canonicalize()?;
        if let Some(prepared) = Self::from_environment(&workspace)? {
            return Ok(prepared);
        }
        Self::build(&workspace)
    }

    pub(crate) fn from_environment(workspace: &Path) -> Result<Option<Self>> {
        match (
            std::env::var_os(PREPARATION_ENV),
            std::env::var_os(XTASK_ENV),
        ) {
            (None, None) => Ok(None),
            (Some(directory), Some(xtask)) if !directory.is_empty() && !xtask.is_empty() => {
                Self::borrow(
                    &workspace.canonicalize()?,
                    Path::new(&directory),
                    Path::new(&xtask),
                )
                .map(Some)
            }
            _ => bail!("{PREPARATION_ENV} and {XTASK_ENV} must be set together and non-empty"),
        }
    }

    fn build(workspace: &Path) -> Result<Self> {
        let workspace = workspace.to_owned();
        let xtask = std::env::current_exe()
            .context("locate desktop test xtask entrypoint")?
            .canonicalize()
            .context("resolve desktop test xtask entrypoint")?;
        let started = std::time::Instant::now();
        ensure_desktop_build_environment(DesktopTarget::current()?)?;
        let app = paths::studio_app_dir(&workspace);
        ensure_flutter_dependencies_for_build(&workspace, &app)?;
        println!(
            "startup_stage=native_preflight elapsed_ms={}",
            started.elapsed().as_millis()
        );
        let helpers = prepare_remote_helpers(&workspace, DemoMode::Native)?
            .context("desktop tests require helper inputs")?
            .canonicalize()?;
        let bridge =
            prepare_bridge_artifacts(&workspace, DemoMode::Native, BridgeConfiguration::Debug)?
                .context("desktop tests require a debug bridge")?;
        let artifacts = artifact_identity(&bridge, &helpers)?;
        let inputs = Inputs {
            source: source_identity(&workspace)?,
            configuration: configuration_identity(),
            host: format!("{}-{}-debug", std::env::consts::OS, std::env::consts::ARCH),
            workspace,
            xtask,
            bridge,
            helpers,
            artifacts,
        };
        Self::own(inputs)
    }

    fn own(inputs: Inputs) -> Result<Self> {
        let parent = inputs.workspace.join("target/test-project-preparation");
        fs::create_dir_all(&parent)?;
        let owner = tempfile::Builder::new().prefix("run-").tempdir_in(parent)?;
        let directory = owner.path().to_owned();
        let lease = File::create_new(directory.join("lease"))?;
        // A separate lease file keeps Windows' mandatory lock from blocking JSON reads.
        lease.try_lock()?;
        fs::write(directory.join("inputs.json"), serde_json::to_vec(&inputs)?)?;
        Ok(Self {
            inputs,
            directory,
            _owner: Some((lease, owner)),
        })
    }

    fn borrow(workspace: &Path, directory: &Path, xtask: &Path) -> Result<Self> {
        let inputs: Inputs = serde_json::from_slice(&fs::read(directory.join("inputs.json"))?)
            .context("read desktop preparation handoff")?;
        ensure!(
            inputs.workspace == workspace,
            "desktop preparation belongs to a different workspace"
        );
        ensure!(
            inputs.xtask == xtask,
            "desktop preparation xtask handoff entrypoint does not match its owner"
        );
        Ok(Self {
            inputs,
            directory: directory.to_owned(),
            _owner: None,
        })
    }

    pub(crate) fn validate(&self) -> Result<()> {
        require_live_owner(&self.directory)?;
        ensure!(
            self.inputs.xtask == std::env::current_exe()?.canonicalize()?,
            "desktop preparation xtask entrypoint changed"
        );
        ensure!(
            self.inputs.host
                == format!("{}-{}-debug", std::env::consts::OS, std::env::consts::ARCH),
            "desktop preparation host or build mode changed"
        );
        ensure!(
            self.inputs.configuration == configuration_identity(),
            "desktop preparation build environment changed"
        );
        ensure!(
            self.inputs.source == source_identity(&self.inputs.workspace)?,
            "desktop preparation source changed; start a new suite"
        );
        ensure!(
            artifact_identity(&self.inputs.bridge, &self.inputs.helpers)? == self.inputs.artifacts,
            "desktop preparation artifact changed"
        );
        Ok(())
    }

    pub(crate) fn workspace(&self) -> &Path {
        &self.inputs.workspace
    }

    pub(crate) fn bridge(&self) -> &RustBridgeArtifacts {
        &self.inputs.bridge
    }

    pub(crate) fn helpers(&self) -> &Path {
        &self.inputs.helpers
    }

    pub(crate) fn environment(&self) -> [(&'static str, &OsStr); 2] {
        [
            (PREPARATION_ENV, self.directory.as_os_str()),
            (XTASK_ENV, self.inputs.xtask.as_os_str()),
        ]
    }
}

fn require_live_owner(directory: &Path) -> Result<()> {
    let lease = File::options()
        .read(true)
        .write(true)
        .open(directory.join("lease"))
        .context("desktop preparation lease is missing")?;
    match lease.try_lock() {
        Err(TryLockError::WouldBlock) => Ok(()),
        Err(TryLockError::Error(error)) => Err(error.into()),
        Ok(()) => bail!("desktop preparation owner has exited"),
    }
}

fn file_digest(path: &Path) -> Result<String> {
    let mut file = File::open(path)
        .with_context(|| format!("read prepared desktop artifact {}", path.display()))?;
    let mut hash = Sha256::new();
    let mut buffer = [0; 64 * 1024];
    loop {
        let count = file.read(&mut buffer)?;
        if count == 0 {
            return Ok(hex::encode(hash.finalize()));
        }
        hash.update(&buffer[..count]);
    }
}

fn artifact_identity(
    bridge: &RustBridgeArtifacts,
    helpers: &Path,
) -> Result<Vec<(PathBuf, String)>> {
    let mut files = vec![bridge.dynamic_library().canonicalize()?];
    if let Some(symbols) = bridge.debug_symbols() {
        files.push(symbols.canonicalize()?);
    }
    collect_files(helpers, &mut files)?;
    files
        .into_iter()
        .map(|path| Ok((path.clone(), file_digest(&path)?)))
        .collect()
}

fn collect_files(directory: &Path, files: &mut Vec<PathBuf>) -> Result<()> {
    let mut entries = fs::read_dir(directory)?.collect::<std::io::Result<Vec<_>>>()?;
    entries.sort_by_key(|entry| entry.file_name());
    for entry in entries {
        let kind = entry.file_type()?;
        if kind.is_dir() {
            collect_files(&entry.path(), files)?;
        } else {
            ensure!(
                kind.is_file(),
                "prepared helper input is not a regular file"
            );
            files.push(entry.path().canonicalize()?);
        }
    }
    Ok(())
}

fn source_identity(workspace: &Path) -> Result<String> {
    let git = |args: &[&str]| -> Result<Vec<u8>> {
        let output = Command::new("git")
            .args(args)
            .current_dir(workspace)
            .output()?;
        ensure!(
            output.status.success(),
            "desktop preparation Git identity failed: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        Ok(output.stdout)
    };
    let mut hash = Sha256::new();
    hash.update(git(&["rev-parse", "HEAD"])?);
    hash.update(git(&[
        "diff",
        "--binary",
        "--no-ext-diff",
        "HEAD",
        "--",
        ".",
    ])?);
    let untracked = git(&["ls-files", "--others", "--exclude-standard", "-z"])?;
    for path in untracked
        .split(|byte| *byte == 0)
        .filter(|path| !path.is_empty())
    {
        let name = std::str::from_utf8(path).context("untracked source path is not UTF-8")?;
        let path = workspace.join(name);
        ensure!(
            path.symlink_metadata()?.is_file(),
            "untracked desktop source is not a regular file: {name}"
        );
        hash.update(name.as_bytes());
        hash.update(file_digest(&path)?.as_bytes());
    }
    Ok(hex::encode(hash.finalize()))
}

fn configuration_identity() -> String {
    let mut hash = Sha256::new();
    for name in [
        "PATH",
        "CARGO_HOME",
        "CARGO_TARGET_DIR",
        "CARGO_BUILD_TARGET",
        "RUSTFLAGS",
        "CARGO_ENCODED_RUSTFLAGS",
        "RUSTUP_TOOLCHAIN",
        "CC",
        "CXX",
        "CFLAGS",
        "CXXFLAGS",
        "LDFLAGS",
        "PKG_CONFIG_PATH",
        "FLUTTER_ROOT",
        "PUB_HOSTED_URL",
        "PUB_CACHE",
        "PURE_REMOTE_HELPER_PREBUILT_DIR",
        "PURE_REMOTE_HELPER_BUILDER",
        "CARGO_PROFILE_DEV_DEBUG",
        "CARGO_PROFILE_DEV_OPT_LEVEL",
        "CARGO_PROFILE_DEV_CODEGEN_UNITS",
        "CARGO_PROFILE_DEV_LTO",
        "CARGO_PROFILE_RELEASE_DEBUG",
        "CARGO_PROFILE_RELEASE_OPT_LEVEL",
        "CARGO_PROFILE_RELEASE_LTO",
        "CARGO_INCREMENTAL",
        "CMAKE_GENERATOR",
        "CMAKE_TOOLCHAIN_FILE",
    ] {
        hash.update(format!("{name}={:?}\0", std::env::var_os(name)));
    }
    hex::encode(hash.finalize())
}

#[cfg(test)]
mod tests {
    use super::*;

    pub(super) fn fixture() -> Result<(TempDir, DesktopTestPreparation)> {
        let temp = tempfile::tempdir()?;
        let workspace = temp.path().canonicalize()?;
        for args in [
            vec!["init", "-q"],
            vec![
                "-c",
                "user.name=Test",
                "-c",
                "user.email=test@example.invalid",
                "commit",
                "--allow-empty",
                "-qm",
                "seed",
            ],
        ] {
            let output = Command::new("git")
                .args(args)
                .current_dir(&workspace)
                .output()?;
            ensure!(output.status.success(), "Git fixture failed");
        }
        fs::write(workspace.join(".gitignore"), "/target/\n")?;
        let helpers = workspace.join("target/helpers");
        fs::create_dir_all(&helpers)?;
        let library = workspace.join("target/bridge");
        fs::write(&library, b"prepared bridge")?;
        let bridge = serde_json::from_value(serde_json::json!({
            "dynamic_library": library,
            "debug_symbols": null
        }))?;
        let inputs = Inputs {
            host: format!("{}-{}-debug", std::env::consts::OS, std::env::consts::ARCH),
            source: source_identity(&workspace)?,
            configuration: configuration_identity(),
            xtask: std::env::current_exe()?.canonicalize()?,
            bridge,
            helpers,
            artifacts: vec![(library.clone(), file_digest(&library)?)],
            workspace,
        };
        Ok((temp, DesktopTestPreparation::own(inputs)?))
    }

    #[test]
    fn live_handoff_rejects_changed_inputs_and_expires_with_its_owner() -> Result<()> {
        let (_temp, owner) = fixture()?;
        let workspace = owner.workspace();
        for _ in 0..2 {
            DesktopTestPreparation::borrow(workspace, &owner.directory, &owner.inputs.xtask)?
                .validate()?;
        }

        fs::write(owner.bridge().dynamic_library(), b"replaced bridge")?;
        assert!(
            DesktopTestPreparation::borrow(workspace, &owner.directory, &owner.inputs.xtask)?
                .validate()
                .unwrap_err()
                .to_string()
                .contains("artifact changed")
        );
        fs::write(owner.bridge().dynamic_library(), b"prepared bridge")?;
        let added_helper = owner.helpers().join("unexpected-input");
        fs::write(&added_helper, b"not in the prepared input set")?;
        assert!(
            owner
                .validate()
                .unwrap_err()
                .to_string()
                .contains("artifact changed")
        );
        fs::remove_file(added_helper)?;
        let source = workspace.join("new_source.rs");
        fs::write(&source, "changed source")?;
        assert!(
            DesktopTestPreparation::borrow(workspace, &owner.directory, &owner.inputs.xtask)?
                .validate()
                .unwrap_err()
                .to_string()
                .contains("source changed")
        );
        fs::remove_file(source)?;
        owner.validate()?;

        // Even a leftover receipt cannot be reused after cancellation releases the lease.
        owner._owner.as_ref().unwrap().0.unlock()?;
        assert!(
            DesktopTestPreparation::borrow(workspace, &owner.directory, &owner.inputs.xtask)?
                .validate()
                .unwrap_err()
                .to_string()
                .contains("owner has exited")
        );
        let directory = owner.directory.clone();
        drop(owner);
        assert!(!directory.exists());
        Ok(())
    }

    #[test]
    fn handoff_rejects_foreign_workspace_entrypoint_and_changed_configuration() -> Result<()> {
        let (_temp, mut owner) = fixture()?;
        let foreign = tempfile::tempdir()?;
        assert!(
            DesktopTestPreparation::borrow(
                &foreign.path().canonicalize()?,
                &owner.directory,
                &owner.inputs.xtask,
            )
            .err()
            .unwrap()
            .to_string()
            .contains("different workspace")
        );
        let foreign_xtask = owner.helpers().join("another-xtask");
        assert!(
            DesktopTestPreparation::borrow(owner.workspace(), &owner.directory, &foreign_xtask)
                .err()
                .unwrap()
                .to_string()
                .contains("handoff entrypoint does not match")
        );
        let mut borrowed = DesktopTestPreparation::borrow(
            owner.workspace(),
            &owner.directory,
            &owner.inputs.xtask,
        )?;
        borrowed.inputs.xtask = foreign_xtask;
        assert!(
            borrowed
                .validate()
                .unwrap_err()
                .to_string()
                .contains("xtask entrypoint changed")
        );
        owner.inputs.configuration = "different configuration".into();
        assert!(
            owner
                .validate()
                .unwrap_err()
                .to_string()
                .contains("environment changed")
        );
        Ok(())
    }
}
