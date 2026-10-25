//! 附件草稿运行时：维护草稿的内存目录与磁盘存储，负责准入、解析、提交、读取与过期清理。

use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};
use std::sync::Arc;

use anyhow::{Context, Result, ensure};
use pl_model::model::ModelInfo;
use pl_protocol::studio::{
    AdmitAttachmentDraftsResponse, StudioAttachmentDraft, StudioAttachmentDraftSource,
    StudioAttachmentModality,
};
use sha2::{Digest, Sha256};

use crate::studio::store::attachment::AttachmentDraftObject;

use super::normalize::normalize_loaded_source;
use super::source::{
    LoadedSource, MAX_GENERIC_SOURCE_BYTES, MAX_IMAGE_SOURCE_BYTES, fetch_remote_snapshot,
    read_local_file,
};
use super::validate::{
    admission_rejection, model_modality, preflight_sources, validate_actual_limits,
    validate_draft_batch, validate_model_source,
};

#[derive(Clone)]
pub(in crate::studio::runtime) struct AttachmentDraftRuntime {
    root: Arc<PathBuf>,
    entries: Arc<tokio::sync::Mutex<BTreeMap<String, AttachmentDraftObject>>>,
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
        })
    }

    pub(in crate::studio::runtime) async fn admit(
        &self,
        sources: Vec<StudioAttachmentDraftSource>,
        model: &ModelInfo,
        files: &super::super::draft_commands::AdmissionFiles,
    ) -> Result<AdmitAttachmentDraftsResponse> {
        let predicted = preflight_sources(&sources, model).map_err(admission_rejection)?;

        let mut admitted = Vec::with_capacity(sources.len());
        for (source, (filename, predicted_modality, source_kind)) in
            sources.into_iter().zip(predicted)
        {
            let max_bytes = model
                .capabilities
                .input_capability(model_modality(predicted_modality))
                .and_then(|capability| capability.limits.max_bytes)
                .unwrap_or(match predicted_modality {
                    StudioAttachmentModality::Image => MAX_IMAGE_SOURCE_BYTES,
                    StudioAttachmentModality::Video | StudioAttachmentModality::File => {
                        MAX_GENERIC_SOURCE_BYTES
                    }
                });
            let result = async {
                let loaded = match source {
                    StudioAttachmentDraftSource::LocalFile { path } => LoadedSource {
                        bytes: read_local_file(Path::new(&path), max_bytes)
                            .await
                            .map_err(admission_rejection)?,
                        initial_remote_url: None,
                    },
                    StudioAttachmentDraftSource::RemoteUrl { url, .. } => {
                        fetch_remote_snapshot(&url, max_bytes)
                            .await
                            .map_err(admission_rejection)?
                    }
                };
                let normalized = normalize_loaded_source(&filename, loaded.bytes)
                    .map_err(admission_rejection)?;
                if normalized.modality != predicted_modality {
                    return Err(admission_rejection(anyhow::anyhow!(
                        "attachment content does not match its filename type"
                    )));
                }
                validate_model_source(model, normalized.modality, source_kind)
                    .map_err(admission_rejection)?;
                validate_actual_limits(model, &normalized).map_err(admission_rejection)?;
                let draft_id = crate::studio::ids::new_id("attachment-draft");
                let storage_path = self.root.join(&draft_id);
                // Register before write: a partial file still belongs to this accepted job.
                files.register(storage_path.clone());
                tokio::fs::write(&storage_path, &normalized.bytes).await?;
                Ok::<_, anyhow::Error>(AttachmentDraftObject {
                    draft_id,
                    modality: normalized.modality,
                    media_type: normalized.media_type,
                    filename,
                    storage_path,
                    byte_size: normalized.bytes.len() as u64,
                    content_sha256: hex::encode(Sha256::digest(&normalized.bytes)),
                    width: normalized.width,
                    height: normalized.height,
                    initial_remote_url: loaded.initial_remote_url,
                })
            }
            .await;
            let draft = result?;
            admitted.push(draft);
        }

        validate_draft_batch(model, &admitted).map_err(admission_rejection)?;
        let response = AdmitAttachmentDraftsResponse {
            drafts: admitted.iter().map(public_draft).collect(),
        };
        let mut entries = self.entries.lock().await;
        for draft in admitted {
            entries.insert(draft.draft_id.clone(), draft);
        }
        files.published();
        Ok(response)
    }

    pub(in crate::studio::runtime) fn validate_for_model(
        &self,
        model: &ModelInfo,
        drafts: &[AttachmentDraftObject],
    ) -> Result<()> {
        validate_draft_batch(model, drafts)
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

    /// Open and remove share entries until the actual OS open has finished. The async entries
    /// guard is deliberately retained across that bounded operation, never across hashing/reads.
    pub(in crate::studio::runtime) async fn open_binary(
        &self,
        draft_id: &str,
    ) -> Result<(std::fs::File, u64)> {
        let entries = self.entries.lock().await;
        let draft = entries
            .get(draft_id)
            .ok_or_else(|| pl_protocol::studio::StudioError::not_found("AttachmentDraft"))?;
        let path = draft.storage_path.clone();
        let expected_length = draft.byte_size;
        let file = tokio::task::spawn_blocking(move || std::fs::File::open(path)).await??;
        drop(entries);
        Ok((file, expected_length))
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
