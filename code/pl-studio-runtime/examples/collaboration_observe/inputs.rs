//! Preserve user configuration; only explicit new-Thread parameters may override its defaults.
use super::evidence::Evidence;
use super::git::{git_value, initialize_repository};
use anyhow::{Context, Result};
use pl_protocol::{
    DelegationMode, DelegationPreference, ThreadWorkspaceMode, studio::NewThreadModelRoute,
};
use pl_studio_runtime::{ConfigStore, STUDIO_CONFIG_SCHEMA_VERSION};
use serde::Deserialize;
use std::{
    collections::BTreeMap,
    path::{Path, PathBuf},
};

pub struct Inputs {
    pub home: PathBuf,
    pub workspace: PathBuf,
    pub mode: String,
    pub workspace_mode: ThreadWorkspaceMode,
    pub delegation_mode: Option<DelegationMode>,
    pub delegation_preference: Option<DelegationPreference>,
    pub route_override: Option<NewThreadModelRoute>,
    pub prompt: String,
}

pub fn require_linux() -> Result<()> {
    anyhow::ensure!(
        cfg!(target_os = "linux"),
        "collaboration_observe supports Linux only; no configuration or business process was opened"
    );
    Ok(())
}

pub fn observation_seconds() -> Result<u64> {
    let seconds = env("ANYWORK_OBSERVATION_SECONDS")?
        .map(|value| value.parse::<u64>())
        .transpose()?
        .unwrap_or(180);
    anyhow::ensure!(
        (1..=1800).contains(&seconds),
        "observation seconds must be 1..=1800"
    );
    Ok(seconds)
}

pub fn artifact_directory() -> Result<PathBuf> {
    let path = std::env::var_os("ANYWORK_WORKFLOW_ARTIFACT_DIR")
        .filter(|value| !value.is_empty())
        .context("ANYWORK_WORKFLOW_ARTIFACT_DIR is required")?;
    std::fs::create_dir_all(&path)?;
    Ok(std::fs::canonicalize(path)?)
}

fn env(name: &str) -> Result<Option<String>> {
    match std::env::var(name) {
        Ok(value) => {
            anyhow::ensure!(!value.trim().is_empty(), "{name} must be nonempty");
            Ok(Some(value))
        }
        Err(std::env::VarError::NotPresent) => Ok(None),
        Err(error) => Err(error).with_context(|| format!("read {name}")),
    }
}

impl Inputs {
    pub async fn prepare(evidence: &Evidence, scene: &super::Boundary) -> Result<Self> {
        require_linux()?;
        scene.check()?;
        let mode = env("ANYWORK_OBSERVATION_MODE")?.unwrap_or_else(|| "mode.simple".into());
        anyhow::ensure!(
            matches!(mode.as_str(), "mode.simple" | "mode.task"),
            "only builtin mode.simple and mode.task are supported; custom mode resources are not copied"
        );
        let delegation_mode = env("ANYWORK_OBSERVATION_DELEGATION_MODE")?
            .map(|value| match value.as_str() {
                "profile" => Ok(DelegationMode::Profile),
                "automatic" => Ok(DelegationMode::Automatic),
                _ => anyhow::bail!("delegation mode must be profile or automatic"),
            })
            .transpose()?;
        let delegation_preference = env("ANYWORK_OBSERVATION_DELEGATION_PREFERENCE")?
            .map(|value| match value.as_str() {
                "economy" => Ok(DelegationPreference::Economy),
                "balanced" => Ok(DelegationPreference::Balanced),
                "fast" => Ok(DelegationPreference::Fast),
                _ => anyhow::bail!("delegation preference must be economy, balanced or fast"),
            })
            .transpose()?;
        let workspace_mode = match env("ANYWORK_OBSERVATION_WORKSPACE_MODE")?.as_deref() {
            None | Some("local") => ThreadWorkspaceMode::Local,
            Some("worktree") => ThreadWorkspaceMode::Worktree,
            _ => anyhow::bail!("workspace mode must be local or worktree"),
        };
        let effort = env("ANYWORK_OBSERVATION_EFFORT")?;
        let route_override = match (
            env("ANYWORK_OBSERVATION_ACCOUNT")?,
            env("ANYWORK_OBSERVATION_MODEL")?,
        ) {
            (None, None) => None,
            (Some(account_id), Some(model_id)) => Some(NewThreadModelRoute {
                account_id,
                model_id,
                effort: effort.clone(),
            }),
            _ => anyhow::bail!(
                "ANYWORK_OBSERVATION_ACCOUNT and ANYWORK_OBSERVATION_MODEL must be set together"
            ),
        };
        let prompt = match std::env::var_os("ANYWORK_OBSERVATION_PROMPT") {
            Some(path) => std::fs::read_to_string(path)?,
            None => "请派两个 fresh-context explorer 分别解释文件所有权和 Turn 生命周期。详细、自包含地派发。一个自然 final，另一个 finish_turn。等待完整报告，阅读后总结；不修改文件，不提交计划，不询问用户。".into(),
        };
        evidence.raw("input-prompt.txt", "submitted prompt", prompt.as_bytes())?;
        let home = evidence.root().join("studio-home");
        std::fs::create_dir(&home)
            .context("studio-home must be new; never reuse an observation home")?;
        scene.check()?;
        copy_configuration(evidence)?;
        let workspace = match std::env::var_os("ANYWORK_OBSERVATION_WORKSPACE") {
            Some(path) => {
                let workspace = std::fs::canonicalize(path)?;
                anyhow::ensure!(
                    workspace.starts_with(evidence.root()) && workspace != evidence.root(),
                    "fixture must be a directory strictly within the artifact directory"
                );
                anyhow::ensure!(
                    workspace.is_dir() && !workspace.starts_with(&home),
                    "fixture must not be Studio home"
                );
                check_fixture_links(&workspace, evidence.root())?;
                workspace
            }
            None => {
                let workspace = tempfile::Builder::new()
                    .prefix("workspace-")
                    .tempdir_in(evidence.root())?
                    .keep();
                initialize_repository(evidence, &workspace, scene).await?;
                workspace
            }
        };
        if workspace_mode == ThreadWorkspaceMode::Worktree {
            git_value(
                evidence,
                &workspace,
                "git/preparation/head",
                &["rev-parse", "--verify", "HEAD"],
                scene,
            )
            .await
            .context(
                "worktree fixture requires an existing valid HEAD; it is never auto-committed",
            )?;
            for (name, args) in [
                ("directory", ["rev-parse", "--absolute-git-dir"]),
                ("common", ["rev-parse", "--git-common-dir"]),
            ] {
                let output = git_value(
                    evidence,
                    &workspace,
                    &format!("git/preparation/{name}"),
                    &args,
                    scene,
                )
                .await?;
                let path = PathBuf::from(String::from_utf8(output)?.trim());
                let path = if path.is_absolute() {
                    path
                } else {
                    workspace.join(path)
                };
                anyhow::ensure!(
                    std::fs::canonicalize(path)?.starts_with(evidence.root()),
                    "fixture Git metadata must remain within the artifact directory"
                );
            }
        }
        evidence.raw(
            "workspace-path.txt",
            "workspace",
            workspace.to_string_lossy().as_bytes(),
        )?;
        let decisions = evidence.root().join("decisions");
        match std::fs::symlink_metadata(&decisions) {
            Ok(metadata) => anyhow::ensure!(
                metadata.is_dir() && !metadata.file_type().is_symlink(),
                "decisions must be a real directory"
            ),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                std::fs::create_dir(&decisions)?
            }
            Err(error) => return Err(error.into()),
        }
        evidence.check_disk_budget()?;
        scene.check()?;
        Ok(Self {
            home,
            workspace,
            mode,
            workspace_mode,
            delegation_mode,
            delegation_preference,
            route_override,
            prompt,
        })
    }
}

