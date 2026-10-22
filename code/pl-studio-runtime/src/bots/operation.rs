//! 每个机器人的配置/凭据操作 owner：准备、短准入裁决、提交/恢复与权威发布。
//!
//! 调用方停止等待不撤销已受理工作。阻塞句柄留在槽内借 `&mut` 等待，取消不 `take` 遗失。

use super::config::{BotConfigFile, try_load_config, validate_app_id, validate_bot_id};
use super::connect::BotConnectionOwner;
use super::credentials::{
    CredentialCommit, CredentialDecision, CredentialPrepare, CredentialRecovery,
    PreparedCredential, abandon_prepared_credentials, auth_invalidate, commit_prepared_credentials,
    has_credential_journal, prepare_bot_credentials, recover_bot_directory,
};
use super::owner::{BotRuntime, ManagedBot};
use super::protocol::error::{FeishuError, FeishuErrorKind};
use super::protocol::token::TokenLease;
use super::storage::BotStateStore;
use crate::studio::new_id;
use pl_protocol::studio::{
    BotCredentialAvailability, BotCredentialOperation, BotDiagnostic,
    BotPendingCredentialOperation, BotSecretUpdate, BotsCommandReply, SaveBotRequest,
};
use std::collections::BTreeSet;
use std::path::Path;
use std::pin::Pin;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use tokio::sync::{Mutex, oneshot, watch};
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

/// 凭据/提交状态无法核实时的固定安全诊断文案。
const CREDENTIAL_STATE_UNVERIFIED: &str =
    "bot credential state could not be verified; retry the operation to continue";
/// 已确定未写入配置、但操作没有完成的固定安全诊断文案。
const CREDENTIAL_OPERATION_INCOMPLETE: &str =
    "bot credential operation did not complete; no configuration was written";
/// 已确定保存后配对清理未完成的独立诊断文案。
const PAIRING_CLEANUP_PENDING: &str = "pairing request cleanup did not finish, saved trust is unchanged and submitting \
     the same trust value again finishes cleanup";
/// 合法 safe-id 目录读取失败时的固定安全诊断文案。
const BOT_DIRECTORY_UNREADABLE: &str =
    "bot directory could not be read; local data is retained for retry";

pub(crate) struct BotRecord {
    pub(crate) published: Option<Arc<ManagedBot>>,
    pub(crate) operation: Arc<BotOperationOwner>,
    /// 已确定发布配置占用的应用：与已发布配置同步维护，跨机器人裁决只读这里，
    /// 不在 registry 锁内取 `ManagedBot` 的配置锁。
    pub(crate) published_app_id: Option<String>,
    /// 准备中的目标应用；同一 owner 未收敛前不得静默替换为其它目标。
    pub(crate) claimed_app_id: Option<String>,
    /// 未提交候选尚未完成清理时仍须保护的目标应用。
    pub(crate) cleanup_app_id: Option<String>,
    /// 旧连接未被确认真实停止时仍须保护的旧应用。
    pub(crate) pending_stop_app_id: Option<String>,
    pub(crate) pending: Option<PendingProjection>,
    pub(crate) watch: Arc<Mutex<WatchSlot>>,
}

#[derive(Clone)]
pub(crate) struct PendingProjection {
    pub bot_id: String,
    pub operation: BotCredentialOperation,
    pub diagnostic: Option<BotDiagnostic>,
}

pub(crate) struct WatchSlot {
    cancel: CancellationToken,
    handle: Option<JoinHandle<()>>,
}

impl WatchSlot {
    fn new() -> Self {
        Self {
            cancel: CancellationToken::new(),
            handle: None,
        }
    }

    async fn join(&mut self) -> Result<(), FeishuError> {
        self.cancel.cancel();
        let Some(handle) = self.handle.as_mut() else {
            return Ok(());
        };
        let joined = Pin::new(handle).await;
        self.handle = None;
        match joined {
            Ok(()) => Ok(()),
            Err(error) if error.is_cancelled() => Ok(()),
            Err(_) => Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "bot connection watch join failed",
                true,
                None,
            )),
        }
    }
}

struct TypedCompletion<T> {
    fingerprint: CommandFingerprint,
    outcome: watch::Sender<Option<Arc<Result<T, FeishuError>>>>,
    /// worker 未发布结果就结束（panic、取消或提前退出）：结果不可复用，需要重新执行。
    interrupted: AtomicBool,
}

impl<T> TypedCompletion<T> {
    fn new(fingerprint: CommandFingerprint) -> Self {
        Self {
            fingerprint,
            outcome: watch::channel(None).0,
            interrupted: AtomicBool::new(false),
        }
    }

    fn is_interrupted(&self) -> bool {
        self.interrupted.load(Ordering::Acquire)
    }
}

/// 一次已受理操作的完成责任：正常路径发布一次结果；worker 被取消、panic 或提前
/// 退出时也发布安全的“结果待核实”错误。不在 `Drop` 中派发任务或做阻塞 IO。
struct CompletionGuard<T> {
    completion: Arc<TypedCompletion<T>>,
    published: bool,
}

impl<T> CompletionGuard<T> {
    fn new(completion: Arc<TypedCompletion<T>>) -> Self {
        Self {
            completion,
            published: false,
        }
    }

    fn publish(&mut self, outcome: Result<T, FeishuError>) {
        self.completion
            .outcome
            .send_replace(Some(Arc::new(outcome)));
        self.completion.interrupted.store(false, Ordering::Release);
        self.published = true;
    }
}

impl<T> Drop for CompletionGuard<T> {
    fn drop(&mut self) {
        if self.published {
            return;
        }
        // Sender 仍由记录持有，通道不会自然关闭；必须主动写入可安全重等的错误。
        self.completion.interrupted.store(true, Ordering::Release);
        self.completion
            .outcome
            .send_replace(Some(Arc::new(Err(interrupted_error()))));
    }
}

enum ActiveCompletion {
    Command(Arc<TypedCompletion<BotsCommandReply>>),
    Registration(Arc<TypedCompletion<CredentialCommit>>),
}

impl ActiveCompletion {
    fn fingerprint(&self) -> &CommandFingerprint {
        match self {
            Self::Command(completion) => &completion.fingerprint,
            Self::Registration(completion) => &completion.fingerprint,
        }
    }
}

pub(crate) struct BotOperationOwner {
    bot_id: String,
    runtime: BotRuntime,
    serial: Mutex<()>,
    task: Mutex<Option<JoinHandle<()>>>,
    blocking: Mutex<Option<JoinHandle<()>>>,
    inspect: Mutex<Option<JoinHandle<()>>>,
    completions: Mutex<CompletionSlot>,
    /// 已确认清理失败、仍待同一信任值重提完成的配对请求身份。
    pairing_cleanup: Mutex<BTreeSet<String>>,
    submitting: AtomicBool,
}

/// 已完成操作的结果保留位置：`current` 是最近受理的操作，`previous` 是上一操作。
/// 调用方停止等待后再次提交同一操作时仍取回已保存结果，而不是重复执行。
struct CompletionSlot {
    current: Option<ActiveCompletion>,
    previous: Option<ActiveCompletion>,
}

impl CompletionSlot {
    fn new() -> Self {
        Self {
            current: None,
            previous: None,
        }
    }

    fn iter(&self) -> impl Iterator<Item = &ActiveCompletion> {
        self.current.iter().chain(self.previous.iter())
    }

    /// 登记本次操作：旧 `current` 降为 `previous`，更早的结果不再保留。
    fn register(&mut self, completion: ActiveCompletion) {
        self.previous = self.current.take();
        self.current = Some(completion);
    }
}

#[derive(Clone, PartialEq, Eq)]
enum CommandFingerprint {
    Save(SaveFingerprint),
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
    RegistrationSave {
        operation_id: String,
        bot_id: String,
        name: String,
        project_id: String,
        app_id: String,
        secret: SecretFingerprint,
        trusted_open_id: Option<String>,
    },
}

#[derive(Clone, PartialEq, Eq)]
struct SaveFingerprint {
    operation_id: String,
    bot_id: String,
    expected_config_revision: u64,
    name: String,
    project_id: String,
    app_id: String,
    secret: SecretFingerprint,
    enabled: bool,
    tools_enabled: bool,
}

