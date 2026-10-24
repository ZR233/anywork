//! Contract coverage of the common ThreadModel encoding boundary. The host fake only records
//! verified originals and supplies execution paths; Studio's physical backends need host acceptance.
use futures::FutureExt;
use pl_core::{
    context::{
        ContextContent, ContextRecord, ContextSnapshot, ContextSource, OpaquePayload,
        ResourceAccess, ResourceReadError, ResourceReader, ResourceReference,
    },
    model::{ModelFactory, ModelFailureKind, ModelRequest, ToolCallMode},
};
use pl_model::{
    completion::AttachmentModality,
    model::{
        MediaMixPolicy, MediaRepresentation, MediaWireFormat, ModelInfo, ModelInputCapability,
        ModelInputSource, ModelMediaInputProfile, ModelModality, ModelTransportProfile,
    },
    protocol::ProtocolEndpoint,
    runtime::{
        CancellationToken, MaterializedUserFile, ModelRuntime, ThreadCompactionOptions,
        ThreadCompactionStrategy, ThreadModel, UserFileAccess, UserFileError, UserFileMaterializer,
        UserFileRequest, attachment_content, user_attachment_content,
        validate_attachment_content_with_files,
    },
};
use pl_provider_fixture::{FixtureServer, Protocol, Reply, Step, responses_text};
use pretty_assertions::assert_eq;
use serde_json::json;
use std::{
    collections::BTreeMap,
    sync::{Arc, Mutex},
};

#[derive(Debug, Clone, Default)]
struct Originals(BTreeMap<String, Arc<[u8]>>);
impl ResourceReader for Originals {
    async fn read(
        &self,
        reference: ResourceReference,
        _: CancellationToken,
    ) -> Result<Arc<[u8]>, ResourceReadError> {
        self.0
            .get(reference.id())
            .cloned()
            .ok_or_else(|| ResourceReadError::Unavailable {
                source: Box::new(std::io::Error::other("missing original")),
            })
    }
}

#[derive(Debug, Clone, Default)]
struct Files(Arc<Mutex<Vec<UserFileRequest>>>, String);
impl UserFileMaterializer for Files {
    async fn materialize(
        &self,
        request: UserFileRequest,
    ) -> Result<MaterializedUserFile, UserFileError> {
        let path = format!(
            ".anywork/sessions/{}/uploads/{}/file-original",
            if self.1.is_empty() { "test" } else { &self.1 },
            request
                .reference
                .content_digest()
                .strip_prefix("sha256:")
                .unwrap()
        );
        self.0.lock().unwrap().push(request);
        Ok(MaterializedUserFile { path })
    }
}

fn retained(
    originals: &mut Originals,
    name: &str,
    media: &str,
    bytes: Vec<u8>,
) -> ResourceReference {
    let reference = ResourceReference::new(
        name.into(),
        pl_core::context::content_hash(&bytes),
        bytes.len() as u64,
        media.into(),
    )
    .unwrap();
    originals.0.insert(name.into(), bytes.into());
    reference
}

fn request(content: Vec<ContextContent>, originals: Originals) -> ModelRequest {
    ModelRequest {
        thread_id: "user-files-thread".into(),
        turn_id: "turn".into(),
        attempt_id: "attempt".into(),
        context: ContextSnapshot {
            revision: 1,
            records: vec![ContextRecord {
                id: "input".into(),
                turn_id: Some("turn".into()),
                source: ContextSource::User,
                content,
                tool_calls: vec![],
            }]
            .into(),
        },
        tools: Default::default(),
        tool_call_mode: ToolCallMode::Parallel,
        solo_tool_ids: Default::default(),
        committed_private_context: None,
        resources: Some(ResourceAccess::new(originals)),
        cancellation: Default::default(),
        progress: None,
    }
}

fn info(id: &str) -> ModelInfo {
    let mut info = ModelInfo::compatible(id);
    info.binding
        .set_transport(ModelTransportProfile::responses_http());
    info
}
fn factory(endpoint: ProtocolEndpoint, info: ModelInfo, files: &Files) -> ThreadModel {
    ThreadModel::new(
        ModelRuntime::new_with_account_id("fixture", endpoint, info).unwrap(),
        None,
    )
    .with_user_files(UserFileAccess::new(files.clone()))
}
fn image() -> Vec<u8> {
    let mut encoded = std::io::Cursor::new(Vec::new());
    image::DynamicImage::new_rgb8(8, 6)
        .write_to(&mut encoded, image::ImageFormat::Png)
        .unwrap();
    encoded.into_inner()
}

