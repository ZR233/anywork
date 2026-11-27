//! Host-owned discovery, permissions and extension commit for standalone skill tools.
use super::super::{
    FrozenSkillCatalog, SkillDiscoverySources, SkillLoadInvocation, SkillResourceBase, SkillSummary,
};
use pl_agent_tool::typed::{TypedTool, decode_json};
use pl_core::{
    context::{ContextContent, OpaquePayload},
    thread::extensions::ExtensionMutation,
    tool::{ToolOutput, opaque::ToolError},
};
use pl_tool_skill::support::{Document, SkillReader};
use sha2::{Digest, Sha256};
use std::sync::Arc;
use tokio_util::sync::CancellationToken;

#[derive(Debug, Clone, Copy)]
pub enum ThreadSkillKind {
    List,
    View,
}
impl ThreadSkillKind {
    pub fn declaration(self) -> pl_agent_tool::ToolDefinition {
        match self {
            Self::List => pl_agent_tool::typed::prepare_json::<
                pl_tool_skill::tools::skills_list::SkillsList,
            >()
            .expect("static skill definition")
            .with_output_schema()
            .expect("static skill listing schema")
            .definition()
            .clone(),
            Self::View => pl_agent_tool::typed::prepare_json::<
                pl_tool_skill::tools::skill_view::SkillView<CatalogReader>,
            >()
            .expect("static skill definition")
            .definition()
            .clone()
            .with_output_schema(crate::binding::program_schema::<super::SkillViewOutput>())
            .expect("static skill view schema"),
        }
    }
}
#[derive(Debug)]
pub struct ThreadSkillTool {
    definition: pl_agent_tool::ToolDefinition,
    sources: SkillDiscoverySources,
    kind: ThreadSkillKind,
}
impl ThreadSkillTool {
    pub fn new(
        sources: SkillDiscoverySources,
        kind: ThreadSkillKind,
        definition: pl_agent_tool::ToolDefinition,
    ) -> Self {
        Self {
            definition,
            sources,
            kind,
        }
    }
}
#[derive(Debug)]
struct CatalogReader(FrozenSkillCatalog);
impl SkillReader for CatalogReader {
    type Error = pl_protocol::PureError;
    type Summary = SkillSummary;
    type ResourceBase = SkillResourceBase;
    async fn load(
        &self,
        name: &str,
        cancellation: CancellationToken,
    ) -> Result<Document<SkillSummary, SkillResourceBase>, Self::Error> {
        let document = self
            .0
            .load(name, SkillLoadInvocation::Model, cancellation)
            .await?;
        Ok(Document {
            name: document.summary.name.clone(),
            resource_base: document.summary.resource_base.clone(),
            summary: document.summary,
            content: document.content,
        })
    }
    async fn read_resource(
        &self,
        name: &str,
        path: &str,
        cancellation: CancellationToken,
    ) -> Result<String, Self::Error> {
        self.0
            .read_resource(name, path, SkillLoadInvocation::Model, cancellation)
            .await
    }
    async fn record_view(
        &self,
        name: &str,
        cancellation: CancellationToken,
    ) -> Result<(), Self::Error> {
        self.0.record_model_view(name, cancellation).await
    }
}
impl ThreadSkillTool {
    /// Executes the shared author without committing Native extension state.
    async fn execute_discovery(
        &self,
        input: OpaquePayload,
        cancellation: CancellationToken,
    ) -> Result<ToolOutput, ToolError> {
        if !self.sources.authorization().is_active() {
            return Err(ToolError::new(
                pl_core::thread::ThreadError::ToolPermissionRevoked,
            ));
        }
        if input.format() != "application/json" || input.version() != 1 {
            return Err(error("unsupported skill argument encoding"));
        }
        if cancellation.is_cancelled() {
            return Err(error("skill operation cancelled"));
        }
        match self.kind {
            ThreadSkillKind::List => {
                let input = decode_json(input.content()).map_err(ToolError::new)?;
                let catalog = self
                    .sources
                    .discover(cancellation)
                    .await
                    .map_err(ToolError::new)?;
                let rows = catalog
                    .snapshot()
                    .skills
                    .iter()
                    .map(|skill| pl_tool_skill::support::Listing {
                        name: skill.name.clone(),
                        description: skill.description.clone(),
                        category: skill.category.clone(),
                        model_invocable: skill.invocation.model_invocable,
                    })
                    .collect();
                let result = pl_tool_skill::tools::skills_list::SkillsList::new(rows)
                    .execute(input, ())
                    .await
                    .map_err(ToolError::new)?;
                let encoded = serde_json::to_string(&result).map_err(ToolError::new)?;
                text_output(&result, encoded)
            }
            ThreadSkillKind::View => {
                let input = decode_json(input.content()).map_err(ToolError::new)?;
                let catalog = self
                    .sources
                    .discover(cancellation.clone())
                    .await
                    .map_err(ToolError::new)?;
                let result =
                    match pl_tool_skill::tools::skill_view::SkillView::new(CatalogReader(catalog))
                        .execute(input, cancellation)
                        .await
                    {
                        Ok(result) => result,
                        Err(pl_tool_skill::tools::skill_view::ViewError::Record {
                            source,
                            output,
                        }) => {
                            return Err(ToolError::new(source)
                                .with_output(text_output(&output.viewed, output.preview)?));
                        }
                        Err(error) => return Err(ToolError::new(error)),
                    };
                text_output(&result.viewed, result.preview)
            }
        }
    }
}

impl pl_agent_tool::Tool for ThreadSkillTool {
    type Input = OpaquePayload;
    type Context = crate::invocation::WorkspaceInvocation;
    type Output = ToolOutput;
    type Error = ToolError;
    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        &self.definition
    }
    async fn execute(
        &self,
        input: OpaquePayload,
        context: crate::invocation::WorkspaceInvocation,
    ) -> Result<ToolOutput, ToolError> {
        self.execute_discovery(input, context.cancellation).await
    }
}

