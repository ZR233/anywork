use pl_agent_tool::typed::TypedTool;
use pl_core::{
    context::{ContextContent, ContextRecord, ContextSource, ResourceReference},
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

use crate::binding_host as host;

#[path = "../support/file_display_ssh.rs"]
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
                pl_model::completion::AttachmentModality::Image,
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
async fn deferred_stream_reopens_saved_fact_and_rejects_changed_or_replaced_bindings() {
    use tokio::io::AsyncReadExt;
    let temp = tempfile::tempdir().unwrap();
    let path = temp.path().join("opaque.bin");
    let bytes = [0, 255, 17, 0, 222, 173];
    std::fs::write(&path, bytes).unwrap();
    let backend = ExecutorWorkspaceFileBackend::local(temp.path().into(), false)
        .await
        .unwrap();
    let target = backend.defer_file("opaque.bin").await.unwrap();
    let saved = serde_json::to_string(&target).unwrap();
    let target = serde_json::from_str(&saved).unwrap();
    let mut reader = backend.open_deferred_file(&target).await.unwrap();
    let mut actual = Vec::new();
    reader.read_to_end(&mut actual).await.unwrap();
    assert_eq!(actual, bytes);
    backend.validate_deferred_file(&target).await.unwrap();

    // Reconstructing the view of the same executor remains usable after cold decoding.
    let same =
        ExecutorWorkspaceFileBackend::new(backend.executor().clone(), backend.canonical_path())
            .unwrap();
    same.validate_deferred_file(&target).await.unwrap();
    let replaced = ExecutorWorkspaceFileBackend::local(temp.path().into(), false)
        .await
        .unwrap();
    assert!(replaced.open_deferred_file(&target).await.is_err());
    let mut old_process = serde_json::to_value(&target).unwrap();
    old_process["executorInstance"] = serde_json::json!("old-startup:1");
    assert!(
        backend
            .validate_deferred_file(&serde_json::from_value(old_process).unwrap())
            .await
            .is_err()
    );

    // Detect a same-length edit through the existing target metadata, without sleeps.
    std::fs::OpenOptions::new()
        .write(true)
        .open(&path)
        .unwrap()
        .set_times(std::fs::FileTimes::new().set_modified(std::time::UNIX_EPOCH))
        .unwrap();
    assert!(backend.validate_deferred_file(&target).await.is_err());
    let target = backend.defer_file("opaque.bin").await.unwrap();

    std::fs::write(&path, b"changed length").unwrap();
    assert!(
        backend.validate_deferred_file(&target).await.is_err(),
        "EOF validation must detect edits"
    );
    assert!(backend.open_deferred_file(&target).await.is_err());
    std::fs::remove_file(&path).unwrap();
    assert!(backend.open_deferred_file(&target).await.is_err());
    #[cfg(unix)]
    {
        let outside = tempfile::NamedTempFile::new().unwrap();
        std::os::unix::fs::symlink(outside.path(), &path).unwrap();
        assert!(backend.open_deferred_file(&target).await.is_err());
    }
}

#[tokio::test]
async fn deferred_host_grant_is_scoped_to_original_workspace_and_path() {
    use pl_core::tool::execution_policy::ExecutionGrant;
    use pl_tool::workspace::{AgentWorkspace, ToolWorkspace, WorkspaceMutability};
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path().join("workspace");
    std::fs::create_dir(&root).unwrap();
    let outside = temp.path().join("outside.bin");
    std::fs::write(&outside, b"outside").unwrap();
    let assigned =
        ToolWorkspace::new(AgentWorkspace::local(&root).with_session_id("original-thread"));
    let backend = ExecutorWorkspaceFileBackend::local(root.clone(), false)
        .await
        .unwrap()
        .with_workspace(assigned);
    let grant = ExecutionGrant::default().with_capability(pl_tool::approval::HOST_WORKSPACE_ACCESS);
    let granted = backend.for_grant(&grant).unwrap();
    let target = granted.defer_file(outside.to_str().unwrap()).await.unwrap();
    backend.validate_deferred_file(&target).await.unwrap();
    assert!(
        backend
            .stat(WorkspaceFileStatRequest {
                path: outside.to_str().unwrap().into(),
                cwd: None
            })
            .await
            .is_err(),
        "download must not grant the backend general host access"
    );
    let changed_thread = backend.clone().with_workspace(ToolWorkspace::new(
        AgentWorkspace::local(&root).with_session_id("different-thread"),
    ));
    assert!(changed_thread.open_deferred_file(&target).await.is_err());
    let confined = backend
        .clone()
        .with_workspace(ToolWorkspace::new(AgentWorkspace::confined(
            &root,
            WorkspaceMutability::ReadOnly,
        )));
    assert!(confined.open_deferred_file(&target).await.is_err());
}

#[tokio::test]
async fn file_display_artifact_serializes_four_states_with_source_facts() {
    use pl_tool::workspace::{AgentWorkspace, ToolWorkspace};
    use serde_json::json;

    let temp = tempfile::tempdir().unwrap();
    let markdown = b"# Rust file display fixture\n";
    std::fs::write(temp.path().join("first.md"), markdown).unwrap();
    std::fs::write(temp.path().join("download.tar"), [0; 360]).unwrap();
    let media = Arc::new(Media::default());
    let backend = Arc::new(
        ExecutorWorkspaceFileBackend::local(temp.path().into(), false)
            .await
            .unwrap()
            .with_workspace(ToolWorkspace::new(
                AgentWorkspace::local(temp.path()).with_session_id("file-display-wire-fixture"),
            )),
    );
    let output = ThreadShowFilesTool::new(backend.clone(), media.clone())
        .execute(
            args(json!({"caption":"交付文件", "files":[
                {"kind":"workspace","path":"first.md"},
                {"kind":"networkImage","url":"https://example.invalid/image.png"},
                {"kind":"networkImage","url":"https://user@example.invalid/blocked.png"}
            ]})),
            context(),
        )
        .await
        .unwrap();

    let mut receipt = saved_file_display_receipt(output.details())
        .unwrap()
        .unwrap();
    assert_eq!(*media.0.lock().unwrap(), vec![markdown.to_vec()]);
    assert_eq!(output.content().len(), 2);
    assert!(matches!(&output.content()[0], ContextContent::Text { text }
        if text.contains("1 archived") && text.contains("1 network previews") && text.contains("1 failed")));
    assert!(matches!(
        &output.content()[1],
        ContextContent::Resource { .. }
    ));
    assert!(
        !pl_tool::approval::assess(
            "show_files",
            &json!({"files":[
                {"kind":"networkImage","url":"https://example.invalid/image.png"}
            ]})
            .to_string(),
            temp.path()
        )
        .requested_access
        .allows_external()
    );

    // A local show_files call archives files. Exercise the Deferred wire variant with
    // a real executor-issued target, without requiring an SSH peer for this contract.
    let target = backend.defer_file("download.tar").await.unwrap();
    backend.validate_deferred_file(&target).await.unwrap();
    assert!(target.workspace_binding.is_some());
    receipt.files.insert(
        1,
        FileDisplayResult::Deferred {
            filename: "download.tar".into(),
            target: target.clone(),
        },
    );

    let digest = pl_core::context::content_hash(markdown);
    let artifact = [json!({"fileDisplay": receipt})];
    let encoded = serde_json::to_vec_pretty(&artifact).unwrap();
    let [artifact]: [serde_json::Value; 1] = serde_json::from_slice(&encoded).unwrap();
    assert_eq!(artifact["fileDisplay"]["caption"], "交付文件");
    assert_eq!(
        artifact["fileDisplay"]["files"],
        json!([
            {
                "status":"ready", "filename":"first.md", "modality":"file",
                "resource":{"id":digest,"contentDigest":digest,"byteLen":markdown.len(),"mediaType":"text/markdown"},
                "origin":{"kind":"local","path":std::path::Path::new(backend.canonical_path()).join("first.md")}
            },
            {
                "status":"deferred", "filename":"download.tar", "target":{
                    "canonicalPath":target.canonical_path,"size":360,"modifiedAt":target.modified_at,
                    "executorInstance":target.executor_instance,"workspaceRoot":target.workspace_root,
                    "workspaceBinding":target.workspace_binding,"hostWorkspaceAccess":false
                }
            },
            {"status":"networkImage", "filename":"image.png", "url":"https://example.invalid/image.png"},
            {"status":"failed", "filename":"network-image", "message":"network image URL requires HTTPS, a host and no credentials"}
        ])
    );
    assert!(
        saved_file_display_receipt(Some(&artifact))
            .unwrap()
            .is_some()
    );
    let invalid = json!({"fileDisplay":{"caption":null,"files":[]}});
    assert!(saved_file_display_receipt(Some(&invalid)).is_err());

    // An opt-in export for the Dart consumer. Ordinary test runs still exercise the same wire assertion.
    if let Some(path) = std::env::var_os("ANYWORK_FILE_DISPLAY_FIXTURE_PATH") {
        use std::io::Write;
        let path = std::path::PathBuf::from(path);
        assert!(path.is_absolute(), "use an absolute session artifact path");
        let mut file = std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(path)
            .unwrap();
        file.write_all(&encoded).unwrap();
    }
}

#[tokio::test]
async fn ordered_partial_results_keep_exact_bytes_and_do_not_project_model_media() {
    let temp = tempfile::tempdir().unwrap();
    std::fs::write(temp.path().join("a.txt"), "exact original\n").unwrap();
    std::fs::write(temp.path().join("bad.png"), b"\x89PNG\r\n\x1a\ncorrupt").unwrap();
    let large = std::fs::File::create(temp.path().join("large.bin")).unwrap();
    large.set_len(50 * 1024 * 1024 + 1).unwrap();
    let backend = Arc::new(
        ExecutorWorkspaceFileBackend::local(temp.path().into(), false)
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
    let receipt = saved_file_display_receipt(output.details())
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
    for index in [1, 3] {
        assert!(matches!(
            &receipt.files[index],
            FileDisplayResult::Failed { .. }
        ));
    }
    // A file past the former 50 MiB ceiling is archived exactly instead of refused.
    assert!(matches!(
        &receipt.files[4],
        FileDisplayResult::Ready { resource, filename, .. }
            if filename == "large.bin" && resource.byte_len() == 50 * 1024 * 1024 + 1
    ));
    {
        let retained = media.0.lock().unwrap();
        assert!(
            retained[..2]
                .iter()
                .all(|bytes| bytes == b"exact original\n")
        );
        assert_eq!(retained[2].len(), 50 * 1024 * 1024 + 1);
        assert!(retained[2].iter().all(|&byte| byte == 0));
    }
    assert!(
        output
            .content()
            .iter()
            .all(|content| !matches!(content, ContextContent::Opaque { .. }))
    );
    assert_eq!(output.content().len(), 4);
    for input in [
        serde_json::json!({"files":[]}),
        serde_json::json!({"files":[{"kind":"workspace","path":"a.txt"}],"caption":"x".repeat(241)}),
        serde_json::json!({"files":[{"kind":"workspace","path":"  "}]}),
    ] {
        assert!(tool.execute(args(input), context()).await.is_err());
    }
    assert_eq!(
        media.0.lock().unwrap().len(),
        3,
        "invalid batch must not read/retain"
    );
}

#[tokio::test]
async fn archive_selection_uses_typed_thread_facts_including_legacy_cards() {
    let temp = tempfile::tempdir().unwrap();
    let backend = Arc::new(
        ExecutorWorkspaceFileBackend::local(temp.path().into(), false)
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
    let mut call = context();
    call.context.records = vec![ContextRecord {
        id: "old-card".into(),
        turn_id: Some("old-turn".into()),
        source: ContextSource::ToolResult {
            call_id: "old-call".into(),
            tool_id: "show_image".into(),
        },
        content: vec![ContextContent::Resource {
            reference: image.clone(),
        }],
        tool_data: Default::default(),
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
    let receipt = saved_file_display_receipt(output.details())
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
        panic!("remote non-preview must never read body")
    }
    async fn defer_file(
        &self,
        _: &str,
    ) -> pl_protocol::Result<pl_tool::file_display::DeferredWorkspaceFile> {
        Ok(serde_json::from_value(serde_json::json!({
            "canonicalPath":"/remote/report.pdf", "size":5, "modifiedAt":1,
            "executorInstance":"fixture", "workspaceRoot":"/remote", "workspaceBinding":null,
            "hostWorkspaceAccess":false
        }))
        .unwrap())
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
    let receipt = saved_file_display_receipt(output.details())
        .unwrap()
        .unwrap();
    assert!(
        matches!(&receipt.files[0], FileDisplayResult::Deferred { filename, target } if filename == "report.pdf" && target.size == 5)
    );
    assert!(media.0.lock().unwrap().is_empty());
    assert!(
        output
            .content()
            .iter()
            .all(|part| matches!(part, ContextContent::Text { .. }))
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
        ExecutorWorkspaceFileBackend::local(temp.path().into(), false)
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
    let receipt = saved_file_display_receipt(output.details())
        .unwrap()
        .unwrap();
    assert!(
        matches!(&receipt.files[0], FileDisplayResult::Ready { modality:pl_model::completion::AttachmentModality::Image, resource, .. } if resource.media_type() == "image/png")
    );
    assert_eq!(media.0.lock().unwrap()[0], *encoded.get_ref());
    assert!(
        matches!(
            &receipt.files[1],
            FileDisplayResult::Ready {
                modality: pl_model::completion::AttachmentModality::File,
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
        Ok(
            pl_core::tool::ToolOutput::text("An image card was added to the timeline.".into())
                .with_details(serde_json::json!({"imageCard":{"image":self.0}})),
        )
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
        prepare_native_tool::<ThreadShowFilesTool<ExecutorWorkspaceFileBackend, Media>>().unwrap();
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
        ExecutorWorkspaceFileBackend::local(temp.path().into(), false)
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
    let receipt = saved_file_display_receipt(delivery.output.details())
        .unwrap()
        .unwrap();
    assert!(
        matches!(&receipt.files[0], FileDisplayResult::Ready { resource, origin:FileDisplayOrigin::Archive, .. } if resource == &image)
    );
    assert!(media.0.lock().unwrap().is_empty());
    thread.close().await.unwrap();
}
