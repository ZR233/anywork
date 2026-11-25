//! 应用拥有活动会话代次；成员资源只由各自会话登记。
use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};

use crate::SessionId;
use pl_core::thread::ThreadHandle;

use super::{SessionPhase, SessionRuntime};
use crate::thread_assembler::{
    AssignmentAdmission, SessionAssignment, ThreadAssemblyError, WorkspaceRecoveryPublisher,
};

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
    plans: Vec<SessionAssignment>,
    closing: bool,
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

    /// 代次安装与应用关闭共用这把锁。已登记计划在插入前应用到新代次，发布后才可见。
    ///
    /// `Closing` 拒绝复用；只有 `Closed` 能被新代次替换。替换看的是 `Arc<Registry>` 身份，不是 `SessionId`。
    pub(crate) fn materialize(
        &self,
        id: &SessionId,
    ) -> Result<SessionRuntime, ThreadAssemblyError> {
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
        let created = SessionRuntime::open(id.clone());
        {
            let mut guard = created.lock_assignment();
            for plan in &state.plans {
                guard.accepts(plan)?;
                guard.commit(plan);
            }
        }
        state.sessions.insert(id.clone(), created.clone());
        Ok(created)
    }

    /// 先检查全部当前代次，再一次提交槽位，最后才登记计划。任何检查失败都不写会话。
    pub(crate) fn push_assignment(
        &self,
        assignment: SessionAssignment,
    ) -> Result<(), ThreadAssemblyError> {
        let mut state = self.state();
        if state.closing {
            return Err(ThreadAssemblyError::Closed);
        }
        assignment_fits(&state.plans, &assignment)?;
        let mut targets = state
            .sessions
            .values()
            .filter(|session| session.phase() == SessionPhase::Open)
            .cloned()
            .collect::<Vec<_>>();
        targets.sort_by_key(|session| Arc::as_ptr(&session.0) as usize);
        let mut guards = targets
            .iter()
            .map(|session| session.lock_assignment())
            .collect::<Vec<_>>();
        let mut ready = Vec::new();
        for (index, guard) in guards.iter().enumerate() {
            match guard.admission(&assignment) {
                AssignmentAdmission::Ready => ready.push(index),
                AssignmentAdmission::Skipping => {}
                AssignmentAdmission::Rejected(error) => return Err(error),
            }
        }
        for index in ready {
            guards[index].commit(&assignment);
        }
        state.plans.push(assignment);
        Ok(())
    }

    pub(crate) fn install_workspace_recovery(
        &self,
        publisher: WorkspaceRecoveryPublisher,
    ) -> Result<(), ThreadAssemblyError> {
        self.push_assignment(SessionAssignment::workspace_recovery(publisher))
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

    /// 短持锁标记关闭并收集已发布代次，然后等待各会话自己的关闭任务。
    pub(crate) async fn join_closes(&self) -> Vec<(String, Arc<ThreadAssemblyError>)> {
        let sessions = self.begin_close();
        futures::future::join_all(
            sessions
                .into_iter()
                .map(|session| async move { session.close_session().await }),
        )
        .await
        .iter()
        .flat_map(|group| group.iter())
        .cloned()
        .collect()
    }

    fn begin_close(&self) -> Vec<SessionRuntime> {
        let mut state = self.state();
        state.closing = true;
        state.sessions.values().cloned().collect()
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

fn assignment_fits(
    plans: &[SessionAssignment],
    next: &SessionAssignment,
) -> Result<(), ThreadAssemblyError> {
    let scratch = SessionRuntime::open(SessionId::new("plan-fit").expect("static session id"));
    let mut guard = scratch.lock_assignment();
    for plan in plans {
        guard.accepts(plan)?;
        guard.commit(plan);
    }
    guard.accepts(next)
}

#[cfg(test)]
mod tests {
    use std::sync::{Arc, Barrier};

    use super::*;

    fn session_id(value: &str) -> SessionId {
        SessionId::new(value).expect("valid session id")
    }

    fn observation_assignment() -> SessionAssignment {
        use futures::FutureExt;
        SessionAssignment::observation(
            |_, _, _| {},
            |_, _| async { Ok(()) }.boxed(),
            None,
            |_, _, _| async { Ok(()) }.boxed(),
            |_| async { Ok(()) }.boxed(),
        )
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
    async fn closed_generation_reopen_receives_registered_assignment() {
        let table = SessionTable::new();
        table.push_assignment(observation_assignment()).unwrap();
        let id = session_id("replaced");
        let first = table.materialize(&id).unwrap();
        assert!(first.test_has_observation());
        assert!(first.close_session().await.is_empty());
        assert_eq!(first.phase(), SessionPhase::Closed);
        let second = table.materialize(&id).unwrap();
        assert_eq!(second.phase(), SessionPhase::Open);
        assert!(!Arc::ptr_eq(&first.0, &second.0));
        assert!(
            second.test_has_observation(),
            "reopened generation must receive plans registered for its SessionId"
        );
    }

    #[test]
    fn rejected_assignment_writes_nothing_and_is_not_registered() {
        let table = SessionTable::new();
        table
            .push_assignment(SessionAssignment::child_factory(
                crate::thread_assembler::children::TestChildFactory,
            ))
            .unwrap();
        let first = session_id("session-a");
        let second = session_id("session-b");
        let left = table.materialize(&first).unwrap();
        let right = table.materialize(&second).unwrap();
        install_observation(&left).unwrap();
        let error = table
            .push_assignment(observation_assignment())
            .expect_err("one generation already has observation");
        assert!(matches!(error, ThreadAssemblyError::Closed));
        assert!(left.test_has_observation());
        assert!(left.test_has_child_factory());
        assert!(!right.test_has_observation());
        assert!(right.test_has_child_factory());
        let late = table.materialize(&session_id("session-c")).unwrap();
        assert!(!late.test_has_observation());
        assert!(late.test_has_child_factory());
    }

    #[test]
    fn concurrent_assignments_do_not_overwrite_each_other() {
        let table = SessionTable::new();
        let id = session_id("shared");
        table.materialize(&id).unwrap();
        let barrier = Arc::new(Barrier::new(2));
        let observation = {
            let table = table.clone();
            let barrier = Arc::clone(&barrier);
            std::thread::spawn(move || {
                barrier.wait();
                table.push_assignment(observation_assignment())
            })
        };
        let factory = {
            let table = table.clone();
            std::thread::spawn(move || {
                barrier.wait();
                table.push_assignment(SessionAssignment::child_factory(
                    crate::thread_assembler::children::TestChildFactory,
                ))
            })
        };
        assert!(observation.join().expect("observation thread").is_ok());
        assert!(factory.join().expect("factory thread").is_ok());
        let session = table.get(&id).unwrap();
        assert!(session.test_has_observation());
        assert!(session.test_has_child_factory());
        let later = table.materialize(&session_id("later")).unwrap();
        assert!(later.test_has_observation());
        assert!(later.test_has_child_factory());
    }

    #[test]
    fn concurrent_materialize_publishes_one_generation() {
        let table = SessionTable::new();
        let id = session_id("shared");
        let barrier = Arc::new(Barrier::new(2));
        let left = {
            let table = table.clone();
            let id = id.clone();
            let barrier = Arc::clone(&barrier);
            std::thread::spawn(move || {
                barrier.wait();
                table.materialize(&id).unwrap()
            })
        };
        let right = std::thread::spawn(move || {
            barrier.wait();
            table.materialize(&id).unwrap()
        });
        let left = left.join().expect("left materialize");
        let right = right.join().expect("right materialize");
        assert!(Arc::ptr_eq(&left.0, &right.0));
    }

    #[test]
    fn closing_table_does_not_publish_or_register() {
        let table = SessionTable::new();
        let _published = table.begin_close();
        let id = session_id("late");
        assert!(matches!(
            table.materialize(&id),
            Err(ThreadAssemblyError::Closed)
        ));
        assert!(table.get(&id).is_none());
        assert!(matches!(
            table.push_assignment(observation_assignment()),
            Err(ThreadAssemblyError::Closed)
        ));
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
}
