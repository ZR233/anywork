//! Deterministic helper reconnect, receipt and resource-release proofs.
#![cfg(target_os = "linux")]

#[path = "support/helper.rs"]
mod helper;
#[path = "support/remote_receipts.rs"]
mod receipts;
#[path = "support/remote_resource.rs"]
mod support;
use anyhow::{Context, ensure};
use pl_protocol::remote::*;
use std::{
    path::Path,
    time::{Duration, Instant},
};
use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader};

#[tokio::test]
async fn helper_directory_removal_retains_effect_and_preserves_neighbor() -> anyhow::Result<()> {
    use pl_tool::remote::RemoteClientError;
    let executable = helper::remote_helper_executable();
    let helper = support::Helper::start(executable).await?;
    let outcome = async {
        let target = helper.root.path().join("deleted");
        let neighbor = helper.root.path().join("neighbor");
        std::fs::create_dir(&neighbor)?;
        std::fs::write(neighbor.join("keep"), b"neighbor")?;
        for directory in 0..16 {
            let directory = target.join(format!("{directory}/nested/deep"));
            std::fs::create_dir_all(&directory)?;
            for file in 0..64 {
                std::fs::write(directory.join(file.to_string()), b"disposable")?;
            }
        }
        let request = |path: &str, recursive| {
            RemoteRequest::RemovePath(RemoteRemoveRequest {
                workspace_id: helper.workspace.clone(),
                path: path.into(),
                recursive,
            })
        };
        let refused = helper
            .client
            .request(request("neighbor", false), &[])
            .await
            .expect_err("nonempty directory refusal");
        ensure!(matches!(
            refused,
            RemoteClientError::Remote {
                code: RemoteErrorCode::Io,
                removal_effect: Some(RemoteRemovalEffect::MayHaveChanged),
                ..
            }
        ));
        let outside = tempfile::tempdir()?;
        std::fs::write(outside.path().join("keep"), b"outside")?;
        std::os::unix::fs::symlink(outside.path(), helper.root.path().join("linked"))?;
        let refused = helper
            .client
            .request(request("linked", true), &[])
            .await
            .expect_err("linked target refusal");
        ensure!(matches!(
            refused,
            RemoteClientError::Remote {
                code: RemoteErrorCode::WorkspaceEscape,
                removal_effect: Some(RemoteRemovalEffect::NotStarted),
                ..
            }
        ));
        ensure!(std::fs::read(outside.path().join("keep"))? == b"outside");
        let started = Instant::now();
        helper.client.request(request("deleted", true), &[]).await?;
        println!(
            "REMOTE_DIRECTORY_DELETE files=1024 directories=48 elapsed_ms={}",
            started.elapsed().as_millis()
        );
        ensure!(!target.exists());
        let absent = helper
            .client
            .request(request("deleted", true), &[])
            .await
            .expect_err("typed absence");
        ensure!(matches!(
            absent,
            RemoteClientError::Remote {
                code: RemoteErrorCode::PathNotFound,
                removal_effect: Some(RemoteRemovalEffect::NotStarted),
                ..
            }
        ));
        ensure!(std::fs::read(neighbor.join("keep"))? == b"neighbor");
        anyhow::Ok(())
    }
    .await;
    let closed = helper.close().await;
    outcome?;
    closed?;
    Ok(())
}

