//! Owns the prepare, admission gate, durable commit and recovery decisions.
use super::diagnostics::*;
use super::{BotMutation, BotOperationOwner, RegistrationSave};
use crate::bots::config::{BotConfigFile, try_load_config};
use crate::bots::connect::BotConnectionOwner;
use crate::bots::credentials::{
    CredentialCommit, CredentialDecision, CredentialPrepare, CredentialRecovery,
    abandon_prepared_credentials, auth_invalidate, commit_prepared_credentials,
    has_credential_journal, prepare_bot_credentials, recover_bot_directory,
};
use crate::bots::owner::ManagedBot;
use crate::bots::protocol::error::{FeishuError, FeishuErrorKind};
use crate::bots::protocol::token::TokenLease;
use crate::bots::registry::{
    AppClaim, CandidateSettlement, PendingProjection, duplicate_app_error,
};
use crate::bots::storage::BotStateStore;
use crate::{
    BotCredentialAvailability, BotCredentialOperation, BotDiagnostic, BotSecretUpdate,
    BotsCommandReply, SaveBotRequest,
};
use std::path::Path;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use tokio::sync::Mutex;

/// 已确定的提交事实：可发布配置与仍需保留的候选目标应用。
pub(super) struct SettledCommit {
    commit: CredentialCommit,
    candidate_app: Option<String>,
}

/// 确定事实收尾的连接与投影选项。
pub(super) struct FinalizeOptions {
    /// 是否由本次收尾启动连接（注册路径留给其保存回执后的既有入口）。
    pub(super) start_connection: bool,
    /// 连接重协调上下文（启动恢复/显式 Retry）：确定事实即使未应用也重建连接。
    pub(super) coordinate_connection: bool,
    /// 已确定保存后需要清理的受信联系人配对。
    pub(super) clear_pairing: Option<String>,
}

/// 收尾可观察的连接结果：只用于显式重试用例报告，不改变保存结论。
pub(super) struct CommitSettlement {
    connection_error: Option<FeishuError>,
}

/// 旧连接隔离结果。
enum ConnectionQuiesce {
    Stopped,
    StopFailed(FeishuError),
}

/// 目录核实的最终裁决：确定事实交给统一收尾，或已核实的未决状态。
enum PrepareVisibility {
    Publish,
    Registration,
}

struct TransactionSettlement {
    settled: SettledCommit,
    gate_rejection: Option<FeishuError>,
    recovered_preparation: bool,
}

enum FailedStage {
    Prepare(FeishuError),
    Commit,
}

/// 目录事实核实结果。
enum VerifiedDirectory {
    /// 有可发布的确定配置。
    Determined(Box<SettledCommit>),
    /// 没有可发布配置，未提交候选仍待清理；投影已更新。
    Unpublished,
    /// 提交待确认：投影已更新，准入保持封闭。
    Uncertain(FeishuError),
    /// 现场无法核实：保留占用与封口，投影已更新。
    Unverified(FeishuError),
}

impl BotOperationOwner {
    pub(super) async fn execute(
        &self,
        mutation: BotMutation,
        owner_epoch: String,
    ) -> Result<BotsCommandReply, FeishuError> {
        match mutation {
            BotMutation::Save(request) => self.execute_save(request, &owner_epoch).await,
            BotMutation::SetEnabled {
                operation_id,
                expected_config_revision,
                enabled,
            } => {
                self.execute_config_mutation(
                    operation_id,
                    expected_config_revision,
                    owner_epoch,
                    move |config| {
                        config.enabled = enabled;
                    },
                    None,
                )
                .await
            }
            BotMutation::SetTrustedUser {
                operation_id,
                expected_config_revision,
                open_id,
                trusted,
            } => {
                let pairing = open_id.clone();
                self.execute_config_mutation(
                    operation_id,
                    expected_config_revision,
                    owner_epoch,
                    move |config| {
                        if trusted {
                            config.feishu_mut().trusted_open_ids.insert(open_id.clone());
                        } else {
                            config.feishu_mut().trusted_open_ids.remove(&open_id);
                        }
                    },
                    Some(pairing),
                )
                .await
            }
            BotMutation::SetTrustedChat {
                operation_id,
                expected_config_revision,
                chat_id,
                trusted,
            } => {
                self.execute_config_mutation(
                    operation_id,
                    expected_config_revision,
                    owner_epoch,
                    move |config| {
                        if trusted {
                            config.feishu_mut().trusted_chat_ids.insert(chat_id.clone());
                        } else {
                            config.feishu_mut().trusted_chat_ids.remove(&chat_id);
                        }
                    },
                    None,
                )
                .await
            }
            BotMutation::Retry { operation_id } => {
                self.execute_retry(operation_id, &owner_epoch).await
            }
        }
    }

