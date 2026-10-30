//! 每个机器人的凭据/配置共同提交、journal 与可恢复版本引用。
use super::config::{
    BOT_CONFIG_SCHEMA_VERSION, BotConfigFile, decode_config_snapshot_at, encode_config_snapshot,
    load_config, save_config, save_recognized_config,
};
use super::protocol::error::{FeishuError, FeishuErrorKind};
use crate::config::{
    BotCredentialCapability, BotCredentialIoError, BotCredentialIoKind, BotCredentialRef,
    BotCredentialRefKind, BotProtectedPayload, BotSecretVersion, SelectedBotCredential,
    try_decode_current_payload,
};
use crate::studio::new_id;
use pl_protocol::studio::{
    BotCredentialAvailability, BotCredentialOperation, BotDiagnostic, BotSecretUpdate,
};
use serde::{Deserialize, Serialize};
use std::path::Path;

const JOURNAL_FILE: &str = "credential-journal.json";
const JOURNAL_SCHEMA: u32 = 3;
const MIGRATION_INTENT_FILE: &str = "credential-migration.json";
// Credential payload versioning arrived in schema 2; later config upgrades must not
// reinterpret its protected payload as the original plaintext credential format.
const VERSIONED_CREDENTIAL_CONFIG_SCHEMA: u32 = 2;

#[derive(Debug, Clone, PartialEq, Eq)]
struct CredentialJournal {
    schema_version: u32,
    operation_id: String,
    bot_id: String,
    phase: CredentialJournalPhase,
    previous: Option<BotConfigFile>,
    target: BotConfigFile,
    candidate_version: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct StoredCredentialJournal {
    schema_version: u32,
    operation_id: String,
    bot_id: String,
    phase: CredentialJournalPhase,
    previous: Option<serde_json::Value>,
    target: serde_json::Value,
    candidate_version: Option<String>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
enum CredentialJournalPhase {
    Intent,
    Prepared,
    CommitUncertain,
    CleanupPending,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct MigrationIntent {
    schema_version: u32,
    bot_id: String,
    app_id: String,
    version: String,
}

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
    pub previous: Option<BotConfigFile>,
    pub target: BotConfigFile,
    pub invalidate: bool,
    journal: CredentialJournal,
}

impl std::fmt::Debug for PreparedCredential {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("PreparedCredential")
            .field("operation_id", &self.operation_id)
            .field("previous", &self.previous)
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

pub fn has_credential_journal(dir: &Path) -> bool {
    dir.join(JOURNAL_FILE).is_file()
}

/// 安全目录身份不匹配时的固定错误：不携带目录名、配置正文或平台标识。
fn directory_identity_error() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Protocol,
        "bot directory identity does not match its configuration",
        false,
        None,
    )
}

/// 原操作仍有未收束的提交/清理义务：新意图须先通过显式 Retry 完成原义务。
fn unsettled_credential_error() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Conflict,
        "bot has an unfinished credential obligation; retry the original operation first",
        true,
        None,
    )
}

/// 触碰任何凭据、迁移或发布前核对普通配置身份。
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

/// journal 的原配置、目标配置都必须属于同一安全目录身份。
fn ensure_journal_identity(
    expected_bot_id: &str,
    journal: &CredentialJournal,
) -> Result<(), FeishuError> {
    if journal.bot_id != expected_bot_id || journal.target.id != expected_bot_id {
        return Err(directory_identity_error());
    }
    if let Some(previous) = &journal.previous {
        ensure_config_identity(expected_bot_id, previous)?;
    }
    Ok(())
}

#[cfg_attr(not(test), allow(dead_code))]
pub fn recover_bot_credentials(
    dir: &Path,
    expected_bot_id: &str,
    credentials: &BotCredentialCapability,
    config: Option<BotConfigFile>,
) -> Result<CredentialRecovery, FeishuError> {
    recover_bot_directory(dir, expected_bot_id, credentials, config)
}

