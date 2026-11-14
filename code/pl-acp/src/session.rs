//! 单个 ACP 业务会话；不启动进程、不保存历史。
//!
//! [`channel`] 在发出 open 请求前交付观察入口。宿主必须恰好一次运行 [`Driver::run`]，
//! 自行 spawn/join 该 future，并拥有 OS 进程、stderr 和最终回收。句柄方法只等待该命令的
//! 协议结果；丢弃调用 future 不取消已经受理的命令，丢弃 driver 更不表示进程已回收。
//! [`Session::close`] 只确认开始关闭；完整关闭事实从 driver join 的 [`Exit`] 读取。

use std::fmt;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};

use agent_client_protocol::schema::ProtocolVersion;
use agent_client_protocol::v1::{ConnectionTo, Responder};
use agent_client_protocol::{Agent, JsonRpcMessage, JsonRpcResponse};
#[cfg(test)]
use agent_client_protocol::{ByteStreams, Client};
use tokio::sync::{Notify, OwnedSemaphorePermit, Semaphore, mpsc, oneshot, watch};
#[cfg(test)]
use tokio_util::compat::{TokioAsyncReadCompatExt, TokioAsyncWriteCompatExt};

use crate::auth::CleanupBudget;
#[cfg(test)]
use crate::auth::{AsyncRead, AsyncWrite};

/// 公开接口直接消费同一版本的官方协议类型。
pub use agent_client_protocol::v1::schema;
use schema::*;

mod observe;
pub use observe::{Event, Gap, Observer};

static NEXT_INSTANCE: AtomicU64 = AtomicU64::new(1);
const SUMMARY_LIMIT: usize = 16 * 1024;
const PERMISSIONS: usize = 64;
const PERMISSION_BYTES: usize = 8 * 1024 * 1024;

/// 明确的会话打开意图；能力不足不降级。
#[derive(Debug, Clone)]
pub enum Open {
    New,
    Load(SessionId),
    Resume(SessionId),
}

type OpenSetupFuture =
    std::pin::Pin<Box<dyn std::future::Future<Output = Result<OpenSetup, Error>> + Send>>;

/// Host preparation after validated initialize and before the session lifecycle request.
/// The callback owns its future; it must not require the protocol receive lock.
pub type PrepareOpen = Arc<dyn Fn(AgentCapabilities) -> OpenSetupFuture + Send + Sync>;

/// Values prepared by the host for this connection; bearer headers must never be logged.
#[derive(Default)]
pub struct OpenSetup {
    pub mcp_servers: Vec<McpServer>,
    pub instructions: Option<String>,
}

#[derive(Clone)]
pub struct OpenRequest {
    pub cwd: String,
    pub intent: Open,
    pub cleanup: CleanupBudget,
    /// Some 要求 initialize.agentInfo.version 精确相等；None 仅校验 ACP V1。
    pub expected_server_version: Option<String>,
    pub prepare: Option<PrepareOpen>,
}

impl fmt::Debug for OpenRequest {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("OpenRequest")
            .field("intent", &self.intent)
            .field("expected_server_version", &self.expected_server_version)
            .field("has_prepare", &self.prepare.is_some())
            .finish_non_exhaustive()
    }
}

/// 不可跨实例或跨运行复用的中断资格。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RunId {
    pub instance: u64,
    pub sequence: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PermissionId {
    pub instance: u64,
    pub sequence: u64,
}

#[derive(Debug, Clone)]
pub enum Error {
    Busy,
    Stale,
    NotReady,
    /// Safe preparation diagnostic supplied by the host, never raw peer/configuration data.
    Preparation(String),
    Closed,
    Unsupported,
    UnsupportedVersion,
    ServerVersionMismatch,
    InvalidOption,
    Rpc(agent_client_protocol::Error),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Preparation(message) => write!(f, "ACP preparation failed: {message}"),
            Self::Rpc(error) => write!(f, "ACP RPC error ({})", i32::from(error.code)),
            other => write!(f, "ACP {other:?}"),
        }
    }
}

impl std::error::Error for Error {}

impl From<agent_client_protocol::Error> for Error {
    fn from(error: agent_client_protocol::Error) -> Self {
        Self::Rpc(error)
    }
}

#[derive(Debug, Clone)]
pub struct Completed {
    pub run: RunId,
    pub completion_sequence: u64,
    pub result: Result<PromptResponse, agent_client_protocol::Error>,
    pub summary: String,
    pub truncated: bool,
}

/// 只读当前态，不包含 transcript；配置和模式保持官方类型及 None/空列表差异。
#[derive(Debug, Clone)]
pub struct Snapshot {
    pub session_id: Option<SessionId>,
    pub capabilities: AgentCapabilities,
    pub ready: bool,
    pub closing: bool,
    pub config_pending: bool,
    pub config_options: Option<Vec<SessionConfigOption>>,
    pub modes: Option<SessionModeState>,
    pub active_run: Option<RunId>,
    pub last_completed: Option<Completed>,
    pub observation_gap: Option<Gap>,
    pub server_info: Option<Implementation>,
    pub auth_methods: Vec<crate::auth::AuthMethod>,
}

/// driver 的协议结果与本地退出事实；不证明子进程/租约已回收。
#[derive(Debug, Clone)]
pub struct Exit {
    pub reason: ExitReason,
    pub close_error: Option<Error>,
    pub sdk_error: Option<agent_client_protocol::Error>,
    pub sdk_finished: bool,
    pub cleanup_timed_out: bool,
    pub unfinished_prompt: Option<RunId>,
    pub unfinished_controls: bool,
    pub observation_gap: Option<Gap>,
    pub last_completed: Option<Completed>,
    /// initialize 实际声明且客户端已实现的方法；失败后可用于向用户提供真实登录指引。
    pub auth_methods: Vec<crate::auth::AuthMethod>,
    pub server_info: Option<Implementation>,
}

#[derive(Debug, Clone)]
pub enum ExitReason {
    Closed,
    IncomingClosed,
    OpenFailed(Error),
}

type Reply<T> = oneshot::Sender<Result<T, Error>>;
type ReplySlot<T> = Arc<Mutex<Option<Reply<T>>>>;

fn deliver<T>(slot: &ReplySlot<T>, result: Result<T, Error>) {
    if let Some(reply) = slot.lock().expect("ACP reply slot panicked").take() {
        let _ = reply.send(result);
    }
}

enum Command {
    Submit(Vec<ContentBlock>, Reply<RunId>),
    Replace(RunId, Vec<ContentBlock>, Reply<RunId>),
    Interrupt(RunId, Reply<()>),
    Config(SessionConfigId, SessionConfigOptionValue, Reply<()>),
    Mode(SessionModeId, Reply<()>),
    Permission(PermissionId, Option<PermissionOptionId>, Reply<()>),
    List(ListSessionsRequest, Reply<ListSessionsResponse>),
    Close(Reply<()>),
}

/// 有限命令入口；不复制运行状态。队列满时明确 Busy，不建立可靠输入队列。
#[derive(Clone)]
pub struct Session {
    state: Shared,
    commands: mpsc::Sender<Command>,
    opened: watch::Receiver<Option<Result<SessionId, Error>>>,
    completion_changes: watch::Receiver<u64>,
}

impl Session {
    /// 等待本次 open 的真实 ID 或失败，可重复调用；取消等待不撤销 open。
    /// 观察缺口不影响结算；成功不证明产品发布或宿主资源已回收。
    pub async fn opened(&self) -> Result<SessionId, Error> {
        let mut opened = self.opened.clone();
        loop {
            if let Some(result) = opened.borrow_and_update().clone() {
                return result;
            }
            opened.changed().await.map_err(|_| Error::Closed)?;
        }
    }

    async fn call<T>(&self, make: impl FnOnce(Reply<T>) -> Command) -> Result<T, Error> {
        let (tx, rx) = oneshot::channel();
        self.commands
            .try_send(make(tx))
            .map_err(|error| match error {
                mpsc::error::TrySendError::Full(_) => Error::Busy,
                mpsc::error::TrySendError::Closed(_) => Error::Closed,
            })?;
        rx.await.map_err(|_| Error::Closed)?
    }

    /// 接纳一次新 prompt；仅真实 PromptResponse/error 完成运行。
    pub async fn submit(&self, content: Vec<ContentBlock>) -> Result<RunId, Error> {
        self.call(|reply| Command::Submit(content, reply)).await
    }

    /// 取消指定运行，等待真实终态，再发出一个替换输入。第二个替换返回 Busy。
    /// 丢弃等待 future 不撤回已接纳的替换；不会重发输入。
    pub async fn replace(&self, run: RunId, content: Vec<ContentBlock>) -> Result<RunId, Error> {
        self.call(|reply| Command::Replace(run, content, reply))
            .await
    }

    pub async fn interrupt(&self, run: RunId) -> Result<(), Error> {
        self.call(|reply| Command::Interrupt(run, reply)).await
    }

    pub async fn set_config(
        &self,
        id: SessionConfigId,
        value: SessionConfigOptionValue,
    ) -> Result<(), Error> {
        self.call(|reply| Command::Config(id, value, reply)).await
    }

    /// 只在 configOptions=None 时使用正式旧模式协议。
    pub async fn set_mode(&self, id: SessionModeId) -> Result<(), Error> {
        self.call(|reply| Command::Mode(id, reply)).await
    }

    /// None 表示 Cancelled；Some 必须是本次权限请求的合法 optionId。
    pub async fn answer_permission(
        &self,
        permission: PermissionId,
        option: Option<PermissionOptionId>,
    ) -> Result<(), Error> {
        self.call(|reply| Command::Permission(permission, option, reply))
            .await
    }

    pub async fn list(&self, request: ListSessionsRequest) -> Result<ListSessionsResponse, Error> {
        self.call(|reply| Command::List(request, reply)).await
    }

    /// 读取驱动维护的原状态；驱动退出后仍可读取最终关闭及完成事实。
    pub async fn snapshot(&self) -> Result<Snapshot, Error> {
        Ok(lock(&self.state).snapshot())
    }

    /// 先注册再读取 snapshot.last_completed，随后等待 changed，避免丢失完成通知。
    /// 仅发布真实 prompt 终态的单调序号；驱动退出时关闭，不消费 Observer。
    pub fn completion_changes(&self) -> watch::Receiver<u64> {
        self.completion_changes.clone()
    }

    /// 仅确认开始关闭；必须继续 join driver，并由宿主回收进程。
    pub async fn close(&self) -> Result<(), Error> {
        self.call(Command::Close).await
    }
}

/// 唯一业务驱动；没有内部 spawn 的业务任务。
pub struct Driver {
    request: OpenRequest,
    commands: mpsc::Receiver<Command>,
    state: Shared,
    lifetime: Option<DriverLifetime>,
    connection: Option<crate::connection::Connection>,
}

// Transferred from the unrun driver into run's outer future, so normal exit,
// cancellation and dropping an unrun driver all close the original state's signals.
struct DriverLifetime(Shared);

impl Drop for DriverLifetime {
    fn drop(&mut self) {
        lock(&self.0).finish_driver();
    }
}

/// 必须先取得 Observer，再启动 driver，才能看到 Load 响应前的历史回放。
pub fn channel(request: OpenRequest) -> (Session, Observer, Driver) {
    let (tx, commands) = mpsc::channel(16);
    let (events, observer) = observe::channel();
    let (opened, open_result) = watch::channel(None);
    let (completion_changes, completion_receiver) = watch::channel(0);
    let session_id = match &request.intent {
        Open::New => None,
        Open::Load(id) | Open::Resume(id) => Some(id.clone()),
    };
    let state = Arc::new(Mutex::new(State {
        instance: NEXT_INSTANCE.fetch_add(1, Ordering::Relaxed),
        session_id,
        ready: false,
        finished: false,
        opened,
        initialized: None,
        capabilities: AgentCapabilities::default(),
        config_options: None,
        modes: None,
        active: None,
        last_completed: None,
        completion_changes: Some(completion_changes),
        prompt_instructions: None,
        next_run: 0,
        permission_sequence: 0,
        permissions: Vec::new(),
        permission_bytes: Arc::new(Semaphore::new(PERMISSION_BYTES)),
        replacement: None,
        config_pending: false,
        config_reply: None,
        list_reply: None,
        list_pending: false,
        closing: false,
        close_sent: false,
        close_done: false,
        close_error: None,
        reason: None,
        events,
        wake: Arc::new(Notify::new()),
        server_info: None,
        auth_methods: Vec::new(),
    }));
    (
        Session {
            state: state.clone(),
            commands: tx,
            opened: open_result,
            completion_changes: completion_receiver,
        },
        observer,
        Driver {
            request,
            commands,
            lifetime: Some(DriverLifetime(state.clone())),
            connection: None,
            state,
        },
    )
}

pub(crate) type Shared = Arc<Mutex<State>>;
pub(crate) fn lock(state: &Shared) -> MutexGuard<'_, State> {
    state.lock().expect("ACP short state callback panicked")
}

struct Active {
    id: RunId,
    summary: String,
    truncated: bool,
    cancelling: bool,
}

struct Permission {
    id: PermissionId,
    run: RunId,
    options: Vec<PermissionOptionId>,
    responder: Responder<RequestPermissionResponse>,
    _bytes: OwnedSemaphorePermit,
}

pub(crate) struct State {
    pub(crate) instance: u64,
    pub(crate) session_id: Option<SessionId>,
    ready: bool,
    pub(crate) finished: bool,
    // DriverLifetime settles pending open and closes completion/events even when
    // Session retains this original State after the driver exits or is cancelled.
    opened: watch::Sender<Option<Result<SessionId, Error>>>,
    initialized: Option<Result<InitializeResponse, agent_client_protocol::Error>>,
    capabilities: AgentCapabilities,
    config_options: Option<Vec<SessionConfigOption>>,
    modes: Option<SessionModeState>,
    active: Option<Active>,
    last_completed: Option<Completed>,
    completion_changes: Option<watch::Sender<u64>>,
    prompt_instructions: Option<String>,
    next_run: u64,
    permission_sequence: u64,
    permissions: Vec<Permission>,
    permission_bytes: Arc<Semaphore>,
    replacement: Option<(Vec<ContentBlock>, Reply<RunId>)>,
    config_pending: bool,
    config_reply: Option<ReplySlot<()>>,
    list_reply: Option<ReplySlot<ListSessionsResponse>>,
    list_pending: bool,
    closing: bool,
    close_sent: bool,
    close_done: bool,
    pub(crate) close_error: Option<Error>,
    reason: Option<ExitReason>,
    events: observe::Sender,
    wake: Arc<Notify>,
    server_info: Option<Implementation>,
    auth_methods: Vec<crate::auth::AuthMethod>,
}

impl State {
    /// 账户撤代的同步准入闸门；驱动随后发送自身取消并等待真实尾部，不排空其他成员。
    pub(crate) fn revoke(&mut self) {
        if self.finished {
            return;
        }
        self.closing = true;
        self.settle_open(Err(Error::Closed));
        self.cancel_permissions();
        if let Some((_, reply)) = self.replacement.take() {
            let _ = reply.send(Err(Error::Closed));
        }
        self.wake.notify_one();
    }

