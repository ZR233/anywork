use std::collections::BTreeSet;
use std::path::PathBuf;
use std::pin::Pin;

use pl_protocol::{PureError, Result};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tokio_util::sync::CancellationToken;

use super::{
    SkillCandidate, SkillDefinition, SkillProvider, SkillProviderId, SkillProviderObservation,
    SkillProviderRequest, cancelled_error,
};
use crate::skill::scanning::{metadata_from_content, scan_skill_files};
use crate::skill::util::platform_matches;
use crate::skill::{SkillMetadata, SkillResourceBase, SkillSourceKind, SkillSummary};
use crate::workspace::path_safety::{metadata_if_real, validate_existing_path};

const FILESYSTEM_PROVIDER_ID: &str = "local-filesystem";

/// Local directory provider preserving Pure's on-disk layout and path-safety rules.
#[derive(Debug)]
pub struct FileSystemSkillProvider {
    id: SkillProviderId,
    sources: FileSystemSkillSources,
}

#[derive(Debug, Clone)]
enum FileSystemSkillSources {
    Configured(crate::skill::SkillSearchOptions),
    Explicit(Vec<SkillDirectorySource>),
}

/// Provider-owned trust roots travel with the frozen locator, not a current filesystem lookup.
#[derive(Debug, Serialize, Deserialize)]
struct FileSystemSkillLocator {
    skill_dir: PathBuf,
    source_root: PathBuf,
    trusted_root: PathBuf,
}

impl FileSystemSkillLocator {
    fn from_candidate(candidate: &SkillCandidate) -> Result<Self> {
        let locator: Self = serde_json::from_str(&candidate.locator)?;
        if candidate.summary.resource_base
            != (SkillResourceBase::Directory {
                path: locator.skill_dir.clone(),
            })
        {
            return Err(PureError::ConfigError(
                "filesystem Skill locator does not match its resource base".to_string(),
            ));
        }
        Ok(locator)
    }

    fn validate(&self, path: &std::path::Path) -> Result<()> {
        if !metadata_if_real(&self.trusted_root)
            .map_err(|error| PureError::ConfigError(error.to_string()))?
            .is_some_and(|metadata| metadata.is_dir())
        {
            return Err(PureError::ConfigError(format!(
                "Skill trust root is missing, linked or not a directory: {}",
                self.trusted_root.display()
            )));
        }
        validate_existing_path(&self.trusted_root, path)
            .and_then(|()| validate_existing_path(&self.source_root, path))
            .map_err(|error| PureError::ConfigError(error.to_string()))
    }
}

/// 宿主显式注册的只读 Skill 目录来源。
///
/// 目录按传入顺序决定同名 Skill 的优先级，靠前来源优先。每个来源仍由 PL 统一负责
/// SKILL.md 校验、平台过滤、revision 冻结和支持资源路径安全。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillDirectorySource {
    pub root: PathBuf,
    pub source: crate::skill::SkillSourceKind,
}

impl SkillDirectorySource {
    pub fn new(root: impl Into<PathBuf>, source: crate::skill::SkillSourceKind) -> Self {
        Self {
            root: root.into(),
            source,
        }
    }
}

impl FileSystemSkillProvider {
    /// Creates the configured desktop User/System/External read-only Provider.
    pub fn configured_readonly() -> Self {
        Self::configured_readonly_with_options(Default::default())
    }

    pub fn configured_readonly_with_options(options: crate::skill::SkillSearchOptions) -> Self {
        Self {
            id: SkillProviderId(FILESYSTEM_PROVIDER_ID.to_string()),
            sources: FileSystemSkillSources::Configured(options),
        }
    }

    /// 创建一个使用宿主显式目录集合的 Provider。
    ///
    /// 该模式不读取 `SkillProviderRequest` 中的默认 project/user/system 路径，只复用其中
    /// 的 enable/disable 配置与取消令牌。
    pub fn from_directories(
        id: impl Into<String>,
        sources: Vec<SkillDirectorySource>,
    ) -> Result<Self> {
        Ok(Self {
            id: SkillProviderId::new(id)?,
            sources: FileSystemSkillSources::Explicit(sources),
        })
    }
}

impl SkillProvider for FileSystemSkillProvider {
    fn id(&self) -> &SkillProviderId {
        &self.id
    }

    fn discovery_identity(&self) -> String {
        let mut digest = Sha256::new();
        let mut part = |bytes: &[u8]| {
            digest.update((bytes.len() as u64).to_le_bytes());
            digest.update(bytes);
        };
        part(b"pl-tool/filesystem-skill-source/v1");
        part(self.id.as_str().as_bytes());
        match &self.sources {
            FileSystemSkillSources::Configured(options) => {
                part(b"configured");
                part(&[u8::from(options.include_default_user_dir)]);
                for directory in &options.additional_dirs {
                    part(directory.as_os_str().as_encoded_bytes());
                }
            }
            FileSystemSkillSources::Explicit(sources) => {
                part(b"explicit");
                for source in sources {
                    part(super::source_label(source.source).as_bytes());
                    part(source.root.as_os_str().as_encoded_bytes());
                }
            }
        }
        format!("filesystem:{}", hex::encode(digest.finalize()))
    }

