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
use agent_client_protocol::{Agent, ByteStreams, Client, JsonRpcMessage, JsonRpcResponse};
use tokio::sync::{Notify, OwnedSemaphorePermit, Semaphore, mpsc, oneshot, watch};
use tokio_util::compat::{TokioAsyncReadCompatExt, TokioAsyncWriteCompatExt};

use crate::auth::{AsyncRead, AsyncWrite, CleanupBudget};

/// 公开接口直接消费同一版本的官方协议类型。
pub use agent_client_protocol::v1::schema;
use schema::*;

mod observe;
pub use observe::{Event, Gap, Observer};

#[cfg(test)]
mod tests;

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

#[derive(Debug, Clone)]
pub struct OpenRequest {
    pub cwd: String,
    pub intent: Open,
    pub cleanup: CleanupBudget,
    /// Some 要求 initialize.agentInfo.version 精确相等；None 仅校验 ACP V1。
    pub expected_server_version: Option<String>,
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
    Snapshot(Reply<Snapshot>),
    Close(Reply<()>),
}

/// 有限命令入口；不复制运行状态。队列满时明确 Busy，不建立可靠输入队列。
#[derive(Clone)]
pub struct Session {
    commands: mpsc::Sender<Command>,
    opened: watch::Receiver<Option<Result<SessionId, Error>>>,
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

