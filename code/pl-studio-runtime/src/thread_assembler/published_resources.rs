//! Published workspace cleanup remains owned until the frozen close policy succeeds.
use super::{Registry, SessionRuntime, State, ThreadAssemblyError};
use pl_tool::collaboration::thread::WorkspaceRelease;
use std::sync::{Arc, Weak};

/// Admission is sealed only while an operation owns this guard. Durable explicit-close intent
/// belongs to the Studio checkpoint, not a process-long set of every closed identity.
#[must_use = "retain this guard until the sealed operation concludes"]
pub(crate) struct AgentOperationSeal {
    registry: Weak<Registry>,
    ids: Vec<String>,
}

/// One frozen registry closure, not a second preparation/job registry.
pub(crate) struct ArchiveScopeSeal {
    admission: AgentOperationSeal,
    members: Vec<(usize, String)>,
    identities: Vec<(String, Option<String>, String)>,
    private_ids: Vec<String>,
    cancellation: Vec<tokio_util::sync::CancellationToken>,
}

impl ArchiveScopeSeal {
    /// The caller has durably committed the complete original scope before this broadcast.
    pub(crate) fn cancel_preparations(&self) {
        for token in &self.cancellation {
            token.cancel();
        }
    }
    pub(crate) fn thread_ids(&self) -> Vec<String> {
        self.members.iter().map(|(_, id)| id.clone()).collect()
    }
    pub(crate) fn preparation_identities(
        &self,
        workspace_id: &str,
    ) -> Vec<crate::studio::store::thread_preparation::PreparationIdentity> {
        self.identities
            .iter()
            .filter(|(id, _, _)| self.private_ids.contains(id))
            .map(|(thread_id, parent_id, root_id)| {
                crate::studio::store::thread_preparation::PreparationIdentity {
                    thread_id: thread_id.clone(),
                    workspace_id: workspace_id.into(),
                    parent_id: parent_id.clone(),
                    root_id: root_id.clone(),
                }
            })
            .collect()
    }
}

impl Drop for AgentOperationSeal {
    fn drop(&mut self) {
        let Some(registry) = self.registry.upgrade() else {
            return;
        };
        let mut state = registry.state();
        for id in &self.ids {
            if let Some(count) = state.sealed_agents.get_mut(id) {
                *count -= 1;
                if *count == 0 {
                    state.sealed_agents.remove(id);
                }
            }
        }
    }
}

fn seal(registry: &Arc<Registry>, state: &mut State, ids: Vec<String>) -> AgentOperationSeal {
    for id in &ids {
        *state.sealed_agents.entry(id.clone()).or_default() += 1;
    }
    AgentOperationSeal {
        registry: Arc::downgrade(registry),
        ids,
    }
}

