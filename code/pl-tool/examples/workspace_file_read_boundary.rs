//! `read_file` 只读取显式请求路径的边界观察；不进入自动测试门禁。
//!
//! 运行：`cargo run -p pl-tool --example workspace_file_read_boundary`
//!
//! 该入口不需要网络、SSH、helper 或产品实例。临时工作区位于 `TMPDIR`；
//! 需要固定位置时用 `PURE_REMOTE_ACCEPTANCE_DIR=<dir>` 指定，脚本只在其中创建
//! 本次专属子目录，不写入源码树或用户 home。
//!
//! 观察内容：
//! 1. 缺失路径的 `read_file` 返回 backend 的原始缺失错误，不递归扫描 workspace，
//!    不附带候选列表。
//! 2. 权限/传输类失败同样原样保留，不被包装成“找不到”。
//! 3. 显式读取执行侧 `.anywork/sessions/<key>/{scratch,artifacts}` 仍然有效，
//!    截短 session key 的读取按普通缺失失败，不触发任何搜索。
//! 4. 显式 `list_files` 仍是唯一的目录遍历入口。
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

use anyhow::{Context, ensure};
use pl_protocol::{PureError, Result};
use pl_tool::workspace::SessionFiles;
use pl_tool::workspace_file::{
    LocalWorkspaceFileBackend, WorkspaceFileBackend, WorkspaceFileListRequest,
    WorkspaceFileListResult, WorkspaceFileReadBytesRequest, WorkspaceFileReadRequest,
    WorkspaceFileRemoveRequest, WorkspaceFileStat, WorkspaceFileStatRequest,
    WorkspaceFileWriteRequest, execute_workspace_file_tool,
};
use serde_json::json;

const TRANSPORT_FAILURE_PATH: &str = "synthetic-transport-failure.txt";

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let root = acceptance_root("workspace-file-read-boundary")?;
    let inner = LocalWorkspaceFileBackend::new(root.path().to_path_buf(), false).await?;
    let listing = ListingRecorder {
        inner,
        list_calls: Arc::new(AtomicUsize::new(0)),
    };
    let session = SessionFiles::new("workspace-file-read-boundary");

    write_fixture(root.path(), &session)?;

    missing_error_reproduces_backend_error(&listing).await?;
    transport_failure_is_not_rewritten(&listing).await?;
    explicit_session_paths_stay_readable(&listing, &session).await?;
    truncated_session_key_is_a_plain_miss(&listing, &session).await?;
    explicit_listing_remains_the_only_traversal(&listing, &session).await?;

    println!(
        "read_file boundary: missing/transport errors preserved, {} explicit listing call(s) observed, session reads intact",
        listing.list_calls()
    );
    Ok(())
}

/// 缺失路径：工具返回的错误必须与 backend 直接返回的错误逐字一致。
async fn missing_error_reproduces_backend_error(backend: &ListingRecorder) -> anyhow::Result<()> {
    let before = backend.list_calls();
    let stat_error = backend
        .stat(WorkspaceFileStatRequest {
            path: "missing.txt".into(),
            cwd: None,
        })
        .await
        .expect_err("missing path must fail stat");
    let tool_error =
        execute_workspace_file_tool(backend, "read_file", json!({ "path": "missing.txt" }))
            .await
            .expect_err("missing path must fail read_file");
    ensure!(
        tool_error.to_string() == stat_error.to_string(),
        "read_file rewrote the original stat failure: tool={tool_error} stat={stat_error}"
    );
    ensure!(
        !tool_error.to_string().contains("recovery")
            && !tool_error.to_string().contains("candidate"),
        "read_file attached an implicit search result: {tool_error}"
    );
    ensure!(
        backend.list_calls() == before,
        "missing read_file triggered workspace listing"
    );
    ensure!(
        stat_error.to_string().contains("missing.txt"),
        "original failure lost the requested path: {stat_error}"
    );
    println!(
        "missing: preserved=\"{stat_error}\" list_calls={}",
        backend.list_calls()
    );
    Ok(())
}

/// 权限/传输失败不是“不存在”，不得被改写成路径提示。
async fn transport_failure_is_not_rewritten(backend: &ListingRecorder) -> anyhow::Result<()> {
    let before = backend.list_calls();
    let error = execute_workspace_file_tool(
        backend,
        "read_file",
        json!({ "path": TRANSPORT_FAILURE_PATH }),
    )
    .await
    .expect_err("transport failure must fail read_file");
    ensure!(
        error.to_string().contains("synthetic transport failure"),
        "transport failure was replaced: {error}"
    );
    ensure!(
        !error.to_string().contains("not found"),
        "transport failure was reported as absence: {error}"
    );
    ensure!(
        backend.list_calls() == before,
        "transport failure triggered workspace listing"
    );
    println!("transport failure: preserved=\"{error}\" list_calls={before}");
    Ok(())
}

/// `.anywork` 不被屏蔽：显式 scratch/artifacts 路径仍按普通文件读取。
async fn explicit_session_paths_stay_readable(
    backend: &ListingRecorder,
    session: &SessionFiles,
) -> anyhow::Result<()> {
    for (path, expected) in [
        (session.scratch().join("note.txt"), "scratch note\n"),
        (session.artifacts().join("out.txt"), "artifact out\n"),
    ] {
        let path = posix(&path);
        let output = execute_workspace_file_tool(backend, "read_file", json!({ "path": path }))
            .await
            .with_context(|| format!("explicit read of {path} failed"))?
            .context("read_file returned no execution")?;
        ensure!(output.success, "explicit read of {path} reported failure");
        let value: serde_json::Value = serde_json::from_str(&output.output)?;
        ensure!(
            value["text"] == expected,
            "explicit read of {path} returned {:?}",
            value["text"]
        );
        println!("explicit read: {path} text_matches=true");
    }
    ensure!(
        backend.list_calls() == 0,
        "explicit session reads triggered workspace listing"
    );
    Ok(())
}

