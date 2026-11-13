use pl_agent_tool::{Tool, typed::TypedTool};
use pl_core::{
    context::OpaquePayload,
    tool::{
        ToolOutput,
        opaque::{CallContext, ToolError},
    },
};
use pl_tool::{
    binding::prepare_native_tool,
    file::WriteFileInput,
    workspace::{AgentWorkspace, ToolWorkspace, WorkspaceMutability},
    workspace_file::*,
};
use serde_json::{Value, json};
use std::sync::{
    Arc,
    atomic::{AtomicUsize, Ordering},
};

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
async fn call<T>(tool: T, input: Value) -> Result<ToolOutput, ToolError>
where
    T: TypedTool<Context = CallContext, Output = ToolOutput, Error = ToolError>,
{
    prepare_native_tool::<T>()
        .unwrap()
        .attach(tool)
        .execute(
            OpaquePayload::new("application/json", 1, input.to_string()).unwrap(),
            context(),
        )
        .await
}
async fn mutation(
    kind: WorkspaceMutationKind,
    workspace: ToolWorkspace,
    input: Value,
) -> Result<ToolOutput, ToolError> {
    let backend = Arc::new(
        ExecutorWorkspaceFileBackend::confined(workspace.clone())
            .await
            .map_err(ToolError::new)?,
    );
    WorkspaceMutationTool::new(kind, kind.definition(), backend, workspace)
        .execute(
            OpaquePayload::new("application/json", 1, input.to_string()).unwrap(),
            context(),
        )
        .await
}
fn patch<B: WorkspaceFileBackend + 'static>(
    backend: Arc<B>,
    workspace: ToolWorkspace,
) -> ThreadWorkspaceFileTool<B> {
    let kind = WorkspaceFileToolKind::ApplyPatch;
    ThreadWorkspaceFileTool::new(kind, backend, workspace, kind.definition())
}

