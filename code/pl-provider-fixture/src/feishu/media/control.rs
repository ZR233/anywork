//! Resource-only environment controls. All registration and scripts are bounded.

use std::collections::BTreeSet;

use anyhow::{Result, ensure};

use super::state::{StoredResource, digest, valid_file_name, valid_identity, valid_mime};
use super::{
    MAX_FILE_BYTES, MAX_SCRIPT_STEPS, MediaStatus, ResourceDownloadDisposition, ResourceOrigin,
    ResourceSummary, SyntheticResource, UploadDisposition,
};
use crate::feishu::FeishuControl;

impl FeishuControl {
    /// Register one nonempty resource, without emitting an event. Keys are unique
    /// for the lifetime of this peer; no overwrite or eviction masks references.
    ///
    /// # Errors
    /// Rejects invalid metadata, shutdown, duplicate keys, or count/byte limits.
    pub async fn register_resource(&self, resource: SyntheticResource) -> Result<ResourceSummary> {
        ensure!(
            valid_identity(&resource.message_id),
            "invalid resource message id"
        );
        ensure!(valid_identity(&resource.file_key), "invalid resource key");
        ensure!(
            valid_file_name(&resource.file_name),
            "invalid resource file name"
        );
        ensure!(
            valid_mime(&resource.mime_type),
            "invalid resource MIME type"
        );
        ensure!(!resource.bytes.is_empty(), "resource is empty");
        ensure!(
            resource.bytes.len() <= MAX_FILE_BYTES,
            "resource exceeds 30 MB"
        );
        let summary = ResourceSummary {
            file_key: resource.file_key,
            kind: resource.kind,
            file_name: resource.file_name,
            mime_type: resource.mime_type,
            byte_len: resource.bytes.len(),
            sha256: digest(&resource.bytes),
            origin: ResourceOrigin::Synthetic {
                message_id: resource.message_id.clone(),
            },
        };
        let stored = StoredResource {
            summary,
            bytes: resource.bytes.into(),
            messages: BTreeSet::from([resource.message_id]),
        };
        let mut inner = self.shared.lock().await;
        ensure!(!inner.closing, "peer is shutting down");
        inner.media.insert(stored)
    }

    pub async fn media_status(&self) -> MediaStatus {
        self.shared.lock().await.media.status()
    }

    /// Replace future upload outcomes. A request selects its step after its
    /// multipart body validates; already-selected steps stay frozen. Replacing
    /// scripts never releases a hang, and rearming with waiters is rejected.
    pub async fn set_upload_script(&self, steps: Vec<UploadDisposition>) -> Result<()> {
        ensure!(steps.len() <= MAX_SCRIPT_STEPS, "upload script step limit");
        for step in &steps {
            if let UploadDisposition::Reject { code, msg } = step {
                ensure!(*code != 0 && msg.len() <= 1024, "invalid upload rejection");
            }
        }
        let mut inner = self.shared.lock().await;
        ensure!(!inner.closing, "peer is shutting down");
        if steps
            .iter()
            .any(|step| matches!(step, UploadDisposition::Hang))
        {
            ensure!(
                !inner
                    .media
                    .uploads
                    .iter()
                    .any(|fact| fact.outcome == super::UploadOutcome::Waiting
                        && fact.disposition == Some(UploadDisposition::Hang)),
                "release in-flight uploads before rearming a hang generation"
            );
            inner.media.upload_hang.arm();
        } else {
            inner.media.upload_hang.clear();
        }
        inner.media.upload_script = steps.into();
        Ok(())
    }

    pub async fn release_upload(&self) {
        self.shared.lock().await.media.upload_hang.release();
    }

    /// Independent from upload and message-send scripts. Invalid key/type
    /// requests never consume a valid download's fault step. Rearming while
    /// hang waiters remain returns an error rather than implicitly waking them.
    pub async fn set_resource_download_script(
        &self,
        steps: Vec<ResourceDownloadDisposition>,
    ) -> Result<()> {
        ensure!(
            steps.len() <= MAX_SCRIPT_STEPS,
            "download script step limit"
        );
        for step in &steps {
            if let ResourceDownloadDisposition::Reject { code, msg } = step {
                ensure!(
                    *code != 0 && msg.len() <= 1024,
                    "invalid download rejection"
                );
            }
        }
        let mut inner = self.shared.lock().await;
        ensure!(!inner.closing, "peer is shutting down");
        if steps
            .iter()
            .any(|step| matches!(step, ResourceDownloadDisposition::Hang))
        {
            ensure!(
                !inner.media.downloads.iter().any(|fact| fact.outcome
                    == super::ResourceDownloadOutcome::Waiting
                    && fact.disposition == Some(ResourceDownloadDisposition::Hang)),
                "release in-flight downloads before rearming a hang generation"
            );
            inner.media.download_hang.arm();
        } else {
            inner.media.download_hang.clear();
        }
        inner.media.download_script = steps.into();
        Ok(())
    }

    pub async fn release_resource_download(&self) {
        self.shared.lock().await.media.download_hang.release();
    }
}
