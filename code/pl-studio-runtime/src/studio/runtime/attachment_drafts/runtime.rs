//! 草稿批次持有来源读取、暂存写入与清理；发布后由 Client 引用生命周期负责。

use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use anyhow::{Context, Result, ensure};
use pl_protocol::studio::{
    AdmitAttachmentDraftsResponse, StudioAttachmentDraft, StudioAttachmentDraftSource, StudioError,
    StudioErrorCode,
};
use sha2::{Digest, Sha256};
use tokio::task::{JoinError, JoinHandle};
use tokio_util::sync::CancellationToken;

use crate::studio::store::attachment::AttachmentDraftObject;

use super::inspection::InspectionOwner;
use super::normalize::InspectionCancelled;
use super::source::{LoadedSource, fetch_remote_snapshot, read_local_file};
use super::validate::{
    MAX_BATCH_BYTES, MAX_BATCH_FILES, MAX_FILE_BYTES, preflight_sources, validate_draft_batch,
};

#[derive(Clone)]
pub(in crate::studio::runtime) struct AttachmentDraftRuntime {
    root: Arc<PathBuf>,
    // Registration, close sealing and publication share this IO-free boundary.
    state: Arc<Mutex<DraftState>>,
    // Borrow the handle while joining. Cancelling any waiter leaves the same task registered.
    worker: Arc<tokio::sync::Mutex<Option<JoinHandle<Result<BatchOutcome>>>>>,
    inspections: Arc<InspectionOwner>,
}

#[derive(Default)]
struct DraftState {
    closed: bool,
    entries: BTreeMap<String, AttachmentDraftObject>,
    active: Option<CancellationToken>,
    unpublished: BTreeSet<PathBuf>,
    cleanup_failure: Option<Arc<CleanupFailure>>,
    failure: Option<OwnerFailure>,
}

#[derive(Debug, thiserror::Error)]
#[error("failed to remove unpublished attachment staging {path}")]
struct CleanupFailure {
    path: PathBuf,
    #[source]
    source: std::io::Error,
}

