//! Document/resource reading; activation is committed by the consuming host.
use pl_agent_tool::typed::TypedTool;
use pl_tool_skill_support::{SkillReader, ViewedSkill, is_main_skill_path};
use serde::Deserialize;
use tokio_util::sync::CancellationToken;

#[derive(Debug, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Args {
    /// Project skill name.
    pub name: String,
    /// Optional support file under references/, templates/, scripts/, or assets/.
    pub file_path: Option<String>,
}
#[derive(Debug)]
pub struct Output<S, R> {
    pub viewed: ViewedSkill<S, R>,
    pub preview: String,
}
#[derive(Debug, thiserror::Error)]
pub enum ViewError<E: std::error::Error + 'static, S: std::fmt::Debug, R: std::fmt::Debug> {
    #[error("skill operation failed: {0}")]
    Read(#[source] E),
    #[error("skill usage could not be saved: {source}")]
    Record {
        #[source]
        source: E,
        output: Box<Output<S, R>>,
    },
    #[error(transparent)]
    Path(#[from] pl_skill_core::SkillCoreError),
}
#[derive(Debug)]
pub struct SkillView<S> {
    reader: S,
}
impl<S: SkillReader> SkillView<S> {
    pub fn new(reader: S) -> Self {
        Self { reader }
    }
}
impl<S: SkillReader> TypedTool for SkillView<S> {
    const NAME: &'static str = "skill_view";
    const DESCRIPTION: &'static str = "Read a skill or a support file. The actual text is retained in history; use it as tool-provided guidance.";
    type Args = Args;
    type Context = CancellationToken;
    type Output = Output<S::Summary, S::ResourceBase>;
    type Error = ViewError<S::Error, S::Summary, S::ResourceBase>;
    async fn execute(
        &self,
        input: Args,
        cancellation: CancellationToken,
    ) -> Result<Self::Output, Self::Error> {
        let document = self
            .reader
            .load(&input.name, cancellation.clone())
            .await
            .map_err(ViewError::Read)?;
        let resource = input
            .file_path
            .as_deref()
            .map(str::trim)
            .filter(|path| !is_main_skill_path(path));
        let (file_path, content) = match resource {
            Some(path) => {
                pl_skill_core::support_file_path(
                    path,
                    pl_skill_core::DEFAULT_ALLOWED_SUPPORT_DIRS,
                )?;
                (
                    path.to_owned(),
                    self.reader
                        .read_resource(&input.name, path, cancellation.clone())
                        .await
                        .map_err(ViewError::Read)?,
                )
            }
            None => (pl_skill_core::SKILL_FILE_NAME.into(), document.content),
        };
        let preview = format!(
            "Skill: {}\nResource: {file_path}\n\n{content}",
            document.name
        );
        let viewed = ViewedSkill {
            success: true,
            skill: document.summary,
            file_path,
            resource_base: document.resource_base,
            resource_hint: "Use filePath to read support resources on demand.".into(),
            content,
        };
        let output = Output { viewed, preview };
        if let Err(source) = self.reader.record_view(&input.name, cancellation).await {
            return Err(ViewError::Record {
                source,
                output: Box::new(output),
            });
        }
        Ok(output)
    }
}
