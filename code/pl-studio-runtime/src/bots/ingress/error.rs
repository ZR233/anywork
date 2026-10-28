//! 保留 typed 失败阶段；诊断文本不参与重试或受理判定。

use crate::bots::InboundWorkOutcome;
use crate::bots::protocol::error::{FeishuError, FeishuErrorKind};
use pl_core::thread::ThreadError;
use pl_protocol::studio::{StudioError, StudioErrorCode};

pub(super) fn attention(diagnostic: impl Into<String>) -> InboundWorkOutcome {
    InboundWorkOutcome::NeedsAttention {
        diagnostic: diagnostic.into(),
    }
}

pub(super) fn retry(diagnostic: impl Into<String>) -> InboundWorkOutcome {
    InboundWorkOutcome::Recoverable {
        diagnostic: diagnostic.into(),
    }
}

pub(super) fn failure(context: &'static str, error: FeishuError) -> InboundWorkOutcome {
    if error.kind() == FeishuErrorKind::Cancelled {
        InboundWorkOutcome::Interrupted
    } else if error.retryable() {
        retry(format!("{context}: {error}"))
    } else {
        attention(format!("{context}: {error}"))
    }
}

pub(super) fn history(context: &'static str, error: anyhow::Error) -> InboundWorkOutcome {
    failure(context, FeishuError::history_read(context, error))
}

/// 仅在提交真实返回且重新读取原 input 为 Absent 后使用。
///
/// core 的 Closed 既可能是 mailbox 未发送，也可能是回执丢失；资源错误还可能发生在
/// core 接受后的 accepted() 中。这些情况都没有「stage_input 前」证明，不能自动重投。
/// InvalidIdentity 的相同摘要已由 Studio submit 的幂等边界处理，剩余 Err 不猜成重放。
pub(super) fn submit_absent(error: anyhow::Error) -> InboundWorkOutcome {
    if let Some(thread_error) = error
        .chain()
        .find_map(|cause| cause.downcast_ref::<ThreadError>())
    {
        return match thread_error {
            ThreadError::StoragePressure | ThreadError::PendingInteraction => {
                retry("bot input admission was deferred before staging")
            }
            ThreadError::Storage(_) => {
                history("bot input storage admission failed before staging", error)
            }
            ThreadError::InvalidIdentity => {
                attention("bot input identity was rejected without a matching canonical receipt")
            }
            ThreadError::RevisionExhausted => {
                attention("bot input admission revision is exhausted")
            }
            // No other ThreadError proves that the request never reached stage_input.
            _ => attention(
                "bot input acceptance is unproven after a Thread failure; automatic resubmission is disabled",
            ),
        };
    }
    if let Some(error) = error
        .chain()
        .find_map(|cause| cause.downcast_ref::<StudioError>())
    {
        return if matches!(
            error.code,
            StudioErrorCode::Cancelled | StudioErrorCode::RuntimeStopped
        ) {
            InboundWorkOutcome::Interrupted
        } else if error.retryable {
            retry(format!(
                "bot input admission failed ({})",
                error.code.label()
            ))
        } else {
            attention(format!(
                "bot input admission rejected ({})",
                error.code.label()
            ))
        };
    }
    // In submit_owned_prompt_with_admission, IO/DB/config/resource preparation finishes before
    // the core call. After it, accepted() can still fail an untyped receipt-integrity check,
    // whereas collect_after_acceptance()/residency.touch() do not propagate errors. With all
    // ThreadError cases handled above, the original typed environmental causes therefore keep
    // their pre-admission retry semantics. The untyped integrity/unknown case stays attention.
    history(
        "bot input submission failed without a canonical receipt",
        error,
    )
}
