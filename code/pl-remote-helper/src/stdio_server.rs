//! A foreground server owned exclusively by one SSH stdio connection.
use bytes::Bytes;
use h2::{RecvStream, server::SendResponse};
use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
};
use tokio::{
    io::{AsyncRead, AsyncReadExt, AsyncWrite},
    sync::{mpsc, oneshot},
};
use tokio_util::{sync::CancellationToken, task::TaskTracker};

use crate::{ChildStdout, ExecutionError, Executor, Stdio, stream, wire};

type Kill = oneshot::Sender<Result<(), ExecutionError>>;
type Processes = Arc<Mutex<HashMap<u32, Process>>>;
struct Process {
    pipes: mpsc::Sender<Pipe>,
    kill: mpsc::Sender<Kill>,
    attached: u8,
}
struct Pipe {
    name: String,
    input: RecvStream,
    response: SendResponse<Bytes>,
}

/// Runs until transport EOF, then bounds registered cleanup to two seconds.
pub async fn serve<T>(io: T) -> Result<(), crate::ServerError>
where
    T: AsyncRead + AsyncWrite + Unpin + Send + 'static,
{
    let executor = Executor::local().map_err(std::io::Error::other)?;
    let tasks = TaskTracker::new();
    let closing = CancellationToken::new();
    let processes: Processes = Default::default();
    let mut connection = h2::server::Builder::new()
        .initial_window_size(stream::WINDOW)
        .initial_connection_window_size(stream::CONNECTION_WINDOW)
        .max_concurrent_streams(stream::STREAMS)
        .max_pending_accept_reset_streams(stream::STREAMS as usize)
        .max_concurrent_reset_streams(stream::STREAMS as usize)
        .handshake::<_, Bytes>(io)
        .await
        .map_err(std::io::Error::other)?;
    let result = loop {
        let Some(request) = connection.accept().await else {
            break Ok(());
        };
        let (request, mut response) = match request {
            Ok(request) => request,
            Err(error) => break Err(std::io::Error::other(error)),
        };
        let path = request.uri().path().to_owned();
        let method = request.method().clone();
        if method == http::Method::POST && path == "/hello" {
            let hello = wire::Hello {
                wire: wire::VERSION,
                build: env!("CARGO_PKG_VERSION").into(),
                target: executor.target_info().clone(),
            };
            tasks.spawn(reply(
                response,
                http::StatusCode::OK,
                serde_json::to_vec(&hello).expect("Hello serializes"),
                closing.clone(),
            ));
        } else if method == http::Method::POST && path == "/process/spawn" {
            let key = request.body().stream_id().as_u32();
            let (pipes, receive_pipes) = mpsc::channel(3);
            let (kill, receive_kill) = mpsc::channel(8);
            // Registration is synchronous with accepting HEADERS, before parsing
            // any DATA or dispatching a task. Pipe requests never create entries.
            processes
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .insert(
                    key,
                    Process {
                        pipes,
                        kill,
                        attached: 0,
                    },
                );
            let processes = processes.clone();
            let executor = executor.clone();
            let stop = closing.clone();
            let owners = tasks.clone();
            tasks.spawn(async move {
                run_process(
                    request.into_body(),
                    response,
                    receive_pipes,
                    receive_kill,
                    executor,
                    owners,
                    stop,
                )
                .await;
                processes
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .remove(&key);
            });
        } else if method == http::Method::POST && path == "/http" {
            tasks.spawn(crate::http::remote::serve(
                request.into_body(),
                response,
                executor.clone(),
                tasks.clone(),
                closing.clone(),
            ));
        } else if method == http::Method::POST && path == "/fs/apply-patch" {
            tasks.spawn(apply_patch(
                request.into_body(),
                response,
                executor.clone(),
                tasks.clone(),
                closing.clone(),
            ));
        } else if method == http::Method::POST && path == "/fs/write" {
            tasks.spawn(write_file(
                request.into_body(),
                response,
                executor.clone(),
                tasks.clone(),
                closing.clone(),
            ));
        } else if method == http::Method::POST && path.starts_with("/fs/") {
            tasks.spawn(filesystem(
                path,
                request.into_body(),
                response,
                executor.clone(),
                closing.clone(),
            ));
        } else if let Some((key, operation)) = process_route(&path) {
            if operation == "kill" && method == http::Method::POST {
                let kill = processes
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .get(&key)
                    .map(|process| process.kill.clone());
                let stop = closing.clone();
                tasks.spawn(async move {
                    let result = if let Some(kill) = kill {
                        let (send, receive) = oneshot::channel();
                        if kill.send(send).await.is_ok() {
                            receive.await.unwrap_or(Ok(()))
                        } else {
                            Ok(())
                        }
                    } else {
                        Ok(())
                    };
                    let status = if result.is_ok() {
                        http::StatusCode::NO_CONTENT
                    } else {
                        http::StatusCode::INTERNAL_SERVER_ERROR
                    };
                    reply(response, status, Vec::new(), stop).await;
                });
            } else {
                let bit = match (method, operation) {
                    (http::Method::PUT, "stdin") => 1,
                    (http::Method::GET, "stdout") => 2,
                    (http::Method::GET, "stderr") => 4,
                    _ => 0,
                };
                let pipe = Pipe {
                    name: operation.into(),
                    input: request.into_body(),
                    response,
                };
                let mut state = processes
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                let accepted = state
                    .get_mut(&key)
                    .filter(|process| bit != 0 && process.attached & bit == 0);
                match accepted {
                    Some(process) => {
                        process.attached |= bit;
                        let _ = process.pipes.try_send(pipe);
                    }
                    None => {
                        let mut response = pipe.response;
                        response.send_reset(h2::Reason::REFUSED_STREAM);
                    }
                }
            }
        } else {
            response.send_reset(h2::Reason::REFUSED_STREAM);
        }
    };
    closing.cancel();
    executor.inner.closing.cancel();
    drop(connection);
    tasks.close();
    executor.inner.tasks.close();
    let cleanup = async {
        tokio::join!(tasks.wait(), executor.inner.tasks.wait());
    };
    if tokio::time::timeout(std::time::Duration::from_secs(2), cleanup)
        .await
        .is_err()
    {
        return Err(crate::ServerError::CleanupTimedOut);
    }
    result.map_err(Into::into)
}

