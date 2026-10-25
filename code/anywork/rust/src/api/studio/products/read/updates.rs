//! Opaque native reads. Transport admission and cleanup stay in the original bridge registry.
use super::super::identity::*;
use super::super::references::*;
use super::super::source::*;
use super::owner::{ModelsRead, ModelsReadHandle, open_read};
use crate::api::studio::observation::{BridgeReadText, BridgeTextChunk};
use crate::api::studio::types::BridgeFeedCloseOutcome;
use crate::api::studio::types::{BridgeError, BridgeFeedCloseReport};
use pl_protocol::products::read::updates as protocol;
use pl_studio_runtime::updates::{
    StudioUpdateDetailsRead, StudioUpdateErrorRead, StudioUpdateOperationRead,
    StudioUpdateSummaryRead, StudioUpdatesRead,
};
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeUpdateTaskIdentity {
    pub runtime_epoch: String,
    pub task_id: String,
    pub operation_id: String,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeUpdateTaskCloseReport {
    pub identity: BridgeUpdateTaskIdentity,
    pub outcome: BridgeFeedCloseOutcome,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeUpdateSummaryRead {
    pub version: BridgeReadText,
    pub published_at: i64,
    pub notes_url: BridgeReadText,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeUpdateAssetRead {
    pub url: BridgeReadText,
    pub size: u64,
    pub sha256: BridgeReadText,
    pub signature: BridgeReadText,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeUpdateDetailsRead {
    pub summary: BridgeUpdateSummaryRead,
    pub installer: BridgeUpdateAssetRead,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeUpdateOperationReadHeader {
    pub operation_id: BridgeReadText,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeUpdatesReadHeader {
    Disabled {
        revision: u64,
        updated_at: i64,
    },
    Idle {
        revision: u64,
        updated_at: i64,
    },
    Checking {
        revision: u64,
        operation_id: BridgeReadText,
        started_at: i64,
    },
    UpToDate {
        revision: u64,
        checked_at: i64,
    },
    Available {
        revision: u64,
        checked_at: i64,
        update: BridgeUpdateDetailsRead,
    },
    Downloading {
        revision: u64,
        updated_at: i64,
        update: BridgeUpdateDetailsRead,
        downloaded: u64,
        total: u64,
    },
    Verifying {
        revision: u64,
        updated_at: i64,
        update: BridgeUpdateDetailsRead,
        downloaded: u64,
        total: u64,
    },
    Ready {
        revision: u64,
        ready_at: i64,
        update: BridgeUpdateDetailsRead,
    },
    InstallerLaunched {
        revision: u64,
        launched_at: i64,
        update: BridgeUpdateDetailsRead,
    },
    CheckFailed {
        revision: u64,
        failed_at: i64,
        error: BridgeSourceStateErrorRead,
    },
    InstallFailed {
        revision: u64,
        failed_at: i64,
        update: BridgeUpdateDetailsRead,
        error: BridgeSourceStateErrorRead,
    },
}
impl From<protocol::UpdateTaskIdentity> for BridgeUpdateTaskIdentity {
    fn from(value: protocol::UpdateTaskIdentity) -> Self {
        Self {
            runtime_epoch: value.runtime_epoch,
            task_id: value.task_id,
            operation_id: value.operation_id,
        }
    }
}

impl From<protocol::UpdateTaskCloseReport> for BridgeUpdateTaskCloseReport {
    fn from(value: protocol::UpdateTaskCloseReport) -> Self {
        Self {
            identity: value.identity.into(),
            outcome: match value.outcome {
                pl_protocol::studio::FeedCloseOutcome::Clean => BridgeFeedCloseOutcome::Clean,
                pl_protocol::studio::FeedCloseOutcome::Unresolved { issues } => {
                    BridgeFeedCloseOutcome::Unresolved {
                        issues: issues.into_iter().map(Into::into).collect(),
                    }
                }
            },
        }
    }
}

impl From<protocol::UpdateSummaryRead> for BridgeUpdateSummaryRead {
    fn from(value: protocol::UpdateSummaryRead) -> Self {
        Self {
            version: value.version.into(),
            published_at: value.published_at,
            notes_url: value.notes_url.into(),
        }
    }
}

impl From<protocol::UpdateAssetRead> for BridgeUpdateAssetRead {
    fn from(value: protocol::UpdateAssetRead) -> Self {
        Self {
            url: value.url.into(),
            size: value.size,
            sha256: value.sha256.into(),
            signature: value.signature.into(),
        }
    }
}

impl From<protocol::UpdateDetailsRead> for BridgeUpdateDetailsRead {
    fn from(value: protocol::UpdateDetailsRead) -> Self {
        Self {
            summary: value.summary.into(),
            installer: value.installer.into(),
        }
    }
}

impl From<protocol::UpdateOperationReadHeader> for BridgeUpdateOperationReadHeader {
    fn from(value: protocol::UpdateOperationReadHeader) -> Self {
        Self {
            operation_id: value.operation_id.into(),
        }
    }
}

impl From<protocol::UpdatesReadHeader> for BridgeUpdatesReadHeader {
    fn from(value: protocol::UpdatesReadHeader) -> Self {
        match value {
            protocol::UpdatesReadHeader::Disabled {
                revision,
                updated_at,
            } => Self::Disabled {
                revision,
                updated_at,
            },
            protocol::UpdatesReadHeader::Idle {
                revision,
                updated_at,
            } => Self::Idle {
                revision,
                updated_at,
            },
            protocol::UpdatesReadHeader::Checking {
                revision,
                operation_id,
                started_at,
            } => Self::Checking {
                revision,
                operation_id: operation_id.into(),
                started_at,
            },
            protocol::UpdatesReadHeader::UpToDate {
                revision,
                checked_at,
            } => Self::UpToDate {
                revision,
                checked_at,
            },
            protocol::UpdatesReadHeader::Available {
                revision,
                checked_at,
                update,
            } => Self::Available {
                revision,
                checked_at,
                update: update.into(),
            },
            protocol::UpdatesReadHeader::Downloading {
                revision,
                updated_at,
                update,
                downloaded,
                total,
            } => Self::Downloading {
                revision,
                updated_at,
                update: update.into(),
                downloaded,
                total,
            },
            protocol::UpdatesReadHeader::Verifying {
                revision,
                updated_at,
                update,
                downloaded,
                total,
            } => Self::Verifying {
                revision,
                updated_at,
                update: update.into(),
                downloaded,
                total,
            },
            protocol::UpdatesReadHeader::Ready {
                revision,
                ready_at,
                update,
            } => Self::Ready {
                revision,
                ready_at,
                update: update.into(),
            },
            protocol::UpdatesReadHeader::InstallerLaunched {
                revision,
                launched_at,
                update,
            } => Self::InstallerLaunched {
                revision,
                launched_at,
                update: update.into(),
            },
            protocol::UpdatesReadHeader::CheckFailed {
                revision,
                failed_at,
                error,
            } => Self::CheckFailed {
                revision,
                failed_at,
                error: error.into(),
            },
            protocol::UpdatesReadHeader::InstallFailed {
                revision,
                failed_at,
                update,
                error,
            } => Self::InstallFailed {
                revision,
                failed_at,
                update: update.into(),
                error: error.into(),
            },
        }
    }
}

impl ModelsRead for StudioUpdatesRead {
    fn identity(&self) -> pl_protocol::products::identity::ProductReadScopeIdentity {
        self.identity()
    }
    fn ensure_open(&self) -> Result<(), pl_protocol::studio::StudioError> {
        self.ensure_open()
    }
    fn request_close(&self) {
        self.request_close();
    }
    fn close(
        &self,
    ) -> impl std::future::Future<Output = pl_protocol::studio::FeedCloseReport> + Send {
        self.close()
    }
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeUpdatesReadConnection {
    read: ModelsReadHandle<StudioUpdatesRead>,
}
pub async fn open_updates_read(
    reference: BridgeUpdatesReadRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgeUpdatesReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeUpdatesReadConnection {
        read: open_read(move |runtime| runtime.open_updates_read(reference, origin)).await?,
    })
}
impl BridgeUpdatesReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeUpdatesReadHeader, BridgeError> {
        Ok(self.read.query(StudioUpdatesRead::header)?.await?.into())
    }
    pub async fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> Result<BridgeTextChunk, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.text(field_id, offset, max_bytes))?
            .await?
            .into())
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.read.request_close();
    }
    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.close().await
    }
    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.retry_close().await
    }
}

