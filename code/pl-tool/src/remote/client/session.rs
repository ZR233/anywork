//! 一次普通操作的真实子流预留、记录读写与连接责任所有权。
//!
//! 每个操作先取得 T1 传输给出的真实 [`StreamReservation`]（控制流之外的一条物理子流），
//! 再把预留转成 [`OperationStream`]。租约在其打开流、记录读写和清理责任结束前保持连接、
//! workspace 句柄与物理 permit，避免端点在该责任存续期间收缩所属连接。

use std::sync::Arc;

use pl_protocol::remote::{
    RemoteMessage, RemoteReadRequest, RemoteRequest, RemoteResourceClass, RemoteResponse,
    RemoteSpawnRequest, RemoteWriteRequest,
};
use pl_remote_helper::remote_transport::{
    ConnectionHandle, MAX_RECORD_BYTES, RecordReader, RecordWriter, RemoteRecord, RemoteStream,
    StreamReservation, TransportError,
};
use tokio::io::{AsyncRead, ReadHalf, WriteHalf};

use super::super::error::RemoteClientError;
use super::fds::{FdLease, WorkspaceRetained};
use super::workspace::WorkspaceLease;
use super::{
    ClientInner, RemoteClient, RemoteDirectoryStream, RemoteFileReader, directory, files, process,
};

/// One operation's reserved physical stream, not yet opened.
pub(in crate::remote) struct StreamLease {
    client: RemoteClient,
    reservation: StreamReservation,
    workspace: Option<Arc<WorkspaceLease>>,
    /// Persistent charge of the workspace root this operation addresses, when it is still active here.
    root: Option<Arc<WorkspaceRetained>>,
    /// Descriptor peak of this operation class on the same physical helper.
    fds: FdLease,
    activity: ActivityGuard,
}

impl StreamLease {
    pub(super) fn new(
        client: RemoteClient,
        reservation: StreamReservation,
        fds: FdLease,
        root: Option<Arc<WorkspaceRetained>>,
    ) -> Self {
        let activity = ActivityGuard::new(client.inner.clone());
        Self {
            client,
            reservation,
            workspace: None,
            root,
            fds,
            activity,
        }
    }

    /// Binds the physical workspace handle this operation runs under, so the handle cannot be
    /// released (and its `closeWorkspace` queued) before the operation finishes.
    pub(in crate::remote) fn with_workspace(mut self, workspace: Arc<WorkspaceLease>) -> Self {
        self.workspace = Some(workspace);
        self
    }

    pub(in crate::remote) fn client(&self) -> &RemoteClient {
        &self.client
    }

    /// The physical workspace handle the serving connection opened for this operation.
    pub(in crate::remote) fn workspace_id(&self) -> Option<&str> {
        self.workspace.as_ref().map(|workspace| workspace.id())
    }

    /// Opens the reserved stream. The reservation is consumed exactly once.
    pub(super) async fn open_stream(self) -> Result<OperationStream, RemoteClientError> {
        let Self {
            client,
            reservation,
            workspace,
            root,
            fds,
            activity,
        } = self;
        let stream = reservation
            .open()
            .await
            .map_err(|error| client.transport_failure("open operation stream", error))?;
        Ok(OperationStream::new(
            client, stream, workspace, root, fds, activity,
        ))
    }

    /// Runs one unary request (`request` → single `response`).
    pub(in crate::remote) async fn request(
        self,
        request: RemoteRequest,
    ) -> Result<RemoteResponse, RemoteClientError> {
        let mut stream = self.open_stream().await?;
        stream.send_request(request).await?;
        let record = stream.read().await?;
        response_record(record, "request")
    }

