//! Host-owned discovery, permissions and extension commit for standalone skill tools.
use super::super::{
    FrozenSkillCatalog, SkillDiscoverySources, SkillLoadInvocation, SkillResourceBase, SkillSummary,
};
use pl_agent_tool::typed::{TypedTool, decode_json};
use pl_core::{
    context::{ContextContent, OpaquePayload},
    thread::extensions::ExtensionMutation,
    tool::{
        ToolOutput,
        opaque::{CallContext, Registration, ToolError},
    },
};
use pl_tool_skill_support::{Document, SkillReader};
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
            Self::List => pl_agent_tool::typed::prepare_json::<pl_tool_skills_list::SkillsList>()
                .expect("static skill definition")
                .definition()
                .clone(),
            Self::View => {
                pl_agent_tool::typed::prepare_json::<pl_tool_skill_view::SkillView<CatalogReader>>()
                    .expect("static skill definition")
                    .definition()
                    .clone()
            }
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
    pub fn registration(
        self,
        prepared: pl_core::tool::opaque::PreparedRegistration,
    ) -> Registration {
        let kind = self.kind;
        let authorization = self.sources.authorization();
        let registration = prepared
            .attach(pl_agent_tool::ToolHandle::new(self))
            .with_authorization(authorization);
        match kind {
            ThreadSkillKind::List => registration,
            ThreadSkillKind::View => registration.with_extension_updates(),
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
impl pl_agent_tool::Tool for ThreadSkillTool {
    type Input = OpaquePayload;
    type Context = CallContext;
    type Output = ToolOutput;
    type Error = ToolError;
    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        &self.definition
    }
    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        if input.format() != "application/json" || input.version() != 1 {
            return Err(error("unsupported skill argument encoding"));
        }
        if context.cancellation.is_cancelled() {
            return Err(error("skill operation cancelled"));
        }
        match self.kind {
            ThreadSkillKind::List => {
                let input = decode_json(input.content()).map_err(ToolError::new)?;
                let catalog = self
                    .sources
                    .discover(context.cancellation)
                    .await
                    .map_err(ToolError::new)?;
                let rows = catalog
                    .snapshot()
                    .skills
                    .iter()
                    .map(|skill| pl_tool_skill_support::Listing {
                        name: skill.name.clone(),
                        description: skill.description.clone(),
                        category: skill.category.clone(),
                        model_invocable: skill.invocation.model_invocable,
                    })
                    .collect();
                let result = pl_tool_skills_list::SkillsList::new(rows)
                    .execute(input, ())
                    .await
                    .map_err(ToolError::new)?;
                let encoded = serde_json::to_string(&result).map_err(ToolError::new)?;
                text_output("pl.tool.skill-list", &result, encoded)
            }
            ThreadSkillKind::View => {
                let input = decode_json(input.content()).map_err(ToolError::new)?;
                let catalog = self
                    .sources
                    .discover(context.cancellation.clone())
                    .await
                    .map_err(ToolError::new)?;
                let result = match pl_tool_skill_view::SkillView::new(CatalogReader(catalog))
                    .execute(input, context.cancellation)
                    .await
                {
                    Ok(result) => result,
                    Err(pl_tool_skill_view::ViewError::Record { source, output }) => {
                        return Err(ToolError::new(source).with_output(text_output(
                            "pl.tool.skill-view",
                            &output.viewed,
                            output.preview,
                        )?));
                    }
                    Err(error) => return Err(ToolError::new(error)),
                };
                let output = text_output("pl.tool.skill-view", &result.viewed, result.preview)?;
                let payload = output.payload().clone();
                let id = format!(
                    "pl.tool.skill-view:{}",
                    hex::encode(Sha256::digest(
                        result.viewed.skill.name.to_ascii_lowercase().as_bytes()
                    ))
                );
                let previous = context.extensions.get(&id);
                if previous.is_some_and(|record| record.payload == payload) {
                    return Ok(output);
                }
                Ok(
                    output.with_extension_mutations(vec![ExtensionMutation::Put {
                        id,
                        expected_revision: previous.map(|record| record.revision),
                        payload,
                    }]),
                )
            }
        }
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
            pl_tool_skill_manage::SkillManage<super::actions::LocalSkillFiles>,
        >()
        .expect("static skill definition")
        .definition()
        .clone()
    }
}
impl TypedTool for ThreadSkillManageTool {
    const NAME: &'static str = "skill_manage";
    const DESCRIPTION: &'static str = <pl_tool_skill_manage::SkillManage<
        super::actions::LocalSkillFiles,
    > as TypedTool>::DESCRIPTION;
    type Args = pl_tool_skill_manage::SkillManageInput;
    type Context = CallContext;
    type Output = ToolOutput;
    type Error = ToolError;
    async fn execute(
        &self,
        input: Self::Args,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        self.workspace
            .ensure_workspace_writable()
            .map_err(ToolError::new)?;
        let lease = tokio::select! {
            biased;
            _ = context.cancellation.cancelled() => return Err(error("operation cancelled before mutation")),
            lease = self.workspace.write_lock() => lease,
        };
        if context.cancellation.is_cancelled() {
            return Err(error("operation cancelled before mutation"));
        }
        let snapshot = self.catalog.snapshot();
        let candidates = snapshot
            .skills
            .iter()
            .map(|skill| pl_tool_skill_manage::Candidate {
                name: skill.name.clone(),
                path: skill.path.clone(),
                read_only_source: match skill.source {
                    super::super::SkillSourceKind::Project => None,
                    source => Some(super::super::provider::source_label(source).into()),
                },
            })
            .collect();
        let tool = pl_tool_skill_manage::SkillManage::new(
            super::actions::LocalSkillFiles {
                workspace: self.workspace.clone(),
                project_dir: snapshot.project_dir.clone(),
            },
            snapshot.project_dir.clone(),
            candidates,
        );
        let catalog = self.catalog.clone();
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
            Err(pl_tool_skill_manage::ManageError::Record { source, output }) => {
                let encoded = serde_json::to_string(&output).map_err(ToolError::new)?;
                return Err(ToolError::new(source).with_output(text_output(
                    "pl.tool.skill-mutation",
                    &output,
                    encoded,
                )?));
            }
            Err(error) => return Err(ToolError::new(error)),
        };
        let encoded = serde_json::to_string(&result).map_err(ToolError::new)?;
        text_output("pl.tool.skill-mutation", &result, encoded)
    }
}
fn text_output(
    format: &str,
    value: &impl serde::Serialize,
    text: String,
) -> Result<ToolOutput, ToolError> {
    Ok(ToolOutput::new(
        OpaquePayload::new(
            format,
            1,
            serde_json::to_string(value).map_err(ToolError::new)?,
        )
        .map_err(ToolError::new)?,
        vec![ContextContent::Text { text: text.into() }],
    ))
}
fn error(message: &str) -> ToolError {
    ToolError::new(crate::tool_error("skills", message))
}
