//! 物理进程登记表与 job 监督。
//!
//! 每个 spawn 请求在任何异步准备之前原子登记一个 reservation，job 结束时由 `Drop` 立即
//! 释放，因此不存在固定条数上限或已结束进程的墓碑。取消信号只有一份（每进程 watch），
//! 由控制面的 `terminate` 与连接终态共享；实际退出、两路输出排空与 capture 计量都由该进程
//! 自己的流结算。
//!
//! job 由独立的监督任务用 `JoinSet` 真实 join：panic/`JoinError` 会记录为 helper 层面失败，
//! 关闭时先停止接收新 job 再等全部 job 结束，因此「监督任务返回」等价于「所有 job 已退出」，
//! 而不是「队列空了」。

mod capture;
mod io;
mod job;
mod resource;

use std::collections::HashMap;
use std::future::Future;
use std::os::fd::AsRawFd;
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};

use cap_std::fs::Dir;
use pl_protocol::remote::{RemoteCapture, RemoteError, RemoteErrorCode, RemoteSpawnRequest};
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::sync::{mpsc, watch};
use tokio::task::{JoinHandle, JoinSet};

use super::ServerState;
use super::fd::LeasedFd;
use super::path::{Target, remote_error};
use super::records;
use super::resources::ResourceLease;
use super::tasks::{SupervisorGuard, publish_failure};
use crate::remote_transport::{RecordReader, RecordWriter};

/// 进程 job 的所有权类型；监督任务唯一持有并 join 它们。
type Job = Pin<Box<dyn Future<Output = ()> + Send + 'static>>;

/// 进程监督任务未正常结束时的失败文案。
const PROCESS_SUPERVISOR_FAILED: &str = "process supervisor ended without finishing";

/// 待受理 job 的短暂队列：监督任务持续排空，容量只需要吸收并发受理的突发。
const JOB_QUEUE: usize = 8;

/// 转交一条进程流：准备失败时以 typed error 回执并结束该流。
pub(super) async fn spawn<R, W>(
    state: &Arc<ServerState>,
    request: RemoteSpawnRequest,
    lease: ResourceLease,
    reader: RecordReader<R>,
    mut writer: RecordWriter<W>,
) where
    R: AsyncRead + Unpin + Send + 'static,
    W: AsyncWrite + Unpin + Send + 'static,
{
    let registry = state.processes.clone();
    // 身份登记先于任何异步准备；同 id 的并发请求不能通过检查后互相覆盖。
    let reservation = match registry.reserve(&request.process_id) {
        Ok(reservation) => reservation,
        Err(error) => {
            records::fail(&mut writer, error).await;
            return;
        }
    };
    let (cwd, capture) = match resolve_paths(state, &request, &lease).await {
        Ok(paths) => paths,
        Err(error) => {
            records::fail(&mut writer, error).await;
            return;
        }
    };
    // 受理名额先取得，才能在不丢弃 writer 的情况下报告拒绝。
    let job = registry.clone();
    let permit = match registry.reserve_job().await {
        Ok(permit) => permit,
        Err(error) => {
            records::fail(&mut writer, error).await;
            return;
        }
    };
    let shell = state.shell.clone();
    permit.send(Box::pin(job::run(job::Job {
        registry: job,
        reservation,
        shell,
        request,
        cwd,
        capture,
        reader,
        writer,
        tasks: state.tasks.clone(),
        lease,
    })));
}

/// 已验证的 cwd 能力：持有目录 fd，用 `/proc/<helper pid>/fd/<fd>` 作为子进程 cwd。
///
/// 这个字符串是内核解析的句柄路径，不重新解析工作区路径；展示路径只用于诊断与 capture 头，
/// 不参与文件授权。fd 由本结构唯一持有，因此不会被复用。
pub(super) struct CwdCapability {
    /// cwd 目录句柄与本次进程操作的预算不可分：句柄先关闭、预算后归还。
    _file: LeasedFd<std::fs::File>,
    path: PathBuf,
    display: PathBuf,
}

impl CwdCapability {
    fn new(dir: LeasedFd<Dir>, display: PathBuf) -> Self {
        // 目录句柄换成 std 文件句柄是同步移交：预算随新句柄一起交给本结构。
        let (dir, lease) = dir.split();
        let file = LeasedFd::new(dir.into_std_file(), lease);
        let fd = file.get().as_raw_fd();
        Self {
            path: PathBuf::from(format!("/proc/{}/fd/{fd}", std::process::id())),
            display,
            _file: file,
        }
    }

    pub(super) fn path(&self) -> &Path {
        &self.path
    }

    pub(super) fn display(&self) -> &Path {
        &self.display
    }
}

