use super::super::StudioRuntime;
use anyhow::Result;
use pl_model::config::AccountId;
use pl_protocol::studio::*;
use url::Url;

use crate::account_usage::account_usage_query_kind;

pub(super) fn read(
    runtime: &StudioRuntime,
    target: &AccountObservationTarget,
) -> Result<AccountDomainFrame> {
    match target {
        AccountObservationTarget::Summaries => {
            runtime
                .config_runtime
                .with_account_projection(|config, _| {
                    let mut accounts = Vec::with_capacity(config.config.models.accounts.len());
                    let desired = config.canonical_config();
                    let account_catalog = desired
                        .models
                        .accounts
                        .values()
                        .any(|account| account.template_id().is_some())
                        .then(pl_model::config::builtin_account_catalog)
                        .transpose()?;
                    let default = desired
                        .mode_model_routes
                        .get(&pl_protocol::ThreadModeId::simple())
                        .map(|route| &route.account_id);
                    for (id, account) in &desired.models.accounts {
                        let usage = account_usage_query_kind(
                            crate::config_editor::account_template_kind(account)?,
                        )
                        .is_some();
                        accounts.push(AccountSummary {
                            identity: AccountIdentity::Native {
                                account_id: id.to_string(),
                            },
                            name: account.name.clone(),
                            display_endpoint: display_endpoint(&account.base_url),
                            brand_key: account.template_id().and_then(|template_id| {
                                account_catalog
                                    .as_ref()?
                                    .templates
                                    .iter()
                                    .find(|template| template.id == *template_id)?
                                    .icon_key
                                    .clone()
                            }),
                            is_default: default == Some(id),
                            billing_kind: Some(account.billing_kind()?),
                            billing_kind_override: account.billing_kind,
                            credential_ready: Some(
                                account.protocol
                                    == pl_model::protocol::ProtocolKind::OpenAiCompatible
                                    || account.resolved_bearer_token().is_some(),
                            ),
                            usage_query_revision: config.usage_query_revision(id),
                            acp_connection_revision: None,
                            capabilities: AccountCapabilities {
                                set_default: true,
                                edit: true,
                                remove: true,
                                query_usage: usage,
                                sync_models: account.discovery_profile()?.is_some(),
                                edit_models: true,
                                acp_auth: false,
                            },
                        });
                    }
                    for account in runtime.acp_auth.settings_view(config.revision, desired)? {
                        accounts.push(AccountSummary {
                            identity: AccountIdentity::Acp {
                                account_id: account.account_id,
                            },
                            name: account.name,
                            display_endpoint: None,
                            brand_key: Some(account.provider.as_str().to_owned()),
                            is_default: false,
                            billing_kind: None,
                            billing_kind_override: None,
                            credential_ready: None,
                            usage_query_revision: None,
                            acp_connection_revision: Some(account.connection_revision),
                            capabilities: AccountCapabilities {
                                set_default: false,
                                edit: true,
                                remove: true,
                                query_usage: false,
                                sync_models: false,
                                edit_models: false,
                                acp_auth: true,
                            },
                        });
                    }
                    Ok(AccountDomainFrame::Summaries {
                        stamp: runtime.resource_stamp("settings", config.revision),
                        accounts,
                    })
                })?
        }
        AccountObservationTarget::Detail { identity } => runtime
            .config_runtime
            .with_account_projection(|config, _| {
                let account = match identity {
                    AccountIdentity::Native { account_id } => {
                        let id = AccountId::new(account_id)?;
                        config
                            .canonical_config()
                            .models
                            .accounts
                            .get(&id)
                            .map(|account| {
                                super::super::settings_api::account_settings(config, &id, account)
                                    .map(Box::new)
                                    .map(AccountDetail::Native)
                            })
                            .transpose()?
                    }
                    AccountIdentity::Acp { account_id } => runtime
                        .acp_auth
                        .settings_view(config.revision, config.canonical_config())?
                        .into_iter()
                        .find(|account| &account.account_id == account_id)
                        .map(AccountDetail::Acp),
                };
                Ok(AccountDomainFrame::Detail {
                    stamp: runtime.resource_stamp("settings", config.revision),
                    identity: identity.clone(),
                    account,
                })
            })?,
        AccountObservationTarget::Models { account_id } => {
            let id = AccountId::new(account_id)?;
            runtime
                .config_runtime
                .with_account_projection(|config, catalog| {
                    let value = config
                        .config
                        .models
                        .accounts
                        .get(&id)
                        .map(|account| {
                            let status = catalog.catalogs.get(&id).cloned().ok_or_else(|| {
                                anyhow::anyhow!("account catalog status is missing")
                            })?;
                            Ok::<_, anyhow::Error>(StudioAccountModelCatalog {
                                account_id: account_id.clone(),
                                effective_models: account
                                    .effective_catalog(None)?
                                    .iter()
                                    .map(pl_model::config::model_descriptor)
                                    .collect(),
                                model_catalog: status,
                            })
                        })
                        .transpose()?;
                    Ok(AccountDomainFrame::Models {
                        stamp: runtime.resource_stamp("model-catalog", catalog.revision),
                        account_id: account_id.clone(),
                        catalog: value,
                    })
                })?
        }
        AccountObservationTarget::Usage => {
            let (revision, accounts) = runtime.account_usage.observations();
            Ok(AccountDomainFrame::Usage {
                stamp: runtime.resource_stamp("account-usage", revision),
                accounts,
            })
        }
        AccountObservationTarget::AcpAuth => {
            let snapshot = runtime.acp_auth.read_state();
            Ok(AccountDomainFrame::AcpAuth {
                stamp: runtime.resource_stamp("acp-auth", snapshot.revision),
                snapshot,
            })
        }
        AccountObservationTarget::AcpInstall => {
            let snapshot = runtime.acp_install.read_state();
            Ok(AccountDomainFrame::AcpInstall {
                stamp: runtime.resource_stamp("acp-install", snapshot.revision),
                snapshot,
            })
        }
    }
}

fn display_endpoint(base_url: &str) -> Option<String> {
    let parsed = Url::parse(base_url).ok()?;
    if !parsed.has_host() {
        return None;
    }
    let origin = parsed.origin();
    origin.is_tuple().then(|| origin.ascii_serialization())
}
