//! Canonical login owner; unsuccessful or discarded attempts never become saved accounts.
use super::StudioRuntime;
use anyhow::Result;
use pl_model::protocol::chatgpt::{
    ChatGptAuthError, ChatGptAuthorization, ChatGptCredentialRecord,
};
use pl_protocol::studio::*;
use std::{
    collections::BTreeMap,
    sync::{Arc, Mutex},
};
use tokio::sync::watch;
use tokio_util::sync::CancellationToken;

#[derive(Clone)]
pub(crate) struct ChatGptAuthRuntime {
    inner: Arc<Mutex<Registry>>,
    updates: watch::Sender<()>,
}

#[derive(Default)]
struct Registry {
    closing: bool,
    operations: BTreeMap<String, Operation>,
}

struct Operation {
    account_revision: Option<u64>,
    snapshot: ChatGptLoginSnapshot,
    record: Option<ChatGptCredentialRecord>,
    claimed: bool,
    cancellation: CancellationToken,
    done: watch::Receiver<bool>,
    task: Option<tokio::task::JoinHandle<()>>,
}

pub(super) struct LoginClaim {
    pub(super) record: ChatGptCredentialRecord,
    pub(super) account_revision: Option<u64>,
}

impl ChatGptAuthRuntime {
    pub(crate) fn new() -> Self {
        Self {
            inner: Arc::new(Mutex::new(Registry::default())),
            updates: watch::channel(()).0,
        }
    }

    pub(crate) fn subscribe(&self) -> watch::Receiver<()> {
        self.updates.subscribe()
    }

    pub(crate) fn read(&self, login_id: &str) -> Result<ChatGptLoginSnapshot> {
        let registry = self
            .inner
            .lock()
            .map_err(|_| StudioError::invalid_argument("Login owner is unavailable"))?;
        registry
            .operations
            .get(login_id)
            .map(|operation| operation.snapshot.clone())
            .ok_or_else(|| StudioError::invalid_argument("Unknown ChatGPT login").into())
    }

    /// The mutex spans the synchronous CAS/credential transaction, so cancel cannot race a
    /// successful save. A failed transaction leaves the original result eligible for explicit retry.
    pub(crate) fn with_claim<T>(
        &self,
        intent: &AccountAuthenticationIntent,
        account_id: &str,
        save: impl FnOnce(Option<LoginClaim>) -> Result<T>,
    ) -> Result<T> {
        let mut registry = self
            .inner
            .lock()
            .map_err(|_| StudioError::invalid_argument("Login owner is unavailable"))?;
        let selected = match intent {
            AccountAuthenticationIntent::ChatGpt {
                login_id,
                editor_id,
            } => {
                let operation = registry
                    .operations
                    .get_mut(login_id)
                    .ok_or_else(|| StudioError::invalid_argument("Unknown ChatGPT login"))?;
                if operation.snapshot.editor_id != *editor_id
                    || operation.snapshot.account_id != account_id
                    || operation.snapshot.phase != ChatGptLoginPhase::Succeeded
                    || operation.claimed
                    || operation.cancellation.is_cancelled()
                    || operation
                        .snapshot
                        .expires_at
                        .is_some_and(|expiry| expiry <= crate::studio::unix_seconds())
                {
                    return Err(StudioError::invalid_argument(
                        "ChatGPT login is not eligible for this save",
                    )
                    .into());
                }
                Some(LoginClaim {
                    record: operation.record.clone().ok_or_else(|| {
                        StudioError::invalid_argument("ChatGPT login has no credentials")
                    })?,
                    account_revision: operation.account_revision,
                })
            }
            _ => None,
        };
        let result = save(selected)?;
        if let AccountAuthenticationIntent::ChatGpt { login_id, .. } = intent {
            let operation = registry
                .operations
                .get_mut(login_id)
                .expect("claim lock retains operation");
            operation.claimed = true;
            operation.record = None;
        } else if matches!(intent, AccountAuthenticationIntent::ApiKey) {
            for operation in registry
                .operations
                .values_mut()
                .filter(|operation| operation.snapshot.account_id == account_id)
            {
                operation.cancellation.cancel();
                operation.record = None;
                operation.claimed = true;
            }
        }
        Ok(result)
    }

