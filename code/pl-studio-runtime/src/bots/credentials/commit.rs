//! Candidate preparation, durable commit, and journal reconciliation.
use super::journal::{CredentialJournalPhase, JOURNAL_SCHEMA, remove_journal};
use super::*;
use crate::bots::config::{BOT_CONFIG_SCHEMA_VERSION, try_load_config};
use crate::config::{BotCredentialRefKind, BotSecretVersion, SelectedBotCredential};
use crate::studio::new_id;

pub(super) fn unsettled_credential_error() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Conflict,
        "bot has an unfinished credential obligation; retry the original operation first",
        true,
        None,
    )
}

pub(super) fn ensure_journal_identity(
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

pub(super) fn prepare_bot_credentials_with_fs(
    fs: &dyn JournalFs,
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
        let recovered = recover_operation_with_fs(fs, dir, credentials, journal)?;
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
                fs.store_journal(dir, &intent)?;
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
            fs.store_journal(dir, &intent)?;
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
            fs.store_journal(dir, &intent)?;
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
        fs.store_journal(dir, &intent)?;
    }
    candidate.schema_version = BOT_CONFIG_SCHEMA_VERSION;
    candidate.selected_ref = selected;
    intent.target = candidate.clone();
    intent.candidate_version = candidate_version;
    intent.phase = CredentialJournalPhase::Prepared;
    fs.store_journal(dir, &intent)?;
    Ok(CredentialPrepare::Ready(Box::new(PreparedCredential {
        operation_id: operation_id.to_string(),
        target: candidate,
        invalidate,
        journal: intent,
    })))
}

pub(super) fn abandon_prepared_credentials_with_fs(
    fs: &dyn JournalFs,
    dir: &Path,
    credentials: &BotCredentialCapability,
    prepared: PreparedCredential,
) -> Result<CredentialCommit, FeishuError> {
    recover_operation_with_fs(fs, dir, credentials, prepared.journal)
}

pub(super) fn commit_prepared_credentials_with_fs(
    fs: &dyn JournalFs,
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
    match fs.replace_config(dir, &candidate) {
        Ok(()) => {
            journal.phase = CredentialJournalPhase::CleanupPending;
            let journal_error = fs.store_journal(dir, &journal).err();
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
            let _ = fs.store_journal(dir, &journal);
            let recovered = recover_operation_with_fs(fs, dir, credentials, journal)?;
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
    if prefer == BotCredentialRefKind::System {
        match credentials.upsert_version(bot_id, prefer, candidate.clone()) {
            Ok(persist) => return Ok(persist),
            Err(error) if error.kind == BotCredentialIoKind::Unavailable => {}
            Err(error) => return Err(map_io(error)),
        }
    }
    credentials
        .upsert_version(bot_id, BotCredentialRefKind::Session, candidate)
        .map_err(map_io)
}

pub(super) fn recover_operation_with_fs(
    fs: &dyn JournalFs,
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
        decided_applied_with_fs(fs, dir, credentials, journal, actual)
    } else if configs_match(actual.as_ref(), journal.previous.as_ref()) {
        decided_not_applied_with_fs(fs, dir, credentials, journal, actual)
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

fn decided_applied_with_fs(
    fs: &dyn JournalFs,
    dir: &Path,
    credentials: &BotCredentialCapability,
    journal: CredentialJournal,
    actual: Option<BotConfigFile>,
) -> Result<CredentialCommit, FeishuError> {
    if needs_durability_confirm(journal.phase) {
        match fs.confirm_config(dir, Some(&journal.target)) {
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

fn decided_not_applied_with_fs(
    fs: &dyn JournalFs,
    dir: &Path,
    credentials: &BotCredentialCapability,
    journal: CredentialJournal,
    actual: Option<BotConfigFile>,
) -> Result<CredentialCommit, FeishuError> {
    if needs_durability_confirm(journal.phase) {
        match fs.confirm_config(dir, journal.previous.as_ref()) {
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

pub(super) fn inspect_decided(
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

fn finish_cleanup(
    dir: &Path,
    credentials: &BotCredentialCapability,
    journal: &CredentialJournal,
    keep: Option<&BotCredentialRef>,
    committed: bool,
) -> Result<(), FeishuError> {
    credentials
        .collect_versions(
            &journal.bot_id,
            keep,
            journal.candidate_version.as_deref(),
            committed,
        )
        .map_err(map_io)?;
    remove_journal(dir)
}

fn actual_config(dir: &Path) -> Result<Option<BotConfigFile>, FeishuError> {
    // 单次读取同时决定存在性与解析结果，不再为探测存在而重读同一文件。
    try_load_config(&dir.join("config.toml"))
}

fn configs_match(actual: Option<&BotConfigFile>, expected: Option<&BotConfigFile>) -> bool {
    match (actual, expected) {
        (None, None) => true,
        (Some(actual), Some(expected)) => actual == expected,
        _ => false,
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

pub(super) fn missing_secret_error() -> FeishuError {
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