    /// Runs one unary request and hands the operation's ownership to the caller.
    ///
    /// A sequence that outlives its single transaction — `openWorkspace` splits the persistent root
    /// charge out of the very reservation that opened it — keeps the ownership instead of having the
    /// descriptor lease released with the transaction.
    pub(in crate::remote) async fn into_request(
        self,
        request: RemoteRequest,
    ) -> Result<(RemoteResponse, StreamOwnership), RemoteClientError> {
        let mut stream = self.open_stream().await?;
        stream.send_request(request).await?;
        let record = stream.read().await?;
        let response = response_record(record, "request")?;
        let OperationStream {
            reader,
            writer,
            ownership,
        } = stream;
        drop(reader);
        drop(writer);
        Ok((response, ownership))
    }

    /// Opens a directory or browse sequence.
    pub(in crate::remote) async fn directory(
        self,
        request: RemoteRequest,
    ) -> Result<RemoteDirectoryStream, RemoteClientError> {
        directory::open(self, request).await
    }

    /// Opens one file read stream after validating its declared metadata.
    pub(in crate::remote) async fn read_file(
        self,
        request: RemoteReadRequest,
    ) -> Result<RemoteFileReader, RemoteClientError> {
        files::open(self, request).await
    }

    /// Uploads exactly `request.total_len` bytes from `reader` and returns the confirmed length.
    pub(in crate::remote) async fn write_file<R>(
        self,
        request: RemoteWriteRequest,
        reader: &mut R,
    ) -> Result<u64, RemoteClientError>
    where
        R: AsyncRead + Unpin + Send,
    {
        files::upload(self, request, reader).await
    }

    /// Spawns one remote process on an exclusive duplex stream and transfers its supervision
    /// into the returned command lease.
    pub(in crate::remote) async fn spawn_process(
        self,
        request: RemoteSpawnRequest,
    ) -> Result<crate::command::ManagedCommand, RemoteClientError> {
        process::spawn(self, request).await
    }
}

/// A reserved stream after opening; the writer half is kept even for receive-only sequences so
/// the helper never mistakes a dropped write half for a client cancellation.
pub(in crate::remote) struct OperationStream {
    reader: RecordReader<ReadHalf<RemoteStream>>,
    writer: RecordWriter<WriteHalf<RemoteStream>>,
    ownership: StreamOwnership,
}

impl OperationStream {
    fn new(
        client: RemoteClient,
        stream: RemoteStream,
        workspace: Option<Arc<WorkspaceLease>>,
        root: Option<Arc<WorkspaceRetained>>,
        fds: FdLease,
        activity: ActivityGuard,
    ) -> Self {
        let id = stream.id();
        let (read, write) = tokio::io::split(stream);
        let ownership = StreamOwnership {
            client,
            _workspace: workspace,
            _root: root,
            fds: Some(fds),
            _activity: activity,
        };
        tracing::trace!(
            connection = ownership.client.instance(),
            stream = id,
            "opened remote operation stream"
        );
        Self {
            reader: RecordReader::new(read),
            writer: RecordWriter::new(write),
            ownership,
        }
    }

    pub(in crate::remote) fn client(&self) -> &RemoteClient {
        &self.ownership.client
    }

    pub(in crate::remote) async fn send(
        &mut self,
        message: &RemoteMessage,
        body: &[u8],
    ) -> Result<(), RemoteClientError> {
        send_record(
            &mut self.writer,
            &self.ownership.client,
            message,
            body,
            "operation",
        )
        .await
    }

    pub(in crate::remote) async fn send_request(
        &mut self,
        request: RemoteRequest,
    ) -> Result<(), RemoteClientError> {
        // The stream and the descriptor peak are reserved for one class: a caller that records a cheap
        // class and then sends an expensive request must fail here instead of under-charging the helper.
        let expected = self.ownership.fds_class();
        let actual = request.resource_class();
        if expected != Some(actual) {
            return Err(RemoteClientError::protocol(format!(
                "{} was sent on a stream reserved for {expected:?}",
                method_name(&request)
            )));
        }
        self.send(&RemoteMessage::Request(request), &[]).await
    }

    pub(in crate::remote) async fn read(
        &mut self,
    ) -> Result<Option<RemoteRecord>, RemoteClientError> {
        read_record(&mut self.reader, &self.ownership.client, "operation").await
    }

