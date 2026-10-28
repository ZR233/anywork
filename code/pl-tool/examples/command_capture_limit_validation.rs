//! 命令捕获上限与模型可见字节上限的手工验证入口。
//!
//! 为什么不是 `cargo test`：本仓库约定（`AGENTS.md`「测试、检查与交付」、`design/24-testing.md`
//! §24.1）只有 `pl-model/tests` 与 `pl-core/tests` 保留常规自动化行为用例、`pl-studio-runtime`
//! 保留历史保存专项用例，**其它 crate 不新增测试**；而这两处都不能反向依赖 pl-tool。因此这里沿用
//! 本 crate 已有的人工入口形式（见 `ssh_remote_validation.rs`）：用公开 API 驱动真实实现，断言失败
//! 即返回非零退出码，由主代理/发布者在目标机上执行。
//!
//! 覆盖严格输入与 no-start 诊断、共享原始双流预算、真实存储故障和修复、64 KiB 正文
//! 额度及独立协议包装、准备阶段 deadline/cancellation、stdin 背压取消及 UTF-8 边界。可选真实进程入口
//! 还验证有限输入与 EOF、无末尾换行和无效编码的原始字节。
//!
//! 运行（确定性部分不需要任何外部依赖）：
//! ```text
//! cargo run -p pl-tool --example command_capture_limit_validation
//! ```
//! 需要真实进程与真实容器的部分（Linux 需要 PATH 上有 pl-remote-helper，先执行
//! `cargo install --path code/pl-remote-helper --locked`）：
//! ```text
//! PURE_PL_COMMAND_REAL_BACKEND=1 cargo run -p pl-tool --example command_capture_limit_validation
//! ```

use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::task::{Context, Poll};
use std::time::Duration;

use anyhow::Context as _;
use pl_core::context::{OpaquePayload, ResourceReference};
use pl_core::thread::cold::{OutputStorageFault, StorageFaultKind};
use pl_core::tool::opaque::{CallContext, ToolError};
use pl_tool::command::{
    CommandBackend, CommandCaptureFailure, CommandCaptureStream, CommandExit, CommandIo,
    CommandOutputSizes, CommandOutputSnapshot, CommandOutputTarget, CommandProcessFinalResult,
    CommandProcessManager, CommandSpawnRequest, CommandStartRequest, ManagedCommand,
    command_output_model_path,
};
use pl_tool::exec::{CommandAccess, CommandOutputArchive, ExecFailure, ExecInput, ThreadExecTool};
use pl_tool::workspace_file::{
    WorkspaceFileBackend, WorkspaceFileReadBytesRequest, WorkspaceFileReadRequest,
    WorkspaceFileRemoveRequest, WorkspaceFileStat, WorkspaceFileStatRequest,
    WorkspaceFileWriteRequest,
};
use tokio_util::sync::CancellationToken;

/// 假后端声明的单命令落盘上限：小到能在毫秒级触顶，又足够验证"成本而不是原始字节"。
const FAKE_CAPTURE_LIMIT_BYTES: u64 = 64 * 1024;
/// 假后端声明的模型可见字节上限。
///
/// 取一个能被多字节正文明显区分的值：同一个上限按字符计会放进 256 个汉字（768 字节），
/// 按字节计只放得下约 1/3，因此"按字节裁到上限内"这条断言能直接证伪按字符计数的实现。
const FAKE_MODEL_OUTPUT_BYTES: usize = 256;
/// 一次假运行的原始输出总量：远大于上限，但有限，因此"上限没生效"会停在这里而不是无限跑。
const FAKE_TOTAL_BYTES: u64 = 4 * 1024 * 1024;
/// 多字节正文：一个汉字 3 字节，因此按字符计和按字节计的结果明显不同。
const MULTIBYTE_PATTERN: &str = "汉字捕获上限";

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    println!("== 命令捕获上限验证（手工入口）==");

    for (head, tail, gap) in [
        (
            "汉字边界".as_bytes()[..4].to_vec(),
            "汉字边界".as_bytes()[4..].to_vec(),
            0,
        ),
        (b"head".repeat(1000), b"tail".repeat(1000), 1_000_000),
        (vec![0xff, 0xfe, b'a'], vec![0xff, b'z'], 100),
    ] {
        let raw_length = head.len() + tail.len() + gap;
        let excerpt = pl_output::OutputExcerpt::from_parts(head, tail, gap);
        for cap in 0..=128 {
            let visible = excerpt.clone().project(cap);
            anyhow::ensure!(visible.content.len() <= cap && visible.original_length == raw_length);
            anyhow::ensure!(visible.content.matches("[output omitted]").count() <= 1);
        }
    }
    println!("OK  0..128 字节预算、原始长度、跨片段 UTF-8 与唯一省略行");
    exec_input_contract().await?;
    session_layout_and_directory_policy().await?;
    concurrent_pool_ignore_create_is_idempotent().await?;
    raw_capture_budget_terminates().await?;
    write_failure_keeps_its_retry_obligation().await?;
    combined_requested_output_budget().await?;
    model_output_cap_counts_bytes_not_chars().await?;
    model_body_budget_preserves_metadata().await?;
    preparation_deadline_and_cancellation().await?;
    backpressured_stdin_cancellation().await?;
    let (mut producer, _root) = scripted_backend(
        Arc::new(CaptureFacts::default()),
        ScriptedBehavior::finite_multibyte(),
        None,
    )?;
    // 故意违反 Producer 的终态回执契约：不能拿本地 header 冒充完整远端捕获。
    producer.capture_ownership = pl_tool::command::CommandCaptureOwnership::Producer;
    let archive = Arc::new(FixedArchive::default());
    let error = run_exec_tool(producer, archive.clone())
        .await
        .expect_err("missing producer receipt must fail");
    anyhow::ensure!(error.source.downcast_ref::<ExecFailure>().is_some());
    anyhow::ensure!(archive.calls.load(Ordering::SeqCst) == 0);
    println!("OK  Producer 缺少回执时不归档未确认捕获");

    if std::env::var("PURE_PL_COMMAND_REAL_BACKEND").as_deref() == Ok("1") {
        real_backend_limit_terminates_process().await?;
        real_stdin_eof_and_raw_utf8().await?;
        #[cfg(target_os = "linux")]
        worker_bootstrap_cancellation().await?;
    } else {
        println!(
            "-- 跳过真实进程验证（PURE_PL_COMMAND_REAL_BACKEND=1 且 PATH 上有 pl-remote-helper 时执行）"
        );
    }

    println!("== 全部断言通过 ==");
    Ok(())
}

