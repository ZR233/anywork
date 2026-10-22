//! Owned command supervision over independent HTTP/2 output streams.
use super::*;
use crate::command::{
    CommandCancellation, CommandCaptureReceipt, CommandExit, CommandIo, ManagedCommand,
};
use base64::{Engine, engine::general_purpose::STANDARD};
use eventsource_stream::Eventsource;
use futures::StreamExt;
use tokio::io::{AsyncReadExt, AsyncWriteExt, DuplexStream};

pub(super) async fn spawn(
    client: &RemoteClient,
    request: RemoteSpawnRequest,
    workspace: Option<Arc<workspace::WorkspaceLease>>,
) -> Result<ManagedCommand, RemoteClientError> {
    if client.is_closing() {
        return Err(RemoteClientError::Disconnected);
    }
    let process_slot = client
        .inner
        .process_slots
        .acquire(&client.inner.stopped)
        .await?;
    let quantum = client.fragment_bytes();
    let framing = base64::encoded_len(quantum, true)
        .unwrap_or(usize::MAX)
        .saturating_add(std::mem::size_of::<RemoteOutputRecord>());
    let (_, startup_cost, startup_reply) =
        request_cost(&client.inner, &RemoteRequest::Spawn(request.clone()), 0)?;
    let (_, input_cost, _) = request_cost(
        &client.inner,
        &RemoteRequest::WriteStdin {
            process_id: request.process_id.clone(),
            offset: u64::MAX,
        },
        quantum,
    )?;
    // IO, startup and the next input exchange are one reservation. No command can consume
    // all host memory and then wait for a second reservation required to make progress.
    let memory = Arc::new(
        client
            .inner
            .budget
            .reserve(
                quantum
                    .saturating_mul(4)
                    .saturating_add(framing)
                    .saturating_add(startup_cost.max(input_cost)),
                &client.inner.stopped,
            )
            .await?,
    );
    let (stdin, input) = tokio::io::duplex(quantum);
    let (stdout, output) = tokio::io::duplex(quantum);
    let (stderr, errors) = tokio::io::duplex(quantum);
    let (started, startup) = oneshot::channel();
    let inner = client.inner.clone();
    let lifetime = client.lifetime.clone();
    let command = ManagedCommand::new(
        None,
        CommandIo {
            stdin: Some(Box::pin(stdin)),
            stdout: Some(Box::pin(stdout)),
            stderr: Some(Box::pin(stderr)),
        },
        move |cancellation| {
            let owner = inner.clone();
            let task = inner.streams.spawn(async move {
                let _process_slot = process_slot;
                let _workspace = workspace;
                supervise(
                    owner,
                    request,
                    CommandStreams {
                        input,
                        output,
                        errors,
                        memory,
                        quantum,
                        startup_reply,
                    },
                    cancellation,
                    started,
                )
                .await
            });
            async move {
                let _lifetime = lifetime;
                task.await
                    .map_err(|e| format!("remote process supervisor: {e}"))?
            }
        },
    );
    startup
        .await
        .unwrap_or(Err(RemoteClientError::Disconnected))?;
    Ok(command)
}

struct CommandStreams {
    input: DuplexStream,
    output: DuplexStream,
    errors: DuplexStream,
    memory: Arc<pl_remote_helper::budget::ByteLease>,
    quantum: usize,
    startup_reply: usize,
}

