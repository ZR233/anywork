//! Thread archive preparation belongs to the shared HistoryStore, not a tool catalog instance.
use super::{FileResourceStore, ResourceReader, ResourceReference};
use crate::studio::HistoryStore;
use anyhow::{Result, ensure};
use futures::FutureExt;
use pl_core::{
    thread::{
        ThreadEffectBatch, ToolOutcome,
        input::{InputChange, InputRecord, ThreadInput},
    },
    tool::opaque::ToolError,
};
use pl_tool::{artifact::ArtifactReceipt, media::ToolResourceOrigin};
use std::{
    collections::BTreeMap,
    future::Future,
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
};
use tokio_util::sync::CancellationToken;

// Reuse reliable admission metadata and attachment-original budgets; originals are not display text.
const MAX_PREPARATIONS: usize = 4096;
const MAX_METADATA: usize = 64 * 1024 * 1024;
const MAX_RETAINED_BYTES: u64 = pl_protocol::studio::ATTACHMENT_MAX_BATCH_BYTES;

/// Transient attempt identity, never persisted and never derived from an untrusted input ID.
#[derive(Debug, Clone)]
pub(crate) struct InputPreparationIdentity(Arc<()>);
impl PartialEq for InputPreparationIdentity {
    fn eq(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.0, &other.0)
    }
}
impl Eq for InputPreparationIdentity {}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum ArchiveOrigin {
    Tool(ToolResourceOrigin),
    Input {
        thread_id: String,
        input_id: String,
        preparation_id: InputPreparationIdentity,
    },
}

/// Narrow host proof checked again at the single canonical projection boundary.
#[derive(Clone)]
pub(crate) struct PublicationEligibility(pub(crate) Arc<dyn Fn() -> bool + Send + Sync>);
impl std::fmt::Debug for PublicationEligibility {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("PublicationEligibility(..)")
    }
}

#[derive(Debug)]
struct Preparation {
    origin: ArchiveOrigin,
    reserved_bytes: u64,
    metadata: usize,
    io: bool,
    references: Vec<ResourceReference>,
    publication: Option<(ArtifactReceipt, PublicationEligibility)>,
    qualification: Option<(u64, bool)>,
    needs_repair: bool,
    sequence: Option<u64>,
    /// Frozen before sending to core. An external input ID alone never identifies a submission.
    input_submission: Option<Arc<ThreadInput>>,
    /// Canonical admission/receipt proof, independent of whether projection has succeeded yet.
    input_accepted: Option<u64>,
}

impl Preparation {
    fn accepted_in(&self, effect: &ThreadEffectBatch) -> bool {
        self.input_submission.as_ref().is_some_and(|input| {
            effect.inputs.iter().any(|change| {
                matches!(change, InputChange::Accepted(record)
                    if record.accepted_sequence == effect.sequence && &record.input == input.as_ref())
            })
        })
    }
}

#[derive(Default, Debug)]
struct Progress {
    next_id: u64,
    sealed: bool,
    preparations: BTreeMap<u64, Preparation>,
    workers: BTreeMap<u64, ArchiveWorker>,
    /// Intentional bounded self-retention only while an actual obligation is owed. A bare reader
    /// or an idle catalog never installs it, so the coordinator's weak share can expire normally.
    keeper: Option<HistoryStore>,
    cleanup: bool,
    recovered: bool,
    error: Option<String>,
}

type JoinedWorker = futures::future::Shared<
    futures::future::BoxFuture<'static, std::result::Result<(), Arc<tokio::task::JoinError>>>,
>;

#[derive(Clone, Debug)]
struct ArchiveWorker {
    state: tokio::task::AbortHandle,
    joined: JoinedWorker,
}

impl ArchiveWorker {
    fn new(worker: tokio::task::JoinHandle<()>) -> Self {
        Self {
            state: worker.abort_handle(),
            joined: async move { worker.await.map_err(Arc::new) }
                .boxed()
                .shared(),
        }
    }
}

#[derive(Debug)]
struct ArchiveState {
    root: PathBuf,
    attachments: PathBuf,
    store: FileResourceStore,
    progress: Mutex<Progress>,
    maintenance: tokio::sync::Mutex<()>,
    collection: tokio::sync::Mutex<Option<Collection>>,
    changed: tokio::sync::Notify,
}

type Collection =
    futures::future::Shared<futures::future::BoxFuture<'static, std::result::Result<(), Arc<str>>>>;

#[derive(Clone, Debug)]
pub(crate) struct ThreadArchive(Arc<ArchiveState>);
impl ThreadArchive {
    pub(crate) fn new(root: PathBuf, trusted_parent: PathBuf, attachments: PathBuf) -> Self {
        Self(Arc::new(ArchiveState {
            store: FileResourceStore::beneath(trusted_parent, root.clone()),
            root,
            attachments,
            progress: Mutex::new(Progress::default()),
            maintenance: Default::default(),
            collection: Default::default(),
            changed: Default::default(),
        }))
    }
    pub(crate) fn root(&self) -> &Path {
        &self.0.root
    }
    pub(crate) fn attachments(&self) -> &Path {
        &self.0.attachments
    }
}

