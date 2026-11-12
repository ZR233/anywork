//! File-tool integration over the production helper transport (not an SSH host).
use super::*;
use crate::workspace::{AgentWorkspace, WorkspaceMutability};
use crate::workspace_file::{
    ThreadStatPathTool, ThreadWorkspaceFileTool, ThreadWriteFileTool, WorkspaceFileToolKind,
};
use anyhow::ensure;
use pl_agent_tool::Tool;
use serde_json::json;
use std::{
    path::PathBuf,
    sync::atomic::{AtomicBool, Ordering},
};

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
        let root = helper.root.path();
        let backend = Arc::new(helper.files.clone());
        let workspace = ToolWorkspace::new(AgentWorkspace::confined(root, WorkspaceMutability::ReadWrite));
        let mutation = |kind: WorkspaceMutationKind| WorkspaceMutationTool::new(
            kind, kind.definition(), backend.clone(), workspace.clone(),
        );
        let create = mutation(WorkspaceMutationKind::CreateDirectory).execute(input(json!({"path":"nested"})), context()).await?;
        ensure!(create.payload().content() == "Created directory nested");
        let write = ThreadWriteFileTool::new(backend.clone(), workspace.clone());
        let written = TypedTool::execute(&write, pl_tool_filesystem::write_file::WriteFileInput {
            path: "nested/a".into(), content: "original\n".into(), mode: pl_tool_filesystem::WriteMode::Create,
        }, context()).await?;
        ensure!(written.payload().format() == "pl.tool.file-write");
        let value: serde_json::Value = serde_json::from_str(written.payload().content())?;
        ensure!(value == json!({"path":"nested/a","mode":"create","bytesWritten":9}));
        ensure!(TypedTool::execute(&write, pl_tool_filesystem::write_file::WriteFileInput {
            path: "nested/a".into(), content: "lost".into(), mode: pl_tool_filesystem::WriteMode::Create,
        }, context()).await.is_err());
        let stat = TypedTool::execute(&ThreadStatPathTool::new(backend.clone()),
            pl_tool_filesystem::PathInput { path: "missing".into() }, context()).await?;
        ensure!(serde_json::from_str::<serde_json::Value>(stat.payload().content())? == json!({"path":"missing","exists":false}));
        mutation(WorkspaceMutationKind::Copy).execute(input(json!({"from":"nested/a","to":"target","collision":"failIfExists"})), context()).await?;
        let collision = mutation(WorkspaceMutationKind::Move).execute(input(json!({"from":"nested/a","to":"target","collision":"failIfExists"})), context()).await.unwrap_err();
        ensure!(collision.source.to_string().contains("destination already exists"));
        ensure!(std::fs::read(root.join("nested/a"))? == b"original\n");
        std::fs::write(root.join("target"), b"old")?;
        mutation(WorkspaceMutationKind::Copy).execute(input(json!({"from":"nested/a","to":"target","collision":"overwrite"})), context()).await?;
        ensure!(std::fs::read(root.join("target"))? == b"original\n");
        // Remote copy has always supported directory traversal; keep it in the backend.
        mutation(WorkspaceMutationKind::Copy).execute(input(json!({"from":"nested","to":"copied","collision":"failIfExists"})), context()).await?;
        ensure!(std::fs::read(root.join("copied/a"))? == b"original\n");
        mutation(WorkspaceMutationKind::Move).execute(input(json!({"from":"target","to":"moved","collision":"failIfExists"})), context()).await?;
        ensure!(!root.join("target").exists());
        mutation(WorkspaceMutationKind::Delete).execute(input(json!({"path":"moved","mode":"file"})), context()).await?;
        ensure!(!root.join("moved").exists());
        ensure!(mutation(WorkspaceMutationKind::Delete).execute(input(json!({"path":"copied","mode":"file"})), context()).await.is_err());
        ensure!(mutation(WorkspaceMutationKind::Delete).execute(input(json!({"path":"copied","mode":"emptyDirectory"})), context()).await.is_err());
        ensure!(root.join("copied/a").exists());
        mutation(WorkspaceMutationKind::Delete).execute(input(json!({"path":"copied","mode":"recursiveDirectory"})), context()).await?;
        ensure!(!root.join("copied").exists());
        let kind = WorkspaceFileToolKind::ApplyPatch;
        let patch = ThreadWorkspaceFileTool::new(kind, backend.clone(), workspace.clone(), kind.definition());
        let output = patch.execute(OpaquePayload::text("*** Begin Patch\n*** Update File: nested/a\n@@\n-original\n+patched\n*** End Patch"), context()).await?;
        ensure!(output.payload().format() == "pl.tool.workspace-file");
        ensure!(std::fs::read(root.join("nested/a"))? == b"patched\n");
        ensure!(mutation(WorkspaceMutationKind::CreateDirectory).execute(input(json!({"path":"../outside"})), context()).await.is_err());
        anyhow::Ok(())
    }.await;
    let closed = helper.close().await;
    result?;
    closed?;
    Ok(())
}

