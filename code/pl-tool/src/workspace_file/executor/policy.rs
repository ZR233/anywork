use super::*;

impl ExecutorWorkspaceFileBackend {
    /// Resolve the existing ancestor on the target, retaining missing suffixes. Inspect
    /// every existing descendant without following links; this is product policy, not
    /// a server sandbox. Checks and mutations retain the ordinary filesystem race.
    pub(crate) async fn bound(
        &self,
        path: TargetPath,
        follow_final: bool,
    ) -> std::result::Result<TargetPath, WorkspaceFileError> {
        if let Some(metadata) = self.executor.fs().symlink_metadata(&self.root).await? {
            if metadata.is_symlink {
                return Err(WorkspaceFileError::Policy(
                    "workspace root is a link or reparse point".into(),
                ));
            }
            let canonical = self.executor.fs().canonicalize(&self.root).await?;
            if self
                .executor
                .relative_path(&self.root, &canonical)?
                .as_deref()
                != Some(".")
            {
                return Err(WorkspaceFileError::Policy(
                    "workspace root changed physical identity".into(),
                ));
            }
        }
        let separators: &[_] = if self.executor.target_info().os == "windows" {
            &['/', '\\']
        } else {
            &['/']
        };
        if !self.allow_workspace_escape && path.as_str().split(separators).any(|part| part == "..")
        {
            return Err(WorkspaceFileError::Policy(
                "path escapes the workspace".into(),
            ));
        }
        // Replacing/removing the final entry does not follow a final link. Reads,
        // appends and patch preflight resolve the entry itself. Ancestors always
        // retain the same no-link policy.
        let mut current = if follow_final {
            path.clone()
        } else {
            self.executor
                .parent_path(&path)?
                .ok_or_else(|| WorkspaceFileError::Policy("path has no parent entry".into()))?
        };
        let mut resolved = None;
        loop {
            if current == self.root {
                break;
            }
            if let Some(metadata) = self.executor.fs().symlink_metadata(&current).await? {
                if metadata.is_symlink {
                    return Err(WorkspaceFileError::Policy(
                        "path contains a symbolic link or Windows reparse point".into(),
                    ));
                }
                if resolved.is_none() {
                    let canonical = self.executor.fs().canonicalize(&current).await?;
                    let tail = self
                        .executor
                        .relative_path(&current, &path)?
                        .ok_or_else(|| {
                            WorkspaceFileError::Policy("invalid target ancestor".into())
                        })?;
                    resolved = Some(if tail == "." {
                        canonical
                    } else {
                        self.executor.join_path(&canonical, &tail)?
                    });
                }
            }
            let Some(parent) = self.executor.parent_path(&current)? else {
                break;
            };
            current = parent;
        }
        let resolved = match resolved {
            Some(path) => path,
            None => {
                let tail = self
                    .executor
                    .relative_path(&self.root, &path)?
                    .ok_or_else(|| {
                        WorkspaceFileError::Policy("path is outside the workspace".into())
                    })?;
                self.executor.join_path(&self.root, &tail)?
            }
        };
        if !self.allow_workspace_escape
            && self
                .executor
                .relative_path(&self.root, &resolved)?
                .is_none()
        {
            return Err(WorkspaceFileError::Policy(
                "path resolves outside workspace".into(),
            ));
        }
        Ok(resolved)
    }
    pub(crate) async fn ensure_writable(&self, path: &TargetPath) -> Result<()> {
        let Some(workspace) = &self.workspace else {
            return Ok(());
        };
        workspace.ensure_workspace_writable()?;
        let policy = workspace.workspace();
        let Some(paths) = policy.writable_paths() else {
            return Ok(());
        };
        if self
            .executor
            .relative_path(&self.root, path)
            .map_err(file_error)?
            .is_none()
        {
            return Ok(());
        }
        let mut allowed = paths
            .iter()
            .map(|p| {
                p.to_str()
                    .map(|path| {
                        if self.executor.target_info().os == "windows" {
                            path.to_owned()
                        } else {
                            path.replace(std::path::MAIN_SEPARATOR, "/")
                        }
                    })
                    .ok_or_else(|| file_error("writable path is not UTF-8"))
            })
            .collect::<Result<Vec<_>>>()?;
        if let Some(files) = policy.session_files() {
            for relative in [files.scratch(), files.artifacts()] {
                allowed.push(
                    self.executor
                        .join_path(
                            &self.root,
                            relative
                                .to_str()
                                .ok_or_else(|| file_error("session path is not UTF-8"))?,
                        )
                        .map_err(file_error)?
                        .as_str()
                        .into(),
                );
            }
        }
        for allowed in allowed {
            let allowed = self
                .bound(
                    self.executor
                        .join_path(&self.root, &allowed)
                        .map_err(file_error)?,
                    true,
                )
                .await
                .map_err(file_error)?;
            if self
                .executor
                .relative_path(&allowed, path)
                .map_err(file_error)?
                .is_some()
            {
                return Ok(());
            }
        }
        Err(file_error(
            "path is outside the directory Agent writablePaths boundary",
        ))
    }
}
