//! Explicit operator observation of this peer. It is not a crate test and
//! does not prove production runtime protocol behaviour.
//!
//! HTTP uses reqwest; WebSocket uses tokio-tungstenite. Protobuf stays prost.

use std::time::Duration;

use anyhow::{Context, Result, bail, ensure};
use futures::{SinkExt, StreamExt};
use reqwest::{Client, redirect::Policy};
use tokio::task::JoinHandle;
use tokio_tungstenite::tungstenite::Message;

use super::types::{
    CallBound, CallKind, DEFAULT_APP_ID, DEFAULT_APP_SECRET, DIRECT_CHAT_ID, GROUP_CHAT_ID,
    REGISTERED_APP_ID, REGISTERED_APP_SECRET, RegistrationBeginOptions, RegistrationPollScript,
    RegistrationTenantBrand, TENANT_ACCESS_TOKEN, TRUSTED_USER_OPEN_ID,
};
use super::wire::{
    FRAME_TYPE_CONTROL, HEADER_SEQ, HEADER_SUM, HEADER_TYPE, ILLEGAL_PBBP2, MESSAGE_TYPE_PONG,
    Pbbp2Frame, encode_addons, required_addons, trusted_direct,
};
use super::{FeishuPeer, FeishuPeerOptions, FeishuReport};

pub struct FeishuObserveOptions {
    pub bind_port: Option<u16>,
}

/// Drive registration, token, IM, WS reconnect, fragment stimuli, hang gates,
/// then join and [`FeishuReport::verify`].
pub async fn run_feishu_observe(options: FeishuObserveOptions) -> Result<()> {
    let mut peer = FeishuPeer::start_with_options(FeishuPeerOptions {
        bind_port: options.bind_port,
        ..FeishuPeerOptions::default()
    })
    .await?;
    let drive = async {
        ensure!(peer.address().port() != 1420, "observe bound 1420");
        let origin = peer.origin().to_owned();
        let ws_origin = peer.ws_origin().to_owned();
        let control = peer.control();
        let client = observe_http_client()?;
        observe_registration_begin_and_brand(&client, &origin, &control).await?;
        observe_late_completed(&client, &origin, &control).await?;
        observe_token_hang(&client, &origin, &control).await?;
        observe_im(&client, &origin).await?;
        super::observe_cards::observe_markdown_and_cards(&client, &origin, &control).await?;
        observe_ws_reconnect_and_fragments(&client, &origin, &ws_origin, &control).await?;
        ensure!(
            control.begin_in_flight().await == 0,
            "main observe left a begin handler counted"
        );
        ensure!(
            control.poll_in_flight().await == 0,
            "main observe left a poll handler counted"
        );
        Ok::<(), anyhow::Error>(())
    };
    let drive_result: Result<()> = drive.await;
    let report = peer.shutdown().await;
    observe_strict_negative().await?;
    super::observe_cards::observe_card_protocol_invariants().await?;
    observe_lifecycle_idempotent().await?;
    observe_status_file_error().await?;
    observe_live_ws_shutdown().await?;
    observe_registration_inflight_lifecycle().await?;
    observe_join_slot_timeout_retry().await?;
    finish_observe(drive_result, report)
}

pub(super) fn observe_http_client() -> Result<Client> {
    Client::builder()
        .no_proxy()
        .redirect(Policy::none())
        .timeout(Duration::from_secs(5))
        .build()
        .context("observe reqwest client")
}

fn finish_observe(drive_result: Result<()>, report: Result<FeishuReport>) -> Result<()> {
    let report = match report {
        Ok(report) => report,
        Err(error) => {
            if let Err(drive) = drive_result {
                return Err(drive).context(error);
            }
            return Err(error);
        }
    };
    for line in report.diagnostic_lines() {
        println!("{line}");
    }
    if let Err(drive) = drive_result {
        let _ = report.verify();
        return Err(drive);
    }
    ensure!(report.listener_joined, "listener not joined");
    ensure!(report.sockets_joined, "sockets not joined");
    report.verify()?;
    Ok(())
}

