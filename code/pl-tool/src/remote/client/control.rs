//! 长驻控制流的单一事务 owner。
//!
//! 控制流只承载小型控制事务：hello（一次，握手期）、可应答 heartbeat、terminate、
//! closeWorkspace 以及单向 shutdown。事务一旦发布就由本 owner 执行到响应或连接终态，
//! 调用方取消只丢弃自己的等待，不会遗弃半条记录。响应必须与请求的种类严格匹配：错误成功
//! envelope 是控制协议违约，收束该物理连接，而不是清空 workspace 清理责任。

use std::sync::{Arc, Weak};

use pl_protocol::remote::{
    REMOTE_PROTOCOL_VERSION, RemoteCapability, RemoteHello, RemoteMessage, RemoteRequest,
    RemoteResponse,
};
use pl_remote_helper::remote_transport::{
    ConnectionHandle, RecordReader, RecordWriter, RemoteStream,
};
use tokio::io::{ReadHalf, WriteHalf};
use tokio::sync::{mpsc, oneshot};

use super::super::error::RemoteClientError;
use super::ClientInner;
use super::session::{
    ActivityGuard, describe_transport_error, message_kind, method_name, response_kind,
    transport_error,
};

/// Bounded control queue: a control record is small, and admission is serialized by the owner.
const CONTROL_QUEUE: usize = 16;

/// Capabilities a serving helper must provide; a partial helper is a protocol rejection, never a
/// silently reduced feature set.
const REQUIRED_CAPABILITIES: [RemoteCapability; 3] = [
    RemoteCapability::DirectoryBrowse,
    RemoteCapability::WorkspaceFiles,
    RemoteCapability::ObservableExec,
];

/// Build this client was compiled with. The helper asset ships from the same workspace version, so
/// a different helper build is a mismatched transport, not a compatible peer.
const CLIENT_BUILD_VERSION: &str = env!("CARGO_PKG_VERSION");

/// The handshake result: the helper hello plus the control stream's record halves.
pub(super) struct NegotiatedControl {
    pub(super) hello: pl_protocol::remote::RemoteHello,
    /// Descriptor admission built from the budget this helper advertised.
    pub(super) fds: super::fds::FdBudget,
    pub(super) reader: RecordReader<ReadHalf<RemoteStream>>,
    pub(super) writer: RecordWriter<WriteHalf<RemoteStream>>,
}

/// Which response a control request must receive.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ControlExpect {
    Hello,
    Ack,
    /// One-way frame; no response is expected and none is accepted.
    None,
}

fn expectation(request: &RemoteRequest) -> Option<ControlExpect> {
    match request {
        RemoteRequest::Hello { .. } => Some(ControlExpect::Hello),
        RemoteRequest::Heartbeat
        | RemoteRequest::Terminate { .. }
        | RemoteRequest::CloseWorkspace { .. } => Some(ControlExpect::Ack),
        RemoteRequest::Shutdown => Some(ControlExpect::None),
        RemoteRequest::BrowseDirectories { .. }
        | RemoteRequest::OpenWorkspace { .. }
        | RemoteRequest::Stat(_)
        | RemoteRequest::ReadFile(_)
        | RemoteRequest::WriteFile(_)
        | RemoteRequest::ListDirectory(_)
        | RemoteRequest::CreateDirectory(_)
        | RemoteRequest::RemovePath(_)
        | RemoteRequest::RenamePath(_)
        | RemoteRequest::CopyPath(_)
        | RemoteRequest::Spawn(_) => None,
    }
}

pub(super) struct ControlRequest {
    message: RemoteMessage,
    reply: oneshot::Sender<Result<RemoteResponse, RemoteClientError>>,
    expect: ControlExpect,
    /// Held by the owner until the transaction reaches its response or the connection's terminal
    /// state; a caller that stops waiting must not release this responsibility early.
    _activity: Option<ActivityGuard>,
}

/// Settles a one-way shutdown frame that never reached the control owner.
///
/// While this value is alive the frame is in flight; dropping it before the request is handed over
/// publishes a failed verdict instead of leaving the observation suspended.
struct ShutdownHandoff<'a> {
    client: &'a ClientInner,
    handed_off: bool,
}

impl Drop for ShutdownHandoff<'_> {
    fn drop(&mut self) {
        if !self.handed_off {
            self.client.settle_shutdown(false);
        }
    }
}

/// Client side of the control owner.
pub(super) struct ControlChannel {
    requests: mpsc::Sender<ControlRequest>,
}

impl ControlChannel {
    pub(super) fn channel() -> (Self, mpsc::Receiver<ControlRequest>) {
        let (requests, receiver) = mpsc::channel(CONTROL_QUEUE);
        (Self { requests }, receiver)
    }

