//! 附件草稿对外 API：校验产品准入上下文，并共享与模型能力无关的草稿 owner。

mod inspection;
pub(in crate::studio) mod normalize;
mod runtime;
mod source;
mod validate;

pub(super) use runtime::AttachmentDraftRuntime;

use anyhow::{Context, Result};
use pl_core::context::{ResourceReadError, ResourceReader, ResourceReference};
use pl_protocol::studio::{
    AdmitAttachmentDraftsRequest, AdmitAttachmentDraftsResponse, StudioAttachmentAdmissionContext,
    StudioError, StudioErrorCode,
};

use crate::resource_store::RESOURCE_ID_PREFIX;

use super::StudioRuntime;
use validate::preflight_sources;

impl StudioRuntime {
    /// 受信宿主读取本 Thread 的精确归档原件，不暴露可变 store 或回读工作区路径。
    /// 调用者须先证明公开资格并持有读取及出站副本预算；此入口只证明归属和字节。
    pub(crate) async fn read_thread_resource_exact(
        &self,
        thread_id: &str,
        reference: ResourceReference,
        cancel: tokio_util::sync::CancellationToken,
    ) -> std::result::Result<std::sync::Arc<[u8]>, ResourceReadError> {
        if cancel.is_cancelled() {
            return Err(ResourceReadError::Cancelled);
        }
        self.read_owned_thread(thread_id).await.map_err(|error| {
            ResourceReadError::Unavailable {
                source: error.into(),
            }
        })?;
        let resources = self
            .store
            .thread_resources(thread_id)
            .await
            .map_err(|error| ResourceReadError::Unavailable {
                source: error.into(),
            })?;
        resources.read(reference, cancel).await
    }

    pub async fn preflight_attachment_drafts(
        &self,
        request: &AdmitAttachmentDraftsRequest,
    ) -> Result<()> {
        self.validate_attachment_context(&request.context).await?;
        preflight_sources(&request.sources).map(|_| ())
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
        let config = self.config_runtime.read()?;
        match context {
            StudioAttachmentAdmissionContext::ExistingThread { thread_id } => {
                let thread = self.read_owned_thread(thread_id).await?;
                let state = self.read_thread_state(thread_id).await?;
                let (_, selector) = crate::studio::model_route::route_record(
                    &state,
                    thread.parent_thread_id.is_some(),
                )?
                .context(StudioError::invalid_argument("会话未保存附件模型路由。"))?;
                let role = if thread.parent_thread_id.is_some() {
                    pl_protocol::AgentRoleId::new(thread.role)?
                } else {
                    crate::config::root_agent_route_id()
                };
                config
                    .config
                    .models
                    .resolve_route(role, &selector)
                    .context(StudioError::invalid_argument(
                        "附件所选模型不可用，请重新选择模型。",
                    ))?;
            }
            StudioAttachmentAdmissionContext::NewThread { route } => {
                let selector = super::settings_api::validated_route(
                    &config.config,
                    "attachment",
                    &route.account_id,
                    &route.model_id,
                    route.effort.as_deref(),
                )
                .context(StudioError::invalid_argument(
                    "附件所选模型不可用，请重新选择模型。",
                ))?;
                config
                    .config
                    .models
                    .resolve_route(crate::config::root_agent_route_id(), &selector)
                    .context(StudioError::invalid_argument(
                        "附件所选模型不可用，请重新选择模型。",
                    ))?;
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
            // Pending metadata can only corroborate saved authorization, never replace it.
            if let Some(pending) = pending.as_ref() {
                let durable = durable.as_ref().ok_or_else(|| {
                    StudioError::new(
                        StudioErrorCode::Busy,
                        "产物尚待可靠保存，请稍后重试。",
                        true,
                    )
                })?;
                anyhow::ensure!(
                    pending == durable,
                    "conflicting canonical public artifact metadata"
                );
            }
            if let Some(reference) = durable {
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