async fn observe_registration_begin_and_brand(
    client: &Client,
    origin: &str,
    control: &super::FeishuControl,
) -> Result<()> {
    let addons = encode_addons(&required_addons())?;
    let default_begin = post_begin(client, origin, &addons).await?;
    ensure!(
        default_begin["verification_uri"] == format!("{origin}/verify"),
        "default verification_uri must stay peer-bound"
    );
    ensure!(
        default_begin["verification_uri_complete"] == format!("{origin}/verify?user_code=ANYWORK"),
        "default verification_uri_complete must stay peer-bound"
    );
    ensure!(default_begin["interval"] == 5, "default interval");
    ensure!(default_begin["expires_in"] == 600, "default expires_in");

    let frozen_url = "https://invalid.example/verify?userinfo=1#frag";
    let frozen = RegistrationBeginOptions {
        verification_url: Some(frozen_url.to_owned()),
        interval_seconds: 1,
        expires_in_seconds: 1,
    };
    let debug = format!("{frozen:?}");
    ensure!(
        !debug.contains("invalid.example") && !debug.contains("userinfo"),
        "begin options Debug must not echo the URL"
    );
    ensure!(debug.contains("verification_url_override: true"));

    control.set_registration_begin_options(frozen).await;
    control.hang_registration_begin().await;
    let inflight = spawn_begin(client, origin, &addons);
    let wait = wait_begin_hang(control).await;
    if wait.is_err() {
        control.release_registration_begin().await;
        let _ = join_http(inflight).await;
        return wait;
    }
    control
        .set_registration_begin_options(RegistrationBeginOptions {
            verification_url: Some("https://invalid.example/replaced".into()),
            interval_seconds: 9,
            expires_in_seconds: 9,
        })
        .await;
    control.release_registration_begin().await;
    let frozen_response = join_http(inflight).await?;
    ensure!(
        frozen_response.status().is_success(),
        "frozen begin http {}",
        frozen_response.status()
    );
    let frozen_json: serde_json::Value = frozen_response.json().await?;
    ensure!(
        frozen_json["verification_uri"] == format!("{origin}/verify"),
        "bare verification_uri stays origin/verify"
    );
    ensure!(
        frozen_json["verification_uri_complete"] == frozen_url,
        "frozen complete URI must not be swapped"
    );
    ensure!(frozen_json["interval"] == 1, "frozen interval");
    ensure!(frozen_json["expires_in"] == 1, "frozen expires_in");
    ensure!(
        control.begin_in_flight().await == 0,
        "begin count must return to 0 after hang release"
    );

    let report = control.snapshot_report().await;
    let evidence = format!("{:?}{}", report, report.diagnostic_lines().join("\n"));
    ensure!(
        !evidence.contains("invalid.example") && !evidence.contains(frozen_url),
        "report must not record the verification URL"
    );

    control
        .set_registration_begin_options(RegistrationBeginOptions::default())
        .await;
    let next_begin = post_begin(client, origin, &addons).await?;
    ensure!(
        next_begin["verification_uri_complete"] == format!("{origin}/verify?user_code=ANYWORK"),
        "later begin uses restored default complete URI"
    );
    ensure!(next_begin["interval"] == 5, "restored interval");
    let next_device = next_begin["device_code"]
        .as_str()
        .context("brand device_code")?
        .to_owned();

    control
        .set_registration_tenant_brand(Some(RegistrationTenantBrand::Feishu))
        .await;
    control
        .set_registration_script(vec![RegistrationPollScript::Completed {
            include_open_id: true,
        }])
        .await;
    let feishu = post_poll(client, origin, &next_device).await?;
    ensure!(feishu["user_info"]["open_id"] == TRUSTED_USER_OPEN_ID);
    ensure!(feishu["user_info"]["tenant_brand"] == "feishu");

    let lark_begin = post_begin(client, origin, &addons).await?;
    let lark_device = lark_begin["device_code"]
        .as_str()
        .context("lark device_code")?
        .to_owned();
    control
        .set_registration_tenant_brand(Some(RegistrationTenantBrand::Lark))
        .await;
    control
        .set_registration_script(vec![RegistrationPollScript::Completed {
            include_open_id: false,
        }])
        .await;
    let lark = post_poll(client, origin, &lark_device).await?;
    ensure!(lark["user_info"]["tenant_brand"] == "lark");
    ensure!(
        lark["user_info"].get("open_id").is_none(),
        "brand without include_open_id must not mint open_id"
    );

    control.set_registration_tenant_brand(None).await;
    control
        .set_registration_script(vec![RegistrationPollScript::Pending])
        .await;
    Ok(())
}