async fn exec_input_contract() -> anyhow::Result<()> {
    use pl_tool::exec::parse_and_validate_exec_input;
    for (raw, code, field) in [
        ("{", "exec.invalid_json", None),
        (r#"{"cwd":"/outside"}"#, "exec.invalid_arguments", None),
        (
            r#"{"command":"echo x","working_directory":"/outside"}"#,
            "exec.invalid_arguments",
            None,
        ),
        (
            r#"{"command":"echo x","timeoutSeconds":"60"}"#,
            "exec.invalid_arguments",
            Some("timeoutSeconds"),
        ),
        (
            r#"{"command":"   "}"#,
            "exec.empty_command",
            Some("command"),
        ),
        (
            r#"{"command":"echo x","timeoutSeconds":0}"#,
            "exec.argument_out_of_range",
            Some("timeoutSeconds"),
        ),
        (
            r#"{"command":"echo x","maxOutputChars":0}"#,
            "exec.argument_out_of_range",
            Some("maxOutputChars"),
        ),
        (r#"{"command":"echo x"} {}"#, "exec.invalid_json", None),
    ] {
        let error = parse_and_validate_exec_input(raw).expect_err("invalid input");
        anyhow::ensure!(error.code == code);
        if let Some(field) = field {
            anyhow::ensure!(error.field.as_deref() == Some(field));
        }
        let error = error.into_tool_error();
        anyhow::ensure!(
            error
                .source
                .downcast_ref::<pl_tool::exec::ExecInputError>()
                .is_some()
        );
        let (backend, _root) = scripted_backend(
            Arc::new(CaptureFacts::default()),
            ScriptedBehavior::finite_multibyte(),
            None,
        )?;
        let archive = Arc::new(FixedArchive::default());
        let tool = ThreadExecTool::new(
            Arc::new(backend),
            archive.clone(),
            CommandAccess::WorkspaceOnly,
        );
        let thread = pl_core::thread::ThreadHandle::start(
            "exec-input-contract".into(),
            pl_core::model::DynModelSession::new(ScriptedToolCalls::single_exec(
                raw.into(),
                "exec-input-call".into(),
            )),
        )?;
        thread
            .register_tools(
                tool.registrations(OpaquePayload::text("exec"), OpaquePayload::text("stdin"))?,
            )
            .await?;
        thread
            .run_turn(pl_core::thread::TurnInput {
                turn_id: "validation-turn".into(),
                attempt_prefix: "validation-step".into(),
                content: vec![],
                max_model_steps: pl_core::thread::ModelStepLimit::Limited(
                    std::num::NonZeroU32::new(2).unwrap(),
                ),
                cancellation: CancellationToken::new(),
            })
            .await?;
        let effects = thread.effects().await?;
        let delivery = effects
            .iter()
            .flat_map(|effect| effect.deliveries.iter())
            .find(|delivery| delivery.tool_id == "exec")
            .context("exec result was not committed")?;
        let receipt: serde_json::Value = serde_json::from_str(delivery.output.payload().content())?;
        anyhow::ensure!(
            receipt["processStarted"] == false && receipt["diagnostic"]["code"] == code
        );
        anyhow::ensure!(archive.calls.load(Ordering::SeqCst) == 0);
        thread.close().await?;
    }
    let command = "  printf 'original spacing'  ";
    let raw = serde_json::json!({"command": command, "cwd":"."}).to_string();
    let input = parse_and_validate_exec_input(&raw)?;
    anyhow::ensure!(input.into_input().command == command);
    for (raw, valid) in [
        (r#"{"taskId":"task:real","chars":""}"#, false),
        (
            r#"{"taskId":"task:real","chars":"","closeStdin":true}"#,
            true,
        ),
        (
            r#"{"taskId":"task:real","chars":"x","maxOutputChars":0}"#,
            false,
        ),
    ] {
        anyhow::ensure!(pl_tool::exec::parse_and_validate_stdin_input(raw).is_ok() == valid);
    }
    println!("OK  strict input, original source/field, no-start diagnostics, EOF validation");
    let (backend, _root) = scripted_backend(
        Arc::new(CaptureFacts::default()),
        ScriptedBehavior::finite_multibyte(),
        None,
    )?;
    let archive = Arc::new(FixedArchive::default());
    let tool = ThreadExecTool::new(
        Arc::new(backend),
        archive.clone(),
        CommandAccess::WorkspaceOnly,
    );
    let thread = pl_core::thread::ThreadHandle::start(
        "exec-large-error-metadata".into(),
        pl_core::model::DynModelSession::new(ScriptedToolCalls::single_exec(
            format!(
                r#"{{"command":"must-not-run","timeoutSeconds":{}}}"#,
                u64::MAX
            ),
            "m".repeat(70000),
        )),
    )?;
    thread
        .register_tools(
            tool.registrations(OpaquePayload::text("exec"), OpaquePayload::text("stdin"))?,
        )
        .await?;
    thread
        .run_turn(pl_core::thread::TurnInput {
            turn_id: "large-error-turn".into(),
            attempt_prefix: "large-error".into(),
            content: vec![],
            max_model_steps: pl_core::thread::ModelStepLimit::Limited(
                std::num::NonZeroU32::new(2).unwrap(),
            ),
            cancellation: CancellationToken::new(),
        })
        .await?;
    let effects = thread.effects().await?;
    let delivery = effects
        .iter()
        .flat_map(|effect| effect.deliveries.iter())
        .find(|delivery| delivery.tool_id == "exec")
        .context("missing range error")?;
    let record: serde_json::Value = serde_json::from_str(delivery.output.payload().content())?;
    let pl_core::context::ContextContent::Text { text } = &delivery.output.context()[0] else {
        anyhow::bail!("missing model error receipt");
    };
    anyhow::ensure!(serde_json::from_str::<serde_json::Value>(text)? == record);
    anyhow::ensure!(record["taskId"] == format!("task:{}", "m".repeat(70000)));
    anyhow::ensure!(record["processStarted"] == false);
    anyhow::ensure!(record["diagnostic"]["code"] == "exec.argument_out_of_range");
    anyhow::ensure!(archive.calls.load(Ordering::SeqCst) == 0);
    thread.close().await?;
    println!(
        "OK  metadata-only error keeps full identity and diagnostic in payload and model receipt"
    );
    Ok(())
}

async fn session_layout_and_directory_policy() -> anyhow::Result<()> {
    use pl_tool::workspace::{
        AgentWorkspace, POOL_GITIGNORE, SessionFiles, WorkspaceMutability, prepare_session_files,
        prepare_worktree_pool,
    };
    use pl_tool::workspace_file::LocalWorkspaceFileBackend;
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

    let backend = LocalWorkspaceFileBackend::new(root.path().to_path_buf(), false).await?;
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

    let local = pl_tool::command::LocalCommandBackend::new(root.path().to_path_buf());
    let target = local
        .output_target(thread, &call, &call, "printf one")
        .await?;
    anyhow::ensure!(target.model_file() == model);
    local
        .prepare_output(&target, "printf one", ".", 64 * 1024)
        .await?;
    anyhow::ensure!(target.capture_file().is_file());
    anyhow::ensure!(target.capture_file().starts_with(root.path()));

    let writable = vec![root.path().join("src")];
    std::fs::create_dir_all(root.path().join("src"))?;
    let workspace =
        AgentWorkspace::directory(root.path(), Some(writable)).with_session_files(files.clone());
    workspace.ensure_path_writable(&root.path().join("src/lib.rs"))?;
    workspace.ensure_path_writable(&root.path().join(files.scratch()).join("probe.sh"))?;
    workspace.ensure_path_writable(&root.path().join(files.artifacts()).join("out.bin"))?;
    anyhow::ensure!(
        workspace
            .ensure_path_writable(&root.path().join(files.commands()).join("output.log"))
            .is_err()
    );
    anyhow::ensure!(
        workspace
            .ensure_path_writable(&root.path().join(neighbor.scratch()).join("x"))
            .is_err()
    );
    anyhow::ensure!(
        workspace
            .ensure_path_writable(&root.path().join(".anywork/sessions/.gitignore"))
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
            .ensure_path_writable(&root.path().join(files.scratch()).join("x"))
            .is_err()
    );

    #[cfg(unix)]
    {
        let linked = root.path().join("outside");
        std::fs::create_dir_all(&linked)?;
        let link = root.path().join(files.scratch()).join("escape");
        std::os::unix::fs::symlink(&linked, &link)?;
        let policy =
            pl_tool::workspace::ToolPathPolicy::new(root.path().to_path_buf(), false, "file")?;
        anyhow::ensure!(
            policy
                .resolve_existing_or_parent_path(&link.join("secret"), "escape/secret")
                .is_err()
        );
    }

    let relative =
        workspace.ensure_relative_path_writable(None, &files.scratch().to_string_lossy());
    anyhow::ensure!(relative.is_ok());
    anyhow::ensure!(
        workspace
            .ensure_relative_path_writable(None, &files.commands().join("x").to_string_lossy())
            .is_err()
    );

    let empty =
        AgentWorkspace::directory(root.path(), Some(Vec::new())).with_session_files(files.clone());
    empty.ensure_path_writable(&root.path().join(files.scratch()).join("probe.sh"))?;
    empty.ensure_path_writable(&root.path().join(files.artifacts()).join("out.bin"))?;
    anyhow::ensure!(
        empty
            .ensure_path_writable(&root.path().join("src/lib.rs"))
            .is_err()
    );
    anyhow::ensure!(
        empty
            .ensure_path_writable(&root.path().join(files.commands()).join("output.log"))
            .is_err()
    );
    anyhow::ensure!(
        empty
            .ensure_path_writable(&root.path().join(neighbor.scratch()).join("x"))
            .is_err()
    );
    anyhow::ensure!(
        empty
            .ensure_path_writable(&root.path().join(".anywork"))
            .is_err()
    );
    anyhow::ensure!(
        empty
            .ensure_path_writable(&root.path().join(".anywork/sessions"))
            .is_err()
    );

    let sentinel = root.path().join("keep-target");
    std::fs::write(&sentinel, b"target-sentinel\n")?;
    let dir_root = root.path().join("dir-ignore-root");
    std::fs::create_dir_all(dir_root.join(".anywork/sessions/.gitignore"))?;
    let dir_backend = LocalWorkspaceFileBackend::new(dir_root.clone(), false).await?;
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
        let linked_backend = LocalWorkspaceFileBackend::new(linked_root.clone(), false).await?;
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
    use pl_tool::workspace_file::LocalWorkspaceFileBackend;
    use tokio::sync::Barrier;

    let root = tempfile::tempdir()?;
    let files = SessionFiles::new("race-thread");
    let inner = LocalWorkspaceFileBackend::new(root.path().to_path_buf(), false).await?;
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

/// 用例 1~3：成本计费、超限取消并真实落幕、typed 容量终止。
async fn raw_capture_budget_terminates() -> anyhow::Result<()> {
    let facts = Arc::new(CaptureFacts::default());
    let (backend, root) = scripted_backend(
        facts.clone(),
        ScriptedBehavior::endless_until_cancelled(),
        Some(FAKE_MODEL_OUTPUT_BYTES as u64),
    )?;

    // 先在 process manager 层看完整状态：这是"成本计费 + 真终态 + 无欠修复"的事实来源。
    let manager = CommandProcessManager::new(Arc::new(backend));
    let snapshot = tokio::time::timeout(
        Duration::from_secs(60),
        manager.run_task("task-capture-limit", start_request()),
    )
    .await
    .context("命令没有在 60 秒内落幕：上限没有真正终止后台命令")??;

    let limit = snapshot
        .output_limit_exceeded()
        .context("终态必须是 typed 的单命令落盘上限，而不是别的失败")?;
    anyhow::ensure!(
        limit.limit_bytes == FAKE_CAPTURE_LIMIT_BYTES,
        "上限快照必须自证本次生效的额度：{limit:?}"
    );
    anyhow::ensure!(
        matches!(
            snapshot.output_failure,
            Some(CommandCaptureFailure::OutputLimitExceeded { .. })
        ),
        "容量终止必须保持 OutputLimitExceeded 类别：{:?}",
        snapshot.output_failure
    );
    anyhow::ensure!(
        snapshot.capture_repair().is_none(),
        "预期容量终止不欠修复：不得留下可靠保存义务"
    );
    anyhow::ensure!(
        limit.refused_bytes > 0,
        "触顶时必须有被拒绝接纳的输出，否则上限没有生效"
    );

    // 每个原始 chunk 只写入所属流一次，双流共用一个预算。
    let appended_raw = facts.appended_raw.load(Ordering::SeqCst);
    let appends = facts.appends.load(Ordering::SeqCst);
    anyhow::ensure!(appends > 0, "上限之前必须先有真正落盘的已接纳 chunk");
    anyhow::ensure!(
        snapshot.capture_usage.expect("manager usage").charged_bytes
            == facts.prepared_bytes.load(Ordering::SeqCst) + appended_raw,
        "落盘预算必须等于接纳的双流原始字节：charged={} raw={} appends={}",
        snapshot.capture_usage.expect("manager usage").charged_bytes,
        appended_raw,
        appends
    );
    anyhow::ensure!(
        snapshot.capture_usage.expect("manager usage").charged_bytes <= FAKE_CAPTURE_LIMIT_BYTES,
        "已接纳成本不得超过声明上限"
    );
    anyhow::ensure!(
        appended_raw == FAKE_CAPTURE_LIMIT_BYTES,
        "原始双流合计精确触顶：raw={appended_raw}"
    );
    anyhow::ensure!(
        facts.repairs.load(Ordering::SeqCst) == 0,
        "预期容量终止不得走修复路径"
    );
    anyhow::ensure!(
        facts.process_cancelled.load(Ordering::SeqCst),
        "后台命令是被取消落幕的，而不是自己跑完的"
    );
    anyhow::ensure!(
        matches!(
            snapshot.state.final_result(),
            Some(CommandProcessFinalResult::Failed { .. })
        ) && !matches!(
            snapshot.state.final_result(),
            Some(CommandProcessFinalResult::Succeeded { .. })
        ),
        "容量终止必须是失败终态，不能报成功：{:?}",
        snapshot.state.final_result()
    );
    let disk_bytes = capture_files_len(root.path())?;
    anyhow::ensure!(
        disk_bytes <= FAKE_CAPTURE_LIMIT_BYTES,
        "声明上限必须覆盖双流合计磁盘占用：disk={disk_bytes}"
    );
    println!(
        "OK  成本计费：charged={} raw={} appends={} refused={} disk={disk_bytes}",
        snapshot.capture_usage.expect("manager usage").charged_bytes,
        appended_raw,
        appends,
        limit.refused_bytes
    );

    // 再在真实 exec 工具边界确认 typed 结果与"不是存储故障"。
    let facts = Arc::new(CaptureFacts::default());
    let (backend, _root) = scripted_backend(
        facts.clone(),
        ScriptedBehavior::endless_until_cancelled(),
        Some(FAKE_MODEL_OUTPUT_BYTES as u64),
    )?;
    let error = run_exec_tool(backend, Arc::new(FixedArchive::default()))
        .await
        .expect_err("超限必须失败");
    anyhow::ensure!(
        error.source.downcast_ref::<OutputStorageFault>().is_none(),
        "预期容量终止不得伪装成可靠存储故障：{error}"
    );
    match error.source.downcast_ref::<ExecFailure>() {
        Some(ExecFailure::OutputLimitExceeded {
            limit_bytes,
            charged_bytes,
            refused_bytes,
        }) => {
            anyhow::ensure!(
                *limit_bytes == FAKE_CAPTURE_LIMIT_BYTES && *refused_bytes > 0,
                "typed 容量终止必须带真实的上限与被拒字节：{error}"
            );
            println!(
                "OK  exec 工具 typed 结果：OutputLimitExceeded limit={limit_bytes} charged={charged_bytes} refused={refused_bytes}"
            );
        }
        other => anyhow::bail!("exec 工具必须返回 typed OutputLimitExceeded，实际 {other:?}"),
    }
    Ok(())
}

/// 用例 4（对照）：真正的存储写失败仍然欠一次修复，与容量终止互不混淆。
async fn write_failure_keeps_its_retry_obligation() -> anyhow::Result<()> {
    let facts = Arc::new(CaptureFacts::default());
    let (backend, _root) = scripted_backend(
        facts.clone(),
        ScriptedBehavior::failing_first_append(),
        None,
    )?;
    let error = run_exec_tool(backend, Arc::new(FixedArchive::default()))
        .await
        .expect_err("写失败必须失败");
    let fault = error
        .source
        .downcast_ref::<OutputStorageFault>()
        .context("真实落盘失败必须仍走可靠存储故障边界")?;
    anyhow::ensure!(
        fault.kind == StorageFaultKind::WriteFailed,
        "写失败必须保持 WriteFailed 类别"
    );
    anyhow::ensure!(
        fault.obligation.is_some(),
        "写失败必须带可重试的 OutputRetryObligation"
    );
    anyhow::ensure!(
        error.source.downcast_ref::<ExecFailure>().is_none(),
        "写失败不得伪装成 typed 容量终止"
    );
    println!("OK  存储写失败仍是带义务的 OutputStorageFault（kind=WriteFailed, obligation=Some）");
    Ok(())
}

async fn model_body_budget_preserves_metadata() -> anyhow::Result<()> {
    for output_limit in [false, true] {
        for budget in [1, 127, 65536, usize::MAX] {
            let behavior = ScriptedBehavior {
                total_bytes: if output_limit { 128 * 1024 } else { 24000 },
                pattern: if output_limit { b"A" } else { b"\0\n\\\"\x01" },
                dual_stream: true,
                ..ScriptedBehavior::finite_multibyte()
            };
            let (backend, _root) =
                scripted_backend(Arc::new(CaptureFacts::default()), behavior, None)?;
            let tool = ThreadExecTool::new(
                Arc::new(backend),
                Arc::new(FixedArchive::default()),
                CommandAccess::WorkspaceOnly,
            );
            let thread = pl_core::thread::ThreadHandle::start(
                "exec-serialized-budget".into(),
                pl_core::model::DynModelSession::new(ScriptedToolCalls::single_exec(
                    serde_json::json!({"command":"scripted-output", "maxOutputChars":budget})
                        .to_string(),
                    "serialized-budget-call".into(),
                )),
            )?;
            thread
                .register_tools(
                    tool.registrations(OpaquePayload::text("exec"), OpaquePayload::text("stdin"))?,
                )
                .await?;
            thread
                .run_turn(pl_core::thread::TurnInput {
                    turn_id: "serialized-budget-turn".into(),
                    attempt_prefix: "serialized-budget".into(),
                    content: vec![],
                    max_model_steps: pl_core::thread::ModelStepLimit::Limited(
                        std::num::NonZeroU32::new(2).unwrap(),
                    ),
                    cancellation: CancellationToken::new(),
                })
                .await?;
            let delivery = tokio::time::timeout(
                Duration::from_secs(60),
                thread.wait_task("task:serialized-budget-call", CancellationToken::new()),
            )
            .await??;
            thread.close().await?;
            let output = &delivery.output;
            anyhow::ensure!(
                output.payload().format() == "pl.tool.exec" && output.payload().version() == 2
            );
            let pl_core::context::ContextContent::Text { text } = &output.context()[0] else {
                anyhow::bail!("missing model JSON");
            };
            let view: serde_json::Value = serde_json::from_str(text)?;
            let record: serde_json::Value = serde_json::from_str(output.payload().content())?;
            anyhow::ensure!(
                view == record,
                "protocol wrapping must not trim body or metadata a second time"
            );
            let visible = view["stdout"]["content"].as_str().unwrap().len()
                + view["stderr"]["content"].as_str().unwrap().len();
            anyhow::ensure!(visible <= budget.min(65536));
            anyhow::ensure!(view["stdoutFile"].is_string() && view["stderrFile"].is_string());
            if output_limit {
                anyhow::ensure!(
                    view["captureStatus"] == "partial"
                        && view["diagnostic"]["code"] == "exec.output_limit"
                );
                anyhow::ensure!(matches!(
                    delivery.outcome,
                    pl_core::thread::ToolOutcome::Failed(_)
                ));
            } else {
                anyhow::ensure!(view["captureStatus"] == "complete");
            }
        }
    }
    println!(
        "OK  committed success/failure body obeys 1/127/65536-byte budgets; escaping and metadata preserve the complete record"
    );
    Ok(())
}

async fn preparation_deadline_and_cancellation() -> anyhow::Result<()> {
    for cancelled in [false, true] {
        let facts = Arc::new(CaptureFacts::default());
        let behavior = ScriptedBehavior {
            gated_prepare: true,
            ..ScriptedBehavior::finite_multibyte()
        };
        let (backend, _root) = scripted_backend(facts.clone(), behavior, None)?;
        let manager = CommandProcessManager::new(Arc::new(backend));
        let cancellation = CancellationToken::new();
        let mut request = start_request();
        request.timeout = if cancelled {
            Duration::from_secs(30)
        } else {
            Duration::from_millis(10)
        };
        request.cancellation_token = Some(cancellation.clone());
        let owner =
            tokio::spawn(async move { manager.run_task("task-preparation-gate", request).await });
        tokio::time::timeout(Duration::from_secs(2), facts.prepared.notified())
            .await
            .context("prepare gate was never reached")?;
        if cancelled {
            cancellation.cancel();
        } else {
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
        facts.release_prepare.notify_one();
        let error = owner
            .await?
            .expect_err("expired/cancelled preparation must not spawn");
        anyhow::ensure!(
            error.process_started == Some(false) && !facts.spawned.load(Ordering::SeqCst)
        );
    }
    println!("OK  gated preparation: deadline and cancellation both prevent business spawn");
    Ok(())
}

struct BackpressuredInput {
    first: bool,
    facts: Arc<CaptureFacts>,
}
impl Drop for BackpressuredInput {
    fn drop(&mut self) {
        self.facts.input_dropped.store(true, Ordering::SeqCst);
    }
}
impl tokio::io::AsyncWrite for BackpressuredInput {
    fn poll_write(
        mut self: Pin<&mut Self>,
        _: &mut Context<'_>,
        bytes: &[u8],
    ) -> Poll<std::io::Result<usize>> {
        if self.first {
            self.first = false;
            self.facts.input_written.notify_one();
            Poll::Ready(Ok(bytes.len().min(32)))
        } else {
            Poll::Pending
        }
    }
    fn poll_flush(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Poll::Pending
    }
    fn poll_shutdown(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Poll::Ready(Ok(()))
    }
}
async fn backpressured_stdin_cancellation() -> anyhow::Result<()> {
    let facts = Arc::new(CaptureFacts::default());
    let behavior = ScriptedBehavior {
        backpressured_stdin: true,
        exit_without_cancellation: false,
        ..ScriptedBehavior::finite_multibyte()
    };
    let (backend, _root) = scripted_backend(facts.clone(), behavior, None)?;
    let tool = ThreadExecTool::new(
        Arc::new(backend),
        Arc::new(FixedArchive::default()),
        CommandAccess::WorkspaceOnly,
    );
    let calls = [
        (
            "backpressure-target",
            "exec",
            serde_json::json!({"command":"blocked-input", "timeoutSeconds":30}),
        ),
        (
            "backpressure-input",
            "write_stdin",
            serde_json::json!({"taskId":"task:backpressure-target", "chars":"中🌙".repeat(1000)}),
        ),
        (
            "cancel-input",
            "cancel_tool_task",
            serde_json::json!({"taskId":"task:backpressure-input"}),
        ),
    ]
    .into_iter()
    .map(
        |(call_id, tool_id, arguments)| pl_core::model::ModelToolCall {
            call_id: call_id.into(),
            tool_id: tool_id.into(),
            arguments: OpaquePayload::text(arguments.to_string()),
            rejection: None,
        },
    )
    .collect();
    let thread = pl_core::thread::ThreadHandle::start(
        "backpressure-scheduling".into(),
        pl_core::model::DynModelSession::new(ScriptedToolCalls { calls }),
    )?;
    let mut registrations =
        tool.registrations(OpaquePayload::text("exec"), OpaquePayload::text("stdin"))?;
    registrations.push(
        pl_tool::task_control::TaskControlTool::new(pl_tool::task_control::TaskControlKind::Cancel)
            .registration(OpaquePayload::text("cancel"))?,
    );
    thread.register_tools(registrations).await?;
    let run = tokio::time::timeout(
        Duration::from_secs(8),
        thread.run_turn(pl_core::thread::TurnInput {
            turn_id: "backpressure-turn".into(),
            attempt_prefix: "backpressure".into(),
            content: vec![],
            max_model_steps: pl_core::thread::ModelStepLimit::Limited(
                std::num::NonZeroU32::new(4).unwrap(),
            ),
            cancellation: CancellationToken::new(),
        }),
    )
    .await;
    if run.is_err() {
        thread.close().await?;
        anyhow::bail!("blocked stdin never yielded its own receipt so the model could cancel it");
    }
    run??;
    let input = tokio::time::timeout(
        Duration::from_secs(2),
        thread.wait_task("task:backpressure-input", CancellationToken::new()),
    )
    .await??;
    let receipt: serde_json::Value = serde_json::from_str(input.output.payload().content())?;
    let snapshot = thread.snapshot();
    let target_running = snapshot
        .tasks
        .get("task:backpressure-target")
        .is_some_and(|task| task.status == pl_core::thread::task::TaskStatus::Running);
    thread.close().await?;
    anyhow::ensure!(matches!(
        input.outcome,
        pl_core::thread::ToolOutcome::Cancelled
    ));
    anyhow::ensure!(
        receipt["inputReceipt"]["acceptedBytes"] == 32
            && receipt["inputReceipt"]["outcome"] == "cancelled"
    );
    anyhow::ensure!(receipt["targetTaskId"] == "task:backpressure-target" && target_running);
    println!(
        "OK  model receives blocked stdin task, cancels it, queries exact accepted prefix; original exec stays alive"
    );
    Ok(())
}

async fn combined_requested_output_budget() -> anyhow::Result<()> {
    for budget in [1, 127, 65536] {
        let behavior = ScriptedBehavior {
            dual_stream: true,
            ..ScriptedBehavior::finite_multibyte()
        };
        let (backend, _root) = scripted_backend(Arc::new(CaptureFacts::default()), behavior, None)?;
        let manager = CommandProcessManager::new(Arc::new(backend));
        let mut request = start_request();
        request.max_output_chars = budget;
        let snapshot = manager.run_task("task-combined-budget", request).await?;
        let visible = snapshot.stdout.content.len() + snapshot.stderr.content.len();
        anyhow::ensure!(
            visible <= budget,
            "combined requested budget exceeded: {visible} > {budget}"
        );
        if budget < 8192 {
            anyhow::ensure!(snapshot.stdout.was_truncated && snapshot.stderr.was_truncated);
        }
    }
    println!("OK  stdout + stderr share requested byte budget including maxOutputChars=1");
    Ok(())
}

/// 用例 5：后端声明的模型可见上限按字节计，不是按 Unicode 字符计；未声明时保持既有语义。
async fn model_output_cap_counts_bytes_not_chars() -> anyhow::Result<()> {
    // 未声明上限（默认）时保持既有语义：正文原样进入模型可见输出。
    let facts = Arc::new(CaptureFacts::default());
    let (backend, _root) = scripted_backend(facts, ScriptedBehavior::finite_multibyte(), None)?;
    let manager = CommandProcessManager::new(Arc::new(backend));
    let snapshot = tokio::time::timeout(
        Duration::from_secs(60),
        manager.run_task("task-model-cap-default", start_request()),
    )
    .await
    .context("未声明上限的有限命令必须正常落幕")??;
    anyhow::ensure!(
        snapshot.model_output_bytes_cap.is_none(),
        "未声明上限时快照必须说明本 operation 没有字节上限"
    );
    anyhow::ensure!(
        !snapshot.stdout.was_truncated,
        "未声明上限时不得新增截断（默认行为不变）"
    );

    // 声明字节上限后：可见正文按字节裁到上限之内，且多字节正文不会被按字符计数。
    let facts = Arc::new(CaptureFacts::default());
    let (backend, _root) = scripted_backend(
        facts,
        ScriptedBehavior::finite_multibyte(),
        Some(FAKE_MODEL_OUTPUT_BYTES as u64),
    )?;
    let manager = CommandProcessManager::new(Arc::new(backend));
    let snapshot = tokio::time::timeout(
        Duration::from_secs(60),
        manager.run_task("task-model-cap", start_request()),
    )
    .await
    .context("声明上限的有限命令必须正常落幕")??;
    anyhow::ensure!(
        snapshot.model_output_bytes_cap == Some(FAKE_MODEL_OUTPUT_BYTES as u64),
        "快照必须自证本次生效的模型可见字节上限"
    );
    anyhow::ensure!(
        snapshot.stdout.was_truncated,
        "超限的模型可见正文必须被截断"
    );
    let visible = snapshot.stdout.content.len() + snapshot.stderr.content.len();
    anyhow::ensure!(
        visible <= FAKE_MODEL_OUTPUT_BYTES,
        "模型可见正文必须按字节裁到上限内（按字符计的实现会在这里失败）：visible={visible}"
    );
    anyhow::ensure!(
        visible * 2 >= FAKE_MODEL_OUTPUT_BYTES,
        "上限必须真的被用掉，而不是退化成一个只有省略指示的正文：visible={visible}"
    );
    anyhow::ensure!(
        snapshot.stdout.original_length > FAKE_MODEL_OUTPUT_BYTES,
        "原始可见长度必须真的超过上限，截断才有意义"
    );
    println!(
        "OK  模型可见字节上限：cap={FAKE_MODEL_OUTPUT_BYTES} visible_bytes={visible} original_bytes={}",
        snapshot.stdout.original_length
    );
    // 极小预算也约束省略标记本身，不能因两条标记超过预算而反向突破硬上限。
    for cap in [0, 1, 32, 64, 127, 128] {
        let (backend, _root) = scripted_backend(
            Arc::new(CaptureFacts::default()),
            ScriptedBehavior::finite_multibyte(),
            Some(cap),
        )?;
        let manager = CommandProcessManager::new(Arc::new(backend));
        let snapshot = tokio::time::timeout(
            Duration::from_secs(60),
            manager.run_task("task-small-model-cap", start_request()),
        )
        .await
        .context("极小模型预算的命令必须正常落幕")??;
        let visible = snapshot.stdout.content.len() + snapshot.stderr.content.len();
        anyhow::ensure!(
            visible as u64 <= cap,
            "省略标记也必须计入模型可见预算：cap={cap} visible={visible}"
        );
        anyhow::ensure!(snapshot.stdout.was_truncated, "空预算仍须报告截断事实");
    }
    println!("OK  极小模型可见预算包含省略标记，UTF-8 正文保持有效");
    Ok(())
}

/// 可选：真实进程后端（`LocalCommandBackend`）在低自定义预算下也必须被取消并等它结束。
async fn real_backend_limit_terminates_process() -> anyhow::Result<()> {
    let root = tempfile::tempdir().context("tempdir")?;
    let inner = pl_tool::command::LocalCommandBackend::new(root.path().to_path_buf());
    let backend = LowBudgetBackend::new(
        inner,
        FAKE_CAPTURE_LIMIT_BYTES,
        None,
        Arc::new(CaptureFacts::default()),
    );
    let manager = CommandProcessManager::new(Arc::new(backend));
    let mut request = start_request();
    request.command = "while :; do printf '0123456789abcdef'; done".to_string();
    let snapshot = tokio::time::timeout(
        Duration::from_secs(60),
        manager.run_task("task-real-capture-limit", request),
    )
    .await
    .context(
        "真实后台命令没有在上限处结束（本段需要 PATH 上有 pl-remote-helper：cargo install --path code/pl-remote-helper --locked）",
    )??;
    anyhow::ensure!(
        snapshot.output_limit_exceeded().is_some(),
        "真实后端触顶后必须是 typed 容量终止：{:?}",
        snapshot.output_failure
    );
    anyhow::ensure!(
        !matches!(
            snapshot.state.final_result(),
            Some(CommandProcessFinalResult::Succeeded { .. })
        ),
        "真实后端触顶不得报成功"
    );
    println!("OK  真实进程后端：低自定义预算触顶后命令被取消并等到终态");
    let root = tempfile::tempdir()?;
    let local = pl_tool::command::LocalCommandBackend::new(root.path().to_path_buf());
    let target = local
        .output_target("tiny", "header", "call", "touch must-not-start")
        .await?;
    anyhow::ensure!(
        local
            .prepare_output(
                &target,
                "touch must-not-start",
                &root.path().display().to_string(),
                1
            )
            .await?
            == 0
    );
    anyhow::ensure!(
        std::fs::read(target.capture_file())?.is_empty()
            && !root.path().join("must-not-start").exists()
    );
    let manager = CommandProcessManager::new(Arc::new(LowBudgetBackend::new(
        local,
        1024 * 1024,
        Some(32 * 1024),
        Arc::new(CaptureFacts::default()),
    )));
    let mut request = start_request();
    request.command =
        "python3 -c 'import os; os.write(1,b\"h\"*262144); os.write(2,b\"e\"*196608)'".into();
    let snapshot = manager.run_task("task-real-rollover", request).await?;
    anyhow::ensure!(matches!(
        snapshot.state.final_result(),
        Some(CommandProcessFinalResult::Succeeded { .. })
    ));
    anyhow::ensure!(
        snapshot.stdout.original_length == 262144 && snapshot.stderr.original_length == 196608
    );
    anyhow::ensure!(snapshot.stdout.content.len() + snapshot.stderr.content.len() <= 32 * 1024);
    for stream in [&snapshot.stdout, &snapshot.stderr] {
        anyhow::ensure!(
            stream.was_truncated && stream.content.matches("[output omitted]").count() == 1
        );
    }
    let disk = tokio::fs::metadata(&snapshot.capture_file).await?.len()
        + tokio::fs::metadata(&snapshot.stderr_capture_file)
            .await?
            .len();
    anyhow::ensure!(
        snapshot
            .capture_usage
            .expect("local budget usage")
            .charged_bytes
            == disk
    );
    println!("OK  本地无头部原始文件与双流滚动窗口：原始长度准确、一次投影、计费等于磁盘长度");
    Ok(())
}

/// 一次运行的观察事实：由 backend 在真实落盘/取消时记录，供断言使用。
async fn real_stdin_eof_and_raw_utf8() -> anyhow::Result<()> {
    let root = tempfile::tempdir()?;
    let manager = CommandProcessManager::new(Arc::new(pl_tool::command::LocalCommandBackend::new(
        root.path(),
    )));
    let mut request = start_request();
    request.command = "cat > stdin.txt; printf done".into();
    let started = manager.start(request).await?;
    let process_id = started.process_id.context("running exec")?;
    let text = "中文🌙\nfinite input\n";
    let result = manager
        .write_stdin(pl_tool::command::CommandWriteRequest {
            process_id: process_id.clone(),
            chars: text.into(),
            close_stdin: true,
            cancellation: CancellationToken::new(),
            yield_time: Duration::ZERO,
            max_output_chars: 1024,
        })
        .await?;
    let receipt = result.input_receipt.as_ref().context("input receipt")?;
    anyhow::ensure!(
        receipt.accepted_bytes == text.len() as u64
            && !receipt.delivery_pending
            && receipt.close_state == Some(pl_tool::command::StdinCloseState::Closed)
    );
    if result.state.final_result().is_none() {
        tokio::time::timeout(Duration::from_secs(10), async {
            loop {
                if let Some(snapshot) = manager.snapshot(&process_id, 1024).await
                    && snapshot.state.final_result().is_some()
                {
                    return anyhow::Ok(());
                }
                tokio::task::yield_now().await;
            }
        })
        .await??;
    }
    anyhow::ensure!(std::fs::read(root.path().join("stdin.txt"))? == text.as_bytes());
    for (id, command, expected, lossy) in [
        (
            "task-raw-utf8",
            r#"python3 -c 'import os,time; b="中文🌙".encode(); os.write(1,b[:2]); time.sleep(0.02); os.write(1,b[2:]); os.write(2,b"error")'"#,
            "中文🌙".as_bytes().to_vec(),
            false,
        ),
        (
            "task-invalid-utf8",
            "python3 -c 'import os; os.write(1,bytes([255,97,226]))'",
            vec![255, 97, 226],
            true,
        ),
        (
            "task-long-utf8",
            r#"python3 -c 'import os; os.write(1,"中文🌙".encode()*20000)'"#,
            "中文🌙".repeat(20000).into_bytes(),
            false,
        ),
    ] {
        let mut request = start_request();
        request.command = command.into();
        let snapshot = manager.run_task(id, request).await?;
        anyhow::ensure!(std::fs::read(&snapshot.capture_file)? == expected);
        anyhow::ensure!(snapshot.stdout_text_lossy == lossy);
        if !lossy {
            anyhow::ensure!(!snapshot.stdout.content.contains('�'));
        }
        anyhow::ensure!(snapshot.capture_offsets.stdout == expected.len() as u64);
    }
    println!("OK  real finite stdin + EOF; raw no-newline UTF-8/invalid bytes/window boundaries");
    Ok(())
}

#[derive(Debug, Default)]
struct CaptureFacts {
    prepared_bytes: AtomicU64,
    appended_raw: AtomicU64,
    appends: AtomicU64,
    repairs: AtomicU64,
    process_cancelled: AtomicBool,
    spawned: AtomicBool,
    prepared: tokio::sync::Notify,
    release_prepare: tokio::sync::Notify,
    input_written: tokio::sync::Notify,
    input_dropped: AtomicBool,
}

/// 假后端的行为开关。
#[derive(Debug, Clone, Copy)]
struct ScriptedBehavior {
    total_bytes: u64,
    pattern: &'static [u8],
    exit_without_cancellation: bool,
    fail_first_append: bool,
    dual_stream: bool,
    gated_prepare: bool,
    backpressured_stdin: bool,
}

impl ScriptedBehavior {
    fn endless_until_cancelled() -> Self {
        Self {
            total_bytes: FAKE_TOTAL_BYTES,
            pattern: b"0123456789abcdef",
            exit_without_cancellation: false,
            fail_first_append: false,
            dual_stream: false,
            gated_prepare: false,
            backpressured_stdin: false,
        }
    }

    fn failing_first_append() -> Self {
        Self {
            fail_first_append: true,
            ..Self::endless_until_cancelled()
        }
    }

    fn finite_multibyte() -> Self {
        Self {
            total_bytes: 4096,
            pattern: MULTIBYTE_PATTERN.as_bytes(),
            exit_without_cancellation: true,
            fail_first_append: false,
            dual_stream: false,
            gated_prepare: false,
            backpressured_stdin: false,
        }
    }
}

/// 只声明低预算与显式存储成本的装饰 backend：其余语义全部委托给内层真实实现。
struct LowBudgetBackend<B> {
    inner: B,
    capture_limit_bytes: u64,
    model_output_bytes_cap: Option<u64>,
    capture_ownership: pl_tool::command::CommandCaptureOwnership,
    facts: Arc<CaptureFacts>,
}

impl<B: CommandBackend> LowBudgetBackend<B> {
    fn new(
        inner: B,
        capture_limit_bytes: u64,
        model_output_bytes_cap: Option<u64>,
        facts: Arc<CaptureFacts>,
    ) -> Self {
        let capture_ownership = inner.capture_ownership();
        Self {
            inner,
            capture_limit_bytes,
            model_output_bytes_cap,
            capture_ownership,
            facts,
        }
    }
}

impl<B: std::fmt::Debug> std::fmt::Debug for LowBudgetBackend<B> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("LowBudgetBackend")
            .field("inner", &self.inner)
            .field("capture_limit_bytes", &self.capture_limit_bytes)
            .field("model_output_bytes_cap", &self.model_output_bytes_cap)
            .finish_non_exhaustive()
    }
}

impl<B: CommandBackend> CommandBackend for LowBudgetBackend<B> {
    type Error = <B as CommandBackend>::Error;
    fn process_capacity(&self) -> Option<usize> {
        self.inner.process_capacity()
    }

    fn capture_limit_bytes(&self) -> Option<u64> {
        Some(self.capture_limit_bytes)
    }

    fn capture_ownership(&self) -> pl_tool::command::CommandCaptureOwnership {
        self.capture_ownership
    }

    fn capture_storage_cost(
        &self,
        target: &CommandOutputTarget,
        stream: CommandCaptureStream,
        chunk: &[u8],
    ) -> u64 {
        self.inner.capture_storage_cost(target, stream, chunk)
    }

    fn model_output_bytes_cap(&self) -> Option<u64> {
        self.model_output_bytes_cap
    }

    async fn resolve_cwd(
        &self,
        cwd: Option<&Path>,
        allow_workspace_escape: bool,
    ) -> Result<String, Self::Error> {
        self.inner.resolve_cwd(cwd, allow_workspace_escape).await
    }

    async fn output_target(
        &self,
        session_id: &str,
        tool_id: &str,
        call_id: &str,
        command: &str,
    ) -> Result<CommandOutputTarget, Self::Error> {
        self.inner
            .output_target(session_id, tool_id, call_id, command)
            .await
    }

    async fn spawn(&self, request: CommandSpawnRequest) -> Result<ManagedCommand, Self::Error> {
        self.inner.spawn(request).await
    }

    async fn prepare_output(
        &self,
        target: &CommandOutputTarget,
        command: &str,
        working_directory: &str,
        capture_limit_bytes: u64,
    ) -> Result<u64, Self::Error> {
        let prepared = self
            .inner
            .prepare_output(target, command, working_directory, capture_limit_bytes)
            .await?;
        self.facts.prepared_bytes.store(prepared, Ordering::SeqCst);
        Ok(prepared)
    }

    async fn append_output_chunk(
        &self,
        target: &CommandOutputTarget,
        stream: CommandCaptureStream,
        chunk: &[u8],
    ) -> Result<u64, Self::Error> {
        self.inner.append_output_chunk(target, stream, chunk).await
    }

    async fn repair_output_chunk(
        &self,
        capture_file: &Path,
        stream: CommandCaptureStream,
        committed_len: u64,
        chunk: &[u8],
    ) -> Result<u64, Self::Error> {
        self.facts.repairs.fetch_add(1, Ordering::SeqCst);
        self.inner
            .repair_output_chunk(capture_file, stream, committed_len, chunk)
            .await
    }

    async fn publish_output(&self, target: &CommandOutputTarget) -> Result<(), Self::Error> {
        self.inner.publish_output(target).await
    }

    async fn collect_output_artifacts(
        &self,
        target: &CommandOutputTarget,
        sizes: CommandOutputSizes,
    ) -> Result<Vec<serde_json::Value>, Self::Error> {
        self.inner.collect_output_artifacts(target, sizes).await
    }
}

/// 不启动真实进程的脚本化后端：按固定模式产出输出，并按"合并 + per-stream"两份真实落盘。
struct ScriptedBackend {
    root: PathBuf,
    behavior: ScriptedBehavior,
    facts: Arc<CaptureFacts>,
}

impl std::fmt::Debug for ScriptedBackend {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ScriptedBackend")
            .field("root", &self.root)
            .field("behavior", &self.behavior)
            .finish_non_exhaustive()
    }
}

impl ScriptedBackend {
    fn stream_capture_path(&self, stream: CommandCaptureStream) -> PathBuf {
        let name = match stream {
            CommandCaptureStream::Stdout => "stdout.log",
            CommandCaptureStream::Stderr => "stderr.log",
        };
        self.root.join("captures").join(name)
    }
}

impl CommandBackend for ScriptedBackend {
    type Error = std::io::Error;
    fn process_capacity(&self) -> Option<usize> {
        Some(8)
    }

    fn capture_ownership(&self) -> pl_tool::command::CommandCaptureOwnership {
        pl_tool::command::CommandCaptureOwnership::Manager
    }

    fn capture_storage_cost(
        &self,
        _target: &CommandOutputTarget,
        _stream: CommandCaptureStream,
        chunk: &[u8],
    ) -> u64 {
        chunk.len() as u64
    }

    async fn resolve_cwd(
        &self,
        _cwd: Option<&Path>,
        _allow_workspace_escape: bool,
    ) -> Result<String, Self::Error> {
        Ok(self.root.to_string_lossy().into_owned())
    }

    async fn output_target(
        &self,
        session_id: &str,
        tool_id: &str,
        _call_id: &str,
        _command: &str,
    ) -> Result<CommandOutputTarget, Self::Error> {
        let model_file = command_output_model_path(session_id, tool_id);
        Ok(CommandOutputTarget::new(
            self.stream_capture_path(CommandCaptureStream::Stdout),
            model_file,
        ))
    }

    async fn spawn(&self, _request: CommandSpawnRequest) -> Result<ManagedCommand, Self::Error> {
        self.facts.spawned.store(true, Ordering::SeqCst);
        let reader = FixedPatternReader {
            pattern: self.behavior.pattern.to_vec(),
            offset: 0,
            remaining: self.behavior.total_bytes,
        };
        let facts = Arc::clone(&self.facts);
        let exit_without_cancellation = self.behavior.exit_without_cancellation;
        Ok(ManagedCommand::new(
            None,
            CommandIo {
                stdin: self.behavior.backpressured_stdin.then(|| {
                    Box::pin(BackpressuredInput {
                        first: true,
                        facts: self.facts.clone(),
                    }) as pl_tool::command::CommandWriter
                }),
                stdout: Some(Box::pin(reader)),
                stderr: self.behavior.dual_stream.then(|| {
                    Box::pin(FixedPatternReader {
                        pattern: self.behavior.pattern.to_vec(),
                        offset: 0,
                        remaining: self.behavior.total_bytes,
                    }) as pl_tool::command::CommandReader
                }),
            },
            move |cancellation| async move {
                if !exit_without_cancellation {
                    // 模拟一个不会自己结束的后台命令：只有生命周期要求取消时才落幕，
                    // 因此"运行到终态"本身就证明 manager 真的终止并等待了它。
                    cancellation.cancelled().await;
                }
                facts.process_cancelled.store(true, Ordering::SeqCst);
                Ok(CommandExit {
                    supervision_failure: None,
                    signal: None,
                    capture_failure: None,
                    exit_code: Some(0),
                    capture: None,
                })
            },
        ))
    }

    async fn prepare_output(
        &self,
        target: &CommandOutputTarget,
        command: &str,
        working_directory: &str,
        capture_limit_bytes: u64,
    ) -> Result<u64, Self::Error> {
        let _ = (command, working_directory, capture_limit_bytes);
        if self.behavior.gated_prepare {
            self.facts.prepared.notify_one();
            self.facts.release_prepare.notified().await;
        }
        tokio::fs::create_dir_all(target.capture_file().parent().unwrap()).await?;
        for stream in [CommandCaptureStream::Stdout, CommandCaptureStream::Stderr] {
            tokio::fs::write(target.stream_capture_file(stream), b"").await?;
        }
        Ok(0)
    }

    async fn append_output_chunk(
        &self,
        target: &CommandOutputTarget,
        stream: CommandCaptureStream,
        chunk: &[u8],
    ) -> Result<u64, Self::Error> {
        if self.behavior.fail_first_append {
            return Err(std::io::Error::other("scripted capture append failure"));
        }
        let mut file = tokio::fs::OpenOptions::new()
            .append(true)
            .open(target.stream_capture_file(stream))
            .await?;
        tokio::io::AsyncWriteExt::write_all(&mut file, chunk).await?;
        tokio::io::AsyncWriteExt::flush(&mut file).await?;
        self.facts
            .appended_raw
            .fetch_add(chunk.len() as u64, Ordering::SeqCst);
        self.facts.appends.fetch_add(1, Ordering::SeqCst);
        Ok(file.metadata().await?.len())
    }

    async fn repair_output_chunk(
        &self,
        capture_file: &Path,
        stream: CommandCaptureStream,
        committed_len: u64,
        chunk: &[u8],
    ) -> Result<u64, Self::Error> {
        let file = tokio::fs::OpenOptions::new()
            .write(true)
            .open(capture_file)
            .await?;
        file.set_len(committed_len).await?;
        drop(file);
        let mut file = tokio::fs::OpenOptions::new()
            .append(true)
            .open(capture_file)
            .await?;
        let _ = stream;
        tokio::io::AsyncWriteExt::write_all(&mut file, chunk).await?;
        tokio::io::AsyncWriteExt::flush(&mut file).await?;
        Ok(file.metadata().await?.len())
    }

    async fn publish_output(&self, _target: &CommandOutputTarget) -> Result<(), Self::Error> {
        Ok(())
    }

    async fn collect_output_artifacts(
        &self,
        _target: &CommandOutputTarget,
        _sizes: CommandOutputSizes,
    ) -> Result<Vec<serde_json::Value>, Self::Error> {
        Ok(Vec::new())
    }
}

/// 只会按固定模式产出、总量有限的读端。
struct FixedPatternReader {
    pattern: Vec<u8>,
    offset: usize,
    remaining: u64,
}

impl tokio::io::AsyncRead for FixedPatternReader {
    fn poll_read(
        mut self: Pin<&mut Self>,
        _cx: &mut Context<'_>,
        buffer: &mut tokio::io::ReadBuf<'_>,
    ) -> Poll<std::io::Result<()>> {
        if self.remaining == 0 || self.pattern.is_empty() {
            return Poll::Ready(Ok(()));
        }
        let take = (buffer.remaining() as u64)
            .min(self.remaining)
            .min(self.pattern.len() as u64) as usize;
        let end = (self.offset + take).min(self.pattern.len());
        buffer.put_slice(&self.pattern[self.offset..end]);
        let written = end - self.offset;
        self.offset = (self.offset + written) % self.pattern.len();
        self.remaining -= written as u64;
        Poll::Ready(Ok(()))
    }
}

/// 假的输出归档：只验证"命令捕获上限"这条路径，不落真实资源。
#[derive(Default)]
struct FixedArchive {
    calls: AtomicU64,
}

impl std::fmt::Debug for FixedArchive {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("FixedArchive")
    }
}

impl CommandOutputArchive for FixedArchive {
    async fn retain(
        &self,
        _thread_id: &str,
        snapshot: &CommandOutputSnapshot,
        stream: CommandCaptureStream,
    ) -> Result<ResourceReference, ToolError> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        let byte_len = snapshot.capture_offsets.get(stream);
        ResourceReference::new(
            "pl-tool://command-capture-limit-validation".to_string(),
            format!("sha256:{}", "0".repeat(64)),
            byte_len,
            "text/plain".to_string(),
        )
        .map_err(ToolError::new)
    }
}