#[tokio::test]
async fn production_bindings_keep_file_outputs_and_write_modes() {
    let root = tempfile::tempdir().unwrap();
    let workspace = ToolWorkspace::new(AgentWorkspace::confined(
        root.path(),
        WorkspaceMutability::ReadWrite,
    ));
    let backend = Arc::new(
        ExecutorWorkspaceFileBackend::confined(workspace.clone())
            .await
            .unwrap(),
    );
    let create = mutation(
        WorkspaceMutationKind::CreateDirectory,
        workspace.clone(),
        json!({"path":"nested"}),
    )
    .await
    .unwrap();
    assert_eq!(create.payload().content(), "Created directory nested");
    assert_eq!(create.payload().format(), "text/plain");
    let input = json!({"path":"nested/a","content":"中文\n","mode":"create"});
    let written = call(
        ThreadWriteFileTool::new(backend.clone(), workspace.clone()),
        input.clone(),
    )
    .await
    .unwrap();
    assert_eq!(written.payload().format(), "pl.tool.file-write");
    assert_eq!(written.payload().version(), 1);
    assert_eq!(
        serde_json::from_str::<Value>(written.payload().content()).unwrap(),
        json!({"path":"nested/a","mode":"create","bytesWritten":7})
    );
    assert!(
        call(
            ThreadWriteFileTool::new(backend.clone(), workspace.clone()),
            input
        )
        .await
        .is_err()
    );
    assert_eq!(
        std::fs::read_to_string(root.path().join("nested/a")).unwrap(),
        "中文\n"
    );
    call(
        ThreadWriteFileTool::new(backend.clone(), workspace.clone()),
        json!({"path":"nested/a","content":"!","mode":"append"}),
    )
    .await
    .unwrap();
    assert_eq!(
        std::fs::read_to_string(root.path().join("nested/a")).unwrap(),
        "中文\n!"
    );
    call(
        ThreadWriteFileTool::new(backend.clone(), workspace.clone()),
        json!({"path":"nested/a","content":"replacement","mode":"overwrite"}),
    )
    .await
    .unwrap();
    let stat = call(
        ThreadStatPathTool::new(backend.clone()),
        json!({"path":"nested/a"}),
    )
    .await
    .unwrap();
    assert_eq!(stat.payload().format(), "pl.tool.path-stat");
    assert_eq!(stat.payload().version(), 1);
    let value: Value = serde_json::from_str(stat.payload().content()).unwrap();
    assert_eq!(value["type"], "file");
    assert_eq!(value["len"], 11);
    let absent = call(
        ThreadStatPathTool::new(backend.clone()),
        json!({"path":"absent"}),
    )
    .await
    .unwrap();
    assert_eq!(
        serde_json::from_str::<Value>(absent.payload().content()).unwrap(),
        json!({"path":"absent","exists":false})
    );
    let copied = mutation(
        WorkspaceMutationKind::Copy,
        workspace.clone(),
        json!({"from":"nested/a","to":"nested/b","collision":"failIfExists"}),
    )
    .await
    .unwrap();
    assert_eq!(copied.payload().content(), "Copied nested/a to nested/b");
    let moved = mutation(
        WorkspaceMutationKind::Move,
        workspace.clone(),
        json!({"from":"nested/b","to":"nested/c","collision":"failIfExists"}),
    )
    .await
    .unwrap();
    assert_eq!(moved.payload().content(), "Moved nested/b to nested/c");
    let deleted = mutation(
        WorkspaceMutationKind::Delete,
        workspace.clone(),
        json!({"path":"nested/c","mode":"file"}),
    )
    .await
    .unwrap();
    assert_eq!(deleted.payload().content(), "Deleted nested/c");
    let patched = patch(backend.clone(), workspace.clone()).execute(
        OpaquePayload::text("*** Begin Patch\n*** Update File: nested/a\n@@\n-replacement\n+patched\n*** End Patch"),
        context(),
    ).await.unwrap();
    assert_eq!(patched.payload().format(), "pl.tool.workspace-file");
    assert_eq!(patched.payload().version(), 1);
    let output: Value = serde_json::from_str(patched.payload().content()).unwrap();
    assert_eq!(
        output,
        json!({
            "cwd":".", "added":[], "updated":["nested/a"], "deleted":[], "moved":[],
            "changedFiles":["nested/a"], "stdout":"apply_patch completed", "stderr":"",
            "summary":"Success. Updated the following files:\nM nested/a\n"
        })
    );
    let error = patch(backend, workspace).execute(OpaquePayload::text(
        "*** Begin Patch\n*** Add File: applied\n+kept\n*** Update File: nested/a\n@@\n-not present\n+bad\n*** End Patch"
    ), context()).await.unwrap_err();
    let source = error
        .source
        .downcast_ref::<pl_protocol::PureError>()
        .unwrap();
    assert!(
        source
            .to_string()
            .contains("Changes applied before failure:\nA applied")
    );
    assert!(
        source
            .to_string()
            .contains("Recovery: read the target file again")
    );
    assert_eq!(
        std::fs::read_to_string(root.path().join("applied")).unwrap(),
        "kept\n"
    );
    assert_eq!(
        std::fs::read_to_string(root.path().join("nested/a")).unwrap(),
        "patched\n"
    );
}