async fn apply_patch(
    input: RecvStream,
    response: SendResponse<Bytes>,
    executor: Executor,
    tasks: TaskTracker,
    closing: CancellationToken,
) {
    let response = Arc::new(Mutex::new(response));
    let (mut reader, _) = stream::receive(
        input,
        stream::ResetOwner::Response(response.clone()),
        &tasks,
        closing.clone(),
        None,
    );
    let operation = async {
        let cwd: String = stream::read_descriptor(&mut reader)
            .await
            .map_err(|error| ExecutionError::io("patch descriptor", error))?;
        let mut bytes = Vec::new();
        (&mut reader)
            .take(16 * 1024 * 1024 + 1)
            .read_to_end(&mut bytes)
            .await
            .map_err(|error| ExecutionError::io("patch input", error))?;
        if bytes.len() > 16 * 1024 * 1024 {
            return Err(ExecutionError::InvalidInput("patch exceeds 16 MiB".into()));
        }
        let patch = String::from_utf8(bytes)
            .map_err(|_| ExecutionError::InvalidInput("patch is not UTF-8".into()))?;
        let cwd = executor.path(cwd)?;
        match executor.fs().apply_patch(&cwd, &patch).await {
            Ok(report) => Ok(Ok(report)),
            Err(crate::PatchExecutionError::Patch(failure)) => Ok(Err(failure)),
            Err(crate::PatchExecutionError::Execution(error)) => Err(error),
        }
    };
    let result = tokio::select! {
        result = operation => result,
        _ = closing.cancelled() => return,
        _ = futures::future::poll_fn(|cx|response.lock().unwrap_or_else(std::sync::PoisonError::into_inner).poll_reset(cx))=>return,
    };
    let (status, bytes) = match result {
        Ok(result) => (
            http::StatusCode::OK,
            serde_json::to_vec(&result).expect("patch result serializes"),
        ),
        Err(error) => (
            http::StatusCode::BAD_REQUEST,
            serde_json::to_vec(&wire::Failure::from(&error)).expect("failure serializes"),
        ),
    };
    let output = response
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .send_response(
            http::Response::builder()
                .status(status)
                .body(())
                .expect("fixed response"),
            false,
        );
    if let Ok(mut output) = output {
        let _ = stream::send(&mut output, bytes.into(), true, &closing).await;
    }
}

