//! 附件草稿对外 API 适配层：解析准入上下文对应的后端能力，并把 preflight、准入、读取与移除请求转发给草稿运行时。

mod normalize;
mod runtime;
mod source;
mod validate;

pub(super) use runtime::AttachmentDraftRuntime;

use anyhow::{Context, Result};
use pl_protocol::session::AgentBackend;
use pl_protocol::studio::{
    AdmitAttachmentDraftsRequest, AdmitAttachmentDraftsResponse, StudioAttachmentAdmissionContext,
    StudioError,
};

use crate::resource_store::{FileResourceStore, RESOURCE_ID_PREFIX};

use super::StudioRuntime;
use validate::{InputPolicy, preflight_sources};

impl StudioRuntime {
    pub async fn preflight_attachment_drafts(
        &self,
        request: &AdmitAttachmentDraftsRequest,
    ) -> Result<()> {
        let policy = self.attachment_policy_for_context(&request.context).await?;
        preflight_sources(&request.sources, &policy).map(|_| ())
    }

    pub async fn admit_attachment_drafts(
        &self,
        request: AdmitAttachmentDraftsRequest,
    ) -> Result<AdmitAttachmentDraftsResponse> {
        let policy = self.attachment_policy_for_context(&request.context).await?;
        self.attachment_drafts.admit(request.sources, &policy).await
    }

