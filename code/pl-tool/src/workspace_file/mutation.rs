//! Target-independent policy adaptation for the independent filesystem tools.
use crate::workspace_file::{ExecutorWorkspaceFileBackend, WorkspaceFileBackend};
use crate::{tool_error, workspace::ToolWorkspace};
use pl_agent_tool::typed::{TypedTool, decode_json};
use pl_core::{
    context::{ContextContent, OpaquePayload},
    tool::{
        ToolOutput,
        opaque::{CallContext, ToolError},
    },
};
use pl_protocol::{PureError, Result};
use pl_tool_filesystem::{MutationBackend, MutationError, PathCollision};
use std::sync::Arc;

#[derive(Debug, Clone)]
pub struct WorkspaceMutationTool {
    definition: pl_agent_tool::ToolDefinition,
    kind: WorkspaceMutationKind,
    backend: Arc<ExecutorWorkspaceFileBackend>,
    workspace: ToolWorkspace,
}

#[derive(Debug, Clone, Copy)]
pub enum WorkspaceMutationKind {
    CreateDirectory,
    Delete,
    Copy,
    Move,
}

impl WorkspaceMutationKind {
    pub fn all() -> &'static [Self] {
        &[Self::CreateDirectory, Self::Delete, Self::Copy, Self::Move]
    }
    fn name(self) -> &'static str {
        match self {
            Self::CreateDirectory => "create_directory",
            Self::Delete => "delete_path",
            Self::Copy => "copy_path",
            Self::Move => "move_path",
        }
    }
    pub fn definition(self) -> pl_agent_tool::ToolDefinition {
        match self {
            Self::CreateDirectory => {
                pl_tool_filesystem::create_directory::definition::<ExecutorMutationCapability>()
            }
            Self::Delete => {
                pl_tool_filesystem::delete_path::definition::<ExecutorMutationCapability>()
            }
            Self::Copy => pl_tool_filesystem::copy_path::definition::<ExecutorMutationCapability>(),
            Self::Move => pl_tool_filesystem::move_path::definition::<ExecutorMutationCapability>(),
        }
    }
}

impl WorkspaceMutationTool {
    pub fn new(
        kind: WorkspaceMutationKind,
        definition: pl_agent_tool::ToolDefinition,
        backend: Arc<ExecutorWorkspaceFileBackend>,
        workspace: ToolWorkspace,
    ) -> Self {
        Self {
            definition,
            kind,
            backend: Arc::new(backend.as_ref().clone().with_workspace(workspace.clone())),
            workspace,
        }
    }
}

impl pl_agent_tool::Tool for WorkspaceMutationTool {
    type Input = OpaquePayload;
    type Context = CallContext;
    type Output = ToolOutput;
    type Error = ToolError;
    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        &self.definition
    }

    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> std::result::Result<ToolOutput, ToolError> {
        self.execute_workspace(input, context.into()).await
    }
}

impl WorkspaceMutationTool {
    pub async fn execute_workspace(
        &self,
        input: OpaquePayload,
        context: crate::invocation::WorkspaceInvocation,
    ) -> std::result::Result<ToolOutput, ToolError> {
        if context.cancellation.is_cancelled() {
            return Err(ToolError::new(pl_core::thread::ThreadError::Cancelled));
        }
        self.workspace
            .ensure_workspace_writable()
            .map_err(ToolError::new)?;
        let _guard = tokio::select! {
            biased;
            _ = context.cancellation.cancelled() => return Err(ToolError::new(pl_core::thread::ThreadError::Cancelled)),
            guard = self.workspace.write_lock() => guard,
        };
        if context.cancellation.is_cancelled() {
            return Err(ToolError::new(pl_core::thread::ThreadError::Cancelled));
        }
        let granted = self.backend.for_grant(&context.grant);
        let backend = ExecutorMutationCapability {
            backend: granted
                .map(Arc::new)
                .unwrap_or_else(|| self.backend.clone()),
            workspace: self.workspace.clone(),
            tool: self.kind.name(),
        };
        let text = match self.kind {
            WorkspaceMutationKind::CreateDirectory => {
                pl_tool_filesystem::create_directory::CreateDirectoryTool::new()
                    .execute(
                        decode_json(input.content()).map_err(ToolError::new)?,
                        backend,
                    )
                    .await
                    .map_err(ToolError::new)?
            }
            WorkspaceMutationKind::Delete => pl_tool_filesystem::delete_path::DeletePathTool::new()
                .execute(
                    decode_json(input.content()).map_err(ToolError::new)?,
                    backend,
                )
                .await
                .map_err(|error| mutation_error(self.kind.name(), error))?,
            WorkspaceMutationKind::Copy => pl_tool_filesystem::copy_path::CopyPathTool::new()
                .execute(
                    decode_json(input.content()).map_err(ToolError::new)?,
                    backend,
                )
                .await
                .map_err(|error| mutation_error(self.kind.name(), error))?,
            WorkspaceMutationKind::Move => pl_tool_filesystem::move_path::MovePathTool::new()
                .execute(
                    decode_json(input.content()).map_err(ToolError::new)?,
                    backend,
                )
                .await
                .map_err(|error| mutation_error(self.kind.name(), error))?,
        };
        Ok(ToolOutput::new(
            OpaquePayload::text(text.clone()),
            vec![ContextContent::Text { text: text.into() }],
        ))
    }
}

