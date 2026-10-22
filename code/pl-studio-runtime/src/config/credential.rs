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
    /// 读取 `bot:<id>` 受保护载荷。系统不可访问且无进程 lease 时为 `Unavailable`。
    fn read_bot_system(
        &self,
        bot_id: &str,
    ) -> std::result::Result<BotProtectedRead, BotCredentialIoError>;
    /// 只读进程 lease，不访问系统凭据。
    fn read_bot_lease(
        &self,
        bot_id: &str,
    ) -> std::result::Result<Option<String>, BotCredentialIoError>;
    /// 只写入系统凭据。`Stored` 必须有系统写入与回读证据；不可访问返回 `Unavailable`，
    /// 不把系统载荷写入独立 lease。
    fn persist_bot_protected(
        &self,
        bot_id: &str,
        payload: &str,
    ) -> std::result::Result<BotProtectedPersist, BotCredentialIoError>;
    /// 只写入当前进程 lease，不宣称系统已保存。
    fn lease_bot_protected(
        &self,
        bot_id: &str,
        payload: &str,
    ) -> std::result::Result<(), BotCredentialIoError>;
    /// 回收系统材料。除明确 NoEntry 外保留错误，不吞 Invalid。
    fn recycle_bot_system(&self, bot_id: &str) -> std::result::Result<(), BotCredentialIoError>;
    /// 回收进程 lease。
    fn recycle_bot_lease(&self, bot_id: &str) -> std::result::Result<(), BotCredentialIoError>;
}

fn bot_account(bot_id: &str) -> String {
    format!("bot:{bot_id}")
}

/// 机器人凭据底层 I/O 的安全分类。不携带 secret 或 keyring 原值。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum BotCredentialIoKind {
    /// 系统项确实不存在。
    Missing,
    /// 系统凭据服务不可访问。
    Unavailable,
    /// 编码/长度/歧义等不可用输入，不降级为 lease。
    Invalid,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct BotCredentialIoError {
    pub kind: BotCredentialIoKind,
}

impl std::fmt::Display for BotCredentialIoError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self.kind {
            BotCredentialIoKind::Missing => write!(formatter, "bot credential material is missing"),
            BotCredentialIoKind::Unavailable => {
                write!(formatter, "bot credential store is unavailable")
            }
            BotCredentialIoKind::Invalid => {
                write!(formatter, "bot credential material is invalid")
            }
        }
    }
}

impl std::error::Error for BotCredentialIoError {}

impl From<BotCredentialIoError> for PureError {
    fn from(error: BotCredentialIoError) -> Self {
        PureError::ConfigError(error.to_string())
    }
}

#[derive(Clone, PartialEq, Eq)]
pub(crate) enum BotProtectedRead {
    System(String),
    Missing,
}

impl std::fmt::Debug for BotProtectedRead {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::System(_) => formatter
                .debug_tuple("System")
                .field(&"<redacted>")
                .finish(),
            Self::Missing => formatter.write_str("Missing"),
        }
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum BotProtectedPersist {
    Stored,
    SessionOnly,
}

fn classify_bot_keyring(error: KeyringError) -> BotCredentialIoError {
    match error {
        KeyringError::NoEntry => BotCredentialIoError {
            kind: BotCredentialIoKind::Missing,
        },
        KeyringError::PlatformFailure(_) | KeyringError::NoStorageAccess(_) => {
            BotCredentialIoError {
                kind: BotCredentialIoKind::Unavailable,
            }
        }
        _ => BotCredentialIoError {
            kind: BotCredentialIoKind::Invalid,
        },
    }
}

#[derive(Default)]
pub(super) struct SystemCredentialStore {
    /// Headless Linux / Xvfb environments without a D-Bus Secret Service daemon
    /// keep secrets in the current-process secret lease (`design/04` §4.4).
    fallback_lease: Mutex<BTreeMap<String, String>>,
}

