//! One owner installs the executable catalog, model and host binding at a request boundary.
use super::*;
use crate::tool::opaque::{PreparedTools, Registration};
use std::any::Any;

/// Immutable host-owned execution resources. Core neither interprets nor persists them.
#[derive(Clone)]
pub struct RuntimeBinding(Arc<dyn Any + Send + Sync>);

impl RuntimeBinding {
    pub fn new(binding: impl Any + Send + Sync) -> Self {
        Self(Arc::new(binding))
    }

    pub fn get<T: Any>(&self) -> Option<&T> {
        self.0.downcast_ref()
    }
}

impl std::fmt::Debug for RuntimeBinding {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("RuntimeBinding")
            .finish_non_exhaustive()
    }
}

/// A read port for the same publication that contains Core's live snapshot. It cannot keep a
/// Thread running and historic snapshots do not retain host resource references.
#[derive(Debug, Clone)]
pub struct RuntimeBindingReader {
    pub(super) snapshots: watch::Receiver<super::subscription::OwnerPublication>,
    pub(super) commands: mpsc::WeakSender<super::handle::Command>,
    pub(super) authorization_dirty: Arc<std::sync::atomic::AtomicBool>,
}

impl RuntimeBindingReader {
    /// Reads the binding while its publication is pinned. The callback must be short and must
    /// not invoke an owner command or reenter this read port.
    pub fn with_binding<T: Any, R>(&self, read: impl FnOnce(Option<&T>) -> R) -> R {
        let publication = self.snapshots.borrow();
        read(publication.binding.as_ref().and_then(RuntimeBinding::get))
    }

    /// Wakes the owner after a host has synchronously revoked an existing authorization.
    pub fn authorization_changed(&self) {
        self.authorization_dirty
            .store(true, std::sync::atomic::Ordering::Release);
        if let Some(commands) = self.commands.upgrade() {
            let _ = commands.try_send(super::handle::Command::Control(
                super::mailbox::MailboxCommand::RuntimeAuthorizationChanged,
            ));
        }
    }
}

/// Live receipts for the latest installed package, independent of journal or persistence revisions.
#[derive(Debug, Clone, Default)]
pub struct RuntimeBundleState {
    pub revision: u64,
    pub installed: Option<Arc<str>>,
    pub preparing: Option<Arc<str>>,
    pub preparing_model_identity: Option<Arc<str>>,
    pub model_identity: Option<Arc<str>>,
    pub model_cleanup_failure: Option<Arc<ModelError>>,
}

/// The exact owner and base from which a candidate was prepared.
#[derive(Debug, Clone, Copy)]
pub struct RuntimeBundleBase {
    pub(super) epoch: current::RuntimeEpoch,
    pub(super) revision: u64,
    pub(super) extension_sequence: u64,
}

/// Frozen model factory and context policy. Core opens the session before installation.
#[derive(Debug, Clone)]
pub struct RuntimeModel {
    pub(super) identity: String,
    pub(super) factory: crate::model::ModelFactory,
    pub(super) preparation: Option<context_preparation::ContextPreparer>,
}

impl RuntimeModel {
    pub fn new(
        identity: String,
        factory: crate::model::ModelFactory,
        preparation: Option<context_preparation::ContextPreparer>,
    ) -> Self {
        Self {
            identity,
            factory,
            preparation,
        }
    }

    pub fn identity(&self) -> &str {
        &self.identity
    }
}

/// Replacement tools, their corresponding host binding and model-visible runtime facts.
#[derive(Debug)]
pub struct RuntimeTools {
    pub registrations: Vec<Registration>,
    pub binding: RuntimeBinding,
    pub facts: Vec<RuntimeFact>,
}

/// An optional idle application transaction installed with the same runtime package.
#[derive(Debug)]
pub struct RuntimeApplication {
    pub expected_sequence: u64,
    pub update: extensions::ApplicationUpdate,
    pub context: Option<ReplaceContext>,
}

/// A preflighted configuration awaiting model opening and installation. The host guard is
/// checked at installation and must be a synchronous, nonblocking revision check.
pub struct RuntimeBundle {
    pub base: RuntimeBundleBase,
    pub desired: Arc<str>,
    pub model: Option<RuntimeModel>,
    pub model_context_revision: Option<u64>,
    pub tools: Option<RuntimeTools>,
    pub application: Option<RuntimeApplication>,
    pub is_current: Arc<dyn Fn() -> bool + Send + Sync>,
}

