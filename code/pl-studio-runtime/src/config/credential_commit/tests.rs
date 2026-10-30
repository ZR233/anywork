use super::*;
use crate::config::credential::CredentialStore;
use crate::config::{ConfigPaths, credential::MemoryCredentialStore};
use pl_model::config::AccountId;
use std::{cell::Cell, sync::Arc};

struct Fixture {
    _home: tempfile::TempDir,
    a: ConfigStore,
    b: ConfigStore,
    credentials: Arc<MemoryCredentialStore>,
    r0: StudioConfig,
}
const ID: &str = "shared-credential";

fn record(generation: &str) -> ChatGptCredentialRecord {
    ChatGptCredentialRecord {
        schema_version: 1,
        registration_id: generation.into(),
        account: ChatGptAccountInfo {
            issuer: "https://auth.openai.com".into(),
            subject: "verified-subject".into(),
            client_id: "issued-client".into(),
            email: None,
            plan_usage_enabled: true,
        },
        ext_agent_host_id: "urn:uuid:00000000-0000-4000-8000-000000000001".into(),
        access_token: format!("secret-access-{generation}"),
        refresh_token: format!("secret-refresh-{generation}"),
        id_token: format!("secret-id-{generation}"),
        scopes: vec!["chatgpt.tokens.use.direct".into()],
        expires_at: crate::studio::unix_seconds() + 3600,
        earliest_refresh_at: None,
        refresh_in_flight: false,
    }
}
fn intent() -> CredentialIntents {
    CredentialIntents::for_account(
        ID,
        &AccountAuthenticationIntent::ChatGpt {
            login_id: "login".into(),
            editor_id: "editor".into(),
        },
    )
}
fn with_record(store: &ConfigStore, base: &StudioConfig, generation: &str) -> StudioConfig {
    let mut next = base.clone();
    let record = record(generation);
    let account = next
        .models
        .accounts
        .get_mut(&AccountId::new(ID).unwrap())
        .unwrap();
    account.authentication = AccountAuthenticationMethod::ChatGpt;
    account.chatgpt_account = Some(record.account.clone());
    account.chatgpt_credentials = Some(record.clone());
    account.chatgpt_session = Some(store.chatgpt_session(ID, &record).unwrap());
    account.bearer_token = None;
    account.bearer_token_env = None;
    next
}
fn api_fixture() -> Fixture {
    api_fixture_with_owner_root(false)
}
fn api_fixture_with_owner_root(separate: bool) -> Fixture {
    let home = tempfile::tempdir().unwrap();
    let credentials = Arc::new(MemoryCredentialStore::default());
    if separate {
        // A distinct logical filesystem for the protected owner; no global paths/mounts.
        credentials
            .account_lock_directory(&home.path().join("protected-owner"))
            .unwrap();
    }
    let a = ConfigStore::with_shared_credentials(
        ConfigPaths::from_config_dir(home.path().join("a")),
        credentials.clone(),
    );
    let b = ConfigStore::with_shared_credentials(
        ConfigPaths::from_config_dir(home.path().join("b")),
        credentials.clone(),
    );
    let mut api = StudioConfig::default_config().unwrap();
    let mut account = pl_model::config::builtin_account_catalog()
        .unwrap()
        .templates
        .into_iter()
        .find(|entry| entry.id.as_str() == "openai")
        .unwrap()
        .account;
    account.bearer_token = Some("original-api-secret".into());
    account.bearer_token_env = None;
    api.models
        .accounts
        .insert(AccountId::new(ID).unwrap(), account);
    a.save(&api).unwrap();
    atomic(
        b.paths().config_file(),
        super::super::store::serialize_persisted_config(&api)
            .unwrap()
            .as_bytes(),
    )
    .unwrap();
    let r0 = a.load().unwrap();
    b.load().unwrap();
    Fixture {
        _home: home,
        a,
        b,
        credentials,
        r0,
    }
}
fn fixture() -> Fixture {
    fixture_with_owner_root(false)
}
fn fixture_with_owner_root(separate: bool) -> Fixture {
    let mut fixture = api_fixture_with_owner_root(separate);
    let r0 = with_record(&fixture.a, &fixture.r0, "R0");
    fixture
        .a
        .commit_config(&fixture.r0, &r0, &intent())
        .unwrap();
    atomic(
        fixture.b.paths().config_file(),
        super::super::store::serialize_persisted_config(&r0)
            .unwrap()
            .as_bytes(),
    )
    .unwrap();
    fixture.b.load().unwrap();
    fixture.r0 = fixture.a.load().unwrap();
    fixture
}
fn current(fixture: &Fixture) -> ChatGptCredentialRecord {
    serde_json::from_str(&fixture.credentials.load_strict(ID).unwrap().unwrap()).unwrap()
}
fn change(fixture: &Fixture, generation: &str) -> (Vec<Change>, StudioConfig) {
    let next = with_record(&fixture.a, &fixture.r0, generation);
    (
        vec![Change {
            id: ID.into(),
            old: fixture.credentials.load_strict(ID).unwrap(),
            new: Some(serde_json::to_string(&record(generation)).unwrap()),
            strict: true,
        }],
        next,
    )
}
fn release_markers(store: &ConfigStore, journal: &Journal) {
    for entry in &journal.entries {
        pl_tool::workspace::move_owned_path(
            &store.pending_path(&entry.account_id).unwrap(),
            &store
                .transaction_dir(journal)
                .join(format!("released-{}.json", entry.digest)),
        )
        .unwrap();
    }
}

