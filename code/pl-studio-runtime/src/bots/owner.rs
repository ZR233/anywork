//! 机器人产品 owner：配置 CAS、凭据、注册代次、连接启动与入站/查询/发送共享同一状态。
//!
//! 每个机器人的配置/凭据操作由 `operation` owner 串行推进；本文件保留 runtime
//! 装配、快照投影与入站 host。

use super::InboundWorkOutcome;
use super::config::{BotConfigFile, validate_bot_id};
use super::connect::BotConnectionOwner;
use super::inbound::{InboundDecision, InboundHost};
use super::occupancy::OccupancyTasks;
use super::operation::BotRecord;
use super::protocol::endpoint::EndpointPolicy;
use super::protocol::error::{FeishuError, FeishuErrorKind};
use super::protocol::http::FeishuHttp;
use super::protocol::token::TokenLease;
use super::registration::ActiveRegistration;
use super::storage::BotStateStore;
use crate::config::ConfigRuntime;
use crate::studio::StudioPaths;
use crate::studio::unix_seconds;
use crate::studio::{ProductEventBus, StudioRuntime};
use pl_protocol::studio::{
    BotCredentialAvailability, BotCredentialOperation, BotDiagnostic, BotPairingRequest,
    BotPlatform, BotSnapshot, BotsStateSnapshot,
};
use std::collections::BTreeMap;
use std::pin::Pin;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use tokio::sync::{Mutex, Notify, Semaphore};
use tokio::task::JoinHandle;
use tokio::task::JoinSet;
use tokio_util::sync::CancellationToken;

pub struct BotRuntime {
    pub(crate) inner: Arc<BotRuntimeInner>,
}

/// 已封闭、资源记录仍在，可供失败后再次回收。
pub(crate) const BOTS_RUNTIME_SEALED: u64 = 1;
/// 成功关闭完成，运行时资源记录已释放。
pub(crate) const BOTS_RUNTIME_RELEASED: u64 = 2;

/// 配对列表读取失败的安全诊断文案：用于说明保留旧列表，也用于合并时去重。
const PAIRING_UNREADABLE: &str =
    "bot pairing requests are unreadable; last published list retained";

pub(crate) struct BotRuntimeInner {
    pub(crate) paths: StudioPaths,
    pub(crate) config: ConfigRuntime,
    pub(crate) events: ProductEventBus,
    pub(crate) http: FeishuHttp,
    pub(crate) bots: Mutex<BTreeMap<String, BotRecord>>,
    pub(crate) canonical: Mutex<BotsStateSnapshot>,
    pub(crate) publish_gate: Mutex<()>,
    pub(crate) publish_notify: Arc<Notify>,
    pub(crate) publisher: Mutex<Option<JoinHandle<()>>>,
    pub(crate) registration: Mutex<Option<ActiveRegistration>>,
    pub(crate) registration_start: Mutex<()>,
    pub(crate) host: std::sync::Mutex<Option<std::sync::Weak<StudioRuntime>>>,
    pub(crate) replies: Mutex<JoinSet<InboundWorkOutcome>>,
    pub(crate) reply_slots: Arc<Semaphore>,
    pub(crate) reply_cancel: CancellationToken,
    pub(crate) occupancy: OccupancyTasks,
    pub(in crate::bots) audience_prepares: super::audience::AudiencePrepareTasks,
    /// One coalescing wakeup for durable prepares; not a per-Thread topic or another work queue.
    pub(in crate::bots) audience_prepare_notify: Notify,
    /// Byte permits for our outgoing source/archive/upload copies, not a second send queue.
    pub(crate) send_bytes: Arc<Semaphore>,
    /// At most one raw inbound batch (128 MiB) plus its admission copy is held by this owner.
    /// This permit is backpressure only, not an alternate work or attachment queue.
    pub(crate) download_batch: Arc<Semaphore>,
    /// Present before any managed-root factory is awaited; shutdown owns cancellation-safe join.
    pub(crate) workspace_io: pl_tool::workspace_file::LocalFileIoOwner,
    pub(crate) sealed: AtomicU64,
    pub(crate) recovery: Mutex<Option<JoinHandle<()>>>,
    /// 回复任务集里已观察到的真实异常终态：由 owner 保留，排空后消费一次。
    pub(crate) reply_fault: AtomicBool,
    /// canonical 水位已耗尽：不再发射新 frame，避免复用同一 revision。
    pub(crate) publish_exhausted: AtomicBool,
}

