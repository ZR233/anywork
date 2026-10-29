use std::path::Path;

use anyhow::Result;
use serde::{Deserialize, Serialize};
use version_migrate::{IntoDomain, MigratesTo, Migrator, Versioned};

use super::{VERSION_KEY, identity, into_current, wire::AgentWorkspaceMode};
use crate::toml_schema::{self, LoadedDocument};

const ENTITY: &str = "agent-profile";

#[derive(Debug, Clone, Serialize, Deserialize, Versioned)]
#[versioned(version = "1.0.0")]
#[serde(deny_unknown_fields)]
pub(crate) struct ProfileV1 {
    #[serde(default = "enabled")]
    enabled: bool,
    display_name: String,
    description: String,
    when_to_use: String,
    system_instructions: String,
    account_id: String,
    model_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    effort: Option<String>,
    #[serde(default)]
    workspace_mode: AgentWorkspaceMode,
}

/// The import is distinct from the first formal version; an on-disk 0 is never admitted.
#[derive(Debug, Serialize, Deserialize, Versioned)]
#[versioned(version = "0.0.0")]
#[serde(try_from = "ImportWire")]
struct ProfileImport(ProfileV1);

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ImportWire {
    #[serde(default = "enabled")]
    enabled: bool,
    display_name: String,
    description: String,
    when_to_use: String,
    system_instructions: String,
    provider: Option<String>,
    account_id: Option<String>,
    model: Option<String>,
    model_id: Option<String>,
    effort: Option<String>,
    #[serde(default)]
    workspace_mode: AgentWorkspaceMode,
}

impl TryFrom<ImportWire> for ProfileImport {
    type Error = anyhow::Error;

    fn try_from(value: ImportWire) -> Result<Self> {
        Ok(Self(ProfileV1 {
            enabled: value.enabled,
            display_name: value.display_name,
            description: value.description,
            when_to_use: value.when_to_use,
            system_instructions: value.system_instructions,
            account_id: identity(value.provider, value.account_id, "account")?,
            model_id: identity(value.model, value.model_id, "model")?,
            effort: value.effort,
            workspace_mode: value.workspace_mode,
        }))
    }
}

impl MigratesTo<ProfileV1> for ProfileImport {
    fn migrate(self) -> ProfileV1 {
        self.0
    }
}

impl IntoDomain<ProfileV1> for ProfileV1 {
    fn into_domain(self) -> Self {
        self
    }
}

impl ProfileV1 {
    pub(crate) fn from_current(profile: &super::super::UserAgentProfile) -> Result<Self> {
        into_current(profile)
    }

    pub(crate) fn into_profile(self) -> Result<super::super::UserAgentProfile> {
        into_current(&self)
    }

    pub(crate) fn encode(&self) -> Result<String> {
        toml_schema::encode(self, VERSION_KEY)
    }
}

fn migrator() -> Result<Migrator> {
    let mut migrator = Migrator::new();
    migrator
        .register(
            Migrator::define(ENTITY)
                .with_keys(VERSION_KEY, "data")
                .from::<ProfileImport>()
                .step::<ProfileV1>()
                .into::<ProfileV1>(),
        )
        .map_err(|error| toml_schema::chain_error(ENTITY, error))?;
    Ok(migrator)
}

pub(crate) fn load_profile(path: &Path, content: &str) -> Result<LoadedDocument<ProfileV1>> {
    let migrator = migrator()?;
    let mut value = toml_schema::parse(path, content, ENTITY, 1)?;
    if value.contains_key(VERSION_KEY) {
        return toml_schema::load::<ProfileV1, ProfileV1>(
            path,
            content,
            &migrator,
            ENTITY,
            VERSION_KEY,
        );
    }
    value.insert(VERSION_KEY.into(), "0.0.0".into());
    let document = migrator
        .load_flat_from(ENTITY, value)
        .map_err(|error| toml_schema::migration_error(path, ENTITY, None, 1, "import", error))?;
    Ok(LoadedDocument {
        document,
        source_version: 0,
        migrated: true,
    })
}

pub(in crate::config) fn load_current(path: &Path, content: &str) -> Result<ProfileV1> {
    toml_schema::load::<ProfileV1, ProfileV1>(path, content, &migrator()?, ENTITY, VERSION_KEY)
        .map(|loaded| loaded.document)
}