async fn write_file(
    input: RecvStream,
    response: SendResponse<Bytes>,
    executor: Executor,
    tasks: TaskTracker,
    closing: CancellationToken,
) {
    let response = Arc::new(Mutex::new(response));
    let (mut reader, _) = stream::receive(
        input,
        stream::ResetOwner::Response(response.clone()),
        &tasks,
        closing.clone(),
        None,
    );
    let operation = async {
        let descriptor: crate::fs::WriteDescriptor = stream::read_descriptor(&mut reader)
            .await
            .map_err(|error| ExecutionError::io("write descriptor", error))?;
        let path = executor.path(&descriptor.path)?;
        let mut writer = executor
            .fs()
            .write(&path, descriptor.mode, descriptor.expected_len)
            .await?;
        tokio::io::copy(&mut reader, &mut writer)
            .await
            .map_err(|error| ExecutionError::io("receive file upload", error))?;
        writer.finish().await
    };
    let result = tokio::select! {
        result = operation => result,
        _ = closing.cancelled() => return,
        _ = futures::future::poll_fn(|cx|response.lock().unwrap_or_else(std::sync::PoisonError::into_inner).poll_reset(cx))=>return,
    };
    let (status, bytes) = match result {
        Ok(result) => (
            http::StatusCode::OK,
            serde_json::to_vec(&result).expect("write result serializes"),
        ),
        Err(error) => (
            http::StatusCode::BAD_REQUEST,
            serde_json::to_vec(&wire::Failure::from(&error)).expect("write failure serializes"),
        ),
    };
    let output = response
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .send_response(
            http::Response::builder()
                .status(status)
                .body(())
                .expect("fixed response"),
            false,
        );
    if let Ok(mut output) = output {
        let _ = stream::send(&mut output, bytes.into(), true, &closing).await;
    }
}