impl ModelsRead for StudioUpdateSummaryRead {
    fn identity(&self) -> pl_protocol::products::identity::ProductReadScopeIdentity {
        self.identity()
    }
    fn ensure_open(&self) -> Result<(), pl_protocol::studio::StudioError> {
        self.ensure_open()
    }
    fn request_close(&self) {
        self.request_close();
    }
    fn close(
        &self,
    ) -> impl std::future::Future<Output = pl_protocol::studio::FeedCloseReport> + Send {
        self.close()
    }
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeUpdateSummaryReadConnection {
    read: ModelsReadHandle<StudioUpdateSummaryRead>,
}
pub async fn open_summary(
    reference: BridgeUpdateSummaryReadRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgeUpdateSummaryReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeUpdateSummaryReadConnection {
        read: open_read(move |runtime| runtime.open_summary(reference, origin)).await?,
    })
}
impl BridgeUpdateSummaryReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeUpdateSummaryRead, BridgeError> {
        Ok(self
            .read
            .query(StudioUpdateSummaryRead::header)?
            .await?
            .into())
    }
    pub async fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> Result<BridgeTextChunk, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.text(field_id, offset, max_bytes))?
            .await?
            .into())
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.read.request_close();
    }
    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.close().await
    }
    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.retry_close().await
    }
}