#[tokio::test]
async fn helper_receipts_reconnect_and_release() -> anyhow::Result<()> {
    let executable = helper::remote_helper_executable();
    receipts::verify(executable).await?;
    let mut helper = support::Helper::start(executable).await?;
    let outcome = exercise(&mut helper, executable).await;
    let close = helper.close().await;
    outcome?;
    close?;
    support::Helper::start(executable)
        .await?
        .close_during_attachment(executable)
        .await?;
    let expiring = support::Helper::start(executable).await?;
    let owner_pid = support::heartbeat(&expiring.client).await?.owner_pid;
    let mut command = expiring
        .command("lease-owned", "printf 'ready\\n'; sleep 120")
        .await?;
    let mut output = BufReader::new(command.take_stdout().context("lease stdout")?);
    let mut ready = String::new();
    output.read_line(&mut ready).await?;
    ensure!(ready == "ready\n");
    expiring.expire(owner_pid).await?;
    ensure!(
        !matches!(command.wait().await, Ok(exit) if exit.exit_code == Some(0)),
        "expired physical command was reported successful"
    );
    Ok(())
}
async fn exercise(helper: &mut support::Helper, executable: &Path) -> anyhow::Result<()> {
    let initial = support::heartbeat(&helper.client).await?;
    let owner_pid = initial.owner_pid;
    let baseline = support::resources(owner_pid);
    let host_baseline = support::resources(std::process::id());
    println!(
        "{}",
        serde_json::json!({"scenario":"baseline", "resources":baseline, "host":host_baseline, "helper":initial})
    );
    // Reproduce the failed-directory request while an independently owned command remains alive.
    for index in 0..1000 {
        std::fs::write(
            helper
                .root
                .path()
                .join(format!("{index:04}-{}", "x".repeat(180))),
            b"fixture",
        )?;
    }
    let mut gated = helper
        .command(
            "gated",
            "printf 'ready\\n'; IFS= read -r value; printf 'received:%s\\n' \"$value\"",
        )
        .await?;
    let mut stdin = gated.take_stdin().context("stdin")?;
    let mut output = BufReader::new(gated.take_stdout().context("stdout")?);
    let mut ready = String::new();
    tokio::time::timeout(Duration::from_secs(10), output.read_line(&mut ready)).await??;
    ensure!(ready == "ready\n");
    let mut listed = 0;
    let mut request = RemoteRequest::ListDirectory(helper.target("."));
    loop {
        let reply = helper.client.request(request, &[]).await?;
        let RemoteResponse::Directory(page) = reply.response else {
            anyhow::bail!("expected directory page");
        };
        listed += page.entries.len();
        match page.next_cursor {
            Some(cursor) => request = RemoteRequest::ContinueDirectory { cursor },
            None => break,
        }
    }
    ensure!(listed == 1000);
    support::heartbeat(&helper.client).await?;
    helper
        .client
        .request(RemoteRequest::Stat(helper.target(".")), &[])
        .await?;
    helper.reconnect(executable, owner_pid).await?;
    stdin.write_all(b"once\n").await?;
    drop(stdin);
    let (read, exit) = tokio::join!(
        async {
            let mut text = String::new();
            output.read_to_string(&mut text).await?;
            anyhow::Ok(text)
        },
        gated.wait()
    );
    ensure!(read? == "received:once\n");
    ensure!(exit.map_err(anyhow::Error::msg)?.exit_code == Some(0));
    println!(
        "{}",
        serde_json::json!({"scenario":"directory-and-command-reattach", "entries":listed, "sameHelper":true, "duplicateOutput":false})
    );

    // Occupy one command's output while unrelated commands and controls continue.
    let mut slow = helper
        .command(
            "slow-output",
            "printf 'started\\n'; head -c 8000000 /dev/zero",
        )
        .await?;
    drop(slow.take_stdin());
    let mut blocked_output = slow.take_stdout().context("slow stdout")?;
    let mut marker = [0; 8];
    blocked_output.read_exact(&mut marker).await?;
    ensure!(&marker == b"started\n");
    let mut silent = helper.command("silent", "sleep 120").await?;
    let mut input_blocked = helper
        .command("blocked-input", "printf 'ready\\n'; sleep 120")
        .await?;
    let mut input_ready = BufReader::new(
        input_blocked
            .take_stdout()
            .context("blocked stdin stdout")?,
    );
    let mut marker = String::new();
    input_ready.read_line(&mut marker).await?;
    ensure!(marker == "ready\n");
    let mut blocked_stdin = input_blocked.take_stdin().context("blocked stdin")?;
    let input_bytes = vec![0x5a; 4 * 1024 * 1024];
    let pending_input = blocked_stdin.write_all(&input_bytes);
    tokio::pin!(pending_input);
    ensure!(
        futures::poll!(&mut pending_input).is_pending(),
        "input fixture did not reach backpressure"
    );
    let control_started = Instant::now();
    support::heartbeat(&helper.client).await?;
    let heartbeat_ms = control_started.elapsed().as_secs_f64() * 1000.0;
    let stat_started = Instant::now();
    helper
        .client
        .request(RemoteRequest::Stat(helper.target(".")), &[])
        .await?;
    let stat_ms = stat_started.elapsed().as_secs_f64() * 1000.0;
    let quick_started = Instant::now();
    let (quick, _) = tokio::time::timeout(
        Duration::from_secs(10),
        support::drain(helper.command("quick", "printf quick").await?),
    )
    .await??;
    ensure!(quick == b"quick");
    let quick_ms = quick_started.elapsed().as_secs_f64() * 1000.0;
    let cancellation_started = Instant::now();
    input_blocked.cancellation().cancel();
    silent.cancellation().cancel();
    let (input_result, blocked_exit, silent_exit) =
        tokio::join!(pending_input, input_blocked.wait(), silent.wait());
    ensure!(
        input_result.is_err(),
        "cancelled blocked input was reported fully written"
    );
    blocked_exit.map_err(anyhow::Error::msg)?;
    silent_exit.map_err(anyhow::Error::msg)?;
    slow.cancellation().cancel();
    let mut discarded_output = tokio::io::sink();
    let (drained, exit) = tokio::join!(
        tokio::io::copy(&mut blocked_output, &mut discarded_output),
        slow.wait()
    );
    drained?;
    exit.map_err(anyhow::Error::msg)?;
    println!(
        "{}",
        serde_json::json!({"scenario":"slow-consumer-isolation", "heartbeatMs":heartbeat_ms,
        "statMs":stat_ms, "quickCommandMs":quick_ms, "cancellationAndDrainMs":cancellation_started.elapsed().as_secs_f64()*1000.0,
        "controlAndCancellationMs":control_started.elapsed().as_secs_f64()*1000.0})
    );

    // One immutable binary source is transferred in ranges, with a real transport replacement.
    let payload = (0..(32 * 1024 * 1024 + 17))
        .map(|index| (index % 251) as u8)
        .collect::<Vec<_>>();
    support::write_file(&helper.client, helper.target("transfer.bin"), &payload).await?;
    let opened = helper
        .client
        .request(RemoteRequest::OpenRead(helper.target("transfer.bin")), &[])
        .await?;
    let RemoteResponse::Transfer(file) = opened.response else {
        anyhow::bail!("expected read handle");
    };
    let mut offset = 0;
    let mut digest = sha2::Sha256::new();
    use sha2::Digest;
    let transfer_started = Instant::now();
    let mut reattached = false;
    let mut recovery_ms = 0.0;
    while offset < payload.len() {
        if !reattached && offset >= payload.len() / 2 {
            let recovery_started = Instant::now();
            helper.reconnect(executable, owner_pid).await?;
            recovery_ms = recovery_started.elapsed().as_secs_f64() * 1000.0;
            reattached = true;
        }
        let reply = helper
            .client
            .request(
                RemoteRequest::ReadFileChunk {
                    transfer_id: file.transfer_id.clone(),
                    offset: offset as u64,
                    max_bytes: helper.client.fragment_bytes(),
                },
                &[],
            )
            .await?;
        ensure!(!reply.body.is_empty());
        ensure!(reply.body.as_ref() == &payload[offset..offset + reply.body.len()]);
        digest.update(&reply.body);
        offset += reply.body.len();
    }
    ensure!(Some(hex::encode(digest.finalize())) == file.sha256);
    helper
        .client
        .request(
            RemoteRequest::CloseTransfer {
                transfer_id: file.transfer_id,
            },
            &[],
        )
        .await?;
    println!(
        "{}",
        serde_json::json!({"scenario":"binary-reattach", "bytes":offset, "seconds":transfer_started.elapsed().as_secs_f64(), "recoveryMs":recovery_ms, "sha256Match":true})
    );
    drop(payload);

    // Same binary, different grants; no rebuilding or editing capacities between runs.
    let before = support::heartbeat(&helper.client).await?.allocation;
    let mut smaller = before;
    smaller.resident_bytes /= 2;
    smaller.ordinary_operations = (smaller.ordinary_operations / 2).max(1);
    smaller.connection_window /= 2;
    smaller.stream_window = smaller.stream_window.min(smaller.connection_window / 3);
    helper
        .client
        .request(
            RemoteRequest::Configure {
                allocation: smaller,
            },
            &[],
        )
        .await?;
    ensure!(
        support::heartbeat(&helper.client)
            .await?
            .allocation
            .resident_bytes
            <= smaller.resident_bytes
    );
    let (output, _) =
        support::drain(helper.command("under-pressure", "printf progress").await?).await?;
    ensure!(output == b"progress");
    println!(
        "{}",
        serde_json::json!({"scenario":"resource-shrink", "before":before,
        "helper":support::heartbeat(&helper.client).await?, "resources":support::resources(owner_pid),
        "host":support::resources(std::process::id())})
    );
    helper
        .client
        .request(RemoteRequest::Configure { allocation: before }, &[])
        .await?;
    println!(
        "{}",
        serde_json::json!({"scenario":"resource-restore", "helper":support::heartbeat(&helper.client).await?})
    );

    for index in 0..1000 {
        let path = helper.root.path().join(format!("workspace-{index}"));
        std::fs::create_dir(&path)?;
        let opened = helper
            .client
            .request(
                RemoteRequest::OpenWorkspace {
                    path: path.to_string_lossy().into_owned(),
                },
                &[],
            )
            .await?;
        let RemoteResponse::WorkspaceOpened(opened) = opened.response else {
            anyhow::bail!("expected workspace");
        };
        helper
            .client
            .request(
                RemoteRequest::CloseWorkspace {
                    workspace_id: opened.workspace_id,
                },
                &[],
            )
            .await?;
    }
    let idle_before = support::resources(owner_pid);
    let queries_before = support::heartbeat(&helper.client).await?.operation_queries;
    tokio::time::sleep(Duration::from_secs(15)).await;
    let final_state = support::heartbeat(&helper.client).await?;
    ensure!(
        final_state.operation_queries == queries_before,
        "normal idle waiting polled operation status"
    );
    println!(
        "{}",
        serde_json::json!({"scenario":"idle", "seconds":15, "before":idle_before,
        "after":support::resources(owner_pid), "businessStatusQueries":final_state.operation_queries-queries_before})
    );
    ensure!(
        final_state.workspaces == 1
            && final_state.processes == 0
            && final_state.cursors == 0
            && final_state.transfers == 0
            && final_state.retained_operations == 0,
        "resources retained: {final_state:?}"
    );
    println!(
        "{}",
        serde_json::json!({"scenario":"resource-release", "baseline":baseline, "final":support::resources(owner_pid),
        "hostBaseline":host_baseline, "hostFinal":support::resources(std::process::id()), "helper":final_state})
    );
    Ok(())
}