/// 解析命令 cwd 与 capture 目标；两者都是 workspace-relative，都在租约上完成。
async fn resolve_paths(
    state: &Arc<ServerState>,
    request: &RemoteSpawnRequest,
    lease: &ResourceLease,
) -> Result<(CwdCapability, Option<Target>), RemoteError> {
    let root = state.workspace(&request.workspace_id)?;
    let (dir, display) = root.open_directory(&request.cwd, lease).await?;
    let capture = match &request.capture {
        RemoteCapture::None => None,
        // capture 目标的 parent 能力随 `Job` 活到进程回收，因此带上本操作预算。
        RemoteCapture::File { path, .. } => Some(root.ensure_target(path, lease).await?),
    };
    Ok((CwdCapability::new(dir, display), capture))
}

/// 物理进程登记表；克隆只共享登记状态，不转移任何进程所有权。
#[derive(Clone)]
pub(super) struct ProcessRegistry {
    inner: Arc<Registry>,
}

struct Registry {
    entries: Mutex<RegistryEntries>,
    jobs: mpsc::Sender<Job>,
    closing: watch::Sender<bool>,
    supervisor: Mutex<Option<JoinHandle<Result<(), RemoteError>>>>,
    /// 第一个 helper 层面失败（真实回收失败、panic 救援失败或 job 异常结束）；持久值。
    failure: watch::Sender<Option<RemoteError>>,
}

#[derive(Default)]
struct RegistryEntries {
    live: HashMap<String, Entry>,
    next_generation: u64,
}

struct Entry {
    generation: u64,
    cancel: watch::Sender<bool>,
}

impl ProcessRegistry {
    /// 由连接创建；监督任务随登记表一起启动，独占所有 job 的 join。
    pub(super) fn new() -> Self {
        let (jobs, incoming) = mpsc::channel(JOB_QUEUE);
        let (closing, closed) = watch::channel(false);
        let (failure, _) = watch::channel(None);
        // guard 在 spawn 之前构造并移入任务体：任务被 panic/取消时它会发布失败通知。
        let guard = SupervisorGuard::new(failure.clone(), PROCESS_SUPERVISOR_FAILED);
        let supervisor = tokio::spawn(supervise(incoming, closed, failure.clone(), guard));
        Self {
            inner: Arc::new(Registry {
                entries: Mutex::new(RegistryEntries::default()),
                jobs,
                closing,
                supervisor: Mutex::new(Some(supervisor)),
                failure,
            }),
        }
    }

    /// 原子登记一个进程身份；关闭中的连接拒绝新的登记。
    pub(super) fn reserve(&self, process_id: &str) -> Result<Reservation, RemoteError> {
        let mut entries = self.entries();
        if *self.inner.closing.borrow() {
            return Err(closing());
        }
        if entries.live.contains_key(process_id) {
            return Err(remote_error(
                RemoteErrorCode::InvalidRequest,
                format!("process identity '{process_id}' is already registered"),
            ));
        }
        let generation = entries.next_generation.checked_add(1).ok_or_else(|| {
            remote_error(
                RemoteErrorCode::Io,
                "process identity generation space is exhausted",
            )
        })?;
        entries.next_generation = generation;
        let (cancel, _) = watch::channel(false);
        entries.live.insert(
            process_id.to_string(),
            Entry {
                generation,
                cancel: cancel.clone(),
            },
        );
        Ok(Reservation {
            registry: self.clone(),
            process_id: process_id.to_string(),
            generation,
            cancel,
        })
    }

