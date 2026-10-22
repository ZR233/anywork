//! 机器人凭据的窄能力：精确版本选择、独立系统/lease 来源与安全错误。
//!
//! 配置基础设施持有系统凭据 backend 与进程 lease；机器人事务/恢复仍由 bot owner 负责。

use super::credential::{
    BotCredentialIoError, BotCredentialIoKind, BotProtectedPersist, BotProtectedRead,
    CredentialStore,
};
use pl_protocol::studio::BotCredentialAvailability;
use serde::{Deserialize, Serialize};
use std::sync::Arc;

const BOT_PAYLOAD_SCHEMA: u32 = 1;
const MAX_BOT_VERSIONS: usize = 8;

#[derive(Clone)]
pub(crate) struct BotCredentialCapability {
    store: Arc<dyn CredentialStore>,
}

impl BotCredentialCapability {
    pub(super) fn new(store: Arc<dyn CredentialStore>) -> Self {
        Self { store }
    }

    pub(crate) fn inspect_selected(
        &self,
        bot_id: &str,
        app_id: &str,
        selected: Option<&BotCredentialRef>,
    ) -> Result<SelectedBotCredential, BotCredentialIoError> {
        let Some(selected) = selected else {
            return Ok(SelectedBotCredential {
                availability: BotCredentialAvailability::Missing,
                secret: None,
            });
        };
        match selected.kind {
            BotCredentialRefKind::Session => {
                let lease = self.store.read_bot_lease(bot_id)?;
                decode_optional(
                    lease.as_deref(),
                    bot_id,
                    app_id,
                    selected,
                    BotCredentialAvailability::SessionOnly,
                )
            }
            BotCredentialRefKind::System => match self.store.read_bot_system(bot_id) {
                Ok(BotProtectedRead::System(raw)) => decode_selected(
                    &raw,
                    bot_id,
                    app_id,
                    selected,
                    BotCredentialAvailability::Stored,
                ),
                Ok(BotProtectedRead::Missing) => {
                    let lease = self.store.read_bot_lease(bot_id)?;
                    decode_optional(
                        lease.as_deref(),
                        bot_id,
                        app_id,
                        selected,
                        BotCredentialAvailability::SessionOnly,
                    )
                }
                Err(error) if error.kind == BotCredentialIoKind::Unavailable => {
                    let lease = match self.store.read_bot_lease(bot_id) {
                        Ok(lease) => lease,
                        Err(lease_error) if lease_error.kind == BotCredentialIoKind::Missing => {
                            None
                        }
                        Err(lease_error) => return Err(lease_error),
                    };
                    match decode_optional(
                        lease.as_deref(),
                        bot_id,
                        app_id,
                        selected,
                        BotCredentialAvailability::SessionOnly,
                    )? {
                        selected @ SelectedBotCredential {
                            availability: BotCredentialAvailability::SessionOnly,
                            secret: Some(_),
                        } => Ok(selected),
                        _ => Ok(SelectedBotCredential {
                            availability: BotCredentialAvailability::Unavailable,
                            secret: None,
                        }),
                    }
                }
                Err(error) => Err(error),
            },
        }
    }

    pub(crate) fn persist_system(
        &self,
        bot_id: &str,
        payload: &BotProtectedPayload,
    ) -> Result<BotProtectedPersist, BotCredentialIoError> {
        let encoded = encode_bot_payload(payload)?;
        self.store.persist_bot_protected(bot_id, &encoded)
    }

    pub(crate) fn persist_lease(
        &self,
        bot_id: &str,
        payload: &BotProtectedPayload,
    ) -> Result<(), BotCredentialIoError> {
        let encoded = encode_bot_payload(payload)?;
        self.store.lease_bot_protected(bot_id, &encoded)
    }

    pub(crate) fn load_system_payload(
        &self,
        bot_id: &str,
    ) -> Result<Option<BotProtectedPayload>, BotCredentialIoError> {
        match self.store.read_bot_system(bot_id)? {
            BotProtectedRead::System(raw) => Ok(Some(decode_bot_payload(&raw)?)),
            BotProtectedRead::Missing => Ok(None),
        }
    }

    pub(crate) fn load_lease_payload(
        &self,
        bot_id: &str,
    ) -> Result<Option<BotProtectedPayload>, BotCredentialIoError> {
        match self.store.read_bot_lease(bot_id)? {
            Some(raw) => Ok(Some(decode_bot_payload(&raw)?)),
            None => Ok(None),
        }
    }

    pub(crate) fn read_system(
        &self,
        bot_id: &str,
    ) -> Result<BotProtectedRead, BotCredentialIoError> {
        self.store.read_bot_system(bot_id)
    }

    pub(crate) fn read_lease(&self, bot_id: &str) -> Result<Option<String>, BotCredentialIoError> {
        self.store.read_bot_lease(bot_id)
    }

    pub(crate) fn recycle_system(&self, bot_id: &str) -> Result<(), BotCredentialIoError> {
        self.store.recycle_bot_system(bot_id)
    }