#[derive(Debug)]
struct ObservedOriginals {
    originals: Originals,
    entered: Arc<tokio::sync::Notify>,
}
impl ResourceReader for ObservedOriginals {
    async fn read(
        &self,
        reference: ResourceReference,
        cancellation: CancellationToken,
    ) -> Result<Arc<[u8]>, ResourceReadError> {
        let bytes = self.originals.read(reference, cancellation).await?;
        self.entered.notify_one();
        Ok(bytes)
    }
}

#[test]
fn abandoned_image_preparations_are_joined_and_owners_do_not_seal_other_sessions() {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .max_blocking_threads(1)
        .build()
        .unwrap();
    runtime.block_on(async {
        for mode in ["estimate", "compact", "session", "strict"] {
            // Occupy the real blocking pool. An admitted image task cannot reach terminal state
            // until this gate is released, so a close that detaches instead of joining fails
            // deterministically without a sleep or assumptions about image-processing speed.
            let (release, blocked) = std::sync::mpsc::channel::<()>();
            let (started, entered) = tokio::sync::oneshot::channel();
            let blocker = tokio::task::spawn_blocking(move || {
                let _ = started.send(());
                let _ = blocked.recv(); // Sender drop also releases it on assertion failure.
            });
            entered.await.unwrap();
            let mut originals = Originals::default();
            let reference = retained(&mut originals, "image", "image/png", image());
            let content = if mode == "strict" {
                attachment_content(reference, AttachmentModality::Image).unwrap()
            } else {
                user_attachment_content(reference, AttachmentModality::Image, "source.png".into()).unwrap()
            };
            let mut request = request(vec![content], originals.clone());
            let observed = Arc::new(tokio::sync::Notify::new());
            request.resources = Some(ResourceAccess::new(ObservedOriginals { originals, entered: observed.clone() }));
            let mut vision = info("vision");
            let mut capability = ModelInputCapability::media(ModelModality::Image, vec![ModelInputSource::Local]);
            capability.limits.max_width = Some(if mode == "strict" { 8 } else { 4 });
            capability.limits.media_types = vec!["image/png".into()];
            vision.capabilities.input.push(capability);
            vision.binding.request.media.push(ModelMediaInputProfile {
                modality: ModelModality::Image,
                wire: MediaWireFormat::ResponsesInputImage,
                first_send: vec![MediaRepresentation::DataUrl], replay: vec![MediaRepresentation::DataUrl],
            });
            let model = factory(ProtocolEndpoint::compatible("fixture", "http://127.0.0.1:1"), vision, &Files::default());
            let mut session = ModelFactory::new(model.clone()).open_session().await.unwrap();
            let mut sibling = ModelFactory::new(model.clone()).open_session().await.unwrap();
            let mut work = match mode {
                "estimate" => model.estimate_input(&request, None).map(|result| result.map(|_| ())).boxed(),
                "compact" => model.compact(request.clone(), ThreadCompactionOptions {
                    strategy: ThreadCompactionStrategy::TextSummary,
                    instructions: "compact".into(), requirement: "compact".into(), summary_prefix: "summary".into(), max_output_tokens: None,
                }).map(|result| result.map(|_| ())).boxed(),
                _ => session.prepare(request.clone()).map(|result| result.map(|_| ())).boxed(),
            };
            tokio::select! {
                biased;
                result = &mut work => panic!("{mode} completed before its queued image worker: {result:?}"),
                () = observed.notified() => {}
            }
            drop(work);
            assert!(!request.cancellation.is_cancelled());
            let session_owner = matches!(mode, "session" | "strict");
            let mut closing = if session_owner { session.close().boxed() } else { model.close_preparation().boxed() };
            assert!(closing.as_mut().now_or_never().is_none(), "{mode} close detached its admitted worker");
            drop(closing);
            let mut closing = if session_owner { session.close().boxed() } else { model.close_preparation().boxed() };
            assert!(closing.as_mut().now_or_never().is_none(), "{mode} cancelled close lost its retained join");
            release.send(()).unwrap();
            blocker.await.unwrap();
            closing.await.unwrap();
            if !session_owner {
                assert_eq!(model.estimate_input(&request, None).await.unwrap_err().kind, ModelFailureKind::Cancelled);
                // Closing standalone work must not seal an already-open session.
                session.prepare(request.clone()).await.unwrap();
                session.close().await.unwrap();
            } else {
                // Closing one physical session must not seal standalone work.
                model.estimate_input(&request, None).await.unwrap();
            }
            sibling.prepare(request.clone()).await.unwrap();
            sibling.close().await.unwrap();
            let mut fresh = ModelFactory::new(model.clone()).open_session().await.unwrap();
            fresh.prepare(request).await.unwrap();
            fresh.close().await.unwrap();
            model.close_preparation().await.unwrap();
        }
    });
}

