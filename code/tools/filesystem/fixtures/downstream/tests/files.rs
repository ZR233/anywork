//! A separate Cargo workspace: real calls without Anywork host feature unification.
use pl_agent_tool::{
    Tool,
    typed::{TypedTool, prepare_json},
};
use pl_patch::{PatchBackend, PatchError, PatchPathDisplay, PatchResult};
use pl_tool_filesystem::apply_patch::{ApplyPatchTool, PatchContext};
use pl_tool_filesystem::copy_path::CopyPathTool;
use pl_tool_filesystem::create_directory::CreateDirectoryTool;
use pl_tool_filesystem::delete_path::{DeleteMode, DeletePathInput, DeletePathTool};
use pl_tool_filesystem::move_path::MovePathTool;
use pl_tool_filesystem::stat_path::StatPathTool;
use pl_tool_filesystem::write_file::{WriteFileInput, WriteFileTool};
use pl_tool_filesystem::*;
use std::{
    fs,
    io::{self, Write},
    path::{Path, PathBuf},
};

#[derive(Clone)]
struct Files(PathBuf);
impl Files {
    fn path(&self, path: &str) -> PathBuf {
        self.0.join(path)
    }
    fn parent(path: &Path) -> io::Result<()> {
        fs::create_dir_all(path.parent().unwrap())
    }
    fn check_collision(path: &Path, collision: PathCollision) -> io::Result<()> {
        if collision == PathCollision::FailIfExists && path.try_exists()? {
            return Err(io::Error::new(
                io::ErrorKind::AlreadyExists,
                "destination already exists",
            ));
        }
        Ok(())
    }
}

