//! Frozen Settings `schemaVersion` 1 → 2 migration path.
//!
//! Fallible input validation lives in the frozen V1 Serde types: the version-migrate
//! step function deserializes `SettingsV1` before `MigratesTo` runs, so a rejected
//! historical payload fails the whole document as a typed migration error. `migrate`
//! itself only moves already-validated fields; it cannot panic or swallow an error.

use anyhow::Result;
use serde::{Deserialize, Serialize};
use version_migrate::{MigratesTo, Migrator, Versioned};

use super::{ENTITY, SettingEntry, SettingsDocument, VERSION_KEY, payload};

/// Frozen schemaVersion 1 document wire. The root header is not a DTO field; the shared
/// integer-header boundary injects and removes it around the typed chain.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Versioned)]
#[versioned(version = "1.0.0")]
#[serde(
    rename_all = "camelCase",
    deny_unknown_fields,
    try_from = "SettingsV1Wire"
)]
pub(super) struct SettingsV1 {
    revision: u64,
    entries: Vec<SettingEntryV1>,
}

/// Frozen schemaVersion 1 entry wire.
///
/// `value` keeps the historical bytes so this intermediate DTO round-trips through its
/// own Serialize/Deserialize. `current_value` is computed while deserializing: for the
/// account usage key it is the validated current payload string, for every other key it
/// equals `value` and the entry passes through untouched.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(
    rename_all = "camelCase",
    deny_unknown_fields,
    try_from = "SettingEntryV1Wire"
)]
pub(super) struct SettingEntryV1 {
    key: String,
    value: String,
    #[serde(skip)]
    current_value: String,
    updated_at: i64,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SettingsV1Wire {
    revision: u64,
    entries: Vec<SettingEntryV1Wire>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SettingEntryV1Wire {
    key: String,
    value: String,
    updated_at: i64,
}

impl TryFrom<SettingsV1Wire> for SettingsV1 {
    type Error = anyhow::Error;

    fn try_from(wire: SettingsV1Wire) -> Result<Self> {
        Ok(Self {
            revision: wire.revision,
            entries: wire
                .entries
                .into_iter()
                .map(SettingEntryV1::try_from)
                .collect::<Result<_>>()?,
        })
    }
}

impl TryFrom<SettingEntryV1Wire> for SettingEntryV1 {
    type Error = anyhow::Error;

    fn try_from(wire: SettingEntryV1Wire) -> Result<Self> {
        let current_value = if wire.key == payload::KEY {
            let migrated = payload::migrate_legacy(&wire.value)?;
            serde_json::to_string(&migrated)?
        } else {
            wire.value.clone()
        };
        Ok(Self {
            key: wire.key,
            value: wire.value,
            current_value,
            updated_at: wire.updated_at,
        })
    }
}

/// Validate through the same raw DTO/TryFrom before the library's Serde error
/// stringification. The official loader still owns strict root admission and all steps.
pub(super) fn preflight(path: &std::path::Path, table: &toml::Table, target: u32) -> Result<()> {
    let first = crate::toml_schema::integer_version(SettingsV1::VERSION)?;
    if table.get(VERSION_KEY).and_then(toml::Value::as_integer) != Some(i64::from(first)) {
        return Ok(());
    }
    let mut data = table.clone();
    data.remove(VERSION_KEY);
    let validate = || -> Result<()> {
        let wire: SettingsV1Wire = toml::Value::Table(data).try_into()?;
        SettingsV1::try_from(wire).map(|_| ())
    };
    validate().map_err(|error| {
        crate::toml_schema::migration_error(
            path,
            ENTITY,
            Some(first),
            target,
            "validate payload",
            error,
        )
    })
}

impl MigratesTo<SettingsDocument> for SettingsV1 {
    fn migrate(self) -> SettingsDocument {
        SettingsDocument {
            revision: self.revision,
            entries: self
                .entries
                .into_iter()
                .map(|entry| SettingEntry {
                    key: entry.key,
                    value: entry.current_value,
                    updated_at: entry.updated_at,
                })
                .collect(),
        }
    }
}

/// The typed Settings chain. Registration failure is an internal chain defect, never a
/// document error.
pub(super) fn migrator() -> Result<Migrator> {
    let mut migrator = Migrator::new();
    migrator
        .register(
            Migrator::define(ENTITY)
                .with_keys(VERSION_KEY, "data")
                .from::<SettingsV1>()
                .step::<SettingsDocument>()
                .into::<SettingsDocument>(),
        )
        .map_err(|error| crate::toml_schema::chain_error(ENTITY, anyhow::anyhow!(error)))?;
    Ok(migrator)
}

#[cfg(test)]
mod tests {
    use super::*;

    const LEGACY_V2: &str = r#"{"state":{"kind":"ready","data":{"revision":19,"updatedAt":22,"lastCheckedAt":22,"value":{"configFingerprint":"legacy-inputs","usages":[]}}}}"#;

    fn v1_wire_entries() -> serde_json::Value {
        serde_json::json!({
            "revision": 7,
            "entries": [
                {
                    "key": "observed:accountUsage:v2",
                    "value": LEGACY_V2,
                    "updatedAt": 42,
                },
                {
                    "key": "unrelated.setting",
                    "value": "keep me exactly",
                    "updatedAt": 43,
                },
            ],
        })
    }

    #[test]
    fn frozen_v1_dto_round_trips_through_its_own_serde() {
        let original: SettingsV1 =
            serde_json::from_value(v1_wire_entries()).expect("valid v1 wire");
        let serialized = serde_json::to_string(&original).expect("v1 serializes");
        let reparsed: SettingsV1 = serde_json::from_str(&serialized).expect("v1 re-parses");
        assert_eq!(reparsed, original);
    }

    #[test]
    fn migration_moves_validated_payload_and_preserves_unknown_entries() {
        let v1: SettingsV1 = serde_json::from_value(v1_wire_entries()).expect("valid v1 wire");
        let current = v1.migrate();
        assert_eq!(current.revision, 7);
        assert_eq!(current.entries.len(), 2);
        let usage = current.entries.first().expect("usage entry");
        assert_eq!(usage.updated_at, 42);
        let payload =
            payload::parse_current(&usage.value).expect("known key holds the current payload");
        assert_eq!(payload.revision, 19);
        assert_eq!(payload.legacy_unbound.as_deref(), Some(LEGACY_V2));
        let unrelated = current.entries.last().expect("unrelated entry");
        assert_eq!(unrelated.key, "unrelated.setting");
        assert_eq!(unrelated.value, "keep me exactly");
        assert_eq!(unrelated.updated_at, 43);
    }

    #[test]
    fn invalid_known_key_payload_fails_during_v1_deserialization() {
        let wire = serde_json::json!({
            "revision": 7,
            "entries": [
                {"key": "observed:accountUsage:v2", "value": "{\"formatVersion\":999}", "updatedAt": 42},
            ],
        });
        assert!(serde_json::from_value::<SettingsV1>(wire).is_err());
    }

    #[test]
    fn typed_chain_loads_v1_toml_and_is_idempotent_for_current_files() {
        let content = format!(
            "schemaVersion = 1\nrevision = 7\n\n[[entries]]\nkey = 'observed:accountUsage:v2'\nvalue = '{LEGACY_V2}'\nupdatedAt = 42\n"
        );
        let path = std::path::Path::new("settings.toml");
        let loaded = crate::toml_schema::load::<SettingsV1, SettingsDocument>(
            path,
            &content,
            &migrator().expect("valid chain"),
            ENTITY,
            VERSION_KEY,
        )
        .expect("v1 document migrates");
        assert!(loaded.migrated);
        assert_eq!(loaded.source_version, 1);
        assert_eq!(loaded.document.revision, 7);
        let encoded = crate::toml_schema::encode(&loaded.document, VERSION_KEY)
            .expect("current document encodes");
        let reloaded = crate::toml_schema::load::<SettingsV1, SettingsDocument>(
            path,
            &encoded,
            &migrator().expect("valid chain"),
            ENTITY,
            VERSION_KEY,
        )
        .expect("current document loads");
        assert!(!reloaded.migrated);
        assert_eq!(reloaded.document, loaded.document);
    }

    #[test]
    fn unknown_root_versions_are_rejected_before_the_library() {
        for header in [
            "schemaVersion = 0",
            "schemaVersion = 3",
            "schemaVersion = '1'",
        ] {
            let content = format!("{header}\nrevision = 7\nentries = []\n");
            let loaded = crate::toml_schema::load::<SettingsV1, SettingsDocument>(
                std::path::Path::new("settings.toml"),
                &content,
                &migrator().expect("valid chain"),
                ENTITY,
                VERSION_KEY,
            );
            let error = match loaded {
                Ok(_) => panic!("unsupported root schema must fail"),
                Err(error) => error,
            };
            assert!(error.is::<crate::toml_schema::DocumentMigrationFailed>());
        }
    }
}
