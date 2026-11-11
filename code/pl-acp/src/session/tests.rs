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
        });
        let driver = tokio::spawn(driver.run(client_writer, client_reader));
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
                    if new_scenario.auth_required { return responder.respond_with_error(RpcError::auth_required()); }
                    connection.send_notification(update("business", text("unbound must not be claimed")))?;
                    responder.respond(NewSessionResponse::new("business")
                        .config_options(new_scenario.config.clone()).modes(new_scenario.modes.clone()))
                }, agent_client_protocol::on_receive_request!())
                .on_receive_request(async move |request: LoadSessionRequest, responder: Responder<LoadSessionResponse>, connection: ConnectionTo<Client>| {
                    assert_eq!(request.session_id.to_string(), "business");
                    peer_lock(&load_state).opens.push("load");
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
                .on_receive_request(async move |_: ResumeSessionRequest, responder: Responder<ResumeSessionResponse>, _: ConnectionTo<Client>| {
                    peer_lock(&resume_state).opens.push("resume");
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
                    server_info: version.map(|version| Implementation::new("any-agent", version)),
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
    });
    let exit = tokio::time::timeout(
        Duration::from_secs(5),
        driver.run(tokio::io::sink(), BrokenReader),
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
async fn permission_window_gap_cancels_existing_and_undeliverable_requests_without_prompt_cancel() {
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
            .summary,
        "still driven"
    );
    harness.finish().await;
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
    harness.control.send(PeerCommand::Eof).await.unwrap();
    let exit = tokio::time::timeout(Duration::from_secs(5), harness.driver)
        .await
        .unwrap()
        .unwrap();
    harness.peer.await.unwrap().unwrap();
    assert!(matches!(exit.reason, ExitReason::IncomingClosed));
    assert!(exit.last_completed.is_none() || exit.last_completed.as_ref().unwrap().result.is_err());
    assert!(exit.unfinished_prompt == Some(run) || exit.last_completed.is_some());
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
        assert_eq!(exit.close_error.is_some(), failure);
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
            assert!(matches!(harness.event().await, Event::ModeSet(id) if id.to_string() == "act"));
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
