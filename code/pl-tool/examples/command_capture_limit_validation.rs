//! 命令捕获上限与模型可见字节上限的手工验证入口。
//!
//! 为什么不是 `cargo test`：本仓库约定（`AGENTS.md`「测试、检查与交付」、`design/24-testing.md`
//! §24.1）只有 `pl-model/tests` 与 `pl-core/tests` 保留常规自动化行为用例、`pl-studio-runtime`
//! 保留历史保存专项用例，**其它 crate 不新增测试**；而这两处都不能反向依赖 pl-tool。因此这里沿用
//! 本 crate 已有的人工入口形式（见 `ssh_remote_validation.rs`）：用公开 API 驱动真实实现，断言失败
//! 即返回非零退出码，由主代理/发布者在目标机上执行。
//!
//! 覆盖的缺陷敏感面：
//! 1. 单命令落盘上限按 backend 声明的**存储成本**计费，而不是原始流字节：合并输出与 per-stream
//!    捕获各算一份、再加每 chunk 的 framing，因此"原始字节还没到上限"就会正确停下。
//! 2. 触及上限会取消后台命令、等它真实结束，并以 typed `OutputLimitExceeded` 落幕（终态不是
//!    `Succeeded`，也不是 timeout/cancelled）。
//! 3. 容量终止与**可靠存储写失败**保持区分：前者不欠修复（`capture_repair()` 为 `None`），
//!    工具结果的 typed 错误是 `ExecFailure::OutputLimitExceeded`；后者仍是带
//!    `OutputRetryObligation` 的 `OutputStorageFault`。
//! 4. 后端声明的模型可见上限按**字节**计而不是 Unicode 字符：多字节正文不会按字符数放大上下文。
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
use tokio_util::sync::CancellationToken;

/// 假后端声明的单命令落盘上限：小到能在毫秒级触顶，又足够验证"成本而不是原始字节"。
const FAKE_CAPTURE_LIMIT_BYTES: u64 = 64 * 1024;
/// 假后端按"合并输出 + per-stream 捕获"两份计费，与 Mai 容器的真实落盘一致。
const FAKE_STORAGE_COPIES: u64 = 2;
/// 每 chunk 的 framing 折算（`=== STDOUT ===\n` 之类）。
const FAKE_FRAME_BYTES: u64 = 15;
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
    limit_is_charged_as_storage_cost_and_terminates().await?;
    write_failure_keeps_its_retry_obligation().await?;
    model_output_cap_counts_bytes_not_chars().await?;
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
    } else {
        println!(
            "-- 跳过真实进程验证（PURE_PL_COMMAND_REAL_BACKEND=1 且 PATH 上有 pl-remote-helper 时执行）"
        );
    }

    println!("== 全部断言通过 ==");
    Ok(())
}

