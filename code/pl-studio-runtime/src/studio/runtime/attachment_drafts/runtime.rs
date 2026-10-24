//! 附件草稿运行时：维护草稿的内存目录与磁盘存储，负责准入、解析、提交、读取与过期清理。

use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};
use std::sync::Arc;

use anyhow::{Context, Result, ensure};
use pl_protocol::studio::{
    AdmitAttachmentDraftsResponse, StudioAttachmentDraft, StudioAttachmentDraftSource,
};
use sha2::{Digest, Sha256};

use crate::studio::store::attachment::AttachmentDraftObject;

use super::inspection::InspectionOwner;
use super::normalize::InspectionCancelled;
use super::source::{LoadedSource, fetch_remote_snapshot, read_local_file};
use super::validate::{
    MAX_BATCH_BYTES, MAX_BATCH_FILES, MAX_FILE_BYTES, admission_rejection, preflight_sources,
    validate_draft_batch,
};

#[derive(Clone)]
pub(in crate::studio::runtime) struct AttachmentDraftRuntime {
    root: Arc<PathBuf>,
    entries: Arc<tokio::sync::Mutex<BTreeMap<String, AttachmentDraftObject>>>,
    inspections: Arc<InspectionOwner>,
}

impl AttachmentDraftRuntime {
    pub(in crate::studio::runtime) fn new(root: PathBuf) -> Result<Self> {
        if root.exists() {
            std::fs::remove_dir_all(&root).context("failed to clear expired attachment drafts")?;
        }
        std::fs::create_dir_all(&root).context("failed to create attachment draft directory")?;
        Ok(Self {
            root: Arc::new(root),
            entries: Arc::new(tokio::sync::Mutex::new(BTreeMap::new())),
            inspections: Default::default(),
        })
    }

    pub(super) async fn admit(
        &self,
        sources: Vec<StudioAttachmentDraftSource>,
    ) -> Result<AdmitAttachmentDraftsResponse> {
        if self.inspections.is_closed() {
            return Err(InspectionCancelled.into());
        }
        let filenames = preflight_sources(&sources).map_err(admission_rejection)?;

        let mut admitted = Vec::with_capacity(sources.len());
        let mut total = 0_u64;
        for (source, filename) in sources.into_iter().zip(filenames) {
            let max_bytes = MAX_FILE_BYTES.min(MAX_BATCH_BYTES - total);
            let result = async {
                let loaded = match source {
                    StudioAttachmentDraftSource::LocalFile { path } => LoadedSource {
                        bytes: read_local_file(Path::new(&path), max_bytes)
                            .await
                            .map_err(admission_rejection)?,
                    },
                    StudioAttachmentDraftSource::RemoteUrl { url, .. } => {
                        fetch_remote_snapshot(&url, max_bytes)
                            .await
                            .map_err(admission_rejection)?
                    }
                };
                self.stage(filename, loaded).await
            }
            .await;
            let draft = match result {
                Ok(draft) => draft,
                Err(error) => {
                    cleanup_drafts(&admitted).await;
                    return Err(error);
                }
            };
            total += draft.byte_size;
            admitted.push(draft);
        }

        self.publish(admitted).await
    }

    pub(super) async fn admit_bytes(
        &self,
        files: Vec<(String, Vec<u8>)>,
    ) -> Result<AdmitAttachmentDraftsResponse> {
        if self.inspections.is_closed() {
            return Err(InspectionCancelled.into());
        }
        ensure!(
            !files.is_empty() && files.len() <= MAX_BATCH_FILES,
            "attachment batch must contain 1 to 32 files"
        );
        let mut total = 0_u64;
        for (_, bytes) in &files {
            ensure!(
                bytes.len() as u64 <= MAX_FILE_BYTES,
                "attachment exceeds 50 MiB"
            );
            total = total
                .checked_add(bytes.len() as u64)
                .context("attachment batch size overflow")?;
            ensure!(total <= MAX_BATCH_BYTES, "attachment batch exceeds 128 MiB");
        }
        let mut admitted = Vec::with_capacity(files.len());
        for (filename, bytes) in files {
            let filename = super::normalize::sanitize_filename(&filename);
            let filename = if filename.is_empty() {
                "attachment".into()
            } else {
                filename
            };
            match self.stage(filename, LoadedSource { bytes }).await {
                Ok(draft) => admitted.push(draft),
                Err(error) => {
                    cleanup_drafts(&admitted).await;
                    return Err(error);
                }
            }
        }
        self.publish(admitted).await
    }