async fn supervise(
    inner: Arc<RemoteClientInner>,
    request: RemoteSpawnRequest,
    streams: CommandStreams,
    cancellation: CommandCancellation,
    started: oneshot::Sender<Result<(), RemoteClientError>>,
) -> Result<CommandExit, String> {
    let CommandStreams {
        input,
        output,
        errors,
        memory,
        quantum,
        startup_reply,
    } = streams;
    let id = request.process_id.clone();
    let expects_capture = matches!(request.capture, RemoteCapture::File { .. });
    let result = if cancellation.is_cancelled() {
        Err(RemoteClientError::Cancelled)
    } else {
        submit_reserved(
            &inner,
            RemoteRequest::Spawn(request),
            Bytes::new(),
            None,
            ReplyMemory::Shared {
                _lease: memory.clone(),
            },
            startup_reply,
            0,
        )
        .await
        .unwrap_or(Err(RemoteClientError::Disconnected))
    }
    .and_then(|reply| match reply.response {
        RemoteResponse::ProcessSpawned { process_id } if process_id == id => Ok(()),
        response => Err(response_error(response)),
    });
    if let Err(error) = result {
        let reason = error.to_string();
        let _ = started.send(Err(error));
        let _ = request_inner(
            &inner,
            RemoteRequest::ReleaseProcess { process_id: id },
            &[],
        )
        .await;
        return Err(reason);
    }
    let _ = started.send(Ok(()));
    let stop_input = CancellationToken::new();
    let stdin_owner = inner.clone();
    let input_id = id.clone();
    let input_stop = stop_input.clone();
    let input_memory = memory.clone();
    let mut input = inner.streams.spawn(async move {
        forward_input(
            &stdin_owner,
            &input_id,
            input,
            &input_stop,
            input_memory,
            quantum,
        )
        .await
    });
    let output_owner = inner.clone();
    let output_id = id.clone();
    let output_cancel = cancellation.clone();
    let mut output = inner.streams.spawn(async move {
        forward_output(&output_owner, &output_id, output, errors, &output_cancel).await
    });
    let mut input_finished = false;
    let mut terminating = false;
    let mut failure = None;
    let exit = loop {
        tokio::select! {
            result = &mut output => break result.map_err(|e| e.to_string())?,
            _ = cancellation.cancelled(), if !terminating => {
                terminating = true;
                stop_input.cancel();
                // Termination never waits for the stdin mutex or for business output consumption.
                if let Err(error) = request_inner(&inner, RemoteRequest::Terminate { process_id: id.clone() }, &[]).await { failure = Some(error.to_string()); }
            }
            result = &mut input, if !input_finished => {
                input_finished = true;
                let error = match result { Ok(Ok(())) => None, Ok(Err(error)) => Some(error.to_string()), Err(error) => Some(error.to_string()) };
                if let Some(error) = error {
                    failure = Some(error);
                    terminating = true;
                    stop_input.cancel();
                    let _ = request_inner(&inner, RemoteRequest::Terminate { process_id: id.clone() }, &[]).await;
                }
            }
        }
    };
    stop_input.cancel();
    if !input_finished {
        let _ = input.await;
    }
    let exit = match exit {
        Ok(exit) => exit,
        Err(error) => {
            let _ = request_inner(
                &inner,
                RemoteRequest::Terminate {
                    process_id: id.clone(),
                },
                &[],
            )
            .await;
            let settled = wait_process(&inner, id.clone()).await;
            let release = match settled {
                Ok(_) => {
                    request_inner(
                        &inner,
                        RemoteRequest::ReleaseProcess { process_id: id },
                        &[],
                    )
                    .await
                }
                Err(error) => Err(error),
            };
            return Err(match release {
                Ok(_) => error.to_string(),
                Err(release) => format!("{error}; process release: {release}"),
            });
        }
    };
    request_inner(
        &inner,
        RemoteRequest::ReleaseProcess { process_id: id },
        &[],
    )
    .await
    .map_err(|e| e.to_string())?;
    if let Some(error) = failure {
        return Err(error);
    }
    if let Some(error) = exit.failure {
        return Err(format!(
            "remote command failed ({:?}): {}",
            error.code, error.message
        ));
    }
    if exit.capture.is_some() != expects_capture {
        return Err("capture receipt does not match command policy".into());
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

async fn forward_input(
    inner: &Arc<RemoteClientInner>,
    id: &str,
    mut input: DuplexStream,
    stop: &CancellationToken,
    memory: Arc<pl_remote_helper::budget::ByteLease>,
    quantum: usize,
) -> Result<(), RemoteClientError> {
    let mut offset = 0;
    loop {
        let mut bytes = vec![0; quantum];
        let count = tokio::select! {
            _ = stop.cancelled() => return Ok(()),
            count = input.read(&mut bytes) => count?,
        };
        let request = if count == 0 {
            RemoteRequest::CloseStdin {
                process_id: id.to_owned(),
            }
        } else {
            RemoteRequest::WriteStdin {
                process_id: id.to_owned(),
                offset,
            }
        };
        let (_, _, reply_limit) = request_cost(inner, &request, count)?;
        bytes.truncate(count);
        let response = submit_reserved(
            inner,
            request,
            Bytes::from(bytes),
            None,
            ReplyMemory::Shared {
                _lease: memory.clone(),
            },
            reply_limit,
            0,
        );
        let reply = tokio::select! {
            reply = response => reply.unwrap_or(Err(RemoteClientError::Disconnected))?,
            _ = stop.cancelled() => return Ok(()),
        };
        if count == 0 {
            return expect_ack(reply);
        }
        let RemoteResponse::InputOffset { offset: confirmed } = reply.response else {
            return Err(response_error(reply.response));
        };
        if confirmed != offset + count as u64 {
            return Err(RemoteClientError::Protocol(
                "stdin acknowledgement offset is inconsistent".into(),
            ));
        }
        offset = confirmed;
    }
}

async fn forward_output(
    inner: &Arc<RemoteClientInner>,
    id: &str,
    mut stdout: DuplexStream,
    mut stderr: DuplexStream,
    cancellation: &CommandCancellation,
) -> Result<RemoteProcessExit, RemoteClientError> {
    let (consumed, mut consuming) = watch::channel(0_u64);
    let (confirmed, mut confirmation) = watch::channel(0_u64);
    let ack_stop = CancellationToken::new();
    let stop = ack_stop.clone();
    let ack_inner = inner.clone();
    let ack_id = id.to_owned();
    let acknowledgement = inner.streams.spawn(async move {
        loop {
            tokio::select! {
                _ = stop.cancelled() => return Ok::<(), RemoteClientError>(()),
                changed = consuming.changed() => if changed.is_err() { return Ok(()); },
            }
            let sequence = *consuming.borrow_and_update();
            tokio::select! {
                _ = stop.cancelled() => return Ok(()),
                result = request_inner(&ack_inner, RemoteRequest::OutputConsumed { process_id: ack_id.clone(), sequence }, &[]) => { result?; },
            }
            confirmed.send_replace(sequence);
        }
    });
    let result = async {
        let mut sequence = 0;
        let mut reset_generation = None;
        loop {
            let (generation, wire) = ready(inner).await?;
            let epoch = inner.hello.lock().unwrap_or_else(std::sync::PoisonError::into_inner).as_ref().map_or(0, |h| h.session.epoch);
            let response = match wire.output(id, sequence, epoch).await {
                Ok(response) => response,
                Err(error) => {
                    let disconnected = wire.is_closed() || error.get_ref().and_then(|source| source.downcast_ref::<h2::Error>())
                        .is_some_and(|error| error.is_io() || error.is_go_away());
                    if disconnected { mark_detached(inner, generation, format!("process output transport: {error}")); wire.close().await.ok(); continue; }
                    if reset_generation != Some(generation) { reset_generation = Some(generation); continue; }
                    return Err(RemoteClientError::Protocol(format!("process observer could not reopen: {error}")));
                }
            };
            if !response.headers().get("content-type").is_some_and(|v| v == transport::EVENT_CONTENT) {
                let reply = transport::receive_reply(response, &inner.control, &inner.stopped).await?;
                return Err(response_error(reply.response));
            }
            let raw = futures::stream::unfold(response.into_body(), |mut body| async move {
                match body.data().await {
                    Some(Ok(bytes)) => {
                        let result = body.flow_control().release_capacity(bytes.len()).map(|_| bytes);
                        Some((result, body))
                    }
                    Some(Err(error)) => Some((Err(error), body)),
                    None => None,
                }
            });
            let events = raw.eventsource();
            let mut reopen = false;
            tokio::pin!(events);
            while let Some(event) = tokio::select! {
                _ = inner.stopped.cancelled() => return Err(RemoteClientError::Disconnected),
                event = events.next() => event,
            } {
                let event = match event {
                    Ok(event) => event,
                    Err(eventsource_stream::EventStreamError::Transport(error)) if wire.is_closed() || error.is_io() || error.is_go_away() => {
                        mark_detached(inner, generation, format!("process output transport: {error}"));
                        wire.close().await.ok();
                        break;
                    }
                    Err(eventsource_stream::EventStreamError::Transport(error)) if error.is_reset() && reset_generation != Some(generation) => {
                        reset_generation = Some(generation);
                        reopen = true;
                        break;
                    }
                    Err(error) => return Err(RemoteClientError::Protocol(format!("process output stream: {error}"))),
                };
                let record: RemoteOutputRecord = serde_json::from_str(&event.data).map_err(|e| RemoteClientError::Protocol(e.to_string()))?;
                if record.sequence <= sequence { continue; }
                if record.sequence != sequence + 1 { return Err(RemoteClientError::Protocol("process output sequence gap".into())); }
                match record.event {
                    RemoteEvent::ProcessOutput(output) => {
                        if output.process_id != id { return Err(RemoteClientError::Protocol("process output identity mismatch".into())); }
                        let bytes = STANDARD.decode(record.bytes).map_err(|e| RemoteClientError::Protocol(e.to_string()))?;
                        if !cancellation.is_cancelled() {
                            let write = match output.stream { RemoteOutputStream::Stdout => stdout.write_all(&bytes), RemoteOutputStream::Stderr => stderr.write_all(&bytes) };
                            tokio::select! {
                                result = write => { if let Err(error) = result && error.kind() != io::ErrorKind::BrokenPipe { return Err(error.into()); } },
                                _ = cancellation.cancelled() => {},
                                _ = inner.stopped.cancelled() => return Err(RemoteClientError::Disconnected),
                            }
                        }
                    }
                    RemoteEvent::ProcessExit(exit) => {
                        if exit.process_id != id { return Err(RemoteClientError::Protocol("process exit identity mismatch".into())); }
                        consumed.send_replace(record.sequence);
                        tokio::select! {
                            _ = inner.stopped.cancelled() => return Err(RemoteClientError::Disconnected),
                            result = confirmation.wait_for(|confirmed| *confirmed >= record.sequence) => { result.map_err(|_| RemoteClientError::Disconnected)?; },
                        }
                        return Ok(exit);
                    }
                }
                sequence = record.sequence;
                consumed.send_replace(sequence);
            }
            // A single stream reset reopens only this observer from its consumed sequence.
            // Malformed output and repeated refusal remain local to the command owner.
            if reopen { continue; }
            if !wire.is_closed() {
                return Err(RemoteClientError::Protocol("process output ended without a terminal record".into()));
            }
        }
    }.await;
    ack_stop.cancel();
    let ack = acknowledgement
        .await
        .map_err(|e| RemoteClientError::Protocol(e.to_string()))?;
    result.and_then(|exit| ack.map(|()| exit))
}
