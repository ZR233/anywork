//! Explicit, deterministic transport acceptance; not part of the automatic test gate.
use anyhow::{Context, ensure};
use pl_protocol::remote::{
    RemoteCapture, RemoteError, RemoteErrorCode, RemoteEvent, RemoteOutputStream,
    RemoteProcessExit, RemoteProcessOutput, RemoteSpawnRequest,
};
use pl_protocol::remote::{
    RemoteFrameHeader, RemoteMessage, RemotePathRequest, RemoteRequest, RemoteResponse,
};
use pl_tool::remote::RemoteClient;
use tokio::io::{AsyncReadExt, AsyncWriteExt, DuplexStream};

async fn send(
    stream: &mut DuplexStream,
    request_id: Option<u64>,
    message: RemoteMessage,
    body: &[u8],
) -> anyhow::Result<()> {
    let bytes = serde_json::to_vec(&RemoteFrameHeader {
        request_id,
        message,
        body_len: body.len(),
    })?;
    stream.write_u32(bytes.len().try_into()?).await?;
    stream.write_all(&bytes).await?;
    stream.write_all(body).await?;
    stream.flush().await?;
    Ok(())
}

fn spawn_request() -> RemoteSpawnRequest {
    RemoteSpawnRequest {
        process_id: "controlled".into(),
        workspace_id: "acceptance".into(),
        command: "synthetic".into(),
        cwd: ".".into(),
        environment: Default::default(),
        capture: RemoteCapture::None,
    }
}
async fn spawned(peer: &mut DuplexStream, id: Option<u64>) -> anyhow::Result<()> {
    send(
        peer,
        id,
        RemoteMessage::Response(RemoteResponse::ProcessSpawned {
            process_id: "controlled".into(),
        }),
        &[],
    )
    .await
}
async fn exited(peer: &mut DuplexStream) -> anyhow::Result<()> {
    send(
        peer,
        None,
        RemoteMessage::Event(RemoteEvent::ProcessExit(RemoteProcessExit {
            process_id: "controlled".into(),
            exit_code: Some(0),
            signal: None,
            failure: None,
            capture: None,
        })),
        &[],
    )
    .await
}