pub fn recover_bot_directory(
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
        let recovered = recover_operation(dir, credentials, journal)?;
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

fn retry_completed_migration_cleanup(dir: &Path, config: &BotConfigFile) {
    let path = dir.join(MIGRATION_INTENT_FILE);
    match std::fs::read(&path) {
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => tracing::warn!(
            bot_id = %config.id,
            error = %error,
            "bot credential migration intent retained after unreadable leftover"
        ),
        Ok(bytes) => match serde_json::from_slice::<MigrationIntent>(&bytes) {
            Ok(intent)
                if intent.bot_id == config.id
                    && intent.app_id == config.feishu().app_id
                    && config.schema_version >= VERSIONED_CREDENTIAL_CONFIG_SCHEMA =>
            {
                if let Err(error) = remove_path(&path) {
                    tracing::warn!(
                        bot_id = %config.id,
                        error = %error,
                        "bot credential migration intent cleanup failed"
                    );
                }
            }
            Ok(_) | Err(_) => tracing::warn!(
                bot_id = %config.id,
                "bot credential migration intent preserved; identity or schema is unusable"
            ),
        },
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

/// 目录核实结果转恢复事实。未提交候选仍在清理时保留 journal 的目标应用，
/// 不能因为回退配置可发布就用回退配置的应用替代候选目标。
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

#[cfg_attr(not(test), allow(dead_code))]
pub fn commit_bot_credentials(
    dir: &Path,
    expected_bot_id: &str,
    credentials: &BotCredentialCapability,
    previous: &BotConfigFile,
    candidate: BotConfigFile,
    secret: BotSecretUpdate,
    operation_id: &str,
) -> Result<CredentialCommit, FeishuError> {
    if previous.id != expected_bot_id || candidate.id != expected_bot_id {
        return Err(directory_identity_error());
    }
    match prepare_bot_credentials(
        dir,
        expected_bot_id,
        credentials,
        previous,
        candidate,
        secret,
        operation_id,
    )? {
        CredentialPrepare::Decided(commit) => Ok(*commit),
        CredentialPrepare::Ready(prepared) => {
            commit_prepared_credentials(dir, credentials, *prepared)
        }
    }
}

pub fn prepare_bot_credentials(
    dir: &Path,
    expected_bot_id: &str,
    credentials: &BotCredentialCapability,
    previous: &BotConfigFile,
    mut candidate: BotConfigFile,
    secret: BotSecretUpdate,
    operation_id: &str,
) -> Result<CredentialPrepare, FeishuError> {
    // 先核对本次操作与目录归属身份，再触碰 journal、普通配置或系统凭据。
    ensure_config_identity(expected_bot_id, previous)?;
    ensure_config_identity(expected_bot_id, &candidate)?;
    if let Some(journal) = read_journal(dir)? {
        ensure_journal_identity(expected_bot_id, &journal)?;
        let same_operation = journal.operation_id == operation_id;
        let recovered = recover_operation(dir, credentials, journal)?;
        if same_operation {
            match recovered.decision {
                CredentialDecision::Applied => {
                    return Ok(CredentialPrepare::Decided(Box::new(recovered)));
                }
                CredentialDecision::Uncertain => {
                    return Err(uncertain_error(operation_id));
                }
                CredentialDecision::NotApplied => {
                    if matches!(
                        recovered.operation,
                        BotCredentialOperation::CleanupPending { .. }
                    ) {
                        return Ok(CredentialPrepare::Decided(Box::new(recovered)));
                    }
                }
            }
        } else {
            match recovered.decision {
                CredentialDecision::Uncertain => {
                    return Err(FeishuError::new(
                        FeishuErrorKind::Conflict,
                        "bot credential commit is uncertain; retry the original operation",
                        true,
                        None,
                    ));
                }
                CredentialDecision::Applied | CredentialDecision::NotApplied => {
                    // 原操作的 journal 仍存在：说明清理/提交义务尚未真实收束。
                    // 新意图不得在此覆盖 journal；先由显式 Retry 完成义务。
                    if has_credential_journal(dir) {
                        return Err(unsettled_credential_error());
                    }
                }
            }
        }
    }

    let previous_ref = previous.selected_ref.clone();
    let mut invalidate = false;
    let mut candidate_version = None;
    let previous_config = actual_config(dir)?;
    if let Some(actual) = &previous_config {
        ensure_config_identity(expected_bot_id, actual)?;
    }
    let mut intent = CredentialJournal {
        schema_version: JOURNAL_SCHEMA,
        operation_id: operation_id.to_string(),
        bot_id: candidate.id.clone(),
        phase: CredentialJournalPhase::Intent,
        previous: previous_config,
        target: candidate.clone(),
        candidate_version: None,
    };

    let selected = match secret {
        BotSecretUpdate::Preserve => {
            if previous.selected_ref.is_none() {
                None
            } else if previous.feishu().app_id == candidate.feishu().app_id {
                previous_ref.clone()
            } else {
                let Some(current) = previous_ref.as_ref() else {
                    return Err(missing_secret_error());
                };
                let inspected = inspect_decided(credentials, previous, Some(current));
                let value = match inspected.availability {
                    BotCredentialAvailability::Unavailable => {
                        return Err(inspected.diagnostic.map_or_else(
                            || {
                                FeishuError::new(
                                    FeishuErrorKind::Unavailable,
                                    "bot credential store is unavailable",
                                    true,
                                    None,
                                )
                            },
                            |diagnostic| {
                                FeishuError::new(
                                    FeishuErrorKind::Unavailable,
                                    diagnostic.message,
                                    diagnostic.retryable,
                                    diagnostic.platform_code,
                                )
                            },
                        ));
                    }
                    BotCredentialAvailability::Missing => return Err(missing_secret_error()),
                    BotCredentialAvailability::Stored | BotCredentialAvailability::SessionOnly => {
                        inspected.secret.ok_or_else(|| {
                            FeishuError::new(
                                FeishuErrorKind::Protocol,
                                "bot credential material is invalid",
                                false,
                                None,
                            )
                        })?
                    }
                };
                let version = new_id("cred");
                intent.candidate_version = Some(version.clone());
                write_journal(dir, &intent)?;
                let persist = persist_version(
                    credentials,
                    &candidate.id,
                    &candidate.feishu().app_id,
                    &version,
                    &value,
                    current.kind,
                )?;
                candidate_version = Some(version.clone());
                Some(ref_for_persist(persist, version))
            }
        }
        BotSecretUpdate::Clear => {
            invalidate = true;
            write_journal(dir, &intent)?;
            None
        }
        BotSecretUpdate::Replace { value } => {
            if value.trim().is_empty() {
                return Err(FeishuError::new(
                    FeishuErrorKind::Rejected,
                    "bot secret is required",
                    false,
                    None,
                ));
            }
            let version = new_id("cred");
            intent.candidate_version = Some(version.clone());
            write_journal(dir, &intent)?;
            let persist = persist_version(
                credentials,
                &candidate.id,
                &candidate.feishu().app_id,
                &version,
                &value,
                BotCredentialRefKind::System,
            )?;
            candidate_version = Some(version.clone());
            invalidate = true;
            Some(ref_for_persist(persist, version))
        }
    };

    if intent.candidate_version.is_none() {
        write_journal(dir, &intent)?;
    }
    candidate.schema_version = BOT_CONFIG_SCHEMA_VERSION;
    candidate.selected_ref = selected;
    intent.target = candidate.clone();
    intent.candidate_version = candidate_version;
    intent.phase = CredentialJournalPhase::Prepared;
    write_journal(dir, &intent)?;
    Ok(CredentialPrepare::Ready(Box::new(PreparedCredential {
        operation_id: operation_id.to_string(),
        previous: intent.previous.clone(),
        target: candidate,
        invalidate,
        journal: intent,
    })))
}

pub fn abandon_prepared_credentials(
    dir: &Path,
    credentials: &BotCredentialCapability,
    prepared: PreparedCredential,
) -> Result<CredentialCommit, FeishuError> {
    recover_operation(dir, credentials, prepared.journal)
}

pub fn commit_prepared_credentials(
    dir: &Path,
    credentials: &BotCredentialCapability,
    prepared: PreparedCredential,
) -> Result<CredentialCommit, FeishuError> {
    let PreparedCredential {
        operation_id,
        target: candidate,
        invalidate,
        mut journal,
        ..
    } = prepared;
    match write_config(dir, &candidate) {
        Ok(()) => {
            journal.phase = CredentialJournalPhase::CleanupPending;
            let journal_error = write_journal(dir, &journal).err();
            Ok(applied_commit(
                dir,
                credentials,
                journal,
                candidate,
                invalidate,
                journal_error,
            ))
        }
        Err(error) => {
            journal.phase = CredentialJournalPhase::CommitUncertain;
            let _ = write_journal(dir, &journal);
            let recovered = recover_operation(dir, credentials, journal)?;
            match recovered.decision {
                CredentialDecision::Applied | CredentialDecision::NotApplied => {
                    let mut recovered = recovered;
                    if recovered.diagnostic.is_none() {
                        recovered.diagnostic = Some(error.diagnostic());
                    }
                    Ok(recovered)
                }
                CredentialDecision::Uncertain => Err(uncertain_error(&operation_id)),
            }
        }
    }
}

fn applied_commit(
    dir: &Path,
    credentials: &BotCredentialCapability,
    journal: CredentialJournal,
    config: BotConfigFile,
    invalidate: bool,
    journal_error: Option<FeishuError>,
) -> CredentialCommit {
    let inspected = inspect_decided(credentials, &config, config.selected_ref.as_ref());
    let operation_id = journal.operation_id.clone();
    if let Some(error) = journal_error {
        return CredentialCommit {
            decision: CredentialDecision::Applied,
            config,
            availability: inspected.availability,
            operation: BotCredentialOperation::CleanupPending {
                operation_id: operation_id.clone(),
                config_committed: true,
            },
            secret: inspected.secret,
            invalidate,
            diagnostic: inspected.diagnostic.or(Some(error.diagnostic())),
            operation_id,
            publishable: true,
        };
    }
    let cleanup = finish_cleanup(
        dir,
        credentials,
        &journal,
        config.selected_ref.as_ref(),
        true,
    );
    CredentialCommit {
        decision: CredentialDecision::Applied,
        config,
        availability: inspected.availability,
        operation: if cleanup.is_err() {
            BotCredentialOperation::CleanupPending {
                operation_id: operation_id.clone(),
                config_committed: true,
            }
        } else {
            BotCredentialOperation::Idle
        },
        secret: inspected.secret,
        invalidate,
        diagnostic: inspected
            .diagnostic
            .or_else(|| cleanup.err().map(|error| error.diagnostic())),
        operation_id,
        publishable: true,
    }
}

fn persist_version(
    credentials: &BotCredentialCapability,
    bot_id: &str,
    app_id: &str,
    version: &str,
    secret: &str,
    prefer: BotCredentialRefKind,
) -> Result<crate::config::BotProtectedPersist, FeishuError> {
    let candidate = BotSecretVersion {
        id: version.to_string(),
        bot_id: bot_id.to_string(),
        app_id: app_id.to_string(),
        secret: secret.to_string(),
    };
    match prefer {
        BotCredentialRefKind::System => persist_system_candidate(credentials, bot_id, candidate),
        BotCredentialRefKind::Session => persist_lease_candidate(credentials, bot_id, candidate),
    }
}

fn persist_system_candidate(
    credentials: &BotCredentialCapability,
    bot_id: &str,
    candidate: BotSecretVersion,
) -> Result<crate::config::BotProtectedPersist, FeishuError> {
    let system_payload = match credentials.load_system_payload(bot_id) {
        Ok(payload) => payload.unwrap_or_default(),
        Err(error) if error.kind == BotCredentialIoKind::Missing => BotProtectedPayload::default(),
        Err(error) if error.kind == BotCredentialIoKind::Unavailable => {
            return persist_lease_candidate(credentials, bot_id, candidate);
        }
        Err(error) => return Err(map_io(error)),
    };
    let lease_candidate = candidate.clone();
    let mut payload = system_payload;
    payload.upsert(candidate).map_err(map_io)?;
    match credentials.persist_system(bot_id, &payload) {
        Ok(persist) => Ok(persist),
        Err(error) if error.kind == BotCredentialIoKind::Unavailable => {
            persist_lease_candidate(credentials, bot_id, lease_candidate)
        }
        Err(error) => Err(map_io(error)),
    }
}

fn persist_lease_candidate(
    credentials: &BotCredentialCapability,
    bot_id: &str,
    candidate: BotSecretVersion,
) -> Result<crate::config::BotProtectedPersist, FeishuError> {
    let mut payload = match credentials.load_lease_payload(bot_id) {
        Ok(Some(payload)) => payload,
        Ok(None)
        | Err(BotCredentialIoError {
            kind: BotCredentialIoKind::Missing,
            ..
        }) => BotProtectedPayload::default(),
        Err(error) => return Err(map_io(error)),
    };
    payload.upsert(candidate).map_err(map_io)?;
    credentials
        .persist_lease(bot_id, &payload)
        .map_err(map_io)?;
    Ok(crate::config::BotProtectedPersist::SessionOnly)
}

fn recover_operation(
    dir: &Path,
    credentials: &BotCredentialCapability,
    journal: CredentialJournal,
) -> Result<CredentialCommit, FeishuError> {
    if journal.schema_version != JOURNAL_SCHEMA
        || journal.bot_id != journal.target.id
        || journal
            .previous
            .as_ref()
            .is_some_and(|previous| previous.id != journal.bot_id)
    {
        return Err(FeishuError::new(
            FeishuErrorKind::Protocol,
            "bot credential journal identity is unusable; original association preserved",
            false,
            None,
        ));
    }
    let actual = actual_config(dir)?;
    if let Some(actual) = &actual
        && actual.id != journal.bot_id
    {
        return Err(directory_identity_error());
    }
    if target_is_proven(&journal) && configs_match(actual.as_ref(), Some(&journal.target)) {
        decided_applied(dir, credentials, journal, actual)
    } else if configs_match(actual.as_ref(), journal.previous.as_ref()) {
        decided_not_applied(dir, credentials, journal, actual)
    } else {
        Ok(inspect_uncertain(credentials, journal, actual))
    }
}

fn target_is_proven(journal: &CredentialJournal) -> bool {
    if journal.phase == CredentialJournalPhase::Intent {
        return false;
    }
    match (
        journal.candidate_version.as_deref(),
        journal.target.selected_ref.as_ref(),
    ) {
        (None, None) | (None, Some(_)) => true,
        (Some(version), Some(selected)) if selected.version == version => true,
        _ => false,
    }
}

fn decided_applied(
    dir: &Path,
    credentials: &BotCredentialCapability,
    journal: CredentialJournal,
    actual: Option<BotConfigFile>,
) -> Result<CredentialCommit, FeishuError> {
    if needs_durability_confirm(journal.phase) {
        match confirm_recognized_config(dir, Some(&journal.target)) {
            Ok(()) => {}
            Err(_) => return Ok(inspect_uncertain(credentials, journal, actual)),
        }
    }
    let config = journal.target.clone();
    let inspected = inspect_decided(credentials, &config, config.selected_ref.as_ref());
    let cleanup = finish_cleanup(
        dir,
        credentials,
        &journal,
        config.selected_ref.as_ref(),
        true,
    );
    let operation_id = journal.operation_id.clone();
    let operation = if cleanup.is_err() {
        BotCredentialOperation::CleanupPending {
            operation_id: operation_id.clone(),
            config_committed: true,
        }
    } else {
        BotCredentialOperation::Idle
    };
    Ok(CredentialCommit {
        decision: CredentialDecision::Applied,
        config,
        availability: inspected.availability,
        operation,
        secret: inspected.secret,
        invalidate: auth_invalidate(journal.previous.as_ref(), &journal.target),
        diagnostic: inspected
            .diagnostic
            .or_else(|| cleanup.err().map(|error| error.diagnostic())),
        operation_id,
        publishable: true,
    })
}

fn decided_not_applied(
    dir: &Path,
    credentials: &BotCredentialCapability,
    journal: CredentialJournal,
    actual: Option<BotConfigFile>,
) -> Result<CredentialCommit, FeishuError> {
    if needs_durability_confirm(journal.phase) {
        match confirm_recognized_config(dir, journal.previous.as_ref()) {
            Ok(()) => {}
            Err(_) => return Ok(inspect_uncertain(credentials, journal, actual)),
        }
    }
    let keep = actual
        .as_ref()
        .and_then(|config| config.selected_ref.clone());
    let publishable = actual.is_some() || journal.previous.is_some();
    let config = actual
        .clone()
        .or_else(|| journal.previous.clone())
        .unwrap_or_else(|| unpublished_placeholder(&journal.target));
    let inspected = inspect_decided(credentials, &config, keep.as_ref());
    let cleanup = finish_cleanup(dir, credentials, &journal, keep.as_ref(), false);
    let operation_id = journal.operation_id.clone();
    let operation = if cleanup.is_err() {
        BotCredentialOperation::CleanupPending {
            operation_id: operation_id.clone(),
            config_committed: false,
        }
    } else {
        BotCredentialOperation::Idle
    };
    Ok(CredentialCommit {
        decision: CredentialDecision::NotApplied,
        config,
        availability: inspected.availability,
        operation,
        secret: inspected.secret,
        invalidate: false,
        diagnostic: inspected
            .diagnostic
            .or_else(|| cleanup.err().map(|error| error.diagnostic())),
        operation_id,
        publishable,
    })
}

fn unpublished_placeholder(target: &BotConfigFile) -> BotConfigFile {
    let mut config = target.clone();
    config.selected_ref = None;
    config
}

fn needs_durability_confirm(phase: CredentialJournalPhase) -> bool {
    matches!(
        phase,
        CredentialJournalPhase::Prepared | CredentialJournalPhase::CommitUncertain
    )
}

fn inspect_uncertain(
    credentials: &BotCredentialCapability,
    journal: CredentialJournal,
    actual: Option<BotConfigFile>,
) -> CredentialCommit {
    let config = actual.unwrap_or_else(|| journal.target.clone());
    let inspected = inspect_decided(credentials, &config, config.selected_ref.as_ref());
    CredentialCommit {
        decision: CredentialDecision::Uncertain,
        config,
        availability: inspected.availability,
        operation: BotCredentialOperation::CommitUncertain {
            operation_id: journal.operation_id.clone(),
        },
        secret: inspected.secret,
        invalidate: false,
        diagnostic: inspected.diagnostic,
        operation_id: journal.operation_id,
        publishable: false,
    }
}

fn inspect_decided(
    credentials: &BotCredentialCapability,
    config: &BotConfigFile,
    selected: Option<&BotCredentialRef>,
) -> InspectedCredential {
    match credentials.inspect_selected(&config.id, &config.feishu().app_id, selected) {
        Ok(selected) => normalize_selected(selected),
        Err(error) => InspectedCredential {
            availability: BotCredentialAvailability::Unavailable,
            secret: None,
            diagnostic: Some(map_io(error).diagnostic()),
        },
    }
}

fn normalize_selected(selected: SelectedBotCredential) -> InspectedCredential {
    match selected.availability {
        BotCredentialAvailability::Stored | BotCredentialAvailability::SessionOnly => {
            if selected.secret.is_some() {
                InspectedCredential {
                    availability: selected.availability,
                    secret: selected.secret,
                    diagnostic: None,
                }
            } else {
                InspectedCredential {
                    availability: BotCredentialAvailability::Unavailable,
                    secret: None,
                    diagnostic: Some(invalid_material_diagnostic()),
                }
            }
        }
        BotCredentialAvailability::Missing => InspectedCredential {
            availability: BotCredentialAvailability::Missing,
            secret: None,
            diagnostic: None,
        },
        BotCredentialAvailability::Unavailable => InspectedCredential {
            availability: BotCredentialAvailability::Unavailable,
            secret: None,
            diagnostic: Some(unavailable_store_diagnostic()),
        },
    }
}

fn migrate_legacy_config(
    dir: &Path,
    credentials: &BotCredentialCapability,
    mut config: BotConfigFile,
) -> Result<BotConfigFile, FeishuError> {
    let intent_path = dir.join(MIGRATION_INTENT_FILE);
    let intent = load_or_write_intent(&intent_path, &config)?;
    if intent.bot_id != config.id || intent.app_id != config.feishu().app_id {
        return Err(FeishuError::new(
            FeishuErrorKind::Protocol,
            "bot credential migration identity does not match config",
            false,
            None,
        ));
    }
    let system = credentials.read_system(&config.id).map_err(map_io)?;
    let lease = credentials.read_lease(&config.id).map_err(map_io)?;
    let selected = migrate_sources(&config, &intent, credentials, system, lease)?;
    config.schema_version = BOT_CONFIG_SCHEMA_VERSION;
    config.selected_ref = selected;
    save_config(&dir.join("config.toml"), &config)?;
    if let Err(error) = remove_path(&intent_path) {
        tracing::warn!(
            bot_id = %config.id,
            error = %error,
            "bot credential migration intent cleanup failed"
        );
    }
    Ok(config)
}

fn migrate_sources(
    config: &BotConfigFile,
    intent: &MigrationIntent,
    credentials: &BotCredentialCapability,
    system: crate::config::BotProtectedRead,
    lease: Option<String>,
) -> Result<Option<BotCredentialRef>, FeishuError> {
    let system_payload = match system {
        crate::config::BotProtectedRead::Missing => None,
        crate::config::BotProtectedRead::System(raw) => Some(classify_legacy_raw(&raw, intent)?),
    };
    let lease_payload = match lease {
        None => None,
        Some(raw) => Some(classify_legacy_raw(&raw, intent)?),
    };
    match (system_payload, lease_payload) {
        (None, None) => Ok(None),
        (Some(LegacyMaterial::Current(payload)), None) if payload_has_intent(&payload, intent) => {
            Ok(Some(BotCredentialRef::system(intent.version.clone())))
        }
        (None, Some(LegacyMaterial::Current(payload))) if payload_has_intent(&payload, intent) => {
            Ok(Some(BotCredentialRef::session(intent.version.clone())))
        }
        (Some(LegacyMaterial::Opaque(secret)), None) => {
            wrap_opaque(credentials, config, intent, &secret, true)
        }
        (None, Some(LegacyMaterial::Opaque(secret))) => {
            wrap_opaque(credentials, config, intent, &secret, false)
        }
        (Some(LegacyMaterial::Current(payload)), Some(LegacyMaterial::Current(_)))
            if payload_has_intent(&payload, intent) =>
        {
            Ok(Some(BotCredentialRef::system(intent.version.clone())))
        }
        _ => Err(FeishuError::new(
            FeishuErrorKind::Protocol,
            "bot credential sources conflict without a selected proof; original association preserved",
            false,
            None,
        )),
    }
}

enum LegacyMaterial {
    Current(BotProtectedPayload),
    Opaque(String),
}

fn payload_has_intent(payload: &BotProtectedPayload, intent: &MigrationIntent) -> bool {
    payload.versions.iter().any(|version| {
        version.id == intent.version
            && version.bot_id == intent.bot_id
            && version.app_id == intent.app_id
    })
}

fn classify_legacy_raw(raw: &str, intent: &MigrationIntent) -> Result<LegacyMaterial, FeishuError> {
    if let Some(payload) = try_decode_current_payload(raw) {
        if payload_has_intent(&payload, intent) {
            Ok(LegacyMaterial::Current(payload))
        } else {
            Err(FeishuError::new(
                FeishuErrorKind::Protocol,
                "bot credential payload does not match migration intent; original association preserved",
                false,
                None,
            ))
        }
    } else {
        Ok(LegacyMaterial::Opaque(raw.to_string()))
    }
}

fn wrap_opaque(
    credentials: &BotCredentialCapability,
    config: &BotConfigFile,
    intent: &MigrationIntent,
    secret: &str,
    prefer_system: bool,
) -> Result<Option<BotCredentialRef>, FeishuError> {
    let mut payload = BotProtectedPayload::default();
    payload
        .upsert(BotSecretVersion {
            id: intent.version.clone(),
            bot_id: config.id.clone(),
            app_id: config.feishu().app_id.clone(),
            secret: secret.to_string(),
        })
        .map_err(map_io)?;
    let persist = if prefer_system {
        match credentials.persist_system(&config.id, &payload) {
            Ok(persist) => persist,
            Err(error) if error.kind == BotCredentialIoKind::Unavailable => {
                persist_lease_candidate(
                    credentials,
                    &config.id,
                    BotSecretVersion {
                        id: intent.version.clone(),
                        bot_id: config.id.clone(),
                        app_id: config.feishu().app_id.clone(),
                        secret: secret.to_string(),
                    },
                )?
            }
            Err(error) => return Err(map_io(error)),
        }
    } else {
        credentials
            .persist_lease(&config.id, &payload)
            .map_err(map_io)?;
        crate::config::BotProtectedPersist::SessionOnly
    };
    Ok(Some(ref_for_persist(persist, intent.version.clone())))
}

fn finish_cleanup(
    dir: &Path,
    credentials: &BotCredentialCapability,
    journal: &CredentialJournal,
    keep: Option<&BotCredentialRef>,
    committed: bool,
) -> Result<(), FeishuError> {
    gc_source(
        credentials,
        &journal.bot_id,
        keep,
        journal.candidate_version.as_deref(),
        committed,
        BotCredentialRefKind::System,
    )?;
    gc_source(
        credentials,
        &journal.bot_id,
        keep,
        journal.candidate_version.as_deref(),
        committed,
        BotCredentialRefKind::Session,
    )?;
    remove_journal(dir)
}

fn gc_source(
    credentials: &BotCredentialCapability,
    bot_id: &str,
    current: Option<&BotCredentialRef>,
    candidate_version: Option<&str>,
    committed: bool,
    kind: BotCredentialRefKind,
) -> Result<(), FeishuError> {
    if committed && current.map(|item| item.kind) != Some(kind) {
        return recycle_kind(credentials, bot_id, kind);
    }
    let loaded = match kind {
        BotCredentialRefKind::System => credentials.load_system_payload(bot_id).map_err(map_io)?,
        BotCredentialRefKind::Session => credentials.load_lease_payload(bot_id).map_err(map_io)?,
    };
    let Some(mut payload) = loaded else {
        return Ok(());
    };
    let before = payload.clone();
    if committed {
        let keep = current
            .filter(|selected| selected.kind == kind)
            .map(|selected| vec![selected.version.clone()])
            .unwrap_or_default();
        payload.retain_referenced(&keep);
        if let Some(candidate) = candidate_version
            && !keep.iter().any(|id| id == candidate)
        {
            payload.versions.retain(|version| version.id != candidate);
        }
    } else if let Some(candidate) = candidate_version {
        payload.versions.retain(|version| version.id != candidate);
    }
    if payload.versions.is_empty() {
        return recycle_kind(credentials, bot_id, kind);
    }
    if payload == before {
        return Ok(());
    }
    match kind {
        BotCredentialRefKind::System => {
            credentials
                .persist_system(bot_id, &payload)
                .map_err(map_io)?;
        }
        BotCredentialRefKind::Session => {
            credentials
                .persist_lease(bot_id, &payload)
                .map_err(map_io)?;
        }
    }
    Ok(())
}

fn recycle_kind(
    credentials: &BotCredentialCapability,
    bot_id: &str,
    kind: BotCredentialRefKind,
) -> Result<(), FeishuError> {
    match kind {
        BotCredentialRefKind::System => {
            if let Err(error) = credentials.recycle_system(bot_id)
                && error.kind != BotCredentialIoKind::Missing
            {
                return Err(map_io(error));
            }
            Ok(())
        }
        BotCredentialRefKind::Session => credentials.recycle_lease(bot_id).map_err(map_io),
    }
}

fn actual_config(dir: &Path) -> Result<Option<BotConfigFile>, FeishuError> {
    let path = dir.join("config.toml");
    match std::fs::read_to_string(&path) {
        Ok(_) => load_config(&path).map(Some),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(io_error(error)),
    }
}

fn configs_match(actual: Option<&BotConfigFile>, expected: Option<&BotConfigFile>) -> bool {
    match (actual, expected) {
        (None, None) => true,
        (Some(actual), Some(expected)) => actual == expected,
        _ => false,
    }
}

fn confirm_recognized_config(
    dir: &Path,
    expected: Option<&BotConfigFile>,
) -> Result<(), FeishuError> {
    #[cfg(test)]
    if take_confirm_fault() {
        return Err(FeishuError::new(
            FeishuErrorKind::Unavailable,
            "injected config durability confirmation failure",
            true,
            None,
        ));
    }
    let path = dir.join("config.toml");
    match expected {
        None => match std::fs::symlink_metadata(&path) {
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Ok(_) => Err(FeishuError::new(
                FeishuErrorKind::Protocol,
                "bot config was expected to be absent",
                false,
                None,
            )),
            Err(error) => Err(io_error(error)),
        },
        Some(expected) => {
            let actual = load_config(&path)?;
            if &actual != expected {
                return Err(FeishuError::new(
                    FeishuErrorKind::Protocol,
                    "bot config does not match the recognized operation target",
                    false,
                    None,
                ));
            }
            save_recognized_config(&path, expected)
        }
    }
}

fn write_config(dir: &Path, config: &BotConfigFile) -> Result<(), FeishuError> {
    let path = dir.join("config.toml");
    #[cfg(test)]
    if take_skip_write_fault() {
        return Err(FeishuError::new(
            FeishuErrorKind::Unavailable,
            "injected config write skip before replacement",
            true,
            None,
        ));
    }
    #[cfg(test)]
    if take_write_fault() {
        let _ = save_config(&path, config);
        return Err(FeishuError::new(
            FeishuErrorKind::Unavailable,
            "injected config write failure after replacement",
            true,
            None,
        ));
    }
    save_config(&path, config)
}

fn write_journal(dir: &Path, journal: &CredentialJournal) -> Result<(), FeishuError> {
    #[cfg(test)]
    if journal.phase == CredentialJournalPhase::CleanupPending && take_journal_fault() {
        return Err(FeishuError::new(
            FeishuErrorKind::Unavailable,
            "injected credential journal advancement failure",
            true,
            None,
        ));
    }
    let stored = StoredCredentialJournal {
        schema_version: journal.schema_version,
        operation_id: journal.operation_id.clone(),
        bot_id: journal.bot_id.clone(),
        phase: journal.phase,
        previous: journal
            .previous
            .as_ref()
            .map(encode_config_snapshot)
            .transpose()?,
        target: encode_config_snapshot(&journal.target)?,
        candidate_version: journal.candidate_version.clone(),
    };
    let encoded = serde_json::to_vec_pretty(&stored).map_err(|_| {
        FeishuError::new(
            FeishuErrorKind::Protocol,
            "failed to encode bot credential journal",
            false,
            None,
        )
    })?;
    pl_tool::workspace::write_file_atomically(&dir.join(JOURNAL_FILE), &encoded).map_err(io_error)
}

fn read_journal(dir: &Path) -> Result<Option<CredentialJournal>, FeishuError> {
    let path = dir.join(JOURNAL_FILE);
    match std::fs::read(&path) {
        Ok(bytes) => decode_journal_bytes(&path, &bytes).map(Some),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(io_error(error)),
    }
}

#[derive(Debug, thiserror::Error)]
#[error("bot credential journal {stage} failed in {path}")]
struct JournalDecodeFailed {
    path: std::path::PathBuf,
    stage: &'static str,
    #[source]
    source: anyhow::Error,
}

fn journal_decode_error(
    path: &Path,
    stage: &'static str,
    error: impl Into<anyhow::Error>,
) -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Protocol,
        "unreadable bot credential journal; original association preserved",
        false,
        None,
    )
    .with_source(JournalDecodeFailed {
        path: path.to_owned(),
        stage,
        source: error.into(),
    })
}

fn decode_journal_bytes(path: &Path, bytes: &[u8]) -> Result<CredentialJournal, FeishuError> {
    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct Header {
        schema_version: u32,
    }
    let header: Header = serde_json::from_slice(bytes)
        .map_err(|error| journal_decode_error(path, "version", error))?;
    if header.schema_version != JOURNAL_SCHEMA {
        return Err(FeishuError::new(
            FeishuErrorKind::Protocol,
            "unsupported bot credential journal schema; original association preserved",
            false,
            None,
        )
        .with_source(JournalDecodeFailed {
            path: path.to_owned(),
            stage: "version",
            source: anyhow::anyhow!("unsupported journal schema {}", header.schema_version),
        }));
    }
    let stored: StoredCredentialJournal = serde_json::from_slice(bytes)
        .map_err(|error| journal_decode_error(path, "decode", error))?;
    let previous = stored
        .previous
        .map(|snapshot| {
            decode_config_snapshot_at(path, snapshot)
                .map_err(|error| journal_decode_error(path, "previous", error))
        })
        .transpose()?;
    let target = decode_config_snapshot_at(path, stored.target)
        .map_err(|error| journal_decode_error(path, "target", error))?;
    Ok(CredentialJournal {
        schema_version: stored.schema_version,
        operation_id: stored.operation_id,
        bot_id: stored.bot_id,
        phase: stored.phase,
        previous,
        target,
        candidate_version: stored.candidate_version,
    })
}

fn remove_journal(dir: &Path) -> Result<(), FeishuError> {
    remove_path(&dir.join(JOURNAL_FILE))
}

fn remove_path(path: &Path) -> Result<(), FeishuError> {
    match std::fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(io_error(error)),
    }
}