/// A real holder of the canonical history lifecycle and its one archive coordination identity.
/// It is deliberately not constructible from a resource-directory string by tools or model input.
#[derive(Clone, Debug)]
pub struct ThreadResourceStore {
    history: HistoryStore,
    archive: ThreadArchive,
}

enum CollectionOutcome {
    Clean,
    Deferred,
}

/// Created before spawn so even an unpolled/aborted task leaves the failure with its owner.
struct CollectionCompletion {
    owner: ThreadResourceStore,
    finished: bool,
}

impl CollectionCompletion {
    fn finish(mut self, result: Result<CollectionOutcome>) -> std::result::Result<(), Arc<str>> {
        let result = result.map_err(|error| Arc::<str>::from(format!("{error:#}")));
        match &result {
            Ok(CollectionOutcome::Clean) => {
                let mut state = self.owner.progress();
                state.error = None;
                state.cleanup = false;
                state.recovered = true;
                if state.preparations.is_empty() {
                    state.keeper = None;
                }
            }
            // Pending IO/no-op is not a new clean proof and cannot clear an older failure.
            Ok(CollectionOutcome::Deferred) => {}
            Err(error) => self.owner.collection_failed(error.to_string()),
        }
        self.finished = true;
        result.map(|_| ())
    }
}

impl Drop for CollectionCompletion {
    fn drop(&mut self) {
        if !self.finished {
            self.owner.collection_failed(
                "Thread archive collection worker ended before recording its result".into(),
            );
        }
    }
}

impl ThreadResourceStore {
    pub(crate) fn new(history: HistoryStore, archive: ThreadArchive) -> Self {
        Self { history, archive }
    }
    pub(crate) fn reader(&self) -> FileResourceStore {
        self.archive.0.store.clone()
    }
    pub(crate) fn history(&self) -> &HistoryStore {
        &self.history
    }

    pub(crate) fn prepare_input(&self, input_id: String) -> InputPreparation {
        InputPreparation {
            owner: self.clone(),
            origin: ArchiveOrigin::Input {
                thread_id: self.history.thread_id().to_owned(),
                input_id,
                preparation_id: InputPreparationIdentity(Arc::new(())),
            },
        }
    }

    pub(crate) fn activate(&self) -> Result<()> {
        let mut state = self.progress();
        if state.sealed {
            ensure!(
                state.preparations.is_empty() && state.workers.is_empty() && !state.cleanup,
                "previous Thread archive owner has unfinished work"
            );
            state.sealed = false;
        }
        Ok(())
    }

    pub(crate) fn local_command_archive(
        &self,
    ) -> ThreadCommandArchive<super::LocalCommandOutputArchive> {
        ThreadCommandArchive {
            owner: self.clone(),
            inner: self.reader().local_command_archive(),
        }
    }

    pub(crate) fn remote_command_archive(
        &self,
        files: Arc<pl_tool::remote::RemoteWorkspaceFileBackend>,
        scratch: PathBuf,
    ) -> ThreadCommandArchive<super::RemoteCommandOutputArchive> {
        ThreadCommandArchive {
            owner: self.clone(),
            inner: self.reader().remote_command_archive(files, scratch),
        }
    }