const fn enabled() -> bool {
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    const FIELDS: &str = "enabled=false\ndisplay_name='Saved'\ndescription='d'\nwhen_to_use='w'\nsystem_instructions='i'\n";

    #[test]
    fn import_identity_matrix_preserves_disabled_choice() {
        for keys in [
            "provider='account'\nmodel='model'\n",
            "account_id='account'\nmodel_id='model'\n",
            "provider='account'\nmodel_id='model'\n",
            "account_id='account'\nmodel='model'\n",
            "provider='account'\naccount_id='account'\nmodel='model'\nmodel_id='model'\n",
        ] {
            let imported = load_profile(Path::new("profile.toml"), &format!("{FIELDS}{keys}"))
                .expect("unique complete identity");
            assert!(imported.migrated);
            let profile = imported.document.into_profile().unwrap();
            assert!(!profile.enabled);
            assert_eq!(profile.account_id.as_str(), "account");
            assert_eq!(profile.model_id, "model");
        }
    }

    #[test]
    fn malformed_imports_and_versioned_inputs_never_fall_back() {
        for keys in [
            "provider='a'\naccount_id='b'\nmodel='m'\n",
            "provider='a'\nmodel='a'\nmodel_id='b'\n",
            "provider='a'\n",
            "model='m'\n",
            "provider=1\nmodel='m'\n",
            "provider='a'\nmodel='m'\nunknown=true\n",
            "schema_version=0\nprovider='a'\nmodel='m'\n",
            "schema_version=1\nprovider='a'\nmodel='m'\n",
            "schema_version=2\naccount_id='a'\nmodel_id='m'\n",
            "schema_version=-1\naccount_id='a'\nmodel_id='m'\n",
            "schema_version='1'\naccount_id='a'\nmodel_id='m'\n",
            "schema_version=1.0\naccount_id='a'\nmodel_id='m'\n",
        ] {
            let error = load_profile(Path::new("profile.toml"), &format!("{FIELDS}{keys}"))
                .err()
                .expect("reject malformed input");
            assert!(error.is::<toml_schema::DocumentMigrationFailed>());
        }
    }

    #[test]
    fn current_dto_round_trip_uses_integer_version() {
        let imported = load_profile(
            Path::new("profile.toml"),
            &format!("{FIELDS}provider='a'\nmodel='m'\n"),
        )
        .unwrap();
        let encoded = imported.document.encode().unwrap();
        assert_eq!(
            toml::from_str::<toml::Table>(&encoded).unwrap()[VERSION_KEY].as_integer(),
            Some(1)
        );
        let current = load_profile(Path::new("profile.toml"), &encoded).unwrap();
        assert!(!current.migrated);
        assert_eq!(
            current.document.into_profile().unwrap(),
            imported.document.into_profile().unwrap()
        );
    }

    #[test]
    fn malformed_import_and_v1_syntax_preserve_typed_sources_without_private_input() {
        const PRIVATE: &str = "PROFILE_PRIVATE_SYSTEM_INSTRUCTIONS_SENTINEL_221";
        for (header, identity) in [
            ("", "provider='account'\nmodel='model'\n"),
            (
                "schema_version=1\n",
                "account_id='account'\nmodel_id='model'\n",
            ),
        ] {
            let content = format!(
                "{header}enabled=false\ndisplay_name='Saved'\ndescription='d'\nwhen_to_use='w'\n\
                 system_instructions='{PRIVATE}' trailing\n{identity}"
            );
            let error = load_profile(Path::new("private-profile.toml"), &content)
                .err()
                .expect("bad syntax must not reach the DTO loader");
            assert!(error.is::<toml_schema::DocumentMigrationFailed>());
            assert!(error.chain().any(|cause| cause.is::<toml::de::Error>()));
            assert!(!format!("{error:#}").contains(PRIVATE));
            assert!(!format!("{error:?}").contains(PRIVATE));

            let mut migration_source = false;
            let mut toml_source = false;
            let mut cause: Option<&(dyn std::error::Error + 'static)> = Some(error.as_ref());
            while let Some(current) = cause {
                migration_source |= current.is::<toml_schema::DocumentMigrationFailed>();
                toml_source |= current.is::<toml::de::Error>();
                assert!(!current.to_string().contains(PRIVATE));
                assert!(!format!("{current:?}").contains(PRIVATE));
                cause = current.source();
            }
            assert!(
                migration_source,
                "StdError source traversal must retain the document wrapper"
            );
            assert!(
                toml_source,
                "StdError source traversal must retain the TOML error type"
            );
        }
    }
}
