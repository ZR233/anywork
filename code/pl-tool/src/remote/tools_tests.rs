//! File-tool integration over the production helper transport (not an SSH host).
use super::*;
use crate::workspace::{AgentWorkspace, WorkspaceMutability};
use crate::workspace_file::{
    ThreadStatPathTool, ThreadWorkspaceFileTool, ThreadWriteFileTool, WorkspaceFileToolKind,
};
use anyhow::ensure;
use pl_agent_tool::Tool;
use serde_json::json;

#[path = "../../tests/support/helper.rs"]
mod executable;
#[path = "../../tests/support/remote.rs"]
mod helper;

fn context() -> CallContext {
    CallContext {
        thread_id: "remote-files".into(),
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
fn input(value: serde_json::Value) -> OpaquePayload {
    OpaquePayload::new("application/json", 1, value.to_string()).unwrap()
}

#[tokio::test]
async fn file_tools_over_real_helper_keep_remote_mutation_semantics() -> anyhow::Result<()> {
    let helper = helper::Helper::start(executable::remote_helper_executable()).await?;
    let result = async {
        helper.client.request(
            pl_protocol::remote::RemoteRequest::CloseWorkspace { workspace_id: helper.workspace.clone() },
            &[],
        ).await?;
        let root = helper.root.path();
        let lease = helper.client.open_workspace_lease(
            root.to_string_lossy().into_owned(), "file-tools".into(),
            Arc::new(super::super::client::workspace::WorkspaceCache::default()),
        ).await?;
        let backend = Arc::new(RemoteWorkspaceFileBackend::new(helper.client.clone(), lease));
        let workspace = ToolWorkspace::new(AgentWorkspace::confined(root, WorkspaceMutability::ReadWrite));
        let mutation = |kind: RemoteMutationKind| RemoteWorkspaceMutationTool::new(
            kind, kind.definition(), backend.clone(), workspace.clone(),
        );
        let create = mutation(RemoteMutationKind::CreateDirectory).execute(input(json!({"path":"nested"})), context()).await?;
        ensure!(create.payload().content() == "Created directory nested");
        let write = ThreadWriteFileTool::new(backend.clone(), workspace.clone());
        let written = TypedTool::execute(&write, pl_tool_write_file::WriteFileInput {
            path: "nested/a".into(), content: "original\n".into(), mode: pl_tool_filesystem::WriteMode::Create,
        }, context()).await?;
        ensure!(written.payload().format() == "pl.tool.file-write");
        let value: serde_json::Value = serde_json::from_str(written.payload().content())?;
        ensure!(value == json!({"path":"nested/a","mode":"create","bytesWritten":9}));
        ensure!(TypedTool::execute(&write, pl_tool_write_file::WriteFileInput {
            path: "nested/a".into(), content: "lost".into(), mode: pl_tool_filesystem::WriteMode::Create,
        }, context()).await.is_err());
        let stat = TypedTool::execute(&ThreadStatPathTool::new(backend.clone()),
            pl_tool_filesystem::PathInput { path: "missing".into() }, context()).await?;
        ensure!(serde_json::from_str::<serde_json::Value>(stat.payload().content())? == json!({"path":"missing","exists":false}));
        mutation(RemoteMutationKind::Copy).execute(input(json!({"from":"nested/a","to":"target","collision":"failIfExists"})), context()).await?;
        let collision = mutation(RemoteMutationKind::Move).execute(input(json!({"from":"nested/a","to":"target","collision":"failIfExists"})), context()).await.unwrap_err();
        ensure!(collision.source.to_string().contains("destination already exists"));
        ensure!(std::fs::read(root.join("nested/a"))? == b"original\n");
        std::fs::write(root.join("target"), b"old")?;
        mutation(RemoteMutationKind::Copy).execute(input(json!({"from":"nested/a","to":"target","collision":"overwrite"})), context()).await?;
        ensure!(std::fs::read(root.join("target"))? == b"original\n");
        // Remote copy has always supported directory traversal; keep it in the backend.
        mutation(RemoteMutationKind::Copy).execute(input(json!({"from":"nested","to":"copied","collision":"failIfExists"})), context()).await?;
        ensure!(std::fs::read(root.join("copied/a"))? == b"original\n");
        mutation(RemoteMutationKind::Move).execute(input(json!({"from":"target","to":"moved","collision":"failIfExists"})), context()).await?;
        ensure!(!root.join("target").exists());
        mutation(RemoteMutationKind::Delete).execute(input(json!({"path":"moved","mode":"file"})), context()).await?;
        ensure!(!root.join("moved").exists());
        ensure!(mutation(RemoteMutationKind::Delete).execute(input(json!({"path":"copied","mode":"file"})), context()).await.is_err());
        ensure!(mutation(RemoteMutationKind::Delete).execute(input(json!({"path":"copied","mode":"emptyDirectory"})), context()).await.is_err());
        ensure!(root.join("copied/a").exists());
        mutation(RemoteMutationKind::Delete).execute(input(json!({"path":"copied","mode":"recursiveDirectory"})), context()).await?;
        ensure!(!root.join("copied").exists());
        let kind = WorkspaceFileToolKind::ApplyPatch;
        let patch = ThreadWorkspaceFileTool::new(kind, backend.clone(), workspace.clone(), kind.definition());
        let output = patch.execute(OpaquePayload::text("*** Begin Patch\n*** Update File: nested/a\n@@\n-original\n+patched\n*** End Patch"), context()).await?;
        ensure!(output.payload().format() == "pl.tool.workspace-file");
        ensure!(std::fs::read(root.join("nested/a"))? == b"patched\n");
        ensure!(mutation(RemoteMutationKind::CreateDirectory).execute(input(json!({"path":"../outside"})), context()).await.is_err());
        anyhow::Ok(())
    }.await;
    let closed = helper.close().await;
    result?;
    closed?;
    Ok(())
}
