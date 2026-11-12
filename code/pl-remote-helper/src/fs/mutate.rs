//! Target-local filesystem mutations. No workspace/session or transfer registry.
use super::*;

#[derive(Serialize, Deserialize)]
pub(crate) enum Mutation {
    CreateDir {
        path: String,
        recursive: bool,
    },
    Remove {
        path: String,
        recursive: bool,
    },
    Rename {
        source: String,
        target: String,
    },
    Copy {
        source: String,
        target: String,
        recursive: bool,
    },
}

impl FileSystem {
    async fn mutate(&self, request: Mutation) -> Result<(), ExecutionError> {
        match &self.executor.inner.backend {
            ExecutorBackend::Local => {
                let (send, receive) = oneshot::channel();
                let executor = self.executor.clone();
                self.executor.inner.tasks.spawn(async move {
                    let result = mutate_native(request, executor.inner.closing.clone()).await;
                    let _ = send.send(result);
                });
                receive.await.map_err(|_| {
                    ExecutionError::Disconnected("filesystem mutation result is unknown".into())
                })?
            }
            ExecutorBackend::Remote(connection) => connection.json("/fs/mutate", &request).await,
        }
    }
    pub async fn create_dir(
        &self,
        path: &TargetPath,
        recursive: bool,
    ) -> Result<(), ExecutionError> {
        self.validate(path)?;
        self.mutate(Mutation::CreateDir {
            path: path.value.clone(),
            recursive,
        })
        .await
    }
    /// Removes the final directory entry. A final symlink is never traversed.
    pub async fn remove(&self, path: &TargetPath, recursive: bool) -> Result<(), ExecutionError> {
        self.validate(path)?;
        self.mutate(Mutation::Remove {
            path: path.value.clone(),
            recursive,
        })
        .await
    }
    pub async fn rename(
        &self,
        source: &TargetPath,
        target: &TargetPath,
    ) -> Result<(), ExecutionError> {
        self.validate(source)?;
        self.validate(target)?;
        self.mutate(Mutation::Rename {
            source: source.value.clone(),
            target: target.value.clone(),
        })
        .await
    }
    /// Copies on this execution machine. Recursive copy rejects symlinks.
    pub async fn copy_path(
        &self,
        source: &TargetPath,
        target: &TargetPath,
        recursive: bool,
    ) -> Result<(), ExecutionError> {
        self.validate(source)?;
        self.validate(target)?;
        self.mutate(Mutation::Copy {
            source: source.value.clone(),
            target: target.value.clone(),
            recursive,
        })
        .await
    }
}

pub(crate) async fn mutate_native(
    request: Mutation,
    cancel: CancellationToken,
) -> Result<(), ExecutionError> {
    let result = match request {
        Mutation::CreateDir { path, recursive } => {
            if recursive {
                tokio::fs::create_dir_all(path).await
            } else {
                tokio::fs::create_dir(path).await
            }
        }
        Mutation::Remove { path, recursive } => {
            let metadata = tokio::fs::symlink_metadata(&path)
                .await
                .map_err(|error| ExecutionError::io("remove metadata", error))?;
            if metadata.is_dir() && !metadata.is_symlink() {
                if recursive {
                    tokio::fs::remove_dir_all(path).await
                } else {
                    tokio::fs::remove_dir(path).await
                }
            } else {
                tokio::fs::remove_file(path).await
            }
        }
        Mutation::Rename { source, target } => tokio::fs::rename(source, target).await,
        Mutation::Copy {
            source,
            target,
            recursive,
        } => return copy(source, target, recursive, cancel).await,
    };
    result.map_err(|error| ExecutionError::io("filesystem mutation", error))
}

async fn copy(
    source: String,
    target: String,
    recursive: bool,
    cancel: CancellationToken,
) -> Result<(), ExecutionError> {
    let metadata = tokio::fs::symlink_metadata(&source)
        .await
        .map_err(|error| ExecutionError::io("copy metadata", error))?;
    if metadata.is_dir() {
        if !recursive {
            return Err(ExecutionError::InvalidInput(
                "directory copy requires recursive=true".into(),
            ));
        }
        let canonical_source = tokio::fs::canonicalize(&source)
            .await
            .map_err(|error| ExecutionError::io("copy source", error))?;
        let target_path = std::path::Path::new(&target);
        let parent = target_path
            .parent()
            .ok_or_else(|| ExecutionError::InvalidInput("copy target has no parent".into()))?;
        let canonical_parent = tokio::fs::canonicalize(parent)
            .await
            .map_err(|error| ExecutionError::io("copy target parent", error))?;
        let resolved_target = canonical_parent.join(
            target_path
                .file_name()
                .ok_or_else(|| ExecutionError::InvalidInput("copy target has no name".into()))?,
        );
        if resolved_target.starts_with(&canonical_source) {
            return Err(ExecutionError::InvalidInput(
                "cannot copy a directory into itself".into(),
            ));
        }
    }
    let mut pending = vec![(
        std::path::PathBuf::from(source),
        std::path::PathBuf::from(target),
    )];
    while let Some((source, target)) = pending.pop() {
        if cancel.is_cancelled() {
            return Err(ExecutionError::Cancelled);
        }
        let metadata = tokio::fs::symlink_metadata(&source)
            .await
            .map_err(|error| ExecutionError::io("copy metadata", error))?;
        if metadata.is_symlink() {
            return Err(ExecutionError::InvalidInput(
                "copy does not follow symbolic links".into(),
            ));
        }
        if metadata.is_dir() {
            tokio::fs::create_dir_all(&target)
                .await
                .map_err(|error| ExecutionError::io("copy directory", error))?;
            let mut entries = tokio::fs::read_dir(&source)
                .await
                .map_err(|error| ExecutionError::io("copy directory", error))?;
            while let Some(entry) = entries
                .next_entry()
                .await
                .map_err(|error| ExecutionError::io("copy directory entry", error))?
            {
                pending.push((entry.path(), target.join(entry.file_name())));
            }
        } else if metadata.is_file() {
            tokio::fs::copy(source, target)
                .await
                .map_err(|error| ExecutionError::io("copy file", error))?;
        } else {
            return Err(ExecutionError::InvalidInput(
                "copy requires a regular file or directory".into(),
            ));
        }
    }
    Ok(())
}