    async fn execute_save(
        &self,
        request: SaveBotRequest,
        owner_epoch: &str,
    ) -> Result<BotsCommandReply, FeishuError> {
        let SaveBotRequest {
            operation_id,
            bot_id,
            expected_config_revision,
            name,
            workspace_id,
            app_id,
            secret,
            enabled,
            tools_enabled,
            model_route,
        } = request;
        let bot_id = bot_id.unwrap_or_else(|| self.bot_id.clone());
        let published = self.published().await;
        let previous = if let Some(managed) = published.clone() {
            Some(managed.config.lock().await.clone())
        } else {
            None
        };
        if let Some(previous) = &previous {
            if previous.config_revision != expected_config_revision {
                return Err(stale_revision_error());
            }
        } else if expected_config_revision != 0 {
            return Err(stale_revision_error());
        }
        // 未收束的清理/停连义务先拒绝，不进入占用查询、候选准备或任何外部 IO。
        self.runtime.reject_unsettled_obligation(&bot_id).await?;
        if let Some(previous) = &previous
            && let Some(managed) = &published
        {
            let occupancy = managed.store.identity_occupancy().await?;
            if previous.workspace_id != workspace_id && occupancy.has_thread_or_inbound {
                return Err(FeishuError::new(
                    FeishuErrorKind::Rejected,
                    "workspaceId cannot change after Thread mapping or admitted input exists",
                    false,
                    None,
                ));
            }
            if previous.feishu().app_id != app_id
                && (occupancy.has_app_identity
                    || !previous.feishu().trusted_open_ids.is_empty()
                    || !previous.feishu().trusted_chat_ids.is_empty())
            {
                return Err(FeishuError::new(
                    FeishuErrorKind::Rejected,
                    "appId cannot change after platform conversations or durable records exist",
                    false,
                    None,
                ));
            }
        }
        let mut candidate = match &previous {
            Some(previous) => previous.clone(),
            None => BotConfigFile::new(
                bot_id.clone(),
                name.clone(),
                workspace_id.clone(),
                app_id.clone(),
            )?,
        };
        candidate.name = name;
        candidate.workspace_id = workspace_id;
        candidate.feishu_mut().app_id = app_id;
        candidate.enabled = enabled;
        candidate.tools_enabled = tools_enabled;
        candidate.model_route = Some(match model_route.or(candidate.model_route) {
            Some(route) => route,
            None => self.runtime.default_model_route()?,
        });
        candidate.schema_version = crate::bots::config::BOT_CONFIG_SCHEMA_VERSION;
        if previous.is_some() {
            candidate.bump();
        }
        self.runtime
            .claim_app_target_or_error(&bot_id, &candidate.feishu().app_id)
            .await?;
        self.execute_configuration_transaction(
            previous,
            candidate,
            secret,
            &operation_id,
            owner_epoch,
            None,
        )
        .await
    }

    async fn execute_config_mutation(
        &self,
        operation_id: String,
        expected_config_revision: u64,
        owner_epoch: String,
        mutate: impl FnOnce(&mut BotConfigFile),
        clear_pairing: Option<String>,
    ) -> Result<BotsCommandReply, FeishuError> {
        // 新意图在构造候选、setPending、claimApp、prepare 或任何外部 IO 之前
        // 先拒绝未收束的清理/停连义务；显式 Retry 不经过这里。
        self.runtime
            .reject_unsettled_obligation(&self.bot_id)
            .await?;
        let managed = self.published().await.ok_or_else(|| {
            FeishuError::new(FeishuErrorKind::NotFound, "bot not found", false, None)
        })?;
        let previous = managed.config.lock().await.clone();
        if previous.config_revision != expected_config_revision {
            return Err(stale_revision_error());
        }
        let mut candidate = previous.clone();
        mutate(&mut candidate);
        candidate.bump();
        self.runtime
            .claim_app_target_or_error(&self.bot_id, &candidate.feishu().app_id)
            .await?;
        self.execute_configuration_transaction(
            Some(previous),
            candidate,
            BotSecretUpdate::Preserve,
            &operation_id,
            &owner_epoch,
            clear_pairing,
        )
        .await
    }

    async fn execute_retry(
        &self,
        operation_id: String,
        owner_epoch: &str,
    ) -> Result<BotsCommandReply, FeishuError> {
        let dir = self.runtime.inner.paths.bot_dir(&self.bot_id);
        let loaded = match load_config_for_recovery(&dir) {
            Ok(loaded) => loaded,
            Err(_) => {
                // 目录不可核实：保留现有真实投影与占用，封闭准入，不向调用方透出
                // 解析/IO 正文。
                self.mark_unverified(None).await;
                return Err(unverified_error());
            }
        };
        let has_journal = has_credential_journal(&dir);
        if !has_journal && loaded.is_none() {
            // 确定没有配置也没有未决 journal：归还全部临时占用并清掉空投影。
            self.runtime.release_app_claim(&self.bot_id).await;
            self.runtime.clear_cleanup_app(&self.bot_id).await;
            self.clear_pending_if_published(&BotCredentialOperation::Idle, None)
                .await;
            self.clear_submitting().await;
            self.runtime.publish().await;
            return Err(FeishuError::new(
                FeishuErrorKind::NotFound,
                "bot not found",
                false,
                None,
            ));
        }
        let settled = match self.verify_recovered_directory(loaded, None).await {
            VerifiedDirectory::Determined(settled) => *settled,
            // 只有未提交候选仍待清理：没有可发布配置，也不能启动连接。
            VerifiedDirectory::Unpublished => {
                return Err(not_applied_error_without_commit(&operation_id));
            }
            VerifiedDirectory::Uncertain(error) | VerifiedDirectory::Unverified(error) => {
                return Err(error);
            }
        };
        let settlement = self
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
        self.runtime.publish().await;
        match settlement.connection_error {
            Some(error) => Err(error),
            None => Ok(self
                .runtime
                .reply(
                    operation_id,
                    true,
                    owner_epoch,
                    crate::bots::owner::ReceiptDurability::Durable,
                )
                .await),
        }
    }

