//! One owner of registered/uploaded bytes and their exact message bindings.

use std::collections::{BTreeSet, HashMap, VecDeque};
use std::sync::Arc;

use anyhow::{Result, ensure};
use axum::body::Bytes;
use axum::http::HeaderValue;
use sha2::{Digest, Sha256};
use tokio::sync::Semaphore;

use super::{
    MAX_FILE_BYTES, MAX_MEDIA_IN_FLIGHT, MAX_MEDIA_REQUESTS, MAX_RESOURCE_COUNT,
    MAX_RETAINED_BYTES, MediaStatus, ResourceDownloadDisposition, ResourceDownloadObservation,
    ResourceSummary, UploadDisposition, UploadObservation,
};
use crate::feishu::state::HangGate;

pub(crate) struct StoredResource {
    pub summary: ResourceSummary,
    pub bytes: Bytes,
    pub messages: BTreeSet<String>,
}

pub(crate) struct MediaState {
    pub file_message_key_mode: super::FileMessageKeyMode,
    pub message_keys: HashMap<(String, String), String>,
    pub resources: HashMap<String, StoredResource>,
    pub retained_bytes: usize,
    pub requests: usize,
    pub request_budget_exhausted: bool,
    pub permits: Arc<Semaphore>,
    pub upload_script: VecDeque<UploadDisposition>,
    pub download_script: VecDeque<ResourceDownloadDisposition>,
    pub upload_hang: HangGate,
    pub download_hang: HangGate,
    pub uploads: Vec<UploadObservation>,
    pub downloads: Vec<ResourceDownloadObservation>,
    pub upload_seq: u64,
}

impl MediaState {
    pub fn new() -> Self {
        Self {
            file_message_key_mode: super::FileMessageKeyMode::PreserveUploadKey,
            message_keys: HashMap::new(),
            resources: HashMap::new(),
            retained_bytes: 0,
            requests: 0,
            request_budget_exhausted: false,
            permits: Arc::new(Semaphore::new(MAX_MEDIA_IN_FLIGHT)),
            upload_script: VecDeque::new(),
            download_script: VecDeque::new(),
            upload_hang: HangGate::new(),
            download_hang: HangGate::new(),
            uploads: Vec::new(),
            downloads: Vec::new(),
            upload_seq: 0,
        }
    }

    pub fn status(&self) -> MediaStatus {
        MediaStatus {
            resources: self.resources.len(),
            retained_bytes: self.retained_bytes,
            requests: self.requests,
            in_flight: MAX_MEDIA_IN_FLIGHT - self.permits.available_permits(),
            request_budget_exhausted: self.request_budget_exhausted,
        }
    }

    pub fn admit_request(&mut self) -> bool {
        if self.requests >= MAX_MEDIA_REQUESTS {
            self.request_budget_exhausted = true;
            return false;
        }
        self.requests += 1;
        true
    }

    pub fn insert(&mut self, resource: StoredResource) -> Result<ResourceSummary> {
        ensure!(!resource.bytes.is_empty(), "resource is empty");
        ensure!(
            resource.bytes.len() <= MAX_FILE_BYTES,
            "resource exceeds 30 MB"
        );
        ensure!(
            self.resources.len() < MAX_RESOURCE_COUNT,
            "resource count limit"
        );
        ensure!(
            resource.bytes.len() <= MAX_RETAINED_BYTES - self.retained_bytes,
            "retained resource byte limit"
        );
        ensure!(
            !self.resources.contains_key(&resource.summary.file_key),
            "resource key already registered"
        );
        let summary = resource.summary.clone();
        self.retained_bytes += resource.bytes.len();
        self.resources.insert(summary.file_key.clone(), resource);
        Ok(summary)
    }
}

pub(crate) fn digest(bytes: &[u8]) -> String {
    hex::encode(Sha256::digest(bytes))
}

pub(crate) fn valid_identity(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 256
        && value
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || b"_-".contains(&c))
}

pub(crate) fn valid_file_name(value: &str) -> bool {
    !value.is_empty() && value.len() <= 1024 && !value.chars().any(char::is_control)
}

pub(crate) fn valid_mime(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 256
        && value.contains('/')
        && value.is_ascii()
        && HeaderValue::from_str(value).is_ok()
}
