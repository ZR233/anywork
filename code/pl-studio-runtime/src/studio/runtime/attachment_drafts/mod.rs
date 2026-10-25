//! 附件草稿对外 API：校验产品准入上下文，并共享与模型能力无关的草稿 owner。

mod inspection;
pub(in crate::studio) mod normalize;
mod runtime;
mod source;
mod validate;

pub(super) use runtime::AttachmentDraftRuntime;

use anyhow::{Context, Result};
use pl_protocol::studio::{
    AdmitAttachmentDraftsRequest, AdmitAttachmentDraftsResponse, StudioAttachmentAdmissionContext,
};

use crate::resource_store::RESOURCE_ID_PREFIX;

use super::StudioRuntime;
use validate::{admission_rejection, preflight_sources};

impl StudioRuntime {
    pub async fn preflight_attachment_drafts(
        &self,
        request: &AdmitAttachmentDraftsRequest,
    ) -> Result<()> {
        self.validate_attachment_context(&request.context).await?;
        preflight_sources(&request.sources)
            .map(|_| ())
            .map_err(admission_rejection)
    }

    pub async fn admit_attachment_drafts(
        &self,
        request: AdmitAttachmentDraftsRequest,
    ) -> Result<AdmitAttachmentDraftsResponse> {
        self.validate_attachment_context(&request.context).await?;
        self.attachment_drafts.admit(request.sources).await
    }

    /// Admits already downloaded user bytes through the ordinary product draft owner.
    /// Callers own platform authorization and transport completeness, not media policy.
    pub async fn admit_attachment_bytes(
        &self,
        files: Vec<(String, Vec<u8>)>,
    ) -> Result<AdmitAttachmentDraftsResponse> {
        self.attachment_drafts.admit_bytes(files).await
    }

    async fn validate_attachment_context(
        &self,
        context: &StudioAttachmentAdmissionContext,
    ) -> Result<()> {
        match context {
            StudioAttachmentAdmissionContext::ExistingThread { thread_id } => {
                self.read_owned_thread(thread_id).await?;
            }
            StudioAttachmentAdmissionContext::NewThread { mode } => {
                let mode = pl_protocol::ThreadModeId::from_label(mode)
                    .map_err(|_| anyhow::anyhow!("mode must be an available mode.* id"))?;
                self.thread_modes
                    .snapshot()
                    .mode(&mode)
                    .context("requested Thread Mode is unavailable")?;
            }
        }
        Ok(())
    }

    pub async fn remove_attachment_draft(&self, draft_id: String) -> Result<bool> {
        self.attachment_drafts.remove(&draft_id).await
    }

    pub async fn read_attachment_draft(&self, draft_id: String) -> Result<Vec<u8>> {
        self.attachment_drafts.read(&draft_id).await
    }

    pub async fn read_thread_attachment(
        &self,
        thread_id: String,
        attachment_id: String,
    ) -> Result<Vec<u8>> {
        self.read_owned_thread(&thread_id).await?;
        if attachment_id.starts_with(RESOURCE_ID_PREFIX) {
            // Pending first, then durable: dequeue is allowed only after the exact typed item is saved.
            let pending = self
                .store
                .thread_persistence()
                .history_channel(&thread_id)
                .pending_public_artifact(&attachment_id)?;
            let history = self.store.history(&thread_id).await?;
            let durable = history.public_artifact_reference(&attachment_id).await?;
            anyhow::ensure!(
                pending
                    .as_ref()
                    .zip(durable.as_ref())
                    .is_none_or(|(pending, durable)| pending == durable),
                "conflicting canonical public artifact metadata"
            );
            if let Some(reference) = pending.or(durable) {
                use pl_core::context::ResourceReader;
                let bytes = self
                    .store
                    .thread_resources(&thread_id)
                    .await?
                    .read(reference, tokio_util::sync::CancellationToken::new())
                    .await?;
                return Ok(bytes.to_vec());
            }
            let facts = self.read_thread_state(&thread_id).await?;
            let mut deliveries = facts.deliveries.to_vec();
            // A completed delivery leaves the resident snapshot. Read pending effects first:
            // once the writer releases an effect from this window, its full delivery is already
            // committed in history. The following history read therefore closes that race.
            if let Some((_, handle)) = self
                .threads
                .observed_threads()
                .into_iter()
                .find(|(id, _)| id == &thread_id)
            {
                for effect in handle.effects().await? {
                    deliveries.extend(effect.deliveries.iter().cloned());
                }
            }
            deliveries.extend(
                self.store
                    .history(&thread_id)
                    .await?
                    .tool_media_deliveries(&attachment_id)
                    .await?,
            );
            let store = self.store.thread_resources(&thread_id).await?.reader();
            return crate::studio::thread_projection::read_persisted_media(
                &store,
                &deliveries,
                &attachment_id,
            )
            .await;
        }
        self.store
            .read_attachment_bytes(&thread_id, &attachment_id)
            .await
    }
}
