//! Owns bot identity and the application IDs protected by each live obligation.
use super::connect::WatchSlot;
use super::operation::{BotDiagnosticSet, BotOperationOwner};
use super::owner::{BotRuntime, ManagedBot};
use super::protocol::error::{FeishuError, FeishuErrorKind};
use crate::{BotCredentialOperation, BotPendingCredentialOperation};
use std::collections::BTreeMap;
use std::sync::Arc;
use std::sync::atomic::Ordering;
use tokio::sync::Mutex;

pub(crate) struct BotRecord {
    pub(crate) published: Option<Arc<ManagedBot>>,
    pub(crate) operation: Arc<BotOperationOwner>,
    apps: AppReservations,
    pub(crate) pending: Option<PendingProjection>,
    pub(crate) watch: Arc<Mutex<WatchSlot>>,
}

#[derive(Clone)]
pub(crate) struct PendingProjection {
    pub bot_id: String,
    pub operation: BotCredentialOperation,
    pub diagnostics: BotDiagnosticSet,
}

/// 跨机器人应用唯一性的一次裁决结果。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum AppClaim {
    /// 本 owner 现在持有该应用（新登记或已是同一目标）。
    Held,
    /// 另一个机器人已发布或已认领同一应用。
    Conflict,
    /// 本 owner 仍有未收束的清理/停连义务或未决目标：先显式 Retry 完成原义务。
    Unsettled,
    /// 运行时已封口或资源记录已释放，不能再登记新工作。
    Sealed,
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum CandidateSettlement {
    Retain,
    Cleared,
    Unchanged,
}

/// A bot can protect its published app and a distinct in-flight app concurrently.
/// Each obligation has one owner and can be released only by its corresponding transition.
#[derive(Clone, Copy)]
enum AppReservation {
    Published,
    Claimed,
    CleanupPending,
    PendingStop,
}

#[derive(Default)]
struct AppReservations([Option<String>; 4]);

impl AppReservations {
    fn holds(&self, app_id: &str) -> bool {
        self.0.iter().flatten().any(|id| id == app_id)
    }

    fn get(&self, state: AppReservation) -> Option<&str> {
        self.0[state as usize].as_deref()
    }

    fn take(&mut self, state: AppReservation) -> Option<String> {
        self.0[state as usize].take()
    }

    fn reserve(&mut self, state: AppReservation, app_id: &str) {
        self.0[state as usize] = Some(app_id.to_owned());
    }

    fn unsettled(&self) -> bool {
        [
            AppReservation::Claimed,
            AppReservation::CleanupPending,
            AppReservation::PendingStop,
        ]
        .into_iter()
        .any(|state| self.get(state).is_some())
    }
}

#[derive(Default)]
pub(super) struct BotRegistry {
    records: BTreeMap<String, BotRecord>,
}

impl BotRegistry {
    pub(super) fn get(&self, bot_id: &str) -> Option<&BotRecord> {
        self.records.get(bot_id)
    }

    pub(super) fn get_mut(&mut self, bot_id: &str) -> Option<&mut BotRecord> {
        self.records.get_mut(bot_id)
    }

    pub(super) fn iter(&self) -> impl Iterator<Item = (&String, &BotRecord)> {
        self.records.iter()
    }

    pub(super) fn values(&self) -> impl Iterator<Item = &BotRecord> {
        self.records.values()
    }

    pub(super) fn clear(&mut self) {
        self.records.clear();
    }

    fn claim(&mut self, bot_id: &str, app_id: &str) -> AppClaim {
        let Some(record) = self.get(bot_id) else {
            return AppClaim::Sealed;
        };
        if record.apps.get(AppReservation::Claimed) == Some(app_id) {
            return AppClaim::Held;
        }
        if record.apps.unsettled() {
            return AppClaim::Unsettled;
        }
        self.reserve(bot_id, app_id, AppReservation::Claimed)
    }

    fn reserve(&mut self, bot_id: &str, app_id: &str, state: AppReservation) -> AppClaim {
        if self
            .records
            .iter()
            .any(|(id, record)| id != bot_id && record.apps.holds(app_id))
        {
            return AppClaim::Conflict;
        }
        let Some(record) = self.get_mut(bot_id) else {
            return AppClaim::Sealed;
        };
        record.apps.reserve(state, app_id);
        AppClaim::Held
    }

    fn promote(&mut self, bot_id: &str, app_id: &str) -> AppClaim {
        let result = self.reserve(bot_id, app_id, AppReservation::Published);
        if result == AppClaim::Held
            && let Some(record) = self.get_mut(bot_id)
            && record.apps.get(AppReservation::Claimed) == Some(app_id)
        {
            record.apps.take(AppReservation::Claimed);
        }
        result
    }
}

