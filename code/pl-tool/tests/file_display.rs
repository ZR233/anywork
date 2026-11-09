use pl_agent_tool::typed::TypedTool;
use pl_core::{
    context::{ContextContent, ContextRecord, ContextSource, OpaquePayload, ResourceReference},
    tool::opaque::{CallContext, ToolError},
};
use pl_tool::{
    file_display::{
        FileDisplayOrigin, FileDisplayResult, ShowFilesInput, ThreadShowFilesTool,
        saved_file_display_receipt,
    },
    media::{RetainedToolMedia, ToolMedia, ToolMediaHost},
    workspace_file::*,
};
use std::sync::{Arc, Mutex};

#[path = "support/binding_host.rs"]
mod host;

#[path = "support/file_display_ssh.rs"]
mod ssh;

#[derive(Debug, Default)]
struct Media(Mutex<Vec<Vec<u8>>>);
impl ToolMediaHost for Media {
    async fn retain(&self, media: ToolMedia) -> Result<RetainedToolMedia, ToolError> {
        assert!(media.model_image.is_none());
        self.0.lock().unwrap().push(media.bytes.to_vec());
        let digest = pl_core::context::content_hash(&media.bytes);
        let reference = ResourceReference::new(
            digest.clone(),
            digest,
            media.bytes.len() as u64,
            media.media_type,
        )
        .unwrap();
        // Even a host-provided model projection must never escape through show_files.
        let context = vec![
            pl_model::runtime::attachment_content(
                reference.clone(),
                pl_protocol::AttachmentModality::Image,
            )
            .unwrap(),
        ];
        Ok(RetainedToolMedia { reference, context })
    }
}

fn context() -> CallContext {
    CallContext {
        thread_id: "files".into(),
        turn_id: "turn".into(),
        call_id: "call".into(),
        cancellation: Default::default(),
        extensions: Default::default(),
        catalog: Arc::from([]),
        extension_sequence: 0,
        grant: Default::default(),
        context: Default::default(),
        history_fence: 0,
        model_projection: None,
        tasks: None,
    }
}

fn args(value: serde_json::Value) -> ShowFilesInput {
    serde_json::from_value(value).unwrap()
}

#[tokio::test]
async fn ordered_partial_results_keep_exact_bytes_and_do_not_project_model_media() {
    let temp = tempfile::tempdir().unwrap();
    std::fs::write(temp.path().join("a.txt"), "exact original\n").unwrap();
    std::fs::write(temp.path().join("bad.png"), b"\x89PNG\r\n\x1a\ncorrupt").unwrap();
    let large = std::fs::File::create(temp.path().join("large.bin")).unwrap();
    large.set_len(50 * 1024 * 1024 + 1).unwrap();
    let backend = Arc::new(
        LocalWorkspaceFileBackend::new(temp.path().into(), false)
            .await
            .unwrap(),
    );
    let media = Arc::new(Media::default());
    let tool = ThreadShowFilesTool::new(backend, media.clone());
    let confined = pl_tool::approval::assess("show_files", &serde_json::json!({
        "files":[{"kind":"workspace","path":"a.txt"},{"kind":"attachment","attachmentId":"/not/a/path"}]
    }).to_string(), temp.path());
    assert!(!confined.requested_access.allows_external());
    let external = pl_tool::approval::assess(
        "show_files",
        &serde_json::json!({
            "files":[{"kind":"workspace","path":"../outside.txt"}]
        })
        .to_string(),
        temp.path(),
    );
    assert!(external.requested_access.allows_external());
    let remote = pl_tool::approval::assess_remote(
        "show_files",
        &serde_json::json!({
            "files":[{"kind":"workspace","path":"/remote/outside.txt"}]
        })
        .to_string(),
        std::path::Path::new("/remote/workspace"),
    );
    assert!(remote.requested_access.allows_external());
    let output = tool
        .execute(
            args(serde_json::json!({
                "caption":"  delivered  ",
                "files":[
                    {"kind":"workspace","path":"a.txt"},
                    {"kind":"workspace","path":"missing"},
                    {"kind":"workspace","path":"a.txt"},
                    {"kind":"workspace","path":"bad.png"},
                    {"kind":"workspace","path":"large.bin"}
                ]
            })),
            context(),
        )
        .await
        .unwrap();
    let receipt = saved_file_display_receipt(output.payload())
        .unwrap()
        .unwrap();
    assert_eq!(receipt.caption.as_deref(), Some("delivered"));
    assert_eq!(receipt.files.len(), 5);
    let FileDisplayResult::Ready {
        resource,
        filename,
        origin,
        ..
    } = &receipt.files[0]
    else {
        panic!("first file")
    };
    assert_eq!(filename, "a.txt");
    assert!(
        matches!(origin, FileDisplayOrigin::Local { path } if std::path::Path::new(path).is_absolute() && path == &temp.path().join("a.txt").to_string_lossy())
    );
    assert!(
        matches!(&receipt.files[2], FileDisplayResult::Ready { resource: other, .. } if other == resource)
    );
    for index in [1, 3, 4] {
        assert!(matches!(
            &receipt.files[index],
            FileDisplayResult::Failed { .. }
        ));
    }
    assert_eq!(
        *media.0.lock().unwrap(),
        vec![b"exact original\n".to_vec(); 2]
    );
    assert!(
        output
            .context()
            .iter()
            .all(|content| !matches!(content, ContextContent::Opaque { .. }))
    );
    assert_eq!(output.context().len(), 3);
    for input in [
        serde_json::json!({"files":[]}),
        serde_json::json!({"files":[{"kind":"workspace","path":"a.txt"}],"caption":"x".repeat(241)}),
        serde_json::json!({"files":[{"kind":"workspace","path":"  "}]}),
    ] {
        assert!(tool.execute(args(input), context()).await.is_err());
    }
    assert_eq!(
        media.0.lock().unwrap().len(),
        2,
        "invalid batch must not read/retain"
    );
}

