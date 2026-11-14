//! 宿主 I/O 上唯一的 SDK 驱动与初始化结果；没有进程或产品配置责任。
use std::collections::BTreeMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use agent_client_protocol::schema::ProtocolVersion;
use agent_client_protocol::v1::{ConnectionTo, Responder};
use agent_client_protocol::{Agent, ByteStreams, Client};
use tokio::sync::{OwnedSemaphorePermit, Semaphore, watch};
use tokio_util::compat::{TokioAsyncReadCompatExt, TokioAsyncWriteCompatExt};
use tokio_util::sync::CancellationToken;

use crate::auth::{AsyncRead, AsyncWrite, CleanupBudget};
use crate::session::{Error, Shared, lock, schema::*};

const LEASES: u32 = u32::MAX >> 3;
type Members = Arc<Mutex<BTreeMap<u64, Shared>>>;

#[derive(Clone)]
pub(crate) struct Ready {
    pub(crate) sdk: ConnectionTo<Agent>,
    pub(crate) initialize: InitializeResponse,
}

/// 克隆只共享同一准备结果，不重新连接或协商。宿主必须持有并汇合原 Driver。
#[derive(Clone)]
pub struct Connection {
    ready: watch::Receiver<Option<Result<Ready, Error>>>,
    members: Members,
    leases: Arc<Semaphore>,
    cancellation: CancellationToken,
}

/// 唯一消费连接 I/O 的驱动。取消后先收束租约，再排空 SDK；整个过程共用原预算。
pub struct Driver {
    connection: Connection,
    result: watch::Sender<Option<Result<Ready, Error>>>,
    expected_version: Option<String>,
    cleanup: CleanupBudget,
}

/// SDK 驱动的实际终态；对端断开、正常排空与关闭预算耗尽不能互相冒充。
#[derive(Debug)]
pub struct Exit {
    pub sdk_finished: bool,
    pub cleanup_timed_out: bool,
    pub result: Result<(), Error>,
}

pub fn channel(expected_version: Option<String>, cleanup: CleanupBudget) -> (Connection, Driver) {
    let (result, ready) = watch::channel(None);
    let connection = Connection {
        ready,
        members: Arc::new(Mutex::new(BTreeMap::new())),
        leases: Arc::new(Semaphore::new(LEASES as usize)),
        cancellation: CancellationToken::new(),
    };
    let driver = Driver {
        connection: connection.clone(),
        result,
        expected_version,
        cleanup,
    };
    (connection, driver)
}

impl Connection {
    pub fn cancel(&self) {
        self.cancellation.cancel();
        let members: Vec<_> = self
            .members
            .lock()
            .expect("ACP members poisoned")
            .values()
            .cloned()
            .collect();
        for state in members {
            lock(&state).revoke();
        }
    }
    pub fn is_closed(&self) -> bool {
        self.cancellation.is_cancelled()
    }
    pub async fn cancelled(&self) {
        self.cancellation.cancelled().await;
    }

    pub async fn initialized(&self) -> Result<InitializeResponse, Error> {
        Ok(self.ready().await?.initialize)
    }

    pub(crate) async fn ready(&self) -> Result<Ready, Error> {
        let mut ready = self.ready.clone();
        loop {
            if let Some(result) = ready.borrow_and_update().clone() {
                return result.and_then(|value| {
                    if self.is_closed() {
                        Err(Error::Closed)
                    } else {
                        Ok(value)
                    }
                });
            }
            tokio::select! {
                biased;
                () = self.cancelled() => return match ready.borrow().clone() {
                    Some(Err(error)) => Err(error),
                    _ => Err(Error::Closed),
                },
                changed = ready.changed() => changed.map_err(|_| Error::Closed)?,
            }
        }
    }

    pub(crate) fn lease(&self) -> Result<OwnedSemaphorePermit, Error> {
        if self.is_closed() {
            return Err(Error::Closed);
        }
        self.leases
            .clone()
            .try_acquire_owned()
            .map_err(|_| Error::Busy)
    }