    pub(crate) fn signal_cancel(&self) {
        let mut registry = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        registry.closing = true;
        for operation in registry.operations.values_mut() {
            operation.cancellation.cancel();
            operation.record = None;
        }
    }

    pub(crate) async fn close(&self) -> Result<()> {
        self.signal_cancel();
        let ids = self
            .inner
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .operations
            .keys()
            .cloned()
            .collect::<Vec<_>>();
        for id in ids {
            self.join(&id).await?;
        }
        Ok(())
    }

    pub(super) async fn discard_account(&self, account_id: &str) -> Result<()> {
        let ids = {
            let mut registry = self
                .inner
                .lock()
                .map_err(|_| StudioError::invalid_argument("Login owner is unavailable"))?;
            registry
                .operations
                .iter_mut()
                .filter_map(|(id, operation)| {
                    if operation.snapshot.account_id != account_id {
                        return None;
                    }
                    operation.cancellation.cancel();
                    operation.record = None;
                    operation.claimed = true;
                    Some(id.clone())
                })
                .collect::<Vec<_>>()
        };
        for id in ids {
            self.join(&id).await?;
        }
        Ok(())
    }

    async fn join(&self, id: &str) -> Result<()> {
        let mut done = self
            .inner
            .lock()
            .map_err(|_| StudioError::invalid_argument("Login owner is unavailable"))?
            .operations
            .get(id)
            .ok_or_else(|| StudioError::invalid_argument("Unknown ChatGPT login"))?
            .done
            .clone();
        while !*done.borrow_and_update() {
            done.changed().await.map_err(|_| {
                StudioError::invalid_argument("ChatGPT login worker stopped unexpectedly")
            })?;
        }
        let task = self
            .inner
            .lock()
            .map_err(|_| StudioError::invalid_argument("Login owner is unavailable"))?
            .operations
            .get_mut(id)
            .and_then(|operation| operation.task.take());
        if let Some(task) = task {
            task.await
                .map_err(|_| StudioError::invalid_argument("ChatGPT login worker failed"))?;
        }
        Ok(())
    }

    fn publish(&self, id: &str, phase: ChatGptLoginPhase, url: Option<String>) {
        let mut registry = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        if let Some(operation) = registry.operations.get_mut(id)
            && !operation.cancellation.is_cancelled()
        {
            operation.snapshot.revision += 1;
            operation.snapshot.phase = phase;
            operation.snapshot.authorization_url = url;
            self.updates.send_replace(());
        }
    }

    async fn worker(
        &self,
        id: String,
        config: crate::config::ConfigRuntime,
        previous: Option<(ChatGptAccountInfo, String)>,
        cancel: CancellationToken,
    ) {
        let result = tokio::select! {
            biased;
            _ = cancel.cancelled() => None,
            result = async {
                let (host, previous) = match previous {
                    Some((info, host)) => (host, Some(info)),
                    None => (config.chatgpt_host_id().map_err(|_| ChatGptAuthError::Storage)?, None),
                };
                let authorization = ChatGptAuthorization::prepare(host, previous).await?;
                self.publish(&id, ChatGptLoginPhase::AwaitingBrowser, Some(authorization.authorization_url().to_owned()));
                // finish owns listener and all network futures; dropping on cancellation
                // synchronously releases them before a terminal snapshot is published.
                authorization.finish_with_progress(|| self.publish(&id, ChatGptLoginPhase::ExchangingCode, None)).await
            } => Some(result),
        };
        let mut registry = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        if let Some(operation) = registry.operations.get_mut(&id) {
            operation.snapshot.revision += 1;
            operation.snapshot.authorization_url = None;
            let result = if operation.cancellation.is_cancelled() {
                None
            } else {
                result
            };
            match result {
                None => {
                    operation.snapshot.phase = ChatGptLoginPhase::Cancelled;
                    operation.record = None;
                }
                Some(Ok(record)) => {
                    operation.snapshot.phase = ChatGptLoginPhase::Succeeded;
                    operation.snapshot.account = Some(record.account.clone());
                    operation.record = Some(record);
                }
                Some(Err(error)) => {
                    operation.snapshot.phase = ChatGptLoginPhase::Failed;
                    operation.snapshot.failure = Some(ChatGptLoginFailure {
                        code: failure(error),
                        retryable: false,
                    });
                }
            }
            self.updates.send_replace(());
        }
    }
}

