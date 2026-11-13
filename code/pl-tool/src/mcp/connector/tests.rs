use super::*;
use rmcp::transport::async_rw::AsyncRwTransport;
use std::sync::atomic::AtomicUsize;
use std::sync::{Condvar, Mutex};
use tokio::sync::{Notify, mpsc};

#[tokio::test]
async fn legacy_initialize_accepts_captured_dart_sdk_response() {
    captured_dart_sdk_handshake(McpServerStartupMode::Auto, Duration::ZERO).await;
}

#[tokio::test]
async fn explicit_initialize_accepts_cold_captured_dart_sdk_response() {
    captured_dart_sdk_handshake(McpServerStartupMode::Initialize, Duration::from_secs(11)).await;
}

#[tokio::test]
#[ignore = "reproduces RMCP's fixed 10-second Auto discovery timeout"]
async fn cold_legacy_initialize_accepts_captured_dart_sdk_response() {
    captured_dart_sdk_handshake(McpServerStartupMode::Auto, Duration::from_secs(11)).await;
}

async fn captured_dart_sdk_handshake(mode: McpServerStartupMode, startup_delay: Duration) {
    use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

    let (client, server) = tokio::io::duplex(16384);
    let (read, mut write) = tokio::io::split(server);
    let peer = tokio::spawn(async move {
        let mut lines = BufReader::new(read).lines();
        tokio::time::sleep(startup_delay).await;
        let responses =
            include_str!("../../../tests/support/dart_mcp_1_2_2_initialize.jsonl").lines();
        for response in responses.skip(usize::from(mode == McpServerStartupMode::Initialize)) {
            let request: serde_json::Value =
                serde_json::from_str(&lines.next_line().await.unwrap().unwrap()).unwrap();
            let mut response_value: serde_json::Value = serde_json::from_str(response).unwrap();
            if mode == McpServerStartupMode::Initialize {
                assert_eq!(request["method"], "initialize");
                assert_eq!(request["id"], 0);
                assert_eq!(request["params"]["protocolVersion"], "2025-11-25");
                // Only correlate the captured envelope with this session's first
                // request. The captured initialize result stays completely intact.
                response_value["id"] = request["id"].clone();
            } else {
                assert_eq!(request["id"], response_value["id"]);
            }
            let response = if mode == McpServerStartupMode::Initialize {
                serde_json::to_string(&response_value).unwrap()
            } else {
                response.to_owned()
            };
            write.write_all(response.as_bytes()).await.unwrap();
            write.write_all(b"\n").await.unwrap();
        }
        let initialized: serde_json::Value =
            serde_json::from_str(&lines.next_line().await.unwrap().unwrap()).unwrap();
        assert_eq!(initialized["method"], "notifications/initialized");
    });
    let (read, write) = tokio::io::split(client);
    let (protocol_version, lifecycle) = startup_lifecycle(mode);
    let result = tokio::time::timeout(
        startup_delay + Duration::from_secs(2),
        client_handler("captured-peer", protocol_version, None)
            .serve_observed(AsyncRwTransport::new(read, write), lifecycle),
    )
    .await
    .expect("handshake deadline");
    let service = result.unwrap_or_else(|error| panic!("typed initialize failure: {error:?}"));
    peer.await.unwrap();
    service.cancel().await.unwrap();
}

pub(crate) struct FaultTransport {
    pub(crate) panic_send: bool,
    pub(crate) fail_close: bool,
    pub(crate) closed: Arc<AtomicUsize>,
}

impl rmcp::transport::Transport<RoleClient> for FaultTransport {
    type Error = std::io::Error;

    fn send(
        &mut self,
        _: ClientJsonRpcMessage,
    ) -> impl Future<Output = std::io::Result<()>> + Send + 'static {
        let panic_send = self.panic_send;
        async move {
            assert!(!panic_send, "send-task-failed secret-close-token");
            Ok(())
        }
    }

    async fn receive(&mut self) -> Option<ServerJsonRpcMessage> {
        std::future::pending().await
    }

    async fn close(&mut self) -> std::io::Result<()> {
        self.closed.fetch_add(1, Ordering::SeqCst);
        if self.fail_close {
            Err(std::io::Error::other(
                "transport-close-failed secret-close-token",
            ))
        } else {
            Ok(())
        }
    }
}

pub(crate) async fn fault_session(transport: FaultTransport) -> ConnectedMcp {
    let panic_send = transport.panic_send;
    let handler = client_handler("fault", ProtocolVersion::V_2025_11_25, None);
    let observed = observed_transport::ObservedTransport::new(transport, handler.identity.clone());
    let service = rmcp::service::serve_directly(handler, observed, None);
    let session = ConnectedMcp::from_running(service, Duration::from_secs(2)).await;
    if panic_send {
        tokio::time::timeout(
            Duration::from_secs(2),
            session
                .peer
                .send_request(ClientRequest::PingRequest(Default::default())),
        )
        .await
        .unwrap()
        .expect_err("send task panic must close the response channel");
    }
    session
}