fn mutation_error(tool: &str, error: MutationError<PureError>) -> ToolError {
    ToolError::new(match error {
        MutationError::Backend(error) => error,
        MutationError::RequiresDirectory => tool_error(tool, "delete mode requires a directory"),
        MutationError::DestinationExists(_) => tool_error(tool, "destination already exists"),
        error => tool_error(tool, error),
    })
}

struct ExecutorMutationCapability {
    backend: Arc<ExecutorWorkspaceFileBackend>,
    workspace: ToolWorkspace,
    tool: &'static str,
}

impl ExecutorMutationCapability {
    async fn stat(&self, path: &str) -> Result<Option<crate::workspace_file::WorkspaceFileStat>> {
        self.backend
            .inspect_path(path.to_string(), None)
            .await
            .map_err(crate::workspace_file::file_error)
    }
}
impl MutationBackend for ExecutorMutationCapability {
    type Error = PureError;
    type Path = String;
    async fn resolve_existing(&self, path: &str) -> Result<String> {
        if self.tool == "delete_path" || self.tool == "move_path" {
            let target = self
                .backend
                .path_request(path.into(), None)
                .map_err(crate::workspace_file::file_error)?;
            let target = self
                .backend
                .bound(target, true)
                .await
                .map_err(crate::workspace_file::file_error)?;
            self.backend.ensure_writable(&target).await?;
        }
        self.stat(path).await?.ok_or_else(|| {
            tool_error(
                self.tool,
                if self.tool == "delete_path" {
                    "path does not exist"
                } else {
                    "source does not exist"
                },
            )
        })?;
        Ok(path.to_string())
    }
    async fn resolve_for_write(&self, path: &str) -> Result<String> {
        let target = self
            .backend
            .path_request(path.into(), None)
            .map_err(crate::workspace_file::file_error)?;
        let target = self
            .backend
            .bound(target, true)
            .await
            .map_err(crate::workspace_file::file_error)?;
        self.backend.ensure_writable(&target).await?;
        Ok(path.to_string())
    }
    fn ensure_writable(&self, _path: &String) -> Result<()> {
        self.workspace.ensure_workspace_writable()
    }
    fn display_path(&self, path: &String) -> String {
        path.clone()
    }
    fn diagnostic_path(&self, path: &String) -> String {
        path.clone()
    }
    async fn is_directory(&self, path: &String) -> Result<bool> {
        self.stat(path)
            .await?
            .map(|stat| stat.is_dir)
            .ok_or_else(|| tool_error(self.tool, "path does not exist"))
    }
    async fn exists(&self, path: &String) -> Result<bool> {
        Ok(self.stat(path).await?.is_some())
    }
    async fn create_directory(&self, path: &String) -> Result<()> {
        self.backend.create_directory(path.clone(), None).await
    }
    async fn remove_file(&self, path: &String) -> Result<()> {
        self.backend
            .remove_path(path.clone(), None, false)
            .await
            .map_err(crate::workspace_file::file_error)
    }
    async fn remove_directory(&self, path: &String, recursive: bool) -> Result<()> {
        self.backend
            .remove_path(path.clone(), None, recursive)
            .await
            .map_err(crate::workspace_file::file_error)
    }
    async fn copy(&self, from: &String, to: &String, collision: PathCollision) -> Result<()> {
        let recursive = self.is_directory(from).await?;
        self.backend
            .copy_path(from.clone(), to.clone(), None, recursive, collision)
            .await
    }
    async fn rename(&self, from: &String, to: &String, collision: PathCollision) -> Result<()> {
        self.backend
            .rename_path(from.clone(), to.clone(), None, collision)
            .await
    }
}

#[cfg(test)]
mod tests {
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

    use crate::test_fixture_helper as executable;

    use crate::test_fixture_remote as helper;
}