fn load_or_write_intent(
    path: &Path,
    config: &BotConfigFile,
) -> Result<MigrationIntent, FeishuError> {
    if path.exists() {
        let text = std::fs::read_to_string(path).map_err(io_error)?;
        return serde_json::from_str(&text).map_err(|_| {
            FeishuError::new(
                FeishuErrorKind::Protocol,
                "unreadable bot credential migration intent; original association preserved",
                false,
                None,
            )
        });
    }
    let intent = MigrationIntent {
        schema_version: 1,
        bot_id: config.id.clone(),
        app_id: config.feishu().app_id.clone(),
        version: new_id("cred"),
    };
    let encoded = serde_json::to_vec_pretty(&intent).map_err(|_| {
        FeishuError::new(
            FeishuErrorKind::Protocol,
            "failed to encode bot credential migration intent",
            false,
            None,
        )
    })?;
    pl_tool::workspace::write_file_atomically(path, &encoded).map_err(io_error)?;
    Ok(intent)
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

fn uncertain_error(operation_id: &str) -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        format!("bot credential commit {operation_id} is uncertain"),
        true,
        None,
    )
}

fn missing_secret_error() -> FeishuError {
    FeishuError::new(FeishuErrorKind::Auth, "bot secret is missing", false, None)
}

fn invalid_material_diagnostic() -> BotDiagnostic {
    FeishuError::new(
        FeishuErrorKind::Protocol,
        "bot credential material is invalid",
        false,
        None,
    )
    .diagnostic()
}