fn failure(error: ChatGptAuthError) -> ChatGptLoginFailureCode {
    match error {
        ChatGptAuthError::Network => ChatGptLoginFailureCode::Network,
        ChatGptAuthError::AuthorizationDenied => ChatGptLoginFailureCode::AuthorizationDenied,
        ChatGptAuthError::InvalidCallback => ChatGptLoginFailureCode::InvalidCallback,
        ChatGptAuthError::InvalidIdentity
        | ChatGptAuthError::Revoked
        | ChatGptAuthError::ReauthorizationRequired
        | ChatGptAuthError::UnsupportedResource => ChatGptLoginFailureCode::InvalidIdentity,
        ChatGptAuthError::MissingPlanPermission => ChatGptLoginFailureCode::MissingPlanPermission,
        ChatGptAuthError::Expired => ChatGptLoginFailureCode::Expired,
        ChatGptAuthError::Storage | ChatGptAuthError::RecoveryRequired => {
            ChatGptLoginFailureCode::Storage
        }
    }
}

impl StudioRuntime {
    pub async fn start_chatgpt_login(
        &self,
        input: StartChatGptLoginRequest,
    ) -> Result<ChatGptLoginCommandReply> {
        for id in [&input.login_id, &input.editor_id, &input.account_id] {
            Self::validate_operation_id(id)?;
        }
        let identity = AccountIdentity::Native {
            account_id: input.account_id.clone(),
        };
        let account_revision = self
            .config_runtime
            .account_configuration_revision(&identity)?;
        let current = self.config_runtime.read()?;
        if self
            .config_runtime
            .account_configuration_revision(&identity)?
            != account_revision
        {
            return Err(StudioError::invalid_argument(
                "Account changed while starting ChatGPT login",
            )
            .into());
        }
        let id = pl_model::config::AccountId::new(&input.account_id)?;
        let previous = current
            .config
            .models
            .accounts
            .get(&id)
            .filter(|account| account.authentication == AccountAuthenticationMethod::ChatGpt)
            .map(|account| {
                let info = account.chatgpt_account.clone().ok_or_else(|| {
                    StudioError::invalid_argument("ChatGPT registration identity is missing")
                })?;
                let record = account.chatgpt_credentials.as_ref().ok_or_else(|| {
                    StudioError::invalid_argument("ChatGPT registration credentials are missing")
                })?;
                // The keyring registration can be shared by configuration homes. Reauthorization
                // keeps that registration's original host ID, rather than issuing a new host hint.
                Ok::<_, anyhow::Error>((info, record.ext_agent_host_id.clone()))
            })
            .transpose()?;
        let mut registry = self
            .chatgpt_auth
            .inner
            .lock()
            .map_err(|_| StudioError::invalid_argument("Login owner is unavailable"))?;
        if let Some(operation) = registry.operations.get(&input.login_id) {
            if operation.snapshot.editor_id != input.editor_id
                || operation.snapshot.account_id != input.account_id
            {
                return Err(StudioError::invalid_argument(
                    "Login ID belongs to another editor/account",
                )
                .into());
            }
            let snapshot = operation.snapshot.clone();
            return Ok(ChatGptLoginCommandReply {
                stamp: self.resource_stamp(
                    format!("chatgpt-login:{}", input.login_id),
                    snapshot.revision,
                ),
                snapshot,
            });
        }
        if registry.closing || registry.operations.len() >= 4096 {
            return Err(StudioError::invalid_argument("ChatGPT login admission is closed").into());
        }
        if registry
            .operations
            .values()
            .filter(|operation| !*operation.done.borrow())
            .count()
            >= 16
        {
            return Err(StudioError::invalid_argument("Too many active ChatGPT logins").into());
        }
        if registry.operations.values().any(|operation| {
            operation.snapshot.editor_id == input.editor_id && !*operation.done.borrow()
        }) {
            return Err(StudioError::invalid_argument(
                "Editor already has an active ChatGPT login",
            )
            .into());
        }
        // A new intent invalidates all unclaimed results of this editor.
        for operation in registry
            .operations
            .values_mut()
            .filter(|operation| operation.snapshot.editor_id == input.editor_id)
        {
            operation.record = None;
            operation.claimed = true;
        }
        let cancellation = CancellationToken::new();
        let (done, receiver) = watch::channel(false);
        let snapshot = ChatGptLoginSnapshot {
            login_id: input.login_id.clone(),
            editor_id: input.editor_id,
            account_id: input.account_id,
            revision: 1,
            phase: ChatGptLoginPhase::Preparing,
            authorization_url: None,
            expires_at: Some(crate::studio::unix_seconds() + 15 * 60),
            account: None,
            failure: None,
        };
        let owner = self.chatgpt_auth.clone();
        let config = self.config_runtime.clone();
        let login_id = input.login_id.clone();
        let cancel = cancellation.clone();
        let task = tokio::spawn(async move {
            use futures::FutureExt;
            if std::panic::AssertUnwindSafe(owner.worker(
                login_id.clone(),
                config,
                previous,
                cancel,
            ))
            .catch_unwind()
            .await
            .is_err()
            {
                let mut registry = owner
                    .inner
                    .lock()
                    .unwrap_or_else(|error| error.into_inner());
                if let Some(operation) = registry.operations.get_mut(&login_id) {
                    operation.snapshot.revision += 1;
                    operation.snapshot.phase = ChatGptLoginPhase::Failed;
                    operation.snapshot.authorization_url = None;
                    operation.snapshot.failure = Some(ChatGptLoginFailure {
                        code: ChatGptLoginFailureCode::TaskFailed,
                        retryable: false,
                    });
                    operation.record = None;
                    owner.updates.send_replace(());
                }
            }
            done.send_replace(true);
        });
        registry.operations.insert(
            input.login_id.clone(),
            Operation {
                account_revision,
                snapshot: snapshot.clone(),
                record: None,
                claimed: false,
                cancellation,
                done: receiver,
                task: Some(task),
            },
        );
        self.chatgpt_auth.updates.send_replace(());
        Ok(ChatGptLoginCommandReply {
            stamp: self.resource_stamp(
                format!("chatgpt-login:{}", input.login_id),
                snapshot.revision,
            ),
            snapshot,
        })
    }

