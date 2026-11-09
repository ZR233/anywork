//! Project skill mutation over an explicitly authorized file capability.
mod args;
mod text_escape;
use crate::support::{category_path, validate_document};
pub use args::*;
use pl_agent_tool::typed::TypedTool;
use pl_skill_core::{DEFAULT_ALLOWED_SUPPORT_DIRS, SKILL_FILE_NAME, SkillCoreError};
use serde::Serialize;
use std::{
    error::Error,
    future::Future,
    path::{Path, PathBuf},
};

#[derive(Debug, Clone)]
pub struct Candidate {
    pub name: String,
    pub path: PathBuf,
    /// None denotes the writable project source.
    pub read_only_source: Option<String>,
}
#[derive(Debug, Clone, Copy)]
pub enum WriteMode {
    Existing,
    Create,
    Upsert,
}

/// Each operation remains confined to the frozen project root and host write grant.
/// The host holds its existing mutation lease for the whole invocation.
pub trait ProjectFiles: Send + Sync + 'static {
    type Error: Error + Send + Sync + 'static;
    fn exists(&self, path: &Path) -> impl Future<Output = Result<bool, Self::Error>> + Send;
    fn read(&self, path: &Path) -> impl Future<Output = Result<String, Self::Error>> + Send;
    fn write(
        &self,
        path: &Path,
        text: String,
        mode: WriteMode,
    ) -> impl Future<Output = Result<(), Self::Error>> + Send;
    fn remove_file(&self, path: &Path) -> impl Future<Output = Result<(), Self::Error>> + Send;
    fn remove_tree(&self, path: &Path) -> impl Future<Output = Result<(), Self::Error>> + Send;
    fn record_created(
        &self,
        directory: &Path,
    ) -> impl Future<Output = Result<(), Self::Error>> + Send;
    fn record_patch(
        &self,
        directory: &Path,
    ) -> impl Future<Output = Result<(), Self::Error>> + Send;
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Output {
    pub success: bool,
    pub action: &'static str,
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub path: Option<PathBuf>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub replacements: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub file_path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    /// Present for deletion; its inner value preserves an explicitly absent absorption note.
    pub absorbed_into: Option<Option<String>>,
}
impl Output {
    fn new(action: &'static str, name: String) -> Self {
        Self {
            success: true,
            action,
            name,
            path: None,
            replacements: None,
            file_path: None,
            absorbed_into: None,
        }
    }
}
#[derive(Debug, thiserror::Error)]
pub enum ManageError<E: Error + 'static> {
    #[error("{0}")]
    Invalid(String),
    #[error(transparent)]
    Document(#[from] SkillCoreError),
    #[error("project skill file operation failed: {0}")]
    Files(#[source] E),
    #[error("skill files were changed but usage recording failed: {source}")]
    Record {
        #[source]
        source: E,
        output: Box<Output>,
    },
}
#[derive(Debug)]
pub struct SkillManage<F> {
    files: F,
    project_dir: PathBuf,
    candidates: Vec<Candidate>,
}
impl<F: ProjectFiles> SkillManage<F> {
    pub fn new(files: F, project_dir: PathBuf, candidates: Vec<Candidate>) -> Self {
        Self {
            files,
            project_dir,
            candidates,
        }
    }
    fn writable(&self, name: &str) -> Result<&Candidate, ManageError<F::Error>> {
        let candidate = self
            .candidates
            .iter()
            .find(|skill| skill.name.eq_ignore_ascii_case(name))
            .ok_or_else(|| ManageError::Invalid(format!("project skill not found: {name}")))?;
        if let Some(source) = &candidate.read_only_source {
            return Err(ManageError::Invalid(format!(
                "skill '{name}' comes from read-only {source} skills; create a project skill override before modifying it"
            )));
        }
        Ok(candidate)
    }
    async fn record(
        &self,
        path: &Path,
        created: bool,
        output: Output,
    ) -> Result<Output, ManageError<F::Error>> {
        let result = if created {
            self.files.record_created(path).await
        } else {
            self.files.record_patch(path).await
        };
        match result {
            Ok(()) => Ok(output),
            Err(source) => Err(ManageError::Record {
                source,
                output: Box::new(output),
            }),
        }
    }
}
impl<F: ProjectFiles> TypedTool for SkillManage<F> {
    const NAME: &'static str = "skill_manage";
    const DESCRIPTION: &'static str = "Create, patch, edit or remove local project skills and their support files within the configured writable paths.";
    type Args = SkillManageInput;
    type Context = ();
    type Output = Output;
    type Error = ManageError<F::Error>;
    async fn execute(&self, args: Self::Args, _: ()) -> Result<Output, Self::Error> {
        match args {
            SkillManageInput::Create(input) => {
                if self.candidates.iter().any(|skill| {
                    skill.read_only_source.is_none() && skill.name.eq_ignore_ascii_case(&input.name)
                }) {
                    return Err(ManageError::Invalid(format!(
                        "project skill already exists: {}",
                        input.name
                    )));
                }
                let metadata = validate_document(&input.content, Some(&input.name))?;
                let mut path = self.project_dir.clone();
                if let Some(category) = input.category.as_deref().or(metadata.category.as_deref()) {
                    path.push(category_path(category)?);
                }
                path.push(&metadata.name);
                let main = path.join(SKILL_FILE_NAME);
                if self.files.exists(&main).await.map_err(ManageError::Files)? {
                    return Err(ManageError::Invalid(format!(
                        "project skill directory already contains SKILL.md: {}",
                        path.display()
                    )));
                }
                self.files
                    .write(&main, input.content, WriteMode::Create)
                    .await
                    .map_err(ManageError::Files)?;
                let mut output = Output::new("create", metadata.name);
                output.path = Some(path.clone());
                self.record(&path, true, output).await
            }
            SkillManageInput::Edit(input) => {
                let skill = self.writable(&input.name)?;
                let metadata = validate_document(&input.content, Some(&input.name))?;
                self.files
                    .write(
                        &skill.path.join(SKILL_FILE_NAME),
                        input.content,
                        WriteMode::Existing,
                    )
                    .await
                    .map_err(ManageError::Files)?;
                let mut output = Output::new("edit", metadata.name);
                output.path = Some(skill.path.clone());
                self.record(&skill.path, false, output).await
            }
            SkillManageInput::Patch(input) => {
                let skill = self.writable(&input.name)?;
                if input.old_string.is_empty() {
                    return Err(ManageError::Invalid("oldString must not be empty".into()));
                }
                let path = skill.path.join(SKILL_FILE_NAME);
                let text = self.files.read(&path).await.map_err(ManageError::Files)?;
                let (needle, matches) = patch_needle(&text, &input.old_string).ok_or_else(|| ManageError::Invalid("oldString was not found in SKILL.md; read the current skill text and pass an exact oldString".into()))?;
                let mode = input.replace_mode.unwrap_or(ReplaceMode::One);
                if matches > 1 && matches!(mode, ReplaceMode::One) {
                    return Err(ManageError::Invalid(format!(
                        "oldString matched {matches} times; use replaceMode=all or provide a unique oldString"
                    )));
                }
                let updated = match mode {
                    ReplaceMode::One => text.replacen(&needle, &input.new_string, 1),
                    ReplaceMode::All => text.replace(&needle, &input.new_string),
                };
                validate_document(&updated, Some(&input.name))?;
                self.files
                    .write(&path, updated, WriteMode::Existing)
                    .await
                    .map_err(ManageError::Files)?;
                let mut output = Output::new("patch", skill.name.clone());
                output.replacements = Some(if matches!(mode, ReplaceMode::One) {
                    1
                } else {
                    matches
                });
                output.path = Some(skill.path.clone());
                self.record(&skill.path, false, output).await
            }
            SkillManageInput::Delete(input) => {
                let skill = self.writable(&input.name)?;
                self.files
                    .remove_tree(&skill.path)
                    .await
                    .map_err(ManageError::Files)?;
                let mut output = Output::new("delete", skill.name.clone());
                output.absorbed_into = Some(input.absorbed_into);
                Ok(output)
            }
            SkillManageInput::WriteFile(input) => {
                let skill = self.writable(&input.name)?;
                let relative = pl_skill_core::support_file_path(
                    &input.file_path,
                    DEFAULT_ALLOWED_SUPPORT_DIRS,
                )?;
                self.files
                    .write(
                        &skill.path.join(relative),
                        input.file_content,
                        WriteMode::Upsert,
                    )
                    .await
                    .map_err(ManageError::Files)?;
                let mut output = Output::new("writeFile", skill.name.clone());
                output.file_path = Some(input.file_path);
                self.record(&skill.path, false, output).await
            }
            SkillManageInput::RemoveFile(input) => {
                let skill = self.writable(&input.name)?;
                let relative = pl_skill_core::support_file_path(
                    &input.file_path,
                    DEFAULT_ALLOWED_SUPPORT_DIRS,
                )?;
                self.files
                    .remove_file(&skill.path.join(relative))
                    .await
                    .map_err(ManageError::Files)?;
                let mut output = Output::new("removeFile", skill.name.clone());
                output.file_path = Some(input.file_path);
                self.record(&skill.path, false, output).await
            }
        }
    }
}

fn patch_needle(text: &str, needle: &str) -> Option<(String, usize)> {
    let count = text.matches(needle).count();
    if count > 0 {
        return Some((needle.into(), count));
    }
    let normalized = text_escape::decode_json_escaped_fragment_once(needle)?;
    let count = text.matches(&normalized).count();
    (count > 0).then_some((normalized, count))
}