fn unavailable_store_diagnostic() -> BotDiagnostic {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        "bot credential store is unavailable",
        true,
        None,
    )
    .diagnostic()
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

#[cfg(test)]
mod fault {
    use std::cell::Cell;
    thread_local! {
        static WRITE_FAILS: Cell<u32> = const { Cell::new(0) };
        static SKIP_WRITES: Cell<u32> = const { Cell::new(0) };
        static CONFIRM_FAILS: Cell<u32> = const { Cell::new(0) };
        static JOURNAL_FAILS: Cell<u32> = const { Cell::new(0) };
    }
    pub fn reset() {
        set_write_fails(0);
        set_skip_writes(0);
        set_confirm_fails(0);
        set_journal_fails(0);
    }
    pub fn set_write_fails(count: u32) {
        WRITE_FAILS.with(|cell| cell.set(count));
    }
    pub fn set_skip_writes(count: u32) {
        SKIP_WRITES.with(|cell| cell.set(count));
    }
    pub fn set_confirm_fails(count: u32) {
        CONFIRM_FAILS.with(|cell| cell.set(count));
    }
    pub fn set_journal_fails(count: u32) {
        JOURNAL_FAILS.with(|cell| cell.set(count));
    }
    pub fn take_write() -> bool {
        take(&WRITE_FAILS)
    }
    pub fn take_skip_write() -> bool {
        take(&SKIP_WRITES)
    }
    pub fn take_confirm() -> bool {
        take(&CONFIRM_FAILS)
    }
    pub fn take_journal() -> bool {
        take(&JOURNAL_FAILS)
    }
    fn take(cell: &'static std::thread::LocalKey<Cell<u32>>) -> bool {
        cell.with(|cell| {
            let remaining = cell.get();
            if remaining == 0 {
                false
            } else {
                cell.set(remaining - 1);
                true
            }
        })
    }
}

#[cfg(test)]
fn take_write_fault() -> bool {
    fault::take_write()
}

#[cfg(test)]
fn take_skip_write_fault() -> bool {
    fault::take_skip_write()
}

#[cfg(test)]
fn take_confirm_fault() -> bool {
    fault::take_confirm()
}

#[cfg(test)]
fn take_journal_fault() -> bool {
    fault::take_journal()
}

#[cfg(test)]
mod tests {
    use super::super::config::assert_current_document;
    use super::*;
    use crate::config::{ConfigPaths, ConfigStore, memory_faults};

    fn capability() -> BotCredentialCapability {
        fault::reset();
        memory_faults::reset();
        ConfigStore::new(ConfigPaths::from_config_dir(
            tempfile::tempdir().unwrap().keep(),
        ))
        .bot_credentials()
    }

    fn bot_config(app_id: &str) -> BotConfigFile {
        BotConfigFile::new(
            "botA1234".into(),
            "Bot".into(),
            "project".into(),
            app_id.into(),
        )
        .unwrap()
    }

    fn write_schema1_config(dir: &Path, mut config: BotConfigFile) {
        config.schema_version = 1;
        save_recognized_config(&dir.join("config.toml"), &config).unwrap();
    }

    /// Exact nested shape emitted by the old confirm writer while retaining the header.
    fn nested_confirmation_snapshot(config: &BotConfigFile, source: u32) -> serde_json::Value {
        serde_json::json!({
            "schema_version": source,
            "id": config.id,
            "name": config.name,
            "project_id": config.workspace_id,
            "platform": "feishuChina",
            "platform_config": {
                "app_id": config.feishu().app_id,
                "trusted_open_ids": config.feishu().trusted_open_ids,
                "trusted_chat_ids": config.feishu().trusted_chat_ids
            },
            "enabled": config.enabled,
            "tools_enabled": config.tools_enabled,
            "config_revision": config.config_revision,
            "created_at": config.created_at,
            "updated_at": config.updated_at
        })
    }

    fn write_nested_confirmation(dir: &Path, value: &serde_json::Value) -> Vec<u8> {
        let table = toml::Value::try_from(value).unwrap();
        let bytes = toml::to_string_pretty(&table).unwrap().into_bytes();
        std::fs::write(dir.join("config.toml"), &bytes).unwrap();
        bytes
    }

