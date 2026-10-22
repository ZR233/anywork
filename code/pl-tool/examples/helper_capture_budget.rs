//! 用独立 stdio helper 验证物理磁盘预算、双流与无归档长流，不需要产品实例。
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
    };
    let error = client
        .spawn_process(request(
            "header",
            "touch must-not-start",
            RemoteCapture::File {
                path: "tiny.log".into(),
                plan: capture_plan(1),
            },
        ))
        .await;
    anyhow::ensure!(
        matches!(
            error,
            Err(RemoteClientError::Remote {
                code: RemoteErrorCode::OutputLimitExceeded,
                ..
            })
        ),
        "header must be refused before file creation/spawn"
    );
    anyhow::ensure!(
        !root.path().join("tiny.log").exists() && !root.path().join("must-not-start").exists()
    );

    for (id, command, capture) in [
        (
            "stdout",
            "head -c 20000000 /dev/zero",
            RemoteCapture::File {
                path: "stdout.log".into(),
                plan: capture_plan(MAX_CAPTURE_BYTES),
            },
        ),
        (
            "both",
            "python3 -c 'import os; [(os.write(1, b\"a\"*4096),os.write(2, b\"b\"*4096)) for _ in range(3000)]'",
            RemoteCapture::File {
                path: "both.log".into(),
                plan: capture_plan(MAX_CAPTURE_BYTES),
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
            let disk = std::fs::metadata(root.path().join(format!("{id}.log")))?.len();
            anyhow::ensure!(
                receipt.limit_bytes == MAX_CAPTURE_BYTES && receipt.charged_bytes == disk
            );
            anyhow::ensure!(receipt.refused_bytes > 0 && disk <= MAX_CAPTURE_BYTES);
            let archive = std::fs::read(root.path().join(format!("{id}.log")))?;
            let raw = archive
                .split(|byte| *byte == b'\n')
                .filter(|line| {
                    !line.is_empty()
                        && (line.iter().all(|byte| *byte == 0)
                            || line.iter().all(|byte| *byte == b'a')
                            || line.iter().all(|byte| *byte == b'b'))
                })
                .map(|line| line.len() as u64)
                .sum::<u64>();
            anyhow::ensure!(
                raw == out + err,
                "raw output and actual archived bytes differ"
            );
            if id == "both" {
                anyhow::ensure!(out > 0 && err > 0);
            }
        }
        println!("case={id} raw_stdout={out} raw_stderr={err} exit={exit:?}");
    }
    atomic_overwrite_publishes_and_refuses_symlinks(client.clone(), root.path()).await?;
    client.close().await?;
    anyhow::ensure!(child.wait().await?.success(), "helper did not close");
    println!("header_preflight=passed");
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

fn capture_plan(limit_bytes: u64) -> pl_protocol::remote::RemoteCapturePlan {
    pl_protocol::remote::RemoteCapturePlan {
        header: "capture fixture\n".into(),
        stdout_prefix: "=== STDOUT ===\n".into(),
        stderr_prefix: "=== STDERR ===\n".into(),
        terminate_line: true,
        limit_bytes,
    }
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