impl ModelsRead for StudioUpdateOperationRead {
    fn identity(&self) -> pl_protocol::products::identity::ProductReadScopeIdentity {
        self.identity()
    }
    fn ensure_open(&self) -> Result<(), pl_protocol::studio::StudioError> {
        self.ensure_open()
    }
    fn request_close(&self) {
        self.request_close();
    }
    fn close(
        &self,
    ) -> impl std::future::Future<Output = pl_protocol::studio::FeedCloseReport> + Send {
        self.close()
    }
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeUpdateOperationReadConnection {
    read: ModelsReadHandle<StudioUpdateOperationRead>,
}
pub async fn open_operation(
    reference: BridgeUpdateOperationReadRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgeUpdateOperationReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeUpdateOperationReadConnection {
        read: open_read(move |runtime| runtime.open_operation(reference, origin)).await?,
    })
}
impl BridgeUpdateOperationReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeUpdateOperationReadHeader, BridgeError> {
        Ok(self
            .read
            .query(StudioUpdateOperationRead::header)?
            .await?
            .into())
    }
    pub async fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> Result<BridgeTextChunk, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.text(field_id, offset, max_bytes))?
            .await?
            .into())
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.read.request_close();
    }
    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.close().await
    }
    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.retry_close().await
    }
}

impl ModelsRead for StudioUpdateErrorRead {
    fn identity(&self) -> pl_protocol::products::identity::ProductReadScopeIdentity {
        self.identity()
    }
    fn ensure_open(&self) -> Result<(), pl_protocol::studio::StudioError> {
        self.ensure_open()
    }
    fn request_close(&self) {
        self.request_close();
    }
    fn close(
        &self,
    ) -> impl std::future::Future<Output = pl_protocol::studio::FeedCloseReport> + Send {
        self.close()
    }
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeUpdateErrorReadConnection {
    read: ModelsReadHandle<StudioUpdateErrorRead>,
}
pub async fn open_error(
    reference: BridgeUpdateErrorReadRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgeUpdateErrorReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeUpdateErrorReadConnection {
        read: open_read(move |runtime| runtime.open_error(reference, origin)).await?,
    })
}
impl BridgeUpdateErrorReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeSourceStateErrorRead, BridgeError> {
        Ok(self
            .read
            .query(StudioUpdateErrorRead::header)?
            .await?
            .into())
    }
    pub async fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> Result<BridgeTextChunk, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.text(field_id, offset, max_bytes))?
            .await?
            .into())
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.read.request_close();
    }
    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.close().await
    }
    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.retry_close().await
    }
}