async fn filesystem(
    path: String,
    input: RecvStream,
    mut response: SendResponse<Bytes>,
    executor: Executor,
    closing: CancellationToken,
) {
    let cancelled = closing.child_token();
    let _cancel = cancelled.clone().drop_guard();
    let prepare = async {
        let bytes = stream::collect(input, stream::DESCRIPTOR_LIMIT)
            .await
            .map_err(|error| ExecutionError::io("filesystem descriptor", error))?;
        if path == "/fs/mutate" {
            let request = serde_json::from_slice(&bytes)
                .map_err(|error| ExecutionError::InvalidInput(error.to_string()))?;
            // Mutation owns its OS work even when the response consumer cancels.
            let (send, receive) = tokio::sync::oneshot::channel();
            let stop = cancelled.clone();
            let owner = executor.clone();
            executor.inner.tasks.spawn(async move {
                let result = crate::fs::mutate::mutate_native(request, owner, stop).await;
                let _ = send.send(result);
            });
            receive
                .await
                .map_err(|_| ExecutionError::Disconnected("mutation result is unknown".into()))??;
            return Ok((Some(b"null".to_vec()), None, None));
        }
        if path == "/fs/metadata" {
            let request = serde_json::from_slice(&bytes)
                .map_err(|error| ExecutionError::InvalidInput(error.to_string()))?;
            let metadata = crate::fs::metadata_native(&executor, request).await?;
            return Ok::<_, ExecutionError>((
                Some(serde_json::to_vec(&metadata).expect("metadata serializes")),
                None,
                None,
            ));
        }
        let path_value: String = serde_json::from_slice(&bytes)
            .map_err(|error| ExecutionError::InvalidInput(error.to_string()))?;
        let target = executor.path(path_value)?;
        match path.as_str() {
            "/fs/read" => Ok((None, Some(executor.fs().read(&target).await?), None)),
            "/fs/read-dir" => Ok((None, None, Some(executor.fs().read_dir(&target).await?))),
            _ => Err(ExecutionError::InvalidInput(
                "unknown filesystem operation".into(),
            )),
        }
    };
    let result = tokio::select! {
        result = prepare => result,
        _ = closing.cancelled() => return,
        _ = futures::future::poll_fn(|cx| response.poll_reset(cx)) => return,
    };
    let (metadata, file, directory) = match result {
        Ok(prepared) => prepared,
        Err(error) => {
            reply(
                response,
                http::StatusCode::BAD_REQUEST,
                serde_json::to_vec(&wire::Failure::from(&error)).expect("failure serializes"),
                closing,
            )
            .await;
            return;
        }
    };
    if let Some(bytes) = metadata {
        reply(response, http::StatusCode::OK, bytes, closing).await;
        return;
    }
    let Ok(mut output) = response.send_response(http::Response::new(()), false) else {
        return;
    };
    let result: Result<(), ExecutionError> = async {
        if let Some(mut file) = file {
            let mut bytes = vec![0; stream::WINDOW as usize];
            loop {
                let length = tokio::select! {
                    result = file.read(&mut bytes) => result.map_err(|error| ExecutionError::io("file stream", error))?,
                    _ = futures::future::poll_fn(|cx| output.poll_reset(cx)) => return Err(ExecutionError::Cancelled),
                    _ = closing.cancelled() => return Err(ExecutionError::Cancelled),
                };
                if length == 0 { break; }
                stream::send(&mut output, Bytes::copy_from_slice(&bytes[..length]), false, &closing).await.map_err(|error| ExecutionError::io("file stream", error))?;
            }
        }
        if let Some(mut directory) = directory {
            while let Some(entry) = directory.next().await? {
                let mut bytes = serde_json::to_vec(&entry).expect("directory entry serializes");
                bytes.push(b'\n');
                if bytes.len() > stream::DESCRIPTOR_LIMIT { return Err(ExecutionError::InvalidInput("directory entry exceeds 1 MiB".into())); }
                stream::send(&mut output, bytes.into(), false, &closing).await.map_err(|error| ExecutionError::io("directory stream", error))?;
            }
        }
        Ok(())
    }.await;
    match result {
        Ok(()) => {
            let _ = output.send_data(Bytes::new(), true);
        }
        Err(error) => {
            let bytes =
                serde_json::to_vec(&wire::Failure::from(&error)).expect("failure serializes");
            if bytes.len() <= wire::RESULT_LIMIT
                && let Ok(value) = http::HeaderValue::from_bytes(&bytes)
            {
                let mut trailers = http::HeaderMap::new();
                trailers.insert("x-executor-error", value);
                let _ = output.send_trailers(trailers);
            } else {
                output.send_reset(h2::Reason::INTERNAL_ERROR);
            }
        }
    }
}

fn process_route(path: &str) -> Option<(u32, &str)> {
    let (key, operation) = path.strip_prefix("/process/")?.split_once('/')?;
    Some((key.parse().ok()?, operation))
}

struct ProcessStreams {
    stdin: Option<Pipe>,
    stdout: Option<Pipe>,
    stderr: Option<Pipe>,
}