impl std::fmt::Debug for RuntimeBundle {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("RuntimeBundle")
            .field("base", &self.base)
            .field("desired", &self.desired)
            .finish_non_exhaustive()
    }
}

impl RuntimeBundle {
    /// Prepares a standalone owner model using its existing tool catalog.
    pub fn model_only(
        thread: &ThreadHandle,
        snapshot: &ThreadSnapshot,
        model: RuntimeModel,
    ) -> Self {
        Self {
            base: thread.runtime_bundle_base(snapshot),
            desired: Arc::from(model.identity()),
            model: Some(model),
            model_context_revision: None,
            tools: None,
            application: None,
            is_current: Arc::new(|| true),
        }
    }

    fn current(&self) -> bool {
        std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| (self.is_current)()))
            .unwrap_or(false)
    }
}

/// The owner has accepted responsibility for this candidate. A caller may wait for the
/// installation, or continue driving the currently installed package while the candidate waits.
type InstallResult = Result<Arc<ThreadSnapshot>, Arc<ThreadError>>;

#[derive(Debug)]
pub struct RuntimeBundleReceipt(watch::Receiver<InstallState>);

#[derive(Debug, Clone)]
enum InstallState {
    Opening,
    Ready,
    Finished(InstallResult),
}

impl RuntimeBundleReceipt {
    /// Waits for mandatory model opening without waiting for old tool leases to drain.
    pub async fn prepared(&mut self) -> Result<(), Arc<ThreadError>> {
        loop {
            match self.0.borrow_and_update().clone() {
                InstallState::Opening => (),
                InstallState::Ready => return Ok(()),
                InstallState::Finished(result) => return result.map(|_| ()),
            }
            self.0
                .changed()
                .await
                .map_err(|_| Arc::new(ThreadError::Closed))?;
        }
    }

    pub async fn installed(mut self) -> InstallResult {
        loop {
            if let InstallState::Finished(result) = self.0.borrow_and_update().clone() {
                return result;
            }
            self.0
                .changed()
                .await
                .map_err(|_| Arc::new(ThreadError::Closed))?;
        }
    }
}

pub(super) struct PendingBundle {
    generation: u64,
    update: RuntimeBundle,
    tools: Option<PreparedTools>,
    opening: bool,
    model: Option<DynModelSession>,
    cancel_open: CancellationToken,
    result: watch::Sender<InstallState>,
}

impl Owner {
    pub(super) fn queue_runtime_bundle(
        &mut self,
        update: RuntimeBundle,
        registrations: Vec<Registration>,
    ) -> Result<RuntimeBundleReceipt, ThreadError> {
        let result = self.stage_runtime_bundle(update, &registrations);
        if result.is_err() {
            self.tools.retain_candidates(&registrations);
        }
        drop(registrations);
        self.publish_snapshot();
        result
    }

    fn stage_runtime_bundle(
        &mut self,
        update: RuntimeBundle,
        registrations: &[Registration],
    ) -> Result<RuntimeBundleReceipt, ThreadError> {
        self.check_runtime_base(&update)?;
        if update.desired.is_empty() || update.tools.is_none() && update.model.is_none() {
            return Err(ThreadError::InvalidIdentity);
        }
        if let Some(pending) = &self.pending_bundle
            && pending.update.desired == update.desired
            && self.check_runtime_base(&pending.update).is_ok()
        {
            let receipt = RuntimeBundleReceipt(pending.result.subscribe());
            self.tools.retain_candidates(registrations);
            return Ok(receipt);
        }
        let tools = update
            .tools
            .as_ref()
            .map(|_| PreparedTools::new(registrations))
            .transpose()?;
        if update
            .model
            .as_ref()
            .is_some_and(|model| model.identity.is_empty())
        {
            return Err(ThreadError::InvalidIdentity);
        }
        let factory = update
            .model
            .as_ref()
            .filter(|model| {
                self.state.runtime_bundle.model_identity.as_deref() != Some(model.identity.as_str())
                    || !self.model.as_ref().map_or_else(
                        || {
                            self.primary
                                .as_ref()
                                .is_some_and(|work| work.model_available)
                        },
                        DynModelSession::is_available,
                    )
            })
            .map(|model| model.factory.clone());
        let generation = self
            .bundle_generation
            .checked_add(1)
            .ok_or(ThreadError::RevisionExhausted)?;
        self.bundle_generation = generation;
        self.reject_pending_bundle(ThreadError::StaleRuntimeBundle);
        let opening = factory.is_some();
        let (result, receiver) = watch::channel(if opening {
            InstallState::Opening
        } else {
            InstallState::Ready
        });
        let cancel_open = self.interrupt.background_token();
        if let Some(factory) = factory {
            let cancel = cancel_open.clone();
            self.runtime_model_jobs += 1;
            self.maintenance.push(Box::pin(async move {
                // Opening has no cancellable model-session handle yet. Once started, let it
                // finish and return the real session to its owner even if superseded.
                let result = if cancel.is_cancelled() {
                    Err(ThreadError::Cancelled)
                } else {
                    factory
                        .open_session()
                        .await
                        .map_err(|error| ThreadError::Model(Arc::new(error)))
                };
                super::execution::MaintenanceCompletion::RuntimeModelOpened { generation, result }
            }));
        }
        self.state.runtime_bundle.preparing = Some(update.desired.clone());
        self.state.runtime_bundle.preparing_model_identity = update
            .model
            .as_ref()
            .map(|model| Arc::from(model.identity.as_str()));
        self.pending_bundle = Some(PendingBundle {
            generation,
            update,
            tools,
            opening,
            model: None,
            cancel_open,
            result,
        });
        Ok(RuntimeBundleReceipt(receiver))
    }