    #[test]
    fn nested_v1_and_v2_confirmation_files_resume_the_original_journal() {
        for source in [1, 2] {
            for phase in [
                CredentialJournalPhase::Prepared,
                CredentialJournalPhase::CommitUncertain,
            ] {
                let directory = tempfile::tempdir().unwrap();
                let credentials = capability();
                let previous = bot_config("cli_old");
                let previous_snapshot = nested_confirmation_snapshot(&previous, source);
                let original = write_nested_confirmation(directory.path(), &previous_snapshot);
                let path = directory.path().join("config.toml");
                let loaded = load_config(&path).expect("old producer's nested file is recognized");
                assert_eq!(loaded.schema_version, source);
                assert_eq!(loaded.config_revision, previous.config_revision);
                assert_eq!(std::fs::read(&path).unwrap(), original);

                let mut target = bot_config("cli_new");
                target.config_revision = previous.config_revision + 1;
                let stored = StoredCredentialJournal {
                    schema_version: JOURNAL_SCHEMA,
                    operation_id: "original-confirm-operation".into(),
                    bot_id: previous.id.clone(),
                    phase,
                    previous: Some(previous_snapshot),
                    target: nested_confirmation_snapshot(&target, 3),
                    candidate_version: None,
                };
                std::fs::write(
                    directory.path().join(JOURNAL_FILE),
                    serde_json::to_vec(&stored).unwrap(),
                )
                .unwrap();
                let journal = read_journal(directory.path()).unwrap().unwrap();
                assert_eq!(journal.previous.as_ref().unwrap(), &loaded);
                let recovered = recover_operation(directory.path(), &credentials, journal).unwrap();
                assert_eq!(recovered.operation_id, "original-confirm-operation");
                assert_eq!(recovered.decision, CredentialDecision::NotApplied);
                assert_eq!(recovered.config, loaded);
                assert_eq!(recovered.operation, BotCredentialOperation::Idle);
                assert!(!directory.path().join(JOURNAL_FILE).exists());
                assert_eq!(load_config(&path).unwrap(), loaded);
            }
        }
    }

    #[test]
    fn nested_v1_confirmation_still_imports_its_original_opaque_secret() {
        let directory = tempfile::tempdir().unwrap();
        let credentials = capability();
        let config = bot_config("cli_old");
        credentials
            .persist_system_raw(&config.id, "synthetic-opaque-secret")
            .unwrap();
        write_nested_confirmation(directory.path(), &nested_confirmation_snapshot(&config, 1));
        let path = directory.path().join("config.toml");
        let loaded = load_config(&path).unwrap();
        assert_eq!(loaded.schema_version, 1);
        let recovered =
            recover_bot_directory(directory.path(), &config.id, &credentials, Some(loaded))
                .unwrap();
        let current = recovered.config.unwrap();
        assert_eq!(current.schema_version, BOT_CONFIG_SCHEMA_VERSION);
        assert_eq!(current.config_revision, config.config_revision);
        assert_eq!(recovered.availability, BotCredentialAvailability::Stored);
        assert_eq!(recovered.secret.as_deref(), Some("synthetic-opaque-secret"));
        let bytes = std::fs::read(&path).unwrap();
        let reopened = recover_bot_directory(
            directory.path(),
            &config.id,
            &credentials,
            Some(load_config(&path).unwrap()),
        )
        .unwrap();
        assert_eq!(reopened.config.unwrap(), current);
        assert_eq!(std::fs::read(&path).unwrap(), bytes);
    }

    #[test]
    fn journal_decode_keeps_json_and_snapshot_causes_with_file_context() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join(JOURNAL_FILE);
        std::fs::write(&path, b"{private-sentinel").unwrap();
        let error = anyhow::Error::new(read_journal(directory.path()).unwrap_err());
        assert!(error.chain().any(|cause| cause.is::<serde_json::Error>()));
        assert!(!format!("{error:#}").contains("private-sentinel"));
        assert!(format!("{error:#}").contains(path.to_str().unwrap()));

        let config = bot_config("cli_old");
        for slot in ["previous", "target"] {
            let mut previous = nested_confirmation_snapshot(&config, 2);
            let mut target = nested_confirmation_snapshot(&config, 3);
            let invalid = if slot == "previous" {
                &mut previous
            } else {
                &mut target
            };
            invalid["platform_config"]["app_id"] = "".into();
            let stored = StoredCredentialJournal {
                schema_version: JOURNAL_SCHEMA,
                operation_id: "unchanged-operation".into(),
                bot_id: config.id.clone(),
                phase: CredentialJournalPhase::Prepared,
                previous: Some(previous),
                target,
                candidate_version: None,
            };
            let bytes = serde_json::to_vec(&stored).unwrap();
            std::fs::write(&path, &bytes).unwrap();
            let error = anyhow::Error::new(read_journal(directory.path()).unwrap_err());
            assert!(
                error
                    .chain()
                    .any(|cause| cause.is::<crate::toml_schema::DocumentMigrationFailed>())
            );
            let diagnostic = format!("{error:#}");
            assert!(diagnostic.contains(slot));
            assert!(diagnostic.contains(path.to_str().unwrap()));
            assert_eq!(std::fs::read(&path).unwrap(), bytes);
        }
        std::fs::write(&path, br#"{"schemaVersion":999}"#).unwrap();
        let error = read_journal(directory.path()).unwrap_err();
        assert!(error.diagnostic().message.starts_with("unsupported"));
        assert!(!error.retryable());
    }

    #[test]
    fn platform_schema_upgrade_preserves_versioned_credentials_without_legacy_migration() {
        let directory = tempfile::tempdir().unwrap();
        let credentials = capability();
        let mut previous = bot_config("cli_original");
        previous.schema_version = 2;
        previous.selected_ref = Some(BotCredentialRef::system("original-version"));
        credentials
            .persist_system(
                &previous.id,
                &BotProtectedPayload {
                    schema_version: 1,
                    versions: vec![BotSecretVersion {
                        id: "original-version".into(),
                        bot_id: previous.id.clone(),
                        app_id: "cli_original".into(),
                        secret: "synthetic-secret".into(),
                    }],
                },
            )
            .unwrap();
        save_recognized_config(&directory.path().join("config.toml"), &previous).unwrap();
        let recovered = recover_bot_directory(
            directory.path(),
            &previous.id,
            &credentials,
            Some(previous.clone()),
        )
        .unwrap();
        assert_eq!(
            recovered.config.as_ref().unwrap().selected_ref,
            previous.selected_ref
        );
        assert_eq!(recovered.availability, BotCredentialAvailability::Stored);
        assert_eq!(recovered.secret.as_deref(), Some("synthetic-secret"));
        assert!(!directory.path().join(MIGRATION_INTENT_FILE).exists());
    }

    #[test]
    fn preserve_empty_ref_does_not_revive_legacy_secret() {
        let directory = tempfile::tempdir().unwrap();
        let credentials = capability();
        credentials
            .persist_system(
                "botA1234",
                &BotProtectedPayload {
                    schema_version: 1,
                    versions: vec![BotSecretVersion {
                        id: "old".into(),
                        bot_id: "botA1234".into(),
                        app_id: "cli_old".into(),
                        secret: "legacy-secret".into(),
                    }],
                },
            )
            .unwrap();
        let previous = bot_config("cli_old");
        let committed = commit_bot_credentials(
            directory.path(),
            "botA1234",
            &credentials,
            &previous,
            previous.clone(),
            BotSecretUpdate::Preserve,
            "op-1",
        )
        .unwrap();
        assert_eq!(committed.decision, CredentialDecision::Applied);
        assert!(committed.config.selected_ref.is_none());
        assert_eq!(committed.availability, BotCredentialAvailability::Missing);
        assert!(committed.secret.is_none());
    }

    #[test]
    fn uncertain_commit_blocks_a_different_operation() {
        let directory = tempfile::tempdir().unwrap();
        let previous = bot_config("cli_a");
        save_config(&directory.path().join("config.toml"), &previous).unwrap();
        let mut foreign = previous.clone();
        foreign.name = "other".into();
        save_config(&directory.path().join("config.toml"), &foreign).unwrap();
        let journal = CredentialJournal {
            schema_version: JOURNAL_SCHEMA,
            operation_id: "op-original".into(),
            bot_id: "botA1234".into(),
            phase: CredentialJournalPhase::CommitUncertain,
            previous: Some(previous.clone()),
            target: previous.clone(),
            candidate_version: None,
        };
        write_journal(directory.path(), &journal).unwrap();
        let error = commit_bot_credentials(
            directory.path(),
            "botA1234",
            &capability(),
            &previous,
            previous.clone(),
            BotSecretUpdate::Clear,
            "op-other",
        )
        .unwrap_err();
        assert_eq!(error.kind(), FeishuErrorKind::Conflict);
        let on_disk = std::fs::read_to_string(directory.path().join("config.toml")).unwrap();
        assert!(on_disk.contains("other"));
    }

    #[test]
    fn session_selection_ignores_system_material() {
        let credentials = capability();
        credentials
            .persist_system(
                "botA1234",
                &BotProtectedPayload {
                    schema_version: 1,
                    versions: vec![BotSecretVersion {
                        id: "sys".into(),
                        bot_id: "botA1234".into(),
                        app_id: "cli_a".into(),
                        secret: "system-secret".into(),
                    }],
                },
            )
            .unwrap();
        credentials
            .persist_lease(
                "botA1234",
                &BotProtectedPayload {
                    schema_version: 1,
                    versions: vec![BotSecretVersion {
                        id: "lease".into(),
                        bot_id: "botA1234".into(),
                        app_id: "cli_a".into(),
                        secret: "lease-secret".into(),
                    }],
                },
            )
            .unwrap();
        let mut config = bot_config("cli_a");
        config.selected_ref = Some(BotCredentialRef::session("lease"));
        let inspected = credentials
            .inspect_selected(
                &config.id,
                &config.feishu().app_id,
                config.selected_ref.as_ref(),
            )
            .unwrap();
        assert_eq!(
            inspected.availability,
            BotCredentialAvailability::SessionOnly
        );
        assert_eq!(inspected.secret.as_deref(), Some("lease-secret"));
    }

    #[test]
    fn write_error_after_replacement_recovers_target_then_stays_uncertain_until_confirm() {
        let directory = tempfile::tempdir().unwrap();
        let credentials = capability();
        let previous = bot_config("cli_a");
        save_config(&directory.path().join("config.toml"), &previous).unwrap();
        fault::set_write_fails(1);
        fault::set_confirm_fails(1);
        let error = commit_bot_credentials(
            directory.path(),
            "botA1234",
            &credentials,
            &previous,
            previous.clone(),
            BotSecretUpdate::Replace {
                value: "new-secret".into(),
            },
            "op-same",
        )
        .unwrap_err();
        assert_eq!(error.kind(), FeishuErrorKind::Unavailable);
        let on_disk = load_config(&directory.path().join("config.toml")).unwrap();
        assert_ne!(on_disk.selected_ref, previous.selected_ref);
        let version = on_disk.selected_ref.clone().unwrap().version;
        fault::set_confirm_fails(0);
        let recovered = commit_bot_credentials(
            directory.path(),
            "botA1234",
            &credentials,
            &previous,
            previous.clone(),
            BotSecretUpdate::Replace {
                value: "should-not-create".into(),
            },
            "op-same",
        )
        .unwrap();
        assert_eq!(recovered.decision, CredentialDecision::Applied);
        assert_eq!(
            recovered
                .config
                .selected_ref
                .as_ref()
                .map(|item| item.version.as_str()),
            Some(version.as_str())
        );
        assert_eq!(recovered.secret.as_deref(), Some("new-secret"));
    }

    #[test]
    fn clear_does_not_require_readable_system_material() {
        let directory = tempfile::tempdir().unwrap();
        let credentials = capability();
        let mut previous = bot_config("cli_a");
        previous.selected_ref = Some(BotCredentialRef::system("gone"));
        save_config(&directory.path().join("config.toml"), &previous).unwrap();
        let committed = commit_bot_credentials(
            directory.path(),
            "botA1234",
            &credentials,
            &previous,
            previous.clone(),
            BotSecretUpdate::Clear,
            "op-clear",
        )
        .unwrap();
        assert_eq!(committed.decision, CredentialDecision::Applied);
        assert!(committed.config.selected_ref.is_none());
        assert_eq!(committed.availability, BotCredentialAvailability::Missing);
    }

