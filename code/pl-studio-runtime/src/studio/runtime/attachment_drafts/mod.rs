//! 附件草稿 preflight、准入上下文与删除；实际准入工作归 draft_commands 的原任务 owner。

mod normalize;
mod runtime;
mod source;
mod validate;

pub(super) use runtime::AttachmentDraftRuntime;

use anyhow::{Context, Result};
use pl_model::model::ModelInfo;
use pl_protocol::studio::{AdmitAttachmentDraftsRequest, StudioAttachmentAdmissionContext, StudioError};

use super::StudioRuntime;
use validate::preflight_sources;

impl StudioRuntime {
    pub async fn preflight_attachment_drafts(
        &self,
        request: &AdmitAttachmentDraftsRequest,
    ) -> Result<()> {
        let model = self.attachment_model_for_context(&request.context).await?;
        preflight_sources(&request.sources, &model).map(|_| ())
    }

    pub(in crate::studio::runtime) async fn attachment_model_for_context(
        &self,
        context: &StudioAttachmentAdmissionContext,
    ) -> Result<ModelInfo> {
        let config = self.config_runtime.read()?;
        let route = match context {
            StudioAttachmentAdmissionContext::ExistingThread { thread_id } => {
                let thread = self.read_owned_thread(thread_id).await?;
                let state = self.read_thread_state(thread_id).await?;
                let (_, selector) = crate::studio::model_route::route_record(
                    &state,
                    thread.parent_thread_id.is_some(),
                )?
                .context("Thread has no saved model route")?;
                let role = if thread.parent_thread_id.is_some() {
                    pl_protocol::AgentRoleId::new(thread.role)?
                } else {
                    crate::config::root_agent_route_id()
                };
                config.config.models.resolve_route(role, &selector)?
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
                    ))?
            }
        };
        Ok(route.model)
    }

    pub async fn remove_attachment_draft(&self, draft_id: String) -> Result<bool> {
        self.attachment_drafts.remove(&draft_id).await
    }
}
