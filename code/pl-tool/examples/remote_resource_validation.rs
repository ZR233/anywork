//! Real HTTP/2 helper acceptance. Explicit opt-in, outside the automated library test gate.
#[path = "support/remote_receipts.rs"]
mod receipts;
#[path = "support/remote.rs"]
mod support;
use anyhow::{Context, ensure};
use pl_protocol::remote::*;
use std::{
    path::PathBuf,
    time::{Duration, Instant},
};
use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let executable = std::env::args()
        .nth(1)
        .map(PathBuf::from)
        .context("usage: remote_resource_validation HELPER [OPERATIONS]")?;
    let operations = std::env::args()
        .nth(2)
        .map(|v| v.parse())
        .transpose()?
        .unwrap_or(10_000);
    ensure!(operations > 0, "operation count must be positive");
    verify_budget_progress().await?;
    receipts::verify(&executable).await?;
    let mut helper = support::Helper::start(&executable).await?;
    let outcome = exercise(&mut helper, operations).await;
    let close = helper.close().await;
    outcome?;
    close?;
    support::Helper::start(&executable)
        .await?
        .close_during_attachment()
        .await?;
    #[cfg(target_os = "linux")]
    {
        let expiring = support::Helper::start(&executable).await?;
        let mut command = expiring
            .command("lease-owned", "printf 'ready\\n'; sleep 120")
            .await?;
        let mut output = BufReader::new(command.take_stdout().context("lease stdout")?);
        let mut ready = String::new();
        output.read_line(&mut ready).await?;
        ensure!(ready == "ready\n");
        expiring.expire().await?;
        ensure!(
            !matches!(command.wait().await, Ok(exit) if exit.exit_code == Some(0)),
            "expired physical command was reported successful"
        );
    }
    println!("REMOTE_RESOURCE_ACCEPTANCE=PASS");
    Ok(())
}
async fn exercise(helper: &mut support::Helper, operations: usize) -> anyhow::Result<()> {
    let initial = support::heartbeat(&helper.client).await?;
    let baseline = support::resources(helper.owner_pid);
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
    helper.reconnect().await?;
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
            helper.reconnect().await?;
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
        "helper":support::heartbeat(&helper.client).await?, "resources":support::resources(helper.owner_pid),
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

    for parallelism in [1_usize, 32, 128, 512] {
        use futures::{StreamExt, stream};
        let mut samples = stream::iter(0..operations)
            .map(|_| {
                let target = helper.target("transfer.bin");
                let client = helper.client.clone();
                async move {
                    let start = Instant::now();
                    let reply = client.request(RemoteRequest::Stat(target), &[]).await?;
                    Ok::<_, pl_tool::remote::RemoteClientError>((
                        start.elapsed().as_secs_f64() * 1000.0,
                        reply.timing,
                    ))
                }
            })
            .buffer_unordered(parallelism);
        let start = Instant::now();
        let mut durations = Vec::new();
        let mut phases = [
            Vec::new(),
            Vec::new(),
            Vec::new(),
            Vec::new(),
            Vec::new(),
            Vec::new(),
        ];
        while let Some(result) = samples.next().await {
            let (elapsed, timing) = result?;
            durations.push(elapsed);
            for (phase, value) in phases.iter_mut().zip([
                timing.admission_wait_micros,
                timing.remote.admission_wait_micros,
                timing.remote.execution_micros,
                timing.remote.filesystem_micros,
                timing.remote.transfer_backpressure_micros,
                timing.cleanup_micros,
            ]) {
                phase.push(value);
            }
        }
        for phase in &mut phases {
            phase.sort_unstable();
        }
        let phases = ["hostAdmission", "helperAdmission", "execution", "filesystem", "flowControlWait", "receiptRelease"].into_iter()
            .zip(phases).map(|(name, values)| (name.to_owned(), serde_json::json!({"p50Us":values[(values.len()-1)/2], "p95Us":values[(values.len()-1)*95/100], "p99Us":values[(values.len()-1)*99/100]})))
            .collect::<serde_json::Map<_, _>>();
        durations.sort_by(f64::total_cmp);
        let percentile =
            |percent: usize| durations[(durations.len().saturating_sub(1) * percent) / 100];
        println!(
            "{}",
            serde_json::json!({"scenario":"concurrent-stat", "parallelism":parallelism, "operations":operations,
            "seconds":start.elapsed().as_secs_f64(), "p50Ms":percentile(50), "p95Ms":percentile(95), "p99Ms":percentile(99), "phaseDurations":phases,
            "resources":support::resources(helper.owner_pid), "host":support::resources(std::process::id()), "helper":support::heartbeat(&helper.client).await?})
        );
    }
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
    let idle_before = support::resources(helper.owner_pid);
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
        "after":support::resources(helper.owner_pid), "businessStatusQueries":final_state.operation_queries-queries_before})
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
        serde_json::json!({"scenario":"resource-release", "baseline":baseline, "final":support::resources(helper.owner_pid),
        "hostBaseline":host_baseline, "hostFinal":support::resources(std::process::id()), "helper":final_state})
    );
    Ok(())
}

