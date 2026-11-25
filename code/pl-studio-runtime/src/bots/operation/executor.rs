//! Serial async operations and retained blocking task ownership.
use super::{BotMutation, BotOperationOwner, RegistrationSave};
use crate::bots::credentials::CredentialCommit;
use crate::bots::protocol::error::{FeishuError, FeishuErrorKind};
use crate::{BotSecretUpdate, BotsCommandReply};
use std::future::Future;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use tokio::sync::{Mutex, oneshot, watch};
use tokio::task::JoinHandle;

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

/// 已完成操作的结果保留位置：`current` 是最近受理的操作，`previous` 是上一操作。
/// 调用方停止等待后再次提交同一操作时仍取回已保存结果，而不是重复执行。
#[derive(Default)]
struct CompletionSlot {
    current: Option<ActiveCompletion>,
    previous: Option<ActiveCompletion>,
}

impl CompletionSlot {
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
        workspace_id: String,
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
    workspace_id: String,
    app_id: String,
    secret: SecretFingerprint,
    enabled: bool,
    tools_enabled: bool,
    model_route: Option<crate::BotModelRoute>,
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

trait OperationResult: Clone + Send + Sync + 'static {
    fn from_active(active: &ActiveCompletion) -> Option<&Arc<TypedCompletion<Self>>>;
    fn into_active(completion: Arc<TypedCompletion<Self>>) -> ActiveCompletion;
}

impl OperationResult for BotsCommandReply {
    fn from_active(active: &ActiveCompletion) -> Option<&Arc<TypedCompletion<Self>>> {
        match active {
            ActiveCompletion::Command(completion) => Some(completion),
            ActiveCompletion::Registration(_) => None,
        }
    }

    fn into_active(completion: Arc<TypedCompletion<Self>>) -> ActiveCompletion {
        ActiveCompletion::Command(completion)
    }
}

impl OperationResult for CredentialCommit {
    fn from_active(active: &ActiveCompletion) -> Option<&Arc<TypedCompletion<Self>>> {
        match active {
            ActiveCompletion::Registration(completion) => Some(completion),
            ActiveCompletion::Command(_) => None,
        }
    }

    fn into_active(completion: Arc<TypedCompletion<Self>>) -> ActiveCompletion {
        ActiveCompletion::Registration(completion)
    }
}

#[derive(Default)]
pub(super) struct SerialOperationExecutor {
    pub(super) serial: Mutex<()>,
    task: Mutex<Option<JoinHandle<()>>>,
    completions: Mutex<CompletionSlot>,
    blocking: BlockingSlot,
    inspect: BlockingSlot,
}

impl SerialOperationExecutor {
    async fn claim<T, F>(
        &self,
        owner: &BotOperationOwner,
        fingerprint: CommandFingerprint,
        work: F,
    ) -> Result<T, FeishuError>
    where
        T: OperationResult,
        F: Future<Output = Result<T, FeishuError>> + Send + 'static,
    {
        let completion = {
            let mut slot = self.task.lock().await;
            let mut completions = self.completions.lock().await;
            let replay = completions
                .iter()
                .find(|entry| entry.fingerprint() == &fingerprint)
                .and_then(T::from_active)
                .filter(|completion| !completion.is_interrupted())
                .cloned();
            if let Some(completion) = replay {
                drop(slot);
                drop(completions);
                return wait_typed(&completion.outcome).await;
            }
            if completions
                .iter()
                .any(|entry| conflicting_operation_id(entry.fingerprint(), &fingerprint))
            {
                return Err(operation_conflict_error());
            }
            if slot.as_ref().is_some_and(|handle| !handle.is_finished()) {
                return Err(busy_error());
            }
            owner.runtime.reject_if_sealed()?;
            drain_terminal(&owner.bot_id, "operation", &mut slot).await;
            owner.runtime.reject_if_sealed()?;
            let completion = Arc::new(TypedCompletion::new(fingerprint));
            completions.register(T::into_active(completion.clone()));
            let mut guard = CompletionGuard::new(completion.clone());
            *slot = Some(tokio::spawn(async move {
                guard.publish(work.await);
            }));
            completion
        };
        wait_typed(&completion.outcome).await
    }

    pub(super) async fn run_blocking<T, F>(&self, bot_id: &str, job: F) -> Result<T, FeishuError>
    where
        T: Send + 'static,
        F: FnOnce() -> Result<T, FeishuError> + Send + 'static,
    {
        self.blocking.run(bot_id, "credential worker", job).await
    }

