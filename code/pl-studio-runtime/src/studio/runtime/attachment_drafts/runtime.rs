//! 附件草稿运行时：维护草稿的内存目录与磁盘存储，负责准入、解析、提交、读取与过期清理。

use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};
use std::sync::Arc;

use anyhow::{Context, Result, ensure};
use pl_model::model::ModelInfo;
use pl_protocol::studio::{
    AdmitAttachmentDraftsResponse, StudioAttachmentDraft, StudioAttachmentDraftSource,
    StudioAttachmentModality, StudioError,
};
use sha2::{Digest, Sha256};

use crate::studio::store::attachment::AttachmentDraftObject;

use super::normalize::normalize_loaded_source;
use super::source::{
    LoadedSource, MAX_GENERIC_SOURCE_BYTES, MAX_IMAGE_SOURCE_BYTES, fetch_remote_snapshot,
    read_local_file,
};
use super::validate::{
    model_modality, preflight_sources, validate_actual_limits, validate_draft_batch,
    validate_model_source,
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

    pub(super) async fn admit(
        &self,
        sources: Vec<StudioAttachmentDraftSource>,
        model: &ModelInfo,
    ) -> Result<AdmitAttachmentDraftsResponse> {
        let predicted = preflight_sources(&sources, model)?;

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
                        bytes: read_local_file(Path::new(&path), max_bytes).await?,
                        initial_remote_url: None,
                    },
                    StudioAttachmentDraftSource::RemoteUrl { url, .. } => {
                        fetch_remote_snapshot(&url, max_bytes).await.context(
                            StudioError::invalid_argument(
                                "无法下载附件，请检查 HTTPS 地址、访问权限与文件大小。",
                            ),
                        )?
                    }
                };
                let normalized = normalize_loaded_source(&filename, loaded.bytes).context(
                    StudioError::invalid_argument(
                        "附件内容无法解析，文件可能已损坏或格式不受支持。",
                    ),
                )?;
                if normalized.modality != predicted_modality {
                    return Err(
                        StudioError::invalid_argument("附件内容与文件名类型不匹配。").into(),
                    );
                }
                validate_model_source(model, normalized.modality, source_kind)?;
                validate_actual_limits(model, &normalized)?;
                let draft_id = crate::studio::ids::new_id("attachment-draft");
                let storage_path = self.root.join(&draft_id);
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
            let draft = match result {
                Ok(draft) => draft,
                Err(error) => {
                    cleanup_drafts(&admitted).await;
                    return Err(error);
                }
            };
            admitted.push(draft);
        }

        if let Err(error) = validate_draft_batch(model, &admitted) {
            cleanup_drafts(&admitted).await;
            return Err(error);
        }
        let response = AdmitAttachmentDraftsResponse {
            drafts: admitted.iter().map(public_draft).collect(),
        };
        let mut entries = self.entries.lock().await;
        for draft in admitted {
            entries.insert(draft.draft_id.clone(), draft);
        }
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