    fn check_runtime_base(&self, update: &RuntimeBundle) -> Result<(), ThreadError> {
        if self.interrupt.is_closing() || self.state.lifecycle != ThreadLifecycle::Open {
            return Err(ThreadError::Closed);
        }
        if update.base.epoch != self.runtime_epoch
            || update.base.revision != self.state.runtime_bundle.revision
            || update.base.extension_sequence != self.state.extension_sequence
            || !update.current()
        {
            return Err(ThreadError::StaleRuntimeBundle);
        }
        if let Some(application) = &update.application {
            if application.expected_sequence != self.state.commit_sequence {
                return Err(ThreadError::ContextConflict {
                    expected: application.expected_sequence,
                    actual: self.state.commit_sequence,
                });
            }
            self.ensure_idle()?;
        }
        if let Some(expected) = update.model_context_revision
            && self.state.context.revision != expected
        {
            return Err(ThreadError::ContextConflict {
                expected,
                actual: self.state.context.revision,
            });
        }
        Ok(())
    }

    pub(super) fn finish_runtime_model_open(
        &mut self,
        generation: u64,
        result: Result<DynModelSession, ThreadError>,
    ) {
        self.runtime_model_jobs -= 1;
        let Some(pending) = self
            .pending_bundle
            .as_mut()
            .filter(|pending| pending.generation == generation)
        else {
            if let Ok(model) = result {
                self.retire_runtime_model(model);
            }
            return;
        };
        match result {
            Ok(model) => {
                pending.opening = false;
                pending.model = Some(model);
                pending.result.send_replace(InstallState::Ready);
            }
            Err(error) => self.reject_pending_bundle(error),
        }
    }

    pub(super) fn reject_pending_bundle(&mut self, error: ThreadError) {
        if let Some(mut pending) = self.pending_bundle.take() {
            pending.cancel_open.cancel();
            if let Some(tools) = pending.tools.take() {
                tools.retire(&mut self.tools);
            }
            if let Some(model) = pending.model.take() {
                self.retire_runtime_model(model);
            }
            self.state.runtime_bundle.preparing = None;
            self.state.runtime_bundle.preparing_model_identity = None;
            self.publish_snapshot();
            pending
                .result
                .send_replace(InstallState::Finished(Err(Arc::new(error))));
        }
    }

