//! Bot-owned archive/claim exclusion and rebuildable, bounded orphan recovery.
//! The operation owner outlives configuration versions. Only the send ledger retains bytes.
use super::BotRuntime;
use super::commands::{FrozenSendClaim, send_claim_freeze_bytes};
use super::occupancy::OccupancyBudget;
use super::protocol::error::{FeishuError, FeishuErrorKind};
use super::send::{SendPlan, SendSource, markdown_fits, plan_file, plan_markdown};
use super::send_service::{SendAdmission, SendRequest, into_record};
use super::storage::{BotStateStore, SendRecord, SendResourceReferenceCursor};
use crate::resource_store::{
    DirectorySyncOutcome, FileResourceStore, OwnedResourceObject, OwnedResourceScan,
};
use std::collections::BTreeSet;
use std::sync::Arc;
use tokio_util::sync::CancellationToken;

// Send records were admitted under the existing 64 MiB metadata-freeze ceiling. One strict
// ledger row at a time needs at most two such stored/decoded copies, plus bounded candidates.
pub(super) const MAINTENANCE_TEXT_BYTES: usize = 48 * 1024 * 1024;
const SCAN_WORK: usize = 512;
const QUERY_WORK: usize = 64;
const DELETE_WORK: usize = 512;

pub(super) enum SendInput {
    Markdown(String),
    File {
        request_hash: String,
        source: Box<SendSource>,
        filename: String,
        bytes: Arc<[u8]>,
    },
}

impl SendInput {
    fn needs_archive(&self, operation: &str, bot: &str, chat: &str) -> Result<bool, FeishuError> {
        match self {
            Self::Markdown(text) => markdown_fits(operation, bot, chat, text).map(|fits| !fits),
            Self::File { .. } => Ok(true),
        }
    }

    async fn plan(
        self,
        store: &FileResourceStore,
        operation: &str,
        bot: &str,
        chat: &str,
    ) -> Result<SendPlan, FeishuError> {
        match self {
            Self::Markdown(text) => plan_markdown(store, operation, bot, chat, text).await,
            Self::File {
                request_hash,
                source,
                filename,
                bytes,
            } => {
                let resource = store
                    .retain_bytes_with_receipt(bytes, "application/octet-stream")
                    .await
                    .map_err(FeishuError::send_resource)?;
                plan_file(operation, request_hash, *source, filename, resource)
            }
        }
    }
}

struct ReferenceBatch {
    objects: Vec<OwnedResourceObject>,
    ids: Vec<String>,
    referenced: BTreeSet<String>,
    after: Option<SendResourceReferenceCursor>,
    complete: bool,
}

#[derive(Default)]
struct SweepProgress {
    scan: Option<OwnedResourceScan>,
    pending: Option<ReferenceBatch>,
    end: bool,
    removed_in_pass: bool,
}

/// This mutex-protected value lives on BotOperationOwner, never on a published config/store clone.
/// A cursor is only resumable work, not a second source of resource references.
pub(super) struct SendResources {
    store: FileResourceStore,
    sweep: Option<SweepProgress>,
    failure: Option<FeishuError>,
    /// Windows' terminal Unsupported remains distinct from an actual Unix Synced barrier.
    directory_sync: Option<DirectorySyncOutcome>,
}

impl SendResources {
    pub(super) fn new(store: FileResourceStore) -> Self {
        Self {
            store,
            sweep: Some(SweepProgress::default()),
            failure: None,
            directory_sync: None,
        }
    }

    pub(super) fn needs_maintenance(&self) -> bool {
        self.sweep.is_some()
    }
    pub(super) fn failure(&self) -> Option<FeishuError> {
        self.failure.clone()
    }

    /// Every await is driven by occupancy or the existing shutdown task slot. Budget exhaustion
    /// keeps both the directory iterator and the current ledger cursor; only an actual failure
    /// restarts a pass, because its partial unlink outcome must be checked again.
    pub(super) async fn maintain(&mut self, ledger: &BotStateStore) -> Result<(), FeishuError> {
        let result = self.sweep_step(ledger).await;
        match &result {
            Ok(()) => self.failure = None,
            Err(error) => {
                if error.kind() != FeishuErrorKind::Busy {
                    self.sweep = Some(SweepProgress::default());
                }
                self.failure = Some(error.clone());
            }
        }
        result
    }

