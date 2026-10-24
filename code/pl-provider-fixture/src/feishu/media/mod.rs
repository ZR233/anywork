//! Independent Feishu resource samples, bounded controls, and safe HTTP facts.
//!
//! These types describe the synthetic platform only, never product admission,
//! chat/thread ownership, tool authorization, or delivery classification.

mod control;
pub(super) mod download;
mod http;
pub(super) mod state;
mod types;
pub(super) mod upload;

pub use types::{
    FileType, MAX_FILE_BYTES, MAX_MEDIA_IN_FLIGHT, MAX_MEDIA_REQUESTS, MAX_RESOURCE_COUNT,
    MAX_RETAINED_BYTES, MAX_SCRIPT_STEPS, MediaStatus, ResourceDownloadDisposition,
    ResourceDownloadObservation, ResourceDownloadOutcome, ResourceDownloadType, ResourceKind,
    ResourceOrigin, ResourceSummary, SyntheticResource, UploadDisposition, UploadObservation,
    UploadOutcome,
};