    pub(super) async fn recover_existing(
        &self,
        loaded: Option<BotConfigFile>,
    ) -> Result<Option<SettledCommit>, FeishuError> {
        let _serial = self.executor.serial.lock().await;
        match self.verify_recovered_directory(loaded, None).await {
            VerifiedDirectory::Determined(mut settled) => {
                // Recovery has already resolved credential ownership. Persist the model once,
                // under this same configuration owner, before publishing or opening a socket.
                if matches!(settled.commit.operation, BotCredentialOperation::Idle)
                    && settled.commit.config.model_route.is_none()
                {
                    settled.commit.config.model_route = Some(self.runtime.default_model_route()?);
                    settled.commit.config.schema_version =
                        crate::bots::config::BOT_CONFIG_SCHEMA_VERSION;
                    settled.commit.config.bump();
                    crate::bots::config::save_config(
                        &self
                            .runtime
                            .inner
                            .paths
                            .bot_dir(&self.bot_id)
                            .join("config.toml"),
                        &settled.commit.config,
                    )?;
                }
                Ok(Some(*settled))
            }
            // 未决与不可核实都已更新投影并保持封口；加载继续，不丢弃现场。
            VerifiedDirectory::Unpublished
            | VerifiedDirectory::Uncertain(_)
            | VerifiedDirectory::Unverified(_) => Ok(None),
        }
    }

    pub(super) async fn run_registration_save(
        &self,
        request: RegistrationSave,
    ) -> Result<CredentialCommit, FeishuError> {
        // 注册本地保存在构造候选、claimApp、prepare 或任何外部 IO 之前同样先
        // 拒绝未收束义务；显式 Retry 不经过这里。
        self.runtime
            .reject_unsettled_obligation(&self.bot_id)
            .await?;
        let RegistrationSave {
            name,
            workspace_id,
            app_id,
            secret,
            trusted_open_id,
            operation_id,
            ..
        } = request;
        let mut config =
            BotConfigFile::new(self.bot_id.clone(), name, workspace_id, app_id.clone())?;
        config.model_route = Some(self.runtime.default_model_route()?);
        if let Some(open_id) = trusted_open_id {
            config.feishu_mut().trusted_open_ids.insert(open_id);
        }
        self.runtime
            .claim_app_target_or_error(&self.bot_id, &app_id)
            .await?;
        let transaction = self
            .prepare_gate_commit(
                None,
                config,
                BotSecretUpdate::Replace { value: secret },
                &operation_id,
                PrepareVisibility::Registration,
            )
            .await?;
        // Registration starts the connection after the save receipt is committed.
        self.finalize_commit(
            &transaction.settled,
            None,
            FinalizeOptions {
                start_connection: false,
                coordinate_connection: true,
                clear_pairing: None,
            },
        )
        .await?;
        self.clear_submitting().await;
        Ok(transaction.settled.commit)
    }

    async fn execute_configuration_transaction(
        &self,
        previous: Option<BotConfigFile>,
        candidate: BotConfigFile,
        secret: BotSecretUpdate,
        operation_id: &str,
        owner_epoch: &str,
        clear_pairing: Option<String>,
    ) -> Result<BotsCommandReply, FeishuError> {
        let transaction = self
            .prepare_gate_commit(
                previous.as_ref(),
                candidate,
                secret,
                operation_id,
                PrepareVisibility::Publish,
            )
            .await?;
        if let Some(rejection) = transaction.gate_rejection {
            // If the journal proves the write happened, report the applied change.
            if transaction.settled.commit.decision == CredentialDecision::Applied {
                return self
                    .finish_decision(transaction.settled, previous.as_ref(), owner_epoch, None)
                    .await;
            }
            let _ = self
                .finalize_commit(
                    &transaction.settled,
                    previous.as_ref(),
                    FinalizeOptions {
                        start_connection: false,
                        coordinate_connection: false,
                        clear_pairing: None,
                    },
                )
                .await;
            return Err(rejection);
        }
        let (previous, clear_pairing) = if transaction.recovered_preparation {
            (None, None)
        } else {
            (previous.as_ref(), clear_pairing)
        };
        self.finish_decision(transaction.settled, previous, owner_epoch, clear_pairing)
            .await
    }

    async fn prepare_gate_commit(
        &self,
        previous: Option<&BotConfigFile>,
        candidate: BotConfigFile,
        secret: BotSecretUpdate,
        operation_id: &str,
        visibility: PrepareVisibility,
    ) -> Result<TransactionSettlement, FeishuError> {
        self.set_pending(
            BotCredentialOperation::Preparing {
                operation_id: operation_id.to_owned(),
            },
            None,
        )
        .await;
        if matches!(visibility, PrepareVisibility::Publish) {
            self.runtime.publish().await;
        }
        let dir = self.runtime.inner.paths.bot_dir(&self.bot_id);
        let credentials = self.runtime.inner.config.bot_credentials();
        let expected_bot_id = self.bot_id.clone();
        let baseline = previous.cloned().unwrap_or_else(|| candidate.clone());
        let operation = operation_id.to_owned();
        let prepared = self
            .executor
            .run_blocking(&self.bot_id, move || {
                prepare_bot_credentials(
                    &dir,
                    &expected_bot_id,
                    &credentials,
                    &baseline,
                    candidate,
                    secret,
                    &operation,
                )
            })
            .await;
        let prepared = match prepared {
            Ok(CredentialPrepare::Ready(prepared)) => *prepared,
            Ok(CredentialPrepare::Decided(commit)) => {
                return Ok(TransactionSettlement {
                    settled: SettledCommit {
                        commit: *commit,
                        candidate_app: None,
                    },
                    gate_rejection: None,
                    recovered_preparation: false,
                });
            }
            Err(error) => {
                let settled = self
                    .settle_worker_failure(operation_id, FailedStage::Prepare(error))
                    .await?;
                return Ok(TransactionSettlement {
                    settled,
                    gate_rejection: None,
                    recovered_preparation: true,
                });
            }
        };
        let gate_rejection = self.gate_prepared(previous, &prepared.target).await.err();
        let accepted = gate_rejection.is_none();
        let dir = self.runtime.inner.paths.bot_dir(&self.bot_id);
        let credentials = self.runtime.inner.config.bot_credentials();
        let committed = self
            .executor
            .run_blocking(&self.bot_id, move || {
                if accepted {
                    commit_prepared_credentials(&dir, &credentials, prepared)
                } else {
                    abandon_prepared_credentials(&dir, &credentials, prepared)
                }
            })
            .await;
        let settled = match committed {
            Ok(commit) => SettledCommit {
                commit,
                candidate_app: None,
            },
            Err(_) => {
                self.settle_worker_failure(operation_id, FailedStage::Commit)
                    .await?
            }
        };
        Ok(TransactionSettlement {
            settled,
            gate_rejection,
            recovered_preparation: false,
        })
    }