    async fn sweep_step(&mut self, ledger: &BotStateStore) -> Result<(), FeishuError> {
        FileResourceStore::preflight_directory_sync().map_err(FeishuError::send_resource)?;
        let mut scanned = 0;
        let mut queries = 0;
        let mut deleted = 0;
        loop {
            let Some(progress) = self.sweep.as_mut() else {
                return Ok(());
            };
            if let Some(batch) = progress.pending.as_mut() {
                if !batch.complete {
                    let needed = if batch.after.is_some() { 1 } else { 2 };
                    if queries + needed > QUERY_WORK {
                        return Err(maintenance_pending());
                    }
                    let page = ledger
                        .referenced_send_resources(&batch.ids, batch.after)
                        .await?;
                    queries += page.query_work;
                    batch.referenced.extend(page.referenced);
                    batch.complete = page.continuation.is_none();
                    batch.after = page.continuation;
                    continue;
                }
                let garbage_count = batch
                    .objects
                    .iter()
                    .filter(|object| {
                        object
                            .resource_id()
                            .is_none_or(|id| !batch.referenced.contains(id))
                    })
                    .count();
                if deleted + garbage_count > DELETE_WORK {
                    return Err(maintenance_pending());
                }
                let batch = progress.pending.take().ok_or_else(maintenance_pending)?;
                let garbage = batch
                    .objects
                    .into_iter()
                    .filter(|object| {
                        object
                            .resource_id()
                            .is_none_or(|id| !batch.referenced.contains(id))
                    })
                    .collect::<Vec<_>>();
                deleted += garbage.len();
                progress.removed_in_pass |= !garbage.is_empty();
                self.directory_sync = Some(
                    self.store
                        .remove_owned_batch(garbage)
                        .await
                        .map_err(FeishuError::send_resource)?,
                );
                continue;
            }
            if progress.end {
                // Repay sync even after an earlier unlink succeeded but its barrier failed.
                self.directory_sync = Some(
                    self.store
                        .remove_owned_batch(Vec::new())
                        .await
                        .map_err(FeishuError::send_resource)?,
                );
                if progress.removed_in_pass {
                    // A fresh verification pass also handles platforms whose directory iterator
                    // may skip entries as earlier batches are unlinked. Its budget still counts.
                    *progress = SweepProgress::default();
                    continue;
                }
                self.sweep = None;
                return Ok(());
            }
            if scanned == SCAN_WORK {
                return Err(maintenance_pending());
            }
            let batch = self
                .store
                .owned_batch(progress.scan.take(), (SCAN_WORK - scanned).min(128))
                .await
                .map_err(FeishuError::send_resource)?;
            scanned += batch.objects.len();
            progress.end = batch.continuation.is_none();
            progress.scan = batch.continuation;
            if !batch.objects.is_empty() {
                let ids = batch
                    .objects
                    .iter()
                    .filter_map(|object| object.resource_id().map(str::to_owned))
                    .collect();
                progress.pending = Some(ReferenceBatch {
                    objects: batch.objects,
                    ids,
                    referenced: BTreeSet::new(),
                    after: None,
                    complete: false,
                });
            }
        }
    }

    fn referenced_commit(&mut self, retention: DirectorySyncOutcome) {
        // The pre-production sweep was complete, and this exclusive producer retained exactly
        // the immutable objects in the now-confirmed claim. No unreferenced object was created:
        // retain already removed its stage and completed the available namespace barrier BEFORE
        // claim. Nothing changed afterwards: a second fallible barrier could strand NotStarted.
        self.directory_sync = Some(retention);
        self.sweep = None;
        self.failure = None;
    }
}

