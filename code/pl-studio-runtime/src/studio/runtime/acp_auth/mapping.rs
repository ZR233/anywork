//! `pl-acp` 结果到产品 wire 的穷尽映射、失败文案与探测目录准备。
//!
//! 这里不持有状态、不发事件：输入是协议层的类型化结果，输出是产品 DTO 或安全摘要。原始 RPC
//! 文本、URL、stderr 与凭据都不会出现在输出里。

use std::path::PathBuf;

use anyhow::Result;
use pl_protocol::studio::{
    AcpAuthAction, AcpAuthFailure, AcpAuthFailureCode, AcpAuthMethod, AcpAuthMethodKind,
    AcpAuthStage, AcpAuthState, AcpServerInfo, StudioError, StudioErrorCode,
};

use super::registry::AcpAuthInner;

/// 类型化阶段失败（与 wire 形态一一对应）。
pub(super) struct AcpFailure {
    pub(super) code: AcpAuthFailureCode,
    pub(super) stage: AcpAuthStage,
    pub(super) retryable: bool,
}

impl AcpFailure {
    pub(super) fn failure(&self) -> AcpAuthFailure {
        AcpAuthFailure {
            code: self.code,
            stage: self.stage,
            message: canonical_failure_message(self.code, self.stage),
            retryable: self.retryable,
        }
    }

    pub(super) fn into_state(self) -> AcpAuthState {
        let failure = self.failure();
        AcpAuthState::Failed { failure }
    }
}

pub(super) fn ensure_operation_id(operation_id: &str) -> Result<()> {
    if operation_id.trim().is_empty() {
        return Err(acp_error(
            StudioErrorCode::InvalidArgument,
            "operationId 不能为空",
            false,
        ));
    }
    Ok(())
}

pub(super) fn acp_error(code: StudioErrorCode, message: &str, retryable: bool) -> anyhow::Error {
    anyhow::Error::new(StudioError::new(code, message, retryable))
}

/// 认证失败类别到 Studio 错误码的穷尽映射。
///
/// 命令阶段（例如程序路径不合法）需要立即失败时使用这里；运行期失败本身作为 typed 认证状态
/// 发布，不会被吞成 `Unchecked` 或成功。
pub(crate) fn acp_failure_studio_error_code(code: AcpAuthFailureCode) -> StudioErrorCode {
    match code {
        // 命令阶段被拒绝的两类输入是调用方参数问题；运行期同一类别仍以 typed 状态发布。
        AcpAuthFailureCode::MissingExecutable | AcpAuthFailureCode::UnsupportedMethod => {
            StudioErrorCode::InvalidArgument
        }
        AcpAuthFailureCode::Startup
        | AcpAuthFailureCode::Io
        | AcpAuthFailureCode::UnsupportedVersion
        | AcpAuthFailureCode::Probe
        | AcpAuthFailureCode::Protocol
        | AcpAuthFailureCode::Transport
        | AcpAuthFailureCode::Timeout => StudioErrorCode::Unavailable,
        AcpAuthFailureCode::Authentication => StudioErrorCode::PermissionDenied,
        AcpAuthFailureCode::ResourceLimit => StudioErrorCode::Overloaded,
        AcpAuthFailureCode::Cancelled => StudioErrorCode::Cancelled,
        AcpAuthFailureCode::StaleOperation
        | AcpAuthFailureCode::ConfigChanged
        | AcpAuthFailureCode::Cleanup => StudioErrorCode::Conflict,
        AcpAuthFailureCode::Internal => StudioErrorCode::Internal,
    }
}

pub(super) fn acp_failure_error(code: AcpAuthFailureCode, message: &str) -> anyhow::Error {
    acp_error(acp_failure_studio_error_code(code), message, false)
}

/// 协议动作映射；wire 类型不进入 pl-acp，pl-acp 类型也不进入产品 wire。
pub(super) fn protocol_action(action: &AcpAuthAction) -> pl_acp::auth::AuthAction {
    match action {
        AcpAuthAction::Check => pl_acp::auth::AuthAction::Check,
        AcpAuthAction::Authenticate { method_id } => pl_acp::auth::AuthAction::Authenticate {
            method_id: method_id.clone(),
        },
    }
}