    fn finish_driver(&mut self) {
        self.finished = true;
        self.closing = true;
        self.ready = false;
        self.settle_open(Err(Error::Closed));
        self.cancel_permissions();
        if let Some(reply) = self.config_reply.take() {
            deliver(&reply, Err(Error::Closed));
        }
        if let Some(reply) = self.list_reply.take() {
            deliver(&reply, Err(Error::Closed));
        }
        if let Some((_, reply)) = self.replacement.take() {
            let _ = reply.send(Err(Error::Closed));
        }
        self.completion_changes.take();
        self.events.close();
    }

    fn settle_open(&self, result: Result<SessionId, Error>) {
        self.opened.send_if_modified(|current| {
            if current.is_some() {
                return false;
            }
            *current = Some(result);
            true
        });
    }

    fn snapshot(&self) -> Snapshot {
        Snapshot {
            session_id: self.session_id.clone(),
            capabilities: self.capabilities.clone(),
            ready: self.ready,
            closing: self.closing,
            config_pending: self.config_pending,
            config_options: self.config_options.clone(),
            modes: self.modes.clone(),
            active_run: self.active.as_ref().map(|run| run.id),
            last_completed: self.last_completed.clone(),
            observation_gap: self.events.gap(),
            server_info: self.server_info.clone(),
            auth_methods: self.auth_methods.clone(),
        }
    }

    fn ready(&self) -> Result<SessionId, Error> {
        if self.closing {
            return Err(Error::Closed);
        }
        if !self.ready {
            return Err(Error::NotReady);
        }
        self.session_id.clone().ok_or(Error::NotReady)
    }

    pub(crate) fn update(&mut self, notification: SessionNotification) {
        if self.finished || self.session_id.as_ref() != Some(&notification.session_id) {
            return;
        }
        match &notification.update {
            SessionUpdate::ConfigOptionUpdate(update) => {
                self.config_options = Some(update.config_options.clone());
            }
            SessionUpdate::CurrentModeUpdate(update) if self.config_options.is_none() => {
                if let Some(modes) = &mut self.modes {
                    modes.current_mode_id = update.current_mode_id.clone();
                }
            }
            SessionUpdate::AgentMessageChunk(chunk) => {
                if let (Some(run), ContentBlock::Text(text)) = (&mut self.active, &chunk.content)
                    && !run.truncated
                {
                    let remaining = SUMMARY_LIMIT - run.summary.len();
                    let mut end = text.text.len().min(remaining);
                    while !text.text.is_char_boundary(end) {
                        end -= 1;
                    }
                    run.summary.push_str(&text.text[..end]);
                    run.truncated |= end != text.text.len();
                }
            }
            _ => {}
        }
        let size = message_size(&notification);
        self.emit(Event::Update(notification), size);
    }

    pub(crate) fn setup(
        &mut self,
        result: Result<NewSessionResponse, agent_client_protocol::Error>,
    ) {
        if self.finished {
            return;
        }
        match result {
            Ok(response) => {
                // New acquires its real ID only here, in the ordered result callback.
                let size = response
                    .clone()
                    .into_json("session/new")
                    .map(|v| v.to_string().len());
                self.session_id = Some(response.session_id.clone());
                self.config_options = response.config_options.clone();
                self.modes = response.modes.clone();
                self.ready = true;
                if self.closing {
                    self.settle_open(Err(Error::Closed));
                    self.wake.notify_one();
                    return;
                }
                self.settle_open(Ok(response.session_id.clone()));
                self.emit(Event::Ready(response), size);
            }
            Err(error) => self.fail_open(error.into()),
        }
        self.wake.notify_one();
    }

    pub(crate) fn fail_open(&mut self, error: Error) {
        if self.finished {
            return;
        }
        self.settle_open(Err(error.clone()));
        let size = match &error {
            Error::Rpc(error) => rpc_error_size(error),
            Error::Preparation(message) => message.len().saturating_add(256),
            _ => 256,
        };
        self.emit(Event::Failed(error.clone()), Ok(size));
        self.reason = Some(ExitReason::OpenFailed(error));
        self.wake.notify_one();
    }

    fn cancel_permissions(&mut self) {
        for permission in self.permissions.drain(..) {
            if let Err(error) = permission.responder.respond(RequestPermissionResponse::new(
                RequestPermissionOutcome::Cancelled,
            )) {
                self.close_error.get_or_insert(error.into());
            }
        }
    }

    fn emit(&mut self, event: Event, size: Result<usize, agent_client_protocol::Error>) -> bool {
        let delivered = self.events.send(event, size);
        if self.events.gap().is_some() {
            self.cancel_permissions();
            return false;
        }
        delivered
    }

    fn reject_permission(&mut self, responder: Responder<RequestPermissionResponse>) {
        if let Err(error) = responder.respond(RequestPermissionResponse::new(
            RequestPermissionOutcome::Cancelled,
        )) {
            self.close_error.get_or_insert(error.into());
        }
    }

    pub(crate) fn permission(
        &mut self,
        request: RequestPermissionRequest,
        responder: Responder<RequestPermissionResponse>,
    ) {
        let observable = self.events.gap().is_none();
        if !observable {
            self.cancel_permissions();
        }
        let run = self
            .active
            .as_ref()
            .filter(|run| !run.cancelling)
            .map(|run| run.id);
        let Some(run) = run.filter(|_| {
            observable
                && !self.closing
                && !self.finished
                && self.session_id.as_ref() == Some(&request.session_id)
                && self.permissions.len() < PERMISSIONS
        }) else {
            self.reject_permission(responder);
            return;
        };

        // Only IDs (not tool-call content or option labels) are retained after delivery.
        // Charge the retained vector, ID bytes, responder identity and fixed record storage.
        let options: Vec<_> = request
            .options
            .iter()
            .map(|option| option.option_id.clone())
            .collect();
        let identity_bytes = match responder.raw_id() {
            agent_client_protocol::RawJsonRpcId::Str(id) => id.len(),
            _ => 0,
        };
        let bytes = options.iter().fold(
            std::mem::size_of::<Permission>()
                .saturating_add(
                    options
                        .capacity()
                        .saturating_mul(std::mem::size_of::<PermissionOptionId>()),
                )
                .saturating_add(responder.method().len())
                .saturating_add(identity_bytes),
            |bytes, option| bytes.saturating_add(option.0.len()),
        );
        let permit = if bytes <= PERMISSION_BYTES {
            self.permission_bytes
                .clone()
                .try_acquire_many_owned(bytes as u32)
                .ok()
        } else {
            None
        };
        let Some(permit) = permit else {
            self.reject_permission(responder);
            return;
        };
        self.permission_sequence += 1;
        let id = PermissionId {
            instance: self.instance,
            sequence: self.permission_sequence,
        };
        let size = message_size(&request);
        if self.emit(Event::Permission { id, request }, size) {
            self.permissions.push(Permission {
                id,
                run,
                options,
                responder,
                _bytes: permit,
            });
        } else {
            self.reject_permission(responder);
        }
    }
}

fn message_size(message: &impl JsonRpcMessage) -> Result<usize, agent_client_protocol::Error> {
    message
        .to_untyped_message()
        .map(|value| value.params.to_string().len())
}

fn rpc_error_size(error: &agent_client_protocol::Error) -> usize {
    // JSON string escaping can expand each input byte to at most six bytes.
    256usize
        .saturating_add(error.message.len().saturating_mul(6))
        .saturating_add(error.data.as_ref().map_or(0, |data| data.to_string().len()))
}

impl Driver {
    /// 租用已登记的账户连接；只驱动自身 session，不排空共享 SDK。
    pub async fn run(mut self, shared: crate::connection::Connection) -> Exit {
        let _lifetime = self.lifetime.take();
        let state = self.state.clone();
        self.connection = Some(shared.clone());
        let (closing, mut deadline) = watch::channel(None);
        let drive = async {
            let ready = loop {
                tokio::select! {
                    result = shared.ready() => break result?,
                    command = self.commands.recv() => {
                        match command {
                            Some(Command::Close(reply)) => { let _ = reply.send(Ok(())); return Ok(()); }
                            None => return Ok(()),
                            Some(command) => reject_unready(command),
                        }
                    }
                }
            };
            let _lease = shared.lease()?;
            let _registration = shared.register(state.clone())?;
            lock(&state).initialized = Some(Ok(ready.initialize));
            self.drive(ready.sdk, closing, shared.clone())
                .await
                .map_err(Error::from)
        };
        tokio::pin!(drive);
        let expires = async {
            loop {
                let value = *deadline.borrow_and_update();
                if let Some(at) = value {
                    tokio::time::sleep_until(at).await;
                    return;
                }
                if deadline.changed().await.is_err() {
                    std::future::pending::<()>().await;
                }
            }
        };
        let (cleanup_timed_out, failure) = tokio::select! {
            result = &mut drive => (false, result.err()),
            () = expires => (true, None),
        };
        let sdk_error = failure.as_ref().and_then(|error| match error {
            Error::Rpc(error) => Some(error.clone()),
            _ => None,
        });
        let mut state = lock(&state);
        if !state.ready && !matches!(state.reason, Some(ExitReason::OpenFailed(_))) {
            let error = failure.unwrap_or(Error::Closed);
            state.settle_open(Err(error.clone()));
            state.emit(
                Event::Failed(error.clone()),
                Ok(match &error {
                    Error::Rpc(error) => rpc_error_size(error),
                    Error::Preparation(message) => message.len().saturating_add(256),
                    _ => 256,
                }),
            );
            if state.reason.is_none() {
                state.reason = Some(ExitReason::OpenFailed(error));
            }
        }
        state.finish_driver();
        Exit {
            reason: state.reason.clone().unwrap_or(ExitReason::IncomingClosed),
            close_error: state.close_error.clone(),
            sdk_error,
            sdk_finished: false,
            cleanup_timed_out,
            unfinished_prompt: state.active.as_ref().map(|run| run.id),
            unfinished_controls: state.config_pending
                || state.list_pending
                || (state.close_sent && !state.close_done),
            observation_gap: state.events.gap(),
            last_completed: state.last_completed.clone(),
            auth_methods: state.auth_methods.clone(),
            server_info: state.server_info.clone(),
        }
    }

    async fn drive(
        mut self,
        connection: ConnectionTo<Agent>,
        closing: watch::Sender<Option<tokio::time::Instant>>,
        shared: crate::connection::Connection,
    ) -> Result<(), agent_client_protocol::Error> {
        let state = self.state.clone();
        let observation_lost = lock(&state).events.invalidated();
        tokio::pin!(observation_lost);
        let mut observation_ended = false;
        let wake = lock(&state).wake.clone();
        let mut preparing: Option<OpenSetupFuture> = None;
        loop {
            let mut prepare_capabilities = None;
            {
                let mut owner = lock(&state);
                if let Some(initialize) = owner.initialized.take() {
                    match initialize {
                        Ok(initialize) if initialize.protocol_version == ProtocolVersion::V1 => {
                            // Conservatively charge the complete official initialize response,
                            // including every capability and its metadata, to the original window.
                            let size = initialize
                                .clone()
                                .into_json("initialize")
                                .map(|value| value.to_string().len());
                            owner.auth_methods =
                                crate::auth::declared_methods(&initialize.auth_methods);
                            owner.server_info = initialize.agent_info;
                            owner.capabilities = initialize.agent_capabilities;
                            if self.request.expected_server_version.as_ref().is_some_and(
                                |expected| {
                                    owner.server_info.as_ref().map(|info| &info.version)
                                        != Some(expected)
                                },
                            ) {
                                owner.fail_open(Error::ServerVersionMismatch);
                            } else if !owner.closing {
                                let capabilities = owner.capabilities.clone();
                                owner
                                    .emit(Event::Initialized(Box::new(capabilities.clone())), size);
                                prepare_capabilities = Some(capabilities);
                            } else {
                                owner.close_done = true;
                            }
                        }
                        Ok(_) => owner.fail_open(Error::UnsupportedVersion),
                        Err(error) => owner.fail_open(error.into()),
                    }
                }
                if matches!(owner.reason, Some(ExitReason::OpenFailed(_))) {
                    break;
                }
                if owner.closing {
                    // No lifecycle request has been sent while preparation is pending.
                    // Drop the host future, but retain the normal SDK cleanup path.
                    if preparing.take().is_some() || prepare_capabilities.take().is_some() {
                        owner.close_done = true;
                    }
                    closing.send_replace(Some(self.request.cleanup.deadline()));
                    if let Some(run) = owner
                        .active
                        .as_ref()
                        .filter(|run| !run.cancelling)
                        .map(|run| run.id)
                    {
                        let _ = cancel(&connection, &mut owner, run);
                    }
                    if owner.ready && !owner.close_sent && owner.active.is_none() {
                        self.close_peer(&connection, &mut owner);
                    }
                    if owner.close_done && owner.active.is_none() {
                        break;
                    }
                } else if owner.active.is_none()
                    && let Some((content, reply)) = owner.replacement.take()
                {
                    let result = start_prompt(&connection, &state, &mut owner, content);
                    let _ = reply.send(result);
                }
            }
            if let Some(capabilities) = prepare_capabilities {
                preparing = Some(match self.request.prepare.take() {
                    Some(prepare) => prepare(capabilities),
                    None => Box::pin(async { Ok(OpenSetup::default()) }),
                });
            }
            tokio::select! {
                result = async { preparing.as_mut().expect("guarded preparation").await },
                    if preparing.is_some() => {
                    preparing = None;
                    let mut owner = lock(&state);
                    match result {
                        Ok(setup) => self.open(&connection, &mut owner, setup),
                        Err(error) => owner.fail_open(error),
                    }
                }
                () = &mut observation_lost, if !observation_ended => {
                    observation_ended = true;
                    lock(&state).cancel_permissions();
                }
                () = shared.cancelled(), if !lock(&state).closing => {
                    begin_close(&connection, &mut lock(&state));
                }
                () = connection.incoming_closed() => {
                    lock(&state).reason = Some(ExitReason::IncomingClosed);
                    break;
                }
                () = wake.notified() => {}
                command = self.commands.recv() => {
                    let mut owner = lock(&state);
                    if let Some(command) = command {
                        self.command(&connection, &mut owner, command);
                    } else {
                        begin_close(&connection, &mut owner);
                    }
                }
            }
        }
        Ok(())
    }