/// Inserts an externally owned destination after the tool's first absence check.
/// All filesystem operations still run through the real production adapter.
struct DestinationAppears {
    inner: ExecutorMutationCapability,
    destination: PathBuf,
    directory: bool,
    inserted: Arc<AtomicBool>,
}

impl MutationBackend for DestinationAppears {
    type Error = PureError;
    type Path = String;

    async fn resolve_existing(&self, path: &str) -> Result<String> {
        self.inner.resolve_existing(path).await
    }
    async fn resolve_for_write(&self, path: &str) -> Result<String> {
        self.inner.resolve_for_write(path).await
    }
    fn ensure_writable(&self, path: &String) -> Result<()> {
        self.inner.ensure_writable(path)
    }
    fn display_path(&self, path: &String) -> String {
        self.inner.display_path(path)
    }
    fn diagnostic_path(&self, path: &String) -> String {
        self.inner.diagnostic_path(path)
    }
    async fn is_directory(&self, path: &String) -> Result<bool> {
        self.inner.is_directory(path).await
    }
    async fn exists(&self, path: &String) -> Result<bool> {
        let existed = self.inner.exists(path).await?;
        if !existed && !self.inserted.swap(true, Ordering::SeqCst) {
            if self.directory {
                std::fs::create_dir_all(self.destination.join("nested"))?;
                std::fs::write(self.destination.join("nested/keep"), b"external tree")?;
            } else {
                std::fs::write(&self.destination, b"external file")?;
            }
        }
        Ok(existed)
    }
    async fn create_directory(&self, path: &String) -> Result<()> {
        self.inner.create_directory(path).await
    }
    async fn remove_file(&self, path: &String) -> Result<()> {
        self.inner.remove_file(path).await
    }
    async fn remove_directory(&self, path: &String, recursive: bool) -> Result<()> {
        self.inner.remove_directory(path, recursive).await
    }
    async fn copy(&self, from: &String, to: &String, collision: PathCollision) -> Result<()> {
        self.inner.copy(from, to, collision).await
    }
    async fn rename(&self, from: &String, to: &String, collision: PathCollision) -> Result<()> {
        self.inner.rename(from, to, collision).await
    }
}

