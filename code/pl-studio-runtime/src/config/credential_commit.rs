//! Credential participation in the configuration coordinator: frozen bindings, protected
//! snapshots and versioned recovery. No plaintext token payload enters filesystem journals.
use super::{ConfigStore, StudioConfig};
use crate::{PureError, Result};
use pl_model::protocol::chatgpt::ChatGptCredentialRecord;
use pl_protocol::studio::{
    AccountAuthenticationIntent, AccountAuthenticationMethod, ChatGptAccountInfo,
};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    path::{Path, PathBuf},
};

pub(super) fn digest(bytes: &[u8]) -> String {
    hex::encode(Sha256::digest(bytes))
}
pub(super) fn recovery_required() -> PureError {
    PureError::ConfigError("RecoveryRequired: credential transaction requires recovery in its owning home; materials preserved".into())
}
fn stale() -> PureError {
    PureError::ConfigError("credential binding changed; reload configuration before saving".into())
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) enum Binding {
    Api(Option<String>),
    OAuth {
        generation: String,
        identity: ChatGptAccountInfo,
    },
}
impl Binding {
    fn api(payload: Option<&str>) -> Self {
        Self::Api(payload.map(|value| digest(value.as_bytes())))
    }
    fn oauth(record: &ChatGptCredentialRecord) -> Self {
        Self::OAuth {
            generation: record.registration_id.clone(),
            identity: record.account.clone(),
        }
    }
    fn matches(&self, payload: Option<&str>) -> bool {
        match self {
            Self::Api(_) => {
                !payload.is_some_and(|value| {
                    serde_json::from_str::<ChatGptCredentialRecord>(value).is_ok()
                }) && self == &Self::api(payload)
            }
            Self::OAuth { .. } => payload
                .and_then(|value| serde_json::from_str::<ChatGptCredentialRecord>(value).ok())
                .is_some_and(|record| self == &Self::oauth(&record)),
        }
    }
}

#[derive(Clone, Default)]
pub(super) struct Baseline(pub BTreeMap<String, Binding>);
impl Baseline {
    pub(super) fn from_config(config: &StudioConfig) -> Result<Self> {
        let mut bindings = BTreeMap::new();
        for (id, account) in &config.models.accounts {
            let binding = if account.authentication == AccountAuthenticationMethod::ChatGpt {
                let record = account.chatgpt_credentials.as_ref().ok_or_else(stale)?;
                record.validate().map_err(|_| stale())?;
                Binding::oauth(record)
            } else {
                Binding::api(account.bearer_token.as_deref())
            };
            bindings.insert(id.to_string(), binding);
        }
        Ok(Self(bindings))
    }
}

/// Explicit authorization supplied by the successful login/selected authentication command.
/// Ordinary settings saves never infer a new OAuth registration from the current keyring value.
#[derive(Default)]
pub(crate) struct CredentialIntents {
    replacements: BTreeSet<String>,
}
impl CredentialIntents {
    pub(crate) fn for_account(id: &str, intent: &AccountAuthenticationIntent) -> Self {
        Self {
            replacements: if matches!(intent, AccountAuthenticationIntent::Keep) {
                BTreeSet::new()
            } else {
                [id.to_owned()].into_iter().collect()
            },
        }
    }
}

enum Intent {
    Keep,
    Replace(Option<String>),
    Delete,
}
struct Change {
    id: String,
    old: Option<String>,
    new: Option<String>,
    strict: bool,
}

#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
enum Phase {
    Staged,
    Prepared,
    Committed,
    RolledBack,
}
#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Entry {
    account_id: String,
    digest: String,
    old_hash: String,
    new_hash: String,
}
#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Journal {
    schema_version: u32,
    transaction_id: String,
    owner: PathBuf,
    phase: Phase,
    original_hash: Option<String>,
    candidate_hash: String,
    entries: Vec<Entry>,
}
#[derive(Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Marker {
    schema_version: u32,
    transaction_id: String,
    owner: PathBuf,
}
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ProtectedSnapshot {
    schema_version: u32,
    payload: Option<String>,
}

