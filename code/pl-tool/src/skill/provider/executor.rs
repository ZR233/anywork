//! Project-source discovery and frozen locators over one concrete executor.
use super::*;
use crate::skill::{
    MAX_SKILL_SCAN_DEPTH, SKILL_FILE_NAME, SkillResourceBase, SkillsConfig, support_file_path,
    validate_skill_document,
};
use crate::workspace_file::{
    ExecutorWorkspaceFileBackend, WorkspaceFileBackend, WorkspaceFileReadRequest,
};
use sha2::{Digest, Sha256};

#[derive(Debug)]
pub struct ExecutorSkillProvider {
    id: SkillProviderId,
    files: Arc<ExecutorWorkspaceFileBackend>,
}
#[derive(Serialize, Deserialize)]
struct Locator {
    executor: String,
    source_root: String,
    directory: String,
}
impl ExecutorSkillProvider {
    pub fn new(files: Arc<ExecutorWorkspaceFileBackend>) -> Result<Self> {
        Ok(Self {
            id: SkillProviderId::new("executor-project")?,
            files,
        })
    }
    fn matches_platform(&self, platforms: &[String]) -> bool {
        platforms.is_empty()
            || platforms
                .iter()
                .any(|platform| platform == &self.files.executor().target_info().os)
    }
    async fn locator(&self, candidate: &SkillCandidate) -> Result<Locator> {
        let locator: Locator = serde_json::from_str(&candidate.locator)?;
        if candidate.summary.provider_id != self.id
            || locator.executor != self.files.executor().id().to_string()
        {
            return Err(PureError::ConfigError(
                "Skill locator belongs to another executor".into(),
            ));
        }
        let root = self
            .files
            .resolve_query_path(&locator.source_root, false)
            .await
            .map_err(crate::workspace_file::file_error)?;
        let directory = self
            .files
            .resolve_query_path(&locator.directory, false)
            .await
            .map_err(crate::workspace_file::file_error)?;
        if self
            .files
            .executor()
            .relative_path(&root, &directory)
            .map_err(crate::workspace_file::file_error)?
            .is_none()
        {
            return Err(PureError::ConfigError(
                "Skill locator is outside its source".into(),
            ));
        }
        Ok(locator)
    }
    fn child(&self, base: &str, relative: &str) -> Result<String> {
        let executor = self.files.executor();
        let base = executor
            .path(base)
            .map_err(crate::workspace_file::file_error)?;
        executor
            .join_path(&base, relative)
            .map(|path| path.as_str().into())
            .map_err(crate::workspace_file::file_error)
    }
    async fn read(&self, path: String) -> Result<String> {
        self.files
            .read_text(WorkspaceFileReadRequest { path, cwd: None })
            .await
    }
    fn metadata(&self, content: &str, root: &str, directory: &str) -> Result<SkillMetadata> {
        let mut metadata = validate_skill_document(content, None)?;
        let executor = self.files.executor();
        let root = executor
            .path(root)
            .map_err(crate::workspace_file::file_error)?;
        let path = executor
            .path(directory)
            .map_err(crate::workspace_file::file_error)?;
        if metadata.category.is_none() {
            let relative = executor
                .relative_path(&root, &path)
                .map_err(crate::workspace_file::file_error)?
                .ok_or_else(|| PureError::ConfigError("Skill is outside source".into()))?;
            let relative = if executor.target_info().os == "windows" {
                relative.replace('\\', "/")
            } else {
                relative
            };
            metadata.category = relative
                .rsplit_once('/')
                .map(|(category, _)| category.into())
                .filter(|category: &String| !category.is_empty());
        }
        metadata.source = SkillSourceKind::Project;
        metadata.provider_id = self.id.clone();
        if executor.is_local() {
            metadata.path = path.as_str().into();
            metadata.resource_base = SkillResourceBase::Directory {
                path: metadata.path.clone(),
            };
        } else {
            metadata.resource_base = SkillResourceBase::Opaque {
                description: path.as_str().into(),
            };
        }
        Ok(metadata)
    }
    async fn scan(&self, root: String, cancellation: &CancellationToken) -> Result<Vec<String>> {
        let mut directories = vec![(root, 0usize)];
        let mut documents = Vec::new();
        while let Some((directory, depth)) = directories.pop() {
            ensure_active(cancellation)?;
            let mut entries = self.files.open_directory(directory).await?;
            let mut children = Vec::new();
            let mut document = None;
            while let Some(entry) = entries.next().await? {
                ensure_active(cancellation)?;
                if entry.is_symlink {
                    continue;
                }
                if entry.name == SKILL_FILE_NAME && !entry.is_directory {
                    if self
                        .files
                        .inspect_path(entry.path.clone(), None)
                        .await
                        .map_err(crate::workspace_file::file_error)?
                        .is_some_and(|stat| stat.is_file)
                    {
                        document = Some(entry.path);
                    }
                } else if entry.is_directory
                    && depth < MAX_SKILL_SCAN_DEPTH
                    && !crate::skill::scanning::skip_directory_name(&entry.name)
                {
                    children.push((entry.path, depth + 1));
                }
            }
            let contains_skill = document.is_some();
            if let Some(document) = document {
                documents.push(document);
            }
            // A Skill's resources cannot contribute nested Skills. The configured
            // source root remains a container, matching the existing scan contract.
            if depth == 0 || !contains_skill {
                directories.extend(children);
            }
        }
        documents.sort();
        documents.dedup();
        Ok(documents)
    }
}
impl SkillProvider for ExecutorSkillProvider {
    fn id(&self) -> &SkillProviderId {
        &self.id
    }
    fn discovery_identity(&self) -> String {
        self.files.binding_identity()
    }
    fn project_directory(&self, config: &SkillsConfig) -> Result<Option<PathBuf>> {
        crate::skill::validate_skills_config(config)?;
        Ok(Some(
            self.child(self.files.canonical_path(), &config.project_dir)?
                .into(),
        ))
    }
    fn list<'a>(
        &'a self,
        request: SkillProviderRequest,
    ) -> Pin<Box<dyn Future<Output = Result<SkillProviderObservation>> + Send + 'a>> {
        let stop = request.cancellation.clone();
        Box::pin(observe(stop, async move {
            ensure_active(&request.cancellation)?;
            crate::skill::validate_skills_config(&request.config)?;
            let source = self
                .files
                .resolve_query_path(&request.config.project_dir, false)
                .await
                .map_err(crate::workspace_file::file_error)?;
            if self
                .files
                .inspect_path(source.as_str().into(), None)
                .await
                .map_err(crate::workspace_file::file_error)?
                .is_none()
            {
                return Ok(SkillProviderObservation::empty());
            }
            let disabled: BTreeSet<_> = request
                .config
                .disabled
                .iter()
                .map(|name| name.to_ascii_lowercase())
                .collect();
            let mut observation = SkillProviderObservation::empty();
            for (local_order, document) in self
                .scan(source.as_str().into(), &request.cancellation)
                .await?
                .into_iter()
                .enumerate()
            {
                let executor = self.files.executor();
                let document = self
                    .files
                    .resolve_query_path(&document, true)
                    .await
                    .map_err(crate::workspace_file::file_error)?;
                let directory = executor
                    .parent_path(&document)
                    .map_err(crate::workspace_file::file_error)?
                    .ok_or_else(|| PureError::ConfigError("Skill document has no parent".into()))?;
                let content = self.read(document.as_str().into()).await?;
                match self.metadata(&content, source.as_str(), directory.as_str()) {
                    Ok(metadata)
                        if !disabled.contains(&metadata.name.to_ascii_lowercase())
                            && self.matches_platform(&metadata.platforms) =>
                    {
                        observation.candidates.push(SkillCandidate {
                            summary: SkillSummary::from(metadata),
                            revision: revision(&content),
                            rank: 0,
                            local_order,
                            locator: serde_json::to_string(&Locator {
                                executor: executor.id().to_string(),
                                source_root: source.as_str().into(),
                                directory: directory.as_str().into(),
                            })?,
                        });
                    }
                    Ok(_) => {}
                    Err(error) => observation.warnings.push(error.to_string()),
                }
            }
            Ok(observation)
        }))
    }
    fn load<'a>(
        &'a self,
        candidate: &'a SkillCandidate,
        cancellation: CancellationToken,
    ) -> Pin<Box<dyn Future<Output = Result<SkillDefinition>> + Send + 'a>> {
        Box::pin(observe(cancellation.clone(), async move {
            ensure_active(&cancellation)?;
            let locator = self.locator(candidate).await?;
            let content = self
                .read(self.child(&locator.directory, SKILL_FILE_NAME)?)
                .await?;
            let metadata = self.metadata(&content, &locator.source_root, &locator.directory)?;
            if !self.matches_platform(&metadata.platforms) {
                return Err(PureError::ConfigError(
                    "Skill is no longer applicable on target platform".into(),
                ));
            }
            Ok(SkillDefinition {
                summary: SkillSummary::from(metadata),
                revision: revision(&content),
                content,
            })
        }))
    }
    fn read_resource<'a>(
        &'a self,
        candidate: &'a SkillCandidate,
        relative: &'a str,
        cancellation: CancellationToken,
    ) -> Pin<Box<dyn Future<Output = Result<String>> + Send + 'a>> {
        Box::pin(observe(cancellation.clone(), async move {
            ensure_active(&cancellation)?;
            let locator = self.locator(candidate).await?;
            let relative = support_file_path(relative)?;
            let relative = relative
                .to_str()
                .ok_or_else(|| PureError::ConfigError("Skill resource path is not UTF-8".into()))?;
            let relative = if self.files.executor().target_info().os == "windows" {
                relative.to_owned()
            } else {
                relative.replace(std::path::MAIN_SEPARATOR, "/")
            };
            self.read(self.child(&locator.directory, &relative)?).await
        }))
    }
    fn record_model_view<'a>(
        &'a self,
        candidate: &'a SkillCandidate,
        cancellation: CancellationToken,
    ) -> Pin<Box<dyn Future<Output = Result<()>> + Send + 'a>> {
        Box::pin(observe(cancellation.clone(), async move {
            // Preserve the existing local project annotation feature; unifying reads
            // does not introduce new writes to remote/read-only Skill sources.
            if !self.files.executor().is_local() {
                return Ok(());
            }
            ensure_active(&cancellation)?;
            let locator = self.locator(candidate).await?;
            let runtime =
                crate::workspace::ToolWorkspace::new(crate::workspace::AgentWorkspace::local(
                    std::path::Path::new(self.files.canonical_path()),
                ));
            let _guard = runtime.write_lock().await;
            let path = self.child(&locator.directory, crate::skill::USAGE_FILE_NAME)?;
            let mut usage: crate::skill::SkillUsage = if self
                .files
                .inspect_path(path.clone(), None)
                .await
                .map_err(crate::workspace_file::file_error)?
                .is_some()
            {
                serde_json::from_str(&self.read(path.clone()).await?)?
            } else {
                crate::skill::SkillUsage::agent_created(crate::unix_seconds())
            };
            usage.views = usage
                .views
                .checked_add(1)
                .ok_or_else(|| PureError::ConfigError("Skill view counter overflow".into()))?;
            usage.uses = usage
                .uses
                .checked_add(1)
                .ok_or_else(|| PureError::ConfigError("Skill use counter overflow".into()))?;
            usage.updated_at = crate::unix_seconds();
            usage.last_viewed_at = Some(usage.updated_at);
            ensure_active(&cancellation)?;
            self.files
                .write_bytes_atomic(path, None, serde_json::to_string_pretty(&usage)?.as_bytes())
                .await
        }))
    }
}
fn ensure_active(cancellation: &CancellationToken) -> Result<()> {
    if cancellation.is_cancelled() {
        Err(cancelled_error())
    } else {
        Ok(())
    }
}
fn revision(content: &str) -> String {
    hex::encode(Sha256::digest(content.as_bytes()))
}

async fn observe<T>(
    cancellation: CancellationToken,
    operation: impl Future<Output = Result<T>>,
) -> Result<T> {
    // Dropping a target FS observation resets only that request. Already-started
    // native IO remains owned by the executor's registered task, not a detached worker.
    tokio::select! { biased; _ = cancellation.cancelled() => Err(cancelled_error()), result = operation => result }
}
