//! SSH remote helper 的 transport-neutral wire 类型。

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

pub const REMOTE_PROTOCOL_VERSION: u32 = 9;

/// Allocation for one connection, derived by its host from current resources and demand.
/// Values are bytes, not eagerly allocated buffers. Existing grants survive shrinkage.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteAllocation {
    pub resident_bytes: usize,
    pub fragment_bytes: usize,
    pub ordinary_operations: usize,
    pub stream_window: u32,
    pub connection_window: u32,
}

/// Identity of a helper instance; the credential is never formatted into diagnostics.
#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteSession {
    pub instance_id: String,
    pub socket_path: String,
    pub credential: String,
    pub epoch: u64,
}

impl std::fmt::Debug for RemoteSession {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("RemoteSession")
            .field("instance_id", &self.instance_id)
            .field("epoch", &self.epoch)
            .finish_non_exhaustive()
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "method",
    content = "params",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum RemoteRequest {
    Hello {
        protocol_version: u32,
    },
    Attach {
        session: RemoteSession,
    },
    Configure {
        allocation: RemoteAllocation,
    },
    Heartbeat,
    OutputConsumed {
        process_id: String,
        sequence: u64,
    },
    ReleaseProcess {
        process_id: String,
    },
    WaitProcess {
        process_id: String,
    },
    OperationResult {
        operation_id: String,
    },
    ReleaseOperation {
        operation_id: String,
    },
    BrowseDirectories {
        path: Option<String>,
    },
    OpenWorkspace {
        path: String,
    },
    CloseWorkspace {
        workspace_id: String,
    },
    Stat(RemotePathRequest),
    BeginWrite(RemoteWriteRequest),
    WriteChunk {
        transfer_id: String,
        offset: u64,
        sha256: String,
    },
    TransferStatus {
        transfer_id: String,
    },
    CommitWrite {
        transfer_id: String,
        length: u64,
        sha256: String,
    },
    CloseTransfer {
        transfer_id: String,
    },
    OpenRead(RemotePathRequest),
    ReadFileChunk {
        transfer_id: String,
        offset: u64,
        max_bytes: usize,
    },
    ListDirectory(RemotePathRequest),
    ContinueDirectory {
        cursor: String,
    },
    CloseDirectory {
        cursor: String,
    },
    CreateDirectory(RemotePathRequest),
    RemovePath(RemoteRemoveRequest),
    RenamePath(RemoteRenameRequest),
    CopyPath(RemoteCopyRequest),
    Spawn(RemoteSpawnRequest),
    WriteStdin {
        process_id: String,
        offset: u64,
    },
    CloseStdin {
        process_id: String,
    },
    Terminate {
        process_id: String,
    },
    Shutdown,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "result",
    content = "payload",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum RemoteResponse {
    Hello(RemoteHello),
    Directories(RemoteDirectoryListing),
    WorkspaceOpened(RemoteWorkspaceOpened),
    Stat(RemoteFileStat),
    ByteRange {
        offset: u64,
        total_len: u64,
    },
    Directory(RemoteDirectoryListing),
    ProcessSpawned {
        process_id: String,
    },
    ProcessExited(RemoteProcessExit),
    Transfer(RemoteTransferStatus),
    ChunkWritten {
        offset: u64,
        length: u64,
        confirmed_offset: u64,
    },
    InputOffset {
        offset: u64,
    },
    Capacity(RemoteAllocation),
    Heartbeat(RemoteHeartbeat),
    Ack,
    Error(RemoteError),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "event",
    content = "payload",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum RemoteEvent {
    ProcessOutput(RemoteProcessOutput),
    ProcessExit(RemoteProcessExit),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteHello {
    pub protocol_version: u32,
    pub helper_version: String,
    pub os: String,
    pub architecture: String,
    pub capabilities: Vec<RemoteCapability>,
    pub shell: RemoteShellDescriptor,
    pub session: RemoteSession,
    pub allocation: RemoteAllocation,
}

/// Shell selected by the helper for all remote command processes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum RemoteShellDialect {
    Bash,
    Sh,
    Pwsh,
    #[serde(rename = "powershell")]
    PowerShell,
    Cmd,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteShellDescriptor {
    pub dialect: RemoteShellDialect,
    pub path: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum RemoteCapability {
    DirectoryBrowse,
    WorkspaceFiles,
    ObservableExec,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteWorkspaceOpened {
    pub workspace_id: String,
    pub canonical_path: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemotePathRequest {
    pub workspace_id: String,
    pub path: String,
}

/// Explicit filesystem write intent; never implemented by a client-side read/modify/write sequence.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum RemoteWriteMode {
    Create,
    Overwrite,
    Append,
}

/// A write body applies to this path under the specified mode.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteWriteRequest {
    pub target: RemotePathRequest,
    pub mode: RemoteWriteMode,
    pub total_len: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteRemoveRequest {
    pub workspace_id: String,
    pub path: String,
    pub recursive: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteRenameRequest {
    pub workspace_id: String,
    pub source: String,
    pub target: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteCopyRequest {
    pub workspace_id: String,
    pub source: String,
    pub target: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteSpawnRequest {
    pub process_id: String,
    pub workspace_id: String,
    pub program: String,
    pub arguments: Vec<String>,
    pub remove_environment: Vec<String>,
    pub cwd: String,
    pub environment: BTreeMap<String, String>,
    pub capture: RemoteCapture,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteFileStat {
    pub path: String,
    pub is_file: bool,
    pub is_directory: bool,
    pub len: Option<u64>,
    pub readonly: bool,
    pub modified_at: Option<i64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteDirectoryListing {
    pub path: String,
    pub parent: Option<String>,
    pub entries: Vec<RemoteDirectoryEntry>,
    pub next_cursor: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteDirectoryEntry {
    pub name: String,
    pub path: String,
    pub is_directory: bool,
    pub is_symlink: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteProcessOutput {
    pub process_id: String,
    pub sequence: u64,
    pub stream: RemoteOutputStream,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum RemoteOutputStream {
    Stdout,
    Stderr,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteProcessExit {
    pub process_id: String,
    pub exit_code: Option<i32>,
    pub signal: Option<i32>,
    pub failure: Option<RemoteError>,
    pub capture: Option<RemoteCaptureReceipt>,
}

/// 命令归档与常驻协议进程分别声明捕获策略，LSP 不写命令日志。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    tag = "kind"
)]
pub enum RemoteCapture {
    None,
    File {
        path: String,
        plan: RemoteCapturePlan,
    },
}

/// Opaque host-generated capture formatting, interpreted by the shared physical writer.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteCapturePlan {
    pub header: String,
    pub stdout_prefix: String,
    pub stderr_prefix: String,
    pub terminate_line: bool,
    pub limit_bytes: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteTransferStatus {
    pub transfer_id: String,
    pub offset: u64,
    pub total_len: Option<u64>,
    pub revision: Option<String>,
    pub sha256: Option<String>,
    pub committed: bool,
}

/// One SSE record. Binary output is encoded only at this textual event boundary.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteOutputRecord {
    pub sequence: u64,
    pub event: RemoteEvent,
    pub bytes: String,
}

/// 由实际写盘的 helper 在物理进程和两路输出收束后交回。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteCaptureReceipt {
    pub limit_bytes: u64,
    pub charged_bytes: u64,
    /// 实际读到但因预算拒绝写入的成本，不估算尚未读取的内核缓冲。
    pub refused_bytes: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteError {
    pub code: RemoteErrorCode,
    pub message: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum RemoteErrorCode {
    OutputLimitExceeded,
    InvalidRequest,
    ProtocolMismatch,
    WorkspaceNotFound,
    WorkspaceEscape,
    PathNotFound,
    ProcessNotFound,
    Io,
    Unsupported,
    RemoteDisconnected,
    ResourceExhausted,
    SessionExpired,
    StaleConnection,
    OutcomeUnknown,
    OperationNotStarted,
    SourceChanged,
    InvalidCursor,
}

impl RemoteRequest {
    pub fn is_metadata(&self) -> bool {
        matches!(self, Self::Stat(_))
    }
    pub fn is_lease_control(&self) -> bool {
        matches!(
            self,
            Self::Heartbeat
                | Self::Configure { .. }
                | Self::Hello { .. }
                | Self::Attach { .. }
                | Self::Shutdown
        )
    }
    pub fn is_observation(&self) -> bool {
        matches!(
            self,
            Self::OperationResult { .. } | Self::TransferStatus { .. } | Self::WaitProcess { .. }
        )
    }
    pub fn is_control(&self) -> bool {
        matches!(
            self,
            Self::Hello { .. }
                | Self::Attach { .. }
                | Self::Configure { .. }
                | Self::Heartbeat
                | Self::Stat(_)
                | Self::Terminate { .. }
                | Self::Shutdown
                | Self::OutputConsumed { .. }
                | Self::ReleaseProcess { .. }
                | Self::WaitProcess { .. }
                | Self::ReleaseOperation { .. }
                | Self::OperationResult { .. }
                | Self::CloseWorkspace { .. }
                | Self::CloseDirectory { .. }
                | Self::CloseTransfer { .. }
                | Self::TransferStatus { .. }
        )
    }
}

/// Operational facts returned with the existing heartbeat, not an extra polling service.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteHeartbeat {
    pub allocation: RemoteAllocation,
    pub epoch: u64,
    pub active_connections: usize,
    pub owner_pid: u32,
    pub workspaces: usize,
    pub processes: usize,
    pub cursors: usize,
    pub transfers: usize,
    pub retained_operations: usize,
    pub pending_tasks: usize,
    pub reserved_bytes: usize,
    pub peak_reserved_bytes: usize,
    pub received_bytes: u64,
    pub sent_bytes: u64,
    pub operation_queries: u64,
    pub replayed_body_bytes: u64,
    pub last_failure: Option<RemoteOperationFailure>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteOperationFailure {
    pub operation_id: String,
    pub epoch: u64,
    pub code: RemoteErrorCode,
    pub request_bytes: usize,
    pub reply_bytes: usize,
    pub phase: String,
    pub reserved_bytes: usize,
    pub wait_reason: Option<String>,
}

/// Monotonic elapsed time for one retained operation, in microseconds. Replaying its receipt
/// preserves these measurements; it does not pretend a second physical execution occurred.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteOperationTiming {
    pub admission_wait_micros: u64,
    pub receive_micros: u64,
    pub execution_micros: u64,
    pub filesystem_micros: u64,
    pub transfer_backpressure_micros: u64,
}
