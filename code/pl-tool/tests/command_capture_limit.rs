//! Product capture uses actual executor processes; layout checks retain the existing ownership cases.
use anyhow::Context as _;
use pl_tool::command::{CommandBackend, ExecutorCommandBackend};
#[cfg(unix)]
use pl_tool::command::{
    CommandCaptureState, CommandCaptureStream, CommandProcessManager, CommandStartRequest,
    MAX_CAPTURE_BYTES,
};
use pl_tool::workspace_file::{
    WorkspaceFileBackend, WorkspaceFileReadBytesRequest, WorkspaceFileReadRequest,
    WorkspaceFileRemoveRequest, WorkspaceFileStat, WorkspaceFileStatRequest,
    WorkspaceFileWriteRequest,
};
use std::{path::PathBuf, sync::Arc, time::Duration};
#[cfg(unix)]
use tokio_util::sync::CancellationToken;
#[tokio::test]
async fn session_files_layout_and_directory_policy() -> anyhow::Result<()> {
    session_layout_and_directory_policy().await
}
#[tokio::test]
async fn concurrent_pool_ignore_create_is_idempotent_test() -> anyhow::Result<()> {
    concurrent_pool_ignore_create_is_idempotent().await
}
async fn session_layout_and_directory_policy() -> anyhow::Result<()> {
    use pl_tool::workspace::{
        AgentWorkspace, POOL_GITIGNORE, SessionFiles, ToolPathPolicy, WorkspaceMutability,
        prepare_session_files, prepare_worktree_pool,
    };
    use pl_tool::workspace_file::ExecutorWorkspaceFileBackend;
    use sha2::{Digest, Sha256};

    let root = tempfile::tempdir()?;
    let thread = "thread-alpha";
    let other = "thread-beta";
    let files = SessionFiles::new(thread);
    let neighbor = SessionFiles::new(other);
    anyhow::ensure!(files.thread_key() != neighbor.thread_key());
    anyhow::ensure!(!files.root().to_string_lossy().contains(thread));
    let expected_key = hex::encode(Sha256::digest(thread.as_bytes()));
    anyhow::ensure!(files.thread_key() == expected_key);
    let hashed_again = SessionFiles::new(format!("task-{}", expected_key));
    anyhow::ensure!(
        hashed_again.thread_key() != files.thread_key(),
        "hashing an already hashed identity must not be treated as the original Thread"
    );

    let call = "task-".to_string() + &hex::encode(Sha256::digest(b"call-one"));
    let same = files.command_output(&call);
    let derived = files.command_output("call-one");
    anyhow::ensure!(same == derived);
    let other_call = files.command_output("call-two");
    anyhow::ensure!(same != other_call);
    anyhow::ensure!(files.command_output("call-one") != neighbor.command_output("call-one"));

    let model = pl_tool::command::command_output_model_path(thread, &call);
    anyhow::ensure!(model == files.command_output(&call));
    anyhow::ensure!(!model.starts_with("target/pure"));

    let backend = ExecutorWorkspaceFileBackend::local(root.path().to_path_buf(), false).await?;
    let ignore_path = root.path().join(".anywork/sessions/.gitignore");
    std::fs::create_dir_all(ignore_path.parent().unwrap())?;
    std::fs::write(&ignore_path, b"keep-me\n")?;
    prepare_session_files(&backend, &files).await?;
    prepare_worktree_pool(&backend).await?;
    anyhow::ensure!(std::fs::read(&ignore_path)? == b"keep-me\n");
    let worktree_ignore = root.path().join(".anywork/worktrees/.gitignore");
    anyhow::ensure!(std::fs::read(&worktree_ignore)? == POOL_GITIGNORE.as_bytes());
    prepare_session_files(&backend, &files).await?;
    anyhow::ensure!(std::fs::read(&ignore_path)? == b"keep-me\n");
    anyhow::ensure!(root.path().join(files.scratch()).is_dir());
    anyhow::ensure!(root.path().join(files.artifacts()).is_dir());
    anyhow::ensure!(root.path().join(files.commands()).is_dir());

    let local = ExecutorCommandBackend::local(root.path())?;
    let target = local
        .output_target(thread, &call, &call, "printf one")
        .await?;
    anyhow::ensure!(target.model_file() == model);
    local
        .prepare_output(&target, "printf one", ".", 64 * 1024)
        .await?;
    anyhow::ensure!(
        target
            .capture_file()
            .parent()
            .context("capture parent")?
            .is_dir()
    );
    anyhow::ensure!(target.capture_file().starts_with(root.path()));

    let writable = vec![root.path().join("src")];
    std::fs::create_dir_all(root.path().join("src"))?;
    let policy = ToolPathPolicy::new(root.path().to_path_buf(), false, "file")?;
    let resolve = |path: PathBuf| {
        let original = path.to_string_lossy();
        policy.resolve_existing_or_parent_path(&path, &original)
    };
    let workspace =
        AgentWorkspace::directory(root.path(), Some(writable)).with_session_files(files.clone());
    workspace.ensure_path_writable(&resolve(root.path().join("src/lib.rs"))?)?;
    workspace.ensure_path_writable(&resolve(
        root.path().join(files.scratch()).join("probe.sh"),
    )?)?;
    workspace.ensure_path_writable(&resolve(
        root.path().join(files.artifacts()).join("out.bin"),
    )?)?;
    anyhow::ensure!(
        workspace
            .ensure_path_writable(&resolve(
                root.path().join(files.commands()).join("output.log")
            )?)
            .is_ok()
    );
    anyhow::ensure!(
        workspace
            .ensure_path_writable(&resolve(root.path().join(neighbor.scratch()).join("x"))?)
            .is_err()
    );
    anyhow::ensure!(
        workspace
            .ensure_path_writable(&resolve(root.path().join(".anywork/sessions/.gitignore"))?)
            .is_err()
    );
    anyhow::ensure!(
        workspace.writable_paths().map(|paths| paths.to_vec())
            == Some(vec![root.path().join("src")])
    );
    let readonly = AgentWorkspace::confined(root.path(), WorkspaceMutability::ReadOnly)
        .with_session_files(files.clone());
    anyhow::ensure!(
        readonly
            .ensure_path_writable(&resolve(root.path().join(files.scratch()).join("x"))?)
            .is_err()
    );

    #[cfg(unix)]
    {
        let linked = root.path().join("outside");
        std::fs::create_dir_all(&linked)?;
        let link = root.path().join(files.scratch()).join("escape");
        std::os::unix::fs::symlink(&linked, &link)?;
        anyhow::ensure!(
            policy
                .resolve_existing_or_parent_path(&link.join("secret"), "escape/secret")
                .is_err()
        );
    }

    // Backend-relative mutation inputs use POSIX separators on every host.
    let relative = workspace
        .ensure_relative_path_writable(None, &files.scratch().to_string_lossy().replace('\\', "/"));
    anyhow::ensure!(relative.is_ok());
    anyhow::ensure!(
        workspace
            .ensure_relative_path_writable(
                None,
                &files
                    .commands()
                    .join("x")
                    .to_string_lossy()
                    .replace('\\', "/"),
            )
            .is_ok()
    );

    let empty =
        AgentWorkspace::directory(root.path(), Some(Vec::new())).with_session_files(files.clone());
    empty.ensure_path_writable(&resolve(
        root.path().join(files.scratch()).join("probe.sh"),
    )?)?;
    empty.ensure_path_writable(&resolve(
        root.path().join(files.artifacts()).join("out.bin"),
    )?)?;
    anyhow::ensure!(
        empty
            .ensure_path_writable(&resolve(root.path().join("src/lib.rs"))?)
            .is_err()
    );
    anyhow::ensure!(
        empty
            .ensure_path_writable(&resolve(
                root.path().join(files.commands()).join("output.log")
            )?)
            .is_ok()
    );
    anyhow::ensure!(
        empty
            .ensure_path_writable(&resolve(root.path().join(neighbor.scratch()).join("x"))?)
            .is_err()
    );
    anyhow::ensure!(
        empty
            .ensure_path_writable(&resolve(root.path().join(".anywork"))?)
            .is_err()
    );
    anyhow::ensure!(
        empty
            .ensure_path_writable(&resolve(root.path().join(".anywork/sessions"))?)
            .is_err()
    );

    let sentinel = root.path().join("keep-target");
    std::fs::write(&sentinel, b"target-sentinel\n")?;
    let dir_root = root.path().join("dir-ignore-root");
    std::fs::create_dir_all(dir_root.join(".anywork/sessions/.gitignore"))?;
    let dir_backend = ExecutorWorkspaceFileBackend::local(dir_root.clone(), false).await?;
    anyhow::ensure!(
        pl_tool::workspace::prepare_session_files(&dir_backend, &files)
            .await
            .is_err()
    );
    anyhow::ensure!(dir_root.join(".anywork/sessions/.gitignore").is_dir());
    anyhow::ensure!(std::fs::read(&sentinel)? == b"target-sentinel\n");

    #[cfg(unix)]
    {
        let linked_root = root.path().join("linked-ignore");
        std::fs::create_dir_all(linked_root.join(".anywork/sessions"))?;
        std::os::unix::fs::symlink("/tmp", linked_root.join(".anywork/sessions/.gitignore"))?;
        let linked_backend =
            ExecutorWorkspaceFileBackend::local(linked_root.clone(), false).await?;
        anyhow::ensure!(
            pl_tool::workspace::prepare_session_files(&linked_backend, &files)
                .await
                .is_err()
        );
        anyhow::ensure!(
            linked_root
                .join(".anywork/sessions/.gitignore")
                .is_symlink()
        );
        anyhow::ensure!(std::fs::read(&sentinel)? == b"target-sentinel\n");
    }

    println!("OK  SessionFiles 布局、directory 许可、既有 ignore 与 unsafe link");
    Ok(())
}