    fn progress(&self) -> std::sync::MutexGuard<'_, Progress> {
        self.archive
            .0
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }

    /// Registers before polling any producer IO. The owned worker is never aborted by caller
    /// cancellation; completion and cleanup stay discoverable through this same history lifecycle.
    pub(crate) async fn perform<T, F, W>(
        &self,
        origin: ArchiveOrigin,
        reserved_bytes: u64,
        work: F,
    ) -> std::result::Result<(u64, T), ToolError>
    where
        T: Send + 'static,
        F: FnOnce(FileResourceStore) -> W + Send + 'static,
        W: Future<Output = std::result::Result<(T, Vec<ResourceReference>), ToolError>>
            + Send
            + 'static,
    {
        self.perform_inner(origin, reserved_bytes, false, work)
            .await
    }

    async fn perform_inner<T, F, W>(
        &self,
        origin: ArchiveOrigin,
        reserved_bytes: u64,
        command_repair: bool,
        work: F,
    ) -> std::result::Result<(u64, T), ToolError>
    where
        T: Send + 'static,
        F: FnOnce(FileResourceStore) -> W + Send + 'static,
        W: Future<Output = std::result::Result<(T, Vec<ResourceReference>), ToolError>>
            + Send
            + 'static,
    {
        let mut _admission = self.archive.0.maintenance.lock().await;
        self.reap().await.map_err(tool_failure)?;
        // A failed sweep must be retried before accepting more disk debt. Cold reads never enter here.
        let recover = {
            let state = self.progress();
            !state.recovered || state.error.is_some()
        };
        if recover {
            self.progress().cleanup = true;
            drop(_admission);
            self.collect().await.map_err(tool_failure)?;
            _admission = self.archive.0.maintenance.lock().await;
            if self.progress().error.is_some() {
                return Err(failure(
                    "Thread archive cleanup remains blocked; no new disk debt admitted",
                ));
            }
        }
        let metadata = format!("{origin:?}").len().saturating_add(512);
        let id = {
            let mut state = self.progress();
            // An unpolled collection can be dropped before taking maintenance. Recheck under the
            // registration lock so that failure and new disk debt have a single admission order.
            if !state.recovered || state.error.is_some() {
                return Err(failure(
                    "Thread archive cleanup remains blocked; no new disk debt admitted",
                ));
            }
            let retry = command_repair
                .then(|| {
                    state.preparations.iter().find_map(|(id, entry)| {
                        (entry.origin == origin
                            && entry.needs_repair
                            && !entry.io
                            && entry.sequence.is_none())
                        .then_some(*id)
                    })
                })
                .flatten();
            if state.sealed && retry.is_none() {
                return Err(failure("Thread archive is closed"));
            }
            let thread = match &origin {
                ArchiveOrigin::Tool(origin) => &origin.thread_id,
                ArchiveOrigin::Input { thread_id, .. } => thread_id,
            };
            if thread != self.history.thread_id() {
                return Err(failure("archive origin belongs to another Thread"));
            }
            if matches!(&origin, ArchiveOrigin::Tool(origin) if origin.turn_id.is_empty() || origin.call_id.is_empty())
                || matches!(&origin, ArchiveOrigin::Input { input_id, .. } if input_id.is_empty())
            {
                return Err(failure("archive origin is incomplete"));
            }
            let bytes: u64 = state
                .preparations
                .values()
                .map(|entry| entry.reserved_bytes)
                .sum();
            let resident: usize = state
                .preparations
                .values()
                .map(|entry| entry.metadata)
                .sum();
            if retry.is_none()
                && (state.preparations.len() >= MAX_PREPARATIONS
                    || resident.saturating_add(metadata) > MAX_METADATA
                    || bytes.saturating_add(reserved_bytes) > MAX_RETAINED_BYTES)
            {
                return Err(failure(
                    "Thread archive preparation budget is exhausted; save or retry existing work first",
                ));
            }
            let id = if let Some(id) = retry {
                id
            } else {
                state.next_id = state
                    .next_id
                    .checked_add(1)
                    .ok_or_else(|| failure("archive preparation identity exhausted"))?;
                state.next_id
            };
            state.keeper = Some(self.history.clone());
            state.cleanup = true;
            state.preparations.insert(
                id,
                Preparation {
                    origin,
                    reserved_bytes,
                    metadata,
                    io: true,
                    references: Vec::new(),
                    publication: None,
                    qualification: None,
                    needs_repair: false,
                    sequence: None,
                    input_submission: None,
                    input_accepted: None,
                },
            );
            id
        };
        let owner = self.clone();
        let (tx, rx) = tokio::sync::oneshot::channel();
        let worker = tokio::spawn(async move {
            let result = std::panic::AssertUnwindSafe(async { work(owner.reader()).await })
                .catch_unwind()
                .await
                .unwrap_or_else(|_| Err(failure("Thread archive producer panicked")));
            let result = match result {
                Ok((value, references)) => {
                    let validation = owner.record_finished(id, references).await;
                    validation.map(|()| value)
                }
                Err(error) => {
                    if let Some(entry) = owner.progress().preparations.get_mut(&id) {
                        entry.io = false;
                        entry.needs_repair = command_repair
                            && error
                                .source
                                .downcast_ref::<pl_core::thread::cold::OutputStorageFault>()
                                .is_some();
                    }
                    Err(error)
                }
            };
            let _ = tx.send(result);
            owner.archive.0.changed.notify_waiters();
        });
        self.progress()
            .workers
            .insert(id, ArchiveWorker::new(worker));
        drop(_admission);
        rx.await
            .map_err(|_| failure("Thread archive worker did not return its result"))?
            .map(|value| (id, value))
    }

    async fn record_finished(
        &self,
        id: u64,
        references: Vec<ResourceReference>,
    ) -> std::result::Result<(), ToolError> {
        // A concurrent durable acknowledgement may replace a preparation pin with its history
        // proof. Use that same maintenance boundary so neither side of the handoff can disappear
        // between checking canonical metadata and checking the still-pending preparations.
        let _maintenance = self.archive.0.maintenance.lock().await;
        if let Some(entry) = self.progress().preparations.get_mut(&id) {
            entry.io = false;
        }
        for reference in &references {
            reference.validate().map_err(ToolError::new)?;
            if let Some(canonical) = self
                .history
                .resource_reference(reference.id())
                .await
                .map_err(tool_failure)?
                && canonical.reference != *reference
            {
                return Err(failure(
                    "archived resource conflicts with its canonical metadata",
                ));
            }
        }
        let mut state = self.progress();
        for (index, reference) in references.iter().enumerate() {
            if state
                .preparations
                .values()
                .flat_map(|entry| &entry.references)
                .chain(&references[..index])
                .any(|previous| previous.id() == reference.id() && previous != reference)
            {
                return Err(failure(
                    "conflicting metadata for the same archived identity",
                ));
            }
        }
        let entry = state
            .preparations
            .get_mut(&id)
            .ok_or_else(|| failure("archive preparation disappeared"))?;
        entry.io = false;
        entry.needs_repair = false;
        let actual_bytes = references
            .iter()
            .map(ResourceReference::byte_len)
            .sum::<u64>();
        if actual_bytes > entry.reserved_bytes {
            return Err(failure(
                "archive producer exceeded its admitted original-byte reservation",
            ));
        }
        entry.reserved_bytes = actual_bytes;
        entry.references = references;
        Ok(())
    }

    pub(crate) async fn retain_bytes(
        &self,
        origin: ArchiveOrigin,
        bytes: Arc<[u8]>,
        media_type: String,
    ) -> std::result::Result<ResourceReference, ToolError> {
        self.perform(origin, bytes.len() as u64, move |store| async move {
            let reference = store
                .retain_bytes(bytes, &media_type)
                .await
                // Media producers preserve their received protocol result on failure. Unlike a
                // command capture they have no OutputRetryObligation, so do not manufacture an
                // unrepairable core output-storage latch. Physical cleanup stays owned here.
                .map_err(ToolError::new)?;
            Ok((reference.clone(), vec![reference]))
        })
        .await
        .map(|(_, reference)| reference)
    }

    pub(crate) fn prove_publication(
        &self,
        preparation: u64,
        receipt: ArtifactReceipt,
        eligibility: PublicationEligibility,
    ) -> std::result::Result<(), ToolError> {
        receipt.validate()?;
        let mut state = self.progress();
        let resident: usize = state
            .preparations
            .values()
            .map(|entry| entry.metadata)
            .sum();
        if resident.saturating_add(receipt.display_name.len()) > MAX_METADATA {
            return Err(failure(
                "publication metadata exceeds reliable preparation budget",
            ));
        }
        let entry = state
            .preparations
            .get_mut(&preparation)
            .ok_or_else(|| failure("publication preparation disappeared"))?;
        if entry.io
            || entry.origin != ArchiveOrigin::Tool(receipt.origin.clone())
            || entry.references.as_slice() != [receipt.resource.clone()]
            || entry
                .publication
                .as_ref()
                .is_some_and(|(previous, _)| previous != &receipt)
        {
            return Err(failure(
                "publication conflicts with its real producer preparation",
            ));
        }
        entry.metadata = entry.metadata.saturating_add(receipt.display_name.len());
        entry.publication = Some((receipt, eligibility));
        Ok(())
    }

    /// Called only by the existing unique projection. A receipt without this actual producer
    /// preparation has no authority, even if a custom/MCP tool copied its exact format and name.
    pub(crate) fn prepare_effect(
        &self,
        effect: &ThreadEffectBatch,
        snapshot: &pl_core::thread::ThreadSnapshot,
    ) -> Result<ArchiveHandoff> {
        let mut state = self.progress();
        let mut identities = Vec::new();
        let mut publications = Vec::new();
        for (id, entry) in &state.preparations {
            let delivery = match &entry.origin {
                ArchiveOrigin::Tool(origin) => effect
                    .deliveries
                    .iter()
                    .find(|delivery| delivery.call_id == origin.call_id),
                ArchiveOrigin::Input { .. } => None,
            };
            let consumed = delivery.is_some()
                || match &entry.origin {
                    ArchiveOrigin::Input { .. } => {
                        entry.input_accepted == Some(effect.sequence) && entry.accepted_in(effect)
                    }
                    ArchiveOrigin::Tool(origin) => effect
                        .delivery_repairs
                        .iter()
                        .any(|repair| repair.call_id == origin.call_id),
                };
            if !consumed {
                continue;
            }
            ensure!(
                !entry.io,
                "canonical result arrived before its archive IO terminal"
            );
            ensure!(
                entry
                    .sequence
                    .is_none_or(|sequence| sequence == effect.sequence),
                "archive preparation handed to two effects"
            );
            if let (Some(delivery), Some((receipt, _))) = (delivery, &entry.publication)
                && matches!(delivery.outcome, ToolOutcome::Succeeded)
                && delivery.tool_id == pl_tool::artifact::TOOL_PUBLISH_ARTIFACT
                && entry.qualification == Some((effect.sequence, true))
            {
                let saved = pl_tool::artifact::saved_artifact_receipt(delivery.output.payload())?
                    .ok_or_else(|| anyhow::anyhow!("trusted publication has no receipt"))?;
                ensure!(
                    &saved == receipt,
                    "publication receipt differs from producer proof"
                );
                let task = effect
                    .tasks
                    .iter()
                    .find(|task| task.call_id == receipt.origin.call_id)
                    .or_else(|| {
                        snapshot
                            .tasks
                            .values()
                            .find(|task| task.call_id == receipt.origin.call_id)
                    });
                ensure!(
                    task.is_some_and(|task| task.turn_id == receipt.origin.turn_id
                        && task.tool_id == pl_tool::artifact::TOOL_PUBLISH_ARTIFACT),
                    "publication origin does not match its canonical task"
                );
                ensure!(
                    delivery
                        .delivered_context
                        .iter()
                        .filter_map(|part| match part {
                            pl_core::context::ContextContent::Resource { reference } =>
                                Some(reference),
                            _ => None,
                        })
                        .eq(std::iter::once(&receipt.resource)),
                    "publication delivered reference differs from producer proof"
                );
                if let Some(previous) = publications.iter().find(|previous: &&ArtifactReceipt| {
                    previous.publication_id == receipt.publication_id
                }) {
                    ensure!(
                        previous == receipt,
                        "one publication identity has conflicting receipts"
                    );
                } else {
                    publications.push(receipt.clone());
                }
            }
            identities.push(*id);
        }
        // Validation is transactional: a later invalid proof must not partially hand earlier
        // preparations over to a batch the projection could not produce.
        for id in &identities {
            if let Some(entry) = state.preparations.get_mut(id) {
                entry.sequence = Some(effect.sequence);
            }
        }
        Ok(ArchiveHandoff {
            owner: self.clone(),
            sequence: effect.sequence,
            identities,
            publications,
        })
    }

    /// Freeze the host's file-execution eligibility when the ORIGINAL reliable queue admits the
    /// canonical result. A later Turn cancellation/close cannot retract an already admitted intent;
    /// a revoked binding before this point cannot grant a late one. This is only transient producer
    /// proof, not a second projection or commit queue: the unique projection still checks the exact
    /// receipt, origin, canonical outcome and delivered reference before creating any public item.
    pub(crate) fn admitted(&self, effect: &ThreadEffectBatch) {
        let mut state = self.progress();
        for entry in state.preparations.values_mut() {
            if entry.accepted_in(effect) {
                entry.input_accepted.get_or_insert(effect.sequence);
            }
            let Some((receipt, eligibility)) = &entry.publication else {
                continue;
            };
            if entry.qualification.is_none()
                && effect.deliveries.iter().any(|delivery| {
                    delivery.call_id == receipt.origin.call_id
                        && delivery.tool_id == pl_tool::artifact::TOOL_PUBLISH_ARTIFACT
                        && matches!(delivery.outcome, ToolOutcome::Succeeded)
                })
            {
                entry.qualification = Some((effect.sequence, (eligibility.0)()));
            }
        }
    }

    async fn reap(&self) -> Result<()> {
        let finished = {
            let state = self.progress();
            state
                .workers
                .iter()
                .filter(|(_, worker)| worker.state.is_finished())
                .map(|(id, worker)| (*id, worker.joined.clone()))
                .collect::<Vec<_>>()
        };
        for (id, worker) in finished {
            worker
                .await
                .map_err(|error| anyhow::anyhow!("archive worker failed: {error}"))?;
            self.progress().workers.remove(&id);
        }
        Ok(())
    }

    /// Keep the GC task/future in the same owner before starting any physical work. A cancelled
    /// waiter cannot release producer exclusion while a blocking unlink is still running.
    async fn collect(&self) -> Result<()> {
        self.collection(true).await
    }

    fn collection_failed(&self, error: String) {
        let mut state = self.progress();
        state.error = Some(error);
        state.cleanup = true;
        state.recovered = false;
        state.keeper = Some(self.history.clone());
    }

    async fn collection(&self, start: bool) -> Result<()> {
        let mut pending = self.archive.0.collection.lock().await;
        if pending.is_none() {
            let mut state = self.progress();
            if !start || !state.cleanup {
                return Ok(());
            }
            state.keeper = Some(self.history.clone());
            drop(state);
            let owner = self.clone();
            let completion = CollectionCompletion {
                owner: self.clone(),
                finished: false,
            };
            let worker = tokio::spawn(async move {
                let _exclusive = owner.archive.0.maintenance.lock().await;
                // Rebind AFTER the lock: unwind/cancellation must record failure before releasing
                // producer exclusion. Before acquiring it the captured guard still owns failure.
                let completion = completion;
                let result = std::panic::AssertUnwindSafe(owner.collect_exclusive())
                    .catch_unwind()
                    .await
                    .unwrap_or_else(|_| {
                        Err(anyhow::anyhow!("Thread archive collection worker panicked"))
                    });
                completion.finish(result)
            });
            *pending = Some(
                async move {
                    worker.await.unwrap_or_else(|error| {
                        Err(Arc::<str>::from(format!(
                            "archive collection worker failed: {error}"
                        )))
                    })
                }
                .boxed()
                .shared(),
            );
        }
        let result = pending
            .as_ref()
            .expect("collection installed above")
            .clone()
            .await;
        *pending = None;
        // Only the worker publishes progress, while still holding maintenance. A late waiter
        // observes its result without overwriting a newer recovery/admission state.
        result.map_err(|error| anyhow::anyhow!("{error}"))
    }

    /// The OWNED task holds maintenance, also used by producer registration. All physical IO has
    /// terminated before it releases that guard, including when the original caller was cancelled.
    async fn collect_exclusive(&self) -> Result<CollectionOutcome> {
        self.retire_durable_inputs().await?;
        let pins = {
            let state = self.progress();
            if !state.cleanup {
                return Ok(CollectionOutcome::Deferred);
            }
            if state.preparations.values().any(|entry| entry.io) {
                return Ok(CollectionOutcome::Deferred);
            }
            state
                .preparations
                .values()
                .flat_map(|entry| {
                    entry
                        .references
                        .iter()
                        .map(|reference| reference.id().to_owned())
                })
                .collect::<std::collections::BTreeSet<_>>()
        };
        let mut cursor = None;
        loop {
            let batch = self.reader().owned_batch(cursor, 128).await?;
            let mut remove = Vec::new();
            for object in batch.objects {
                if let Some(id) = object.resource_id()
                    && (pins.contains(id) || self.history.resource_reference(id).await?.is_some())
                {
                    continue;
                }
                remove.push(object);
            }
            self.reader().remove_owned_batch(remove).await?;
            cursor = batch.continuation;
            if cursor.is_none() {
                break;
            }
        }
        Ok(CollectionOutcome::Clean)
    }

    /// Same-payload duplicate receipts need not emit another Accepted effect. End their redundant
    /// preparation only once the original ordered writer has saved its fence and exact references.
    /// This reads current proof; it never waits for the input being submitted to become saved.
    async fn retire_durable_inputs(&self) -> Result<()> {
        let candidates = self
            .progress()
            .preparations
            .iter()
            .filter_map(|(id, entry)| {
                entry
                    .input_accepted
                    .filter(|_| !entry.io)
                    .map(|sequence| (*id, sequence, entry.references.clone()))
            })
            .collect::<Vec<_>>();
        if candidates.is_empty() {
            return Ok(());
        }
        let durable = self.history.watermark().await?;
        let mut retired = Vec::new();
        for (id, sequence, references) in candidates {
            if sequence > durable {
                continue;
            }
            for reference in references {
                ensure!(
                    self.history
                        .resource_reference(reference.id())
                        .await?
                        .is_some_and(|fact| fact.reference == reference),
                    "durable accepted input has no matching canonical resource proof"
                );
            }
            retired.push((id, sequence));
        }
        let mut state = self.progress();
        for (id, sequence) in retired {
            if state
                .preparations
                .get(&id)
                .is_some_and(|entry| !entry.io && entry.input_accepted == Some(sequence))
            {
                state.preparations.remove(&id);
            }
        }
        Ok(())
    }

    /// Pre-close only seals new IO and joins real workers. Canonical results can still be queued
    /// by core after this stage, so it must not drop their unhanded-off preparation pins or sweep.
    pub(crate) async fn drain(&self) -> Result<()> {
        self.progress().sealed = true;
        loop {
            let changed = self.archive.0.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            if !self.progress().preparations.values().any(|entry| entry.io) {
                break;
            }
            changed.await;
        }
        let workers = self
            .progress()
            .workers
            .iter()
            .map(|(id, worker)| (*id, worker.joined.clone()))
            .collect::<Vec<_>>();
        for (id, worker) in workers {
            worker
                .await
                .map_err(|error| anyhow::anyhow!("archive worker failed: {error}"))?;
            self.progress().workers.remove(&id);
        }
        let retry_cleanup = self.progress().error.is_some();
        self.collection(retry_cleanup).await?;
        Ok(())
    }

    /// The post-core-close, post-observation barrier alone can prove that an unsubmitted operation
    /// will never produce another canonical result. Writer-owned entries still require durable ACK.
    pub(crate) async fn close(&self) -> Result<()> {
        self.drain().await?;
        let _maintenance = self.archive.0.maintenance.lock().await;
        // Core has closed all producers. Unsent preparations have no effect/writer owner, but a
        // submitted/unknown input is NOT proof of non-admission, even if projection failed. Keep
        // those and handed-off entries until their exact canonical/durable proof is available.
        self.progress().preparations.retain(|_, entry| {
            entry.sequence.is_some() || entry.needs_repair || entry.input_submission.is_some()
        });
        drop(_maintenance);
        self.collect().await?;
        ensure!(
            self.progress().preparations.is_empty(),
            "Thread archive still awaits reliable history acknowledgement"
        );
        Ok(())
    }

    fn abandon_input(&self, origin: ArchiveOrigin) {
        let mut state = self.progress();
        if state.sealed
            || !state.preparations.values().any(|entry| {
                entry.origin == origin
                    && entry.sequence.is_none()
                    && entry.input_submission.is_none()
                    && entry.input_accepted.is_none()
            })
        {
            return;
        }
        let Some(id) = state.next_id.checked_add(1) else {
            state.error = Some("archive cleanup identity exhausted".into());
            return;
        };
        state.next_id = id;
        let owner = self.clone();
        let worker = tokio::spawn(async move {
            loop {
                let changed = owner.archive.0.changed.notified();
                tokio::pin!(changed);
                changed.as_mut().enable();
                if !owner
                    .progress()
                    .preparations
                    .values()
                    .any(|entry| entry.origin == origin && entry.io)
                {
                    // Registration and this final recheck share the same boundary. Do not remove
                    // an IO preparation that became live after the notification check above.
                    let _maintenance = owner.archive.0.maintenance.lock().await;
                    if owner
                        .progress()
                        .preparations
                        .values()
                        .any(|entry| entry.origin == origin && entry.io)
                    {
                        continue;
                    }
                    owner.progress().preparations.retain(|_, entry| {
                        entry.origin != origin
                            || entry.sequence.is_some()
                            || entry.input_submission.is_some()
                            || entry.input_accepted.is_some()
                    });
                    break;
                }
                changed.await;
            }
            if let Err(error) = owner.collect().await {
                tracing::warn!(%error, "unsubmitted input resource cleanup remains owed");
            }
        });
        state.workers.insert(id, ArchiveWorker::new(worker));
    }
}