async fn run_process(
    input: RecvStream,
    mut response: SendResponse<Bytes>,
    mut pipes: mpsc::Receiver<Pipe>,
    mut kills: mpsc::Receiver<Kill>,
    executor: Executor,
    tasks: TaskTracker,
    closing: CancellationToken,
) {
    let prepared = async {
        let bytes = stream::collect(input, stream::DESCRIPTOR_LIMIT)
            .await
            .map_err(|error| ExecutionError::io("command descriptor", error))?;
        let spec: wire::CommandSpec = serde_json::from_slice(&bytes)
            .map_err(|error| ExecutionError::InvalidInput(error.to_string()))?;
        let count = [spec.stdin, spec.stdout, spec.stderr]
            .iter()
            .filter(|stdio| **stdio == Stdio::Piped)
            .count();
        let mut streams = ProcessStreams {
            stdin: None,
            stdout: None,
            stderr: None,
        };
        for _ in 0..count {
            let pipe = pipes
                .recv()
                .await
                .ok_or_else(|| ExecutionError::Protocol("spawn pipe missing".into()))?;
            let slot = match pipe.name.as_str() {
                "stdin" if spec.stdin == Stdio::Piped => &mut streams.stdin,
                "stdout" if spec.stdout == Stdio::Piped => &mut streams.stdout,
                "stderr" if spec.stderr == Stdio::Piped => &mut streams.stderr,
                _ => {
                    return Err(ExecutionError::InvalidInput(
                        "unexpected process pipe".into(),
                    ));
                }
            };
            if slot.replace(pipe).is_some() {
                return Err(ExecutionError::InvalidInput(
                    "duplicate process pipe".into(),
                ));
            }
        }
        let mut command = executor.command(spec.program);
        command
            .args(spec.arguments)
            .stdin(spec.stdin)
            .stdout(spec.stdout)
            .stderr(spec.stderr);
        if let Some(cwd) = spec.cwd {
            command.current_dir(cwd);
        }
        if spec.clear_environment {
            command.env_clear();
        }
        for (key, value) in spec.environment {
            if let Some(value) = value {
                command.env(key, value);
            } else {
                command.env_remove(key);
            }
        }
        if let Some(capture) = spec.capture {
            command.capture(capture);
        }
        let child = command.spawn().await.map_err(|error| error.cause)?;
        Ok::<_, ExecutionError>((child, streams))
    };
    let result = tokio::select! {
        biased;
        _ = closing.cancelled() => return,
        _ = futures::future::poll_fn(|cx| response.poll_reset(cx)) => return,
        result = prepared => result,
    };
    let (mut child, mut streams) = match result {
        Ok(prepared) => prepared,
        Err(error) => {
            reply(
                response,
                http::StatusCode::BAD_REQUEST,
                serde_json::to_vec(&wire::Failure::from(&error)).expect("Failure serializes"),
                closing,
            )
            .await;
            return;
        }
    };
    let main = http::Response::builder()
        .status(200)
        .header("x-process-id", child.id().unwrap_or(0))
        .body(())
        .expect("fixed response");
    let Ok(mut main) = response.send_response(main, false) else {
        return;
    };
    if let Some(mut endpoint) = streams.stdin.take() {
        let stdin = child.stdin.take();
        let stop = closing.clone();
        let tracker = tasks.clone();
        tasks.spawn(async move {
            let Ok(output) = endpoint
                .response
                .send_response(http::Response::new(()), false)
            else {
                return;
            };
            let output = Arc::new(Mutex::new(output));
            let (mut input, _) = stream::receive(
                endpoint.input,
                output.clone().into(),
                &tracker,
                stop.clone(),
                None,
            );
            let result = if let Some(mut stdin) = stdin {
                tokio::io::copy(&mut input, &mut stdin).await.map(|_| ())
            } else {
                Err(std::io::ErrorKind::BrokenPipe.into())
            };
            let mut output = output
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if result.is_ok() {
                let _ = output.send_data(Bytes::new(), true);
            } else {
                output.send_reset(h2::Reason::INTERNAL_ERROR);
            }
        });
    }
    let capture = child.capture.clone();
    for (endpoint, reader, completion) in [
        (
            streams.stdout.take(),
            child.stdout.take(),
            capture.as_ref().map(|value| value.0.clone()),
        ),
        (
            streams.stderr.take(),
            child.stderr.take(),
            capture.as_ref().map(|value| value.1.clone()),
        ),
    ] {
        if let (Some(endpoint), Some(reader)) = (endpoint, reader) {
            tasks.spawn(output_pipe(endpoint, reader, completion, closing.clone()));
        }
    }
    let outcome = loop {
        tokio::select! {
            biased;
            result = child.wait() => break result,
            Some(kill) = kills.recv() => { let _ = kill.send(child.start_kill().await); }
            _ = futures::future::poll_fn(|cx| main.poll_reset(cx)) => { let _ = child.kill().await; return; }
            _ = closing.cancelled() => { let _ = child.kill().await; return; }
        }
    };
    // A finished root has no kill route; queued/repeated kill requests must not
    // address its PID again. Output tasks retain their own pipe/job lifetimes.
    kills.close();
    while let Some(kill) = kills.recv().await {
        let _ = kill.send(Ok(()));
    }
    let outcome: wire::ExitOutcome = outcome.map_err(|error| wire::Failure::from(&error));
    let bytes = serde_json::to_vec(&outcome).expect("exit serializes");
    let _ = stream::send(&mut main, bytes.into(), true, &closing).await;
}