async fn observe_late_completed(
    client: &Client,
    origin: &str,
    control: &super::FeishuControl,
) -> Result<()> {
    control
        .set_registration_script(vec![RegistrationPollScript::Hang])
        .await;
    let addons = encode_addons(&required_addons())?;
    let begin = client
        .post(format!("{origin}/oauth/v1/app/registration"))
        .header("content-type", "application/x-www-form-urlencoded")
        .body(format!(
            "action=begin&archetype=PersonalAgent&auth_method=client_secret&request_user_info=open_id&addons={}",
            form_encode(&addons)
        ))
        .send()
        .await
        .context("begin")?;
    ensure!(begin.status().is_success(), "begin http {}", begin.status());
    let begin_json: serde_json::Value = begin.json().await?;
    let device = begin_json["device_code"]
        .as_str()
        .context("device_code")?
        .to_owned();

    let inflight = spawn_poll(client, origin, &device);
    let result = async {
        wait_poll_hang(control).await?;
        control
            .set_registration_script(vec![RegistrationPollScript::Completed {
                include_open_id: true,
            }])
            .await;
        control.cancel_registration_generation().await;
        control.release_registration().await;
        Ok::<(), anyhow::Error>(())
    }
    .await;
    let response = join_http(inflight).await;
    result?;
    let response = response?;
    ensure!(
        response.status() == reqwest::StatusCode::OK,
        "late completed http {}",
        response.status()
    );
    let json: serde_json::Value = response.json().await?;
    ensure!(
        json["client_id"] == REGISTERED_APP_ID,
        "late completed masked: {json}"
    );
    ensure!(json["user_info"]["open_id"] == TRUSTED_USER_OPEN_ID);
    ensure!(json["user_info"]["tenant_brand"] == "feishu");
    ensure!(
        control.poll_in_flight().await == 0,
        "poll count must return to 0 after hang release"
    );
    Ok(())
}

async fn observe_token_hang(
    client: &Client,
    origin: &str,
    control: &super::FeishuControl,
) -> Result<()> {
    control.hang_token().await;
    let mut tasks = Vec::new();
    for _ in 0..3 {
        tasks.push(spawn_token(client, origin));
    }
    let wait = wait_token_in_flight(control, 3).await;
    if wait.is_err() {
        control.release_token().await;
        join_http_all(tasks).await;
        return wait;
    }
    control.release_token().await;
    let responses = join_http_all(tasks).await;
    for response in responses {
        let response = response?;
        let json: serde_json::Value = response.json().await?;
        ensure!(json["code"] == 0, "token hang {json}");
        ensure!(json["access_token"] == TENANT_ACCESS_TOKEN);
        ensure!(json["expires_in"] == 7200);
        ensure!(json["token_type"] == "Bearer");
    }
    Ok(())
}

async fn observe_im(client: &Client, origin: &str) -> Result<()> {
    let info = client
        .get(format!("{origin}/open-apis/bot/v3/info"))
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .send()
        .await?;
    let info_json: serde_json::Value = info.json().await?;
    ensure!(info_json["bot"]["open_id"] != DEFAULT_APP_ID);
    ensure!(info_json["bot"]["open_id"] != REGISTERED_APP_ID);

    let chats = client
        .get(format!("{origin}/open-apis/im/v1/chats"))
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .send()
        .await?;
    let chats_json: serde_json::Value = chats.json().await?;
    let items = chats_json["data"]["items"].as_array().context("chats")?;
    ensure!(items.iter().all(|item| item["chat_id"] != DIRECT_CHAT_ID));
    ensure!(items.iter().any(|item| item["chat_id"] == GROUP_CHAT_ID));

    let bad = client
        .get(format!(
            "{origin}/open-apis/im/v1/chats?page_token=not-a-cursor"
        ))
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .send()
        .await?;
    let bad_json: serde_json::Value = bad.json().await?;
    ensure!(bad_json["code"] == 232001, "bad cursor {bad_json}");

    let history = client
        .get(format!(
            "{origin}/open-apis/im/v1/messages?container_id_type=chat&container_id={GROUP_CHAT_ID}&page_size=20"
        ))
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .send()
        .await?;
    let history_json: serde_json::Value = history.json().await?;
    ensure!(history_json["code"] == 0, "history {history_json}");

    let send = client
        .post(format!(
            "{origin}/open-apis/im/v1/messages?receive_id_type=chat_id"
        ))
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .json(&serde_json::json!({
                    "receive_id": GROUP_CHAT_ID,
                    "msg_type": "post",
                    "content": serde_json::json!({
                        "zh_cn": {
                            "title": "fixture",
                            "content": [[{ "tag": "md", "text": "**fixture** reply" }]]
        }
                    })
                    .to_string(),
                    "uuid": "uuid-anywork-fixture-observe-01"
                }))
        .send()
        .await?;
    let send_json: serde_json::Value = send.json().await?;
    ensure!(send_json["code"] == 0, "send {send_json}");
    Ok(())
}