#[tokio::test]
async fn stale_cross_home_keep_and_explicit_replacement_cannot_resurrect_r0() {
    let fixture = fixture();
    let old_b = fixture.b.load().unwrap();
    let old_session = old_b.models.accounts[&AccountId::new(ID).unwrap()]
        .chatgpt_session
        .clone()
        .unwrap();
    let r1 = with_record(&fixture.a, &fixture.r0, "R1");
    fixture
        .a
        .commit_config(&fixture.r0, &r1, &intent())
        .unwrap();
    let mut unrelated = old_b.clone();
    unrelated.ui.compact_timeline = !unrelated.ui.compact_timeline;
    assert!(
        fixture
            .b
            .save(&unrelated)
            .unwrap_err()
            .to_string()
            .contains("binding changed")
    );
    let r2 = with_record(&fixture.b, &old_b, "R2");
    assert!(
        fixture
            .b
            .commit_config(&old_b, &r2, &intent())
            .unwrap_err()
            .to_string()
            .contains("binding changed")
    );
    assert_eq!(current(&fixture).registration_id, "R1");
    assert_eq!(
        old_session.access_token().await,
        Err(pl_model::protocol::chatgpt::ChatGptAuthError::Revoked)
    );
}

#[test]
fn frozen_api_binding_also_rejects_a_stale_authentication_switch() {
    let fixture = api_fixture();
    let old_b = fixture.b.load().unwrap();
    let mut changed = fixture.r0.clone();
    changed
        .models
        .accounts
        .get_mut(&AccountId::new(ID).unwrap())
        .unwrap()
        .bearer_token = Some("replacement-api-secret".into());
    fixture.a.save(&changed).unwrap();
    let subscription = with_record(&fixture.b, &old_b, "R0");
    assert!(
        fixture
            .b
            .commit_config(&old_b, &subscription, &intent())
            .unwrap_err()
            .to_string()
            .contains("binding changed")
    );
    assert_eq!(
        fixture.credentials.load_strict(ID).unwrap().as_deref(),
        Some("replacement-api-secret")
    );
    assert!(!fixture.b.pending_path(ID).unwrap().exists());
}

#[test]
fn post_rename_failure_restores_both_sides_and_reopens() {
    let fixture = api_fixture();
    let original = fs::read(fixture.a.paths().config_file()).unwrap();
    let r1 = with_record(&fixture.a, &fixture.r0, "R1");
    let calls = Cell::new(0);
    let writer = |path: &Path, bytes: &[u8]| {
        atomic(path, bytes)?;
        calls.set(calls.get() + 1);
        if calls.get() == 1 {
            return Err(PureError::ConfigError(
                "injected error after replacement".into(),
            ));
        }
        Ok(())
    };
    let error = fixture
        .a
        .commit_config_with(&fixture.r0, &r1, &intent(), &writer)
        .unwrap_err();
    assert!(error.to_string().contains("after replacement"));
    assert_eq!(calls.get(), 2);
    assert_eq!(fs::read(fixture.a.paths().config_file()).unwrap(), original);
    assert_eq!(
        fixture.credentials.load_strict(ID).unwrap().as_deref(),
        Some("original-api-secret")
    );
    let reopened = ConfigStore::with_shared_credentials(
        fixture.a.paths().clone(),
        fixture.credentials.clone(),
    );
    let restored = reopened.load_for_startup().unwrap();
    assert_eq!(
        restored.models.accounts[&AccountId::new(ID).unwrap()].authentication,
        AccountAuthenticationMethod::ApiKey
    );
    assert_eq!(
        restored.models.accounts[&AccountId::new(ID).unwrap()]
            .bearer_token
            .as_deref(),
        Some("original-api-secret")
    );
    assert!(!fixture.a.pending_path(ID).unwrap().exists());
}