pub(super) struct ClaimedSend {
    pub(super) record: SendRecord,
    pub(super) revision: u64,
    pub(super) replay: bool,
}

struct ProductionClaim {
    operation_id: String,
    bot_id: String,
    chat_id: String,
    authority: super::SendAuthority,
    preparation: SendAdmission,
    cancel: CancellationToken,
}

impl BotRuntime {
    pub(super) async fn maintain_send_resources(&self, bot_id: &str) -> Result<(), FeishuError> {
        let owner = self.ensure_record(bot_id).await?;
        let gate = owner.send_resources.clone();
        let managed = self.managed(bot_id).await?;
        self.submit_occupancy(MAINTENANCE_TEXT_BYTES, move |_budget| async move {
            let outcome = gate.lock().await.maintain(&managed.store).await;
            project_cleanup(&managed, &outcome).await;
            outcome
        })
        .await
    }

    pub(super) async fn produce_send_owned(
        &self,
        request: SendRequest,
        preparation: SendAdmission,
        cancel: CancellationToken,
        mut budget: OccupancyBudget,
    ) -> Result<ClaimedSend, FeishuError> {
        FileResourceStore::preflight_directory_sync().map_err(FeishuError::send_resource)?;
        let owner = self.ensure_record(&request.bot_id).await?;
        let archive = request.input.needs_archive(
            &request.operation_id,
            &request.bot_id,
            &request.chat_id,
        )?;
        let SendRequest {
            operation_id,
            bot_id,
            chat_id,
            authority,
            input,
        } = request;
        let production = ProductionClaim {
            operation_id,
            bot_id,
            chat_id,
            authority,
            preparation,
            cancel,
        };
        if !archive {
            self.check_send_active(&production.cancel)?;
            let plan = input
                .plan(
                    &self.send_resources(&production.bot_id),
                    &production.operation_id,
                    &production.bot_id,
                    &production.chat_id,
                )
                .await?;
            return self.claim_plan_owned(production, plan, &mut budget).await;
        }
        let mut resources = owner.send_resources.lock().await;
        let mut maintenance_reserved = false;
        if resources.needs_maintenance() {
            budget.reserve_more(MAINTENANCE_TEXT_BYTES)?;
            maintenance_reserved = true;
            let outcome = resources
                .maintain(&production.preparation.managed.store)
                .await;
            project_cleanup(&production.preparation.managed, &outcome).await;
            outcome?;
        }
        self.check_production_admission(&production).await?;
        resources.sweep = Some(SweepProgress::default());
        let store = resources.store.clone();
        let ledger = production.preparation.managed.clone();
        let result = async {
            let plan = input
                .plan(
                    &store,
                    &production.operation_id,
                    &production.bot_id,
                    &production.chat_id,
                )
                .await?;
            let retention = plan.retention.ok_or_else(|| {
                FeishuError::new(
                    FeishuErrorKind::Unavailable,
                    "archived send lacks its completed retention receipt",
                    false,
                    None,
                )
            })?;
            self.check_send_active(&production.cancel)?;
            self.claim_plan_owned(production, plan, &mut budget)
                .await
                .map(|claimed| (claimed, retention))
        }
        .await;
        match result {
            Ok((claimed, retention)) => {
                resources.referenced_commit(retention);
                project_cleanup(&ledger, &Ok(())).await;
                Ok(claimed)
            }
            Err(primary) => {
                // The worker still owns the gate/bytes permit and waits for all physical work.
                // If the extra cleanup budget was unavailable, keep a real pending obligation.
                let cleanup = if maintenance_reserved
                    || budget.reserve_more(MAINTENANCE_TEXT_BYTES).is_ok()
                {
                    resources.maintain(&ledger.store).await
                } else {
                    Err(maintenance_pending())
                };
                project_cleanup(&ledger, &cleanup).await;
                if let Err(error) = cleanup {
                    resources.failure = Some(error);
                }
                Err(primary)
            }
        }
    }