    #[test]
    fn schema1_opaque_lease_migrates_to_session_ref() {
        let directory = tempfile::tempdir().unwrap();
        let credentials = capability();
        credentials
            .lease_raw("botA1234", "opaque-session-secret")
            .unwrap();
        let config = bot_config("cli_a");
        write_schema1_config(directory.path(), config);
        let loaded = load_config(&directory.path().join("config.toml")).unwrap();
        let migrated =
            recover_bot_credentials(directory.path(), "botA1234", &credentials, Some(loaded))
                .unwrap();
        assert_eq!(
            migrated.availability,
            BotCredentialAvailability::SessionOnly
        );
        assert_eq!(migrated.secret.as_deref(), Some("opaque-session-secret"));
        assert!(matches!(
            migrated
                .config
                .as_ref()
                .and_then(|config| config.selected_ref.clone()),
            Some(BotCredentialRef {
                kind: BotCredentialRefKind::Session,
                ..
            })
        ));
    }

    #[test]
    fn schema1_opaque_system_migrates_to_system_ref_and_reopens() {
        let directory = tempfile::tempdir().unwrap();
        let credentials = capability();
        credentials
            .persist_system_raw("botA1234", "opaque-system-secret")
            .unwrap();
        let config = bot_config("cli_a");
        write_schema1_config(directory.path(), config);
        let loaded = load_config(&directory.path().join("config.toml")).unwrap();
        let migrated =
            recover_bot_credentials(directory.path(), "botA1234", &credentials, Some(loaded))
                .unwrap();
        assert_eq!(migrated.availability, BotCredentialAvailability::Stored);
        assert_eq!(migrated.secret.as_deref(), Some("opaque-system-secret"));
        let selected = migrated
            .config
            .as_ref()
            .and_then(|config| config.selected_ref.clone())
            .unwrap();
        assert_eq!(selected.kind, BotCredentialRefKind::System);
        let reopened = load_config(&directory.path().join("config.toml")).unwrap();
        assert_eq!(reopened.schema_version, BOT_CONFIG_SCHEMA_VERSION);
        assert_eq!(reopened.config_revision, 1);
        let persisted = std::fs::read_to_string(directory.path().join("config.toml")).unwrap();
        assert!(persisted.contains("schema_version = 4"));
        assert_current_document(&persisted, "cli_a");
        let recovered =
            recover_bot_credentials(directory.path(), "botA1234", &credentials, Some(reopened))
                .unwrap();
        assert_eq!(
            recovered
                .config
                .as_ref()
                .and_then(|config| config.selected_ref.clone()),
            Some(selected.clone())
        );
        assert_eq!(
            recovered
                .config
                .as_ref()
                .map(|config| config.schema_version),
            Some(BOT_CONFIG_SCHEMA_VERSION)
        );
        assert_eq!(
            recovered
                .config
                .as_ref()
                .map(|config| config.config_revision),
            Some(1)
        );
        assert_eq!(recovered.availability, BotCredentialAvailability::Stored);
        assert_eq!(recovered.secret.as_deref(), Some("opaque-system-secret"));
        assert_eq!(
            std::fs::read_to_string(directory.path().join("config.toml")).unwrap(),
            persisted
        );
        let payload = credentials
            .load_system_payload("botA1234")
            .unwrap()
            .unwrap();
        assert!(
            payload
                .versions
                .iter()
                .any(|version| version.id == selected.version
                    && version.bot_id == "botA1234"
                    && version.app_id == "cli_a")
        );
    }

    #[test]
    fn cleanup_failure_does_not_swallow_a_later_clear() {
        let directory = tempfile::tempdir().unwrap();
        let credentials = capability();
        let previous = bot_config("cli_a");
        save_config(&directory.path().join("config.toml"), &previous).unwrap();
        let stored = commit_bot_credentials(
            directory.path(),
            "botA1234",
            &credentials,
            &previous,
            previous.clone(),
            BotSecretUpdate::Replace {
                value: "keep-until-cleared".into(),
            },
            "op-store",
        )
        .unwrap();
        assert_eq!(stored.decision, CredentialDecision::Applied);
        let with_secret = stored.config.clone();
        memory_faults::set_recycle_fails(1);
        let first = commit_bot_credentials(
            directory.path(),
            "botA1234",
            &credentials,
            &with_secret,
            with_secret.clone(),
            BotSecretUpdate::Clear,
            "op-old",
        )
        .unwrap();
        assert_eq!(first.decision, CredentialDecision::Applied);
        assert!(first.config.selected_ref.is_none());
        assert_eq!(
            first.operation,
            BotCredentialOperation::CleanupPending {
                operation_id: "op-old".into(),
                config_committed: true,
            }
        );
        assert!(
            credentials
                .load_system_payload("botA1234")
                .unwrap()
                .is_some()
        );
        let second = commit_bot_credentials(
            directory.path(),
            "botA1234",
            &credentials,
            &first.config,
            first.config.clone(),
            BotSecretUpdate::Clear,
            "op-new",
        )
        .unwrap();
        assert_eq!(second.decision, CredentialDecision::Applied);
        assert!(second.config.selected_ref.is_none());
        assert_ne!(
            second.operation,
            BotCredentialOperation::CleanupPending {
                operation_id: "op-old".into(),
                config_committed: true,
            }
        );
        let on_disk = load_config(&directory.path().join("config.toml")).unwrap();
        assert!(on_disk.selected_ref.is_none());
        assert!(
            credentials
                .load_system_payload("botA1234")
                .unwrap()
                .is_none()
        );
    }

    #[test]
    fn decided_commit_survives_invalid_inspect_and_allows_clear() {
        let directory = tempfile::tempdir().unwrap();
        let credentials = capability();
        let previous = bot_config("cli_a");
        save_config(&directory.path().join("config.toml"), &previous).unwrap();
        let committed = commit_bot_credentials(
            directory.path(),
            "botA1234",
            &credentials,
            &previous,
            previous.clone(),
            BotSecretUpdate::Replace {
                value: "live-secret".into(),
            },
            "op-replace",
        )
        .unwrap();
        assert_eq!(committed.decision, CredentialDecision::Applied);
        credentials
            .persist_system_raw("botA1234", "not-json")
            .unwrap();
        let recovered = recover_bot_credentials(
            directory.path(),
            "botA1234",
            &credentials,
            Some(committed.config.clone()),
        )
        .unwrap();
        let recovered_config = recovered
            .config
            .clone()
            .expect("publishable recovered config");
        assert_eq!(recovered_config.selected_ref, committed.config.selected_ref);
        assert_eq!(
            recovered.availability,
            BotCredentialAvailability::Unavailable
        );
        assert!(recovered.secret.is_none());
        let cleared = commit_bot_credentials(
            directory.path(),
            "botA1234",
            &credentials,
            &recovered_config,
            recovered_config.clone(),
            BotSecretUpdate::Clear,
            "op-clear-after-invalid",
        )
        .unwrap();
        assert_eq!(cleared.decision, CredentialDecision::Applied);
        assert!(cleared.config.selected_ref.is_none());
    }

    #[test]
    fn preserve_across_app_unavailable_is_not_auth_missing() {
        let directory = tempfile::tempdir().unwrap();
        let credentials = capability();
        let previous = bot_config("cli_a");
        save_config(&directory.path().join("config.toml"), &previous).unwrap();
        let stored = commit_bot_credentials(
            directory.path(),
            "botA1234",
            &credentials,
            &previous,
            previous.clone(),
            BotSecretUpdate::Replace {
                value: "app-secret".into(),
            },
            "op-store",
        )
        .unwrap();
        let mut candidate = stored.config.clone();
        candidate.feishu_mut().app_id = "cli_b".into();
        memory_faults::set_system_unavailable(true);
        let error = commit_bot_credentials(
            directory.path(),
            "botA1234",
            &credentials,
            &stored.config,
            candidate,
            BotSecretUpdate::Preserve,
            "op-preserve",
        )
        .unwrap_err();
        assert_eq!(error.kind(), FeishuErrorKind::Unavailable);
        assert!(error.retryable());
        memory_faults::reset();
        let still = load_config(&directory.path().join("config.toml")).unwrap();
        assert_eq!(still.selected_ref, stored.config.selected_ref);
        assert_eq!(still.feishu().app_id, "cli_a");
    }

    #[test]
    fn not_applied_reclaims_candidate_and_keeps_previous_secret() {
        let directory = tempfile::tempdir().unwrap();
        let credentials = capability();
        let mut previous = bot_config("cli_a");
        previous.selected_ref = Some(BotCredentialRef::system("cred-old"));
        save_config(&directory.path().join("config.toml"), &previous).unwrap();
        credentials
            .persist_system(
                "botA1234",
                &BotProtectedPayload {
                    schema_version: 1,
                    versions: vec![
                        BotSecretVersion {
                            id: "cred-old".into(),
                            bot_id: "botA1234".into(),
                            app_id: "cli_a".into(),
                            secret: "old-secret".into(),
                        },
                        BotSecretVersion {
                            id: "cred-new".into(),
                            bot_id: "botA1234".into(),
                            app_id: "cli_b".into(),
                            secret: "candidate-secret".into(),
                        },
                    ],
                },
            )
            .unwrap();
        let mut target = previous.clone();
        target.feishu_mut().app_id = "cli_b".into();
        target.selected_ref = Some(BotCredentialRef::system("cred-new"));
        let journal = CredentialJournal {
            schema_version: JOURNAL_SCHEMA,
            operation_id: "op-not-applied".into(),
            bot_id: "botA1234".into(),
            phase: CredentialJournalPhase::Prepared,
            previous: Some(previous.clone()),
            target,
            candidate_version: Some("cred-new".into()),
        };
        write_journal(directory.path(), &journal).unwrap();
        let recovered = recover_operation(directory.path(), &credentials, journal).unwrap();
        assert_eq!(recovered.decision, CredentialDecision::NotApplied);
        assert_eq!(
            recovered.config.selected_ref,
            Some(BotCredentialRef::system("cred-old"))
        );
        assert_eq!(recovered.secret.as_deref(), Some("old-secret"));
        match recovered.operation {
            BotCredentialOperation::Idle => {}
            BotCredentialOperation::CleanupPending {
                config_committed, ..
            } => assert!(!config_committed),
            other => panic!("unexpected operation {other:?}"),
        }
        let payload = credentials
            .load_system_payload("botA1234")
            .unwrap()
            .unwrap();
        assert!(
            payload
                .versions
                .iter()
                .any(|version| version.id == "cred-old" && version.secret == "old-secret")
        );
        assert!(
            payload
                .versions
                .iter()
                .all(|version| version.id != "cred-new")
        );
        // 回退配置可发布、候选清理失败：恢复事实仍须保留候选目标应用，不能用
        // 回退配置的应用替代或丢失它。
        credentials
            .persist_system(
                "botA1234",
                &BotProtectedPayload {
                    schema_version: 1,
                    versions: vec![
                        BotSecretVersion {
                            id: "cred-old".into(),
                            bot_id: "botA1234".into(),
                            app_id: "cli_a".into(),
                            secret: "old-secret".into(),
                        },
                        BotSecretVersion {
                            id: "cred-new".into(),
                            bot_id: "botA1234".into(),
                            app_id: "cli_b".into(),
                            secret: "candidate-secret".into(),
                        },
                    ],
                },
            )
            .unwrap();
        let mut candidate_target = previous.clone();
        candidate_target.feishu_mut().app_id = "cli_b".into();
        candidate_target.selected_ref = Some(BotCredentialRef::system("cred-new"));
        let journal = CredentialJournal {
            schema_version: JOURNAL_SCHEMA,
            operation_id: "op-candidate".into(),
            bot_id: "botA1234".into(),
            phase: CredentialJournalPhase::Prepared,
            previous: Some(previous.clone()),
            target: candidate_target,
            candidate_version: Some("cred-new".into()),
        };
        write_journal(directory.path(), &journal).unwrap();
        memory_faults::set_persist_unavailable(true);
        let pending_candidate = recover_bot_credentials(
            directory.path(),
            "botA1234",
            &credentials,
            Some(previous.clone()),
        )
        .unwrap();
        memory_faults::reset();
        assert_eq!(pending_candidate.decision, CredentialDecision::NotApplied);
        assert_eq!(
            pending_candidate
                .config
                .as_ref()
                .map(|config| config.feishu().app_id.as_str()),
            Some("cli_a")
        );
        assert_eq!(
            pending_candidate.operation,
            BotCredentialOperation::CleanupPending {
                operation_id: "op-candidate".into(),
                config_committed: false,
            }
        );
        assert_eq!(
            pending_candidate.reserved_app_id.as_deref(),
            Some("cli_b"),
            "uncommitted candidate app must stay reserved while cleanup is pending"
        );
    }