    /// Runs one acknowledged control transaction, holding a connection responsibility until the
    /// owner reaches its result.
    pub(super) async fn transaction(
        &self,
        client: &Arc<ClientInner>,
        request: RemoteRequest,
    ) -> Result<RemoteResponse, RemoteClientError> {
        let method = method_name(&request);
        let expect = match expectation(&request) {
            Some(ControlExpect::Ack) => ControlExpect::Ack,
            Some(ControlExpect::Hello) => ControlExpect::Hello,
            Some(ControlExpect::None) | None => {
                return Err(RemoteClientError::protocol(format!(
                    "{method} is not an acknowledged control transaction"
                )));
            }
        };
        if client.admission_is_sealed() || client.handle.is_closed() {
            return Err(RemoteClientError::Disconnected);
        }
        let (reply, completed) = oneshot::channel();
        let activity = ActivityGuard::new(client.clone());
        let permit = tokio::select! {
            biased;
            _ = client.observe_closed() => return Err(RemoteClientError::Disconnected),
            permit = self.requests.reserve() => {
                permit.map_err(|_| RemoteClientError::Disconnected)?
            }
        };
        permit.send(ControlRequest {
            message: RemoteMessage::Request(request),
            reply,
            expect,
            _activity: Some(activity),
        });
        match completed.await {
            Ok(result) => {
                if let Err(error) = &result {
                    tracing::debug!(
                        connection = client.instance(),
                        method,
                        %error,
                        "control transaction failed"
                    );
                }
                result
            }
            Err(_) => Err(RemoteClientError::Disconnected),
        }
    }

    /// Publishes the one-way shutdown frame without a helper response.
    pub(super) async fn one_way(
        &self,
        client: &Arc<ClientInner>,
        request: RemoteRequest,
    ) -> Result<(), RemoteClientError> {
        if !matches!(request, RemoteRequest::Shutdown) {
            return Err(RemoteClientError::protocol(
                "only shutdown is published as a one-way control frame",
            ));
        }
        if client.admission_is_sealed() || client.handle.is_closed() {
            return Err(RemoteClientError::Disconnected);
        }
        // The frame's verdict is published for the terminal classification: a driver that ends while it
        // is in flight must not be classified before the verdict settles.
        client.begin_shutdown();
        let mut handoff = ShutdownHandoff {
            client,
            handed_off: false,
        };
        let (reply, completed) = oneshot::channel();
        let permit = tokio::select! {
            biased;
            _ = client.observe_closed() => {
                client.settle_shutdown(false);
                return Err(RemoteClientError::Disconnected);
            }
            permit = self.requests.reserve() => match permit {
                Ok(permit) => permit,
                Err(_) => {
                    client.settle_shutdown(false);
                    return Err(RemoteClientError::Disconnected);
                }
            }
        };
        permit.send(ControlRequest {
            message: RemoteMessage::Request(request),
            reply,
            expect: ControlExpect::None,
            _activity: None,
        });
        // The owner now owns the verdict; this caller no longer settles it.
        handoff.handed_off = true;
        match completed.await {
            Ok(Ok(_)) => Ok(()),
            Ok(Err(error)) => Err(error),
            Err(_) => Err(RemoteClientError::Disconnected),
        }
    }
}

/// Opens the reserved control slot and runs the one and only hello transaction.
pub(super) async fn negotiate(
    handle: &ConnectionHandle,
) -> Result<NegotiatedControl, RemoteClientError> {
    let stream = handle
        .open_control()
        .await
        .map_err(|error| transport_error(handle, "open control stream", error))?;
    let (read, write) = tokio::io::split(stream);
    let mut reader = RecordReader::new(read);
    let mut writer = RecordWriter::new(write);
    writer
        .send(
            &RemoteMessage::Request(RemoteRequest::Hello {
                protocol_version: REMOTE_PROTOCOL_VERSION,
            }),
            &[],
        )
        .await
        .map_err(|error| transport_error(handle, "send hello", error))?;
    let record = reader
        .read()
        .await
        .map_err(|error| transport_error(handle, "read hello", error))?
        .ok_or_else(|| {
            RemoteClientError::protocol("helper closed the control stream during the handshake")
        })?;
    let hello = match record.message {
        RemoteMessage::Response(RemoteResponse::Error(error)) => {
            return Err(RemoteClientError::remote(&error));
        }
        RemoteMessage::Response(RemoteResponse::Hello(hello)) => hello,
        other => {
            return Err(RemoteClientError::protocol(format!(
                "expected the helper hello, received {}",
                message_kind(&other)
            )));
        }
    };
    let fds = validate_hello(&hello)?;
    Ok(NegotiatedControl {
        hello,
        fds,
        reader,
        writer,
    })
}

/// Requires the exact protocol version, the same build and every capability this client uses.
///
/// A helper that negotiated a different build or omits a capability is rejected before the
/// connection is published, so no backend ever runs against a partially compatible peer.
///
/// The advertised descriptor budget is validated here as well: a helper that cannot hold its own
/// operation peaks would otherwise be accepted and only fail at the first real transfer. The returned
/// budget is the connection's only copy of those numbers.
fn validate_hello(hello: &RemoteHello) -> Result<super::fds::FdBudget, RemoteClientError> {
    if hello.protocol_version != REMOTE_PROTOCOL_VERSION {
        return Err(RemoteClientError::protocol(format!(
            "helper negotiated protocol version {}, expected {REMOTE_PROTOCOL_VERSION}",
            hello.protocol_version
        )));
    }
    if hello.helper_version != CLIENT_BUILD_VERSION {
        return Err(RemoteClientError::protocol(format!(
            "helper build {} does not match this client build {CLIENT_BUILD_VERSION}",
            hello.helper_version
        )));
    }
    let missing: Vec<RemoteCapability> = REQUIRED_CAPABILITIES
        .iter()
        .filter(|required| !hello.capabilities.contains(*required))
        .copied()
        .collect();
    if !missing.is_empty() {
        return Err(RemoteClientError::protocol(format!(
            "helper is missing required capabilities {missing:?}"
        )));
    }
    if hello.shell.path.trim().is_empty() {
        return Err(RemoteClientError::protocol(
            "helper hello returned an empty shell path",
        ));
    }
    super::fds::FdBudget::new(hello.resources).map_err(RemoteClientError::protocol)
}

