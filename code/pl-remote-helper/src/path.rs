use std::collections::HashMap;
use std::io;
use std::path::{Component, Path, PathBuf};

use pl_protocol::remote::{RemoteError, RemoteErrorCode};

#[derive(Debug)]
struct WorkspaceRoot {
    path: PathBuf,
    create_root: crate::workspace_dir::WorkspaceDir,
    _memory: crate::budget::ByteLease,
}
#[derive(Debug)]
struct Registry {
    roots: std::sync::RwLock<HashMap<String, WorkspaceRoot>>,
    next_id: std::sync::atomic::AtomicU64,
    budget: crate::budget::ResourceBudget,
}
#[derive(Debug, Clone)]
pub(crate) struct WorkspaceRegistry(std::sync::Arc<Registry>);
impl WorkspaceRegistry {
    pub(crate) fn new(budget: crate::budget::ResourceBudget) -> Self {
        Self(std::sync::Arc::new(Registry {
            roots: Default::default(),
            next_id: std::sync::atomic::AtomicU64::new(0),
            budget,
        }))
    }
    pub(crate) async fn resolve_workspace_root(
        path: &str,
    ) -> Result<(PathBuf, crate::workspace_dir::WorkspaceDir), RemoteError> {
        let canonical = tokio::fs::canonicalize(path)
            .await
            .map_err(|error| io_error("failed to open workspace", error))?;
        let metadata = tokio::fs::metadata(&canonical)
            .await
            .map_err(|error| io_error("failed to inspect workspace", error))?;
        if !metadata.is_dir() {
            return Err(remote_error(
                RemoteErrorCode::InvalidRequest,
                "workspace path is not a directory",
            ));
        }
        let root_path = canonical.clone();
        let create_root = tokio::task::spawn_blocking(move || {
            crate::workspace_dir::WorkspaceDir::open(&root_path)
        })
        .await
        .map_err(|error| io_error("open workspace capability task", io::Error::other(error)))?
        .map_err(|error| io_error("open workspace capability", error))?;
        Ok((canonical, create_root))
    }

    pub(crate) fn open_resolved(
        &self,
        canonical: PathBuf,
        create_root: crate::workspace_dir::WorkspaceDir,
    ) -> Result<(String, PathBuf), RemoteError> {
        let memory = self
            .0
            .budget
            .try_reserve(std::mem::size_of::<WorkspaceRoot>() + canonical.as_os_str().len())
            .ok_or_else(|| {
                remote_error(
                    RemoteErrorCode::ResourceExhausted,
                    "workspace handle budget exhausted",
                )
            })?;
        let sequence = self
            .0
            .next_id
            .try_update(
                std::sync::atomic::Ordering::Relaxed,
                std::sync::atomic::Ordering::Relaxed,
                |id| id.checked_add(1),
            )
            .map_err(|_| {
                remote_error(
                    RemoteErrorCode::ResourceExhausted,
                    "workspace identity exhausted",
                )
            })?;
        let id = format!("workspace-{sequence}");
        self.0
            .roots
            .write()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .insert(
                id.clone(),
                WorkspaceRoot {
                    path: canonical.clone(),
                    create_root,
                    _memory: memory,
                },
            );
        Ok((id, canonical))
    }
    pub(crate) fn close(&self, workspace_id: &str) -> Result<(), RemoteError> {
        let mut roots = self
            .0
            .roots
            .write()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let result = roots.remove(workspace_id).map(|_| ()).ok_or_else(|| {
            remote_error(
                RemoteErrorCode::WorkspaceNotFound,
                "workspace handle is closed",
            )
        });
        if roots.len().saturating_mul(4) < roots.capacity() {
            roots.shrink_to_fit();
        }
        result
    }

    pub(crate) async fn resolve_existing(
        &self,
        workspace_id: &str,
        path: &str,
    ) -> Result<PathBuf, RemoteError> {
        let (root, joined) = self.join(workspace_id, path)?;
        reject_symlink_ancestors(&root, &joined, false).await?;
        tokio::fs::canonicalize(&joined)
            .await
            .map_err(|error| io_error("failed to resolve remote path", error))
            .and_then(|canonical| ensure_within(&root, canonical))
    }