fn encoded<T: Serialize>(value: &T) -> Result<Vec<u8>> {
    serde_json::to_vec(value).map_err(|_| recovery_required())
}
fn snapshot(value: &Option<String>) -> Result<String> {
    serde_json::to_string(&ProtectedSnapshot {
        schema_version: 1,
        payload: value.clone(),
    })
    .map_err(|_| recovery_required())
}
fn alias(journal: &Journal, entry: &Entry, side: &str) -> String {
    format!(
        "credential-transaction:{}:{}:{side}",
        journal.transaction_id, entry.digest
    )
}
fn atomic(path: &Path, bytes: &[u8]) -> Result<()> {
    pl_tool::workspace::write_file_atomically(path, bytes).map_err(Into::into)
}
fn move_owned(source: &Path, target: &Path) -> Result<()> {
    pl_tool::workspace::move_owned_path(source, target).map_err(Into::into)
}
/// The existing platform IO primitives, kept injectable at the recovery boundary.
struct CleanupIo<'a> {
    journal_write: &'a dyn Fn(&Path, &[u8]) -> Result<()>,
    marker_move: &'a dyn Fn(&Path, &Path) -> Result<()>,
    release_write: &'a dyn Fn(&Path, &[u8]) -> Result<()>,
}
impl CleanupIo<'_> {
    fn platform() -> Self {
        Self {
            journal_write: &atomic,
            marker_move: &move_owned,
            release_write: &atomic,
        }
    }
}
fn file_bytes(path: &Path) -> Result<Option<Vec<u8>>> {
    match fs::read(path) {
        Ok(value) => Ok(Some(value)),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            if fs::symlink_metadata(path).is_ok() {
                return Err(recovery_required());
            }
            Ok(None)
        }
        Err(error) => Err(error.into()),
    }
}

impl ConfigStore {
    fn transaction_root(&self) -> PathBuf {
        self.paths()
            .config_dir()
            .join("data/credential-transactions")
    }
    fn transaction_dir(&self, journal: &Journal) -> PathBuf {
        self.transaction_root().join(&journal.transaction_id)
    }
    fn pending_path(&self, id: &str) -> Result<PathBuf> {
        Ok(self.chatgpt_lock_path(id)?.with_extension("pending.json"))
    }
    fn released_marker_path(&self, journal: &Journal, entry: &Entry) -> Result<PathBuf> {
        // A configured home and the OS credential owner may be on different filesystems.
        // Rename within the marker's own directory; never move it into the home journal.
        Ok(self
            .pending_path(&entry.account_id)?
            .with_file_name(format!(
                ".released-{}-{}.json",
                journal.transaction_id, entry.digest,
            )))
    }
    pub(super) fn ensure_credential_available(&self, id: &str) -> Result<()> {
        ensure_available(&self.pending_path(id)?)
    }
    pub(super) fn lock_accounts(
        &self,
        ids: impl IntoIterator<Item = String>,
    ) -> Result<Vec<fs::File>> {
        let ids = ids.into_iter().collect::<BTreeSet<_>>();
        let mut locks = Vec::new();
        for id in ids {
            let path = self.chatgpt_lock_path(&id)?;
            fs::create_dir_all(path.parent().ok_or_else(recovery_required)?)?;
            let file = fs::OpenOptions::new()
                .create(true)
                .truncate(false)
                .read(true)
                .write(true)
                .open(path)?;
            fs4::FileExt::try_lock(&file).map_err(|_| {
                PureError::ConfigError("account credential transaction is busy".into())
            })?;
            locks.push(file);
        }
        Ok(locks)
    }