    pub async fn cancel_chatgpt_login(
        &self,
        input: CancelChatGptLoginRequest,
    ) -> Result<ChatGptLoginCommandReply> {
        {
            let mut registry = self
                .chatgpt_auth
                .inner
                .lock()
                .map_err(|_| StudioError::invalid_argument("Login owner is unavailable"))?;
            let operation = registry
                .operations
                .get_mut(&input.login_id)
                .ok_or_else(|| StudioError::invalid_argument("Unknown ChatGPT login"))?;
            if operation.snapshot.editor_id != input.editor_id
                || operation.snapshot.account_id != input.account_id
            {
                return Err(StudioError::invalid_argument(
                    "Login ID belongs to another editor/account",
                )
                .into());
            }
            operation.cancellation.cancel();
            operation.record = None;
            operation.claimed = true;
        }
        self.chatgpt_auth.join(&input.login_id).await?;
        let snapshot = {
            let mut registry = self
                .chatgpt_auth
                .inner
                .lock()
                .map_err(|_| StudioError::invalid_argument("Login owner is unavailable"))?;
            let operation = registry
                .operations
                .get_mut(&input.login_id)
                .expect("retained operation");
            if operation.snapshot.phase != ChatGptLoginPhase::Cancelled {
                operation.snapshot.revision += 1;
                operation.snapshot.phase = ChatGptLoginPhase::Cancelled;
                operation.snapshot.authorization_url = None;
                operation.snapshot.account = None;
            }
            operation.snapshot.clone()
        };
        self.chatgpt_auth.updates.send_replace(());
        Ok(ChatGptLoginCommandReply {
            stamp: self.resource_stamp(
                format!("chatgpt-login:{}", input.login_id),
                snapshot.revision,
            ),
            snapshot,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pl_model::config::AccountId;

    fn completed(runtime: &StudioRuntime, login_id: &str, account_id: &str) {
        let account = ChatGptAccountInfo {
            issuer: "https://auth.openai.com".into(),
            subject: "fixture-subject".into(),
            client_id: "fixture-client".into(),
            email: Some("fixture@example.test".into()),
            plan_usage_enabled: true,
        };
        let snapshot = ChatGptLoginSnapshot {
            login_id: login_id.into(),
            editor_id: "fixture-editor".into(),
            account_id: account_id.into(),
            revision: 4,
            phase: ChatGptLoginPhase::Succeeded,
            authorization_url: None,
            expires_at: Some(crate::studio::unix_seconds() + 900),
            account: Some(account.clone()),
            failure: None,
        };
        let record = ChatGptCredentialRecord {
            schema_version: 1,
            registration_id: format!("generation-{login_id}"),
            account,
            ext_agent_host_id: "urn:uuid:00000000-0000-4000-8000-000000000001".into(),
            access_token: "fixture-private-access".into(),
            refresh_token: "fixture-private-refresh".into(),
            id_token: "fixture-private-verified-id".into(),
            scopes: vec!["chatgpt.tokens.use.direct".into()],
            expires_at: crate::studio::unix_seconds() + 3600,
            earliest_refresh_at: None,
            refresh_in_flight: false,
        };
        let account_revision = runtime
            .config_runtime
            .account_configuration_revision(&AccountIdentity::Native {
                account_id: account_id.into(),
            })
            .unwrap();
        runtime
            .chatgpt_auth
            .inner
            .lock()
            .unwrap()
            .operations
            .insert(
                login_id.into(),
                Operation {
                    account_revision,
                    snapshot,
                    record: Some(record),
                    claimed: false,
                    cancellation: CancellationToken::new(),
                    done: watch::channel(true).1,
                    task: None,
                },
            );
    }

    fn patch(
        account_id: &str,
        revision: u64,
        authentication: AccountAuthenticationIntent,
    ) -> PatchAccountRequest {
        PatchAccountRequest {
            operation_id: format!("patch-{revision}"),
            expected_revision: revision,
            account_id: account_id.into(),
            authentication,
            name: AccountTextPatch::Keep,
            base_url: AccountTextPatch::Keep,
            template_id: AccountTextPatch::Keep,
            protocol: AccountTextPatch::Keep,
            secret: AccountSecretUpdate::Preserve,
            custom_models: AccountModelsPatch::Keep,
        }
    }

    #[tokio::test]
    async fn chatgpt_login_cancellation_and_account_save_isolation_use_public_commands()
    -> Result<()> {
        let home = tempfile::tempdir()?;
        let runtime = StudioRuntime::initialize(crate::StudioRuntimeOptions {
            studio_home: Some(home.path().to_owned()),
            host: crate::StudioHostKind::Test,
            ..crate::StudioRuntimeOptions::desktop()
        })
        .await?;
        let request = StartChatGptLoginRequest {
            login_id: "cancel-login".into(),
            editor_id: "cancel-editor".into(),
            account_id: "cancel-account".into(),
        };
        let started = runtime.start_chatgpt_login(request.clone()).await?;
        let observation =
            runtime.open_account_observation(AccountObservationTarget::ChatGptLogin {
                login_id: request.login_id.clone(),
            })?;
        let cancelled = runtime
            .cancel_chatgpt_login(CancelChatGptLoginRequest {
                login_id: request.login_id.clone(),
                editor_id: request.editor_id.clone(),
                account_id: request.account_id.clone(),
            })
            .await?;
        assert_eq!(cancelled.snapshot.phase, ChatGptLoginPhase::Cancelled);
        assert_eq!(started.stamp.resource_key, cancelled.stamp.resource_key);
        assert_eq!(started.stamp.owner_epoch, cancelled.stamp.owner_epoch);
        assert!(cancelled.stamp.revision > started.stamp.revision);
        let frame = observation.next().await?.unwrap();
        assert_eq!(
            frame,
            AccountDomainFrame::ChatGptLogin {
                stamp: cancelled.stamp.clone(),
                snapshot: cancelled.snapshot.clone()
            }
        );
        assert_eq!(runtime.start_chatgpt_login(request).await?, cancelled);
        observation.close().await?;

        let account_id = "chatgpt-fixture-account";
        completed(&runtime, "save-login", account_id);
        let revision = runtime.read_settings()?.config.revision;
        let mut input = AccountSettingsUpdate {
            account_id: account_id.into(),
            authentication: AccountAuthenticationIntent::ChatGpt {
                login_id: "save-login".into(),
                editor_id: "wrong-editor".into(),
            },
            template_id: Some("openai".into()),
            protocol: pl_model::protocol::ProtocolKind::OpenAi.as_str().into(),
            name: "ChatGPT Fixture".into(),
            base_url: "https://api.openai.com/v1".into(),
            secret: AccountSecretUpdate::Preserve,
            initial_billing_kind: Some(pl_protocol::BillingKind::NoCharge),
            custom_models: Vec::new(),
            model_connection_modes: Vec::new(),
            model_auto_compact_limits: Vec::new(),
        };
        assert!(
            runtime
                .create_account(CreateAccountRequest {
                    operation_id: "wrong-save".into(),
                    expected_revision: revision,
                    account: input.clone()
                })
                .await
                .is_err()
        );
        assert!(
            !runtime
                .config_runtime
                .read()?
                .config
                .models
                .accounts
                .contains_key(&AccountId::new(account_id)?)
        );
        input.authentication = AccountAuthenticationIntent::ChatGpt {
            login_id: "save-login".into(),
            editor_id: "fixture-editor".into(),
        };
        // Exercise the real login claim boundary with a real coordinated save that reports
        // failure only after replacing the candidate config. The matching login stays eligible.
        let baseline = runtime.config_runtime.read()?.config;
        let fault_store = crate::config::ConfigStore::new(
            crate::config::ConfigPaths::from_config_dir(home.path().join("fault-save")),
        );
        fault_store.save(&baseline)?;
        let calls = std::cell::Cell::new(0);
        let failed = runtime
            .chatgpt_auth
            .with_claim(&input.authentication, account_id, |claim| {
                let record = claim.unwrap().record;
                let mut candidate = baseline.clone();
                let mut account = pl_model::config::builtin_account_catalog()?
                    .templates
                    .into_iter()
                    .find(|entry| entry.id.as_str() == "openai")
                    .unwrap()
                    .account;
                account.authentication = AccountAuthenticationMethod::ChatGpt;
                account.bearer_token_env = None;
                account.chatgpt_account = Some(record.account.clone());
                account.chatgpt_session = Some(
                    runtime
                        .config_runtime
                        .chatgpt_session(account_id, &record)?,
                );
                account.chatgpt_credentials = Some(record);
                candidate
                    .models
                    .accounts
                    .insert(AccountId::new(account_id)?, account);
                fault_store.commit_config_with(
                    &baseline,
                    &candidate,
                    &crate::config::credential_commit::CredentialIntents::for_account(
                        account_id,
                        &input.authentication,
                    ),
                    &|path, bytes| {
                        pl_tool::workspace::write_file_atomically(path, bytes)?;
                        calls.set(calls.get() + 1);
                        if calls.get() == 1 {
                            return Err(crate::PureError::ConfigError(
                                "injected post-replacement failure".into(),
                            ));
                        }
                        Ok(())
                    },
                )?;
                Ok(())
            });
        assert!(failed.is_err());
        assert_eq!(calls.get(), 2);
        assert!(!runtime.chatgpt_auth.inner.lock().unwrap().operations["save-login"].claimed);
        assert!(
            runtime.chatgpt_auth.inner.lock().unwrap().operations["save-login"]
                .record
                .is_some()
        );
        fault_store.load_for_startup().unwrap();
        runtime
            .create_account(CreateAccountRequest {
                operation_id: "correct-save".into(),
                expected_revision: revision,
                account: input,
            })
            .await?;
        let snapshot = runtime.config_runtime.read()?;
        let account = &snapshot.config.models.accounts[&AccountId::new(account_id)?];
        assert_eq!(account.authentication, AccountAuthenticationMethod::ChatGpt);
        assert_eq!(account.billing_kind()?, pl_protocol::BillingKind::NoCharge);
        assert!(account.bearer_token.is_none());
        let session = account.chatgpt_session.clone().unwrap();
        assert_eq!(session.access_token().await?, "fixture-private-access");
        let wire = serde_json::to_string(&runtime.read_settings()?)?;
        assert!(!wire.contains("fixture-private"));
        assert!(
            runtime
                .patch_account(patch(
                    account_id,
                    snapshot.revision - 1,
                    AccountAuthenticationIntent::ApiKey
                ))
                .await
                .is_err()
        );
        assert_eq!(session.access_token().await?, "fixture-private-access");
        runtime
            .patch_account(patch(
                account_id,
                snapshot.revision,
                AccountAuthenticationIntent::ApiKey,
            ))
            .await?;
        let api = runtime.config_runtime.read()?;
        let account = &api.config.models.accounts[&AccountId::new(account_id)?];
        assert_eq!(account.authentication, AccountAuthenticationMethod::ApiKey);
        assert!(account.bearer_token.is_none());
        assert!(account.chatgpt_account.is_none());
        assert_eq!(session.access_token().await, Err(ChatGptAuthError::Revoked));
        assert!(
            runtime
                .patch_account(patch(
                    account_id,
                    api.revision,
                    AccountAuthenticationIntent::ChatGpt {
                        login_id: "save-login".into(),
                        editor_id: "fixture-editor".into(),
                    }
                ))
                .await
                .is_err()
        );
        completed(&runtime, "second-login", account_id);
        runtime
            .patch_account(patch(
                account_id,
                api.revision,
                AccountAuthenticationIntent::ChatGpt {
                    login_id: "second-login".into(),
                    editor_id: "fixture-editor".into(),
                },
            ))
            .await?;
        let subscribed = runtime.config_runtime.read()?;
        assert_eq!(
            subscribed.config.models.accounts[&AccountId::new(account_id)?].authentication,
            AccountAuthenticationMethod::ChatGpt
        );
        let reauth = StartChatGptLoginRequest {
            login_id: "reauth-login".into(),
            editor_id: "reauth-editor".into(),
            account_id: account_id.into(),
        };
        runtime.start_chatgpt_login(reauth.clone()).await?;
        let observation =
            runtime.open_account_observation(AccountObservationTarget::ChatGptLogin {
                login_id: reauth.login_id.clone(),
            })?;
        let authorization_url = tokio::time::timeout(std::time::Duration::from_secs(5), async {
            loop {
                if let Some(AccountDomainFrame::ChatGptLogin { snapshot, .. }) =
                    observation.next().await?
                    && let Some(url) = snapshot.authorization_url
                {
                    return Ok::<_, anyhow::Error>(url);
                }
            }
        })
        .await??;
        let url = url::Url::parse(&authorization_url)?;
        let params: BTreeMap<_, _> = url.query_pairs().into_owned().collect();
        assert_eq!(params["client_id"], "fixture-client");
        assert_eq!(
            params["ext_agent_host_id"],
            "urn:uuid:00000000-0000-4000-8000-000000000001"
        );
        assert!(!params.contains_key("agent_name_hint"));
        assert!(!params.contains_key("id_token_hint"));
        runtime
            .cancel_chatgpt_login(CancelChatGptLoginRequest {
                login_id: reauth.login_id,
                editor_id: reauth.editor_id,
                account_id: reauth.account_id,
            })
            .await?;
        observation.close().await?;
        runtime.shutdown_runtime().await?;
        Ok(())
    }
}