pub(crate) struct ManagedBot {
    pub(crate) config: Mutex<BotConfigFile>,
    pub(crate) store: BotStateStore,
    pub(crate) connection: BotConnectionOwner,
    pub(crate) credential: Mutex<BotCredentialAvailability>,
    pub(crate) credential_operation: Mutex<BotCredentialOperation>,
    pub(crate) diagnostic: Mutex<Option<pl_protocol::studio::BotDiagnostic>>,
    pub(crate) generation: Arc<AtomicU64>,
    pub(crate) token: TokenLease,
    pub(crate) send_rate: super::send::SendRate,
    pub(crate) bot_open_id: Mutex<Option<(u64, String)>>,
    pub(crate) admission: tokio::sync::Mutex<()>,
    pub(crate) admission_closed: AtomicBool,
    pub(crate) submitting: AtomicBool,
    pub(crate) audience_changes:
        tokio::sync::watch::Sender<crate::studio::thread_audience::BotAudienceWatchVersion>,
    pub(crate) audience_recovery_cursor: Mutex<(String, u64)>,
}

impl Clone for BotRuntime {
    fn clone(&self) -> Self {
        Self {
            inner: self.inner.clone(),
        }
    }
}

impl BotRuntime {
    pub fn new(
        paths: StudioPaths,
        config: ConfigRuntime,
        events: ProductEventBus,
    ) -> Result<Self, FeishuError> {
        let http = FeishuHttp::new(EndpointPolicy::for_studio(&paths)?)?;
        Ok(Self {
            inner: Arc::new(BotRuntimeInner {
                paths,
                config,
                events,
                http,
                bots: Mutex::new(BTreeMap::new()),
                canonical: Mutex::new(BotsStateSnapshot {
                    revision: 1,
                    updated_at: unix_seconds(),
                    bots: Vec::new(),
                    registration: None,
                    pending_credential_operations: Vec::new(),
                }),
                publish_gate: Mutex::new(()),
                publish_notify: Arc::new(Notify::new()),
                publisher: Mutex::new(None),
                registration: Mutex::new(None),
                registration_start: Mutex::new(()),
                host: std::sync::Mutex::new(None),
                replies: Mutex::new(JoinSet::new()),
                reply_slots: Arc::new(Semaphore::new(32)),
                reply_cancel: CancellationToken::new(),
                occupancy: OccupancyTasks::new(),
                audience_prepares: super::audience::AudiencePrepareTasks::new(),
                audience_prepare_notify: Notify::new(),
                send_bytes: Arc::new(Semaphore::new(128 * 1024 * 1024)),
                download_batch: Arc::new(Semaphore::new(1)),
                workspace_io: Default::default(),
                sealed: AtomicU64::new(0),
                recovery: Mutex::new(None),
                reply_fault: AtomicBool::new(false),
                publish_exhausted: AtomicBool::new(false),
            }),
        })
    }

