//! Persistent raw media and model-owned image projection for Thread tools.
use crate::resource_store::FileResourceStore;
use pl_core::{context::ContextContent, tool::opaque::ToolError};
use pl_tool::media::{RetainedToolMedia, ToolMedia, ToolMediaHost, ToolMediaKind};
use std::sync::Arc;

/// Shared resource host used by Thread tools that archive media bytes.
#[derive(Debug)]
pub(crate) struct MediaHost(pub(crate) FileResourceStore);

impl ToolMediaHost for MediaHost {
    async fn retain(&self, media: ToolMedia) -> Result<RetainedToolMedia, ToolError> {
        let reference = self
            .0
            .retain_bytes(media.bytes.clone(), &media.media_type)
            .await
            .map_err(ToolError::new)?;
        let context = if let Some(image) = media.model_image {
            let projected = if image.media_type == media.media_type
                && image.bytes.as_ref() == media.bytes.as_ref()
            {
                reference.clone()
            } else {
                self.0
                    .retain_bytes(image.bytes, &image.media_type)
                    .await
                    .map_err(ToolError::new)?
            };
            vec![
                pl_model::runtime::attachment_content(
                    projected,
                    pl_protocol::AttachmentModality::Image,
                )
                .map_err(ToolError::new)?,
            ]
        } else {
            let mut context = vec![ContextContent::Resource {
                reference: reference.clone(),
            }];
            match media.kind {
                ToolMediaKind::Image => context.push(ContextContent::Text { text: Arc::from("Image retained as a resource; this prepared model does not advertise image input.") }),
                ToolMediaKind::Audio | ToolMediaKind::Blob => {}
            }
            context
        };
        Ok(RetainedToolMedia { reference, context })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pl_agent_tool::ToolHandle;
    use pl_core::{
        context::{OpaquePayload, ResourceReader},
        model::{
            DynModelSession, ModelError, ModelRequest, ModelSession, ModelStepOutput,
            ModelToolCall, PreparedModelCall,
        },
        persistence::{SqliteSessionOptions, SqliteSessionStore, ThreadEffectQuery},
        thread::{ModelStepLimit, ThreadHandle, TurnInput, cold::ColdStoreHandle},
    };
    use pl_tool::binding::{ToolCallPolicy, prepare_native_tool, prepare_registration};
    use std::{collections::VecDeque, io::Cursor};

    struct MediaCalls(VecDeque<(&'static str, &'static str)>);
    impl ModelSession for MediaCalls {
        async fn prepare(
            &mut self,
            request: ModelRequest,
        ) -> Result<PreparedModelCall, ModelError> {
            let calls = self
                .0
                .pop_front()
                .map(|(name, input)| {
                    let mut input: serde_json::Value = serde_json::from_str(input).unwrap();
                    if name == "show_files" {
                        // Select the actual normalized attachment from the preceding delivery,
                        // not a guessed resource identity or the removed implicit image selector.
                        let attachment = request
                            .context
                            .records
                            .iter()
                            .rev()
                            .flat_map(|record| record.content.iter().rev())
                            .find_map(|content| match content {
                                ContextContent::Opaque { payload } => {
                                    pl_model::runtime::decode_attachment(payload).unwrap()
                                }
                                _ => None,
                            })
                            .expect("view_image delivered a normalized attachment");
                        input["files"] = serde_json::json!([{
                            "kind": "attachment",
                            "attachmentId": attachment.reference.id(),
                        }]);
                    }
                    ModelToolCall {
                        call_id: request.attempt_id.clone(),
                        tool_id: name.into(),
                        arguments: OpaquePayload::new("application/json", 1, input.to_string())
                            .unwrap(),
                        rejection: None,
                        presentation_contract: None,
                    }
                })
                .into_iter()
                .collect();
            let projection = OpaquePayload::new(
                pl_protocol::tool_projection::FORMAT,
                pl_protocol::tool_projection::VERSION,
                serde_json::to_string(&pl_protocol::tool_projection::ToolProjection {
                    image: Some(pl_protocol::tool_projection::ImageProjection {
                        max_width: Some(4),
                        max_height: Some(4),
                        media_types: vec!["image/png".into(), "image/jpeg".into()],
                        ..Default::default()
                    }),
                })
                .unwrap(),
            )
            .unwrap();
            Ok(PreparedModelCall::new(async move {
                Ok(ModelStepOutput {
                    turn_action: Default::default(),
                    attempt_id: request.attempt_id,
                    base_context_revision: request.context.revision,
                    content: Vec::new(),
                    tool_calls: calls,
                    private_context: None,
                    usage: Default::default(),
                })
            })
            .with_tool_projection(projection))
        }
        async fn close(&mut self) -> Result<(), ModelError> {
            Ok(())
        }
    }

    #[tokio::test]
    async fn media_bindings_keep_original_variant_and_display_receipt_through_cold_history()
    -> anyhow::Result<()> {
        let root = tempfile::tempdir()?;
        let mut encoded = Cursor::new(Vec::new());
        image::DynamicImage::new_rgb8(20, 10).write_to(&mut encoded, image::ImageFormat::Png)?;
        let original = encoded.into_inner();
        std::fs::write(root.path().join("capture.png"), &original)?;
        let resource_root = root.path().join("resources");
        let store = FileResourceStore::new(resource_root.clone());
        let host = Arc::new(MediaHost(store.clone()));
        let backend = Arc::new(
            pl_tool::workspace_file::ExecutorWorkspaceFileBackend::local(
                root.path().to_path_buf(),
                false,
            )
            .await?,
        );
        let view = prepare_native_tool::<pl_tool::image::ThreadViewImageTool<_, MediaHost>>()?;
        let view_registration =
            prepare_registration("view_image", view.definition(), ToolCallPolicy::DirectOnly)?;
        let view = view_registration.attach(ToolHandle::new(view.attach(
            pl_tool::image::ThreadViewImageTool::new(backend.clone(), host.clone()),
        )));
        let show =
            prepare_native_tool::<pl_tool::file_display::ThreadShowFilesTool<_, MediaHost>>()?;
        let show_registration =
            prepare_registration("show_files", show.definition(), ToolCallPolicy::DirectOnly)?;
        let show = show_registration.attach(ToolHandle::new(show.attach(
            pl_tool::file_display::ThreadShowFilesTool::new(backend, host),
        )));
        let options = SqliteSessionOptions {
            path: root.path().join("history.sqlite"),
        };
        let history = SqliteSessionStore::open(options.clone()).await?;
        let thread = ThreadHandle::start(
            "media-bindings".into(),
            DynModelSession::new(MediaCalls(
                [
                    ("view_image", r#"{"path":"capture.png"}"#),
                    ("show_files", r#"{"caption":"  delivered  "}"#),
                ]
                .into(),
            )),
        )?;
        thread
            .attach_storage(ColdStoreHandle::new(history.clone()))
            .await?;
        thread.register_tools(vec![view, show]).await?;
        thread
            .run_turn(TurnInput {
                turn_id: "media".into(),
                attempt_prefix: "media".into(),
                content: vec![ContextContent::Text {
                    text: "inspect and display".into(),
                }],
                max_model_steps: ModelStepLimit::Limited(4.try_into().unwrap()),
                cancellation: Default::default(),
            })
            .await?;
        thread.close().await?;
        history.shutdown().await.unwrap();
        drop((thread, history, store));

        // No current tool, model or renderer is called during this cold read.
        let history = SqliteSessionStore::open(options).await?;
        let page = history
            .query_thread_effects(
                "media-bindings",
                ThreadEffectQuery {
                    before_sequence: None,
                    limit: 64,
                },
            )
            .await?;
        let deliveries = page
            .effects
            .iter()
            .flat_map(|effect| effect.deliveries.iter())
            .collect::<Vec<_>>();
        assert_eq!(deliveries.len(), 2);
        let viewed = deliveries
            .iter()
            .find(|delivery| delivery.tool_id == "view_image")
            .unwrap();
        let receipt = pl_tool::image::saved_view_image_receipt(viewed.output.payload())?.unwrap();
        assert_eq!((receipt.model_width, receipt.model_height), (4, 2));
        assert_eq!(receipt.path, "capture.png");
        let reopened = FileResourceStore::new(resource_root);
        assert_eq!(
            reopened
                .read(receipt.original.clone(), Default::default())
                .await?
                .as_ref(),
            original.as_slice()
        );
        let attachment = viewed
            .delivered_context
            .iter()
            .find_map(|content| match content {
                ContextContent::Opaque { payload } => {
                    pl_model::runtime::decode_attachment(payload).unwrap()
                }
                _ => None,
            })
            .expect("actual normalized attachment delivery");
        assert_ne!(receipt.original.id(), attachment.reference.id());
        let variant = reopened
            .read(attachment.reference.clone(), Default::default())
            .await?;
        let variant = image::load_from_memory(&variant)?;
        assert_eq!((variant.width(), variant.height()), (4, 2));
        let shown = deliveries
            .iter()
            .find(|delivery| delivery.tool_id == "show_files")
            .unwrap();
        let display =
            pl_tool::file_display::saved_file_display_receipt(shown.output.payload())?.unwrap();
        assert_eq!(display.files.len(), 1);
        assert!(
            matches!(&display.files[0], pl_tool::file_display::FileDisplayResult::Ready {
            resource, modality: pl_protocol::AttachmentModality::Image,
            origin: pl_tool::file_display::FileDisplayOrigin::Archive, ..
        } if resource == &attachment.reference)
        );
        assert_eq!(display.caption.as_deref(), Some("delivered"));
        assert!(matches!(shown.delivered_context.as_slice(), [
                ContextContent::Text { text }, ContextContent::Resource { reference }
            ] if text.as_ref() == "File display archived: 1 ready, 0 failed."
                && reference == &attachment.reference));
        history.shutdown().await.unwrap();
        Ok(())
    }
}
