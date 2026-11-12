use std::sync::{Arc, Mutex};

use bytes::Bytes;
use tokio::{
    io::{AsyncRead, AsyncReadExt, AsyncWrite},
    sync::{Semaphore, mpsc, watch},
};
use tokio_util::{sync::CancellationToken, task::TaskTracker};

use crate::{
    Child, ChildStdin, ChildStdout, Command, ExecutionError, SpawnError, StartKnowledge, Stdio,
};
use crate::{
    child::KillRequest,
    stream::{self, Permit, Reset},
    wire,
};

#[derive(Clone)]
pub(crate) struct RemoteConnection {
    sender: h2::client::SendRequest<Bytes>,
    pub tasks: TaskTracker,
    pub closing: CancellationToken,
    reason: Arc<Mutex<Option<String>>>,
    ordinary: Arc<Semaphore>,
    control: Arc<Semaphore>,
}

#[derive(Default)]
struct SpawnGuard {
    streams: Vec<Reset>,
    permits: Vec<Permit>,
}
impl SpawnGuard {
    fn new(stream: Reset, permit: Permit) -> Self {
        Self {
            streams: vec![stream],
            permits: vec![permit],
        }
    }
    fn track(&mut self, stream: Reset, permit: Permit) {
        self.streams.push(stream);
        self.permits.push(permit);
    }
    fn disarm(&mut self) {
        self.streams.clear();
        self.permits.clear();
    }
}
impl Drop for SpawnGuard {
    fn drop(&mut self) {
        for stream in &self.streams {
            stream
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .send_reset(h2::Reason::CANCEL);
        }
        self.disarm();
    }
}

impl RemoteConnection {
    pub async fn patch(
        &self,
        cwd: &str,
        patch: &str,
    ) -> Result<Result<pl_patch::PatchReport, pl_patch::PatchFailure>, ExecutionError> {
        if patch.len() > 16 * 1024 * 1024 {
            return Err(ExecutionError::InvalidInput("patch exceeds 16 MiB".into()));
        }
        let descriptor = stream::encode_descriptor(&cwd)
            .map_err(|error| ExecutionError::io("patch descriptor", error))?;
        let permit = self.permit(1, false).await?;
        let (response, send) = self.open("POST", "/fs/apply-patch", false).await?;
        let send = Arc::new(Mutex::new(send));
        let mut guard = SpawnGuard::new(send.clone(), permit.clone());
        send_shared(&send, descriptor.into(), false, &self.closing).await?;
        send_shared(
            &send,
            Bytes::copy_from_slice(patch.as_bytes()),
            true,
            &self.closing,
        )
        .await?;
        let response = response.await.map_err(disconnected)?;
        let status = response.status();
        let bytes = stream::collect(response.into_body(), stream::DESCRIPTOR_LIMIT)
            .await
            .map_err(disconnected)?;
        if !status.is_success() {
            return Err(serde_json::from_slice::<wire::Failure>(&bytes)
                .map_err(protocol)?
                .into());
        }
        let result = serde_json::from_slice(&bytes).map_err(protocol)?;
        guard.disarm();
        Ok(result)
    }