impl ModelsRead for StudioUpdateDetailsRead {
    fn identity(&self) -> pl_protocol::products::identity::ProductReadScopeIdentity {
        self.identity()
    }
    fn ensure_open(&self) -> Result<(), pl_protocol::studio::StudioError> {
        self.ensure_open()
    }
    fn request_close(&self) {
        self.request_close();
    }
    fn close(
        &self,
    ) -> impl std::future::Future<Output = pl_protocol::studio::FeedCloseReport> + Send {
        self.close()
    }
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeUpdateDetailsReadConnection {
    read: ModelsReadHandle<StudioUpdateDetailsRead>,
}
pub async fn open_details(
    reference: BridgeUpdateDetailsReadRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgeUpdateDetailsReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeUpdateDetailsReadConnection {
        read: open_read(move |runtime| runtime.open_details(reference, origin)).await?,
    })
}
impl BridgeUpdateDetailsReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeUpdateDetailsRead, BridgeError> {
        Ok(self
            .read
            .query(StudioUpdateDetailsRead::header)?
            .await?
            .into())
    }
    pub async fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> Result<BridgeTextChunk, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.text(field_id, offset, max_bytes))?
            .await?
            .into())
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.read.request_close();
    }
    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.close().await
    }
    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.retry_close().await
    }
}

// Update task supervision reuses TypedFeedTask's retained actual producer join, but deliberately
// has no stream/ACK API: canonical progress belongs only to the independent Updates feed.
use crate::api::studio::subscription::BridgeTaskRegistry;
use crate::api::studio::subscription::typed_feed::{TypedFeedResource, TypedFeedTask, closed};
use pl_studio_runtime::updates::StudioUpdateTask;
use std::sync::{Arc, Mutex};