/// Input preparation owns unsubmitted copies. Once the core command is sent, uncertainty keeps pins
/// until its canonical accepted/durable proof; a cancelled waiter never guesses rejection.
pub(crate) struct InputPreparation {
    owner: ThreadResourceStore,
    // A failed/rejected caller owns only this attempt, never a later retry of the same input ID.
    origin: ArchiveOrigin,
}
impl InputPreparation {
    pub(crate) fn origin(&self) -> ArchiveOrigin {
        self.origin.clone()
    }
    pub(crate) fn submitting(&self, input: &ThreadInput) -> Result<()> {
        ensure!(
            matches!(&self.origin, ArchiveOrigin::Input { input_id, .. } if input_id == &input.id),
            "input preparation does not match its real submission"
        );
        let expected = crate::studio::context_resources(&input.context)?
            .into_iter()
            .map(|fact| fact.reference)
            .collect::<Vec<_>>();
        let metadata = serde_json::to_vec(input)?.len();
        let mut state = self.owner.progress();
        let mut ids = Vec::new();
        let mut prepared = Vec::new();
        for (id, entry) in &state.preparations {
            if entry.origin != self.origin {
                continue;
            }
            ensure!(
                !entry.io,
                "input submission precedes its archive IO terminal"
            );
            ensure!(
                entry
                    .input_submission
                    .as_deref()
                    .is_none_or(|saved| saved == input),
                "input preparation already froze a different submission"
            );
            ids.push(*id);
            prepared.extend(entry.references.iter().cloned());
        }
        ensure!(
            prepared == expected,
            "input submission resources differ from its prepared originals"
        );
        let Some(first) = ids.first() else {
            return Ok(());
        };
        if state.preparations[first].input_submission.is_some() {
            return Ok(());
        }
        let resident: usize = state
            .preparations
            .values()
            .map(|entry| entry.metadata)
            .sum();
        ensure!(
            resident.saturating_add(metadata) <= MAX_METADATA,
            "input submission exceeds reliable preparation metadata budget"
        );
        state
            .preparations
            .get_mut(first)
            .expect("checked above")
            .metadata += metadata;
        let input = Arc::new(input.clone());
        for id in ids {
            state
                .preparations
                .get_mut(&id)
                .expect("checked above")
                .input_submission = Some(input.clone());
        }
        Ok(())
    }

