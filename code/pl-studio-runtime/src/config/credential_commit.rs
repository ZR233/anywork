//! Credential participation in the configuration coordinator: frozen bindings, protected
//! snapshots and versioned recovery. No token-bearing payload is written to the filesystem.
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
        self.paths().config_dir().join("v2/credential-transactions")
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
mod tests;
