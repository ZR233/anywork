use super::super::StudioRuntime;
use super::lifetime::Lifetime;
use super::registry::Registry;
use pl_protocol::studio::{
    AdmitAttachmentDraftsRequest, AdmitAttachmentDraftsResponse, AttachmentAdmissionIdentity,
    AttachmentAdmissionOutcome, CleanupRecovery, FeedCloseIssue, FeedCloseReport, StudioError,
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
    outcome: Mutex<Option<RetainedAdmissionOutcome>>,
}

enum RetainedAdmissionOutcome {
    Returned(AdmitAttachmentDraftsResponse),
    Rejected {
        rejection: AdmissionRejection,
        reported: bool,
    },
    Unknown(StudioError),
}

/// The original owner retains the cause; only its safe projection crosses transport boundaries.
#[derive(Clone)]
struct AdmissionRejection {
    error: StudioError,
    source: Arc<anyhow::Error>,
}

impl AdmissionRejection {
    fn new(source: anyhow::Error) -> Self {
        Self {
            error: crate::studio_error_from_anyhow_ref(&source),
            source: Arc::new(source),
        }
    }

    fn report(&self, operation_id: &str) {
        // Inspect typed causes without formatting them: HTTP/I/O errors may contain credentials,
        // complete URLs or local paths. This is the owner's diagnostic seam, not a second registry.
        let cause_kind = if self.source.downcast_ref::<std::io::Error>().is_some() {
            "io"
        } else if self.source.downcast_ref::<reqwest::Error>().is_some() {
            "http"
        } else {
            "other"
        };
        tracing::warn!(
            operation_id,
            correlation_id = %self.error.correlation_id,
            code = self.error.code.label(),
            retryable = self.error.retryable,
            stage = "attachmentAdmission",
            cause_kind,
            "attachment admission rejected"
        );
    }
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
            Ok(value) => RetainedAdmissionOutcome::Returned(value),
            Err(error) => {
                // No entries are published until the complete batch validates. A normal return
                // here proves rejection; a panic/missing result is classified Unknown by result().
                self.life.replace_cleanup(self.files.cleanup().await);
                RetainedAdmissionOutcome::Rejected {
                    rejection: AdmissionRejection::new(error),
                    reported: false,
                }
            }
        };
        *self
            .outcome
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(outcome);
    }
    pub(super) fn finish_result(&self) -> AttachmentAdmissionOutcome {
        let (outcome, diagnostic) = {
            let mut retained = self
                .outcome
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            match retained
                .get_or_insert_with(|| RetainedAdmissionOutcome::Unknown(StudioError::internal()))
            {
                RetainedAdmissionOutcome::Returned(value) => (
                    AttachmentAdmissionOutcome::Returned {
                        value: value.clone(),
                    },
                    None,
                ),
                RetainedAdmissionOutcome::Rejected {
                    rejection,
                    reported,
                } => {
                    let diagnostic = if *reported {
                        None
                    } else {
                        *reported = true;
                        Some(rejection.clone())
                    };
                    (
                        AttachmentAdmissionOutcome::Rejected {
                            error: rejection.error.clone(),
                        },
                        diagnostic,
                    )
                }
                RetainedAdmissionOutcome::Unknown(error) => (
                    AttachmentAdmissionOutcome::UnknownOutcome {
                        error: error.clone(),
                    },
                    None,
                ),
            }
        };
        // Logging may re-enter observers. Mark once under the owner lock, then report outside it.
        if let Some(diagnostic) = diagnostic {
            diagnostic.report(&self.life.id);
        }
        outcome
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::{ConfigPaths, ConfigStore, StudioConfig};
    use pl_model::config::{AccountConfig, AccountId, ModelRouteConfig};
    use pl_model::model::{
        MediaRepresentation, MediaWireFormat, ModelInfo, ModelInputCapability, ModelInputSource,
        ModelMediaInputProfile, ModelModality,
    };
    use pl_model::protocol::ProtocolEndpoint;
    use pl_protocol::studio::{
        FeedCloseOutcome, NewThreadModelRoute, StudioAttachmentAdmissionContext,
        StudioAttachmentDraftSource, StudioErrorCode,
    };

    #[tokio::test]
    async fn rejection_retains_correlated_cause_without_leaking_wire_or_close_budget()
    -> anyhow::Result<()> {
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let account_name = "attachment-fixture";
        let account_id = AccountId::new(account_name)?;
        let route = ModelRouteConfig {
            account_id: account_id.clone(),
            model_id: "attachment-model".into(),
            effort: None,
        };
        let mut model = ModelInfo::compatible(&route.model_id);
        model.capabilities.input.push(ModelInputCapability::media(
            ModelModality::Image,
            vec![ModelInputSource::Local],
        ));
        model.binding.request.media.push(ModelMediaInputProfile {
            modality: ModelModality::Image,
            wire: MediaWireFormat::ChatImageUrl,
            first_send: vec![MediaRepresentation::DataUrl],
            replay: vec![MediaRepresentation::DataUrl],
        });
        let mut config = StudioConfig::default_config()?;
        config.models.accounts.clear();
        config.models.accounts.insert(
            account_id,
            AccountConfig::from_explicit_models(
                // Route resolution uses explicit local metadata only. No model session, server,
                // credentials, remote source or network request is needed for this admission.
                ProtocolEndpoint::compatible(
                    "Attachment fixture",
                    "https://attachment-fixture.invalid",
                ),
                vec![model],
            ),
        );
        for selected in config
            .models
            .routes
            .values_mut()
            .chain(config.mode_model_routes.values_mut())
        {
            *selected = route.clone();
        }
        ConfigStore::new(ConfigPaths::from_config_dir(&home)).save(&config)?;
        let runtime = StudioRuntime::initialize(crate::StudioRuntimeOptions {
            studio_home: Some(home),
            host: crate::StudioHostKind::Test,
            ..crate::StudioRuntimeOptions::desktop()
        })
        .await?;
        let missing = temp.path().join("private-credential-missing.png");
        assert!(!missing.exists());
        let valid = temp.path().join("valid.png");
        image::RgbaImage::from_pixel(1, 1, image::Rgba([0, 0, 0, 255])).save(&valid)?;
        let request = AdmitAttachmentDraftsRequest {
            context: StudioAttachmentAdmissionContext::NewThread {
                route: NewThreadModelRoute {
                    account_id: account_name.into(),
                    model_id: route.model_id,
                    effort: None,
                },
            },
            // The first file is staged before the second file fails, so rejection must really
            // roll back unpublished files rather than merely calling cleanup on an empty set.
            sources: vec![
                StudioAttachmentDraftSource::LocalFile {
                    path: valid.to_string_lossy().into_owned(),
                },
                StudioAttachmentDraftSource::LocalFile {
                    path: missing.to_string_lossy().into_owned(),
                },
            ],
        };
        // Prove the same frozen route and Image/Local source pass model preflight. The rejection
        // below must be the real file-open IO failure, not an unavailable model masquerading as it.
        runtime.preflight_attachment_drafts(&request).await?;
        let operation_id = "attachment-operation";
        let admission = runtime.begin_attachment_admission(operation_id.into(), request)?;
        let held = runtime
            .find_attachment_admission(operation_id.into())?
            .expect("original job registered");
        let result = admission.result().await;
        let AttachmentAdmissionOutcome::Rejected { error } = &result else {
            panic!("a completed file-open failure must be a known rejection");
        };
        assert_eq!(error.code, StudioErrorCode::InvalidArgument);
        let source = {
            let outcome = admission.0.outcome.lock().expect("outcome lock");
            let Some(RetainedAdmissionOutcome::Rejected { rejection, .. }) = outcome.as_ref()
            else {
                panic!("the original run must retain its rejection and source");
            };
            assert_eq!(rejection.error, *error);
            let io = rejection
                .source
                .downcast_ref::<std::io::Error>()
                .expect("file-open IO cause retained by run");
            assert_eq!(io.kind(), std::io::ErrorKind::NotFound);
            let original = rejection
                .source
                .downcast_ref::<StudioError>()
                .expect("source-layer safe error retained");
            assert_eq!(original.correlation_id, error.correlation_id);
            Arc::downgrade(&rejection.source)
        };
        let wire = serde_json::to_string(&result).expect("safe outcome serialization");
        for sensitive in [
            missing.to_str().expect("temporary UTF-8 path"),
            "private-credential",
            "attachment-fixture.invalid",
        ] {
            assert!(
                !wire.contains(sensitive),
                "original causes must not cross wire"
            );
        }
        assert!(
            admission.close_issues().is_empty(),
            "a known rejection is not a cleanup failure"
        );
        assert!(admission.0.files.0.lock().expect("files lock").is_empty());
        let mut staged = tokio::fs::read_dir(runtime.store.paths().attachment_drafts_dir()).await?;
        assert!(
            staged.next_entry().await?.is_none(),
            "run must remove unpublished files before returning rejection"
        );
        drop(staged);

        let report = admission.close().await;
        assert_eq!(report.outcome, FeedCloseOutcome::Clean);
        assert!(admission.is_closed());
        assert!(
            runtime
                .find_attachment_admission(operation_id.into())?
                .is_none()
        );
        assert!(
            runtime
                .draft_commands
                .0
                .lock()
                .expect("registry lock")
                .jobs
                .is_empty()
        );
        // Closing releases the original job budget; a still-held result handle may re-read the
        // same safe error/correlation without keeping a second registry entry or a new task alive.
        assert_eq!(held.result().await, result);
        assert!(source.upgrade().is_some());
        drop(admission);
        assert!(
            source.upgrade().is_some(),
            "the original held handle still owns its cause"
        );
        drop(held);
        assert!(
            source.upgrade().is_none(),
            "last original owner releases the cause"
        );
        runtime.shutdown_runtime().await?;
        Ok(())
    }
}
