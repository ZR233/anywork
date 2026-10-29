//! `settings.toml`: 产品设置键值对象的 canonical TOML 存储。
//!
//! 旧 `app_settings` 表属于旧会话版本，v2 不导入；普通启动与运行期只读写本文件。
//! 根 `schemaVersion` 由 version-migrate 类型化链管理（1→2 见 `migration`）：只有源为
//! 旧版时才原子持久化一次，当前版本读取是纯 no-op。每个 mutation 使用同一把锁完成
//! 读取-修改-原子替换，`revision` 单调递增并提供幂等 no-op。
//!
//! 已知 `observed:accountUsage:v2` key 的 value 结构由 `payload` 定义；读取与写入
//! 边界只接受当前 payload，不再承担历史格式分派。

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, PoisonError};

use anyhow::{Context, Result, ensure};
use version_migrate::{IntoDomain, Versioned};

use crate::studio::ids::unix_seconds;
use crate::studio::store::StudioStore;
use crate::studio::toml_store::{self, RevisionedDocument};
use crate::toml_schema;

mod history;
mod migration;
pub(in crate::studio) mod payload;

const ENTITY: &str = "settings";
const VERSION_KEY: &str = "schemaVersion";

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::studio) struct SettingEntry {
    pub(in crate::studio) key: String,
    pub(in crate::studio) value: String,
    pub(in crate::studio) updated_at: i64,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize, Versioned)]
#[versioned(version = "2.0.0")]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SettingsDocument {
    revision: u64,
    entries: Vec<SettingEntry>,
}

impl IntoDomain<SettingsDocument> for SettingsDocument {
    fn into_domain(self) -> SettingsDocument {
        self
    }
}

impl RevisionedDocument for SettingsDocument {
    const KIND: &'static str = "Studio settings";
    const VERSION_KEY: &'static str = VERSION_KEY;

    fn revision_mut(&mut self) -> &mut u64 {
        &mut self.revision
    }
}

#[derive(Clone)]
pub(in crate::studio) struct SettingsStore {
    path: PathBuf,
    inner: Arc<Mutex<SettingsDocument>>,
}

impl SettingsStore {
    pub(in crate::studio) async fn load(path: PathBuf) -> Result<Self> {
        let document = match tokio::fs::read_to_string(&path).await {
            Ok(content) => load_current(&path, &content)?,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => SettingsDocument {
                revision: 1,
                entries: Vec::new(),
            },
            Err(error) => return Err(error.into()),
        };
        Ok(Self {
            path,
            inner: Arc::new(Mutex::new(document)),
        })
    }

    pub(in crate::studio) fn get(&self, key: &str) -> Option<String> {
        self.lock()
            .entries
            .iter()
            .find(|entry| entry.key == key)
            .map(|entry| entry.value.clone())
    }

    pub(in crate::studio) async fn put(&self, key: &str, value: &str) -> Result<()> {
        ensure!(!key.trim().is_empty(), "setting key must not be empty");
        if key == payload::KEY {
            payload::parse_current(value).with_context(|| {
                format!("setting {key} must hold the current account usage payload")
            })?;
        }
        let key = key.to_string();
        let value = value.to_string();
        self.mutate(move |document| {
            let updated_at = unix_seconds();
            match document.entries.iter_mut().find(|entry| entry.key == key) {
                Some(existing) if existing.value == value => false,
                Some(existing) => {
                    existing.value = value;
                    existing.updated_at = updated_at;
                    true
                }
                None => {
                    document.entries.push(SettingEntry {
                        key,
                        value,
                        updated_at,
                    });
                    true
                }
            }
        })
        .await
    }

    /// 把当前内存文档写入 canonical 文件；文件已存在时不覆盖。
    ///
    /// 只有全新安装的初始化使用，用来在任何 mutation 之前落盘完整空文档；正常运行
    /// 写入都经 [`Self::put`]，历史版本的升级持久化发生在 [`Self::load`] 内。
    pub(in crate::studio) async fn persist_if_absent(&self) -> Result<()> {
        let inner = self.inner.clone();
        let path = self.path.clone();
        tokio::task::spawn_blocking(move || toml_store::persist_if_absent(&inner, &path)).await?
    }