    pub(crate) fn register(&self, state: Shared) -> Result<Registration, Error> {
        if self.is_closed() {
            return Err(Error::Closed);
        }
        let mut members = self.members.lock().expect("ACP members poisoned");
        if self.is_closed() {
            return Err(Error::Closed);
        }
        let id = lock(&state).session_id.clone();
        if let Some(id) = id {
            for existing in members.values() {
                if lock(existing).session_id.as_ref() == Some(&id) {
                    return Err(Error::Busy);
                }
            }
        }
        let instance = lock(&state).instance;
        members.insert(instance, state);
        Ok(Registration {
            members: self.members.clone(),
            instance,
        })
    }

    /// 新身份只由有序响应绑定；同一对端身份不能同时进入两个活动 State。
    pub(crate) fn setup(
        &self,
        state: &Shared,
        result: Result<NewSessionResponse, agent_client_protocol::Error>,
    ) {
        let members = self.members.lock().expect("ACP members poisoned");
        if let Ok(response) = &result {
            let duplicate = members.values().any(|other| {
                !Arc::ptr_eq(other, state)
                    && lock(other).session_id.as_ref() == Some(&response.session_id)
            });
            if duplicate {
                drop(members);
                lock(state).fail_open(Error::Busy);
                return;
            }
        }
        let mut owner = lock(state);
        if !owner.finished {
            if let Ok(response) = &result {
                owner.session_id = Some(response.session_id.clone());
            }
            drop(members);
            owner.setup(result);
        } else {
            drop(owner);
            drop(members);
            if let Ok(response) = result
                && let Some(Ok(ready)) = self.ready.borrow().clone()
            {
                if ready
                    .initialize
                    .agent_capabilities
                    .session_capabilities
                    .close
                    .is_some()
                {
                    let retained = state.clone();
                    let close = ready
                        .sdk
                        .prepare_request(CloseSessionRequest::new(response.session_id))
                        .on_receiving_result(async move |result| {
                            if let Err(error) = result {
                                lock(&retained).close_error = Some(error.into());
                            }
                            Ok(())
                        });
                    if let Err(error) = close {
                        lock(state).close_error = Some(error.into());
                    }
                } else {
                    lock(state).close_error = Some(Error::Unsupported);
                }
            }
        }
    }
}

pub(crate) struct Registration {
    members: Members,
    instance: u64,
}
impl Drop for Registration {
    fn drop(&mut self) {
        self.members
            .lock()
            .expect("ACP members poisoned")
            .remove(&self.instance);
    }
}

fn find(members: &Members, id: &SessionId) -> Option<Shared> {
    // 克隆引用后释放集合锁，再进入单个会话；从不持集合锁调用 SDK。
    let states: Vec<_> = members
        .lock()
        .expect("ACP members poisoned")
        .values()
        .cloned()
        .collect();
    states
        .into_iter()
        .find(|state| lock(state).session_id.as_ref() == Some(id))
}

