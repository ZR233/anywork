//! Bot-owned execution roots; historical session storage retains its canonical identity.
use super::{
    BotRuntime,
    config::BotConfigFile,
    protocol::error::{FeishuError, FeishuErrorKind},
};

#[derive(serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CreatedWorkspace {
    schema_version: u32,
    thread_id: String,
}

fn completion_matches(
    text: &str,
    thread_id: &str,
    source: &std::path::Path,
) -> std::io::Result<bool> {
    if text == source.to_string_lossy() {
        return Ok(true);
    }
    let created: CreatedWorkspace = serde_json::from_str(text).map_err(std::io::Error::other)?;
    Ok(created.schema_version == 1 && created.thread_id == thread_id)
}

impl BotRuntime {
    #[cfg(test)]
    pub(crate) async fn install_workspace_migration_fixture(
        &self,
        bot_id: &str,
        root_id: &str,
        workspace_id: &str,
    ) -> Result<(), FeishuError> {
        let mut config = BotConfigFile::new(
            bot_id.into(),
            "Workspace migration".into(),
            workspace_id.into(),
            "cli_workspace_fixture".into(),
        )?;
        config.enabled = false;
        config.model_route = Some(self.default_model_route()?);
        let dir = self.inner.paths.bot_dir(bot_id);
        super::config::save_config(&dir.join("config.toml"), &config)?;
        let store = super::storage::BotStateStore::new(dir.join("state.sqlite"));
        store
            .claim_thread_binding("workspace-chat", "workspace-creation", workspace_id)
            .await?;
        store
            .bind_thread(
                "workspace-chat",
                root_id,
                "workspace-creation",
                workspace_id,
            )
            .await?;
        self.load().await
    }

