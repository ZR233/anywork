use super::super::StudioRuntime;
use super::lifetime::Lifetime;
use super::registry::Registry;
use pl_protocol::studio::{
    AdmitAttachmentDraftsRequest, AttachmentAdmissionIdentity, AttachmentAdmissionOutcome,
    CleanupRecovery, FeedCloseIssue, FeedCloseReport,
};
use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex, Weak};

/// Only unpublished files belong to the job; published entries transfer to the draft ledger.
#[derive(Clone, Default)]
pub(in crate::studio::runtime) struct AdmissionFiles(
    Arc<Mutex<BTreeMap<PathBuf, Option<FeedCloseIssue>>>>,
);
impl AdmissionFiles {
    pub(in crate::studio::runtime) fn register(&self, path: PathBuf) {
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .insert(path, None);
    }
    pub(in crate::studio::runtime) fn published(&self) {
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clear();
    }
    async fn cleanup(&self) -> Vec<FeedCloseIssue> {
        let paths: Vec<_> = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .keys()
            .cloned()
            .collect();
        for path in paths {
            let result = tokio::fs::remove_file(&path).await;
            let mut files = self
                .0
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            match result {
                Ok(()) => {
                    files.remove(&path);
                }
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                    files.remove(&path);
                }
                Err(_) => {
                    files.entry(path).or_default().get_or_insert_with(|| {
                        super::issue(
                            "attachmentRollback",
                            "An unpublished attachment draft file could not be removed",
                            CleanupRecovery::RetryClose,
                        )
                    });
                }
            }
        }
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .values()
            .filter_map(Clone::clone)
            .collect()
    }
}

pub(super) struct AdmissionOwner {
    pub(super) life: Arc<Lifetime>,
    pub(super) request: AdmitAttachmentDraftsRequest,
    files: AdmissionFiles,
    outcome: Mutex<Option<AttachmentAdmissionOutcome>>,
}

#[derive(Clone)]
pub struct StudioAttachmentAdmission(pub(super) Arc<AdmissionOwner>);

impl AdmissionOwner {
    pub(super) fn new(
        id: String,
        request: AdmitAttachmentDraftsRequest,
        registry: Weak<Mutex<Registry>>,
    ) -> Arc<Self> {
        Arc::new(Self {
            life: Lifetime::new(id, registry),
            request,
            files: AdmissionFiles::default(),
            outcome: Mutex::new(None),
        })
    }
    pub(super) async fn run(&self, runtime: StudioRuntime) {
        let result = async {
            let model = runtime
                .attachment_model_for_context(&self.request.context)
                .await?;
            runtime
                .attachment_drafts
                .admit(self.request.sources.clone(), &model, &self.files)
                .await
        }
        .await;
        let outcome = match result {
            Ok(value) => AttachmentAdmissionOutcome::Returned { value },
            Err(error) => {
                // No entries are published until the complete batch validates. A normal return
                // here proves rejection; a panic/missing result is classified Unknown by result().
                self.life.replace_cleanup(self.files.cleanup().await);
                AttachmentAdmissionOutcome::Rejected {
                    error: crate::studio_error_from_anyhow(error),
                }
            }
        };
        *self
            .outcome
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(outcome);
    }
    pub(super) fn finish_result(&self) -> AttachmentAdmissionOutcome {
        self.outcome
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get_or_insert_with(|| AttachmentAdmissionOutcome::UnknownOutcome {
                error: super::StudioError::internal(),
            })
            .clone()
    }
    pub(super) fn request_close(&self) {
        self.life.request_close();
    }
}

impl StudioAttachmentAdmission {
    /// Side-effect-free fact used by HTTP to reap only actually joined Clean owners.
    pub fn is_closed(&self) -> bool {
        self.0.life.is_closed()
    }
    /// Current retained diagnostics only; does not close, retry, dispatch or release anything.
    pub fn close_issues(&self) -> Vec<FeedCloseIssue> {
        self.0.life.issues()
    }
    pub fn matches_request(&self, request: &AdmitAttachmentDraftsRequest) -> bool {
        &self.0.request == request
    }
    pub fn identity(&self) -> AttachmentAdmissionIdentity {
        AttachmentAdmissionIdentity {
            operation_id: self.0.life.id.clone(),
        }
    }
    /// Joins the original result even while closing. No new dispatch is performed.
    pub async fn result(&self) -> AttachmentAdmissionOutcome {
        self.0.life.join_work().await;
        self.0.finish_result()
    }
    pub fn request_close(&self) {
        self.0.request_close();
    }
    async fn finish(&self, retry: bool) -> FeedCloseReport {
        self.request_close();
        let work = self.0.clone();
        let cleanup = self.0.life.close_task(retry, async move {
            work.life.join_work().await;
            work.life.replace_cleanup(work.files.cleanup().await);
        });
        self.0.life.report(cleanup).await
    }
    pub async fn close(&self) -> FeedCloseReport {
        self.finish(false).await
    }
    pub async fn retry_close(&self) -> FeedCloseReport {
        self.finish(true).await
    }
}
