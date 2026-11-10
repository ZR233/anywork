use std::path::Path;

use anyhow::Result;
use pl_protocol::studio::NewThreadModelRoute;
use pl_protocol::{AcpAgentConfig, AgentBinding, NativeAgentConfig};
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

/// Profile schema 2 的冻结格式：定义元数据 + 后端 binding，ACP 仍含旧连接修订。
///
/// binding 使用本文件冻结的 wire 形状，不直接借用会随产品演进的 domain 结构；
/// V1 的原 Native 字段在迁移中无损进入 Native binding。
#[derive(Debug, Clone, Serialize, Deserialize, Versioned)]
#[versioned(version = "2.0.0")]
#[serde(deny_unknown_fields)]
pub(crate) struct ProfileV2 {
    #[serde(default = "enabled")]
    enabled: bool,
    display_name: String,
    description: String,
    when_to_use: String,
    #[serde(default)]
    workspace_mode: AgentWorkspaceMode,
    binding: ProfileBindingWire,
}

/// Schema 2 的冻结 binding wire；与 domain `AgentBinding` 显式互转，不共享类型。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
enum ProfileBindingWire {
    Native(ProfileNativeWire),
    Acp(ProfileAcpWire),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct ProfileNativeWire {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    route: Option<ProfileRouteWire>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    system_instructions: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct ProfileRouteWire {
    account_id: String,
    model_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    effort: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct ProfileAcpWire {
    account_id: String,
    connection_revision: u64,
}

/// V1 的全部原字段无损进入 Native binding；Acp 绑定只能由 schema 2 显式表达。
impl MigratesTo<ProfileV2> for ProfileV1 {
    fn migrate(self) -> ProfileV2 {
        ProfileV2 {
            enabled: self.enabled,
            display_name: self.display_name,
            description: self.description,
            when_to_use: self.when_to_use,
            workspace_mode: self.workspace_mode,
            binding: ProfileBindingWire::Native(ProfileNativeWire {
                route: Some(ProfileRouteWire {
                    account_id: self.account_id,
                    model_id: self.model_id,
                    effort: self.effort,
                }),
                system_instructions: Some(self.system_instructions),
            }),
        }
    }
}

/// Current Profile wire; ACP references only the stable user definition id.
#[derive(Debug, Clone, Serialize, Deserialize, Versioned)]
#[versioned(version = "3.0.0")]
#[serde(deny_unknown_fields)]
pub(crate) struct ProfileV3 {
    #[serde(default = "enabled")]
    enabled: bool,
    display_name: String,
    description: String,
    when_to_use: String,
    #[serde(default)]
    workspace_mode: AgentWorkspaceMode,
    binding: ProfileBindingV3,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
enum ProfileBindingV3 {
    Native(ProfileNativeWire),
    Acp(ProfileAcpV3),
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct ProfileAcpV3 {
    account_id: String,
}

impl MigratesTo<ProfileV3> for ProfileV2 {
    fn migrate(self) -> ProfileV3 {
        ProfileV3 {
            enabled: self.enabled,
            display_name: self.display_name,
            description: self.description,
            when_to_use: self.when_to_use,
            workspace_mode: self.workspace_mode,
            binding: match self.binding {
                ProfileBindingWire::Native(native) => ProfileBindingV3::Native(native),
                ProfileBindingWire::Acp(acp) => ProfileBindingV3::Acp(ProfileAcpV3 {
                    account_id: acp.account_id,
                }),
            },
        }
    }
}

impl From<&AgentBinding> for ProfileBindingV3 {
    fn from(binding: &AgentBinding) -> Self {
        match binding {
            AgentBinding::Native(native) => Self::Native(ProfileNativeWire {
                route: native.route.as_ref().map(|route| ProfileRouteWire {
                    account_id: route.account_id.clone(),
                    model_id: route.model_id.clone(),
                    effort: route.effort.clone(),
                }),
                system_instructions: native.system_instructions.clone(),
            }),
            AgentBinding::Acp(acp) => Self::Acp(ProfileAcpV3 {
                account_id: acp.account_id.clone(),
            }),
        }
    }
}

impl From<ProfileBindingV3> for AgentBinding {
    fn from(wire: ProfileBindingV3) -> Self {
        match wire {
            ProfileBindingV3::Native(native) => Self::Native(NativeAgentConfig {
                route: native.route.map(|route| NewThreadModelRoute {
                    account_id: route.account_id,
                    model_id: route.model_id,
                    effort: route.effort,
                }),
                system_instructions: native.system_instructions,
            }),
            ProfileBindingV3::Acp(acp) => Self::Acp(AcpAgentConfig {
                account_id: acp.account_id,
            }),
        }
    }
}

impl IntoDomain<ProfileV3> for ProfileV3 {
    fn into_domain(self) -> Self {
        self
    }
}

impl ProfileV3 {
    pub(crate) fn from_current(profile: &super::super::UserAgentProfile) -> Result<Self> {
        Ok(Self {
            enabled: profile.enabled,
            display_name: profile.display_name.clone(),
            description: profile.description.clone(),
            when_to_use: profile.when_to_use.clone(),
            workspace_mode: into_current(&profile.workspace_mode)?,
            binding: (&profile.binding).into(),
        })
    }

    pub(crate) fn into_profile(self) -> Result<super::super::UserAgentProfile> {
        Ok(super::super::UserAgentProfile {
            enabled: self.enabled,
            display_name: self.display_name,
            description: self.description,
            when_to_use: self.when_to_use,
            workspace_mode: into_current(&self.workspace_mode)?,
            binding: self.binding.into(),
        })
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
                .step::<ProfileV2>()
                .step::<ProfileV3>()
                .into::<ProfileV3>(),
        )
        .map_err(|error| toml_schema::chain_error(ENTITY, error))?;
    Ok(migrator)
}

pub(crate) fn load_profile(path: &Path, content: &str) -> Result<LoadedDocument<ProfileV3>> {
    let migrator = migrator()?;
    let mut value = toml_schema::parse(path, content, ENTITY, 3)?;
    if value.contains_key(VERSION_KEY) {
        return toml_schema::load::<ProfileV1, ProfileV3>(
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
        .map_err(|error| toml_schema::migration_error(path, ENTITY, None, 3, "import", error))?;
    Ok(LoadedDocument {
        document,
        source_version: 0,
        migrated: true,
    })
}

pub(in crate::config) fn load_current(path: &Path, content: &str) -> Result<ProfileV3> {
    toml_schema::load::<ProfileV3, ProfileV3>(path, content, &migrator()?, ENTITY, VERSION_KEY)
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
            let AgentBinding::Native(native) = profile.binding else {
                panic!("legacy Profile must migrate to Native");
            };
            let route = native.route.expect("legacy Native route");
            assert_eq!(route.account_id, "account");
            assert_eq!(route.model_id, "model");
            assert_eq!(native.system_instructions.as_deref(), Some("i"));
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
            Some(3)
        );
        let current = load_profile(Path::new("profile.toml"), &encoded).unwrap();
        assert!(!current.migrated);
        assert_eq!(
            current.document.into_profile().unwrap(),
            imported.document.into_profile().unwrap()
        );
    }

    #[test]
    fn v1_migration_preserves_native_effort_instructions_disabled_and_workspace() {
        let migrated = load_profile(
            Path::new("profile.toml"),
            "schema_version=1\nenabled=false\ndisplay_name='Saved'\n\
             description='d'\nwhen_to_use='w'\nsystem_instructions='instructions'\n\
             account_id='account'\nmodel_id='model'\neffort='high'\nworkspace_mode='worktree'\n",
        )
        .unwrap();
        assert_eq!(migrated.source_version, 1);
        assert!(migrated.migrated);
        let profile = migrated.document.into_profile().unwrap();
        assert!(!profile.enabled);
        assert_eq!(
            profile.workspace_mode,
            pl_protocol::AgentWorkspaceMode::Worktree
        );
        let AgentBinding::Native(native) = profile.binding else {
            panic!("V1 must migrate to Native");
        };
        assert_eq!(native.system_instructions.as_deref(), Some("instructions"));
        let route = native.route.expect("V1 Native route");
        assert_eq!(route.account_id, "account");
        assert_eq!(route.model_id, "model");
        assert_eq!(route.effort.as_deref(), Some("high"));
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
