//! Only weak historical locators are retained. Live feeds, two unACKed frames and reads own pins.
use std::collections::BTreeMap;
use std::sync::{
    Arc, Mutex, Weak,
    atomic::{AtomicBool, Ordering},
};

use pl_protocol::ObservedResource;
use pl_protocol::products::identity::{
    ProductCollectionRef, ProductEntityRef, ProductReadOrigin, ProductResource,
    ProductSourceStatusRef,
};
use pl_protocol::studio::{StudioError, StudioErrorCode};

use super::ThreadDirectoryScope;
use super::capture::CapturedDirectory;
use super::material::DirectoryMaterial;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) enum DirectoryBinding {
    Projects,
    Agents,
    Threads(ThreadDirectoryScope),
}

impl DirectoryBinding {
    pub(super) fn resource(&self) -> ProductResource {
        match self {
            Self::Projects => ProductResource::ProjectDirectory,
            Self::Agents => ProductResource::AgentDirectory,
            Self::Threads(_) => ProductResource::ThreadDirectory,
        }
    }
    pub(super) fn budget(&self) -> &'static str {
        match self {
            Self::Projects => "workspace.projectDirectory",
            Self::Agents => "workspace.agentDirectory",
            Self::Threads(ThreadDirectoryScope::Query { .. }) => "workspace.threadDirectory",
            Self::Threads(ThreadDirectoryScope::Thread { .. }) => "workspace.threadMetadata",
        }
    }
}

#[derive(Clone, PartialEq)]
pub(super) enum DirectoryRows {
    Projects(Vec<crate::ProjectRecord>),
    Agents(Vec<crate::StudioAgentDirectoryEntry>),
    Threads(Vec<pl_protocol::Thread>),
}

impl DirectoryRows {
    pub(super) fn len(&self) -> usize {
        match self {
            Self::Projects(rows) => rows.len(),
            Self::Agents(rows) => rows.len(),
            Self::Threads(rows) => rows.len(),
        }
    }
    pub(super) fn id(&self, index: usize) -> &str {
        match self {
            Self::Projects(rows) => &rows[index].id,
            Self::Agents(rows) => &rows[index].id,
            Self::Threads(rows) => &rows[index].id,
        }
    }
    fn same(&self, index: usize, other: &Self, other_index: usize) -> bool {
        match (self, other) {
            (Self::Projects(left), Self::Projects(right)) => left[index] == right[other_index],
            (Self::Agents(left), Self::Agents(right)) => left[index] == right[other_index],
            (Self::Threads(left), Self::Threads(right)) => left[index] == right[other_index],
            _ => false,
        }
    }
}

pub(super) struct WorkspaceStatus {
    pub(super) reference: ProductSourceStatusRef,
    pub(super) binding: DirectoryBinding,
    pub(super) metadata: ObservedResource<()>,
}

pub(super) struct DirectorySnapshot {
    pub(super) entry: u64,
    pub(super) revision: u64,
    pub(super) binding: DirectoryBinding,
    pub(super) collection: ProductCollectionRef,
    pub(super) entities: Vec<ProductEntityRef>,
    pub(super) capture: CapturedDirectory,
    pub(super) status: Arc<WorkspaceStatus>,
    pub(super) material: DirectoryMaterial,
}

struct DirectoryState {
    current: Option<Arc<DirectorySnapshot>>,
}

pub(super) struct DirectoryOwner {
    pub(super) binding: DirectoryBinding,
    entry: u64,
    collection_entry: u64,
    status_entry: u64,
    /// Serializes an entire original keyset capture/extension; no synchronous guard crosses await.
    pub(super) capture_gate: tokio::sync::Mutex<()>,
    state: Mutex<DirectoryState>,
    updates: tokio::sync::watch::Sender<()>,
}

impl DirectoryOwner {
    pub(super) fn current(&self) -> Option<Arc<DirectorySnapshot>> {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .current
            .clone()
    }
    pub(super) fn subscribe(&self) -> tokio::sync::watch::Receiver<()> {
        self.updates.subscribe()
    }

