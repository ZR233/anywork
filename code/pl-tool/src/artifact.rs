//! Explicit delivery of an exact reliable original to this Thread's audience.
use crate::media::ToolResourceOrigin;
use pl_core::{
    context::{ContextContent, OpaquePayload, ResourceReference},
    tool::{
        ToolOutput,
        opaque::{CallContext, Registration, RegistryError, Tool, ToolError},
    },
};
use std::{future::Future, sync::Arc};
use tokio_util::sync::CancellationToken;

pub const TOOL_PUBLISH_ARTIFACT: &str = "publish_artifact";
pub const ARTIFACT_FORMAT: &str = "pl.tool.public-artifact";
pub const ARTIFACT_VERSION: u32 = 1;
/// The existing Studio single-original admission ceiling; zero-byte files are valid.
pub const MAX_ARTIFACT_BYTES: u64 = 50 * 1024 * 1024;

#[derive(Debug, Clone, serde::Deserialize, schemars::JsonSchema)]
#[serde(tag = "kind", rename_all = "camelCase", deny_unknown_fields)]
pub enum ArtifactSource {
    WorkspaceFile {
        path: String,
    },
    ThreadResource {
        #[serde(rename = "resourceId")]
        resource_id: String,
    },
}

#[derive(Debug, Clone, serde::Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PublishArtifactInput {
    pub source: ArtifactSource,
    pub display_name: Option<String>,
}

/// A producer receipt, not proof of canonical submission, history saved or platform acceptance.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ArtifactReceipt {
    pub publication_id: String,
    pub origin: ToolResourceOrigin,
    pub resource: ResourceReference,
    pub display_name: String,
}

impl ArtifactReceipt {
    pub fn validate(&self) -> Result<(), ToolError> {
        self.resource.validate().map_err(ToolError::new)?;
        validate_display_name(&self.display_name)?;
        if self.origin.thread_id.is_empty()
            || self.origin.turn_id.is_empty()
            || self.origin.call_id.is_empty()
            || self.publication_id.is_empty()
            || self.resource.byte_len() > MAX_ARTIFACT_BYTES
        {
            return Err(failure("invalid public artifact receipt identity or size"));
        }
        Ok(())
    }
}

pub fn validate_display_name(name: &str) -> Result<(), ToolError> {
    if name.is_empty()
        || matches!(name, "." | "..")
        || name
            .chars()
            .any(|ch| ch == '/' || ch == '\\' || ch.is_control())
    {
        return Err(failure("displayName must be a safe filename, not a path"));
    }
    Ok(())
}

pub fn saved_artifact_receipt(
    payload: &OpaquePayload,
) -> Result<Option<ArtifactReceipt>, ToolError> {
    if payload.format() != ARTIFACT_FORMAT {
        return Ok(None);
    }
    if payload.version() != ARTIFACT_VERSION {
        return Err(failure("unsupported public artifact receipt version"));
    }
    let receipt: ArtifactReceipt =
        serde_json::from_str(payload.content()).map_err(ToolError::new)?;
    receipt.validate()?;
    Ok(Some(receipt))
}

/// Host authority combines current file access, reliable ownership and archive preparation.
/// Merely decoding a receipt never grants publication authority to an arbitrary tool.
pub trait ArtifactHost: std::fmt::Debug + Send + Sync + 'static {
    fn publish(
        &self,
        origin: ToolResourceOrigin,
        input: PublishArtifactInput,
        cancellation: CancellationToken,
    ) -> impl Future<Output = Result<ArtifactReceipt, ToolError>> + Send;
}

#[derive(Debug)]
pub struct ThreadPublishArtifactTool<H: ArtifactHost>(Arc<H>);

impl<H: ArtifactHost> ThreadPublishArtifactTool<H> {
    pub fn new(host: Arc<H>) -> Self {
        Self(host)
    }

    pub fn declaration() -> pl_protocol::ToolSpec {
        declaration()
    }

    pub fn registration(self, declaration: OpaquePayload) -> Result<Registration, RegistryError> {
        Ok(
            Registration::new(TOOL_PUBLISH_ARTIFACT.into(), declaration, self)?
                .foreground_coexisting(),
        )
    }
}

pub fn declaration() -> pl_protocol::ToolSpec {
    pl_protocol::ToolSpec::function(
        TOOL_PUBLISH_ARTIFACT,
        "Publish one exact original file to this Thread's audience. Select a regular file in the current execution workspace or a reliable resource already referenced by this Thread. This does not send to an external chat. Returns a reliable resource, not a history-saved or platform-delivered receipt.",
        schemars::schema_for!(PublishArtifactInput).to_value(),
    )
}

impl<H: ArtifactHost> Tool for ThreadPublishArtifactTool<H> {
    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        if input.format() != "application/json" || input.version() != 1 {
            return Err(failure("unsupported publish_artifact argument encoding"));
        }
        let input: PublishArtifactInput =
            serde_json::from_str(input.content()).map_err(ToolError::new)?;
        if matches!(&input.source, ArtifactSource::ThreadResource { resource_id } if resource_id.is_empty())
        {
            return Err(failure("resourceId must not be empty"));
        }
        if let Some(name) = &input.display_name {
            validate_display_name(name)?;
        }
        let receipt = self
            .0
            .publish(
                ToolResourceOrigin::from_call(&context),
                input,
                context.cancellation,
            )
            .await?;
        receipt.validate()?;
        let payload = OpaquePayload::new(
            ARTIFACT_FORMAT,
            ARTIFACT_VERSION,
            serde_json::to_string(&receipt).map_err(ToolError::new)?,
        )
        .map_err(ToolError::new)?;
        // The resource is descriptor-only in the model codec; original bytes are never expanded.
        Ok(ToolOutput::new(
            payload,
            vec![
                ContextContent::Text {
                    text: "Original archived; publication intent returned for this Thread.".into(),
                },
                ContextContent::Resource {
                    reference: receipt.resource,
                },
            ],
        ))
    }
}

fn failure(message: &str) -> ToolError {
    ToolError::new(crate::tool_error(TOOL_PUBLISH_ARTIFACT, message))
}