    async fn gate_prepared(
        &self,
        expected: Option<&BotConfigFile>,
        target: &BotConfigFile,
    ) -> Result<(), FeishuError> {
        self.runtime.reject_if_sealed()?;
        if let Some(managed) = self.published().await {
            let _admission = managed.admission.lock().await;
            self.runtime.reject_if_sealed()?;
            if !self.still_owner().await {
                return Err(FeishuError::new(
                    FeishuErrorKind::Conflict,
                    "bot operation owner was replaced",
                    true,
                    None,
                ));
            }
            let current = managed.config.lock().await.clone();
            if let Some(expected) = expected
                && current.config_revision != expected.config_revision
            {
                return Err(stale_revision_error());
            }
            let occupancy = managed.store.identity_occupancy().await?;
            if current.workspace_id != target.workspace_id && occupancy.has_thread_or_inbound {
                return Err(FeishuError::new(
                    FeishuErrorKind::Rejected,
                    "workspaceId cannot change after Thread mapping or admitted input exists",
                    false,
                    None,
                ));
            }
            if current.feishu().app_id != target.feishu().app_id
                && (occupancy.has_app_identity
                    || !current.feishu().trusted_open_ids.is_empty()
                    || !current.feishu().trusted_chat_ids.is_empty())
            {
                return Err(FeishuError::new(
                    FeishuErrorKind::Rejected,
                    "appId cannot change after platform conversations or durable records exist",
                    false,
                    None,
                ));
            }
            self.runtime
                .claim_app_target_or_error(&self.bot_id, &target.feishu().app_id)
                .await?;
            managed.admission_closed.store(true, Ordering::Release);
            managed.submitting.store(true, Ordering::Release);
            return Ok(());
        }
        self.runtime
            .claim_app_target_or_error(&self.bot_id, &target.feishu().app_id)
            .await?;
        Ok(())
    }

    async fn finish_decision(
        &self,
        settled: SettledCommit,
        previous: Option<&BotConfigFile>,
        owner_epoch: &str,
        clear_pairing: Option<String>,
    ) -> Result<BotsCommandReply, FeishuError> {
        let decision = settled.commit.decision;
        let operation_id = settled.commit.operation_id.clone();
        let not_applied = not_applied_error(&settled.commit);
        self.finalize_commit(
            &settled,
            previous,
            FinalizeOptions {
                start_connection: true,
                coordinate_connection: false,
                clear_pairing,
            },
        )
        .await?;
        match decision {
            CredentialDecision::Applied => Ok(self
                .runtime
                .reply(
                    operation_id,
                    true,
                    owner_epoch,
                    crate::bots::owner::ReceiptDurability::Durable,
                )
                .await),
            CredentialDecision::Uncertain => Err(uncertain_error(&operation_id)),
            CredentialDecision::NotApplied => Err(not_applied),
        }
    }