#[derive(Deserialize)]
struct ConfigGuard {
    schema_version: u32,
    models: ModelGuard,
}
#[derive(Deserialize)]
struct ModelGuard {
    accounts: BTreeMap<String, AccountGuard>,
}
#[derive(Deserialize)]
struct AccountGuard {
    bearer_token: Option<String>,
}

fn copy_configuration(evidence: &Evidence) -> Result<()> {
    let installed = ConfigStore::default_app()?;
    // Do not hydrate credentials, reserialize settings, or select/prune accounts in this process.
    let content = std::fs::read(installed.paths().config_file())?;
    let guard: ConfigGuard = toml::from_str(std::str::from_utf8(&content)?).map_err(|_| {
        anyhow::anyhow!(
            "cannot validate configuration header/credential fields; raw TOML is private"
        )
    })?;
    anyhow::ensure!(
        (23..=STUDIO_CONFIG_SCHEMA_VERSION).contains(&guard.schema_version),
        "observation requires schema 23..={STUDIO_CONFIG_SCHEMA_VERSION} without credential migration"
    );
    anyhow::ensure!(
        guard
            .models
            .accounts
            .values()
            .all(|account| account.bearer_token.is_none()),
        "inline account credentials are forbidden; observation never imports credentials"
    );
    evidence.raw(
        "inputs/config.toml",
        "immutable unhydrated original config bytes",
        &content,
    )?;
    evidence.raw(
        "studio-home/config.toml",
        "unhydrated original config bytes",
        &content,
    )?;
    let agents = installed.paths().agents_dir();
    match std::fs::symlink_metadata(&agents) {
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(error.into()),
        Ok(metadata) => anyhow::ensure!(
            metadata.is_dir() && !metadata.file_type().is_symlink(),
            "user agents directory must not be a symlink"
        ),
    }
    for entry in std::fs::read_dir(agents)? {
        let entry = entry?;
        anyhow::ensure!(
            !entry.file_type()?.is_symlink(),
            "user agent symlinks are not copied"
        );
        if entry
            .path()
            .extension()
            .is_some_and(|extension| extension == "toml")
            && entry.file_type()?.is_file()
        {
            let name = entry
                .file_name()
                .into_string()
                .map_err(|_| anyhow::anyhow!("agent filename must be Unicode"))?;
            let content = std::fs::read(entry.path())?;
            evidence.raw(
                &format!("inputs/agents/{name}"),
                "immutable user child Profile",
                &content,
            )?;
            evidence.raw(
                &format!("studio-home/agents/{name}"),
                "user child Profile",
                &content,
            )?;
        }
    }
    Ok(())
}

fn check_fixture_links(workspace: &Path, artifacts: &Path) -> Result<()> {
    let mut pending = vec![workspace.to_path_buf()];
    let mut count = 0;
    while let Some(directory) = pending.pop() {
        for entry in std::fs::read_dir(directory)? {
            let entry = entry?;
            count += 1;
            anyhow::ensure!(count <= 100_000, "fixture entry budget exceeded");
            let kind = entry.file_type()?;
            if kind.is_symlink() {
                anyhow::ensure!(
                    std::fs::canonicalize(entry.path())?.starts_with(artifacts),
                    "fixture symlink escapes artifact directory"
                );
            } else if kind.is_dir() {
                pending.push(entry.path());
            }
        }
    }
    Ok(())
}
