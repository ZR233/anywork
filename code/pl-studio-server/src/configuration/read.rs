//! HTTP scope tickets retain late native opens and the original query/join responsibility.
use pl_protocol::products::configuration::ConfigurationRoleReadTarget;
use pl_protocol::products::identity::{
    ProductReadOrigin, ProductReadScopeIdentity, ProductResource, ProductSourceStatusRef,
};
use pl_protocol::products::references::{AgentProfilesReadRef, ConfigurationReadRef};
use pl_protocol::studio::{
    CleanupRecovery, FeedCloseIssue, FeedCloseOutcome, FeedCloseReport, StudioError,
};
use pl_studio_runtime::{
    StudioRuntime,
    configuration::{
        StudioAgentProfilesRead, StudioConfigurationRead, StudioConfigurationRoleRead,
        StudioConfigurationSourceStatusRead, StudioConfigurationStartRead,
    },
};
use std::sync::{Arc, Mutex, Weak};
use tokio::sync::oneshot;
use tokio_util::sync::CancellationToken;

use super::feed::Transport;
use super::tasks::{self, Completion};

pub(super) enum OpenReadKind {
    Value(ConfigurationReadRef),
    Profiles(AgentProfilesReadRef),
    Role(ConfigurationRoleReadTarget),
    Start(ConfigurationRoleReadTarget),
    Source(ProductSourceStatusRef),
}
impl OpenReadKind {
    pub(super) fn check_origin(
        &self,
        origin: &ProductReadOrigin,
        resource: ProductResource,
    ) -> Result<(), StudioError> {
        let valid = match self {
            Self::Value(_) => resource == ProductResource::Configuration,
            Self::Profiles(_) => resource == ProductResource::AgentProfiles,
            Self::Role(target) | Self::Start(target) => {
                resource == ProductResource::Configuration && &target.configuration.origin == origin
            }
            Self::Source(_) => matches!(
                resource,
                ProductResource::Configuration | ProductResource::AgentProfiles
            ),
        };
        if valid {
            Ok(())
        } else {
            Err(StudioError::invalid_argument(
                "Read target does not belong to the original HTTP feed's product and origin",
            ))
        }
    }
    async fn open(
        self,
        runtime: StudioRuntime,
        origin: ProductReadOrigin,
    ) -> anyhow::Result<NativeRead> {
        Ok(match self {
            Self::Value(reference) => {
                NativeRead::Value(runtime.open_configuration_read(reference, origin).await?)
            }
            Self::Profiles(reference) => {
                NativeRead::Profiles(runtime.open_agent_profiles_read(reference, origin).await?)
            }
            Self::Role(target) => {
                NativeRead::Role(runtime.open_configuration_role_read(target).await?)
            }
            Self::Start(target) => {
                NativeRead::Start(runtime.open_configuration_start_read(target).await?)
            }
            Self::Source(reference) => NativeRead::Source(
                runtime
                    .open_configuration_source_status_read(reference, origin)
                    .await?,
            ),
        })
    }
}
pub(super) enum NativeRead {
    Value(StudioConfigurationRead),
    Profiles(StudioAgentProfilesRead),
    Role(StudioConfigurationRoleRead),
    Start(StudioConfigurationStartRead),
    Source(StudioConfigurationSourceStatusRead),
}
impl NativeRead {
    pub(super) fn value(&self) -> Result<&StudioConfigurationRead, StudioError> {
        if let Self::Value(value) = self {
            Ok(value)
        } else {
            Err(wrong_scope())
        }
    }
    pub(super) fn profiles(&self) -> Result<&StudioAgentProfilesRead, StudioError> {
        if let Self::Profiles(value) = self {
            Ok(value)
        } else {
            Err(wrong_scope())
        }
    }
    pub(super) fn role(&self) -> Result<&StudioConfigurationRoleRead, StudioError> {
        if let Self::Role(value) = self {
            Ok(value)
        } else {
            Err(wrong_scope())
        }
    }
    pub(super) fn start(&self) -> Result<&StudioConfigurationStartRead, StudioError> {
        if let Self::Start(value) = self {
            Ok(value)
        } else {
            Err(wrong_scope())
        }
    }
    pub(super) fn source(&self) -> Result<&StudioConfigurationSourceStatusRead, StudioError> {
        if let Self::Source(value) = self {
            Ok(value)
        } else {
            Err(wrong_scope())
        }
    }
    fn identity(&self) -> ProductReadScopeIdentity {
        match self {
            Self::Value(value) => value.identity(),
            Self::Profiles(value) => value.identity(),
            Self::Role(value) => value.identity(),
            Self::Start(value) => value.identity(),
            Self::Source(value) => value.identity(),
        }
    }
    fn ensure_open(&self) -> Result<(), StudioError> {
        match self {
            Self::Value(value) => value.ensure_open(),
            Self::Profiles(value) => value.ensure_open(),
            Self::Role(value) => value.ensure_open(),
            Self::Start(value) => value.ensure_open(),
            Self::Source(value) => value.ensure_open(),
        }
    }
    fn request_close(&self) {
        match self {
            Self::Value(value) => value.request_close(),
            Self::Profiles(value) => value.request_close(),
            Self::Role(value) => value.request_close(),
            Self::Start(value) => value.request_close(),
            Self::Source(value) => value.request_close(),
        }
    }
    async fn close(&self) -> FeedCloseReport {
        match self {
            Self::Value(value) => value.close().await,
            Self::Profiles(value) => value.close().await,
            Self::Role(value) => value.close().await,
            Self::Start(value) => value.close().await,
            Self::Source(value) => value.close().await,
        }
    }
}