    pub(crate) fn workspace_root(&self, config: &BotConfigFile) -> std::path::PathBuf {
        self.inner.paths.bot_dir(&config.id).join("workspace")
    }
    pub(crate) async fn workspace_migration_complete(
        &self,
        config: &BotConfigFile,
        thread_id: &str,
        old_root: &str,
    ) -> Result<bool, FeishuError> {
        let files = pl_tool::workspace::SessionFiles::new(thread_id);
        let target = self.workspace_root(config).join(files.root());
        let marker = target.join(".migration-complete");
        pl_tool::workspace::path_safety::validate_path_for_write_async(
            &self.inner.paths.bot_dir(&config.id),
            &marker,
        )
        .await
        .map_err(workspace_error)?;
        match tokio::fs::read_to_string(&marker).await {
            Ok(source) => {
                pl_tool::workspace::path_safety::validate_existing_path_async(
                    &self.inner.paths.bot_dir(&config.id),
                    &marker,
                )
                .await
                .map_err(workspace_error)?;
                if !completion_matches(
                    &source,
                    thread_id,
                    &std::path::Path::new(old_root).join(files.root()),
                )
                .map_err(workspace_error)?
                {
                    return Err(workspace_error(
                        "workspace migration completion belongs to a different source",
                    ));
                }
                Ok(true)
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(false),
            Err(error) => Err(workspace_error(error)),
        }
    }
    pub(crate) async fn ensure_workspace_project(
        &self,
        bot_id: &str,
        name: &str,
    ) -> Result<String, FeishuError> {
        let root = self.inner.paths.bot_dir(bot_id).join("workspace");
        tokio::fs::create_dir_all(&root)
            .await
            .map_err(workspace_error)?;
        let host = self
            .studio_host()
            .ok_or_else(|| workspace_error("Studio runtime is closed"))?;
        let project = host.open_project(root).await.map_err(workspace_error)?;
        if project.name != name {
            host.rename_project(&project.id, name)
                .await
                .map_err(workspace_error)?;
        }
        Ok(project.id)
    }

    pub(crate) fn model_selector(
        &self,
        config: &BotConfigFile,
    ) -> Result<pl_model::config::ModelRouteConfig, FeishuError> {
        let route = match &config.model_route {
            Some(route) => route.clone(),
            None => self.default_model_route()?,
        };
        Ok(pl_model::config::ModelRouteConfig {
            account_id: pl_model::config::AccountId::new(route.account_id)
                .map_err(workspace_error)?,
            model_id: route.model_id,
            effort: route.effort.map(pl_model::config::ReasoningEffort::new),
        })
    }

    /// Copy only the old Thread-owned execution directory. Never move a user's project.
    /// Files are published atomically; repeat recovery preserves already completed copies.
    pub(crate) async fn prepare_workspace(
        &self,
        config: &BotConfigFile,
        thread_id: &str,
        old_root: &str,
    ) -> Result<std::path::PathBuf, FeishuError> {
        let root = self.workspace_root(config);
        let target_container = self.inner.paths.bot_dir(&config.id);
        let source_container = std::path::PathBuf::from(old_root);
        let files = pl_tool::workspace::SessionFiles::new(thread_id);
        let source = std::path::Path::new(old_root).join(files.root());
        let target = root.join(files.root());
        let root_copy = root.clone();
        let owner = thread_id.to_owned();
        let root = tokio::task::spawn_blocking(move || {
            migrate_owned_directory(
                &source_container,
                &source,
                &target_container,
                &target,
                &owner,
            )?;
            dunce::canonicalize(root_copy)
        })
        .await
        .map_err(workspace_error)?
        .map_err(workspace_error)?;
        pl_tool::workspace::SessionTempBackend::Local(&root)
            .migrate(&files)
            .await
            .map_err(workspace_error)?;
        tokio::fs::create_dir_all(root.join(files.uploads()))
            .await
            .map_err(workspace_error)?;
        Ok(root)
    }

    /// A newly dispatched identity has no old execution files to migrate or source to read.
    pub(crate) async fn prepare_new_workspace(
        &self,
        config: &BotConfigFile,
        thread_id: &str,
    ) -> Result<std::path::PathBuf, FeishuError> {
        let root = self.workspace_root(config);
        let container = self.inner.paths.bot_dir(&config.id);
        let files = pl_tool::workspace::SessionFiles::new(thread_id);
        let target = root.join(files.root());
        let uploads = root.join(files.uploads());
        let owner = thread_id.to_owned();
        tokio::task::spawn_blocking(move || -> std::io::Result<std::path::PathBuf> {
            pl_tool::workspace::path_safety::validate_path_for_write(&container, &target)
                .map_err(std::io::Error::other)?;
            std::fs::create_dir_all(uploads)?;
            let marker = target.join(".migration-complete");
            pl_tool::workspace::path_safety::validate_path_for_write(&container, &marker)
                .map_err(std::io::Error::other)?;
            match std::fs::read_to_string(&marker) {
                Ok(text) => {
                    let created: CreatedWorkspace =
                        serde_json::from_str(&text).map_err(std::io::Error::other)?;
                    if created.schema_version != 1 || created.thread_id != owner {
                        return Err(std::io::Error::other(
                            "new workspace completion has another owner",
                        ));
                    }
                }
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                    let bytes = serde_json::to_vec(&CreatedWorkspace {
                        schema_version: 1,
                        thread_id: owner,
                    })
                    .map_err(std::io::Error::other)?;
                    pl_tool::workspace::write_file_atomically(&marker, &bytes)?;
                }
                Err(error) => return Err(error),
            }
            dunce::canonicalize(root)
        })
        .await
        .map_err(workspace_error)?
        .map_err(workspace_error)
    }
}

