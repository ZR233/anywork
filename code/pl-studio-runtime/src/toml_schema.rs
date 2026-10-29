//! Integer TOML headers at the boundary of the official typed migration paths.
//!
//! Resource owners retain validation, locking, credentials, recovery and all writes.

use std::path::{Path, PathBuf};

use anyhow::{Context, Result, ensure};
use serde::{Serialize, de::DeserializeOwned};
use version_migrate::{Migrator, Versioned};

#[derive(Debug, thiserror::Error)]
#[error(
    "{document} TOML schema operation failed at {stage} in {path} (source {source_version:?}, target {target_version})"
)]
pub(crate) struct DocumentMigrationFailed {
    path: PathBuf,
    document: &'static str,
    source_version: Option<u32>,
    target_version: u32,
    stage: &'static str,
    #[source]
    source: anyhow::Error,
}

#[derive(Debug, thiserror::Error)]
#[error("{document} TOML migration path is invalid")]
pub(crate) struct DocumentChainInvalid {
    document: &'static str,
    #[source]
    source: anyhow::Error,
}

pub(crate) struct LoadedDocument<D> {
    pub(crate) document: D,
    pub(crate) source_version: u32,
    pub(crate) migrated: bool,
}

/// Keep the underlying cause, without adding file contents or credentials to context.
pub(crate) fn migration_error(
    path: &Path,
    document: &'static str,
    source_version: Option<u32>,
    target_version: u32,
    stage: &'static str,
    error: impl Into<anyhow::Error>,
) -> anyhow::Error {
    anyhow::Error::new(DocumentMigrationFailed {
        path: path.to_owned(),
        document,
        source_version,
        target_version,
        stage,
        source: error.into(),
    })
}

pub(crate) fn chain_error(
    document: &'static str,
    error: impl Into<anyhow::Error>,
) -> anyhow::Error {
    anyhow::Error::new(DocumentChainInvalid {
        document,
        source: error.into(),
    })
}

/// A version is a document's integer schema, not an application semver.
pub(crate) fn integer_version(version: &str) -> Result<u32> {
    let version = semver::Version::parse(version)?;
    ensure!(
        version.minor == 0
            && version.patch == 0
            && version.pre.is_empty()
            && version.build.is_empty(),
        "document schema must use an integer major version"
    );
    u32::try_from(version.major).context("document schema exceeds u32")
}

/// Strict admission precedes the library loader, which otherwise accepts unknown versions.
/// `First` is the first *formal* DTO, never the Profile's unversioned import DTO.
pub(crate) fn load<First, Current>(
    path: &Path,
    content: &str,
    migrator: &Migrator,
    entity: &'static str,
    version_key: &'static str,
) -> Result<LoadedDocument<Current>>
where
    First: Versioned,
    Current: Versioned + DeserializeOwned,
{
    let (_, target) = bounds::<First, Current>(migrator, entity)?;
    let value = parse(path, content, entity, target)?;
    load_table::<First, Current>(path, value, migrator, entity, version_key)
}

/// A resource with a fallible preflight can retain typed causes before the library's
/// Serde boundary. Parsing remains shared so diagnostics never include source lines.
pub(crate) fn parse(
    path: &Path,
    content: &str,
    entity: &'static str,
    target: u32,
) -> Result<toml::Table> {
    toml::from_str(content).map_err(|mut error: toml::de::Error| {
        error.set_input(None);
        migration_error(path, entity, None, target, "parse", error)
    })
}

fn bounds<First: Versioned, Current: Versioned>(
    migrator: &Migrator,
    entity: &'static str,
) -> Result<(u32, u32)> {
    let target = migrator
        .get_latest_version(entity)
        .context("missing document migration path")
        .and_then(integer_version)
        .map_err(|error| chain_error(entity, error))?;
    let minimum = integer_version(First::VERSION).map_err(|error| chain_error(entity, error))?;
    ensure!(
        target == integer_version(Current::VERSION)? && minimum > 0 && minimum <= target,
        chain_error(
            entity,
            anyhow::anyhow!("current DTO does not match the registered schema path")
        )
    );
    Ok((minimum, target))
}

/// The same strict loader for an already parsed root table; this does not schedule steps
/// or commit anything. Owners may prevalidate a nested payload without stringifying its error.
pub(crate) fn load_table<First, Current>(
    path: &Path,
    value: toml::Table,
    migrator: &Migrator,
    entity: &'static str,
    version_key: &'static str,
) -> Result<LoadedDocument<Current>>
where
    First: Versioned,
    Current: Versioned + DeserializeOwned,
{
    let (_, target) = bounds::<First, Current>(migrator, entity)?;
    let value = serde_json::to_value(value)
        .map_err(|error| migration_error(path, entity, None, target, "adapt", error))?;
    load_json::<First, Current>(path, value, migrator, entity, version_key)
}