    fn list<'a>(
        &'a self,
        request: SkillProviderRequest,
    ) -> Pin<Box<dyn Future<Output = Result<SkillProviderObservation>> + Send + 'a>> {
        let id = self.id.clone();
        let sources = self.sources.clone();
        Box::pin(async move {
            tokio::task::spawn_blocking(move || list_local_skills(&id, request, sources))
                .await
                .map_err(|error| {
                    PureError::ConfigError(format!(
                        "filesystem skill discovery task failed: {error}"
                    ))
                })?
        })
    }

    fn load<'a>(
        &'a self,
        candidate: &'a SkillCandidate,
        cancellation: CancellationToken,
    ) -> Pin<Box<dyn Future<Output = Result<SkillDefinition>> + Send + 'a>> {
        let candidate = candidate.clone();
        Box::pin(async move {
            tokio::task::spawn_blocking(move || load_local_skill(&candidate, cancellation))
                .await
                .map_err(|error| {
                    PureError::ConfigError(format!("filesystem skill load task failed: {error}"))
                })?
        })
    }

    fn read_resource<'a>(
        &'a self,
        candidate: &'a SkillCandidate,
        relative_path: &'a str,
        cancellation: CancellationToken,
    ) -> Pin<Box<dyn Future<Output = Result<String>> + Send + 'a>> {
        let candidate = candidate.clone();
        let relative_path = relative_path.to_string();
        Box::pin(async move {
            tokio::task::spawn_blocking(move || {
                read_local_resource(&candidate, &relative_path, cancellation)
            })
            .await
            .map_err(|error| {
                PureError::ConfigError(format!("filesystem skill resource task failed: {error}"))
            })?
        })
    }
}

fn load_local_skill(
    candidate: &SkillCandidate,
    cancellation: CancellationToken,
) -> Result<SkillDefinition> {
    if cancellation.is_cancelled() {
        return Err(cancelled_error());
    }
    let locator = FileSystemSkillLocator::from_candidate(candidate)?;
    locator.validate(&locator.skill_dir.join(crate::skill::SKILL_FILE_NAME))?;
    let skill = SkillMetadata::from(candidate.summary.clone());
    let content = crate::skill::read_skill_file(&skill, None)?.content;
    let mut metadata =
        crate::skill::validate_skill_document(&content, Some(&candidate.summary.name))?;
    if !platform_matches(&metadata.platforms) {
        return Err(PureError::ConfigError(format!(
            "skill is no longer applicable on this platform: {}",
            metadata.name
        )));
    }
    metadata.source = candidate.summary.source;
    metadata.path = locator.skill_dir;
    metadata.provider_id = candidate.summary.provider_id.clone();
    metadata.resource_base = SkillResourceBase::Directory {
        path: metadata.path.clone(),
    };
    let summary = SkillSummary::from(metadata);
    Ok(SkillDefinition {
        summary,
        revision: content_revision(&content),
        content,
    })
}

fn read_local_resource(
    candidate: &SkillCandidate,
    relative_path: &str,
    cancellation: CancellationToken,
) -> Result<String> {
    if cancellation.is_cancelled() {
        return Err(cancelled_error());
    }
    let locator = FileSystemSkillLocator::from_candidate(candidate)?;
    let relative = crate::skill::support_file_path(relative_path)?;
    locator.validate(&locator.skill_dir.join(relative))?;
    let metadata = SkillMetadata::from(candidate.summary.clone());
    crate::skill::read_skill_file(&metadata, Some(relative_path)).map(|read| read.content)
}