async fn observe_ws_reconnect_and_fragments(
    client: &Client,
    origin: &str,
    ws_origin: &str,
    control: &super::FeishuControl,
) -> Result<()> {
    let discover = client
        .post(format!("{origin}/callback/ws/endpoint"))
        .json(&serde_json::json!({
            "AppID": DEFAULT_APP_ID,
            "AppSecret": DEFAULT_APP_SECRET
        }))
        .send()
        .await?;
    let discover_json: serde_json::Value = discover.json().await?;
    ensure!(discover_json["code"] == 0, "discover {discover_json}");
    let ws_url = discover_json["data"]["URL"]
        .as_str()
        .context("ws url")?
        .to_owned();
    ensure!(ws_url.starts_with(&format!("{ws_origin}/")));
    ensure!(!ws_url.contains("1420"));

    let (mut socket_a, response) = connect_ws(&ws_url).await?;
    ensure!(
        response.status() == axum::http::StatusCode::SWITCHING_PROTOCOLS,
        "upgrade {}",
        response.status()
    );
    ping_pong(&mut socket_a).await?;
    drop(socket_a);

    let (mut socket_b, _) = connect_ws(&ws_url).await?;
    ping_pong(&mut socket_b).await?;
    control
        .send_event(trusted_direct("om_observe_reconnect", "hello b"))
        .await?;
    let event = recv_binary(&mut socket_b).await?;
    let event_frame = Pbbp2Frame::decode_slice(&event)?;
    ensure!(event_frame.header(HEADER_SUM) == Some("1"));
    ack_event(&mut socket_b, &event_frame).await?;

    let payload_a = b"frag-a".to_vec();
    let payload_b = b"frag-B".to_vec();
    let event = trusted_direct("om_observe_frag", "unused");
    control
        .send_incomplete_fragment(event.clone(), 2, 0, payload_a.clone())
        .await?;
    let first = recv_binary(&mut socket_b).await?;
    let first_frame = Pbbp2Frame::decode_slice(&first)?;
    ensure!(first_frame.header(HEADER_SUM) == Some("2"));
    ensure!(first_frame.header(HEADER_SEQ) == Some("0"));
    ensure!(first_frame.payload.as_deref() == Some(payload_a.as_slice()));

    control
        .send_incomplete_fragment(event.clone(), 2, 0, payload_a.clone())
        .await?;
    let retry = recv_binary(&mut socket_b).await?;
    let retry_frame = Pbbp2Frame::decode_slice(&retry)?;
    ensure!(retry_frame.header(HEADER_SUM) == Some("2"));
    ensure!(retry_frame.header(HEADER_SEQ) == Some("0"));
    ensure!(retry_frame.payload.as_deref() == Some(payload_a.as_slice()));

    control
        .send_incomplete_fragment(event, 2, 0, payload_b.clone())
        .await?;
    let conflict = recv_binary(&mut socket_b).await?;
    let conflict_frame = Pbbp2Frame::decode_slice(&conflict)?;
    ensure!(conflict_frame.header(HEADER_SUM) == Some("2"));
    ensure!(conflict_frame.header(HEADER_SEQ) == Some("0"));
    ensure!(conflict_frame.payload.as_deref() == Some(payload_b.as_slice()));

    control.send_illegal_frame().await?;
    let illegal = recv_binary(&mut socket_b).await?;
    ensure!(illegal.as_slice() == ILLEGAL_PBBP2, "illegal stimulus");
    let _ = socket_b.close(None).await;
    Ok(())
}

/// A synthetic card entity whose serialized length is exactly `target` bytes.
///
/// Multi-byte padding makes the UTF-8 boundary exact, so the 30 KB check is
/// proven on the real encoded document rather than on a character count.
async fn observe_strict_negative() -> Result<()> {
    let mut peer = FeishuPeer::start().await?;
    let drive = async {
        let origin = peer.origin().to_owned();
        let client = observe_http_client()?;
        let _ = client
            .get(format!("{origin}/callback/ws/connect"))
            .send()
            .await?;
        peer.control()
            .require_calls(vec![CallBound {
                kind: CallKind::BotInfo,
                min: 8,
                max: None,
            }])
            .await;
        Ok::<(), anyhow::Error>(())
    };
    let drive_result = drive.await;
    let report = peer.shutdown().await?;
    drive_result?;
    ensure!(report.verify().is_err(), "strict negative must fail verify");
    Ok(())
}

