//! 用独立 stdio helper 验证物理磁盘预算、双流与无归档长流，不需要产品实例。
use anyhow::Context as _;
use pl_protocol::remote::{
    REMOTE_PROTOCOL_VERSION, RemoteCapture, RemoteErrorCode, RemoteRequest, RemoteResponse,
    RemoteSpawnRequest,
};
use pl_tool::{
    command::MAX_CAPTURE_BYTES,
    remote::{RemoteClient, RemoteClientError},
};
use std::{collections::BTreeMap, process::Stdio};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let root = tempfile::tempdir()?;
    let mut child = tokio::process::Command::new("pl-remote-helper")
        .arg("--serve")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()?;
    let client =
        RemoteClient::from_streams(child.stdout.take().unwrap(), child.stdin.take().unwrap())
            .await?;
    let old_protocol = client
        .request(
            RemoteRequest::Hello {
                protocol_version: REMOTE_PROTOCOL_VERSION - 1,
            },
            &[],
        )
        .await;
    anyhow::ensure!(
        matches!(
            old_protocol,
            Err(RemoteClientError::Remote {
                code: RemoteErrorCode::ProtocolMismatch,
                ..
            })
        ),
        "old protocol must be explicitly rejected"
    );
    client
        .request(
            RemoteRequest::Hello {
                protocol_version: REMOTE_PROTOCOL_VERSION,
            },
            &[],
        )
        .await?;
    let opened = client
        .request(
            RemoteRequest::OpenWorkspace {
                path: root.path().display().to_string(),
            },
            &[],
        )
        .await?;
    let RemoteResponse::WorkspaceOpened(workspace) = opened.response else {
        anyhow::bail!("unexpected workspace response");
    };
    let request = |id: &str, command: &str, capture| RemoteSpawnRequest {
        process_id: id.into(),
        workspace_id: workspace.workspace_id.clone(),
        program: "/bin/sh".into(),
        arguments: vec!["-c".into(), command.into()],
        remove_environment: vec![],
        cwd: ".".into(),
        environment: BTreeMap::new(),
        capture,
        remaining_timeout_ms: None,
    };
    let error = client
        .spawn_process(request(
            "invalid-capture",
            "touch must-not-start",
            RemoteCapture::Files {
                stdout_path: "tiny.log".into(),
                stderr_path: "tiny-err.log".into(),
                limit_bytes: 0,
            },
        ))
        .await;
    anyhow::ensure!(
        matches!(
            error,
            Err(RemoteClientError::Remote {
                code: RemoteErrorCode::InvalidRequest,
                ..
            })
        ),
        "invalid capture budget must be refused before file creation/spawn"
    );
    anyhow::ensure!(
        !root.path().join("tiny.log").exists() && !root.path().join("must-not-start").exists()
    );

    for (id, command, capture) in [
        (
            "stdout",
            "head -c 20000000 /dev/zero",
            RemoteCapture::Files {
                stdout_path: "stdout.log".into(),
                stderr_path: "stdout-err.log".into(),
                limit_bytes: MAX_CAPTURE_BYTES,
            },
        ),
        (
            "both",
            "python3 -c 'import os; [(os.write(1, b\"a\"*4096),os.write(2, b\"b\"*4096)) for _ in range(3000)]'",
            RemoteCapture::Files {
                stdout_path: "both.log".into(),
                stderr_path: "both-err.log".into(),
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
            anyhow::ensure!(
                out == 20_000_000
                    && err == 0
                    && exit.exit_code == Some(0)
                    && exit.capture.is_none()
            );
            anyhow::ensure!(!root.path().join("stream.log").exists());
        } else {
            let receipt = exit
                .capture
                .ok_or_else(|| anyhow::anyhow!("missing physical receipt"))?;
            let disk = std::fs::metadata(root.path().join(format!("{id}.log")))?.len()
                + std::fs::metadata(root.path().join(format!("{id}-err.log")))?.len();
            anyhow::ensure!(
                receipt.limit_bytes == MAX_CAPTURE_BYTES && receipt.charged_bytes == disk
            );
            anyhow::ensure!(receipt.refused_bytes > 0 && disk <= MAX_CAPTURE_BYTES);
            let stdout = std::fs::read(root.path().join(format!("{id}.log")))?;
            let stderr = std::fs::read(root.path().join(format!("{id}-err.log")))?;
            anyhow::ensure!(
                stdout.len() as u64 == receipt.confirmed.stdout
                    && stderr.len() as u64 == receipt.confirmed.stderr
            );
            anyhow::ensure!(
                stdout
                    .iter()
                    .all(|byte| *byte == if id == "both" { b'a' } else { 0 })
            );
            anyhow::ensure!(stderr.iter().all(|byte| *byte == b'b'));
            if id == "both" {
                anyhow::ensure!(out > 0 && err > 0);
            }
        }
        println!("case={id} raw_stdout={out} raw_stderr={err} exit={exit:?}");
    }
    atomic_overwrite_publishes_and_refuses_symlinks(client.clone(), root.path()).await?;
    client.close().await?;
    anyhow::ensure!(child.wait().await?.success(), "helper did not close");
    #[cfg(target_os = "linux")]
    capture_flush_failure_preserves_exit().await?;
    println!("raw_capture_preflight=passed");
    Ok(())
}