    fn open(&self, connection: &ConnectionTo<Agent>, owner: &mut State, setup: OpenSetup) {
        if !owner.capabilities.mcp_capabilities.http
            && setup
                .mcp_servers
                .iter()
                .any(|server| matches!(server, McpServer::Http(_)))
        {
            owner.fail_open(Error::Unsupported);
            return;
        }
        let instructions = setup.instructions.filter(|text| !text.is_empty());
        let system_prompt = if owner
            .capabilities
            .session_capabilities
            .system_prompt
            .is_some()
        {
            instructions.map(|text| {
                SystemPrompt::new(vec![ContentBlock::Text(TextContent::new(text))])
                    .mode(SystemPromptMode::Append)
            })
        } else {
            owner.prompt_instructions = instructions;
            None
        };
        let state = self.state.clone();
        let account = self.connection.clone().expect("registered connection");
        let cwd = &self.request.cwd;
        let result = match &self.request.intent {
            Open::New => connection
                .prepare_request(
                    NewSessionRequest::new(cwd)
                        .mcp_servers(setup.mcp_servers)
                        .system_prompt(system_prompt),
                )
                .on_receiving_result(async move |result| {
                    account.setup(&state, result);
                    Ok(())
                }),
            Open::Load(id) if owner.capabilities.load_session => {
                let id = id.clone();
                connection
                    .prepare_request(
                        LoadSessionRequest::new(id.clone(), cwd)
                            .mcp_servers(setup.mcp_servers)
                            .system_prompt(system_prompt),
                    )
                    .on_receiving_result(async move |result| {
                        account.setup(
                            &state,
                            result.map(|r| {
                                NewSessionResponse::new(id)
                                    .config_options(r.config_options)
                                    .modes(r.modes)
                                    .meta(r.meta)
                            }),
                        );
                        Ok(())
                    })
            }
            Open::Resume(id) if owner.capabilities.session_capabilities.resume.is_some() => {
                let id = id.clone();
                connection
                    .prepare_request(
                        ResumeSessionRequest::new(id.clone(), cwd)
                            .mcp_servers(setup.mcp_servers)
                            .system_prompt(system_prompt),
                    )
                    .on_receiving_result(async move |result| {
                        account.setup(
                            &state,
                            result.map(|r| {
                                NewSessionResponse::new(id)
                                    .config_options(r.config_options)
                                    .modes(r.modes)
                                    .meta(r.meta)
                            }),
                        );
                        Ok(())
                    })
            }
            _ => {
                owner.fail_open(Error::Unsupported);
                return;
            }
        };
        if let Err(error) = result {
            owner.fail_open(error.into());
        }
    }

    fn close_peer(&self, connection: &ConnectionTo<Agent>, owner: &mut State) {
        owner.close_sent = true;
        if owner.capabilities.session_capabilities.close.is_none() {
            owner.close_error = Some(Error::Unsupported);
            owner.close_done = true;
            return;
        }
        let state = self.state.clone();
        let result = connection
            .prepare_request(CloseSessionRequest::new(
                owner.session_id.clone().expect("ready session"),
            ))
            .on_receiving_result(async move |result| {
                let mut state = lock(&state);
                if let Err(error) = result {
                    state.close_error = Some(error.into());
                }
                state.close_done = true;
                state.wake.notify_one();
                Ok(())
            });
        if let Err(error) = result {
            owner.close_error = Some(error.into());
            owner.close_done = true;
        }
    }

    fn command(&self, connection: &ConnectionTo<Agent>, owner: &mut State, command: Command) {
        match command {
            Command::Close(reply) => {
                begin_close(connection, owner);
                let _ = reply.send(Ok(()));
            }
            Command::Submit(content, reply) => {
                let result = if owner.replacement.is_some() {
                    Err(Error::Busy)
                } else {
                    start_prompt(connection, &self.state, owner, content)
                };
                let _ = reply.send(result);
            }
            Command::Interrupt(run, reply) => {
                let _ = reply.send(cancel(connection, owner, run));
            }
            Command::Replace(run, content, reply) => {
                let result = owner.ready().and_then(|_| {
                    if owner.replacement.is_some() {
                        return Err(Error::Busy);
                    }
                    validate_content(&owner.capabilities.prompt_capabilities, &content)?;
                    cancel(connection, owner, run)
                });
                match result {
                    Ok(()) => owner.replacement = Some((content, reply)),
                    Err(error) => {
                        let _ = reply.send(Err(error));
                    }
                }
            }
            Command::Config(id, value, reply) => {
                self.configure(connection, owner, id, value, reply);
            }
            Command::Mode(id, reply) => self.mode(connection, owner, id, reply),
            Command::Permission(id, option, reply) => {
                let result = answer_permission(owner, id, option);
                let _ = reply.send(result);
            }
            Command::List(request, reply) => {
                let valid = owner.ready().and_then(|_| {
                    if owner.list_pending {
                        Err(Error::Busy)
                    } else if owner.capabilities.session_capabilities.list.is_none() {
                        Err(Error::Unsupported)
                    } else {
                        Ok(())
                    }
                });
                if let Err(error) = valid {
                    let _ = reply.send(Err(error));
                    return;
                }
                owner.list_pending = true;
                let state = self.state.clone();
                let reply = Arc::new(Mutex::new(Some(reply)));
                owner.list_reply = Some(reply.clone());
                let callback_reply = reply.clone();
                let result =
                    connection
                        .prepare_request(request)
                        .on_receiving_result(async move |result| {
                            let mut owner = lock(&state);
                            owner.list_pending = false;
                            deliver(
                                &callback_reply,
                                if owner.finished {
                                    Err(Error::Closed)
                                } else {
                                    result.map_err(Error::from)
                                },
                            );
                            Ok(())
                        });
                if let Err(error) = result {
                    owner.list_pending = false;
                    deliver(&reply, Err(error.into()));
                }
            }
        }
    }
}

fn validate_content(
    capabilities: &PromptCapabilities,
    content: &[ContentBlock],
) -> Result<(), Error> {
    for block in content {
        let supported = match block {
            ContentBlock::Text(_) | ContentBlock::ResourceLink(_) => true,
            ContentBlock::Image(_) => capabilities.image,
            ContentBlock::Audio(_) => capabilities.audio,
            ContentBlock::Resource(_) => capabilities.embedded_context,
            _ => false,
        };
        if !supported {
            return Err(Error::Unsupported);
        }
    }
    Ok(())
}

fn start_prompt(
    connection: &ConnectionTo<Agent>,
    state: &Shared,
    owner: &mut State,
    mut content: Vec<ContentBlock>,
) -> Result<RunId, Error> {
    let session_id = owner.ready()?;
    if owner.active.is_some() {
        return Err(Error::Busy);
    }
    validate_content(&owner.capabilities.prompt_capabilities, &content)?;
    if let Some(instructions) = &owner.prompt_instructions {
        content.insert(
            0,
            ContentBlock::Text(TextContent::new(instructions.clone())),
        );
    }
    owner.next_run += 1;
    let id = RunId {
        instance: owner.instance,
        sequence: owner.next_run,
    };
    owner.active = Some(Active {
        id,
        summary: String::new(),
        truncated: false,
        cancelling: false,
    });
    let state = state.clone();
    let result = connection
        .prepare_request(PromptRequest::new(session_id, content))
        .on_receiving_result(async move |result| {
            let mut owner = lock(&state);
            if !owner.finished && owner.active.as_ref().map(|run| run.id) == Some(id) {
                let active = owner.active.take().expect("matched run");
                owner.cancel_permissions();
                let completed = Completed {
                    run: id,
                    completion_sequence: owner
                        .last_completed
                        .as_ref()
                        .map_or(1, |last| last.completion_sequence + 1),
                    result,
                    summary: active.summary,
                    truncated: active.truncated,
                };
                let size = completed
                    .result
                    .clone()
                    .map(|r| {
                        r.into_json("session/prompt")
                            .map(|value| value.to_string().len())
                    })
                    .unwrap_or_else(|error| Ok(rpc_error_size(&error)))
                    .map(|size| size + completed.summary.len());
                owner.emit(Event::Completed(completed.clone()), size);
                let sequence = completed.completion_sequence;
                owner.last_completed = Some(completed);
                if let Some(changes) = &owner.completion_changes {
                    changes.send_replace(sequence);
                }
                owner.wake.notify_one();
            }
            Ok(())
        });
    if let Err(error) = result {
        owner.active = None;
        return Err(error.into());
    }
    Ok(id)
}

fn cancel(connection: &ConnectionTo<Agent>, owner: &mut State, id: RunId) -> Result<(), Error> {
    let session_id = owner.ready()?;
    let active = owner
        .active
        .as_mut()
        .filter(|active| active.id == id)
        .ok_or(Error::Stale)?;
    if !active.cancelling {
        active.cancelling = true;
        owner.cancel_permissions();
        connection.send_notification(CancelNotification::new(session_id))?;
    }
    Ok(())
}

fn begin_close(connection: &ConnectionTo<Agent>, owner: &mut State) {
    if owner.closing {
        return;
    }
    if let Some(run) = owner.active.as_ref().map(|run| run.id)
        && let Err(error) = cancel(connection, owner, run)
    {
        owner.close_error = Some(error);
    }
    owner.cancel_permissions();
    if let Some((_, reply)) = owner.replacement.take() {
        let _ = reply.send(Err(Error::Closed));
    }
    owner.closing = true;
    owner.settle_open(Err(Error::Closed));
    owner.reason.get_or_insert(ExitReason::Closed);
    owner.wake.notify_one();
}

fn answer_permission(
    owner: &mut State,
    id: PermissionId,
    option: Option<PermissionOptionId>,
) -> Result<(), Error> {
    if owner.events.gap().is_some() {
        owner.cancel_permissions();
    }
    owner.ready()?;
    let index = owner
        .permissions
        .iter()
        .position(|permission| permission.id == id)
        .ok_or(Error::Stale)?;
    let permission = &owner.permissions[index];
    if owner.active.as_ref().map(|run| run.id) != Some(permission.run) {
        return Err(Error::Stale);
    }
    if let Some(option) = &option
        && !permission.options.contains(option)
    {
        return Err(Error::InvalidOption);
    }
    let permission = owner.permissions.remove(index);
    permission
        .responder
        .respond(RequestPermissionResponse::new(match option {
            Some(option) => {
                RequestPermissionOutcome::Selected(SelectedPermissionOutcome::new(option))
            }
            None => RequestPermissionOutcome::Cancelled,
        }))?;
    Ok(())
}

impl Driver {
    fn configure(
        &self,
        connection: &ConnectionTo<Agent>,
        owner: &mut State,
        id: SessionConfigId,
        value: SessionConfigOptionValue,
        reply: Reply<()>,
    ) {
        let valid = owner.ready().and_then(|session| {
            if owner.config_pending {
                return Err(Error::Busy);
            }
            let options = owner.config_options.as_ref().ok_or(Error::Unsupported)?;
            let option = options
                .iter()
                .find(|option| option.id == id)
                .ok_or(Error::InvalidOption)?;
            let matches = match (&option.kind, &value) {
                (SessionConfigKind::Boolean(_), SessionConfigOptionValue::Boolean { .. }) => true,
                (
                    SessionConfigKind::Select(select),
                    SessionConfigOptionValue::ValueId { value },
                ) => match &select.options {
                    SessionConfigSelectOptions::Ungrouped(options) => {
                        options.iter().any(|o| o.value == *value)
                    }
                    SessionConfigSelectOptions::Grouped(groups) => groups
                        .iter()
                        .any(|g| g.options.iter().any(|o| o.value == *value)),
                    _ => false,
                },
                _ => false,
            };
            if matches {
                Ok(session)
            } else {
                Err(Error::InvalidOption)
            }
        });
        let session = match valid {
            Ok(session) => session,
            Err(error) => {
                let _ = reply.send(Err(error));
                return;
            }
        };
        owner.config_pending = true;
        let state = self.state.clone();
        let reply = Arc::new(Mutex::new(Some(reply)));
        owner.config_reply = Some(reply.clone());
        let callback_reply = reply.clone();
        let result = connection
            .prepare_request(SetSessionConfigOptionRequest::new(session, id, value))
            .on_receiving_result(async move |result| {
                let mut owner = lock(&state);
                if owner.finished {
                    deliver(&callback_reply, Err(Error::Closed));
                    return Ok(());
                }
                owner.config_pending = false;
                if let Ok(response) = &result {
                    owner.config_options = Some(response.config_options.clone());
                    let size = response
                        .clone()
                        .into_json("session/set_config_option")
                        .map(|v| v.to_string().len());
                    owner.emit(Event::Configured(response.clone()), size);
                }
                deliver(&callback_reply, result.map(|_| ()).map_err(Error::from));
                Ok(())
            });
        if let Err(error) = result {
            owner.config_pending = false;
            deliver(&reply, Err(error.into()));
        }
    }

    fn mode(
        &self,
        connection: &ConnectionTo<Agent>,
        owner: &mut State,
        id: SessionModeId,
        reply: Reply<()>,
    ) {
        let valid = owner.ready().and_then(|session| {
            if owner.config_pending {
                return Err(Error::Busy);
            }
            if owner.config_options.is_some() {
                return Err(Error::Unsupported);
            }
            if !owner
                .modes
                .as_ref()
                .is_some_and(|modes| modes.available_modes.iter().any(|mode| mode.id == id))
            {
                return Err(Error::InvalidOption);
            }
            Ok(session)
        });
        let session = match valid {
            Ok(session) => session,
            Err(error) => {
                let _ = reply.send(Err(error));
                return;
            }
        };
        owner.config_pending = true;
        let state = self.state.clone();
        let reply = Arc::new(Mutex::new(Some(reply)));
        owner.config_reply = Some(reply.clone());
        let callback_reply = reply.clone();
        let result = connection
            .prepare_request(SetSessionModeRequest::new(session, id.clone()))
            .on_receiving_result(async move |result| {
                let mut owner = lock(&state);
                if owner.finished {
                    deliver(&callback_reply, Err(Error::Closed));
                    return Ok(());
                }
                owner.config_pending = false;
                if result.is_ok()
                    && owner.config_options.is_none()
                    && let Some(modes) = &mut owner.modes
                {
                    modes.current_mode_id = id.clone();
                    let size = Ok(id.to_string().len());
                    owner.emit(Event::ModeSet(id), size);
                }
                deliver(&callback_reply, result.map(|_| ()).map_err(Error::from));
                Ok(())
            });
        if let Err(error) = result {
            owner.config_pending = false;
            deliver(&reply, Err(error.into()));
        }
    }
}

fn reject_unready(command: Command) {
    match command {
        Command::Submit(_, reply) | Command::Replace(_, _, reply) => {
            let _ = reply.send(Err(Error::NotReady));
        }
        Command::Interrupt(_, reply)
        | Command::Config(_, _, reply)
        | Command::Mode(_, reply)
        | Command::Permission(_, _, reply)
        | Command::Close(reply) => {
            let _ = reply.send(Err(Error::NotReady));
        }
        Command::List(_, reply) => {
            let _ = reply.send(Err(Error::NotReady));
        }
    }
}

#[cfg(test)]
impl Driver {
    async fn run_isolated<W, R>(self, outgoing: W, incoming: R) -> Exit
    where
        W: AsyncWrite + Unpin + Send + 'static,
        R: AsyncRead + Unpin + Send + 'static,
    {
        let (connection, driver) = crate::connection::channel(None, self.request.cleanup.clone());
        struct CancelOnDrop(crate::connection::Connection);
        impl Drop for CancelOnDrop {
            fn drop(&mut self) {
                self.0.cancel();
            }
        }
        let _cancel = CancelOnDrop(connection.clone());
        let sdk = tokio::spawn(driver.run(outgoing, incoming));
        let mut exit = self.run(connection.clone()).await;
        connection.cancel();
        let sdk = sdk.await.expect("SDK joined");
        exit.sdk_finished = sdk.sdk_finished;
        exit.cleanup_timed_out |= sdk.cleanup_timed_out;
        if let Err(Error::Rpc(error)) = sdk.result {
            exit.sdk_error = Some(error);
        }
        exit
    }
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use super::*;
    use agent_client_protocol::Error as RpcError;