#[derive(Clone, PartialEq, Eq)]
enum SecretFingerprint {
    Preserve,
    Clear,
    Replace(String),
}

impl std::fmt::Debug for SecretFingerprint {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Preserve => formatter.write_str("Preserve"),
            Self::Clear => formatter.write_str("Clear"),
            Self::Replace(_) => formatter.write_str("Replace(<redacted>)"),
        }
    }
}

pub(crate) struct RegistrationSave {
    pub bot_id: String,
    pub name: String,
    pub project_id: String,
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

/// 跨机器人应用唯一性的一次裁决结果。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum AppClaim {
    /// 本 owner 现在持有该应用（新登记或已是同一目标）。
    Held,
    /// 另一个机器人已发布或已认领同一应用。
    Conflict,
    /// 本 owner 仍有未收束的清理/停连义务或未决目标：先显式 Retry 完成原义务。
    Unsettled,
    /// 运行时已封口或资源记录已释放，不能再登记新工作。
    Sealed,
}

/// 已确定的提交事实：可发布配置与仍需保留的候选目标应用。
struct SettledCommit {
    commit: CredentialCommit,
    candidate_app: Option<String>,
}

/// 确定事实收尾的连接与投影选项。
struct FinalizeOptions {
    /// 是否由本次收尾启动连接（注册路径留给其保存回执后的既有入口）。
    start_connection: bool,
    /// 连接重协调上下文（启动恢复/显式 Retry）：确定事实即使未应用也重建连接。
    coordinate_connection: bool,
    /// 已确定保存后需要清理的受信联系人配对。
    clear_pairing: Option<String>,
}

/// 收尾可观察的连接结果：只用于显式重试用例报告，不改变保存结论。
struct CommitSettlement {
    connection_error: Option<FeishuError>,
}

/// 旧连接隔离结果。
enum ConnectionQuiesce {
    Stopped,
    StopFailed(FeishuError),
}

/// 目录核实的最终裁决：确定事实交给统一收尾，或已核实的未决状态。
enum SettleOutcome {
    Determined(Box<SettledCommit>),
    Uncertain(FeishuError),
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

impl BotRuntime {
    pub(crate) fn new_record(runtime: BotRuntime, bot_id: String) -> BotRecord {
        BotRecord {
            published: None,
            operation: Arc::new(BotOperationOwner::new(runtime, bot_id)),
            published_app_id: None,
            claimed_app_id: None,
            cleanup_app_id: None,
            pending_stop_app_id: None,
            pending: None,
            watch: Arc::new(Mutex::new(WatchSlot::new())),
        }
    }

    pub(crate) async fn ensure_record(
        &self,
        bot_id: &str,
    ) -> Result<Arc<BotOperationOwner>, FeishuError> {
        let mut records = self.inner.bots.lock().await;
        if let Some(record) = records.get(bot_id) {
            return Ok(record.operation.clone());
        }
        if self.inner.sealed.load(Ordering::SeqCst) != 0 {
            return Err(sealed_error());
        }
        records.insert(
            bot_id.to_string(),
            Self::new_record(self.clone(), bot_id.to_string()),
        );
        Ok(records
            .get(bot_id)
            .expect("inserted bot record")
            .operation
            .clone())
    }

    pub(crate) async fn pending_projections(&self) -> Vec<BotPendingCredentialOperation> {
        let records = self.inner.bots.lock().await;
        let mut pending = records
            .values()
            .filter(|record| record.published.is_none())
            .filter_map(|record| record.pending.clone())
            .map(|pending| BotPendingCredentialOperation {
                bot_id: pending.bot_id,
                credential_operation: pending.operation,
                diagnostic: pending.diagnostic,
            })
            .collect::<Vec<_>>();
        pending.sort_by(|left, right| left.bot_id.cmp(&right.bot_id));
        pending
    }

    pub(crate) fn management_sealed(&self) -> bool {
        self.inner.sealed.load(Ordering::SeqCst) != 0
    }

    pub(crate) fn reject_if_sealed(&self) -> Result<(), FeishuError> {
        if self.management_sealed() {
            Err(sealed_error())
        } else {
            Ok(())
        }
    }

