use super::super::config::{
    BOT_CONFIG_SCHEMA_VERSION, assert_current_document, load_config, save_config,
    save_recognized_config,
};
use super::journal::{
    CredentialJournalPhase, JOURNAL_FILE, JOURNAL_SCHEMA, StoredCredentialJournal,
};
use super::legacy_migration::MIGRATION_INTENT_FILE;
use super::*;
use crate::config::{BotCredentialRefKind, BotProtectedPayload, BotSecretVersion};
use crate::config::{ConfigPaths, ConfigStore, memory_faults};
use std::cell::Cell;

fn capability() -> CredentialHome {
    memory_faults::reset();
    let home = tempfile::tempdir().unwrap();
    let credentials = ConfigStore::new(ConfigPaths::from_config_dir(home.path())).bot_credentials();
    CredentialHome {
        _home: home,
        credentials,
        fs: FaultingJournalFs::default(),
    }
}

struct CredentialHome {
    _home: tempfile::TempDir,
    credentials: BotCredentialCapability,
    fs: FaultingJournalFs,
}

impl std::ops::Deref for CredentialHome {
    type Target = BotCredentialCapability;

    fn deref(&self) -> &Self::Target {
        &self.credentials
    }
}

/// 同步准备并提交：测试只需最终 `CredentialCommit`，不观察 owner 的交接边界。
fn commit_bot_credentials(
    dir: &Path,
    expected_bot_id: &str,
    credentials: &CredentialHome,
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
        recover_bot_directory(directory.path(), &config.id, &credentials, Some(loaded)).unwrap();
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
fn write_error_after_replacement_recovers_target_then_stays_uncertain_until_confirm() {
    let directory = tempfile::tempdir().unwrap();
    let credentials = capability();
    let previous = bot_config("cli_a");
    save_config(&directory.path().join("config.toml"), &previous).unwrap();
    credentials.fs.write_fails.set(1);
    credentials.fs.confirm_fails.set(1);
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
    credentials.fs.confirm_fails.set(0);
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
    let raw = std::fs::read_to_string(directory.path().join("config.toml")).unwrap();
    assert!(raw.contains("schema_version = 1"));
    assert!(raw.contains("app_id ="));
    assert_eq!(loaded.schema_version, 1);
    assert!(loaded.selected_ref.is_none());
    let migrated =
        recover_bot_directory(directory.path(), "botA1234", &credentials, Some(loaded)).unwrap();
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
        recover_bot_directory(directory.path(), "botA1234", &credentials, Some(loaded)).unwrap();
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
        recover_bot_directory(directory.path(), "botA1234", &credentials, Some(reopened)).unwrap();
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
    let recovered = recover_bot_directory(
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
    let pending_candidate = recover_bot_directory(
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
    credentials.fs.journal_fails.set(1);
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
    let reopened = recover_bot_directory(
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

fn payload_ids(credentials: &BotCredentialCapability, bot_id: &str, system: bool) -> Vec<String> {
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
fn first_create_not_applied_reclaims_candidate_without_reserving_app_identity() {
    // Public recovery of an idle first create must not reserve the app id,
    // and it reclaims the uncommitted candidate immediately.
    {
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
            recover_bot_directory(directory.path(), "botA1234", &credentials, None).unwrap();
        assert_eq!(recovered.decision, CredentialDecision::NotApplied);
        assert_eq!(recovered.operation, BotCredentialOperation::Idle);
        assert!(recovered.config.is_none());
        assert!(recovered.reserved_app_id.is_none());
        assert!(!directory.path().join("config.toml").exists());
        assert!(payload_ids(&credentials, "botA1234", true).is_empty());
    }
    // A recycle failure is a different recovery: the candidate stays, the
    // target ref is not adopted, and a later pass reclaims it without
    // marking the credential stored.
    {
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
    credentials.fs.confirm_fails.set(3);
    let first = recover_operation(directory.path(), &credentials, journal.clone()).unwrap();
    assert_eq!(first.decision, CredentialDecision::Uncertain);
    assert_eq!(first.operation_id, "op-prepared");
    let ids = payload_ids(&credentials, "botA1234", true);
    assert!(ids.contains(&"cred-old".into()));
    assert!(ids.contains(&"cred-new".into()));
    // 实际文件是旧 A、journal 目标是新 B：未决恢复必须保留目标 B，并同时保留
    // 已知旧 A 关联占用，不能拿实际 A 替代 B。
    let recovery = recover_bot_directory(
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
    credentials.fs.confirm_fails.set(0);
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
    let reopened = recover_bot_directory(
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
    credentials.fs.skip_writes.set(1);
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

fn prepare_bot_credentials(
    dir: &Path,
    expected_bot_id: &str,
    credentials: &CredentialHome,
    previous: &BotConfigFile,
    candidate: BotConfigFile,
    secret: BotSecretUpdate,
    operation_id: &str,
) -> Result<CredentialPrepare, FeishuError> {
    prepare_bot_credentials_with_fs(
        &credentials.fs,
        dir,
        expected_bot_id,
        credentials,
        previous,
        candidate,
        secret,
        operation_id,
    )
}

fn commit_prepared_credentials(
    dir: &Path,
    credentials: &CredentialHome,
    prepared: PreparedCredential,
) -> Result<CredentialCommit, FeishuError> {
    commit_prepared_credentials_with_fs(&credentials.fs, dir, credentials, prepared)
}

fn recover_bot_directory(
    dir: &Path,
    expected_bot_id: &str,
    credentials: &CredentialHome,
    loaded: Option<BotConfigFile>,
) -> Result<CredentialRecovery, FeishuError> {
    recover_bot_directory_with_fs(&credentials.fs, dir, expected_bot_id, credentials, loaded)
}

fn recover_operation(
    dir: &Path,
    credentials: &CredentialHome,
    journal: CredentialJournal,
) -> Result<CredentialCommit, FeishuError> {
    recover_operation_with_fs(&credentials.fs, dir, credentials, journal)
}

fn write_journal(dir: &Path, journal: &CredentialJournal) -> Result<(), FeishuError> {
    LocalJournalFs.store_journal(dir, journal)
}

#[derive(Default)]
struct FaultingJournalFs {
    write_fails: Cell<u32>,
    skip_writes: Cell<u32>,
    confirm_fails: Cell<u32>,
    journal_fails: Cell<u32>,
}

impl FaultingJournalFs {
    fn fail(counter: &Cell<u32>, message: &str) -> Result<(), FeishuError> {
        let count = counter.get();
        if count == 0 {
            return Ok(());
        }
        counter.set(count - 1);
        Err(FeishuError::new(
            FeishuErrorKind::Unavailable,
            message,
            true,
            None,
        ))
    }
}

impl JournalFs for FaultingJournalFs {
    fn replace_config(&self, dir: &Path, config: &BotConfigFile) -> Result<(), FeishuError> {
        Self::fail(
            &self.skip_writes,
            "injected config write skip before replacement",
        )?;
        LocalJournalFs.replace_config(dir, config)?;
        Self::fail(
            &self.write_fails,
            "injected config write failure after replacement",
        )
    }

    fn confirm_config(
        &self,
        dir: &Path,
        expected: Option<&BotConfigFile>,
    ) -> Result<(), FeishuError> {
        Self::fail(
            &self.confirm_fails,
            "injected config durability confirmation failure",
        )?;
        LocalJournalFs.confirm_config(dir, expected)
    }

    fn store_journal(&self, dir: &Path, journal: &CredentialJournal) -> Result<(), FeishuError> {
        if journal.phase == CredentialJournalPhase::CleanupPending {
            Self::fail(
                &self.journal_fails,
                "injected credential journal advancement failure",
            )?;
        }
        LocalJournalFs.store_journal(dir, journal)
    }
}
