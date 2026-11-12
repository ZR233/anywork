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
        collision: PathCollision,
    },
    Copy {
        source: String,
        target: String,
        recursive: bool,
        collision: PathCollision,
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
        collision: PathCollision,
    ) -> Result<(), ExecutionError> {
        self.validate(source)?;
        self.validate(target)?;
        self.mutate(Mutation::Rename {
            source: source.value.clone(),
            target: target.value.clone(),
            collision,
        })
        .await
    }
    /// Copies on this execution machine without traversing source links. Overwrite merges directories.
    pub async fn copy_path(
        &self,
        source: &TargetPath,
        target: &TargetPath,
        recursive: bool,
        collision: PathCollision,
    ) -> Result<(), ExecutionError> {
        self.validate(source)?;
        self.validate(target)?;
        self.mutate(Mutation::Copy {
            source: source.value.clone(),
            target: target.value.clone(),
            recursive,
            collision,
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
            if metadata.is_dir() && !super::is_link_boundary(&metadata) {
                if recursive {
                    tokio::fs::remove_dir_all(path).await
                } else {
                    tokio::fs::remove_dir(path).await
                }
            } else {
                tokio::fs::remove_file(path).await
            }
        }
        Mutation::Rename {
            source,
            target,
            collision,
        } => {
            super::rename::rename(
                std::path::Path::new(&source),
                std::path::Path::new(&target),
                collision,
            )
            .await
        }
        Mutation::Copy {
            source,
            target,
            recursive,
            collision,
        } => return copy(source, target, recursive, collision, executor, cancel).await,
    };
    result.map_err(|error| ExecutionError::io("filesystem mutation", error))
}

async fn copy(
    source: String,
    target: String,
    recursive: bool,
    collision: PathCollision,
    executor: Executor,
    cancel: CancellationToken,
) -> Result<(), ExecutionError> {
    if source == target {
        return Err(ExecutionError::InvalidInput(
            "cannot copy a path onto itself".into(),
        ));
    }
    let metadata = tokio::fs::symlink_metadata(&source)
        .await
        .map_err(|error| ExecutionError::io("copy metadata", error))?;
    if metadata.is_dir() && !super::is_link_boundary(&metadata) {
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
    if !super::is_link_boundary(&metadata) {
        let canonical_source = tokio::fs::canonicalize(&source)
            .await
            .map_err(|error| ExecutionError::io("copy source", error))?;
        match tokio::fs::canonicalize(&target).await {
            Ok(target) if target == canonical_source => {
                return Err(ExecutionError::InvalidInput(
                    "cannot copy a path onto itself".into(),
                ));
            }
            Ok(_) => {}
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => return Err(ExecutionError::io("copy target", error)),
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
        if source.to_str().is_none() || target.to_str().is_none() {
            return Err(ExecutionError::InvalidInput(
                "copy entry path is not UTF-8".into(),
            ));
        }
        let metadata = tokio::fs::symlink_metadata(&source)
            .await
            .map_err(|error| ExecutionError::io("copy metadata", error))?;
        match tokio::fs::symlink_metadata(&target).await {
            Ok(target_metadata)
                if metadata.is_dir()
                    && !super::is_link_boundary(&metadata)
                    && super::is_link_boundary(&target_metadata) =>
            {
                return Err(ExecutionError::InvalidInput(
                    "copy does not follow destination symbolic links".into(),
                ));
            }
            Ok(_) => {}
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => return Err(ExecutionError::io("copy target metadata", error)),
        }
        if super::is_link_boundary(&metadata) {
            copy_link(&source, &target, &metadata, collision, &cancel).await?;
        } else if metadata.is_dir() {
            match tokio::fs::create_dir(&target).await {
                Ok(()) => {}
                Err(error)
                    if collision == PathCollision::Overwrite
                        && error.kind() == io::ErrorKind::AlreadyExists =>
                {
                    let target_metadata = tokio::fs::symlink_metadata(&target)
                        .await
                        .map_err(|error| ExecutionError::io("copy directory metadata", error))?;
                    if !target_metadata.is_dir() || super::is_link_boundary(&target_metadata) {
                        return Err(ExecutionError::io("copy directory", error));
                    }
                }
                Err(error) => return Err(ExecutionError::io("copy directory", error)),
            }
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
                    mode: if collision == PathCollision::FailIfExists {
                        WriteMode::CreateNew
                    } else {
                        WriteMode::ReplaceAtomic
                    },
                    expected_len: None,
                },
                Some(permissions),
            )
            .await?;
            tokio::io::copy(&mut source, &mut writer)
                .await
                .map_err(|error| ExecutionError::io("copy file", error))?;
            if cancel.is_cancelled() {
                return Err(ExecutionError::Cancelled);
            }
            writer.finish().await?;
        } else {
            return Err(ExecutionError::InvalidInput(
                "copy requires a regular file or directory".into(),
            ));
        }
    }
    Ok(())
}

async fn copy_link(
    source: &std::path::Path,
    target: &std::path::Path,
    metadata: &std::fs::Metadata,
    collision: PathCollision,
    cancel: &CancellationToken,
) -> Result<(), ExecutionError> {
    if !metadata.is_symlink() {
        return Err(ExecutionError::InvalidInput(
            "copy of non-symlink reparse points is unsupported".into(),
        ));
    }
    let link = tokio::fs::read_link(source)
        .await
        .map_err(|error| ExecutionError::io("copy link", error))?;
    let parent = target
        .parent()
        .ok_or_else(|| ExecutionError::InvalidInput("copy target has no parent".into()))?
        .to_owned();
    let metadata = metadata.clone();
    let target = target.to_owned();
    let temporary = tokio::task::spawn_blocking(move || -> io::Result<_> {
        let directory = tempfile::tempdir_in(parent)?;
        let staged = directory.path().join("link");
        #[cfg(unix)]
        {
            let _ = metadata;
            std::os::unix::fs::symlink(link, &staged)?;
        }
        #[cfg(windows)]
        if metadata.is_dir() {
            std::os::windows::fs::symlink_dir(link, &staged)?;
        } else {
            std::os::windows::fs::symlink_file(link, &staged)?;
        }
        Ok((directory, staged))
    })
    .await
    .map_err(|error| ExecutionError::io("copy link task", io::Error::other(error)))?
    .map_err(|error| ExecutionError::io("copy link", error))?;
    if cancel.is_cancelled() {
        return Err(ExecutionError::Cancelled);
    }
    super::rename::rename(&temporary.1, &target, collision)
        .await
        .map_err(|error| ExecutionError::io("publish copied link", error))?;
    // The private staging directory owns only this operation's link.
    drop(temporary);
    Ok(())
}
