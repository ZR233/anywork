use std::sync::{Arc, Mutex, PoisonError};
use std::time::Duration;

use agent_client_protocol::schema::ProtocolVersion;
use agent_client_protocol::v1::schema::{
    AgentCapabilities, AuthMethod as SdkAuthMethod, AuthMethodAgent, AuthenticateRequest,
    AuthenticateResponse, CloseSessionRequest, CloseSessionResponse, ContentBlock, ContentChunk,
    Implementation, InitializeRequest, InitializeResponse, NewSessionRequest, NewSessionResponse,
    PromptRequest, PromptResponse, SessionCapabilities, SessionCloseCapabilities,
    SessionNotification, SessionUpdate, StopReason, TextContent,
};
use agent_client_protocol::v1::{ConnectionTo, Responder};
use agent_client_protocol::{Agent, Client};

use super::*;

const VERSION: &str = "1.4.5";
const METHOD: &str = "fixture-login";
const REPORT: &str = "### Quota Limits\n- No quota limits reported.";

#[derive(Clone, Copy, Default)]
enum Choice {
    #[default]
    Authenticate,
    Cancel,
    Disconnect,
    Unsupported,
}

#[derive(Clone, Copy, Default)]
struct Scenario {
    initialize_delay: Duration,
    probe_delay: Duration,
    authenticate_delay: Duration,
    human_delay: Duration,
    requires_login: bool,
    deny_after_auth: bool,
    close_failure: bool,
    prompt_failure: bool,
    cancel_at: Option<AuthStage>,
    choice: Choice,
}

#[derive(Default, Debug)]
struct Observed {
    initializes: usize,
    probes: usize,
    authenticates: usize,
    closes: usize,
    prompts: Vec<Vec<ContentBlock>>,
    default_capabilities: bool,
}

