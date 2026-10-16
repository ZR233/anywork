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
        RemoteClient::from_streams(child.stdout.take().unwrap(), child.stdin.take().unwrap());
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
        command: command.into(),
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
                limit_bytes: 1,
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
        let transport = client.spawn_process(request(id, command, capture)).await?;
        drop(transport.stdin);
        let mut stdout = transport.stdout;
        let mut stderr = transport.stderr;
        let (out, err, exit) = tokio::join!(
            async {
                let mut sink = tokio::io::sink();
                tokio::io::copy(&mut stdout, &mut sink).await
            },
            async {
                let mut sink = tokio::io::sink();
                tokio::io::copy(&mut stderr, &mut sink).await
            },
            transport.exit,
        );
        let (out, err, exit) = (out?, err?, exit??);
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
            anyhow::ensure!(
                receipt.refused_bytes > 0
                    && disk <= MAX_CAPTURE_BYTES
                    && disk > MAX_CAPTURE_BYTES - 32768
            );
            anyhow::ensure!(out + err > MAX_CAPTURE_BYTES - 131072 && out + err <= disk);
            if id == "both" {
                anyhow::ensure!(out > 0 && err > 0);
            }
        }
        println!("case={id} raw_stdout={out} raw_stderr={err} exit={exit:?}");
    }
    client.close().await?;
    anyhow::ensure!(child.wait().await?.success(), "helper did not close");
    println!("header_preflight=passed");
    Ok(())
}