async fn concurrent_pool_ignore_create_is_idempotent() -> anyhow::Result<()> {
    use pl_tool::workspace::{POOL_GITIGNORE, SessionFiles, prepare_session_files};
    use pl_tool::workspace_file::ExecutorWorkspaceFileBackend;
    use tokio::sync::Barrier;

    let root = tempfile::tempdir()?;
    let files = SessionFiles::new("race-thread");
    let inner = ExecutorWorkspaceFileBackend::local(root.path().to_path_buf(), false).await?;
    let barrier = Arc::new(Barrier::new(2));
    let left = RacingIgnoreBackend {
        inner: inner.clone(),
        barrier: barrier.clone(),
        ignore_path: ".anywork/sessions/.gitignore".into(),
    };
    let right = RacingIgnoreBackend {
        inner,
        barrier,
        ignore_path: ".anywork/sessions/.gitignore".into(),
    };
    let (left_result, right_result) = tokio::join!(
        prepare_session_files(&left, &files),
        prepare_session_files(&right, &files)
    );
    left_result?;
    right_result?;
    let ignore = root.path().join(".anywork/sessions/.gitignore");
    anyhow::ensure!(std::fs::read(&ignore)? == POOL_GITIGNORE.as_bytes());
    println!("OK  并发 Create ignore 后置条件收敛，既有规则字节保留");
    Ok(())
}

