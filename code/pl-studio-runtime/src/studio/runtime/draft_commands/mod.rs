//! The two recoverable draft commands, not a general task scheduler or read-resource pool.
mod admission;
mod creation;
mod lifetime;
mod registry;

pub(super) use admission::AdmissionFiles;
pub use admission::StudioAttachmentAdmission;
pub(super) use creation::CreationEvidence;
pub use creation::{
    StudioCreatedInputExecutionSource, StudioThreadCreation, StudioThreadCreationProgress,
};
use lifetime::{closed, issue};
pub use pl_protocol::studio::{
    AdmitAttachmentDraftsRequest, AttachmentAdmissionIdentity, AttachmentAdmissionOutcome,
    BeginThreadCreationRequest, ThreadCreationIdentity, ThreadCreationOutcome,
    ThreadCreationResult, ThreadPreparationProgress,
};
pub use pl_protocol::studio::{FeedCloseIssue, FeedCloseReport, StudioError};
pub(super) use registry::DraftCommandRegistry;
pub(super) use registry::DraftCommandsCloseFailure;
