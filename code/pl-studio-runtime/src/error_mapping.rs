use pl_protocol::PureError;
use pl_protocol::studio::{StudioError, StudioErrorCode};

use crate::ConfigRuntimeError;
use crate::{StudioDatabaseError, StudioUpdateError, StudioUpdateErrorCode};

/// Maps an internal runtime failure to the shared, redacted Studio API error.
///
/// Classification is based exclusively on typed error sources. Unclassified
/// failures are logged for diagnostics and cross the adapter boundary only as
/// a redacted internal error.
pub fn studio_error_from_anyhow(error: anyhow::Error) -> StudioError {
    studio_error_from_ref(&error)
}

/// Borrowing variant used by diagnostics that must keep the original error chain.
pub fn studio_error_from_anyhow_ref(error: &anyhow::Error) -> StudioError {
    studio_error_from_ref(error)
}

fn studio_error_from_ref(error: &anyhow::Error) -> StudioError {
    if let Some(error) = error.downcast_ref::<StudioError>() {
        return error.clone();
    }
    if let Some(error) = error
        .chain()
        .find_map(|cause| cause.downcast_ref::<crate::agent::worktree::WorktreeError>())
    {
        use crate::agent::worktree::WorktreeError;
        let (code, retryable) = match error {
            WorktreeError::IdentityMismatch(_) => (StudioErrorCode::Conflict, false),
            WorktreeError::InvalidResource(_) => (StudioErrorCode::InvalidArgument, false),
            WorktreeError::Missing => (StudioErrorCode::Unavailable, true),
            WorktreeError::LocalIo { .. } => (StudioErrorCode::Storage, true),
            WorktreeError::GitLaunchFailed { .. }
            | WorktreeError::GitTimedOut { .. }
            | WorktreeError::GitExited { .. }
            | WorktreeError::GitStatusUnknown { .. }
            | WorktreeError::Remote { .. }
            | WorktreeError::RemoteExecution { .. }
            | WorktreeError::RemoteDownload { .. }
            | WorktreeError::RemoteFile { .. } => (StudioErrorCode::Unavailable, true),
        };
        return StudioError::new(code, error.safe_diagnostic(), retryable);
    }
    if let Some(startup) = error.downcast_ref::<crate::StudioStartupError>() {
        if let Some(ConfigRuntimeError::ModeDefinitions(cause)) = error
            .chain()
            .find_map(|cause| cause.downcast_ref::<ConfigRuntimeError>())
        {
            return StudioError::new(
                StudioErrorCode::InvalidArgument,
                format!("工作模式配置加载失败，原文件已保留：{cause:#}"),
                false,
            )
            .with_details(
                serde_json::json!({"startupStep": startup.step, "startupKind": "ModeDefinitions"}),
            );
        }
        if startup.kind == crate::StudioStartupErrorKind::Migration {
            if error
                .chain()
                .any(|cause| cause.is::<crate::studio::AccountUsageCacheMigrationError>())
            {
                return StudioError::new(
                    StudioErrorCode::InvalidArgument,
                    "账号用量缓存升级失败，原记录已保留。请使用支持该数据版本的应用重试。",
                    false,
                )
                .with_details(
                    serde_json::json!({"startupStep": startup.step, "startupKind": "Migration"}),
                );
            }
            return StudioError::new(
                StudioErrorCode::InvalidArgument,
                "配置迁移失败，原文件已保留。请检查模型标识与配置声明后重新启动。",
                false,
            )
            .with_details(
                serde_json::json!({"startupStep": startup.step, "startupKind": "Migration"}),
            );
        }
        if let Some(original) = error
            .chain()
            .find_map(|cause| cause.downcast_ref::<StudioError>())
        {
            return original.clone();
        }
        let (code, retryable) = match startup.kind {
            crate::StudioStartupErrorKind::PersistentData => (StudioErrorCode::Storage, false),
            crate::StudioStartupErrorKind::Environment => (StudioErrorCode::Storage, true),
            crate::StudioStartupErrorKind::Cancelled => (StudioErrorCode::Cancelled, true),
            crate::StudioStartupErrorKind::Internal => (StudioErrorCode::Internal, false),
            crate::StudioStartupErrorKind::Migration => (StudioErrorCode::InvalidArgument, false),
        };
        return StudioError::new(code, format!("应用初始化失败（{}，{:?}）", startup.step, startup.kind), retryable)
            .with_details(serde_json::json!({"startupStep": startup.step, "startupKind": format!("{:?}", startup.kind)}));
    }
    if error.downcast_ref::<StudioDatabaseError>().is_some()
        || error.downcast_ref::<std::io::Error>().is_some()
    {
        return StudioError::storage();
    }
    if let Some(error) = error.downcast_ref::<pl_core::chat::ChatError>() {
        return chat_error(error);
    }
    if let Some(error) = error.downcast_ref::<ConfigRuntimeError>() {
        return match error {
            ConfigRuntimeError::ModelDiscoveryUnsupported => {
                StudioError::invalid_argument("Model discovery is unsupported").with_reason(
                    pl_protocol::studio::StudioErrorReason::AccountModelDiscoveryUnsupported,
                    serde_json::json!({}),
                )
            }
            ConfigRuntimeError::StaleRevision { expected, actual } => StudioError::new(
                StudioErrorCode::StaleRevision,
                "Studio data changed; reload and try again",
                true,
            )
            .with_details(serde_json::json!({
                "expectedRevision": expected,
                "actualRevision": actual,
            })),
            ConfigRuntimeError::Core(error) => pure_error(error),
            ConfigRuntimeError::BundledAgentCatalog(_) => StudioError::internal(),
            ConfigRuntimeError::ModeDefinitions(error) => StudioError::new(
                StudioErrorCode::InvalidArgument,
                format!("工作模式配置无效，原文件已保留：{error:#}"),
                false,
            ),
            ConfigRuntimeError::Migration(_) => StudioError::new(
                StudioErrorCode::InvalidArgument,
                "配置迁移失败，原文件已保留。请检查模型标识与配置声明。",
                false,
            ),
        };
    }
    if error.downcast_ref::<serde_json::Error>().is_some() {
        return StudioError::new(
            StudioErrorCode::Protocol,
            "Studio received incompatible protocol data",
            false,
        );
    }
    if let Some(error) = error.downcast_ref::<StudioUpdateError>() {
        return update_error(error);
    }
    // A malformed product interaction identity is a caller mistake, not a runtime failure: it must
    // stay a typed rejection on every entry that decodes one, including the decision path.
    if error
        .downcast_ref::<crate::thread_assembler::InteractionKeyError>()
        .is_some()
    {
        return StudioError::invalid_argument(
            "The interaction identity is not a Studio interaction id",
        );
    }
    if let Some(error) = error.downcast_ref::<pl_core::thread::ThreadError>()
        && let Some(studio_error) = thread_error(error)
    {
        return studio_error;
    }
    if let Some(error) = error.downcast_ref::<pl_tool::remote::RemoteClientError>() {
        return remote_client_error(error);
    }
    if let Some(error) = error.downcast_ref::<PureError>() {
        return pure_error(error);
    }

    let studio_error = StudioError::internal();
    tracing::error!(
        correlation_id = %studio_error.correlation_id,
        operation = "studioRuntime",
        error_code = "internal",
        diagnostic_bytes = error.to_string().len(),
        "unclassified Studio runtime failure"
    );
    studio_error
}