    /// Splits the stream into its record halves and keeps the operation's responsibility with
    /// the caller that continues the sequence.
    pub(in crate::remote) fn into_parts(self) -> StreamParts {
        StreamParts {
            reader: self.reader,
            writer: self.writer,
            ownership: self.ownership,
        }
    }
}

/// Connection, workspace and admission ownership of one operation.
pub(in crate::remote) struct StreamOwnership {
    client: RemoteClient,
    _workspace: Option<Arc<WorkspaceLease>>,
    /// Persistent charge of the addressed workspace root, captured under the same lock that removes it
    /// on acknowledgement: an operation that captured it first keeps the descriptors to its own end.
    _root: Option<Arc<WorkspaceRetained>>,
    /// Descriptor peak held for this operation until its local cleanup really ended; `None` only
    /// after the charge was handed to an active workspace root.
    fds: Option<FdLease>,
    _activity: ActivityGuard,
}

impl StreamOwnership {
    pub(in crate::remote) fn client(&self) -> &RemoteClient {
        &self.client
    }

    fn fds_class(&self) -> Option<RemoteResourceClass> {
        self.fds.as_ref().map(FdLease::class)
    }

    /// Takes the descriptor charge out of this operation's ownership.
    ///
    /// The caller becomes responsible for releasing it at the same point the operation would have.
    pub(in crate::remote) fn take_fds(&mut self) -> Option<FdLease> {
        self.fds.take()
    }
}

impl std::fmt::Debug for StreamOwnership {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("StreamOwnership")
            .field("connection", &self.client.instance())
            .field("workspace", &self._workspace.is_some())
            .field("root", &self._root.as_ref().map(|root| root.id()))
            .field("class", &self.fds_class())
            .finish_non_exhaustive()
    }
}

/// The record halves of an opened stream together with everything that keeps it valid.
pub(in crate::remote) struct StreamParts {
    pub(in crate::remote) reader: RecordReader<ReadHalf<RemoteStream>>,
    pub(in crate::remote) writer: RecordWriter<WriteHalf<RemoteStream>>,
    pub(in crate::remote) ownership: StreamOwnership,
}

/// Counts one outstanding responsibility on its physical connection.
///
/// Operations, processes, workspace handles and in-flight `closeWorkspace` transactions all hold
/// one; only when the last one ends may an endpoint shrink the pool.
pub(in crate::remote) struct ActivityGuard {
    inner: Arc<ClientInner>,
}

impl ActivityGuard {
    pub(in crate::remote) fn new(inner: Arc<ClientInner>) -> Self {
        inner.begin_activity();
        Self { inner }
    }
}

impl Drop for ActivityGuard {
    fn drop(&mut self) {
        self.inner.end_activity();
    }
}

impl std::fmt::Debug for ActivityGuard {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("ActivityGuard")
            .field("connection", &self.inner.instance())
            .field("activity", &self.inner.activity())
            .finish()
    }
}

/// Reads one record of an owned operation stream.
pub(in crate::remote) async fn read_record(
    reader: &mut RecordReader<ReadHalf<RemoteStream>>,
    client: &RemoteClient,
    stage: &'static str,
) -> Result<Option<RemoteRecord>, RemoteClientError> {
    tokio::select! {
            // Delivered records always win, so a connection that ends while records are still buffered
            // lets its owner settle them instead of losing them to the terminal state.
            biased;
            record = reader.read() => record.map_err(|error| client.transport_failure(stage, error)),
            // A terminated connection can no longer deliver a record, and the multiplexer does not wake a
            // read whose driver already ended. Racing the driver's real end here keeps the owning
            // operation, process or transfer task from suspending forever on a stream nobody will feed.
            closed = client.inner.observe_closed() => match closed {
                // The stream never delivered its own terminal record, so a transport that ended, cleanly
                // or not, is a disconnect for this operation instead of a silent end of data.
                Ok(()) | Err(RemoteClientError::Disconnected) => Err(RemoteClientError::Disconnected),
                Err(error) => Err(error),
            },
    }
}

