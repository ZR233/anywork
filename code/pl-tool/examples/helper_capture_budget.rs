//! 用独立 stdio helper 验证物理磁盘预算、双流与无归档长流，不需要产品实例。
//!
//! 运行：`cargo run -p pl-tool --example helper_capture_budget`
//!
//! 需要 PATH 上有 `pl-remote-helper`（`cargo install --path code/pl-remote-helper --locked`），
//! 或用 `PURE_HELPER_BIN=<path>` 指定。工作区位于 `TMPDIR`，可用
//! `PURE_REMOTE_ACCEPTANCE_DIR=<dir>` 指定父目录。
//!
//! 观察内容：capture 预算的预检拒绝、单/双流磁盘计量与拒绝量、无归档长流、原子 overwrite
//! 发布以及链接拒绝。任何一项失败都返回错误；成功、失败与超时路径都执行同一 helper 收尾
//! （退出裁决 → stderr 排空 → 后代回收）。
use std::collections::BTreeMap;
use std::path::PathBuf;
use std::time::Duration;

use anyhow::{Context, ensure};
use pl_protocol::remote::{
    RemoteCapture, RemoteErrorCode, RemotePathRequest, RemoteRequest, RemoteResponse,
    RemoteSpawnRequest, RemoteWriteMode, RemoteWriteRequest,
};
use pl_tool::command::MAX_CAPTURE_BYTES;
use pl_tool::remote::{RemoteClient, RemoteClientError};

#[path = "support/helper.rs"]
mod helper_process;
#[path = "support/outcome.rs"]
mod outcome;

use helper_process::{ExitExpectation, Helper, finish_scenario, request_graceful_shutdown};
use outcome::{TaskOwner, run_with_deadline};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let fixture = Some(acceptance_root("helper-capture-budget")?);
    let mut helper = Helper::start().await?;
    let mut tasks = TaskOwner::new();
    let outcome = run_with_deadline(Duration::from_secs(300), async {
        let client = helper.connect().await?;
        let root = fixture
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("capture scenario requires an owned fixture"))?;
        let opened = client
            .request(RemoteRequest::OpenWorkspace {
                path: root.path().display().to_string(),
            })
            .await?;
        let RemoteResponse::WorkspaceOpened(workspace) = opened else {
            anyhow::bail!("unexpected openWorkspace response: {opened:?}");
        };
        let workspace_id = workspace.workspace_id;
        let request = |id: &str, command: &str, capture| RemoteSpawnRequest {
            process_id: id.into(),
            workspace_id: workspace_id.clone(),
            command: command.into(),
            cwd: ".".into(),
            environment: BTreeMap::new(),
            capture,
        };

        // capture 预算在创建文件和启动命令之前就被拒绝。
        let error = client
            .spawn_process(request(
                "header",
                "touch must-not-start",
                RemoteCapture::File {
                    path: "tiny.log".into(),
                    limit_bytes: 1,
                },
            ))
            .await;
        ensure!(
            matches!(
                error,
                Err(RemoteClientError::Remote {
                    code: RemoteErrorCode::OutputLimitExceeded,
                    ..
                })
            ),
            "header must be refused before file creation or spawn: {error:?}"
        );
        ensure!(
            !root.path().join("tiny.log").exists() && !root.path().join("must-not-start").exists(),
            "refused capture policy left side effects"
        );

        for (id, command, capture) in [
            (
                "stdout",
                "head -c 20000000 /dev/zero",
                RemoteCapture::File {
                    path: "stdout.log".into(),
                    limit_bytes: MAX_CAPTURE_BYTES,
                },
            ),
            (
                "both",
                "python3 -c 'import os; [(os.write(1, b\"a\"*4096),os.write(2, b\"b\"*4096)) for _ in range(3000)]'",
                RemoteCapture::File {
                    path: "both.log".into(),
                    limit_bytes: MAX_CAPTURE_BYTES,
                },
            ),
            ("stream", "head -c 20000000 /dev/zero", RemoteCapture::None),
        ] {
            let mut transport = client.spawn_process(request(id, command, capture)).await?;
            drop(transport.take_stdin());
            let mut stdout = transport
                .take_stdout()
                .ok_or_else(|| anyhow::anyhow!("missing stdout"))?;
            let mut stderr = transport
                .take_stderr()
                .ok_or_else(|| anyhow::anyhow!("missing stderr"))?;
            let (out, err, exit) = tokio::join!(
                async {
                    let mut sink = tokio::io::sink();
                    tokio::io::copy(&mut stdout, &mut sink).await
                },
                async {
                    let mut sink = tokio::io::sink();
                    tokio::io::copy(&mut stderr, &mut sink).await
                },
                transport.wait(),
            );
            let (out, err, exit) = (out?, err?, exit.map_err(anyhow::Error::msg)?);
            if id == "stream" {
                ensure!(
                    out == 20_000_000
                        && err == 0
                        && exit.exit_code == Some(0)
                        && exit.capture.is_none()
                );
                ensure!(!root.path().join("stream.log").exists());
            } else {
                let receipt = exit
                    .capture
                    .ok_or_else(|| anyhow::anyhow!("missing physical receipt"))?;
                let disk = std::fs::metadata(root.path().join(format!("{id}.log")))?.len();
                ensure!(
                    receipt.limit_bytes == MAX_CAPTURE_BYTES && receipt.charged_bytes == disk,
                    "capture receipt does not match the physical file: receipt={receipt:?} disk={disk}"
                );
                ensure!(
                    receipt.refused_bytes > 0
                        && disk <= MAX_CAPTURE_BYTES
                        && disk > MAX_CAPTURE_BYTES - 32768
                );
                ensure!(out + err > MAX_CAPTURE_BYTES - 131072 && out + err <= disk);
                if id == "both" {
                    ensure!(out > 0 && err > 0);
                }
            }
            println!("case={id} raw_stdout={out} raw_stderr={err} exit={exit:?}");
        }

        atomic_overwrite_publishes_and_refuses_symlinks(&client, &workspace_id, root.path()).await?;
        request_graceful_shutdown(&client).await?;
        println!("header_preflight=passed cases=3 atomic=passed symlink=refused");
        anyhow::Ok(())
    })
    .await;
    finish_scenario(
        outcome,
        &mut tasks,
        helper,
        fixture,
        ExitExpectation::Success,
        Duration::from_secs(60),
        |_, _| Ok(()),
    )
    .await
}