/// Recovery snapshots of the same document may contain JSON null Options. Admission
/// and library execution are identical; snapshots never round-trip through TOML.
pub(crate) fn load_json<First, Current>(
    path: &Path,
    mut value: serde_json::Value,
    migrator: &Migrator,
    entity: &'static str,
    version_key: &'static str,
) -> Result<LoadedDocument<Current>>
where
    First: Versioned,
    Current: Versioned + DeserializeOwned,
{
    let (minimum, target) = bounds::<First, Current>(migrator, entity)?;
    let source = value
        .get(version_key)
        .and_then(serde_json::Value::as_u64)
        .and_then(|version| u32::try_from(version).ok());
    let document = (|| {
        let source = source.context("missing or invalid integer document schema")?;
        ensure!(
            (minimum..=target).contains(&source),
            "unsupported document schema"
        );
        value
            .as_object_mut()
            .context("document must be an object")?
            .insert(version_key.into(), format!("{source}.0.0").into());
        migrator.load_flat_from(entity, value).map_err(Into::into)
    })()
    .map_err(|error| migration_error(path, entity, source, target, "decode/migrate", error))?;
    Ok(LoadedDocument {
        document,
        source_version: source.context("validated document schema is missing")?,
        migrated: source != Some(target),
    })
}

/// Current DTO -> TOML directly. The library's JSON save API is deliberately not used.
pub(crate) fn encode<D: Versioned + Serialize>(
    document: &D,
    version_key: &'static str,
) -> Result<String> {
    let version = integer_version(D::VERSION)?;
    ensure!(version > 0, "cannot persist an unversioned import DTO");
    let mut value = toml::Value::try_from(document)?;
    let table = value
        .as_table_mut()
        .context("document must be a TOML table")?;
    ensure!(
        !table.contains_key(version_key),
        "document DTO must not contain its root schema header"
    );
    table.insert(version_key.into(), i64::from(version).into());
    toml::to_string_pretty(&value).map_err(Into::into)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::Deserialize;
    use version_migrate::{IntoDomain, MigratesTo};

    #[derive(Debug, Serialize, Deserialize, Versioned)]
    #[versioned(version = "1.0.0")]
    #[serde(deny_unknown_fields)]
    struct V1 {
        name: String,
        count: i64,
        path: PathBuf,
    }

    #[derive(Debug, Serialize, Deserialize, Versioned)]
    #[versioned(version = "2.0.0")]
    #[serde(deny_unknown_fields)]
    struct V2 {
        name: String,
        count: i64,
        path: PathBuf,
        note: Option<String>,
    }

    #[derive(Debug, PartialEq, Serialize, Deserialize, Versioned)]
    #[versioned(version = "3.0.0")]
    #[serde(deny_unknown_fields)]
    struct V3 {
        title: String,
        values: Vec<i64>,
        path: PathBuf,
        #[serde(skip_serializing_if = "Option::is_none")]
        note: Option<String>,
    }

    impl MigratesTo<V2> for V1 {
        fn migrate(self) -> V2 {
            V2 {
                name: self.name,
                count: self.count,
                path: self.path,
                note: None,
            }
        }
    }

    impl MigratesTo<V3> for V2 {
        fn migrate(self) -> V3 {
            V3 {
                title: self.name,
                values: vec![self.count, i64::MAX],
                path: self.path,
                note: self.note,
            }
        }
    }

    impl IntoDomain<V3> for V3 {
        fn into_domain(self) -> V3 {
            self
        }
    }

    fn migrator() -> Migrator {
        let mut migrator = Migrator::new();
        migrator
            .register(
                Migrator::define("test")
                    .with_keys("schemaVersion", "data")
                    .from::<V1>()
                    .step::<V2>()
                    .step::<V3>()
                    .into::<V3>(),
            )
            .expect("valid path");
        migrator
    }

    #[test]
    fn two_steps_preserve_real_toml_serde_and_integer_wire() {
        let raw = "schemaVersion=1\nname='saved'\ncount=-7\npath='relative/file'\n";
        let loaded = load::<V1, V3>(
            Path::new("test.toml"),
            raw,
            &migrator(),
            "test",
            "schemaVersion",
        )
        .expect("two real conversions");
        assert!(loaded.migrated);
        assert_eq!(loaded.source_version, 1);
        assert_eq!(loaded.document.title, "saved");
        assert_eq!(loaded.document.values, [-7, i64::MAX]);
        assert_eq!(loaded.document.path, Path::new("relative/file"));
        assert_eq!(loaded.document.note, None);
        let encoded = encode(&loaded.document, "schemaVersion").expect("TOML save");
        let header: toml::Table = toml::from_str(&encoded).expect("integer TOML header");
        assert_eq!(header["schemaVersion"].as_integer(), Some(3));
        let reloaded = load::<V1, V3>(
            Path::new("test.toml"),
            &encoded,
            &migrator(),
            "test",
            "schemaVersion",
        )
        .expect("current schema");
        assert!(!reloaded.migrated);
        assert_eq!(reloaded.document, loaded.document);
    }

    #[test]
    fn rejects_bad_headers_even_with_current_payload() {
        for header in [
            "",
            "schemaVersion=-1\n",
            "schemaVersion=0\n",
            "schemaVersion=4\n",
            "schemaVersion=4294967296\n",
            "schemaVersion='3'\n",
            "schemaVersion=3.0\n",
        ] {
            let raw = format!("{header}title='current'\nvalues=[9]\npath='p'\n");
            let error = load::<V1, V3>(
                Path::new("test.toml"),
                &raw,
                &migrator(),
                "test",
                "schemaVersion",
            )
            .err()
            .expect("reject before permissive library loader");
            assert!(error.is::<DocumentMigrationFailed>());
        }
    }

    #[test]
    fn recovery_snapshots_keep_null_options_and_strict_integer_admission() {
        let snapshot = serde_json::json!({
            "schemaVersion": 3,
            "title": "snapshot",
            "values": [17],
            "path": "relative/file",
            "note": null
        });
        let loaded = load_json::<V1, V3>(
            Path::new("journal.json"),
            snapshot.clone(),
            &migrator(),
            "test",
            "schemaVersion",
        )
        .expect("a recovery snapshot does not serialize null through TOML");
        assert_eq!(loaded.document.note, None);
        assert_eq!(loaded.document.values, [17]);
        assert!(!loaded.migrated);
        for invalid in [
            serde_json::json!(0),
            serde_json::json!(-1),
            serde_json::json!(4),
            serde_json::json!("3"),
            serde_json::json!(3.0),
            serde_json::json!(u64::MAX),
            serde_json::Value::Null,
        ] {
            let mut value = snapshot.clone();
            value["schemaVersion"] = invalid;
            let error = load_json::<V1, V3>(
                Path::new("journal.json"),
                value,
                &migrator(),
                "test",
                "schemaVersion",
            )
            .err()
            .expect("invalid integer snapshot schema");
            assert!(error.is::<DocumentMigrationFailed>());
        }
    }

    #[test]
    fn parse_context_retains_typed_cause_without_echoing_source() {
        let error = load::<V1, V3>(
            Path::new("private.toml"),
            "schemaVersion=1\nsecret='private-token' invalid\n",
            &migrator(),
            "test",
            "schemaVersion",
        )
        .err()
        .expect("invalid TOML");
        assert!(error.is::<DocumentMigrationFailed>());
        assert!(error.chain().any(|cause| cause.is::<toml::de::Error>()));
        assert!(!format!("{error:#}").contains("private-token"));
    }

    #[test]
    fn admission_uses_the_formal_first_dto_and_checks_the_latest_type() {
        let mut later = Migrator::new();
        later
            .register(
                Migrator::define("test")
                    .with_keys("schemaVersion", "data")
                    .from::<V2>()
                    .step::<V3>()
                    .into::<V3>(),
            )
            .expect("valid later path");
        let error = load::<V2, V3>(
            Path::new("test.toml"),
            "schemaVersion=1\ntitle='current'\nvalues=[9]\npath='p'\n",
            &later,
            "test",
            "schemaVersion",
        )
        .err()
        .expect("below the formal lower bound");
        assert!(error.is::<DocumentMigrationFailed>());
        let error = load::<V2, V2>(
            Path::new("test.toml"),
            "schemaVersion=2\nname='saved'\ncount=9\npath='p'\n",
            &later,
            "test",
            "schemaVersion",
        )
        .err()
        .expect("the registered latest and current DTO must agree");
        assert!(error.is::<DocumentChainInvalid>());
    }
}
