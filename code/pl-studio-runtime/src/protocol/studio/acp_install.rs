//! ACP 官方 server 自动准备（下载/校验/解压/发布）的 typed wire DTO。
//!
//! 这些类型是产品与外围 adapter（FRB/HTTP）之间的唯一公共契约：安装是**共享资产**而非某个
//! 账号的字段，因此它拥有独立 revision、独立 topic 与独立命令，不进入 Settings 快照，也不与
//! `acpAuth` 的认证状态共用水位。这里不携带原始 URL 之外的任何凭据、代理信息、本地文件路径
//! 或库错误链——失败只暴露稳定 code/phase/安全摘要（见 design/28 §28.6、§28.7）。
//!
//! 安装的版本、target、archive 与启动 argv 全部来自产品固定清单，运行期不读取远端 registry，
//! 也不解析远端版本（design/28 §28.5）。

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use super::{AcpProvider, StudioCommandReceipt};

/// 自动准备的平台可用性。
///
/// `target` 只由后端按运行 Studio 的宿主平台产生（`linux-x86_64`/`linux-aarch64`/
/// `windows-x86_64`/`windows-aarch64`），客户端显示平台不决定下载目标。不支持的平台没有可准备的
/// 官方发行，接入的检查会明确失败为 `unsupportedPlatform`，不存在本地程序或任意版本回退。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", tag = "kind", deny_unknown_fields)]
pub enum AcpInstallAvailability {
    Available { target: String },
    UnsupportedPlatform,
}

/// 一次准备冻结的发行身份：解析完成后不再随远端 registry 变化。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpInstallRelease {
    pub version: String,
    pub target: String,
    pub archive_url: String,
    /// 发行方公布的摘要；`None` 表示官方未提供，此时信任边界仅到官方 HTTPS 来源。
    pub sha256: Option<String>,
}

/// 当前下载阶段的实际进度。
///
/// `completed_bytes` 是本地当前有效长度（重试续传时可能真实回退），不是多次传输累计；
/// `total_bytes` 未知时为 `None`，不合成百分比；`bytes_per_second` 尚未形成样本时为 `None`。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpInstallProgress {
    pub completed_bytes: u64,
    pub total_bytes: Option<u64>,
    pub bytes_per_second: Option<u64>,
}

impl AcpInstallProgress {
    pub const fn empty() -> Self {
        Self {
            completed_bytes: 0,
            total_bytes: None,
            bytes_per_second: None,
        }
    }
}

/// 已就绪的官方 server：绝对 program（只读诊断）、安装身份与复用标记。
///
/// 固定 argv 留在内部启动边界，不出现在账户编辑/保存 DTO 与这里。`reused` 表示本次操作复用了
/// 既有完整安装，而不是重新下载；它就绪只证明 server 可启动，不证明账号已保存或已认证。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpInstalledServer {
    pub installation_id: String,
    pub release: AcpInstallRelease,
    pub program: String,
    pub ready_at: i64,
    pub reused: bool,
}

/// 失败发生在安装链的哪一步。
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum AcpInstallStage {
    /// 解析产品固定清单（本地、不联网）。
    Resolve,
    WaitForLock,
    Download,
    Verify,
    Extract,
    Publish,
    Close,
}

impl AcpInstallStage {
    /// 稳定的阶段标签；用于安全日志与诊断，不随内部重构变化。
    pub const fn label(self) -> &'static str {
        match self {
            Self::Resolve => "resolve",
            Self::WaitForLock => "waitForLock",
            Self::Download => "download",
            Self::Verify => "verify",
            Self::Extract => "extract",
            Self::Publish => "publish",
            Self::Close => "close",
        }
    }
}

/// 安装失败的稳定分类；恢复决策只依赖它，不解析 message。
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum AcpInstallFailureCode {
    /// 当前宿主平台没有可自动准备的官方包。
    UnsupportedPlatform,
    /// 来源、重定向或格式不在允许范围内。
    SourceRejected,
    Network,
    Timeout,
    /// 元数据、包或解压结果超过预算。
    TooLarge,
    ChecksumMismatch,
    InvalidArchive,
    MissingExecutable,
    /// 已发布安装回执与实际内容不一致；现场保留，不静默修复。
    CacheCorrupt,
    Io,
    Busy,
    StaleOperation,
    Cancelled,
    /// 物理资源未能确认收束。
    ResourceClose,
}

impl AcpInstallFailureCode {
    /// 稳定的失败标签；用于安全日志与诊断，不随内部重构变化。
    pub const fn label(self) -> &'static str {
        match self {
            Self::UnsupportedPlatform => "unsupportedPlatform",
            Self::SourceRejected => "sourceRejected",
            Self::Network => "network",
            Self::Timeout => "timeout",
            Self::TooLarge => "tooLarge",
            Self::ChecksumMismatch => "checksumMismatch",
            Self::InvalidArchive => "invalidArchive",
            Self::MissingExecutable => "missingExecutable",
            Self::CacheCorrupt => "cacheCorrupt",
            Self::Io => "io",
            Self::Busy => "busy",
            Self::StaleOperation => "staleOperation",
            Self::Cancelled => "cancelled",
            Self::ResourceClose => "resourceClose",
        }
    }
}