    async fn check_production_admission(
        &self,
        production: &ProductionClaim,
    ) -> Result<(), FeishuError> {
        let ProductionClaim {
            preparation,
            cancel,
            ..
        } = production;
        let _admission = preparation.managed.admission.lock().await;
        self.check_send_active(cancel)?;
        self.reject_closed_admission(&preparation.managed)?;
        let config = preparation.managed.config.lock().await;
        self.check_send_active(cancel)?;
        self.authorize_chat(
            &config,
            &production.chat_id,
            production.authority.clone(),
            &preparation.membership,
        )?;
        if config.feishu().app_id != preparation.app_id
            || config.project_id != preparation.project_id
            || config.config_revision != preparation.revision
        {
            return Err(super::send_service::conflict());
        }
        Ok(())
    }

    async fn claim_plan_owned(
        &self,
        production: ProductionClaim,
        plan: SendPlan,
        budget: &mut OccupancyBudget,
    ) -> Result<ClaimedSend, FeishuError> {
        let ProductionClaim {
            operation_id,
            bot_id,
            chat_id,
            authority,
            preparation,
            cancel,
        } = production;
        let record = into_record(operation_id, bot_id, chat_id, plan);
        budget.reserve_more(send_claim_freeze_bytes(
            &record,
            &authority,
            &preparation.app_id,
            &preparation.project_id,
            super::storage::segment_facts_bytes(&record.segments)?,
        )?)?;
        let frozen = FrozenSendClaim {
            managed: preparation.managed,
            record: record.clone(),
            membership: preparation.membership,
            authority,
            app_id: preparation.app_id,
            project_id: preparation.project_id,
            expected_config_revision: preparation.revision,
            cancel,
        };
        let (existing, revision) = self.claim_send_owned(frozen, budget).await?;
        Ok(ClaimedSend {
            replay: existing.is_some(),
            record: existing.unwrap_or(record),
            revision,
        })
    }
}

async fn project_cleanup(managed: &super::owner::ManagedBot, outcome: &Result<(), FeishuError>) {
    let mut diagnostic = managed.diagnostic.lock().await;
    let ours = diagnostic
        .as_ref()
        .is_some_and(|diagnostic| diagnostic.code == "sendResourceCleanup");
    match outcome {
        Ok(()) if ours => *diagnostic = None,
        Err(error) if diagnostic.is_none() || ours => {
            let mut value = error.diagnostic();
            value.code = "sendResourceCleanup".into();
            *diagnostic = Some(value);
        }
        _ => {}
    }
}

fn maintenance_pending() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Busy,
        "send resource cleanup has bounded work remaining; retry to continue before new archive",
        true,
        None,
    )
}

#[cfg(all(test, unix))]
mod persistence_fault_tests {
    use super::super::send::{SendContent, SendSource};
    use super::*;
    use crate::resource_store::ResourceStoreError;
    use pl_core::context::ResourceReader;