#[tokio::test]
async fn host_policy_and_grants_do_not_expand_confined_paths() {
    let root = tempfile::tempdir().unwrap();
    let outside = tempfile::tempdir().unwrap();
    let workspace = ToolWorkspace::new(
        AgentWorkspace::confined(root.path(), WorkspaceMutability::ReadWrite)
            .with_writable_paths(Some(vec![root.path().join("allowed")])),
    );
    let backend = Arc::new(
        ExecutorWorkspaceFileBackend::confined(workspace.clone())
            .await
            .unwrap(),
    );
    for destination in [
        "denied/a".to_string(),
        outside
            .path()
            .join("outside")
            .to_string_lossy()
            .into_owned(),
    ] {
        let mut granted = context();
        granted.grant = granted
            .grant
            .with_capability(pl_tool::approval::HOST_WORKSPACE_ACCESS);
        let error = TypedTool::execute(
            &ThreadWriteFileTool::new(backend.clone(), workspace.clone()),
            WriteFileInput {
                path: destination.clone(),
                content: "denied".into(),
                mode: pl_tool_filesystem::WriteMode::Create,
            },
            granted,
        )
        .await
        .unwrap_err();
        assert!(error.source.is::<pl_protocol::PureError>());
        let physical = root.path().join(&destination);
        assert!(!physical.exists());
        assert!(
            mutation(
                WorkspaceMutationKind::CreateDirectory,
                workspace.clone(),
                json!({"path":destination})
            )
            .await
            .is_err()
        );
        assert!(!physical.exists());
    }
    let readonly = ToolWorkspace::new(AgentWorkspace::confined(
        root.path(),
        WorkspaceMutability::ReadOnly,
    ));
    assert!(
        mutation(
            WorkspaceMutationKind::CreateDirectory,
            readonly.clone(),
            json!({"path":"no"})
        )
        .await
        .is_err()
    );
    assert!(
        call(
            ThreadWriteFileTool::new(backend.clone(), readonly),
            json!({"path":"allowed/a","content":"no","mode":"create"})
        )
        .await
        .is_err()
    );
    let host_workspace = ToolWorkspace::new(AgentWorkspace::local(root.path()));
    let host_backend = Arc::new(
        ExecutorWorkspaceFileBackend::confined(host_workspace.clone())
            .await
            .unwrap(),
    );
    let target = outside
        .path()
        .join("granted")
        .to_string_lossy()
        .into_owned();
    let write = ThreadWriteFileTool::new(host_backend, host_workspace);
    assert!(
        call(
            ThreadWriteFileTool::new(backend, workspace),
            json!({"path":target,"content":"no","mode":"create"})
        )
        .await
        .is_err()
    );
    let input = || WriteFileInput {
        path: target.clone(),
        content: "approved".into(),
        mode: pl_tool_filesystem::WriteMode::Create,
    };
    assert!(
        TypedTool::execute(&write, input(), context())
            .await
            .is_err()
    );
    let mut granted = context();
    granted.grant = granted
        .grant
        .with_capability(pl_tool::approval::HOST_WORKSPACE_ACCESS);
    TypedTool::execute(&write, input(), granted).await.unwrap();
    assert_eq!(std::fs::read_to_string(target).unwrap(), "approved");
}

#[cfg(unix)]
#[tokio::test]
async fn every_local_adapter_rejects_symlink_traversal() {
    let root = tempfile::tempdir().unwrap();
    let outside = tempfile::tempdir().unwrap();
    std::fs::write(outside.path().join("keep"), b"untouched").unwrap();
    std::os::unix::fs::symlink(outside.path(), root.path().join("link")).unwrap();
    std::fs::write(root.path().join("source"), b"source").unwrap();
    let workspace = ToolWorkspace::new(AgentWorkspace::confined(
        root.path(),
        WorkspaceMutability::ReadWrite,
    ));
    let backend = Arc::new(
        ExecutorWorkspaceFileBackend::confined(workspace.clone())
            .await
            .unwrap(),
    );
    assert!(
        call(
            ThreadStatPathTool::new(backend.clone()),
            json!({"path":"link/keep"})
        )
        .await
        .is_err()
    );
    assert!(
        call(
            ThreadWriteFileTool::new(backend.clone(), workspace.clone()),
            json!({"path":"link/keep","content":"no","mode":"overwrite"})
        )
        .await
        .is_err()
    );
    assert!(
        mutation(
            WorkspaceMutationKind::CreateDirectory,
            workspace.clone(),
            json!({"path":"link/new"})
        )
        .await
        .is_err()
    );
    assert!(
        mutation(
            WorkspaceMutationKind::Delete,
            workspace.clone(),
            json!({"path":"link","mode":"recursiveDirectory"})
        )
        .await
        .is_err()
    );
    assert!(
        mutation(
            WorkspaceMutationKind::Copy,
            workspace.clone(),
            json!({"from":"source","to":"link/keep","collision":"overwrite"})
        )
        .await
        .is_err()
    );
    assert!(
        mutation(
            WorkspaceMutationKind::Move,
            workspace.clone(),
            json!({"from":"link/keep","to":"moved","collision":"overwrite"})
        )
        .await
        .is_err()
    );
    assert!(patch(backend, workspace).execute(OpaquePayload::text("*** Begin Patch\n*** Update File: link/keep\n@@\n-untouched\n+no\n*** End Patch"), context()).await.is_err());
    assert_eq!(
        std::fs::read(outside.path().join("keep")).unwrap(),
        b"untouched"
    );
    assert!(!outside.path().join("new").exists());
}