/// Runs the control owner until a close/abort request or a connection-level failure.
pub(super) async fn run(
    mut reader: RecordReader<ReadHalf<RemoteStream>>,
    mut writer: RecordWriter<WriteHalf<RemoteStream>>,
    mut requests: mpsc::Receiver<ControlRequest>,
    client: Weak<ClientInner>,
) {
    loop {
        // A closed driver ends this owner even while no control request is pending; the strong
        // client reference is never held across the wait, so it cannot extend the connection.
        let closed = match client.upgrade() {
            Some(inner) => inner.observe_closed(),
            None => break,
        };
        let request = tokio::select! {
            biased;
            _ = closed => break,
            request = requests.recv() => request,
        };
        let Some(request) = request else {
            break;
        };
        let method = message_kind(&request.message);
        if let Err(error) = writer.send(&request.message, &[]).await {
            if request.expect == ControlExpect::None
                && let Some(inner) = client.upgrade()
            {
                // A shutdown frame that could not be written is a failed verdict, not a pending one.
                inner.settle_shutdown(false);
            }
            let description = describe_transport_error(&error);
            fail(
                &client,
                format!("write {method} control record: {description}"),
            );
            let _ = request
                .reply
                .send(Err(map_transport(&client, "write control record", error)));
            break;
        }
        if request.expect == ControlExpect::None {
            let finished = writer.finish().await;
            if let Some(inner) = client.upgrade() {
                inner.settle_shutdown(finished.is_ok());
            }
            match finished {
                Ok(()) => {
                    let _ = request.reply.send(Ok(RemoteResponse::Ack));
                }
                Err(error) => {
                    let description = describe_transport_error(&error);
                    fail(
                        &client,
                        format!("finish control stream after shutdown: {description}"),
                    );
                    let _ = request.reply.send(Err(map_transport(
                        &client,
                        "finish control stream",
                        error,
                    )));
                }
            }
            break;
        }
        match read_control_record(&mut reader, &client).await {
            Err(error) => {
                let _ = request.reply.send(Err(error));
                break;
            }
            Ok(RemoteMessage::Response(RemoteResponse::Error(error))) => {
                // A helper application error ends only this transaction.
                let _ = request.reply.send(Err(RemoteClientError::remote(&error)));
            }
            Ok(RemoteMessage::Response(response)) => {
                let matched = matches!(
                    (&request.expect, &response),
                    (ControlExpect::Hello, RemoteResponse::Hello(_))
                        | (ControlExpect::Ack, RemoteResponse::Ack)
                );
                if matched {
                    let _ = request.reply.send(Ok(response));
                } else {
                    let reason = format!(
                        "helper answered {} to {method} on the control stream",
                        response_kind(&response)
                    );
                    fail(&client, reason.clone());
                    let _ = request.reply.send(Err(RemoteClientError::Protocol(reason)));
                    break;
                }
            }
            Ok(other) => {
                let reason = format!("helper sent {} on the control stream", message_kind(&other));
                fail(&client, reason.clone());
                let _ = request.reply.send(Err(RemoteClientError::Protocol(reason)));
                break;
            }
        }
    }
    // The control stream is a connection-level resource: dropping it is safe once this owner
    // ends, because the connection close path owns the driver.
    drop(reader);
    drop(writer);
}

async fn read_control_record(
    reader: &mut RecordReader<ReadHalf<RemoteStream>>,
    client: &Weak<ClientInner>,
) -> Result<RemoteMessage, RemoteClientError> {
    match reader.read().await {
        Ok(Some(record)) => Ok(record.message),
        Ok(None) => {
            fail(client, "helper closed the control stream".to_string());
            Err(RemoteClientError::Disconnected)
        }
        Err(error) => {
            let mapped = map_transport(client, "read control response", error);
            fail(client, format!("control stream failed: {mapped}"));
            Err(mapped)
        }
    }
}

fn fail(client: &Weak<ClientInner>, reason: String) {
    if let Some(inner) = client.upgrade() {
        inner.request_abort(reason);
    }
}

fn map_transport(
    client: &Weak<ClientInner>,
    stage: &'static str,
    error: pl_remote_helper::remote_transport::TransportError,
) -> RemoteClientError {
    match client.upgrade() {
        Some(inner) => transport_error(&inner.handle, stage, error),
        None => RemoteClientError::Disconnected,
    }
}