/// 用真实 `ThreadExecTool` 驱动一次 exec 调用，返回它的 typed 错误。
async fn run_exec_tool<B: CommandBackend + 'static>(
    backend: B,
    archive: Arc<FixedArchive>,
) -> Result<pl_core::tool::ToolOutput, ToolError> {
    run_exec_tool_with_budget(backend, archive, None).await
}

async fn run_exec_tool_with_budget<B: CommandBackend + 'static>(
    backend: B,
    archive: Arc<FixedArchive>,
    budget: Option<usize>,
) -> Result<pl_core::tool::ToolOutput, ToolError> {
    let tool = ThreadExecTool::new(Arc::new(backend), archive, CommandAccess::WorkspaceOnly);
    let input = ExecInput {
        command: "while :; do printf '0123456789abcdef'; done".to_string(),
        cwd: None,
        timeout_seconds: Some(30),
        max_output_chars: budget,
    };
    let content = serde_json::to_string(&input).map_err(ToolError::new)?;
    let payload = OpaquePayload::new("application/json", 1, content).map_err(ToolError::new)?;
    let call = CallContext {
        grant: Default::default(),
        context: Default::default(),
        model_projection: None,
        tasks: None,
        thread_id: "capture-limit-validation".to_string(),
        turn_id: "capture-limit-validation-turn".to_string(),
        call_id: "capture-limit-validation-call".to_string(),
        cancellation: CancellationToken::new(),
        extensions: Arc::new(std::collections::BTreeMap::new()),
        catalog: Arc::from(Vec::new()),
        extension_sequence: 0,
        history_fence: 0,
    };
    // 超时仅用于将不收敛的实现判为失败；成功由终态、实际回执与存储事实断言决定。
    tokio::time::timeout(
        Duration::from_secs(90),
        pl_core::tool::opaque::Tool::execute(&tool, payload, call),
    )
    .await
    .map_err(|_elapsed| {
        ToolError::new(std::io::Error::other(
            "exec tool did not settle within 90 seconds",
        ))
    })?
}