    /// Confirms receipt integrity only. Cleanup errors are not input-admission errors.
    pub(crate) fn accepted(&self, receipt: &InputRecord) -> Result<()> {
        let mut state = self.owner.progress();
        for entry in state
            .preparations
            .values_mut()
            .filter(|entry| entry.origin == self.origin)
        {
            ensure!(
                entry.input_submission.as_deref() == Some(&receipt.input),
                "input receipt differs from its real submission"
            );
            entry
                .input_accepted
                .get_or_insert(receipt.accepted_sequence);
        }
        Ok(())
    }

    /// Waits on owned collection without letting its outcome replace a confirmed core receipt.
    /// Its worker records failure in the SAME owner before releasing maintenance, even without a waiter;
    /// the original writer handoff, producer admission and close continue to observe/retry it.
    /// This unit result is not a claim that the archive is clean or history is saved.
    pub(crate) async fn collect_after_acceptance(&self) {
        let retained = self
            .owner
            .progress()
            .preparations
            .values()
            .any(|entry| entry.origin == self.origin && entry.input_accepted.is_some());
        // A duplicate can arrive after the original writer ACK. Query it now, without waiting for
        // a new effect that core correctly will not emit for an identical submission.
        if retained {
            let _ = self.owner.collect().await;
        }
    }