    async fn stage(&self, filename: String, loaded: LoadedSource) -> Result<AttachmentDraftObject> {
        let normalized = self.inspections.inspect(loaded.bytes).await?;
        let draft_id = crate::studio::ids::new_id("attachment-draft");
        let storage_path = self.root.join(&draft_id);
        tokio::fs::write(&storage_path, &normalized.bytes).await?;
        if self.inspections.is_closed() {
            tokio::fs::remove_file(&storage_path)
                .await
                .context("remove cancelled attachment staging")?;
            return Err(InspectionCancelled.into());
        }
        Ok(AttachmentDraftObject {
            draft_id,
            modality: normalized.modality,
            media_type: normalized.media_type,
            filename,
            storage_path,
            byte_size: normalized.bytes.len() as u64,
            content_sha256: hex::encode(Sha256::digest(&normalized.bytes)),
            width: normalized.width,
            height: normalized.height,
        })
    }

    pub(in crate::studio::runtime) fn signal_close(&self) {
        self.inspections.signal_close();
    }

    pub(in crate::studio::runtime) async fn close(&self) -> Result<()> {
        self.inspections.close().await
    }

    async fn publish(
        &self,
        admitted: Vec<AttachmentDraftObject>,
    ) -> Result<AdmitAttachmentDraftsResponse> {
        if let Err(error) = validate_draft_batch(&admitted).map_err(admission_rejection) {
            cleanup_drafts(&admitted).await;
            return Err(error);
        }
        let response = AdmitAttachmentDraftsResponse {
            drafts: admitted.iter().map(public_draft).collect(),
        };
        let mut entries = self.entries.lock().await;
        if self.inspections.is_closed() {
            drop(entries);
            cleanup_drafts(&admitted).await;
            return Err(InspectionCancelled.into());
        }
        for draft in admitted {
            entries.insert(draft.draft_id.clone(), draft);
        }
        Ok(response)
    }

    pub(in crate::studio::runtime) fn validate_batch(
        &self,
        drafts: &[AttachmentDraftObject],
    ) -> Result<()> {
        validate_draft_batch(drafts)
    }

    pub(in crate::studio::runtime) async fn resolve(
        &self,
        draft_ids: &[String],
    ) -> Result<Vec<AttachmentDraftObject>> {
        let entries = self.entries.lock().await;
        let mut seen = BTreeSet::new();
        let mut drafts = Vec::with_capacity(draft_ids.len());
        for draft_id in draft_ids {
            ensure!(seen.insert(draft_id), "duplicate attachment draft id");
            let draft = entries
                .get(draft_id)
                .with_context(|| format!("attachment draft {draft_id} is unavailable"))?;
            drafts.push(draft.clone());
        }
        Ok(drafts)
    }

    pub(in crate::studio::runtime) async fn remove(&self, draft_id: &str) -> Result<bool> {
        let mut entries = self.entries.lock().await;
        let Some(draft) = entries.get(draft_id) else {
            return Ok(false);
        };
        match tokio::fs::remove_file(&draft.storage_path).await {
            Ok(()) => {}
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => return Err(error).context("failed to remove attachment staging"),
        }
        entries.remove(draft_id);
        Ok(true)
    }

    pub(in crate::studio::runtime) async fn read(&self, draft_id: &str) -> Result<Vec<u8>> {
        let path = self
            .entries
            .lock()
            .await
            .get(draft_id)
            .map(|draft| draft.storage_path.clone())
            .with_context(|| format!("attachment draft {draft_id} is unavailable"))?;
        Ok(tokio::fs::read(path).await?)
    }
}

fn public_draft(draft: &AttachmentDraftObject) -> StudioAttachmentDraft {
    StudioAttachmentDraft {
        draft_id: draft.draft_id.clone(),
        modality: draft.modality,
        media_type: draft.media_type.clone(),
        filename: draft.filename.clone(),
        byte_size: draft.byte_size,
        width: draft.width,
        height: draft.height,
    }
}

async fn cleanup_drafts(drafts: &[AttachmentDraftObject]) {
    for draft in drafts {
        let _ = tokio::fs::remove_file(&draft.storage_path).await;
    }
}
