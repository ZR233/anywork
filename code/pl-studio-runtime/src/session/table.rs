//! 应用拥有活动会话代次；成员资源只由各自会话登记。
use std::collections::{BTreeMap, BTreeSet};
use std::sync::{Arc, Condvar, Mutex};

use crate::SessionId;
use pl_core::thread::ThreadHandle;

use super::{SessionPhase, SessionRuntime};
use crate::thread_assembler::{InstallerSlots, ThreadAssemblyError, WorkspaceRecoveryPublisher};

pub(crate) type SessionInstaller =
    Arc<dyn Fn(&SessionRuntime) -> Result<(), ThreadAssemblyError> + Send + Sync>;

#[derive(Clone, Default)]
pub(crate) struct SessionTable(Arc<Mutex<TableState>>);
#[derive(Clone, Default)]
pub(crate) struct WeakSessionTable(std::sync::Weak<Mutex<TableState>>);
impl WeakSessionTable {
    pub(crate) fn upgrade(&self) -> Option<SessionTable> {
        self.0.upgrade().map(SessionTable)
    }
}

#[derive(Default)]
struct TableState {
    sessions: BTreeMap<SessionId, SessionRuntime>,
    installers: Vec<SessionInstaller>,
    inflight: BTreeMap<SessionId, InFlight>,
    closing: bool,
}

struct InFlight {
    session: SessionRuntime,
    owner: std::thread::ThreadId,
    slot: Arc<InFlightSlot>,
}

/// Completion of one materialize attempt. Waiters block here, never on `TableState`.
struct InFlightSlot {
    settled: Mutex<bool>,
    cvar: Condvar,
}

impl InFlightSlot {
    fn new() -> Arc<Self> {
        Arc::new(Self {
            settled: Mutex::new(false),
            cvar: Condvar::new(),
        })
    }

    fn finish(&self) {
        let mut settled = self
            .settled
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        *settled = true;
        self.cvar.notify_all();
    }

    fn wait(&self) {
        let mut settled = self
            .settled
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        while !*settled {
            settled = self
                .cvar
                .wait(settled)
                .unwrap_or_else(std::sync::PoisonError::into_inner);
        }
    }
}

impl SessionTable {
    pub(crate) fn downgrade(&self) -> WeakSessionTable {
        WeakSessionTable(Arc::downgrade(&self.0))
    }
    pub(crate) fn new() -> Self {
        Self::default()
    }

    pub(crate) fn get(&self, id: &SessionId) -> Option<SessionRuntime> {
        self.state().sessions.get(id).cloned()
    }

    /// 代次安装与应用关闭共用同步边界；只有 Closed 才能被新代次替换。
    ///
    /// Installer 回调不持有 `TableState`。同线程重入同一代次直接拿到正在安装的会话，
    /// 不等待自己要发布的结果；其他线程只等该代次自己的完成槽。
    pub(crate) fn materialize(
        &self,
        id: &SessionId,
    ) -> Result<SessionRuntime, ThreadAssemblyError> {
        loop {
            let mut state = self.state();
            if state.closing {
                return Err(ThreadAssemblyError::Closed);
            }
            if let Some(existing) = state.sessions.get(id) {
                match existing.phase() {
                    SessionPhase::Open => return Ok(existing.clone()),
                    SessionPhase::Closing => return Err(ThreadAssemblyError::Closed),
                    SessionPhase::Closed => {}
                }
            }
            if let Some(flight) = state.inflight.get(id) {
                if flight.owner == std::thread::current().id() {
                    return Ok(flight.session.clone());
                }
                let slot = Arc::clone(&flight.slot);
                drop(state);
                slot.wait();
                continue;
            }
            let created = SessionRuntime::open(id.clone());
            let slot = InFlightSlot::new();
            state.inflight.insert(
                id.clone(),
                InFlight {
                    session: created.clone(),
                    owner: std::thread::current().id(),
                    slot: Arc::clone(&slot),
                },
            );
            drop(state);
            return self.finish_materialize(id, created, slot);
        }
    }