async fn process_lifetime() -> anyhow::Result<()> {
    // Hold startup after actual submission, cancel the caller, and prove Terminate cannot overtake it.
    let (transport, mut peer) = tokio::io::duplex(256 * 1024);
    let (reader, writer) = tokio::io::split(transport);
    let client = RemoteClient::from_streams(reader, writer);
    let mut opening = Box::pin(client.spawn_process(spawn_request()));
    ensure!(futures::poll!(&mut opening).is_pending());
    let start = receive(&mut peer).await?;
    ensure!(matches!(
        start.message,
        RemoteMessage::Request(RemoteRequest::Spawn(_))
    ));
    drop(opening);
    ensure!(
        tokio::time::timeout(std::time::Duration::from_millis(50), peer.read_u8())
            .await
            .is_err(),
        "termination overtook unacknowledged startup"
    );
    spawned(&mut peer, start.request_id).await?;
    loop {
        let frame = receive(&mut peer).await?;
        acknowledge(&mut peer, frame.request_id).await?;
        if matches!(
            frame.message,
            RemoteMessage::Request(RemoteRequest::Terminate { .. })
        ) {
            break;
        }
    }
    exited(&mut peer).await?;
    client.close().await?;
    println!(
        "startup: submission -> caller cancellation -> startup result -> terminate -> exit PASS"
    );

    // Input rejection and exit are delivered together, before the input task can resume.
    let (transport, mut peer) = tokio::io::duplex(256 * 1024);
    let (reader, writer) = tokio::io::split(transport);
    let client = RemoteClient::from_streams(reader, writer);
    let opening = client.spawn_process(spawn_request());
    tokio::pin!(opening);
    let (poll, start) = tokio::join!(
        async {
            ensure!(futures::poll!(&mut opening).is_pending());
            anyhow::Ok(())
        },
        receive(&mut peer)
    );
    poll?;
    let start = start?;
    spawned(&mut peer, start.request_id).await?;
    let mut command = opening.await?;
    command.take_stdin().unwrap().write_all(b"input").await?;
    let input = receive(&mut peer).await?;
    send(
        &mut peer,
        input.request_id,
        RemoteMessage::Response(RemoteResponse::Error(RemoteError {
            code: RemoteErrorCode::Io,
            message: "synthetic input rejected".into(),
        })),
        &[],
    )
    .await?;
    exited(&mut peer).await?;
    let peer_task = tokio::spawn(async move {
        while let Ok(frame) = receive(&mut peer).await {
            if frame.request_id.is_some() {
                acknowledge(&mut peer, frame.request_id).await?;
            }
        }
        anyhow::Ok(())
    });
    let error = command
        .wait()
        .await
        .expect_err("stdin error was swallowed by exit cleanup");
    ensure!(
        error.contains("synthetic input rejected"),
        "original stdin failure lost: {error}"
    );
    client.close().await?;
    peer_task.await??;
    println!("input: rejection survives immediate exit and cleanup PASS");

    // Exit can precede local output drain. Dropping the external command must still release it.
    let (transport, mut peer) = tokio::io::duplex(256 * 1024);
    let (reader, writer) = tokio::io::split(transport);
    let client = RemoteClient::from_streams(reader, writer);
    let mut opening = Box::pin(client.spawn_process(spawn_request()));
    ensure!(futures::poll!(&mut opening).is_pending());
    let start = receive(&mut peer).await?;
    spawned(&mut peer, start.request_id).await?;
    let mut command = opening.await?;
    let _unread = command.take_stdout();
    for sequence in 1..=8 {
        send(
            &mut peer,
            None,
            RemoteMessage::Event(RemoteEvent::ProcessOutput(RemoteProcessOutput {
                process_id: "controlled".into(),
                sequence,
                stream: RemoteOutputStream::Stdout,
            })),
            &[b'x'; 8192],
        )
        .await?;
    }
    // Observe credit before supplying more than the consumer's 64 KiB buffer.
    loop {
        if matches!(
            receive(&mut peer).await?.message,
            RemoteMessage::Request(RemoteRequest::OutputConsumed { .. })
        ) {
            break;
        }
    }
    send(
        &mut peer,
        None,
        RemoteMessage::Event(RemoteEvent::ProcessOutput(RemoteProcessOutput {
            process_id: "controlled".into(),
            sequence: 9,
            stream: RemoteOutputStream::Stdout,
        })),
        &[b'x'; 8192],
    )
    .await?;
    exited(&mut peer).await?;
    let peer_task = tokio::spawn(async move {
        while let Ok(frame) = receive(&mut peer).await {
            if frame.request_id.is_some() {
                acknowledge(&mut peer, frame.request_id).await?;
            }
        }
        anyhow::Ok(())
    });
    command.cancellation().cancel();
    command.wait().await.map_err(anyhow::Error::msg)?;
    drop(command);
    drop(client);
    peer_task.await??;
    println!("output: unread stream after exit, dropped external owners and transport EOF PASS");

    let (transport, mut peer) = tokio::io::duplex(256 * 1024);
    let (reader, writer) = tokio::io::split(transport);
    let client = RemoteClient::from_streams(reader, writer);
    let mut opening = Box::pin(client.spawn_process(spawn_request()));
    ensure!(futures::poll!(&mut opening).is_pending());
    let start = receive(&mut peer).await?;
    spawned(&mut peer, start.request_id).await?;
    let mut command = opening.await?;
    drop(command.take_stdin());
    let input = receive(&mut peer).await?;
    ensure!(matches!(
        input.message,
        RemoteMessage::Request(RemoteRequest::CloseStdin { .. })
    ));
    // Deliberately omit the stdin acknowledgement; exit must release its waiter.
    exited(&mut peer).await?;
    drop(client);
    command.wait().await.map_err(anyhow::Error::msg)?;
    ensure!(
        peer.read_u8().await.is_err(),
        "internal process tasks retained the external connection lifetime"
    );
    println!("owners: unacknowledged stdin, process exit and final external owner release PASS");
    Ok(())
}