fn remote_client_error(error: &pl_tool::remote::RemoteClientError) -> StudioError {
    use pl_tool::remote::RemoteClientError;

    match error {
        RemoteClientError::AuthenticationFailed(failure) => {
            let mut details = serde_json::json!({
                "sshErrorKind": "authenticationFailed",
            });
            if let Some(offered) = failure.password_offered() {
                details["sshPasswordOffered"] = serde_json::Value::Bool(offered);
            }
            StudioError::new(
                StudioErrorCode::PermissionDenied,
                format!("SSH authentication required or failed: {failure}"),
                true,
            )
            .with_details(details)
        }
        RemoteClientError::Disconnected
        | RemoteClientError::Cancelled
        | RemoteClientError::ManagerClosing => {
            StudioError::new(StudioErrorCode::Unavailable, error.to_string(), true)
        }
        RemoteClientError::Protocol(reason) => {
            StudioError::new(StudioErrorCode::InvalidArgument, reason.clone(), false)
        }
        RemoteClientError::Remote { code, message } => StudioError::new(
            StudioErrorCode::Unavailable,
            format!("{code:?}: {message}"),
            false,
        ),
    }
}

/// Maps one Timeline content failure to its public category.
///
/// The classification comes from the typed variant; no error text is parsed. Messages stay generic
/// and the structured details carry only identities, field keys and sizes — never content.
fn chat_error(error: &pl_core::chat::ChatError) -> StudioError {
    use pl_core::chat::ChatError as Chat;
    match error {
        Chat::InvalidArgument(reason) => StudioError::new(
            StudioErrorCode::InvalidArgument,
            "Studio received an invalid timeline request",
            false,
        )
        .with_details(serde_json::json!({ "reason": reason })),
        Chat::NotFound(identity) => StudioError::new(
            StudioErrorCode::NotFound,
            "The requested timeline content is not available",
            false,
        )
        .with_details(serde_json::json!({ "identity": identity })),
        Chat::StaleRevision {
            item_id,
            field,
            revision,
        } => StudioError::new(
            StudioErrorCode::StaleRevision,
            "Timeline content changed; reload the item before reading it again",
            true,
        )
        .with_details(serde_json::json!({
            "itemId": item_id,
            "field": field.to_string(),
            "revision": revision,
        })),
        Chat::Cancelled => StudioError::new(
            StudioErrorCode::Cancelled,
            "The timeline content observation is closed",
            false,
        ),
        Chat::Overloaded(reason) => StudioError::new(
            StudioErrorCode::Overloaded,
            "Timeline content exceeds the display budget",
            false,
        )
        .with_details(serde_json::json!({ "reason": reason })),
        Chat::ReadInvalidated => StudioError::new(
            StudioErrorCode::Busy,
            "The timeline range is not fully readable yet; retry the read",
            true,
        ),
        Chat::Conflict(identity) => StudioError::new(
            StudioErrorCode::Conflict,
            "Timeline content conflicts with the fact this Thread already holds",
            false,
        )
        .with_details(serde_json::json!({ "identity": identity })),
        Chat::History(_) => StudioError::storage(),
        Chat::OrderExhausted | Chat::OrderNotInitialized => StudioError::internal(),
    }
}