    pub(super) fn install_ready_bundle(&mut self) {
        let Some(pending) = self.pending_bundle.as_ref() else {
            return;
        };
        if pending.opening || self.primary.is_some() {
            return;
        }
        let phase = self.active.as_ref().map(|active| &active.phase);
        if !matches!(
            phase,
            None | Some(
                super::execution::RunPhase::Starting | super::execution::RunPhase::NextStep { .. }
            )
        ) || (pending.model.is_some()
            && matches!(phase, Some(super::execution::RunPhase::NextStep { .. })))
        {
            return;
        }
        if let Err(error) = self.check_runtime_base(&pending.update) {
            self.reject_pending_bundle(error);
            return;
        }
        if let Some(tools) = pending.tools.as_ref() {
            if !tools.is_authorized() {
                self.reject_pending_bundle(ThreadError::ToolPermissionRevoked);
                return;
            }
            if self.revoked_runtime_tools && self.tools.cleanup_state().pending != 0 {
                return;
            }
            // The very same authority test protects progress, output faults and terminal
            // control. An ordinary refresh leaves the old package usable until these leases end.
            if self
                .executing_authorities
                .values()
                .any(|authority| !tools.authorizes(authority))
                || self
                    .pending
                    .values()
                    .any(|call| !tools.authorizes(&call.executor.authority()))
                || self
                    .nested_plans
                    .values()
                    .any(|scope| !scope.plan.is_authorized_by(tools))
            {
                return;
            }
        }
        let Some(revision) = self.state.runtime_bundle.revision.checked_add(1) else {
            self.reject_pending_bundle(ThreadError::RevisionExhausted);
            return;
        };
        let mut state = self.state.clone();
        let mut pending = self.pending_bundle.take().expect("ready bundle");
        let changes = (|| {
            if let Some(application) = pending.update.application.take() {
                self.stage_reconfiguration(&mut state, application.update, application.context)?;
            }
            if let Some(tools) = &pending.update.tools {
                facts::stage_facts(&mut state, tools.facts.clone())?;
            }
            Ok(())
        })();
        if let Err(error) = changes {
            self.pending_bundle = Some(pending);
            self.reject_pending_bundle(error);
            return;
        }
        if let Some(tools) = pending.tools.take() {
            self.tools.install(tools);
            state.discovered_tools = self.tools.discovery();
            self.runtime_binding = pending.update.tools.take().map(|tools| tools.binding);
            self.revoked_runtime_tools = false;
            self.retry_plan = None;
        }
        if let Some(model) = pending.model.take()
            && let Some(update) = pending.update.model.take()
        {
            if let Some(previous) = self.model.replace(model) {
                self.retire_runtime_model(previous);
            }
            state.runtime_bundle.model_identity = Some(Arc::from(update.identity.as_str()));
            self.context_preparation = update.preparation;
            self.retry_plan = None;
        }
        state.runtime_bundle.revision = revision;
        state.runtime_bundle.installed = Some(pending.update.desired);
        state.runtime_bundle.preparing = None;
        state.runtime_bundle.preparing_model_identity = None;
        self.state = state;
        let before = self.state.commit_sequence;
        let committed = self.publish();
        if self.state.commit_sequence == before {
            self.publish_snapshot();
        }
        let result = committed
            .map(|()| Arc::new(self.state.clone()))
            .map_err(Arc::new);
        pending.result.send_replace(InstallState::Finished(result));
    }

    pub(super) fn retire_revoked_runtime_tools(&mut self) -> Result<(), ThreadError> {
        if !self
            .authorization_dirty
            .swap(false, std::sync::atomic::Ordering::AcqRel)
            || !self.tools.retire_revoked()
        {
            return Ok(());
        }
        self.revoked_runtime_tools = true;
        self.retry_plan = None;
        self.state.discovered_tools = self.tools.discovery();
        let revoked = self
            .executing_authorities
            .iter()
            .filter(|(_, authority)| !authority.remains_authorized(&self.tools))
            .map(|(id, _)| id.clone())
            .collect::<Vec<_>>();
        self.revoke_stale_permissions()?;
        for id in revoked {
            self.cancel_task(&id)?;
        }
        self.publish()?;
        self.publish_snapshot();
        Ok(())
    }

    fn retire_runtime_model(&mut self, mut model: DynModelSession) {
        self.runtime_model_jobs += 1;
        self.maintenance.push(Box::pin(async move {
            let result = model.close().await;
            super::execution::MaintenanceCompletion::RetiredRuntimeModel { model, result }
        }));
    }

    pub(super) fn finish_retired_runtime_model(
        &mut self,
        model: DynModelSession,
        result: Result<(), ModelError>,
    ) {
        self.runtime_model_jobs -= 1;
        if let Err(error) = result {
            let error = Arc::new(error);
            self.state.runtime_bundle.model_cleanup_failure = Some(error.clone());
            self.retired_runtime_models.push((model, error));
            self.publish_snapshot();
        }
    }

    pub(super) fn retry_retired_runtime_models(&mut self) {
        self.state.runtime_bundle.model_cleanup_failure = None;
        for (model, _) in std::mem::take(&mut self.retired_runtime_models) {
            self.retire_runtime_model(model);
        }
    }
}