    /// `baseline` comes from the original canonical snapshot, never a just-in-time keyring read.
    pub(super) fn commit_credentials(
        &self,
        baseline: &Baseline,
        candidate: &StudioConfig,
        intents: &CredentialIntents,
        replace: &impl Fn(&Path, &[u8]) -> Result<()>,
    ) -> Result<()> {
        self.recover_credentials_with(replace)
            .map_err(|_| recovery_required())?;
        candidate.validate_declarations()?;
        let content = super::store::serialize_persisted_config(candidate)?.into_bytes();
        fs::create_dir_all(self.paths().config_dir())?;
        let ids = baseline
            .0
            .keys()
            .cloned()
            .chain(candidate.models.accounts.keys().map(ToString::to_string))
            .collect::<BTreeSet<_>>();
        let _locks = self.lock_accounts(ids.iter().cloned())?;
        let mut changes = Vec::new();
        let mut needs_transaction = false;
        for id in ids {
            self.ensure_credential_available(&id)?;
            let expected = baseline.0.get(&id).cloned().unwrap_or(Binding::Api(None));
            let old_oauth = matches!(expected, Binding::OAuth { .. });
            let old = if old_oauth {
                self.credentials.load_strict(&id)?
            } else {
                self.credentials.load(&id)?
            };
            if !expected.matches(old.as_deref()) {
                return Err(stale());
            }
            let account = candidate
                .models
                .accounts
                .iter()
                .find(|(key, _)| key.as_str() == id)
                .map(|(_, value)| value);
            let new_oauth = account
                .is_some_and(|value| value.authentication == AccountAuthenticationMethod::ChatGpt);
            let intent = match account {
                None => Intent::Delete,
                Some(account) if new_oauth => {
                    let record = account.chatgpt_credentials.as_ref().ok_or_else(stale)?;
                    record.validate().map_err(|_| stale())?;
                    if account.chatgpt_account.as_ref() != Some(&record.account) {
                        return Err(stale());
                    }
                    if expected == Binding::oauth(record) {
                        Intent::Keep
                    } else if intents.replacements.contains(&id) {
                        Intent::Replace(Some(serde_json::to_string(record).map_err(|_| stale())?))
                    } else {
                        return Err(stale());
                    }
                }
                Some(account) => {
                    if old_oauth && !intents.replacements.contains(&id) {
                        return Err(stale());
                    }
                    let new = account
                        .bearer_token
                        .clone()
                        .filter(|value| !value.trim().is_empty());
                    if new.as_deref().is_some_and(|payload| {
                        serde_json::from_str::<ChatGptCredentialRecord>(payload).is_ok()
                    }) {
                        return Err(PureError::ConfigError(
                            "OAuth credential material cannot be saved as an API key".into(),
                        ));
                    }
                    if !old_oauth && expected == Binding::api(new.as_deref()) {
                        Intent::Keep
                    } else {
                        Intent::Replace(new)
                    }
                }
            };
            let new = match intent {
                Intent::Keep => continue, // In particular, preserve latest same-generation refresh/in-flight state.
                Intent::Replace(value) => value,
                Intent::Delete => None,
            };
            if new == old {
                continue;
            }
            needs_transaction |= old_oauth || new_oauth;
            changes.push(Change {
                id,
                old,
                new,
                strict: old_oauth || new_oauth,
            });
        }
        if needs_transaction {
            // All changed aliases must be recoverable, including API siblings changed in the
            // same config command. A process lease is not a durable old snapshot.
            for change in &changes {
                if self.credentials.load_strict(&change.id)? != change.old {
                    return Err(PureError::ConfigError("durable credential snapshots are unavailable; authentication change was not saved".into()));
                }
            }
            return self.recoverable_commit(&changes, &content, replace);
        }
        // Pure API updates retain the established process-lease behavior.
        let mut previous = Vec::new();
        for change in changes {
            previous.push((change.id.clone(), change.old, change.strict));
            if let Err(error) = self.write_account(&change.id, change.new.as_deref(), change.strict)
            {
                self.restore_api(&previous)?;
                return Err(error);
            }
        }
        if let Err(error) = replace(self.paths().config_file(), &content) {
            self.restore_api(&previous)?;
            return Err(error);
        }
        Ok(())
    }

    fn write_account(&self, id: &str, value: Option<&str>, strict: bool) -> Result<()> {
        match (value, strict) {
            (Some(value), true) => self.credentials.save_strict(id, value)?,
            (Some(value), false) => self.credentials.save(id, value)?,
            (None, true) => self.credentials.delete_strict(id)?,
            (None, false) => self.credentials.delete(id)?,
        }
        let read = if strict {
            self.credentials.load_strict(id)?
        } else {
            self.credentials.load(id)?
        };
        if read.as_deref() != value {
            return Err(recovery_required());
        }
        Ok(())
    }
    fn restore_api(&self, previous: &[(String, Option<String>, bool)]) -> Result<()> {
        for (id, value, strict) in previous.iter().rev() {
            self.write_account(id, value.as_deref(), *strict)?;
        }
        Ok(())
    }