#[tokio::test]
async fn image_derivation_budget_is_not_hidden_as_a_file_fallback() {
    let mut encoded = std::io::Cursor::new(Vec::new());
    image::DynamicImage::new_rgb8(16_385, 1)
        .write_to(&mut encoded, image::ImageFormat::Png)
        .unwrap();
    let mut originals = Originals::default();
    let reference = retained(&mut originals, "wide", "image/png", encoded.into_inner());
    let request = request(
        vec![
            user_attachment_content(reference, AttachmentModality::Image, "wide.png".into())
                .unwrap(),
        ],
        originals,
    );
    let files = Files::default();
    let endpoint = ProtocolEndpoint::compatible("fixture", "http://127.0.0.1:1");
    let mut vision = info("vision");
    let mut capability =
        ModelInputCapability::media(ModelModality::Image, vec![ModelInputSource::Local]);
    capability.limits.media_types = vec!["image/png".into()];
    vision.capabilities.input.push(capability);
    vision.binding.request.media.push(ModelMediaInputProfile {
        modality: ModelModality::Image,
        wire: MediaWireFormat::ResponsesInputImage,
        first_send: vec![MediaRepresentation::DataUrl],
        replay: vec![MediaRepresentation::DataUrl],
    });
    // A raw native pass-through is not constrained by the full-decode derivation budget.
    let raw = factory(endpoint.clone(), vision.clone(), &files);
    raw.estimate_input(&request, None).await.unwrap();
    vision
        .capabilities
        .input
        .last_mut()
        .unwrap()
        .limits
        .max_width = Some(4);
    let derived = factory(endpoint, vision, &files);
    assert_eq!(
        derived
            .estimate_input(&request, None)
            .await
            .unwrap_err()
            .kind,
        ModelFailureKind::Unavailable
    );
    assert!(files.0.lock().unwrap().is_empty());
    raw.close_preparation().await.unwrap();
    derived.close_preparation().await.unwrap();
}