#[derive(Debug)]
struct GrantProbe {
    inner: ExecutorWorkspaceFileBackend,
    grants: Arc<AtomicUsize>,
}
impl WorkspaceFileBackend for GrantProbe {
    fn for_grant(&self, _: &pl_core::tool::execution_policy::ExecutionGrant) -> Option<Self> {
        self.grants.fetch_add(1, Ordering::SeqCst);
        None
    }
    async fn default_cwd(&self) -> pl_protocol::Result<String> {
        self.inner.default_cwd().await
    }
    async fn stat_optional(
        &self,
        request: WorkspaceFileStatRequest,
    ) -> pl_protocol::Result<Option<WorkspaceFileStat>> {
        self.inner.stat_optional(request).await
    }
    async fn read_text(&self, request: WorkspaceFileReadRequest) -> pl_protocol::Result<String> {
        self.inner.read_text(request).await
    }
    async fn read_bytes(
        &self,
        request: WorkspaceFileReadBytesRequest,
    ) -> pl_protocol::Result<Vec<u8>> {
        self.inner.read_bytes(request).await
    }
    async fn write_text(&self, request: WorkspaceFileWriteRequest) -> pl_protocol::Result<()> {
        self.inner.write_text(request).await
    }
    async fn remove_file(&self, request: WorkspaceFileRemoveRequest) -> pl_protocol::Result<()> {
        self.inner.remove_file(request).await
    }
    async fn create_directory(&self, path: String, cwd: Option<String>) -> pl_protocol::Result<()> {
        self.inner.create_directory(path, cwd).await
    }
}

#[tokio::test]
async fn patch_preserves_lock_then_cancel_then_grant_order() {
    let root = tempfile::tempdir().unwrap();
    let workspace = ToolWorkspace::new(AgentWorkspace::confined(
        root.path(),
        WorkspaceMutability::ReadWrite,
    ));
    let grants = Arc::new(AtomicUsize::new(0));
    let backend = Arc::new(GrantProbe {
        inner: ExecutorWorkspaceFileBackend::confined(workspace.clone())
            .await
            .unwrap(),
        grants: grants.clone(),
    });
    let tool = patch(backend.clone(), workspace.clone());
    let lock = workspace.write_lock().await;
    let ctx = context();
    let cancellation = ctx.cancellation.clone();
    let mut future = Box::pin(tool.execute(
        OpaquePayload::text("*** Begin Patch\n*** Add File: no\n+no\n*** End Patch"),
        ctx,
    ));
    assert!(futures::poll!(future.as_mut()).is_pending());
    assert_eq!(grants.load(Ordering::SeqCst), 0);
    cancellation.cancel();
    assert!(futures::poll!(future.as_mut()).is_pending());
    drop(lock);
    assert!(
        future
            .await
            .unwrap_err()
            .source
            .is::<pl_core::thread::ThreadError>()
    );
    assert_eq!(grants.load(Ordering::SeqCst), 0);
    assert!(!root.path().join("no").exists());
    tool.execute(
        OpaquePayload::text("*** Begin Patch\n*** Add File: yes\n+yes\n*** End Patch"),
        context(),
    )
    .await
    .unwrap();
    assert_eq!(grants.load(Ordering::SeqCst), 1);
    assert_eq!(std::fs::read(root.path().join("yes")).unwrap(), b"yes\n");

    let lock = workspace.write_lock().await;
    let write = ThreadWriteFileTool::new(backend, workspace.clone());
    let ctx = context();
    let cancellation = ctx.cancellation.clone();
    let mut future = Box::pin(TypedTool::execute(
        &write,
        WriteFileInput {
            path: "cancelled".into(),
            content: "no".into(),
            mode: pl_tool_filesystem::WriteMode::Create,
        },
        ctx,
    ));
    assert!(futures::poll!(future.as_mut()).is_pending());
    cancellation.cancel();
    assert!(
        future
            .await
            .unwrap_err()
            .source
            .is::<pl_core::thread::ThreadError>()
    );
    assert_eq!(grants.load(Ordering::SeqCst), 1);
    assert!(!root.path().join("cancelled").exists());
    drop(lock);
}