pub(crate) fn retains_io_close_source(session: &ConnectedMcp) -> bool {
    let error = session.identity.close_error.lock().unwrap();
    let source = std::error::Error::source(error.as_ref().unwrap()).unwrap();
    source.downcast_ref::<std::io::Error>().is_some()
}

// Deliberately park the SDK consumer on a dedicated worker thread: pending send
// futures alone do not stop RMCP, which spawns them concurrently. This fixture
// reproduces consumer starvation without changing the real bounded SDK channel.
struct BlockedSink {
    incoming: mpsc::UnboundedReceiver<ServerJsonRpcMessage>,
    sender: mpsc::UnboundedSender<ServerJsonRpcMessage>,
    entered: Arc<Notify>,
    release: Arc<(Mutex<bool>, Condvar)>,
    blocked: bool,
    tool_calls: Arc<AtomicUsize>,
}

impl rmcp::transport::Transport<RoleClient> for BlockedSink {
    type Error = std::io::Error;

    fn send(
        &mut self,
        item: ClientJsonRpcMessage,
    ) -> impl Future<Output = std::io::Result<()>> + Send + 'static {
        let sender = self.sender.clone();
        let tool_calls = self.tool_calls.clone();
        async move {
            if let ClientJsonRpcMessage::Request(request) = item {
                if matches!(request.request, ClientRequest::CallToolRequest(_)) {
                    tool_calls.fetch_add(1, Ordering::SeqCst);
                }
                sender
                    .send(ServerJsonRpcMessage::response(
                        ServerResult::empty(()),
                        request.id,
                    ))
                    .unwrap();
            }
            Ok(())
        }
    }

    async fn receive(&mut self) -> Option<ServerJsonRpcMessage> {
        if !self.blocked {
            self.blocked = true;
            self.entered.notify_one();
            let (lock, wake) = &*self.release;
            let mut released = lock.lock().unwrap();
            while !*released {
                released = wake.wait(released).unwrap();
            }
        }
        self.incoming.recv().await
    }

    async fn close(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

struct ReleaseOnDrop(Arc<(Mutex<bool>, Condvar)>);

impl Drop for ReleaseOnDrop {
    fn drop(&mut self) {
        let (lock, wake) = &*self.0;
        *lock.lock().unwrap() = true;
        wake.notify_all();
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn request_deadline_bounds_sdk_enqueue_without_sending_or_replaying_the_tool() {
    let (sender, incoming) = mpsc::unbounded_channel();
    let entered = Arc::new(Notify::new());
    let release = Arc::new((Mutex::new(false), Condvar::new()));
    let release_on_drop = ReleaseOnDrop(release.clone());
    let tool_calls = Arc::new(AtomicUsize::new(0));
    let service = rmcp::service::serve_directly(
        client_handler("blocked", ProtocolVersion::V_2025_11_25, None),
        BlockedSink {
            incoming,
            sender: sender.clone(),
            entered: entered.clone(),
            release: release.clone(),
            blocked: false,
            tool_calls: tool_calls.clone(),
        },
        None,
    );
    let session = ConnectedMcp::from_running(service, Duration::from_secs(2)).await;
    tokio::time::timeout(Duration::from_secs(2), entered.notified())
        .await
        .unwrap();
    let mut handles = Vec::new();
    loop {
        // A cooperative-budget yield is not evidence that the channel is full.
        let enqueue = tokio::task::unconstrained(session.peer.send_request_with_option(
            ClientRequest::PingRequest(Default::default()),
            PeerRequestOptions::no_options(),
        ));
        tokio::pin!(enqueue);
        match futures::poll!(enqueue.as_mut()) {
            std::task::Poll::Ready(handle) => handles.push(handle.unwrap()),
            std::task::Poll::Pending => break,
        }
        assert!(handles.len() < 16_384, "the SDK channel must be bounded");
    }
    assert!(!handles.is_empty());
    let budget = Duration::from_millis(40);
    let result = tokio::time::timeout(
        Duration::from_secs(1),
        session.call_tool_timed("never-sent".into(), serde_json::json!({}), budget),
    )
    .await;
    // Always release the fixture before reporting an assertion failure.
    drop(release_on_drop);
    assert!(
        matches!(result, Ok(Err(ServiceError::Timeout { timeout })) if timeout == budget),
        "expected the enqueue deadline, got {result:?}",
    );
    session
        .request(
            ClientRequest::PingRequest(Default::default()),
            Duration::from_secs(2),
        )
        .await
        .unwrap();
    assert_eq!(
        tool_calls.load(Ordering::SeqCst),
        0,
        "a cancelled enqueue must not be sent later or replayed"
    );
    session.close().await.unwrap();
}