#[tokio::test]
async fn failed_rollback_keeps_pending_and_blocks_other_home_and_old_session_until_recovery() {
    let fixture = fixture();
    let old_b = fixture.b.load().unwrap();
    let old_session = old_b.models.accounts[&AccountId::new(ID).unwrap()]
        .chatgpt_session
        .clone()
        .unwrap();
    let mut r1 = fixture.r0.clone();
    let account = r1
        .models
        .accounts
        .get_mut(&AccountId::new(ID).unwrap())
        .unwrap();
    account.authentication = AccountAuthenticationMethod::ApiKey;
    account.chatgpt_account = None;
    account.chatgpt_credentials = None;
    account.chatgpt_session = None;
    account.bearer_token = Some("new-api-key".into());
    let calls = Cell::new(0);
    let writer = |path: &Path, bytes: &[u8]| {
        calls.set(calls.get() + 1);
        if calls.get() == 1 {
            atomic(path, bytes)?;
        }
        Err(PureError::ConfigError(
            "injected commit/rollback failure".into(),
        ))
    };
    assert!(
        fixture
            .a
            .commit_config_with(&fixture.r0, &r1, &intent(), &writer)
            .unwrap_err()
            .to_string()
            .contains("RecoveryRequired")
    );
    assert!(fixture.a.pending_path(ID).unwrap().exists());
    assert!(
        fixture
            .b
            .save(&old_b)
            .unwrap_err()
            .to_string()
            .contains("RecoveryRequired")
    );
    assert!(
        fixture
            .b
            .load()
            .unwrap_err()
            .to_string()
            .contains("RecoveryRequired")
    );
    assert_eq!(
        old_session.access_token().await,
        Err(pl_model::protocol::chatgpt::ChatGptAuthError::RecoveryRequired)
    );
    let reopened = ConfigStore::with_shared_credentials(
        fixture.a.paths().clone(),
        fixture.credentials.clone(),
    );
    reopened.load_for_startup().unwrap();
    assert_eq!(current(&fixture).registration_id, "R0");
    assert!(!fixture.a.pending_path(ID).unwrap().exists());
    fixture.b.save(&old_b).unwrap();
}

#[test]
fn staged_recovery_never_replays_old_snapshots_after_another_owner_commits() {
    let fixture = fixture();
    let (changes, next) = change(&fixture, "R1");
    let journal = fixture
        .a
        .stage(
            &changes,
            super::super::store::serialize_persisted_config(&next)
                .unwrap()
                .as_bytes(),
        )
        .unwrap();
    assert_eq!(current(&fixture).registration_id, "R0");
    let b0 = fixture.b.load().unwrap();
    fixture.a.prepare(&journal).unwrap();
    assert!(fixture.b.save(&b0).is_err());
    release_markers(&fixture.a, &journal); // Crash during staged cleanup after marker release.
    let r2 = with_record(&fixture.b, &b0, "R2");
    fixture.b.commit_config(&b0, &r2, &intent()).unwrap();
    fixture.a.recover_credentials().unwrap();
    assert_eq!(current(&fixture).registration_id, "R2");
    assert!(!fixture.a.transaction_dir(&journal).exists());
}

#[test]
fn prepared_recovery_rolls_back_both_resources_and_rejects_external_conflicts() {
    let fixture = fixture();
    let (changes, next) = change(&fixture, "R1");
    let bytes = super::super::store::serialize_persisted_config(&next).unwrap();
    let mut journal = fixture.a.stage(&changes, bytes.as_bytes()).unwrap();
    fixture.a.prepare(&journal).unwrap();
    journal.phase = Phase::Prepared;
    fixture.a.write_journal(&journal).unwrap();
    fixture
        .a
        .write_account(ID, changes[0].new.as_deref(), true)
        .unwrap();
    atomic(fixture.a.paths().config_file(), bytes.as_bytes()).unwrap();
    let unexpected = format!("{bytes}\n# external modification\n");
    atomic(fixture.a.paths().config_file(), unexpected.as_bytes()).unwrap();
    assert!(fixture.a.recover_credentials().is_err());
    assert_eq!(current(&fixture).registration_id, "R1");
    assert!(fixture.a.pending_path(ID).unwrap().exists());
    atomic(fixture.a.paths().config_file(), bytes.as_bytes()).unwrap();
    fixture.a.recover_credentials().unwrap();
    assert_eq!(current(&fixture).registration_id, "R0");
}