async fn atomic_overwrite_publishes_and_refuses_symlinks(
    client: RemoteClient,
    root: &std::path::Path,
) -> anyhow::Result<()> {
    use pl_protocol::remote::{RemotePathRequest, RemoteWriteMode, RemoteWriteRequest};
    let opened = client
        .request(
            RemoteRequest::OpenWorkspace {
                path: root.display().to_string(),
            },
            &[],
        )
        .await?;
    let RemoteResponse::WorkspaceOpened(workspace) = opened.response else {
        anyhow::bail!("unexpected workspace response");
    };
    write_file(
        &client,
        RemoteWriteRequest {
            target: RemotePathRequest {
                workspace_id: workspace.workspace_id.clone(),
                path: "atomic.txt".into(),
            },
            mode: RemoteWriteMode::Overwrite,
            total_len: 9,
        },
        b"published",
    )
    .await?;
    anyhow::ensure!(std::fs::read(root.join("atomic.txt"))? == b"published");
    let leftovers: Vec<_> = std::fs::read_dir(root)?
        .filter_map(|entry| entry.ok())
        .filter(|entry| {
            entry
                .file_name()
                .to_string_lossy()
                .starts_with(".anywork-transfer-")
        })
        .collect();
    anyhow::ensure!(
        leftovers.is_empty(),
        "successful overwrite must not leave temps"
    );
    #[cfg(unix)]
    {
        std::os::unix::fs::symlink(root.join("atomic.txt"), root.join("link.txt"))?;
        let linked = write_file(
            &client,
            RemoteWriteRequest {
                target: RemotePathRequest {
                    workspace_id: workspace.workspace_id,
                    path: "link.txt".into(),
                },
                mode: RemoteWriteMode::Overwrite,
                total_len: 8,
            },
            b"via-link",
        )
        .await;
        anyhow::ensure!(linked.is_err(), "writeAtomic must refuse symlink entries");
        anyhow::ensure!(std::fs::read(root.join("atomic.txt"))? == b"published");
    }
    println!("OK  writeAtomic publishes atomically and refuses symlink entries");
    Ok(())
}

