//! One physical helper instance and at most one authorized HTTP/2 attachment.
use super::*;
use crate::ServerError;
use crate::budget::{ByteLease, ResourceBudget, ResourcePolicy};
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
    _memory: ByteLease,
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
    operations: Mutex<HashMap<String, Arc<Operation>>>,
    tasks: TaskTracker,
    budget: ResourceBudget,
    control: ResourceBudget,
    metadata: ResourceBudget,
    lease_control: ResourceBudget,
    allocation: watch::Sender<RemoteAllocation>,
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
    let allocation = ResourcePolicy::default().allocation()?;
    let (budget, control, lease_control, metadata) = budgets(allocation)?;
    let directories = directories::Directories::new(identity.instance_id.clone());
    let transfers = transfers::Transfers::new(identity.instance_id.clone());
    let owner = Arc::new(Owner {
        identity,
        epoch: AtomicU64::new(0),
        attachment: Mutex::new(None),
        state: Arc::new(Mutex::new(ServerState {
            workspaces: WorkspaceRegistry::new(budget.clone()),
            shell: shell.clone(),
        })),
        directories,
        transfers,
        processes: ProcessRegistry::new(budget.clone()),
        operations: Default::default(),
        tasks: TaskTracker::new(),
        budget,
        control,
        lease_control,
        metadata,
        allocation: watch::channel(allocation).0,
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

fn budgets(
    allocation: RemoteAllocation,
) -> io::Result<(
    ResourceBudget,
    ResourceBudget,
    ResourceBudget,
    ResourceBudget,
)> {
    let mut data = allocation;
    let mut control = allocation;
    control.resident_bytes = allocation.fragment_bytes.saturating_mul(2);
    let mut lease = control;
    control.ordinary_operations = allocation.ordinary_operations;
    data.resident_bytes = allocation
        .resident_bytes
        .saturating_sub(control.resident_bytes)
        .saturating_sub(lease.resident_bytes)
        .saturating_sub(control.resident_bytes);
    lease.ordinary_operations = 1;
    Ok((
        ResourceBudget::new(data)?,
        ResourceBudget::new(control)?,
        ResourceBudget::new(lease)?,
        ResourceBudget::new(control)?,
    ))
}

impl Owner {
    async fn connection(self: &Arc<Self>, socket: tokio::net::UnixStream) -> io::Result<()> {
        let allocation = *self.allocation.borrow();
        let mut receive_credit = self
            .budget
            .try_reserve(allocation.connection_window as usize)
            .ok_or_else(|| {
                io::Error::new(
                    io::ErrorKind::OutOfMemory,
                    "connection receive credit unavailable",
                )
            })?;
        let _attachment_memory = self
            .lease_control
            .try_reserve(std::mem::size_of::<Attachment>())
            .ok_or_else(|| {
                io::Error::new(
                    io::ErrorKind::OutOfMemory,
                    "attachment control reservation unavailable",
                )
            })?;
        let handshake = h2::server::Builder::new()
            .initial_window_size(allocation.stream_window)
            .initial_connection_window_size(allocation.connection_window)
            // HTTP/2's wire ceiling is not a fixed application concurrency policy. Each
            // stream is physically admitted below; host process/RPC grants resize independently.
            .max_concurrent_streams(u32::MAX)
            .max_send_buffer_size(allocation.fragment_bytes)
            .max_header_list_size(allocation.fragment_bytes.min(u32::MAX as usize) as u32)
            .handshake(transport::MeasuredIo {
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
        let mut changes = self.allocation.subscribe();
        let mut retained_window = allocation.connection_window;
        let mut pending_stream_window = None;
        let authentication_deadline =
            tokio::time::Instant::now() + std::time::Duration::from_secs(25);
        let mut failure = None;
        loop {
            tokio::select! {
                _ = attachment.stop.cancelled() => break,
                _ = self.stopped.cancelled(), if attachment.epoch.load(Ordering::Acquire) == 0 => break,
                _ = tokio::time::sleep_until(authentication_deadline), if attachment.epoch.load(Ordering::Acquire) == 0 => break,
                changed = changes.changed() => {
                    if changed.is_err() { break; }
                    let allocation = *changes.borrow_and_update();
                    let busy = self.processes.len().await > 0 || !self.operations.lock().await.is_empty();
                    let requested = if busy { retained_window.max(allocation.connection_window) } else { allocation.connection_window };
                    if receive_credit.resize(requested as usize) { retained_window = requested; }
                    connection.set_target_window_size(retained_window);
                    pending_stream_window = Some(allocation.stream_window);
                }
                request = futures::future::poll_fn(|cx| {
                    let result = connection.poll_accept(cx);
                    if let Some(window) = pending_stream_window
                        && connection.set_initial_window_size(window).is_ok() {
                            pending_stream_window = None;
                            cx.waker().wake_by_ref();
                        }
                    result
                }) => match request {
                    None => break,
                    Some(Err(error)) => { failure = Some(error); break; },
                    Some(Ok((request, mut sender))) => {
                        let pool = if request.uri().path().starts_with("/lease/") { &self.lease_control }
                            else if request.uri().path().starts_with("/control/") { &self.control }
                            else if request.uri().path().starts_with("/metadata/") { &self.metadata } else { &self.budget };
                        let Some(intent) = pool.try_reserve(std::mem::size_of::<Attachment>() + std::mem::size_of_val(&request)) else {
                            sender.send_reset(h2::Reason::REFUSED_STREAM);
                            continue;
                        };
                        let owner = self.clone();
                        let attachment = attachment.clone();
                        streams.spawn(async move {
                            let _intent = intent;
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
        request: http::Request<h2::RecvStream>,
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
        let lease_message = path.starts_with("/lease/");
        let metadata_message = path.starts_with("/metadata/");
        let control = lease_message || metadata_message || path.starts_with("/control/");
        let id = path
            .rsplit('/')
            .next()
            .filter(|v| !v.is_empty())
            .ok_or_else(|| io::Error::other("missing operation identity"))?
            .to_owned();
        let budget = if lease_message {
            &self.lease_control
        } else if metadata_message {
            &self.metadata
        } else if control {
            &self.control
        } else {
            &self.budget
        };
        let length = transport::body_length(request.headers())?;
        let reply_limit = request
            .headers()
            .get("x-anywork-reply-limit")
            .and_then(|value| value.to_str().ok())
            .and_then(|value| value.parse::<usize>().ok())
            .unwrap_or(budget.allocation().fragment_bytes);
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
        let (bytes, memory, admission_wait_micros, receive_micros, _) =
            match transport::collect_reserved(
                request.into_body(),
                length,
                if control {
                    control_metadata.as_ref().map_or(0, Vec::len)
                } else {
                    reply_limit
                        .max(budget.allocation().fragment_bytes)
                        .saturating_mul(2)
                },
                budget,
                &attachment.stop,
            )
            .await
            {
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
        if control != request.is_control()
            || lease_message != request.is_lease_control()
            || metadata_message != request.is_metadata()
        {
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
            return transport::respond_control(&mut sender, &reply, reply_limit);
        }
        if !self.authorized(attachment, epoch) {
            return transport::respond(&mut sender, &error_reply(stale()), &attachment.stop).await;
        }
        if control {
            let retained_result = matches!(request, RemoteRequest::OperationResult { .. });
            // The original operation/transfer already owns the metadata and result reservation.
            // Observation must not pin the lifecycle-control pool while awaiting file/process IO.
            if request.is_observation() {
                drop(memory);
            }
            let filesystem = request.is_metadata()
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
                reply.timing.admission_wait_micros = admission_wait_micros;
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
                transport::respond_control(&mut sender, &reply, reply_limit)
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
                    _memory: memory,
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
                    let outcome = owner.handle(request, body, reply_limit).await;
                    let mut reply = match outcome {
                        Ok((response, body)) => {
                            // Reply capacity was reserved before invoking the physical operation.
                            Reply::new(response, body.into())
                        }
                        Err(error) => error_reply(error),
                    };
                    reply.timing = RemoteOperationTiming {
                        admission_wait_micros,
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
                            reserved_bytes: owner.budget.usage().0,
                            wait_reason: (error.code == RemoteErrorCode::ResourceExhausted)
                                .then(|| "residentBudget".into()),
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
        let allocation = *self.allocation.borrow();
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
                allocation,
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
                            _memory: None,
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
                    let (reserved_bytes, peak_reserved_bytes) = self.budget.usage();
                    let (received_bytes, sent_bytes) = self.counters.snapshot();
                    let allocation = *self.allocation.borrow();
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
                            allocation,
                            epoch: self.epoch.load(Ordering::Acquire),
                            owner_pid: std::process::id(),
                            active_connections,
                            workspaces,
                            processes,
                            cursors,
                            transfers,
                            retained_operations,
                            pending_tasks: self.tasks.len(),
                            reserved_bytes,
                            peak_reserved_bytes,
                            received_bytes,
                            sent_bytes,
                            operation_queries: self.operation_queries.load(Ordering::Relaxed),
                            replayed_body_bytes: self.replayed_body_bytes.load(Ordering::Relaxed),
                            last_failure,
                        }),
                        Vec::new(),
                    ))
                }
                RemoteRequest::Configure { allocation } => {
                    let limits =
                        tokio::task::spawn_blocking(|| ResourcePolicy::default().allocation())
                            .await
                            .map_err(|e| io_error("resource sampler", io::Error::other(e)))?
                            .map_err(|e| io_error("resource sample", e))?;
                    let mut allocation = allocation;
                    allocation.resident_bytes =
                        allocation.resident_bytes.min(limits.resident_bytes);
                    allocation.fragment_bytes =
                        allocation.fragment_bytes.min(limits.fragment_bytes);
                    allocation.ordinary_operations = allocation
                        .ordinary_operations
                        .min(limits.ordinary_operations);
                    allocation.stream_window = allocation.stream_window.min(limits.stream_window);
                    allocation.connection_window =
                        allocation.connection_window.min(limits.connection_window);
                    let (data, control, lease, metadata) =
                        budgets(allocation).map_err(|e| io_error("resource allocation", e))?;
                    self.budget
                        .resize(data.allocation())
                        .map_err(|e| io_error("data allocation", e))?;
                    self.control
                        .resize(control.allocation())
                        .map_err(|e| io_error("control allocation", e))?;
                    self.lease_control
                        .resize(lease.allocation())
                        .map_err(|e| io_error("lease allocation", e))?;
                    self.metadata
                        .resize(metadata.allocation())
                        .map_err(|e| io_error("metadata allocation", e))?;
                    self.allocation.send_replace(allocation);
                    Ok((RemoteResponse::Capacity(allocation), Vec::new()))
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
                RemoteRequest::CloseWorkspace { workspace_id } => {
                    self.directories.close_workspace(&workspace_id).await;
                    self.transfers.close_workspace(&workspace_id).await?;
                    match self.state.lock().await.workspaces.close(&workspace_id) {
                        Ok(()) => {}
                        Err(error) if error.code == RemoteErrorCode::WorkspaceNotFound => {}
                        Err(error) => return Err(error),
                    }
                    self.transfers.forget_closed_workspace(&workspace_id);
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
        reply_limit: usize,
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
                            .open(path, display, None, &self.budget, reply_limit)
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
                                &self.budget,
                                reply_limit,
                            )
                            .await?,
                    ),
                    Vec::new(),
                ))
            }
            RemoteRequest::ContinueDirectory { cursor } => Ok((
                RemoteResponse::Directory(
                    self.directories
                        .next(&cursor, &self.budget, reply_limit)
                        .await?,
                ),
                Vec::new(),
            )),
            RemoteRequest::OpenRead(target) => {
                let _opening = self.transfers.admit(&target.workspace_id)?;
                let workspaces = self.state.lock().await.workspaces.clone();
                let path = workspaces
                    .resolve_existing(&target.workspace_id, &target.path)
                    .await?;
                Ok((
                    RemoteResponse::Transfer(
                        self.transfers
                            .open_read(target.workspace_id, path, &self.budget)
                            .await?,
                    ),
                    Vec::new(),
                ))
            }
            RemoteRequest::BeginWrite(request) => {
                let _opening = self.transfers.admit(&request.target.workspace_id)?;
                let workspaces = self.state.lock().await.workspaces.clone();
                let path = workspaces
                    .resolve_for_write(&request.target.workspace_id, &request.target.path)
                    .await?;
                let create = if request.mode == RemoteWriteMode::Create {
                    Some((
                        workspaces.create_root(&request.target.workspace_id)?,
                        PathBuf::from(&request.target.path),
                    ))
                } else {
                    None
                };
                Ok((
                    RemoteResponse::Transfer(
                        self.transfers
                            .begin_write(
                                request.target.workspace_id,
                                path,
                                request.mode,
                                request.total_len,
                                &self.budget,
                                create,
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
                    .write(&transfer_id, offset, &sha256, &body, &self.budget)
                    .await?,
                Vec::new(),
            )),
            RemoteRequest::ReadFileChunk {
                transfer_id,
                offset,
                max_bytes,
            } => {
                if max_bytes > reply_limit {
                    return Err(remote_error(
                        RemoteErrorCode::InvalidRequest,
                        "read exceeds reserved reply grant",
                    ));
                }
                self.transfers.read(&transfer_id, offset, max_bytes).await
            }
            RemoteRequest::CommitWrite {
                transfer_id,
                length,
                sha256,
            } => Ok((
                RemoteResponse::Transfer(
                    self.transfers
                        .commit(
                            &transfer_id,
                            length,
                            &sha256,
                            self.budget.allocation().fragment_bytes,
                        )
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