async fn receive(stream: &mut DuplexStream) -> anyhow::Result<RemoteFrameHeader> {
    let length = stream.read_u32().await? as usize;
    ensure!(length <= pl_protocol::remote::REMOTE_MAX_HEADER_BYTES);
    let mut bytes = vec![0; length];
    stream.read_exact(&mut bytes).await?;
    let header: RemoteFrameHeader = serde_json::from_slice(&bytes)?;
    ensure!(header.body_len <= pl_protocol::remote::REMOTE_MAX_BODY_BYTES);
    let mut body = vec![0; header.body_len];
    stream.read_exact(&mut body).await?;
    Ok(header)
}

async fn acknowledge(stream: &mut DuplexStream, request_id: Option<u64>) -> anyhow::Result<()> {
    let bytes = serde_json::to_vec(&RemoteFrameHeader {
        request_id,
        message: RemoteMessage::Response(RemoteResponse::Ack),
        body_len: 0,
    })?;
    stream.write_u32(bytes.len().try_into()?).await?;
    stream.write_all(&bytes).await?;
    stream.flush().await?;
    Ok(())
}

fn ordinary() -> RemoteRequest {
    RemoteRequest::Stat(RemotePathRequest {
        workspace_id: "acceptance".into(),
        path: ".".into(),
    })
}

async fn capacity() -> anyhow::Result<()> {
    let (transport, mut peer) = tokio::io::duplex(64 * 1024);
    let (reader, writer) = tokio::io::split(transport);
    let client = RemoteClient::from_streams(reader, writer);
    let (full, filled) = tokio::sync::oneshot::channel();
    let (release, released) = tokio::sync::oneshot::channel();
    let peer_task = tokio::spawn(async move {
        let mut pending = Vec::new();
        for _ in 0..32 {
            pending.push(receive(&mut peer).await?.request_id);
        }
        full.send(())
            .map_err(|_| anyhow::anyhow!("acceptance owner exited"))?;
        let heartbeat = receive(&mut peer).await?;
        ensure!(
            matches!(
                heartbeat.message,
                RemoteMessage::Request(RemoteRequest::Heartbeat)
            ),
            "ordinary request exceeded capacity"
        );
        acknowledge(&mut peer, heartbeat.request_id).await?;
        released.await?;
        acknowledge(&mut peer, pending.remove(0)).await?;
        pending.push(receive(&mut peer).await?.request_id);
        for request in pending {
            acknowledge(&mut peer, request).await?;
        }
        let mut byte = [0];
        ensure!(peer.read(&mut byte).await? == 0, "transport did not close");
        anyhow::Ok(())
    });
    let mut requests = tokio::task::JoinSet::new();
    for _ in 0..32 {
        let client = client.clone();
        requests.spawn(async move { client.request(ordinary(), &[]).await });
    }
    filled.await?;
    let mut cancelled = Box::pin(client.request(ordinary(), &[]));
    ensure!(
        futures::poll!(&mut cancelled).is_pending(),
        "full transport rejected a request instead of waiting"
    );
    drop(cancelled);
    let mut next = Box::pin(client.request(ordinary(), &[]));
    ensure!(
        futures::poll!(&mut next).is_pending(),
        "33rd request was not waiting"
    );
    client.request(RemoteRequest::Heartbeat, &[]).await?;
    release
        .send(())
        .map_err(|_| anyhow::anyhow!("peer exited"))?;
    next.await?;
    while let Some(result) = requests.join_next().await {
        result??;
    }
    client.close().await?;
    peer_task.await??;
    println!(
        "capacity: 32 outstanding, cancellable 33rd, independent heartbeat, response release and close PASS"
    );
    Ok(())
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tokio::time::timeout(std::time::Duration::from_secs(15), capacity())
        .await
        .context("transport acceptance did not settle")??;
    tokio::time::timeout(std::time::Duration::from_secs(15), process_lifetime())
        .await
        .context("process acceptance did not settle")??;
    Ok(())
}