#[tokio::test]
async fn user_originals_are_projected_in_order_and_recomputed_on_route_switch() {
    let fixture = FixtureServer::start(vec![
        Step::prompt(
            Protocol::ResponsesHttp,
            "inspect files",
            0,
            Reply::Sse(responses_text("native and file", "native", "vision")),
        ),
        Step::prompt(
            Protocol::ResponsesHttp,
            "inspect files",
            1,
            Reply::Sse(responses_text("only files", "text", "text")),
        ),
    ])
    .await
    .unwrap();
    let mut originals = Originals::default();
    let png = image();
    let first = retained(&mut originals, "first", "image/png", png.clone());
    // The second occurrence cannot be native once the first consumed max_count. Even a
    // source outside the full-decode budget must go straight to the file route then.
    let mut wide = std::io::Cursor::new(Vec::new());
    image::DynamicImage::new_rgb8(16_385, 1)
        .write_to(&mut wide, image::ImageFormat::Png)
        .unwrap();
    let second = retained(&mut originals, "second", "image/png", wide.into_inner());
    let binary = retained(
        &mut originals,
        "audio",
        "application/octet-stream",
        vec![0, 255, 1, 128],
    );
    let empty = retained(&mut originals, "empty", "text/plain", vec![]);
    // A v1 user attachment is migrated only using its original context source. Its identity
    // and bytes remain untouched; there was no filename in that old durable shape.
    let legacy = ContextContent::Opaque {
        payload: OpaquePayload::new(
            "pl.model.attachment",
            1,
            serde_json::to_string(&json!({"reference":second, "modality":"image"})).unwrap(),
        )
        .unwrap(),
    };
    let request = request(
        vec![
            ContextContent::Text {
                text: "inspect files".into(),
            },
            user_attachment_content(
                first.clone(),
                AttachmentModality::Image,
                "original.png".into(),
            )
            .unwrap(),
            legacy,
            user_attachment_content(
                binary.clone(),
                AttachmentModality::File,
                "audio-no-extension".into(),
            )
            .unwrap(),
            user_attachment_content(empty.clone(), AttachmentModality::File, "empty".into())
                .unwrap(),
        ],
        originals.clone(),
    );
    let durable = request.context.clone();
    let files = Files::default();
    let endpoint = ProtocolEndpoint::compatible("fixture", fixture.base_url());
    let mut vision = info("vision");
    let mut capability =
        ModelInputCapability::media(ModelModality::Image, vec![ModelInputSource::Local]);
    capability.limits.max_count = Some(1);
    capability.limits.max_width = Some(4);
    capability.limits.max_height = Some(4);
    capability.limits.media_types = vec!["image/png".into()];
    vision.capabilities.input.push(capability);
    vision.binding.request.media_mix_policy = MediaMixPolicy::SingleModality;
    vision.binding.request.media.push(ModelMediaInputProfile {
        modality: ModelModality::Image,
        wire: MediaWireFormat::ResponsesInputImage,
        first_send: vec![MediaRepresentation::DataUrl],
        replay: vec![MediaRepresentation::DataUrl],
    });
    let native = factory(endpoint.clone(), vision, &files);
    let preview = native.estimate_input(&request, None).await.unwrap();
    let mut session = ModelFactory::new(native).open_session().await.unwrap();
    let call = session.prepare(request.clone()).await.unwrap();
    assert_eq!(call.input_estimate(), preview);
    call.execute().await.unwrap();
    session.close().await.unwrap();
    let text = factory(endpoint, info("text"), &files);
    validate_attachment_content_with_files(
        request.context.records.iter().flat_map(|record| {
            record
                .content
                .iter()
                .map(move |content| (&record.source, content))
        }),
        &info("text"),
    )
    .unwrap();
    let preview = text.estimate_input(&request, None).await.unwrap();
    let mut session = ModelFactory::new(text).open_session().await.unwrap();
    let call = session.prepare(request.clone()).await.unwrap();
    assert_eq!(call.input_estimate(), preview);
    call.execute().await.unwrap();
    session.close().await.unwrap();
    assert_eq!(
        serde_json::to_value(&request.context).unwrap(),
        serde_json::to_value(&durable).unwrap()
    );
    let records = fixture.recorded();
    let native_parts = records[0].body["input"][0]["content"].as_array().unwrap();
    assert_eq!(
        native_parts
            .iter()
            .map(|part| part["type"].as_str().unwrap())
            .collect::<Vec<_>>(),
        vec![
            "input_text",
            "input_image",
            "input_text",
            "input_text",
            "input_text"
        ]
    );
    use base64::{Engine as _, engine::general_purpose::STANDARD};
    let derived = STANDARD
        .decode(
            native_parts[1]["image_url"]
                .as_str()
                .unwrap()
                .strip_prefix("data:image/png;base64,")
                .unwrap(),
        )
        .unwrap();
    let derived = image::load_from_memory(&derived).unwrap();
    assert!(derived.width() <= 4 && derived.height() <= 4);
    let text_parts = records[1].body["input"][0]["content"].as_array().unwrap();
    assert!(text_parts.iter().all(|part| part["type"] == "input_text"));
    for (part, filename) in text_parts.iter().skip(1).zip([
        "original.png",
        "attachment.png",
        "audio-no-extension",
        "empty",
    ]) {
        let description = part["text"].as_str().unwrap();
        assert!(description.contains(filename));
        assert!(description.contains(".anywork/sessions/test/uploads/"));
        assert!(description.contains("not yet read or interpreted"));
    }
    {
        let captured = files.0.lock().unwrap();
        assert!(captured.iter().any(|request| request.reference == first));
        assert!(captured.iter().any(|request| request.reference == second));
        for request in captured.iter() {
            assert_eq!(
                &request.bytes,
                originals.0.get(request.reference.id()).unwrap()
            );
            request.reference.verify(&request.bytes).unwrap();
        }
    }
    assert_eq!(originals.0["first"].as_ref(), png);
    fixture.finish().await.unwrap();
}