    pub(super) async fn finalize_commit(
        &self,
        settled: &SettledCommit,
        previous: Option<&BotConfigFile>,
        options: FinalizeOptions,
    ) -> Result<CommitSettlement, FeishuError> {
        let commit = &settled.commit;
        if commit.decision == CredentialDecision::Uncertain {
            self.publish_uncertain_state(
                &commit.config.feishu().app_id,
                commit.operation.clone(),
                commit.diagnostic.clone(),
            )
            .await;
            return Ok(CommitSettlement {
                connection_error: None,
            });
        }
        if !commit.publishable {
            self.finalize_unpublished(commit, settled.candidate_app.as_deref())
                .await;
            return Ok(CommitSettlement {
                connection_error: None,
            });
        }
        let managed = self.ensure_published(&commit.config).await?;
        let previous_app = managed.config.lock().await.feishu().app_id.clone();
        let must_stop =
            commit.decision == CredentialDecision::Applied || options.coordinate_connection;
        let quiesce = if must_stop {
            Some(self.quiesce_old_connection(&managed).await)
        } else {
            None
        };
        let stopped = matches!(quiesce, Some(ConnectionQuiesce::Stopped));
        let stop_error = match quiesce {
            Some(ConnectionQuiesce::StopFailed(error)) => Some(error),
            _ => None,
        };
        if stopped {
            self.runtime.clear_pending_stop_app(&self.bot_id).await;
        } else if stop_error.is_some() {
            // 旧 socket 未确认真实停止：继续保护旧应用，避免另一机器人接管。
            self.runtime
                .retain_pending_stop_app(&self.bot_id, &previous_app)
                .await;
        }
        let candidate = match commit.operation {
            BotCredentialOperation::CleanupPending { .. } => CandidateSettlement::Retain,
            BotCredentialOperation::Idle => CandidateSettlement::Cleared,
            _ => CandidateSettlement::Unchanged,
        };
        let claim = self
            .runtime
            .publish_app_reservation(
                &self.bot_id,
                &commit.config.feishu().app_id,
                settled.candidate_app.as_deref(),
                candidate,
            )
            .await;
        let claim_ok = claim == AppClaim::Held;
        if !claim_ok {
            // 该应用已被另一 owner 占用并因此继续受保护；本记录只关闭准入并诊断。
            self.set_managed_diagnostic(
                &managed,
                DiagnosticSlot::Connection,
                duplicate_app_error().diagnostic(),
            )
            .await;
        }
        if let Some(error) = &stop_error {
            // 连接回收失败独立诊断：保存结论仍是 Applied，旧应用与目标都继续受保护。
            self.set_managed_diagnostic(&managed, DiagnosticSlot::Connection, error.diagnostic())
                .await;
        }
        self.write_commit_facts(&managed, commit, previous).await;
        self.clear_pending_if_published(&commit.operation, commit.diagnostic.clone())
            .await;
        if commit.decision == CredentialDecision::Applied
            && let Some(open_id) = options.clear_pairing
        {
            self.clear_pairing_after_commit(&open_id).await;
        }
        let can_open = claim_ok && stop_error.is_none();
        if can_open {
            self.open_admission(&managed).await;
        }
        let start_new = options.start_connection
            && (commit.decision == CredentialDecision::Applied || options.coordinate_connection);
        let mut connection_error = stop_error;
        if can_open && start_new {
            connection_error = self.start_determined_connection(&managed, commit).await;
        } else if can_open && !commit.config.enabled {
            self.clear_non_cleanup_diagnostic(&managed).await;
        }
        self.clear_submitting().await;
        self.runtime.publish().await;
        Ok(CommitSettlement { connection_error })
    }

    async fn finalize_unpublished(&self, commit: &CredentialCommit, candidate: Option<&str>) {
        self.runtime
            .abandon_app_reservation(
                &self.bot_id,
                candidate,
                matches!(
                    commit.operation,
                    BotCredentialOperation::CleanupPending {
                        config_committed: false,
                        ..
                    }
                ),
            )
            .await;
        self.set_pending(commit.operation.clone(), commit.diagnostic.clone())
            .await;
        if let Some(managed) = self.published().await {
            managed.admission_closed.store(true, Ordering::Release);
            self.set_managed_diagnostic(
                &managed,
                DiagnosticSlot::Credential,
                commit
                    .diagnostic
                    .clone()
                    .unwrap_or_else(unverified_diagnostic),
            )
            .await;
        }
        self.clear_submitting().await;
        self.runtime.publish().await;
    }

    async fn publish_uncertain_state(
        &self,
        app_id: &str,
        operation: BotCredentialOperation,
        diagnostic: Option<BotDiagnostic>,
    ) {
        if !app_id.is_empty() {
            self.runtime.retain_cleanup_app(&self.bot_id, app_id).await;
        }
        self.set_pending(operation.clone(), diagnostic.clone())
            .await;
        if let Some(managed) = self.published().await {
            managed.admission_closed.store(true, Ordering::Release);
            *managed.credential_operation.lock().await = operation;
            self.set_managed_diagnostic(
                &managed,
                DiagnosticSlot::Credential,
                diagnostic.unwrap_or_else(unverified_diagnostic),
            )
            .await;
        }
        self.clear_submitting().await;
        self.runtime.publish().await;
    }

    async fn start_determined_connection(
        &self,
        managed: &Arc<ManagedBot>,
        commit: &CredentialCommit,
    ) -> Option<FeishuError> {
        if !commit.config.enabled {
            self.clear_non_cleanup_diagnostic(managed).await;
            return None;
        }
        let Some(secret) = commit.secret.clone() else {
            let error =
                FeishuError::new(FeishuErrorKind::Auth, "bot secret is missing", false, None);
            self.set_managed_diagnostic(managed, DiagnosticSlot::Connection, error.diagnostic())
                .await;
            return Some(error);
        };
        match self
            .runtime
            .start_connection(managed, commit.config.clone(), secret)
            .await
        {
            Ok(()) => {
                self.clear_non_cleanup_diagnostic(managed).await;
                None
            }
            Err(error) => {
                self.set_managed_diagnostic(
                    managed,
                    DiagnosticSlot::Connection,
                    error.diagnostic(),
                )
                .await;
                Some(error)
            }
        }
    }

    async fn clear_pairing_after_commit(&self, open_id: &str) {
        let Some(managed) = self.published().await else {
            return;
        };
        if managed.store.clear_pairing(open_id).await.is_ok() {
            // 该配对行的清理义务已由持久事实证明完成：只移除它对应的诊断，
            // 其它用户仍未完成的清理与连接错误保持可见。
            self.finish_pairing_cleanup(open_id).await;
            return;
        }
        self.pairing_cleanup
            .lock()
            .await
            .insert(open_id.to_string());
        self.set_managed_diagnostic(
            &managed,
            DiagnosticSlot::Pairing,
            FeishuError::new(
                FeishuErrorKind::Unavailable,
                PAIRING_CLEANUP_PENDING,
                true,
                None,
            )
            .diagnostic(),
        )
        .await;
    }

