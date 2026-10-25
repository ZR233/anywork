//! Concrete HTTP command identities, not a second business task registry or budget.

use pl_protocol::studio::{
    AdmitAttachmentDraftsRequest, BeginThreadCreationRequest, CleanupRecovery, FeedCloseIssue,
    StudioError, StudioErrorCode, StudioShutdownIssue,
};
use pl_studio_runtime::StudioRuntime;
use pl_studio_runtime::draft_commands::{StudioAttachmentAdmission, StudioThreadCreation};
use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};
use std::time::Instant;
use tokio::sync::OwnedSemaphorePermit;

use super::upload::Upload;

#[derive(Clone)]
pub(crate) struct UploadPermit(pub(crate) Arc<Mutex<Option<OwnedSemaphorePermit>>>);

#[derive(Default)]
pub(crate) struct DraftCommands(pub(super) Mutex<Registry>);
#[derive(Default)]
pub(super) struct Registry {
    pub(super) sealed: bool,
    pub(super) entries: BTreeMap<String, Entry>,
}
#[derive(Clone)]
pub(super) enum Entry {
    Upload(Arc<Upload>),
    Admission(StudioAttachmentAdmission),
    Creation(StudioThreadCreation),
}

impl Registry {
    pub(super) fn reap(&mut self) {
        // This follows the native actual-join fact, not HTTP caller completion. A cancelled
        // close response must not leave an unbounded cache or remove a later same-ID owner.
        self.entries.retain(|_, entry| match entry {
            Entry::Upload(_) => true,
            Entry::Admission(job) => !job.is_closed(),
            Entry::Creation(job) => !job.is_closed(),
        });
    }
}

