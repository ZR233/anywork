//! Authorized local file operations used by the independent skill mutation tool.
use crate::{
    tool_error,
    workspace::{ToolWorkspace, path_safety::*},
};
use pl_protocol::PureError;
use pl_tool_skill_manage::{ProjectFiles, WriteMode};
use std::{
    fs,
    path::{Path, PathBuf},
};

#[derive(Debug)]
pub(super) struct LocalSkillFiles {
    pub workspace: ToolWorkspace,
    pub project_dir: PathBuf,
}
impl LocalSkillFiles {
    fn check(&self, path: &Path, requirement: ProjectPathRequirement) -> Result<(), PureError> {
        ensure_project_path(&self.project_dir, path, requirement, "skill_manage")?;
        self.workspace.ensure_path_writable(path)
    }
}
impl ProjectFiles for LocalSkillFiles {
    type Error = PureError;
    async fn exists(&self, path: &Path) -> Result<bool, PureError> {
        self.check(path, ProjectPathRequirement::AllowMissing)?;
        Ok(path.exists())
    }
    async fn read(&self, path: &Path) -> Result<String, PureError> {
        self.check(path, ProjectPathRequirement::MustExist)?;
        Ok(fs::read_to_string(path)?)
    }
    async fn write(&self, path: &Path, text: String, mode: WriteMode) -> Result<(), PureError> {
        self.check(
            path,
            match mode {
                WriteMode::Existing => ProjectPathRequirement::MustExist,
                WriteMode::Create | WriteMode::Upsert => ProjectPathRequirement::AllowMissing,
            },
        )?;
        if matches!(mode, WriteMode::Create) && path.exists() {
            return Err(tool_error(
                "skill_manage",
                format!("project skill file already exists: {}", path.display()),
            ));
        }
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        Ok(fs::write(path, text)?)
    }
    async fn remove_file(&self, path: &Path) -> Result<(), PureError> {
        self.check(path, ProjectPathRequirement::MustExist)?;
        if !path.is_file() {
            return Err(tool_error(
                "skill_manage",
                format!("support file does not exist: {}", path.display()),
            ));
        }
        Ok(fs::remove_file(path)?)
    }
    async fn remove_tree(&self, path: &Path) -> Result<(), PureError> {
        self.check(path, ProjectPathRequirement::MustExist)?;
        remove_dir_all_no_follow(&self.project_dir, path)
            .map_err(|source| tool_error("skill_manage", source))
    }
    async fn record_created(&self, directory: &Path) -> Result<(), PureError> {
        self.check(directory, ProjectPathRequirement::MustExist)?;
        super::super::mark_project_skill_created(&self.project_dir, directory)
    }
    async fn record_patch(&self, directory: &Path) -> Result<(), PureError> {
        self.check(directory, ProjectPathRequirement::MustExist)?;
        super::super::bump_project_patch(&self.project_dir, directory)
    }
}

#[derive(Debug, Clone, Copy)]
enum ProjectPathRequirement {
    MustExist,
    AllowMissing,
}

fn ensure_project_path(
    project_dir: &Path,
    path: &Path,
    requirement: ProjectPathRequirement,
    tool: &str,
) -> Result<(), PureError> {
    let absolute_project = absolute_path(project_dir);
    let absolute_path = absolute_path(path);
    if !is_lexically_within(&absolute_project, &absolute_path) {
        return Err(tool_error(
            tool,
            format!("path escapes project skills directory: {}", path.display()),
        ));
    }
    match std::fs::symlink_metadata(&absolute_project) {
        Ok(metadata) if crate::workspace::path_safety::is_link_or_reparse(&metadata) => {
            return Err(tool_error(
                tool,
                format!(
                    "project skills directory is a symbolic link or Windows reparse point: {}",
                    project_dir.display()
                ),
            ));
        }
        Ok(metadata) if !metadata.is_dir() => {
            return Err(tool_error(
                tool,
                format!(
                    "project skills path is not a directory: {}",
                    project_dir.display()
                ),
            ));
        }
        Ok(_) => {}
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => return Err(tool_error(tool, error)),
    }
    let result = match requirement {
        ProjectPathRequirement::MustExist => {
            validate_existing_path(&absolute_project, &absolute_path)
        }
        ProjectPathRequirement::AllowMissing => {
            validate_path_for_write(&absolute_project, &absolute_path)
        }
    };
    result.map_err(|error| tool_error(tool, error))
}

fn absolute_path(path: &Path) -> PathBuf {
    if path.is_absolute() {
        path.to_path_buf()
    } else {
        std::env::current_dir().unwrap_or_default().join(path)
    }
}