async fn atomic_overwrite_publishes_and_refuses_symlinks(
    client: &RemoteClient,
    workspace_id: &str,
    root: &std::path::Path,
) -> anyhow::Result<()> {
    let mut source: &[u8] = b"published";
    let written = client
        .write_file(
            RemoteWriteRequest {
                target: RemotePathRequest {
                    workspace_id: workspace_id.to_string(),
                    path: "atomic.txt".into(),
                },
                mode: RemoteWriteMode::Overwrite,
                total_len: 9,
            },
            &mut source,
        )
        .await?;
    ensure!(written == 9, "published byte count mismatch: {written}");
    ensure!(std::fs::read(root.join("atomic.txt"))? == b"published");
    let leftovers: Vec<_> = std::fs::read_dir(root)?
        .filter_map(|entry| entry.ok())
        .filter(|entry| {
            entry
                .file_name()
                .to_string_lossy()
                .starts_with(".pure-write-")
        })
        .collect();
    ensure!(
        leftovers.is_empty(),
        "successful overwrite must not leave temps"
    );
    #[cfg(unix)]
    {
        std::os::unix::fs::symlink(root.join("atomic.txt"), root.join("link.txt"))?;
        let mut source: &[u8] = b"via-link";
        let linked = client
            .write_file(
                RemoteWriteRequest {
                    target: RemotePathRequest {
                        workspace_id: workspace_id.to_string(),
                        path: "link.txt".into(),
                    },
                    mode: RemoteWriteMode::Overwrite,
                    total_len: 8,
                },
                &mut source,
            )
            .await;
        ensure!(linked.is_err(), "writeAtomic must refuse symlink entries");
        ensure!(std::fs::read(root.join("atomic.txt"))? == b"published");
    }
    println!("OK  writeAtomic publishes atomically and refuses symlink entries");
    Ok(())
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
