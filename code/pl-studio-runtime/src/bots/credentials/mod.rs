//! Credential version selection and recoverable bot configuration transactions.
mod commit;
mod journal;
mod legacy_migration;

use crate::bots::config::BotConfigFile;
use crate::bots::protocol::error::{FeishuError, FeishuErrorKind};
use crate::config::{
    BotCredentialCapability, BotCredentialIoError, BotCredentialIoKind, BotCredentialRef,
};
use crate::{BotCredentialAvailability, BotCredentialOperation, BotDiagnostic, BotSecretUpdate};
use commit::{
    CredentialChange, abandon_prepared_credentials_with_fs, commit_prepared_credentials_with_fs,
    ensure_journal_identity, inspect_decided, missing_secret_error,
    prepare_bot_credentials_with_fs, recover_operation_with_fs,
};
pub use journal::has_credential_journal;
use journal::{CredentialJournal, JournalFs, LocalJournalFs, read_journal};
use legacy_migration::{
    VERSIONED_CREDENTIAL_CONFIG_SCHEMA, migrate_legacy_config, retry_completed_migration_cleanup,
};
use std::path::Path;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CredentialDecision {
    Applied,
    NotApplied,
    Uncertain,
}

#[derive(Clone)]
pub struct CredentialCommit {
    pub decision: CredentialDecision,
    pub config: BotConfigFile,
    pub availability: BotCredentialAvailability,
    pub operation: BotCredentialOperation,
    pub secret: Option<String>,
    pub invalidate: bool,
    pub diagnostic: Option<BotDiagnostic>,
    pub operation_id: String,
    /// 仅当配置提交已确定（Applied）或可发布的原配置仍在（NotApplied）时为 true。
    /// Uncertain 与尚无 config.toml/previous 的 NotApplied 不得据此发布机器人。
    pub publishable: bool,
}

impl std::fmt::Debug for CredentialCommit {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("CredentialCommit")
            .field("decision", &self.decision)
            .field("config", &self.config)
            .field("availability", &self.availability)
            .field("operation", &self.operation)
            .field("secret", &self.secret.as_ref().map(|_| "<redacted>"))
            .field("invalidate", &self.invalidate)
            .field("diagnostic", &self.diagnostic)
            .field("operation_id", &self.operation_id)
            .field("publishable", &self.publishable)
            .finish()
    }
}

/// 目录恢复的结构化结果。`config` 仅在可发布的确定配置时为 Some。
#[derive(Clone)]
pub struct CredentialRecovery {
    pub decision: CredentialDecision,
    pub config: Option<BotConfigFile>,
    pub availability: BotCredentialAvailability,
    pub operation: BotCredentialOperation,
    pub secret: Option<String>,
    pub invalidate: bool,
    pub diagnostic: Option<BotDiagnostic>,
    pub operation_id: Option<String>,
    pub reserved_app_id: Option<String>,
    /// 本次操作原配置的应用（存在时）：未决恢复仍须同时保护旧关联占用。
    pub previous_app_id: Option<String>,
}

impl std::fmt::Debug for CredentialRecovery {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("CredentialRecovery")
            .field("decision", &self.decision)
            .field("config", &self.config)
            .field("availability", &self.availability)
            .field("operation", &self.operation)
            .field("secret", &self.secret.as_ref().map(|_| "<redacted>"))
            .field("invalidate", &self.invalidate)
            .field("diagnostic", &self.diagnostic)
            .field("operation_id", &self.operation_id)
            .field("reserved_app_id", &self.reserved_app_id)
            .field("previous_app_id", &self.previous_app_id)
            .finish()
    }
}

/// 阻塞准备完成后交给异步 owner 的交接物。尚未写入目标配置。
pub struct PreparedCredential {
    pub operation_id: String,
    pub target: BotConfigFile,
    pub invalidate: bool,
    journal: CredentialJournal,
}

impl std::fmt::Debug for PreparedCredential {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("PreparedCredential")
            .field("operation_id", &self.operation_id)
            .field("target", &self.target)
            .field("invalidate", &self.invalidate)
            .finish()
    }
}

pub enum CredentialPrepare {
    Decided(Box<CredentialCommit>),
    Ready(Box<PreparedCredential>),
}

impl CredentialRecovery {
    pub fn publishable_config(&self) -> Option<&BotConfigFile> {
        match self.decision {
            CredentialDecision::Uncertain => None,
            CredentialDecision::Applied | CredentialDecision::NotApplied => self.config.as_ref(),
        }
    }
}

pub fn auth_invalidate(previous: Option<&BotConfigFile>, current: &BotConfigFile) -> bool {
    match previous {
        None => current.selected_ref.is_some(),
        Some(previous) => {
            previous.selected_ref != current.selected_ref
                || previous.feishu().app_id != current.feishu().app_id
        }
    }
}

struct InspectedCredential {
    availability: BotCredentialAvailability,
    secret: Option<String>,
    diagnostic: Option<BotDiagnostic>,
}

fn directory_identity_error() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Protocol,
        "bot directory identity does not match its configuration",
        false,
        None,
    )
}

fn ensure_config_identity(
    expected_bot_id: &str,
    config: &BotConfigFile,
) -> Result<(), FeishuError> {
    if config.id == expected_bot_id {
        Ok(())
    } else {
        Err(directory_identity_error())
    }
}

fn inspect_idle(
    credentials: &BotCredentialCapability,
    config: BotConfigFile,
) -> CredentialRecovery {
    let inspected = inspect_decided(credentials, &config, config.selected_ref.as_ref());
    CredentialRecovery {
        decision: CredentialDecision::Applied,
        config: Some(config),
        availability: inspected.availability,
        operation: BotCredentialOperation::Idle,
        secret: inspected.secret,
        invalidate: false,
        diagnostic: inspected.diagnostic,
        operation_id: None,
        reserved_app_id: None,
        previous_app_id: None,
    }
}