fn migrate_owned_directory(
    source_container: &std::path::Path,
    source: &std::path::Path,
    target_container: &std::path::Path,
    target: &std::path::Path,
    thread_id: &str,
) -> std::io::Result<()> {
    pl_tool::workspace::path_safety::validate_path_for_write(target_container, target)
        .map_err(std::io::Error::other)?;
    reject_link(target)?;
    let marker = target.join(".migration-complete");
    if marker.exists() {
        reject_link(&marker)?;
        if !completion_matches(&std::fs::read_to_string(&marker)?, thread_id, source)? {
            return Err(std::io::Error::other(
                "workspace migration completion has a different source",
            ));
        }
        return Ok(());
    }
    // A catalog refresh may have passed admission before the source went offline. Only a
    // live source workspace can prove that an absent owned directory means an empty migration.
    if !std::fs::metadata(source_container)?.is_dir() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::NotADirectory,
            "workspace migration source is not a directory",
        ));
    }
    pl_tool::workspace::path_safety::validate_path_for_write(source_container, source)
        .map_err(std::io::Error::other)?;
    reject_link(source)?;
    std::fs::create_dir_all(target)?;
    if source != target && source.try_exists()? {
        copy_owned_directory(source, target)?;
    }
    pl_tool::workspace::write_file_atomically(&marker, source.to_string_lossy().as_bytes())?;
    Ok(())
}

fn copy_owned_directory(source: &std::path::Path, target: &std::path::Path) -> std::io::Result<()> {
    for entry in std::fs::read_dir(source)? {
        let entry = entry?;
        let kind = entry.file_type()?;
        if kind.is_symlink() {
            return Err(std::io::Error::other(
                "bot workspace migration refuses symbolic links",
            ));
        }
        let destination = target.join(entry.file_name());
        reject_link(&destination)?;
        if kind.is_dir() {
            // Python virtual environments are not relocatable. Keep originals intact; uv creates
            // this Thread's new environment on demand from the retained dependency manifests.
            if entry.file_name() == ".venv" {
                continue;
            }
            std::fs::create_dir_all(&destination)?;
            copy_owned_directory(&entry.path(), &destination)?;
        } else if kind.is_file() && !destination.exists() {
            let mut original = std::fs::File::open(entry.path())?;
            let mut pending = tempfile::NamedTempFile::new_in(target)?;
            std::io::copy(&mut original, pending.as_file_mut())?;
            pending.as_file().sync_all()?;
            match pending.persist_noclobber(&destination) {
                Ok(_) => {}
                Err(error) if error.error.kind() == std::io::ErrorKind::AlreadyExists => {}
                Err(error) => return Err(error.error),
            }
        }
    }
    Ok(())
}

fn reject_link(path: &std::path::Path) -> std::io::Result<()> {
    match std::fs::symlink_metadata(path) {
        Ok(metadata) if metadata.file_type().is_symlink() => Err(std::io::Error::other(
            "bot workspace migration refuses symbolic links",
        )),
        Ok(_) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error),
    }
}

fn workspace_error(error: impl std::fmt::Display) -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        format!("bot workspace: {error}"),
        true,
        None,
    )
}

#[cfg(test)]
mod migration_tests {
    use super::migrate_owned_directory;
    use std::fs;

    #[test]
    fn incomplete_migration_cannot_publish_completion_after_source_workspace_disappears() {
        let temp = tempfile::tempdir().unwrap();
        let business = temp.path().join("business");
        let source = business.join(".anywork/sessions/owned");
        let target = temp.path().join("bot/workspace/.anywork/sessions/owned");
        fs::create_dir_all(&business).unwrap();
        // An existing workspace may legitimately have no old Thread-owned files.
        migrate_owned_directory(&business, &source, temp.path(), &target, "owned").unwrap();
        fs::write(target.join("new-work.txt"), "preserve target work").unwrap();
        fs::rename(&business, temp.path().join("source-offline")).unwrap();
        // A completed migration is independent of the old source.
        migrate_owned_directory(&business, &source, temp.path(), &target, "owned").unwrap();
        fs::remove_file(target.join(".migration-complete")).unwrap();
        assert!(
            migrate_owned_directory(&business, &source, temp.path(), &target, "owned").is_err(),
            "a missing source workspace is not proof of an empty completed migration"
        );
        assert!(!target.join(".migration-complete").exists());
        assert_eq!(
            fs::read_to_string(target.join("new-work.txt")).unwrap(),
            "preserve target work"
        );
    }