fn start_request() -> CommandStartRequest {
    CommandStartRequest {
        command: "scripted-endless-output".to_string(),
        cwd: None,
        allow_workspace_escape: false,
        timeout: Duration::from_secs(300),
        yield_time: Duration::ZERO,
        max_output_chars: 64 * 1024,
        session_id: "capture-limit-validation".to_string(),
        tool_id: "task-capture-limit".to_string(),
        call_id: "task-capture-limit".to_string(),
        cancellation_token: None,
        output_observer: None,
    }
}

fn scripted_backend(
    facts: Arc<CaptureFacts>,
    behavior: ScriptedBehavior,
    model_output_bytes_cap: Option<u64>,
) -> anyhow::Result<(LowBudgetBackend<ScriptedBackend>, tempfile::TempDir)> {
    let root = tempfile::tempdir().context("tempdir")?;
    let inner = ScriptedBackend {
        root: root.path().to_path_buf(),
        behavior,
        facts: Arc::clone(&facts),
    };
    Ok((
        LowBudgetBackend::new(
            inner,
            FAKE_CAPTURE_LIMIT_BYTES,
            model_output_bytes_cap,
            facts,
        ),
        root,
    ))
}

fn capture_files_len(root: &Path) -> anyhow::Result<u64> {
    let mut total = 0;
    for entry in std::fs::read_dir(root.join("captures"))? {
        total += entry?.metadata()?.len();
    }
    Ok(total)
}

