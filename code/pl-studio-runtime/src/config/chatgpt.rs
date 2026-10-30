//! Host-provided protected storage for the model-owned ChatGPT session.
use super::ConfigStore;
use super::credential::CredentialStore;
use crate::{PureError, Result};
use pl_model::protocol::chatgpt::{
    ChatGptAuthError, ChatGptCredentialRecord, ChatGptCredentialStorage, ChatGptSession,
};
use std::path::PathBuf;
use std::sync::Arc;

struct AccountStorage {
    account_id: String,
    credentials: Arc<dyn CredentialStore>,
    pending_path: PathBuf,
}

impl ChatGptCredentialStorage for AccountStorage {
    fn load(&self) -> std::result::Result<ChatGptCredentialRecord, ChatGptAuthError> {
        super::credential_commit::ensure_available(&self.pending_path)
            .map_err(|_| ChatGptAuthError::RecoveryRequired)?;
        let payload = self
            .credentials
            .load_strict(&self.account_id)
            .map_err(|_| ChatGptAuthError::Storage)?
            .ok_or(ChatGptAuthError::Revoked)?;
        serde_json::from_str(&payload).map_err(|_| ChatGptAuthError::Revoked)
    }

    fn persist(
        &self,
        expected_registration: &str,
        record: &ChatGptCredentialRecord,
    ) -> std::result::Result<(), ChatGptAuthError> {
        let current = self.load()?;
        if current.registration_id != expected_registration
            || current.account != record.account
            || record.registration_id != expected_registration
        {
            return Err(ChatGptAuthError::Revoked);
        }
        let payload = serde_json::to_string(record).map_err(|_| ChatGptAuthError::Storage)?;
        self.credentials
            .save_strict(&self.account_id, &payload)
            .map_err(|_| ChatGptAuthError::Storage)?;
        if self.load()? != *record {
            return Err(ChatGptAuthError::Storage);
        }
        Ok(())
    }
}

impl ConfigStore {
    pub(crate) fn chatgpt_lock_path(&self, account_id: &str) -> Result<PathBuf> {
        let directory = self
            .credentials
            .account_lock_directory(self.paths().config_dir())?;
        // Account IDs are not paths; hash to keep even non-UUID historical IDs confined.
        use sha2::{Digest, Sha256};
        Ok(directory.join(format!(
            "{}.lock",
            hex::encode(Sha256::digest(account_id.as_bytes()))
        )))
    }

    pub(crate) fn chatgpt_session(
        &self,
        account_id: &str,
        record: &ChatGptCredentialRecord,
    ) -> Result<ChatGptSession> {
        let path = self.chatgpt_lock_path(account_id)?;
        std::fs::create_dir_all(path.parent().expect("credential lock has a directory"))?;
        ChatGptSession::new(
            record,
            Arc::new(AccountStorage {
                account_id: account_id.into(),
                credentials: self.credentials.clone(),
                pending_path: path.with_extension("pending.json"),
            }),
            path,
        )
        .map_err(|error| PureError::ConfigError(error.to_string()))
    }