    /// Source admission precedes slot admission everywhere; send callbacks never re-enter either.
    pub(super) fn publish(
        &self,
        source: &WorkspaceProductSource,
        capture: CapturedDirectory,
    ) -> Result<Arc<DirectorySnapshot>, StudioError> {
        let mut source_state = source
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        source.ensure_open()?;
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let previous = state.current.clone();
        if let Some(previous) = &previous
            && previous.capture == capture
        {
            return Ok(previous.clone());
        }
        // SDK last-known projections compare stamps across reconnects with this same origin.
        // A new query connection must not restart that projection clock at one.
        let revision = super::next(source_state.projection_revision)?;
        let old_positions: BTreeMap<_, _> = previous
            .as_ref()
            .map(|previous| {
                (0..previous.capture.rows.len())
                    .map(|index| (previous.capture.rows.id(index), index))
                    .collect()
            })
            .unwrap_or_default();
        let mut entities = Vec::with_capacity(capture.rows.len());
        for index in 0..capture.rows.len() {
            let old = previous.as_ref().and_then(|previous| {
                old_positions
                    .get(capture.rows.id(index))
                    .map(|old| (previous, *old))
            });
            let reference = if let Some((previous, old)) = old {
                let old_ref = previous.entities[old];
                if capture.rows.same(index, &previous.capture.rows, old) {
                    old_ref
                } else {
                    ProductEntityRef {
                        entry: old_ref.entry,
                        revision: super::next(old_ref.revision)?,
                    }
                }
            } else {
                source_state.next_entry = super::next(source_state.next_entry)?;
                ProductEntityRef {
                    entry: source_state.next_entry,
                    revision: 1,
                }
            };
            entities.push(reference);
        }
        let collection_revision = match &previous {
            Some(previous) if previous.entities == entities => previous.collection.revision,
            Some(previous) => super::next(previous.collection.revision)?,
            None => 1,
        };
        let collection = ProductCollectionRef {
            entry: self.collection_entry,
            revision: collection_revision,
            total: super::super::read_budget::count(entities.len())?,
        };
        let status = match &previous {
            Some(previous) if previous.status.metadata == capture.metadata => {
                previous.status.clone()
            }
            _ => Arc::new(WorkspaceStatus {
                reference: ProductSourceStatusRef {
                    entry: self.status_entry,
                    revision: super::next(
                        previous
                            .as_ref()
                            .map_or(0, |value| value.status.reference.revision),
                    )?,
                },
                binding: self.binding.clone(),
                metadata: capture.metadata.clone(),
            }),
        };
        let snapshot = Arc::new(DirectorySnapshot {
            entry: self.entry,
            revision,
            binding: self.binding.clone(),
            collection,
            entities,
            capture,
            status,
            material: DirectoryMaterial::default(),
        });
        source_state.projection_revision = revision;
        state.current = Some(snapshot.clone());
        drop(state);
        self.updates.send_replace(());
        Ok(snapshot)
    }
}

#[derive(Default)]
struct SourceState {
    next_entry: u64,
    projection_revision: u64,
    directories: Vec<Weak<DirectoryOwner>>,
    values: BTreeMap<(u64, u64), Weak<DirectorySnapshot>>,
    statuses: BTreeMap<(u64, u64), Weak<WorkspaceStatus>>,
}

/// Runtime-owned publication/pin index, not a writable Project/Agent/Thread directory.
pub(crate) struct WorkspaceProductSource {
    origin: ProductReadOrigin,
    sealed: AtomicBool,
    state: Mutex<SourceState>,
    stopped: tokio_util::sync::CancellationToken,
}