    async fn finish_pairing_cleanup(&self, open_id: &str) {
        let mut pending = self.pairing_cleanup.lock().await;
        pending.remove(open_id);
        if !pending.is_empty() {
            return;
        }
        drop(pending);
        let Some(managed) = self.published().await else {
            return;
        };
        let mut slot = managed.diagnostic.lock().await;
        slot.set(DiagnosticSlot::Pairing, None);
    }

    async fn verify_recovered_directory(
        &self,
        loaded: Option<BotConfigFile>,
        unverified: Option<BotCredentialOperation>,
    ) -> VerifiedDirectory {
        let dir = self.runtime.inner.paths.bot_dir(&self.bot_id);
        let credentials = self.runtime.inner.config.bot_credentials();
        let expected_bot_id = self.bot_id.clone();
        let recovered = match self
            .executor
            .run_blocking(&self.bot_id, move || {
                recover_bot_directory(&dir, &expected_bot_id, &credentials, loaded)
            })
            .await
        {
            Ok(recovered) => recovered,
            Err(_) => {
                self.mark_unverified(unverified).await;
                return VerifiedDirectory::Unverified(unverified_error());
            }
        };
        match recovered.decision {
            CredentialDecision::Uncertain => {
                let app_id = recovered
                    .reserved_app_id
                    .clone()
                    .or_else(|| {
                        recovered
                            .config
                            .as_ref()
                            .map(|config| config.feishu().app_id.clone())
                    })
                    .unwrap_or_default();
                // 已知的原配置应用与被 journal 证明的目标应用都要继续受保护：
                // 旧关联不能因为实际文件是旧配置就丢掉候选目标，反之亦然。
                let previous_app = recovered.previous_app_id.clone();
                let operation_id = recovered.operation_id.clone();
                self.publish_uncertain_state(
                    &app_id,
                    recovered.operation.clone(),
                    recovered.diagnostic.clone(),
                )
                .await;
                if let Some(previous_app) = previous_app
                    && previous_app != app_id
                {
                    self.runtime
                        .retain_pending_stop_app(&self.bot_id, &previous_app)
                        .await;
                }
                VerifiedDirectory::Uncertain(
                    operation_id
                        .as_deref()
                        .map(uncertain_error)
                        .unwrap_or_else(unverified_error),
                )
            }
            CredentialDecision::Applied | CredentialDecision::NotApplied => {
                let candidate_app = recovered.reserved_app_id.clone();
                let fallback = recovered.operation_id.clone().unwrap_or_default();
                if recovered.publishable_config().is_none() {
                    // 没有可发布配置：只有仍待清理的未提交候选才保留占用；清理已
                    // 真实完成（Idle）时必须归还，否则新意图会被旧的空义务永久拦住。
                    let operation = recovered.operation.clone();
                    let diagnostic = recovered.diagnostic.clone();
                    if matches!(
                        operation,
                        BotCredentialOperation::CleanupPending {
                            config_committed: false,
                            ..
                        }
                    ) {
                        self.publish_uncertain_state(
                            &candidate_app.unwrap_or_default(),
                            operation,
                            diagnostic,
                        )
                        .await;
                    } else {
                        self.runtime.release_app_claim(&self.bot_id).await;
                        self.runtime.clear_cleanup_app(&self.bot_id).await;
                        self.set_pending(operation, diagnostic).await;
                        self.clear_submitting().await;
                        self.runtime.publish().await;
                    }
                    return VerifiedDirectory::Unpublished;
                }
                match commit_from_recovery(recovered, &fallback) {
                    Some(commit) => VerifiedDirectory::Determined(Box::new(SettledCommit {
                        commit,
                        candidate_app,
                    })),
                    // publishable_config 已证明存在配置；保留兜底分类而不 panic。
                    None => VerifiedDirectory::Unpublished,
                }
            }
        }
    }

    async fn write_commit_facts(
        &self,
        managed: &Arc<ManagedBot>,
        commit: &CredentialCommit,
        previous: Option<&BotConfigFile>,
    ) {
        let invalidate = commit.invalidate || auth_invalidate(previous, &commit.config);
        *managed.config.lock().await = commit.config.clone();
        *managed.credential.lock().await = commit.availability;
        *managed.credential_operation.lock().await = commit.operation.clone();
        {
            let mut slot = managed.diagnostic.lock().await;
            slot.set(DiagnosticSlot::Credential, commit.diagnostic.clone());
            slot.set(DiagnosticSlot::Directory, None);
        }
        if invalidate {
            managed.generation.fetch_add(1, Ordering::AcqRel);
            *managed.bot_open_id.lock().await = None;
            managed
                .token
                .replace(
                    commit.config.feishu().app_id.clone(),
                    commit.secret.clone().unwrap_or_default(),
                )
                .await;
        } else if let Some(secret) = commit.secret.clone() {
            managed
                .token
                .replace(commit.config.feishu().app_id.clone(), secret)
                .await;
        }
    }

    async fn set_managed_diagnostic(
        &self,
        managed: &ManagedBot,
        kind: DiagnosticSlot,
        diagnostic: BotDiagnostic,
    ) {
        let mut slot = managed.diagnostic.lock().await;
        slot.set(kind, Some(diagnostic));
    }

    async fn clear_non_cleanup_diagnostic(&self, managed: &ManagedBot) {
        let mut slot = managed.diagnostic.lock().await;
        slot.set(DiagnosticSlot::Connection, None);
    }