    pub(crate) async fn resolve_for_write(
        &self,
        workspace_id: &str,
        path: &str,
    ) -> Result<PathBuf, RemoteError> {
        let (root, joined) = self.join(workspace_id, path)?;
        reject_symlink_ancestors(&root, &joined, true).await?;
        ensure_within(&root, joined)
    }

    pub(crate) fn len(&self) -> usize {
        self.0
            .roots
            .read()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .len()
    }
    pub(crate) fn root(&self, workspace_id: &str) -> Result<PathBuf, RemoteError> {
        self.0
            .roots
            .read()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(workspace_id)
            .map(|root| root.path.clone())
            .ok_or_else(|| {
                remote_error(
                    RemoteErrorCode::WorkspaceNotFound,
                    "workspace handle is closed",
                )
            })
    }
    pub(crate) fn create_root(
        &self,
        workspace_id: &str,
    ) -> Result<crate::workspace_dir::WorkspaceDir, RemoteError> {
        self.0
            .roots
            .read()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(workspace_id)
            .map(|root| root.create_root.clone())
            .ok_or_else(|| {
                remote_error(
                    RemoteErrorCode::WorkspaceNotFound,
                    "workspace handle is closed",
                )
            })
    }
    fn join(&self, workspace_id: &str, path: &str) -> Result<(PathBuf, PathBuf), RemoteError> {
        let root = self.root(workspace_id)?;
        let relative = normalize_relative(path)?;
        let joined = root.join(relative);
        Ok((root, joined))
    }
}

fn normalize_relative(path: &str) -> Result<PathBuf, RemoteError> {
    let mut normalized = PathBuf::new();
    for component in Path::new(path).components() {
        match component {
            Component::CurDir => {}
            Component::Normal(value) => normalized.push(value),
            Component::ParentDir | Component::RootDir | Component::Prefix(_) => {
                return Err(remote_error(
                    RemoteErrorCode::WorkspaceEscape,
                    format!("path '{path}' escapes the workspace"),
                ));
            }
        }
    }
    Ok(normalized)
}

async fn reject_symlink_ancestors(
    root: &Path,
    path: &Path,
    allow_missing_tail: bool,
) -> Result<(), RemoteError> {
    let relative = path.strip_prefix(root).map_err(|_| {
        remote_error(
            RemoteErrorCode::WorkspaceEscape,
            "path escapes the workspace",
        )
    })?;
    let mut current = root.to_path_buf();
    for component in relative.components() {
        current.push(component);
        match tokio::fs::symlink_metadata(&current).await {
            Ok(metadata) if metadata.file_type().is_symlink() => {
                return Err(remote_error(
                    RemoteErrorCode::WorkspaceEscape,
                    format!("symbolic link entry '{}' is not allowed", current.display()),
                ));
            }
            Ok(_) => {}
            Err(error) if error.kind() == io::ErrorKind::NotFound && allow_missing_tail => break,
            Err(error) => return Err(io_error("failed to inspect remote path", error)),
        }
    }
    Ok(())
}

fn ensure_within(root: &Path, path: PathBuf) -> Result<PathBuf, RemoteError> {
    if path == root || path.starts_with(root) {
        Ok(path)
    } else {
        Err(remote_error(
            RemoteErrorCode::WorkspaceEscape,
            "path escapes the workspace",
        ))
    }
}

pub(crate) fn remote_error(code: RemoteErrorCode, message: impl Into<String>) -> RemoteError {
    RemoteError {
        code,
        message: message.into(),
    }
}

pub(crate) fn io_error(operation: &str, error: io::Error) -> RemoteError {
    let code = if error.kind() == io::ErrorKind::NotFound {
        RemoteErrorCode::PathNotFound
    } else {
        RemoteErrorCode::Io
    };
    remote_error(code, format!("{operation}: {error}"))
}