impl WorkspaceProductSource {
    pub(crate) fn new(origin: ProductReadOrigin) -> Arc<Self> {
        Arc::new(Self {
            origin,
            sealed: AtomicBool::new(false),
            state: Mutex::new(SourceState::default()),
            stopped: tokio_util::sync::CancellationToken::new(),
        })
    }
    pub(super) fn origin(&self) -> ProductReadOrigin {
        self.origin.clone()
    }
    pub(super) fn stopped(&self) -> tokio_util::sync::CancellationToken {
        self.stopped.clone()
    }
    pub(super) fn ensure_open(&self) -> Result<(), StudioError> {
        if self.sealed.load(Ordering::Acquire) {
            Err(super::cancelled())
        } else {
            Ok(())
        }
    }
    pub(super) fn directory(
        &self,
        binding: DirectoryBinding,
    ) -> Result<Arc<DirectoryOwner>, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.ensure_open()?;
        state
            .directories
            .retain(|directory| directory.strong_count() != 0);
        // Each feed owns its original frontier; equal queries must not extend each other.
        let entry = super::next(state.next_entry)?;
        let collection_entry = super::next(entry)?;
        let status_entry = super::next(collection_entry)?;
        state.next_entry = status_entry;
        let (updates, _) = tokio::sync::watch::channel(());
        let directory = Arc::new(DirectoryOwner {
            binding,
            entry,
            collection_entry,
            status_entry,
            capture_gate: tokio::sync::Mutex::new(()),
            state: Mutex::new(DirectoryState { current: None }),
            updates,
        });
        state.directories.push(Arc::downgrade(&directory));
        Ok(directory)
    }
    pub(super) fn pin(
        &self,
        origin: &ProductReadOrigin,
        entry: u64,
        revision: u64,
        resource: ProductResource,
    ) -> Result<Arc<DirectorySnapshot>, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check_origin(origin)?;
        state.values.retain(|_, value| value.strong_count() != 0);
        let value = state
            .values
            .get(&(entry, revision))
            .and_then(Weak::upgrade)
            .ok_or_else(expired)?;
        if value.binding.resource() != resource {
            return Err(super::wrong_field());
        }
        Ok(value)
    }
    pub(super) fn pin_status(
        &self,
        origin: &ProductReadOrigin,
        reference: ProductSourceStatusRef,
    ) -> Result<Arc<WorkspaceStatus>, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check_origin(origin)?;
        state.statuses.retain(|_, value| value.strong_count() != 0);
        state
            .statuses
            .get(&(reference.entry, reference.revision))
            .and_then(Weak::upgrade)
            .ok_or_else(expired)
    }
    fn check_origin(&self, origin: &ProductReadOrigin) -> Result<(), StudioError> {
        self.ensure_open()?;
        if origin != &self.origin {
            return Err(StudioError::invalid_argument(
                "Workspace read origin belongs to another owner",
            ));
        }
        Ok(())
    }
    /// The callback is synchronous, bounded and non-reentrant. Failed sends expose nothing.
    pub(super) fn send_exposing(
        &self,
        snapshot: &Arc<DirectorySnapshot>,
        send: impl FnOnce() -> Result<bool, StudioError>,
    ) -> Result<bool, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.ensure_open()?;
        let sent = send()?;
        if sent {
            expose(&mut state, snapshot);
        }
        Ok(sent)
    }
    /// extendWindow returns its own issued query target, never a command receipt or fake ACK.
    pub(super) fn expose_extension(
        &self,
        snapshot: &Arc<DirectorySnapshot>,
    ) -> Result<(), StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.ensure_open()?;
        expose(&mut state, snapshot);
        Ok(())
    }
    pub(crate) fn seal(&self) {
        let _state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.sealed.store(true, Ordering::Release);
        self.stopped.cancel();
    }
    /// Called only after the original transport and read owners have joined; retry uses this owner.
    pub(crate) fn finish_close(&self) {
        self.seal();
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.directories.clear();
        state.values.clear();
        state.statuses.clear();
    }
}

fn expose(state: &mut SourceState, snapshot: &Arc<DirectorySnapshot>) {
    state.values.retain(|_, value| value.strong_count() != 0);
    state.statuses.retain(|_, value| value.strong_count() != 0);
    if snapshot.capture.metadata.value().is_some() {
        state.values.insert(
            (snapshot.entry, snapshot.revision),
            Arc::downgrade(snapshot),
        );
    }
    state.statuses.insert(
        (
            snapshot.status.reference.entry,
            snapshot.status.reference.revision,
        ),
        Arc::downgrade(&snapshot.status),
    );
}
fn expired() -> StudioError {
    StudioError::new(
        StudioErrorCode::Superseded,
        "The Workspace reference was not exposed or its original material has expired",
        false,
    )
}
