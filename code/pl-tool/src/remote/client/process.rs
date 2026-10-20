//! One tracked owner from cancellable admission through physical exit and output drain.
use super::*;
use crate::command::{
    CommandCancellation, CommandCaptureReceipt, CommandExit, CommandIo, ManagedCommand,
};

struct ProcessJob {
    _workspace: Option<Arc<workspace::WorkspaceLease>>,
    request: RemoteSpawnRequest,
    stdin: DuplexStream,
    stdout: DuplexStream,
    stderr: DuplexStream,
    cancellation: CommandCancellation,
    started: oneshot::Sender<Result<(), RemoteClientError>>,
}

pub(super) async fn spawn(
    client: &RemoteClient,
    request: RemoteSpawnRequest,
    workspace: Option<Arc<workspace::WorkspaceLease>>,
) -> Result<ManagedCommand, RemoteClientError> {
    let (stdin, input) = tokio::io::duplex(64 * 1024);
    let (stdout, output) = tokio::io::duplex(64 * 1024);
    let (stderr, errors) = tokio::io::duplex(64 * 1024);
    let (started, startup) = oneshot::channel();
    let inner = client.inner.clone();
    let lifetime = client.transport.clone();
    let command = ManagedCommand::new(
        None,
        CommandIo {
            stdin: Some(Box::pin(stdin)),
            stdout: Some(Box::pin(stdout)),
            stderr: Some(Box::pin(stderr)),
        },
        move |cancellation| {
            let completion = inner.streams.spawn(supervise(
                inner.clone(),
                ProcessJob {
                    request,
                    stdin: input,
                    stdout: output,
                    stderr: errors,
                    cancellation,
                    started,
                    _workspace: workspace,
                },
            ));
            async move {
                let _lifetime = lifetime;
                completion
                    .await
                    .map_err(|error| format!("remote process supervisor failed: {error}"))?
            }
        },
    );
    startup
        .await
        .unwrap_or(Err(RemoteClientError::Disconnected))?;
    Ok(command)
}