#[tokio::test]
async fn archive_selection_uses_typed_thread_facts_including_legacy_cards() {
    let temp = tempfile::tempdir().unwrap();
    let backend = Arc::new(
        LocalWorkspaceFileBackend::new(temp.path().into(), false)
            .await
            .unwrap(),
    );
    let media = Arc::new(Media::default());
    let tool = ThreadShowFilesTool::new(backend, media.clone());
    let image = ResourceReference::new(
        "old-image".into(),
        format!("sha256:{}", "a".repeat(64)),
        12,
        "image/png".into(),
    )
    .unwrap();
    let payload = OpaquePayload::new(
        "pl.tool.image-card",
        1,
        serde_json::json!({"image":image}).to_string(),
    )
    .unwrap();
    let mut call = context();
    call.context.records = vec![ContextRecord {
        id: "old-card".into(),
        turn_id: Some("old-turn".into()),
        source: ContextSource::ToolResult {
            call_id: "old-call".into(),
            tool_id: "show_image".into(),
        },
        content: vec![ContextContent::Opaque { payload }],
        tool_calls: Vec::new(),
    }]
    .into();
    let output = tool
        .execute(
            args(serde_json::json!({"files":[
                {"kind":"attachment","attachmentId":"old-image"},
                {"kind":"attachment","attachmentId":"unknown"},
                {"kind":"attachment","attachmentId":"old-image"}
            ]})),
            call,
        )
        .await
        .unwrap();
    let receipt = saved_file_display_receipt(output.payload())
        .unwrap()
        .unwrap();
    assert!(
        matches!(&receipt.files[0], FileDisplayResult::Ready { resource, origin:FileDisplayOrigin::Archive, .. } if resource == &image)
    );
    assert!(matches!(
        &receipt.files[1],
        FileDisplayResult::Failed { .. }
    ));
    assert!(
        matches!(&receipt.files[2], FileDisplayResult::Ready { resource, .. } if resource == &image)
    );
    assert!(
        media.0.lock().unwrap().is_empty(),
        "archive selection does not reopen source bytes"
    );
}

/// Remote environment fixture: an absolute path in its stat must not become a host locator.
#[derive(Debug)]
struct Remote;
impl WorkspaceFileBackend for Remote {
    async fn default_cwd(&self) -> pl_protocol::Result<String> {
        Ok("/remote".into())
    }
    async fn stat_optional(
        &self,
        _: WorkspaceFileStatRequest,
    ) -> pl_protocol::Result<Option<WorkspaceFileStat>> {
        Ok(Some(WorkspaceFileStat {
            path: "/remote/report.pdf".into(),
            is_file: true,
            is_dir: false,
            len: Some(5),
            readonly: None,
            modified_at: None,
        }))
    }
    async fn read_bytes(&self, _: WorkspaceFileReadBytesRequest) -> pl_protocol::Result<Vec<u8>> {
        Ok(b"%PDF-".to_vec())
    }
    async fn read_text(&self, _: WorkspaceFileReadRequest) -> pl_protocol::Result<String> {
        unreachable!()
    }
    async fn write_text(&self, _: WorkspaceFileWriteRequest) -> pl_protocol::Result<()> {
        unreachable!()
    }
    async fn remove_file(&self, _: WorkspaceFileRemoveRequest) -> pl_protocol::Result<()> {
        unreachable!()
    }
    async fn create_directory(&self, _: String, _: Option<String>) -> pl_protocol::Result<()> {
        unreachable!()
    }
}