    #[test]
    fn unreadable_config_preserves_bytes_and_intent_placeholder_is_not_applied() {
        let directory = tempfile::tempdir().unwrap();
        let credentials = capability();
        let previous = bot_config("cli_a");
        let original = b"not-a-bot-config = true\n";
        std::fs::write(directory.path().join("config.toml"), original).unwrap();
        let error = commit_bot_credentials(
            directory.path(),
            "botA1234",
            &credentials,
            &previous,
            previous.clone(),
            BotSecretUpdate::Replace {
                value: "new-secret".into(),
            },
            "op-bad-config",
        )
        .unwrap_err();
        assert_eq!(error.kind(), FeishuErrorKind::Protocol);
        assert_eq!(
            std::fs::read(directory.path().join("config.toml")).unwrap(),
            original
        );

        save_config(&directory.path().join("config.toml"), &previous).unwrap();
        credentials
            .persist_system(
                "botA1234",
                &BotProtectedPayload {
                    schema_version: 1,
                    versions: vec![BotSecretVersion {
                        id: "cred-old".into(),
                        bot_id: "botA1234".into(),
                        app_id: "cli_a".into(),
                        secret: "old-secret".into(),
                    }],
                },
            )
            .unwrap();
        let mut previous = previous;
        previous.selected_ref = Some(BotCredentialRef::system("cred-old"));
        save_config(&directory.path().join("config.toml"), &previous).unwrap();
        let journal = CredentialJournal {
            schema_version: JOURNAL_SCHEMA,
            operation_id: "op-intent".into(),
            bot_id: "botA1234".into(),
            phase: CredentialJournalPhase::Intent,
            previous: Some(previous.clone()),
            target: previous.clone(),
            candidate_version: Some("cred-placeholder".into()),
        };
        write_journal(directory.path(), &journal).unwrap();
        let recovered = recover_operation(directory.path(), &credentials, journal).unwrap();
        assert_eq!(recovered.decision, CredentialDecision::NotApplied);
        assert_eq!(recovered.config.selected_ref, previous.selected_ref);
        assert_eq!(recovered.secret.as_deref(), Some("old-secret"));
        assert_eq!(
            std::fs::read_to_string(directory.path().join("config.toml"))
                .ok()
                .and_then(|_| load_config(&directory.path().join("config.toml")).ok())
                .map(|config| config.selected_ref),
            Some(previous.selected_ref.clone())
        );
    }

    #[test]
    fn config_write_success_survives_journal_fault_and_reopens_applied() {
        let directory = tempfile::tempdir().unwrap();
        let credentials = capability();
        let previous = bot_config("cli_a");
        save_config(&directory.path().join("config.toml"), &previous).unwrap();
        fault::set_journal_fails(1);
        let committed = commit_bot_credentials(
            directory.path(),
            "botA1234",
            &credentials,
            &previous,
            previous.clone(),
            BotSecretUpdate::Replace {
                value: "journal-fault-secret".into(),
            },
            "op-journal",
        )
        .unwrap();
        assert_eq!(committed.decision, CredentialDecision::Applied);
        assert_eq!(committed.secret.as_deref(), Some("journal-fault-secret"));
        assert_eq!(
            committed.operation,
            BotCredentialOperation::CleanupPending {
                operation_id: "op-journal".into(),
                config_committed: true,
            }
        );
        assert!(directory.path().join(JOURNAL_FILE).exists());
        let version = committed
            .config
            .selected_ref
            .as_ref()
            .map(|item| item.version.clone())
            .unwrap();
        let again = commit_bot_credentials(
            directory.path(),
            "botA1234",
            &credentials,
            &previous,
            previous.clone(),
            BotSecretUpdate::Replace {
                value: "should-not-create".into(),
            },
            "op-journal",
        )
        .unwrap();
        assert_eq!(again.decision, CredentialDecision::Applied);
        assert_eq!(
            again
                .config
                .selected_ref
                .as_ref()
                .map(|item| item.version.as_str()),
            Some(version.as_str())
        );
        assert_eq!(again.secret.as_deref(), Some("journal-fault-secret"));
        let reopened = recover_bot_credentials(
            directory.path(),
            "botA1234",
            &credentials,
            Some(again.config.clone()),
        )
        .unwrap();
        assert_eq!(
            reopened
                .config
                .as_ref()
                .and_then(|config| config.selected_ref.as_ref())
                .map(|item| item.version.as_str()),
            Some(version.as_str())
        );
        assert_eq!(reopened.secret.as_deref(), Some("journal-fault-secret"));
    }

    fn payload_ids(
        credentials: &BotCredentialCapability,
        bot_id: &str,
        system: bool,
    ) -> Vec<String> {
        let payload = if system {
            credentials.load_system_payload(bot_id).unwrap()
        } else {
            credentials.load_lease_payload(bot_id).unwrap()
        };
        payload
            .map(|payload| {
                payload
                    .versions
                    .into_iter()
                    .map(|version| version.id)
                    .collect()
            })
            .unwrap_or_default()
    }

    #[test]
    fn idle_first_create_not_applied_does_not_reserve_app_identity() {
        let directory = tempfile::tempdir().unwrap();
        let credentials = capability();
        let previous = bot_config("cli_a");
        credentials
            .persist_system(
                "botA1234",
                &BotProtectedPayload {
                    schema_version: 1,
                    versions: vec![BotSecretVersion {
                        id: "cred-new".into(),
                        bot_id: "botA1234".into(),
                        app_id: "cli_a".into(),
                        secret: "orphan-candidate".into(),
                    }],
                },
            )
            .unwrap();
        let mut target = previous.clone();
        target.selected_ref = Some(BotCredentialRef::system("cred-new"));
        let journal = CredentialJournal {
            schema_version: JOURNAL_SCHEMA,
            operation_id: "op-first-idle".into(),
            bot_id: "botA1234".into(),
            phase: CredentialJournalPhase::Prepared,
            previous: None,
            target,
            candidate_version: Some("cred-new".into()),
        };
        write_journal(directory.path(), &journal).unwrap();
        let recovered =
            recover_bot_credentials(directory.path(), "botA1234", &credentials, None).unwrap();
        assert_eq!(recovered.decision, CredentialDecision::NotApplied);
        assert_eq!(recovered.operation, BotCredentialOperation::Idle);
        assert!(recovered.config.is_none());
        assert!(recovered.reserved_app_id.is_none());
        assert!(!directory.path().join("config.toml").exists());
        assert!(payload_ids(&credentials, "botA1234", true).is_empty());
    }

    #[test]
    fn first_create_not_applied_reclaims_candidate_without_using_target_ref() {
        let directory = tempfile::tempdir().unwrap();
        let credentials = capability();
        let previous = bot_config("cli_a");
        credentials
            .persist_system(
                "botA1234",
                &BotProtectedPayload {
                    schema_version: 1,
                    versions: vec![BotSecretVersion {
                        id: "cred-new".into(),
                        bot_id: "botA1234".into(),
                        app_id: "cli_a".into(),
                        secret: "orphan-candidate".into(),
                    }],
                },
            )
            .unwrap();
        let mut target = previous.clone();
        target.selected_ref = Some(BotCredentialRef::system("cred-new"));
        let journal = CredentialJournal {
            schema_version: JOURNAL_SCHEMA,
            operation_id: "op-first".into(),
            bot_id: "botA1234".into(),
            phase: CredentialJournalPhase::Prepared,
            previous: None,
            target,
            candidate_version: Some("cred-new".into()),
        };
        write_journal(directory.path(), &journal).unwrap();
        memory_faults::set_recycle_fails(1);
        let first = recover_operation(directory.path(), &credentials, journal).unwrap();
        assert_eq!(first.decision, CredentialDecision::NotApplied);
        assert!(first.config.selected_ref.is_none());
        assert_eq!(first.operation_id, "op-first");
        assert_eq!(
            first.operation,
            BotCredentialOperation::CleanupPending {
                operation_id: "op-first".into(),
                config_committed: false,
            }
        );
        assert!(!directory.path().join("config.toml").exists());
        assert_eq!(
            payload_ids(&credentials, "botA1234", true),
            vec!["cred-new".to_string()]
        );
        memory_faults::reset();
        let journal = read_journal(directory.path())
            .unwrap()
            .expect("cleanup pending journal");
        let resumed = recover_operation(directory.path(), &credentials, journal).unwrap();
        assert_eq!(resumed.decision, CredentialDecision::NotApplied);
        assert!(resumed.config.selected_ref.is_none());
        assert_eq!(resumed.operation_id, "op-first");
        assert_eq!(resumed.operation, BotCredentialOperation::Idle);
        assert!(payload_ids(&credentials, "botA1234", true).is_empty());
        assert!(!directory.path().join("config.toml").exists());
        assert_ne!(resumed.availability, BotCredentialAvailability::Stored);
    }