async fn run(action: AuthAction, scenario: Scenario) -> (Result<AuthOutcome, AuthError>, Observed) {
    let observed = Arc::new(Mutex::new(Observed::default()));
    let cancellation = CancellationToken::new();
    let disconnect = CancellationToken::new();
    let (client_writer, agent_reader) = tokio::io::duplex(64 * 1024);
    let (agent_writer, client_reader) = tokio::io::duplex(64 * 1024);
    let transport = ByteStreams::new(agent_writer.compat_write(), agent_reader.compat());
    let agent_observed = Arc::clone(&observed);
    let agent_cancel = cancellation.clone();
    let agent_disconnect = disconnect.clone();
    let agent = tokio::spawn(async move {
        Agent.v1()
            .on_receive_request({
                let observed = agent_observed.clone();
                let cancel = agent_cancel.clone();
                async move |request: InitializeRequest, responder: Responder<InitializeResponse>, _: ConnectionTo<Client>| {
                    {
                        let mut observed = observed.lock().unwrap_or_else(PoisonError::into_inner);
                        observed.initializes += 1;
                        observed.default_capabilities = request.client_capabilities == Default::default();
                    }
                    tokio::time::sleep(scenario.initialize_delay).await;
                    if scenario.cancel_at == Some(AuthStage::Initialize) { cancel.cancel(); }
                    responder.respond(InitializeResponse::new(ProtocolVersion::V1)
                        .agent_info(Implementation::new("fixture", VERSION))
                        .auth_methods(vec![SdkAuthMethod::Agent(AuthMethodAgent::new(METHOD, "Fixture login"))])
                        .agent_capabilities(AgentCapabilities::new().session_capabilities(
                            SessionCapabilities::new().close(SessionCloseCapabilities::new()))))
                }
            }, agent_client_protocol::on_receive_request!())
            .on_receive_request({
                let observed = agent_observed.clone();
                let cancel = agent_cancel.clone();
                async move |_: NewSessionRequest, responder: Responder<NewSessionResponse>, _: ConnectionTo<Client>| {
                    let required = {
                        let mut observed = observed.lock().unwrap_or_else(PoisonError::into_inner);
                        observed.probes += 1;
                        scenario.requires_login && (observed.authenticates == 0 || scenario.deny_after_auth)
                    };
                    tokio::time::sleep(scenario.probe_delay).await;
                    if scenario.cancel_at == Some(AuthStage::Probe) { cancel.cancel(); }
                    if required { responder.respond_with_error(RpcError::auth_required()) }
                    else { responder.respond(NewSessionResponse::new("probe")) }
                }
            }, agent_client_protocol::on_receive_request!())
            .on_receive_request({
                let observed = agent_observed.clone();
                let cancel = agent_cancel.clone();
                async move |request: AuthenticateRequest, responder: Responder<AuthenticateResponse>, _: ConnectionTo<Client>| {
                    assert_eq!(request.method_id.to_string(), METHOD);
                    observed.lock().unwrap_or_else(PoisonError::into_inner).authenticates += 1;
                    tokio::time::sleep(scenario.authenticate_delay).await;
                    if scenario.cancel_at == Some(AuthStage::Authenticate) { cancel.cancel(); }
                    responder.respond(AuthenticateResponse::default())
                }
            }, agent_client_protocol::on_receive_request!())
            .on_receive_request({
                let observed = agent_observed.clone();
                async move |request: PromptRequest, responder: Responder<PromptResponse>, connection: ConnectionTo<Client>| {
                    observed.lock().unwrap_or_else(PoisonError::into_inner).prompts.push(request.prompt);
                    connection.send_notification(SessionNotification::new(request.session_id.clone(),
                        SessionUpdate::AgentThoughtChunk(ContentChunk::new(ContentBlock::Text(TextContent::new("not quota"))))))?;
                    connection.send_notification(SessionNotification::new(request.session_id,
                        SessionUpdate::AgentMessageChunk(ContentChunk::new(ContentBlock::Text(TextContent::new(REPORT))))))?;
                    if scenario.prompt_failure { responder.respond_with_error(RpcError::auth_required()) }
                    else { responder.respond(PromptResponse::new(StopReason::EndTurn)) }
                }
            }, agent_client_protocol::on_receive_request!())
            .on_receive_request({
                let observed = agent_observed.clone();
                async move |_: CloseSessionRequest, responder: Responder<CloseSessionResponse>, _: ConnectionTo<Client>| {
                    observed.lock().unwrap_or_else(PoisonError::into_inner).closes += 1;
                    if scenario.close_failure { responder.respond_with_error(RpcError::internal_error()) }
                    else { responder.respond(CloseSessionResponse::default()) }
                }
            }, agent_client_protocol::on_receive_request!())
            .connect_with(transport, async move |cx| {
                tokio::select! { () = cx.incoming_closed() => {}, () = agent_disconnect.cancelled() => {} }
                Ok(())
            }).await
    });
    let (progress, mut observer) = watch::channel(AuthProgress::Initializing);
    let (sender, commands) = mpsc::channel(1);
    let drive = async {
        let mut required_count = 0;
        while observer.changed().await.is_ok() {
            let required = matches!(*observer.borrow_and_update(), AuthProgress::Required { .. });
            if !required {
                continue;
            }
            required_count += 1;
            tokio::time::sleep(scenario.human_delay).await;
            if required_count > 1 {
                cancellation.cancel();
                continue;
            }
            match scenario.choice {
                Choice::Authenticate => sender
                    .send(AuthCommand::Authenticate {
                        method_id: METHOD.into(),
                    })
                    .await
                    .expect("live connection"),
                Choice::Unsupported => sender
                    .send(AuthCommand::Authenticate {
                        method_id: "undeclared".into(),
                    })
                    .await
                    .expect("live connection"),
                Choice::Cancel => cancellation.cancel(),
                Choice::Disconnect => disconnect.cancel(),
            }
        }
    };
    let flow = run_connection(
        client_writer,
        client_reader,
        AuthRequest {
            expected_server_version: VERSION.into(),
            probe_cwd: "/tmp".into(),
            action,
            commands,
            cleanup: CleanupBudget::new(Duration::from_secs(5)),
            cancellation: cancellation.clone(),
            progress,
        },
    );
    let (outcome, ()) = tokio::time::timeout(Duration::from_secs(4000), async {
        tokio::join!(flow, drive)
    })
    .await
    .expect("fixture must settle by events");
    agent
        .await
        .expect("fixture task joins")
        .expect("fixture SDK drains");
    let observed = Arc::into_inner(observed)
        .expect("fixture releases state")
        .into_inner()
        .unwrap_or_else(PoisonError::into_inner);
    (outcome, observed)
}

#[tokio::test(start_paused = true)]
async fn slow_authorization_keeps_one_connection_past_all_former_deadlines() {
    let (outcome, observed) = run(
        AuthAction::Check,
        Scenario {
            initialize_delay: Duration::from_secs(181),
            probe_delay: Duration::from_secs(61),
            authenticate_delay: Duration::from_secs(901),
            human_delay: Duration::from_secs(901),
            requires_login: true,
            ..Scenario::default()
        },
    )
    .await;
    assert!(matches!(
        outcome,
        Ok(AuthOutcome::Verified { usage: None, .. })
    ));
    assert_eq!(
        (
            observed.initializes,
            observed.probes,
            observed.authenticates,
            observed.closes
        ),
        (1, 2, 1, 1)
    );
    assert!(observed.default_capabilities);
    assert!(observed.prompts.is_empty());
}

