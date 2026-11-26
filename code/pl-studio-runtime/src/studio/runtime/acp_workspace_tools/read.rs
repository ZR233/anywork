use super::{OperationDomain, WorkspaceTools};
use crate::studio::runtime::acp_host_mcp::{HostBinding, attach_binding, prepare_binding};
use crate::tool_json::JsonToolInput;
use base64::{Engine as _, engine::general_purpose::STANDARD};
use pl_agent_tool::{Tool, ToolDefinition, typed::input_schema_for};
use pl_core::{context::OpaquePayload, tool::opaque::ToolError};
use pl_studio_mcp::{HostContent, HostResult, JsonInput};
use pl_tool::{
    collaboration::control::AgentCallContext,
    image::{ImageOutputLimits, TOOL_VIEW_IMAGE, ViewImageInput, prepare_workspace_image},
    workspace_file::{ExecutorWorkspaceFileBackend, WorkspaceFileBackend, read_regular_file},
};
use serde_json::{Value, json};
use std::{
    collections::BTreeMap,
    sync::{Arc, Weak},
};

const MAX_TEXT_BYTES: usize = 256 * 1024;
// Leaves room for base64 and the MCP/IPC envelopes within the 4 MiB IPC limit.
const MAX_IMAGE_BYTES: u64 = 2 * 1024 * 1024;

#[derive(Clone, Copy)]
enum ReadKind {
    Text,
    Image,
}

#[derive(serde::Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
struct TextInput {
    /// File path in the current workspace. Use a workspace-relative POSIX path for SSH.
    path: String,
}

struct ReadTool {
    definition: ToolDefinition,
    kind: ReadKind,
    owner: Weak<WorkspaceTools>,
    backend: Arc<ExecutorWorkspaceFileBackend>,
}

pub(super) fn bind(
    owner: &Arc<WorkspaceTools>,
    backend: Arc<ExecutorWorkspaceFileBackend>,
    bindings: &mut BTreeMap<String, HostBinding>,
) -> anyhow::Result<()> {
    let definitions = [
        (
            ReadKind::Text,
            ToolDefinition::json(
                "read_text_file",
                "Read a UTF-8 file from the current local or SSH workspace (up to 256 KiB).",
                input_schema_for::<TextInput>(),
            )?,
        ),
        (
            ReadKind::Image,
            ToolDefinition::json(
                TOOL_VIEW_IMAGE,
                "View a PNG, JPEG, WebP or GIF image from the current local or SSH workspace. Returns image content for visual inspection.",
                input_schema_for::<ViewImageInput>(),
            )?,
        ),
    ];
    for (kind, definition) in definitions {
        let projection = prepare_binding(bindings, &definition, JsonInput::Object)?;
        let tool = ReadTool {
            definition,
            kind,
            owner: Arc::downgrade(owner),
            backend: Arc::clone(&backend),
        };
        attach_binding(
            bindings,
            projection,
            tool,
            |handle, host, input, context| {
                Box::pin(async move {
                    host.authorize_workspace_call(&context).await?;
                    Ok(match handle.execute(input, context).await {
                        Ok(content) => HostResult {
                            value: Value::Null,
                            is_error: false,
                            content: Some(content),
                        },
                        Err(error) => HostResult {
                            value: json!({"error": error.to_string()}),
                            is_error: true,
                            content: None,
                        },
                    })
                })
            },
        );
    }
    Ok(())
}

impl Tool for ReadTool {
    type Input = OpaquePayload;
    type Context = AgentCallContext;
    type Output = HostContent;
    type Error = ToolError;

    fn definition(&self) -> &ToolDefinition {
        &self.definition
    }

    async fn execute(
        &self,
        input: OpaquePayload,
        context: AgentCallContext,
    ) -> Result<HostContent, ToolError> {
        let args = JsonToolInput::new(&input)?;
        let owner = self
            .owner
            .upgrade()
            .ok_or_else(|| ToolError::new(pl_core::thread::ThreadError::Closed))?;
        let authorization = owner.binding.workspace.authorization();
        if !authorization.is_active()
            || owner.closed.is_cancelled()
            || context.cancellation.is_cancelled()
        {
            return Err(ToolError::new(pl_core::thread::ThreadError::Closed));
        }
        let grant = owner
            .authorize(self.definition.name(), &input, OperationDomain::Workspace)
            .await?;
        let backend = self
            .backend
            .for_grant(&grant)
            .map_or_else(|| Arc::clone(&self.backend), Arc::new);
        match self.kind {
            ReadKind::Text => {
                let TextInput { path } = args.decode()?;
                let bytes = read_regular_file(backend.as_ref(), path, MAX_TEXT_BYTES)
                    .await
                    .map_err(ToolError::new)?;
                let text = String::from_utf8(bytes).map_err(ToolError::new)?;
                Ok(HostContent::Text(text))
            }
            ReadKind::Image => {
                let image = prepare_workspace_image(
                    backend,
                    args.decode()?,
                    ImageOutputLimits {
                        max_bytes: Some(MAX_IMAGE_BYTES),
                        ..Default::default()
                    },
                    context.cancellation,
                )
                .await?;
                Ok(HostContent::Image {
                    data: STANDARD.encode(image.bytes),
                    mime_type: image.media_type,
                })
            }
        }
    }
}
