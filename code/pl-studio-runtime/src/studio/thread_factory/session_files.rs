//! Bind one Thread's execution-side session layout before tools freeze the workspace.
use super::errors::resource_error;
use crate::thread_assembler::ThreadAssemblyError;
use pl_tool::workspace::{SessionFiles, ToolWorkspace, WorkspaceMutability};

/// Attaches [`SessionFiles::new`] using the original Thread identity.
///
/// Call this before [`ToolWorkspace`] is cloned into a frozen tool binding so
/// refresh, permissions, and host facts share one layout. The Thread key is
/// hashed once here; callers must not hash a `task-` key again.
pub(super) fn bind_thread_session_files(
    workspace: ToolWorkspace,
    thread_id: &str,
) -> ToolWorkspace {
    let lsp = workspace.lsp_runtime();
    ToolWorkspace::new(
        workspace
            .workspace()
            .clone()
            .with_session_files(SessionFiles::new(thread_id)),
    )
    .with_lsp_runtime(lsp)
}

/// Creates this Thread's scratch/artifacts/commands through the physical backend.
///
/// ReadOnly workspaces keep the bound layout but do not create directories.
/// Infrastructure preparation uses a confined backend so directory write policy
/// cannot refuse pool ignore files, and HostGranted never opens an arbitrary host path.
pub(super) async fn prepare_bound_session_files(
    workspace: &ToolWorkspace,
    remote: Option<&pl_tool::remote::RemoteWorkspaceHost>,
) -> Result<(), ThreadAssemblyError> {
    let files = workspace
        .workspace()
        .session_files()
        .cloned()
        .ok_or_else(|| {
            resource_error(
                "prepare Thread session files",
                std::io::Error::other("Thread workspace is missing bound session files"),
            )
        })?;
    if workspace.workspace().mutability() == WorkspaceMutability::ReadOnly {
        return Ok(());
    }
    match remote {
        Some(host) => pl_tool::workspace::prepare_session_files(&host.files, &files)
            .await
            .map_err(|error| resource_error("prepare remote Thread session files", error)),
        None => {
            let backend = pl_tool::workspace_file::LocalWorkspaceFileBackend::new(
                workspace.root().to_path_buf(),
                false,
            )
            .await
            .map_err(|error| resource_error("open confined session-file backend", error))?;
            pl_tool::workspace::prepare_session_files(&backend, &files)
                .await
                .map_err(|error| resource_error("prepare local Thread session files", error))
        }
    }
}

/// Latest `studio.session-files` fact from the bound layout, not a second string source.
pub(super) fn session_files_fact(
    workspace: &ToolWorkspace,
) -> Option<pl_core::thread::RuntimeFact> {
    let files = workspace.workspace().session_files()?;
    let posix = |path: std::path::PathBuf| path.to_string_lossy().replace('\\', "/");
    let text = format!(
        "Execution-side session files for this Thread (workspace-relative):\n\
         scratch: {}\n\
         artifacts: {}\n\
         commands: {}\n\
         uploads: {}\n\
         Python environment: {} (create on demand with `uv venv <path>`, then use `uv pip --python <path>`; never install into global Python).\n\
         These paths belong to the current workspace root and execution target. \
         They are not the host's internal session database, transfer cache, or \
         another Thread's directories.",
        posix(files.scratch()),
        posix(files.artifacts()),
        posix(files.commands()),
        posix(files.root().join("uploads")),
        posix(files.root().join(".venv")),
    );
    Some(pl_core::thread::RuntimeFact {
        source_id: "studio.session-files".into(),
        content: vec![pl_core::context::ContextContent::Text { text: text.into() }],
    })
}