    pub(super) async fn run_inspect<T, F>(&self, bot_id: &str, job: F) -> Result<T, FeishuError>
    where
        T: Send + 'static,
        F: FnOnce() -> Result<T, FeishuError> + Send + 'static,
    {
        self.inspect.run(bot_id, "credential inspect", job).await
    }
}

/// The join handle stays in the slot if its waiter is cancelled. Keep the slot
/// locked across result and join so a concurrent inspector cannot replace it.
#[derive(Default)]
struct BlockingSlot(Mutex<Option<JoinHandle<()>>>);

impl BlockingSlot {
    async fn run<T, F>(&self, bot_id: &str, stage: &str, job: F) -> Result<T, FeishuError>
    where
        T: Send + 'static,
        F: FnOnce() -> Result<T, FeishuError> + Send + 'static,
    {
        let mut slot = self.0.lock().await;
        drain_terminal(bot_id, stage, &mut slot).await;
        let (tx, rx) = oneshot::channel();
        *slot = Some(tokio::task::spawn_blocking(move || {
            let _ = tx.send(job());
        }));
        let result = rx.await;
        drain_terminal(bot_id, stage, &mut slot).await;
        result.map_err(|_| {
            FeishuError::new(
                FeishuErrorKind::Unavailable,
                format!("bot {stage} ended before returning"),
                true,
                None,
            )
        })?
    }

    async fn close(&self) -> Result<(), FeishuError> {
        join_slot(&mut *self.0.lock().await).await
    }
}

async fn join_slot(slot: &mut Option<JoinHandle<()>>) -> Result<(), FeishuError> {
    crate::bots::join_owned_task(slot)
        .await
        .map_err(|_| join_error())
}

async fn drain_terminal(bot_id: &str, stage: &str, slot: &mut Option<JoinHandle<()>>) {
    if join_slot(slot).await.is_err() {
        tracing::warn!(
            bot_id,
            stage,
            "bot worker terminated abnormally; state requires verification"
        );
    }
}

impl BotOperationOwner {
    pub(super) async fn submit(
        &self,
        mutation: BotMutation,
        owner_epoch: String,
    ) -> Result<BotsCommandReply, FeishuError> {
        let fingerprint = fingerprint_of(&mutation, &self.bot_id);
        let owner = self.runtime.ensure_record(&self.bot_id).await?;
        let worker = owner.clone();
        self.executor
            .claim(&owner, fingerprint, async move {
                let _serial = worker.executor.serial.lock().await;
                worker.execute(mutation, owner_epoch).await
            })
            .await
    }

    pub(super) async fn submit_registration_save(
        &self,
        request: RegistrationSave,
    ) -> Result<CredentialCommit, FeishuError> {
        let fingerprint = CommandFingerprint::RegistrationSave {
            operation_id: request.operation_id.clone(),
            bot_id: request.bot_id.clone(),
            name: request.name.clone(),
            workspace_id: request.workspace_id.clone(),
            app_id: request.app_id.clone(),
            secret: SecretFingerprint::Replace(request.secret.clone()),
            trusted_open_id: request.trusted_open_id.clone(),
        };
        let owner = self.runtime.ensure_record(&self.bot_id).await?;
        let worker = owner.clone();
        self.executor
            .claim(&owner, fingerprint, async move {
                let _serial = worker.executor.serial.lock().await;
                worker.run_registration_save(request).await
            })
            .await
    }

    pub(crate) async fn close(&self) -> Result<(), FeishuError> {
        join_slot(&mut *self.executor.task.lock().await).await?;
        self.executor.blocking.close().await?;
        self.executor.inspect.close().await
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
            workspace_id: request.workspace_id.clone(),
            app_id: request.app_id.clone(),
            secret: match &request.secret {
                BotSecretUpdate::Preserve => SecretFingerprint::Preserve,
                BotSecretUpdate::Clear => SecretFingerprint::Clear,
                BotSecretUpdate::Replace { value } => SecretFingerprint::Replace(value.clone()),
            },
            enabled: request.enabled,
            tools_enabled: request.tools_enabled,
            model_route: request.model_route.clone(),
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

fn busy_error() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Conflict,
        "bot already has an in-flight configuration operation",
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

fn join_error() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        "bot credential worker failed",
        true,
        None,
    )
}