    pub async fn save_bot(
        &self,
        request: SaveBotRequest,
        owner_epoch: &str,
    ) -> Result<BotsCommandReply, FeishuError> {
        self.reject_if_sealed()?;
        validate_app_id(&request.app_id)?;
        if request.name.trim().is_empty() || request.project_id.trim().is_empty() {
            return Err(FeishuError::new(
                FeishuErrorKind::Rejected,
                "bot name and projectId are required",
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
        request: RegistrationSave,
    ) -> Result<CredentialCommit, FeishuError> {
        self.reject_if_sealed()?;
        validate_bot_id(&request.bot_id)?;
        validate_app_id(&request.app_id)?;
        let owner = self.ensure_record(&request.bot_id).await?;
        owner.submit_registration_save(request).await
    }

    pub(crate) async fn recover_bot_dir(&self, bot_id: &str) -> Result<(), FeishuError> {
        let dir = self.inner.paths.bot_dir(bot_id);
        let loaded = load_config_for_recovery(&dir)?;
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

    /// 合法 safe-id 目录读取或恢复失败：保留原现场，用既有 pending/诊断投影让它可见并
    /// 可明确本地重试。不构造默认配置、不删除目录、不阻断其它机器人；诊断只用固定
    /// 安全分类，不输出可能携带损坏文件正文的解析错误。
    pub(crate) async fn note_unreadable_directory(&self, bot_id: &str) {
        let Ok(owner) = self.ensure_record(bot_id).await else {
            return;
        };
        let diagnostic = FeishuError::new(
            FeishuErrorKind::Unavailable,
            BOT_DIRECTORY_UNREADABLE,
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

    pub(crate) async fn close_connection_watches(&self) -> Result<(), FeishuError> {
        let records = self.inner.bots.lock().await;
        let slots = records
            .values()
            .map(|record| record.watch.clone())
            .collect::<Vec<_>>();
        drop(records);
        for slot in slots {
            let mut guard = slot.lock().await;
            if let Err(error) = guard.join().await {
                // 及时上报已观察错误：不再 await 其他 slot，剩余句柄保持登记可重试。
                return Err(FeishuError::new(
                    FeishuErrorKind::Unavailable,
                    format!("bot connection watch join failed: {error}"),
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

    /// 在 registry 的同一临界区内完成“检查其它 owner 已发布/已认领的应用 + 登记本
    /// owner 的准备目标”。这是跨机器人应用唯一性的唯一裁决点：只做短内存读写，不
    /// 在锁内等待凭据访问、文件同步或连接回收，也不取 `ManagedBot` 的配置锁。
    ///
    /// 锁序：`bots` registry 是这里的唯一锁；每个 `BotRecord` 的
    /// `published_app_id`/`claimed_app_id`/`cleanup_app_id`/`pending_stop_app_id`
    /// 共同表达该机器人仍须保护的完整应用事实，写入都发生在同一提交 owner 内，
    /// 因而不需要嵌套其它锁，也不是第二份 App→bot 索引。
    async fn claim_app_target(&self, bot_id: &str, app_id: &str) -> AppClaim {
        let mut records = self.inner.bots.lock().await;
        if self.inner.sealed.load(Ordering::SeqCst) != 0 {
            return AppClaim::Sealed;
        }
        let Some(record) = records.get(bot_id) else {
            return AppClaim::Sealed;
        };
        if record.claimed_app_id.as_deref() == Some(app_id) {
            return AppClaim::Held;
        }
        if record.claimed_app_id.is_some()
            || record.cleanup_app_id.is_some()
            || record.pending_stop_app_id.is_some()
        {
            // 本 owner 仍有未收束的目标/清理/停连义务：新意图先显式 Retry 完成原义务，
            // 不在候选准备或任何外部 IO 之前追加更多义务或被静默换掉。
            return AppClaim::Unsettled;
        }
        for (other_id, other) in records.iter() {
            if other_id == bot_id {
                continue;
            }
            if record_holds_app(other, app_id) {
                return AppClaim::Conflict;
            }
        }
        match records.get_mut(bot_id) {
            Some(record) => {
                record.claimed_app_id = Some(app_id.to_string());
                AppClaim::Held
            }
            None => AppClaim::Sealed,
        }
    }

    /// 在短 registry 临界区把已确定配置的应用登记为发布占用，并归还准备目标。
    /// 调用方必须已在旧连接真实停止后调用；冲突时不覆盖其它 owner。
    async fn promote_app_claim(&self, bot_id: &str, app_id: &str) -> AppClaim {
        let mut records = self.inner.bots.lock().await;
        if self.inner.sealed.load(Ordering::SeqCst) != 0 {
            return AppClaim::Sealed;
        }
        for (other_id, other) in records.iter() {
            if other_id == bot_id {
                continue;
            }
            if record_holds_app(other, app_id) {
                return AppClaim::Conflict;
            }
        }
        match records.get_mut(bot_id) {
            Some(record) => {
                record.published_app_id = Some(app_id.to_string());
                if record.claimed_app_id.as_deref() == Some(app_id) {
                    record.claimed_app_id = None;
                }
                AppClaim::Held
            }
            None => AppClaim::Sealed,
        }
    }

    /// 取走准备目标：只有提交已确定且没有清理义务时才真正归还。
    async fn take_prep_claim(&self, bot_id: &str) -> Option<String> {
        self.inner
            .bots
            .lock()
            .await
            .get_mut(bot_id)
            .and_then(|record| record.claimed_app_id.take())
    }

    /// 未提交候选仍待清理：保留候选目标应用，直到清理真实完成。
    async fn retain_cleanup_app(&self, bot_id: &str, app_id: &str) {
        if let Some(record) = self.inner.bots.lock().await.get_mut(bot_id) {
            record.cleanup_app_id = Some(app_id.to_string());
        }
    }

    /// 清理义务已真实完成：释放候选目标占用。
    async fn clear_cleanup_app(&self, bot_id: &str) {
        if let Some(record) = self.inner.bots.lock().await.get_mut(bot_id) {
            record.cleanup_app_id = None;
        }
    }

    /// 旧连接未被确认真实停止：保留旧应用占用，避免其它机器人接管仍在使用的应用。
    async fn retain_pending_stop_app(&self, bot_id: &str, app_id: &str) {
        if let Some(record) = self.inner.bots.lock().await.get_mut(bot_id) {
            // 保留最早未确认停止的旧应用，后续失败不得用新配置的应用覆盖它。
            if record.pending_stop_app_id.is_none() {
                record.pending_stop_app_id = Some(app_id.to_string());
            }
        }
    }

    /// 旧连接已真实 join：释放旧应用占用。
    async fn clear_pending_stop_app(&self, bot_id: &str) {
        if let Some(record) = self.inner.bots.lock().await.get_mut(bot_id) {
            record.pending_stop_app_id = None;
        }
    }

    /// 确定未提交且已无未决义务：归还准备目标；已发布占用保持不变。
    async fn release_app_claim(&self, bot_id: &str) {
        if let Some(record) = self.inner.bots.lock().await.get_mut(bot_id) {
            record.claimed_app_id = None;
        }
    }

    async fn claim_app_target_or_error(
        &self,
        bot_id: &str,
        app_id: &str,
    ) -> Result<(), FeishuError> {
        match self.claim_app_target(bot_id, app_id).await {
            AppClaim::Held => Ok(()),
            AppClaim::Conflict => Err(duplicate_app_error()),
            AppClaim::Unsettled => Err(unsettled_intent_error()),
            AppClaim::Sealed => Err(sealed_error()),
        }
    }

    /// 只读的新意图 guard：本 owner 仍有未收束目标/清理/停连义务时先拒绝，
    /// 不登记新占用、不进入候选准备或外部 IO。
    async fn reject_unsettled_obligation(&self, bot_id: &str) -> Result<(), FeishuError> {
        let records = self.inner.bots.lock().await;
        let Some(record) = records.get(bot_id) else {
            return Ok(());
        };
        if record.claimed_app_id.is_some()
            || record.cleanup_app_id.is_some()
            || record.pending_stop_app_id.is_some()
        {
            return Err(unsettled_intent_error());
        }
        Ok(())
    }

    pub(crate) async fn spawn_connection_watch(&self, managed: &Arc<ManagedBot>) {
        if self.management_sealed() {
            return;
        }
        let bot_id = managed.config.lock().await.id.clone();
        let slot = {
            let records = self.inner.bots.lock().await;
            let Some(record) = records.get(&bot_id) else {
                return;
            };
            record.watch.clone()
        };
        let mut guard = slot.lock().await;
        if self.management_sealed() {
            return;
        }
        if let Err(error) = guard.join().await {
            tracing::warn!(bot_id, %error, "previous bot connection watch join failed");
        }
        if self.management_sealed() {
            return;
        }
        guard.cancel = CancellationToken::new();
        let cancel = guard.cancel.clone();
        let mut rx = managed.connection.subscribe();
        let runtime = self.clone();
        runtime.request_publish();
        let handle = tokio::spawn(async move {
            loop {
                tokio::select! {
                    _ = cancel.cancelled() => return,
                    changed = rx.changed() => {
                        if changed.is_err() {
                            return;
                        }
                        runtime.request_publish();
                    }
                }
            }
        });
        if self.management_sealed() {
            guard.cancel.cancel();
            guard.handle = Some(handle);
            let _ = guard.join().await;
            return;
        }
        guard.handle = Some(handle);
    }
}

impl BotOperationOwner {
    fn new(runtime: BotRuntime, bot_id: String) -> Self {
        Self {
            bot_id,
            runtime,
            serial: Mutex::new(()),
            task: Mutex::new(None),
            blocking: Mutex::new(None),
            inspect: Mutex::new(None),
            completions: Mutex::new(CompletionSlot::new()),
            pairing_cleanup: Mutex::new(BTreeSet::new()),
            submitting: AtomicBool::new(false),
        }
    }

    async fn submit(
        &self,
        mutation: BotMutation,
        owner_epoch: String,
    ) -> Result<BotsCommandReply, FeishuError> {
        let fingerprint = fingerprint_of(&mutation, &self.bot_id);
        let owner = self.runtime.ensure_record(&self.bot_id).await?;
        let completion = self
            .claim_command(&fingerprint, &owner, mutation, owner_epoch)
            .await?;
        wait_typed(&completion.outcome).await
    }

    async fn claim_command(
        &self,
        fingerprint: &CommandFingerprint,
        owner: &Arc<BotOperationOwner>,
        mutation: BotMutation,
        owner_epoch: String,
    ) -> Result<Arc<TypedCompletion<BotsCommandReply>>, FeishuError> {
        let mut slot = self.task.lock().await;
        let mut completions = self.completions.lock().await;
        for existing in completions.iter() {
            if existing.fingerprint() != fingerprint {
                continue;
            }
            match existing {
                ActiveCompletion::Command(completion) if !completion.is_interrupted() => {
                    // 同一输入的重复提交复用已保存结果（含先前完成后才订阅的等待者）。
                    return Ok(completion.clone());
                }
                ActiveCompletion::Command(_) => {
                    // 上次 worker 未发布结果：本次重新执行，不永久复报不可用结果。
                }
                ActiveCompletion::Registration(_) => return Err(operation_conflict_error()),
            }
        }
        if completions
            .iter()
            .any(|existing| conflicting_operation_id(existing.fingerprint(), fingerprint))
        {
            return Err(operation_conflict_error());
        }
        if slot.as_ref().is_some_and(|handle| !handle.is_finished()) {
            return Err(busy_error());
        }
        if self.runtime.management_sealed() {
            return Err(sealed_error());
        }
        self.drain_task_terminal(&mut slot).await;
        if self.runtime.management_sealed() {
            return Err(sealed_error());
        }
        let completion = Arc::new(TypedCompletion::new(fingerprint.clone()));
        completions.register(ActiveCompletion::Command(completion.clone()));
        drop(completions);
        let worker = owner.clone();
        let published = completion.clone();
        let handle = tokio::spawn(async move {
            // 完成责任跨整个执行期持有：panic、取消或提前退出也结束原等待。
            let mut guard = CompletionGuard::new(published);
            let _serial = worker.serial.lock().await;
            let outcome = worker.execute(mutation, owner_epoch).await;
            guard.publish(outcome);
        });
        *slot = Some(handle);
        Ok(completion)
    }

    async fn execute(
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
                            config.trusted_open_ids.insert(open_id.clone());
                        } else {
                            config.trusted_open_ids.remove(&open_id);
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
                            config.trusted_chat_ids.insert(chat_id.clone());
                        } else {
                            config.trusted_chat_ids.remove(&chat_id);
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
            project_id,
            app_id,
            secret,
            enabled,
            tools_enabled,
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
            if previous.project_id != project_id && occupancy.has_thread_or_inbound {
                return Err(FeishuError::new(
                    FeishuErrorKind::Rejected,
                    "projectId cannot change after Thread mapping or admitted input exists",
                    false,
                    None,
                ));
            }
            if previous.app_id != app_id
                && (occupancy.has_app_identity
                    || !previous.trusted_open_ids.is_empty()
                    || !previous.trusted_chat_ids.is_empty())
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
                project_id.clone(),
                app_id.clone(),
            )?,
        };
        self.runtime
            .claim_app_target_or_error(&bot_id, &app_id)
            .await?;
        candidate.name = name;
        candidate.project_id = project_id;
        candidate.app_id = app_id;
        candidate.enabled = enabled;
        candidate.tools_enabled = tools_enabled;
        if previous.is_some() {
            candidate.bump();
        }
        self.set_pending(
            BotCredentialOperation::Preparing {
                operation_id: operation_id.clone(),
            },
            None,
        )
        .await;
        self.runtime.publish().await;
        let dir = self.runtime.inner.paths.bot_dir(&bot_id);
        let credentials = self.runtime.inner.config.bot_credentials();
        let baseline = previous.clone().unwrap_or_else(|| candidate.clone());
        let worker_operation_id = operation_id.clone();
        let prepared = match self
            .run_blocking(move || {
                prepare_bot_credentials(
                    &dir,
                    &bot_id,
                    &credentials,
                    &baseline,
                    candidate,
                    secret,
                    &worker_operation_id,
                )
            })
            .await
        {
            Ok(prepared) => prepared,
            Err(error) => {
                return self
                    .settle_prepare_failure(error, &operation_id, owner_epoch)
                    .await;
            }
        };
        match prepared {
            CredentialPrepare::Decided(commit) => {
                self.finish_decision(
                    SettledCommit {
                        commit: *commit,
                        candidate_app: None,
                    },
                    previous.as_ref(),
                    owner_epoch,
                    None,
                )
                .await
            }
            CredentialPrepare::Ready(prepared) => {
                self.commit_after_gate(*prepared, previous, owner_epoch, None)
                    .await
            }
        }
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
            .claim_app_target_or_error(&self.bot_id, &candidate.app_id)
            .await?;
        self.set_pending(
            BotCredentialOperation::Preparing {
                operation_id: operation_id.clone(),
            },
            None,
        )
        .await;
        self.runtime.publish().await;
        let dir = self.runtime.inner.paths.bot_dir(&self.bot_id);
        let credentials = self.runtime.inner.config.bot_credentials();
        let expected_bot_id = self.bot_id.clone();
        let worker_operation_id = operation_id.clone();
        let prepared = match self
            .run_blocking({
                let previous = previous.clone();
                move || {
                    prepare_bot_credentials(
                        &dir,
                        &expected_bot_id,
                        &credentials,
                        &previous,
                        candidate,
                        BotSecretUpdate::Preserve,
                        &worker_operation_id,
                    )
                }
            })
            .await
        {
            Ok(prepared) => prepared,
            Err(error) => {
                return self
                    .settle_prepare_failure(error, &operation_id, &owner_epoch)
                    .await;
            }
        };
        match prepared {
            CredentialPrepare::Decided(commit) => {
                self.finish_decision(
                    SettledCommit {
                        commit: *commit,
                        candidate_app: None,
                    },
                    Some(&previous),
                    &owner_epoch,
                    clear_pairing,
                )
                .await
            }
            CredentialPrepare::Ready(prepared) => {
                self.commit_after_gate(*prepared, Some(previous), &owner_epoch, clear_pairing)
                    .await
            }
        }
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
            None => Ok(self.runtime.reply(operation_id, true, owner_epoch).await),
        }
    }

    async fn recover_existing(
        &self,
        loaded: Option<BotConfigFile>,
    ) -> Result<Option<SettledCommit>, FeishuError> {
        let _serial = self.serial.lock().await;
        match self.verify_recovered_directory(loaded, None).await {
            VerifiedDirectory::Determined(settled) => Ok(Some(*settled)),
            // 未决与不可核实都已更新投影并保持封口；加载继续，不丢弃现场。
            VerifiedDirectory::Unpublished
            | VerifiedDirectory::Uncertain(_)
            | VerifiedDirectory::Unverified(_) => Ok(None),
        }
    }

    async fn submit_registration_save(
        &self,
        request: RegistrationSave,
    ) -> Result<CredentialCommit, FeishuError> {
        let fingerprint = CommandFingerprint::RegistrationSave {
            operation_id: request.operation_id.clone(),
            bot_id: request.bot_id.clone(),
            name: request.name.clone(),
            project_id: request.project_id.clone(),
            app_id: request.app_id.clone(),
            secret: SecretFingerprint::Replace(request.secret.clone()),
            trusted_open_id: request.trusted_open_id.clone(),
        };
        let owner = self.runtime.ensure_record(&self.bot_id).await?;
        let completion = self
            .claim_registration(&fingerprint, &owner, request)
            .await?;
        wait_typed(&completion.outcome).await
    }

    async fn claim_registration(
        &self,
        fingerprint: &CommandFingerprint,
        owner: &Arc<BotOperationOwner>,
        request: RegistrationSave,
    ) -> Result<Arc<TypedCompletion<CredentialCommit>>, FeishuError> {
        let mut slot = self.task.lock().await;
        let mut completions = self.completions.lock().await;
        for existing in completions.iter() {
            if existing.fingerprint() != fingerprint {
                continue;
            }
            match existing {
                ActiveCompletion::Registration(completion) if !completion.is_interrupted() => {
                    return Ok(completion.clone());
                }
                ActiveCompletion::Registration(_) => {}
                ActiveCompletion::Command(_) => return Err(operation_conflict_error()),
            }
        }
        if completions
            .iter()
            .any(|existing| conflicting_operation_id(existing.fingerprint(), fingerprint))
        {
            return Err(operation_conflict_error());
        }
        if slot.as_ref().is_some_and(|handle| !handle.is_finished()) {
            return Err(busy_error());
        }
        if self.runtime.management_sealed() {
            return Err(sealed_error());
        }
        self.drain_task_terminal(&mut slot).await;
        if self.runtime.management_sealed() {
            return Err(sealed_error());
        }
        let completion = Arc::new(TypedCompletion::new(fingerprint.clone()));
        completions.register(ActiveCompletion::Registration(completion.clone()));
        drop(completions);
        let worker = owner.clone();
        let published = completion.clone();
        let handle = tokio::spawn(async move {
            let mut guard = CompletionGuard::new(published);
            let _serial = worker.serial.lock().await;
            let outcome = worker.run_registration_save(request).await;
            guard.publish(outcome);
        });
        *slot = Some(handle);
        Ok(completion)
    }

    async fn run_registration_save(
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
            project_id,
            app_id,
            secret,
            trusted_open_id,
            operation_id,
            ..
        } = request;
        let mut config = BotConfigFile::new(self.bot_id.clone(), name, project_id, app_id.clone())?;
        if let Some(open_id) = trusted_open_id {
            config.trusted_open_ids.insert(open_id);
        }
        self.runtime
            .claim_app_target_or_error(&self.bot_id, &app_id)
            .await?;
        self.set_pending(
            BotCredentialOperation::Preparing {
                operation_id: operation_id.clone(),
            },
            None,
        )
        .await;
        let dir = self.runtime.inner.paths.bot_dir(&self.bot_id);
        let credentials = self.runtime.inner.config.bot_credentials();
        let expected_bot_id = self.bot_id.clone();
        let worker_operation_id = operation_id.clone();
        let prepared = match self
            .run_blocking({
                let previous = config.clone();
                move || {
                    prepare_bot_credentials(
                        &dir,
                        &expected_bot_id,
                        &credentials,
                        &previous,
                        config,
                        BotSecretUpdate::Replace { value: secret },
                        &worker_operation_id,
                    )
                }
            })
            .await
        {
            Ok(prepared) => prepared,
            Err(error) => {
                // 准备异常也要按原 journal 核实：已确定提交不能改报未保存。
                return match self
                    .settle_prepare_failure_inner(error.clone(), &operation_id)
                    .await
                {
                    Ok(settled) => {
                        self.finalize_commit(
                            &settled,
                            None,
                            FinalizeOptions {
                                start_connection: false,
                                coordinate_connection: true,
                                clear_pairing: None,
                            },
                        )
                        .await?;
                        self.clear_submitting().await;
                        Ok(settled.commit)
                    }
                    Err(settled_error) => Err(settled_error),
                };
            }
        };
        let expected = None;
        let commit = match prepared {
            CredentialPrepare::Decided(commit) => *commit,
            CredentialPrepare::Ready(prepared) => {
                self.commit_or_abandon(*prepared, expected).await?
            }
        };
        let settled = SettledCommit {
            commit,
            candidate_app: None,
        };
        // 注册成功路径的连接启动仍由保存回执后的既有入口负责；这里只完成旧连接
        // 隔离、认领收敛、确定配置发布与准入恢复。
        self.finalize_commit(
            &settled,
            None,
            FinalizeOptions {
                start_connection: false,
                coordinate_connection: true,
                clear_pairing: None,
            },
        )
        .await?;
        self.clear_submitting().await;
        Ok(settled.commit)
    }

    async fn commit_after_gate(
        &self,
        prepared: PreparedCredential,
        previous: Option<BotConfigFile>,
        owner_epoch: &str,
        clear_pairing: Option<String>,
    ) -> Result<BotsCommandReply, FeishuError> {
        match self
            .gate_prepared(previous.as_ref(), &prepared.target)
            .await
        {
            Ok(()) => {
                let operation_id = prepared.operation_id.clone();
                let dir = self.runtime.inner.paths.bot_dir(&self.bot_id);
                let credentials = self.runtime.inner.config.bot_credentials();
                let committed = self
                    .run_blocking(move || commit_prepared_credentials(&dir, &credentials, prepared))
                    .await;
                let settled = match committed {
                    Ok(commit) => SettledCommit {
                        commit,
                        candidate_app: None,
                    },
                    Err(error) => match self.settle_interrupted(&operation_id, error).await? {
                        SettleOutcome::Determined(settled) => *settled,
                        SettleOutcome::Uncertain(error) => return Err(error),
                    },
                };
                self.finish_decision(settled, previous.as_ref(), owner_epoch, clear_pairing)
                    .await
            }
            Err(rejection) => {
                let operation_id = prepared.operation_id.clone();
                let dir = self.runtime.inner.paths.bot_dir(&self.bot_id);
                let credentials = self.runtime.inner.config.bot_credentials();
                let abandoned = self
                    .run_blocking(move || {
                        abandon_prepared_credentials(&dir, &credentials, prepared)
                    })
                    .await;
                let settled = match abandoned {
                    Ok(commit) => SettledCommit {
                        commit,
                        candidate_app: None,
                    },
                    Err(error) => match self.settle_interrupted(&operation_id, error).await {
                        Ok(SettleOutcome::Determined(settled)) => *settled,
                        Ok(SettleOutcome::Uncertain(error)) => return Err(error),
                        Err(error) => return Err(error),
                    },
                };
                // 已确定 Applied 是真实保存事实，不能被子系统拒绝原因抹掉；只有确定
                // 未应用时才保留本次准入拒绝。
                if settled.commit.decision == CredentialDecision::Applied {
                    return self
                        .finish_decision(settled, previous.as_ref(), owner_epoch, None)
                        .await;
                }
                let _ = self
                    .finalize_commit(
                        &settled,
                        previous.as_ref(),
                        FinalizeOptions {
                            start_connection: false,
                            coordinate_connection: false,
                            clear_pairing: None,
                        },
                    )
                    .await;
                Err(rejection)
            }
        }
    }

    async fn commit_or_abandon(
        &self,
        prepared: PreparedCredential,
        expected: Option<BotConfigFile>,
    ) -> Result<CredentialCommit, FeishuError> {
        let operation_id = prepared.operation_id.clone();
        match self
            .gate_prepared(expected.as_ref(), &prepared.target)
            .await
        {
            Ok(()) => {
                let dir = self.runtime.inner.paths.bot_dir(&self.bot_id);
                let credentials = self.runtime.inner.config.bot_credentials();
                match self
                    .run_blocking(move || commit_prepared_credentials(&dir, &credentials, prepared))
                    .await
                {
                    Ok(commit) => Ok(commit),
                    Err(error) => match self.settle_interrupted(&operation_id, error).await? {
                        SettleOutcome::Determined(settled) => Ok(settled.commit),
                        SettleOutcome::Uncertain(error) => Err(error),
                    },
                }
            }
            Err(_) => {
                let dir = self.runtime.inner.paths.bot_dir(&self.bot_id);
                let credentials = self.runtime.inner.config.bot_credentials();
                let abandoned = self
                    .run_blocking(move || {
                        abandon_prepared_credentials(&dir, &credentials, prepared)
                    })
                    .await;
                match abandoned {
                    Ok(commit) => Ok(commit),
                    Err(error) => match self.settle_interrupted(&operation_id, error).await? {
                        SettleOutcome::Determined(settled) => Ok(settled.commit),
                        SettleOutcome::Uncertain(error) => Err(error),
                    },
                }
            }
        }
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
            if current.project_id != target.project_id && occupancy.has_thread_or_inbound {
                return Err(FeishuError::new(
                    FeishuErrorKind::Rejected,
                    "projectId cannot change after Thread mapping or admitted input exists",
                    false,
                    None,
                ));
            }
            if current.app_id != target.app_id
                && (occupancy.has_app_identity
                    || !current.trusted_open_ids.is_empty()
                    || !current.trusted_chat_ids.is_empty())
            {
                return Err(FeishuError::new(
                    FeishuErrorKind::Rejected,
                    "appId cannot change after platform conversations or durable records exist",
                    false,
                    None,
                ));
            }
            self.runtime
                .claim_app_target_or_error(&self.bot_id, &target.app_id)
                .await?;
            managed.admission_closed.store(true, Ordering::Release);
            managed.submitting.store(true, Ordering::Release);
            self.submitting.store(true, Ordering::Release);
            return Ok(());
        }
        self.runtime
            .claim_app_target_or_error(&self.bot_id, &target.app_id)
            .await?;
        self.submitting.store(true, Ordering::Release);
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
            CredentialDecision::Applied => {
                Ok(self.runtime.reply(operation_id, true, owner_epoch).await)
            }
            CredentialDecision::Uncertain => Err(uncertain_error(&operation_id)),
            CredentialDecision::NotApplied => Err(not_applied),
        }
    }

    /// 提交/恢复确定后统一收尾：短 admission 边界封口并失效旧回调 → 不持
    /// registry/config 锁取消并等待旧连接真实 stop/join → 短 registry 收敛认领 →
    /// 发布确定配置 → 旧连接已收束且配置已核实后恢复准入 → 按既有入口登记新连接。
    async fn finalize_commit(
        &self,
        settled: &SettledCommit,
        previous: Option<&BotConfigFile>,
        options: FinalizeOptions,
    ) -> Result<CommitSettlement, FeishuError> {
        let commit = &settled.commit;
        if commit.decision == CredentialDecision::Uncertain {
            self.publish_uncertain_state(
                &commit.config.app_id,
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
        let previous_app = managed.config.lock().await.app_id.clone();
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
        let claim = self
            .runtime
            .promote_app_claim(&self.bot_id, &commit.config.app_id)
            .await;
        let prep = self.runtime.take_prep_claim(&self.bot_id).await;
        // 已提交或未提交候选的清理义务都算未收束：即使应用与已发布配置相同，
        // 新意图也必须先由显式 Retry 完成清理。
        let retain_candidate = matches!(
            commit.operation,
            BotCredentialOperation::CleanupPending { .. }
        );
        let candidate = settled
            .candidate_app
            .clone()
            .or_else(|| prep.filter(|app| retain_candidate && app != &commit.config.app_id))
            .or_else(|| retain_candidate.then(|| commit.config.app_id.clone()));
        if let Some(candidate) = candidate
            && (retain_candidate || candidate != commit.config.app_id)
        {
            self.runtime
                .retain_cleanup_app(&self.bot_id, &candidate)
                .await;
        } else if matches!(commit.operation, BotCredentialOperation::Idle) {
            self.runtime.clear_cleanup_app(&self.bot_id).await;
        }
        let claim_ok = claim == AppClaim::Held;
        if !claim_ok {
            // 该应用已被另一 owner 占用并因此继续受保护；本记录只关闭准入并诊断。
            self.merge_managed_diagnostic(&managed, duplicate_app_error().diagnostic())
                .await;
        }
        if let Some(error) = &stop_error {
            // 连接回收失败独立诊断：保存结论仍是 Applied，旧应用与目标都继续受保护。
            self.merge_managed_diagnostic(&managed, error.diagnostic())
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

    /// 不可发布的确定结论：没有可运行配置，只更新投影与必要占用。
    async fn finalize_unpublished(&self, commit: &CredentialCommit, candidate: Option<&str>) {
        let prep = self.runtime.take_prep_claim(&self.bot_id).await;
        let candidate = candidate.map(str::to_string).or(prep);
        if matches!(
            commit.operation,
            BotCredentialOperation::CleanupPending {
                config_committed: false,
                ..
            }
        ) {
            if let Some(candidate) = candidate {
                self.runtime
                    .retain_cleanup_app(&self.bot_id, &candidate)
                    .await;
            }
        } else {
            self.runtime.clear_cleanup_app(&self.bot_id).await;
        }
        self.set_pending(commit.operation.clone(), commit.diagnostic.clone())
            .await;
        if let Some(managed) = self.published().await {
            managed.admission_closed.store(true, Ordering::Release);
            self.merge_managed_diagnostic(
                &managed,
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

    /// 未决提交/清理投影：保留必要目标并继续封口，等待明确 Retry 核实。
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
            self.merge_managed_diagnostic(
                &managed,
                diagnostic.unwrap_or_else(unverified_diagnostic),
            )
            .await;
        }
        self.clear_submitting().await;
        self.runtime.publish().await;
    }

    /// 已确定配置的连接协调：停用即保持真实停止；启用则沿既有入口重新登记连接。
    /// 返回的连接错误只用于需要显式报告的调用方，保存结论不受影响。
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
            self.merge_managed_diagnostic(managed, error.diagnostic())
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
                self.merge_managed_diagnostic(managed, error.diagnostic())
                    .await;
                Some(error)
            }
        }
    }

    /// 已确定保存后的受信联系人配对清理：失败只追加授权中立的固定诊断并保留原
    /// pairing 行；已保存的当前信任集合不变，重复原信任值即可完成清理，无需撤销授权。
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
        self.merge_managed_diagnostic(
            &managed,
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

    /// 一次配对清理真实成功：仅当已无其它待清理请求身份时才移除该诊断条款。
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
        *slot = without_diagnostic_clause(slot.clone(), PAIRING_CLEANUP_PENDING);
    }

    /// 目录核实：失败时保留现场并给出固定安全错误；确定事实交给统一提交收尾。
    async fn verify_recovered_directory(
        &self,
        loaded: Option<BotConfigFile>,
        unverified: Option<BotCredentialOperation>,
    ) -> VerifiedDirectory {
        let dir = self.runtime.inner.paths.bot_dir(&self.bot_id);
        let credentials = self.runtime.inner.config.bot_credentials();
        let expected_bot_id = self.bot_id.clone();
        let recovered = match self
            .run_blocking(move || {
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
                            .map(|config| config.app_id.clone())
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
            *slot = merge_commit_diagnostic(slot.clone(), commit.diagnostic.clone());
        }
        if invalidate {
            managed.generation.fetch_add(1, Ordering::AcqRel);
            *managed.bot_open_id.lock().await = None;
            managed
                .token
                .replace(
                    commit.config.app_id.clone(),
                    commit.secret.clone().unwrap_or_default(),
                )
                .await;
        } else if let Some(secret) = commit.secret.clone() {
            managed
                .token
                .replace(commit.config.app_id.clone(), secret)
                .await;
        }
    }

    /// 后处理诊断合并而不是覆盖：独立清理义务不会被连接错误遮住。
    async fn merge_managed_diagnostic(&self, managed: &ManagedBot, diagnostic: BotDiagnostic) {
        let mut slot = managed.diagnostic.lock().await;
        *slot = Some(merge_diagnostic(slot.clone(), diagnostic));
    }

    /// 连接成功/停用后只清掉旧连接类诊断，保留独立的配对清理义务。
    async fn clear_non_cleanup_diagnostic(&self, managed: &ManagedBot) {
        let mut slot = managed.diagnostic.lock().await;
        *slot = slot
            .clone()
            .filter(|diagnostic| diagnostic.message.contains(PAIRING_CLEANUP_PENDING));
    }

    /// 短 admission 边界封口并让旧回调失效；随后在无 registry/config 锁的情况下
    /// 取消并等待旧连接真实 join。
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

    /// 仅在旧连接已真实停止、当前配置已核实后恢复准入；后续新回调捕获新配置。
    async fn open_admission(&self, managed: &Arc<ManagedBot>) {
        {
            let _admission = managed.admission.lock().await;
            managed.admission_closed.store(false, Ordering::Release);
            managed.submitting.store(false, Ordering::Release);
        }
        self.submitting.store(false, Ordering::Release);
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
            diagnostic: Mutex::new(None),
            generation: Arc::new(AtomicU64::new(0)),
            token: TokenLease::new(
                self.runtime.inner.http.clone(),
                config.app_id.clone(),
                String::new(),
            ),
            bot_open_id: Mutex::new(None),
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
        let app_id = config.app_id.clone();
        let selected = config.selected_ref.clone();
        let inspected = self
            .run_inspect(move || {
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
                || current.app_id != config.app_id
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
                .replace(config.app_id.clone(), secret.clone())
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
                diagnostic: diagnostic.clone(),
            });
        }
        drop(records);
        if let Some(managed) = self.published().await {
            *managed.credential_operation.lock().await = operation;
            let mut slot = managed.diagnostic.lock().await;
            *slot = merge_commit_diagnostic(slot.clone(), diagnostic);
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
                    diagnostic,
                });
            }
        }
    }

    async fn run_blocking<T, F>(&self, job: F) -> Result<T, FeishuError>
    where
        T: Send + 'static,
        F: FnOnce() -> Result<T, FeishuError> + Send + 'static,
    {
        let (tx, rx) = oneshot::channel();
        {
            let mut slot = self.blocking.lock().await;
            self.drain_blocking_terminal(&mut slot).await;
            let handle = tokio::task::spawn_blocking(move || {
                let _ = tx.send(job());
            });
            *slot = Some(handle);
        }
        let result = match rx.await {
            Ok(result) => result,
            Err(_) => {
                // worker 未返回结果就结束：先消费终态一次，再报告原始失败。
                let mut slot = self.blocking.lock().await;
                self.drain_blocking_terminal(&mut slot).await;
                return Err(FeishuError::new(
                    FeishuErrorKind::Unavailable,
                    "bot credential worker ended before returning",
                    true,
                    None,
                ));
            }
        };
        let mut slot = self.blocking.lock().await;
        if self.join_slot(&mut slot).await.is_err() {
            // 结果已取得；异常终态只保留安全分类，不覆盖真实结果。
            tracing::warn!(
                bot_id = %self.bot_id,
                "bot credential worker terminated abnormally after returning its result"
            );
        }
        result
    }

    async fn run_inspect<T, F>(&self, job: F) -> Result<T, FeishuError>
    where
        T: Send + 'static,
        F: FnOnce() -> Result<T, FeishuError> + Send + 'static,
    {
        let (tx, rx) = oneshot::channel();
        {
            let mut slot = self.inspect.lock().await;
            self.drain_inspect_terminal(&mut slot).await;
            let handle = tokio::task::spawn_blocking(move || {
                let _ = tx.send(job());
            });
            *slot = Some(handle);
        }
        let result = match rx.await {
            Ok(result) => result,
            Err(_) => {
                let mut slot = self.inspect.lock().await;
                self.drain_inspect_terminal(&mut slot).await;
                return Err(FeishuError::new(
                    FeishuErrorKind::Unavailable,
                    "bot credential inspect ended before returning",
                    true,
                    None,
                ));
            }
        };
        let mut slot = self.inspect.lock().await;
        if self.join_slot(&mut slot).await.is_err() {
            tracing::warn!(
                bot_id = %self.bot_id,
                "bot credential inspect terminated abnormally after returning its result"
            );
        }
        result
    }

    async fn join_slot(&self, slot: &mut Option<JoinHandle<()>>) -> Result<(), FeishuError> {
        let Some(handle) = slot.as_mut() else {
            return Ok(());
        };
        let joined = Pin::new(handle).await;
        *slot = None;
        match joined {
            Ok(()) => Ok(()),
            Err(error) if error.is_cancelled() => Ok(()),
            Err(_) => Err(join_error()),
        }
    }

    /// 已结束任务槽的终态消费：异常只保留安全分类并清槽一次，后续操作不复报旧 join
    /// 错误。任务仍在运行时由调用方的 busy 检查处理，这里不等待。
    async fn drain_task_terminal(&self, slot: &mut Option<JoinHandle<()>>) {
        if self.join_slot(slot).await.is_err() {
            tracing::warn!(
                bot_id = %self.bot_id,
                "previous bot operation worker terminated abnormally; state requires verification"
            );
        }
    }

    async fn drain_blocking_terminal(&self, slot: &mut Option<JoinHandle<()>>) {
        if self.join_slot(slot).await.is_err() {
            tracing::warn!(
                bot_id = %self.bot_id,
                "bot credential worker terminated abnormally; state requires verification"
            );
        }
    }

    async fn drain_inspect_terminal(&self, slot: &mut Option<JoinHandle<()>>) {
        if self.join_slot(slot).await.is_err() {
            tracing::warn!(
                bot_id = %self.bot_id,
                "bot credential inspect terminated abnormally; state requires verification"
            );
        }
    }

    /// 准备 worker 异常后的核实与投影，按原 journal 与实际配置裁决已发生的步骤。
    /// 命令上下文携带真实 operationId：无法核实时保留为 CommitUncertain 而不是丢 ID。
    async fn settle_prepare_failure_inner(
        &self,
        original: FeishuError,
        operation_id: &str,
    ) -> Result<SettledCommit, FeishuError> {
        let dir = self.runtime.inner.paths.bot_dir(&self.bot_id);
        let loaded = match load_config_for_recovery(&dir) {
            Ok(loaded) => loaded,
            Err(_) => {
                // 配置不可读：无法核实。保留真实操作身份、目标占用与封口，等待
                // 明确 Retry；不向调用方透出解析正文。
                self.mark_unverified(Some(BotCredentialOperation::CommitUncertain {
                    operation_id: operation_id.to_string(),
                }))
                .await;
                return Err(unverified_error());
            }
        };
        let has_journal = has_credential_journal(&dir);
        if loaded.is_none() && !has_journal {
            // 确定未写入配置或 journal：临时目标归还，不永占已确认未提交的意图。
            self.runtime.release_app_claim(&self.bot_id).await;
            self.set_pending(BotCredentialOperation::Idle, Some(incomplete_diagnostic()))
                .await;
            self.clear_submitting().await;
            self.runtime.publish().await;
            return Err(original);
        }
        match self
            .verify_recovered_directory(
                loaded,
                Some(BotCredentialOperation::CommitUncertain {
                    operation_id: operation_id.to_string(),
                }),
            )
            .await
        {
            VerifiedDirectory::Determined(settled) => Ok(*settled),
            // 确定没有可发布配置：保留原始准备失败。
            VerifiedDirectory::Unpublished => Err(original),
            VerifiedDirectory::Uncertain(error) | VerifiedDirectory::Unverified(error) => {
                Err(error)
            }
        }
    }

    /// 命令路径的准备异常收尾：核实为已确定提交时照常发布并返回真实回执；
    /// 未决/无法核实的 typed 结论原样上报，不固定回原 IO 错误。
    async fn settle_prepare_failure(
        &self,
        original: FeishuError,
        operation_id: &str,
        owner_epoch: &str,
    ) -> Result<BotsCommandReply, FeishuError> {
        let settled = self
            .settle_prepare_failure_inner(original, operation_id)
            .await?;
        self.finish_decision(settled, None, owner_epoch, None).await
    }

    /// 提交或放弃 worker 异常后的核实：按原 journal 与实际配置裁决。确定事实交给
    /// 统一收尾；Uncertain 继续封口并可 Retry；无法核实保留目标占用与封口。
    async fn settle_interrupted(
        &self,
        operation_id: &str,
        _original: FeishuError,
    ) -> Result<SettleOutcome, FeishuError> {
        let uncertain_operation = BotCredentialOperation::CommitUncertain {
            operation_id: operation_id.to_string(),
        };
        let dir = self.runtime.inner.paths.bot_dir(&self.bot_id);
        let loaded = match load_config_for_recovery(&dir) {
            Ok(loaded) => loaded,
            Err(_) => {
                self.mark_unverified(Some(uncertain_operation)).await;
                return Err(unverified_error());
            }
        };
        if loaded.is_none() && !has_credential_journal(&dir) {
            // 配置不存在且没有未决 journal：提交确定没有写入配置，也没有清理义务。
            self.runtime.release_app_claim(&self.bot_id).await;
            self.runtime.clear_cleanup_app(&self.bot_id).await;
            self.set_pending(BotCredentialOperation::Idle, Some(incomplete_diagnostic()))
                .await;
            self.clear_submitting().await;
            self.runtime.publish().await;
            return Err(not_applied_error_without_commit(operation_id));
        }
        match self
            .verify_recovered_directory(loaded, Some(uncertain_operation))
            .await
        {
            VerifiedDirectory::Determined(settled) => Ok(SettleOutcome::Determined(settled)),
            VerifiedDirectory::Unpublished => Err(not_applied_error_without_commit(operation_id)),
            // 已核实的未决提交：保留 typed 结论，不固定回调用方的原始错误。
            VerifiedDirectory::Uncertain(error) => Ok(SettleOutcome::Uncertain(error)),
            VerifiedDirectory::Unverified(error) => Err(error),
        }
    }

    /// 核实失败时的保守投影：不释放目标占用、不重开准入；给出固定安全诊断等待
    /// 明确 Retry。`operation` 为 None 时保留现有操作投影，只追加诊断。
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
            *slot = Some(merge_diagnostic(slot.clone(), diagnostic));
        } else if let Some(operation) = operation {
            self.set_pending(operation, Some(diagnostic)).await;
        } else {
            self.note_directory_diagnostic(diagnostic).await;
        }
        self.clear_submitting().await;
        self.runtime.publish().await;
    }

    /// 目录读取/恢复失败时的既有投影：有已发布配置的机器人更新其安全诊断；尚无
    /// 配置的机器人用 Idle + 诊断进入 pending 列表，不伪造一次提交。
    async fn note_directory_diagnostic(&self, diagnostic: BotDiagnostic) {
        if let Some(managed) = self.published().await {
            let mut slot = managed.diagnostic.lock().await;
            *slot = Some(merge_diagnostic(slot.clone(), diagnostic));
            return;
        }
        let mut records = self.runtime.inner.bots.lock().await;
        if let Some(record) = records.get_mut(&self.bot_id) {
            let operation = record
                .pending
                .as_ref()
                .map(|pending| pending.operation.clone())
                .unwrap_or(BotCredentialOperation::Idle);
            let existing = record
                .pending
                .as_ref()
                .and_then(|pending| pending.diagnostic.clone());
            record.pending = Some(PendingProjection {
                bot_id: self.bot_id.clone(),
                operation,
                diagnostic: Some(merge_diagnostic(existing, diagnostic)),
            });
        }
    }

    async fn clear_submitting(&self) {
        self.submitting.store(false, Ordering::Release);
        if let Some(managed) = self.published().await {
            managed.submitting.store(false, Ordering::Release);
        }
    }

    pub(crate) async fn close(&self) -> Result<(), FeishuError> {
        let mut task = self.task.lock().await;
        self.join_slot(&mut task).await?;
        drop(task);
        let mut blocking = self.blocking.lock().await;
        self.join_slot(&mut blocking).await?;
        drop(blocking);
        let mut inspect = self.inspect.lock().await;
        self.join_slot(&mut inspect).await
    }
}

fn fingerprint_of(mutation: &BotMutation, fallback_bot_id: &str) -> CommandFingerprint {
    match mutation {
        BotMutation::Save(request) => CommandFingerprint::Save(SaveFingerprint {
            operation_id: request.operation_id.clone(),
            bot_id: request
                .bot_id
                .clone()
                .unwrap_or_else(|| fallback_bot_id.to_string()),
            expected_config_revision: request.expected_config_revision,
            name: request.name.clone(),
            project_id: request.project_id.clone(),
            app_id: request.app_id.clone(),
            secret: match &request.secret {
                BotSecretUpdate::Preserve => SecretFingerprint::Preserve,
                BotSecretUpdate::Clear => SecretFingerprint::Clear,
                BotSecretUpdate::Replace { value } => SecretFingerprint::Replace(value.clone()),
            },
            enabled: request.enabled,
            tools_enabled: request.tools_enabled,
        }),
        BotMutation::SetEnabled {
            operation_id,
            expected_config_revision,
            enabled,
        } => CommandFingerprint::SetEnabled {
            operation_id: operation_id.clone(),
            expected_config_revision: *expected_config_revision,
            enabled: *enabled,
        },
        BotMutation::SetTrustedUser {
            operation_id,
            expected_config_revision,
            open_id,
            trusted,
        } => CommandFingerprint::SetTrustedUser {
            operation_id: operation_id.clone(),
            expected_config_revision: *expected_config_revision,
            open_id: open_id.clone(),
            trusted: *trusted,
        },
        BotMutation::SetTrustedChat {
            operation_id,
            expected_config_revision,
            chat_id,
            trusted,
        } => CommandFingerprint::SetTrustedChat {
            operation_id: operation_id.clone(),
            expected_config_revision: *expected_config_revision,
            chat_id: chat_id.clone(),
            trusted: *trusted,
        },
        BotMutation::Retry { operation_id } => CommandFingerprint::Retry {
            operation_id: operation_id.clone(),
        },
    }
}

fn operation_id_of(fingerprint: &CommandFingerprint) -> &str {
    match fingerprint {
        CommandFingerprint::Save(save) => &save.operation_id,
        CommandFingerprint::SetEnabled { operation_id, .. }
        | CommandFingerprint::SetTrustedUser { operation_id, .. }
        | CommandFingerprint::SetTrustedChat { operation_id, .. }
        | CommandFingerprint::Retry { operation_id }
        | CommandFingerprint::RegistrationSave { operation_id, .. } => operation_id,
    }
}

/// 读取普通配置用于核实。配置不可读但存在未决 journal 时以 `None` 继续：原 journal
/// 的 target 仍是可裁决的事实，不能因为普通配置损坏就丢弃未完成义务。
fn load_config_for_recovery(dir: &Path) -> Result<Option<BotConfigFile>, FeishuError> {
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

async fn wait_typed<T: Clone>(
    outcome: &watch::Sender<Option<Arc<Result<T, FeishuError>>>>,
) -> Result<T, FeishuError> {
    let mut rx = outcome.subscribe();
    loop {
        if let Some(value) = rx.borrow().clone() {
            return match &*value {
                Ok(value) => Ok(value.clone()),
                Err(error) => Err(error.clone()),
            };
        }
        if rx.changed().await.is_err() {
            return Err(join_error());
        }
    }
}

fn sealed_error() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        "bot runtime is sealed",
        true,
        None,
    )
}

fn busy_error() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Conflict,
        "bot already has an in-flight configuration operation",
        true,
        None,
    )
}