impl BotRuntime {
    pub(crate) fn new_record(runtime: BotRuntime, bot_id: String) -> BotRecord {
        BotRecord {
            published: None,
            operation: Arc::new(BotOperationOwner::new(runtime, bot_id)),
            apps: AppReservations::default(),
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
        records.records.insert(
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
                diagnostic: pending.diagnostics.projection(),
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

    // Registry locking covers only in-memory identity decisions. Callers release the
    // lock before waiting on a credential, admission mutex, or socket worker.
    async fn claim_app_target(&self, bot_id: &str, app_id: &str) -> AppClaim {
        let mut registry = self.inner.bots.lock().await;
        if self.management_sealed() {
            return AppClaim::Sealed;
        }
        registry.claim(bot_id, app_id)
    }

    /// Publish the durable app and transfer any surviving candidate obligation
    /// in one registry transition. Another bot must never observe the candidate
    /// as free between dropping its claim and retaining it for cleanup.
    pub(super) async fn publish_app_reservation(
        &self,
        bot_id: &str,
        app_id: &str,
        candidate: Option<&str>,
        settlement: CandidateSettlement,
    ) -> AppClaim {
        let mut registry = self.inner.bots.lock().await;
        let result = if self.management_sealed() {
            AppClaim::Sealed
        } else {
            registry.promote(bot_id, app_id)
        };
        if let Some(record) = registry.get_mut(bot_id) {
            let claimed = record.apps.take(AppReservation::Claimed);
            let candidate = candidate.map(str::to_owned).or_else(|| match settlement {
                CandidateSettlement::Retain => claimed.or_else(|| Some(app_id.to_owned())),
                CandidateSettlement::Cleared | CandidateSettlement::Unchanged => None,
            });
            if let Some(candidate) = candidate
                && (settlement == CandidateSettlement::Retain || candidate != app_id)
            {
                record
                    .apps
                    .reserve(AppReservation::CleanupPending, &candidate);
            } else if settlement == CandidateSettlement::Cleared {
                record.apps.take(AppReservation::CleanupPending);
            }
        }
        result
    }

    pub(super) async fn abandon_app_reservation(
        &self,
        bot_id: &str,
        candidate: Option<&str>,
        retain: bool,
    ) {
        let mut registry = self.inner.bots.lock().await;
        if let Some(record) = registry.get_mut(bot_id) {
            let claimed = record.apps.take(AppReservation::Claimed);
            if retain {
                if let Some(candidate) = candidate.map(str::to_owned).or(claimed) {
                    record
                        .apps
                        .reserve(AppReservation::CleanupPending, &candidate);
                }
            } else {
                record.apps.take(AppReservation::CleanupPending);
            }
        }
    }

    async fn release_reservation(&self, bot_id: &str, state: AppReservation) -> Option<String> {
        self.inner
            .bots
            .lock()
            .await
            .get_mut(bot_id)
            .and_then(|record| record.apps.take(state))
    }

    pub(super) async fn retain_cleanup_app(&self, bot_id: &str, app_id: &str) {
        if let Some(record) = self.inner.bots.lock().await.get_mut(bot_id) {
            record.apps.reserve(AppReservation::CleanupPending, app_id);
        }
    }

    pub(super) async fn clear_cleanup_app(&self, bot_id: &str) {
        self.release_reservation(bot_id, AppReservation::CleanupPending)
            .await;
    }

    pub(super) async fn retain_pending_stop_app(&self, bot_id: &str, app_id: &str) {
        if let Some(record) = self.inner.bots.lock().await.get_mut(bot_id)
            && record.apps.get(AppReservation::PendingStop).is_none()
        {
            record.apps.reserve(AppReservation::PendingStop, app_id);
        }
    }

    pub(super) async fn clear_pending_stop_app(&self, bot_id: &str) {
        self.release_reservation(bot_id, AppReservation::PendingStop)
            .await;
    }

    pub(super) async fn release_app_claim(&self, bot_id: &str) {
        self.release_reservation(bot_id, AppReservation::Claimed)
            .await;
    }

    pub(super) async fn claim_app_target_or_error(
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

    pub(super) async fn reject_unsettled_obligation(
        &self,
        bot_id: &str,
    ) -> Result<(), FeishuError> {
        let records = self.inner.bots.lock().await;
        let Some(record) = records.get(bot_id) else {
            return Ok(());
        };
        if record.apps.unsettled() {
            return Err(unsettled_intent_error());
        }
        Ok(())
    }
}

pub(super) fn sealed_error() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        "bot runtime is sealed",
        true,
        None,
    )
}

pub(super) fn duplicate_app_error() -> FeishuError {
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