#[derive(Clone, Debug, thiserror::Error)]
enum OwnerFailure {
    #[error("attachment batch worker did not complete")]
    Worker(#[source] Arc<JoinError>),
    #[error("attachment inspection shutdown failed")]
    Inspection(#[source] Arc<dyn std::error::Error + Send + Sync>),
}

enum BatchOutcome {
    Admitted(AdmitAttachmentDraftsResponse),
    Cleaned,
}

enum BatchSource {
    Source(StudioAttachmentDraftSource),
    Bytes(Vec<u8>),
}

struct BatchFile {
    filename: String,
    source: BatchSource,
}

impl AttachmentDraftRuntime {
    pub(in crate::studio::runtime) fn new(root: PathBuf) -> Result<Self> {
        if root.exists() {
            std::fs::remove_dir_all(&root).context("failed to clear expired attachment drafts")?;
        }
        std::fs::create_dir_all(&root).context("failed to create attachment draft directory")?;
        Ok(Self {
            root: Arc::new(root),
            state: Default::default(),
            worker: Default::default(),
            inspections: Default::default(),
        })
    }

    pub(super) async fn admit(
        &self,
        sources: Vec<StudioAttachmentDraftSource>,
    ) -> Result<AdmitAttachmentDraftsResponse> {
        let filenames = preflight_sources(&sources)?;
        let files = sources
            .into_iter()
            .zip(filenames)
            .map(|(source, filename)| BatchFile {
                filename,
                source: BatchSource::Source(source),
            })
            .collect();
        self.admit_batch(files).await
    }

    pub(super) async fn admit_bytes(
        &self,
        files: Vec<(String, Vec<u8>)>,
    ) -> Result<AdmitAttachmentDraftsResponse> {
        ensure!(
            !files.is_empty() && files.len() <= MAX_BATCH_FILES,
            StudioError::invalid_argument("一次请选择 1 至 32 个附件。")
        );
        let mut total = 0_u64;
        for (_, bytes) in &files {
            ensure!(
                bytes.len() as u64 <= MAX_FILE_BYTES,
                StudioError::invalid_argument("单个附件不能超过 50 MiB。")
            );
            total = total
                .checked_add(bytes.len() as u64)
                .context(StudioError::invalid_argument("附件总大小超出限制。"))?;
            ensure!(
                total <= MAX_BATCH_BYTES,
                StudioError::invalid_argument("附件总大小不能超过 128 MiB。")
            );
        }
        let files = files
            .into_iter()
            .map(|(filename, bytes)| {
                let filename = super::normalize::sanitize_filename(&filename);
                BatchFile {
                    filename: if filename.is_empty() {
                        "attachment".into()
                    } else {
                        filename
                    },
                    source: BatchSource::Bytes(bytes),
                }
            })
            .collect();
        self.admit_batch(files).await
    }

    async fn admit_batch(&self, files: Vec<BatchFile>) -> Result<AdmitAttachmentDraftsResponse> {
        let mut worker = self.worker.lock().await;
        // An abandoned caller's ordinary rejection belongs to that batch. Cleanup/fatal failures
        // remain in state, so no later admission can bypass the responsibility by draining it.
        let _previous = self.join_worker(&mut worker).await?;
        let cancellation = CancellationToken::new();
        let _cancel_on_drop = cancellation.clone().drop_guard();
        {
            let mut state = self
                .state
                .lock()
                .expect("attachment draft state lock poisoned");
            if state.closed {
                return Err(cancelled());
            }
            if let Some(failure) = &state.failure {
                return Err(failure.clone().into());
            }
            state.active = Some(cancellation.clone());
            let owner = self.clone();
            *worker = Some(tokio::spawn(async move {
                owner
                    .run_batch(files, cancellation)
                    .await
                    .map(BatchOutcome::Admitted)
            }));
        }
        match self
            .join_worker(&mut worker)
            .await?
            .context("attachment batch was not registered")??
        {
            BatchOutcome::Admitted(response) => Ok(response),
            BatchOutcome::Cleaned => {
                anyhow::bail!("attachment admission returned a cleanup result")
            }
        }
    }

    async fn run_batch(
        &self,
        files: Vec<BatchFile>,
        cancellation: CancellationToken,
    ) -> Result<AdmitAttachmentDraftsResponse> {
        // This retained task also owns retries of an earlier failed cleanup, before new IO.
        self.cleanup_unpublished().await?;
        let result = async {
            let mut admitted = Vec::with_capacity(files.len());
            let mut total = 0_u64;
            for file in files {
                if cancellation.is_cancelled() {
                    return Err(cancelled());
                }
                let max_bytes = MAX_FILE_BYTES.min(MAX_BATCH_BYTES - total);
                let loaded = match file.source {
                    BatchSource::Bytes(bytes) => LoadedSource { bytes },
                    BatchSource::Source(StudioAttachmentDraftSource::LocalFile { path }) => {
                        // Do not drop a started filesystem future: its blocking work must finish
                        // before this batch can clear its staging responsibility.
                        LoadedSource {
                            bytes: read_local_file(Path::new(&path), max_bytes).await?,
                        }
                    }
                    BatchSource::Source(StudioAttachmentDraftSource::RemoteUrl { url, .. }) => {
                        fetch_remote_snapshot(&url, max_bytes, &cancellation)
                            .await
                            .context(StudioError::new(
                                if cancellation.is_cancelled() {
                                    StudioErrorCode::Cancelled
                                } else {
                                    StudioErrorCode::InvalidArgument
                                },
                                "无法下载附件，请检查 HTTPS 地址、访问权限与文件大小。",
                                cancellation.is_cancelled(),
                            ))?
                    }
                };
                let draft = self.stage(file.filename, loaded, &cancellation).await?;
                total += draft.byte_size;
                admitted.push(draft);
            }
            self.publish(admitted, &cancellation)
        }
        .await;
        match result {
            Ok(response) => Ok(response),
            Err(error) => match self.cleanup_unpublished().await {
                Ok(()) => Err(error),
                Err(cleanup) => Err(error.context(cleanup)),
            },
        }
    }

    async fn stage(
        &self,
        filename: String,
        loaded: LoadedSource,
        cancellation: &CancellationToken,
    ) -> Result<AttachmentDraftObject> {
        // A source read may finish after its caller cancelled or close sealed inspection.
        // Do not begin new decoding in that case; the retained batch still owns cleanup.
        if cancellation.is_cancelled() || self.inspections.is_closed() {
            return Err(cancelled());
        }
        let normalized = self
            .inspections
            .inspect(loaded.bytes)
            .await
            .map_err(|error| {
                if error.is::<InspectionCancelled>() {
                    error.context(StudioError::new(
                        StudioErrorCode::Cancelled,
                        "附件处理已取消。",
                        true,
                    ))
                } else {
                    error.context(StudioError::new(
                        StudioErrorCode::Unavailable,
                        "无法读取附件元信息，请重试。",
                        true,
                    ))
                }
            })?;
        let draft_id = crate::studio::ids::new_id("attachment-draft");
        let storage_path = self.root.join(&draft_id);
        {
            let mut state = self
                .state
                .lock()
                .expect("attachment draft state lock poisoned");
            if state.closed || cancellation.is_cancelled() {
                return Err(cancelled());
            }
            // Register before write can create even a partial file. The retained batch awaits the
            // write to its real result, and only then may cleanup remove this exact owned path.
            state.unpublished.insert(storage_path.clone());
        }
        tokio::fs::write(&storage_path, &normalized.bytes).await?;
        Ok(AttachmentDraftObject {
            draft_id,
            modality: normalized.modality,
            media_type: normalized.media_type,
            filename,
            storage_path,
            byte_size: normalized.bytes.len() as u64,
            content_sha256: hex::encode(Sha256::digest(&normalized.bytes)),
            width: normalized.width,
            height: normalized.height,
        })
    }

    pub(in crate::studio::runtime) fn signal_close(&self) {
        let mut state = self
            .state
            .lock()
            .expect("attachment draft state lock poisoned");
        state.closed = true;
        if let Some(cancellation) = &state.active {
            cancellation.cancel();
        }
        self.inspections.signal_close();
    }

    pub(in crate::studio::runtime) async fn close(&self) -> Result<()> {
        self.signal_close();
        let mut worker = self.worker.lock().await;
        let _previous = self.join_worker(&mut worker).await;
        let has_unpublished = !self
            .state
            .lock()
            .expect("attachment draft state lock poisoned")
            .unpublished
            .is_empty();
        if has_unpublished {
            let owner = self.clone();
            *worker = Some(tokio::spawn(async move {
                owner
                    .cleanup_unpublished()
                    .await
                    .map(|()| BatchOutcome::Cleaned)
            }));
            let _cleanup = self.join_worker(&mut worker).await;
        }
        // Always join inspection too, even after a batch/cleanup failure. A cancelled close
        // waiter leaves both original handles retained for the next close, not detached/repolled.
        if let Err(error) = self.inspections.close().await {
            let failure = OwnerFailure::Inspection(Arc::from(error.into_boxed_dyn_error()));
            self.state
                .lock()
                .expect("attachment draft state lock poisoned")
                .failure
                .get_or_insert(failure);
        }
        let state = self
            .state
            .lock()
            .expect("attachment draft state lock poisoned");
        if let Some(failure) = &state.failure {
            return Err(failure.clone().into());
        }
        if let Some(failure) = &state.cleanup_failure {
            return Err(failure.clone().into());
        }
        ensure!(
            state.unpublished.is_empty(),
            "attachment staging still requires cleanup"
        );
        Ok(())
    }

    async fn join_worker(
        &self,
        worker: &mut Option<JoinHandle<Result<BatchOutcome>>>,
    ) -> Result<Option<Result<BatchOutcome>>> {
        let Some(task) = worker.as_mut() else {
            return Ok(None);
        };
        let joined = task.await;
        // Clear on every terminal path, before propagating JoinError or batch failure.
        *worker = None;
        let mut state = self
            .state
            .lock()
            .expect("attachment draft state lock poisoned");
        state.active = None;
        match joined {
            Ok(result) => Ok(Some(result)),
            Err(error) => {
                let failure = OwnerFailure::Worker(Arc::new(error));
                state.failure.get_or_insert(failure.clone());
                Err(failure.into())
            }
        }
    }

    async fn cleanup_unpublished(&self) -> Result<()> {
        let paths = self
            .state
            .lock()
            .expect("attachment draft state lock poisoned")
            .unpublished
            .clone();
        for path in paths {
            match tokio::fs::remove_file(&path).await {
                Ok(()) => {}
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
                Err(error) => {
                    let failure = Arc::new(CleanupFailure {
                        path,
                        source: error,
                    });
                    self.state
                        .lock()
                        .expect("attachment draft state lock poisoned")
                        .cleanup_failure = Some(failure.clone());
                    return Err(failure.into());
                }
            }
            self.state
                .lock()
                .expect("attachment draft state lock poisoned")
                .unpublished
                .remove(&path);
        }
        self.state
            .lock()
            .expect("attachment draft state lock poisoned")
            .cleanup_failure = None;
        Ok(())
    }

    fn publish(
        &self,
        admitted: Vec<AttachmentDraftObject>,
        cancellation: &CancellationToken,
    ) -> Result<AdmitAttachmentDraftsResponse> {
        validate_draft_batch(&admitted)?;
        let mut state = self
            .state
            .lock()
            .expect("attachment draft state lock poisoned");
        if state.closed || cancellation.is_cancelled() {
            return Err(cancelled());
        }
        let response = AdmitAttachmentDraftsResponse {
            drafts: admitted.iter().map(public_draft).collect(),
        };
        for draft in admitted {
            state.unpublished.remove(&draft.storage_path);
            state.entries.insert(draft.draft_id.clone(), draft);
        }
        Ok(response)
    }

    pub(in crate::studio::runtime) fn validate_batch(
        &self,
        drafts: &[AttachmentDraftObject],
    ) -> Result<()> {
        validate_draft_batch(drafts)
    }

    pub(in crate::studio::runtime) async fn resolve(
        &self,
        draft_ids: &[String],
    ) -> Result<Vec<AttachmentDraftObject>> {
        let state = self
            .state
            .lock()
            .expect("attachment draft state lock poisoned");
        let mut seen = BTreeSet::new();
        let mut drafts = Vec::with_capacity(draft_ids.len());
        for draft_id in draft_ids {
            ensure!(seen.insert(draft_id), "duplicate attachment draft id");
            let draft = state
                .entries
                .get(draft_id)
                .with_context(|| format!("attachment draft {draft_id} is unavailable"))?;
            drafts.push(draft.clone());
        }
        Ok(drafts)
    }

    pub(in crate::studio::runtime) async fn remove(&self, draft_id: &str) -> Result<bool> {
        let path = self
            .state
            .lock()
            .expect("attachment draft state lock poisoned")
            .entries
            .get(draft_id)
            .map(|draft| draft.storage_path.clone());
        let Some(path) = path else { return Ok(false) };
        match tokio::fs::remove_file(&path).await {
            Ok(()) => {}
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => return Err(error).context("failed to remove attachment staging"),
        }
        self.state
            .lock()
            .expect("attachment draft state lock poisoned")
            .entries
            .remove(draft_id);
        Ok(true)
    }

    pub(in crate::studio::runtime) async fn read(&self, draft_id: &str) -> Result<Vec<u8>> {
        let path = self
            .state
            .lock()
            .expect("attachment draft state lock poisoned")
            .entries
            .get(draft_id)
            .map(|draft| draft.storage_path.clone())
            .with_context(|| format!("attachment draft {draft_id} is unavailable"))?;
        Ok(tokio::fs::read(path).await?)
    }
}

fn public_draft(draft: &AttachmentDraftObject) -> StudioAttachmentDraft {
    StudioAttachmentDraft {
        draft_id: draft.draft_id.clone(),
        modality: draft.modality,
        media_type: draft.media_type.clone(),
        filename: draft.filename.clone(),
        byte_size: draft.byte_size,
        width: draft.width,
        height: draft.height,
    }
}

fn cancelled() -> anyhow::Error {
    StudioError::new(StudioErrorCode::Cancelled, "附件处理已取消。", true).into()
}