impl WriteBackend for Files {
    type Error = io::Error;
    async fn write_text(&self, request: WriteRequest) -> io::Result<()> {
        assert!(request.cwd.is_none());
        let path = self.path(&request.path);
        Self::parent(&path)?;
        let mut options = fs::OpenOptions::new();
        options.write(true);
        match request.mode {
            WriteMode::Create => {
                options.create_new(true);
            }
            WriteMode::Overwrite => {
                options.create(true).truncate(true);
            }
            WriteMode::Append => {
                options.create(true).append(true);
            }
        }
        options.open(path)?.write_all(request.content.as_bytes())
    }
}
impl StatBackend for Files {
    type Error = io::Error;
    async fn stat_optional(&self, request: StatRequest) -> io::Result<Option<FileStat>> {
        assert!(request.cwd.is_none());
        match fs::metadata(self.path(&request.path)) {
            Ok(stat) => Ok(Some(FileStat {
                path: request.path,
                is_file: stat.is_file(),
                is_dir: stat.is_dir(),
                len: stat.is_file().then_some(stat.len()),
                readonly: Some(stat.permissions().readonly()),
                modified_at: Some(123),
            })),
            Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
            Err(error) => Err(error),
        }
    }
}
impl MutationBackend for Files {
    type Error = io::Error;
    type Path = PathBuf;
    async fn resolve_existing(&self, path: &str) -> io::Result<PathBuf> {
        let path = self.path(path);
        fs::metadata(&path)?;
        Ok(path)
    }
    async fn resolve_for_write(&self, path: &str) -> io::Result<PathBuf> {
        Ok(self.path(path))
    }
    fn ensure_writable(&self, _path: &PathBuf) -> io::Result<()> {
        Ok(())
    }
    fn display_path(&self, path: &PathBuf) -> String {
        path.strip_prefix(&self.0)
            .unwrap()
            .to_string_lossy()
            .into_owned()
    }
    fn diagnostic_path(&self, path: &PathBuf) -> String {
        path.display().to_string()
    }
    async fn is_directory(&self, path: &PathBuf) -> io::Result<bool> {
        Ok(fs::metadata(path)?.is_dir())
    }
    async fn exists(&self, path: &PathBuf) -> io::Result<bool> {
        path.try_exists()
    }
    async fn create_directory(&self, path: &PathBuf) -> io::Result<()> {
        fs::create_dir_all(path)
    }
    async fn remove_file(&self, path: &PathBuf) -> io::Result<()> {
        fs::remove_file(path)
    }
    async fn remove_directory(&self, path: &PathBuf, recursive: bool) -> io::Result<()> {
        if recursive {
            fs::remove_dir_all(path)
        } else {
            fs::remove_dir(path)
        }
    }
    async fn copy(&self, from: &PathBuf, to: &PathBuf, collision: PathCollision) -> io::Result<()> {
        Self::parent(to)?;
        Self::check_collision(to, collision)?;
        fs::copy(from, to).map(|_| ())
    }
    async fn rename(
        &self,
        from: &PathBuf,
        to: &PathBuf,
        collision: PathCollision,
    ) -> io::Result<()> {
        Self::parent(to)?;
        Self::check_collision(to, collision)?;
        fs::rename(from, to)
    }
}
impl PatchPathDisplay for Files {
    fn display_path(&self, path: &Path) -> String {
        path.strip_prefix(&self.0)
            .unwrap()
            .to_string_lossy()
            .into_owned()
    }
}
impl PatchBackend for Files {
    async fn resolve_existing(&self, path: &str) -> PatchResult<PathBuf> {
        MutationBackend::resolve_existing(self, path)
            .await
            .map_err(PatchError::new)
    }
    async fn resolve_for_write(&self, path: &str) -> PatchResult<PathBuf> {
        Ok(self.path(path))
    }
    async fn reject_symlink_write(&self, _path: &Path) -> PatchResult<()> {
        Ok(())
    }
    async fn ensure_file(&self, path: &Path) -> PatchResult<()> {
        if fs::metadata(path).map_err(PatchError::new)?.is_file() {
            Ok(())
        } else {
            Err(PatchError::new("expected file"))
        }
    }
    async fn read_to_string(&self, path: &Path) -> PatchResult<String> {
        fs::read_to_string(path).map_err(PatchError::new)
    }
    async fn read_optional_text(&self, path: &Path) -> PatchResult<Option<String>> {
        match fs::read_to_string(path) {
            Ok(content) => Ok(Some(content)),
            Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
            Err(error) => Err(PatchError::new(error)),
        }
    }
    async fn create_parent_dirs(&self, path: &Path) -> PatchResult<()> {
        Self::parent(path).map_err(PatchError::new)
    }
    async fn write_text(&self, path: &Path, content: &str) -> PatchResult<()> {
        fs::write(path, content).map_err(PatchError::new)
    }
    async fn remove_file(&self, path: &Path) -> PatchResult<()> {
        fs::remove_file(path).map_err(PatchError::new)
    }
}
fn args(path: &str, content: &str, mode: WriteMode) -> WriteFileInput {
    WriteFileInput {
        path: path.into(),
        content: content.into(),
        mode,
    }
}
fn pair(from: &str, to: &str, collision: PathCollision) -> CopyMoveInput {
    CopyMoveInput {
        from: from.into(),
        to: to.into(),
        collision,
    }
}