    async fn attachment_policy_for_context(
        &self,
        context: &StudioAttachmentAdmissionContext,
    ) -> Result<InputPolicy> {
        if let StudioAttachmentAdmissionContext::ExistingThread { thread_id } = context {
            let (_, agent) = self
                .agent_facility
                .product_events
                .directory_facts(thread_id)
                .context("attachment Thread directory entry is missing")?;
            if matches!(agent.backend, AgentBackend::Acp { .. }) {
                return Ok(InputPolicy::Acp(
                    self.acp_prompt_capabilities_for_thread(thread_id).await?,
                ));
            }
        }
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
        Ok(InputPolicy::Native(Box::new(route.model)))
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
            let facts = self.read_thread_state(&thread_id).await?;
            let mut deliveries = facts.deliveries.to_vec();
            // A completed delivery leaves the resident snapshot. Read pending effects first:
            // once the writer releases an effect from this window, its full delivery is already
            // committed in history. The following history read therefore closes that race.
            if let Some((_, handle)) = self
                .sessions
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
            let store = FileResourceStore::new(self.store.session_resources_dir(&thread_id)?);
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

#[cfg(test)]
mod tests {
    use std::io::Cursor;
    use std::path::Path;

    use anyhow::Result;
    use pl_protocol::studio::acp_schema::PromptCapabilities;
    use pl_protocol::studio::{StudioAttachmentDraftSource, StudioAttachmentModality};

    use super::AttachmentDraftRuntime;
    use super::source::MAX_GENERIC_SOURCE_BYTES;
    use super::validate::{InputPolicy, preflight_sources};

    fn local(path: &Path) -> StudioAttachmentDraftSource {
        StudioAttachmentDraftSource::LocalFile {
            path: path.to_string_lossy().into_owned(),
        }
    }

    fn png() -> Result<Vec<u8>> {
        let mut bytes = Cursor::new(Vec::new());
        image::DynamicImage::new_rgb8(2, 3).write_to(&mut bytes, image::ImageFormat::Png)?;
        Ok(bytes.into_inner())
    }

    #[test]
    fn acp_preflight_uses_independent_prompt_capabilities_for_local_and_remote_sources()
    -> Result<()> {
        for (extension, modality) in [
            ("png", StudioAttachmentModality::Image),
            ("pdf", StudioAttachmentModality::File),
            ("mp4", StudioAttachmentModality::Video),
        ] {
            for (image, embedded_context) in
                [(false, false), (true, false), (false, true), (true, true)]
            {
                let policy = InputPolicy::Acp(
                    PromptCapabilities::new()
                        .image(image)
                        .embedded_context(embedded_context),
                );
                let expected = match modality {
                    StudioAttachmentModality::Image => image,
                    StudioAttachmentModality::File => embedded_context,
                    StudioAttachmentModality::Video => false,
                };
                for source in [
                    local(Path::new(&format!("attachment.{extension}"))),
                    StudioAttachmentDraftSource::RemoteUrl {
                        url: format!("https://example.com/attachment.{extension}"),
                        filename: None,
                    },
                ] {
                    let predicted = preflight_sources(&[source], &policy);
                    assert_eq!(predicted.is_ok(), expected);
                    if expected {
                        assert_eq!(predicted?[0].1, modality);
                    }
                }
            }
        }
        Ok(())
    }

    #[tokio::test]
    async fn acp_admission_reuses_normalization_preview_and_removal_without_native_model()
    -> Result<()> {
        let home = tempfile::tempdir()?;
        let runtime = AttachmentDraftRuntime::new(home.path().join("drafts"))?;
        let image_path = home.path().join("image.png");
        let file_path = home.path().join("context.pdf");
        let image_bytes = png()?;
        let file_bytes = b"%PDF-1.7\nattachment";
        std::fs::write(&image_path, &image_bytes)?;
        std::fs::write(&file_path, file_bytes)?;
        let policy = InputPolicy::Acp(PromptCapabilities::new().image(true).embedded_context(true));
        let admitted = runtime
            .admit(vec![local(&image_path), local(&file_path)], &policy)
            .await?;
        assert_eq!(admitted.drafts.len(), 2);
        assert_eq!(admitted.drafts[0].modality, StudioAttachmentModality::Image);
        assert_eq!(admitted.drafts[0].width, Some(2));
        assert_eq!(admitted.drafts[0].height, Some(3));
        assert_eq!(admitted.drafts[1].modality, StudioAttachmentModality::File);
        assert_eq!(admitted.drafts[1].media_type, "application/pdf");
        for (draft, bytes) in admitted
            .drafts
            .iter()
            .zip([image_bytes.as_slice(), file_bytes])
        {
            assert_eq!(runtime.read(&draft.draft_id).await?, bytes);
            assert!(runtime.remove(&draft.draft_id).await?);
            assert!(!runtime.remove(&draft.draft_id).await?);
            assert!(runtime.read(&draft.draft_id).await.is_err());
        }
        assert_eq!(std::fs::read_dir(home.path().join("drafts"))?.count(), 0);
        Ok(())
    }

    #[tokio::test]
    async fn acp_batch_failure_cleans_new_staging_and_preserves_existing_drafts() -> Result<()> {
        let home = tempfile::tempdir()?;
        let root = home.path().join("drafts");
        let runtime = AttachmentDraftRuntime::new(root.clone())?;
        let valid = home.path().join("context.txt");
        std::fs::write(&valid, b"context")?;
        let disguised_image = home.path().join("disguised.txt");
        std::fs::write(&disguised_image, png()?)?;
        let oversized = home.path().join("oversized.txt");
        std::fs::File::create(&oversized)?.set_len(MAX_GENERIC_SOURCE_BYTES + 1)?;
        let corrupt_image = home.path().join("corrupt.png");
        std::fs::write(&corrupt_image, b"\x89PNG\r\n\x1a\ncorrupt")?;
        let policy = InputPolicy::Acp(PromptCapabilities::new().image(true).embedded_context(true));
        let existing = runtime.admit(vec![local(&valid)], &policy).await?;
        let existing_id = &existing.drafts[0].draft_id;
        for invalid in [
            home.path().join("missing.txt"),
            disguised_image,
            oversized,
            corrupt_image,
        ] {
            assert!(
                runtime
                    .admit(vec![local(&valid), local(&invalid)], &policy)
                    .await
                    .is_err()
            );
            assert_eq!(std::fs::read_dir(&root)?.count(), 1);
            assert_eq!(runtime.read(existing_id).await?, b"context");
            assert_eq!(
                runtime
                    .resolve(std::slice::from_ref(existing_id))
                    .await?
                    .len(),
                1
            );
        }
        runtime.remove(existing_id).await?;
        Ok(())
    }

    #[cfg(target_os = "linux")]
    mod public_api {
        use anyhow::{Context, Result};
        use pl_protocol::studio::{
            AdmitAttachmentDraftsRequest, StudioAttachmentAdmissionContext, StudioError,
        };

        use super::local;
        use crate::acp_transport_fixture::AcpTransportFixture as Fixture;

        #[tokio::test]
        async fn acp_thread_admission_reads_ready_session_capabilities_without_opening_another_session()
        -> Result<()> {
            let fixture = Fixture::new("replay").await?;
            let missing = AdmitAttachmentDraftsRequest {
                context: StudioAttachmentAdmissionContext::ExistingThread {
                    thread_id: "missing".into(),
                },
                sources: vec![local(&fixture.home.path().join("context.pdf"))],
            };
            assert!(
                fixture
                    .runtime
                    .preflight_attachment_drafts(&missing)
                    .await
                    .is_err()
            );
            assert!(!fixture.home.path().join("pid").exists());
            let mut open = fixture.open().await?;
            Fixture::ready(&mut open).await?;
            let pid = fixture.pid("pid")?;
            let calls = std::fs::read(fixture.home.path().join("calls"))?;
            for filename in ["image.png", "context.pdf", "movie.mp4"] {
                let request = AdmitAttachmentDraftsRequest {
                    context: StudioAttachmentAdmissionContext::ExistingThread {
                        thread_id: open.target.thread_id.clone(),
                    },
                    sources: vec![local(&fixture.home.path().join(filename))],
                };
                for error in [
                    fixture
                        .runtime
                        .preflight_attachment_drafts(&request)
                        .await
                        .unwrap_err(),
                    fixture
                        .runtime
                        .admit_attachment_drafts(request)
                        .await
                        .unwrap_err(),
                ] {
                    let failure = error
                        .downcast_ref::<StudioError>()
                        .context("typed admission failure")?;
                    assert!(failure.to_string().contains("ACP"));
                }
            }
            assert_eq!(std::fs::read(fixture.home.path().join("calls"))?, calls);
            fixture
                .runtime
                .close_acp_session(open.target.clone())
                .await?;
            let request = AdmitAttachmentDraftsRequest {
                context: StudioAttachmentAdmissionContext::ExistingThread {
                    thread_id: open.target.thread_id,
                },
                sources: vec![local(&fixture.home.path().join("context.pdf"))],
            };
            assert!(
                fixture
                    .runtime
                    .preflight_attachment_drafts(&request)
                    .await
                    .is_err()
            );
            fixture.runtime.shutdown_runtime().await?;
            assert!(!std::path::Path::new(&format!("/proc/{pid}")).exists());
            Ok(())
        }
    }
}