    #[derive(Clone)]
    struct Scenario {
        capabilities: AgentCapabilities,
        config: Option<Vec<SessionConfigOption>>,
        modes: Option<SessionModeState>,
        load_replay: bool,
        close_failure: bool,
        close_hangs: bool,
        auth_required: bool,
        server_info: Option<Implementation>,
        expected_server_version: Option<String>,
        prepare: Option<PrepareOpen>,
    }

    impl Default for Scenario {
        fn default() -> Self {
            Self {
                capabilities: AgentCapabilities::new()
                    .load_session(true)
                    .session_capabilities(
                        SessionCapabilities::new()
                            .resume(SessionResumeCapabilities::new())
                            .list(SessionListCapabilities::new())
                            .close(SessionCloseCapabilities::new()),
                    ),
                config: Some(configs("a")),
                modes: None,
                load_replay: false,
                close_failure: false,
                close_hangs: false,
                auth_required: false,
                server_info: None,
                expected_server_version: None,
                prepare: None,
            }
        }
    }

    fn configs(value: &str) -> Vec<SessionConfigOption> {
        vec![
            SessionConfigOption::new(
                "model",
                "Model",
                SessionConfigKind::Select(SessionConfigSelect::new(
                    value.to_owned(),
                    SessionConfigSelectOptions::Grouped(vec![SessionConfigSelectGroup::new(
                        "vendor-x",
                        "Vendor X",
                        vec![
                            SessionConfigSelectOption::new("a", "Alpha").description("First"),
                            SessionConfigSelectOption::new("b", "Beta"),
                        ],
                    )]),
                )),
            )
            .category(SessionConfigOptionCategory::Model)
            .description("Model choice"),
            SessionConfigOption::new(
                "effort",
                "Thinking",
                SessionConfigKind::Select(SessionConfigSelect::new(
                    "deep",
                    SessionConfigSelectOptions::Ungrouped(vec![
                        SessionConfigSelectOption::new("deep", "Deep"),
                        SessionConfigSelectOption::new("fast", "Fast"),
                    ]),
                )),
            )
            .category(SessionConfigOptionCategory::Other("vendor/effort".into())),
            SessionConfigOption::new(
                "safe",
                "Safe",
                SessionConfigKind::Boolean(SessionConfigBoolean::new(true)),
            )
            .category(SessionConfigOptionCategory::Other("vendor/safety".into())),
        ]
    }

    #[derive(Default)]
    struct PeerState {
        opens: Vec<&'static str>,
        setups: Vec<(Vec<McpServer>, Option<SystemPrompt>)>,
        prompt_requests: Vec<PromptRequest>,
        prompts: Vec<Responder<PromptResponse>>,
        config_requests: Vec<SetSessionConfigOptionRequest>,
        configs: Vec<Responder<SetSessionConfigOptionResponse>>,
        permission_results: Vec<RequestPermissionOutcome>,
        cancels: usize,
        closes: usize,
        lists: usize,
        modes: Vec<SessionModeId>,
        boolean_advertised: bool,
        initialize_request: Option<InitializeRequest>,
        held_closes: Vec<Responder<CloseSessionResponse>>,
        held_load: Option<(Responder<LoadSessionResponse>, LoadSessionResponse)>,
    }

    type PeerShared = Arc<Mutex<PeerState>>;

    enum PeerCommand {
        Updates(Vec<SessionNotification>, oneshot::Sender<()>),
        Complete(StopReason, oneshot::Sender<()>),
        FailPrompt(RpcError),
        Config {
            before: Option<Vec<SessionConfigOption>>,
            result: Result<Vec<SessionConfigOption>, RpcError>,
            after: Option<Vec<SessionConfigOption>>,
        },
        Permission,
        PermissionOptions(Vec<PermissionOption>),
        ReleaseLoad,
        FailLoad(RpcError),
        Eof,
    }

    struct Harness {
        session: Session,
        observer: Observer,
        initialized: bool,
        driver: tokio::task::JoinHandle<Exit>,
        peer: tokio::task::JoinHandle<Result<(), RpcError>>,
        state: PeerShared,
        changed: Arc<Notify>,
        control: mpsc::Sender<PeerCommand>,
    }