#[test]
fn exact_utf8_writes_modes_and_metadata() {
    futures::executor::block_on(async {
        let root = tempfile::tempdir().unwrap();
        let files = Files(root.path().into());
        let write = prepare_json::<WriteFileTool<Files>>()
            .unwrap()
            .attach(WriteFileTool::new());
        let receipt = write
            .execute(
                r#"{"path":"text","content":"中文\n","mode":"create"}"#.into(),
                files.clone(),
            )
            .await
            .unwrap();
        assert_eq!(receipt.bytes_written, 7);
        assert_eq!(
            serde_json::to_value(receipt).unwrap(),
            serde_json::json!({
                "path":"text", "mode":"create", "bytesWritten":7
            })
        );
        let error = write
            .execute(
                r#"{"path":"text","content":"lost","mode":"create"}"#.into(),
                files.clone(),
            )
            .await
            .unwrap_err();
        assert!(
            matches!(error, pl_agent_tool::typed::InvocationError::Tool(error) if error.kind() == io::ErrorKind::AlreadyExists)
        );
        assert_eq!(fs::read_to_string(files.path("text")).unwrap(), "中文\n");
        TypedTool::execute(
            &WriteFileTool::new(),
            args("text", "!", WriteMode::Append),
            files.clone(),
        )
        .await
        .unwrap();
        assert_eq!(fs::read_to_string(files.path("text")).unwrap(), "中文\n!");
        TypedTool::execute(
            &WriteFileTool::new(),
            args("text", "", WriteMode::Overwrite),
            files.clone(),
        )
        .await
        .unwrap();
        assert_eq!(fs::read(files.path("text")).unwrap(), b"");
        TypedTool::execute(
            &WriteFileTool::new(),
            args("new", "appended", WriteMode::Append),
            files.clone(),
        )
        .await
        .unwrap();
        let stat = TypedTool::execute(
            &StatPathTool::new(),
            PathInput { path: "new".into() },
            files.clone(),
        )
        .await
        .unwrap();
        assert_eq!(
            serde_json::to_value(stat).unwrap(),
            serde_json::json!({
                "path":"new", "exists":true, "type":"file", "len":8, "readonly":false, "modifiedAt":123
            })
        );
        let missing = TypedTool::execute(
            &StatPathTool::new(),
            PathInput {
                path: "missing".into(),
            },
            files.clone(),
        )
        .await
        .unwrap();
        assert_eq!(
            serde_json::to_value(missing).unwrap(),
            serde_json::json!({"path":"missing", "exists":false})
        );
        fs::create_dir(files.path("directory")).unwrap();
        let directory = TypedTool::execute(
            &StatPathTool::new(),
            PathInput {
                path: "directory".into(),
            },
            files.clone(),
        )
        .await
        .unwrap();
        assert_eq!(directory.kind, Some("directory"));
        assert_eq!(directory.len, None);
        assert!(
            write
                .execute(
                    r#"{"path":"new","content":"no","mode":"truncate"}"#.into(),
                    files.clone()
                )
                .await
                .is_err()
        );
        assert!(
            write
                .execute(
                    r#"{"path":"new","content":"no","mode":"overwrite","extra":true}"#.into(),
                    files.clone()
                )
                .await
                .is_err()
        );
        assert_eq!(fs::read_to_string(files.path("new")).unwrap(), "appended");
    });
}

#[test]
fn directory_and_delete_mode_boundaries() {
    futures::executor::block_on(async {
        let root = tempfile::tempdir().unwrap();
        let files = Files(root.path().into());
        let text = TypedTool::execute(
            &CreateDirectoryTool::new(),
            PathInput { path: "a/b".into() },
            files.clone(),
        )
        .await
        .unwrap();
        assert_eq!(text, "Created directory a/b");
        assert!(files.path("a/b").is_dir());
        fs::write(files.path("a/b/file"), b"keep").unwrap();
        let delete = DeletePathTool::new();
        for (path, mode) in [
            ("a/b", DeleteMode::File),
            ("a/b/file", DeleteMode::EmptyDirectory),
            ("a/b/file", DeleteMode::RecursiveDirectory),
            ("a/b", DeleteMode::EmptyDirectory),
        ] {
            assert!(
                TypedTool::execute(
                    &delete,
                    DeletePathInput {
                        path: path.into(),
                        mode
                    },
                    files.clone()
                )
                .await
                .is_err()
            );
            assert_eq!(fs::read(files.path("a/b/file")).unwrap(), b"keep");
        }
        assert_eq!(
            TypedTool::execute(
                &delete,
                DeletePathInput {
                    path: "a/b/file".into(),
                    mode: DeleteMode::File
                },
                files.clone()
            )
            .await
            .unwrap(),
            "Deleted a/b/file"
        );
        TypedTool::execute(
            &delete,
            DeletePathInput {
                path: "a/b".into(),
                mode: DeleteMode::EmptyDirectory,
            },
            files.clone(),
        )
        .await
        .unwrap();
        assert!(!files.path("a/b").exists());
        fs::create_dir_all(files.path("a/c")).unwrap();
        fs::write(files.path("a/c/file"), b"owned").unwrap();
        TypedTool::execute(
            &delete,
            DeletePathInput {
                path: "a".into(),
                mode: DeleteMode::RecursiveDirectory,
            },
            files.clone(),
        )
        .await
        .unwrap();
        assert!(!files.path("a").exists());
    });
}