    fn finish_materialize(
        &self,
        id: &SessionId,
        created: SessionRuntime,
        slot: Arc<InFlightSlot>,
    ) -> Result<SessionRuntime, ThreadAssemblyError> {
        let mut applied = 0usize;
        let published = loop {
            let batch = {
                let state = self.state();
                if state.closing {
                    break false;
                }
                if applied >= state.installers.len() {
                    // Publish under the same lock that observed the installer list, so a
                    // concurrent push cannot register an installer this generation skips.
                    let mut state = state;
                    state.sessions.insert(id.clone(), created.clone());
                    state.inflight.remove(id);
                    drop(state);
                    slot.finish();
                    return Ok(created);
                }
                state.installers[applied..].to_vec()
            };
            for installer in batch {
                if let Err(error) = installer(&created) {
                    self.abandon_materialize(id, &slot);
                    return Err(error);
                }
                applied += 1;
            }
        };
        let _ = published;
        self.abandon_materialize(id, &slot);
        Err(ThreadAssemblyError::Closed)
    }

    fn abandon_materialize(&self, id: &SessionId, slot: &InFlightSlot) {
        let mut state = self.state();
        state.inflight.remove(id);
        drop(state);
        slot.finish();
    }

    pub(crate) fn push_installer(
        &self,
        installer: SessionInstaller,
    ) -> Result<(), ThreadAssemblyError> {
        let mut applied = Vec::new();
        loop {
            let targets = {
                let state = self.state();
                if state.closing {
                    drop(state);
                    restore_installer_slots(&applied);
                    return Err(ThreadAssemblyError::Closed);
                }
                let seen = applied_ids(&applied);
                state
                    .sessions
                    .values()
                    .filter(|session| {
                        session.phase() != SessionPhase::Closed && !seen.contains(session.id())
                    })
                    .cloned()
                    .collect::<Vec<_>>()
            };
            if targets.is_empty() {
                let mut state = self.state();
                if state.closing {
                    drop(state);
                    restore_installer_slots(&applied);
                    return Err(ThreadAssemblyError::Closed);
                }
                let seen = applied_ids(&applied);
                let missed = state.sessions.values().any(|session| {
                    session.phase() != SessionPhase::Closed && !seen.contains(session.id())
                });
                if missed {
                    continue;
                }
                state.installers.push(installer);
                return Ok(());
            }
            for session in targets {
                let slots = session.installer_slots();
                if let Err(error) = installer(&session) {
                    session.restore_installer_slots(slots);
                    restore_installer_slots(&applied);
                    return Err(error);
                }
                applied.push((session, slots));
            }
        }
    }

    pub(crate) fn install_workspace_recovery(
        &self,
        publisher: WorkspaceRecoveryPublisher,
    ) -> Result<(), ThreadAssemblyError> {
        self.push_installer(Arc::new(move |session| {
            session.set_workspace_recovery(Some(publisher.clone()))
        }))
    }

    pub(crate) fn holding(&self, thread_id: &str) -> Option<SessionRuntime> {
        self.resident_sessions()
            .into_iter()
            .find(|session| session.hosts(thread_id))
    }

    pub(crate) fn observed_threads(&self) -> Vec<(String, ThreadHandle)> {
        self.resident_sessions()
            .into_iter()
            .flat_map(|session| session.observed_threads())
            .collect()
    }

    /// 同步封闭物化入口，然后并行加入会话自己持有的关闭任务。
    pub(crate) async fn join_closes(&self) -> Vec<(String, Arc<ThreadAssemblyError>)> {
        let sessions = self.begin_close();
        futures::future::join_all(
            sessions
                .into_iter()
                .map(|session| async move { session.close_session().await }),
        )
        .await
        .into_iter()
        .flat_map(|group| group.iter().cloned())
        .collect()
    }

    fn begin_close(&self) -> Vec<SessionRuntime> {
        let mut state = self.state();
        state.closing = true;
        let current = std::thread::current().id();
        loop {
            let foreign = state
                .inflight
                .values()
                .filter(|flight| flight.owner != current)
                .map(|flight| Arc::clone(&flight.slot))
                .collect::<Vec<_>>();
            if foreign.is_empty() {
                return state.sessions.values().cloned().collect();
            }
            drop(state);
            for slot in foreign {
                slot.wait();
            }
            state = self.state();
        }
    }