async fn supervise(inner: Arc<RemoteClientInner>, job: ProcessJob) -> Result<CommandExit, String> {
    let ProcessJob {
        request,
        stdin,
        stdout,
        stderr,
        cancellation,
        started,
        _workspace,
    } = job;
    let process_id = request.process_id.clone();
    let expects_capture = matches!(
        request.capture,
        pl_protocol::remote::RemoteCapture::File { .. }
    );
    let (exit_sender, mut exit) = oneshot::channel();
    let (output, incoming) = mpsc::channel(REMOTE_OUTPUT_WINDOW);
    {
        let mut processes = inner.processes.lock().await;
        let error = if inner.disconnected.is_cancelled() {
            Some(RemoteClientError::Disconnected)
        } else if processes.contains_key(&process_id) {
            Some(RemoteClientError::Protocol(
                "process identity already registered".into(),
            ))
        } else {
            None
        };
        if let Some(error) = error {
            let reason = error.to_string();
            let _ = started.send(Err(error));
            return Err(reason);
        }
        processes.insert(
            process_id.clone(),
            RemoteProcessChannels {
                output: Some(output),
                exit: Some(exit_sender),
            },
        );
    }
    let discard = CancellationToken::new();
    let output = inner.streams.spawn(forward_output(
        inner.clone(),
        process_id.clone(),
        incoming,
        stdout,
        stderr,
        discard.clone(),
    ));
    let submitted = tokio::select! {
        biased;
        () = cancellation.cancelled() => Err(RemoteClientError::Cancelled),
        result = submit_request(&inner, RemoteRequest::Spawn(request), &[]) => result,
    };
    // After admission, keep the response even when cancellation arrives: Terminate
    // must never overtake an unacknowledged Spawn on the independent control queue.
    let startup = match submitted {
        Ok(response) => response
            .await
            .unwrap_or(Err(RemoteClientError::Disconnected)),
        Err(error) => Err(error),
    }
    .and_then(|reply| match reply.response {
        RemoteResponse::ProcessSpawned {
            process_id: spawned,
        } if spawned == process_id => Ok(()),
        response => {
            inner.disconnected.cancel();
            Err(RemoteClientError::Protocol(format!(
                "unexpected spawn response: {response:?}"
            )))
        }
    });
    if let Err(error) = startup {
        let reason = error.to_string();
        discard.cancel();
        inner.processes.lock().await.remove(&process_id);
        let _ = started.send(Err(error));
        output.await.map_err(|error| error.to_string())?;
        return Err(reason);
    }
    let _ = started.send(Ok(()));
    let stop_input = CancellationToken::new();
    let mut input = inner.streams.spawn(forward_stdin(
        inner.clone(),
        process_id.clone(),
        stdin,
        stop_input.clone(),
    ));
    let mut input_finished = false;
    let mut failure = None;
    let result = loop {
        tokio::select! {
            result = &mut exit => break result,
            () = cancellation.cancelled() => {
                discard.cancel();
                stop_input.cancel();
                let (termination, result) = tokio::join!(
                    request_inner(&inner, RemoteRequest::Terminate { process_id: process_id.clone() }, &[]), &mut exit,
                );
                if let Err(error) = termination { failure = Some(error.to_string()); }
                break result;
            },
            result = &mut input, if !input_finished => {
                input_finished = true;
                let error = match result { Ok(Ok(())) => None, Ok(Err(error)) => Some(error.to_string()), Err(error) => Some(error.to_string()) };
                if let Some(error) = error {
                    failure = Some(error);
                    discard.cancel();
                    let (_, result) = tokio::join!(
                        request_inner(&inner, RemoteRequest::Terminate { process_id: process_id.clone() }, &[]), &mut exit,
                    );
                    break result;
                }
            }
        }
    };
    stop_input.cancel();
    if !input_finished {
        match input.await {
            Ok(Ok(())) => {}
            Ok(Err(error)) => {
                failure.get_or_insert(error.to_string());
            }
            Err(error) => {
                failure.get_or_insert(error.to_string());
            }
        }
    }
    tokio::pin!(output);
    let drained = tokio::select! {
        result = &mut output => result,
        () = cancellation.cancelled() => {
            discard.cancel();
            output.await
        },
    };
    inner.processes.lock().await.remove(&process_id);
    if let Some(error) = failure {
        return Err(error);
    }
    drained.map_err(|error| format!("remote output task failed: {error}"))?;
    let exit = result
        .map_err(|_| "remote process exit channel closed".to_string())?
        .map_err(|error| error.to_string())?;
    if exit.capture.is_some() != expects_capture {
        return Err("capture receipt does not match spawn policy".into());
    }
    Ok(CommandExit {
        exit_code: exit.exit_code,
        capture: exit.capture.map(|receipt| CommandCaptureReceipt {
            limit_bytes: receipt.limit_bytes,
            committed_len: receipt.charged_bytes,
            charged_bytes: receipt.charged_bytes,
            refused_bytes: receipt.refused_bytes,
        }),
    })
}

async fn forward_stdin(
    inner: Arc<RemoteClientInner>,
    process_id: String,
    mut input: DuplexStream,
    stop: CancellationToken,
) -> Result<(), RemoteClientError> {
    let mut bytes = [0; 8192];
    loop {
        let response = tokio::select! {
            biased;
            () = stop.cancelled() => return Ok(()),
            result = async {
                let count = input.read(&mut bytes).await?;
                let request = if count == 0 { RemoteRequest::CloseStdin { process_id: process_id.clone() } }
                    else { RemoteRequest::WriteStdin { process_id: process_id.clone() } };
                Ok::<_, RemoteClientError>((count, submit_request(&inner, request, &bytes[..count]).await?))
            } => result?,
        };
        let (count, response) = response;
        // A response already delivered before ProcessExit keeps its original error.
        // An unacknowledged stdin request must not retain the process after exit.
        tokio::select! {
            biased;
            result = response => expect_ack(result.unwrap_or(Err(RemoteClientError::Disconnected))?)?,
            () = stop.cancelled() => return Ok(()),
        }
        if count == 0 {
            return Ok(());
        }
    }
}