    /// 取得一个受理名额；连接关闭后拒绝，避免 job 进入无人 join 的通道。
    async fn reserve_job(&self) -> Result<mpsc::Permit<'_, Job>, RemoteError> {
        if *self.inner.closing.borrow() {
            return Err(closing());
        }
        self.inner.jobs.reserve().await.map_err(|_| closing())
    }

    /// 只确认终止意图已送达；实际退出与 capture 从那进程自己的流结算。
    pub(super) fn terminate(&self, process_id: &str) -> Result<(), RemoteError> {
        let entries = self.entries();
        match entries.live.get(process_id) {
            Some(entry) => {
                entry.cancel.send_replace(true);
                Ok(())
            }
            None => Err(remote_error(
                RemoteErrorCode::ProcessNotFound,
                format!("unknown process id '{process_id}'"),
            )),
        }
    }

    /// 封闭新登记与受理，取消全部进程，并等待监督任务确认所有 job 真实结束。
    pub(super) async fn terminate_all(&self) -> Result<(), RemoteError> {
        self.inner.closing.send_replace(true);
        {
            let entries = self.entries();
            for entry in entries.live.values() {
                entry.cancel.send_replace(true);
            }
        }
        let supervisor = self
            .inner
            .supervisor
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .take();
        let supervised = match supervisor {
            Some(supervisor) => match supervisor.await {
                Ok(result) => result,
                Err(error) => Err(remote_error(
                    RemoteErrorCode::Io,
                    format!("process supervisor ended abnormally: {error}"),
                )),
            },
            // 已经等待过一次终态；重复关闭不再重新 join。
            None => Ok(()),
        };
        let recorded = self.inner.failure.borrow().as_ref().cloned();
        match (supervised, recorded) {
            (Err(error), _) => Err(error),
            (Ok(()), Some(error)) => Err(error),
            (Ok(()), None) => Ok(()),
        }
    }

    /// 记录一次未能完成的物理回收；连接 owner 会被立即唤醒并主动收尾。
    ///
    /// 只有真正的 helper 层面失败（`worker.wait` 物理回收失败、panic 救援失败）才走这里；
    /// 正常命令退出码（含非零）和普通操作错误都不是 helper 失败。
    fn record_failure(&self, error: RemoteError) {
        publish_failure(&self.inner.failure, error);
    }

    /// 等待第一次 helper 层面失败；owner 用它主动结束连接并走统一收尾。
    ///
    /// 值持久保留，因此「先失败、后开始等待」也不会错过；连接正常时该 future 永不完成。
    pub(super) async fn failed(&self) -> RemoteError {
        let mut failures = self.inner.failure.subscribe();
        loop {
            let observed = failures.borrow_and_update().as_ref().cloned();
            if let Some(error) = observed {
                return error;
            }
            if failures.changed().await.is_err() {
                // owner 已释放：不会再有新的失败可观察，连接本身会在别处结束。
                std::future::pending::<()>().await;
            }
        }
    }

    fn release(&self, process_id: &str, generation: u64) {
        let mut entries = self.entries();
        if entries
            .live
            .get(process_id)
            .is_some_and(|entry| entry.generation == generation)
        {
            entries.live.remove(process_id);
        }
    }

    fn entries(&self) -> MutexGuard<'_, RegistryEntries> {
        self.inner
            .entries
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
    }
}

/// 唯一的 job owner：持续 join 已受理的 job，并把异常结束记录为失败。
async fn supervise(
    mut jobs: mpsc::Receiver<Job>,
    mut closing: watch::Receiver<bool>,
    notify: watch::Sender<Option<RemoteError>>,
    guard: SupervisorGuard,
) -> Result<(), RemoteError> {
    let mut running = JoinSet::new();
    let mut failure = None;
    loop {
        tokio::select! {
            biased;
            _ = closing.wait_for(|closing| *closing) => break,
            // 先回收已完成的 job 再接收新 job：连续 spawn 就绪时不能饿死 join，
            // 否则已结束 job 的条目（及其捕获的资源）会无限堆积。
            Some(result) = running.join_next(), if !running.is_empty() => {
                observe(result, &mut failure, &notify);
            }
            job = jobs.recv() => match job {
                Some(job) => {
                    running.spawn(job);
                }
                None => break,
            },
        }
    }
    // 关闭后仍要等全部已受理 job 真正结束：队列为空不等于进程已回收。
    while let Some(result) = running.join_next().await {
        observe(result, &mut failure, &notify);
    }
    // 走到这里说明全部 job 已真实结束：撤销「未正常结束」通知责任，真实终态由
    // `terminate_all` 观察 `JoinHandle` 结果。
    guard.disarm();
    match failure {
        Some(error) => Err(error),
        None => Ok(()),
    }
}

/// `JoinError` 说明 job 没有走完自己的回收路径（panic 或被取消），必须上报并通知 owner。
fn observe(
    result: Result<(), tokio::task::JoinError>,
    failure: &mut Option<RemoteError>,
    notify: &watch::Sender<Option<RemoteError>>,
) {
    if let Err(error) = result {
        let error = remote_error(
            RemoteErrorCode::Io,
            format!("process job ended abnormally: {error}"),
        );
        publish_failure(notify, error.clone());
        failure.get_or_insert(error);
    }
}

fn closing() -> RemoteError {
    remote_error(
        RemoteErrorCode::RemoteDisconnected,
        "remote helper is closing",
    )
}

/// 一次进程身份登记；`Drop` 释放条目，因此成功、失败和取消回到同一状态。
pub(super) struct Reservation {
    registry: ProcessRegistry,
    process_id: String,
    generation: u64,
    cancel: watch::Sender<bool>,
}

impl Reservation {
    pub(super) fn process_id(&self) -> &str {
        &self.process_id
    }

    /// 与连接终态共享的取消信号；置位后 job 负责终止并回收。
    pub(super) fn cancel(&self) -> watch::Sender<bool> {
        self.cancel.clone()
    }

    pub(super) fn cancelled(&self) -> watch::Receiver<bool> {
        self.cancel.subscribe()
    }

    pub(super) fn is_cancelled(&self) -> bool {
        *self.cancel.borrow()
    }
}

impl Drop for Reservation {
    fn drop(&mut self) {
        self.registry.release(&self.process_id, self.generation);
    }
}