    pub async fn writer(
        &self,
        executor: crate::Executor,
        descriptor: crate::fs::WriteDescriptor,
    ) -> Result<crate::fs::FileWriter, ExecutionError> {
        let bytes = stream::encode_descriptor(&descriptor)
            .map_err(|error| ExecutionError::io("write descriptor", error))?;
        let permit = self.permit(1, false).await?;
        let (response, send) = self.open("POST", "/fs/write", false).await?;
        let send = Arc::new(Mutex::new(send));
        let mut guard = SpawnGuard::new(send.clone(), permit.clone());
        send_shared(&send, bytes.into(), false, &self.closing).await?;
        let (mut input, output) = tokio::io::duplex(stream::WINDOW as usize);
        let (finish, commit) = tokio::sync::oneshot::channel();
        let (result, observed) = tokio::sync::oneshot::channel();
        let cancel = CancellationToken::new();
        let stopped = cancel.clone();
        let connection = self.clone();
        let owner = executor.clone();
        let held = permit.clone();
        self.tasks.spawn(async move {
            let _permit = held;
            let _owner = owner;
            let operation = async {
                let upload = async {
                    let mut bytes = vec![0; stream::WINDOW as usize];
                    loop {
                        let length = input
                            .read(&mut bytes)
                            .await
                            .map_err(|error| ExecutionError::io("upload source", error))?;
                        if length == 0 {
                            break;
                        }
                        send_shared(
                            &send,
                            Bytes::copy_from_slice(&bytes[..length]),
                            false,
                            &connection.closing,
                        )
                        .await?;
                    }
                    commit.await.map_err(|_| ExecutionError::Cancelled)?;
                    send_shared(&send, Bytes::new(), true, &connection.closing).await
                };
                let receive = async {
                    let response = response.await.map_err(disconnected)?;
                    let status = response.status();
                    let bytes = stream::collect(response.into_body(), wire::RESULT_LIMIT)
                        .await
                        .map_err(disconnected)?;
                    if status.is_success() {
                        serde_json::from_slice(&bytes).map_err(protocol)
                    } else {
                        Err(serde_json::from_slice::<wire::Failure>(&bytes)
                            .map_err(protocol)?
                            .into())
                    }
                };
                let ((), result) = tokio::try_join!(upload, receive)?;
                Ok(result)
            };
            let outcome = tokio::select! {
                result = operation => result,
                _ = stopped.cancelled() => Err(ExecutionError::Cancelled),
                _ = connection.closing.cancelled() => Err(connection.failure()),
            };
            if outcome.is_ok() {
                guard.disarm();
            }
            let _ = result.send(outcome);
        });
        Ok(crate::fs::FileWriter {
            io: Some(output),
            finish: Some(finish),
            result: Some(observed),
            cancel,
            finishing: false,
            _executor: executor,
            _permit: Some(permit),
        })
    }

    async fn exchange_json<S: serde::Serialize>(
        &self,
        path: &str,
        descriptor: &S,
    ) -> Result<(http::Response<h2::RecvStream>, Reset, Permit, SpawnGuard), ExecutionError> {
        let bytes = serde_json::to_vec(descriptor).map_err(protocol)?;
        if bytes.len() > stream::DESCRIPTOR_LIMIT {
            return Err(ExecutionError::InvalidInput(
                "descriptor exceeds 1 MiB".into(),
            ));
        }
        let permit = self.permit(1, false).await?;
        let (response, send) = self.open("POST", path, false).await?;
        let send = Arc::new(Mutex::new(send));
        let guard = SpawnGuard::new(send.clone(), permit.clone());
        send_shared(&send, bytes.into(), true, &self.closing).await?;
        let response = response.await.map_err(disconnected)?;
        if !response.status().is_success() {
            let bytes = stream::collect(response.into_body(), wire::RESULT_LIMIT)
                .await
                .map_err(disconnected)?;
            return Err(serde_json::from_slice::<wire::Failure>(&bytes)
                .map_err(protocol)?
                .into());
        }
        Ok((response, send, permit, guard))
    }

    pub async fn json<S: serde::Serialize, R: serde::de::DeserializeOwned>(
        &self,
        path: &str,
        descriptor: &S,
    ) -> Result<R, ExecutionError> {
        let (response, _, _permit, mut guard) = self.exchange_json(path, descriptor).await?;
        let bytes = stream::collect(response.into_body(), stream::DESCRIPTOR_LIMIT)
            .await
            .map_err(disconnected)?;
        let result = serde_json::from_slice(&bytes).map_err(protocol)?;
        guard.disarm();
        Ok(result)
    }

    pub async fn reader<S: serde::Serialize>(
        &self,
        path: &str,
        descriptor: &S,
    ) -> Result<stream::BodyReader, ExecutionError> {
        let (response, send, permit, mut guard) = self.exchange_json(path, descriptor).await?;
        let (reader, _) = stream::receive(
            response.into_body(),
            send.into(),
            &self.tasks,
            self.closing.clone(),
            Some(permit),
        );
        guard.disarm();
        Ok(reader)
    }