async fn verify_budget_progress() -> anyhow::Result<()> {
    use pl_remote_helper::budget::{FRAME_BYTES, ResourceBudget, ResourcePolicy};
    use tokio_util::sync::CancellationToken;
    let allocation = ResourcePolicy {
        available_memory_divisor: 16,
        resident_ceiling: Some(FRAME_BYTES * 64),
    }
    .allocation()?;
    let budget = ResourceBudget::new(allocation)?;
    let stop = CancellationToken::new();
    let occupied = budget
        .try_reserve(allocation.resident_bytes / 2)
        .context("initial reservation")?;
    let large = budget.reserve(allocation.resident_bytes * 3 / 4, &stop);
    tokio::pin!(large);
    ensure!(futures::poll!(&mut large).is_pending());
    let small =
        tokio::time::timeout(Duration::from_secs(5), budget.reserve(FRAME_BYTES, &stop)).await??;
    drop(occupied);
    let admitted = tokio::time::timeout(Duration::from_secs(5), large).await??;
    drop(admitted);
    drop(small);
    ensure!(budget.usage().0 == 0);
    // A full exchange pool must still admit a lightweight wait intent in the runtime budget.
    let controls = ResourceBudget::new(allocation)?;
    let occupied_controls = controls
        .try_reserve(allocation.resident_bytes)
        .context("full control pool")?;
    let waiting_control = controls.reserve_with_intent(FRAME_BYTES, &stop, &budget);
    tokio::pin!(waiting_control);
    ensure!(futures::poll!(&mut waiting_control).is_pending());
    ensure!(budget.usage().0 > 0 && controls.usage().0 == allocation.resident_bytes);
    drop(occupied_controls);
    drop(tokio::time::timeout(Duration::from_secs(5), waiting_control).await??);
    ensure!(budget.usage().0 == 0 && controls.usage().0 == 0);
    let occupied = budget
        .try_reserve(allocation.resident_bytes / 2)
        .context("shrink reservation")?;
    let waiting = budget.reserve(allocation.resident_bytes * 3 / 4, &stop);
    tokio::pin!(waiting);
    ensure!(futures::poll!(&mut waiting).is_pending());
    let mut reduced = allocation;
    reduced.resident_bytes /= 2;
    budget.resize(reduced)?;
    ensure!(
        waiting.await.is_err(),
        "oversized intent survived an incompatible resource shrink"
    );
    drop(occupied);
    budget.resize(allocation)?;
    stop.cancel();
    ensure!(budget.reserve(FRAME_BYTES, &stop).await.is_err());
    ensure!(budget.usage().0 == 0, "cancelled intents retained bytes");
    println!("RESOURCE_ADMISSION_PROGRESS=PASS");
    Ok(())
}
