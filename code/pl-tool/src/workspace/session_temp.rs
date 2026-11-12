//! Explicit migration and removal of one bound Thread's disposable execution files.
use std::path::{Component, Path, PathBuf};

use pl_protocol::Result;
use serde::{Deserialize, Serialize};

use super::SessionFiles;
use crate::workspace_file::{ExecutorWorkspaceFileBackend, WorkspaceFileError};
use crate::workspace_file::{WorkspaceFileBackend, WorkspaceFileReadRequest};

/// Uses an already frozen physical binding. It never discovers or reconnects an endpoint.
#[derive(Debug)]
pub struct SessionTempBackend {
    files: ExecutorWorkspaceFileBackend,
}

/// Retains the physical removal boundary independently of the connection manager.
#[derive(Debug, thiserror::Error)]
#[error(transparent)]
pub struct SessionRemovalError(#[from] WorkspaceFileError);
impl SessionRemovalError {
    pub fn definitely_not_started(&self) -> bool {
        !matches!(self.0, WorkspaceFileError::Removal(_))
    }
    fn is_absent(&self) -> bool {
        self.0.is_not_found()
    }
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

impl SessionTempBackend {
    pub fn new(files: &ExecutorWorkspaceFileBackend) -> Self {
        Self {
            files: files.clone(),
        }
    }
    pub async fn local(root: &Path) -> Result<Self> {
        let executor = pl_remote_helper::Executor::local().map_err(failure)?;
        let root = executor
            .path(
                root.to_str()
                    .ok_or_else(|| failure("workspace path is not UTF-8"))?,
            )
            .map_err(failure)?;
        let mut ancestor = Some(root.clone());
        while let Some(path) = ancestor {
            if executor
                .fs()
                .symlink_metadata(&path)
                .await
                .map_err(failure)?
                .is_some_and(|metadata| metadata.is_symlink)
            {
                return Err(failure("workspace root crosses a link or reparse point"));
            }
            ancestor = executor.parent_path(&path).map_err(failure)?;
        }
        Ok(Self {
            files: ExecutorWorkspaceFileBackend::new(executor, root.as_str()).map_err(failure)?,
        })
    }

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
        self.remove_dedicated(&files.temp()).await.map_err(failure)
    }

    /// Permanently removes only this Thread's private execution SessionFiles directory.
    /// The lifecycle owner must have joined its producers and released reliable readers/writers.
    pub async fn remove_session(
        &self,
        files: &SessionFiles,
    ) -> std::result::Result<(), SessionRemovalError> {
        self.remove_dedicated(&files.root()).await
    }

    /// Inspects this bound SessionFiles root without following links. An I/O or transport error
    /// is never absence; a lifecycle owner uses this to reconcile an unacknowledged removal.
    pub async fn session_exists(&self, files: &SessionFiles) -> Result<bool> {
        self.exists(&files.root()).await
    }

    async fn remove_dedicated(&self, path: &Path) -> std::result::Result<(), SessionRemovalError> {
        if self
            .files
            .inspect_path(posix(path), None)
            .await?
            .is_some_and(|metadata| !metadata.is_dir)
        {
            return Err(
                WorkspaceFileError::Policy("session removal requires a directory".into()).into(),
            );
        }
        let result = self
            .files
            .remove_path(posix(path), None, true)
            .await
            .map_err(SessionRemovalError::from);
        match result {
            Err(error) if error.is_absent() => Ok(()),
            result => result,
        }
    }

    async fn exists(&self, path: &Path) -> Result<bool> {
        self.files
            .inspect_path(posix(path), None)
            .await
            .map(|value| value.is_some())
            .map_err(failure)
    }
    async fn entries(&self, path: &Path) -> Result<Vec<String>> {
        let mut names = Vec::new();
        let mut entries = self.files.open_directory(posix(path)).await?;
        while let Some(entry) = entries.next().await? {
            // Existing virtual environments stay in place even when their internal links
            // are valid; every migrated entry itself must be an owned real directory/file.
            if entry.name != ".venv" && entry.is_symlink {
                return Err(failure("legacy session contains a link or reparse point"));
            }
            names.push(entry.name);
        }
        names.sort();
        Ok(names)
    }
    async fn require_directory(&self, path: &Path) -> Result<()> {
        if !self
            .files
            .inspect_path(posix(path), None)
            .await
            .map_err(failure)?
            .is_some_and(|stat| stat.is_dir)
        {
            return Err(failure("legacy session directory has unexpected type"));
        }
        Ok(())
    }
    async fn read(&self, path: &Path) -> Result<Vec<u8>> {
        self.files
            .read_text(WorkspaceFileReadRequest {
                path: posix(path),
                cwd: None,
            })
            .await
            .map(String::into_bytes)
    }
    async fn write(&self, path: &Path, bytes: &[u8]) -> Result<()> {
        self.files
            .write_bytes_atomic(posix(path), None, bytes)
            .await
    }
    async fn create(&self, path: &Path) -> Result<()> {
        self.files.create_directory(posix(path), None).await
    }
    async fn move_entry(&self, source: &Path, target: &Path) -> Result<()> {
        self.files
            .rename_path(
                posix(source),
                posix(target),
                None,
                pl_tool_filesystem::PathCollision::FailIfExists,
            )
            .await
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

    /// Explicit observation, not a timing threshold in the default regression suite.
    #[tokio::test]
    #[ignore = "explicit directory deletion timing; creates isolated files"]
    async fn session_directory_removal_timing() {
        for sample in 0..3 {
            let workspace = tempfile::tempdir().unwrap();
            let root = workspace.path();
            let files = SessionFiles::new("timing-owner");
            let neighbor = SessionFiles::new("timing-neighbor");
            put(root, neighbor.artifacts().join("keep"), b"neighbor");
            for directory in 0..16 {
                for file in 0..64 {
                    put(
                        root,
                        files.root().join(format!("{directory}/nested/deep/{file}")),
                        b"disposable",
                    );
                }
            }
            let started = std::time::Instant::now();
            SessionTempBackend::local(root)
                .await
                .unwrap()
                .remove_session(&files)
                .await
                .unwrap();
            println!(
                "SESSION_DIRECTORY_DELETE sample={sample} files=1024 elapsed_us={}",
                started.elapsed().as_micros()
            );
            assert!(!root.join(files.root()).exists());
            assert_eq!(
                std::fs::read(root.join(neighbor.artifacts()).join("keep")).unwrap(),
                b"neighbor"
            );
        }
    }

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

        let backend = SessionTempBackend::local(root).await.unwrap();
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
            crate::workspace_file::ExecutorWorkspaceFileBackend::local(root.to_owned(), false)
                .await
                .unwrap();
        super::super::prepare_session_files(&physical, &files)
            .await
            .unwrap();
        assert!(root.join(files.commands()).is_dir());
        assert!(!root.join(files.scratch()).join("probe.py").exists());
        backend.remove_session(&files).await.unwrap();
        backend.remove_session(&files).await.unwrap();
        assert!(!root.join(files.root()).exists());
        assert!(!backend.session_exists(&files).await.unwrap());
        assert_eq!(
            std::fs::read(root.join(neighbor.temp()).join("active")).unwrap(),
            b"neighbor"
        );
        assert_eq!(std::fs::read(root.join("user-file")).unwrap(), b"user");
    }

    #[tokio::test]
    async fn migration_conflicts_before_moving_and_resumes_an_unacknowledged_move() {
        let workspace = tempfile::tempdir().unwrap();
        let root = workspace.path();
        let files = SessionFiles::new("thread");
        put(root, files.root().join("scratch/probe"), b"source");
        put(root, files.temp().join("probe"), b"target");
        let backend = SessionTempBackend::local(root).await.unwrap();
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
        let backend = SessionTempBackend::local(root).await.unwrap();
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
        symlink(outside.path(), root.join(files.root()).join("linked")).unwrap();
        backend.remove_session(&files).await.unwrap();
        assert_eq!(
            std::fs::read(outside.path().join("important")).unwrap(),
            b"keep"
        );
        symlink(outside.path(), root.join(files.root())).unwrap();
        assert!(backend.remove_session(&files).await.is_err());
        assert!(backend.session_exists(&files).await.is_err());
        std::fs::remove_file(root.join(files.root())).unwrap();

        std::fs::remove_dir_all(root.join(".anywork")).unwrap();
        symlink(outside.path(), root.join(".anywork")).unwrap();
        assert!(backend.remove(&files).await.is_err());
        assert!(backend.remove_session(&files).await.is_err());
        assert!(backend.session_exists(&files).await.is_err());
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
        let backend = SessionTempBackend::local(root).await.unwrap();
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
