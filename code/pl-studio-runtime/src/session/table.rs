//! 应用拥有活动会话代次；成员资源只由各自会话登记。
use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};

use pl_core::thread::ThreadHandle;
use pl_protocol::SessionId;

use super::{SessionPhase, SessionRuntime};
use crate::thread_assembler::{ThreadAssemblyError, WorkspaceRecoveryPublisher};

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

    /// 代次安装与应用关闭共用同步边界；只有 Closed 才能被新代次替换。
    pub(crate) fn materialize(
        &self,
        id: &SessionId,
    ) -> Result<SessionRuntime, ThreadAssemblyError> {
        let mut state = self.state();
        if state.closing {
            return Err(ThreadAssemblyError::Closed);
        }
        if let Some(existing) = state.sessions.get(id)
            && existing.phase() != SessionPhase::Closed
        {
            return Ok(existing.clone());
        }
        let created = SessionRuntime::open(id.clone());
        for installer in &state.installers {
            installer(&created)?;
        }
        state.sessions.insert(id.clone(), created.clone());
        Ok(created)
    }

    pub(crate) fn push_installer(
        &self,
        installer: SessionInstaller,
    ) -> Result<(), ThreadAssemblyError> {
        let mut state = self.state();
        if state.closing {
            return Err(ThreadAssemblyError::Closed);
        }
        for session in state.sessions.values() {
            if session.phase() != SessionPhase::Closed {
                installer(session)?;
            }
        }
        state.installers.push(installer);
        Ok(())
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
        let sessions = {
            let mut state = self.state();
            state.closing = true;
            state.sessions.values().cloned().collect::<Vec<_>>()
        };
        futures::future::join_all(
            sessions
                .into_iter()
                .map(|session| async move { session.close_session().await }),
        )
        .await
        .into_iter()
        .flat_map(|group| group.iter().cloned().collect::<Vec<_>>())
        .collect()
    }

    pub(crate) fn resident_sessions(&self) -> Vec<SessionRuntime> {
        self.state().sessions.values().cloned().collect()
    }

    pub(crate) async fn resume_agent_closes(&self) -> anyhow::Result<()> {
        for session in self.resident_sessions() {
            session.resume_agent_closes().await?;
        }
        Ok(())
    }

    fn state(&self) -> std::sync::MutexGuard<'_, TableState> {
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }
}