fn recovery_from_commit(
    commit: CredentialCommit,
    candidate_app_id: Option<String>,
    previous_app_id: Option<String>,
) -> CredentialRecovery {
    let publishable = commit.publishable;
    let reserved_app_id = match (&commit.decision, &commit.operation, publishable) {
        // 未决提交必须保留 journal 的目标应用；实际文件中的旧配置应用只作为
        // 原关联占用另行传递，不能替代候选目标。
        (CredentialDecision::Uncertain, _, _) => candidate_app_id
            .clone()
            .or_else(|| Some(commit.config.feishu().app_id.clone())),
        (
            CredentialDecision::NotApplied | CredentialDecision::Applied,
            BotCredentialOperation::CleanupPending {
                config_committed: false,
                ..
            },
            _,
        ) => candidate_app_id
            .clone()
            .or_else(|| Some(commit.config.feishu().app_id.clone())),
        (
            CredentialDecision::NotApplied | CredentialDecision::Applied,
            BotCredentialOperation::CleanupPending { .. },
            false,
        ) => Some(commit.config.feishu().app_id.clone()),
        _ => None,
    };
    CredentialRecovery {
        decision: commit.decision,
        config: publishable.then_some(commit.config),
        availability: commit.availability,
        operation: commit.operation,
        secret: commit.secret,
        invalidate: commit.invalidate,
        diagnostic: commit.diagnostic,
        operation_id: Some(commit.operation_id),
        reserved_app_id,
        previous_app_id,
    }
}

fn ref_for_persist(
    persist: crate::config::BotProtectedPersist,
    version: String,
) -> BotCredentialRef {
    match persist {
        crate::config::BotProtectedPersist::Stored => BotCredentialRef::system(version),
        crate::config::BotProtectedPersist::SessionOnly => BotCredentialRef::session(version),
    }
}

fn map_io(error: BotCredentialIoError) -> FeishuError {
    match error.kind {
        BotCredentialIoKind::Missing => missing_secret_error(),
        BotCredentialIoKind::Unavailable => FeishuError::new(
            FeishuErrorKind::Unavailable,
            "bot credential store is unavailable",
            true,
            None,
        ),
        BotCredentialIoKind::Invalid => FeishuError::new(
            FeishuErrorKind::Protocol,
            "bot credential material is invalid",
            false,
            None,
        ),
    }
}

fn io_error(error: std::io::Error) -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        format!("bot credential file failed: {error}"),
        true,
        None,
    )
    .with_source(error)
}

fn recover_bot_directory_with_fs(
    fs: &dyn JournalFs,
    dir: &Path,
    expected_bot_id: &str,
    credentials: &BotCredentialCapability,
    loaded: Option<BotConfigFile>,
) -> Result<CredentialRecovery, FeishuError> {
    if let Some(config) = &loaded {
        ensure_config_identity(expected_bot_id, config)?;
    }
    if let Some(journal) = read_journal(dir)? {
        ensure_journal_identity(expected_bot_id, &journal)?;
        // 消费 journal 前保留候选目标应用：回退到旧配置时仍须保留该候选占用。
        let candidate_app_id = journal.target.feishu().app_id.clone();
        let previous_app_id = journal
            .previous
            .as_ref()
            .map(|previous| previous.feishu().app_id.clone());
        let recovered = recover_operation_with_fs(fs, dir, credentials, journal)?;
        return Ok(recovery_from_commit(
            recovered,
            Some(candidate_app_id),
            previous_app_id,
        ));
    }
    let config = match loaded {
        Some(config) if config.schema_version < VERSIONED_CREDENTIAL_CONFIG_SCHEMA => {
            migrate_legacy_config(dir, credentials, config)?
        }
        Some(config) => {
            retry_completed_migration_cleanup(dir, &config);
            config
        }
        None => {
            return Err(FeishuError::new(
                FeishuErrorKind::Protocol,
                "bot directory has no recoverable config",
                false,
                None,
            ));
        }
    };
    Ok(inspect_idle(credentials, config))
}

pub fn prepare_bot_credentials(
    dir: &Path,
    expected_bot_id: &str,
    credentials: &BotCredentialCapability,
    previous: &BotConfigFile,
    candidate: BotConfigFile,
    secret: BotSecretUpdate,
    operation_id: &str,
) -> Result<CredentialPrepare, FeishuError> {
    prepare_bot_credentials_with_fs(
        &LocalJournalFs,
        dir,
        expected_bot_id,
        credentials,
        CredentialChange {
            previous,
            candidate,
            secret,
        },
        operation_id,
    )
}

pub fn abandon_prepared_credentials(
    dir: &Path,
    credentials: &BotCredentialCapability,
    prepared: PreparedCredential,
) -> Result<CredentialCommit, FeishuError> {
    abandon_prepared_credentials_with_fs(&LocalJournalFs, dir, credentials, prepared)
}

pub fn commit_prepared_credentials(
    dir: &Path,
    credentials: &BotCredentialCapability,
    prepared: PreparedCredential,
) -> Result<CredentialCommit, FeishuError> {
    commit_prepared_credentials_with_fs(&LocalJournalFs, dir, credentials, prepared)
}

pub fn recover_bot_directory(
    dir: &Path,
    expected_bot_id: &str,
    credentials: &BotCredentialCapability,
    loaded: Option<BotConfigFile>,
) -> Result<CredentialRecovery, FeishuError> {
    recover_bot_directory_with_fs(&LocalJournalFs, dir, expected_bot_id, credentials, loaded)
}

#[cfg(test)]
mod tests;