#[tokio::test]
async fn fail_if_exists_preserves_destination_appearing_before_remote_mutation()
-> anyhow::Result<()> {
    let helper = helper::Helper::start(executable::remote_helper_executable()).await?;
    let result = async {
        let root = helper.root.path();
        let backend = Arc::new(helper.files.clone());
        let workspace = ToolWorkspace::new(AgentWorkspace::confined(root, WorkspaceMutability::ReadWrite));
        let mut failures = Vec::new();
        for moving in [false, true] {
            for directory in [false, true] {
                let name = format!("{}-{}", if moving { "move" } else { "copy" }, if directory { "tree" } else { "file" });
                let source = format!("{name}-source");
                let target = format!("{name}-target");
                std::fs::write(root.join(&source), b"source")?;
                let inserted = Arc::new(AtomicBool::new(false));
                let capability = DestinationAppears {
                    inner: ExecutorMutationCapability {
                        backend: backend.clone(), workspace: workspace.clone(),
                        tool: if moving { "move_path" } else { "copy_path" },
                    },
                    destination: root.join(&target), directory, inserted: inserted.clone(),
                };
                let args = pl_tool_filesystem::CopyMoveInput {
                    from: source.clone(), to: target.clone(),
                    collision: pl_tool_filesystem::PathCollision::FailIfExists,
                };
                let outcome = if moving {
                    TypedTool::execute(&pl_tool_filesystem::move_path::MovePathTool::new(), args, capability).await
                } else {
                    TypedTool::execute(&pl_tool_filesystem::copy_path::CopyPathTool::new(), args, capability).await
                };
                let conflict = outcome.is_err();
                let preserved = if directory {
                    std::fs::read(root.join(&target).join("nested/keep")).ok().as_deref() == Some(b"external tree")
                } else {
                    std::fs::read(root.join(&target)).ok().as_deref() == Some(b"external file")
                };
                let source_preserved = std::fs::read(root.join(&source)).ok().as_deref() == Some(b"source");
                if !inserted.load(Ordering::SeqCst) || !conflict || !preserved || !source_preserved {
                    failures.push(format!("{name}: result={outcome:?}, inserted={}, destination_preserved={preserved}, source_preserved={source_preserved}", inserted.load(Ordering::SeqCst)));
                }
            }
        }
        ensure!(failures.is_empty(), "{}", failures.join("\n"));
        anyhow::Ok(())
    }.await;
    let closed = helper.close().await;
    result?;
    closed?;
    Ok(())
}

#[tokio::test]
async fn copy_and_move_keep_remote_collision_policies() -> anyhow::Result<()> {
    let helper = helper::Helper::start(executable::remote_helper_executable()).await?;
    let result = async {
        let root = helper.root.path();
        let backend = Arc::new(helper.files.clone());
        let workspace = ToolWorkspace::new(AgentWorkspace::confined(
            root,
            WorkspaceMutability::ReadWrite,
        ));
        for moving in [false, true] {
            // No target keeps the normal FailIfExists success path. Existing
            // files and trees may only be replaced under explicit Overwrite.
            for target_kind in [None, Some(false), Some(true)] {
                let name = format!("{}-{target_kind:?}", if moving { "move" } else { "copy" });
                let source = format!("{name}-source");
                let target = format!("{name}-target");
                std::fs::write(root.join(&source), b"source")?;
                match target_kind {
                    Some(true) => {
                        std::fs::create_dir_all(root.join(&target).join("nested"))?;
                        std::fs::write(root.join(&target).join("nested/old"), b"replace")?;
                    }
                    Some(false) => std::fs::write(root.join(&target), b"replace")?,
                    None => {}
                }
                let kind = if moving {
                    WorkspaceMutationKind::Move
                } else {
                    WorkspaceMutationKind::Copy
                };
                let tool = WorkspaceMutationTool::new(
                    kind,
                    kind.definition(),
                    backend.clone(),
                    workspace.clone(),
                );
                let collision = if target_kind.is_some() {
                    "overwrite"
                } else {
                    "failIfExists"
                };
                let output = tool
                    .execute(
                        input(json!({"from":source,"to":target,"collision":collision})),
                        context(),
                    )
                    .await;
                if target_kind == Some(true) {
                    ensure!(
                        output.is_err(),
                        "native copy/rename must not delete a directory to replace it with a file"
                    );
                    ensure!(std::fs::read(root.join(&target).join("nested/old"))? == b"replace");
                    ensure!(std::fs::read(root.join(&source))? == b"source");
                    continue;
                }
                let output = output?;
                ensure!(
                    output.payload().content()
                        == format!(
                            "{} {source} to {target}",
                            if moving { "Moved" } else { "Copied" }
                        )
                );
                ensure!(std::fs::read(root.join(&target))? == b"source");
                ensure!(root.join(&source).exists() != moving);
            }
        }
        anyhow::Ok(())
    }
    .await;
    let closed = helper.close().await;
    result?;
    closed?;
    Ok(())
}

