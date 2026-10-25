//! 安装失败的安全映射与命令错误构造。
//!
//! 这里不持有状态、不发事件。输入是内部阶段结果，输出只有稳定 code/stage/安全摘要；原始 URL、
//! 代理凭据、完整本地路径与库错误链都不进入输出（见 design/28 §28.6、§28.7）。

use anyhow::Result;
use pl_protocol::studio::{
    AcpInstallFailure, AcpInstallFailureCode, AcpInstallStage, StudioError, StudioErrorCode,
};

pub(super) fn ensure_operation_id(operation_id: &str) -> Result<()> {
    if operation_id.trim().is_empty() {
        return Err(command_error(
            StudioErrorCode::InvalidArgument,
            "operationId 不能为空",
            false,
        ));
    }
    Ok(())
}

pub(super) fn command_error(
    code: StudioErrorCode,
    message: &str,
    retryable: bool,
) -> anyhow::Error {
    anyhow::Error::new(StudioError::new(code, message, retryable))
}

/// 构造一次类型化安装失败；`message` 由类别固定生成，绝不拼接原始错误文本。
pub(super) fn failure(
    code: AcpInstallFailureCode,
    stage: AcpInstallStage,
    retryable: bool,
) -> AcpInstallFailure {
    AcpInstallFailure {
        code,
        stage,
        message: canonical_message(code).to_string(),
        retryable,
    }
}

/// 带明确安全摘要的失败：只用于"已提交但未确认持久化"这类不能由类别概括的事实。
pub(super) fn failure_with_message(
    code: AcpInstallFailureCode,
    stage: AcpInstallStage,
    retryable: bool,
    message: &str,
) -> AcpInstallFailure {
    AcpInstallFailure {
        code,
        stage,
        message: message.to_string(),
        retryable,
    }
}

/// 失败类别的稳定安全摘要；对外只表达发生了什么，不表达内部路径或对端内容。
fn canonical_message(code: AcpInstallFailureCode) -> &'static str {
    match code {
        AcpInstallFailureCode::UnsupportedPlatform => "当前平台不支持自动准备官方 server",
        AcpInstallFailureCode::SourceRejected => "下载来源不在允许的官方范围内",
        AcpInstallFailureCode::Network => "下载官方 server 时网络失败",
        AcpInstallFailureCode::Timeout => "准备官方 server 超时",
        AcpInstallFailureCode::TooLarge => "官方 server 包超过允许的大小",
        AcpInstallFailureCode::ChecksumMismatch => "官方 server 包摘要不匹配",
        AcpInstallFailureCode::InvalidArchive => "官方 server 包不是可接受的 ZIP",
        AcpInstallFailureCode::MissingExecutable => "官方 server 包内缺少可执行入口",
        AcpInstallFailureCode::CacheCorrupt => "已安装的官方 server 校验失败",
        AcpInstallFailureCode::Io => "准备官方 server 时本地文件操作失败",
        AcpInstallFailureCode::Busy => "该平台已有进行中的准备操作",
        AcpInstallFailureCode::StaleOperation => "目标准备操作已不是当前操作",
        AcpInstallFailureCode::Cancelled => "准备官方 server 已取消",
        AcpInstallFailureCode::ResourceClose => "准备官方 server 的本地资源未能确认收束",
    }
}

/// 命令阶段立即失败时的 Studio 错误码映射；运行期失败仍以 typed 状态发布。
pub(crate) fn failure_studio_error_code(code: AcpInstallFailureCode) -> StudioErrorCode {
    match code {
        AcpInstallFailureCode::UnsupportedPlatform | AcpInstallFailureCode::SourceRejected => {
            StudioErrorCode::InvalidArgument
        }
        AcpInstallFailureCode::Network | AcpInstallFailureCode::Timeout => {
            StudioErrorCode::Unavailable
        }
        AcpInstallFailureCode::TooLarge => StudioErrorCode::Overloaded,
        AcpInstallFailureCode::Busy => StudioErrorCode::Busy,
        AcpInstallFailureCode::StaleOperation => StudioErrorCode::Conflict,
        AcpInstallFailureCode::Cancelled => StudioErrorCode::Cancelled,
        AcpInstallFailureCode::ChecksumMismatch
        | AcpInstallFailureCode::InvalidArchive
        | AcpInstallFailureCode::MissingExecutable
        | AcpInstallFailureCode::CacheCorrupt
        | AcpInstallFailureCode::Io
        | AcpInstallFailureCode::ResourceClose => StudioErrorCode::Storage,
    }
}

/// 命令阶段把失败变成可返回的错误；message 仍是安全摘要。
pub(super) fn failure_command_error(failure: &AcpInstallFailure) -> anyhow::Error {
    command_error(
        failure_studio_error_code(failure.code),
        &failure.message,
        failure.retryable,
    )
}