/// 一次安装失败的安全摘要：不含原始 URL、代理凭据、完整文件路径或库错误链。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpInstallFailure {
    pub code: AcpInstallFailureCode,
    pub stage: AcpInstallStage,
    pub message: String,
    pub retryable: bool,
}

/// 一个 provider 当前宿主 target 的安装观察状态。
///
/// 除 `Idle` 外每个阶段都携带受理时的 operation 身份；终态同样保留它，供草稿与迟到回执
/// 正确关联，而不是靠时间或先后顺序猜归属。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    tag = "kind",
    deny_unknown_fields
)]
pub enum AcpInstallState {
    /// 本次 runtime 生命周期内尚未准备过。
    Idle,
    Resolving {
        operation_id: String,
    },
    /// 已冻结发行身份，正在等待该资产的跨进程锁。
    Waiting {
        operation_id: String,
        release: AcpInstallRelease,
    },
    Downloading {
        operation_id: String,
        release: AcpInstallRelease,
        progress: AcpInstallProgress,
        /// 本次操作累计的自动重试次数（最多 3），不是库的连续失败计数。
        retry_count: u32,
    },
    Verifying {
        operation_id: String,
        release: AcpInstallRelease,
        progress: AcpInstallProgress,
    },
    Extracting {
        operation_id: String,
        release: AcpInstallRelease,
        progress: AcpInstallProgress,
    },
    /// 正在原子发布；这是不可被业务取消回滚的提交阶段。
    Publishing {
        operation_id: String,
        release: AcpInstallRelease,
    },
    /// 业务阶段已结束、物理任务仍在收束的非终态。
    Closing {
        operation_id: String,
        failure: Option<AcpInstallFailure>,
    },
    Ready {
        operation_id: String,
        server: AcpInstalledServer,
    },
    Cancelling {
        operation_id: String,
    },
    Cancelled {
        operation_id: String,
    },
    Failed {
        operation_id: String,
        failure: AcpInstallFailure,
    },
}

impl AcpInstallState {
    /// 该状态归属的 operation 身份；`Idle` 为 `None`。
    pub fn operation_id(&self) -> Option<&str> {
        match self {
            Self::Idle => None,
            Self::Resolving { operation_id }
            | Self::Waiting { operation_id, .. }
            | Self::Downloading { operation_id, .. }
            | Self::Verifying { operation_id, .. }
            | Self::Extracting { operation_id, .. }
            | Self::Publishing { operation_id, .. }
            | Self::Closing { operation_id, .. }
            | Self::Ready { operation_id, .. }
            | Self::Cancelling { operation_id }
            | Self::Cancelled { operation_id }
            | Self::Failed { operation_id, .. } => Some(operation_id.as_str()),
        }
    }

    /// 是否已到终态；终态之后才发布 Ready/Cancelled/Failed 并释放占用。
    pub fn is_terminal(&self) -> bool {
        matches!(
            self,
            Self::Ready { .. } | Self::Cancelled { .. } | Self::Failed { .. }
        )
    }
}

/// 一个 provider 的安装条目。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpInstallEntry {
    pub provider: AcpProvider,
    pub state: AcpInstallState,
}

/// 安装 topic 的 canonical 快照；revision 独立于 Settings 与 `acpAuth`。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpInstallSnapshot {
    pub revision: u64,
    pub updated_at: i64,
    pub installations: Vec<AcpInstallEntry>,
}

impl AcpInstallSnapshot {
    /// 某 provider 的当前状态；没有条目时是 `Idle`，不是"已准备"。
    pub fn state_of(&self, provider: AcpProvider) -> AcpInstallState {
        self.installations
            .iter()
            .find(|entry| entry.provider == provider)
            .map(|entry| entry.state.clone())
            .unwrap_or(AcpInstallState::Idle)
    }
}

/// 安装命令回执：受理身份与受理时的 canonical 快照。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpInstallCommandReply {
    pub receipt: StudioCommandReceipt,
    pub snapshot: AcpInstallSnapshot,
}

/// 显式准备请求；只表达 provider，平台 target 由后端决定。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StartAcpInstallRequest {
    pub operation_id: String,
    pub provider: AcpProvider,
}

/// 显式取消请求；`target_operation_id` 必须命中当前 operation 才生效。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CancelAcpInstallRequest {
    pub operation_id: String,
    pub provider: AcpProvider,
    pub target_operation_id: String,
}