#[tokio::test]
async fn target_policy_prechecks_both_move_endpoints_and_preserves_partial_patch_facts()
-> anyhow::Result<()> {
    use crate::workspace_file::{WorkspaceFileBackend, WorkspaceFileWriteRequest};
    let helper = helper::Helper::start(executable::remote_helper_executable()).await?;
    let result = async {
        for remote in [false, true] {
            let local = tempfile::tempdir()?;
            let outside = tempfile::tempdir()?;
            let root = if remote { helper.root.path() } else { local.path() };
            std::fs::create_dir_all(root.join("allowed"))?;
            std::fs::write(root.join("allowed/source"), b"original\n")?;
            let workspace = ToolWorkspace::new(AgentWorkspace::host_permitted(root, root, Some(vec![root.join("allowed")])));
            let files = if remote { helper.files.clone() } else { ExecutorWorkspaceFileBackend::local(root.into(), false).await? }.with_workspace(workspace.clone());
            let write = |path: String| WorkspaceFileWriteRequest { path, cwd: None, mode: crate::workspace::WriteMode::Overwrite, content: "written\n".into() };
            ensure!(files.write_text(write("denied".into())).await.is_err());
            let patch = "*** Begin Patch\n*** Add File: allowed/preflight\n+must not appear\n*** Update File: allowed/source\n*** Move to: denied\n@@\n-original\n+moved\n*** End Patch";
            let failure = files.apply_patch(".".into(), patch).await.unwrap_err();
            ensure!(failure.applied_changes.is_empty() && !failure.changes_may_be_incomplete);
            ensure!(!root.join("allowed/preflight").exists() && !root.join("denied").exists());
            ensure!(std::fs::read(root.join("allowed/source"))? == b"original\n");
            let failure = files.apply_patch(".".into(), "*** Begin Patch\n*** Add File: allowed/applied\n+kept\n*** Update File: allowed/source\n@@\n-missing\n+bad\n*** End Patch").await.unwrap_err();
            ensure!(matches!(failure.applied_changes.as_slice(), [pl_patch::PatchChange::Add { path }] if path == "allowed/applied"));
            ensure!(!failure.changes_may_be_incomplete);
            ensure!(std::fs::read(root.join("allowed/applied"))? == b"kept\n");
            let external = outside.path().join("host-file").to_str().unwrap().to_owned();
            ensure!(files.write_text(write(external.clone())).await.is_err());
            let grant = pl_core::tool::execution_policy::ExecutionGrant::default().with_capability(crate::approval::HOST_WORKSPACE_ACCESS);
            let granted = files.for_grant(&grant).expect("host-permitted workspace");
            granted.write_text(write(external)).await?;
            ensure!(std::fs::read(outside.path().join("host-file"))? == b"written\n");
            let readonly = files.clone().with_workspace(ToolWorkspace::new(AgentWorkspace::confined(root, WorkspaceMutability::ReadOnly)));
            ensure!(readonly.for_grant(&grant).is_none());
            ensure!(readonly.write_text(write("allowed/source".into())).await.is_err());
            ensure!(readonly.apply_patch(".".into(), "*** Begin Patch\n*** Delete File: allowed/source\n*** End Patch").await.is_err());
            ensure!(std::fs::read(root.join("allowed/source"))? == b"original\n");
        }
        anyhow::Ok(())
    }.await;
    let closed = helper.close().await;
    result?;
    closed?;
    Ok(())
}