impl SessionRuntime {
    /// Capture all admitted owners and seal their admission in the same short registry lock.
    /// No cancellation or permit wait precedes the caller's complete durable scope commit.
    pub(crate) fn seal_archive_scope(
        &self,
        roots: &[String],
    ) -> Result<ArchiveScopeSeal, ThreadAssemblyError> {
        use std::collections::{BTreeMap, BTreeSet};
        let scope = {
            let mut state = self.0.state();
            let mut parents = BTreeMap::<String, Option<String>>::new();
            let mut observe = |id: &str, parent: Option<&str>| {
                let parent = parent.map(str::to_owned);
                if let Some(previous) = parents.insert(id.to_owned(), parent.clone())
                    && previous != parent
                {
                    return Err(ThreadAssemblyError::Identity(id.to_owned()));
                }
                Ok(())
            };
            for (id, entry) in &state.entries {
                observe(id, super::State::membership_parent(&state.by_agent, entry))?;
            }
            for (id, entry) in &state.creating {
                observe(id, entry.parent_id.as_deref())?;
            }
            for (id, entry) in &state.preparing_children {
                observe(id, Some(&entry.parent))?;
            }
            for (id, entry) in &state.unpublished_children {
                observe(id, Some(&entry.parent))?;
            }
            let roots = roots.iter().cloned().collect::<BTreeSet<_>>();
            for root in &roots {
                if root.is_empty() || parents.get(root).is_some_and(Option::is_some) {
                    return Err(ThreadAssemblyError::Identity(root.clone()));
                }
            }
            let mut depths = roots
                .iter()
                .map(|id| (id.clone(), 0usize))
                .collect::<BTreeMap<_, _>>();
            loop {
                let mut added = false;
                for (id, parent) in &parents {
                    if depths.contains_key(id) {
                        continue;
                    }
                    if let Some(depth) = parent
                        .as_ref()
                        .and_then(|parent| depths.get(parent))
                        .copied()
                    {
                        depths.insert(id.clone(), depth + 1);
                        added = true;
                    }
                }
                if !added {
                    break;
                }
            }
            let ids = depths.keys().cloned().collect::<Vec<_>>();
            let private_ids = ids
                .iter()
                .filter(|id| {
                    state.creating.get(*id).is_some_and(|preparation| {
                        matches!(
                            preparation.resources,
                            crate::session::PreparedResources::Native(_)
                        )
                    }) || state.preparing_children.contains_key(*id)
                        || state.unpublished_children.contains_key(*id)
                })
                .cloned()
                .collect();
            let mut identities = Vec::new();
            for id in &ids {
                let mut root = id;
                while !roots.contains(root) {
                    root = parents
                        .get(root)
                        .and_then(Option::as_ref)
                        .ok_or_else(|| ThreadAssemblyError::Identity(id.clone()))?;
                }
                identities.push((id.clone(), parents.get(id).cloned().flatten(), root.clone()));
            }
            for id in &ids {
                if let Some(pending) = state.unpublished_children.get(id)
                    && *pending
                        .retirement
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner)
                        == Some(WorkspaceRelease::Cleanup)
                {
                    return Err(ThreadAssemblyError::Preparing(id.clone()));
                }
            }
            for id in &ids {
                if let Some(pending) = state.unpublished_children.get(id) {
                    *pending
                        .retirement
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner) =
                        Some(WorkspaceRelease::Preserve);
                }
            }
            let cancellation = state
                .creating
                .iter()
                .filter(|(id, _)| depths.contains_key(*id))
                .map(|(_, entry)| entry.cancellation.clone())
                .chain(
                    state
                        .preparing_children
                        .iter()
                        .filter(|(id, _)| depths.contains_key(*id))
                        .map(|(_, entry)| entry.cancellation.clone()),
                )
                .collect::<Vec<_>>();
            let mut members = depths
                .into_iter()
                .map(|(id, depth)| (depth, id))
                .collect::<Vec<_>>();
            members.sort_by(|left, right| right.0.cmp(&left.0).then_with(|| left.1.cmp(&right.1)));
            ArchiveScopeSeal {
                admission: seal(&self.0, &mut state, ids),
                members,
                identities,
                private_ids,
                cancellation,
            }
        };
        Ok(scope)
    }

    /// Joins admitted permits/preparations, then serially disposes retained unpublished owners.
    /// The caller first interrupts visible work and retains `scope` until directory publication.
    pub(crate) async fn drain_archive_preparations(
        &self,
        scope: &ArchiveScopeSeal,
    ) -> Result<(), ThreadAssemblyError> {
        if !scope
            .admission
            .registry
            .upgrade()
            .is_some_and(|registry| Arc::ptr_eq(&registry, &self.0))
        {
            return Err(ThreadAssemblyError::Identity(
                "archive registry changed".into(),
            ));
        }
        // Never hold a child permit while awaiting its parent's spawn operation: that operation
        // can be waiting for the same child's retained disposal.
        for (_, id) in &scope.members {
            drop(self.agent_operation(id).await);
        }
        loop {
            let changed = self.0.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            let preparing = {
                let state = self.0.state();
                scope.members.iter().any(|(_, id)| {
                    state.creating.contains_key(id) || state.preparing_children.contains_key(id)
                })
            };
            if !preparing {
                break;
            }
            changed.await;
        }
        for (_, id) in &scope.members {
            self.discard_unpublished_child(id).await?;
            let acp = self
                .0
                .state()
                .failed_preparations
                .get(id)
                .is_some_and(|failed| {
                    matches!(failed.resources, crate::session::PreparedResources::Acp(_))
                });
            if acp {
                self.close_failed_preparation(id).await?;
            }
        }
        Ok(())
    }

    /// Caller owns this identity's operation permit. Tree operations seal roots before children.
    pub(crate) fn seal_agent_operation(&self, id: &str) -> AgentOperationSeal {
        seal(&self.0, &mut self.0.state(), vec![id.to_owned()])
    }

    pub(crate) async fn seal_agent_operations(&self, ids: &[String]) -> AgentOperationSeal {
        let mut ids = ids.to_vec();
        ids.sort();
        ids.dedup();
        let mut permits = Vec::with_capacity(ids.len());
        for id in &ids {
            permits.push(self.agent_operation(id).await);
        }
        seal(&self.0, &mut self.0.state(), ids)
    }

    pub(super) async fn seal_agent_close(
        &self,
        targets: &[(usize, String)],
        disposition: WorkspaceRelease,
    ) -> Result<AgentOperationSeal, ThreadAssemblyError> {
        let mut ids = targets.iter().map(|(_, id)| id).collect::<Vec<_>>();
        ids.sort();
        ids.dedup();
        let close_seal = {
            let mut state = self.0.state();
            if let Some(id) = ids
                .iter()
                .find(|id| state.sealed_agents.contains_key(id.as_str()))
            {
                return Err(ThreadAssemblyError::CloseDisposition((*id).clone()));
            }
            seal(
                &self.0,
                &mut state,
                ids.iter().map(|id| (*id).clone()).collect(),
            )
        };
        let mut permits = Vec::new();
        for id in &ids {
            permits.push(self.agent_operation(id).await);
        }
        let mut state = self.0.state();
        for (_, id) in targets {
            if let Some(entry) = state.entries.get(id)
                && entry
                    .native()?
                    .workspace_disposition
                    .is_some_and(|current| current != disposition)
            {
                return Err(ThreadAssemblyError::CloseDisposition(id.clone()));
            }
        }
        let standalone = state.agent_services.is_none();
        for (_, id) in targets {
            if let Some(entry) = state.entries.get_mut(id) {
                // Standalone assemblers have no Studio persistence contract. Studio seals only
                // admission here: publishing Cleanup before a successful flush would let ordinary
                // shutdown consume an uncommitted request after the owned close fails.
                if standalone {
                    if entry.native()?.workspace_disposition != Some(disposition) {
                        entry.native_mut()?.published_resources_closed = false;
                    }
                    entry.native_mut()?.workspace_disposition = Some(disposition);
                    entry.native_mut()?.ready = false;
                }
            }
        }
        Ok(close_seal)
    }

    /// Caller holds this identity's operation permit and has just successfully flushed its close
    /// intent. An in-memory marker after a failed flush never authorizes publishing a new policy.
    pub(super) fn freeze_agent_close_disposition(
        &self,
        id: &str,
        disposition: WorkspaceRelease,
    ) -> Result<(), ThreadAssemblyError> {
        let mut state = self.0.state();
        let entry = state
            .entries
            .get_mut(id)
            .ok_or_else(|| ThreadAssemblyError::Identity(id.to_owned()))?;
        if let Some(current) = entry.native()?.workspace_disposition {
            if current != disposition {
                return Err(ThreadAssemblyError::CloseDisposition(id.to_owned()));
            }
        } else {
            // A previous default Preserve is not an explicit policy; first durable Cleanup must
            // still run even if that ordinary resource retirement had already completed.
            entry.native_mut()?.published_resources_closed = false;
            entry.native_mut()?.workspace_disposition = Some(disposition);
        }
        Ok(())
    }

    pub(super) async fn close_published_resources(
        &self,
        id: &str,
        incarnation: &Arc<()>,
    ) -> Result<(), ThreadAssemblyError> {
        let cleanup = {
            let state = self.0.state();
            if state.unpublished_children.contains_key(id) {
                return Ok(());
            }
            state
                .entries
                .get(id)
                .filter(|entry| {
                    entry.native().is_ok_and(|native| {
                        entry.identity.parent_agent_id.is_some()
                            && Arc::ptr_eq(&native.incarnation, incarnation)
                    })
                })
                .and_then(|entry| {
                    let native = entry.native().ok()?;
                    Some(native.cleanup.clone())
                })
        };
        let Some(cleanup) = cleanup else {
            return Ok(());
        };
        let _permit = cleanup.acquire().await;
        let resource = {
            let state = self.0.state();
            state
                .entries
                .get(id)
                .filter(|entry| {
                    entry.native().is_ok_and(|native| {
                        !native.published_resources_closed
                            && Arc::ptr_eq(&native.incarnation, incarnation)
                    })
                })
                .and_then(|entry| {
                    let disposition = entry
                        .native()
                        .ok()?
                        .workspace_disposition
                        .unwrap_or_default();
                    state
                        .child_factory
                        .clone()
                        .map(|factory| (factory, disposition))
                })
        };
        if let Some((factory, disposition)) = resource {
            factory.close_published(id, disposition).await?;
            if let Some(entry) = self.0.state().entries.get_mut(id)
                && Arc::ptr_eq(&entry.native()?.incarnation, incarnation)
            {
                entry.native_mut()?.published_resources_closed = true;
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod archive_scope_tests {
    //! Deterministic registry/owner interleavings; no model, real user workspace or remote endpoint.
    use super::*;
    use crate::thread_assembler::{
        ChildThreadRequest, EntryPurpose, Preparation, StudioChildFactory, StudioThreadSpec,
        child_resources::{UnpublishedChild, WorkspacePreparationOwner},
        children::{ChildFactory, PreparingChild},
    };
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
    use tokio_util::sync::CancellationToken;

    #[test]
    fn contradictory_archive_parentage_fails_before_sealing_or_cancelling_any_owner() {
        let owner = SessionRuntime::default();
        let cancellation = CancellationToken::new();
        {
            let mut state = owner.0.state();
            state.creating.insert(
                "child".into(),
                Preparation {
                    resources: crate::session::PreparedResources::Native(Arc::new(
                        crate::session::NativeResources::default(),
                    )),
                    identity: None,
                    settlement: None,
                    purpose: None,
                    parent_id: Some("root".into()),
                    cancellation: cancellation.clone(),
                    result: None,
                },
            );
            state.preparing_children.insert(
                "child".into(),
                PreparingChild {
                    parent: "another-root".into(),
                    cancellation: cancellation.clone(),
                },
            );
        }
        assert!(matches!(
            owner.seal_archive_scope(&["root".into()]),
            Err(ThreadAssemblyError::Identity(_))
        ));
        assert!(!cancellation.is_cancelled());
        assert!(owner.0.state().sealed_agents.is_empty());
    }

    #[tokio::test]
    async fn archive_seals_and_cancels_before_waiting_on_a_preparer_owned_root_permit() {
        let owner = SessionRuntime::default();
        let reservation = owner.reserve("root", None).unwrap();
        let unrelated = owner.reserve("unrelated", None).unwrap();
        let root_cancel = owner.0.state().creating["root"].cancellation.clone();
        let unrelated_cancel = owner.0.state().creating["unrelated"].cancellation.clone();
        let permit = owner.agent_operation("root").await;
        let scope = owner.seal_archive_scope(&["root".into()]).unwrap();
        assert!(
            !root_cancel.is_cancelled(),
            "seal must not cancel before durable scope commit"
        );
        scope.cancel_preparations();
        assert!(
            root_cancel.is_cancelled(),
            "broadcast must precede the permit wait"
        );
        assert!(!unrelated_cancel.is_cancelled());
        assert!(matches!(
            owner.reserve("late", Some("root")),
            Err(ThreadAssemblyError::Closed)
        ));
        {
            let drain = owner.drain_archive_preparations(&scope);
            tokio::pin!(drain);
            assert!(futures::poll!(&mut drain).is_pending());
            drop(permit);
            assert!(
                futures::poll!(&mut drain).is_pending(),
                "the permit alone is not preparation completion"
            );
            drop(reservation);
            tokio::time::timeout(std::time::Duration::from_secs(2), &mut drain)
                .await
                .unwrap()
                .unwrap();
        }
        drop(scope);
        assert!(
            owner.reserve("root", None).is_ok(),
            "RAII admission must not become a permanent close"
        );
        drop(unrelated);
    }

    #[derive(Debug)]
    struct Disposal {
        fail: Arc<AtomicBool>,
        calls: Arc<AtomicUsize>,
        resource: std::path::PathBuf,
        gate: Option<(
            tokio::sync::watch::Sender<bool>,
            Arc<tokio::sync::Semaphore>,
        )>,
    }

    impl StudioChildFactory for Disposal {
        type Admission = ();

        async fn admit(
            &self,
            _: &str,
            _: pl_protocol::DelegationSettings,
            _: Option<pl_protocol::studio::NewThreadModelRoute>,
        ) -> Result<(), ThreadAssemblyError> {
            Ok(())
        }

        async fn prepare(
            &self,
            _: ChildThreadRequest,
            _: (),
        ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
            Err(ThreadAssemblyError::Closed)
        }
        async fn discard_unpublished(
            &self,
            _: &str,
            _: Option<&crate::studio::WorkspaceUsageLease>,
            _: pl_tool::collaboration::thread::WorkspaceRelease,
        ) -> Result<(), ThreadAssemblyError> {
            self.calls.fetch_add(1, Ordering::SeqCst);
            if let Some((entered, release)) = &self.gate {
                entered.send_replace(true);
                release.acquire().await.unwrap().forget();
            }
            if self.fail.load(Ordering::SeqCst) {
                return Err(ThreadAssemblyError::Resource {
                    operation: "injected unpublished disposal failure",
                    source: Box::new(std::io::Error::other("disposal failed")),
                });
            }
            tokio::fs::remove_file(&self.resource)
                .await
                .map_err(|source| ThreadAssemblyError::Resource {
                    operation: "dispose isolated prepared resource",
                    source: Box::new(source),
                })
        }
    }

    #[tokio::test]
    async fn archive_closure_keeps_unpublished_resources_until_the_real_disposal_ack_and_retry() {
        let temp = tempfile::tempdir().unwrap();
        let resource = temp.path().join("prepared-resource");
        tokio::fs::write(&resource, b"still owned").await.unwrap();
        let owner = SessionRuntime::default();
        let fail = Arc::new(AtomicBool::new(true));
        let calls = Arc::new(AtomicUsize::new(0));
        let preparation_cancel = CancellationToken::new();
        let child_cancel = CancellationToken::new();
        {
            let mut state = owner.0.state();
            state.creating.insert(
                "creating-child".into(),
                Preparation {
                    resources: crate::session::PreparedResources::Native(Arc::new(
                        crate::session::NativeResources::default(),
                    )),
                    identity: None,
                    settlement: None,
                    purpose: None,
                    parent_id: Some("root".into()),
                    cancellation: preparation_cancel.clone(),
                    result: None,
                },
            );
            state.preparing_children.insert(
                "unpublished-grandchild".into(),
                PreparingChild {
                    parent: "creating-child".into(),
                    cancellation: child_cancel.clone(),
                },
            );
            state.unpublished_children.insert(
                "unpublished-grandchild".into(),
                UnpublishedChild {
                    retirement: Default::default(),
                    workspace: WorkspacePreparationOwner::default(),
                    parent: "creating-child".into(),
                    cleanup: Default::default(),
                    disposal: Default::default(),
                    factory: ChildFactory::new(Disposal {
                        fail: fail.clone(),
                        calls: calls.clone(),
                        resource: resource.clone(),
                        gate: None,
                    }),
                },
            );
        }
        let scope = owner.seal_archive_scope(&["root".into()]).unwrap();
        scope.cancel_preparations();
        assert!(preparation_cancel.is_cancelled() && child_cancel.is_cancelled());
        assert_eq!(
            scope.thread_ids(),
            vec!["unpublished-grandchild", "creating-child", "root"]
        );
        let drain = owner.drain_archive_preparations(&scope);
        tokio::pin!(drain);
        assert!(futures::poll!(&mut drain).is_pending());
        {
            let mut state = owner.0.state();
            state.creating.remove("creating-child");
            state.preparing_children.remove("unpublished-grandchild");
        }
        owner.0.changed.notify_waiters();
        assert!(drain.await.is_err());
        assert!(resource.exists());
        assert!(
            owner
                .0
                .state()
                .unpublished_children
                .contains_key("unpublished-grandchild")
        );
        fail.store(false, Ordering::SeqCst);
        owner.drain_archive_preparations(&scope).await.unwrap();
        assert!(!resource.exists());
        assert!(
            !owner
                .0
                .state()
                .unpublished_children
                .contains_key("unpublished-grandchild")
        );
        assert_eq!(calls.load(Ordering::SeqCst), 2);
    }

    #[tokio::test]
    async fn archive_seal_racing_publication_cannot_release_the_unpublished_owner() {
        let owner = SessionRuntime::default();
        let temp = tempfile::tempdir().unwrap();
        owner.install_explicit_activation(crate::thread_assembler::ThreadActivation::native_test(
            "root", None,
        ));
        owner
            .assemble(crate::thread_assembler::archive_test_spec(
                "root".into(),
                None,
                temp.path(),
            ))
            .await
            .unwrap();
        let resource = temp.path().join("resource");
        tokio::fs::write(&resource, b"owned").await.unwrap();
        let child =
            pl_core::thread::ThreadHandle::resume_without_model("child".into(), None).unwrap();
        let calls = Arc::new(AtomicUsize::new(0));
        let activation =
            crate::thread_assembler::ThreadActivation::native_test("child", Some("root"));
        {
            let mut state = owner.0.state();
            state.insert_entry(
                "child".into(),
                crate::session::AgentInstance {
                    identity: activation.agent,
                    binding: activation.binding,
                    runtime: crate::session::AgentRuntime::Native(Box::new(
                        crate::session::NativeThreadRuntime {
                            resources: Arc::new(crate::session::NativeResources::default()),
                            purpose: EntryPurpose::Execution,
                            workspace_usage: None,
                            close_storage: None,
                            published_resources_closed: false,
                            workspace_disposition: None,
                            cleanup: Default::default(),
                            execution: pl_core::thread::input::InputDriverOptions {
                                max_model_steps: pl_core::thread::ModelStepLimit::Limited(
                                    std::num::NonZeroU32::new(1).unwrap(),
                                ),
                            },
                            incarnation: Arc::new(()),
                            parent_id: Some("root".into()),
                            ready: false,
                            thread: child,
                        },
                    )),
                },
            );
            state.unpublished_children.insert(
                "child".into(),
                UnpublishedChild {
                    retirement: Default::default(),
                    workspace: Default::default(),
                    parent: "root".into(),
                    cleanup: Default::default(),
                    disposal: Default::default(),
                    factory: ChildFactory::new(Disposal {
                        fail: Arc::new(AtomicBool::new(false)),
                        calls: calls.clone(),
                        resource: resource.clone(),
                        gate: None,
                    }),
                },
            );
        }
        let scope = owner.seal_archive_scope(&["root".into()]).unwrap();
        assert!(matches!(
            owner.publish_child_resources("child"),
            Err(ThreadAssemblyError::Closed)
        ));
        assert!(owner.0.state().unpublished_children.contains_key("child"));
        owner.drain_archive_preparations(&scope).await.unwrap();
        assert!(!owner.0.state().entries.contains_key("child"));
        assert!(!resource.exists());
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        drop(scope);
        owner.close("root").await.unwrap();
    }

    #[tokio::test]
    async fn cancelled_archive_waiter_rejoins_the_original_unpublished_disposal() {
        let owner = SessionRuntime::default();
        let temp = tempfile::tempdir().unwrap();
        let resource = temp.path().join("resource");
        tokio::fs::write(&resource, b"owned").await.unwrap();
        let calls = Arc::new(AtomicUsize::new(0));
        let (entered, mut observed) = tokio::sync::watch::channel(false);
        let release = Arc::new(tokio::sync::Semaphore::new(0));
        owner.0.state().unpublished_children.insert(
            "child".into(),
            UnpublishedChild {
                retirement: Default::default(),
                workspace: Default::default(),
                parent: "root".into(),
                cleanup: Default::default(),
                disposal: Default::default(),
                factory: ChildFactory::new(Disposal {
                    fail: Arc::new(AtomicBool::new(false)),
                    calls: calls.clone(),
                    resource: resource.clone(),
                    gate: Some((entered, release.clone())),
                }),
            },
        );
        let scope = owner.seal_archive_scope(&["root".into()]).unwrap();
        let caller = owner.clone();
        let waiter = tokio::spawn(async move { caller.drain_archive_preparations(&scope).await });
        while !*observed.borrow_and_update() {
            observed.changed().await.unwrap();
        }
        waiter.abort();
        assert!(waiter.await.unwrap_err().is_cancelled());
        assert!(resource.exists());
        assert!(owner.0.state().unpublished_children.contains_key("child"));
        let retry_scope = owner.seal_archive_scope(&["root".into()]).unwrap();
        let retry = owner.drain_archive_preparations(&retry_scope);
        tokio::pin!(retry);
        assert!(futures::poll!(&mut retry).is_pending());
        release.add_permits(1);
        retry.await.unwrap();
        assert!(!resource.exists());
        assert_eq!(
            calls.load(Ordering::SeqCst),
            1,
            "retry joins, not restarts, the retained producer"
        );
    }
}
