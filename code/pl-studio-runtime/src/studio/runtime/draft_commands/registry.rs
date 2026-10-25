use super::super::{StudioRuntime, background_task::BackgroundTask};
use super::admission::{AdmissionOwner, StudioAttachmentAdmission};
use super::creation::{CreationOwner, StudioThreadCreation};
use anyhow::Result;
use pl_protocol::studio::{
    AdmitAttachmentDraftsRequest, BeginThreadCreationRequest, StudioError, StudioErrorCode,
    StudioErrorDetails,
};
use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};

const JOB_LIMIT: usize = 64;

#[derive(Clone, Default)]
pub(in crate::studio::runtime) struct DraftCommandRegistry(pub(super) Arc<Mutex<Registry>>);
#[derive(Default)]
pub(super) struct Registry {
    sealed: bool,
    pub(super) jobs: BTreeMap<String, Job>,
    creating: Option<String>,
}
#[derive(Clone)]
pub(super) enum Job {
    Admission(Arc<AdmissionOwner>),
    Creation(Arc<CreationOwner>),
}

impl Registry {
    fn admit(&self) -> Result<(), StudioError> {
        if self.sealed {
            return Err(super::closed());
        }
        if self.jobs.len() >= JOB_LIMIT {
            return Err(StudioError::new(
                StudioErrorCode::Overloaded,
                "Draft command capacity is exhausted",
                true,
            )
            .with_details(StudioErrorDetails::ResourceLimit {
                resource: "draftCommands".into(),
                capacity: JOB_LIMIT as u64,
            }));
        }
        Ok(())
    }
}

impl StudioRuntime {
    pub fn begin_attachment_admission(
        &self,
        operation_id: String,
        request: AdmitAttachmentDraftsRequest,
    ) -> Result<StudioAttachmentAdmission> {
        Self::validate_operation_id(&operation_id)?;
        let mut registry = self
            .draft_commands
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(job) = registry.jobs.get(&operation_id) {
            return match job {
                Job::Admission(job) if job.request == request => {
                    Ok(StudioAttachmentAdmission(job.clone()))
                }
                Job::Admission(_) | Job::Creation(_) => Err(conflict().into()),
            };
        }
        registry.admit()?;
        let job = AdmissionOwner::new(
            operation_id.clone(),
            request,
            Arc::downgrade(&self.draft_commands.0),
        );
        registry
            .jobs
            .insert(operation_id, Job::Admission(job.clone()));
        let runtime = self.clone();
        let work = job.clone();
        let finished = Arc::downgrade(&job);
        job.life.install(BackgroundTask::with_cleanup(
            tokio::spawn(async move {
                work.run(runtime).await;
            }),
            move || {
                if let Some(job) = finished.upgrade() {
                    job.finish_result();
                }
            },
        ));
        Ok(StudioAttachmentAdmission(job))
    }
    pub fn find_attachment_admission(
        &self,
        operation_id: String,
    ) -> Result<Option<StudioAttachmentAdmission>> {
        Self::validate_operation_id(&operation_id)?;
        match self
            .draft_commands
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .jobs
            .get(&operation_id)
        {
            Some(Job::Admission(job)) => Ok(Some(StudioAttachmentAdmission(job.clone()))),
            Some(Job::Creation(_)) => Err(conflict().into()),
            None => Ok(None),
        }
    }
    pub fn begin_thread_creation(
        &self,
        request: BeginThreadCreationRequest,
    ) -> Result<StudioThreadCreation> {
        Self::validate_operation_id(&request.operation_id)?;
        let mut registry = self
            .draft_commands
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(job) = registry.jobs.get(&request.operation_id) {
            return match job {
                Job::Creation(job) if job.request == request => {
                    Ok(StudioThreadCreation(job.clone()))
                }
                Job::Admission(_) | Job::Creation(_) => Err(conflict().into()),
            };
        }
        registry.admit()?;
        if registry.creating.is_some() {
            return Err(StudioError::new(
                StudioErrorCode::Busy,
                "Another Thread creation is still running",
                true,
            )
            .into());
        }
        let id = request.operation_id.clone();
        let job = CreationOwner::new(request, Arc::downgrade(&self.draft_commands.0));
        registry.creating = Some(id.clone());
        registry.jobs.insert(id.clone(), Job::Creation(job.clone()));
        let runtime = self.clone();
        let work = job.clone();
        let gate = Arc::downgrade(&self.draft_commands.0);
        let finished = Arc::downgrade(&job);
        job.life.install(BackgroundTask::with_cleanup(
            tokio::spawn(async move {
                work.run(runtime).await;
            }),
            move || {
                if let Some(job) = finished.upgrade() {
                    job.finish_progress();
                }
                if let Some(gate) = gate.upgrade() {
                    let mut state = gate
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner);
                    if state.creating.as_deref() == Some(id.as_str()) {
                        state.creating = None;
                    }
                }
            },
        ));
        Ok(StudioThreadCreation(job))
    }
    pub fn find_thread_creation(
        &self,
        operation_id: String,
    ) -> Result<Option<StudioThreadCreation>> {
        Self::validate_operation_id(&operation_id)?;
        match self
            .draft_commands
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .jobs
            .get(&operation_id)
        {
            Some(Job::Creation(job)) => Ok(Some(StudioThreadCreation(job.clone()))),
            Some(Job::Admission(_)) => Err(conflict().into()),
            None => Ok(None),
        }
    }
}

impl DraftCommandRegistry {
    pub(in crate::studio::runtime) fn seal(&self) {
        let jobs: Vec<_> = {
            let mut state = self
                .0
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            state.sealed = true;
            state.jobs.values().cloned().collect()
        };
        // Never call a resource under the registry guard; actual completion releases in reverse.
        for job in jobs {
            match job {
                Job::Admission(job) => job.request_close(),
                Job::Creation(job) => job.request_close(),
            }
        }
    }
    pub(in crate::studio::runtime) async fn close(
        &self,
    ) -> Vec<pl_protocol::studio::FeedCloseIssue> {
        self.seal();
        let jobs: Vec<_> = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .jobs
            .values()
            .cloned()
            .collect();
        futures::future::join_all(jobs.into_iter().map(|job| async move {
            let report = match job {
                Job::Admission(job) => StudioAttachmentAdmission(job).retry_close().await,
                Job::Creation(job) => StudioThreadCreation(job).retry_close().await,
            };
            match report.outcome {
                pl_protocol::studio::FeedCloseOutcome::Clean => Vec::new(),
                pl_protocol::studio::FeedCloseOutcome::Unresolved { issues } => issues,
            }
        }))
        .await
        .into_iter()
        .flatten()
        .collect()
    }
}

fn conflict() -> StudioError {
    StudioError::new(
        StudioErrorCode::Conflict,
        "Operation ID is bound to another frozen draft command",
        false,
    )
}

#[derive(Debug, thiserror::Error)]
#[error("Draft command cleanup retained unresolved owners")]
pub(in crate::studio::runtime) struct DraftCommandsCloseFailure {
    pub(in crate::studio::runtime) issues: Vec<pl_protocol::studio::FeedCloseIssue>,
    #[source]
    pub(in crate::studio::runtime) source: Option<anyhow::Error>,
}