async fn output_pipe(
    mut endpoint: Pipe,
    mut reader: ChildStdout,
    completion: Option<crate::capture::CaptureCompletion>,
    closing: CancellationToken,
) {
    let Ok(mut output) = endpoint
        .response
        .send_response(http::Response::new(()), false)
    else {
        return;
    };
    let result = async {
        let mut bytes = vec![0; stream::WINDOW as usize];
        loop {
            let length = tokio::select! {
                result = reader.read(&mut bytes) => result?,
                _ = closing.cancelled() => return Err(std::io::ErrorKind::Interrupted.into()),
                _ = futures::future::poll_fn(|cx| output.poll_reset(cx)) => return Err(std::io::ErrorKind::BrokenPipe.into()),
            };
            if length == 0 {
                break;
            }
            stream::send(
                &mut output,
                Bytes::copy_from_slice(&bytes[..length]),
                false,
                &closing,
            )
            .await?;
        }
        if let Some(mut completion) = completion {
            let result = crate::capture::completion(&mut completion).await;
            let mut trailers = http::HeaderMap::new();
            let value = serde_json::to_vec(&wire::CaptureOutcome::from(result))
                .map_err(std::io::Error::other)?;
            trailers.insert(
                "x-capture",
                http::HeaderValue::from_bytes(&value).map_err(std::io::Error::other)?,
            );
            output
                .send_trailers(trailers)
                .map_err(std::io::Error::other)
        } else {
            output
                .send_data(Bytes::new(), true)
                .map_err(std::io::Error::other)
        }
    };
    tokio::pin!(result);
    tokio::select! { _ = result => (), _ = closing.cancelled() => () }
}

pub(crate) async fn reply(
    mut response: SendResponse<Bytes>,
    status: http::StatusCode,
    bytes: Vec<u8>,
    closing: CancellationToken,
) {
    let response_head = http::Response::builder()
        .status(status)
        .body(())
        .expect("fixed response");
    if let Ok(mut stream) = response.send_response(response_head, bytes.is_empty())
        && !bytes.is_empty()
    {
        let _ = stream::send(&mut stream, bytes.into(), true, &closing).await;
    }
}