fn list_local_skills(
    provider_id: &SkillProviderId,
    request: SkillProviderRequest,
    source_policy: FileSystemSkillSources,
) -> Result<SkillProviderObservation> {
    if request.cancellation.is_cancelled() {
        return Err(cancelled_error());
    }
    let (sources, first_rank, required_roots) = match source_policy {
        FileSystemSkillSources::Explicit(sources) => (sources, 0, Vec::new()),
        FileSystemSkillSources::Configured(options) => (
            crate::skill::resolve_local_readonly_skill_sources(
                &request.config,
                request.system_dir.as_deref(),
                &options,
            )?,
            1,
            options.additional_dirs,
        ),
    };
    let sources = sources
        .into_iter()
        .enumerate()
        .map(|(rank, source)| {
            Ok((
                source.root,
                source.source,
                u16::try_from(rank)
                    .ok()
                    .and_then(|rank| rank.checked_add(first_rank))
                    .ok_or_else(|| PureError::ConfigError("too many Skill sources".into()))?,
            ))
        })
        .collect::<Result<Vec<_>>>()?;
    let disabled = request
        .config
        .disabled
        .iter()
        .map(|name| name.to_ascii_lowercase())
        .collect::<BTreeSet<_>>();
    let mut observation = SkillProviderObservation::empty();
    let mut local_order = 0;
    for (root, source_kind, rank) in sources {
        tracing::debug!(source = ?source_kind, path = %root.display(), rank, "discovering Skill source");
        if source_kind == SkillSourceKind::System && !request.config.system.enabled {
            continue;
        }
        if request.cancellation.is_cancelled() {
            return Err(cancelled_error());
        }
        let scan = scan_skill_files(&root, &request.cancellation, required_roots.contains(&root))?;
        observation.complete &= scan.complete;
        observation.warnings.extend(scan.warnings);
        for skill_file in scan.files {
            if request.cancellation.is_cancelled() {
                return Err(cancelled_error());
            }
            let trusted_root = &root;
            let locator = FileSystemSkillLocator {
                skill_dir: skill_file
                    .parent()
                    .ok_or_else(|| {
                        PureError::ConfigError("Skill document has no parent directory".to_string())
                    })?
                    .to_path_buf(),
                source_root: root.clone(),
                trusted_root: trusted_root.clone(),
            };
            locator.validate(&skill_file)?;
            let content = std::fs::read_to_string(&skill_file).map_err(|error| {
                PureError::ConfigError(format!(
                    "failed to read skill {}: {error}",
                    skill_file.display()
                ))
            })?;
            match metadata_from_content(&content, &skill_file, &root, source_kind) {
                Ok(mut metadata) => {
                    if disabled.contains(&metadata.name.to_ascii_lowercase())
                        || !platform_matches(&metadata.platforms)
                    {
                        continue;
                    }
                    metadata.provider_id = provider_id.clone();
                    metadata.resource_base = SkillResourceBase::Directory {
                        path: metadata.path.clone(),
                    };
                    observation.candidates.push(SkillCandidate {
                        summary: SkillSummary::from(metadata.clone()),
                        locator: serde_json::to_string(&locator)?,
                        revision: content_revision(&content),
                        rank,
                        local_order,
                    });
                    local_order += 1;
                }
                Err(error) => {
                    observation.warnings.push(error.to_string());
                }
            }
        }
    }
    Ok(observation)
}