    #[test]
    fn prepared_target_without_durability_stays_uncertain_and_keeps_both_secrets() {
        let directory = tempfile::tempdir().unwrap();
        let credentials = capability();
        let mut previous = bot_config("cli_a");
        previous.selected_ref = Some(BotCredentialRef::system("cred-old"));
        save_config(&directory.path().join("config.toml"), &previous).unwrap();
        credentials
            .persist_system(
                "botA1234",
                &BotProtectedPayload {
                    schema_version: 1,
                    versions: vec![
                        BotSecretVersion {
                            id: "cred-old".into(),
                            bot_id: "botA1234".into(),
                            app_id: "cli_a".into(),
                            secret: "old-secret".into(),
                        },
                        BotSecretVersion {
                            id: "cred-new".into(),
                            bot_id: "botA1234".into(),
                            app_id: "cli_b".into(),
                            secret: "candidate-secret".into(),
                        },
                    ],
                },
            )
            .unwrap();
        let mut target = previous.clone();
        target.feishu_mut().app_id = "cli_b".into();
        target.selected_ref = Some(BotCredentialRef::system("cred-new"));
        save_config(&directory.path().join("config.toml"), &target).unwrap();
        let journal = CredentialJournal {
            schema_version: JOURNAL_SCHEMA,
            operation_id: "op-prepared".into(),
            bot_id: "botA1234".into(),
            phase: CredentialJournalPhase::Prepared,
            previous: Some(previous.clone()),
            target: target.clone(),
            candidate_version: Some("cred-new".into()),
        };
        write_journal(directory.path(), &journal).unwrap();
        fault::set_confirm_fails(3);
        let first = recover_operation(directory.path(), &credentials, journal.clone()).unwrap();
        assert_eq!(first.decision, CredentialDecision::Uncertain);
        assert_eq!(first.operation_id, "op-prepared");
        let ids = payload_ids(&credentials, "botA1234", true);
        assert!(ids.contains(&"cred-old".into()));
        assert!(ids.contains(&"cred-new".into()));
        // 实际文件是旧 A、journal 目标是新 B：未决恢复必须保留目标 B，并同时保留
        // 已知旧 A 关联占用，不能拿实际 A 替代 B。
        let recovery = recover_bot_credentials(
            directory.path(),
            "botA1234",
            &credentials,
            Some(target.clone()),
        )
        .unwrap();
        assert_eq!(recovery.decision, CredentialDecision::Uncertain);
        assert!(recovery.config.is_none());
        assert_eq!(recovery.reserved_app_id.as_deref(), Some("cli_b"));
        assert_eq!(recovery.previous_app_id.as_deref(), Some("cli_a"));
        let blocked = commit_bot_credentials(
            directory.path(),
            "botA1234",
            &credentials,
            &previous,
            previous.clone(),
            BotSecretUpdate::Replace {
                value: "should-not-create".into(),
            },
            "op-prepared",
        )
        .unwrap_err();
        assert_eq!(blocked.kind(), FeishuErrorKind::Unavailable);
        fault::set_confirm_fails(0);
        let applied = commit_bot_credentials(
            directory.path(),
            "botA1234",
            &credentials,
            &previous,
            previous.clone(),
            BotSecretUpdate::Replace {
                value: "should-not-create".into(),
            },
            "op-prepared",
        )
        .unwrap();
        assert_eq!(applied.decision, CredentialDecision::Applied);
        assert_eq!(applied.secret.as_deref(), Some("candidate-secret"));
        assert_eq!(
            applied.config.selected_ref,
            Some(BotCredentialRef::system("cred-new"))
        );
        assert_eq!(
            payload_ids(&credentials, "botA1234", true),
            vec!["cred-new".to_string()]
        );
    }

    #[test]
    fn replace_when_system_unavailable_uses_independent_session_lease() {
        let directory = tempfile::tempdir().unwrap();
        let credentials = capability();
        let previous = bot_config("cli_a");
        memory_faults::set_system_unavailable(true);
        let committed = commit_bot_credentials(
            directory.path(),
            "botA1234",
            &credentials,
            &previous,
            previous.clone(),
            BotSecretUpdate::Replace {
                value: "lease-only-secret".into(),
            },
            "op-session",
        )
        .unwrap();
        assert_eq!(committed.decision, CredentialDecision::Applied);
        assert_eq!(
            committed.availability,
            BotCredentialAvailability::SessionOnly
        );
        assert_eq!(committed.secret.as_deref(), Some("lease-only-secret"));
        let selected = committed.config.selected_ref.clone().unwrap();
        assert_eq!(selected.kind, BotCredentialRefKind::Session);
        memory_faults::reset();
        credentials.recycle_lease("botA1234").unwrap();
        let reopened = recover_bot_credentials(
            directory.path(),
            "botA1234",
            &credentials,
            Some(committed.config.clone()),
        )
        .unwrap();
        assert_eq!(reopened.availability, BotCredentialAvailability::Missing);
        assert!(reopened.secret.is_none());
        assert_ne!(reopened.availability, BotCredentialAvailability::Stored);
    }

    #[test]
    fn system_write_unavailable_appends_candidate_on_existing_lease() {
        let directory = tempfile::tempdir().unwrap();
        let credentials = capability();
        let mut previous = bot_config("cli_a");
        previous.selected_ref = Some(BotCredentialRef::session("cred-session"));
        save_config(&directory.path().join("config.toml"), &previous).unwrap();
        credentials
            .persist_system(
                "botA1234",
                &BotProtectedPayload {
                    schema_version: 1,
                    versions: vec![BotSecretVersion {
                        id: "cred-system".into(),
                        bot_id: "botA1234".into(),
                        app_id: "cli_a".into(),
                        secret: "system-secret".into(),
                    }],
                },
            )
            .unwrap();
        credentials
            .persist_lease(
                "botA1234",
                &BotProtectedPayload {
                    schema_version: 1,
                    versions: vec![BotSecretVersion {
                        id: "cred-session".into(),
                        bot_id: "botA1234".into(),
                        app_id: "cli_a".into(),
                        secret: "session-secret".into(),
                    }],
                },
            )
            .unwrap();
        memory_faults::set_persist_unavailable(true);
        fault::set_skip_writes(1);
        let first = commit_bot_credentials(
            directory.path(),
            "botA1234",
            &credentials,
            &previous,
            previous.clone(),
            BotSecretUpdate::Replace {
                value: "candidate-secret".into(),
            },
            "op-lease-keep",
        )
        .unwrap();
        assert_eq!(first.decision, CredentialDecision::NotApplied);
        assert_eq!(first.config.selected_ref, previous.selected_ref);
        assert_eq!(first.secret.as_deref(), Some("session-secret"));
        let session = credentials
            .inspect_selected(
                "botA1234",
                "cli_a",
                Some(&BotCredentialRef::session("cred-session")),
            )
            .unwrap();
        assert_eq!(session.secret.as_deref(), Some("session-secret"));
        let lease_ids = payload_ids(&credentials, "botA1234", false);
        assert_eq!(lease_ids, vec!["cred-session".to_string()]);
        assert_eq!(
            payload_ids(&credentials, "botA1234", true),
            vec!["cred-system".to_string()]
        );
        let on_disk = load_config(&directory.path().join("config.toml")).unwrap();
        assert_eq!(on_disk.selected_ref, previous.selected_ref);
    }

    #[test]
    fn journal_historical_v2_snapshot_matches_disk_without_upgrading_schema() {
        let directory = tempfile::tempdir().unwrap();
        let credentials = capability();
        let mut previous = bot_config("cli_a");
        previous.schema_version = 2;
        previous.selected_ref = Some(BotCredentialRef::system("cred-old"));
        save_recognized_config(&directory.path().join("config.toml"), &previous).unwrap();
        let on_disk = std::fs::read_to_string(directory.path().join("config.toml")).unwrap();
        assert!(on_disk.contains("schema_version = 2"));
        assert!(on_disk.contains("app_id ="));
        credentials
            .persist_system(
                "botA1234",
                &BotProtectedPayload {
                    schema_version: 1,
                    versions: vec![BotSecretVersion {
                        id: "cred-old".into(),
                        bot_id: "botA1234".into(),
                        app_id: "cli_a".into(),
                        secret: "old-secret".into(),
                    }],
                },
            )
            .unwrap();
        let mut target = previous.clone();
        target.schema_version = 2;
        target.feishu_mut().app_id = "cli_b".into();
        target.selected_ref = Some(BotCredentialRef::system("cred-new"));
        let journal = CredentialJournal {
            schema_version: JOURNAL_SCHEMA,
            operation_id: "op-historical".into(),
            bot_id: "botA1234".into(),
            phase: CredentialJournalPhase::Prepared,
            previous: Some(previous.clone()),
            target,
            candidate_version: Some("cred-new".into()),
        };
        write_journal(directory.path(), &journal).unwrap();
        let stored: serde_json::Value =
            serde_json::from_slice(&std::fs::read(directory.path().join(JOURNAL_FILE)).unwrap())
                .unwrap();
        assert_eq!(stored["previous"]["schema_version"], 2);
        assert_eq!(stored["previous"]["app_id"], "cli_a");
        assert!(stored["previous"].get("platform_config").is_none());
        let recovered = recover_operation(directory.path(), &credentials, journal).unwrap();
        assert_eq!(recovered.decision, CredentialDecision::NotApplied);
        assert_eq!(recovered.config.schema_version, 2);
        assert_eq!(
            recovered.config.selected_ref,
            Some(BotCredentialRef::system("cred-old"))
        );
        let still = std::fs::read_to_string(directory.path().join("config.toml")).unwrap();
        assert!(still.contains("schema_version = 2"));
        assert_eq!(
            load_config(&directory.path().join("config.toml"))
                .unwrap()
                .schema_version,
            2
        );
    }

    #[test]
    fn v1_legacy_import_is_not_skipped_after_current_shaped_decode() {
        let directory = tempfile::tempdir().unwrap();
        let credentials = capability();
        credentials
            .persist_system_raw("botA1234", "opaque-system-secret")
            .unwrap();
        let config = bot_config("cli_a");
        write_schema1_config(directory.path(), config.clone());
        let raw = std::fs::read_to_string(directory.path().join("config.toml")).unwrap();
        assert!(raw.contains("schema_version = 1"));
        assert!(raw.contains("app_id ="));
        let loaded = load_config(&directory.path().join("config.toml")).unwrap();
        assert_eq!(loaded.schema_version, 1);
        assert!(loaded.selected_ref.is_none());
        let migrated =
            recover_bot_credentials(directory.path(), "botA1234", &credentials, Some(loaded))
                .unwrap();
        assert_eq!(migrated.availability, BotCredentialAvailability::Stored);
        assert_eq!(migrated.secret.as_deref(), Some("opaque-system-secret"));
        assert_eq!(
            migrated.config.as_ref().map(|config| config.schema_version),
            Some(BOT_CONFIG_SCHEMA_VERSION)
        );
        assert_eq!(
            migrated
                .config
                .as_ref()
                .map(|config| config.config_revision),
            Some(config.config_revision)
        );
        assert!(matches!(
            migrated
                .config
                .as_ref()
                .and_then(|config| config.selected_ref.clone()),
            Some(BotCredentialRef {
                kind: BotCredentialRefKind::System,
                ..
            })
        ));
    }
}
