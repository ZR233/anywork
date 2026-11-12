use super::*;

impl ExecutorWorkspaceFileBackend {
    pub(super) async fn execute_patch(
        &self,
        cwd: String,
        patch: &str,
    ) -> std::result::Result<pl_patch::PatchReport, pl_patch::PatchFailure> {
        let failed = |error: String| pl_patch::PatchFailure {
            diagnostic: error,
            applied_changes: Vec::new(),
            changes_may_be_incomplete: false,
        };
        let paths = pl_patch::affected_paths(patch).map_err(|error| failed(error.to_string()))?;
        // Validate every role, including both move endpoints, before the single submission.
        for path in paths {
            let target = self
                .path_request(path.path, Some(cwd.clone()))
                .map_err(|error| failed(error.to_string()))?;
            let target = self
                .bound(target, true)
                .await
                .map_err(|error| failed(error.to_string()))?;
            self.ensure_writable(&target)
                .await
                .map_err(|error| failed(error.to_string()))?;
        }
        let cwd = self
            .bound(
                self.path_request(cwd, None)
                    .map_err(|error| failed(error.to_string()))?,
                true,
            )
            .await
            .map_err(|error| failed(error.to_string()))?;
        let mut result = match self.executor.fs().apply_patch(&cwd, patch).await {
            Ok(report) => Ok(report),
            Err(pl_remote_helper::PatchExecutionError::Patch(failure)) => Err(failure),
            Err(pl_remote_helper::PatchExecutionError::Execution(error)) => {
                Err(pl_patch::PatchFailure {
                    diagnostic: error.to_string(),
                    applied_changes: Vec::new(),
                    changes_may_be_incomplete: true,
                })
            }
        };
        let changes = match &mut result {
            Ok(report) => &mut report.changes,
            Err(failure) => &mut failure.applied_changes,
        };
        for change in changes {
            use pl_patch::PatchChange;
            let (changed, deleted) = match change {
                PatchChange::Add { path } | PatchChange::Update { path } => (Some(path), None),
                PatchChange::Delete { path } => (None, Some(path)),
                PatchChange::Move { source, target } => (Some(target), Some(source)),
            };
            for (path, removed) in changed
                .into_iter()
                .map(|path| (path, false))
                .chain(deleted.into_iter().map(|path| (path, true)))
            {
                let target = self.executor.join_path(&cwd, &*path).map_err(|error| {
                    pl_patch::PatchFailure {
                        diagnostic: error.to_string(),
                        applied_changes: Vec::new(),
                        changes_may_be_incomplete: true,
                    }
                })?;
                if removed {
                    self.notify_deleted(&target).await;
                } else {
                    self.notify_changed(&target).await;
                }
                *path = self.display_path(&target);
            }
        }
        result
    }
}
