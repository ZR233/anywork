use crate::api::studio::convert::thread_stream::bridge_thread;
use crate::api::studio::types::{
    BridgeAttachmentDraft, BridgeError, StartNewThreadResponse, SubmitPromptResponse,
};

#[derive(Debug, Clone, PartialEq, thiserror::Error)]
pub enum BridgeDraftCommandBeginFailure {
    #[error("Draft command was rejected before dispatch: {error}")]
    Rejected { error: BridgeError },
    #[error("Draft command was registered but its observer could not be returned: {error}")]
    UnknownOutcome { error: BridgeError },
}
impl From<BridgeError> for BridgeDraftCommandBeginFailure {
    fn from(error: BridgeError) -> Self {
        Self::Rejected { error }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAttachmentAdmissionIdentity {
    pub operation_id: String,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadCreationIdentity {
    pub operation_id: String,
    pub project_id: String,
    pub input_id: String,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeCreatedInputExecutionIdentity {
    pub thread_id: String,
    pub input_id: String,
    pub runtime_epoch: String,
    pub incarnation: u64,
}

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAttachmentAdmissionOutcome {
    Returned { drafts: Vec<BridgeAttachmentDraft> },
    Rejected { error: BridgeError },
    UnknownOutcome { error: BridgeError },
}
impl From<pl_protocol::studio::AttachmentAdmissionOutcome> for BridgeAttachmentAdmissionOutcome {
    fn from(value: pl_protocol::studio::AttachmentAdmissionOutcome) -> Self {
        use pl_protocol::studio::AttachmentAdmissionOutcome;
        match value {
            AttachmentAdmissionOutcome::Returned { value } => Self::Returned {
                drafts: value.drafts.into_iter().map(Into::into).collect(),
            },
            AttachmentAdmissionOutcome::Rejected { error } => Self::Rejected {
                error: error.into(),
            },
            AttachmentAdmissionOutcome::UnknownOutcome { error } => Self::UnknownOutcome {
                error: error.into(),
            },
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeThreadCreationOutcome {
    Returned { value: StartNewThreadResponse },
    Rejected { error: BridgeError },
    UnknownOutcome { error: BridgeError },
}
impl From<pl_protocol::studio::ThreadCreationOutcome> for BridgeThreadCreationOutcome {
    fn from(value: pl_protocol::studio::ThreadCreationOutcome) -> Self {
        use pl_protocol::studio::ThreadCreationOutcome;
        match value {
            ThreadCreationOutcome::Returned { value } => Self::Returned {
                value: StartNewThreadResponse {
                    thread: bridge_thread(value.thread),
                    receipt: SubmitPromptResponse {
                        thread_id: value.receipt.thread_id,
                        input_id: value.receipt.input_id,
                        cursor: value.receipt.cursor,
                        request_digest: value.receipt.request_digest,
                    },
                },
            },
            ThreadCreationOutcome::Rejected { error } => Self::Rejected {
                error: error.into(),
            },
            ThreadCreationOutcome::UnknownOutcome { error } => Self::UnknownOutcome {
                error: error.into(),
            },
        }
    }
}