#[derive(Debug)]
struct DeniedFiles;
impl UserFileMaterializer for DeniedFiles {
    async fn materialize(&self, _: UserFileRequest) -> Result<MaterializedUserFile, UserFileError> {
        Err(UserFileError::Unavailable {
            source: Box::new(std::io::Error::new(
                std::io::ErrorKind::PermissionDenied,
                "upload permission denied",
            )),
        })
    }
}

#[tokio::test]
async fn user_file_fallback_never_hides_resource_host_or_native_media_failures() {
    let mut originals = Originals::default();
    let reference = retained(
        &mut originals,
        "binary",
        "application/octet-stream",
        vec![0, 255],
    );
    let request = request(
        vec![
            user_attachment_content(reference.clone(), AttachmentModality::File, "binary".into())
                .unwrap(),
        ],
        originals,
    );
    let base = ThreadModel::new(
        ModelRuntime::new_with_account_id(
            "fixture",
            ProtocolEndpoint::compatible("fixture", "http://127.0.0.1:1"),
            info("text"),
        )
        .unwrap(),
        None,
    );
    assert_eq!(
        base.estimate_input(&request, None).await.unwrap_err().kind,
        ModelFailureKind::UnsupportedContent
    );
    let denied = base
        .clone()
        .with_user_files(UserFileAccess::new(DeniedFiles));
    let failure = denied.estimate_input(&request, None).await.unwrap_err();
    assert_eq!(failure.kind, ModelFailureKind::Unavailable);
    assert!(
        failure
            .source
            .unwrap()
            .to_string()
            .contains("upload permission denied")
    );
    let mut corrupt = request.clone();
    corrupt.resources = Some(ResourceAccess::new(Originals(BTreeMap::from([(
        "binary".into(),
        Arc::from([5_u8]),
    )]))));
    assert_eq!(
        denied
            .estimate_input(&corrupt, None)
            .await
            .unwrap_err()
            .kind,
        ModelFailureKind::IncompatibleContext
    );
    let mut cancelled = request.clone();
    cancelled.cancellation = CancellationToken::new();
    cancelled.cancellation.cancel();
    assert_eq!(
        denied
            .estimate_input(&cancelled, None)
            .await
            .unwrap_err()
            .kind,
        ModelFailureKind::Cancelled
    );
    let mut native = request;
    Arc::make_mut(&mut native.context.records)[0].content =
        vec![attachment_content(reference, AttachmentModality::Image).unwrap()];
    assert_eq!(
        denied.estimate_input(&native, None).await.unwrap_err().kind,
        ModelFailureKind::UnsupportedContent
    );
}

