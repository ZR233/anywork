//! One physical helper instance and at most one authorized HTTP/2 attachment.
use super::*;
use crate::ServerError;
use crate::transport::{self, Bytes, Reply};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use tokio::sync::watch;
use tokio_util::{sync::CancellationToken, task::TaskTracker};

mod relay;
pub use relay::{attach_stdio, run_stdio};

struct Operation {
    result: watch::Sender<Option<Arc<Reply>>>,
}
struct Attachment {
    epoch: AtomicU64,
    stop: CancellationToken,
}
struct Owner {
    identity: RemoteSession,
    epoch: AtomicU64,
    attachment: Mutex<Option<CancellationToken>>,
    state: Arc<Mutex<ServerState>>,
    directories: directories::Directories,
    transfers: transfers::Transfers,
    processes: ProcessRegistry,
    http: http::HttpProxy,
    operations: Mutex<HashMap<String, Arc<Operation>>>,
    tasks: TaskTracker,
    heartbeat: watch::Sender<tokio::time::Instant>,
    stopped: CancellationToken,
    shutdown_requested: std::sync::atomic::AtomicBool,
    shutdown_result: watch::Sender<Option<Result<(), RemoteError>>>,
    counters: Arc<transport::WireCounters>,
    last_failure: Mutex<Option<RemoteOperationFailure>>,
    operation_queries: AtomicU64,
    replayed_body_bytes: AtomicU64,
}

pub async fn run_owner(socket: PathBuf) -> Result<(), ServerError> {
    use std::io::Read;
    let root = socket
        .parent()
        .ok_or_else(|| io::Error::other("helper socket parent missing"))?;
    let mut secret = [0_u8; 32];
    std::fs::File::open("/dev/urandom")?.read_exact(&mut secret)?;
    let identity = RemoteSession {
        instance_id: hex::encode(&secret[..16]),
        socket_path: socket.to_string_lossy().into_owned(),
        credential: hex::encode(secret),
        epoch: 0,
    };
    let shell = detect_shell().map_err(ServerError::Cleanup)?;
    let directories = directories::Directories::new(identity.instance_id.clone());
    let transfers = transfers::Transfers::new(identity.instance_id.clone());
    let http = http::HttpProxy::new()?;
    let owner = Arc::new(Owner {
        identity,
        epoch: AtomicU64::new(0),
        attachment: Mutex::new(None),
        state: Arc::new(Mutex::new(ServerState {
            workspaces: WorkspaceRegistry::new(),
            shell: shell.clone(),
        })),
        directories,
        transfers,
        processes: ProcessRegistry::new(),
        http,
        operations: Default::default(),
        tasks: TaskTracker::new(),
        heartbeat: watch::channel(tokio::time::Instant::now()).0,
        stopped: CancellationToken::new(),
        shutdown_requested: std::sync::atomic::AtomicBool::new(false),
        shutdown_result: watch::channel(None).0,
        counters: Default::default(),
        last_failure: Mutex::new(None),
        operation_queries: AtomicU64::new(0),
        replayed_body_bytes: AtomicU64::new(0),
    });
    let listener = tokio::net::UnixListener::bind(&socket)?;
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&socket, std::fs::Permissions::from_mode(0o600))?;
    }
    // This pipe is owned by the bootstrap relay, not the SSH protocol stdout.
    use tokio::io::AsyncWriteExt;
    tokio::io::stdout().write_all(b"READY\n").await?;
    tokio::io::stdout().flush().await?;
    let connections = TaskTracker::new();
    let mut activity = owner.heartbeat.subscribe();
    let expiry = async {
        loop {
            let deadline = *activity.borrow_and_update() + std::time::Duration::from_secs(30);
            tokio::select! {
                result = activity.changed() => if result.is_err() { break; },
                _ = tokio::time::sleep_until(deadline) => {
                    if tokio::time::Instant::now().duration_since(*activity.borrow()) >= std::time::Duration::from_secs(30) { break; }
                }
            }
        }
    };
    tokio::pin!(expiry);
    let outcome = loop {
        tokio::select! {
            _ = owner.stopped.cancelled() => break Ok(()),
            _ = &mut expiry => break Err(io::Error::new(io::ErrorKind::TimedOut, "helper heartbeat lease expired")),
            socket = listener.accept() => match socket {
                Ok((socket, _)) => {
                    let owner = owner.clone();
                    connections.spawn(async move {
                        if let Err(error) = owner.connection(socket).await { eprintln!("helper transport: {error}"); }
                    });
                }
                Err(error) => break Err(error),
            }
        }
    };
    owner.stopped.cancel();
    // Connections keep driving protocol while physical owners finish. In particular, the
    // shutdown stream must be able to receive the final cleanup receipt.
    let mut failures = Vec::new();
    if let Err(error) = owner.processes.terminate_all().await {
        failures.push(error.message);
    }
    owner.tasks.close();
    owner.tasks.wait().await;
    owner.directories.close_all().await;
    if let Err(error) = owner.transfers.close_all().await {
        failures.push(error.message);
    }
    owner.operations.lock().await.clear();
    let cleanup = if failures.is_empty() {
        Ok(())
    } else {
        Err(remote_error(RemoteErrorCode::Io, failures.join("; ")))
    };
    owner.shutdown_result.send_replace(Some(cleanup.clone()));
    if owner.shutdown_requested.load(Ordering::Acquire) {
        let active = owner.attachment.lock().await.clone();
        if let Some(active) = active {
            // Let the driver flush the final response; the client closes after receiving it.
            let _ =
                tokio::time::timeout(std::time::Duration::from_secs(2), active.cancelled()).await;
        }
    }
    if let Some(active) = owner.attachment.lock().await.take() {
        active.cancel();
    }
    connections.close();
    connections.wait().await;
    drop(listener);
    std::fs::remove_file(&socket)?;
    std::fs::remove_dir(root)?;
    cleanup.map_err(ServerError::Cleanup)?;
    outcome.map_err(ServerError::Io)
}