    pub(crate) fn chatgpt_host_id(&self) -> Result<String> {
        use fs4::FileExt;
        let directory = self.paths().config_dir().join("v2");
        std::fs::create_dir_all(&directory)?;
        let path = directory.join("chatgpt-host.toml");
        let lock = std::fs::OpenOptions::new()
            .create(true)
            .truncate(false)
            .read(true)
            .write(true)
            .open(directory.join("chatgpt-host.lock"))?;
        FileExt::try_lock(&lock)
            .map_err(|_| PureError::ConfigError("ChatGPT host identity is busy".into()))?;
        #[derive(serde::Serialize, serde::Deserialize)]
        #[serde(deny_unknown_fields)]
        struct Host {
            schema_version: u32,
            ext_agent_host_id: String,
        }
        if path.exists() {
            let host: Host = toml::from_str(&std::fs::read_to_string(&path)?)
                .map_err(|_| PureError::ConfigError("ChatGPT host identity is invalid".into()))?;
            if host.schema_version != 1
                || host
                    .ext_agent_host_id
                    .strip_prefix("urn:uuid:")
                    .and_then(|id| uuid::Uuid::parse_str(id).ok())
                    .is_none()
            {
                return Err(PureError::ConfigError(
                    "ChatGPT host identity is invalid".into(),
                ));
            }
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                if std::fs::metadata(&path)?.permissions().mode() & 0o077 != 0 {
                    return Err(PureError::ConfigError(
                        "ChatGPT host identity must be owner-only".into(),
                    ));
                }
            }
            return Ok(host.ext_agent_host_id);
        }
        let host = Host {
            schema_version: 1,
            ext_agent_host_id: format!("urn:uuid:{}", uuid::Uuid::new_v4()),
        };
        let payload = toml::to_string(&host)
            .map_err(|_| PureError::ConfigError("ChatGPT host identity encoding failed".into()))?;
        // Existing platform adapter uses private tempfile permissions, atomic replacement
        // and platform-specific directory synchronization (no Windows directory File::open).
        pl_tool::workspace::write_file_atomically(&path, payload.as_bytes())?;
        Ok(host.ext_agent_host_id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chatgpt_protected_store_lock_identity_is_shared_across_configuration_homes() {
        use super::super::ConfigPaths;
        use super::super::credential::{MemoryCredentialStore, SystemCredentialStore};
        let home = tempfile::tempdir().unwrap();
        let first_paths = ConfigPaths::from_config_dir(home.path().join("first"));
        let second_paths = ConfigPaths::from_config_dir(home.path().join("second"));
        let system = Arc::new(SystemCredentialStore::default());
        let first = ConfigStore::with_credential_store(first_paths.clone(), system.clone());
        let second = ConfigStore::with_credential_store(second_paths.clone(), system);
        let first_lock = first.chatgpt_lock_path("same-protected-account").unwrap();
        let second_lock = second.chatgpt_lock_path("same-protected-account").unwrap();
        assert_eq!(first_lock, second_lock);
        assert!(
            first_lock.starts_with(
                dirs::data_local_dir()
                    .unwrap()
                    .join("anywork/credential-locks")
            )
        );
        assert!(!first_lock.starts_with(home.path()));
        assert_ne!(
            first_lock,
            second
                .chatgpt_lock_path("another-protected-account")
                .unwrap()
        );
        // No system keyring IO or writes to the real user data root. The isolated protected
        // store follows the same owner-level namespace and proves actual file-lock exclusion.
        let memory = Arc::new(MemoryCredentialStore::default());
        let first = ConfigStore::with_credential_store(first_paths, memory.clone());
        let second = ConfigStore::with_credential_store(second_paths, memory);
        let first_path = first.chatgpt_lock_path("same-protected-account").unwrap();
        let second_path = second.chatgpt_lock_path("same-protected-account").unwrap();
        assert_eq!(first_path, second_path);
        std::fs::create_dir_all(first_path.parent().unwrap()).unwrap();
        let open = |path| {
            std::fs::OpenOptions::new()
                .create(true)
                .truncate(false)
                .read(true)
                .write(true)
                .open(path)
                .unwrap()
        };
        let first = open(&first_path);
        let second = open(&second_path);
        fs4::FileExt::try_lock(&first).unwrap();
        assert!(matches!(
            fs4::FileExt::try_lock(&second),
            Err(fs4::TryLockError::WouldBlock)
        ));
        drop(first);
        fs4::FileExt::try_lock(&second).unwrap();
    }

    #[test]
    fn chatgpt_host_identity_is_stable_protected_and_invalid_data_is_not_replaced() {
        let home = tempfile::tempdir().unwrap();
        let store = ConfigStore::new(super::super::ConfigPaths::from_config_dir(home.path()));
        let first = store.chatgpt_host_id().unwrap();
        assert!(uuid::Uuid::parse_str(first.strip_prefix("urn:uuid:").unwrap()).is_ok());
        let restarted = ConfigStore::new(super::super::ConfigPaths::from_config_dir(home.path()));
        assert_eq!(restarted.chatgpt_host_id().unwrap(), first);
        let file = home.path().join("v2/chatgpt-host.toml");
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(
                std::fs::metadata(&file).unwrap().permissions().mode() & 0o777,
                0o600
            );
        }
        let malformed = "schema_version = 1\next_agent_host_id = 'urn:uuid:not-a-uuid'\n";
        std::fs::write(&file, malformed).unwrap();
        assert!(restarted.chatgpt_host_id().is_err());
        assert_eq!(std::fs::read_to_string(&file).unwrap(), malformed);
    }
}
