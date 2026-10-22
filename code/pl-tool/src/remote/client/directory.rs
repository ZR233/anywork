//! 目录序列：元数据、逐条 entry 与明确终结，绝不把目录全集放进一条记录。

use pl_protocol::remote::{
    RemoteDirectoryEntry, RemoteDirectoryMetadata, RemoteMessage, RemoteRequest, RemoteResponse,
};

use super::super::error::RemoteClientError;
use super::RemoteClient;
use super::session::OperationStream;
use super::session::{StreamLease, message_kind, response_kind, response_record};

/// Lifecycle of one directory sequence.
///
/// A corrupt or unterminated sequence becomes [`SequenceState::Failed`] permanently: the damaged
/// stream (and its physical permit) is dropped and later calls can never resume reading it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SequenceState {
    Streaming,
    Complete,
    Failed,
}

/// One incremental directory enumeration owned by its consumer.
///
/// Entries arrive one at a time; the sequence ends only with an explicit completion record, so a
/// bare transport EOF is reported as a failure instead of an empty tail.
pub struct RemoteDirectoryStream {
    client: RemoteClient,
    metadata: RemoteDirectoryMetadata,
    stream: Option<OperationStream>,
    state: SequenceState,
    failure: Option<RemoteClientError>,
}

impl std::fmt::Debug for RemoteDirectoryStream {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("RemoteDirectoryStream")
            .field("connection", &self.client.instance())
            .field("path", &self.metadata.path)
            .field("has_parent", &self.metadata.parent.is_some())
            .field("state", &self.state)
            .finish()
    }
}

impl RemoteDirectoryStream {
    /// The validated directory metadata that opened this sequence.
    pub fn metadata(&self) -> &RemoteDirectoryMetadata {
        &self.metadata
    }

    /// Reads the next entry, `None` after the explicit completion record.
    ///
    /// # Errors
    /// Reports a typed helper error, a transport failure, or a sequence that ended without an
    /// explicit completion. Any such failure is terminal for this stream.
    pub async fn next_entry(&mut self) -> Result<Option<RemoteDirectoryEntry>, RemoteClientError> {
        match self.state {
            SequenceState::Complete => return Ok(None),
            SequenceState::Failed => {
                return Err(self
                    .failure
                    .clone()
                    .unwrap_or(RemoteClientError::Disconnected));
            }
            SequenceState::Streaming => {}
        }
        let read = match self.stream.as_mut() {
            Some(stream) => stream.read().await,
            None => {
                return self.fail(RemoteClientError::protocol(
                    "directory stream is no longer readable",
                ));
            }
        };
        match read {
            Err(error) => self.fail(error),
            Ok(None) => self.fail(RemoteClientError::protocol(
                "directory stream ended without a completion record",
            )),
            Ok(Some(record)) => match record.message {
                RemoteMessage::DirectoryEntry(entry) => Ok(Some(entry)),
                RemoteMessage::Response(RemoteResponse::Complete) => {
                    self.state = SequenceState::Complete;
                    self.stream = None;
                    Ok(None)
                }
                RemoteMessage::Response(RemoteResponse::Error(error)) => {
                    self.fail(RemoteClientError::remote(&error))
                }
                other => self.fail(RemoteClientError::protocol(format!(
                    "unexpected {} in a directory sequence",
                    message_kind(&other)
                ))),
            },
        }
    }

    /// Terminal failure: the damaged stream and its permit are released and never read again.
    fn fail<T>(&mut self, error: RemoteClientError) -> Result<T, RemoteClientError> {
        self.stream = None;
        self.state = SequenceState::Failed;
        self.failure = Some(error.clone());
        Err(error)
    }
}

/// Opens one directory sequence after its metadata record.
pub(super) async fn open(
    lease: StreamLease,
    request: RemoteRequest,
) -> Result<RemoteDirectoryStream, RemoteClientError> {
    let mut stream = lease.open_stream().await?;
    stream.send_request(request).await?;
    let record = stream.read().await?;
    match response_record(record, "directory")? {
        RemoteResponse::Directory(metadata) => Ok(RemoteDirectoryStream {
            client: stream.client().clone(),
            metadata,
            stream: Some(stream),
            state: SequenceState::Streaming,
            failure: None,
        }),
        response => Err(RemoteClientError::protocol(format!(
            "expected directory metadata, received {}",
            response_kind(&response)
        ))),
    }
}
