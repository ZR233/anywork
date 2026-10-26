//! ACP 官方 server 自动准备的 Bridge DTO。
//!
//! 字段与 `pl_protocol::studio::acp_install` 一一对应；这里是 FRB 的镜像层，不解释状态、不重排
//! revision。安装是共享资产，拥有独立快照与回执，不与 `acpAuth` 或 Settings 混用（见 design/25）。

use serde::{Deserialize, Serialize};

use super::{BridgeAcpProvider, BridgeStudioCommandReceipt};

/// 自动准备的平台可用性；`target` 只由后端按宿主平台产生。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum BridgeAcpInstallAvailability {
    Available { target: String },
    UnsupportedPlatform,
}

/// 一次准备冻结的发行身份。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct BridgeAcpInstallRelease {
    pub version: String,
    pub target: String,
    pub archive_url: String,
    pub sha256: Option<String>,
}

/// 当前阶段的实际进度；未知总量与未成样本的速度都是 `None`。
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub struct BridgeAcpInstallProgress {
    pub completed_bytes: u64,
    pub total_bytes: Option<u64>,
    pub bytes_per_second: Option<u64>,
}

/// 已就绪的官方 server；`reused` 表示复用既有完整安装。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct BridgeAcpInstalledServer {
    pub installation_id: String,
    pub release: BridgeAcpInstallRelease,
    pub program: String,
    pub ready_at: i64,
    pub reused: bool,
}

/// 失败发生在安装链的哪一步。
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum BridgeAcpInstallStage {
    Resolve,
    WaitForLock,
    Download,
    Verify,
    Extract,
    Publish,
    Close,
}

/// 安装失败的稳定分类。
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum BridgeAcpInstallFailureCode {
    UnsupportedPlatform,
    SourceRejected,
    Network,
    Timeout,
    TooLarge,
    ChecksumMismatch,
    InvalidArchive,
    MissingExecutable,
    CacheCorrupt,
    Io,
    Busy,
    StaleOperation,
    Cancelled,
    ResourceClose,
}

/// 一次安装失败的安全摘要；不含原始 URL、代理凭据或本地文件路径。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct BridgeAcpInstallFailure {
    pub code: BridgeAcpInstallFailureCode,
    pub stage: BridgeAcpInstallStage,
    pub message: String,
    pub retryable: bool,
}

/// 一个 provider 的安装观察状态；终态同样保留 operation 身份。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum BridgeAcpInstallState {
    Idle,
    Resolving {
        operation_id: String,
    },
    Waiting {
        operation_id: String,
        release: BridgeAcpInstallRelease,
    },
    Downloading {
        operation_id: String,
        release: BridgeAcpInstallRelease,
        progress: BridgeAcpInstallProgress,
        retry_count: u32,
    },
    Verifying {
        operation_id: String,
        release: BridgeAcpInstallRelease,
        progress: BridgeAcpInstallProgress,
    },
    Extracting {
        operation_id: String,
        release: BridgeAcpInstallRelease,
        progress: BridgeAcpInstallProgress,
    },
    Publishing {
        operation_id: String,
        release: BridgeAcpInstallRelease,
    },
    Closing {
        operation_id: String,
        failure: Option<BridgeAcpInstallFailure>,
    },
    Ready {
        operation_id: String,
        server: BridgeAcpInstalledServer,
    },
    Cancelling {
        operation_id: String,
    },
    Cancelled {
        operation_id: String,
    },
    Failed {
        operation_id: String,
        failure: BridgeAcpInstallFailure,
    },
}

/// 一个 provider 的安装条目。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct BridgeAcpInstallEntry {
    pub provider: BridgeAcpProvider,
    pub state: BridgeAcpInstallState,
}

/// 安装 topic 的 canonical 快照；revision 独立于 Settings 与 `acpAuth`。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct BridgeAcpInstallSnapshot {
    pub revision: u64,
    pub updated_at: i64,
    pub installations: Vec<BridgeAcpInstallEntry>,
}

/// 安装命令回执：受理身份与受理时快照。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAcpInstallCommandReply {
    pub receipt: BridgeStudioCommandReceipt,
    pub snapshot: BridgeAcpInstallSnapshot,
}
