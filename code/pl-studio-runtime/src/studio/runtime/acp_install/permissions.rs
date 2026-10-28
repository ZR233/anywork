//! Unix 受管对象的权限位核验；Windows 依托用户目录的原生 ACL。

use std::os::unix::fs::PermissionsExt;
use std::path::Path;

use pl_protocol::studio::{AcpInstallFailure, AcpInstallFailureCode, AcpInstallStage};

use super::mapping::failure_with_message;

/// 目录必须是 0700；文件不得包含其他用户写位与特殊权限位。只读核验，不改既有权限。
pub(super) fn verify(
    path: &Path,
    is_directory: bool,
    stage: AcpInstallStage,
) -> Result<(), AcpInstallFailure> {
    let metadata = std::fs::symlink_metadata(path).map_err(|_| {
        failure_with_message(
            AcpInstallFailureCode::Io,
            stage,
            false,
            "无法确认受管对象的私有权限，请检查文件系统权限后重试",
        )
    })?;
    let mode = metadata.permissions().mode() & 0o7777;
    let private = if is_directory {
        mode == super::paths::DIRECTORY_MODE
    } else {
        mode & 0o022 == 0 && mode & 0o7000 == 0
    };
    if private {
        Ok(())
    } else {
        tracing::debug!(
            mode = format_args!("{mode:04o}"),
            "rejecting ACP install object that is not private"
        );
        Err(failure_with_message(
            AcpInstallFailureCode::Io,
            stage,
            false,
            "受管对象的权限不是产品私有权限，请检查后重试",
        ))
    }
}