struct ScriptedToolCalls {
    calls: std::collections::VecDeque<pl_core::model::ModelToolCall>,
}
impl ScriptedToolCalls {
    fn single_exec(raw: String, call_id: String) -> Self {
        Self {
            calls: [pl_core::model::ModelToolCall {
                call_id,
                tool_id: "exec".into(),
                arguments: OpaquePayload::text(raw),
                rejection: None,
            }]
            .into(),
        }
    }
}
impl pl_core::model::ModelSession for ScriptedToolCalls {
    async fn prepare(
        &mut self,
        request: pl_core::model::ModelRequest,
    ) -> Result<pl_core::model::PreparedModelCall, pl_core::model::ModelError> {
        let calls = self.calls.pop_front().into_iter().collect();
        Ok(pl_core::model::PreparedModelCall::new(async move {
            Ok(pl_core::model::ModelStepOutput {
                attempt_id: request.attempt_id,
                base_context_revision: request.context.revision,
                content: vec![],
                tool_calls: calls,
                private_context: None,
                usage: Default::default(),
            })
        }))
    }
    async fn close(&mut self) -> Result<(), pl_core::model::ModelError> {
        Ok(())
    }
}

#[cfg(target_os = "linux")]
async fn worker_bootstrap_cancellation() -> anyhow::Result<()> {
    use pl_remote_helper::client::{ManagedWorker, ProcessCommand, WorkerClientError};
    use pl_remote_helper::start_control::CommandStartControl;
    use std::os::unix::fs::PermissionsExt;
    for configure in [false, true] {
        let root = tempfile::tempdir()?;
        let script = root.path().join("held-worker.py");
        let frame =
            serde_json::to_string(&pl_protocol::process_worker::ProcessWorkerEvent::Ready {
                protocol_version: pl_protocol::process_worker::PROCESS_WORKER_PROTOCOL_VERSION,
            })? + "\n";
        let announce = if configure {
            format!(
                "wire.sendall({}.encode())\nwire.recv(4, socket.MSG_WAITALL)\n",
                serde_json::to_string(&frame)?
            )
        } else {
            String::new()
        };
        std::fs::write(
            &script,
            format!(
                "#!/usr/bin/env python3\nimport pathlib,socket,sys,time\nwire=socket.socket(fileno=int(sys.argv[2]))\n{announce}pathlib.Path(__file__).with_name('entered').write_text('entered')\ntime.sleep(30)\n"
            ),
        )?;
        std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o755))?;
        let cancellation = CancellationToken::new();
        let control = CommandStartControl::new(
            tokio::time::Instant::now() + Duration::from_secs(20),
            cancellation.clone(),
            CancellationToken::new(),
        );
        let mut command = ProcessCommand::new("touch")
            .args([root.path().join("must-not-start").into_os_string()]);
        if configure {
            command = command
                .env("PADDING_A", "x".repeat(100000))
                .env("PADDING_B", "x".repeat(100000));
        }
        let owner = {
            let control = control.clone();
            tokio::spawn(async move {
                ManagedWorker::spawn_controlled(&script, command, &control).await
            })
        };
        let entered = tokio::time::timeout(Duration::from_secs(3), async {
            while !root.path().join("entered").exists() {
                tokio::time::sleep(Duration::from_millis(5)).await;
            }
        })
        .await;
        cancellation.cancel();
        let error = owner
            .await?
            .expect_err("held worker must be cancelled and reaped");
        entered?;
        let mut source = &error;
        while let WorkerClientError::Bootstrap { source: nested, .. } = source {
            source = nested;
        }
        anyhow::ensure!(
            matches!(source, WorkerClientError::StartCancelled),
            "bootstrap did not observe cancellation: {error}"
        );
        anyhow::ensure!(!control.start_attempted() && !root.path().join("must-not-start").exists());
    }
    println!("OK  real worker Ready/configure cancellation: no business Start and owner reaped");
    Ok(())
}