    async fn mutate(
        &self,
        change: impl FnOnce(&mut SettingsDocument) -> bool + Send + 'static,
    ) -> Result<()> {
        let inner = self.inner.clone();
        let path = self.path.clone();
        tokio::task::spawn_blocking(move || toml_store::mutate_document(&inner, &path, change))
            .await?
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, SettingsDocument> {
        self.inner.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

/// Loads the current document through the typed schema chain, validates business
/// invariants, and persists exactly once when the source schema was older.
fn load_current(path: &Path, content: &str) -> Result<SettingsDocument> {
    let target = toml_schema::integer_version(SettingsDocument::VERSION)?;
    let table = toml_schema::parse(path, content, ENTITY, target)?;
    migration::preflight(path, &table, target)?;
    let loaded = toml_schema::load_table::<migration::SettingsV1, SettingsDocument>(
        path,
        table,
        &migration::migrator()?,
        ENTITY,
        VERSION_KEY,
    )?;
    validate(path, &loaded.document, loaded.source_version, target)?;
    if loaded.migrated {
        // Schema-only upgrade: the business revision and entry times are preserved and
        // the current document is published atomically. Re-opening it is a pure read.
        let contents = toml_schema::encode(&loaded.document, VERSION_KEY)?;
        pl_tool::workspace::write_file_atomically(path, contents.as_bytes())?;
    }
    Ok(loaded.document)
}

fn validate(path: &Path, document: &SettingsDocument, source: u32, target: u32) -> Result<()> {
    let invalid = |error: anyhow::Error| {
        toml_schema::migration_error(path, ENTITY, Some(source), target, "validate", error)
    };
    if document.revision < 1 {
        return Err(invalid(anyhow::anyhow!(
            "Studio settings revision is invalid"
        )));
    }
    let mut seen = std::collections::BTreeSet::new();
    for entry in &document.entries {
        if entry.key.trim().is_empty() {
            return Err(invalid(anyhow::anyhow!("Studio settings key is empty")));
        }
        if !seen.insert(entry.key.as_str()) {
            return Err(invalid(anyhow::anyhow!(
                "Studio settings contain a duplicate key"
            )));
        }
        if entry.key == payload::KEY {
            payload::parse_current(&entry.value).map_err(invalid)?;
        }
    }
    Ok(())
}

impl StudioStore {
    pub async fn save_setting(&self, key: &str, value: &str) -> Result<()> {
        self.settings_store().put(key, value).await
    }

    pub async fn load_setting(&self, key: &str) -> Result<Option<String>> {
        Ok(self.settings_store().get(key))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const LEGACY_V2: &str = r#"{"state":{"kind":"ready","data":{"revision":19,"updatedAt":22,"lastCheckedAt":22,"value":{"configFingerprint":"legacy-inputs","usages":[{"accountId":"legacy-balance","revision":9,"updatedAt":22,"lastOperationId":"legacy-check","state":{"kind":"ready","data":{"data":{"kind":"deepSeekBalance","data":{"is_available":true,"balances":[{"currency":"USD","total_balance":"1.000001","granted_balance":"0.000001","topped_up_balance":"1.000000"},{"currency":"CNY","total_balance":"7.25","granted_balance":"2.00","topped_up_balance":"5.25"}]}}}}}]}}}}"#;

    const LEGACY_V3: &str = r#"{"formatVersion":3,"revision":5,"updatedAt":77,"accounts":[{"queryIdentity":"identity-a","observation":{"accountId":"acct-1","queryRevision":2,"revision":3,"phase":"succeeded","operationId":null,"checkedAt":76,"failure":null,"lastGood":null}}],"legacyUnbound":null}"#;

    fn v1_content(value: &str) -> String {
        format!(
            "schemaVersion = 1\nrevision = 7\n\n[[entries]]\nkey = 'observed:accountUsage:v2'\nvalue = '{value}'\nupdatedAt = 42\n\n[[entries]]\nkey = 'unrelated.setting'\nvalue = 'keep me exactly'\nupdatedAt = 43\n"
        )
    }

    fn read_table(path: &Path) -> toml::Table {
        let content = std::fs::read_to_string(path).expect("settings file is readable");
        toml::from_str(&content).expect("settings file is valid TOML")
    }

    #[test]
    fn historical_payload_failure_keeps_its_typed_source() {
        let error = load_current(Path::new("settings.toml"), &v1_content("invalid json"))
            .expect_err("invalid nested JSON must fail before committing");
        assert!(error.is::<toml_schema::DocumentMigrationFailed>());
        assert!(error.chain().any(|cause| cause.is::<serde_json::Error>()));
    }

    #[tokio::test]
    async fn fresh_install_persists_current_document() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let path = temp.path().join("settings.toml");
        let store = SettingsStore::load(path.clone()).await?;
        store.persist_if_absent().await?;
        let table = read_table(&path);
        assert_eq!(table["schemaVersion"].as_integer(), Some(2));
        assert_eq!(table["revision"].as_integer(), Some(1));
        match table.get("entries") {
            None => {}
            Some(value) => assert!(value.as_array().is_some_and(Vec::is_empty)),
        }
        Ok(())
    }

    #[tokio::test]
    async fn migrates_v1_once_preserving_revisions_and_unknown_entries() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let path = temp.path().join("settings.toml");
        std::fs::write(&path, v1_content(LEGACY_V2))?;

        let store = SettingsStore::load(path.clone()).await?;
        let table = read_table(&path);
        assert_eq!(table["schemaVersion"].as_integer(), Some(2));
        assert_eq!(table["revision"].as_integer(), Some(7));
        let entries = table["entries"].as_array().expect("entries survive");
        assert_eq!(entries.len(), 2);
        let usage = entries[0].as_table().expect("usage entry");
        assert_eq!(usage["key"].as_str(), Some(payload::KEY));
        assert_eq!(usage["updatedAt"].as_integer(), Some(42));
        let migrated = payload::parse_current(usage["value"].as_str().expect("value survives"))
            .expect("known key holds the current payload");
        assert_eq!(migrated.revision, 19);
        assert_eq!(migrated.updated_at, 22);
        assert!(migrated.accounts.is_empty());
        assert_eq!(migrated.legacy_unbound.as_deref(), Some(LEGACY_V2));
        let unrelated = entries[1].as_table().expect("unrelated entry");
        assert_eq!(unrelated["key"].as_str(), Some("unrelated.setting"));
        assert_eq!(unrelated["value"].as_str(), Some("keep me exactly"));
        assert_eq!(unrelated["updatedAt"].as_integer(), Some(43));
        assert_eq!(
            store.get(payload::KEY).as_deref(),
            Some(usage["value"].as_str().expect("value survives"))
        );

        // The persisted current document reopens as a pure read without rewriting.
        let before = std::fs::read(&path)?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let original = std::fs::metadata(temp.path())?.permissions();
            let mut readonly = original.clone();
            readonly.set_mode(0o555);
            std::fs::set_permissions(temp.path(), readonly)?;
            let reopened = SettingsStore::load(path.clone()).await;
            std::fs::set_permissions(temp.path(), original)?;
            reopened?;
        }
        #[cfg(not(unix))]
        {
            SettingsStore::load(path.clone()).await?;
        }
        assert_eq!(std::fs::read(&path)?, before);
        Ok(())
    }

    #[tokio::test]
    async fn migrates_v3_payload_without_its_embedded_version() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let path = temp.path().join("settings.toml");
        std::fs::write(&path, v1_content(LEGACY_V3))?;
        let store = SettingsStore::load(path.clone()).await?;
        let table = read_table(&path);
        assert_eq!(table["schemaVersion"].as_integer(), Some(2));
        let value = table["entries"][0]["value"]
            .as_str()
            .expect("value survives");
        let payload = payload::parse_current(value).expect("current payload");
        assert_eq!(payload.revision, 5);
        assert_eq!(payload.updated_at, 77);
        assert_eq!(payload.accounts.len(), 1);
        assert_eq!(payload.accounts[0].query_identity, "identity-a");
        assert_eq!(payload.accounts[0].observation.account_id, "acct-1");
        assert_eq!(payload.legacy_unbound, None);
        assert_eq!(store.get(payload::KEY).as_deref(), Some(value));
        Ok(())
    }

