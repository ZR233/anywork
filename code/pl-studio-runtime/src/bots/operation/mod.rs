//! Serial operations on a robot's configuration and credentials.
mod coordinator;
mod diagnostics;
mod executor;

use coordinator::FinalizeOptions;
pub(super) use diagnostics::{BotDiagnosticSet, DiagnosticSlot};
use executor::SerialOperationExecutor;

use crate::bots::config::{validate_app_id, validate_bot_id};
use crate::bots::credentials::{CredentialCommit, has_credential_journal};
use crate::bots::owner::BotRuntime;
use crate::bots::protocol::error::{FeishuError, FeishuErrorKind};
use crate::studio::new_id;
use crate::{BotsCommandReply, SaveBotRequest};
use std::collections::BTreeSet;
use tokio::sync::Mutex;

pub(crate) struct RegistrationSave {
    pub bot_id: String,
    pub name: String,
    pub workspace_id: String,
    pub app_id: String,
    pub secret: String,
    pub trusted_open_id: Option<String>,
    pub operation_id: String,
}

pub(crate) enum BotMutation {
    Save(SaveBotRequest),
    SetEnabled {
        operation_id: String,
        expected_config_revision: u64,
        enabled: bool,
    },
    SetTrustedUser {
        operation_id: String,
        expected_config_revision: u64,
        open_id: String,
        trusted: bool,
    },
    SetTrustedChat {
        operation_id: String,
        expected_config_revision: u64,
        chat_id: String,
        trusted: bool,
    },
    Retry {
        operation_id: String,
    },
}

pub(crate) struct BotOperationOwner {
    bot_id: String,
    runtime: BotRuntime,
    executor: SerialOperationExecutor,
    pairing_cleanup: Mutex<BTreeSet<String>>,
}

impl BotOperationOwner {
    pub(in crate::bots) fn new(runtime: BotRuntime, bot_id: String) -> Self {
        Self {
            bot_id,
            runtime,
            executor: SerialOperationExecutor::default(),
            pairing_cleanup: Mutex::new(BTreeSet::new()),
        }
    }
}

impl BotRuntime {
    pub async fn save_bot(
        &self,
        request: SaveBotRequest,
        owner_epoch: &str,
    ) -> Result<BotsCommandReply, FeishuError> {
        self.reject_if_sealed()?;
        validate_app_id(&request.app_id)?;
        if request.name.trim().is_empty() {
            return Err(FeishuError::new(
                FeishuErrorKind::Rejected,
                "bot name and workspaceId are required",
                false,
                None,
            ));
        }
        let bot_id = match request.bot_id.clone() {
            Some(id) => {
                validate_bot_id(&id)?;
                id
            }
            None => new_id("bot"),
        };
        let mut request = request;
        if request.workspace_id.is_empty() {
            request.workspace_id = match &request.bot_id {
                Some(id) => self
                    .managed(id)
                    .await?
                    .config
                    .lock()
                    .await
                    .workspace_id
                    .clone(),
                None => {
                    self.ensure_workspace_project(&bot_id, &request.name)
                        .await?
                }
            };
        }
        request.bot_id = Some(bot_id.clone());
        self.submit(bot_id, BotMutation::Save(request), owner_epoch)
            .await
    }

    pub async fn set_enabled(
        &self,
        operation_id: String,
        bot_id: String,
        expected_config_revision: u64,
        enabled: bool,
        owner_epoch: &str,
    ) -> Result<BotsCommandReply, FeishuError> {
        self.reject_if_sealed()?;
        self.submit(
            bot_id,
            BotMutation::SetEnabled {
                operation_id,
                expected_config_revision,
                enabled,
            },
            owner_epoch,
        )
        .await
    }

    pub async fn retry_connection(
        &self,
        operation_id: String,
        bot_id: String,
        owner_epoch: &str,
    ) -> Result<BotsCommandReply, FeishuError> {
        self.reject_if_sealed()?;
        self.submit(bot_id, BotMutation::Retry { operation_id }, owner_epoch)
            .await
    }