    fn peer_lock(state: &PeerShared) -> MutexGuard<'_, PeerState> {
        state.lock().unwrap()
    }

    impl Harness {
        fn new(intent: Open, scenario: Scenario) -> Self {
            Self::with_cleanup(intent, scenario, CleanupBudget::new(Duration::from_secs(2)))
        }

        fn with_cleanup(intent: Open, scenario: Scenario, cleanup: CleanupBudget) -> Self {
            let state = Arc::new(Mutex::new(PeerState::default()));
            let changed = Arc::new(Notify::new());
            let (control, mut controls) = mpsc::channel(16);
            let (client_writer, agent_reader) = tokio::io::duplex(64 * 1024);
            let (agent_writer, client_reader) = tokio::io::duplex(64 * 1024);
            let (session, observer, driver) = channel(OpenRequest {
                cwd: "/workspace/real-business".into(),
                intent,
                cleanup,
                expected_server_version: scenario.expected_server_version.clone(),
                prepare: scenario.prepare.clone(),
            });
            let driver = tokio::spawn(driver.run_isolated(client_writer, client_reader));
            let peer_state = state.clone();
            let peer_changed = changed.clone();
            let init_scenario = scenario.clone();
            let new_scenario = scenario.clone();
            let load_scenario = scenario.clone();
            let resume_scenario = scenario.clone();
            let peer = tokio::spawn(async move {
                let init_state = peer_state.clone();
                let new_state = peer_state.clone();
                let load_state = peer_state.clone();
                let resume_state = peer_state.clone();
                let prompt_state = peer_state.clone();
                let config_state = peer_state.clone();
                let cancel_state = peer_state.clone();
                let close_state = peer_state.clone();
                let list_state = peer_state.clone();
                let mode_state = peer_state.clone();
                let prompt_changed = peer_changed.clone();
                let load_changed = peer_changed.clone();
                let config_changed = peer_changed.clone();
                let cancel_changed = peer_changed.clone();
                Agent.v1()
                .on_receive_request(async move |request: InitializeRequest, responder: Responder<InitializeResponse>, _: ConnectionTo<Client>| {
                    peer_lock(&init_state).initialize_request = Some(request.clone());
                    peer_lock(&init_state).boolean_advertised = request.client_capabilities.session.and_then(|session| session.config_options)
                        .is_some_and(|config| config.boolean.is_some());
                    responder.respond(InitializeResponse::new(ProtocolVersion::V1)
                        .auth_methods(vec![
                            AuthMethod::Agent(AuthMethodAgent::new("agent-login", "Agent sign in").description("Use the server login")),
                            AuthMethod::Terminal(AuthMethodTerminal::new("terminal-login", "Terminal sign in")),
                        ])
                        .agent_info(init_scenario.server_info.clone())
                        .agent_capabilities(init_scenario.capabilities.clone()))
                }, agent_client_protocol::on_receive_request!())
                .on_receive_request(async move |request: NewSessionRequest, responder: Responder<NewSessionResponse>, connection: ConnectionTo<Client>| {
                    assert_eq!(request.cwd.to_str(), Some("/workspace/real-business"));
                    peer_lock(&new_state).opens.push("new");
                    peer_lock(&new_state).setups.push((request.mcp_servers, request.system_prompt));
                    if new_scenario.auth_required { return responder.respond_with_error(RpcError::auth_required()); }
                    connection.send_notification(update("business", text("unbound must not be claimed")))?;
                    responder.respond(NewSessionResponse::new("business")
                        .config_options(new_scenario.config.clone()).modes(new_scenario.modes.clone()))
                }, agent_client_protocol::on_receive_request!())
                .on_receive_request(async move |request: LoadSessionRequest, responder: Responder<LoadSessionResponse>, connection: ConnectionTo<Client>| {
                    assert_eq!(request.session_id.to_string(), "business");
                    peer_lock(&load_state).opens.push("load");
                    peer_lock(&load_state).setups.push((request.mcp_servers, request.system_prompt));
                    if load_scenario.load_replay {
                        connection.send_notification(update("foreign", text("must not bind")))?;
                        connection.send_notification(update("business", text("replayed before response")))?;
                        connection.send_notification(config_update(configs("b")))?;
                        peer_lock(&load_state).held_load = Some((responder,
                            LoadSessionResponse::new().config_options(load_scenario.config.clone())
                                .modes(load_scenario.modes.clone())));
                        load_changed.notify_one();
                        return Ok(());
                    }
                    responder.respond(LoadSessionResponse::new().config_options(load_scenario.config.clone())
                        .modes(load_scenario.modes.clone()))
                }, agent_client_protocol::on_receive_request!())
                .on_receive_request(async move |request: ResumeSessionRequest, responder: Responder<ResumeSessionResponse>, _: ConnectionTo<Client>| {
                    peer_lock(&resume_state).opens.push("resume");
                    peer_lock(&resume_state).setups.push((request.mcp_servers, request.system_prompt));
                    responder.respond(ResumeSessionResponse::new().config_options(resume_scenario.config.clone())
                        .modes(resume_scenario.modes.clone()))
                }, agent_client_protocol::on_receive_request!())
                .on_receive_request(async move |request: PromptRequest, responder: Responder<PromptResponse>, _: ConnectionTo<Client>| {
                    let mut state = peer_lock(&prompt_state);
                    state.prompt_requests.push(request);
                    state.prompts.push(responder);
                    prompt_changed.notify_one();
                    Ok(())
                }, agent_client_protocol::on_receive_request!())
                .on_receive_request(async move |request: SetSessionConfigOptionRequest, responder: Responder<SetSessionConfigOptionResponse>, _: ConnectionTo<Client>| {
                    let mut state = peer_lock(&config_state);
                    state.config_requests.push(request);
                    state.configs.push(responder);
                    config_changed.notify_one();
                    Ok(())
                }, agent_client_protocol::on_receive_request!())
                .on_receive_request(async move |request: SetSessionModeRequest, responder: Responder<SetSessionModeResponse>, _: ConnectionTo<Client>| {
                    peer_lock(&mode_state).modes.push(request.mode_id);
                    responder.respond(SetSessionModeResponse::new())
                }, agent_client_protocol::on_receive_request!())
                .on_receive_notification(async move |_: CancelNotification, _: ConnectionTo<Client>| {
                    peer_lock(&cancel_state).cancels += 1;
                    cancel_changed.notify_one();
                    Ok(())
                }, agent_client_protocol::on_receive_notification!())
                .on_receive_request(async move |_: CloseSessionRequest, responder: Responder<CloseSessionResponse>, _: ConnectionTo<Client>| {
                    peer_lock(&close_state).closes += 1;
                    if scenario.close_hangs { peer_lock(&close_state).held_closes.push(responder); Ok(()) }
                    else if scenario.close_failure { responder.respond_with_error(RpcError::method_not_found()) }
                    else { responder.respond(CloseSessionResponse::new()) }
                }, agent_client_protocol::on_receive_request!())
                .on_receive_request(async move |_: ListSessionsRequest, responder: Responder<ListSessionsResponse>, _: ConnectionTo<Client>| {
                    peer_lock(&list_state).lists += 1;
                    responder.respond(ListSessionsResponse::new(vec![]))
                }, agent_client_protocol::on_receive_request!())
                .connect_with(ByteStreams::new(agent_writer.compat_write(), agent_reader.compat()), async move |connection| {
                    loop {
                        tokio::select! {
                            () = connection.incoming_closed() => break,
                            command = controls.recv() => match command {
                                Some(PeerCommand::Updates(updates, reply)) => {
                                    for update in updates { connection.send_notification(update)?; }
                                    let _ = reply.send(());
                                }
                                Some(PeerCommand::Complete(reason, reply)) => {
                                    peer_lock(&peer_state).prompts.remove(0).respond(PromptResponse::new(reason))?;
                                    let _ = reply.send(());
                                }
                                Some(PeerCommand::FailPrompt(error)) => {
                                    peer_lock(&peer_state).prompts.remove(0).respond_with_error(error)?;
                                }
                                Some(PeerCommand::Config { before, result, after }) => {
                                    if let Some(before) = before { connection.send_notification(config_update(before))?; }
                                    let responder = peer_lock(&peer_state).configs.remove(0);
                                    match result {
                                        Ok(options) => responder.respond(SetSessionConfigOptionResponse::new(options))?,
                                        Err(error) => responder.respond_with_error(error)?,
                                    }
                                    if let Some(after) = after { connection.send_notification(config_update(after))?; }
                                }
                                Some(PeerCommand::Permission) => {
                                    send_permission(&connection, peer_state.clone(), peer_changed.clone(),
                                        vec![PermissionOption::new("allow", "Allow", PermissionOptionKind::AllowOnce)])?;
                                }
                                Some(PeerCommand::PermissionOptions(options)) => {
                                    send_permission(&connection, peer_state.clone(), peer_changed.clone(), options)?;
                                }
                                Some(PeerCommand::ReleaseLoad) => {
                                    let (responder, response) = peer_lock(&peer_state).held_load.take().unwrap();
                                    responder.respond(response)?;
                                }
                                Some(PeerCommand::FailLoad(error)) => {
                                    let (responder, _) = peer_lock(&peer_state).held_load.take().unwrap();
                                    responder.respond_with_error(error)?;
                                }
                                Some(PeerCommand::Eof) | None => break,
                            }
                        }
                    }
                    Ok(())
                }).await
            });
            Self {
                session,
                observer,
                initialized: false,
                driver,
                peer,
                state,
                changed,
                control,
            }
        }

        async fn wait(&self, predicate: impl Fn(&PeerState) -> bool) {
            tokio::time::timeout(Duration::from_secs(5), async {
                loop {
                    let notified = self.changed.notified();
                    if predicate(&peer_lock(&self.state)) {
                        break;
                    }
                    notified.await;
                }
            })
            .await
            .expect("peer received expected real SDK request");
        }

        async fn event(&mut self) -> Event {
            let event = tokio::time::timeout(Duration::from_secs(5), self.observer.recv())
                .await
                .unwrap()
                .unwrap();
            if matches!(event, Event::Initialized(_)) {
                assert!(
                    !self.initialized,
                    "initialize must be published exactly once"
                );
                self.initialized = true;
            }
            event
        }

        async fn ready(&mut self) -> NewSessionResponse {
            let event = self.event().await;
            let event = if matches!(event, Event::Initialized(_)) {
                self.event().await
            } else {
                event
            };
            assert!(self.initialized, "Ready must follow initialize");
            match event {
                Event::Ready(response) => response,
                event => panic!("{event:?}"),
            }
        }

        async fn updates(&self, updates: Vec<SessionNotification>) {
            let (tx, rx) = oneshot::channel();
            self.control
                .send(PeerCommand::Updates(updates, tx))
                .await
                .unwrap();
            rx.await.unwrap();
        }

        async fn complete(&self, reason: StopReason) {
            let (tx, rx) = oneshot::channel();
            self.control
                .send(PeerCommand::Complete(reason, tx))
                .await
                .unwrap();
            rx.await.unwrap();
        }

        async fn finish(self) -> Exit {
            self.session.close().await.unwrap();
            self.join().await
        }

        async fn join(self) -> Exit {
            let exit = tokio::time::timeout(Duration::from_secs(5), self.driver)
                .await
                .unwrap()
                .unwrap();
            tokio::time::timeout(Duration::from_secs(5), self.peer)
                .await
                .unwrap()
                .unwrap()
                .unwrap();
            exit
        }
    }

    fn send_permission(
        connection: &ConnectionTo<Client>,
        state: PeerShared,
        changed: Arc<Notify>,
        options: Vec<PermissionOption>,
    ) -> Result<(), RpcError> {
        connection
            .prepare_request(RequestPermissionRequest::new(
                "business",
                ToolCallUpdate::new("tool-1", ToolCallUpdateFields::new()),
                options,
            ))
            .on_receiving_result(async move |result| {
                peer_lock(&state).permission_results.push(result?.outcome);
                changed.notify_one();
                Ok(())
            })
    }

    fn text(value: &str) -> SessionUpdate {
        SessionUpdate::AgentMessageChunk(ContentChunk::new(ContentBlock::Text(TextContent::new(
            value,
        ))))
    }

    fn update(id: &str, update: SessionUpdate) -> SessionNotification {
        SessionNotification::new(id.to_owned(), update)
    }

    fn config_update(options: Vec<SessionConfigOption>) -> SessionNotification {
        update(
            "business",
            SessionUpdate::ConfigOptionUpdate(ConfigOptionUpdate::new(options)),
        )
    }

    fn input(value: &str) -> Vec<ContentBlock> {
        vec![ContentBlock::Text(TextContent::new(value))]
    }

    fn http_server() -> McpServer {
        McpServer::Http(
            McpServerHttp::new("host-tools", "http://127.0.0.1:43129/mcp")
                .headers(vec![HttpHeader::new("Authorization", "Bearer test-secret")]),
        )
    }

    async fn completion_changed(
        changes: &mut watch::Receiver<u64>,
    ) -> Result<(), watch::error::RecvError> {
        tokio::time::timeout(Duration::from_secs(5), changes.changed())
            .await
            .expect("completion or driver closure must wake waiter")
    }

    #[tokio::test]
    async fn snapshot_reads_original_completion_after_driver_exit_before_join() {
        for ending in ["close", "eof", "driver-drop", "close-timeout"] {
            let mut harness = Harness::with_cleanup(
                Open::New,
                Scenario {
                    close_hangs: ending == "close-timeout",
                    ..Scenario::default()
                },
                CleanupBudget::new(Duration::from_millis(50)),
            );
            harness.ready().await;
            let session = harness.session.clone();
            let mut changes = session.completion_changes();
            let run = session
                .submit(input("complete before shutdown"))
                .await
                .unwrap();
            harness.wait(|peer| !peer.prompts.is_empty()).await;
            harness
                .updates(vec![update("business", text("original completed summary"))])
                .await;
            harness.complete(StopReason::EndTurn).await;
            completion_changed(&mut changes).await.unwrap();
            changes.borrow_and_update();
            let before = session.snapshot().await.unwrap().last_completed.unwrap();
            assert_eq!(before.run, run);
            assert_eq!(before.summary, "original completed summary");
            match ending {
                "close" | "close-timeout" => session.close().await.unwrap(),
                "eof" => harness.control.send(PeerCommand::Eof).await.unwrap(),
                "driver-drop" => harness.driver.abort(),
                _ => unreachable!(),
            }
            // Observe closure and read the source before the resource owner receives Exit.
            assert!(completion_changed(&mut changes).await.is_err());
            let after = session.snapshot().await.unwrap();
            assert!(after.closing, "{ending}");
            assert!(!after.ready, "{ending}");
            assert!(after.active_run.is_none());
            let completed = after.last_completed.unwrap();
            assert_eq!(completed.run, before.run);
            assert_eq!(completed.completion_sequence, before.completion_sequence);
            assert_eq!(completed.result, before.result);
            assert_eq!(completed.summary, before.summary);
            assert_eq!(completed.truncated, before.truncated);
            let mut ui_completions = 0;
            while let Some(event) =
                tokio::time::timeout(Duration::from_secs(5), harness.observer.recv())
                    .await
                    .unwrap()
            {
                if matches!(event, Event::Completed(value) if value.run == run) {
                    ui_completions += 1;
                }
            }
            assert_eq!(ui_completions, 1, "original observer must drain and close");
            if ending == "driver-drop" {
                assert!(harness.driver.await.unwrap_err().is_cancelled());
                tokio::time::timeout(Duration::from_secs(5), harness.peer)
                    .await
                    .unwrap()
                    .unwrap()
                    .unwrap();
            } else {
                let exit = harness.join().await;
                assert_eq!(exit.cleanup_timed_out, ending == "close-timeout");
                let terminal = exit.last_completed.unwrap();
                assert_eq!(completed.run, terminal.run);
                assert_eq!(completed.completion_sequence, terminal.completion_sequence);
                assert_eq!(completed.result, terminal.result);
                assert_eq!(completed.summary, terminal.summary);
                assert_eq!(completed.truncated, terminal.truncated);
            }
            assert!(matches!(
                session.submit(input("after exit")).await,
                Err(Error::Closed)
            ));
        }
    }

    #[tokio::test]
    async fn prepared_lifecycle_mcp_and_instructions_reach_real_sdk_requests() {
        for system_prompt in [false, true] {
            for intent in [
                Open::New,
                Open::Load("business".into()),
                Open::Resume("business".into()),
            ] {
                let calls = Arc::new(AtomicU64::new(0));
                let callback_calls = calls.clone();
                let mut scenario = Scenario::default();
                scenario.capabilities.mcp_capabilities.http = true;
                if system_prompt {
                    scenario.capabilities.session_capabilities.system_prompt =
                        Some(SessionSystemPromptCapabilities::new());
                }
                scenario.prepare = Some(Arc::new(move |capabilities| {
                    assert!(capabilities.mcp_capabilities.http);
                    assert_eq!(
                        capabilities.session_capabilities.system_prompt.is_some(),
                        system_prompt
                    );
                    callback_calls.fetch_add(1, Ordering::SeqCst);
                    Box::pin(async {
                        Ok(OpenSetup {
                            mcp_servers: vec![http_server()],
                            instructions: Some("Host instructions\n保持原文".into()),
                        })
                    })
                }));
                let mut harness = Harness::new(intent, scenario);
                harness.ready().await;
                {
                    let peer = peer_lock(&harness.state);
                    assert_eq!(peer.setups.len(), 1);
                    assert_eq!(peer.setups[0].0, vec![http_server()]);
                    let expected = system_prompt.then(|| {
                        SystemPrompt::new(input("Host instructions\n保持原文"))
                            .mode(SystemPromptMode::Append)
                    });
                    assert_eq!(peer.setups[0].1, expected);
                }
                let source = input("first user input");
                let run = harness.session.submit(source.clone()).await.unwrap();
                harness.wait(|peer| peer.prompts.len() == 1).await;
                let session = harness.session.clone();
                let replacement_source = input("second user input");
                let replacement_content = replacement_source.clone();
                let replacement =
                    tokio::spawn(async move { session.replace(run, replacement_content).await });
                harness.wait(|peer| peer.cancels == 1).await;
                let mut changes = harness.session.completion_changes();
                assert_eq!(*changes.borrow_and_update(), 0);
                assert!(
                    harness
                        .session
                        .snapshot()
                        .await
                        .unwrap()
                        .last_completed
                        .is_none()
                );
                assert!(
                    !changes.has_changed().unwrap(),
                    "cancel is not a prompt terminal"
                );
                harness.complete(StopReason::Cancelled).await;
                completion_changed(&mut changes).await.unwrap();
                assert_eq!(*changes.borrow_and_update(), 1);
                let completed = harness
                    .session
                    .snapshot()
                    .await
                    .unwrap()
                    .last_completed
                    .unwrap();
                assert_eq!(completed.run, run);
                let second = replacement.await.unwrap().unwrap();
                harness.wait(|peer| peer.prompt_requests.len() == 2).await;
                {
                    let peer = peer_lock(&harness.state);
                    for (request, original) in peer
                        .prompt_requests
                        .iter()
                        .zip([&source, &replacement_source])
                    {
                        let mut expected = Vec::new();
                        if !system_prompt {
                            expected.extend(input("Host instructions\n保持原文"));
                        }
                        expected.extend(original.clone());
                        assert_eq!(request.prompt, expected);
                    }
                }
                assert_eq!(source, input("first user input"));
                assert_eq!(replacement_source, input("second user input"));
                harness.complete(StopReason::EndTurn).await;
                completion_changed(&mut changes).await.unwrap();
                assert_eq!(*changes.borrow_and_update(), 2);
                assert_eq!(
                    harness
                        .session
                        .snapshot()
                        .await
                        .unwrap()
                        .last_completed
                        .unwrap()
                        .run,
                    second
                );
                // Completion watch does not take the UI's ordered events.
                assert!(
                    matches!(harness.event().await, Event::Completed(value) if value.run == run)
                );
                assert!(
                    matches!(harness.event().await, Event::Completed(value) if value.run == second)
                );
                assert_eq!(calls.load(Ordering::SeqCst), 1);
                harness.finish().await;
                assert!(completion_changed(&mut changes).await.is_err());
            }
        }
    }

    #[tokio::test]
    async fn asynchronous_prepare_keeps_receiving_and_does_not_open_until_success() {
        let release = Arc::new(Notify::new());
        let gate = release.clone();
        let calls = Arc::new(AtomicU64::new(0));
        let callback_calls = calls.clone();
        let mut harness = Harness::new(
            Open::Load("business".into()),
            Scenario {
                prepare: Some(Arc::new(move |_| {
                    callback_calls.fetch_add(1, Ordering::SeqCst);
                    let gate = gate.clone();
                    Box::pin(async move {
                        gate.notified().await;
                        Ok(OpenSetup {
                            instructions: Some(String::new()),
                            ..OpenSetup::default()
                        })
                    })
                })),
                ..Scenario::default()
            },
        );
        assert!(matches!(harness.event().await, Event::Initialized(_)));
        harness
            .updates(vec![update(
                "business",
                text("received during host preparation"),
            )])
            .await;
        assert!(matches!(harness.event().await, Event::Update(_)));
        assert!(!harness.session.snapshot().await.unwrap().ready);
        assert!(matches!(
            harness.session.submit(input("too early")).await,
            Err(Error::NotReady)
        ));
        assert!(peer_lock(&harness.state).opens.is_empty());
        release.notify_one();
        harness.ready().await;
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        assert_eq!(peer_lock(&harness.state).opens, vec!["load"]);
        harness
            .session
            .submit(input("no empty instruction block"))
            .await
            .unwrap();
        harness.wait(|peer| !peer.prompts.is_empty()).await;
        assert_eq!(
            peer_lock(&harness.state).prompt_requests[0].prompt,
            input("no empty instruction block")
        );
        harness.complete(StopReason::EndTurn).await;
        assert!(matches!(harness.event().await, Event::Completed(_)));
        harness.finish().await;
    }

    #[tokio::test]
    async fn invalid_protocol_is_rejected_before_preparation() {
        use agent_client_protocol::UntypedRole;
        let (client_writer, agent_reader) = tokio::io::duplex(64 * 1024);
        let (agent_writer, client_reader) = tokio::io::duplex(64 * 1024);
        // Agent.v1 normalizes initialize responses; the SDK raw role preserves an invalid version.
        let peer = tokio::spawn(
        UntypedRole
            .builder()
            .on_receive_request(
                async |_: InitializeRequest,
                       responder: agent_client_protocol::Responder<InitializeResponse>,
                       _: agent_client_protocol::ConnectionTo<UntypedRole>| {
                    responder.respond(InitializeResponse::new(ProtocolVersion::V0))
                },
                agent_client_protocol::on_receive_request!(),
            )
            .on_receive_request(
                async |_: NewSessionRequest,
                       _: agent_client_protocol::Responder<NewSessionResponse>,
                       _: agent_client_protocol::ConnectionTo<UntypedRole>|
                       -> Result<(), RpcError> {
                    panic!("invalid protocol must not send session/new")
                },
                agent_client_protocol::on_receive_request!(),
            )
            .connect_with(
                ByteStreams::new(agent_writer.compat_write(), agent_reader.compat()),
                async |connection| {
                    connection.incoming_closed().await;
                    Ok(())
                },
            ),
    );
        let (session, _observer, driver) = channel(OpenRequest {
            cwd: "/unused".into(),
            intent: Open::New,
            cleanup: CleanupBudget::new(Duration::from_secs(2)),
            expected_server_version: None,
            prepare: Some(Arc::new(|_| {
                panic!("invalid protocol must not invoke prepare")
            })),
        });
        let driver = tokio::spawn(driver.run_isolated(client_writer, client_reader));
        // The official client rejects V0 before producing a typed InitializeResponse.
        match opened(&session).await {
            Err(Error::Rpc(error)) => assert_eq!(
                error.code,
                agent_client_protocol::ErrorCode::INVALID_REQUEST
            ),
            result => panic!("invalid protocol must fail at initialize: {result:?}"),
        }
        let exit = tokio::time::timeout(Duration::from_secs(5), driver)
            .await
            .unwrap()
            .unwrap();
        assert!(
            matches!(exit.reason, ExitReason::OpenFailed(Error::Rpc(error))
        if error.code == agent_client_protocol::ErrorCode::INVALID_REQUEST)
        );
        tokio::time::timeout(Duration::from_secs(5), peer)
            .await
            .unwrap()
            .unwrap()
            .unwrap();
    }

    #[tokio::test]
    async fn preparation_errors_and_version_rejections_never_send_lifecycle_requests() {
        for failure in [
            "server-version",
            "prepare",
            "host-preparation",
            "http-capability",
        ] {
            let calls = Arc::new(AtomicU64::new(0));
            let callback_calls = calls.clone();
            let mut scenario = Scenario {
                prepare: Some(Arc::new(move |_| {
                    callback_calls.fetch_add(1, Ordering::SeqCst);
                    Box::pin(async move {
                        if failure == "prepare" {
                            Err(Error::Rpc(
                                RpcError::invalid_params().data("host preparation failed"),
                            ))
                        } else if failure == "host-preparation" {
                            Err(Error::Preparation("native helper asset is missing".into()))
                        } else {
                            Ok(OpenSetup {
                                mcp_servers: vec![http_server()],
                                instructions: None,
                            })
                        }
                    })
                })),
                ..Scenario::default()
            };
            if failure == "server-version" {
                scenario.expected_server_version = Some("required".into());
            }
            let harness = Harness::new(Open::New, scenario);
            let session = harness.session.clone();
            let state = harness.state.clone();
            let mut changes = session.completion_changes();
            let error = opened(&session).await.unwrap_err();
            match (failure, error) {
                ("server-version", Error::ServerVersionMismatch)
                | ("http-capability", Error::Unsupported) => {}
                ("prepare", Error::Rpc(error)) => assert_eq!(
                    error,
                    RpcError::invalid_params().data("host preparation failed")
                ),
                ("host-preparation", Error::Preparation(message)) => {
                    assert_eq!(message, "native helper asset is missing");
                }
                (_, error) => panic!("unexpected {failure} result: {error:?}"),
            }
            let exit = harness.join().await;
            assert!(matches!(exit.reason, ExitReason::OpenFailed(_)));
            assert!(peer_lock(&state).opens.is_empty());
            assert_eq!(
                calls.load(Ordering::SeqCst),
                u64::from(matches!(
                    failure,
                    "prepare" | "host-preparation" | "http-capability"
                ))
            );
            assert!(completion_changed(&mut changes).await.is_err());
            assert_eq!(*changes.borrow(), 0);
            let snapshot = session.snapshot().await.unwrap();
            assert!(snapshot.closing);
            assert!(!snapshot.ready);
            assert!(snapshot.last_completed.is_none());
        }
    }

    #[tokio::test]
    async fn close_eof_and_driver_cancellation_drop_pending_preparation_and_wake_waiters() {
        for ending in ["close", "eof", "driver-drop"] {
            let (dropped, cancelled) = oneshot::channel::<()>();
            let dropped = Arc::new(Mutex::new(Some(dropped)));
            let started = Arc::new(Notify::new());
            let entered = started.clone();
            let harness = Harness::new(
                Open::New,
                Scenario {
                    prepare: Some(Arc::new(move |_| {
                        let guard = dropped.lock().unwrap().take().expect("prepare called once");
                        let entered = entered.clone();
                        Box::pin(async move {
                            let _guard = guard;
                            entered.notify_one();
                            std::future::pending::<Result<OpenSetup, Error>>().await
                        })
                    })),
                    ..Scenario::default()
                },
            );
            tokio::time::timeout(Duration::from_secs(5), started.notified())
                .await
                .unwrap();
            let session = harness.session.clone();
            let state = harness.state.clone();
            let mut changes = session.completion_changes();
            assert!(session.snapshot().await.unwrap().last_completed.is_none());
            match ending {
                "close" => session.close().await.unwrap(),
                "eof" => harness.control.send(PeerCommand::Eof).await.unwrap(),
                "driver-drop" => harness.driver.abort(),
                _ => unreachable!(),
            }
            if ending == "driver-drop" {
                assert!(harness.driver.await.unwrap_err().is_cancelled());
                tokio::time::timeout(Duration::from_secs(5), harness.peer)
                    .await
                    .unwrap()
                    .unwrap()
                    .unwrap();
            } else {
                let exit = harness.join().await;
                assert!(!exit.cleanup_timed_out);
            }
            assert!(
                tokio::time::timeout(Duration::from_secs(5), cancelled)
                    .await
                    .unwrap()
                    .is_err()
            );
            assert!(matches!(
                opened(&session).await,
                Err(Error::Closed | Error::Rpc(_))
            ));
            assert!(peer_lock(&state).opens.is_empty());
            assert_eq!(peer_lock(&state).closes, 0);
            assert!(completion_changed(&mut changes).await.is_err());
            assert_eq!(*changes.borrow(), 0);
        }
    }

    #[tokio::test]
    async fn official_new_load_resume_and_realtime_load_replay() {
        for intent in [
            Open::New,
            Open::Load("business".into()),
            Open::Resume("business".into()),
        ] {
            let mut harness = Harness::new(
                intent.clone(),
                Scenario {
                    load_replay: true,
                    ..Scenario::default()
                },
            );
            let Event::Initialized(capabilities) = harness.event().await else {
                panic!("initialize must precede every setup or replay event");
            };
            assert_eq!(*capabilities, Scenario::default().capabilities);
            if matches!(intent, Open::Load(_)) {
                assert!(matches!(
                    harness.event().await,
                    Event::Update(SessionNotification {
                        update: SessionUpdate::AgentMessageChunk(_),
                        ..
                    })
                ));
                assert!(matches!(
                    harness.event().await,
                    Event::Update(SessionNotification {
                        update: SessionUpdate::ConfigOptionUpdate(_),
                        ..
                    })
                ));
                let replaying = harness.session.snapshot().await.unwrap();
                assert!(
                    !replaying.ready,
                    "history must arrive while Load response is still held"
                );
                assert_eq!(replaying.config_options, Some(configs("b")));
                harness
                    .control
                    .send(PeerCommand::ReleaseLoad)
                    .await
                    .unwrap();
            }
            let ready = harness.ready().await;
            assert_eq!(ready.session_id.to_string(), "business");
            assert_eq!(
                harness.session.opened().await.unwrap().to_string(),
                "business"
            );
            assert!(
                harness
                    .session
                    .snapshot()
                    .await
                    .unwrap()
                    .server_info
                    .is_none()
            );
            assert_eq!(ready.config_options, Some(configs("a")));
            let snapshot = harness.session.snapshot().await.unwrap();
            assert_eq!(
                snapshot.config_options,
                Some(configs("a")),
                "setup response follows pre-load update"
            );
            assert!(peer_lock(&harness.state).boolean_advertised);
            let initialize = peer_lock(&harness.state)
                .initialize_request
                .as_ref()
                .unwrap()
                .to_untyped_message()
                .unwrap();
            assert!(
                initialize.params["clientCapabilities"]["session"]["configOptions"]["boolean"]
                    .as_object()
                    .unwrap()
                    .is_empty()
            );
            assert_eq!(
                peer_lock(&harness.state).opens,
                vec![match intent {
                    Open::New => "new",
                    Open::Load(_) => "load",
                    Open::Resume(_) => "resume",
                }]
            );
            let exit = harness.finish().await;
            assert!(exit.sdk_finished && !exit.cleanup_timed_out);
        }
    }

    async fn opened(session: &Session) -> Result<SessionId, Error> {
        tokio::time::timeout(Duration::from_secs(5), session.opened())
            .await
            .expect("open must settle")
    }

    #[tokio::test]
    async fn initialized_capabilities_use_the_original_byte_window_without_failing_open() {
        let mut meta = Meta::new();
        meta.insert("large".into(), "x".repeat(8 * 1024 * 1024).into());
        let mut harness = Harness::new(
            Open::New,
            Scenario {
                capabilities: Scenario::default().capabilities.meta(meta),
                ..Scenario::default()
            },
        );
        assert!(matches!(
            harness.event().await,
            Event::Gap(Gap::WindowExceeded)
        ));
        assert!(harness.observer.recv().await.is_none());
        assert_eq!(
            opened(&harness.session).await.unwrap().to_string(),
            "business"
        );
        assert_eq!(peer_lock(&harness.state).opens, vec!["new"]);
        let exit = harness.finish().await;
        assert_eq!(exit.observation_gap, Some(Gap::WindowExceeded));
    }

    #[tokio::test]
    async fn expected_server_version_is_checked_before_every_business_open() {
        for intent in [
            Open::New,
            Open::Load("business".into()),
            Open::Resume("business".into()),
        ] {
            for version in [None, Some("other"), Some("1.2.3")] {
                let mut harness = Harness::new(
                    intent.clone(),
                    Scenario {
                        expected_server_version: Some("1.2.3".into()),
                        server_info: version
                            .map(|version| Implementation::new("any-agent", version)),
                        ..Scenario::default()
                    },
                );
                if version == Some("1.2.3") {
                    assert_eq!(
                        opened(&harness.session).await.unwrap().to_string(),
                        "business"
                    );
                    harness.ready().await;
                    assert_eq!(peer_lock(&harness.state).opens.len(), 1);
                    harness.finish().await;
                } else {
                    assert!(matches!(
                        opened(&harness.session).await,
                        Err(Error::ServerVersionMismatch)
                    ));
                    assert!(matches!(
                        harness.event().await,
                        Event::Failed(Error::ServerVersionMismatch)
                    ));
                    let session = harness.session.clone();
                    let state = harness.state.clone();
                    let exit = harness.join().await;
                    assert!(peer_lock(&state).opens.is_empty());
                    assert!(matches!(
                        exit.reason,
                        ExitReason::OpenFailed(Error::ServerVersionMismatch)
                    ));
                    assert_eq!(
                        exit.server_info.as_ref().map(|info| info.version.as_str()),
                        version
                    );
                    assert!(!exit.auth_methods.is_empty());
                    assert!(matches!(
                        opened(&session).await,
                        Err(Error::ServerVersionMismatch)
                    ));
                }
            }
        }
    }

    #[tokio::test]
    async fn opened_survives_load_replay_gap_and_direct_observer_drop() {
        for drop_observer in [false, true] {
            let mut harness = Harness::new(
                Open::Load("business".into()),
                Scenario {
                    load_replay: true,
                    ..Scenario::default()
                },
            );
            harness.wait(|state| state.held_load.is_some()).await;
            if drop_observer {
                drop(std::mem::replace(
                    &mut harness.observer,
                    observe::channel().1,
                ));
            } else {
                harness
                    .updates(
                        (0..65)
                            .map(|_| update("business", text("history")))
                            .collect(),
                    )
                    .await;
            }
            harness
                .control
                .send(PeerCommand::ReleaseLoad)
                .await
                .unwrap();
            assert_eq!(
                opened(&harness.session).await.unwrap().to_string(),
                "business"
            );
            if !drop_observer {
                assert!(matches!(
                    harness.event().await,
                    Event::Gap(Gap::WindowExceeded)
                ));
                assert!(harness.observer.recv().await.is_none());
            }
            let session = harness.session.clone();
            harness.finish().await;
            assert_eq!(opened(&session).await.unwrap().to_string(), "business");
        }
    }

    #[tokio::test]
    async fn cancelled_opened_waiter_preserves_same_success_or_rpc_failure() {
        for fail in [false, true] {
            let harness = Harness::new(
                Open::Load("business".into()),
                Scenario {
                    load_replay: true,
                    ..Scenario::default()
                },
            );
            harness.wait(|state| state.held_load.is_some()).await;
            let mut waiter = Box::pin(harness.session.opened());
            tokio::select! {
                biased;
                result = &mut waiter => panic!("open is still held: {result:?}"),
                () = std::future::ready(()) => {}
            }
            drop(waiter);
            harness
                .control
                .send(if fail {
                    PeerCommand::FailLoad(RpcError::auth_required())
                } else {
                    PeerCommand::ReleaseLoad
                })
                .await
                .unwrap();
            let session = harness.session.clone();
            for _ in 0..2 {
                match opened(&session).await {
                    Err(Error::Rpc(error)) if fail => {
                        assert_eq!(error, RpcError::auth_required());
                    }
                    Ok(id) if !fail => assert_eq!(id.to_string(), "business"),
                    result => panic!("unexpected open result: {result:?}"),
                }
            }
            if fail {
                let exit = harness.join().await;
                assert!(matches!(exit.reason, ExitReason::OpenFailed(Error::Rpc(_))));
                assert!(matches!(opened(&session).await, Err(Error::Rpc(_))));
            } else {
                harness.finish().await;
            }
        }
    }

    #[tokio::test]
    async fn opened_ends_on_eof_close_or_driver_cancellation_before_ready() {
        for ending in ["eof", "close", "close-then-response", "driver-drop"] {
            let harness = Harness::new(
                Open::Load("business".into()),
                Scenario {
                    load_replay: true,
                    ..Scenario::default()
                },
            );
            harness.wait(|state| state.held_load.is_some()).await;
            match ending {
                "eof" => harness.control.send(PeerCommand::Eof).await.unwrap(),
                "close" | "close-then-response" => {
                    harness.session.close().await.unwrap();
                    assert!(matches!(opened(&harness.session).await, Err(Error::Closed)));
                    if ending == "close-then-response" {
                        harness
                            .control
                            .send(PeerCommand::ReleaseLoad)
                            .await
                            .unwrap();
                    }
                }
                "driver-drop" => harness.driver.abort(),
                _ => unreachable!(),
            }
            let session = harness.session.clone();
            if ending == "driver-drop" {
                assert!(harness.driver.await.unwrap_err().is_cancelled());
                tokio::time::timeout(Duration::from_secs(5), harness.peer)
                    .await
                    .unwrap()
                    .unwrap()
                    .unwrap();
            } else {
                harness.join().await;
            }
            for _ in 0..2 {
                let result = opened(&session).await;
                if ending == "eof" {
                    assert!(matches!(result, Err(Error::Closed | Error::Rpc(_))));
                } else {
                    assert!(matches!(result, Err(Error::Closed)));
                }
            }
        }
        let (session, observer, driver) = channel(OpenRequest {
            cwd: "/unused".into(),
            intent: Open::New,
            cleanup: CleanupBudget::new(Duration::from_secs(1)),
            expected_server_version: None,
            prepare: None,
        });
        drop(driver);
        drop(observer);
        assert!(matches!(opened(&session).await, Err(Error::Closed)));
    }

    #[tokio::test]
    async fn opened_preserves_real_sdk_io_failure() {
        struct BrokenReader;
        impl tokio::io::AsyncRead for BrokenReader {
            fn poll_read(
                self: std::pin::Pin<&mut Self>,
                _: &mut std::task::Context<'_>,
                _: &mut tokio::io::ReadBuf<'_>,
            ) -> std::task::Poll<std::io::Result<()>> {
                std::task::Poll::Ready(Err(std::io::Error::other("open input failed")))
            }
        }
        let (session, _observer, driver) = channel(OpenRequest {
            cwd: "/unused".into(),
            intent: Open::New,
            cleanup: CleanupBudget::new(Duration::from_secs(1)),
            expected_server_version: None,
            prepare: None,
        });
        let exit = tokio::time::timeout(
            Duration::from_secs(5),
            driver.run_isolated(tokio::io::sink(), BrokenReader),
        )
        .await
        .unwrap();
        let sdk_error = exit.sdk_error.expect("real SDK read error");
        for _ in 0..2 {
            match opened(&session).await {
                Err(Error::Rpc(error)) => assert_eq!(error, sdk_error),
                result => panic!("SDK error must remain observable: {result:?}"),
            }
        }
    }

    #[tokio::test]
    async fn capabilities_fail_before_open_without_fallback() {
        for intent in [
            Open::Load("business".into()),
            Open::Resume("business".into()),
        ] {
            let mut harness = Harness::new(
                intent,
                Scenario {
                    capabilities: AgentCapabilities::default(),
                    ..Scenario::default()
                },
            );
            assert!(matches!(harness.event().await, Event::Initialized(_)));
            assert!(matches!(
                harness.event().await,
                Event::Failed(Error::Unsupported)
            ));
            let exit = harness.driver.await.unwrap();
            harness.peer.await.unwrap().unwrap();
            assert!(matches!(
                exit.reason,
                ExitReason::OpenFailed(Error::Unsupported)
            ));
            assert!(peer_lock(&harness.state).opens.is_empty());
        }
    }

    #[tokio::test]
    async fn configuration_full_lists_follow_wire_order_and_failure_keeps_push() {
        let mut harness = Harness::new(Open::New, Scenario::default());
        harness.ready().await;
        for (before, result, after, expected) in [
            (Some(configs("b")), Ok(configs("a")), None, configs("a")),
            (None, Ok(configs("a")), Some(configs("b")), configs("b")),
            (
                Some(configs("b")),
                Err(RpcError::invalid_params()),
                None,
                configs("b"),
            ),
        ] {
            let session = harness.session.clone();
            let call = tokio::spawn(async move {
                session
                    .set_config("model".into(), SessionConfigOptionValue::value_id("b"))
                    .await
            });
            harness.wait(|state| !state.configs.is_empty()).await;
            assert!(matches!(
                harness
                    .session
                    .set_config("effort".into(), SessionConfigOptionValue::value_id("fast"))
                    .await,
                Err(Error::Busy)
            ));
            let events = usize::from(before.is_some())
                + usize::from(result.is_ok())
                + usize::from(after.is_some());
            let success = result.is_ok();
            harness
                .control
                .send(PeerCommand::Config {
                    before,
                    result,
                    after,
                })
                .await
                .unwrap();
            assert_eq!(call.await.unwrap().is_ok(), success);
            for _ in 0..events {
                let _ = harness.event().await;
            }
            assert_eq!(
                harness.session.snapshot().await.unwrap().config_options,
                Some(expected)
            );
        }
        // Distinct typed boolean and effort IDs must survive the production request entry.
        for (id, value) in [
            ("safe", SessionConfigOptionValue::boolean(false)),
            ("effort", SessionConfigOptionValue::value_id("fast")),
        ] {
            let session = harness.session.clone();
            let expected = value.clone();
            let call = tokio::spawn(async move { session.set_config(id.into(), value).await });
            harness.wait(|state| !state.configs.is_empty()).await;
            let request = peer_lock(&harness.state)
                .config_requests
                .last()
                .unwrap()
                .clone();
            assert_eq!(request.config_id.to_string(), id);
            assert_eq!(request.value, expected);
            let wire = request.to_untyped_message().unwrap();
            assert_eq!(wire.params["configId"].as_str(), Some(id));
            if id == "safe" {
                assert_eq!(wire.params["type"].as_str(), Some("boolean"));
                assert_eq!(wire.params["value"].as_bool(), Some(false));
            } else {
                assert_eq!(wire.params["value"].as_str(), Some("fast"));
            }
            harness
                .control
                .send(PeerCommand::Config {
                    before: None,
                    result: Ok(configs("a")),
                    after: None,
                })
                .await
                .unwrap();
            call.await.unwrap().unwrap();
            assert!(matches!(harness.event().await, Event::Configured(_)));
        }
        harness.finish().await;
    }

    #[tokio::test]
    async fn prompt_busy_permissions_cancel_tail_replacement_and_stale_interrupt() {
        let mut harness = Harness::new(Open::New, Scenario::default());
        harness.ready().await;
        let first = harness.session.submit(input("first")).await.unwrap();
        harness.wait(|state| state.prompts.len() == 1).await;
        assert!(matches!(
            harness
                .session
                .interrupt(RunId {
                    instance: first.instance + 1,
                    ..first
                })
                .await,
            Err(Error::Stale)
        ));
        assert!(matches!(
            harness.session.submit(input("busy")).await,
            Err(Error::Busy)
        ));
        harness.control.send(PeerCommand::Permission).await.unwrap();
        let permission = match harness.event().await {
            Event::Permission { id, .. } => id,
            event => panic!("{event:?}"),
        };
        assert!(matches!(
            harness
                .session
                .answer_permission(
                    PermissionId {
                        instance: permission.instance + 1,
                        ..permission
                    },
                    Some("allow".into())
                )
                .await,
            Err(Error::Stale)
        ));
        assert!(matches!(
            harness
                .session
                .answer_permission(permission, Some("wrong".into()))
                .await,
            Err(Error::InvalidOption)
        ));
        harness
            .session
            .answer_permission(permission, Some("allow".into()))
            .await
            .unwrap();
        harness
            .wait(|state| state.permission_results.len() == 1)
            .await;
        assert!(matches!(
            peer_lock(&harness.state).permission_results[0],
            RequestPermissionOutcome::Selected(_)
        ));
        harness.control.send(PeerCommand::Permission).await.unwrap();
        assert!(matches!(harness.event().await, Event::Permission { .. }));
        let session = harness.session.clone();
        let replacement =
            tokio::spawn(async move { session.replace(first, input("replacement")).await });
        harness
            .wait(|state| state.cancels == 1 && state.permission_results.len() == 2)
            .await;
        assert!(matches!(
            peer_lock(&harness.state).permission_results[1],
            RequestPermissionOutcome::Cancelled
        ));
        assert!(matches!(
            harness.session.replace(first, input("busy")).await,
            Err(Error::Busy)
        ));
        // The cancel notification alone cannot complete or start another prompt.
        assert_eq!(
            harness.session.snapshot().await.unwrap().active_run,
            Some(first)
        );
        harness.control.send(PeerCommand::Permission).await.unwrap();
        harness
            .wait(|state| state.permission_results.len() == 3)
            .await;
        assert!(matches!(
            peer_lock(&harness.state).permission_results[2],
            RequestPermissionOutcome::Cancelled
        ));
        harness
            .updates(vec![update("business", text("legal tail"))])
            .await;
        assert!(matches!(harness.event().await, Event::Update(_)));
        harness.complete(StopReason::Cancelled).await;
        assert!(matches!(harness.event().await, Event::Completed(_)));
        let second = replacement.await.unwrap().unwrap();
        assert_ne!(first, second);
        harness.wait(|state| state.prompt_requests.len() == 2).await;
        assert!(matches!(
            harness.session.interrupt(first).await,
            Err(Error::Stale)
        ));
        assert_eq!(peer_lock(&harness.state).cancels, 1);
        harness.complete(StopReason::EndTurn).await;
        let completed = match harness.event().await {
            Event::Completed(completed) => completed,
            event => panic!("{event:?}"),
        };
        assert_eq!(completed.run, second);
        assert_eq!(completed.completion_sequence, 2);
        assert!(completed.summary.is_empty());
        assert_eq!(
            peer_lock(&harness.state).prompt_requests[1].prompt,
            input("replacement")
        );
        let exit = harness.finish().await;
        assert_eq!(exit.last_completed.unwrap().run, second);
    }

    #[tokio::test]
    async fn pending_config_does_not_block_prompt_permission_or_interrupt() {
        let mut harness = Harness::new(Open::New, Scenario::default());
        harness.ready().await;
        let session = harness.session.clone();
        let config = tokio::spawn(async move {
            session
                .set_config("effort".into(), SessionConfigOptionValue::value_id("fast"))
                .await
        });
        harness.wait(|state| !state.configs.is_empty()).await;
        let run = harness
            .session
            .submit(input("can run while config waits"))
            .await
            .unwrap();
        harness.wait(|state| !state.prompts.is_empty()).await;
        harness.control.send(PeerCommand::Permission).await.unwrap();
        let id = match harness.event().await {
            Event::Permission { id, .. } => id,
            event => panic!("{event:?}"),
        };
        harness
            .session
            .answer_permission(id, Some("allow".into()))
            .await
            .unwrap();
        harness
            .wait(|state| !state.permission_results.is_empty())
            .await;
        harness.session.interrupt(run).await.unwrap();
        harness.wait(|state| state.cancels == 1).await;
        harness.complete(StopReason::Cancelled).await;
        assert!(matches!(harness.event().await, Event::Completed(_)));
        harness
            .control
            .send(PeerCommand::Config {
                before: Some(configs("b")),
                result: Err(RpcError::invalid_params()),
                after: None,
            })
            .await
            .unwrap();
        assert!(matches!(config.await.unwrap(), Err(Error::Rpc(_))));
        assert!(matches!(harness.event().await, Event::Update(_)));
        assert_eq!(
            harness.session.snapshot().await.unwrap().config_options,
            Some(configs("b"))
        );
        harness.finish().await;
    }

    #[tokio::test]
    async fn permission_window_gap_cancels_existing_and_undeliverable_requests_without_prompt_cancel()
     {
        let mut harness = Harness::new(Open::New, Scenario::default());
        harness.ready().await;
        let run = harness
            .session
            .submit(input("keep the prompt active"))
            .await
            .unwrap();
        harness.wait(|state| !state.prompts.is_empty()).await;
        harness.control.send(PeerCommand::Permission).await.unwrap();
        let id = match harness.event().await {
            Event::Permission { id, .. } => id,
            event => panic!("{event:?}"),
        };
        // The next permission itself exceeds the event window, rather than an unrelated update.
        harness
            .updates((0..64).map(|_| update("business", text("x"))).collect())
            .await;
        harness.control.send(PeerCommand::Permission).await.unwrap();
        harness
            .wait(|state| state.permission_results.len() == 2)
            .await;
        assert!(matches!(
            harness.event().await,
            Event::Gap(Gap::WindowExceeded)
        ));
        assert!(matches!(
            harness
                .session
                .answer_permission(id, Some("allow".into()))
                .await,
            Err(Error::Stale)
        ));
        for _ in 0..5 {
            harness.control.send(PeerCommand::Permission).await.unwrap();
        }
        harness
            .wait(|state| state.permission_results.len() == 7)
            .await;
        assert!(
            peer_lock(&harness.state)
                .permission_results
                .iter()
                .all(|outcome| matches!(outcome, RequestPermissionOutcome::Cancelled))
        );
        assert_eq!(peer_lock(&harness.state).cancels, 0);
        assert_eq!(
            harness.session.snapshot().await.unwrap().active_run,
            Some(run)
        );
        harness
            .session
            .list(ListSessionsRequest::new())
            .await
            .unwrap();
        harness.complete(StopReason::EndTurn).await;
        harness
            .session
            .list(ListSessionsRequest::new())
            .await
            .unwrap();
        assert_eq!(
            harness
                .session
                .snapshot()
                .await
                .unwrap()
                .last_completed
                .unwrap()
                .run,
            run
        );
        assert_eq!(
            peer_lock(&harness.state).permission_results.len(),
            7,
            "no duplicate answers"
        );
        harness.finish().await;
    }

    #[tokio::test]
    async fn permission_receiver_drop_cancels_pending_without_any_new_protocol_traffic() {
        let mut harness = Harness::new(Open::New, Scenario::default());
        harness.ready().await;
        let run = harness.session.submit(input("quiet prompt")).await.unwrap();
        harness.wait(|state| !state.prompts.is_empty()).await;
        harness.control.send(PeerCommand::Permission).await.unwrap();
        assert!(matches!(harness.event().await, Event::Permission { .. }));
        let (_, other) = observe::channel();
        drop(std::mem::replace(&mut harness.observer, other));
        // No notification, command or second permission is sent to make the driver notice the drop.
        harness
            .wait(|state| state.permission_results.len() == 1)
            .await;
        harness.control.send(PeerCommand::Permission).await.unwrap();
        harness
            .wait(|state| state.permission_results.len() == 2)
            .await;
        let snapshot = harness.session.snapshot().await.unwrap();
        assert_eq!(snapshot.observation_gap, Some(Gap::Disconnected));
        assert_eq!(snapshot.active_run, Some(run));
        assert_eq!(peer_lock(&harness.state).cancels, 0);
        assert!(
            peer_lock(&harness.state)
                .permission_results
                .iter()
                .all(|outcome| matches!(outcome, RequestPermissionOutcome::Cancelled))
        );
        harness.complete(StopReason::EndTurn).await;
        harness
            .session
            .list(ListSessionsRequest::new())
            .await
            .unwrap();
        assert!(
            harness
                .session
                .snapshot()
                .await
                .unwrap()
                .active_run
                .is_none()
        );
        harness.finish().await;
    }

    #[tokio::test]
    async fn permission_pending_count_is_bounded_after_consumption_and_reusable_after_answers() {
        let mut harness = Harness::new(Open::New, Scenario::default());
        harness.ready().await;
        let run = harness
            .session
            .submit(input("many permissions"))
            .await
            .unwrap();
        harness.wait(|state| !state.prompts.is_empty()).await;
        let mut ids = Vec::new();
        for _ in 0..64 {
            harness.control.send(PeerCommand::Permission).await.unwrap();
            match harness.event().await {
                Event::Permission { id, .. } => ids.push(id),
                event => panic!("{event:?}"),
            }
        }
        harness.control.send(PeerCommand::Permission).await.unwrap();
        harness
            .wait(|state| state.permission_results.len() == 1)
            .await;
        assert!(matches!(
            peer_lock(&harness.state).permission_results[0],
            RequestPermissionOutcome::Cancelled
        ));
        assert_eq!(
            harness.session.snapshot().await.unwrap().observation_gap,
            None
        );
        harness
            .session
            .answer_permission(ids[0], Some("allow".into()))
            .await
            .unwrap();
        harness
            .wait(|state| state.permission_results.len() == 2)
            .await;
        assert!(matches!(
            peer_lock(&harness.state).permission_results[1],
            RequestPermissionOutcome::Selected(_)
        ));
        harness.control.send(PeerCommand::Permission).await.unwrap();
        let id = match harness.event().await {
            Event::Permission { id, .. } => id,
            event => panic!("{event:?}"),
        };
        harness.session.answer_permission(id, None).await.unwrap();
        harness.session.interrupt(run).await.unwrap();
        harness
            .wait(|state| state.permission_results.len() == 66 && state.cancels == 1)
            .await;
        assert!(matches!(
            harness
                .session
                .answer_permission(ids[1], Some("allow".into()))
                .await,
            Err(Error::Stale)
        ));
        harness.complete(StopReason::Cancelled).await;
        assert!(matches!(harness.event().await, Event::Completed(_)));
        assert_eq!(
            peer_lock(&harness.state).permission_results.len(),
            66,
            "each request answered once"
        );
        harness.finish().await;
    }

    #[tokio::test]
    async fn permission_pending_bytes_are_bounded_after_consumption_and_released_on_answer() {
        let mut harness = Harness::new(Open::New, Scenario::default());
        harness.ready().await;
        let run = harness
            .session
            .submit(input("large legal option IDs"))
            .await
            .unwrap();
        harness.wait(|state| !state.prompts.is_empty()).await;
        let options = vec![PermissionOption::new(
            "a".repeat(3 * 1024 * 1024),
            "Allow",
            PermissionOptionKind::AllowOnce,
        )];
        let mut ids = Vec::new();
        for _ in 0..2 {
            harness
                .control
                .send(PeerCommand::PermissionOptions(options.clone()))
                .await
                .unwrap();
            match harness.event().await {
                Event::Permission { id, request } => {
                    assert_eq!(request.options[0].option_id, options[0].option_id);
                    ids.push(id);
                }
                event => panic!("{event:?}"),
            }
        }
        harness
            .control
            .send(PeerCommand::PermissionOptions(options.clone()))
            .await
            .unwrap();
        harness
            .wait(|state| state.permission_results.len() == 1)
            .await;
        assert_eq!(
            harness.session.snapshot().await.unwrap().observation_gap,
            None
        );
        assert!(matches!(
            peer_lock(&harness.state).permission_results[0],
            RequestPermissionOutcome::Cancelled
        ));
        harness
            .session
            .answer_permission(ids[0], None)
            .await
            .unwrap();
        harness
            .wait(|state| state.permission_results.len() == 2)
            .await;
        harness
            .control
            .send(PeerCommand::PermissionOptions(options))
            .await
            .unwrap();
        let id = match harness.event().await {
            Event::Permission { id, .. } => id,
            event => panic!("{event:?}"),
        };
        harness.session.answer_permission(id, None).await.unwrap();
        harness.session.interrupt(run).await.unwrap();
        harness
            .wait(|state| state.permission_results.len() == 4 && state.cancels == 1)
            .await;
        harness.complete(StopReason::Cancelled).await;
        assert!(matches!(harness.event().await, Event::Completed(_)));
        assert!(
            peer_lock(&harness.state)
                .permission_results
                .iter()
                .all(|outcome| matches!(outcome, RequestPermissionOutcome::Cancelled))
        );
        harness.finish().await;
    }

    #[tokio::test]
    async fn close_cancels_permission_and_waits_for_real_prompt_tail() {
        let mut harness = Harness::new(Open::New, Scenario::default());
        harness.ready().await;
        let run = harness.session.submit(input("active close")).await.unwrap();
        harness.wait(|state| !state.prompts.is_empty()).await;
        harness.control.send(PeerCommand::Permission).await.unwrap();
        let id = match harness.event().await {
            Event::Permission { id, .. } => id,
            event => panic!("{event:?}"),
        };
        harness.session.close().await.unwrap();
        harness
            .wait(|state| state.cancels == 1 && state.permission_results.len() == 1)
            .await;
        assert!(matches!(
            peer_lock(&harness.state).permission_results[0],
            RequestPermissionOutcome::Cancelled
        ));
        assert_eq!(
            peer_lock(&harness.state).closes,
            0,
            "close must not discard the live prompt tail"
        );
        assert!(matches!(
            harness
                .session
                .answer_permission(id, Some("allow".into()))
                .await,
            Err(Error::Closed)
        ));
        assert!(matches!(
            harness.session.submit(input("closed")).await,
            Err(Error::Closed)
        ));
        harness
            .updates(vec![update("business", text("final tail"))])
            .await;
        assert!(matches!(harness.event().await, Event::Update(_)));
        harness.complete(StopReason::Cancelled).await;
        assert!(matches!(harness.event().await, Event::Completed(_)));
        let exit = harness.driver.await.unwrap();
        harness.peer.await.unwrap().unwrap();
        assert!(exit.unfinished_prompt.is_none());
        assert_eq!(exit.last_completed.as_ref().unwrap().run, run);
        assert_eq!(exit.last_completed.unwrap().summary, "final tail");
        assert_eq!(peer_lock(&harness.state).closes, 1);
    }

    #[tokio::test]
    async fn prompt_capabilities_and_list_are_checked_before_publication() {
        for image_supported in [false, true] {
            let mut harness = Harness::new(
                Open::New,
                Scenario {
                    capabilities: AgentCapabilities::new()
                        .prompt_capabilities(PromptCapabilities::new().image(image_supported)),
                    ..Scenario::default()
                },
            );
            harness.ready().await;
            assert_eq!(
                harness
                    .session
                    .snapshot()
                    .await
                    .unwrap()
                    .capabilities
                    .prompt_capabilities
                    .image,
                image_supported
            );
            assert!(matches!(
                harness.session.list(ListSessionsRequest::new()).await,
                Err(Error::Unsupported)
            ));
            let content = vec![ContentBlock::Image(ImageContent::new(
                "aGVsbG8=",
                "image/png",
            ))];
            let result = harness.session.submit(content.clone()).await;
            assert_eq!(result.is_ok(), image_supported);
            if image_supported {
                harness.wait(|state| !state.prompts.is_empty()).await;
                assert_eq!(peer_lock(&harness.state).prompt_requests[0].prompt, content);
                harness.complete(StopReason::EndTurn).await;
                assert!(matches!(harness.event().await, Event::Completed(_)));
            } else {
                assert!(matches!(result, Err(Error::Unsupported)));
                assert!(peer_lock(&harness.state).prompt_requests.is_empty());
            }
            assert_eq!(peer_lock(&harness.state).lists, 0);
            harness.finish().await;
        }
    }

    #[tokio::test]
    async fn auth_required_keeps_actual_agent_guidance_without_auth_or_usage() {
        let mut harness = Harness::new(
            Open::New,
            Scenario {
                auth_required: true,
                ..Scenario::default()
            },
        );
        assert!(matches!(harness.event().await, Event::Initialized(_)));
        assert!(
            matches!(harness.event().await, Event::Failed(Error::Rpc(error)) if error.code == agent_client_protocol::ErrorCode::AUTH_REQUIRED)
        );
        let exit = harness.driver.await.unwrap();
        harness.peer.await.unwrap().unwrap();
        assert_eq!(
            exit.auth_methods,
            vec![crate::auth::AuthMethod {
                id: "agent-login".into(),
                name: "Agent sign in".into(),
                description: Some("Use the server login".into()),
                kind: crate::auth::AuthMethodKind::Agent,
            }]
        );
        assert!(peer_lock(&harness.state).prompt_requests.is_empty());
    }

    #[tokio::test]
    async fn disconnected_observer_is_explicit_but_business_remains_live() {
        let mut harness = Harness::new(Open::New, Scenario::default());
        harness.ready().await;
        let run = harness.session.submit(input("no observer")).await.unwrap();
        harness.wait(|state| !state.prompts.is_empty()).await;
        let (_, other_observer) = observe::channel();
        drop(std::mem::replace(&mut harness.observer, other_observer));
        harness
            .updates(vec![update("business", text("still driven"))])
            .await;
        harness
            .session
            .list(ListSessionsRequest::new())
            .await
            .unwrap();
        let snapshot = harness.session.snapshot().await.unwrap();
        assert_eq!(snapshot.observation_gap, Some(Gap::Disconnected));
        assert_eq!(snapshot.active_run, Some(run));
        let mut changes = harness.session.completion_changes();
        assert!(
            harness
                .session
                .snapshot()
                .await
                .unwrap()
                .last_completed
                .is_none()
        );
        harness
            .control
            .send(PeerCommand::FailPrompt(RpcError::invalid_params()))
            .await
            .unwrap();
        completion_changed(&mut changes).await.unwrap();
        assert_eq!(*changes.borrow_and_update(), 1);
        assert_eq!(
            harness
                .session
                .snapshot()
                .await
                .unwrap()
                .last_completed
                .unwrap()
                .result
                .unwrap_err(),
            RpcError::invalid_params()
        );
        harness
            .session
            .list(ListSessionsRequest::new())
            .await
            .unwrap();
        assert_eq!(
            harness
                .session
                .snapshot()
                .await
                .unwrap()
                .last_completed
                .unwrap()
                .summary,
            "still driven"
        );
        harness.finish().await;
        assert!(completion_changed(&mut changes).await.is_err());
    }

    #[tokio::test]
    async fn observation_window_gap_does_not_cancel_prompt_or_control() {
        let mut harness = Harness::new(Open::New, Scenario::default());
        harness.ready().await;
        let run = harness.session.submit(input("long")).await.unwrap();
        harness.wait(|state| !state.prompts.is_empty()).await;
        harness
            .updates((0..65).map(|_| update("business", text("x"))).collect())
            .await;
        // A real list response is a wire barrier after all preceding updates.
        harness
            .session
            .list(ListSessionsRequest::new())
            .await
            .unwrap();
        assert!(matches!(
            harness.event().await,
            Event::Gap(Gap::WindowExceeded)
        ));
        assert!(harness.observer.recv().await.is_none());
        assert_eq!(
            harness.session.snapshot().await.unwrap().active_run,
            Some(run)
        );
        harness.session.interrupt(run).await.unwrap();
        harness.wait(|state| state.cancels == 1).await;
        harness.complete(StopReason::Cancelled).await;
        // Wait for the true completion via protocol-ordered list, not an idle hint.
        harness
            .session
            .list(ListSessionsRequest::new())
            .await
            .unwrap();
        let snapshot = harness.session.snapshot().await.unwrap();
        assert!(snapshot.active_run.is_none());
        assert_eq!(snapshot.last_completed.unwrap().summary, "x".repeat(65));
        harness.finish().await;
    }

    #[tokio::test]
    async fn bytes_window_is_reusable_and_summary_is_utf8_bounded() {
        let mut harness = Harness::new(Open::New, Scenario::default());
        harness.ready().await;
        harness.session.submit(input("long")).await.unwrap();
        harness.wait(|state| !state.prompts.is_empty()).await;
        for _ in 0..3 {
            harness
                .updates(vec![update("business", text(&"界".repeat(1024 * 1024)))])
                .await;
            assert!(matches!(harness.event().await, Event::Update(_)));
        }
        harness
            .updates(vec![update("business", text(&"x".repeat(8 * 1024 * 1024)))])
            .await;
        assert!(matches!(
            harness.event().await,
            Event::Gap(Gap::WindowExceeded)
        ));
        harness.complete(StopReason::EndTurn).await;
        harness
            .session
            .list(ListSessionsRequest::new())
            .await
            .unwrap();
        let completed = harness
            .session
            .snapshot()
            .await
            .unwrap()
            .last_completed
            .unwrap();
        assert!(completed.truncated);
        assert!(completed.summary.len() <= SUMMARY_LIMIT);
        assert_eq!(completed.summary.chars().last(), Some('界'));
        harness.finish().await;
    }

    #[tokio::test]
    async fn eof_terminates_live_prompt_without_fabricated_completion() {
        let mut harness = Harness::new(Open::New, Scenario::default());
        harness.ready().await;
        let run = harness.session.submit(input("pending")).await.unwrap();
        harness.wait(|state| !state.prompts.is_empty()).await;
        let mut changes = harness.session.completion_changes();
        harness.control.send(PeerCommand::Eof).await.unwrap();
        let exit = tokio::time::timeout(Duration::from_secs(5), harness.driver)
            .await
            .unwrap()
            .unwrap();
        harness.peer.await.unwrap().unwrap();
        assert!(matches!(exit.reason, ExitReason::IncomingClosed));
        assert!(
            exit.last_completed.is_none() || exit.last_completed.as_ref().unwrap().result.is_err()
        );
        assert!(exit.unfinished_prompt == Some(run) || exit.last_completed.is_some());
        let snapshot = harness.session.snapshot().await.unwrap();
        assert!(snapshot.closing);
        assert!(!snapshot.ready);
        assert_eq!(snapshot.active_run, exit.unfinished_prompt);
        assert_eq!(
            snapshot
                .last_completed
                .as_ref()
                .map(|completed| (&completed.run, &completed.result)),
            exit.last_completed
                .as_ref()
                .map(|completed| (&completed.run, &completed.result)),
        );
        let sequence = exit
            .last_completed
            .map_or(0, |completed| completed.completion_sequence);
        // SDK EOF may settle an RPC error, but closure must never invent a completion.
        if completion_changed(&mut changes).await.is_ok() {
            assert_eq!(*changes.borrow_and_update(), sequence);
            assert!(completion_changed(&mut changes).await.is_err());
        }
        assert_eq!(*changes.borrow(), sequence);
    }

    #[tokio::test]
    async fn close_capability_failure_and_shared_budget_report_local_facts() {
        for (capability, failure, hangs) in [
            (false, false, false),
            (true, true, false),
            (true, false, true),
        ] {
            let capabilities = if capability {
                Scenario::default().capabilities
            } else {
                AgentCapabilities::default()
            };
            let mut harness = Harness::new(
                Open::New,
                Scenario {
                    capabilities,
                    close_failure: failure,
                    close_hangs: hangs,
                    ..Scenario::default()
                },
            );
            harness.ready().await;
            let state = harness.state.clone();
            let exit = harness.finish().await;
            assert_eq!(peer_lock(&state).closes, usize::from(capability));
            assert_eq!(exit.close_error.is_some(), failure || !capability);
            assert_eq!(exit.cleanup_timed_out, hangs);
            assert_eq!(exit.sdk_finished, !hangs);
        }
    }

    #[tokio::test(start_paused = true)]
    async fn close_uses_one_deadline_across_prompt_tail_and_close_rpc() {
        let budget = CleanupBudget::new(Duration::from_secs(5));
        let mut harness = Harness::with_cleanup(
            Open::New,
            Scenario {
                close_hangs: true,
                ..Scenario::default()
            },
            budget.clone(),
        );
        harness.ready().await;
        harness
            .session
            .submit(input("tail uses cleanup time"))
            .await
            .unwrap();
        harness.wait(|state| !state.prompts.is_empty()).await;
        harness.session.close().await.unwrap();
        harness.wait(|state| state.cancels == 1).await;
        let deadline = budget.deadline();
        tokio::time::advance(Duration::from_secs(4)).await;
        harness.complete(StopReason::Cancelled).await;
        assert!(matches!(harness.event().await, Event::Completed(_)));
        let exit = harness.driver.await.unwrap();
        harness.peer.await.unwrap().unwrap();
        assert_eq!(tokio::time::Instant::now(), deadline);
        assert!(exit.cleanup_timed_out && !exit.sdk_finished);
        assert!(exit.unfinished_prompt.is_none());
        assert!(exit.unfinished_controls);
        assert!(
            exit.close_error.is_none(),
            "no fabricated protocol error for missing close response"
        );
    }

    #[tokio::test(start_paused = true)]
    async fn close_timeout_reports_unfinished_prompt_instead_of_success() {
        let mut harness = Harness::new(Open::New, Scenario::default());
        harness.ready().await;
        let run = harness
            .session
            .submit(input("never terminal"))
            .await
            .unwrap();
        harness.wait(|state| !state.prompts.is_empty()).await;
        harness.session.close().await.unwrap();
        let exit = harness.driver.await.unwrap();
        harness.peer.await.unwrap().unwrap();
        assert!(exit.cleanup_timed_out && !exit.sdk_finished);
        assert_eq!(exit.unfinished_prompt, Some(run));
        assert!(exit.last_completed.is_none());
        assert_eq!(peer_lock(&harness.state).closes, 0);
    }

    #[tokio::test]
    async fn only_missing_configuration_uses_real_legacy_mode() {
        for config in [None, Some(vec![])] {
            let mut harness = Harness::new(
                Open::New,
                Scenario {
                    config: config.clone(),
                    modes: Some(SessionModeState::new(
                        "ask",
                        vec![
                            SessionMode::new("ask", "Ask"),
                            SessionMode::new("act", "Act"),
                        ],
                    )),
                    ..Scenario::default()
                },
            );
            harness.ready().await;
            let result = harness.session.set_mode("act".into()).await;
            assert_eq!(result.is_ok(), config.is_none());
            if config.is_none() {
                assert!(
                    matches!(harness.event().await, Event::ModeSet(id) if id.to_string() == "act")
                );
                assert_eq!(
                    peer_lock(&harness.state).modes,
                    vec![SessionModeId::new("act")]
                );
                harness
                    .updates(vec![update(
                        "business",
                        SessionUpdate::CurrentModeUpdate(CurrentModeUpdate::new("ask")),
                    )])
                    .await;
                assert!(matches!(harness.event().await, Event::Update(_)));
                assert_eq!(
                    harness
                        .session
                        .snapshot()
                        .await
                        .unwrap()
                        .modes
                        .unwrap()
                        .current_mode_id
                        .to_string(),
                    "ask"
                );
            } else {
                assert!(matches!(result, Err(Error::Unsupported)));
                assert!(peer_lock(&harness.state).modes.is_empty());
            }
            harness.finish().await;
        }
    }
}
