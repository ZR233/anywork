//! Explicit migration and removal of one bound Thread's disposable execution files.
use std::path::{Component, Path, PathBuf};

use pl_protocol::Result;
use serde::{Deserialize, Serialize};

use super::{SessionFiles, path_safety};
use crate::remote::RemoteWorkspaceFileBackend;
use crate::workspace_file::{WorkspaceFileBackend, WorkspaceFileReadRequest};

/// Uses an already frozen physical binding. It never discovers or reconnects an endpoint.
#[derive(Debug)]
pub enum SessionTempBackend<'a> {
    Local(&'a Path),
    Ssh(&'a RemoteWorkspaceFileBackend),
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Migration {
    schema_version: u32,
    thread_key: String,
    moves: Vec<MigrationMove>,
    complete: bool,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", tag = "kind", deny_unknown_fields)]
enum MigrationMove {
    Scratch { name: String },
    Commands,
    Uploads,
}

impl MigrationMove {
    fn paths(&self, files: &SessionFiles) -> Result<(PathBuf, PathBuf)> {
        let (source, target) = match self {
            Self::Scratch { name } => {
                let mut components = Path::new(name).components();
                if !matches!(components.next(), Some(Component::Normal(_)))
                    || components.next().is_some()
                    || name.contains('\\')
                    || name == ".venv"
                {
                    return Err(failure("invalid scratch migration entry"));
                }
                (
                    files.root().join("scratch").join(name),
                    files.temp().join(name),
                )
            }
            Self::Commands => (files.root().join("commands"), files.commands()),
            Self::Uploads => (files.root().join("uploads"), files.uploads()),
        };
        Ok((source, target))
    }
}

impl SessionTempBackend<'_> {
    /// Converts only this explicitly bound Thread. A durable intent precedes every move.
    /// Old virtual environments remain at their original path; new ones are created on demand.
    pub async fn migrate(&self, files: &SessionFiles) -> Result<()> {
        let journal = files.root().join(".temp-layout-migration.json");
        let mut migration = if self.exists(&journal).await? {
            let value: Migration =
                serde_json::from_slice(&self.read(&journal).await?).map_err(failure)?;
            if value.schema_version != 1 || value.thread_key != files.thread_key() {
                return Err(failure("session temp migration identity/version mismatch"));
            }
            // Validate even a completed record before accepting it.
            let mut targets = std::collections::HashSet::new();
            for step in &value.moves {
                let (_, target) = step.paths(files)?;
                if !targets.insert(target) {
                    return Err(failure("duplicate session temp migration target"));
                }
            }
            value
        } else {
            let scratch = files.root().join("scratch");
            let mut moves = Vec::new();
            if self.exists(&scratch).await? {
                for name in self.entries(&scratch).await? {
                    if name != ".venv" {
                        moves.push(MigrationMove::Scratch { name });
                    }
                }
            }
            for (path, step) in [
                (files.root().join("commands"), MigrationMove::Commands),
                (files.root().join("uploads"), MigrationMove::Uploads),
            ] {
                if self.exists(&path).await? {
                    self.require_directory(&path).await?;
                    moves.push(step);
                }
            }
            if moves.is_empty() {
                return Ok(());
            }
            let mut destinations = std::collections::HashSet::new();
            for step in &moves {
                let (_, target) = step.paths(files)?;
                if !destinations.insert(target.clone()) || self.exists(&target).await? {
                    return Err(failure(format!(
                        "session temp migration target conflicts: {}",
                        target.display()
                    )));
                }
            }
            let value = Migration {
                schema_version: 1,
                thread_key: files.thread_key().to_owned(),
                moves,
                complete: false,
            };
            self.write(&journal, &serde_json::to_vec(&value).map_err(failure)?)
                .await?;
            value
        };
        if migration.complete {
            return Ok(());
        }
        self.create(&files.temp()).await?;
        for step in &migration.moves {
            let (source, target) = step.paths(files)?;
            match (self.exists(&source).await?, self.exists(&target).await?) {
                (true, false) => self.move_entry(&source, &target).await?,
                // The atomic move may have completed before its caller observed the ACK.
                (false, true) => {}
                _ => {
                    return Err(failure(format!(
                        "session temp migration cannot reconcile {}",
                        source.display()
                    )));
                }
            }
        }
        migration.complete = true;
        self.write(&journal, &serde_json::to_vec(&migration).map_err(failure)?)
            .await
    }

    /// Removes only the dedicated temp directory. Explicit absence is idempotent success.
    /// Callers must stop/join producers and confirm reliable persistence before invoking this.
    pub async fn remove(&self, files: &SessionFiles) -> Result<()> {
        let path = files.temp();
        if !self.exists(&path).await? {
            return Ok(());
        }
        match self {
            Self::Local(root) => {
                path_safety::remove_dir_all_no_follow_async(root, &root.join(&path))
                    .await
                    .map_err(failure)?
            }
            Self::Ssh(backend) => backend.remove_path(posix(&path), None, true).await?,
        }
        if self.exists(&path).await? {
            return Err(failure("session temp remains after removal"));
        }
        Ok(())
    }

    async fn exists(&self, path: &Path) -> Result<bool> {
        match self {
            Self::Local(root) => {
                let anchor = root
                    .ancestors()
                    .last()
                    .ok_or_else(|| failure("missing workspace root"))?;
                path_safety::validate_path_for_write_async(anchor, root)
                    .await
                    .map_err(failure)?;
                let path = root.join(path);
                path_safety::validate_path_for_write_async(root, &path)
                    .await
                    .map_err(failure)?;
                Ok(path_safety::metadata_if_real_async(&path)
                    .await
                    .map_err(failure)?
                    .is_some())
            }
            Self::Ssh(backend) => {
                // Stat resolves links, so inspect each directory entry before asking for stat.
                let mut parent = PathBuf::new();
                for component in path.components() {
                    let Component::Normal(name) = component else {
                        return Err(failure("session path is not relative"));
                    };
                    let mut entries = backend
                        .open_directory(if parent.as_os_str().is_empty() {
                            ".".into()
                        } else {
                            posix(&parent)
                        })
                        .await?;
                    let mut found = false;
                    while let Some(entry) = entries.next().await? {
                        if entry.name == name.to_string_lossy() {
                            if entry.is_symlink {
                                return Err(failure("session path crosses a symbolic link"));
                            }
                            found = true;
                            break;
                        }
                    }
                    if !found {
                        // Only a typed PathNotFound may establish absence; listing is not enough.
                        let candidate = parent.join(name);
                        return match backend
                            .stat_optional(posix(&candidate), None)
                            .await
                            .map_err(failure)?
                        {
                            None => Ok(false),
                            Some(_) => {
                                Err(failure("session directory changed while inspecting links"))
                            }
                        };
                    }
                    parent.push(name);
                }
                backend
                    .stat_optional(posix(path), None)
                    .await
                    .map(|value| value.is_some())
                    .map_err(failure)
            }
        }
    }

    async fn entries(&self, path: &Path) -> Result<Vec<String>> {
        let mut names = Vec::new();
        match self {
            Self::Local(root) => {
                let mut entries = tokio::fs::read_dir(root.join(path))
                    .await
                    .map_err(failure)?;
                while let Some(entry) = entries.next_entry().await.map_err(failure)? {
                    let name = entry
                        .file_name()
                        .into_string()
                        .map_err(|_| failure("non-UTF8 legacy session path"))?;
                    if name != ".venv"
                        && path_safety::is_link_or_reparse(
                            &tokio::fs::symlink_metadata(entry.path())
                                .await
                                .map_err(failure)?,
                        )
                    {
                        return Err(failure("legacy session contains a link or reparse point"));
                    }
                    names.push(name);
                }
            }
            Self::Ssh(backend) => {
                let mut entries = backend.open_directory(posix(path)).await?;
                while let Some(entry) = entries.next().await? {
                    if entry.is_symlink {
                        return Err(failure("legacy session contains a symbolic link"));
                    }
                    names.push(entry.name);
                }
            }
        }
        names.sort();
        Ok(names)
    }

    async fn require_directory(&self, path: &Path) -> Result<()> {
        let is_directory = match self {
            Self::Local(root) => tokio::fs::symlink_metadata(root.join(path))
                .await
                .map_err(failure)?
                .is_dir(),
            Self::Ssh(backend) => backend
                .stat_optional(posix(path), None)
                .await
                .map_err(failure)?
                .is_some_and(|stat| stat.is_dir),
        };
        if !is_directory {
            return Err(failure(format!(
                "legacy session directory has unexpected type: {}",
                path.display()
            )));
        }
        Ok(())
    }

    async fn read(&self, path: &Path) -> Result<Vec<u8>> {
        match self {
            Self::Local(root) => tokio::fs::read(root.join(path)).await.map_err(failure),
            Self::Ssh(backend) => backend
                .read_text(WorkspaceFileReadRequest {
                    path: posix(path),
                    cwd: None,
                })
                .await
                .map(String::into_bytes),
        }
    }

    async fn write(&self, path: &Path, bytes: &[u8]) -> Result<()> {
        // Reject linked ancestors before atomic publication too.
        self.exists(path).await?;
        match self {
            Self::Local(root) => {
                let path = root.join(path);
                let bytes = bytes.to_vec();
                tokio::task::spawn_blocking(move || super::write_file_atomically(&path, &bytes))
                    .await
                    .map_err(failure)?
                    .map_err(failure)
            }
            Self::Ssh(backend) => backend.write_bytes_atomic(posix(path), None, bytes).await,
        }
    }

    async fn create(&self, path: &Path) -> Result<()> {
        self.exists(path).await?;
        match self {
            Self::Local(root) => tokio::fs::create_dir_all(root.join(path))
                .await
                .map_err(failure),
            Self::Ssh(backend) => backend.create_directory(posix(path), None).await,
        }
    }

    async fn move_entry(&self, source: &Path, target: &Path) -> Result<()> {
        match self {
            Self::Local(root) => {
                let source = root.join(source);
                let target = root.join(target);
                tokio::task::spawn_blocking(move || super::move_owned_path(&source, &target))
                    .await
                    .map_err(failure)?
                    .map_err(failure)
            }
            Self::Ssh(backend) => {
                backend
                    .rename_path(posix(source), posix(target), None)
                    .await
            }
        }
    }
}

fn posix(path: &Path) -> String {
    path.to_string_lossy().replace('\\', "/")
}

fn failure(error: impl std::fmt::Display) -> pl_protocol::PureError {
    crate::tool_error("workspace", error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn put(root: &Path, path: impl AsRef<Path>, bytes: &[u8]) {
        let path = root.join(path);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, bytes).unwrap();
    }

    #[tokio::test]
    async fn migration_and_cleanup_preserve_deliveries_neighbors_and_original_venvs() {
        let workspace = tempfile::tempdir().unwrap();
        let root = workspace.path();
        let files = SessionFiles::new("raw-thread-id");
        let neighbor = SessionFiles::new("other-thread");
        put(root, files.root().join("scratch/probe.py"), b"probe");
        put(
            root,
            files.root().join("scratch/.venv/python"),
            b"old scratch venv",
        );
        put(root, files.root().join(".venv/python"), b"old root venv");
        put(root, files.root().join("commands/output"), b"captured");
        put(root, files.root().join("uploads/input"), b"input");
        put(root, files.artifacts().join("delivery"), b"keep");
        put(root, neighbor.temp().join("active"), b"neighbor");
        put(root, "user-file", b"user");

        let backend = SessionTempBackend::Local(root);
        backend.migrate(&files).await.unwrap();
        assert_eq!(
            std::fs::read(root.join(files.scratch()).join("probe.py")).unwrap(),
            b"probe"
        );
        assert_eq!(
            std::fs::read(root.join(files.commands()).join("output")).unwrap(),
            b"captured"
        );
        assert_eq!(
            std::fs::read(root.join(files.uploads()).join("input")).unwrap(),
            b"input"
        );
        assert!(!root.join(files.python_environment()).exists());
        backend.remove(&files).await.unwrap();
        backend.remove(&files).await.unwrap();
        backend.migrate(&files).await.unwrap();
        assert!(
            !root.join(files.temp()).exists(),
            "retry must not recreate removed temp"
        );
        for (path, bytes) in [
            (files.artifacts().join("delivery"), b"keep".as_slice()),
            (neighbor.temp().join("active"), b"neighbor".as_slice()),
            (
                files.root().join("scratch/.venv/python"),
                b"old scratch venv".as_slice(),
            ),
            (
                files.root().join(".venv/python"),
                b"old root venv".as_slice(),
            ),
            (PathBuf::from("user-file"), b"user".as_slice()),
        ] {
            assert_eq!(std::fs::read(root.join(path)).unwrap(), bytes);
        }
        let physical =
            crate::workspace_file::LocalWorkspaceFileBackend::new(root.to_owned(), false)
                .await
                .unwrap();
        super::super::prepare_session_files(&physical, &files)
            .await
            .unwrap();
        assert!(root.join(files.commands()).is_dir());
        assert!(!root.join(files.scratch()).join("probe.py").exists());
    }

    #[tokio::test]
    async fn migration_conflicts_before_moving_and_resumes_an_unacknowledged_move() {
        let workspace = tempfile::tempdir().unwrap();
        let root = workspace.path();
        let files = SessionFiles::new("thread");
        put(root, files.root().join("scratch/probe"), b"source");
        put(root, files.temp().join("probe"), b"target");
        let backend = SessionTempBackend::Local(root);
        assert!(backend.migrate(&files).await.is_err());
        assert_eq!(
            std::fs::read(root.join(files.temp()).join("probe")).unwrap(),
            b"target"
        );
        assert_eq!(
            std::fs::read(root.join(files.root()).join("scratch/probe")).unwrap(),
            b"source"
        );
        assert!(
            !root
                .join(files.root())
                .join(".temp-layout-migration.json")
                .exists()
        );

        std::fs::remove_file(root.join(files.temp()).join("probe")).unwrap();
        let journal = Migration {
            schema_version: 1,
            thread_key: files.thread_key().to_owned(),
            moves: vec![
                MigrationMove::Scratch {
                    name: "probe".into(),
                },
                MigrationMove::Commands,
            ],
            complete: false,
        };
        put(root, files.root().join("commands/output"), b"command");
        put(
            root,
            files.root().join(".temp-layout-migration.json"),
            &serde_json::to_vec(&journal).unwrap(),
        );
        super::super::move_owned_path(
            &root.join(files.root()).join("scratch/probe"),
            &root.join(files.temp()).join("probe"),
        )
        .unwrap();
        backend.migrate(&files).await.unwrap();
        backend.migrate(&files).await.unwrap();
        assert_eq!(
            std::fs::read(root.join(files.temp()).join("probe")).unwrap(),
            b"source"
        );
        assert_eq!(
            std::fs::read(root.join(files.commands()).join("output")).unwrap(),
            b"command"
        );
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn cleanup_rejects_linked_ancestors_and_unlinks_only_nested_links() {
        use std::os::unix::fs::symlink;
        let workspace = tempfile::tempdir().unwrap();
        let outside = tempfile::tempdir().unwrap();
        let root = workspace.path();
        let files = SessionFiles::new("thread");
        put(outside.path(), "important", b"keep");
        std::fs::create_dir_all(root.join(files.root())).unwrap();
        symlink(outside.path(), root.join(files.temp())).unwrap();
        let backend = SessionTempBackend::Local(root);
        assert!(backend.remove(&files).await.is_err());
        std::fs::remove_file(root.join(files.temp())).unwrap();
        std::fs::create_dir_all(root.join(files.temp())).unwrap();
        symlink(outside.path(), root.join(files.temp()).join("linked")).unwrap();
        backend.remove(&files).await.unwrap();
        assert_eq!(
            std::fs::read(outside.path().join("important")).unwrap(),
            b"keep"
        );
        assert!(!root.join(files.temp()).exists());

        std::fs::remove_dir_all(root.join(".anywork")).unwrap();
        symlink(outside.path(), root.join(".anywork")).unwrap();
        assert!(backend.remove(&files).await.is_err());
        assert_eq!(
            std::fs::read(outside.path().join("important")).unwrap(),
            b"keep"
        );
    }

    #[tokio::test]
    async fn failed_partial_removal_keeps_responsibility_retryable() {
        let workspace = tempfile::tempdir().unwrap();
        let root = workspace.path();
        let first = SessionFiles::new("first-member");
        let files = SessionFiles::new("second-member");
        put(root, first.temp().join("removable"), b"temp");
        put(root, files.temp(), b"wrong kind");
        put(root, files.artifacts().join("delivery"), b"keep");
        let backend = SessionTempBackend::Local(root);
        backend.remove(&first).await.unwrap();
        assert!(backend.remove(&files).await.is_err());
        assert!(!root.join(first.temp()).exists());
        std::fs::remove_file(root.join(files.temp())).unwrap();
        put(root, files.temp().join("fixed"), b"temp");
        backend.remove(&first).await.unwrap();
        backend.remove(&files).await.unwrap();
        assert!(!root.join(files.temp()).exists());
        assert_eq!(
            std::fs::read(root.join(files.artifacts()).join("delivery")).unwrap(),
            b"keep"
        );
    }
}