/// Maps the prompt-admission failures of a Thread to their public category.
///
/// Only variants with a distinct, actionable meaning are classified; every
/// other variant returns `None` so the caller keeps the redacted internal
/// fallback. Messages never embed the source error text or any caller context.
fn thread_error(error: &pl_core::thread::ThreadError) -> Option<StudioError> {
    match error {
        pl_core::thread::ThreadError::PendingInteraction => Some(StudioError::new(
            StudioErrorCode::Conflict,
            "Resolve the pending Studio interaction before sending another prompt",
            false,
        )),
        pl_core::thread::ThreadError::StoragePressure => Some(StudioError::new(
            StudioErrorCode::Busy,
            "Studio is still persisting earlier work; retry shortly",
            true,
        )),
        pl_core::thread::ThreadError::StorageRecoveryPending { .. } => Some(StudioError::new(
            StudioErrorCode::Busy,
            "Studio has not saved the recovered history yet; retry saving before continuing",
            true,
        )),
        pl_core::thread::ThreadError::StorageRecoveryUnverified { .. } => Some(StudioError::new(
            StudioErrorCode::Busy,
            "Studio has not verified that this save fault recovered; retry saving before continuing",
            true,
        )),
        pl_core::thread::ThreadError::Storage(_) => Some(StudioError::storage()),
        pl_core::thread::ThreadError::NoContinuation => Some(StudioError::new(
            StudioErrorCode::Conflict,
            "This Thread has no continuation to claim",
            false,
        )),
        pl_core::thread::ThreadError::InvalidControlInput => Some(StudioError::new(
            StudioErrorCode::InvalidArgument,
            "Studio sent a continuation control input that carries content",
            false,
        )),
        pl_core::thread::ThreadError::Closed => Some(StudioError::new(
            StudioErrorCode::RuntimeStopped,
            "Studio runtime stopped; restart the runtime to continue",
            false,
        )),
        _ => None,
    }
}

fn pure_error(error: &PureError) -> StudioError {
    match error {
        PureError::PermissionDenied(_) | PureError::SandboxError(_) => StudioError::new(
            StudioErrorCode::PermissionDenied,
            "Studio does not have permission to complete this operation",
            false,
        ),
        PureError::ConfigError(_) => StudioError::new(
            StudioErrorCode::InvalidArgument,
            "Studio received invalid configuration",
            false,
        ),
        PureError::SerdeJson(_) | PureError::Protocol(_) => StudioError::new(
            StudioErrorCode::Protocol,
            "Studio received incompatible protocol data",
            false,
        ),
        PureError::Io(_) | PureError::MemoryError(_) => StudioError::storage(),
        PureError::HttpError(_)
        | PureError::TransientModelTransport { .. }
        | PureError::ProviderCapacity { .. }
        | PureError::Provider(_) => StudioError::new(
            StudioErrorCode::Unavailable,
            "A required Studio service is unavailable",
            true,
        ),
        PureError::LlmError(_)
        | PureError::ContextOverflow(_)
        | PureError::ToolNotFound(_)
        | PureError::ToolExecutionFailed { .. }
        | PureError::AgentLimitReached { .. }
        | PureError::AgentDepthLimitReached { .. } => StudioError::internal(),
    }
}

fn update_error(error: &StudioUpdateError) -> StudioError {
    let code = error.code();
    let retryable = matches!(
        code,
        StudioUpdateErrorCode::Network
            | StudioUpdateErrorCode::InstallInProgress
            | StudioUpdateErrorCode::Io
    );
    let studio_code = match code {
        StudioUpdateErrorCode::InstallInProgress => StudioErrorCode::Busy,
        StudioUpdateErrorCode::Cancelled => StudioErrorCode::Cancelled,
        StudioUpdateErrorCode::CancellationTooLate => StudioErrorCode::CancellationTooLate,
        StudioUpdateErrorCode::Network => StudioErrorCode::Unavailable,
        StudioUpdateErrorCode::InvalidManifest
        | StudioUpdateErrorCode::UnsupportedPlatform
        | StudioUpdateErrorCode::DownloadTooLarge
        | StudioUpdateErrorCode::DownloadIncomplete
        | StudioUpdateErrorCode::HashMismatch
        | StudioUpdateErrorCode::SignatureInvalid
        | StudioUpdateErrorCode::InstallerLaunchFailed
        | StudioUpdateErrorCode::Io => StudioErrorCode::Update,
    };
    StudioError::new(
        studio_code,
        format!("Studio update could not be completed: {error}"),
        retryable,
    )
}