fn stale_revision_error() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Conflict,
        "stale bot config revision",
        true,
        None,
    )
}

fn duplicate_app_error() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Conflict,
        "appId already owns another bot",
        false,
        None,
    )
}

fn unsettled_intent_error() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Conflict,
        "bot has an unfinished recovery obligation; retry the original operation first",
        true,
        None,
    )
}

fn operation_conflict_error() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Conflict,
        "operationId already used with different bot input",
        false,
        None,
    )
}

fn conflicting_operation_id(existing: &CommandFingerprint, incoming: &CommandFingerprint) -> bool {
    existing != incoming && operation_id_of(existing) == operation_id_of(incoming)
}

fn interrupted_error() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        "bot operation worker ended before publishing its result; retry to verify the commit",
        true,
        None,
    )
}

/// 文件或凭据状态无法核实时的固定安全诊断：不使用底层解析错误，避免把损坏文件
/// 正文带进日志或管理投影。
fn unverified_diagnostic() -> BotDiagnostic {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        CREDENTIAL_STATE_UNVERIFIED,
        true,
        None,
    )
    .diagnostic()
}

fn incomplete_diagnostic() -> BotDiagnostic {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        CREDENTIAL_OPERATION_INCOMPLETE,
        true,
        None,
    )
    .diagnostic()
}