#[tokio::test]
async fn legacy_prepared_transaction_recovers_after_layout_and_before_schema_migration() {
    let fixture = fixture_with_owner_root(true);
    let (changes, next) = change(&fixture, "R1");
    let bytes = super::super::store::serialize_persisted_config(&next).unwrap();
    let mut journal = fixture.a.stage(&changes, bytes.as_bytes()).unwrap();
    let old_version = |bytes: &[u8]| {
        let mut value: toml::Value = toml::from_str(std::str::from_utf8(bytes).unwrap()).unwrap();
        value["schema_version"] = 28.into();
        toml::to_string(&value).unwrap().into_bytes()
    };
    let directory = fixture.a.transaction_dir(&journal);
    let original = old_version(&fs::read(directory.join("original.toml")).unwrap());
    let candidate = old_version(bytes.as_bytes());
    atomic(&directory.join("original.toml"), &original).unwrap();
    atomic(&directory.join("candidate.toml"), &candidate).unwrap();
    journal.original_hash = Some(digest(&original));
    journal.candidate_hash = digest(&candidate);
    fixture.a.prepare(&journal).unwrap();
    journal.phase = Phase::Prepared;
    fixture.a.write_journal(&journal).unwrap();
    fixture
        .a
        .write_account(ID, changes[0].new.as_deref(), true)
        .unwrap();
    atomic(fixture.a.paths().config_file(), &candidate).unwrap();
    let home = fixture.a.paths().config_dir();
    fs::create_dir_all(home.join("v2")).unwrap();
    fs::rename(
        fixture.a.transaction_root(),
        home.join("v2/credential-transactions"),
    )
    .unwrap();
    fs::remove_dir(home.join("data")).unwrap();
    assert!(fixture.a.load_for_startup().is_err());
    assert_eq!(
        fs::read(fixture.a.paths().config_file()).unwrap(),
        candidate
    );
    assert!(home.join("v2/credential-transactions").exists());
    let paths = crate::studio::StudioPaths::from_home(home.to_owned());
    crate::studio::startup::storage_layout::prepare(&paths)
        .await
        .unwrap();
    assert_eq!(
        fs::read(fixture.a.transaction_dir(&journal).join("original.toml")).unwrap(),
        original
    );
    let loaded = fixture.a.load_for_startup().unwrap();
    assert_eq!(
        loaded.schema_version,
        crate::config::STUDIO_CONFIG_SCHEMA_VERSION
    );
    assert_eq!(current(&fixture).registration_id, "R0");
    assert!(!fixture.a.pending_path(ID).unwrap().exists());
    assert!(!fixture.a.transaction_dir(&journal).exists());
    let persisted = fs::read(fixture.a.paths().config_file()).unwrap();
    let reopened = fixture.a.load_for_startup().unwrap();
    assert_eq!(
        fs::read(fixture.a.paths().config_file()).unwrap(),
        persisted
    );
    let account = &reopened.models.accounts[&AccountId::new(ID).unwrap()];
    assert_eq!(
        account.chatgpt_account,
        loaded.models.accounts[&AccountId::new(ID).unwrap()].chatgpt_account
    );
    assert_eq!(
        account
            .chatgpt_credentials
            .as_ref()
            .unwrap()
            .registration_id,
        "R0"
    );
}

#[test]
fn broken_credential_recovery_cannot_trigger_startup_reset() {
    let fixture = fixture();
    let before = fs::read(fixture.a.paths().config_file()).unwrap();
    let directory = fixture
        .a
        .transaction_root()
        .join(uuid::Uuid::new_v4().to_string());
    fs::create_dir_all(&directory).unwrap();
    fs::write(directory.join("journal.json"), b"invalid transaction").unwrap();
    let error = fixture.a.load_for_startup().unwrap_err();
    let error = crate::studio::startup::input_error(error);
    let startup = crate::studio::startup::StudioStartupError::input("prepare_configuration", error);
    assert_eq!(
        startup.kind,
        crate::studio::startup::StudioStartupErrorKind::Migration
    );
    assert_eq!(fs::read(fixture.a.paths().config_file()).unwrap(), before);
    assert!(directory.exists());
}

#[test]
fn direct_configuration_load_rejects_unfinished_layout_before_writing() {
    let fixture = fixture_with_owner_root(true);
    let home = fixture.a.paths().config_dir();
    let before = fs::read(fixture.a.paths().config_file()).unwrap();
    let journal = b"schemaVersion = 1\noperationId = 'layout-interrupted'\nphase = 'building'\ncopied = []\nbotRoots = []\n[[roots]]\nsource = 'v2'\npresent = true\nmoved = true\n[[roots]]\nsource = 'studio/v2'\npresent = false\nmoved = false\n[[roots]]\nsource = 'skills'\npresent = false\nmoved = false\n";
    fs::write(home.join("storage-migration.toml"), journal).unwrap();
    assert!(fixture.a.load_for_startup().is_err());
    assert_eq!(fs::read(fixture.a.paths().config_file()).unwrap(), before);
    assert_eq!(
        fs::read(home.join("storage-migration.toml")).unwrap(),
        journal
    );
}