    async fn quiesce_old_connection(&self, managed: &Arc<ManagedBot>) -> ConnectionQuiesce {
        {
            let _admission = managed.admission.lock().await;
            managed.admission_closed.store(true, Ordering::Release);
            managed.submitting.store(true, Ordering::Release);
            managed.generation.fetch_add(1, Ordering::AcqRel);
            *managed.bot_open_id.lock().await = None;
        }
        match managed.connection.stop().await {
            Ok(()) => ConnectionQuiesce::Stopped,
            Err(error) => ConnectionQuiesce::StopFailed(error),
        }
    }

    async fn open_admission(&self, managed: &Arc<ManagedBot>) {
        {
            let _admission = managed.admission.lock().await;
            managed.admission_closed.store(false, Ordering::Release);
            managed.submitting.store(false, Ordering::Release);
        }
    }

    async fn ensure_published(
        &self,
        config: &BotConfigFile,
    ) -> Result<Arc<ManagedBot>, FeishuError> {
        if let Some(existing) = self.published().await {
            return Ok(existing);
        }
        let dir = self.runtime.inner.paths.bot_dir(&self.bot_id);
        let managed = Arc::new(ManagedBot {
            config: Mutex::new(config.clone()),
            store: BotStateStore::new(dir.join("state.sqlite")),
            connection: BotConnectionOwner::new(self.bot_id.clone()),
            credential: Mutex::new(BotCredentialAvailability::Missing),
            credential_operation: Mutex::new(BotCredentialOperation::Idle),
            diagnostic: Mutex::new(BotDiagnosticSet::default()),
            generation: Arc::new(AtomicU64::new(0)),
            token: TokenLease::new(
                self.runtime.inner.http.clone(),
                config.feishu().app_id.clone(),
                String::new(),
            ),
            bot_open_id: Mutex::new(None),
            send_rate: crate::bots::send::SendRate::new(),
            file_delivery: Mutex::new(()),
            admission: Mutex::new(()),
            admission_closed: AtomicBool::new(false),
            submitting: AtomicBool::new(false),
        });
        {
            let mut records = self.runtime.inner.bots.lock().await;
            if let Some(record) = records.get_mut(&self.bot_id) {
                record.published = Some(managed.clone());
            }
        }
        self.runtime.spawn_connection_watch(&managed).await;
        Ok(managed)
    }

    pub(crate) async fn read_selected_secret(
        &self,
        config: &BotConfigFile,
    ) -> Result<String, FeishuError> {
        let credentials = self.runtime.inner.config.bot_credentials();
        let bot_id = config.id.clone();
        let app_id = config.feishu().app_id.clone();
        let selected = config.selected_ref.clone();
        let inspected = self
            .executor
            .run_inspect(&self.bot_id, move || {
                credentials
                    .inspect_selected(&bot_id, &app_id, selected.as_ref())
                    .map_err(|error| {
                        FeishuError::new(
                            FeishuErrorKind::Unavailable,
                            error.to_string(),
                            true,
                            None,
                        )
                    })
            })
            .await?;
        let Some(secret) = inspected.secret else {
            return Err(FeishuError::new(
                FeishuErrorKind::Auth,
                "bot secret is missing",
                false,
                None,
            ));
        };
        if let Some(managed) = self.published().await {
            let current = managed.config.lock().await.clone();
            if current.id != config.id
                || current.feishu().app_id != config.feishu().app_id
                || current.selected_ref != config.selected_ref
                || current.config_revision != config.config_revision
            {
                return Err(FeishuError::new(
                    FeishuErrorKind::Conflict,
                    "bot credential material was superseded",
                    true,
                    None,
                ));
            }
            managed
                .token
                .replace(config.feishu().app_id.clone(), secret.clone())
                .await;
        }
        Ok(secret)
    }

    pub(crate) async fn published(&self) -> Option<Arc<ManagedBot>> {
        self.runtime
            .inner
            .bots
            .lock()
            .await
            .get(&self.bot_id)
            .and_then(|record| record.published.clone())
    }

    async fn still_owner(&self) -> bool {
        self.runtime
            .inner
            .bots
            .lock()
            .await
            .get(&self.bot_id)
            .is_some_and(|record| std::ptr::eq(Arc::as_ptr(&record.operation), self))
    }

    async fn set_pending(
        &self,
        operation: BotCredentialOperation,
        diagnostic: Option<BotDiagnostic>,
    ) {
        let mut records = self.runtime.inner.bots.lock().await;
        if let Some(record) = records.get_mut(&self.bot_id)
            && record.published.is_none()
        {
            record.pending = Some(PendingProjection {
                bot_id: self.bot_id.clone(),
                operation: operation.clone(),
                diagnostics: pending_diagnostics(diagnostic.clone()),
            });
        }
        drop(records);
        if let Some(managed) = self.published().await {
            *managed.credential_operation.lock().await = operation;
            let mut slot = managed.diagnostic.lock().await;
            slot.set(DiagnosticSlot::Credential, diagnostic);
        }
    }

    async fn clear_pending_if_published(
        &self,
        operation: &BotCredentialOperation,
        diagnostic: Option<BotDiagnostic>,
    ) {
        let mut records = self.runtime.inner.bots.lock().await;
        if let Some(record) = records.get_mut(&self.bot_id) {
            if record.published.is_some() || matches!(operation, BotCredentialOperation::Idle) {
                record.pending = None;
            } else {
                record.pending = Some(PendingProjection {
                    bot_id: self.bot_id.clone(),
                    operation: operation.clone(),
                    diagnostics: pending_diagnostics(diagnostic),
                });
            }
        }
    }