    pub async fn connect<T>(io: T) -> Result<(Self, wire::Hello), ExecutionError>
    where
        T: AsyncRead + AsyncWrite + Unpin + Send + 'static,
    {
        let (sender, driver) = h2::client::Builder::new()
            .initial_window_size(stream::WINDOW)
            .initial_connection_window_size(stream::CONNECTION_WINDOW)
            .max_concurrent_reset_streams(stream::STREAMS as usize)
            .enable_push(false)
            .handshake(io)
            .await
            .map_err(disconnected)?;
        let closing = CancellationToken::new();
        let tasks = TaskTracker::new();
        let reason = Arc::new(Mutex::new(None));
        let stop = closing.clone();
        let failure = reason.clone();
        tasks.spawn(async move {
            let result = tokio::select! { result = driver => result.map_err(|error| error.to_string()), _ = stop.cancelled() => Ok(()) };
            *failure.lock().unwrap_or_else(std::sync::PoisonError::into_inner) = Some(result.err().unwrap_or_else(|| "SSH/h2 connection ended".into()));
            stop.cancel();
        });
        let connection = Self {
            sender,
            tasks,
            closing,
            reason,
            ordinary: Arc::new(Semaphore::new(stream::ORDINARY)),
            control: Arc::new(Semaphore::new(stream::CONTROL)),
        };
        struct Connecting(Option<CancellationToken>);
        impl Drop for Connecting {
            fn drop(&mut self) {
                if let Some(cancel) = self.0.take() {
                    cancel.cancel();
                }
            }
        }
        let mut guard = Connecting(Some(connection.closing.clone()));
        let hello = async {
            let (response, _) = connection.open("POST", "/hello", true).await?;
            let response = response.await.map_err(disconnected)?;
            let bytes = stream::collect(response.into_body(), stream::DESCRIPTOR_LIMIT)
                .await
                .map_err(disconnected)?;
            let hello: wire::Hello = serde_json::from_slice(&bytes).map_err(protocol)?;
            if hello.wire != wire::VERSION {
                return Err(ExecutionError::ProtocolMismatch {
                    expected: wire::VERSION,
                    actual: hello.wire,
                });
            }
            Ok(hello)
        }
        .await;
        match hello {
            Ok(hello) => {
                guard.0.take();
                Ok((connection, hello))
            }
            Err(error) => {
                connection.closing.cancel();
                Err(error)
            }
        }
    }

    pub(crate) fn failure(&self) -> ExecutionError {
        ExecutionError::Disconnected(
            self.reason
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .clone()
                .unwrap_or_else(|| "connection closed".into()),
        )
    }

    pub(crate) async fn permit(&self, count: u32, control: bool) -> Result<Permit, ExecutionError> {
        let semaphore = if control {
            &self.control
        } else {
            &self.ordinary
        };
        tokio::select! {
            _ = self.closing.cancelled() => Err(self.failure()),
            permit = semaphore.clone().acquire_many_owned(count) => permit.map(Arc::new).map_err(|_| self.failure()),
        }
    }

    pub(crate) async fn open(
        &self,
        method: &str,
        path: &str,
        end: bool,
    ) -> Result<(h2::client::ResponseFuture, h2::SendStream<Bytes>), ExecutionError> {
        let mut sender = tokio::select! {
            _ = self.closing.cancelled() => return Err(self.failure()),
            sender = self.sender.clone().ready() => sender.map_err(disconnected)?,
        };
        let request = http::Request::builder()
            .method(method)
            .uri(format!("http://helper{path}"))
            .body(())
            .map_err(protocol)?;
        sender.send_request(request, end).map_err(disconnected)
    }

    pub async fn spawn(&self, command: &Command) -> Result<Child, SpawnError> {
        let spec = wire::CommandSpec::from(command);
        let bytes = serde_json::to_vec(&spec).map_err(|error| SpawnError {
            knowledge: StartKnowledge::NotStarted,
            cause: protocol(error),
        })?;
        if bytes.len() > stream::DESCRIPTOR_LIMIT {
            return Err(SpawnError {
                knowledge: StartKnowledge::NotStarted,
                cause: ExecutionError::InvalidInput("command descriptor exceeds 1 MiB".into()),
            });
        }
        let count = 1 + [spec.stdin, spec.stdout, spec.stderr]
            .iter()
            .filter(|stdio| **stdio == Stdio::Piped)
            .count() as u32;
        let permit = self
            .permit(count, false)
            .await
            .map_err(|cause| SpawnError {
                knowledge: StartKnowledge::NotStarted,
                cause,
            })?;
        let mut knowledge = StartKnowledge::NotStarted;
        self.spawn_admitted(command, spec, bytes, permit, &mut knowledge)
            .await
            .map_err(|cause| SpawnError { knowledge, cause })
    }