struct UpdateTaskOwner {
    task: Arc<TypedFeedTask>,
    native: Mutex<Option<Arc<StudioUpdateTask>>>,
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeUpdateTask {
    owner: Arc<UpdateTaskOwner>,
    registry: &'static BridgeTaskRegistry,
    identity: BridgeUpdateTaskIdentity,
}
struct TaskOpening(Option<Arc<UpdateTaskOwner>>);
impl Drop for TaskOpening {
    fn drop(&mut self) {
        if let Some(owner) = &self.0 {
            owner.request_close();
        }
    }
}

pub async fn open_update_check(operation_id: String) -> Result<BridgeUpdateTask, BridgeError> {
    open_task(move |runtime| runtime.open_update_check(operation_id)).await
}
pub async fn open_automatic_update(operation_id: String) -> Result<BridgeUpdateTask, BridgeError> {
    open_task(move |runtime| runtime.open_automatic_update(operation_id)).await
}
pub async fn open_update_preparation(
    operation_id: String,
    expected_revision: u64,
    version: String,
) -> Result<BridgeUpdateTask, BridgeError> {
    open_task(move |runtime| {
        runtime.open_update_preparation(operation_id, expected_revision, version)
    })
    .await
}
async fn open_task<F>(
    open: impl FnOnce(pl_studio_runtime::StudioRuntime) -> F + Send + 'static,
) -> Result<BridgeUpdateTask, BridgeError>
where
    F: std::future::Future<Output = anyhow::Result<StudioUpdateTask>> + Send + 'static,
{
    let bridge = crate::api::studio::bridge_runtime::installed_bridge()?;
    let task = TypedFeedTask::new(
        bridge.subscriptions.next_id(),
        bridge.shutdown.child_token(),
    );
    let owner = Arc::new(UpdateTaskOwner {
        task: task.clone(),
        native: Mutex::new(None),
    });
    bridge.subscriptions.register_typed(&task, &owner)?;
    let mut opening = TaskOpening(Some(owner.clone()));
    let (opened, ready) = tokio::sync::oneshot::channel();
    let producer = owner.clone();
    if let Err(error) = task.start(async move {
        // This starts only transport supervision. No native command is started by named open.
        let native = match open(bridge.studio.clone()).await {
            Ok(native) => Arc::new(native),
            Err(error) => {
                producer.request_close();
                let _ = opened.send(Err(BridgeError::from(error)));
                return;
            }
        };
        *producer
            .native
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(native.clone());
        let installed = producer.task.admit(|| {
            native.ensure_open()?;
            Ok(native.identity())
        });
        match installed {
            Ok(identity) => {
                if opened.send(Ok(identity)).is_err() {
                    producer.request_close();
                }
            }
            Err(error) => {
                producer.request_close();
                let _ = opened.send(Err(error));
            }
        }
        producer.task.cancel().cancelled().await;
        native.request_close();
        match native.close().await.outcome {
            pl_protocol::studio::FeedCloseOutcome::Clean => {
                producer
                    .native
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .take();
            }
            pl_protocol::studio::FeedCloseOutcome::Unresolved { issues } => {
                for issue in issues {
                    producer.task.record_cleanup_issue(issue.into());
                }
            }
        }
    }) {
        owner.request_close();
        return Err(error);
    }
    let identity = match ready.await {
        Ok(result) => result?,
        Err(_) => {
            owner.request_close();
            return Err(pl_protocol::studio::StudioError::internal().into());
        }
    };
    let handle = BridgeUpdateTask {
        owner,
        registry: &bridge.subscriptions,
        identity: identity.into(),
    };
    opening.0.take();
    Ok(handle)
}
impl UpdateTaskOwner {
    fn native(&self) -> Result<Arc<StudioUpdateTask>, BridgeError> {
        self.native
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
            .ok_or_else(closed)
    }
    fn request_close(&self) {
        self.task.signal_cancel();
        if let Some(native) = self
            .native
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
        {
            native.request_close();
        }
    }
}
#[flutter_rust_bridge::frb(ignore)]
impl TypedFeedResource for UpdateTaskOwner {
    fn release_after_join(&self) {
        self.native
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take();
    }
}
impl BridgeUpdateTask {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeUpdateTaskIdentity {
        self.identity.clone()
    }
    pub async fn start(&self) -> Result<(), BridgeError> {
        self.owner.task.admit(|| Ok(self.owner.native()?.start()?))
    }
    pub async fn finish(&self) -> Result<BridgeUpdatesReadTarget, BridgeError> {
        let finish = self
            .owner
            .task
            .admit(|| Ok(self.owner.native()?.finish()))?;
        Ok(finish.await?.into())
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn request_cancel(&self) {
        // Cancel work, not its completion observation: Ready may already have won the race.
        if let Ok(native) = self.owner.native() {
            native.request_cancel();
        }
    }
    pub async fn close(&self) -> Result<BridgeUpdateTaskCloseReport, BridgeError> {
        self.owner.request_close();
        let outcome = if self.owner.task.wait_stopped().await.is_ok() {
            self.registry.unregister_typed(self.owner.task.id);
            BridgeFeedCloseOutcome::Clean
        } else {
            BridgeFeedCloseOutcome::Unresolved {
                issues: self.owner.task.close_issues(),
            }
        };
        Ok(BridgeUpdateTaskCloseReport {
            identity: self.identity(),
            outcome,
        })
    }
    pub async fn retry_close(&self) -> Result<BridgeUpdateTaskCloseReport, BridgeError> {
        self.owner.request_close();
        let _ = self.owner.task.wait_stopped().await;
        let native = self
            .owner
            .native
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        if let Some(native) = native {
            match native.retry_close().await.outcome {
                pl_protocol::studio::FeedCloseOutcome::Clean => {
                    self.owner.task.replace_cleanup_issues(Vec::new());
                    self.owner
                        .native
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner)
                        .take();
                }
                pl_protocol::studio::FeedCloseOutcome::Unresolved { issues } => self
                    .owner
                    .task
                    .replace_cleanup_issues(issues.into_iter().map(Into::into).collect()),
            }
        }
        self.close().await
    }
}
impl Drop for BridgeUpdateTask {
    fn drop(&mut self) {
        self.owner.request_close();
    }
}