    pub async fn set_trusted_user(
        &self,
        operation_id: String,
        bot_id: String,
        expected_config_revision: u64,
        open_id: String,
        trusted: bool,
        owner_epoch: &str,
    ) -> Result<BotsCommandReply, FeishuError> {
        self.reject_if_sealed()?;
        self.submit(
            bot_id,
            BotMutation::SetTrustedUser {
                operation_id,
                expected_config_revision,
                open_id,
                trusted,
            },
            owner_epoch,
        )
        .await
    }

    pub async fn set_trusted_chat(
        &self,
        operation_id: String,
        bot_id: String,
        expected_config_revision: u64,
        chat_id: String,
        trusted: bool,
        owner_epoch: &str,
    ) -> Result<BotsCommandReply, FeishuError> {
        self.reject_if_sealed()?;
        self.submit(
            bot_id,
            BotMutation::SetTrustedChat {
                operation_id,
                expected_config_revision,
                chat_id,
                trusted,
            },
            owner_epoch,
        )
        .await
    }

    pub(crate) async fn save_registration_bot(
        &self,
        mut request: RegistrationSave,
    ) -> Result<CredentialCommit, FeishuError> {
        self.reject_if_sealed()?;
        validate_bot_id(&request.bot_id)?;
        validate_app_id(&request.app_id)?;
        if request.workspace_id.is_empty() {
            request.workspace_id = self
                .ensure_workspace_project(&request.bot_id, &request.name)
                .await?;
        }
        let owner = self.ensure_record(&request.bot_id).await?;
        owner.submit_registration_save(request).await
    }

    pub(crate) async fn recover_bot_dir(&self, bot_id: &str) -> Result<(), FeishuError> {
        let dir = self.inner.paths.bot_dir(bot_id);
        let loaded = coordinator::load_config_for_recovery(&dir)?;
        if loaded.is_none() && !has_credential_journal(&dir) {
            return Ok(());
        }
        let owner = self.ensure_record(bot_id).await?;
        let Some(settled) = owner.recover_existing(loaded).await? else {
            return Ok(());
        };
        // 启动恢复没有旧进程 socket：确定事实的认领收敛、发布与连接启动共用提交收尾。
        owner
            .finalize_commit(
                &settled,
                None,
                FinalizeOptions {
                    start_connection: true,
                    coordinate_connection: true,
                    clear_pairing: None,
                },
            )
            .await?;
        Ok(())
    }

    pub(crate) async fn note_unreadable_directory(&self, bot_id: &str) {
        let Ok(owner) = self.ensure_record(bot_id).await else {
            return;
        };
        let diagnostic = FeishuError::new(
            FeishuErrorKind::Unavailable,
            diagnostics::BOT_DIRECTORY_UNREADABLE,
            true,
            None,
        )
        .diagnostic();
        owner.note_directory_diagnostic(diagnostic).await;
        self.publish().await;
    }

    pub(crate) async fn close_operations(&self) -> Result<(), FeishuError> {
        let records = self.inner.bots.lock().await;
        let owners = records
            .values()
            .map(|record| record.operation.clone())
            .collect::<Vec<_>>();
        drop(records);
        for owner in owners {
            if let Err(error) = owner.close().await {
                // 及时上报已观察错误：不再 await 其他 owner，剩余槽位保持登记可重试。
                return Err(FeishuError::new(
                    FeishuErrorKind::Unavailable,
                    format!("bot operation close failed: {error}"),
                    true,
                    None,
                ));
            }
        }
        Ok(())
    }

    async fn submit(
        &self,
        bot_id: String,
        mutation: BotMutation,
        owner_epoch: &str,
    ) -> Result<BotsCommandReply, FeishuError> {
        let owner = self.ensure_record(&bot_id).await?;
        owner.submit(mutation, owner_epoch.to_string()).await
    }
}