/// Publishes one record. Recording is encoded and length-checked before any byte is written by
/// the shared transport, so a local encoding failure cannot damage other streams.
pub(in crate::remote) async fn send_record(
    writer: &mut RecordWriter<WriteHalf<RemoteStream>>,
    client: &RemoteClient,
    message: &RemoteMessage,
    body: &[u8],
    stage: &'static str,
) -> Result<(), RemoteClientError> {
    if body.len() > MAX_RECORD_BYTES {
        return Err(RemoteClientError::protocol(format!(
            "{stage}: record body of {} bytes is too large",
            body.len()
        )));
    }
    writer
        .send(message, body)
        .await
        .map_err(|error| client.transport_failure(stage, error))
}

/// Reads the single unary response of a sequence, preserving helper application errors.
pub(in crate::remote) fn response_record(
    record: Option<RemoteRecord>,
    stage: &'static str,
) -> Result<RemoteResponse, RemoteClientError> {
    let Some(record) = record else {
        return Err(RemoteClientError::protocol(format!(
            "helper ended the {stage} stream before responding"
        )));
    };
    match record.message {
        RemoteMessage::Response(RemoteResponse::Error(error)) => {
            Err(RemoteClientError::remote(&error))
        }
        RemoteMessage::Response(response) => Ok(response),
        other => Err(RemoteClientError::protocol(format!(
            "expected a response on the {stage} stream, received {}",
            message_kind(&other)
        ))),
    }
}

/// Requires a plain acknowledgement without hiding a typed helper error.
pub(in crate::remote) fn expect_ack(response: RemoteResponse) -> Result<(), RemoteClientError> {
    match response {
        RemoteResponse::Ack => Ok(()),
        response => Err(RemoteClientError::protocol(format!(
            "expected an acknowledgement, received {}",
            response_kind(&response)
        ))),
    }
}

/// Maps a transport failure for an operation that has no owning client (handshake/bootstrap).
pub(in crate::remote) fn transport_error(
    handle: &ConnectionHandle,
    stage: &'static str,
    error: TransportError,
) -> RemoteClientError {
    let description = describe_transport_error(&error);
    let mapped = match error {
        TransportError::Closed | TransportError::Multiplex(_) => RemoteClientError::Disconnected,
        // Real I/O and driver-task failures keep their sources; both are connection-fatal.
        TransportError::Io(source) => RemoteClientError::Io { stage, source },
        TransportError::DriverTask(source) => RemoteClientError::Task {
            stage: "transport driver",
            source,
        },
        TransportError::Cancelled => RemoteClientError::Cancelled,
        TransportError::ControlAlreadyOpened => {
            RemoteClientError::protocol(format!("{stage}: {description}"))
        }
        TransportError::InvalidRecord { .. }
        | TransportError::RecordTooLarge { .. }
        | TransportError::Encoding { .. } => {
            RemoteClientError::Protocol(format!("{stage}: {description}"))
        }
    };
    // Losing the driver is what makes a locally scoped failure connection-terminal; the typed source
    // is kept either way.
    if handle.is_closed() {
        tracing::debug!(stage, "transport failed while the connection was closing");
    }
    mapped
}

/// Describes a transport failure with its source chain, without any payload bytes.
pub(in crate::remote) fn describe_transport_error(error: &TransportError) -> String {
    use std::error::Error;

    let mut description = error.to_string();
    let mut source = error.source();
    let mut depth = 0_u8;
    while let Some(cause) = source {
        if depth == 4 {
            break;
        }
        description.push_str(": ");
        description.push_str(&cause.to_string());
        source = cause.source();
        depth += 1;
    }
    description
}