    pub async fn snapshot(&self) -> Result<Snapshot, Error> {
        self.call(Command::Snapshot).await
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
}

/// 必须先取得 Observer，再启动 driver，才能看到 Load 响应前的历史回放。
pub fn channel(request: OpenRequest) -> (Session, Observer, Driver) {
    let (tx, commands) = mpsc::channel(16);
    let (events, observer) = observe::channel();
    let (opened, open_result) = watch::channel(None);
    let session_id = match &request.intent {
        Open::New => None,
        Open::Load(id) | Open::Resume(id) => Some(id.clone()),
    };
    let state = Arc::new(Mutex::new(State {
        instance: NEXT_INSTANCE.fetch_add(1, Ordering::Relaxed),
        session_id,
        ready: false,
        opened,
        initialized: None,
        capabilities: AgentCapabilities::default(),
        config_options: None,
        modes: None,
        active: None,
        last_completed: None,
        next_run: 0,
        permission_sequence: 0,
        permissions: Vec::new(),
        permission_bytes: Arc::new(Semaphore::new(PERMISSION_BYTES)),
        replacement: None,
        config_pending: false,
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
            commands: tx,
            opened: open_result,
        },
        observer,
        Driver {
            request,
            commands,
            state,
        },
    )
}

type Shared = Arc<Mutex<State>>;
fn lock(state: &Shared) -> MutexGuard<'_, State> {
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

struct State {
    instance: u64,
    session_id: Option<SessionId>,
    ready: bool,
    // Only State/Driver and SDK callbacks own the sender. Dropping an unrun/cancelled
    // driver releases it, so pending waiters end with Closed instead of hanging.
    opened: watch::Sender<Option<Result<SessionId, Error>>>,
    initialized: Option<Result<InitializeResponse, agent_client_protocol::Error>>,
    capabilities: AgentCapabilities,
    config_options: Option<Vec<SessionConfigOption>>,
    modes: Option<SessionModeState>,
    active: Option<Active>,
    last_completed: Option<Completed>,
    next_run: u64,
    permission_sequence: u64,
    permissions: Vec<Permission>,
    permission_bytes: Arc<Semaphore>,
    replacement: Option<(Vec<ContentBlock>, Reply<RunId>)>,
    config_pending: bool,
    list_pending: bool,
    closing: bool,
    close_sent: bool,
    close_done: bool,
    close_error: Option<Error>,
    reason: Option<ExitReason>,
    events: observe::Sender,
    wake: Arc<Notify>,
    server_info: Option<Implementation>,
    auth_methods: Vec<crate::auth::AuthMethod>,
}

impl State {
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

    fn update(&mut self, notification: SessionNotification) {
        if self.session_id.as_ref() != Some(&notification.session_id) {
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

    fn setup(&mut self, result: Result<NewSessionResponse, agent_client_protocol::Error>) {
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
                self.settle_open(Ok(response.session_id.clone()));
                self.emit(Event::Ready(response), size);
            }
            Err(error) => self.fail_open(error.into()),
        }
        self.wake.notify_one();
    }

    fn fail_open(&mut self, error: Error) {
        self.settle_open(Err(error.clone()));
        let size = match &error {
            Error::Rpc(error) => rpc_error_size(error),
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

    fn permission(
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
    /// 消费受监督 I/O，驱动协议及全部命令；宿主负责 spawn/join 和真实 worker 回收。
    pub async fn run<W, R>(self, outgoing: W, incoming: R) -> Exit
    where
        W: AsyncWrite + Unpin + Send + 'static,
        R: AsyncRead + Unpin + Send + 'static,
    {
        let state = self.state.clone();
        let updates = state.clone();
        let permissions = state.clone();
        let (closing, mut deadline) = watch::channel(None);
        let connection = Client
            .v1()
            .on_receive_notification(
                async move |notification: SessionNotification, _: ConnectionTo<Agent>| {
                    lock(&updates).update(notification);
                    Ok(())
                },
                agent_client_protocol::on_receive_notification!(),
            )
            .on_receive_request(
                async move |request: RequestPermissionRequest,
                            responder: Responder<RequestPermissionResponse>,
                            _: ConnectionTo<Agent>| {
                    lock(&permissions).permission(request, responder);
                    Ok(())
                },
                agent_client_protocol::on_receive_request!(),
            )
            .connect_with(
                ByteStreams::new(outgoing.compat_write(), incoming.compat()),
                async move |connection| self.drive(connection, closing).await,
            );
        tokio::pin!(connection);
        let expires = async move {
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
        let (sdk_finished, cleanup_timed_out, sdk_error) = tokio::select! {
            result = &mut connection => (true, false, result.err()),
            () = expires => (false, true, None),
        };
        let mut state = lock(&state);
        if !state.ready && !matches!(state.reason, Some(ExitReason::OpenFailed(_))) {
            let error = sdk_error.clone().map_or(Error::Closed, Error::from);
            state.settle_open(Err(error.clone()));
            state.emit(
                Event::Failed(error.clone()),
                Ok(match &error {
                    Error::Rpc(error) => rpc_error_size(error),
                    _ => 256,
                }),
            );
            if state.reason.is_none() {
                state.reason = Some(ExitReason::OpenFailed(error));
            }
        }
        state.cancel_permissions();
        if let Some((_, reply)) = state.replacement.take() {
            let _ = reply.send(Err(Error::Closed));
        }
        Exit {
            reason: state.reason.clone().unwrap_or(ExitReason::IncomingClosed),
            close_error: state.close_error.clone(),
            sdk_error,
            sdk_finished,
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
    ) -> Result<(), agent_client_protocol::Error> {
        let state = self.state.clone();
        let observation_lost = lock(&state).events.invalidated();
        tokio::pin!(observation_lost);
        let mut observation_ended = false;
        connection
            .prepare_request(InitializeRequest::new(ProtocolVersion::V1))
            .on_receiving_result({
                let state = state.clone();
                async move |result| {
                    let mut state = lock(&state);
                    state.initialized = Some(result);
                    state.wake.notify_one();
                    Ok(())
                }
            })?;
        let wake = lock(&state).wake.clone();
        loop {
            {
                let mut owner = lock(&state);
                if let Some(initialize) = owner.initialized.take() {
                    match initialize {
                        Ok(initialize) if initialize.protocol_version == ProtocolVersion::V1 => {
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
                                self.open(&connection, &mut owner);
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
                    closing.send_replace(Some(self.request.cleanup.deadline()));
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
            tokio::select! {
                () = &mut observation_lost, if !observation_ended => {
                    observation_ended = true;
                    lock(&state).cancel_permissions();
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
        closing.send_replace(Some(self.request.cleanup.deadline()));
        Ok(())
    }

    fn open(&self, connection: &ConnectionTo<Agent>, owner: &mut State) {
        let state = self.state.clone();
        let cwd = &self.request.cwd;
        let result = match &self.request.intent {
            Open::New => connection
                .prepare_request(NewSessionRequest::new(cwd))
                .on_receiving_result(async move |result| {
                    lock(&state).setup(result);
                    Ok(())
                }),
            Open::Load(id) if owner.capabilities.load_session => {
                let id = id.clone();
                connection
                    .prepare_request(LoadSessionRequest::new(id.clone(), cwd))
                    .on_receiving_result(async move |result| {
                        lock(&state).setup(result.map(|r| {
                            NewSessionResponse::new(id)
                                .config_options(r.config_options)
                                .modes(r.modes)
                                .meta(r.meta)
                        }));
                        Ok(())
                    })
            }
            Open::Resume(id) if owner.capabilities.session_capabilities.resume.is_some() => {
                let id = id.clone();
                connection
                    .prepare_request(ResumeSessionRequest::new(id.clone(), cwd))
                    .on_receiving_result(async move |result| {
                        lock(&state).setup(result.map(|r| {
                            NewSessionResponse::new(id)
                                .config_options(r.config_options)
                                .modes(r.modes)
                                .meta(r.meta)
                        }));
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
            Command::Snapshot(reply) => {
                let _ = reply.send(Ok(owner.snapshot()));
            }
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
                let callback_reply = reply.clone();
                let result =
                    connection
                        .prepare_request(request)
                        .on_receiving_result(async move |result| {
                            lock(&state).list_pending = false;
                            deliver(&callback_reply, result.map_err(Error::from));
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
    content: Vec<ContentBlock>,
) -> Result<RunId, Error> {
    let session_id = owner.ready()?;
    if owner.active.is_some() {
        return Err(Error::Busy);
    }
    validate_content(&owner.capabilities.prompt_capabilities, &content)?;
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
            if owner.active.as_ref().map(|run| run.id) == Some(id) {
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
                owner.last_completed = Some(completed);
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
    owner.reason = Some(ExitReason::Closed);
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
        let callback_reply = reply.clone();
        let result = connection
            .prepare_request(SetSessionConfigOptionRequest::new(session, id, value))
            .on_receiving_result(async move |result| {
                let mut owner = lock(&state);
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
        let callback_reply = reply.clone();
        let result = connection
            .prepare_request(SetSessionModeRequest::new(session, id.clone()))
            .on_receiving_result(async move |result| {
                let mut owner = lock(&state);
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