#[derive(Debug, Clone)]
struct RacingIgnoreBackend<B> {
    inner: B,
    barrier: Arc<tokio::sync::Barrier>,
    ignore_path: String,
}

impl<B> WorkspaceFileBackend for RacingIgnoreBackend<B>
where
    B: WorkspaceFileBackend + Clone,
{
    async fn default_cwd(&self) -> pl_protocol::Result<String> {
        self.inner.default_cwd().await
    }

    async fn stat_optional(
        &self,
        request: WorkspaceFileStatRequest,
    ) -> pl_protocol::Result<Option<WorkspaceFileStat>> {
        let racing = request.path == self.ignore_path;
        let result = self.inner.stat_optional(request).await?;
        if racing && result.is_none() {
            self.barrier.wait().await;
        }
        Ok(result)
    }

    async fn read_text(&self, request: WorkspaceFileReadRequest) -> pl_protocol::Result<String> {
        self.inner.read_text(request).await
    }

    async fn read_bytes(
        &self,
        request: WorkspaceFileReadBytesRequest,
    ) -> pl_protocol::Result<Vec<u8>> {
        self.inner.read_bytes(request).await
    }

    async fn write_text(&self, request: WorkspaceFileWriteRequest) -> pl_protocol::Result<()> {
        self.inner.write_text(request).await
    }

    async fn remove_file(&self, request: WorkspaceFileRemoveRequest) -> pl_protocol::Result<()> {
        self.inner.remove_file(request).await
    }

    async fn create_directory(&self, path: String, cwd: Option<String>) -> pl_protocol::Result<()> {
        self.inner.create_directory(path, cwd).await
    }
}