/// 截短的 session key 只是一次普通缺失，不能触发“同名文件”搜索。
async fn truncated_session_key_is_a_plain_miss(
    backend: &ListingRecorder,
    session: &SessionFiles,
) -> anyhow::Result<()> {
    let before = backend.list_calls();
    let key = session.thread_key();
    ensure!(key.len() >= 32, "unexpected session key: {key}");
    let truncated = posix(
        &PathBuf::from(".anywork")
            .join("sessions")
            .join(&key[..key.len() / 2])
            .join("scratch")
            .join("note.txt"),
    );
    let error = execute_workspace_file_tool(backend, "read_file", json!({ "path": truncated }))
        .await
        .expect_err("truncated session key must not resolve");
    ensure!(
        !error.to_string().contains("recovery"),
        "truncated session key produced a search recovery: {error}"
    );
    ensure!(
        backend.list_calls() == before,
        "truncated session key triggered workspace listing"
    );
    println!("truncated session key: {truncated} list_calls={before} error=\"{error}\"");
    Ok(())
}

/// 显式 list_files 仍可用，且是唯一会遍历 workspace 的入口。
async fn explicit_listing_remains_the_only_traversal(
    backend: &ListingRecorder,
    session: &SessionFiles,
) -> anyhow::Result<()> {
    let before = backend.list_calls();
    let output = execute_workspace_file_tool(
        backend,
        "list_files",
        json!({
            "path": posix(&session.scratch()),
            "glob": "*.txt",
            "limit": 50,
        }),
    )
    .await?
    .context("list_files returned no execution")?;
    ensure!(output.success, "list_files reported failure");
    let value: serde_json::Value = serde_json::from_str(&output.output)?;
    let files = value["files"]
        .as_array()
        .context("list_files output has no files array")?
        .iter()
        .filter_map(|file| file.as_str())
        .collect::<Vec<_>>();
    ensure!(
        files.iter().any(|file| file.ends_with("note.txt")),
        "explicit listing missed the session note: {files:?}"
    );
    ensure!(
        backend.list_calls() == before + 1,
        "explicit listing must be the only traversal entry"
    );
    println!(
        "explicit listing: {} file(s), list_calls={}",
        files.len(),
        backend.list_calls()
    );
    Ok(())
}

fn write_fixture(root: &Path, session: &SessionFiles) -> anyhow::Result<()> {
    for (path, content) in [
        (session.scratch().join("note.txt"), "scratch note\n"),
        (session.artifacts().join("out.txt"), "artifact out\n"),
        (PathBuf::from("src").join("lib.rs"), "pub fn ok() {}\n"),
    ] {
        let target = root.join(&path);
        if let Some(parent) = target.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(target, content)?;
    }
    Ok(())
}

fn posix(path: &Path) -> String {
    path.to_string_lossy().replace('\\', "/")
}

fn acceptance_root(prefix: &str) -> anyhow::Result<tempfile::TempDir> {
    // prefix 由 Builder 借用，先让它成为具名绑定，避免临时值在 tempdir 调用前被释放。
    let prefix = format!("{prefix}-");
    let mut builder = tempfile::Builder::new();
    let builder = builder.prefix(&prefix);
    match std::env::var_os("PURE_REMOTE_ACCEPTANCE_DIR") {
        Some(directory) => {
            let directory = PathBuf::from(directory);
            std::fs::create_dir_all(&directory).with_context(|| {
                format!(
                    "failed to create explicit acceptance directory {}",
                    directory.display()
                )
            })?;
            Ok(builder.tempdir_in(directory)?)
        }
        None => Ok(builder.tempdir()?),
    }
}

/// 记录 `list` 调用次数，用来证明 `read_file` 没有隐式遍历 workspace。
#[derive(Debug)]
struct ListingRecorder {
    inner: LocalWorkspaceFileBackend,
    list_calls: Arc<AtomicUsize>,
}

impl ListingRecorder {
    fn list_calls(&self) -> usize {
        self.list_calls.load(Ordering::SeqCst)
    }
}

impl WorkspaceFileBackend for ListingRecorder {
    async fn default_cwd(&self) -> Result<String> {
        self.inner.default_cwd().await
    }

    async fn stat_optional(
        &self,
        request: WorkspaceFileStatRequest,
    ) -> Result<Option<WorkspaceFileStat>> {
        if request.path == TRANSPORT_FAILURE_PATH {
            return Err(PureError::Protocol(
                "synthetic transport failure: channel closed".into(),
            ));
        }
        self.inner.stat_optional(request).await
    }

    async fn read_text(&self, request: WorkspaceFileReadRequest) -> Result<String> {
        self.inner.read_text(request).await
    }

    async fn read_bytes(&self, request: WorkspaceFileReadBytesRequest) -> Result<Vec<u8>> {
        self.inner.read_bytes(request).await
    }

    async fn write_text(&self, request: WorkspaceFileWriteRequest) -> Result<()> {
        self.inner.write_text(request).await
    }

    async fn remove_file(&self, request: WorkspaceFileRemoveRequest) -> Result<()> {
        self.inner.remove_file(request).await
    }

    async fn list(&self, request: WorkspaceFileListRequest) -> Result<WorkspaceFileListResult> {
        self.list_calls.fetch_add(1, Ordering::SeqCst);
        self.inner.list(request).await
    }

    async fn create_directory(&self, path: String, cwd: Option<String>) -> Result<()> {
        self.inner.create_directory(path, cwd).await
    }
}