    pub(crate) fn recycle_lease(&self, bot_id: &str) -> Result<(), BotCredentialIoError> {
        self.store.recycle_bot_lease(bot_id)
    }

    #[cfg(test)]
    pub(crate) fn persist_system_raw(
        &self,
        bot_id: &str,
        raw: &str,
    ) -> Result<BotProtectedPersist, BotCredentialIoError> {
        self.store.persist_bot_protected(bot_id, raw)
    }

    #[cfg(test)]
    pub(crate) fn lease_raw(&self, bot_id: &str, raw: &str) -> Result<(), BotCredentialIoError> {
        self.store.lease_bot_protected(bot_id, raw)
    }
}

#[derive(Clone, PartialEq, Eq)]
pub(crate) struct SelectedBotCredential {
    pub availability: BotCredentialAvailability,
    pub secret: Option<String>,
}

impl std::fmt::Debug for SelectedBotCredential {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("SelectedBotCredential")
            .field("availability", &self.availability)
            .field("secret", &self.secret.as_ref().map(|_| "<redacted>"))
            .finish()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) enum BotCredentialRefKind {
    System,
    Session,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct BotCredentialRef {
    pub kind: BotCredentialRefKind,
    pub version: String,
}

impl BotCredentialRef {
    pub(crate) fn system(version: impl Into<String>) -> Self {
        Self {
            kind: BotCredentialRefKind::System,
            version: version.into(),
        }
    }

    pub(crate) fn session(version: impl Into<String>) -> Self {
        Self {
            kind: BotCredentialRefKind::Session,
            version: version.into(),
        }
    }
}

#[derive(Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(crate) struct BotProtectedPayload {
    pub schema_version: u32,
    pub versions: Vec<BotSecretVersion>,
}

impl std::fmt::Debug for BotProtectedPayload {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("BotProtectedPayload")
            .field("schema_version", &self.schema_version)
            .field("versions", &self.versions)
            .finish()
    }
}

impl Default for BotProtectedPayload {
    fn default() -> Self {
        Self {
            schema_version: BOT_PAYLOAD_SCHEMA,
            versions: Vec::new(),
        }
    }
}

impl BotProtectedPayload {
    pub(crate) fn version(&self, selected: &BotCredentialRef) -> Option<&BotSecretVersion> {
        self.versions
            .iter()
            .find(|version| version.id == selected.version)
    }

    pub(crate) fn upsert(&mut self, version: BotSecretVersion) -> Result<(), BotCredentialIoError> {
        if let Some(existing) = self.versions.iter_mut().find(|item| item.id == version.id) {
            *existing = version;
            return Ok(());
        }
        if self.versions.len() >= MAX_BOT_VERSIONS {
            return Err(BotCredentialIoError {
                kind: BotCredentialIoKind::Invalid,
            });
        }
        self.versions.push(version);
        Ok(())
    }

    pub(crate) fn retain_referenced(&mut self, keep: &[String]) {
        self.versions
            .retain(|version| keep.iter().any(|id| id == &version.id));
    }
}

#[derive(Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(crate) struct BotSecretVersion {
    pub id: String,
    pub bot_id: String,
    pub app_id: String,
    pub secret: String,
}

impl std::fmt::Debug for BotSecretVersion {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("BotSecretVersion")
            .field("id", &self.id)
            .field("bot_id", &self.bot_id)
            .field("app_id", &self.app_id)
            .field("secret", &"<redacted>")
            .finish()
    }
}

impl BotSecretVersion {
    pub(crate) fn matches(&self, bot_id: &str, app_id: &str, selected: &BotCredentialRef) -> bool {
        self.id == selected.version && self.bot_id == bot_id && self.app_id == app_id
    }
}

fn decode_optional(
    raw: Option<&str>,
    bot_id: &str,
    app_id: &str,
    selected: &BotCredentialRef,
    availability: BotCredentialAvailability,
) -> Result<SelectedBotCredential, BotCredentialIoError> {
    let Some(raw) = raw else {
        return Ok(SelectedBotCredential {
            availability: BotCredentialAvailability::Missing,
            secret: None,
        });
    };
    decode_selected(raw, bot_id, app_id, selected, availability)
}

fn decode_selected(
    raw: &str,
    bot_id: &str,
    app_id: &str,
    selected: &BotCredentialRef,
    availability: BotCredentialAvailability,
) -> Result<SelectedBotCredential, BotCredentialIoError> {
    let payload = decode_bot_payload(raw)?;
    let Some(version) = payload.version(selected) else {
        return Ok(SelectedBotCredential {
            availability: BotCredentialAvailability::Missing,
            secret: None,
        });
    };
    if !version.matches(bot_id, app_id, selected) {
        return Err(BotCredentialIoError {
            kind: BotCredentialIoKind::Invalid,
        });
    }
    Ok(SelectedBotCredential {
        availability,
        secret: Some(version.secret.clone()),
    })
}

