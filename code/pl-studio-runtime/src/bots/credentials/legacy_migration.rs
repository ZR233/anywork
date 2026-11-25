//! Original plaintext payload and durable migration-intent recovery.
use super::journal::remove_path;
use super::{io_error, map_io, ref_for_persist};
use crate::bots::config::{BOT_CONFIG_SCHEMA_VERSION, BotConfigFile, save_config};
use crate::bots::protocol::error::{FeishuError, FeishuErrorKind};
use crate::config::{
    BotCredentialCapability, BotCredentialIoKind, BotCredentialRef, BotCredentialRefKind,
    BotProtectedPayload, BotSecretVersion, try_decode_current_payload,
};
use crate::studio::new_id;
use serde::{Deserialize, Serialize};
use std::path::Path;

pub(super) const MIGRATION_INTENT_FILE: &str = "credential-migration.json";
// Credential payload versioning arrived in schema 2; later config upgrades must not
// reinterpret its protected payload as the original plaintext credential format.
pub(super) const VERSIONED_CREDENTIAL_CONFIG_SCHEMA: u32 = 2;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct MigrationIntent {
    schema_version: u32,
    bot_id: String,
    app_id: String,
    version: String,
}

pub(super) fn retry_completed_migration_cleanup(dir: &Path, config: &BotConfigFile) {
    let path = dir.join(MIGRATION_INTENT_FILE);
    match std::fs::read(&path) {
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => tracing::warn!(
            bot_id = %config.id,
            error = %error,
            "bot credential migration intent retained after unreadable leftover"
        ),
        Ok(bytes) => match serde_json::from_slice::<MigrationIntent>(&bytes) {
            Ok(intent)
                if intent.bot_id == config.id
                    && intent.app_id == config.feishu().app_id
                    && config.schema_version >= VERSIONED_CREDENTIAL_CONFIG_SCHEMA =>
            {
                if let Err(error) = remove_path(&path) {
                    tracing::warn!(
                        bot_id = %config.id,
                        error = %error,
                        "bot credential migration intent cleanup failed"
                    );
                }
            }
            Ok(_) | Err(_) => tracing::warn!(
                bot_id = %config.id,
                "bot credential migration intent preserved; identity or schema is unusable"
            ),
        },
    }
}

pub(super) fn migrate_legacy_config(
    dir: &Path,
    credentials: &BotCredentialCapability,
    mut config: BotConfigFile,
) -> Result<BotConfigFile, FeishuError> {
    let intent_path = dir.join(MIGRATION_INTENT_FILE);
    let intent = load_or_write_intent(&intent_path, &config)?;
    if intent.bot_id != config.id || intent.app_id != config.feishu().app_id {
        return Err(FeishuError::new(
            FeishuErrorKind::Protocol,
            "bot credential migration identity does not match config",
            false,
            None,
        ));
    }
    let system = credentials.read_system(&config.id).map_err(map_io)?;
    let lease = credentials.read_lease(&config.id).map_err(map_io)?;
    let selected = migrate_sources(&config, &intent, credentials, system, lease)?;
    config.schema_version = BOT_CONFIG_SCHEMA_VERSION;
    config.selected_ref = selected;
    save_config(&dir.join("config.toml"), &config)?;
    if let Err(error) = remove_path(&intent_path) {
        tracing::warn!(
            bot_id = %config.id,
            error = %error,
            "bot credential migration intent cleanup failed"
        );
    }
    Ok(config)
}