    /// Crash recovery may span maintenance budgets. Once Clean is proven, an exact new committed
    /// resource must not be stranded by another full-history scan after its claim succeeds.
    #[tokio::test]
    async fn history_recovery_keeps_failed_sync_obligations_and_unblocks_known_commits()
    -> Result<(), Box<dyn std::error::Error>> {
        let directory = tempfile::tempdir()?;
        let root = directory.path().join("send-resources");
        let ledger_path = directory.path().join("state.sqlite");
        let ledger = BotStateStore::new(ledger_path.clone());
        let mut resources = SendResources::new(FileResourceStore::beneath(
            directory.path().to_owned(),
            root.clone(),
        ));
        assert_eq!(
            FileResourceStore::preflight_directory_sync()?,
            DirectorySyncOutcome::NotRequired
        );
        assert!(
            !root.exists(),
            "platform capability is known before the first archive"
        );
        let mut historical = Vec::new();
        let source = SendSource {
            bot_id: "bot".into(),
            chat_id: "chat".into(),
            app_id: "app".into(),
            project_id: "project".into(),
            thread_id: "thread".into(),
            input_id: "input".into(),
            original_input_id: "input".into(),
            message_id: "message".into(),
            open_id: "open".into(),
            chat_kind: "direct".into(),
            creation_id: "thread".into(),
            binding_revision: 1,
        };
        for index in 0_u32..513 {
            let operation = format!("persisted-{index:04}");
            let retained = resources
                .store
                .retain_bytes_with_receipt(
                    Arc::from(index.to_le_bytes().to_vec()),
                    "application/octet-stream",
                )
                .await?;
            let plan = plan_file(
                &operation,
                operation.clone(),
                source.clone(),
                "file.bin".into(),
                retained,
            )?;
            if let SendContent::File { resource, .. } = &plan.segments[0] {
                historical.push(resource.clone());
            }
            let record = into_record(operation, "bot".into(), "chat".into(), plan);
            ledger.claim_send(&record).await?;
        }
        let mut recovery_jobs = 0;
        loop {
            recovery_jobs += 1;
            match resources.maintain(&ledger).await {
                Ok(()) => break,
                Err(error) if error.kind() == FeishuErrorKind::Busy && recovery_jobs < 150 => {}
                Err(error) => return Err(error.into()),
            }
        }
        assert!(
            recovery_jobs > 1,
            "fixture must exceed both recovery work budgets"
        );
        resources.sweep = Some(SweepProgress::default());
        resources
            .store
            .inject_directory_sync_failures_after_unlink(1);
        let failed_archive = SendInput::File {
            request_hash: "new-request".into(),
            source: Box::new(source.clone()),
            filename: "new.bin".into(),
            bytes: Arc::from(b"new complete original".as_slice()),
        }
        .plan(&resources.store, "new-send", "bot", "chat")
        .await;
        let error = match failed_archive {
            Err(error) => error,
            Ok(_) => panic!("the actual preclaim archive barrier fault must prevent a plan"),
        };
        assert_eq!(error.kind(), FeishuErrorKind::Unavailable);
        assert!(
            error.retryable(),
            "even Unix Unsupported IO remains a retryable barrier failure"
        );
        assert!(
            ledger.load_send("new-send").await?.is_none(),
            "failed archive cannot create a claim"
        );
        assert!(resources.needs_maintenance());
        for attempt in 0..150 {
            match resources.maintain(&ledger).await {
                Ok(()) => break,
                Err(error) if error.kind() == FeishuErrorKind::Busy && attempt < 149 => {}
                Err(error) => return Err(error.into()),
            }
        }
        assert!(!resources.needs_maintenance());
        assert_eq!(
            std::fs::read_dir(&root)?.count(),
            513,
            "failed preclaim archive orphan is removed"
        );
        for original in &historical {
            assert!(
                resources
                    .store
                    .read(original.clone(), Default::default())
                    .await
                    .is_ok()
            );
        }
        resources.sweep = Some(SweepProgress::default());
        let plan = SendInput::File {
            request_hash: "new-request".into(),
            source: Box::new(source),
            filename: "new.bin".into(),
            bytes: Arc::from(b"new complete original".as_slice()),
        }
        .plan(&resources.store, "new-send", "bot", "chat")
        .await?;
        let retention = plan.retention.ok_or("preclaim retention receipt missing")?;
        assert_eq!(retention, DirectorySyncOutcome::Synced);
        let reference = match &plan.segments[0] {
            SendContent::File { resource, .. } => resource.clone(),
            _ => return Err("file plan lost its resource".into()),
        };
        let record = into_record("new-send".into(), "bot".into(), "chat".into(), plan);
        assert!(ledger.claim_send(&record).await?.is_none());
        resources.referenced_commit(retention);
        assert!(
            !resources.needs_maintenance(),
            "known committed producer must be ready for delivery, not require replay of a NotStarted ledger"
        );
        assert!(
            resources
                .store
                .read(reference.clone(), Default::default())
                .await
                .is_ok()
        );
        let stored = ledger
            .load_send("new-send")
            .await?
            .ok_or("new claim was lost")?;
        assert_eq!(stored.content_hash, record.content_hash);

        // A later process interruption leaves an unclaimed original beside real retained history.
        let before = std::fs::read_dir(&root)?
            .map(|entry| entry.map(|entry| entry.file_name()))
            .collect::<Result<BTreeSet<_>, _>>()?;
        let orphan = resources
            .store
            .retain_bytes(
                Arc::from(b"archive interrupted before claim".as_slice()),
                "application/octet-stream",
            )
            .await?;
        let orphan_name = std::fs::read_dir(&root)?
            .map(|entry| entry.map(|entry| entry.file_name()))
            .collect::<Result<BTreeSet<_>, _>>()?
            .difference(&before)
            .next()
            .cloned()
            .ok_or("unclaimed object missing")?;
        resources.sweep = Some(SweepProgress::default());
        assert_eq!(
            resources
                .maintain(&ledger)
                .await
                .expect_err("history exceeds one maintenance query budget")
                .kind(),
            FeishuErrorKind::Busy
        );
        let foreign = FileResourceStore::new(directory.path().join("foreign"));
        let tokens = resources.store.owned_batch(None, 128).await?;
        assert!(matches!(
            foreign.remove_owned_batch(tokens.objects).await,
            Err(ResourceStoreError::Identity)
        ));
        assert!(
            resources
                .store
                .read(reference.clone(), Default::default())
                .await
                .is_ok(),
            "foreign cleanup must leave committed history untouched"
        );

        // The owner already holds scan/candidate capabilities. Replacing the ambient parent
        // must not redirect orphan cleanup to unrelated bytes in a new namespace.
        let moved = directory.path().join("moved-send-resources");
        std::fs::rename(&root, &moved)?;
        std::fs::create_dir(&root)?;
        std::fs::write(
            root.join(&orphan_name),
            b"unrelated replacement must remain",
        )?;
        resources
            .store
            .inject_directory_sync_failures_after_unlink(2);
        for attempt in 0..150 {
            match resources.maintain(&ledger).await {
                Err(error) if error.kind() == FeishuErrorKind::Busy && attempt < 149 => continue,
                Err(error) => {
                    assert_eq!(error.kind(), FeishuErrorKind::Unavailable);
                    break;
                }
                Ok(()) => panic!("injected post-unlink sync failure must not report Clean"),
            }
        }
        assert!(
            !moved.join(&orphan_name).exists(),
            "unlink happened before the failed durability barrier"
        );
        assert!(resources.needs_maintenance());
        assert!(
            resources.failure().is_some(),
            "the failed cleanup must retain its retry responsibility"
        );
        drop(ledger);
        let ledger = BotStateStore::new(ledger_path);
        assert!(ledger.load_send("new-send").await?.is_some());
        for attempt in 0..150 {
            match resources.maintain(&ledger).await {
                Err(error) if error.kind() == FeishuErrorKind::Busy && attempt < 149 => continue,
                Err(error) => {
                    assert_eq!(error.kind(), FeishuErrorKind::Unavailable);
                    break;
                }
                Ok(()) => panic!("empty cleanup batches must retry the remaining sync obligation"),
            }
        }
        assert!(resources.needs_maintenance());
        let mut retries = 0;
        loop {
            retries += 1;
            match resources.maintain(&ledger).await {
                Ok(()) => break,
                Err(error) if error.kind() == FeishuErrorKind::Busy && retries < 150 => {}
                Err(error) => return Err(error.into()),
            }
        }
        assert!(!resources.needs_maintenance());
        assert!(resources.failure().is_none());
        assert!(
            resources
                .store
                .read(orphan, Default::default())
                .await
                .is_err()
        );
        assert!(
            resources
                .store
                .read(reference, Default::default())
                .await
                .is_ok()
        );
        for original in historical {
            assert!(
                resources
                    .store
                    .read(original, Default::default())
                    .await
                    .is_ok(),
                "retry/reopened ledger must preserve every committed historical original"
            );
        }
        assert_eq!(
            std::fs::read(root.join(orphan_name))?,
            b"unrelated replacement must remain"
        );
        Ok(())
    }
}