#[test]
fn terminal_cleanup_after_marker_release_never_replays_over_r2() {
    for terminal in [Phase::Committed, Phase::RolledBack] {
        let fixture = fixture();
        let (changes, next) = change(&fixture, "R1");
        let bytes = super::super::store::serialize_persisted_config(&next).unwrap();
        let mut journal = fixture.a.stage(&changes, bytes.as_bytes()).unwrap();
        fixture.a.prepare(&journal).unwrap();
        if terminal == Phase::Committed {
            fixture
                .a
                .write_account(ID, changes[0].new.as_deref(), true)
                .unwrap();
            atomic(fixture.a.paths().config_file(), bytes.as_bytes()).unwrap();
        }
        journal.phase = terminal;
        fixture.a.write_journal(&journal).unwrap();
        release_markers(&fixture.a, &journal);
        // Interrupted cleanup may already have removed some snapshots/materials.
        fixture
            .credentials
            .delete_transaction(&alias(&journal, &journal.entries[0], "old"))
            .unwrap();
        fs::remove_file(fixture.a.transaction_dir(&journal).join("candidate.toml")).unwrap();
        let before = fs::read(fixture.a.paths().config_file()).unwrap();
        let b = fixture.b.load().unwrap();
        let r2 = with_record(&fixture.b, &b, "R2");
        fixture.b.commit_config(&b, &r2, &intent()).unwrap();
        fixture.a.recover_credentials().unwrap();
        fixture.a.recover_credentials().unwrap();
        assert_eq!(current(&fixture).registration_id, "R2");
        assert_eq!(fs::read(fixture.a.paths().config_file()).unwrap(), before);
        assert!(!fixture.a.transaction_dir(&journal).exists());
    }
}

#[test]
fn transaction_files_never_contain_protected_snapshots_and_cleanup_retains_unknown_files() {
    let fixture = fixture();
    let (changes, next) = change(&fixture, "R1");
    let journal = fixture
        .a
        .stage(
            &changes,
            super::super::store::serialize_persisted_config(&next)
                .unwrap()
                .as_bytes(),
        )
        .unwrap();
    for file in fs::read_dir(fixture.a.transaction_dir(&journal)).unwrap() {
        let bytes = fs::read_to_string(file.unwrap().path()).unwrap();
        for secret in [
            "secret-access",
            "secret-refresh",
            "secret-id",
            "original-api-secret",
        ] {
            assert!(!bytes.contains(secret));
        }
    }
    let unknown = fixture.a.transaction_dir(&journal).join("unknown");
    fs::write(&unknown, "owned elsewhere").unwrap();
    assert!(fixture.a.recover_credentials().is_err());
    assert!(unknown.exists());
    assert_eq!(current(&fixture).registration_id, "R0");
}

/// Interruption after marker publication, or immediately before terminal journal publication.
fn interrupted_cleanup(fixture: &Fixture, phase: Phase) -> Journal {
    let (changes, next) = change(fixture, "R1");
    let candidate = super::super::store::serialize_persisted_config(&next).unwrap();
    let mut journal = fixture.a.stage(&changes, candidate.as_bytes()).unwrap();
    fixture.a.prepare(&journal).unwrap();
    if phase != Phase::Staged {
        journal.phase = Phase::Prepared;
        fixture.a.write_journal(&journal).unwrap();
        if phase == Phase::Committed {
            fixture
                .a
                .write_account(ID, changes[0].new.as_deref(), true)
                .unwrap();
            atomic(fixture.a.paths().config_file(), candidate.as_bytes()).unwrap();
        }
        journal.phase = phase;
    }
    journal
}

