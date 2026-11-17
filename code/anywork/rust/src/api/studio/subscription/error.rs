//! 生命周期状态到现有桥接错误和退出报告的转换。

use pl_lifecycle::{CloseError, CloseReport, OpenError};

use crate::api::studio::types::{BridgeError, BridgeShutdownIssue};

fn internal(message: &str) -> BridgeError {
    pl_studio_runtime::StudioError::new(
        pl_studio_runtime::StudioErrorCode::Internal,
        message,
        false,
    )
    .into()
}

pub(crate) fn open_error(error: OpenError<BridgeError>) -> BridgeError {
    match error {
        OpenError::ScopeClosed => BridgeError::runtime_stopped(),
        OpenError::Cancelled => pl_studio_runtime::StudioError::new(
            pl_studio_runtime::StudioErrorCode::Cancelled,
            "Observation creation was cancelled",
            false,
        )
        .into(),
        OpenError::Resource(error) => (*error).clone(),
        OpenError::Panicked => internal("Observation creation panicked"),
        OpenError::WorkerStopped => internal("Observation creation worker stopped"),
    }
}

pub(crate) fn close_error(error: CloseError<BridgeError>) -> BridgeError {
    match error {
        CloseError::Resource(error) => (*error).clone(),
        CloseError::Panicked => internal("Observation cleanup panicked"),
        CloseError::WorkerStopped => internal("Observation cleanup worker stopped"),
    }
}

pub(crate) fn shutdown_issues(report: CloseReport<BridgeError>) -> Vec<BridgeShutdownIssue> {
    let mut issues = Vec::new();
    for failure in report.failures {
        let error = close_error(failure.error);
        let code = serde_json::to_value(error.code)
            .ok()
            .and_then(|value| value.as_str().map(str::to_owned))
            .unwrap_or_else(|| "internal".to_owned());
        tracing::error!(
            stage = failure.resource.label,
            resource = failure.resource.resource_id.get(),
            code = %code,
            correlation_id = %error.correlation_id,
            "observation lifecycle did not finish cleanly"
        );
        issues.push(BridgeShutdownIssue {
            stage: failure.resource.label.to_owned(),
            code,
            // 退出 DTO 的 message 是脱敏诊断，不承载业务正文或原始 details_json。
            // 资源端点返回原始 BridgeError；ScopeOwner 保留完整原错误供重试。
            message: format!("观察资源 {} 未确认完成", failure.resource.resource_id.get()),
            retryable: error.retryable,
            correlation_id: error.correlation_id,
        });
    }
    for pending in report.pending {
        let error = internal("Observation cleanup exceeded the exit deadline");
        issues.push(BridgeShutdownIssue {
            stage: pending.resource.label.to_owned(),
            code: "timeout".to_owned(),
            message: format!(
                "资源 {} 的 {:?} 尚未完成；原资源继续保留",
                pending.resource.resource_id.get(),
                pending.phase
            ),
            retryable: true,
            correlation_id: error.correlation_id,
        });
    }
    if !report.workers_finished && issues.is_empty() {
        let error = internal("Observation workers did not finish");
        issues.push(BridgeShutdownIssue {
            stage: "subscriptions".to_owned(),
            code: "timeout".to_owned(),
            message: error.message,
            retryable: true,
            correlation_id: error.correlation_id,
        });
    }
    issues
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    #[test]
    fn resource_errors_keep_the_original_wire_fields() {
        let original = BridgeError {
            code: crate::api::studio::types::BridgeErrorCode::Storage,
            message: "native failure".to_owned(),
            retryable: true,
            correlation_id: "same-correlation".to_owned(),
            details_json: Some(r#"{"native":"details"}"#.to_owned()),
        };
        assert_eq!(
            open_error(OpenError::Resource(Arc::new(original.clone()))),
            original
        );
        assert_eq!(
            close_error(CloseError::Resource(Arc::new(original.clone()))),
            original
        );
    }
}
