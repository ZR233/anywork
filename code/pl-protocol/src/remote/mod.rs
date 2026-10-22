//! SSH remote helper 的 transport-neutral wire 类型。

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

pub const REMOTE_PROTOCOL_VERSION: u32 = 9;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteRecordHeader {
    pub message: RemoteMessage,
    pub body_len: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "payload",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum RemoteMessage {
    Request(RemoteRequest),
    Response(RemoteResponse),
    Event(RemoteEvent),
    DirectoryEntry(RemoteDirectoryEntry),
    /// Binary body bytes at this absolute file offset (zero-based for uploads).
    Data {
        offset: u64,
    },
    /// Explicit upload completion; EOF alone never commits a file.
    UploadFinished {
        total_len: u64,
    },
    Stdin,
    StdinClosed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "method",
    content = "params",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum RemoteRequest {
    Hello { protocol_version: u32 },
    Heartbeat,
    BrowseDirectories { path: Option<String> },
    OpenWorkspace { path: String },
    CloseWorkspace { workspace_id: String },
    Stat(RemotePathRequest),
    ReadFile(RemoteReadRequest),
    WriteFile(RemoteWriteRequest),
    ListDirectory(RemotePathRequest),
    CreateDirectory(RemotePathRequest),
    RemovePath(RemoteRemoveRequest),
    RenamePath(RemoteRenameRequest),
    CopyPath(RemoteCopyRequest),
    Spawn(RemoteSpawnRequest),
    Terminate { process_id: String },
    Shutdown,
}

impl RemoteRequest {
    /// Classifies the request's descriptor responsibility, independently of transport scheduling.
    pub fn resource_class(&self) -> RemoteResourceClass {
        match self {
            Self::Hello { .. }
            | Self::Heartbeat
            | Self::CloseWorkspace { .. }
            | Self::Terminate { .. }
            | Self::Shutdown => RemoteResourceClass::Control,
            Self::OpenWorkspace { .. } => RemoteResourceClass::OpenWorkspace,
            Self::BrowseDirectories { .. } | Self::ListDirectory(_) => {
                RemoteResourceClass::Directory
            }
            Self::ReadFile(_) => RemoteResourceClass::ReadFile,
            Self::WriteFile(_) => RemoteResourceClass::WriteFile,
            Self::Spawn(_) => RemoteResourceClass::Spawn,
            Self::CopyPath(request) => {
                if request.recursive {
                    RemoteResourceClass::Recursive
                } else {
                    RemoteResourceClass::CopyFile
                }
            }
            Self::RemovePath(request) => {
                if request.recursive {
                    RemoteResourceClass::Recursive
                } else {
                    RemoteResourceClass::Metadata
                }
            }
            Self::Stat(_) | Self::CreateDirectory(_) | Self::RenamePath(_) => {
                RemoteResourceClass::Metadata
            }
        }
    }
}

/// Descriptor ownership class; not another field on the wire request.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RemoteResourceClass {
    Control,
    OpenWorkspace,
    Metadata,
    Directory,
    ReadFile,
    WriteFile,
    CopyFile,
    /// Exclusive use of a physical helper's operation descriptor budget.
    Recursive,
    Spawn,
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
    WorkspaceOpened(RemoteWorkspaceOpened),
    Stat(RemoteFileStat),
    Directory(RemoteDirectoryMetadata),
    File(RemoteFileMetadata),
    /// File destination is prepared; the uploader may start sending chunks.
    Ready,
    /// Successful end of a directory sequence, distinct from transport EOF.
    Complete,
    /// Successful file transfer (and, for writes, publication) receipt.
    Transferred {
        bytes: u64,
    },
    ProcessSpawned {
        process_id: String,
    },
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
    pub resources: RemoteResourceLimits,
}

/// Per-physical-helper descriptor capacity, independent of the multiplexer's stream capacity.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteResourceLimits {
    pub operation_fds: u32,
    pub workspace_fds: u32,
    pub costs: RemoteResourceCosts,
}

/// Descriptor peaks advertised by the helper; consumers do not duplicate implementation costs.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteResourceCosts {
    pub workspace_open: u32,
    pub workspace_retained: u32,
    pub metadata: u32,
    pub directory: u32,
    pub read_file: u32,
    pub write_file: u32,
    pub copy_file: u32,
    pub spawn: u32,
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
pub struct RemoteReadRequest {
    pub workspace_id: String,
    pub path: String,
    pub offset: u64,
    /// Range length, or the remainder of the opened file when absent.
    pub max_bytes: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteFileMetadata {
    pub offset: u64,
    pub total_len: u64,
    pub transfer_len: u64,
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
    pub recursive: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteSpawnRequest {
    pub process_id: String,
    pub workspace_id: String,
    pub command: String,
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
pub struct RemoteDirectoryMetadata {
    pub path: String,
    pub parent: Option<String>,
}

/// Consumer-owned aggregate for GUI APIs; never a wire response record.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteDirectoryListing {
    pub path: String,
    pub parent: Option<String>,
    pub entries: Vec<RemoteDirectoryEntry>,
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
    /// Starts at one and increases within this process, not across the connection.
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
    File { path: String, limit_bytes: u64 },
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
    /// The operation could not acquire its helper-owned resource budget; never implies replay safety.
    ResourceExhausted,
    InvalidRequest,
    ProtocolMismatch,
    WorkspaceNotFound,
    WorkspaceEscape,
    PathNotFound,
    ProcessNotFound,
    Io,
    Unsupported,
    RemoteDisconnected,
    TransferIncomplete,
    InvalidRecord,
    Cancelled,
}