    #[test]
    fn interrupted_copy_resumes_without_overwriting_new_files_or_touching_business_data() {
        let temp = tempfile::tempdir().unwrap();
        let business = temp.path().join("business");
        let source = business.join(".anywork/sessions/owned");
        let target = temp.path().join("bot/workspace/.anywork/sessions/owned");
        fs::create_dir_all(source.join("scratch")).unwrap();
        fs::create_dir_all(source.join(".venv")).unwrap();
        fs::write(business.join("business.txt"), "not bot-owned").unwrap();
        fs::write(source.join("scratch/old.txt"), "retained original").unwrap();
        fs::write(source.join(".venv/python"), "not relocatable").unwrap();
        fs::create_dir_all(&target).unwrap();
        fs::write(target.join("scratch"), "interrupted destination").unwrap();
        assert!(
            migrate_owned_directory(&business, &source, temp.path(), &target, "owned").is_err()
        );
        assert!(!target.join(".migration-complete").exists());
        fs::remove_file(target.join("scratch")).unwrap();
        fs::create_dir_all(target.join("scratch")).unwrap();
        fs::write(target.join("scratch/new.txt"), "new work").unwrap();
        migrate_owned_directory(&business, &source, temp.path(), &target, "owned").unwrap();
        assert_eq!(
            fs::read_to_string(target.join("scratch/new.txt")).unwrap(),
            "new work"
        );
        assert_eq!(
            fs::read_to_string(target.join("scratch/old.txt")).unwrap(),
            "retained original"
        );
        assert_eq!(
            fs::read_to_string(business.join("business.txt")).unwrap(),
            "not bot-owned"
        );
        assert!(!target.join(".venv").exists());
        assert!(source.join(".venv/python").exists());
        fs::remove_file(target.join("scratch/old.txt")).unwrap();
        migrate_owned_directory(&business, &source, temp.path(), &target, "owned").unwrap();
        assert!(
            !target.join("scratch/old.txt").exists(),
            "completed migrations must not resurrect intentionally removed work files"
        );
        fs::rename(
            &business,
            temp.path().join("old-business-no-longer-mounted"),
        )
        .unwrap();
        migrate_owned_directory(&business, &source, temp.path(), &target, "owned").unwrap();
        assert_eq!(
            fs::read_to_string(target.join("scratch/new.txt")).unwrap(),
            "new work"
        );
        assert!(
            !source.exists(),
            "a completed migration must not recreate its old source"
        );

        // A refresh can pass admission before its completion marker disappears. The copy boundary
        // must still reject an unavailable source rather than publish a new completion for no copy.
        let marker = target.join(".migration-complete");
        let completion = fs::read(&marker).unwrap();
        fs::remove_file(&marker).unwrap();
        let error =
            migrate_owned_directory(&business, &source, temp.path(), &target, "owned").unwrap_err();
        assert_eq!(error.kind(), std::io::ErrorKind::NotFound);
        assert!(!marker.exists());
        assert!(!source.exists());
        assert_eq!(
            fs::read_to_string(target.join("scratch/new.txt")).unwrap(),
            "new work"
        );
        let nested_target = business.join("studio-home/bot/workspace/owned");
        let error =
            migrate_owned_directory(&business, &source, temp.path(), &nested_target, "owned")
                .unwrap_err();
        assert_eq!(error.kind(), std::io::ErrorKind::NotFound);
        assert!(!business.exists());
        fs::write(&marker, completion).unwrap();
        migrate_owned_directory(&business, &source, temp.path(), &target, "owned").unwrap();
    }
}