#[test]
fn marker_release_stays_on_owner_filesystem_for_staged_and_terminal_recovery() {
    for phase in [Phase::Staged, Phase::Committed, Phase::RolledBack] {
        let fixture = fixture_with_owner_root(true);
        let journal = interrupted_cleanup(&fixture, phase);
        if phase != Phase::Staged {
            fixture.a.write_journal(&journal).unwrap();
        }
        let marker_root = fixture
            .a
            .pending_path(ID)
            .unwrap()
            .parent()
            .unwrap()
            .to_owned();
        assert!(!marker_root.starts_with(fixture.a.paths().config_dir()));
        let unrelated = marker_root.join("unrelated-owner-item");
        fs::write(&unrelated, "not owned by this transaction").unwrap();
        let moves = Cell::new(0);
        // Equivalent EXDEV boundary: all real IO stays in isolated temporary directories.
        // The old cross-root destination necessarily fails; permitted same-FS moves perform
        // the real platform rename and directory durability operations.
        let move_marker = |source: &Path, target: &Path| {
            if !source.starts_with(&marker_root) || !target.starts_with(&marker_root) {
                return Err(PureError::Io(std::io::Error::new(
                    std::io::ErrorKind::CrossesDevices,
                    "injected EXDEV at marker filesystem boundary",
                )));
            }
            moves.set(moves.get() + 1);
            move_owned(source, target)
        };
        let old_destination = fixture
            .a
            .transaction_dir(&journal)
            .join("released-marker.json");
        assert!(
            matches!(move_marker(&fixture.a.pending_path(ID).unwrap(), &old_destination),
            Err(PureError::Io(error)) if error.kind() == std::io::ErrorKind::CrossesDevices)
        );
        fixture
            .a
            .recover_credentials_with_io(
                &atomic,
                &CleanupIo {
                    journal_write: &atomic,
                    marker_move: &move_marker,
                    release_write: &atomic,
                },
            )
            .unwrap();
        assert_eq!(moves.get(), 1);
        assert!(!fixture.a.pending_path(ID).unwrap().exists());
        assert!(
            !fixture
                .a
                .released_marker_path(&journal, &journal.entries[0])
                .unwrap()
                .exists()
        );
        assert!(!fixture.a.transaction_dir(&journal).exists());
        assert!(unrelated.exists());
        assert_eq!(
            current(&fixture).registration_id,
            if phase == Phase::Committed {
                "R1"
            } else {
                "R0"
            }
        );
        fixture.a.load().unwrap();
        fixture.b.load().unwrap();
    }
}

fn visible_replace_then_sync_failure(path: &Path, bytes: &[u8]) -> Result<()> {
    use std::io::Write;
    let mut file = tempfile::NamedTempFile::new_in(path.parent().unwrap())?;
    file.write_all(bytes)?;
    file.as_file().sync_all()?;
    file.persist(path)
        .map_err(|error| PureError::Io(error.error))?;
    // The replacement is genuinely visible, but no parent-directory durability
    // acknowledgement is returned. This is the atomic writer's post-rename error boundary.
    Err(PureError::Io(std::io::Error::other(
        "injected atomic replacement directory sync failure",
    )))
}

fn rename_marker_then_sync_failure(source: &Path, target: &Path) -> Result<()> {
    // Do not call move_owned: the failure is BEFORE its directory-sync acknowledgement.
    fs::rename(source, target)?;
    Err(PureError::Io(std::io::Error::other(
        "injected marker directory sync failure",
    )))
}