fn content_revision(content: &str) -> String {
    hex::encode(Sha256::digest(content.as_bytes()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::skill::{SkillRegistry, SkillSearchOptions, SkillsConfig};
    use anyhow::Result;
    use std::{path::Path, sync::Arc};

    fn skill(root: &Path, name: &str, description: &str) -> Result<()> {
        let directory = root.join(name);
        std::fs::create_dir_all(&directory)?;
        std::fs::write(
            directory.join("SKILL.md"),
            format!("---\nname: {name}\ndescription: {description}\n---\n{description}\n"),
        )?;
        Ok(())
    }

    // HOME is changed only on a child process; parallel tests never mutate process environment.
    fn isolated(test_name: &str, without_home: bool) -> Result<Option<tempfile::TempDir>> {
        if std::env::var_os("ANYWORK_SKILL_SEARCH_TEST_CHILD").is_some() {
            return Ok(None);
        }
        let directory = tempfile::tempdir()?;
        let mut command = std::process::Command::new(std::env::current_exe()?);
        command
            .args(["--exact", test_name, "--nocapture"])
            .env("ANYWORK_SKILL_SEARCH_TEST_CHILD", "1");
        if without_home {
            command.env_remove("HOME").env_remove("USERPROFILE");
        } else {
            command
                .env("HOME", directory.path())
                .env("USERPROFILE", directory.path());
        }
        let output = command.output()?;
        assert!(
            output.status.success(),
            "{}\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
        Ok(Some(directory))
    }

    #[tokio::test]
    async fn configured_sources_follow_project_user_system_config_cli_priority() -> Result<()> {
        if isolated("skill::provider::filesystem::tests::configured_sources_follow_project_user_system_config_cli_priority", false)?.is_some() { return Ok(()); }
        let root = tempfile::tempdir()?;
        let workspace = root.path().join("workspace");
        let project = workspace.join(".agents/skills");
        let user = crate::skill::util::agents_user_skills_dir()?;
        let system = root.path().join("system");
        let configured = root.path().join("configured");
        let extra = root.path().join("extra");
        let later = root.path().join("later");
        let roots = [&project, &user, &system, &configured, &extra, &later];
        for (index, directory) in roots.iter().enumerate() {
            skill(
                directory,
                if index % 2 == 0 { "Shared" } else { "shared" },
                &format!("layer-{index}"),
            )?;
        }
        let options = SkillSearchOptions::resolve(
            true,
            [
                extra.clone(),
                root.path().join("extra/../extra"),
                later.clone(),
            ],
            root.path(),
        )?;
        assert_eq!(options.additional_dirs, [extra.clone(), later.clone()]);
        let config = SkillsConfig {
            external_dirs: vec![configured.to_string_lossy().into_owned()],
            ..Default::default()
        };
        let registry = SkillRegistry::new();
        let _registration = registry.register(Arc::new(
            FileSystemSkillProvider::configured_readonly_with_options(options),
        ))?;
        let files = Arc::new(crate::workspace_file::ExecutorWorkspaceFileBackend::new(
            pl_remote_helper::Executor::local()?,
            workspace.to_str().unwrap(),
        )?);
        let request = || SkillProviderRequest {
            workspace_root: workspace.clone(),
            config: config.clone(),
            system_dir: Some(system.clone()),
            cancellation: CancellationToken::new(),
        };
        for (index, directory) in roots.iter().enumerate() {
            let catalog = registry.discover_project(request(), files.clone()).await?;
            assert!(
                catalog.snapshot().complete,
                "{:?}",
                catalog.snapshot().warnings
            );
            let winner = catalog.find("SHARED").unwrap();
            assert_eq!(winner.description, format!("layer-{index}"));
            let name = if index % 2 == 0 { "Shared" } else { "shared" };
            std::fs::remove_dir_all(directory.join(name))?;
        }
        let other_workspace = root.path().join("other-workspace");
        skill(
            &other_workspace.join(".agents/skills"),
            "other-project",
            "other-project",
        )?;
        let other_files = Arc::new(crate::workspace_file::ExecutorWorkspaceFileBackend::new(
            pl_remote_helper::Executor::local()?,
            other_workspace.to_str().unwrap(),
        )?);
        let mut other_request = request();
        other_request.workspace_root = other_workspace;
        assert!(
            registry
                .discover_project(other_request, other_files)
                .await?
                .find("other-project")
                .is_some()
        );
        assert!(
            registry
                .discover_project(request(), files)
                .await?
                .find("other-project")
                .is_none()
        );
        let options = SkillSearchOptions::resolve(false, [user.clone()], root.path())?;
        skill(&user, "explicit-user", "explicit-user")?;
        let provider = FileSystemSkillProvider::configured_readonly_with_options(options);
        let observed = provider.list(request()).await?;
        assert!(
            observed
                .candidates
                .iter()
                .any(|candidate| candidate.summary.name == "explicit-user"
                    && candidate.summary.source == SkillSourceKind::External)
        );
        Ok(())
    }

    #[tokio::test]
    async fn explicit_sources_without_home_stay_required_and_frozen() -> Result<()> {
        if isolated("skill::provider::filesystem::tests::explicit_sources_without_home_stay_required_and_frozen", true)?.is_some() { return Ok(()); }
        let root = tempfile::tempdir()?;
        let extra = root.path().join("extra");
        skill(&extra, "visible", "original")?;
        let options = SkillSearchOptions::resolve(false, [extra.clone()], root.path())?;
        let provider = FileSystemSkillProvider::configured_readonly_with_options(options.clone());
        assert_ne!(
            provider.discovery_identity(),
            FileSystemSkillProvider::configured_readonly().discovery_identity()
        );
        let registry = SkillRegistry::new();
        let _registration = registry.register(Arc::new(provider))?;
        let request = SkillProviderRequest {
            workspace_root: root.path().into(),
            config: SkillsConfig {
                system: crate::skill::SystemSkillsConfig { enabled: false },
                ..Default::default()
            },
            system_dir: None,
            cancellation: CancellationToken::new(),
        };
        let catalog = registry.discover(request).await?;
        assert!(catalog.snapshot().complete);
        assert!(catalog.find("visible").is_some());
        let frozen = catalog.discovery_sources();
        let other = root.path().join("other");
        skill(&other, "unregistered-at-capture", "later")?;
        let _later = registry.register(Arc::new(FileSystemSkillProvider::from_directories(
            "late-provider",
            vec![SkillDirectorySource::new(other, SkillSourceKind::External)],
        )?))?;
        assert!(
            frozen
                .discover(CancellationToken::new())
                .await?
                .find("unregistered-at-capture")
                .is_none()
        );
        std::fs::remove_dir_all(&extra)?;
        assert!(frozen.discover(CancellationToken::new()).await.is_err());
        assert!(SkillSearchOptions::resolve(false, [extra], root.path()).is_err());
        Ok(())
    }
}
