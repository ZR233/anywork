//! Bounded ownership of real prepare continuations, independent of API waiters and reply workers.
//! Only the existing mutation/recovery driver registers here; reads never create work.

use super::command::unavailable;
use crate::bots::BotRuntime;
use crate::bots::occupancy::{
    OCCUPANCY_TASK_LIMIT, OccupancyBudget, PublishOnExit, counted_extra_bytes, counted_text_bytes,
};
use crate::bots::owner::ManagedBot;
use crate::bots::protocol::error::{FeishuError, FeishuErrorKind};
use crate::bots::storage::audience::Authorization;
use crate::studio::audience_start::AudienceStartIntent;
use pl_protocol::BotAudienceCloseReason;
use pl_protocol::studio::BotAuthorizationPhase;
use std::collections::BTreeMap;
use std::sync::Arc;
use std::sync::atomic::Ordering;
use tokio::sync::Mutex;
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

/// Keep at least one global occupancy slot available for a control command while cuts are busy.
const PREPARE_TASK_LIMIT: usize = OCCUPANCY_TASK_LIMIT - 1;

#[derive(Clone, PartialEq, Eq, PartialOrd, Ord)]
struct PrepareIdentity {
    bot: String,
    chat: String,
    generation: u64,
    thread: String,
    operation: String,
    binding_revision: u64,
}

impl PrepareIdentity {
    fn matches(&self, intent: &AudienceStartIntent) -> bool {
        self.bot == intent.authorization.bot_id
            && self.chat == intent.authorization.chat_id
            && self.generation == intent.authorization.generation
            && self.thread == intent.thread_id
            && self.operation == intent.operation_id
            && self.binding_revision == intent.binding_revision
    }

    fn new(intent: &AudienceStartIntent) -> Self {
        Self {
            bot: intent.authorization.bot_id.clone(),
            chat: intent.authorization.chat_id.clone(),
            generation: intent.authorization.generation,
            thread: intent.thread_id.clone(),
            operation: intent.operation_id.clone(),
            binding_revision: intent.binding_revision,
        }
    }
}

struct PrepareTask {
    /// None only while reserving this entry before spawn, without yielding under the registry lock.
    handle: Option<JoinHandle<()>>,
    /// Retained through the actual join: even a finished task's key still consumes frozen text.
    _budget: OccupancyBudget,
}

#[derive(Default)]
struct PrepareRegistry {
    tasks: BTreeMap<PrepareIdentity, PrepareTask>,
    abnormal: bool,
}

pub(in crate::bots) struct AudiencePrepareTasks {
    registry: Mutex<PrepareRegistry>,
    stopping: CancellationToken,
}

impl AudiencePrepareTasks {
    pub(in crate::bots) fn new() -> Self {
        Self {
            registry: Mutex::new(PrepareRegistry::default()),
            stopping: CancellationToken::new(),
        }
    }