    fn recoverable_commit(
        &self,
        changes: &[Change],
        candidate: &[u8],
        replace: &impl Fn(&Path, &[u8]) -> Result<()>,
    ) -> Result<()> {
        let journal = self.stage(changes, candidate)?;
        // Failure here can include a post-rename error. Leave the durable staged record;
        // recovery only cleans preparation and never replays old canonical credentials.
        self.prepare(&journal).map_err(|_| recovery_required())?;
        let mut prepared = journal.clone();
        prepared.phase = Phase::Prepared;
        self.write_journal(&prepared)
            .map_err(|_| recovery_required())?;
        let committed = (|| {
            for change in changes {
                self.write_account(&change.id, change.new.as_deref(), true)?;
            }
            replace(self.paths().config_file(), candidate)?;
            if file_bytes(self.paths().config_file())?.as_deref() != Some(candidate) {
                return Err(recovery_required());
            }
            for change in changes {
                if self.credentials.load_strict(&change.id)? != change.new {
                    return Err(recovery_required());
                }
            }
            Ok(())
        })();
        if let Err(error) = committed {
            self.rollback(&prepared, replace)
                .map_err(|_| recovery_required())?;
            return Err(error);
        }
        let mut terminal = prepared;
        terminal.phase = Phase::Committed;
        // An error may follow the terminal rename; never roll back from an in-memory
        // Prepared phase after attempting to publish a terminal journal.
        self.write_journal(&terminal)
            .map_err(|_| recovery_required())?;
        self.cleanup(&terminal).map_err(|_| recovery_required())
    }

    fn stage(&self, changes: &[Change], candidate: &[u8]) -> Result<Journal> {
        let original = file_bytes(self.paths().config_file())?;
        if let Some(original) = &original {
            // Reject inline secrets/abnormal source documents before copying any ordinary file.
            let text = std::str::from_utf8(original).map_err(|_| recovery_required())?;
            super::store::parse_current_config(text).map_err(|_| recovery_required())?;
        }
        let mut journal = Journal {
            schema_version: 1,
            transaction_id: uuid::Uuid::new_v4().to_string(),
            owner: self.paths().config_dir().canonicalize()?,
            phase: Phase::Staged,
            original_hash: original.as_deref().map(digest),
            candidate_hash: digest(candidate),
            entries: Vec::new(),
        };
        for change in changes {
            journal.entries.push(Entry {
                account_id: change.id.clone(),
                digest: digest(change.id.as_bytes()),
                old_hash: digest(snapshot(&change.old)?.as_bytes()),
                new_hash: digest(snapshot(&change.new)?.as_bytes()),
            });
        }
        let root = self.transaction_root();
        fs::create_dir_all(&root)?;
        let staging = tempfile::Builder::new()
            .prefix(".staging-")
            .tempdir_in(&root)?;
        if let Some(original) = original {
            atomic(&staging.path().join("original.toml"), &original)?;
        }
        atomic(&staging.path().join("candidate.toml"), candidate)?;
        atomic(&staging.path().join("journal.json"), &encoded(&journal)?)?;
        let staging = staging.keep();
        pl_tool::workspace::move_owned_path(&staging, &self.transaction_dir(&journal))?;
        // The staged journal is already discoverable if any protected write fails.
        for (entry, change) in journal.entries.iter().zip(changes) {
            self.credentials
                .write_transaction(&alias(&journal, entry, "old"), &snapshot(&change.old)?)?;
            self.credentials
                .write_transaction(&alias(&journal, entry, "new"), &snapshot(&change.new)?)?;
        }
        Ok(journal)
    }
    fn write_journal(&self, journal: &Journal) -> Result<()> {
        self.write_journal_with(journal, &atomic)
    }
    fn write_journal_with(
        &self,
        journal: &Journal,
        write: &dyn Fn(&Path, &[u8]) -> Result<()>,
    ) -> Result<()> {
        write(
            &self.transaction_dir(journal).join("journal.json"),
            &encoded(journal)?,
        )
    }
    fn prepare(&self, journal: &Journal) -> Result<()> {
        for entry in &journal.entries {
            self.read_snapshot(journal, entry, "old", false)?;
            self.read_snapshot(journal, entry, "new", false)?;
            let path = self.pending_path(&entry.account_id)?;
            ensure_available(&path)?;
            atomic(
                &path,
                &encoded(&Marker {
                    schema_version: 1,
                    transaction_id: journal.transaction_id.clone(),
                    owner: journal.owner.clone(),
                })?,
            )?;
        }
        Ok(())
    }