    async fn spawn_admitted(
        &self,
        command: &Command,
        spec: wire::CommandSpec,
        bytes: Vec<u8>,
        permit: Permit,
        knowledge: &mut StartKnowledge,
    ) -> Result<Child, ExecutionError> {
        // Admission is atomic for the bundle, then each physical stream owns
        // its own permit until its public IO, pump and flow references end.
        let mut permits = Arc::try_unwrap(permit).expect("fresh process admission owner");
        let main_permit = Arc::new(permits.split(1).expect("main stream admission"));
        let (main_response, main) = self.open("POST", "/process/spawn", false).await?;
        *knowledge = StartKnowledge::Unknown;
        let key = main.stream_id().as_u32();
        let mut guard = SpawnGuard::default();
        // Register reset ownership before the first cancellable body write.
        let main = Arc::new(Mutex::new(main));
        guard.track(main.clone(), main_permit.clone());
        send_shared(&main, bytes.into(), true, &self.closing).await?;
        let mut pipes = Vec::new();
        for (name, stdio, method, end) in [
            ("stdin", spec.stdin, "PUT", false),
            ("stdout", spec.stdout, "GET", true),
            ("stderr", spec.stderr, "GET", true),
        ] {
            if stdio == Stdio::Piped {
                let (response, send) = self
                    .open(method, &format!("/process/{key}/{name}"), end)
                    .await?;
                let send = Arc::new(Mutex::new(send));
                let permit = Arc::new(permits.split(1).expect("pipe admission"));
                guard.track(send.clone(), permit.clone());
                pipes.push((name, response, send, permit));
            }
        }
        let response = main_response.await.map_err(disconnected)?;
        if !response.status().is_success() {
            let bytes = stream::collect(response.into_body(), wire::RESULT_LIMIT)
                .await
                .map_err(disconnected)?;
            *knowledge = StartKnowledge::NotStarted;
            return Err(serde_json::from_slice::<wire::Failure>(&bytes)
                .map(ExecutionError::from)
                .map_err(protocol)?);
        }
        *knowledge = StartKnowledge::Started;
        let pid = response
            .headers()
            .get("x-process-id")
            .and_then(|value| value.to_str().ok())
            .and_then(|value| value.parse().ok());
        let mut stdin = None;
        let mut stdout = None;
        let mut stderr = None;
        let mut captures = Vec::new();
        for (name, response, send, permit) in pipes {
            let response = response.await.map_err(disconnected)?;
            if !response.status().is_success() {
                return Err(ExecutionError::Protocol(
                    "process pipe setup rejected".into(),
                ));
            }
            if name == "stdin" {
                let (mut input, writer) = tokio::io::duplex(stream::WINDOW as usize);
                let connection = self.clone();
                let owner = command.executor.clone();
                let held = permit.clone();
                self.tasks.spawn(async move {
                    let _owner = owner;
                    let _permit = held;
                    let upload = async {
                        let mut bytes = vec![0; stream::WINDOW as usize];
                        loop {
                            let length = input
                                .read(&mut bytes)
                                .await
                                .map_err(|error| ExecutionError::io("stdin", error))?;
                            send_shared(
                                &send,
                                Bytes::copy_from_slice(&bytes[..length]),
                                length == 0,
                                &connection.closing,
                            )
                            .await?;
                            if length == 0 {
                                break;
                            }
                        }
                        Ok::<_, ExecutionError>(())
                    };
                    let receive = stream::collect(response.into_body(), wire::RESULT_LIMIT);
                    let _ = tokio::try_join!(upload, async {
                        receive.await.map_err(disconnected).map(|_| ())
                    });
                });
                stdin = Some(ChildStdin {
                    io: Some(Box::pin(writer)),
                    lifetime: Some(Arc::new(crate::child::PipeLifetime {
                        notify: Arc::new(tokio::sync::Notify::new()),
                        _executor: command.executor.clone(),
                        _permit: Some(permit),
                    })),
                });
            } else {
                let (reader, trailers) = stream::receive(
                    response.into_body(),
                    send.into(),
                    &self.tasks,
                    self.closing.clone(),
                    Some(permit.clone()),
                );
                let reader: std::pin::Pin<Box<dyn AsyncRead + Send>> = Box::pin(reader);
                let reader = if spec.capture.is_some() {
                    let (reader, observed) = crate::capture::observe(reader, move || {
                        trailers
                            .borrow()
                            .clone()
                            .and_then(Result::ok)
                            .and_then(|headers| {
                                headers.get("x-capture").and_then(|value| {
                                    serde_json::from_slice::<wire::CaptureOutcome>(value.as_bytes())
                                        .ok()
                                })
                            })
                            .map(Into::into)
                            .unwrap_or(crate::CapturedStream {
                                state: crate::CaptureState::Incomplete,
                                confirmed_bytes: None,
                                error: None,
                            })
                    });
                    captures.push(observed);
                    reader
                } else {
                    reader
                };
                let pipe = ChildStdout {
                    io: reader,
                    lifetime: Some(Arc::new(crate::child::PipeLifetime {
                        notify: Arc::new(tokio::sync::Notify::new()),
                        _executor: command.executor.clone(),
                        _permit: None,
                    })),
                    cancel: None,
                };
                if name == "stdout" {
                    stdout = Some(pipe);
                } else {
                    stderr = Some(pipe);
                }
            }
        }
        let capture = if spec.capture.is_some() {
            let mut captures = captures.into_iter();
            Some((
                captures.next().expect("stdout capture"),
                captures.next().expect("stderr capture"),
            ))
        } else {
            None
        };
        let (exit_send, exit) = watch::channel(None);
        let (kill, mut requests) = mpsc::channel::<KillRequest>(8);
        let cancellation = CancellationToken::new();
        let stopped = cancellation.clone();
        let connection = self.clone();
        self.tasks.spawn(async move {
            let _permit = main_permit;
            let result = async {
                let exit = async {
                    let bytes = stream::collect(response.into_body(), wire::RESULT_LIMIT).await.map_err(disconnected)?;
                    serde_json::from_slice::<wire::ExitOutcome>(&bytes).map_err(protocol)?.map_err(ExecutionError::from)
                };
                tokio::pin!(exit);
                loop {
                    tokio::select! {
                        biased;
                        result = &mut exit => break result,
                        request = requests.recv() => {
                            if let Some(request) = request { let _ = request.send(connection.kill(key).await); }
                            else { main.lock().unwrap_or_else(std::sync::PoisonError::into_inner).send_reset(h2::Reason::CANCEL); }
                        }
                        _ = stopped.cancelled() => { main.lock().unwrap_or_else(std::sync::PoisonError::into_inner).send_reset(h2::Reason::CANCEL); break Err(ExecutionError::Cancelled); }
                        _ = connection.closing.cancelled() => break Err(connection.failure()),
                    }
                }
            }.await;
            exit_send.send_replace(Some(result));
        });
        guard.disarm();
        Ok(Child {
            stdin,
            stdout,
            stderr,
            pid,
            exit,
            kill,
            cancellation,
            capture,
            executor: command.executor.clone(),
        })
    }

    async fn kill(&self, key: u32) -> Result<(), ExecutionError> {
        let _permit = self.permit(1, true).await?;
        let (response, _) = self
            .open("POST", &format!("/process/{key}/kill"), true)
            .await?;
        let response = response.await.map_err(disconnected)?;
        if response.status() != http::StatusCode::NO_CONTENT {
            return Err(ExecutionError::Protocol("kill rejected".into()));
        }
        stream::collect(response.into_body(), wire::RESULT_LIMIT)
            .await
            .map_err(disconnected)?;
        Ok(())
    }
}

async fn send_shared(
    stream: &Reset,
    bytes: Bytes,
    end: bool,
    cancel: &CancellationToken,
) -> Result<(), ExecutionError> {
    stream::send_shared(stream, bytes, end, cancel)
        .await
        .map_err(|error| ExecutionError::io("h2 send", error))
}

fn disconnected(error: impl std::fmt::Display) -> ExecutionError {
    ExecutionError::Disconnected(error.to_string())
}
fn protocol(error: impl std::fmt::Display) -> ExecutionError {
    ExecutionError::Protocol(error.to_string())
}
