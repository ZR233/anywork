use super::*;
use std::sync::OnceLock;

/// A host-issued target saved in the original tool delivery. This is not a path
/// permission: consumers must select it from trusted delivery/history, never UI input.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DeferredWorkspaceFile {
    pub canonical_path: String,
    pub size: u64,
    pub modified_at: Option<i64>,
    pub executor_instance: String,
    pub workspace_root: String,
    pub workspace_binding: Option<String>,
    pub host_workspace_access: bool,
}

// ExecutorId is only process-local. A random startup identity prevents an old
// persisted target from accidentally matching a new process's counter value.
fn process_instance() -> std::result::Result<&'static str, WorkspaceFileError> {
    static INSTANCE: OnceLock<std::result::Result<String, String>> = OnceLock::new();
    INSTANCE
        .get_or_init(|| {
            let mut random = [0; 32];
            getrandom::fill(&mut random).map_err(|error| error.to_string())?;
            Ok(hex::encode(random))
        })
        .as_ref()
        .map(String::as_str)
        .map_err(|error| {
            WorkspaceFileError::Policy(format!(
                "cannot establish executor startup identity: {error}"
            ))
        })
}

impl ExecutorWorkspaceFileBackend {
    fn deferred_executor_instance(&self) -> std::result::Result<String, WorkspaceFileError> {
        Ok(format!("{}:{}", process_instance()?, self.executor.id()))
    }

    fn deferred_workspace_binding(&self) -> Option<String> {
        self.workspace
            .as_ref()
            .map(ToolWorkspace::authorization_identity)
    }

    pub(super) async fn freeze_deferred_file(
        &self,
        path: &str,
    ) -> std::result::Result<DeferredWorkspaceFile, WorkspaceFileError> {
        let path = self
            .bound(self.path_request(path.into(), None)?, true)
            .await?;
        let path = self.executor.fs().canonicalize(&path).await?;
        let metadata = self
            .executor
            .fs()
            .metadata(&path)
            .await?
            .filter(|metadata| metadata.is_file)
            .ok_or_else(|| {
                WorkspaceFileError::Policy("deferred source is not a regular file".into())
            })?;
        Ok(DeferredWorkspaceFile {
            canonical_path: path.as_str().into(),
            size: metadata.len,
            modified_at: metadata.modified_at,
            executor_instance: self.deferred_executor_instance()?,
            workspace_root: self.root.as_str().into(),
            workspace_binding: self.deferred_workspace_binding(),
            host_workspace_access: self.allow_workspace_escape,
        })
    }

    async fn deferred_path(
        &self,
        target: &DeferredWorkspaceFile,
    ) -> std::result::Result<TargetPath, WorkspaceFileError> {
        if self.executor.is_closed()
            || target.executor_instance != self.deferred_executor_instance()?
            || target.workspace_root != self.root.as_str()
            || target.workspace_binding != self.deferred_workspace_binding()
        {
            return Err(WorkspaceFileError::Policy(
                "deferred file execution/workspace binding is no longer valid".into(),
            ));
        }
        let mut authorized = self.clone();
        if target.host_workspace_access
            && self
                .workspace
                .as_ref()
                .map_or(!self.allow_workspace_escape, |w| {
                    !w.workspace().boundary().allows_host_paths()
                })
        {
            return Err(WorkspaceFileError::Policy(
                "deferred host grant is no longer permitted".into(),
            ));
        }
        authorized.allow_workspace_escape = target.host_workspace_access;
        let path = authorized
            .bound(self.executor.path(&target.canonical_path)?, true)
            .await?;
        if path.as_str() != target.canonical_path {
            return Err(WorkspaceFileError::Policy(
                "deferred file canonical path changed".into(),
            ));
        }
        let metadata =
            self.executor.fs().metadata(&path).await?.ok_or_else(|| {
                WorkspaceFileError::Policy("deferred file source is missing".into())
            })?;
        if !metadata.is_file
            || metadata.len != target.size
            || metadata.modified_at != target.modified_at
        {
            return Err(WorkspaceFileError::Policy(
                "deferred file source changed".into(),
            ));
        }
        Ok(path)
    }

    /// Opens the original, host-selected target with the existing bounded streaming
    /// reader. The caller enforces the saved size and validates again after EOF.
    pub async fn open_deferred_file(
        &self,
        target: &DeferredWorkspaceFile,
    ) -> std::result::Result<pl_remote_helper::fs::FileReader, WorkspaceFileError> {
        let path = self.deferred_path(target).await?;
        Ok(self.executor.fs().read(&path).await?)
    }

    /// Rechecks the frozen binding, confined boundary and observable source metadata.
    /// Use after EOF as well as before delivery; size/mtime cannot detect every edit.
    pub async fn validate_deferred_file(
        &self,
        target: &DeferredWorkspaceFile,
    ) -> std::result::Result<(), WorkspaceFileError> {
        self.deferred_path(target).await.map(|_| ())
    }
}