fn decode_bot_payload(raw: &str) -> Result<BotProtectedPayload, BotCredentialIoError> {
    let payload: BotProtectedPayload =
        serde_json::from_str(raw).map_err(|_| BotCredentialIoError {
            kind: BotCredentialIoKind::Invalid,
        })?;
    if payload.schema_version != BOT_PAYLOAD_SCHEMA {
        return Err(BotCredentialIoError {
            kind: BotCredentialIoKind::Invalid,
        });
    }
    Ok(payload)
}

pub(crate) fn try_decode_current_payload(raw: &str) -> Option<BotProtectedPayload> {
    decode_bot_payload(raw).ok()
}

fn encode_bot_payload(payload: &BotProtectedPayload) -> Result<String, BotCredentialIoError> {
    serde_json::to_string(payload).map_err(|_| BotCredentialIoError {
        kind: BotCredentialIoKind::Invalid,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::credential::MemoryCredentialStore;

    #[test]
    fn inspect_none_ref_does_not_revive_legacy_system_value() {
        let store = MemoryCredentialStore::default();
        store
            .persist_bot_protected(
                "bot-a",
                &encode_bot_payload(&BotProtectedPayload {
                    schema_version: BOT_PAYLOAD_SCHEMA,
                    versions: vec![BotSecretVersion {
                        id: "v1".into(),
                        bot_id: "bot-a".into(),
                        app_id: "cli_old".into(),
                        secret: "legacy".into(),
                    }],
                })
                .unwrap(),
            )
            .unwrap();
        let capability = BotCredentialCapability::new(std::sync::Arc::new(store));
        let selected = capability
            .inspect_selected("bot-a", "cli_old", None)
            .unwrap();
        assert_eq!(selected.availability, BotCredentialAvailability::Missing);
        assert!(selected.secret.is_none());
    }

    #[test]
    fn stored_requires_system_payload_and_matching_version() {
        let store = MemoryCredentialStore::default();
        let payload = BotProtectedPayload {
            schema_version: BOT_PAYLOAD_SCHEMA,
            versions: vec![BotSecretVersion {
                id: "v1".into(),
                bot_id: "bot-a".into(),
                app_id: "cli_a".into(),
                secret: "secret-a".into(),
            }],
        };
        store
            .persist_bot_protected("bot-a", &encode_bot_payload(&payload).unwrap())
            .unwrap();
        let capability = BotCredentialCapability::new(std::sync::Arc::new(store));
        let selected = capability
            .inspect_selected("bot-a", "cli_a", Some(&BotCredentialRef::system("v1")))
            .unwrap();
        assert_eq!(selected.availability, BotCredentialAvailability::Stored);
        assert_eq!(selected.secret.as_deref(), Some("secret-a"));
    }

    #[test]
    fn session_ref_reads_lease_even_when_system_has_another_version() {
        let store = MemoryCredentialStore::default();
        store
            .persist_bot_protected(
                "bot-a",
                &encode_bot_payload(&BotProtectedPayload {
                    schema_version: BOT_PAYLOAD_SCHEMA,
                    versions: vec![BotSecretVersion {
                        id: "sys".into(),
                        bot_id: "bot-a".into(),
                        app_id: "cli_a".into(),
                        secret: "system-secret".into(),
                    }],
                })
                .unwrap(),
            )
            .unwrap();
        store
            .lease_bot_protected(
                "bot-a",
                &encode_bot_payload(&BotProtectedPayload {
                    schema_version: BOT_PAYLOAD_SCHEMA,
                    versions: vec![BotSecretVersion {
                        id: "lease".into(),
                        bot_id: "bot-a".into(),
                        app_id: "cli_a".into(),
                        secret: "lease-secret".into(),
                    }],
                })
                .unwrap(),
            )
            .unwrap();
        let capability = BotCredentialCapability::new(std::sync::Arc::new(store));
        let selected = capability
            .inspect_selected("bot-a", "cli_a", Some(&BotCredentialRef::session("lease")))
            .unwrap();
        assert_eq!(
            selected.availability,
            BotCredentialAvailability::SessionOnly
        );
        assert_eq!(selected.secret.as_deref(), Some("lease-secret"));
    }

    #[test]
    fn system_unavailable_without_matching_lease_is_unavailable() {
        crate::config::memory_faults::reset();
        crate::config::memory_faults::set_system_unavailable(true);
        let store = MemoryCredentialStore::default();
        store
            .persist_bot_protected(
                "bot-a",
                &encode_bot_payload(&BotProtectedPayload {
                    schema_version: BOT_PAYLOAD_SCHEMA,
                    versions: vec![BotSecretVersion {
                        id: "v1".into(),
                        bot_id: "bot-a".into(),
                        app_id: "cli_a".into(),
                        secret: "secret-a".into(),
                    }],
                })
                .unwrap(),
            )
            .unwrap();
        let capability = BotCredentialCapability::new(std::sync::Arc::new(store));
        let selected = capability
            .inspect_selected("bot-a", "cli_a", Some(&BotCredentialRef::system("v1")))
            .unwrap();
        crate::config::memory_faults::reset();
        assert_eq!(
            selected.availability,
            BotCredentialAvailability::Unavailable
        );
        assert!(selected.secret.is_none());
    }
}