#[test]
fn copy_and_move_preserve_sources_and_enforce_collisions() {
    futures::executor::block_on(async {
        let root = tempfile::tempdir().unwrap();
        let files = Files(root.path().into());
        fs::write(files.path("source"), b"source").unwrap();
        fs::write(files.path("target"), b"target").unwrap();
        let copy = CopyPathTool::new();
        let moving = MovePathTool::new();
        assert!(matches!(
            TypedTool::execute(
                &copy,
                pair("source", "target", PathCollision::FailIfExists),
                files.clone()
            )
            .await,
            Err(MutationError::DestinationExists(_))
        ));
        assert!(matches!(
            TypedTool::execute(
                &moving,
                pair("source", "target", PathCollision::FailIfExists),
                files.clone()
            )
            .await,
            Err(MutationError::DestinationExists(_))
        ));
        assert_eq!(fs::read(files.path("source")).unwrap(), b"source");
        assert_eq!(fs::read(files.path("target")).unwrap(), b"target");
        assert_eq!(
            TypedTool::execute(
                &copy,
                pair("source", "target", PathCollision::Overwrite),
                files.clone()
            )
            .await
            .unwrap(),
            "Copied source to target"
        );
        assert_eq!(fs::read(files.path("target")).unwrap(), b"source");
        assert!(files.path("source").exists());
        assert_eq!(
            TypedTool::execute(
                &moving,
                pair("source", "nested/dest", PathCollision::FailIfExists),
                files.clone()
            )
            .await
            .unwrap(),
            "Moved source to nested/dest"
        );
        assert!(!files.path("source").exists());
        assert_eq!(fs::read(files.path("nested/dest")).unwrap(), b"source");
        fs::write(files.path("target"), b"replace").unwrap();
        TypedTool::execute(
            &moving,
            pair("target", "nested/dest", PathCollision::Overwrite),
            files.clone(),
        )
        .await
        .unwrap();
        assert_eq!(fs::read(files.path("nested/dest")).unwrap(), b"replace");
        fs::create_dir_all(files.path("dir/sub")).unwrap();
        TypedTool::execute(
            &moving,
            pair("dir", "renamed", PathCollision::FailIfExists),
            files.clone(),
        )
        .await
        .unwrap();
        assert!(files.path("renamed/sub").is_dir());
    });
}

#[test]
fn raw_patch_results_and_partial_failure_are_not_reexecuted() {
    futures::executor::block_on(async {
        let root = tempfile::tempdir().unwrap();
        let files = Files(root.path().into());
        let tool = ApplyPatchTool::<Files>::default();
        let patch =
            "*** Begin Patch\n*** Add File: a\n+first\n*** Add File: b\n+second\n*** End Patch";
        let output = Tool::execute(
            &tool,
            patch.into(),
            PatchContext {
                backend: files.clone(),
                cwd: ".".into(),
            },
        )
        .await
        .unwrap();
        assert_eq!(output.added, ["a", "b"]);
        assert_eq!(output.changed_files, ["a", "b"]);
        assert_eq!(output.stdout, "apply_patch completed");
        assert_eq!(
            output.summary,
            "Success. Updated the following files:\nA a\nA b\n"
        );
        let patch = "*** Begin Patch\n*** Update File: a\n@@\n-first\n+changed\n*** Update File: b\n@@\n-not present\n+no\n*** End Patch";
        let error = Tool::execute(
            &tool,
            patch.into(),
            PatchContext {
                backend: files.clone(),
                cwd: ".".into(),
            },
        )
        .await
        .unwrap_err();
        assert!(error.diagnostic.contains("Changes applied before failure:"));
        assert!(error.diagnostic.contains("M a"));
        assert!(
            error
                .diagnostic
                .contains("Recovery: read the target file again")
        );
        assert_eq!(fs::read_to_string(files.path("a")).unwrap(), "changed\n");
        assert_eq!(fs::read_to_string(files.path("b")).unwrap(), "second\n");
        assert!(
            Tool::execute(
                &tool,
                r#"{"input":"not a raw patch"}"#.into(),
                PatchContext {
                    backend: files.clone(),
                    cwd: ".".into()
                }
            )
            .await
            .is_err()
        );
    });
}
