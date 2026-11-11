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
fn acp_preflight_uses_independent_prompt_capabilities_for_local_and_remote_sources() -> Result<()> {
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
async fn acp_admission_reuses_normalization_preview_and_removal_without_native_model() -> Result<()>
{
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
