//! Bot-owned execution roots; historical session storage retains its canonical identity.
use super::{
    BotRuntime,
    config::BotConfigFile,
    protocol::error::{FeishuError, FeishuErrorKind},
};
use pl_tool::workspace_file::LocalWorkspaceRoot;

impl BotRuntime {
    pub(crate) async fn ensure_workspace_project(
        &self,
        bot_id: &str,
        name: &str,
    ) -> Result<String, FeishuError> {
        let root = self.managed_workspace_root(bot_id).await?;
        let host = self
            .studio_host()
            .ok_or_else(|| workspace_error("Studio runtime is closed"))?;
        let project = host
            .open_project(root.path().to_owned())
            .await
            .map_err(workspace_error)?;
        if project.name != name {
            host.rename_project(&project.id, name)
                .await
                .map_err(workspace_error)?;
        }
        Ok(project.id)
    }

    /// The host home is the ambient grant; every managed descendant (including workspace itself)
    /// is opened/created no-follow. Never canonicalize an unvalidated bot/workspace descendant.
    async fn managed_workspace_root(
        &self,
        bot_id: &str,
    ) -> Result<LocalWorkspaceRoot, FeishuError> {
        super::config::validate_bot_id(bot_id)?;
        let parent = self.inner.paths.home().to_owned();
        let relative = self
            .inner
            .paths
            .bot_dir(bot_id)
            .join("workspace")
            .strip_prefix(&parent)
            .map_err(workspace_error)?
            .to_owned();
        LocalWorkspaceRoot::ensure_beneath(self.inner.workspace_io.clone(), parent, relative)
            .await
            .map_err(workspace_error)
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
        let root = self.managed_workspace_root(&config.id).await?;
        let root_path = root.path().to_owned();
        let files = pl_tool::workspace::SessionFiles::new(thread_id);
        let source = std::path::Path::new(old_root).join(files.root());
        let target = root_path.join(files.root());
        // Reuse the existing long-lived operation owner for the legacy copy's blocking join.
        // Cancellation of root activation does not abandon an in-progress owned-directory copy.
        let bytes = super::occupancy::counted_extra_bytes(
            0,
            [
                (source.as_os_str().len(), 2),
                (target.as_os_str().len(), 2),
                (root_path.as_os_str().len(), 2),
            ],
        )?;
        self.submit_occupancy(bytes, move |_budget| async move {
            tokio::task::spawn_blocking(move || {
                let _root_lease = root;
                migrate_owned_directory(&source, &target)?;
                std::fs::create_dir_all(target.join("uploads"))?;
                Ok::<_, std::io::Error>(root_path)
            })
            .await
            .map_err(workspace_error)?
            .map_err(workspace_error)
        })
        .await
    }
}

fn migrate_owned_directory(
    source: &std::path::Path,
    target: &std::path::Path,
) -> std::io::Result<()> {
    reject_link(source)?;
    reject_link(target)?;
    std::fs::create_dir_all(target)?;
    let marker = target.join(".migration-complete");
    if source != target && source.is_dir() && !marker.exists() {
        copy_owned_directory(source, target)?;
        pl_tool::workspace::write_file_atomically(&marker, source.to_string_lossy().as_bytes())?;
    }
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
        assert!(migrate_owned_directory(&source, &target).is_err());
        assert!(!target.join(".migration-complete").exists());
        fs::remove_file(target.join("scratch")).unwrap();
        fs::create_dir_all(target.join("scratch")).unwrap();
        fs::write(target.join("scratch/new.txt"), "new work").unwrap();
        migrate_owned_directory(&source, &target).unwrap();
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
        migrate_owned_directory(&source, &target).unwrap();
        assert!(
            !target.join("scratch/old.txt").exists(),
            "completed migrations must not resurrect intentionally removed work files"
        );
    }
}
