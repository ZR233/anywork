//! Durable, non-secret credential journal and recognized configuration replacement.
use super::io_error;
use crate::bots::config::{
    BotConfigFile, decode_config_snapshot_at, encode_config_snapshot, load_config, save_config,
    save_recognized_config,
};
use crate::bots::protocol::error::{FeishuError, FeishuErrorKind};
use serde::{Deserialize, Serialize};
use std::path::Path;

pub(super) const JOURNAL_FILE: &str = "credential-journal.json";
pub(super) const JOURNAL_SCHEMA: u32 = 3;

pub fn has_credential_journal(dir: &Path) -> bool {
    dir.join(JOURNAL_FILE).is_file()
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct CredentialJournal {
    pub(super) schema_version: u32,
    pub(super) operation_id: String,
    pub(super) bot_id: String,
    pub(super) phase: CredentialJournalPhase,
    pub(super) previous: Option<BotConfigFile>,
    pub(super) target: BotConfigFile,
    pub(super) candidate_version: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(super) struct StoredCredentialJournal {
    pub(super) schema_version: u32,
    pub(super) operation_id: String,
    pub(super) bot_id: String,
    pub(super) phase: CredentialJournalPhase,
    pub(super) previous: Option<serde_json::Value>,
    pub(super) target: serde_json::Value,
    pub(super) candidate_version: Option<String>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(super) enum CredentialJournalPhase {
    Intent,
    Prepared,
    CommitUncertain,
    CleanupPending,
}

pub(super) trait JournalFs {
    fn replace_config(&self, dir: &Path, config: &BotConfigFile) -> Result<(), FeishuError>;
    fn confirm_config(
        &self,
        dir: &Path,
        expected: Option<&BotConfigFile>,
    ) -> Result<(), FeishuError>;
    fn store_journal(&self, dir: &Path, journal: &CredentialJournal) -> Result<(), FeishuError>;
}

pub(super) struct LocalJournalFs;

impl JournalFs for LocalJournalFs {
    fn replace_config(&self, dir: &Path, config: &BotConfigFile) -> Result<(), FeishuError> {
        save_config(&dir.join("config.toml"), config)
    }

    fn confirm_config(
        &self,
        dir: &Path,
        expected: Option<&BotConfigFile>,
    ) -> Result<(), FeishuError> {
        confirm_recognized_config(dir, expected)
    }

    fn store_journal(&self, dir: &Path, journal: &CredentialJournal) -> Result<(), FeishuError> {
        write_journal(dir, journal)
    }
}

fn confirm_recognized_config(
    dir: &Path,
    expected: Option<&BotConfigFile>,
) -> Result<(), FeishuError> {
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

pub(super) fn write_journal(dir: &Path, journal: &CredentialJournal) -> Result<(), FeishuError> {
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

pub(super) fn read_journal(dir: &Path) -> Result<Option<CredentialJournal>, FeishuError> {
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

pub(super) fn remove_journal(dir: &Path) -> Result<(), FeishuError> {
    remove_path(&dir.join(JOURNAL_FILE))
}

pub(super) fn remove_path(path: &Path) -> Result<(), FeishuError> {
    match std::fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(io_error(error)),
    }
}