#[tokio::test]
async fn visible_terminal_requires_durable_reconfirmation_before_any_marker_release() {
    use pl_model::protocol::chatgpt::ChatGptAuthError;
    for phase in [Phase::Committed, Phase::RolledBack] {
        let fixture = fixture_with_owner_root(true);
        let old_b = fixture.b.load().unwrap();
        let old_session = old_b.models.accounts[&AccountId::new(ID).unwrap()]
            .chatgpt_session
            .clone()
            .unwrap();
        let journal = interrupted_cleanup(&fixture, phase);
        let fail = Cell::new(true);
        let confirmations = Cell::new(0);
        let journal_write = |path: &Path, bytes: &[u8]| {
            confirmations.set(confirmations.get() + 1);
            if fail.get() {
                visible_replace_then_sync_failure(path, bytes)
            } else {
                atomic(path, bytes)
            }
        };
        assert!(
            fixture
                .a
                .write_journal_with(&journal, &journal_write)
                .is_err()
        );
        let visible: Journal = serde_json::from_slice(
            &fs::read(fixture.a.transaction_dir(&journal).join("journal.json")).unwrap(),
        )
        .unwrap();
        assert_eq!(visible.phase, phase);
        // Same-process recovery must not confuse this visible terminal with durability.
        assert!(
            fixture
                .a
                .recover_credentials_with_io(
                    &atomic,
                    &CleanupIo {
                        journal_write: &journal_write,
                        marker_move: &move_owned,
                        release_write: &atomic,
                    },
                )
                .is_err()
        );
        assert_eq!(confirmations.get(), 2);
        assert!(
            fixture
                .a
                .owned_marker(&journal, &journal.entries[0])
                .unwrap()
        );
        assert!(fixture.a.transaction_dir(&journal).exists());
        for side in ["old", "new"] {
            assert!(
                fixture
                    .credentials
                    .read_transaction(&alias(&journal, &journal.entries[0], side))
                    .unwrap()
                    .is_some()
            );
        }
        assert!(
            fixture
                .b
                .save(&old_b)
                .unwrap_err()
                .to_string()
                .contains("RecoveryRequired")
        );
        assert_eq!(
            old_session.access_token().await,
            Err(ChatGptAuthError::RecoveryRequired)
        );
        assert_eq!(
            current(&fixture).registration_id,
            if phase == Phase::Committed {
                "R1"
            } else {
                "R0"
            }
        );

        fail.set(false);
        // Confirmation now succeeds. Rename is visible but its directory sync fails;
        // subsequent legal R2 must survive release confirmation and cleanup resumption.
        assert!(
            fixture
                .a
                .recover_credentials_with_io(
                    &atomic,
                    &CleanupIo {
                        journal_write: &journal_write,
                        marker_move: &rename_marker_then_sync_failure,
                        release_write: &atomic,
                    },
                )
                .is_err()
        );
        assert_eq!(confirmations.get(), 3);
        assert!(!fixture.a.pending_path(ID).unwrap().exists());
        let b = fixture.b.load().unwrap();
        let r2 = with_record(&fixture.b, &b, "R2");
        fixture.b.commit_config(&b, &r2, &intent()).unwrap();
        fixture.a.recover_credentials().unwrap();
        assert_eq!(current(&fixture).registration_id, "R2");
        assert_eq!(
            old_session.access_token().await,
            Err(ChatGptAuthError::Revoked)
        );
        assert!(!fixture.a.transaction_dir(&journal).exists());
    }
}

const SECOND_ID: &str = "shared-credential-second";

fn multi_entry_fixture() -> Fixture {
    let mut fixture = fixture_with_owner_root(true);
    let mut next = fixture.r0.clone();
    let mut second = next.models.accounts[&AccountId::new(ID).unwrap()].clone();
    let mut saved = record("R0-second");
    saved.account.subject = "second-verified-subject".into();
    saved.account.client_id = "second-issued-client".into();
    second.chatgpt_account = Some(saved.account.clone());
    second.chatgpt_session = Some(fixture.a.chatgpt_session(SECOND_ID, &saved).unwrap());
    second.chatgpt_credentials = Some(saved);
    next.models
        .accounts
        .insert(AccountId::new(SECOND_ID).unwrap(), second);
    let intents = CredentialIntents::for_account(
        SECOND_ID,
        &AccountAuthenticationIntent::ChatGpt {
            login_id: "second-login".into(),
            editor_id: "second-editor".into(),
        },
    );
    fixture
        .a
        .commit_config(&fixture.r0, &next, &intents)
        .unwrap();
    atomic(
        fixture.b.paths().config_file(),
        super::super::store::serialize_persisted_config(&next)
            .unwrap()
            .as_bytes(),
    )
    .unwrap();
    fixture.b.load().unwrap();
    fixture.r0 = fixture.a.load().unwrap();
    fixture
}

fn interrupted_multi_entry_cleanup(fixture: &Fixture, phase: Phase) -> Journal {
    let (mut changes, mut next) = change(fixture, "R1");
    let second = next
        .models
        .accounts
        .get_mut(&AccountId::new(SECOND_ID).unwrap())
        .unwrap();
    let mut saved = second.chatgpt_credentials.clone().unwrap();
    saved.registration_id = "R1-second".into();
    saved.access_token = "new-second-access".into();
    saved.refresh_token = "new-second-refresh".into();
    second.chatgpt_session = Some(fixture.a.chatgpt_session(SECOND_ID, &saved).unwrap());
    second.chatgpt_credentials = Some(saved.clone());
    changes.push(Change {
        id: SECOND_ID.into(),
        old: fixture.credentials.load_strict(SECOND_ID).unwrap(),
        new: Some(serde_json::to_string(&saved).unwrap()),
        strict: true,
    });
    let candidate = super::super::store::serialize_persisted_config(&next).unwrap();
    let mut journal = fixture.a.stage(&changes, candidate.as_bytes()).unwrap();
    fixture.a.prepare(&journal).unwrap();
    if phase != Phase::Staged {
        journal.phase = Phase::Prepared;
        fixture.a.write_journal(&journal).unwrap();
        if phase == Phase::Committed {
            for change in changes {
                fixture
                    .a
                    .write_account(&change.id, change.new.as_deref(), true)
                    .unwrap();
            }
            atomic(fixture.a.paths().config_file(), candidate.as_bytes()).unwrap();
        }
        journal.phase = phase;
        fixture.a.write_journal(&journal).unwrap();
    }
    journal
}