fn migrate_sources(
    config: &BotConfigFile,
    intent: &MigrationIntent,
    credentials: &BotCredentialCapability,
    system: crate::config::BotProtectedRead,
    lease: Option<String>,
) -> Result<Option<BotCredentialRef>, FeishuError> {
    let system_payload = match system {
        crate::config::BotProtectedRead::Missing => None,
        crate::config::BotProtectedRead::System(raw) => Some(classify_legacy_raw(&raw, intent)?),
    };
    let lease_payload = match lease {
        None => None,
        Some(raw) => Some(classify_legacy_raw(&raw, intent)?),
    };
    match (system_payload, lease_payload) {
        (None, None) => Ok(None),
        (Some(LegacyMaterial::Current(payload)), None) if payload_has_intent(&payload, intent) => {
            Ok(Some(BotCredentialRef::system(intent.version.clone())))
        }
        (None, Some(LegacyMaterial::Current(payload))) if payload_has_intent(&payload, intent) => {
            Ok(Some(BotCredentialRef::session(intent.version.clone())))
        }
        (Some(LegacyMaterial::Opaque(secret)), None) => {
            wrap_opaque(credentials, config, intent, &secret, true)
        }
        (None, Some(LegacyMaterial::Opaque(secret))) => {
            wrap_opaque(credentials, config, intent, &secret, false)
        }
        (Some(LegacyMaterial::Current(payload)), Some(LegacyMaterial::Current(_)))
            if payload_has_intent(&payload, intent) =>
        {
            Ok(Some(BotCredentialRef::system(intent.version.clone())))
        }
        _ => Err(FeishuError::new(
            FeishuErrorKind::Protocol,
            "bot credential sources conflict without a selected proof; original association preserved",
            false,
            None,
        )),
    }
}

enum LegacyMaterial {
    Current(BotProtectedPayload),
    Opaque(String),
}

fn payload_has_intent(payload: &BotProtectedPayload, intent: &MigrationIntent) -> bool {
    payload.versions.iter().any(|version| {
        version.id == intent.version
            && version.bot_id == intent.bot_id
            && version.app_id == intent.app_id
    })
}

fn classify_legacy_raw(raw: &str, intent: &MigrationIntent) -> Result<LegacyMaterial, FeishuError> {
    if let Some(payload) = try_decode_current_payload(raw) {
        if payload_has_intent(&payload, intent) {
            Ok(LegacyMaterial::Current(payload))
        } else {
            Err(FeishuError::new(
                FeishuErrorKind::Protocol,
                "bot credential payload does not match migration intent; original association preserved",
                false,
                None,
            ))
        }
    } else {
        Ok(LegacyMaterial::Opaque(raw.to_string()))
    }
}

fn wrap_opaque(
    credentials: &BotCredentialCapability,
    config: &BotConfigFile,
    intent: &MigrationIntent,
    secret: &str,
    prefer_system: bool,
) -> Result<Option<BotCredentialRef>, FeishuError> {
    let mut payload = BotProtectedPayload::default();
    payload
        .upsert(BotSecretVersion {
            id: intent.version.clone(),
            bot_id: config.id.clone(),
            app_id: config.feishu().app_id.clone(),
            secret: secret.to_string(),
        })
        .map_err(map_io)?;
    let persist = if prefer_system {
        match credentials.persist_system(&config.id, &payload) {
            Ok(persist) => persist,
            Err(error) if error.kind == BotCredentialIoKind::Unavailable => credentials
                .upsert_version(
                    &config.id,
                    BotCredentialRefKind::Session,
                    BotSecretVersion {
                        id: intent.version.clone(),
                        bot_id: config.id.clone(),
                        app_id: config.feishu().app_id.clone(),
                        secret: secret.to_string(),
                    },
                )
                .map_err(map_io)?,
            Err(error) => return Err(map_io(error)),
        }
    } else {
        credentials
            .persist_lease(&config.id, &payload)
            .map_err(map_io)?;
        crate::config::BotProtectedPersist::SessionOnly
    };
    Ok(Some(ref_for_persist(persist, intent.version.clone())))
}

fn load_or_write_intent(
    path: &Path,
    config: &BotConfigFile,
) -> Result<MigrationIntent, FeishuError> {
    if path.exists() {
        let text = std::fs::read_to_string(path).map_err(io_error)?;
        return serde_json::from_str(&text).map_err(|_| {
            FeishuError::new(
                FeishuErrorKind::Protocol,
                "unreadable bot credential migration intent; original association preserved",
                false,
                None,
            )
        });
    }
    let intent = MigrationIntent {
        schema_version: 1,
        bot_id: config.id.clone(),
        app_id: config.feishu().app_id.clone(),
        version: new_id("cred"),
    };
    let encoded = serde_json::to_vec_pretty(&intent).map_err(|_| {
        FeishuError::new(
            FeishuErrorKind::Protocol,
            "failed to encode bot credential migration intent",
            false,
            None,
        )
    })?;
    pl_tool::workspace::write_file_atomically(path, &encoded).map_err(io_error)?;
    Ok(intent)
}