    pub(crate) fn resident_sessions(&self) -> Vec<SessionRuntime> {
        self.state().sessions.values().cloned().collect()
    }

    pub(crate) async fn resume_agent_closes(&self) -> anyhow::Result<()> {
        let mut failures = Vec::new();
        for session in self.resident_sessions() {
            if let Err(error) = session.resume_agent_closes().await {
                failures.push(format!("{}: {error:#}", session.id().as_str()));
            }
        }
        if failures.is_empty() {
            Ok(())
        } else {
            Err(anyhow::anyhow!(failures.join("\n")))
        }
    }

    fn state(&self) -> std::sync::MutexGuard<'_, TableState> {
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }
}

fn applied_ids(applied: &[(SessionRuntime, InstallerSlots)]) -> BTreeSet<SessionId> {
    applied
        .iter()
        .map(|(session, _)| session.id().clone())
        .collect()
}

fn restore_installer_slots(applied: &[(SessionRuntime, InstallerSlots)]) {
    for (session, slots) in applied {
        session.restore_installer_slots(slots.clone());
    }
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
    use std::sync::{Arc, mpsc};
    use std::time::Duration;

    use super::*;

    fn session_id(value: &str) -> SessionId {
        SessionId::new(value).expect("valid session id")
    }

    fn install_observation(session: &SessionRuntime) -> Result<(), ThreadAssemblyError> {
        use futures::FutureExt;
        session.observe_assembly(
            |_, _, _| {},
            |_, _| async { Ok(()) }.boxed(),
            None,
            |_, _, _| async { Ok(()) }.boxed(),
            |_| async { Ok(()) }.boxed(),
        )
    }

    #[test]
    fn installer_reentry_returns_the_inflight_generation_without_deadlock() {
        let table = SessionTable::new();
        let id = session_id("reenter");
        let other = session_id("other");
        let probed = Arc::new(AtomicBool::new(false));
        let table_for_installer = table.clone();
        let probed_for_installer = Arc::clone(&probed);
        let other_for_installer = other.clone();
        table
            .push_installer(Arc::new(move |session| {
                if probed_for_installer.swap(true, Ordering::SeqCst) {
                    return Ok(());
                }
                let again = table_for_installer.materialize(session.id())?;
                assert!(
                    Arc::ptr_eq(&again.0, &session.0),
                    "same-thread reentry must observe the generation being installed"
                );
                let created = table_for_installer.materialize(&other_for_installer)?;
                assert_eq!(created.id().as_str(), other_for_installer.as_str());
                table_for_installer.push_installer(Arc::new(|_| Ok(())))?;
                Ok(())
            }))
            .unwrap();
        let (done_tx, done_rx) = mpsc::channel();
        let table_for_thread = table.clone();
        let id_for_thread = id.clone();
        std::thread::spawn(move || {
            done_tx
                .send(table_for_thread.materialize(&id_for_thread).is_ok())
                .ok();
        });
        assert_eq!(
            done_rx.recv_timeout(Duration::from_secs(2)),
            Ok(true),
            "installer reentry deadlocked"
        );
        assert!(probed.load(Ordering::SeqCst));
        assert!(table.get(&other).is_some());
    }

    #[test]
    fn failed_installer_can_be_retried_and_does_not_publish_the_generation() {
        let table = SessionTable::new();
        let id = session_id("retry");
        let attempts = Arc::new(AtomicUsize::new(0));
        let attempts_for_installer = Arc::clone(&attempts);
        let installer = Arc::new(move |_session: &SessionRuntime| {
            if attempts_for_installer.fetch_add(1, Ordering::SeqCst) == 0 {
                Err(ThreadAssemblyError::Closed)
            } else {
                Ok(())
            }
        });
        table.push_installer(Arc::clone(&installer)).unwrap();
        assert!(table.materialize(&id).is_err());
        assert!(table.get(&id).is_none());
        assert!(table.materialize(&id).is_ok());
        assert_eq!(table.get(&id).unwrap().phase(), SessionPhase::Open);
        assert_eq!(attempts.load(Ordering::SeqCst), 2);
    }

    #[test]
    fn closing_generation_is_not_reused() {
        let table = SessionTable::new();
        let id = session_id("closing");
        let session = table.materialize(&id).unwrap();
        session.test_enter_closing();
        assert!(matches!(
            table.materialize(&id),
            Err(ThreadAssemblyError::Closed)
        ));
        assert_eq!(table.get(&id).unwrap().phase(), SessionPhase::Closing);
    }

    #[tokio::test]
    async fn closed_generation_can_be_replaced() {
        let table = SessionTable::new();
        let id = session_id("replaced");
        let first = table.materialize(&id).unwrap();
        assert!(first.close_session().await.is_empty());
        assert_eq!(first.phase(), SessionPhase::Closed);
        let second = table.materialize(&id).unwrap();
        assert_eq!(second.phase(), SessionPhase::Open);
        assert!(!Arc::ptr_eq(&first.0, &second.0));
    }

    #[test]
    fn failed_push_restores_sessions_and_is_not_registered() {
        let table = SessionTable::new();
        let first = session_id("session-a");
        let second = session_id("session-b");
        table.materialize(&first).unwrap();
        table.materialize(&second).unwrap();
        let runs = Arc::new(AtomicUsize::new(0));
        let runs_for_installer = Arc::clone(&runs);
        let error = table
            .push_installer(Arc::new(move |session| {
                runs_for_installer.fetch_add(1, Ordering::SeqCst);
                install_observation(session)?;
                if session.id().as_str() == "session-b" {
                    return Err(ThreadAssemblyError::Closed);
                }
                Ok(())
            }))
            .expect_err("second session rejects the installer");
        assert!(matches!(error, ThreadAssemblyError::Closed));
        assert_eq!(runs.load(Ordering::SeqCst), 2);

        table
            .push_installer(Arc::new(|session| install_observation(session)))
            .expect("restored sessions accept observation again");
        let late = session_id("session-c");
        table.materialize(&late).unwrap();
        assert_eq!(runs.load(Ordering::SeqCst), 2);
    }

    #[tokio::test]
    async fn resume_agent_closes_reports_every_resident_session() {
        let table = SessionTable::new();
        table.materialize(&session_id("session-a")).unwrap();
        table.materialize(&session_id("session-b")).unwrap();
        let error = table
            .resume_agent_closes()
            .await
            .expect_err("sessions have no close services");
        let text = format!("{error:#}");
        assert!(text.contains("session-a"), "{text}");
        assert!(text.contains("session-b"), "{text}");
    }

    #[test]
    fn cross_thread_materialize_waits_for_the_inflight_generation() {
        let table = SessionTable::new();
        let id = session_id("shared");
        let (entered_tx, entered_rx) = mpsc::channel();
        let (release_tx, release_rx) = mpsc::channel();
        let once = Arc::new(AtomicBool::new(false));
        let once_for_installer = Arc::clone(&once);
        table
            .push_installer(Arc::new(move |_session| {
                if once_for_installer.swap(true, Ordering::SeqCst) {
                    return Ok(());
                }
                entered_tx.send(()).unwrap();
                release_rx.recv().unwrap();
                Ok(())
            }))
            .unwrap();
        let worker_table = table.clone();
        let worker_id = id.clone();
        let worker = std::thread::spawn(move || worker_table.materialize(&worker_id));
        entered_rx
            .recv_timeout(Duration::from_secs(2))
            .expect("installer entered");
        let waiter_table = table.clone();
        let waiter_id = id.clone();
        let waiter = std::thread::spawn(move || waiter_table.materialize(&waiter_id));
        release_tx.send(()).unwrap();
        let (done_tx, done_rx) = mpsc::channel();
        std::thread::spawn(move || {
            let first = worker.join().expect("worker");
            let second = waiter.join().expect("waiter");
            done_tx
                .send(match (first, second) {
                    (Ok(first), Ok(second)) => Arc::ptr_eq(&first.0, &second.0),
                    _ => false,
                })
                .ok();
        });
        assert_eq!(
            done_rx.recv_timeout(Duration::from_secs(2)),
            Ok(true),
            "cross-thread materialize did not share the inflight generation"
        );
    }
}