struct State {
    closing: bool,
    identity: Option<ProductReadScopeIdentity>,
    source: Option<Arc<NativeRead>>,
    task: Option<Completion>,
    issues: Vec<FeedCloseIssue>,
    join_issue: Option<FeedCloseIssue>,
    runtime_joined: bool,
}
pub(super) struct ReadOwner {
    parent: Weak<Transport>,
    cancel: CancellationToken,
    state: Mutex<State>,
}
pub(super) struct ReadTicket {
    owner: Arc<ReadOwner>,
    ready: Option<oneshot::Receiver<Result<ProductReadScopeIdentity, StudioError>>>,
    adopted: bool,
}

impl ReadOwner {
    pub(super) fn new(parent: &Arc<Transport>) -> Arc<Self> {
        Arc::new(Self {
            parent: Arc::downgrade(parent),
            cancel: parent.cancel.child_token(),
            state: Mutex::new(State {
                closing: false,
                identity: None,
                source: None,
                task: None,
                issues: Vec::new(),
                join_issue: None,
                runtime_joined: false,
            }),
        })
    }
    pub(super) fn start(
        self: &Arc<Self>,
        runtime: StudioRuntime,
        kind: OpenReadKind,
        origin: ProductReadOrigin,
    ) -> ReadTicket {
        let (opened, ready) = oneshot::channel();
        let owner = self.clone();
        let task = tokio::spawn(async move {
            let source = match kind.open(runtime, origin).await {
                Ok(source) => Arc::new(source),
                Err(error) => {
                    owner.request_close();
                    let _ = opened.send(Err(pl_studio_runtime::studio_error_from_anyhow(error)));
                    return;
                }
            };
            let result = {
                let mut state = owner
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                state.identity = Some(source.identity());
                state.source = Some(source.clone());
                if state.closing || owner.cancel.is_cancelled() {
                    Err(tasks::cancelled())
                } else {
                    source.ensure_open().map(|()| source.identity())
                }
            };
            if opened.send(result).is_err() {
                owner.request_close();
            }
            owner.cancel.cancelled().await;
            source.request_close();
            owner.close_source(&source).await;
        });
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .task = Some(tasks::retain(task));
        ReadTicket {
            owner: self.clone(),
            ready: Some(ready),
            adopted: false,
        }
    }
    pub(super) fn matches(&self, id: &str) -> bool {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .identity
            .as_ref()
            .is_some_and(|identity| identity.scope_id == id)
    }
    pub(super) fn query<F>(
        &self,
        query: impl FnOnce(&NativeRead) -> Result<F, StudioError>,
    ) -> Result<F, StudioError> {
        self.parent
            .upgrade()
            .ok_or_else(tasks::cancelled)?
            .admit(|| {
                let state = self
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                if state.closing || self.cancel.is_cancelled() {
                    return Err(tasks::cancelled());
                }
                let source = state.source.as_ref().ok_or_else(tasks::cancelled)?;
                source.ensure_open()?;
                query(source)
            })
    }
    pub(super) fn request_close(&self) {
        let source = {
            let mut state = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            state.closing = true;
            state.source.clone()
        };
        self.cancel.cancel();
        if let Some(source) = source {
            source.request_close();
        }
    }
    pub(super) async fn close(&self) -> Vec<FeedCloseIssue> {
        self.request_close();
        let task = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .task
            .clone();
        if let Some(task) = task
            && task.await.is_err()
        {
            self.state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .join_issue
                .get_or_insert_with(|| {
                    tasks::issue(
                        "readJoinError",
                        "Configuration HTTP read task did not join",
                        CleanupRecovery::Terminal,
                    )
                });
        }
        let source = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .source
            .clone();
        if let Some(source) = source {
            self.close_source(&source).await;
        }
        self.issues()
    }
    async fn close_source(&self, source: &NativeRead) {
        let report = source.close().await;
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.runtime_joined = true;
        match report.outcome {
            FeedCloseOutcome::Clean => {
                state.source.take();
                state.issues.clear();
            }
            FeedCloseOutcome::Unresolved { issues } => state.issues = issues,
        }
    }
    pub(super) fn issues(&self) -> Vec<FeedCloseIssue> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.task.as_ref().is_some_and(tasks::failed) && state.join_issue.is_none() {
            state.join_issue = Some(tasks::issue(
                "readJoinError",
                "Configuration HTTP read task did not join",
                CleanupRecovery::Terminal,
            ));
        }
        let mut issues = state.issues.clone();
        issues.extend(state.join_issue.iter().cloned());
        issues
    }
    pub(super) fn is_finished(&self) -> bool {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.closing
            && state.task.as_ref().is_none_or(tasks::finished)
            && (state.source.is_none() || state.runtime_joined)
    }
    pub(super) fn is_clean(&self) -> bool {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.closing
            && state.source.is_none()
            && state.issues.is_empty()
            && state.join_issue.is_none()
            && state.task.as_ref().is_none_or(tasks::succeeded)
    }
}
impl ReadTicket {
    pub(super) async fn ready(&mut self) -> Result<ProductReadScopeIdentity, StudioError> {
        self.ready
            .take()
            .ok_or_else(StudioError::internal)?
            .await
            .map_err(|_| StudioError::internal())?
    }
    pub(super) fn adopt(&mut self) -> Result<(), StudioError> {
        self.owner.query(|_| Ok(()))?;
        self.adopted = true;
        Ok(())
    }
}
impl Drop for ReadTicket {
    fn drop(&mut self) {
        if !self.adopted {
            self.owner.request_close();
        }
    }
}
fn wrong_scope() -> StudioError {
    StudioError::invalid_argument(
        "This named query is not supported by the original Configuration scope kind",
    )
}