    pub(crate) fn admission_failed(&self, error: &pl_core::thread::ThreadError) {
        use pl_core::thread::ThreadError;
        // These errors originate before stage_input in both owner admission paths. Closed is NOT
        // here: the public handle also maps a lost reply channel to Closed after possible acceptance.
        if !matches!(
            error,
            ThreadError::InvalidIdentity
                | ThreadError::StoragePressure
                | ThreadError::Storage(_)
                | ThreadError::PendingInteraction
                | ThreadError::RevisionExhausted
        ) {
            return;
        }
        let mut state = self.owner.progress();
        for entry in state
            .preparations
            .values_mut()
            .filter(|entry| entry.origin == self.origin)
        {
            if entry.sequence.is_none() && entry.input_accepted.is_none() {
                entry.input_submission = None;
            }
        }
    }
}
impl Drop for InputPreparation {
    fn drop(&mut self) {
        self.owner.abandon_input(self.origin());
    }
}

#[derive(Debug)]
pub(crate) struct ThreadCommandArchive<A> {
    owner: ThreadResourceStore,
    inner: A,
}
impl<A: pl_tool::exec::CommandOutputArchive + Clone> pl_tool::exec::CommandOutputArchive
    for ThreadCommandArchive<A>
{
    async fn retain(
        &self,
        origin: &ToolResourceOrigin,
        snapshot: &pl_tool::command::CommandOutputSnapshot,
    ) -> std::result::Result<ResourceReference, ToolError> {
        let archive = self.inner.clone();
        let producer = origin.clone();
        let snapshot = snapshot.clone();
        self.owner
            .perform_inner(
                ArchiveOrigin::Tool(origin.clone()),
                super::MAX_COMMAND_ARCHIVE_BYTES,
                true,
                move |_| async move {
                    let reference = archive.retain(&producer, &snapshot).await?;
                    Ok((reference.clone(), vec![reference]))
                },
            )
            .await
            .map(|(_, reference)| reference)
    }
}