    async fn settle_worker_failure(
        &self,
        operation_id: &str,
        stage: FailedStage,
    ) -> Result<SettledCommit, FeishuError> {
        let uncertain_operation = BotCredentialOperation::CommitUncertain {
            operation_id: operation_id.to_owned(),
        };
        let dir = self.runtime.inner.paths.bot_dir(&self.bot_id);
        let loaded = match load_config_for_recovery(&dir) {
            Ok(loaded) => loaded,
            Err(_) => {
                self.mark_unverified(Some(uncertain_operation)).await;
                return Err(unverified_error());
            }
        };
        let commit_started = matches!(stage, FailedStage::Commit);
        let no_commit = match stage {
            FailedStage::Prepare(error) => error,
            FailedStage::Commit => not_applied_error_without_commit(operation_id),
        };
        if loaded.is_none() && !has_credential_journal(&dir) {
            self.runtime.release_app_claim(&self.bot_id).await;
            if commit_started {
                self.runtime.clear_cleanup_app(&self.bot_id).await;
            }
            self.set_pending(BotCredentialOperation::Idle, Some(incomplete_diagnostic()))
                .await;
            self.clear_submitting().await;
            self.runtime.publish().await;
            return Err(no_commit);
        }
        match self
            .verify_recovered_directory(loaded, Some(uncertain_operation))
            .await
        {
            VerifiedDirectory::Determined(settled) => Ok(*settled),
            VerifiedDirectory::Unpublished => Err(no_commit),
            VerifiedDirectory::Uncertain(error) | VerifiedDirectory::Unverified(error) => {
                Err(error)
            }
        }
    }

    async fn mark_unverified(&self, operation: Option<BotCredentialOperation>) {
        let diagnostic = unverified_diagnostic();
        tracing::warn!(
            bot_id = %self.bot_id,
            "bot directory state could not be verified; retained for local retry"
        );
        if let Some(managed) = self.published().await {
            managed.admission_closed.store(true, Ordering::Release);
            if let Some(operation) = operation {
                *managed.credential_operation.lock().await = operation;
            }
            let mut slot = managed.diagnostic.lock().await;
            slot.set(DiagnosticSlot::Directory, Some(diagnostic));
        } else if let Some(operation) = operation {
            self.set_pending(operation, Some(diagnostic)).await;
        } else {
            self.note_directory_diagnostic(diagnostic).await;
        }
        self.clear_submitting().await;
        self.runtime.publish().await;
    }

    pub(super) async fn note_directory_diagnostic(&self, diagnostic: BotDiagnostic) {
        if let Some(managed) = self.published().await {
            let mut slot = managed.diagnostic.lock().await;
            slot.set(DiagnosticSlot::Directory, Some(diagnostic));
            return;
        }
        let mut records = self.runtime.inner.bots.lock().await;
        if let Some(record) = records.get_mut(&self.bot_id) {
            let pending = record.pending.get_or_insert_with(|| PendingProjection {
                bot_id: self.bot_id.clone(),
                operation: BotCredentialOperation::Idle,
                diagnostics: BotDiagnosticSet::default(),
            });
            pending
                .diagnostics
                .set(DiagnosticSlot::Directory, Some(diagnostic));
        }
    }

    async fn clear_submitting(&self) {
        if let Some(managed) = self.published().await {
            managed.submitting.store(false, Ordering::Release);
        }
    }
}

pub(super) fn load_config_for_recovery(dir: &Path) -> Result<Option<BotConfigFile>, FeishuError> {
    match try_load_config(&dir.join("config.toml")) {
        Ok(loaded) => Ok(loaded),
        Err(error) => {
            if has_credential_journal(dir) {
                Ok(None)
            } else {
                Err(error)
            }
        }
    }
}

fn stale_revision_error() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Conflict,
        "stale bot config revision",
        true,
        None,
    )
}

fn unverified_error() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        "bot directory state could not be verified; retry after fixing local data",
        true,
        None,
    )
}

fn commit_from_recovery(
    recovered: CredentialRecovery,
    fallback_operation_id: &str,
) -> Option<CredentialCommit> {
    let config = recovered.config?;
    Some(CredentialCommit {
        decision: recovered.decision,
        config,
        availability: recovered.availability,
        operation: recovered.operation,
        secret: recovered.secret,
        invalidate: recovered.invalidate,
        diagnostic: recovered.diagnostic,
        operation_id: recovered
            .operation_id
            .unwrap_or_else(|| fallback_operation_id.to_string()),
        publishable: true,
    })
}

fn uncertain_error(operation_id: &str) -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        format!("bot credential commit {operation_id} is uncertain"),
        true,
        None,
    )
}

fn not_applied_error(commit: &CredentialCommit) -> FeishuError {
    if let Some(diagnostic) = &commit.diagnostic {
        FeishuError::new(
            FeishuErrorKind::Rejected,
            diagnostic.message.clone(),
            diagnostic.retryable,
            diagnostic.platform_code.clone(),
        )
    } else {
        FeishuError::new(
            FeishuErrorKind::Rejected,
            format!(
                "bot credential operation {} was not applied",
                commit.operation_id
            ),
            false,
            None,
        )
    }
}

fn not_applied_error_without_commit(operation_id: &str) -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Rejected,
        format!("bot credential operation {operation_id} was not applied"),
        false,
        None,
    )
}

fn pending_diagnostics(diagnostic: Option<BotDiagnostic>) -> BotDiagnosticSet {
    let mut diagnostics = BotDiagnosticSet::default();
    diagnostics.set(DiagnosticSlot::Credential, diagnostic);
    diagnostics
}