#[tokio::test]
async fn user_file_compaction_uses_the_same_execution_projection_as_preparation() {
    for strategy in [
        ThreadCompactionStrategy::TextSummary,
        ThreadCompactionStrategy::PreferNative,
    ] {
        let old_path = ".anywork/sessions/old/uploads/deleted/source";
        let item = json!({"type":"compaction", "encrypted_content":format!("opaque checkpoint mentions {old_path}")});
        // Neither provider route preserves a reliable reference for the product. The text
        // summary and the opaque native item deliberately remember only a stale path.
        let reply = match strategy {
            ThreadCompactionStrategy::TextSummary => {
                responses_text(old_path, "files-summary", "text")
            }
            ThreadCompactionStrategy::PreferNative => vec![
                json!({"type":"response.output_item.done", "item":item}),
                json!({"type":"response.completed", "response":{"id":"files-compaction", "output":[item]}}),
            ],
        };
        let fixture = FixtureServer::start(
            (0..3)
                .map(|round| {
                    Step::prompt(
                        Protocol::ResponsesHttp,
                        match strategy {
                            ThreadCompactionStrategy::TextSummary => "compact\n\ncompact",
                            ThreadCompactionStrategy::PreferNative => "inspect files",
                        },
                        round,
                        Reply::Sse(reply.clone()),
                    )
                })
                .collect(),
        )
        .await
        .unwrap();
        let mut endpoint = ProtocolEndpoint::compatible("fixture", fixture.base_url());
        endpoint.service_capabilities.remote_compaction = true;
        let mut originals = Originals::default();
        let reference = retained(
            &mut originals,
            "source",
            "application/octet-stream",
            vec![255, 0, 9],
        );
        let attachment =
            user_attachment_content(reference.clone(), AttachmentModality::File, "source".into())
                .unwrap();
        let mut request = request(
            vec![ContextContent::Text {
                text: "inspect files".into(),
            }],
            originals.clone(),
        );
        let active = request.context.records[0].clone();
        request.context.records = vec![
            ContextRecord {
                id: "old-files".into(),
                turn_id: Some("old-turn".into()),
                source: ContextSource::User,
                content: vec![attachment.clone(), attachment.clone()],
                tool_calls: vec![],
            },
            active.clone(),
        ]
        .into();
        let files = Files::default();
        let model = factory(endpoint.clone(), info("text"), &files);
        model.estimate_input(&request, None).await.unwrap();
        let options = ThreadCompactionOptions {
            strategy,
            instructions: "compact".into(),
            requirement: "compact".into(),
            summary_prefix: "summary".into(),
            max_output_tokens: None,
        };
        let first = model
            .compact(request.clone(), options.clone())
            .await
            .unwrap();
        assert_eq!(first.implementation, strategy);
        assert_eq!(
            attachment_references(&first.replacement.records),
            vec![reference.clone()]
        );
        assert_eq!(
            serde_json::to_value(first.replacement.records.last().unwrap()).unwrap(),
            serde_json::to_value(&active).unwrap()
        );
        let inventories = first.replacement.records.iter().filter(|record| matches!(&record.source, ContextSource::Runtime { source_id } if source_id == "model.user-files")).collect::<Vec<_>>();
        assert_eq!(inventories.len(), 1);
        assert!(
            !serde_json::to_string(inventories[0])
                .unwrap()
                .contains("uploads/")
        );

        // Reconstructed context and a fresh host model a cold rebind with no old execution
        // copies. The framework must consult the reliable reference again, not the old path.
        request.context.records =
            serde_json::from_value(serde_json::to_value(first.replacement.records).unwrap())
                .unwrap();
        request.context.revision += 1;
        request.attempt_id = "rebound".into();
        let rebound_files = Files(Default::default(), "rebound".into());
        let rebound = factory(endpoint, info("text"), &rebound_files);
        rebound.estimate_input(&request, None).await.unwrap();
        let mut session = ModelFactory::new(rebound.clone())
            .open_session()
            .await
            .unwrap();
        let prepared = session.prepare(request.clone()).await.unwrap();
        drop(prepared);
        session.close().await.unwrap();
        {
            let calls = rebound_files.0.lock().unwrap();
            assert!(!calls.is_empty());
            for call in calls.iter() {
                assert_eq!(call.reference, reference);
                assert_eq!(call.filename, "source");
                assert_eq!(&call.bytes, originals.0.get("source").unwrap());
            }
        }
        let second = rebound
            .compact(request.clone(), options.clone())
            .await
            .unwrap();
        assert_eq!(
            attachment_references(&second.replacement.records),
            vec![reference.clone()]
        );
        assert_eq!(second.replacement.records.iter().filter(|record| matches!(&record.source, ContextSource::Runtime { source_id } if source_id == "model.user-files")).count(), 1);
        request.context.records = second.replacement.records.into();
        request.context.revision += 1;
        request.attempt_id = "already-retained".into();
        Arc::make_mut(&mut request.context.records)
            .last_mut()
            .unwrap()
            .content
            .push(attachment);
        let third = rebound.compact(request, options).await.unwrap();
        assert_eq!(
            attachment_references(&third.replacement.records),
            vec![reference]
        );
        assert!(third.replacement.records.iter().all(|record| !matches!(&record.source, ContextSource::Runtime { source_id } if source_id == "model.user-files")));
        let records = fixture.recorded();
        assert!(
            records[0]
                .body
                .to_string()
                .contains(".anywork/sessions/test/uploads/")
        );
        assert!(
            records[1]
                .body
                .to_string()
                .contains(".anywork/sessions/rebound/uploads/")
        );
        fixture.finish().await.unwrap();
    }
}

fn attachment_references(records: &[ContextRecord]) -> Vec<ResourceReference> {
    records
        .iter()
        .flat_map(|record| &record.content)
        .filter_map(|content| {
            let ContextContent::Opaque { payload } = content else {
                return None;
            };
            pl_model::runtime::decode_attachment(payload)
                .unwrap()
                .map(|attachment| attachment.reference)
        })
        .collect()
}