#[tokio::test]
async fn remote_source_never_exposes_a_local_path_and_valid_image_is_exact() {
    let media = Arc::new(Media::default());
    let output = ThreadShowFilesTool::new(Arc::new(Remote), media.clone())
        .execute(
            args(serde_json::json!({"files":[{"kind":"workspace","path":"report.pdf"}]})),
            context(),
        )
        .await
        .unwrap();
    let receipt = saved_file_display_receipt(output.payload())
        .unwrap()
        .unwrap();
    assert!(
        matches!(&receipt.files[0], FileDisplayResult::Ready { origin:FileDisplayOrigin::Remote, filename, .. } if filename == "report.pdf")
    );
    let temp = tempfile::tempdir().unwrap();
    let mut encoded = std::io::Cursor::new(Vec::new());
    image::DynamicImage::new_rgba8(2, 3)
        .write_to(&mut encoded, image::ImageFormat::Png)
        .unwrap();
    std::fs::write(temp.path().join("image.bin"), encoded.get_ref()).unwrap();
    std::fs::write(
        temp.path().join("drawing.svg"),
        b"<svg xmlns=\"http://www.w3.org/2000/svg\"/>",
    )
    .unwrap();
    let backend = Arc::new(
        LocalWorkspaceFileBackend::new(temp.path().into(), false)
            .await
            .unwrap(),
    );
    let output = ThreadShowFilesTool::new(backend, media.clone())
        .execute(
            args(serde_json::json!({"files":[
                {"kind":"workspace","path":"image.bin"},
                {"kind":"workspace","path":"drawing.svg"}
            ]})),
            context(),
        )
        .await
        .unwrap();
    let receipt = saved_file_display_receipt(output.payload())
        .unwrap()
        .unwrap();
    assert!(
        matches!(&receipt.files[0], FileDisplayResult::Ready { modality:pl_protocol::AttachmentModality::Image, resource, .. } if resource.media_type() == "image/png")
    );
    assert_eq!(media.0.lock().unwrap()[1], *encoded.get_ref());
    assert!(
        matches!(
            &receipt.files[1],
            FileDisplayResult::Ready {
                modality: pl_protocol::AttachmentModality::File,
                ..
            }
        ),
        "unsupported previews remain ordinary files, not decodable images"
    );
}

#[derive(serde::Deserialize, schemars::JsonSchema)]
struct Empty {}

/// Replays a historical producer's exact receipt and short model note, without restoring
/// its removed production tool. The new tool must resolve the real Thread delivery.
struct HistoricalCard(ResourceReference);
impl TypedTool for HistoricalCard {
    const NAME: &'static str = "historical_fixture";
    const DESCRIPTION: &'static str = "Historical receipt fixture.";
    type Args = Empty;
    type Context = CallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = ToolError;
    async fn execute(&self, _: Empty, _: CallContext) -> Result<Self::Output, ToolError> {
        Ok(pl_core::tool::ToolOutput::new(
            OpaquePayload::new(
                "pl.tool.image-card",
                1,
                serde_json::json!({"image":self.0}).to_string(),
            )
            .unwrap(),
            vec![ContextContent::Text {
                text: "An image card was added to the timeline.".into(),
            }],
        ))
    }
}

#[tokio::test]
async fn real_thread_selects_a_legacy_card_whose_context_contains_no_media() {
    use pl_agent_tool::ToolHandle;
    use pl_core::{model::DynModelSession, thread::ThreadHandle};
    use pl_tool::binding::{ToolCallPolicy, prepare_native_tool, prepare_registration};
    let temp = tempfile::tempdir().unwrap();
    let image = ResourceReference::new(
        "legacy-image".into(),
        format!("sha256:{}", "b".repeat(64)),
        7,
        "image/png".into(),
    )
    .unwrap();
    let old = prepare_native_tool::<HistoricalCard>().unwrap();
    let old_registration = prepare_registration(
        "historical_fixture",
        old.definition(),
        ToolCallPolicy::DirectOnly,
    )
    .unwrap();
    let new =
        prepare_native_tool::<ThreadShowFilesTool<LocalWorkspaceFileBackend, Media>>().unwrap();
    let new_registration =
        prepare_registration("show_files", new.definition(), ToolCallPolicy::DirectOnly).unwrap();
    let requests = Arc::new(Mutex::new(Vec::new()));
    let thread = ThreadHandle::start("legacy-display".into(), DynModelSession::new(host::Calls {
        calls: [
            ("historical_fixture".into(), "{}".into()),
            ("show_files".into(), serde_json::json!({"files":[{"kind":"attachment","attachmentId":"legacy-image"}]}).to_string()),
        ].into(), requests,
    })).unwrap();
    let media = Arc::new(Media::default());
    let backend = Arc::new(
        LocalWorkspaceFileBackend::new(temp.path().into(), false)
            .await
            .unwrap(),
    );
    thread
        .register_tools(vec![
            old_registration
                .attach(ToolHandle::new(old.attach(HistoricalCard(image.clone()))))
                .foreground_coexisting(),
            new_registration
                .attach(ToolHandle::new(
                    new.attach(ThreadShowFilesTool::new(backend, media.clone())),
                ))
                .foreground_coexisting(),
        ])
        .await
        .unwrap();
    thread.run_turn(host::turn("legacy")).await.unwrap();
    let effects = thread.effects().await.unwrap();
    let delivery = effects
        .iter()
        .flat_map(|effect| effect.deliveries.iter())
        .find(|delivery| delivery.tool_id == "show_files")
        .unwrap();
    let receipt = saved_file_display_receipt(delivery.output.payload())
        .unwrap()
        .unwrap();
    assert!(
        matches!(&receipt.files[0], FileDisplayResult::Ready { resource, origin:FileDisplayOrigin::Archive, .. } if resource == &image)
    );
    assert!(media.0.lock().unwrap().is_empty());
    thread.close().await.unwrap();
}
