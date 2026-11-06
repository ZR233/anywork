//! Skill discovery and actual read snapshots at the opaque Thread boundary.
use super::{
    FrozenSkillCatalog, SKILL_FILE_NAME, SkillDiscoverySources, SkillLoadInvocation,
    SkillViewInput, SkillViewOutput, SkillsListInput, is_main_skill_path, list_snapshot,
};
use pl_core::{
    context::{ContextContent, OpaquePayload},
    thread::extensions::ExtensionMutation,
    tool::{
        ToolOutput,
        opaque::{CallContext, Registration, ToolError},
    },
};
use sha2::{Digest, Sha256};
use std::sync::Arc;

/// Stable tool operations; catalog contents and activation state are result data.
#[derive(Debug, Clone, Copy)]
pub enum ThreadSkillKind {
    List,
    View,
}

impl ThreadSkillKind {
    /// Declares the input owned by this tool, without embedding mutable catalog rows.
    pub fn declaration(self) -> pl_agent_tool::ToolDefinition {
        match self {
            Self::List => pl_agent_tool::ToolDefinition::json(
                "skills_list",
                "List or search available skill names and descriptions before loading one by exact name.",
                pl_agent_tool::typed::input_schema_for::<SkillsListInput>(),
            ).expect("valid tool definition"),
            Self::View => pl_agent_tool::ToolDefinition::json(
                "skill_view",
                "Read a skill or a support file. The actual text is retained in history; use it as tool-provided guidance.",
                pl_agent_tool::typed::input_schema_for::<SkillViewInput>(),
            ).expect("valid tool definition"),
        }
    }
}

/// An instance owns fixed discovery sources; each invocation freezes its own result.
#[derive(Debug)]
pub struct ThreadSkillTool {
    definition: pl_agent_tool::ToolDefinition,
    sources: SkillDiscoverySources,
    kind: ThreadSkillKind,
}

impl ThreadSkillTool {
    /// Binds this tool to an immutable workspace/configuration and complete Provider set.
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

    /// Transfers an instance, granting state updates only to the tool that saves read snapshots.
    ///
    /// The supplied preparation has already validated the registration identity.
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

impl pl_agent_tool::Tool for ThreadSkillTool {
    type Input = pl_core::context::OpaquePayload;
    type Context = pl_core::tool::opaque::CallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

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
                let input: SkillsListInput =
                    pl_agent_tool::typed::decode_json(input.content()).map_err(ToolError::new)?;
                let catalog = self
                    .sources
                    .discover(context.cancellation)
                    .await
                    .map_err(ToolError::new)?;
                let value = list_snapshot(&catalog, input).map_err(ToolError::new)?;
                let encoded = serde_json::to_string(&value).map_err(ToolError::new)?;
                Ok(ToolOutput::new(
                    OpaquePayload::new("pl.tool.skill-list", 1, encoded.clone())
                        .map_err(ToolError::new)?,
                    vec![ContextContent::Text {
                        text: Arc::from(encoded),
                    }],
                ))
            }
            ThreadSkillKind::View => {
                let input: SkillViewInput =
                    pl_agent_tool::typed::decode_json(input.content()).map_err(ToolError::new)?;
                let catalog = self
                    .sources
                    .discover(context.cancellation.clone())
                    .await
                    .map_err(ToolError::new)?;
                let definition = catalog
                    .load(
                        &input.target.name,
                        SkillLoadInvocation::Model,
                        context.cancellation.clone(),
                    )
                    .await
                    .map_err(ToolError::new)?;
                let resource = input
                    .file_path
                    .as_deref()
                    .map(str::trim)
                    .filter(|path| !is_main_skill_path(path));
                let (file_path, content) = match resource {
                    Some(path) => (
                        path.to_owned(),
                        catalog
                            .read_resource(
                                &input.target.name,
                                path,
                                SkillLoadInvocation::Model,
                                context.cancellation.clone(),
                            )
                            .await
                            .map_err(ToolError::new)?,
                    ),
                    None => (SKILL_FILE_NAME.to_owned(), definition.content),
                };
                let visible = vec![ContextContent::Text {
                    text: Arc::from(format!(
                        "Skill: {}\nResource: {file_path}\n\n{content}",
                        definition.summary.name
                    )),
                }];
                let result = SkillViewOutput {
                    success: true,
                    skill: definition.summary.clone(),
                    file_path,
                    resource_base: definition.summary.resource_base,
                    resource_hint: "Use filePath to read support resources on demand.".into(),
                    content,
                };
                let payload = OpaquePayload::new(
                    "pl.tool.skill-view",
                    1,
                    serde_json::to_string(&result).map_err(ToolError::new)?,
                )
                .map_err(ToolError::new)?;
                let output = ToolOutput::new(payload.clone(), visible);
                if let Err(source) = catalog
                    .record_model_view(&input.target.name, context.cancellation)
                    .await
                {
                    return Err(ToolError::new(source).with_output(output));
                }
                let id = format!(
                    "pl.tool.skill-view:{}",
                    hex::encode(Sha256::digest(
                        result.skill.name.to_ascii_lowercase().as_bytes()
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

/// Local project Skill mutation, explicitly installed by the product host.
#[derive(Debug)]
pub struct ThreadSkillManageTool {
    catalog: Arc<FrozenSkillCatalog>,
    workspace: crate::workspace::ToolWorkspace,
}

impl ThreadSkillManageTool {
    /// Binds a local project catalog to its writable workspace policy.
    pub fn new(
        catalog: Arc<FrozenSkillCatalog>,
        workspace: crate::workspace::ToolWorkspace,
    ) -> Self {
        Self { catalog, workspace }
    }

    /// Stable mutation schema; no live skill names or directory revisions are embedded.
    pub fn declaration() -> pl_agent_tool::ToolDefinition {
        crate::binding::prepare_native_tool::<Self>()
            .expect("static skill definition")
            .definition()
            .clone()
    }
}

impl pl_agent_tool::typed::TypedTool for ThreadSkillManageTool {
    const NAME: &'static str = "skill_manage";
    const DESCRIPTION: &'static str = "Create, patch, edit or remove local project skills and their support files within the configured writable paths.";
    type Args = super::SkillManageInput;
    type Context = pl_core::tool::opaque::CallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    async fn execute(
        &self,
        input: Self::Args,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        let result = super::manage_snapshot(
            self.catalog.clone(),
            self.workspace.clone(),
            super::ManageRequest {
                input,
                cancellation: context.cancellation,
            },
        )
        .await
        .map_err(ToolError::new)?;
        let encoded = serde_json::to_string(&result).map_err(ToolError::new)?;
        Ok(ToolOutput::new(
            OpaquePayload::new("pl.tool.skill-mutation", 1, encoded.clone())
                .map_err(ToolError::new)?,
            vec![ContextContent::Text {
                text: Arc::from(encoded),
            }],
        ))
    }
}

fn error(message: &str) -> ToolError {
    ToolError::new(super::tool_error("skills", message))
}