async fn post_begin(client: &Client, origin: &str, addons: &str) -> Result<serde_json::Value> {
    let response = client
        .post(format!("{origin}/oauth/v1/app/registration"))
        .header("content-type", "application/x-www-form-urlencoded")
        .body(format!(
            "action=begin&archetype=PersonalAgent&auth_method=client_secret&request_user_info=open_id&addons={}",
            form_encode(addons)
        ))
        .send()
        .await
        .context("begin")?;
    ensure!(
        response.status().is_success(),
        "begin http {}",
        response.status()
    );
    response.json().await.context("begin json")
}

fn spawn_begin(
    client: &Client,
    origin: &str,
    addons: &str,
) -> JoinHandle<reqwest::Result<reqwest::Response>> {
    let client = client.clone();
    let origin = origin.to_owned();
    let addons = addons.to_owned();
    tokio::spawn(async move {
        client
            .post(format!("{origin}/oauth/v1/app/registration"))
            .header("content-type", "application/x-www-form-urlencoded")
            .body(format!(
                "action=begin&archetype=PersonalAgent&auth_method=client_secret&request_user_info=open_id&addons={}",
                form_encode(&addons)
            ))
            .send()
            .await
    })
}

async fn post_poll(client: &Client, origin: &str, device: &str) -> Result<serde_json::Value> {
    let response = client
        .post(format!("{origin}/oauth/v1/app/registration"))
        .header("content-type", "application/x-www-form-urlencoded")
        .body(format!("action=poll&device_code={device}"))
        .send()
        .await
        .context("poll")?;
    ensure!(
        response.status().is_success(),
        "poll http {}",
        response.status()
    );
    response.json().await.context("poll json")
}

fn spawn_poll(
    client: &Client,
    origin: &str,
    device: &str,
) -> JoinHandle<reqwest::Result<reqwest::Response>> {
    let client = client.clone();
    let origin = origin.to_owned();
    let device = device.to_owned();
    tokio::spawn(async move {
        client
            .post(format!("{origin}/oauth/v1/app/registration"))
            .header("content-type", "application/x-www-form-urlencoded")
            .body(format!("action=poll&device_code={device}"))
            .send()
            .await
    })
}

fn spawn_token(client: &Client, origin: &str) -> JoinHandle<reqwest::Result<reqwest::Response>> {
    let client = client.clone();
    let origin = origin.to_owned();
    tokio::spawn(async move {
        let encoded = url::form_urlencoded::Serializer::new(String::new())
            .extend_pairs([
                ("grant_type", "client_credentials"),
                ("client_id", REGISTERED_APP_ID),
                ("client_secret", REGISTERED_APP_SECRET),
            ])
            .finish();
        client
            .post(format!("{origin}/oauth/v3/token"))
            .header("content-type", "application/x-www-form-urlencoded")
            .body(encoded)
            .send()
            .await
    })
}

async fn join_http(
    handle: JoinHandle<reqwest::Result<reqwest::Response>>,
) -> Result<reqwest::Response> {
    handle
        .await
        .context("observe client join")?
        .context("observe http")
}

async fn join_http_all(
    tasks: Vec<JoinHandle<reqwest::Result<reqwest::Response>>>,
) -> Vec<Result<reqwest::Response>> {
    let mut out = Vec::new();
    for task in tasks {
        out.push(join_http(task).await);
    }
    out
}

async fn connect_ws(
    url: &str,
) -> Result<(
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>,
    tokio_tungstenite::tungstenite::http::Response<Option<Vec<u8>>>,
)> {
    tokio_tungstenite::connect_async(url)
        .await
        .context("tungstenite connect")
}

async fn ping_pong(
    socket: &mut tokio_tungstenite::WebSocketStream<
        tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
    >,
) -> Result<()> {
    socket
        .send(Message::Binary(Pbbp2Frame::ping(1).encode_vec().into()))
        .await?;
    let bytes = recv_binary(socket).await?;
    let frame = Pbbp2Frame::decode_slice(&bytes)?;
    ensure!(frame.method == FRAME_TYPE_CONTROL);
    ensure!(frame.header(HEADER_TYPE) == Some(MESSAGE_TYPE_PONG));
    Ok(())
}