    async fn register(
        &self,
        runtime: &BotRuntime,
        managed: Arc<ManagedBot>,
        auth: Authorization,
    ) -> Result<(), FeishuError> {
        if runtime.inner.sealed.load(Ordering::SeqCst) != 0 {
            return Err(unavailable());
        }
        let mut registry = self.registry.lock().await;
        reap_finished(&mut registry).await?;
        // Registration, deduplication and closing all share this boundary. A task registered
        // immediately before the seal still observes stopping and remains owned until joined.
        if runtime.inner.sealed.load(Ordering::SeqCst) != 0 || self.stopping.is_cancelled() {
            return Err(unavailable());
        }
        if registry.tasks.keys().any(|id| id.matches(&auth.intent)) {
            return Ok(());
        }
        if registry.tasks.len() >= PREPARE_TASK_LIMIT {
            return Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "bot audience prepare slots are full; durable intent retained",
                true,
                None,
            ));
        }
        // Intent/current-auth/readback and encoded SQL/core payloads, plus the registered key
        // and one key clone during reap. Serialized length covers JSON escaping, not just chars.
        let encoded = serde_json::to_vec(&auth).map_err(|_| unavailable())?;
        let frozen = counted_extra_bytes(
            counted_text_bytes([
                (auth.intent.operation_id.as_str(), 3),
                (auth.intent.thread_id.as_str(), 3),
                (auth.intent.authorization.bot_id.as_str(), 3),
                (auth.intent.authorization.chat_id.as_str(), 3),
            ])?,
            [(encoded.len(), 8)],
        )?;
        drop(encoded);
        let budget = runtime.inner.occupancy.task_budget(frozen)?;
        let task = registry
            .tasks
            .entry(PrepareIdentity::new(&auth.intent))
            .or_insert(PrepareTask {
                handle: None,
                _budget: budget,
            });
        let worker = runtime.clone();
        // Reserve the exact identity before creating the task. No await separates reservation,
        // spawn and handle installation; shutdown cannot observe an unregistered child.
        task.handle = Some(tokio::spawn(async move {
            let _publish = PublishOnExit(worker.clone());
            if let Err(error) = worker.recover_audience_prepare(&managed, auth).await
                && !worker.inner.audience_prepares.stopping.is_cancelled()
            {
                tracing::warn!(kind=?error.kind(),"audience preparation retained for recovery");
            }
        }));
        Ok(())
    }

    async fn reap(&self) -> Result<(), FeishuError> {
        let mut registry = self.registry.lock().await;
        reap_finished(&mut registry).await
    }

    pub(in crate::bots) async fn stop_and_drain(&self) -> Result<(), FeishuError> {
        // Cancel the core wait, not the already queued core command or durable bot intent. This
        // must happen before joins: outer Studio shutdown has not yet stopped busy Threads.
        self.stopping.cancel();
        let mut registry = self.registry.lock().await;
        while let Some(mut entry) = registry.tasks.first_entry() {
            let handle = entry.get_mut().handle.as_mut().ok_or_else(unavailable)?;
            let joined = handle.await;
            entry.remove_entry();
            if joined.is_err() {
                registry.abnormal = true;
            }
        }
        // Handles stay in the map across every await, including a cancelled close. Observe and
        // remove a terminal handle before propagating its error, never poll it a second time.
        if std::mem::take(&mut registry.abnormal) {
            return Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "bot audience prepare task terminated abnormally",
                true,
                None,
            ));
        }
        Ok(())
    }
}

async fn reap_finished(registry: &mut PrepareRegistry) -> Result<(), FeishuError> {
    while let Some(id) = registry.tasks.iter().find_map(|(id, task)| {
        task.handle
            .as_ref()
            .filter(|h| h.is_finished())
            .map(|_| id.clone())
    }) {
        if let Some(task) = registry.tasks.get_mut(&id) {
            let joined = task.handle.as_mut().ok_or_else(unavailable)?.await;
            registry.tasks.remove(&id);
            if joined.is_err() {
                registry.abnormal = true;
                tracing::warn!("a bot audience prepare task terminated abnormally");
            }
        }
    }
    Ok(())
}