pub(super) fn initial_state(action: &AcpAuthAction, operation_id: &str) -> AcpAuthState {
    match action {
        AcpAuthAction::Check => AcpAuthState::Checking {
            operation_id: operation_id.to_string(),
        },
        AcpAuthAction::Authenticate { method_id } => AcpAuthState::Authenticating {
            operation_id: operation_id.to_string(),
            method_id: method_id.clone(),
        },
    }
}

/// 认证进度到产品状态的映射。
///
/// `Initializing`/`Authenticating`/`Verifying` 只表达步骤；`Closing` 进入 busy 非终态
/// `Closing`，终态必须由资源收尾后的结果决定。
pub(super) fn map_progress(
    progress: &pl_acp::auth::AuthProgress,
    operation_id: &str,
    action: &AcpAuthAction,
) -> Option<AcpAuthState> {
    match progress {
        pl_acp::auth::AuthProgress::Initializing => Some(initial_state(action, operation_id)),
        pl_acp::auth::AuthProgress::Authenticating => match action {
            AcpAuthAction::Check => None,
            AcpAuthAction::Authenticate { method_id } => Some(AcpAuthState::Authenticating {
                operation_id: operation_id.to_string(),
                method_id: method_id.clone(),
            }),
        },
        pl_acp::auth::AuthProgress::Verifying => match action {
            AcpAuthAction::Check => None,
            AcpAuthAction::Authenticate { .. } => Some(AcpAuthState::Verifying {
                operation_id: operation_id.to_string(),
            }),
        },
        pl_acp::auth::AuthProgress::Closing => Some(AcpAuthState::Closing {
            operation_id: operation_id.to_string(),
            failure: None,
        }),
    }
}

pub(super) fn map_auth_server(server: Option<pl_acp::auth::ServerInfo>) -> Option<AcpServerInfo> {
    server.map(|server| AcpServerInfo {
        name: server.name,
        title: server.title,
        version: server.version,
    })
}

pub(super) fn map_auth_methods(methods: Vec<pl_acp::auth::AuthMethod>) -> Vec<AcpAuthMethod> {
    methods
        .into_iter()
        .map(|method| AcpAuthMethod {
            id: method.id,
            name: method.name,
            description: method.description,
            kind: match method.kind {
                pl_acp::auth::AuthMethodKind::Agent => AcpAuthMethodKind::Agent,
                pl_acp::auth::AuthMethodKind::Terminal => AcpAuthMethodKind::Terminal,
                pl_acp::auth::AuthMethodKind::Unsupported => AcpAuthMethodKind::Unsupported,
            },
        })
        .collect()
}

/// 协议失败到产品失败状态的穷尽映射；消息由类别与阶段生成，不转发原始 RPC 文本。
pub(super) fn map_auth_error(error: &pl_acp::auth::AuthError) -> AcpFailure {
    let code = match error.kind() {
        pl_acp::auth::AuthFailureKind::Transport => AcpAuthFailureCode::Transport,
        pl_acp::auth::AuthFailureKind::Protocol => AcpAuthFailureCode::Protocol,
        pl_acp::auth::AuthFailureKind::UnsupportedVersion => AcpAuthFailureCode::UnsupportedVersion,
        pl_acp::auth::AuthFailureKind::UnsupportedMethod => AcpAuthFailureCode::UnsupportedMethod,
        pl_acp::auth::AuthFailureKind::Authentication => AcpAuthFailureCode::Authentication,
        pl_acp::auth::AuthFailureKind::Probe => AcpAuthFailureCode::Probe,
        pl_acp::auth::AuthFailureKind::Timeout => AcpAuthFailureCode::Timeout,
        pl_acp::auth::AuthFailureKind::Cancelled => AcpAuthFailureCode::Cancelled,
        pl_acp::auth::AuthFailureKind::ResourceLimit => AcpAuthFailureCode::ResourceLimit,
        // 只表示远端探测会话关闭无法确认；本地进程/管道的收尾失败使用 Cleanup 阶段。
        pl_acp::auth::AuthFailureKind::Cleanup => AcpAuthFailureCode::Cleanup,
    };
    let stage = match error.stage() {
        pl_acp::auth::AuthStage::Initialize => AcpAuthStage::Initialize,
        pl_acp::auth::AuthStage::Authenticate => AcpAuthStage::Authenticate,
        pl_acp::auth::AuthStage::Probe => AcpAuthStage::Probe,
        pl_acp::auth::AuthStage::Close => AcpAuthStage::Close,
    };
    AcpFailure {
        code,
        stage,
        retryable: matches!(
            code,
            AcpAuthFailureCode::Authentication
                | AcpAuthFailureCode::Probe
                | AcpAuthFailureCode::Protocol
                | AcpAuthFailureCode::Transport
                | AcpAuthFailureCode::Timeout
                | AcpAuthFailureCode::ResourceLimit
                | AcpAuthFailureCode::Cancelled
                | AcpAuthFailureCode::Cleanup
        ),
    }
}