#[tokio::test]
async fn every_release_directory_must_be_confirmed_before_any_recovery_material_is_destroyed() {
    use pl_model::protocol::chatgpt::ChatGptAuthError;
    for phase in [Phase::Staged, Phase::Committed, Phase::RolledBack] {
        for home_local in [false, true] {
            let fixture = multi_entry_fixture();
            let old_b = fixture.b.load().unwrap();
            let old_session = old_b.models.accounts[&AccountId::new(ID).unwrap()]
                .chatgpt_session
                .clone()
                .unwrap();
            let journal = interrupted_multi_entry_cleanup(&fixture, phase);
            // Both current and supported home-local receipts can be visible after only
            // rename, without any successful marker-parent sync. No complete move helper.
            let mut receipts = Vec::new();
            for entry in &journal.entries {
                let destination = if home_local {
                    fixture
                        .a
                        .transaction_dir(&journal)
                        .join(format!("released-{}.json", entry.digest))
                } else {
                    fixture.a.released_marker_path(&journal, entry).unwrap()
                };
                assert!(
                    rename_marker_then_sync_failure(
                        &fixture.a.pending_path(&entry.account_id).unwrap(),
                        &destination,
                    )
                    .is_err()
                );
                receipts.push(destination);
            }
            let owner_directory = fixture
                .a
                .pending_path(ID)
                .unwrap()
                .parent()
                .unwrap()
                .to_owned();
            let fail = Cell::new(true);
            let confirmations = Cell::new(0);
            let second_receipt = fixture
                .a
                .released_marker_path(&journal, &journal.entries[1])
                .unwrap();
            let release_write = |path: &Path, bytes: &[u8]| {
                // A home-local receipt must NOT cause a home-only durability confirmation.
                assert_eq!(path.parent(), Some(owner_directory.as_path()));
                confirmations.set(confirmations.get() + 1);
                if fail.get() && path == second_receipt {
                    visible_replace_then_sync_failure(path, bytes)
                } else {
                    atomic(path, bytes)
                }
            };
            let io = CleanupIo {
                journal_write: &atomic,
                marker_move: &move_owned,
                release_write: &release_write,
            };
            // Reentry sees no pending marker and visible receipts. A failed confirmation
            // of the second entry must not destroy even the first entry's secret snapshots.
            for _ in 0..2 {
                assert!(fixture.a.recover_credentials_with_io(&atomic, &io).is_err());
                assert!(
                    fixture
                        .a
                        .transaction_dir(&journal)
                        .join("journal.json")
                        .exists()
                );
                for receipt in &receipts {
                    assert!(receipt.exists());
                }
                for entry in &journal.entries {
                    for side in ["old", "new"] {
                        assert!(
                            fixture
                                .credentials
                                .read_transaction(&alias(&journal, entry, side))
                                .unwrap()
                                .is_some()
                        );
                    }
                }
            }
            assert_eq!(confirmations.get(), 4);

            // No terminal/staged cleanup may replay old snapshots. A real second owner
            // can adopt the canonical binding and commit a later R2 after visible release.
            let b = fixture.b.load().unwrap();
            let r2 = with_record(&fixture.b, &b, "R2");
            fixture.b.commit_config(&b, &r2, &intent()).unwrap();
            assert_eq!(
                old_session.access_token().await,
                Err(ChatGptAuthError::Revoked)
            );
            let foreign_path = fixture.a.pending_path(ID).unwrap();
            let foreign = encoded(&Marker {
                schema_version: 1,
                transaction_id: uuid::Uuid::new_v4().to_string(),
                owner: fixture.b.paths().config_dir().canonicalize().unwrap(),
            })
            .unwrap();
            atomic(&foreign_path, &foreign).unwrap();
            fail.set(false);
            fixture.a.recover_credentials_with_io(&atomic, &io).unwrap();
            assert_eq!(current(&fixture).registration_id, "R2");
            assert_eq!(fs::read(&foreign_path).unwrap(), foreign);
            assert!(!fixture.a.transaction_dir(&journal).exists());
            for entry in &journal.entries {
                for side in ["old", "new"] {
                    assert!(
                        fixture
                            .credentials
                            .read_transaction(&alias(&journal, entry, side))
                            .unwrap()
                            .is_none()
                    );
                }
                assert!(
                    !fixture
                        .a
                        .released_marker_path(&journal, entry)
                        .unwrap()
                        .exists()
                );
            }
        }
    }
}
