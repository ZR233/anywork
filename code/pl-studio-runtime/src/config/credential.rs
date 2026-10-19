use keyring::{Entry, Error as KeyringError};
use std::collections::BTreeMap;
use std::sync::Mutex;

use crate::{PureError, Result};

const CREDENTIAL_SERVICE: &str = "anywork";
/// 当前 account 凭据命名空间；`config.toml` 只保存 env 引用，不保存该值。
fn account_key(account_id: &str) -> String {
    format!("account:{account_id}")
}

/// 迁移前的 provider 凭据命名空间；只在迁移边界读取，正常运行不回落。
fn legacy_provider_key(account_id: &str) -> String {
    format!("provider:{account_id}")
}

/// 一次 `provider:<id>` → `account:<id>` 复制的结果。
///
/// `Absent` 表示旧项确实不存在（无系统凭据）；服务不可访问是错误而不是该状态。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum LegacyCredentialCopy {
    Copied,
    AlreadyIdentical,
    Absent,
}

pub(super) trait CredentialStore: Send + Sync {
    fn load(&self, account_id: &str) -> Result<Option<String>>;
    fn save(&self, account_id: &str, secret: &str) -> Result<()>;
    fn delete(&self, account_id: &str) -> Result<()>;
    fn load_ssh(&self, alias: &str) -> Result<Option<String>>;
    fn save_ssh(&self, alias: &str, secret: &str) -> Result<()>;
    fn delete_ssh(&self, alias: &str) -> Result<()>;
    /// 把旧 `provider:<id>` 关联复制为当前 `account:<id>` 关联。
    ///
    /// 复制必须由持久服务确认写入并回读；不可访问不能解释为"原项不存在"，也不能用
    /// 进程内 lease 的读回冒充耐久成功。旧项保持不变。
    fn copy_legacy_account(&self, account_id: &str) -> Result<LegacyCredentialCopy>;
    /// 迁移专用：把历史内联密钥导入当前 `account:<id>` 关联并回读确认。
    ///
    /// 与 [`Self::copy_legacy_account`] 相同的持久义务：只接受持久服务的成功写入与回读，
    /// 目标已有不同密钥时明确冲突，不使用进程内 lease 制造假成功。
    fn import_inline_secret(&self, account_id: &str, secret: &str) -> Result<LegacyCredentialCopy>;
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
    fn load(&self, account_id: &str) -> Result<Option<String>> {
        self.load_account("account", account_id, &account_key(account_id))
    }

    fn save(&self, account_id: &str, secret: &str) -> Result<()> {
        self.save_account("account", account_id, &account_key(account_id), secret)
    }

    fn delete(&self, account_id: &str) -> Result<()> {
        self.delete_account("account", account_id, &account_key(account_id))
    }

    fn copy_legacy_account(&self, account_id: &str) -> Result<LegacyCredentialCopy> {
        // 迁移是耐久操作：只接受持久服务的成功写入与回读，绝不使用进程内 fallback lease。
        let legacy = entry_for_account("provider", account_id, &legacy_provider_key(account_id))?;
        let source = match legacy.get_password() {
            Ok(secret) => secret,
            Err(KeyringError::NoEntry) => return Ok(LegacyCredentialCopy::Absent),
            Err(error) => {
                return Err(credential_error(
                    "read legacy",
                    "provider",
                    account_id,
                    error,
                ));
            }
        };
        let target = entry_for_account("account", account_id, &account_key(account_id))?;
        match target.get_password() {
            Ok(existing) if existing == source => {
                return Ok(LegacyCredentialCopy::AlreadyIdentical);
            }
            Ok(_) => {
                return Err(PureError::ConfigError(format!(
                    "system credential conflicts with the migration target for account {account_id}"
                )));
            }
            Err(KeyringError::NoEntry) => {}
            Err(error) => return Err(credential_error("read", "account", account_id, error)),
        }
        target
            .set_password(&source)
            .map_err(|error| credential_error("write", "account", account_id, error))?;
        match target.get_password() {
            Ok(actual) if actual == source => Ok(LegacyCredentialCopy::Copied),
            Ok(_) => Err(PureError::ConfigError(format!(
                "system credential verification failed for migrated account {account_id}"
            ))),
            Err(error) => Err(credential_error("verify", "account", account_id, error)),
        }
    }