#[cfg(unix)]
fn request(command: String, key: &str) -> CommandStartRequest {
    CommandStartRequest {
        command,
        cwd: None,
        allow_workspace_escape: false,
        timeout: Duration::from_secs(30),
        yield_time: Duration::ZERO,
        max_output_chars: 4096,
        session_id: "capture-product".into(),
        tool_id: key.into(),
        call_id: key.into(),
        cancellation_token: None,
        output_observer: None,
    }
}
#[tokio::test]
async fn invalid_input_is_rejected_with_its_typed_diagnostic() -> anyhow::Result<()> {
    for (raw, code) in [
        ("{", "exec.invalid_json"),
        (r#"{"command":"   "}"#, "exec.empty_command"),
        (
            r#"{"command":"touch forbidden","timeoutSeconds":0}"#,
            "exec.argument_out_of_range",
        ),
        (
            r#"{"command":"echo x","working_directory":"/outside"}"#,
            "exec.invalid_arguments",
        ),
    ] {
        let error = pl_tool::exec::parse_and_validate_exec_input(raw).expect_err("invalid input");
        anyhow::ensure!(error.code == code);
        anyhow::ensure!(
            error
                .into_tool_error()
                .source
                .downcast_ref::<pl_tool::exec::ExecInputError>()
                .is_some()
        );
    }
    Ok(())
}
#[cfg(unix)]
#[tokio::test]
async fn default_raw_capture_budget_has_exact_eof_edges_and_keeps_binary_files()
-> anyhow::Result<()> {
    for delta in [-1i64, 0, 1] {
        let root = tempfile::tempdir()?;
        let backend = Arc::new(ExecutorCommandBackend::local(root.path())?);
        let manager = CommandProcessManager::new(backend.clone());
        let len = (MAX_CAPTURE_BYTES as i64 + delta) as u64;
        // Keep both byte streams active. A shell pipeline would create an unrelated process owner.
        let script = format!(
            r#"python3 -c 'import os; os.write(2,b"\xff\x00"); left={}; block=b"\x00x"*4096
while left:
 n=min(left,len(block)); os.write(1,block[:n]); left-=n'"#,
            len - 2
        );
        let snapshot = manager
            .run_task("task-capture-budget", request(script, "budget"))
            .await?;
        let capture = snapshot.capture.as_ref().context("target capture result")?;
        if delta <= 0 {
            anyhow::ensure!(capture.complete() && snapshot.exit_code == Some(0));
            anyhow::ensure!(capture.confirmed_total() == Some(len));
        } else {
            anyhow::ensure!(snapshot.output_limit_exceeded().is_some());
            anyhow::ensure!(
                capture.stdout.state == CommandCaptureState::LimitExceeded
                    || capture.stderr.state == CommandCaptureState::LimitExceeded
            );
            anyhow::ensure!(capture.confirmed_total() == Some(MAX_CAPTURE_BYTES));
        }
        let actual = std::fs::metadata(&snapshot.capture_file)?.len()
            + std::fs::metadata(&snapshot.stderr_capture_file)?.len();
        anyhow::ensure!(actual == len.min(MAX_CAPTURE_BYTES));
        anyhow::ensure!(std::fs::read(&snapshot.stderr_capture_file)? == b"\xff\x00");
        anyhow::ensure!(snapshot.stdout.content.len() + snapshot.stderr.content.len() <= 4096);
        backend.executor().close().await?;
    }
    Ok(())
}
#[cfg(unix)]
#[tokio::test]
async fn stdin_eof_delivers_utf8_and_yield_keeps_the_same_process() -> anyhow::Result<()> {
    let root = tempfile::tempdir()?;
    let backend = Arc::new(ExecutorCommandBackend::local(root.path())?);
    let manager = CommandProcessManager::new(backend.clone());
    let snapshot = manager
        .start(request("cat; printf stderr >&2".into(), "input"))
        .await?;
    let id = snapshot
        .process_id
        .context("still running without stdin EOF")?;
    let snapshot = manager
        .write_stdin(pl_tool::command::CommandWriteRequest {
            process_id: id,
            chars: "中文输入\n".into(),
            close_stdin: true,
            yield_time: Duration::from_secs(2),
            max_output_chars: 4096,
            cancellation: CancellationToken::new(),
        })
        .await?;
    anyhow::ensure!(
        snapshot
            .input_receipt
            .as_ref()
            .context("receipt")?
            .accepted_bytes
            == 13
    );
    anyhow::ensure!(snapshot.stdout.content == "中文输入\n" && snapshot.stderr.content == "stderr");
    anyhow::ensure!(
        snapshot
            .capture
            .as_ref()
            .is_some_and(|capture| capture.complete())
    );
    let stdout = snapshot.confirmed_bytes(CommandCaptureStream::Stdout);
    anyhow::ensure!(stdout == Some(13));
    backend.executor().close().await?;
    Ok(())
}