#[tokio::test(start_paused = true)]
async fn successful_authenticate_still_requires_a_successful_session() {
    let (outcome, observed) = run(
        AuthAction::Check,
        Scenario {
            requires_login: true,
            deny_after_auth: true,
            ..Scenario::default()
        },
    )
    .await;
    assert_eq!(
        outcome
            .expect_err("rejected second probe must not verify")
            .kind(),
        AuthFailureKind::Cancelled
    );
    assert_eq!(
        (
            observed.initializes,
            observed.probes,
            observed.authenticates,
            observed.closes
        ),
        (1, 2, 1, 0)
    );
}

#[tokio::test(start_paused = true)]
async fn cancellation_wins_over_responses_at_each_business_stage() {
    for stage in [
        AuthStage::Initialize,
        AuthStage::Authenticate,
        AuthStage::Probe,
    ] {
        let (outcome, _) = run(
            AuthAction::Check,
            Scenario {
                requires_login: true,
                cancel_at: Some(stage),
                ..Scenario::default()
            },
        )
        .await;
        let error = outcome.expect_err("accepted cancellation wins");
        assert_eq!(
            (error.kind(), error.stage()),
            (AuthFailureKind::Cancelled, stage)
        );
    }
}

#[tokio::test(start_paused = true)]
async fn required_state_can_cancel_without_sending_authenticate() {
    let (outcome, observed) = run(
        AuthAction::Check,
        Scenario {
            requires_login: true,
            choice: Choice::Cancel,
            ..Scenario::default()
        },
    )
    .await;
    assert_eq!(
        outcome.expect_err("cancelled").kind(),
        AuthFailureKind::Cancelled
    );
    assert_eq!(observed.authenticates, 0);
}

#[tokio::test(start_paused = true)]
async fn connection_close_while_waiting_for_user_settles_without_another_command() {
    let (outcome, observed) = run(
        AuthAction::Check,
        Scenario {
            requires_login: true,
            choice: Choice::Disconnect,
            ..Scenario::default()
        },
    )
    .await;
    assert_eq!(
        outcome.expect_err("closed transport").kind(),
        AuthFailureKind::Transport
    );
    assert_eq!(observed.authenticates, 0);
}

#[tokio::test(start_paused = true)]
async fn undeclared_method_is_never_sent_to_agent() {
    let (outcome, observed) = run(
        AuthAction::Check,
        Scenario {
            requires_login: true,
            choice: Choice::Unsupported,
            ..Scenario::default()
        },
    )
    .await;
    assert_eq!(
        outcome.expect_err("unsupported method").kind(),
        AuthFailureKind::UnsupportedMethod
    );
    assert_eq!(observed.authenticates, 0);
}

#[tokio::test(start_paused = true)]
async fn close_failure_does_not_publish_verified() {
    let (outcome, observed) = run(
        AuthAction::Check,
        Scenario {
            close_failure: true,
            ..Scenario::default()
        },
    )
    .await;
    let error = outcome.expect_err("close failed");
    assert_eq!(
        (error.kind(), error.stage()),
        (AuthFailureKind::Cleanup, AuthStage::Close)
    );
    assert_eq!(observed.closes, 1);
}

#[tokio::test(start_paused = true)]
async fn usage_prompt_error_remains_nested_and_the_probe_is_closed() {
    let (outcome, observed) = run(
        AuthAction::QueryUsage,
        Scenario {
            prompt_failure: true,
            ..Scenario::default()
        },
    )
    .await;
    assert!(matches!(
        outcome,
        Ok(AuthOutcome::Verified {
            usage: Some(UsageReport::Failed(UsageFailure::Query)),
            ..
        })
    ));
    assert_eq!(observed.probes, 1);
    assert_eq!(observed.authenticates, 0);
    assert_eq!(observed.closes, 1);
    assert_eq!(observed.prompts.len(), 1);
}

#[tokio::test(start_paused = true)]
async fn checks_never_prompt_and_explicit_usage_only_sends_fixed_command() {
    let (outcome, observed) = run(AuthAction::Check, Scenario::default()).await;
    assert!(matches!(
        outcome,
        Ok(AuthOutcome::Verified { usage: None, .. })
    ));
    assert!(observed.prompts.is_empty());
    let (outcome, observed) = run(
        AuthAction::QueryUsage,
        Scenario {
            requires_login: true,
            ..Scenario::default()
        },
    )
    .await;
    assert!(
        matches!(outcome, Ok(AuthOutcome::Verified { usage: Some(UsageReport::Text(ref text)), .. }) if text == REPORT)
    );
    assert_eq!(
        observed.prompts,
        vec![vec![ContentBlock::Text(TextContent::new("/usage"))]]
    );
    assert_eq!(
        (
            observed.initializes,
            observed.authenticates,
            observed.closes
        ),
        (1, 1, 1)
    );
}
