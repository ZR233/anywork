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
                let cancel = executor.inner.closing.child_token();
                let _cancel = cancel.clone().drop_guard();
                self.executor.inner.tasks.spawn(async move {
                    let result = mutate_native(request, executor, cancel).await;
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
    executor: Executor,
    cancel: CancellationToken,
) -> Result<(), ExecutionError> {
    if cancel.is_cancelled() {
        return Err(ExecutionError::Cancelled);
    }
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
            if cancel.is_cancelled() {
                return Err(ExecutionError::Cancelled);
            }
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
        } => return copy(source, target, recursive, executor, cancel).await,
    };
    result.map_err(|error| ExecutionError::io("filesystem mutation", error))
}

async fn copy(
    source: String,
    target: String,
    recursive: bool,
    executor: Executor,
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
    let mut pending = Some((
        std::path::PathBuf::from(source),
        std::path::PathBuf::from(target),
    ));
    let mut directories: Vec<(tokio::fs::ReadDir, std::path::PathBuf)> = Vec::new();
    loop {
        if cancel.is_cancelled() {
            return Err(ExecutionError::Cancelled);
        }
        let (source, target) = if let Some(entry) = pending.take() {
            entry
        } else {
            let Some((reader, target)) = directories.last_mut() else {
                break;
            };
            match reader
                .next_entry()
                .await
                .map_err(|error| ExecutionError::io("copy directory entry", error))?
            {
                Some(entry) => (entry.path(), target.join(entry.file_name())),
                None => {
                    directories.pop();
                    continue;
                }
            }
        };
        let metadata = tokio::fs::symlink_metadata(&source)
            .await
            .map_err(|error| ExecutionError::io("copy metadata", error))?;
        match tokio::fs::symlink_metadata(&target).await {
            Ok(metadata) if metadata.is_symlink() => {
                return Err(ExecutionError::InvalidInput(
                    "copy does not follow destination symbolic links".into(),
                ));
            }
            Ok(_) => {}
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => return Err(ExecutionError::io("copy target metadata", error)),
        }
        if metadata.is_symlink() {
            return Err(ExecutionError::InvalidInput(
                "copy does not follow symbolic links".into(),
            ));
        }
        if metadata.is_dir() {
            tokio::fs::create_dir_all(&target)
                .await
                .map_err(|error| ExecutionError::io("copy directory", error))?;
            let entries = tokio::fs::read_dir(&source)
                .await
                .map_err(|error| ExecutionError::io("copy directory", error))?;
            directories.push((entries, target));
        } else if metadata.is_file() {
            // Reuse the same atomic publisher instead of truncating a destination
            // inode which may also be a hardlink to the source.
            let mut source = tokio::fs::File::open(source)
                .await
                .map_err(|error| ExecutionError::io("copy source", error))?;
            let permissions = source
                .metadata()
                .await
                .map_err(|error| ExecutionError::io("copy source metadata", error))?
                .permissions();
            let path = target
                .into_os_string()
                .into_string()
                .map_err(|_| ExecutionError::InvalidInput("copy target is not UTF-8".into()))?;
            let mut writer = super::write::open(
                executor.clone(),
                WriteDescriptor {
                    path,
                    mode: WriteMode::ReplaceAtomic,
                    expected_len: None,
                },
                Some(permissions),
            )
            .await?;
            tokio::io::copy(&mut source, &mut writer)
                .await
                .map_err(|error| ExecutionError::io("copy file", error))?;
            writer.finish().await?;
        } else {
            return Err(ExecutionError::InvalidInput(
                "copy requires a regular file or directory".into(),
            ));
        }
    }
    Ok(())
}