/// Stable diagnostic name of a request; payload values are never logged.
pub(in crate::remote) fn method_name(request: &RemoteRequest) -> &'static str {
    match request {
        RemoteRequest::Hello { .. } => "hello",
        RemoteRequest::Heartbeat => "heartbeat",
        RemoteRequest::BrowseDirectories { .. } => "browseDirectories",
        RemoteRequest::OpenWorkspace { .. } => "openWorkspace",
        RemoteRequest::CloseWorkspace { .. } => "closeWorkspace",
        RemoteRequest::Stat(_) => "stat",
        RemoteRequest::ReadFile(_) => "readFile",
        RemoteRequest::WriteFile(_) => "writeFile",
        RemoteRequest::ListDirectory(_) => "listDirectory",
        RemoteRequest::CreateDirectory(_) => "createDirectory",
        RemoteRequest::RemovePath(_) => "removePath",
        RemoteRequest::RenamePath(_) => "renamePath",
        RemoteRequest::CopyPath(_) => "copyPath",
        RemoteRequest::Spawn(_) => "spawn",
        RemoteRequest::Terminate { .. } => "terminate",
        RemoteRequest::Shutdown => "shutdown",
    }
}

/// The opaque workspace handle one request is addressed to, when it names an already open root.
///
/// This is the only place a request's own handle is read for descriptor accounting. It never invents a
/// handle: an id this connection no longer knows stays the helper's authoritative rejection, and a
/// request that creates or does not address a root (hello, browse, open, close, terminate, shutdown,
/// heartbeat) keeps no root charge.
pub(in crate::remote) fn request_workspace_id(request: &RemoteRequest) -> Option<&str> {
    match request {
        RemoteRequest::Stat(target)
        | RemoteRequest::ListDirectory(target)
        | RemoteRequest::CreateDirectory(target) => Some(&target.workspace_id),
        RemoteRequest::ReadFile(request) => Some(&request.workspace_id),
        RemoteRequest::WriteFile(request) => Some(&request.target.workspace_id),
        RemoteRequest::RemovePath(request) => Some(&request.workspace_id),
        RemoteRequest::RenamePath(request) => Some(&request.workspace_id),
        RemoteRequest::CopyPath(request) => Some(&request.workspace_id),
        RemoteRequest::Spawn(request) => Some(&request.workspace_id),
        RemoteRequest::Hello { .. }
        | RemoteRequest::Heartbeat
        | RemoteRequest::BrowseDirectories { .. }
        | RemoteRequest::OpenWorkspace { .. }
        | RemoteRequest::CloseWorkspace { .. }
        | RemoteRequest::Terminate { .. }
        | RemoteRequest::Shutdown => None,
    }
}

/// Stable diagnostic name of a response.
pub(in crate::remote) fn response_kind(response: &RemoteResponse) -> &'static str {
    match response {
        RemoteResponse::Hello(_) => "hello",
        RemoteResponse::WorkspaceOpened(_) => "workspaceOpened",
        RemoteResponse::Stat(_) => "stat",
        RemoteResponse::Directory(_) => "directory",
        RemoteResponse::File(_) => "file",
        RemoteResponse::Ready => "ready",
        RemoteResponse::Complete => "complete",
        RemoteResponse::Transferred { .. } => "transferred",
        RemoteResponse::ProcessSpawned { .. } => "processSpawned",
        RemoteResponse::Ack => "ack",
        RemoteResponse::Error(_) => "error",
    }
}

/// Stable diagnostic name of a record message.
pub(in crate::remote) fn message_kind(message: &RemoteMessage) -> &'static str {
    match message {
        RemoteMessage::Request(request) => method_name(request),
        RemoteMessage::Response(response) => response_kind(response),
        RemoteMessage::Event(pl_protocol::remote::RemoteEvent::ProcessOutput(_)) => {
            "event:processOutput"
        }
        RemoteMessage::Event(pl_protocol::remote::RemoteEvent::ProcessExit(_)) => {
            "event:processExit"
        }
        RemoteMessage::DirectoryEntry(_) => "directoryEntry",
        RemoteMessage::Data { .. } => "data",
        RemoteMessage::UploadFinished { .. } => "uploadFinished",
        RemoteMessage::Stdin => "stdin",
        RemoteMessage::StdinClosed => "stdinClosed",
    }
}