    pub fn attach_host(&self, runtime: std::sync::Weak<StudioRuntime>) {
        *self
            .inner
            .host
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner()) = Some(runtime);
    }

    pub(crate) fn clear_host(&self) {
        *self
            .inner
            .host
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner()) = None;
    }

    pub async fn load(&self) -> Result<(), FeishuError> {
        self.ensure_publisher().await?;
        let root = self.inner.paths.bots_dir();
        let entries = match std::fs::read_dir(&root) {
            Ok(entries) => entries,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                self.ensure_inbound_recovery().await?;
                return Ok(());
            }
            Err(error) => {
                return Err(FeishuError::new(
                    FeishuErrorKind::Unavailable,
                    format!("failed to read bots directory: {error}"),
                    true,
                    None,
                ));
            }
        };
        for entry in entries {
            let entry = match entry {
                Ok(entry) => entry,
                Err(error) => {
                    tracing::warn!(%error, "failed to read bots directory entry");
                    continue;
                }
            };
            if !entry.file_type().map(|kind| kind.is_dir()).unwrap_or(false) {
                continue;
            }
            let bot_id = entry.file_name().to_string_lossy().into_owned();
            if validate_bot_id(&bot_id).is_err() {
                // 无效目录名不构造可操作身份，也不回显原始名字/路径。
                tracing::warn!("skipping invalid bot directory; entry isolated");
                continue;
            }
            match self.recover_bot_dir(&bot_id).await {
                Ok(()) => {}
                Err(_) => {
                    // 不输出底层错误：损坏配置的解析文本可能携带文件正文。保留原目录，
                    // 用 pending/诊断投影让它可见并可明确本地重试。
                    tracing::warn!(
                        bot_id,
                        "bot directory is unreadable; retained for local retry"
                    );
                    self.note_unreadable_directory(&bot_id).await;
                }
            }
        }
        self.publish().await;
        self.request_publish();
        self.ensure_inbound_recovery().await?;
        Ok(())
    }

    pub(crate) fn request_publish(&self) {
        self.inner.publish_notify.notify_one();
    }

    pub(crate) async fn ensure_publisher(&self) -> Result<(), FeishuError> {
        if self.runtime_released() {
            return Ok(());
        }
        let mut slot = self.inner.publisher.lock().await;
        if self.runtime_released() {
            return Ok(());
        }
        if slot.as_ref().is_some_and(|handle| !handle.is_finished()) {
            return Ok(());
        }
        if let Some(handle) = slot.as_mut() {
            let result = join_owned_slot(handle).await;
            *slot = None;
            result?;
        }
        if self.inner.sealed.load(Ordering::SeqCst) != 0 {
            return Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "bot runtime is sealed",
                true,
                None,
            ));
        }
        let runtime = self.clone();
        let cancel = self.inner.reply_cancel.clone();
        let notify = self.inner.publish_notify.clone();
        let handle = tokio::spawn(async move {
            loop {
                let notified = notify.notified();
                tokio::pin!(notified);
                tokio::select! {
                    _ = cancel.cancelled() => return,
                    _ = &mut notified => {}
                }
                if runtime.inner.sealed.load(Ordering::SeqCst) != 0 {
                    return;
                }
                runtime.publish().await;
            }
        });
        *slot = Some(handle);
        if self.inner.sealed.load(Ordering::SeqCst) != 0 {
            self.inner.publish_notify.notify_one();
            if let Some(handle) = slot.as_mut() {
                let result = join_owned_slot(handle).await;
                *slot = None;
                return result;
            }
        }
        Ok(())
    }

    pub(crate) async fn close_publisher(&self) -> Result<(), FeishuError> {
        let mut slot = self.inner.publisher.lock().await;
        if let Some(handle) = slot.as_mut() {
            let result = join_owned_slot(handle).await;
            *slot = None;
            result
        } else {
            Ok(())
        }
    }

    pub async fn snapshot(&self) -> BotsStateSnapshot {
        self.inner.canonical.lock().await.clone()
    }

    pub(crate) fn default_model_route(
        &self,
    ) -> Result<pl_protocol::studio::BotModelRoute, FeishuError> {
        let settings = self.inner.config.read().map_err(|error| {
            FeishuError::new(FeishuErrorKind::Unavailable, error.to_string(), false, None)
        })?;
        let route = settings
            .config
            .mode_model_route(&pl_protocol::ThreadModeId::simple())
            .map_err(|error| {
                FeishuError::new(FeishuErrorKind::Rejected, error.to_string(), false, None)
            })?;
        Ok(pl_protocol::studio::BotModelRoute {
            account_id: route.account_id.as_str().into(),
            model_id: route.model_id.clone(),
            effort: route.effort.as_ref().map(|effort| effort.as_str().into()),
        })
    }

    /// Resolve ownership from durable bindings, never from a user-controlled ID prefix.
    pub(crate) async fn config_for_thread(
        &self,
        thread_id: &str,
    ) -> Result<Option<BotConfigFile>, FeishuError> {
        let bots: Vec<_> = self
            .inner
            .bots
            .lock()
            .await
            .values()
            .filter_map(|record| record.published.clone())
            .collect();
        for bot in bots {
            if bot.store.owns_thread(thread_id).await?
                || bot.store.has_source_thread(thread_id).await?
            {
                return Ok(Some(bot.config.lock().await.clone()));
            }
        }
        Ok(None)
    }

    pub(crate) fn runtime_released(&self) -> bool {
        self.inner.sealed.load(Ordering::SeqCst) == BOTS_RUNTIME_RELEASED
    }

    /// 成功关闭末尾：在 publish_gate→bots 锁序内标记已释放并清空运行时资源登记。
    /// 已进入 publish 且通过 released 检查的调用先完成；后继 publish 在门内复查必退出。
    pub(crate) async fn release_runtime_records(&self) {
        let _gate = self.inner.publish_gate.lock().await;
        let mut bots = self.inner.bots.lock().await;
        if self.inner.sealed.load(Ordering::SeqCst) == BOTS_RUNTIME_RELEASED {
            return;
        }
        self.inner
            .sealed
            .store(BOTS_RUNTIME_RELEASED, Ordering::SeqCst);
        bots.clear();
    }

    pub(crate) async fn publish(&self) {
        if self.runtime_released() {
            return;
        }
        let _gate = self.inner.publish_gate.lock().await;
        if self.runtime_released() {
            return;
        }
        if self.inner.publish_exhausted.load(Ordering::SeqCst) {
            return;
        }
        // 读取上一次已发布的 canonical：配对列表读取失败时保留该 bot 的已发布列表。
        let previous = self.inner.canonical.lock().await.clone();
        let bots = self.list_snapshots(&previous).await;
        let registration = self
            .inner
            .registration
            .lock()
            .await
            .as_ref()
            .map(Self::registration_snapshot);
        let pending_credential_operations = self.pending_projections().await;
        let updated_at = unix_seconds();
        let mut canonical = self.inner.canonical.lock().await;
        let Some(revision) = canonical.revision.checked_add(1) else {
            // 水位耗尽：保留最后合法 canonical，不发射复用 revision 的新 frame。
            if !self.inner.publish_exhausted.swap(true, Ordering::SeqCst) {
                tracing::error!(
                    "bot canonical revision is exhausted; further state frames are not published"
                );
            }
            return;
        };
        let snapshot = BotsStateSnapshot {
            revision,
            updated_at,
            bots,
            registration,
            pending_credential_operations,
        };
        *canonical = snapshot.clone();
        drop(canonical);
        self.inner
            .events
            .emit(crate::StudioProductEventKind::BotsStateChanged(snapshot));
    }

    pub(crate) async fn list_snapshots(&self, previous: &BotsStateSnapshot) -> Vec<BotSnapshot> {
        let records = self.inner.bots.lock().await;
        let published = records
            .iter()
            .filter_map(|(id, record)| {
                record
                    .published
                    .as_ref()
                    .map(|bot| (id.clone(), bot.clone()))
            })
            .collect::<Vec<_>>();
        drop(records);
        let mut snapshots = Vec::new();
        for (id, bot) in published {
            let prior = previous.bots.iter().find(|snapshot| snapshot.id == id);
            snapshots.push(self.snapshot_managed(&id, &bot, prior).await);
        }
        snapshots.sort_by(|left, right| left.id.cmp(&right.id));
        snapshots
    }

    async fn snapshot_managed(
        &self,
        id: &str,
        bot: &ManagedBot,
        previous: Option<&BotSnapshot>,
    ) -> BotSnapshot {
        let config = bot.config.lock().await.clone();
        let mut diagnostic = bot.diagnostic.lock().await.clone();
        let pairing = match bot.store.list_pairings().await {
            Ok(rows) => rows
                .into_iter()
                .map(|row| BotPairingRequest {
                    request_id: row.request_id,
                    bot_id: id.to_string(),
                    open_id: row.open_id,
                    display_name: row.display_name,
                    created_at: row.created_at,
                })
                .collect(),
            Err(_) => {
                // 读取失败不等于“没有待确认”：保留上次已发布的列表，并把配对不可读
                // 显式并入诊断（既有其它诊断不得遮住它）。既有不可恢复分类不被弱化，
                // 不追加底层错误或载荷，也不阻断其他 bot 的投影。
                let fault =
                    FeishuError::new(FeishuErrorKind::Unavailable, PAIRING_UNREADABLE, true, None)
                        .diagnostic();
                diagnostic = Some(match diagnostic {
                    Some(existing) if existing.message.contains(PAIRING_UNREADABLE) => existing,
                    Some(existing) => BotDiagnostic {
                        message: format!("{}; {}", existing.message, PAIRING_UNREADABLE),
                        retryable: existing.retryable,
                        ..existing
                    },
                    None => fault,
                });
                previous
                    .map(|snapshot| snapshot.pairing.clone())
                    .unwrap_or_default()
            }
        };
        let occupancy = bot.store.identity_occupancy().await.ok();
        let (can_change_project, can_change_app_id) = match occupancy {
            Some(value) => (
                !value.has_thread_or_inbound,
                !value.has_app_identity
                    && config.feishu().trusted_open_ids.is_empty()
                    && config.feishu().trusted_chat_ids.is_empty(),
            ),
            None => (false, false),
        };
        let last_activity_at = match bot.store.last_activity_at().await {
            Ok(at) => at,
            Err(error) => {
                tracing::warn!(%error, "bot activity is unavailable");
                None
            }
        };
        BotSnapshot {
            last_activity_at,
            workspace_path: self
                .inner
                .paths
                .bot_dir(&config.id)
                .join("workspace")
                .to_string_lossy()
                .into_owned(),
            model_route: config.model_route.clone(),
            id: config.id.clone(),
            name: config.name.clone(),
            project_id: config.project_id.clone(),
            app_id: config.feishu().app_id.clone(),
            platform: BotPlatform::FeishuChina,
            enabled: config.enabled,
            tools_enabled: config.tools_enabled,
            config_revision: config.config_revision,
            trusted_open_ids: config.feishu().trusted_open_ids.iter().cloned().collect(),
            trusted_chat_ids: config.feishu().trusted_chat_ids.iter().cloned().collect(),
            connection: bot.connection.snapshot(),
            credential: *bot.credential.lock().await,
            credential_operation: bot.credential_operation.lock().await.clone(),
            pairing,
            diagnostic,
            can_change_project,
            can_change_app_id,
            created_at: config.created_at,
            updated_at: config.updated_at,
        }
    }
}

pub(crate) struct RuntimeInboundHost {
    pub(crate) runtime: BotRuntime,
    pub(crate) current: Arc<AtomicU64>,
    pub(crate) expected: u64,
}

impl InboundHost for RuntimeInboundHost {
    fn is_current(&self) -> bool {
        self.current.load(Ordering::Acquire) == self.expected
    }

    async fn admit(&self, bot_id: &str, decision: InboundDecision) -> Result<(), FeishuError> {
        self.runtime
            .admit_decision(bot_id, self.expected, decision)
            .await
    }
}

async fn join_owned_slot(handle: &mut JoinHandle<()>) -> Result<(), FeishuError> {
    let joined = Pin::new(handle).await;
    match joined {
        Ok(()) => Ok(()),
        Err(error) if error.is_cancelled() => Ok(()),
        // 取消类终态已在上一个分支按职责视为正常收回；这里只剩异常终止。
        // 只给安全分类：不把原始 panic 载荷写进诊断。
        Err(_) => Err(FeishuError::new(
            FeishuErrorKind::Unavailable,
            "bot background task terminated abnormally",
            true,
            None,
        )),
    }
}