impl Driver {
    pub async fn run<W, R>(self, outgoing: W, incoming: R) -> Exit
    where
        W: AsyncWrite + Unpin + Send + 'static,
        R: AsyncRead + Unpin + Send + 'static,
    {
        struct Lifetime(Connection);
        impl Drop for Lifetime {
            fn drop(&mut self) {
                self.0.cancel();
            }
        }
        let _lifetime = Lifetime(self.connection.clone());
        let peer_closed = Arc::new(AtomicBool::new(false));
        let inbound_closed = peer_closed.clone();
        let shared = self.connection.clone();
        let updates = shared.clone();
        let permissions = shared.clone();
        let outcome = self.result.clone();
        let sdk = Client
            .v1()
            .on_receive_notification(
                async move |notification: SessionNotification, _: ConnectionTo<Agent>| {
                    if !updates.is_closed()
                        && let Some(state) = find(&updates.members, &notification.session_id)
                    {
                        lock(&state).update(notification);
                    }
                    Ok(())
                },
                agent_client_protocol::on_receive_notification!(),
            )
            .on_receive_request(
                async move |request: RequestPermissionRequest,
                            responder: Responder<RequestPermissionResponse>,
                            _: ConnectionTo<Agent>| {
                    if !permissions.is_closed()
                        && let Some(state) = find(&permissions.members, &request.session_id)
                    {
                        lock(&state).permission(request, responder);
                    } else {
                        responder.respond(RequestPermissionResponse::new(
                            RequestPermissionOutcome::Cancelled,
                        ))?;
                    }
                    Ok(())
                },
                agent_client_protocol::on_receive_request!(),
            )
            .connect_with(
                ByteStreams::new(outgoing.compat_write(), incoming.compat()),
                async move |sdk| {
                    let initialize = sdk
                        .send_request(
                            InitializeRequest::new(ProtocolVersion::V1)
                                .client_info(Implementation::new(
                                    "anywork",
                                    env!("CARGO_PKG_VERSION"),
                                ))
                                .client_capabilities(
                                    ClientCapabilities::new().session(
                                        ClientSessionCapabilities::new().config_options(
                                            SessionConfigOptionsCapabilities::new()
                                                .boolean(BooleanConfigOptionCapabilities::new()),
                                        ),
                                    ),
                                ),
                        )
                        .block_task()
                        .await;
                    let ready = initialize.map_err(Error::from).and_then(|initialize| {
                        if initialize.protocol_version != ProtocolVersion::V1 {
                            return Err(Error::UnsupportedVersion);
                        }
                        if self.expected_version.as_ref().is_some_and(|expected| {
                            initialize.agent_info.as_ref().map(|info| &info.version)
                                != Some(expected)
                        }) {
                            return Err(Error::ServerVersionMismatch);
                        }
                        Ok(Ready {
                            sdk: sdk.clone(),
                            initialize,
                        })
                    });
                    let failed = ready.is_err();
                    outcome.send_replace(Some(ready));
                    if failed {
                        return Ok(());
                    }
                    tokio::select! {
                        biased;
                        () = shared.cancelled() => {}
                        () = sdk.incoming_closed() => {
                            if !shared.is_closed() { inbound_closed.store(true, Ordering::Relaxed); }
                            shared.cancel();
                        }
                    }
                    let _all = shared.leases.clone().acquire_many_owned(LEASES).await;
                    Ok(())
                },
            );
        tokio::pin!(sdk);
        let (sdk_finished, cleanup_timed_out, mut result) = tokio::select! {
            result = &mut sdk => (true, false, result.map_err(Error::from)),
            () = self.connection.cancelled() => {
                match tokio::time::timeout_at(self.cleanup.deadline(), &mut sdk).await {
                    Ok(result) => (true, false, result.map_err(Error::from)),
                    Err(_) => (false, true, Err(Error::Closed)),
                }
            }
        };
        if result.is_ok() && peer_closed.load(Ordering::Relaxed) {
            result = Err(Error::Closed);
        }
        if self.result.borrow().is_none() {
            self.result
                .send_replace(Some(Err(result.clone().err().unwrap_or(Error::Closed))));
        }
        self.connection.cancel();
        Exit {
            sdk_finished,
            cleanup_timed_out,
            result,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{auth, session};
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::time::Duration;
    use tokio::sync::oneshot;

    async fn permission(observer: &mut session::Observer, expected: &str) -> session::PermissionId {
        loop {
            match observer.recv().await.expect("live observer") {
                session::Event::Permission { id, request } => {
                    assert_eq!(request.session_id.to_string(), expected);
                    return id;
                }
                session::Event::Update(update) => {
                    assert_eq!(update.session_id.to_string(), expected)
                }
                _ => {}
            }
        }
    }

    fn configs(value: &str) -> Vec<SessionConfigOption> {
        vec![SessionConfigOption::select(
            "model",
            "Model",
            value.to_owned(),
            vec![
                SessionConfigSelectOption::new("a", "A"),
                SessionConfigSelectOption::new("b", "B"),
            ],
        )]
    }

    #[tokio::test]
    async fn shared_initialize_permissions_probe_cancellation_and_independent_close() {
        tokio::time::timeout(Duration::from_secs(10), async {
            let initializes = Arc::new(AtomicUsize::new(0));
            let pending = Arc::new(Mutex::new(
                BTreeMap::<String, Responder<PromptResponse>>::new(),
            ));
            let observed = Arc::new(Mutex::new(Vec::<(String, Vec<ContentBlock>)>::new()));
            let init_count = initializes.clone();
            let prompts = pending.clone();
            let requests = observed.clone();
            let cancels = pending.clone();
            let control = Arc::new(Mutex::new(
                None::<Responder<SetSessionConfigOptionResponse>>,
            ));
            let held_control = control.clone();
            let peer = Agent
                .v1()
                .on_receive_request(
                    async move |_: InitializeRequest,
                                reply: Responder<InitializeResponse>,
                                _: ConnectionTo<Client>| {
                        init_count.fetch_add(1, Ordering::Relaxed);
                        reply.respond(
                            InitializeResponse::new(ProtocolVersion::V1).agent_capabilities(
                                AgentCapabilities::new().session_capabilities(
                                    SessionCapabilities::new()
                                        .close(SessionCloseCapabilities::new()),
                                ),
                            ),
                        )
                    },
                    agent_client_protocol::on_receive_request!(),
                )
                .on_receive_request(
                    async |request: NewSessionRequest,
                           reply: Responder<NewSessionResponse>,
                           _: ConnectionTo<Client>| {
                        assert!(request.mcp_servers.is_empty());
                        reply.respond(
                            NewSessionResponse::new(request.cwd.to_string_lossy().into_owned())
                                .config_options(configs("a")),
                        )
                    },
                    agent_client_protocol::on_receive_request!(),
                )
                .on_receive_request(
                    async move |_: SetSessionConfigOptionRequest,
                                reply: Responder<SetSessionConfigOptionResponse>,
                                _: ConnectionTo<Client>| {
                        *held_control.lock().unwrap() = Some(reply);
                        Ok(())
                    },
                    agent_client_protocol::on_receive_request!(),
                )
                .on_receive_request(
                    async move |request: PromptRequest,
                                reply: Responder<PromptResponse>,
                                cx: ConnectionTo<Client>| {
                        let id = request.session_id.to_string();
                        requests.lock().unwrap().push((id.clone(), request.prompt));
                        prompts.lock().unwrap().insert(id.clone(), reply);
                        cx.send_notification(SessionNotification::new(
                            id.clone(),
                            SessionUpdate::AgentMessageChunk(ContentChunk::new(
                                ContentBlock::Text(TextContent::new(format!("only {id}"))),
                            )),
                        ))?;
                        if id != "/probe" {
                            cx.prepare_request(RequestPermissionRequest::new(
                                id,
                                ToolCallUpdate::new("tool", ToolCallUpdateFields::new()),
                                vec![PermissionOption::new(
                                    "once",
                                    "Once",
                                    PermissionOptionKind::AllowOnce,
                                )],
                            ))
                            .on_receiving_result(async |result| {
                                assert!(result.is_ok());
                                Ok(())
                            })?;
                        }
                        Ok(())
                    },
                    agent_client_protocol::on_receive_request!(),
                )
                .on_receive_notification(
                    async move |request: CancelNotification, _: ConnectionTo<Client>| {
                        if let Some(reply) = cancels
                            .lock()
                            .unwrap()
                            .remove(&request.session_id.to_string())
                        {
                            reply.respond(PromptResponse::new(StopReason::Cancelled))?;
                        }
                        Ok(())
                    },
                    agent_client_protocol::on_receive_notification!(),
                )
                .on_receive_request(
                    async |_: CloseSessionRequest,
                           reply: Responder<CloseSessionResponse>,
                           _: ConnectionTo<Client>| {
                        reply.respond(CloseSessionResponse::new())
                    },
                    agent_client_protocol::on_receive_request!(),
                );
            let (outgoing, peer_read) = tokio::io::duplex(64 * 1024);
            let (peer_write, incoming) = tokio::io::duplex(64 * 1024);
            let (peer_ready, peer_context) = oneshot::channel();
            let peer = tokio::spawn(peer.connect_with(
                ByteStreams::new(peer_write.compat_write(), peer_read.compat()),
                async |cx| {
                    let _ = peer_ready.send(cx.clone());
                    cx.incoming_closed().await;
                    Ok(())
                },
            ));
            let (connection, sdk) = channel(None, CleanupBudget::new(Duration::from_secs(2)));
            let sdk = tokio::spawn(sdk.run(outgoing, incoming));
            let open = |cwd: &str| {
                session::channel(session::OpenRequest {
                    cwd: cwd.into(),
                    intent: session::Open::New,
                    cleanup: CleanupBudget::new(Duration::from_secs(2)),
                    expected_server_version: None,
                    prepare: None,
                })
            };
            let (a, mut updates_a, driver_a) = open("/a");
            let (b, mut updates_b, driver_b) = open("/b");
            let join_a = tokio::spawn(driver_a.run(connection.clone()));
            let join_b = tokio::spawn(driver_b.run(connection.clone()));
            a.opened().await.unwrap();
            b.opened().await.unwrap();
            let run_a = a
                .submit(vec![ContentBlock::Text(TextContent::new("a"))])
                .await
                .unwrap();
            let run_b = b
                .submit(vec![ContentBlock::Text(TextContent::new("b"))])
                .await
                .unwrap();
            assert_ne!(run_a.instance, run_b.instance);
            let permission_a = permission(&mut updates_a, "/a").await;
            let permission_b = permission(&mut updates_b, "/b").await;
            assert!(matches!(
                b.answer_permission(permission_a, None).await,
                Err(session::Error::Stale)
            ));
            a.answer_permission(permission_a, None).await.unwrap();
            let config_session = a.clone();
            let config = tokio::spawn(async move {
                config_session
                    .set_config("model".into(), SessionConfigOptionValue::value_id("b"))
                    .await
            });
            while control.lock().unwrap().is_none() {
                tokio::task::yield_now().await;
            }
            pending
                .lock()
                .unwrap()
                .remove("/a")
                .unwrap()
                .respond(PromptResponse::new(StopReason::EndTurn))
                .unwrap();
            a.close().await.unwrap();
            let exit_a = join_a.await.unwrap();
            assert!(!exit_a.cleanup_timed_out && exit_a.unfinished_controls);
            assert!(matches!(config.await.unwrap(), Err(session::Error::Closed)));
            control
                .lock()
                .unwrap()
                .take()
                .unwrap()
                .respond(SetSessionConfigOptionResponse::new(configs("b")))
                .unwrap();
            assert!(b.snapshot().await.unwrap().active_run.is_some());
            assert!(!connection.is_closed());
            let peer_context = peer_context.await.unwrap();
            // The old auth transport had an 8 MiB lifetime cap. Business bytes now belong
            // only to the reusable session window and must not poison later auth/usage.
            for _ in 0..3 {
                peer_context
                    .send_notification(SessionNotification::new(
                        "/b",
                        SessionUpdate::AgentMessageChunk(ContentChunk::new(ContentBlock::Text(
                            TextContent::new("x".repeat(3 * 1024 * 1024)),
                        ))),
                    ))
                    .unwrap();
                assert!(matches!(
                    updates_b.recv().await,
                    Some(session::Event::Update(_))
                ));
            }
            // Duplicate restore cannot attach a second active state to the same remote identity.
            let (duplicate, _, duplicate_driver) = session::channel(session::OpenRequest {
                cwd: "/b".into(),
                intent: session::Open::Load("/b".into()),
                cleanup: CleanupBudget::new(Duration::from_secs(2)),
                expected_server_version: None,
                prepare: None,
            });
            let duplicate_join = tokio::spawn(duplicate_driver.run(connection.clone()));
            assert!(matches!(
                duplicate.opened().await,
                Err(session::Error::Busy)
            ));
            duplicate_join.await.unwrap();
            let (progress, _) = watch::channel(auth::AuthProgress::Initializing);
            let (_commands, commands) = tokio::sync::mpsc::channel(1);
            let cancel = CancellationToken::new();
            let query = tokio::spawn(auth::run(
                connection.clone(),
                auth::AuthRequest {
                    probe_cwd: "/probe".into(),
                    expected_server_version: None,
                    action: auth::AuthAction::QueryUsage,
                    commands,
                    cleanup: CleanupBudget::new(Duration::from_secs(2)),
                    cancellation: cancel.clone(),
                    progress,
                },
            ));
            while !pending.lock().unwrap().contains_key("/probe") {
                tokio::task::yield_now().await;
            }
            cancel.cancel();
            assert_eq!(
                query.await.unwrap().unwrap_err().kind(),
                auth::AuthFailureKind::Cancelled
            );
            assert!(!connection.is_closed());
            b.answer_permission(permission_b, Some("once".into()))
                .await
                .unwrap();
            let (unknown_done, unknown) = oneshot::channel();
            peer_context
                .prepare_request(RequestPermissionRequest::new(
                    "unknown",
                    ToolCallUpdate::new("tool", ToolCallUpdateFields::new()),
                    vec![],
                ))
                .on_receiving_result(async move |result| {
                    let _ = unknown_done.send(result);
                    Ok(())
                })
                .unwrap();
            assert!(matches!(
                unknown.await.unwrap().unwrap().outcome,
                RequestPermissionOutcome::Cancelled
            ));
            assert_eq!(
                a.snapshot().await.unwrap().config_options,
                Some(configs("a")),
                "late control result cannot rewrite a closed member"
            );
            pending
                .lock()
                .unwrap()
                .remove("/b")
                .unwrap()
                .respond(PromptResponse::new(StopReason::EndTurn))
                .unwrap();
            connection.cancel();
            assert!(matches!(
                b.submit(vec![ContentBlock::Text(TextContent::new(
                    "after account revoke"
                ))])
                .await,
                Err(session::Error::Closed)
            ));
            assert!(matches!(
                b.close().await,
                Ok(()) | Err(session::Error::Closed)
            ));
            assert!(!join_b.await.unwrap().cleanup_timed_out);
            let prompts = observed.lock().unwrap();
            assert_eq!(
                prompts
                    .iter()
                    .filter(|(id, content)| id == "/probe"
                        && *content == vec![ContentBlock::Text(TextContent::new("/usage"))])
                    .count(),
                1
            );
            drop(prompts);
            assert_eq!(initializes.load(Ordering::Relaxed), 1);
            connection.cancel();
            sdk.await.unwrap().result.unwrap();
            peer.await.unwrap().unwrap();
        })
        .await
        .expect("all shared session owners settled");
    }

    #[tokio::test]
    async fn eof_settles_every_pending_open_without_reinitializing() {
        tokio::time::timeout(Duration::from_secs(5), async {
            let count = Arc::new(AtomicUsize::new(0));
            let initialized = count.clone();
            let held = Arc::new(Mutex::new(Vec::new()));
            let opens = held.clone();
            let stop = CancellationToken::new();
            let peer_stop = stop.clone();
            let peer = Agent
                .v1()
                .on_receive_request(
                    async move |_: InitializeRequest,
                                reply: Responder<InitializeResponse>,
                                _: ConnectionTo<Client>| {
                        initialized.fetch_add(1, Ordering::Relaxed);
                        reply.respond(InitializeResponse::new(ProtocolVersion::V1))
                    },
                    agent_client_protocol::on_receive_request!(),
                )
                .on_receive_request(
                    async move |_: NewSessionRequest,
                                reply: Responder<NewSessionResponse>,
                                _: ConnectionTo<Client>| {
                        opens.lock().unwrap().push(reply);
                        Ok(())
                    },
                    agent_client_protocol::on_receive_request!(),
                );
            let (outgoing, peer_read) = tokio::io::duplex(64 * 1024);
            let (peer_write, incoming) = tokio::io::duplex(64 * 1024);
            let peer = tokio::spawn(peer.connect_with(
                ByteStreams::new(peer_write.compat_write(), peer_read.compat()),
                async move |_| {
                    peer_stop.cancelled().await;
                    Ok(())
                },
            ));
            let (connection, driver) = channel(None, CleanupBudget::new(Duration::from_secs(1)));
            let sdk = tokio::spawn(driver.run(outgoing, incoming));
            let request = |cwd: &str| session::OpenRequest {
                cwd: cwd.into(),
                intent: session::Open::New,
                cleanup: CleanupBudget::new(Duration::from_secs(1)),
                expected_server_version: None,
                prepare: None,
            };
            let (a, _observer_a, driver_a) = session::channel(request("/a"));
            let (b, _observer_b, driver_b) = session::channel(request("/b"));
            let a_join = tokio::spawn(driver_a.run(connection.clone()));
            let b_join = tokio::spawn(driver_b.run(connection.clone()));
            while held.lock().unwrap().len() != 2 {
                tokio::task::yield_now().await;
            }
            // Simulate an abrupt peer crash, not an orderly SDK drain retaining responders.
            peer.abort();
            assert!(peer.await.unwrap_err().is_cancelled());
            assert!(a.opened().await.is_err());
            assert!(b.opened().await.is_err());
            a_join.await.unwrap();
            b_join.await.unwrap();
            let _ = sdk.await.unwrap();
            assert!(connection.initialized().await.is_err());
            assert_eq!(count.load(Ordering::Relaxed), 1);
        })
        .await
        .expect("EOF completed every original open and driver");
    }
}