fn merge_diagnostic(existing: Option<BotDiagnostic>, incoming: BotDiagnostic) -> BotDiagnostic {
    match existing {
        Some(existing) if existing.message.contains(&incoming.message) => existing,
        Some(existing) => BotDiagnostic {
            message: format!("{}; {}", existing.message, incoming.message),
            ..existing
        },
        None => incoming,
    }
}

/// 新提交/恢复诊断合并：独立配对清理义务不因连接错误或后继成功被覆盖，
/// 其余旧连接类诊断由新的确定事实替换或清除。
fn merge_commit_diagnostic(
    existing: Option<BotDiagnostic>,
    incoming: Option<BotDiagnostic>,
) -> Option<BotDiagnostic> {
    let cleanup =
        existing.filter(|diagnostic| diagnostic.message.contains(PAIRING_CLEANUP_PENDING));
    match (cleanup, incoming) {
        (Some(cleanup), Some(incoming)) => Some(merge_diagnostic(Some(incoming), cleanup)),
        (Some(cleanup), None) => Some(cleanup),
        (None, incoming) => incoming,
    }
}

/// 移除单个诊断条款，保留其它独立错误/义务；不解析外部文本格式，只处理本模块
/// 用 `; ` 合并的安全诊断。
fn without_diagnostic_clause(
    existing: Option<BotDiagnostic>,
    clause: &str,
) -> Option<BotDiagnostic> {
    let existing = existing?;
    let message = existing
        .message
        .split("; ")
        .filter(|part| !part.trim().is_empty() && !part.contains(clause))
        .collect::<Vec<_>>()
        .join("; ");
    if message.is_empty() {
        None
    } else {
        Some(BotDiagnostic {
            message,
            ..existing
        })
    }
}

/// 一个机器人记录当前仍须保护的应用事实。
fn record_holds_app(record: &BotRecord, app_id: &str) -> bool {
    record.published_app_id.as_deref() == Some(app_id)
        || record.claimed_app_id.as_deref() == Some(app_id)
        || record.cleanup_app_id.as_deref() == Some(app_id)
        || record.pending_stop_app_id.as_deref() == Some(app_id)
}

fn unverified_error() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        "bot directory state could not be verified; retry after fixing local data",
        true,
        None,
    )
}

/// 把目录核实结果转成可直接发布的提交事实；没有可发布配置时返回 None。
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

fn join_error() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        "bot credential worker failed",
        true,
        None,
    )
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