impl std::fmt::Debug for SystemCredentialStore {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let lease_entries = self
            .fallback_lease
            .lock()
            .map(|guard| guard.len())
            .unwrap_or(0);
        formatter
            .debug_struct("SystemCredentialStore")
            .field("fallback_lease_entries", &lease_entries)
            .finish()
    }
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
        self.save_account_with_status(scope, id, account, secret)
            .map(|_| ())
    }

    fn save_account_with_status(
        &self,
        scope: &str,
        id: &str,
        account: &str,
        secret: &str,
    ) -> Result<bool> {
        match entry_for_account(scope, id, account)?.set_password(secret) {
            Ok(()) => {
                self.fallback_lease
                    .lock()
                    .unwrap_or_else(|poisoned| poisoned.into_inner())
                    .insert(account.to_string(), secret.to_string());
                Ok(true)
            }
            Err(KeyringError::PlatformFailure(_) | KeyringError::NoStorageAccess(_)) => {
                self.fallback_lease
                    .lock()
                    .unwrap_or_else(|poisoned| poisoned.into_inner())
                    .insert(account.to_string(), secret.to_string());
                Ok(false)
            }
            Err(error) => Err(credential_error("write", scope, id, error)),
        }
    }

    fn lease_account(&self, account: &str, secret: &str) {
        self.fallback_lease
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .insert(account.to_string(), secret.to_string());
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

    fn read_bot_payload(
        &self,
        bot_id: &str,
    ) -> std::result::Result<BotProtectedRead, BotCredentialIoError> {
        let account = bot_account(bot_id);
        let entry = bot_entry(&account)?;
        match entry.get_password() {
            Ok(secret) => Ok(BotProtectedRead::System(secret)),
            Err(KeyringError::NoEntry) => Ok(BotProtectedRead::Missing),
            Err(error) => Err(classify_bot_keyring(error)),
        }
    }

    fn persist_bot_payload(
        &self,
        bot_id: &str,
        payload: &str,
    ) -> std::result::Result<BotProtectedPersist, BotCredentialIoError> {
        let account = bot_account(bot_id);
        let entry = bot_entry(&account)?;
        match entry.set_password(payload) {
            Ok(()) => match entry.get_password() {
                Ok(actual) if actual == payload => Ok(BotProtectedPersist::Stored),
                Ok(_) => Err(BotCredentialIoError {
                    kind: BotCredentialIoKind::Invalid,
                }),
                Err(error) => Err(classify_bot_keyring(error)),
            },
            Err(KeyringError::PlatformFailure(_) | KeyringError::NoStorageAccess(_)) => {
                Err(BotCredentialIoError {
                    kind: BotCredentialIoKind::Unavailable,
                })
            }
            Err(error) => Err(classify_bot_keyring(error)),
        }
    }

    fn recycle_bot_payload(&self, bot_id: &str) -> std::result::Result<(), BotCredentialIoError> {
        let account = bot_account(bot_id);
        let entry = bot_entry(&account)?;
        match entry.delete_credential() {
            Ok(()) | Err(KeyringError::NoEntry) => Ok(()),
            Err(error) => Err(classify_bot_keyring(error)),
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

    fn persist_bot_protected(
        &self,
        bot_id: &str,
        payload: &str,
    ) -> std::result::Result<BotProtectedPersist, BotCredentialIoError> {
        self.persist_bot_payload(bot_id, payload)
    }

    fn lease_bot_protected(
        &self,
        bot_id: &str,
        payload: &str,
    ) -> std::result::Result<(), BotCredentialIoError> {
        self.lease_account(&bot_account(bot_id), payload);
        Ok(())
    }

    fn read_bot_system(
        &self,
        bot_id: &str,
    ) -> std::result::Result<BotProtectedRead, BotCredentialIoError> {
        self.read_bot_payload(bot_id)
    }

    fn read_bot_lease(
        &self,
        bot_id: &str,
    ) -> std::result::Result<Option<String>, BotCredentialIoError> {
        Ok(self
            .fallback_lease
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .get(&bot_account(bot_id))
            .cloned())
    }

    fn recycle_bot_system(&self, bot_id: &str) -> std::result::Result<(), BotCredentialIoError> {
        self.recycle_bot_payload(bot_id)
    }

    fn recycle_bot_lease(&self, bot_id: &str) -> std::result::Result<(), BotCredentialIoError> {
        self.fallback_lease
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .remove(&bot_account(bot_id));
        Ok(())
    }
}

#[derive(Default)]
pub(super) struct MemoryCredentialStore {
    values: Mutex<BTreeMap<String, String>>,
    leases: Mutex<BTreeMap<String, String>>,
}

impl std::fmt::Debug for MemoryCredentialStore {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let system_entries = self.values.lock().map(|guard| guard.len()).unwrap_or(0);
        let lease_entries = self.leases.lock().map(|guard| guard.len()).unwrap_or(0);
        formatter
            .debug_struct("MemoryCredentialStore")
            .field("system_entries", &system_entries)
            .field("lease_entries", &lease_entries)
            .finish()
    }
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

    fn persist_bot_protected(
        &self,
        bot_id: &str,
        payload: &str,
    ) -> std::result::Result<BotProtectedPersist, BotCredentialIoError> {
        #[cfg(test)]
        if memory_faults::persist_unavailable() {
            return Err(BotCredentialIoError {
                kind: BotCredentialIoKind::Unavailable,
            });
        }
        self.values
            .lock()
            .unwrap()
            .insert(bot_account(bot_id), payload.to_string());
        Ok(BotProtectedPersist::Stored)
    }

    fn lease_bot_protected(
        &self,
        bot_id: &str,
        payload: &str,
    ) -> std::result::Result<(), BotCredentialIoError> {
        self.leases
            .lock()
            .unwrap()
            .insert(bot_account(bot_id), payload.to_string());
        Ok(())
    }

    fn read_bot_system(
        &self,
        bot_id: &str,
    ) -> std::result::Result<BotProtectedRead, BotCredentialIoError> {
        #[cfg(test)]
        if memory_faults::system_unavailable() {
            return Err(BotCredentialIoError {
                kind: BotCredentialIoKind::Unavailable,
            });
        }
        Ok(self
            .values
            .lock()
            .unwrap()
            .get(&bot_account(bot_id))
            .cloned()
            .map(BotProtectedRead::System)
            .unwrap_or(BotProtectedRead::Missing))
    }

    fn read_bot_lease(
        &self,
        bot_id: &str,
    ) -> std::result::Result<Option<String>, BotCredentialIoError> {
        Ok(self
            .leases
            .lock()
            .unwrap()
            .get(&bot_account(bot_id))
            .cloned())
    }

    fn recycle_bot_system(&self, bot_id: &str) -> std::result::Result<(), BotCredentialIoError> {
        #[cfg(test)]
        if memory_faults::take_recycle_fail() {
            return Err(BotCredentialIoError {
                kind: BotCredentialIoKind::Unavailable,
            });
        }
        self.values.lock().unwrap().remove(&bot_account(bot_id));
        Ok(())
    }

    fn recycle_bot_lease(&self, bot_id: &str) -> std::result::Result<(), BotCredentialIoError> {
        self.leases.lock().unwrap().remove(&bot_account(bot_id));
        Ok(())
    }
}

fn entry_for_account(scope: &str, id: &str, account: &str) -> Result<Entry> {
    Entry::new(CREDENTIAL_SERVICE, account)
        .map_err(|error| credential_error("open", scope, id, error))
}

fn bot_entry(account: &str) -> std::result::Result<Entry, BotCredentialIoError> {
    Entry::new(CREDENTIAL_SERVICE, account).map_err(classify_bot_keyring)
}

fn credential_error(action: &str, scope: &str, id: &str, error: KeyringError) -> PureError {
    PureError::Io(std::io::Error::other(format!(
        "failed to {action} system credential for {scope} {id}: {error}"
    )))
}

#[cfg(test)]
pub(crate) mod memory_faults {
    use std::cell::Cell;

    thread_local! {
        static SYSTEM_UNAVAILABLE: Cell<bool> = const { Cell::new(false) };
        static PERSIST_UNAVAILABLE: Cell<bool> = const { Cell::new(false) };
        static RECYCLE_FAILS: Cell<u32> = const { Cell::new(0) };
    }

    pub fn reset() {
        set_system_unavailable(false);
        set_persist_unavailable(false);
        set_recycle_fails(0);
    }

    pub fn set_system_unavailable(value: bool) {
        SYSTEM_UNAVAILABLE.with(|cell| cell.set(value));
    }

    pub fn set_persist_unavailable(value: bool) {
        PERSIST_UNAVAILABLE.with(|cell| cell.set(value));
    }

    pub fn set_recycle_fails(count: u32) {
        RECYCLE_FAILS.with(|cell| cell.set(count));
    }

    pub(super) fn system_unavailable() -> bool {
        SYSTEM_UNAVAILABLE.with(Cell::get)
    }

    pub(super) fn persist_unavailable() -> bool {
        PERSIST_UNAVAILABLE.with(Cell::get)
    }

    pub(super) fn take_recycle_fail() -> bool {
        RECYCLE_FAILS.with(|cell| {
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