    pub(super) fn recover_credentials(&self) -> Result<()> {
        self.recover_credentials_with(&atomic)
            .map_err(|_| recovery_required())
    }
    fn recover_credentials_with(
        &self,
        replace: &impl Fn(&Path, &[u8]) -> Result<()>,
    ) -> Result<()> {
        self.recover_credentials_with_io(replace, &CleanupIo::platform())
    }
    fn recover_credentials_with_io(
        &self,
        replace: &impl Fn(&Path, &[u8]) -> Result<()>,
        cleanup_io: &CleanupIo<'_>,
    ) -> Result<()> {
        let home = self.paths().config_dir();
        crate::studio::startup::validate_credential_recovery(home)
            .map_err(|_| recovery_required())?;
        let layout = home.join("storage-migration.toml");
        match fs::symlink_metadata(&layout) {
            Ok(_) => {
                pl_tool::workspace::path_safety::validate_path_for_write(home, &layout)
                    .map_err(|_| recovery_required())?;
                if crate::studio::startup::storage_layout::incomplete_operation(&layout)
                    .map_err(|_| recovery_required())?
                {
                    return Err(recovery_required());
                }
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(_) => return Err(recovery_required()),
        }
        for relative in [
            "v2/credential-transactions",
            "studio/v2/credential-transactions",
        ] {
            let legacy = home.join(relative);
            match fs::symlink_metadata(&legacy) {
                Ok(meta) => {
                    pl_tool::workspace::path_safety::validate_path_for_write(home, &legacy)
                        .map_err(|_| recovery_required())?;
                    if !meta.is_dir()
                        || pl_tool::workspace::path_safety::is_link_or_reparse(&meta)
                        || fs::read_dir(&legacy)
                            .map_err(|_| recovery_required())?
                            .next()
                            .is_some()
                    {
                        return Err(recovery_required());
                    }
                }
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
                Err(_) => return Err(recovery_required()),
            }
        }
        let root = self.transaction_root();
        let directories = match fs::read_dir(&root) {
            Ok(entries) => entries,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
            Err(_) => return Err(recovery_required()),
        };
        for directory in directories {
            let directory = directory.map_err(|_| recovery_required())?;
            let name = directory.file_name().to_string_lossy().into_owned();
            if name.starts_with(".staging-") {
                continue;
            } // No canonical alias was touched before publication.
            if uuid::Uuid::parse_str(&name).is_err() || !directory.file_type()?.is_dir() {
                return Err(recovery_required());
            }
            let bytes = file_bytes(&directory.path().join("journal.json"))?;
            let Some(bytes) = bytes else {
                if fs::read_dir(directory.path())?.next().is_none() {
                    continue;
                }
                return Err(recovery_required());
            };
            let journal: Journal =
                serde_json::from_slice(&bytes).map_err(|_| recovery_required())?;
            if journal.schema_version != 1
                || journal.transaction_id != name
                || journal.owner != self.paths().config_dir().canonicalize()?
                || journal.entries.is_empty()
            {
                return Err(recovery_required());
            }
            let mut seen = BTreeSet::new();
            for entry in &journal.entries {
                if entry.digest != digest(entry.account_id.as_bytes())
                    || !seen.insert(&entry.account_id)
                {
                    return Err(recovery_required());
                }
            }
            let _locks =
                self.lock_accounts(journal.entries.iter().map(|entry| entry.account_id.clone()))?;
            match journal.phase {
                Phase::Prepared => self.rollback(&journal, replace)?,
                Phase::Staged | Phase::Committed | Phase::RolledBack => {
                    self.cleanup_with_io(&journal, cleanup_io)?;
                }
            }
        }
        Ok(())
    }
    fn read_snapshot(
        &self,
        journal: &Journal,
        entry: &Entry,
        side: &str,
        optional: bool,
    ) -> Result<Option<String>> {
        let Some(payload) = self
            .credentials
            .read_transaction(&alias(journal, entry, side))?
        else {
            if optional {
                return Ok(None);
            }
            return Err(recovery_required());
        };
        let expected = if side == "old" {
            &entry.old_hash
        } else {
            &entry.new_hash
        };
        if &digest(payload.as_bytes()) != expected {
            return Err(recovery_required());
        }
        let decoded: ProtectedSnapshot =
            serde_json::from_str(&payload).map_err(|_| recovery_required())?;
        if decoded.schema_version != 1 {
            return Err(recovery_required());
        }
        Ok(Some(payload))
    }
    fn snapshot_value(
        &self,
        journal: &Journal,
        entry: &Entry,
        side: &str,
    ) -> Result<Option<String>> {
        let bytes = self
            .read_snapshot(journal, entry, side, false)?
            .ok_or_else(recovery_required)?;
        let decoded: ProtectedSnapshot =
            serde_json::from_str(&bytes).map_err(|_| recovery_required())?;
        Ok(decoded.payload)
    }
    fn owned_marker(&self, journal: &Journal, entry: &Entry) -> Result<bool> {
        let Some(bytes) = file_bytes(&self.pending_path(&entry.account_id)?)? else {
            return Ok(false);
        };
        let marker: Marker = serde_json::from_slice(&bytes).map_err(|_| recovery_required())?;
        Ok(marker
            == Marker {
                schema_version: 1,
                transaction_id: journal.transaction_id.clone(),
                owner: journal.owner.clone(),
            })
    }
    fn owned_release_receipt(&self, journal: &Journal, path: &Path) -> Result<bool> {
        let Some(bytes) = file_bytes(path)? else {
            return Ok(false);
        };
        let marker: Marker = serde_json::from_slice(&bytes).map_err(|_| recovery_required())?;
        if marker
            != (Marker {
                schema_version: 1,
                transaction_id: journal.transaction_id.clone(),
                owner: journal.owner.clone(),
            })
        {
            return Err(recovery_required());
        }
        Ok(true)
    }
    fn confirm_marker_release(
        &self,
        journal: &Journal,
        entry: &Entry,
        io: &CleanupIo<'_>,
    ) -> Result<()> {
        if self.owned_marker(journal, entry)? {
            return Err(recovery_required());
        }
        let receipt = self.released_marker_path(journal, entry)?;
        self.owned_release_receipt(journal, &receipt)?;
        // A missing pending path or visible receipt is not a directory-sync ACK. Rewriting
        // our own receipt with the platform atomic writer confirms the current directory
        // entries in the actual credential owner filesystem. This also covers home-local
        // receipts and interrupted cleanup after an earlier receipt was unlinked.
        (io.release_write)(
            &receipt,
            &encoded(&Marker {
                schema_version: 1,
                transaction_id: journal.transaction_id.clone(),
                owner: journal.owner.clone(),
            })?,
        )?;
        if self.owned_marker(journal, entry)? || !self.owned_release_receipt(journal, &receipt)? {
            return Err(recovery_required());
        }
        Ok(())
    }
    fn verified_file(
        &self,
        journal: &Journal,
        name: &str,
        expected: Option<&str>,
        optional: bool,
    ) -> Result<Option<Vec<u8>>> {
        let bytes = file_bytes(&self.transaction_dir(journal).join(name))?;
        match (&bytes, expected) {
            (Some(bytes), Some(expected)) if digest(bytes) == expected => Ok(Some(bytes.clone())),
            (None, _) if optional => Ok(None),
            (None, None) => Ok(None),
            _ => Err(recovery_required()),
        }
    }
    fn rollback(
        &self,
        journal: &Journal,
        replace: &impl Fn(&Path, &[u8]) -> Result<()>,
    ) -> Result<()> {
        let original = self.verified_file(
            journal,
            "original.toml",
            journal.original_hash.as_deref(),
            false,
        )?;
        self.verified_file(
            journal,
            "candidate.toml",
            Some(&journal.candidate_hash),
            false,
        )?;
        let current = file_bytes(self.paths().config_file())?;
        let hash = current.as_deref().map(digest);
        if hash != journal.original_hash && hash.as_deref() != Some(&journal.candidate_hash) {
            return Err(recovery_required());
        }
        let mut old = Vec::new();
        for entry in &journal.entries {
            if !self.owned_marker(journal, entry)? {
                return Err(recovery_required());
            }
            let previous = self.snapshot_value(journal, entry, "old")?;
            let candidate = self.snapshot_value(journal, entry, "new")?;
            let current = self.credentials.load_strict(&entry.account_id)?;
            if current != previous && current != candidate {
                return Err(recovery_required());
            }
            old.push((entry.account_id.clone(), previous));
        }
        for (id, value) in &old {
            self.write_account(id, value.as_deref(), true)?;
        }
        match original {
            Some(bytes) => replace(self.paths().config_file(), &bytes)?,
            None if current.is_some() => {
                pl_tool::workspace::move_owned_path(
                    self.paths().config_file(),
                    &self.transaction_dir(journal).join("retired-config.toml"),
                )?;
            }
            None => {}
        }
        if file_bytes(self.paths().config_file())?
            .as_deref()
            .map(digest)
            != journal.original_hash
        {
            return Err(recovery_required());
        }
        for (id, value) in old {
            if self.credentials.load_strict(&id)? != value {
                return Err(recovery_required());
            }
        }
        let mut terminal = journal.clone();
        terminal.phase = Phase::RolledBack;
        self.write_journal(&terminal)?;
        self.cleanup(&terminal)
    }
    fn cleanup(&self, journal: &Journal) -> Result<()> {
        self.cleanup_with_io(journal, &CleanupIo::platform())
    }
    fn cleanup_with_io(&self, journal: &Journal, io: &CleanupIo<'_>) -> Result<()> {
        // Validate all of our own material before removing anything. Terminal cleanup never
        // inspects/replays canonical values: legitimate later refreshes/R2 remain untouched.
        let directory = self.transaction_dir(journal);
        let mut allowed = BTreeSet::from([
            "journal.json".to_owned(),
            "original.toml".into(),
            "candidate.toml".into(),
            "retired-config.toml".into(),
        ]);
        for entry in &journal.entries {
            allowed.insert(format!("released-{}.json", entry.digest));
        }
        for entry in fs::read_dir(&directory)? {
            let entry = entry?;
            if !entry.file_type()?.is_file()
                || !allowed.contains(&entry.file_name().to_string_lossy().into_owned())
            {
                return Err(recovery_required());
            }
        }
        self.verified_file(
            journal,
            "original.toml",
            journal.original_hash.as_deref(),
            true,
        )?;
        self.verified_file(
            journal,
            "candidate.toml",
            Some(&journal.candidate_hash),
            true,
        )?;
        self.verified_file(
            journal,
            "retired-config.toml",
            Some(&journal.candidate_hash),
            true,
        )?;
        for entry in &journal.entries {
            for side in ["old", "new"] {
                self.read_snapshot(journal, entry, side, true)?;
            }
            // Also finish already-owned home-local receipts from an interrupted R2 cleanup.
            for released in [
                directory.join(format!("released-{}.json", entry.digest)),
                self.released_marker_path(journal, entry)?,
            ] {
                self.owned_release_receipt(journal, &released)?;
            }
        }
        if matches!(journal.phase, Phase::Committed | Phase::RolledBack) {
            // A terminal rename can have become visible before directory sync failed.
            // Re-observation is not a durability acknowledgement. Confirm the unchanged
            // terminal record with the platform's durable atomic writer BEFORE any release.
            let path = directory.join("journal.json");
            let visible = file_bytes(&path)?.ok_or_else(recovery_required)?;
            let visible: Journal =
                serde_json::from_slice(&visible).map_err(|_| recovery_required())?;
            if encoded(&visible)? != encoded(journal)? {
                return Err(recovery_required());
            }
            self.write_journal_with(journal, io.journal_write)?;
        }
        for entry in &journal.entries {
            if self.owned_marker(journal, entry)? {
                (io.marker_move)(
                    &self.pending_path(&entry.account_id)?,
                    &self.released_marker_path(journal, entry)?,
                )?;
            }
        }
        // This is a transaction-wide barrier, not a per-entry deletion condition. No secret
        // snapshot or journal is destroyed until EVERY released marker directory is durable,
        // including reentry after rename succeeded but its parent-directory sync failed.
        for entry in &journal.entries {
            self.confirm_marker_release(journal, entry, io)?;
        }
        for entry in &journal.entries {
            for side in ["old", "new"] {
                self.credentials
                    .delete_transaction(&alias(journal, entry, side))?;
            }
            let released = self.released_marker_path(journal, entry)?;
            if self.owned_release_receipt(journal, &released)? {
                fs::remove_file(released)?;
            }
        }
        for entry in fs::read_dir(&directory)? {
            let entry = entry?;
            if entry.file_name() != "journal.json" {
                fs::remove_file(entry.path())?;
            }
        }
        fs::remove_file(directory.join("journal.json"))?;
        fs::remove_dir(directory)?;
        Ok(())
    }
}

pub(super) fn ensure_available(path: &Path) -> Result<()> {
    if file_bytes(path)?.is_some() {
        return Err(recovery_required());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
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
                codex: None,
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

    #[cfg(windows)]
    #[test]
    fn windows_codex_account_commit_reopens_large_protected_credentials() -> crate::Result<()> {
        let home = tempfile::tempdir()?;
        let store = ConfigStore::for_studio_home(home.path());
        let id = format!("codex-commit-test-{}", uuid::Uuid::new_v4());
        let previous_id = format!("other-home-test-{}", uuid::Uuid::new_v4());
        let baseline_id = AccountId::new(format!("baseline-test-{}", uuid::Uuid::new_v4()))?;
        struct Cleanup<'a>(&'a ConfigStore, [&'a str; 3]);
        impl Drop for Cleanup<'_> {
            fn drop(&mut self) {
                let _ = self.0.recover_credentials();
                for id in self.1 {
                    let _ = self.0.credentials.delete_strict(id);
                }
            }
        }
        let _cleanup = Cleanup(&store, [&id, &previous_id, baseline_id.as_str()]);
        let mut baseline = StudioConfig::default_config()?;
        // This test owns only its UUID namespace, never the user's default account aliases.
        let mut default = baseline.models.accounts.pop_first().unwrap().1;
        default.bearer_token_env = None;
        baseline
            .models
            .accounts
            .insert(baseline_id.clone(), default);
        for route in baseline.mode_model_routes.values_mut() {
            route.account_id = baseline_id.clone();
        }
        store.save(&baseline)?;
        let mut record = record("windows-codex-registration");
        record.account.client_id = pl_model::protocol::chatgpt::CODEX_CLIENT_ID.into();
        record.account.codex = Some(pl_protocol::studio::CodexAccountInfo {
            account_id: "verified-workspace".into(),
            plan_type: Some("plus".into()),
        });
        record.access_token = "synthetic-access-".repeat(1024);
        record.id_token = "synthetic-id-".repeat(1024);
        record.scopes = ["openid", "profile", "email", "offline_access"]
            .into_iter()
            .map(str::to_owned)
            .collect();
        let mut account = pl_model::config::builtin_account_catalog()?
            .templates
            .into_iter()
            .find(|entry| entry.id.as_str() == "openai")
            .unwrap()
            .account;
        account.authentication = AccountAuthenticationMethod::ChatGpt;
        account.base_url = pl_model::protocol::chatgpt::CODEX_RESOURCE.into();
        account.bearer_token_env = None;
        account.chatgpt_account = Some(record.account.clone());
        account.chatgpt_credentials = Some(record.clone());
        let mut candidate = baseline.clone();
        let previous_account_id = AccountId::new(&previous_id)?;
        store
            .credentials
            .save_strict(&previous_id, "other-home-api-secret")?;
        account.chatgpt_session = Some(store.chatgpt_session(&previous_id, &record)?);
        candidate
            .models
            .accounts
            .insert(previous_account_id.clone(), account.clone());
        let replacement = |id: &str| {
            CredentialIntents::for_account(
                id,
                &AccountAuthenticationIntent::ChatGpt {
                    login_id: "windows-login".into(),
                    editor_id: "windows-editor".into(),
                },
            )
        };
        let conflict = store
            .commit_config(&baseline, &candidate, &replacement(&previous_id))
            .unwrap_err();
        assert!(conflict.to_string().contains("credential binding changed"));
        assert_eq!(
            store.credentials.load_strict(&previous_id)?.as_deref(),
            Some("other-home-api-secret")
        );
        assert_eq!(store.load()?.models.accounts, baseline.models.accounts);
        candidate.models.accounts.remove(&previous_account_id);
        account.chatgpt_session = Some(store.chatgpt_session(&id, &record)?);
        let account_id = AccountId::new(&id)?;
        candidate
            .models
            .accounts
            .insert(account_id.clone(), account);
        store.commit_config(&baseline, &candidate, &replacement(&id))?;
        let reopened = ConfigStore::for_studio_home(home.path()).load()?;
        let saved = &reopened.models.accounts[&account_id];
        assert_eq!(saved.chatgpt_account.as_ref(), Some(&record.account));
        assert_eq!(saved.chatgpt_credentials.as_ref(), Some(&record));
        let persisted = fs::read_to_string(store.paths().config_file())?;
        assert!(!persisted.contains("synthetic-access-"));
        assert!(!persisted.contains("synthetic-id-"));
        assert!(fs::read_dir(store.transaction_root())?.next().is_none());
        for owned in [&id, &previous_id, baseline_id.as_str()] {
            store.credentials.delete_strict(owned)?;
            assert!(store.credentials.load_strict(owned)?.is_none());
        }
        Ok(())
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
            let mut value: toml::Value =
                toml::from_str(std::str::from_utf8(bytes).unwrap()).unwrap();
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
        let startup =
            crate::studio::startup::StudioStartupError::input("prepare_configuration", error);
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
}