async fn write_file(
    client: &RemoteClient,
    request: pl_protocol::remote::RemoteWriteRequest,
    bytes: &[u8],
) -> anyhow::Result<()> {
    use sha2::{Digest, Sha256};
    let opened = client
        .request(RemoteRequest::BeginWrite(request), &[])
        .await?;
    let RemoteResponse::Transfer(opened) = opened.response else {
        anyhow::bail!("expected write handle")
    };
    let digest = hex::encode(Sha256::digest(bytes));
    client
        .request(
            RemoteRequest::WriteChunk {
                transfer_id: opened.transfer_id.clone(),
                offset: 0,
                sha256: digest.clone(),
            },
            bytes,
        )
        .await?;
    client
        .request(
            RemoteRequest::CommitWrite {
                transfer_id: opened.transfer_id.clone(),
                length: bytes.len() as u64,
                sha256: digest,
            },
            &[],
        )
        .await?;
    client
        .request(
            RemoteRequest::CloseTransfer {
                transfer_id: opened.transfer_id,
            },
            &[],
        )
        .await?;
    Ok(())
}

#[cfg(target_os = "linux")]
async fn capture_flush_failure_preserves_exit() -> anyhow::Result<()> {
    let root = tempfile::tempdir()?;
    // RLIMIT_FSIZE affects regular capture files, while the business process writes to a pipe.
    // Ignoring SIGXFSZ makes the physical writer observe EFBIG instead of killing the helper.
    let mut child = tokio::process::Command::new("sh")
        .args([
            "-c",
            "trap '' XFSZ; exec prlimit --fsize=0 -- pl-remote-helper --serve",
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .kill_on_drop(true)
        .spawn()?;
    let client =
        RemoteClient::from_streams(child.stdout.take().unwrap(), child.stdin.take().unwrap())
            .await?;
    let outcome = async {
        client
            .request(
                RemoteRequest::Hello {
                    protocol_version: REMOTE_PROTOCOL_VERSION,
                },
                &[],
            )
            .await?;

        let workspace = client
            .request(
                RemoteRequest::OpenWorkspace {
                    path: root.path().display().to_string(),
                },
                &[],
            )
            .await?;
        let RemoteResponse::WorkspaceOpened(workspace) = workspace.response else {
            anyhow::bail!("workspace response");
        };
        let mut command = client
            .spawn_process(RemoteSpawnRequest {
                process_id: "capture-flush-failure".into(),
                workspace_id: workspace.workspace_id,
                program: "/bin/sh".into(),
                arguments: vec!["-c".into(), "printf data; exit 0".into()],
                remove_environment: vec![],
                cwd: ".".into(),
                environment: Default::default(),
                remaining_timeout_ms: Some(10000),
                capture: RemoteCapture::Files {
                    stdout_path: "stdout.log".into(),
                    stderr_path: "stderr.log".into(),
                    limit_bytes: 65536,
                },
            })
            .await?;
        drop(command.take_stdin());
        let mut stdout = command.take_stdout().unwrap();
        let mut stderr = command.take_stderr().unwrap();
        let mut out_sink = tokio::io::sink();
        let mut err_sink = tokio::io::sink();
        let (_, _, exit) = tokio::join!(
            tokio::io::copy(&mut stdout, &mut out_sink),
            tokio::io::copy(&mut stderr, &mut err_sink),
            command.wait()
        );
        let exit = exit.map_err(anyhow::Error::msg)?;
        anyhow::ensure!(
            exit.exit_code == Some(0),
            "capture failure must retain business exit: {exit:?}"
        );
        anyhow::ensure!(matches!(
            exit.capture_failure,
            Some(
                pl_tool::command::CommandCaptureFailure::Flush { .. }
                    | pl_tool::command::CommandCaptureFailure::Write { .. }
            )
        ));
        let receipt = exit
            .capture
            .context("capture failure must retain its receipt")?;
        anyhow::ensure!(receipt.confirmed.total() == 0 && receipt.captured_bytes == 4);
        println!(
            "OK  real capture EFBIG: exit=0, typed write/flush failure, confirmed=0 captured=4"
        );
        anyhow::Ok(())
    }
    .await;
    let close = client.close().await;
    let waited = child.wait().await;
    outcome?;
    close?;
    anyhow::ensure!(waited?.success());
    Ok(())
}