impl DraftCommands {
    pub(super) fn begin_admission(
        &self,
        runtime: &StudioRuntime,
        id: String,
        request: AdmitAttachmentDraftsRequest,
    ) -> anyhow::Result<StudioAttachmentAdmission> {
        let mut registry = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        registry.reap();
        if let Some(entry) = registry.entries.get(&id) {
            return match entry {
                Entry::Admission(job) if job.matches_request(&request) => Ok(job.clone()),
                Entry::Upload(_) | Entry::Admission(_) | Entry::Creation(_) => {
                    Err(conflict().into())
                }
            };
        }
        if registry.sealed {
            return Err(closed().into());
        }
        let job = runtime.begin_attachment_admission(id.clone(), request)?;
        registry.entries.insert(id, Entry::Admission(job.clone()));
        Ok(job)
    }
    pub(super) fn begin_creation(
        &self,
        runtime: &StudioRuntime,
        request: BeginThreadCreationRequest,
    ) -> anyhow::Result<StudioThreadCreation> {
        let mut registry = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        registry.reap();
        if let Some(entry) = registry.entries.get(&request.operation_id) {
            return match entry {
                Entry::Creation(job) if job.matches_request(&request) => Ok(job.clone()),
                Entry::Upload(_) | Entry::Admission(_) | Entry::Creation(_) => {
                    Err(conflict().into())
                }
            };
        }
        if registry.sealed {
            return Err(closed().into());
        }
        let id = request.operation_id.clone();
        let job = runtime.begin_thread_creation(request)?;
        registry.entries.insert(id, Entry::Creation(job.clone()));
        Ok(job)
    }
    pub(super) fn admission(
        &self,
        runtime: &StudioRuntime,
        id: &str,
    ) -> anyhow::Result<Option<StudioAttachmentAdmission>> {
        let mut registry = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        registry.reap();
        match registry.entries.get(id) {
            Some(Entry::Admission(job)) => return Ok(Some(job.clone())),
            Some(Entry::Upload(_) | Entry::Creation(_)) => return Err(conflict().into()),
            None => {}
        }
        let job = runtime.find_attachment_admission(id.to_owned())?;
        if let Some(job) = &job {
            registry
                .entries
                .insert(id.to_owned(), Entry::Admission(job.clone()));
        }
        Ok(job)
    }
    pub(super) fn creation(
        &self,
        runtime: &StudioRuntime,
        id: &str,
    ) -> anyhow::Result<Option<StudioThreadCreation>> {
        let mut registry = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        registry.reap();
        match registry.entries.get(id) {
            Some(Entry::Creation(job)) => return Ok(Some(job.clone())),
            Some(Entry::Upload(_) | Entry::Admission(_)) => return Err(conflict().into()),
            None => {}
        }
        let job = runtime.find_thread_creation(id.to_owned())?;
        if let Some(job) = &job {
            registry
                .entries
                .insert(id.to_owned(), Entry::Creation(job.clone()));
        }
        Ok(job)
    }
    pub(super) fn upload(&self, id: &str) -> Result<Option<Arc<Upload>>, StudioError> {
        validate_id(id)?;
        match self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .entries
            .get(id)
        {
            Some(Entry::Upload(owner)) => Ok(Some(owner.clone())),
            Some(Entry::Admission(_) | Entry::Creation(_)) => Err(conflict()),
            None => Ok(None),
        }
    }
    pub(super) fn remove(&self, id: &str) {
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .entries
            .remove(id);
    }
    pub(super) fn reap(&self) {
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .reap();
    }
    pub(crate) fn seal(&self) {
        let entries: Vec<_> = {
            let mut registry = self
                .0
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            registry.sealed = true;
            registry.entries.values().cloned().collect()
        };
        for entry in entries {
            match entry {
                Entry::Upload(owner) => owner.request_close(),
                Entry::Admission(job) => job.request_close(),
                Entry::Creation(job) => job.request_close(),
            }
        }
    }
    pub(crate) async fn close_for_exit(&self, deadline: Instant) -> Vec<StudioShutdownIssue> {
        self.seal();
        let entries: Vec<_> = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .entries
            .values()
            .cloned()
            .collect();
        futures::future::join_all(entries.into_iter().map(|entry| async move {
            let close = async {
                match &entry {
                    Entry::Upload(owner) => owner.close(true).await,
                    Entry::Admission(job) => job.retry_close().await,
                    Entry::Creation(job) => job.retry_close().await,
                }
            };
            match tokio::time::timeout_at(tokio::time::Instant::from_std(deadline), close).await {
                Ok(report) => match report.outcome {
                    pl_protocol::studio::FeedCloseOutcome::Clean => Vec::new(),
                    pl_protocol::studio::FeedCloseOutcome::Unresolved { issues } => {
                        issues.into_iter().map(|issue| issue.diagnostic).collect()
                    }
                },
                Err(_) => {
                    let mut issues = match &entry {
                        Entry::Upload(owner) => owner.close_issues(),
                        Entry::Admission(job) => job.close_issues(),
                        Entry::Creation(job) => job.close_issues(),
                    };
                    issues.push(issue(
                        "pending",
                        "An original HTTP draft command/body/cleanup has not joined",
                        CleanupRecovery::AwaitCompletion,
                    ));
                    issues.into_iter().map(|issue| issue.diagnostic).collect()
                }
            }
        }))
        .await
        .into_iter()
        .flatten()
        .collect()
    }
}

pub(super) fn validate_id(id: &str) -> Result<(), StudioError> {
    if id.trim().is_empty() {
        Err(StudioError::invalid_argument("operationId is empty"))
    } else {
        Ok(())
    }
}
pub(super) fn conflict() -> StudioError {
    StudioError::new(
        StudioErrorCode::Conflict,
        "Operation ID belongs to another original HTTP input or command capability",
        false,
    )
}
pub(super) fn closed() -> StudioError {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "HTTP draft command admission is closed",
        false,
    )
}
pub(super) fn issue(code: &str, message: &str, recovery: CleanupRecovery) -> FeedCloseIssue {
    FeedCloseIssue {
        diagnostic: StudioShutdownIssue {
            stage: "draftCommandsHttp".into(),
            code: code.into(),
            message: message.into(),
            retryable: recovery != CleanupRecovery::Terminal,
            correlation_id: StudioError::internal().correlation_id,
        },
        recovery,
    }
}