impl Owner {
    async fn connection(self: &Arc<Self>, socket: tokio::net::UnixStream) -> io::Result<()> {
        let handshake = h2::server::Builder::new().handshake(transport::MeasuredIo {
            io: socket,
            counters: self.counters.clone(),
        });
        let mut connection = tokio::select! {
            _ = self.stopped.cancelled() => return Ok(()),
            result = tokio::time::timeout(std::time::Duration::from_secs(25), handshake) =>
                result.map_err(|_| io::Error::new(io::ErrorKind::TimedOut, "HTTP/2 handshake timed out"))?.map_err(io::Error::other)?,
        };
        let attachment = Arc::new(Attachment {
            epoch: AtomicU64::new(0),
            stop: CancellationToken::new(),
        });
        let streams = TaskTracker::new();
        let authentication_deadline =
            tokio::time::Instant::now() + std::time::Duration::from_secs(25);
        let mut failure = None;
        loop {
            tokio::select! {
                _ = attachment.stop.cancelled() => break,
                _ = self.stopped.cancelled(), if attachment.epoch.load(Ordering::Acquire) == 0 => break,
                _ = tokio::time::sleep_until(authentication_deadline), if attachment.epoch.load(Ordering::Acquire) == 0 => break,
                request = connection.accept() => match request {
                    None => break,
                    Some(Err(error)) => { failure = Some(error); break; },
                    Some(Ok((request, sender))) => {
                        let owner = self.clone();
                        let attachment = attachment.clone();
                        streams.spawn(async move {
                            if let Err(error) = owner.exchange(request, sender, &attachment).await {
                                eprintln!("helper stream epoch={}: {error}", attachment.epoch.load(Ordering::Acquire));
                            }
                        });
                    }
                }
            }
        }
        attachment.stop.cancel();
        streams.close();
        streams.wait().await;
        failure.map_or(Ok(()), |error| Err(io::Error::other(error)))
    }
    fn authorized(&self, attachment: &Attachment, epoch: u64) -> bool {
        epoch != 0
            && epoch == attachment.epoch.load(Ordering::Acquire)
            && epoch == self.epoch.load(Ordering::Acquire)
            && !attachment.stop.is_cancelled()
    }
    async fn exchange(
        self: &Arc<Self>,
        request: ::http::Request<h2::RecvStream>,
        mut sender: h2::server::SendResponse<Bytes>,
        attachment: &Arc<Attachment>,
    ) -> io::Result<()> {
        let path = request.uri().path().to_owned();
        let epoch = request
            .headers()
            .get("x-anywork-epoch")
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.parse().ok())
            .unwrap_or(0);
        if let Some(process) = path.strip_prefix("/output/") {
            if !self.authorized(attachment, epoch) {
                return transport::respond(&mut sender, &error_reply(stale()), &attachment.stop)
                    .await;
            }
            let after = request
                .uri()
                .query()
                .and_then(|v| v.strip_prefix("after="))
                .and_then(|v| v.parse().ok())
                .unwrap_or(0);
            return self
                .processes
                .output(process, after, sender, attachment.stop.clone())
                .await;
        }
        if let Some(exchange_id) = path.strip_prefix("/http/") {
            if !self.authorized(attachment, epoch) {
                return http::respond_early_error(&mut sender, stale(), &attachment.stop).await;
            }
            if self.stopped.is_cancelled() {
                return http::respond_early_error(
                    &mut sender,
                    remote_error(
                        RemoteErrorCode::RemoteDisconnected,
                        "helper admission is closed",
                    ),
                    &attachment.stop,
                )
                .await;
            }
            return self
                .http
                .exchange(exchange_id, request, sender, attachment.stop.clone())
                .await;
        }
        let control = path.starts_with("/control/");
        let id = path
            .rsplit('/')
            .next()
            .filter(|v| !v.is_empty())
            .ok_or_else(|| io::Error::other("missing operation identity"))?
            .to_owned();
        let length = transport::body_length(request.headers())?;
        let binary = request
            .headers()
            .get("content-type")
            .is_some_and(|v| v == transport::BINARY_CONTENT);
        let control_metadata = request
            .headers()
            .get("x-anywork-control")
            .map(|value| value.as_bytes().to_vec());
        let metadata = request
            .headers()
            .get("x-anywork-operation")
            .map(|v| v.as_bytes().to_vec());
        let (bytes, receive_micros, _) =
            match transport::collect(request.into_body(), length, &attachment.stop).await {
                Ok(value) => value,
                Err(error) => {
                    return transport::respond(
                        &mut sender,
                        &error_reply(io_error("receive request", error)),
                        &attachment.stop,
                    )
                    .await;
                }
            };
        let parsed: Result<RemoteRequest, _> = serde_json::from_slice(if control {
            control_metadata.as_deref().unwrap_or_default()
        } else if binary {
            metadata.as_deref().unwrap_or_default()
        } else {
            &bytes
        });
        let request = match parsed {
            Ok(value) => value,
            Err(error) => {
                return transport::respond(
                    &mut sender,
                    &error_reply(remote_error(
                        RemoteErrorCode::InvalidRequest,
                        error.to_string(),
                    )),
                    &attachment.stop,
                )
                .await;
            }
        };
        if control != request.is_control() {
            return transport::respond(
                &mut sender,
                &error_reply(remote_error(
                    RemoteErrorCode::InvalidRequest,
                    "incorrect request lane",
                )),
                &attachment.stop,
            )
            .await;
        }
        if matches!(
            request,
            RemoteRequest::Hello { .. } | RemoteRequest::Attach { .. }
        ) {
            let reply = match self.attach(request, attachment).await {
                Ok(reply) => reply,
                Err(error) => error_reply(error),
            };
            return transport::respond_control(&mut sender, &reply);
        }
        if !self.authorized(attachment, epoch) {
            return transport::respond(&mut sender, &error_reply(stale()), &attachment.stop).await;
        }
        if control {
            let retained_result = matches!(request, RemoteRequest::OperationResult { .. });
            let filesystem = matches!(request, RemoteRequest::Stat(_))
                || matches!(
                    request,
                    RemoteRequest::CloseTransfer { .. } | RemoteRequest::TransferStatus { .. }
                );
            let started = std::time::Instant::now();
            let mut reply = tokio::select! {
                _ = attachment.stop.cancelled() => return Ok(()),
                reply = self.control_request(request) => reply,
            };
            if !retained_result {
                reply.timing.receive_micros = receive_micros;
                if filesystem {
                    reply.timing.filesystem_micros = transport::elapsed_micros(started);
                } else {
                    reply.timing.execution_micros = transport::elapsed_micros(started);
                }
            }
            let result = if retained_result {
                transport::respond(&mut sender, &reply, &attachment.stop).await
            } else {
                transport::respond_control(&mut sender, &reply)
            };
            return result;
        }
        if self.stopped.is_cancelled() {
            return transport::respond(
                &mut sender,
                &error_reply(remote_error(
                    RemoteErrorCode::RemoteDisconnected,
                    "helper admission is closed",
                )),
                &attachment.stop,
            )
            .await;
        }
        let operation = {
            let mut operations = self.operations.lock().await;
            if let Some(operation) = operations.get(&id) {
                operation.clone()
            } else {
                if !self.authorized(attachment, epoch) {
                    drop(operations);
                    return transport::respond(
                        &mut sender,
                        &error_reply(stale()),
                        &attachment.stop,
                    )
                    .await;
                }
                let operation = Arc::new(Operation {
                    result: watch::channel(None).0,
                });
                operations.insert(id.clone(), operation.clone());
                let completion = operation.clone();
                let owner = self.clone();
                let operation_id = id.clone();
                let body = if binary {
                    bytes
                } else {
                    drop(bytes);
                    Bytes::new()
                };
                self.tasks.spawn(async move {
                    let execution = matches!(
                        request,
                        RemoteRequest::Spawn(_)
                            | RemoteRequest::WriteStdin { .. }
                            | RemoteRequest::CloseStdin { .. }
                    );
                    let started = std::time::Instant::now();
                    let outcome = owner.handle(request, body).await;
                    let mut reply = match outcome {
                        Ok((response, body)) => Reply::new(response, body.into()),
                        Err(error) => error_reply(error),
                    };
                    reply.timing = RemoteOperationTiming {
                        receive_micros,
                        execution_micros: if execution {
                            transport::elapsed_micros(started)
                        } else {
                            0
                        },
                        filesystem_micros: if execution {
                            0
                        } else {
                            transport::elapsed_micros(started)
                        },
                        transfer_backpressure_micros: 0,
                    };
                    if let RemoteResponse::Error(error) = &reply.response {
                        *owner.last_failure.lock().await = Some(RemoteOperationFailure {
                            operation_id,
                            epoch,
                            code: error.code,
                            request_bytes: length,
                            reply_bytes: reply.body.len(),
                            phase: if execution { "process" } else { "filesystem" }.into(),
                        });
                    }
                    completion.result.send_replace(Some(Arc::new(reply)));
                });
                operation
            }
        };
        let reply = wait_operation(&operation, &attachment.stop).await?;
        transport::respond(&mut sender, &reply, &attachment.stop).await
    }
    async fn attach(
        &self,
        request: RemoteRequest,
        attachment: &Attachment,
    ) -> Result<Reply, RemoteError> {
        let shell = self.state.lock().await.shell.clone();
        let mut active = self.attachment.lock().await;
        match request {
            RemoteRequest::Hello { protocol_version } => {
                if protocol_version != REMOTE_PROTOCOL_VERSION {
                    return Err(remote_error(
                        RemoteErrorCode::ProtocolMismatch,
                        "unsupported helper protocol",
                    ));
                }
                if self.epoch.load(Ordering::Acquire) != 0 {
                    return Err(remote_error(
                        RemoteErrorCode::SessionExpired,
                        "helper requires its existing attachment credential",
                    ));
                }
            }
            RemoteRequest::Attach { session } => {
                if session.instance_id != self.identity.instance_id
                    || session.credential != self.identity.credential
                {
                    return Err(remote_error(
                        RemoteErrorCode::SessionExpired,
                        "helper attachment identity is invalid",
                    ));
                }
            }
            _ => {
                return Err(remote_error(
                    RemoteErrorCode::InvalidRequest,
                    "invalid attachment operation",
                ));
            }
        }
        let epoch = self.epoch.fetch_add(1, Ordering::AcqRel) + 1;
        if let Some(previous) = active.replace(attachment.stop.clone()) {
            previous.cancel();
        }
        attachment.epoch.store(epoch, Ordering::Release);
        self.heartbeat.send_replace(tokio::time::Instant::now());
        let mut session = self.identity.clone();
        session.epoch = epoch;
        Ok(Reply::new(
            RemoteResponse::Hello(RemoteHello {
                protocol_version: REMOTE_PROTOCOL_VERSION,
                helper_version: env!("CARGO_PKG_VERSION").into(),
                os: std::env::consts::OS.into(),
                architecture: std::env::consts::ARCH.into(),
                capabilities: vec![
                    RemoteCapability::DirectoryBrowse,
                    RemoteCapability::WorkspaceFiles,
                    RemoteCapability::ObservableExec,
                ],
                shell,
                session,
            }),
            Bytes::new(),
        ))
    }
    async fn control_request(&self, request: RemoteRequest) -> Reply {
        if let RemoteRequest::OperationResult { operation_id } = &request {
            self.operation_queries.fetch_add(1, Ordering::Relaxed);
            let operation = self.operations.lock().await.get(operation_id).cloned();
            return match operation {
                None => error_reply(remote_error(
                    RemoteErrorCode::OperationNotStarted,
                    "operation was not admitted before the previous attachment was fenced",
                )),
                Some(operation) => match wait_operation(&operation, &self.stopped).await {
                    Ok(reply) => {
                        self.replayed_body_bytes
                            .fetch_add(reply.body.len() as u64, Ordering::Relaxed);
                        Reply {
                            response: reply.response.clone(),
                            body: reply.body.clone(),
                            timing: reply.timing,
                        }
                    }
                    Err(error) => error_reply(io_error("wait retained operation", error)),
                },
            };
        }
        let result = async {
            match request {
                RemoteRequest::Heartbeat => {
                    self.heartbeat.send_replace(tokio::time::Instant::now());
                    let (received_bytes, sent_bytes) = self.counters.snapshot();
                    let active_connections = usize::from(
                        self.attachment
                            .lock()
                            .await
                            .as_ref()
                            .is_some_and(|active| !active.is_cancelled()),
                    );
                    let workspaces = self.state.lock().await.workspaces.len();
                    let processes = self.processes.len().await;
                    let cursors = self.directories.len().await;
                    let transfers = self.transfers.len().await;
                    let retained_operations = self.operations.lock().await.len();
                    let last_failure = self.last_failure.lock().await.clone();
                    Ok((
                        RemoteResponse::Heartbeat(RemoteHeartbeat {
                            epoch: self.epoch.load(Ordering::Acquire),
                            owner_pid: std::process::id(),
                            active_connections,
                            workspaces,
                            processes,
                            cursors,
                            transfers,
                            retained_operations,
                            pending_tasks: self.tasks.len(),
                            received_bytes,
                            sent_bytes,
                            operation_queries: self.operation_queries.load(Ordering::Relaxed),
                            replayed_body_bytes: self.replayed_body_bytes.load(Ordering::Relaxed),
                            last_failure,
                        }),
                        Vec::new(),
                    ))
                }
                RemoteRequest::Stat(request) => stat(&self.state, request).await,
                RemoteRequest::ReleaseOperation { operation_id } => {
                    let mut operations = self.operations.lock().await;
                    operations.remove(&operation_id);
                    if operations.len().saturating_mul(4) < operations.capacity() {
                        operations.shrink_to_fit();
                    }
                    Ok(ack())
                }
                RemoteRequest::OutputConsumed {
                    process_id,
                    sequence,
                } => {
                    self.processes.acknowledge(&process_id, sequence).await?;
                    Ok(ack())
                }
                RemoteRequest::WaitProcess { process_id } => Ok((
                    RemoteResponse::ProcessExited(self.processes.wait(&process_id).await?),
                    Vec::new(),
                )),
                RemoteRequest::ReleaseProcess { process_id } => {
                    self.processes.release(&process_id).await?;
                    Ok(ack())
                }
                RemoteRequest::Terminate { process_id } => {
                    self.processes.terminate(&process_id).await?;
                    Ok(ack())
                }
                RemoteRequest::RenewProcessLease {
                    process_id,
                    lease_id,
                } => {
                    self.processes.renew_lease(&process_id, &lease_id).await?;
                    Ok(ack())
                }
                RemoteRequest::CloseWorkspace { workspace_id } => {
                    self.directories.close_workspace(&workspace_id).await;
                    self.transfers.close_workspace(&workspace_id).await?;
                    match self.state.lock().await.workspaces.close(&workspace_id) {
                        Ok(()) => {}
                        Err(error) if error.code == RemoteErrorCode::WorkspaceNotFound => {}
                        Err(error) => return Err(error),
                    }
                    Ok(ack())
                }
                RemoteRequest::CloseDirectory { cursor } => {
                    self.directories.close(&cursor).await;
                    Ok(ack())
                }
                RemoteRequest::CloseTransfer { transfer_id } => {
                    self.transfers.close(&transfer_id).await?;
                    Ok(ack())
                }
                RemoteRequest::TransferStatus { transfer_id } => Ok((
                    RemoteResponse::Transfer(self.transfers.status(&transfer_id).await?),
                    Vec::new(),
                )),
                RemoteRequest::Shutdown => {
                    self.shutdown_requested.store(true, Ordering::Release);
                    let mut completion = self.shutdown_result.subscribe();
                    self.stopped.cancel();
                    let result = completion
                        .wait_for(Option::is_some)
                        .await
                        .map_err(|_| {
                            remote_error(
                                RemoteErrorCode::OutcomeUnknown,
                                "helper cleanup completion unavailable",
                            )
                        })?
                        .as_ref()
                        .cloned()
                        .ok_or_else(|| {
                            remote_error(
                                RemoteErrorCode::OutcomeUnknown,
                                "helper cleanup result missing",
                            )
                        })?;
                    result?;
                    Ok(ack())
                }
                _ => Err(remote_error(
                    RemoteErrorCode::InvalidRequest,
                    "not a control operation",
                )),
            }
        }
        .await;
        match result {
            Ok((response, bytes)) => Reply::new(response, bytes.into()),
            Err(error) => error_reply(error),
        }
    }
    async fn handle(
        &self,
        request: RemoteRequest,
        body: Bytes,
    ) -> Result<(RemoteResponse, Vec<u8>), RemoteError> {
        match request {
            RemoteRequest::BrowseDirectories { path } => {
                let path =
                    path.unwrap_or_else(|| std::env::var("HOME").unwrap_or_else(|_| "/".into()));
                let path = tokio::fs::canonicalize(path)
                    .await
                    .map_err(|e| io_error("browse directory", e))?;
                let display = path.to_string_lossy().into_owned();
                Ok((
                    RemoteResponse::Directories(
                        self.directories
                            .open(path, display, None, REMOTE_IO_CHUNK_BYTES)
                            .await?,
                    ),
                    Vec::new(),
                ))
            }
            RemoteRequest::ListDirectory(target) => {
                let workspaces = self.state.lock().await.workspaces.clone();
                let path = workspaces
                    .resolve_existing(&target.workspace_id, &target.path)
                    .await?;
                Ok((
                    RemoteResponse::Directory(
                        self.directories
                            .open(
                                path,
                                target.path,
                                Some(target.workspace_id),
                                REMOTE_IO_CHUNK_BYTES,
                            )
                            .await?,
                    ),
                    Vec::new(),
                ))
            }
            RemoteRequest::ContinueDirectory { cursor } => Ok((
                RemoteResponse::Directory(
                    self.directories
                        .next(&cursor, REMOTE_IO_CHUNK_BYTES)
                        .await?,
                ),
                Vec::new(),
            )),
            RemoteRequest::OpenRead(target) => {
                let workspaces = self.state.lock().await.workspaces.clone();
                let path = workspaces
                    .resolve_existing(&target.workspace_id, &target.path)
                    .await?;
                Ok((
                    RemoteResponse::Transfer(
                        self.transfers.open_read(target.workspace_id, path).await?,
                    ),
                    Vec::new(),
                ))
            }
            RemoteRequest::BeginWrite(request) => {
                let workspaces = self.state.lock().await.workspaces.clone();
                let path = workspaces
                    .resolve_for_write(&request.target.workspace_id, &request.target.path)
                    .await?;
                Ok((
                    RemoteResponse::Transfer(
                        self.transfers
                            .begin_write(
                                request.target.workspace_id,
                                path,
                                request.mode,
                                request.total_len,
                            )
                            .await?,
                    ),
                    Vec::new(),
                ))
            }
            RemoteRequest::WriteChunk {
                transfer_id,
                offset,
                sha256,
            } => Ok((
                self.transfers
                    .write(&transfer_id, offset, &sha256, &body)
                    .await?,
                Vec::new(),
            )),
            RemoteRequest::ReadFileChunk {
                transfer_id,
                offset,
                max_bytes,
            } => self.transfers.read(&transfer_id, offset, max_bytes).await,
            RemoteRequest::CommitWrite {
                transfer_id,
                length,
                sha256,
            } => Ok((
                RemoteResponse::Transfer(
                    self.transfers
                        .commit(&transfer_id, length, &sha256, REMOTE_IO_CHUNK_BYTES)
                        .await?,
                ),
                Vec::new(),
            )),
            request => handle_request(&self.state, &self.processes, request, body).await,
        }
    }
}
async fn wait_operation(operation: &Operation, stop: &CancellationToken) -> io::Result<Arc<Reply>> {
    let mut reply = operation.result.subscribe();
    tokio::select! {
        _ = stop.cancelled() => Err(io::Error::new(io::ErrorKind::Interrupted, "operation observation cancelled")),
        result = reply.wait_for(Option::is_some) => result.map_err(io::Error::other)?.as_ref().cloned()
            .ok_or_else(|| io::Error::other("operation result missing")),
    }
}
fn error_reply(error: RemoteError) -> Reply {
    Reply::new(RemoteResponse::Error(error), Bytes::new())
}
fn stale() -> RemoteError {
    remote_error(
        RemoteErrorCode::StaleConnection,
        "connection generation is no longer current",
    )
}