#[derive(Debug)]
pub struct ThreadSkillManageTool {
    catalog: Arc<FrozenSkillCatalog>,
    workspace: crate::workspace::ToolWorkspace,
}
impl ThreadSkillManageTool {
    pub fn new(
        catalog: Arc<FrozenSkillCatalog>,
        workspace: crate::workspace::ToolWorkspace,
    ) -> Self {
        Self { catalog, workspace }
    }
    pub fn declaration() -> pl_agent_tool::ToolDefinition {
        pl_agent_tool::typed::prepare_json::<
            pl_tool_skill::tools::skill_manage::SkillManage<super::actions::LocalSkillFiles>,
        >()
        .expect("static skill definition")
        .with_output_schema()
        .expect("static skill mutation schema")
        .definition()
        .clone()
    }
}
impl ThreadSkillManageTool {
    async fn execute_mutation(
        &self,
        input: pl_tool_skill::tools::skill_manage::SkillManageInput,
        cancellation: CancellationToken,
    ) -> Result<ToolOutput, ToolError> {
        if !self.workspace.authorization().is_active() {
            return Err(ToolError::new(
                pl_core::thread::ThreadError::ToolPermissionRevoked,
            ));
        }
        self.workspace
            .ensure_workspace_writable()
            .map_err(ToolError::new)?;
        let lease = tokio::select! {
            biased;
            _ = cancellation.cancelled() => return Err(error("operation cancelled before mutation")),
            lease = self.workspace.write_lock() => lease,
        };
        if cancellation.is_cancelled() {
            return Err(error("operation cancelled before mutation"));
        }
        let catalog = Arc::new(
            self.catalog
                .discovery_sources()
                .discover(cancellation.clone())
                .await
                .map_err(ToolError::new)?,
        );
        let snapshot = catalog.snapshot();
        let candidates = snapshot
            .skills
            .iter()
            .map(|skill| pl_tool_skill::tools::skill_manage::Candidate {
                name: skill.name.clone(),
                path: skill.path.clone(),
                read_only_source: match skill.source {
                    super::super::SkillSourceKind::Project => None,
                    source => Some(super::super::provider::source_label(source).into()),
                },
            })
            .collect();
        let tool = pl_tool_skill::tools::skill_manage::SkillManage::new(
            super::actions::LocalSkillFiles {
                workspace: self.workspace.clone(),
                project_dir: snapshot.project_dir.clone(),
            },
            snapshot.project_dir.clone(),
            candidates,
        );
        let result = tokio::task::spawn_blocking(move || {
            let _lease = lease;
            let result = futures::executor::block_on(tool.execute(input, ()));
            catalog.invalidate();
            result
        })
        .await
        .map_err(ToolError::new)?;
        let result = match result {
            Ok(result) => result,
            Err(pl_tool_skill::tools::skill_manage::ManageError::Record { source, output }) => {
                let encoded = serde_json::to_string(&output).map_err(ToolError::new)?;
                return Err(ToolError::new(source).with_output(text_output(&output, encoded)?));
            }
            Err(error) => return Err(ToolError::new(error)),
        };
        let encoded = serde_json::to_string(&result).map_err(ToolError::new)?;
        text_output(&result, encoded)
    }
}

impl TypedTool for ThreadSkillManageTool {
    const NAME: &'static str = "skill_manage";
    const DESCRIPTION: &'static str = <pl_tool_skill::tools::skill_manage::SkillManage<
        super::actions::LocalSkillFiles,
    > as TypedTool>::DESCRIPTION;
    type Args = pl_tool_skill::tools::skill_manage::SkillManageInput;
    type Context = crate::invocation::WorkspaceInvocation;
    type Output = ToolOutput;
    type Error = ToolError;
    async fn execute(
        &self,
        input: Self::Args,
        context: crate::invocation::WorkspaceInvocation,
    ) -> Result<ToolOutput, ToolError> {
        self.execute_mutation(input, context.cancellation).await
    }
}
fn text_output(value: &impl serde::Serialize, text: String) -> Result<ToolOutput, ToolError> {
    Ok(ToolOutput::from_data(
        serde_json::to_value(value).map_err(ToolError::new)?,
        vec![ContextContent::Text { text: text.into() }],
    ))
}
fn error(message: &str) -> ToolError {
    ToolError::new(crate::tool_error("skills", message))
}

pub fn native_skill_view_effect(
    output: ToolOutput,
    extensions: &std::collections::BTreeMap<String, pl_core::thread::extensions::ExtensionRecord>,
) -> Result<ToolOutput, ToolError> {
    let name = match crate::skill::saved_skill_name(output.data()) {
        Ok(name) => name,
        Err(error) => return Err(ToolError::new(error).with_output(output)),
    };
    let id = format!(
        "pl.tool.skill-view:{}",
        hex::encode(Sha256::digest(name.to_ascii_lowercase().as_bytes()))
    );
    let previous = extensions.get(&id);
    let value = output.data().expect("Skill identity requires result data");
    if previous.is_some_and(|record| {
        record.payload.format() == "pl.tool.skill-view"
            && record.payload.version() == 1
            && serde_json::from_str::<serde_json::Value>(record.payload.content())
                .is_ok_and(|saved| &saved == value)
    }) {
        return Ok(output);
    }
    let payload =
        OpaquePayload::new("pl.tool.skill-view", 1, value.to_string()).map_err(ToolError::new)?;
    Ok(
        output.with_extension_mutations(vec![ExtensionMutation::Put {
            id,
            expected_revision: previous.map(|record| record.revision),
            payload,
        }]),
    )
}