/// 面向用户的安全摘要；只由类别与阶段派生，不含 URL、token、RPC 原文或 stderr。
pub(super) fn canonical_failure_message(code: AcpAuthFailureCode, stage: AcpAuthStage) -> String {
    // 远端探测会话关闭失败与本地进程/管道收尾失败必须区分，不能互相冒充。
    let reason = match (code, stage) {
        (AcpAuthFailureCode::Cleanup, AcpAuthStage::Close) => "无法确认远端探测会话关闭",
        (AcpAuthFailureCode::Cleanup, _) => "本地进程或管道未确认退出",
        (AcpAuthFailureCode::Startup, _) => "无法启动官方 ACP server",
        (AcpAuthFailureCode::MissingExecutable, _) => "官方 ACP server 程序不可用",
        (AcpAuthFailureCode::Io, _) => "读写探测目录或管道失败",
        (AcpAuthFailureCode::UnsupportedVersion, _) => "该 server 的 ACP 版本不受支持",
        (AcpAuthFailureCode::UnsupportedMethod, _) => "该认证方法当前不受支持",
        (AcpAuthFailureCode::Authentication, _) => "登录未完成",
        (AcpAuthFailureCode::Probe, _) => "连接验证未通过",
        (AcpAuthFailureCode::Protocol, _) => "server 响应不符合已实现的协议范围",
        (AcpAuthFailureCode::Transport, _) => "与 server 的连接已中断",
        (AcpAuthFailureCode::Timeout, _) => "等待超时",
        (AcpAuthFailureCode::ResourceLimit, _) => "输出超出预算",
        (AcpAuthFailureCode::Cancelled, _) => "已取消",
        (AcpAuthFailureCode::StaleOperation, _) => "该操作已被新的接入配置取代",
        (AcpAuthFailureCode::ConfigChanged, _) => "该接入的连接配置已变化",
        (AcpAuthFailureCode::Internal, _) => "内部状态不一致",
    };
    let step = match stage {
        AcpAuthStage::Process => "启动",
        AcpAuthStage::Config => "配置",
        AcpAuthStage::Initialize => "连接协商",
        AcpAuthStage::Authenticate => "登录",
        AcpAuthStage::Probe => "连接验证",
        AcpAuthStage::Close => "连接关闭",
        AcpAuthStage::Cleanup => "资源收尾",
    };
    format!("{step}阶段失败：{reason}")
}

/// 准备接入专属空探测目录；不存在或旧内容一律重建，绝不使用用户项目目录。
pub(super) async fn prepare_probe_dir(
    inner: &AcpAuthInner,
    account_id: &str,
) -> Result<PathBuf, String> {
    let directory = inner
        .store
        .acp_probe_dir(account_id)
        .map_err(|error| error.to_string())?;
    match tokio::fs::remove_dir_all(&directory).await {
        Ok(()) => {}
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => return Err(error.to_string()),
    }
    tokio::fs::create_dir_all(&directory)
        .await
        .map_err(|error| error.to_string())?;
    Ok(directory)
}
