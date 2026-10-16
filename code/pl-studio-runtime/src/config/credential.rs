use keyring::{Entry, Error as KeyringError};
use std::collections::BTreeMap;
use std::sync::Mutex;

use crate::{PureError, Result};

const CREDENTIAL_SERVICE: &str = "anywork";

pub(super) trait CredentialStore: Send + Sync {
    fn load(&self, provider_id: &str) -> Result<Option<String>>;
    fn save(&self, provider_id: &str, secret: &str) -> Result<()>;
    fn delete(&self, provider_id: &str) -> Result<()>;
    fn load_ssh(&self, alias: &str) -> Result<Option<String>>;
    fn save_ssh(&self, alias: &str, secret: &str) -> Result<()>;
    fn delete_ssh(&self, alias: &str) -> Result<()>;
}

#[derive(Debug, Default)]
pub(super) struct SystemCredentialStore {
    /// Headless Linux / Xvfb environments without a D-Bus Secret Service daemon
    /// keep secrets in the current-process secret lease (`design/04` §4.4).
    fallback_lease: Mutex<BTreeMap<String, String>>,
}

impl SystemCredentialStore {
    fn load_account(&self, scope: &str, id: &str, account: &str) -> Result<Option<String>> {
        match entry_for_account(scope, id, account)?.get_password() {
            Ok(secret) => Ok(Some(secret)),
            Err(KeyringError::NoEntry) => Ok(self
                .fallback_lease
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner())
                .get(account)
                .cloned()),
            Err(KeyringError::PlatformFailure(_) | KeyringError::NoStorageAccess(_)) => Ok(self
                .fallback_lease
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner())
                .get(account)
                .cloned()),
            Err(error) => Err(credential_error("read", scope, id, error)),
        }
    }

    fn save_account(&self, scope: &str, id: &str, account: &str, secret: &str) -> Result<()> {
        match entry_for_account(scope, id, account)?.set_password(secret) {
            Ok(()) => {
                self.fallback_lease
                    .lock()
                    .unwrap_or_else(|poisoned| poisoned.into_inner())
                    .insert(account.to_string(), secret.to_string());
                Ok(())
            }
            Err(KeyringError::PlatformFailure(_) | KeyringError::NoStorageAccess(_)) => {
                self.fallback_lease
                    .lock()
                    .unwrap_or_else(|poisoned| poisoned.into_inner())
                    .insert(account.to_string(), secret.to_string());
                Ok(())
            }
            Err(error) => Err(credential_error("write", scope, id, error)),
        }
    }

    fn delete_account(&self, scope: &str, id: &str, account: &str) -> Result<()> {
        self.fallback_lease
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .remove(account);
        match entry_for_account(scope, id, account)?.delete_credential() {
            Ok(())
            | Err(
                KeyringError::NoEntry
                | KeyringError::PlatformFailure(_)
                | KeyringError::NoStorageAccess(_),
            ) => Ok(()),
            Err(error) => Err(credential_error("delete", scope, id, error)),
        }
    }
}

impl CredentialStore for SystemCredentialStore {
    fn load(&self, provider_id: &str) -> Result<Option<String>> {
        self.load_account("provider", provider_id, &format!("provider:{provider_id}"))
    }

    fn save(&self, provider_id: &str, secret: &str) -> Result<()> {
        self.save_account(
            "provider",
            provider_id,
            &format!("provider:{provider_id}"),
            secret,
        )
    }

    fn delete(&self, provider_id: &str) -> Result<()> {
        self.delete_account("provider", provider_id, &format!("provider:{provider_id}"))
    }

    fn load_ssh(&self, alias: &str) -> Result<Option<String>> {
        self.load_account("SSH server", alias, &format!("ssh:{alias}"))
    }

    fn save_ssh(&self, alias: &str, secret: &str) -> Result<()> {
        self.save_account("SSH server", alias, &format!("ssh:{alias}"), secret)
    }

    fn delete_ssh(&self, alias: &str) -> Result<()> {
        self.delete_account("SSH server", alias, &format!("ssh:{alias}"))
    }
}

#[derive(Debug, Default)]
pub(super) struct MemoryCredentialStore {
    values: Mutex<BTreeMap<String, String>>,
}

impl CredentialStore for MemoryCredentialStore {
    fn load(&self, provider_id: &str) -> Result<Option<String>> {
        Ok(self.values.lock().unwrap().get(provider_id).cloned())
    }

    fn save(&self, provider_id: &str, secret: &str) -> Result<()> {
        self.values
            .lock()
            .unwrap()
            .insert(provider_id.to_string(), secret.to_string());
        Ok(())
    }

    fn delete(&self, provider_id: &str) -> Result<()> {
        self.values.lock().unwrap().remove(provider_id);
        Ok(())
    }

    fn load_ssh(&self, alias: &str) -> Result<Option<String>> {
        Ok(self
            .values
            .lock()
            .unwrap()
            .get(&format!("ssh:{alias}"))
            .cloned())
    }

    fn save_ssh(&self, alias: &str, secret: &str) -> Result<()> {
        self.values
            .lock()
            .unwrap()
            .insert(format!("ssh:{alias}"), secret.to_string());
        Ok(())
    }

    fn delete_ssh(&self, alias: &str) -> Result<()> {
        self.values.lock().unwrap().remove(&format!("ssh:{alias}"));
        Ok(())
    }
}

fn entry_for_account(scope: &str, id: &str, account: &str) -> Result<Entry> {
    Entry::new(CREDENTIAL_SERVICE, account)
        .map_err(|error| credential_error("open", scope, id, error))
}

fn credential_error(action: &str, scope: &str, id: &str, error: KeyringError) -> PureError {
    PureError::Io(std::io::Error::other(format!(
        "failed to {action} system credential for {scope} {id}: {error}"
    )))
}