impl BotRuntime {
    async fn recover_audience_prepare(
        &self,
        managed: &Arc<ManagedBot>,
        auth: Authorization,
    ) -> Result<Authorization, FeishuError> {
        // This task owns all bot transactions through their real result. Only the core wait is
        // stoppable: cancellation cannot prove whether its opaque extension command committed.
        if auth.phase != BotAuthorizationPhase::PendingStart {
            return Ok(auth);
        }
        // 撤权/停用必须显式封闭这一代：不能把 PendingStart 留在库里等之后 enable 自动接续。
        // 判据与首次绑定门控共用，且优先使用该 chat 已持久化的 typed 目标证明。
        if let Err(error) = self.prepare_permission(managed, &auth).await {
            return self.settle_unstartable(managed, &auth, error).await;
        }
        let current = managed
            .store
            .audience_authorization(&auth.intent.authorization)
            .await?
            .ok_or_else(unavailable)?;
        if current != auth {
            return Ok(current);
        }
        let Some(host) = self.studio_host() else {
            return Err(unavailable());
        };
        let result = tokio::select! {
            biased;
            _ = self.inner.audience_prepares.stopping.cancelled() => return Ok(auth),
            result = host.prepare_bot_audience_start(&auth.intent) => result,
        };
        let result = match result {
            Ok(result) => result,
            Err(error) => {
                let error = FeishuError::history_read("audience cut remains pending", error);
                if error.retryable() {
                    return Err(error);
                }
                // 确定性失败不会自行恢复：显式封闭为 StartFailed，不让 PendingStart 挂着。
                return self
                    .close_pending(managed, &auth, BotAudienceCloseReason::StartFailed)
                    .await;
            }
        };
        match result {
            crate::studio::AudienceStartPreparation::Pending { extension_revision } => {
                if extension_revision == 0 {
                    return Err(unavailable());
                }
                Ok(auth)
            }
            crate::studio::AudienceStartPreparation::Superseded => {
                self.close_pending(managed, &auth, BotAudienceCloseReason::StartCancelled)
                    .await
            }
            crate::studio::AudienceStartPreparation::Saved(receipt) => {
                let _admission = managed.admission.lock().await;
                self.reject_closed_admission(managed)?;
                if let Err(error) = self.prepare_permission(managed, &auth).await {
                    return self.settle_unstartable(managed, &auth, error).await;
                }
                let identity_matches = {
                    let config = managed.config.lock().await;
                    config.project_id == auth.project_id && config.feishu().app_id == auth.app_id
                };
                if !identity_matches {
                    // 目标应用/项目身份已变：这一代不再可能激活，按真实原因封闭。
                    return self
                        .close_pending(managed, &auth, BotAudienceCloseReason::TrustRevoked)
                        .await;
                }
                let change = managed.store.activate_sync(&receipt).await?;
                if change.changed {
                    managed.audience_changed();
                }
                Ok(change.authorization)
            }
        }
    }

    /// The durable-prepare permission recheck: current config plus the chat's persisted typed
    /// target proof, shared with the first-binding gate (`first_start_allowed`).
    async fn prepare_permission(
        &self,
        managed: &Arc<ManagedBot>,
        auth: &Authorization,
    ) -> Result<(), FeishuError> {
        let config = managed.config.lock().await.clone();
        super::prepare_permission(&managed.store, &config, auth).await
    }

    /// A pending generation that can never start is closed with its real reason instead of
    /// staying pending forever. Only permission facts close here; transient errors stay
    /// retryable with the durable intent untouched.
    async fn settle_unstartable(
        &self,
        managed: &Arc<ManagedBot>,
        auth: &Authorization,
        error: FeishuError,
    ) -> Result<Authorization, FeishuError> {
        if error.kind() != FeishuErrorKind::Permission {
            return Err(error);
        }
        let reason = super::permission_close_reason(&*managed.config.lock().await);
        self.close_pending(managed, auth, reason).await
    }

    async fn close_pending(
        &self,
        managed: &Arc<ManagedBot>,
        auth: &Authorization,
        reason: BotAudienceCloseReason,
    ) -> Result<Authorization, FeishuError> {
        let changed = managed
            .store
            .close_sync_generation(&auth.intent.authorization, reason)
            .await?;
        if changed {
            managed.audience_changed();
        }
        managed
            .store
            .audience_authorization(&auth.intent.authorization)
            .await?
            .ok_or_else(unavailable)
    }

    pub(in crate::bots) async fn recover_audience_prepares(
        &self,
        bot: &str,
    ) -> Result<(), FeishuError> {
        self.inner.audience_prepares.reap().await?;
        let managed = self.managed(bot).await?;
        // Keep the original 32-key rotation; registering one busy Thread never awaits its cut
        // and therefore cannot starve the later keys in this page or subsequent bots.
        let after = managed.audience_recovery_cursor.lock().await.clone();
        let pending = managed.store.pending_syncs((&after.0, after.1)).await?;
        let next = pending.last().map(|a| {
            (
                a.intent.authorization.chat_id.clone(),
                a.intent.authorization.generation,
            )
        });
        let full = pending.len() == 32;
        for auth in pending {
            if self.inner.sealed.load(Ordering::SeqCst) != 0 {
                return Ok(());
            }
            if let Err(error) = self
                .inner
                .audience_prepares
                .register(self, managed.clone(), auth)
                .await
            {
                tracing::warn!(bot,kind=?error.kind(),"audience preparation retained for recovery");
            }
        }
        *managed.audience_recovery_cursor.lock().await = if full {
            next.unwrap_or_default()
        } else {
            Default::default()
        };
        Ok(())
    }
}