/// 用例 1~3：成本计费、超限取消并真实落幕、typed 容量终止。
async fn limit_is_charged_as_storage_cost_and_terminates() -> anyhow::Result<()> {
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

    // 成本计费：每个被接纳的 chunk 只贡献 2 份字节 + 一份 framing。
    let appended_raw = facts.appended_raw.load(Ordering::SeqCst);
    let appends = facts.appends.load(Ordering::SeqCst);
    anyhow::ensure!(appends > 0, "上限之前必须先有真正落盘的已接纳 chunk");
    anyhow::ensure!(
        snapshot.capture_usage.expect("manager usage").charged_bytes
            == facts.prepared_bytes.load(Ordering::SeqCst)
                + appended_raw * FAKE_STORAGE_COPIES
                + appends * FAKE_FRAME_BYTES,
        "落盘预算必须按存储成本计费（两份 + framing）：charged={} raw={} appends={}",
        snapshot.capture_usage.expect("manager usage").charged_bytes,
        appended_raw,
        appends
    );
    anyhow::ensure!(
        snapshot.capture_usage.expect("manager usage").charged_bytes <= FAKE_CAPTURE_LIMIT_BYTES,
        "已接纳成本不得超过声明上限"
    );
    anyhow::ensure!(
        appended_raw < FAKE_CAPTURE_LIMIT_BYTES,
        "原始字节仍在上限之内就触顶，证明计费覆盖了分流与 framing：raw={appended_raw}"
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
        "声明上限必须覆盖头部与 framing 在内的全部磁盘占用：disk={disk_bytes}"
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
            .await
            .is_err()
    );
    anyhow::ensure!(
        !target.capture_file().exists() && !root.path().join("must-not-start").exists()
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
    let disk = tokio::fs::metadata(&snapshot.capture_file).await?.len();
    anyhow::ensure!(
        snapshot
            .capture_usage
            .expect("local budget usage")
            .charged_bytes
            == disk
    );
    println!("OK  本地头部预检与双流滚动窗口：原始长度准确、一次投影、计费等于磁盘长度");
    Ok(())
}

/// 一次运行的观察事实：由 backend 在真实落盘/取消时记录，供断言使用。
#[derive(Debug, Default)]
struct CaptureFacts {
    prepared_bytes: AtomicU64,
    appended_raw: AtomicU64,
    appends: AtomicU64,
    repairs: AtomicU64,
    process_cancelled: AtomicBool,
}

/// 假后端的行为开关。
#[derive(Debug, Clone, Copy)]
struct ScriptedBehavior {
    total_bytes: u64,
    pattern: &'static [u8],
    exit_without_cancellation: bool,
    fail_first_append: bool,
}

impl ScriptedBehavior {
    fn endless_until_cancelled() -> Self {
        Self {
            total_bytes: FAKE_TOTAL_BYTES,
            pattern: b"0123456789abcdef",
            exit_without_cancellation: false,
            fail_first_append: false,
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

    fn capture_ownership(&self) -> pl_tool::command::CommandCaptureOwnership {
        pl_tool::command::CommandCaptureOwnership::Manager
    }

    fn capture_storage_cost(
        &self,
        _target: &CommandOutputTarget,
        _stream: CommandCaptureStream,
        chunk: &[u8],
    ) -> u64 {
        chunk.len() as u64 * FAKE_STORAGE_COPIES + FAKE_FRAME_BYTES
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
        let capture_file = self.root.join("captures").join("combined.log");
        Ok(
            CommandOutputTarget::new(capture_file, model_file).with_stream_capture_files(
                self.stream_capture_path(CommandCaptureStream::Stdout),
                self.stream_capture_path(CommandCaptureStream::Stderr),
            ),
        )
    }

    async fn spawn(&self, _request: CommandSpawnRequest) -> Result<ManagedCommand, Self::Error> {
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
                stdin: None,
                stdout: Some(Box::pin(reader)),
                stderr: None,
            },
            move |cancellation| async move {
                if !exit_without_cancellation {
                    // 模拟一个不会自己结束的后台命令：只有生命周期要求取消时才落幕，
                    // 因此"运行到终态"本身就证明 manager 真的终止并等待了它。
                    cancellation.cancelled().await;
                }
                facts.process_cancelled.store(true, Ordering::SeqCst);
                Ok(CommandExit {
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
        let header = format!("=== COMMAND ===\n{command}\n\n=== CWD ===\n{working_directory}\n\n");
        if header.len() as u64 > capture_limit_bytes {
            return Err(std::io::Error::other("capture header exceeds budget"));
        }
        if let Some(parent) = target.capture_file().parent() {
            tokio::fs::create_dir_all(parent).await?;
        }
        for stream in [CommandCaptureStream::Stdout, CommandCaptureStream::Stderr] {
            if let Some(parent) = self.stream_capture_path(stream).parent() {
                tokio::fs::create_dir_all(parent).await?;
            }
        }
        tokio::fs::write(target.capture_file(), header.as_bytes()).await?;
        Ok(header.len() as u64)
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
        let label = match stream {
            CommandCaptureStream::Stdout => "STDOUT",
            CommandCaptureStream::Stderr => "STDERR",
        };
        let mut file = tokio::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(target.capture_file())
            .await?;
        tokio::io::AsyncWriteExt::write_all(&mut file, format!("=== {label} ===\n").as_bytes())
            .await?;
        tokio::io::AsyncWriteExt::write_all(&mut file, chunk).await?;
        tokio::io::AsyncWriteExt::flush(&mut file).await?;
        let mut stream_file = tokio::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(self.stream_capture_path(stream))
            .await?;
        tokio::io::AsyncWriteExt::write_all(&mut stream_file, chunk).await?;
        tokio::io::AsyncWriteExt::flush(&mut stream_file).await?;
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
        let label = match stream {
            CommandCaptureStream::Stdout => "STDOUT",
            CommandCaptureStream::Stderr => "STDERR",
        };
        tokio::io::AsyncWriteExt::write_all(&mut file, format!("=== {label} ===\n").as_bytes())
            .await?;
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
    ) -> Result<ResourceReference, ToolError> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        let byte_len = snapshot.capture_committed_len;
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
    let tool = ThreadExecTool::new(Arc::new(backend), archive, CommandAccess::WorkspaceOnly);
    let input = ExecInput {
        command: "while :; do printf '0123456789abcdef'; done".to_string(),
        cwd: None,
        timeout_seconds: Some(30),
        max_output_chars: None,
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
