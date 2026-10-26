//! Recoverable identities and typed outcomes of the two concrete draft commands.
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use super::{
    AdmitAttachmentDraftsRequest, AdmitAttachmentDraftsResponse, CreateThreadRequest, StudioError,
    SubmitPromptReceipt,
};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BeginAttachmentAdmissionRequest {
    pub operation_id: String,
    pub request: AdmitAttachmentDraftsRequest,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BeginThreadCreationRequest {
    pub operation_id: String,
    pub project_id: String,
    pub request: CreateThreadRequest,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct AttachmentAdmissionIdentity {
    pub operation_id: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ThreadCreationIdentity {
    pub operation_id: String,
    pub project_id: String,
    pub input_id: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum AttachmentAdmissionOutcome {
    Returned {
        value: AdmitAttachmentDraftsResponse,
    },
    Rejected {
        error: StudioError,
    },
    UnknownOutcome {
        error: StudioError,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ThreadCreationResult {
    pub thread: crate::Thread,
    pub receipt: SubmitPromptReceipt,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum ThreadCreationOutcome {
    Returned { value: Box<ThreadCreationResult> },
    Rejected { error: StudioError },
    UnknownOutcome { error: StudioError },
}