    fn import_inline_secret(&self, account_id: &str, secret: &str) -> Result<LegacyCredentialCopy> {
        // 与旧命名空间复制同一持久义务：只用 keyring 的持久读写，绝不回退到进程内 lease。
        let target = entry_for_account("account", account_id, &account_key(account_id))?;
        match target.get_password() {
            Ok(existing) if existing == secret => {
                return Ok(LegacyCredentialCopy::AlreadyIdentical);
            }
            Ok(_) => {
                return Err(PureError::ConfigError(format!(
                    "system credential conflicts with the migrated inline credential of account {account_id}"
                )));
            }
            Err(KeyringError::NoEntry) => {}
            Err(error) => return Err(credential_error("read", "account", account_id, error)),
        }
        target
            .set_password(secret)
            .map_err(|error| credential_error("write", "account", account_id, error))?;
        match target.get_password() {
            Ok(actual) if actual == secret => Ok(LegacyCredentialCopy::Copied),
            Ok(_) => Err(PureError::ConfigError(format!(
                "system credential verification failed for migrated account {account_id}"
            ))),
            Err(error) => Err(credential_error("verify", "account", account_id, error)),
        }
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

#[cfg(test)]
impl MemoryCredentialStore {
    /// 只在测试中预置旧 `provider:<id>` 条目，用于验证迁移边界。
    pub(super) fn seed_legacy_provider(&self, account_id: &str, secret: &str) {
        self.values
            .lock()
            .unwrap()
            .insert(legacy_provider_key(account_id), secret.to_string());
    }

    /// 只在测试中读取旧命名空间，验证"旧项保持不变"。
    pub(super) fn legacy_provider_secret(&self, account_id: &str) -> Option<String> {
        self.values
            .lock()
            .unwrap()
            .get(&legacy_provider_key(account_id))
            .cloned()
    }
}

impl CredentialStore for MemoryCredentialStore {
    fn load(&self, account_id: &str) -> Result<Option<String>> {
        Ok(self
            .values
            .lock()
            .unwrap()
            .get(&account_key(account_id))
            .cloned())
    }

    fn save(&self, account_id: &str, secret: &str) -> Result<()> {
        self.values
            .lock()
            .unwrap()
            .insert(account_key(account_id), secret.to_string());
        Ok(())
    }

    fn delete(&self, account_id: &str) -> Result<()> {
        self.values.lock().unwrap().remove(&account_key(account_id));
        Ok(())
    }

    fn import_inline_secret(&self, account_id: &str, secret: &str) -> Result<LegacyCredentialCopy> {
        let mut values = self.values.lock().unwrap();
        match values.get(&account_key(account_id)) {
            Some(existing) if existing == secret => {
                return Ok(LegacyCredentialCopy::AlreadyIdentical);
            }
            Some(_) => {
                return Err(PureError::ConfigError(format!(
                    "system credential conflicts with the migrated inline credential of account {account_id}"
                )));
            }
            None => {}
        }
        values.insert(account_key(account_id), secret.to_string());
        Ok(LegacyCredentialCopy::Copied)
    }

    fn copy_legacy_account(&self, account_id: &str) -> Result<LegacyCredentialCopy> {
        let mut values = self.values.lock().unwrap();
        let Some(source) = values.get(&legacy_provider_key(account_id)).cloned() else {
            return Ok(LegacyCredentialCopy::Absent);
        };
        match values.get(&account_key(account_id)) {
            Some(existing) if existing == &source => {
                return Ok(LegacyCredentialCopy::AlreadyIdentical);
            }
            Some(_) => {
                return Err(PureError::ConfigError(format!(
                    "system credential conflicts with the migration target for account {account_id}"
                )));
            }
            None => {}
        }
        values.insert(account_key(account_id), source);
        Ok(LegacyCredentialCopy::Copied)
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