impl ResourceReader for ThreadResourceStore {
    async fn read(
        &self,
        reference: ResourceReference,
        cancellation: CancellationToken,
    ) -> std::result::Result<Arc<[u8]>, pl_core::context::ResourceReadError> {
        self.reader().read(reference, cancellation).await
    }
}

/// Transferred with the SAME prepared content batch and retained by the original reliable queue.
#[derive(Debug)]
pub(crate) struct ArchiveHandoff {
    owner: ThreadResourceStore,
    sequence: u64,
    identities: Vec<u64>,
    pub(crate) publications: Vec<ArtifactReceipt>,
}
impl ArchiveHandoff {
    pub(crate) async fn durable(&self) -> Result<()> {
        let _maintenance = self.owner.archive.0.maintenance.lock().await;
        {
            let mut state = self.owner.progress();
            for id in &self.identities {
                if let Some(entry) = state.preparations.get_mut(id) {
                    ensure!(
                        entry.sequence == Some(self.sequence),
                        "archive handoff sequence changed"
                    );
                    if entry.needs_repair {
                        entry.sequence = None;
                        continue;
                    }
                }
                state.preparations.remove(id);
            }
        }
        self.owner.reap().await?;
        drop(_maintenance);
        self.owner.collect().await
    }
}

fn failure(message: &str) -> ToolError {
    tool_failure(anyhow::anyhow!(message.to_owned()))
}
fn tool_failure(error: anyhow::Error) -> ToolError {
    ToolError::new(std::io::Error::other(format!("{error:#}")))
}