async fn ack_event(
    socket: &mut tokio_tungstenite::WebSocketStream<
        tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
    >,
    event: &Pbbp2Frame,
) -> Result<()> {
    let mut ack = event.clone();
    ack.payload = Some(serde_json::json!({"code": 200}).to_string().into_bytes());
    ack.headers
        .push(super::wire::header(super::wire::HEADER_BIZ_RT, "1"));
    socket
        .send(Message::Binary(ack.encode_vec().into()))
        .await?;
    Ok(())
}

async fn recv_binary(
    socket: &mut tokio_tungstenite::WebSocketStream<
        tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
    >,
) -> Result<Vec<u8>> {
    loop {
        let message = tokio::time::timeout(Duration::from_secs(2), socket.next())
            .await
            .context("ws timeout")?
            .context("ws closed")??;
        match message {
            Message::Binary(bytes) => return Ok(bytes.to_vec()),
            Message::Ping(payload) => {
                socket.send(Message::Pong(payload)).await?;
            }
            Message::Pong(_) | Message::Frame(_) => {}
            Message::Close(_) => bail!("ws closed"),
            Message::Text(_) => bail!("unexpected text ws frame"),
        }
    }
}

fn form_encode(value: &str) -> String {
    url::form_urlencoded::byte_serialize(value.as_bytes()).collect()
}