    #[tokio::test]
    async fn failing_candidates_preserve_the_original_bytes() -> Result<()> {
        let candidates: Vec<String> = vec![
            "schemaVersion = 9\nrevision = 7\nentries = []\n".to_string(),
            v1_content(r#"{"formatVersion":999,"futurePayload":"preserve exactly"}"#),
            v1_content(
                r#"{"formatVersion":3,"revision":5,"updatedAt":77,"accounts":[{"queryIdentity":"a","observation":{"accountId":"dup","queryRevision":1,"revision":1,"phase":"unchecked","operationId":null,"checkedAt":null,"failure":null,"lastGood":null}},{"queryIdentity":"b","observation":{"accountId":"dup","queryRevision":1,"revision":1,"phase":"unchecked","operationId":null,"checkedAt":null,"failure":null,"lastGood":null}}],"legacyUnbound":null}"#,
            ),
            "schemaVersion = 1\nrevision = 0\nentries = []\n".to_owned(),
            "schemaVersion = 1\nrevision = 7\n\n[[entries]]\nkey = ''\nvalue = 'x'\nupdatedAt = 1\n"
                .to_owned(),
        ];
        for content in candidates {
            let temp = tempfile::tempdir()?;
            let path = temp.path().join("settings.toml");
            std::fs::write(&path, &content)?;
            let error = match SettingsStore::load(path.clone()).await {
                Ok(_) => panic!("invalid candidate must fail the whole document"),
                Err(error) => error,
            };
            assert!(
                error
                    .chain()
                    .any(|cause| cause.is::<crate::toml_schema::DocumentMigrationFailed>()),
                "expected a typed migration failure, got: {error:#}"
            );
            assert_eq!(std::fs::read(&path)?, content.as_bytes());
        }
        Ok(())
    }

    #[tokio::test]
    async fn put_validates_the_known_key_payload_boundary() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let path = temp.path().join("settings.toml");
        let store = SettingsStore::load(path.clone()).await?;
        assert!(store.put(payload::KEY, LEGACY_V3).await.is_err());
        assert!(store.put(payload::KEY, "invalid json").await.is_err());
        assert!(!path.exists(), "rejected puts must not touch the document");
        let current = r#"{"revision":1,"updatedAt":9,"accounts":[]}"#;
        store.put(payload::KEY, current).await?;
        let first = std::fs::read_to_string(&path)?;
        let table = toml::from_str::<toml::Table>(&first).expect("valid TOML");
        assert_eq!(table["schemaVersion"].as_integer(), Some(2));
        assert_eq!(table["revision"].as_integer(), Some(2));
        assert_eq!(store.get(payload::KEY).as_deref(), Some(current));
        // Idempotent no-op: same value does not bump the revision or rewrite the file.
        store.put(payload::KEY, current).await?;
        assert_eq!(std::fs::read_to_string(&path)?, first);
        Ok(())
    }
}