async fn wait_token_in_flight(control: &super::FeishuControl, expected: usize) -> Result<()> {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(2);
    loop {
        if control.token_in_flight().await >= expected {
            return Ok(());
        }
        ensure!(
            tokio::time::Instant::now() < deadline,
            "token hang waiters did not become in-flight"
        );
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
}

/// Keep a real WS open, then shutdown the peer without client close first.
async fn observe_live_ws_shutdown() -> Result<()> {
    let mut peer = FeishuPeer::start().await?;
    let mut live_socket = None;
    let drive_result: Result<()> = async {
        let origin = peer.origin().to_owned();
        let client = observe_http_client()?;
        let discover = client
            .post(format!("{origin}/callback/ws/endpoint"))
            .json(&serde_json::json!({
                "AppID": DEFAULT_APP_ID,
                "AppSecret": DEFAULT_APP_SECRET
            }))
            .send()
            .await?;
        let discover_json: serde_json::Value = discover.json().await?;
        let ws_url = discover_json["data"]["URL"]
            .as_str()
            .context("live ws url")?
            .to_owned();
        let (socket, _) = connect_ws(&ws_url).await?;
        live_socket = Some(socket);
        Ok(())
    }
    .await;
    let started = tokio::time::Instant::now();
    let cleanup = peer.shutdown().await;
    let elapsed = started.elapsed();
    drop(live_socket);
    match (drive_result, cleanup) {
        (Ok(()), Ok(report)) => {
            ensure!(
                elapsed < Duration::from_secs(2),
                "live ws shutdown self-locked for {elapsed:?}"
            );
            ensure!(report.listener_joined, "live ws listener not joined");
            ensure!(report.sockets_joined, "live ws sockets not joined");
            Ok(())
        }
        (Err(drive), Ok(report)) => {
            for line in report.diagnostic_lines() {
                println!("{line}");
            }
            Err(drive)
        }
        (Ok(()), Err(cleanup)) => Err(cleanup).context("live ws cleanup after success"),
        (Err(drive), Err(cleanup)) => Err(drive).context(cleanup),
    }
}

/// JoinSlot timeout must leave the same owner Pending, then succeed after release.
async fn observe_join_slot_timeout_retry() -> Result<()> {
    let (tx, rx) = tokio::sync::oneshot::channel::<()>();
    let handle = tokio::spawn(async move {
        let _ = rx.await;
    });
    let mut slot = super::state::JoinSlot::Pending(handle);
    let first = slot.join_with_timeout(Duration::from_millis(50)).await;
    ensure!(first.is_err(), "short deadline must time out");
    ensure!(!slot.is_joined(), "timed-out slot must stay Pending");
    let _ = tx.send(());
    slot.join_with_timeout(Duration::from_secs(2))
        .await
        .map_err(|error| anyhow::anyhow!(error))?;
    ensure!(slot.is_joined(), "same slot must join after release");
    Ok(())
}

async fn observe_lifecycle_idempotent() -> Result<()> {
    let mut peer = FeishuPeer::start().await?;
    let first = peer.shutdown().await?;
    ensure!(first.listener_joined);
    ensure!(first.sockets_joined);
    let second = peer.shutdown().await?;
    ensure!(second.listener_joined);
    ensure!(second.sockets_joined);
    Ok(())
}

async fn observe_status_file_error() -> Result<()> {
    let mut peer = FeishuPeer::start().await?;
    ensure!(peer.listener_pending(), "fresh peer listener is pending");
    let first = peer.shutdown().await?;
    ensure!(first.listener_joined);
    ensure!(!peer.listener_pending(), "joined listener stays joined");
    let second = peer.shutdown().await?;
    ensure!(second.listener_joined);
    Ok(())
}

/// Client abort vs server-handler lifetime for hung registration requests.
///
/// Axum may keep the handler until hang release even after the client
/// future is cancelled. That live handler must stay counted. Drop of
/// [`super::state::InFlightGuard`] is owned by the handler future; peer
/// shutdown must still join and return both counters to zero.
async fn observe_registration_inflight_lifecycle() -> Result<()> {
    observe_client_cancel_hung_begin().await?;
    observe_client_cancel_hung_poll().await?;
    observe_shutdown_while_registration_hung().await
}

async fn observe_client_cancel_hung_begin() -> Result<()> {
    let mut peer = FeishuPeer::start().await?;
    let control = peer.control();
    let drive_result: Result<()> = async {
        ensure!(peer.address().port() != 1420, "observe bound 1420");
        let origin = peer.origin().to_owned();
        let client = observe_http_client()?;
        let addons = encode_addons(&required_addons())?;
        control.hang_registration_begin().await;
        let begin_handle = spawn_begin(&client, &origin, &addons);
        let wait = wait_begin_hang(&control).await;
        if wait.is_err() {
            control.release_registration_begin().await;
            let _ = abort_http(begin_handle).await;
            return wait;
        }
        ensure!(
            control.begin_in_flight().await == 1,
            "hung begin must count 1"
        );
        abort_http(begin_handle).await?;
        if registration_count_zero(&control, true, Duration::from_millis(400)).await {
            println!("feishu_observe_begin_client_cancel=handler_dropped");
            ensure!(
                control.begin_in_flight().await == 0,
                "dropped begin handler must not stay counted"
            );
        } else {
            println!("feishu_observe_begin_client_cancel=handler_still_alive");
            ensure!(
                control.begin_in_flight().await == 1,
                "live begin handler after client cancel must stay counted"
            );
        }
        Ok(())
    }
    .await;
    if drive_result.is_err() {
        control.release_registration_begin().await;
    }
    let cleanup = peer.shutdown().await;
    finish_inflight_observe(drive_result, cleanup, &control, true, "begin-cancel").await
}

async fn observe_client_cancel_hung_poll() -> Result<()> {
    let mut peer = FeishuPeer::start().await?;
    let control = peer.control();
    let drive_result: Result<()> = async {
        ensure!(peer.address().port() != 1420, "observe bound 1420");
        let origin = peer.origin().to_owned();
        let client = observe_http_client()?;
        let addons = encode_addons(&required_addons())?;
        let device = post_begin(&client, &origin, &addons).await?["device_code"]
            .as_str()
            .context("inflight device_code")?
            .to_owned();
        control
            .set_registration_script(vec![RegistrationPollScript::Hang])
            .await;
        let poll_handle = spawn_poll(&client, &origin, &device);
        let wait = wait_poll_hang(&control).await;
        if wait.is_err() {
            control.release_registration().await;
            let _ = abort_http(poll_handle).await;
            return wait;
        }
        ensure!(
            control.poll_in_flight().await == 1,
            "hung poll must count 1"
        );
        abort_http(poll_handle).await?;
        if registration_count_zero(&control, false, Duration::from_millis(400)).await {
            println!("feishu_observe_poll_client_cancel=handler_dropped");
            ensure!(
                control.poll_in_flight().await == 0,
                "dropped poll handler must not stay counted"
            );
        } else {
            println!("feishu_observe_poll_client_cancel=handler_still_alive");
            ensure!(
                control.poll_in_flight().await == 1,
                "live poll handler after client cancel must stay counted"
            );
        }
        Ok(())
    }
    .await;
    if drive_result.is_err() {
        control.release_registration().await;
    }
    let cleanup = peer.shutdown().await;
    finish_inflight_observe(drive_result, cleanup, &control, false, "poll-cancel").await
}

async fn finish_inflight_observe(
    drive_result: Result<()>,
    cleanup: Result<FeishuReport>,
    control: &super::FeishuControl,
    begin: bool,
    label: &str,
) -> Result<()> {
    match (drive_result, cleanup) {
        (Ok(()), Ok(report)) => {
            ensure!(report.listener_joined, "{label} listener not joined");
            ensure!(report.sockets_joined, "{label} sockets not joined");
            ensure!(
                registration_count_zero(control, begin, Duration::from_secs(2)).await,
                "{label} handler count must return to 0 after shutdown"
            );
            Ok(())
        }
        (Err(drive), Ok(report)) => {
            for line in report.diagnostic_lines() {
                println!("{line}");
            }
            Err(drive)
        }
        (Ok(()), Err(cleanup)) => Err(cleanup).context(format!("{label} cleanup after success")),
        (Err(drive), Err(cleanup)) => Err(drive).context(cleanup),
    }
}

async fn observe_shutdown_while_registration_hung() -> Result<()> {
    let mut peer = FeishuPeer::start().await?;
    let control = peer.control();
    let mut begin_handle = None;
    let drive_result: Result<()> = async {
        ensure!(peer.address().port() != 1420, "observe bound 1420");
        let origin = peer.origin().to_owned();
        let client = observe_http_client()?;
        let addons = encode_addons(&required_addons())?;
        control.hang_registration_begin().await;
        let handle = spawn_begin(&client, &origin, &addons);
        begin_handle = Some(handle);
        wait_begin_hang(&control).await?;
        ensure!(control.begin_in_flight().await == 1);
        Ok(())
    }
    .await;
    let started = tokio::time::Instant::now();
    let cleanup = peer.shutdown().await;
    let elapsed = started.elapsed();
    if let Some(handle) = begin_handle.take() {
        handle.abort();
        let _ = tokio::time::timeout(Duration::from_secs(2), handle).await;
    }
    match (drive_result, cleanup) {
        (Ok(()), Ok(report)) => {
            ensure!(
                elapsed < Duration::from_secs(2),
                "hung begin shutdown self-locked for {elapsed:?}"
            );
            ensure!(report.listener_joined, "hung-begin listener not joined");
            ensure!(report.sockets_joined, "hung-begin sockets not joined");
            ensure!(
                control.begin_in_flight().await == 0,
                "shutdown must drop or finish the hung begin handler"
            );
            Ok(())
        }
        (Err(drive), Ok(report)) => {
            for line in report.diagnostic_lines() {
                println!("{line}");
            }
            Err(drive)
        }
        (Ok(()), Err(cleanup)) => Err(cleanup).context("hung-begin cleanup after success"),
        (Err(drive), Err(cleanup)) => Err(drive).context(cleanup),
    }
}

async fn abort_http(handle: JoinHandle<reqwest::Result<reqwest::Response>>) -> Result<()> {
    handle.abort();
    match tokio::time::timeout(Duration::from_secs(2), handle).await {
        Err(_) => bail!("cancelled client join timed out"),
        Ok(Err(_)) => Ok(()),
        Ok(Ok(Err(_))) => Ok(()),
        Ok(Ok(Ok(_))) => bail!("cancelled client completed with a response"),
    }
}

async fn registration_count_zero(
    control: &super::FeishuControl,
    begin: bool,
    bound: Duration,
) -> bool {
    let deadline = tokio::time::Instant::now() + bound;
    loop {
        let current = if begin {
            control.begin_in_flight().await
        } else {
            control.poll_in_flight().await
        };
        if current == 0 {
            return true;
        }
        if tokio::time::Instant::now() >= deadline {
            return false;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
}

async fn wait_begin_hang(control: &super::FeishuControl) -> Result<()> {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(2);
    loop {
        if control.begin_in_flight().await >= 1 {
            return Ok(());
        }
        ensure!(
            tokio::time::Instant::now() < deadline,
            "registration begin did not hang"
        );
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
}

async fn wait_poll_hang(control: &super::FeishuControl) -> Result<()> {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(2);
    loop {
        if control.poll_in_flight().await >= 1 {
            return Ok(());
        }
        ensure!(
            tokio::time::Instant::now() < deadline,
            "registration poll did not hang"
        );
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
}
