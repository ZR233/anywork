#![cfg(unix)]

mod support;

use std::{process::Stdio, sync::atomic::Ordering};

use pl_studio_mcp::{IPC_CAPABILITY_ENV, IPC_ENDPOINT_ENV, STDIO_ARG, ipc::IpcServer};
use rmcp::{
    RoleClient, ServiceExt,
    model::{
        CallToolRequest, CallToolRequestParams, CallToolResponse, ClientCapabilities,
        ClientJsonRpcMessage, ClientRequest, Implementation, InitializeRequest,
        InitializeRequestParams, ProtocolVersion, RequestId,
    },
    service::PeerRequestOptions,
    transport::{Transport, async_rw::AsyncRwTransport},
};
use serde_json::{Value, json};
use support::{Backend, TIMEOUT, invocation};
use tokio::{
    io::AsyncReadExt,
    process::{Child, Command},
};
use tokio_util::sync::CancellationToken;

fn child(server: &IpcServer) -> Child {
    Command::new(env!("CARGO_BIN_EXE_pl-studio-mcp"))
        .arg(STDIO_ARG)
        .env(IPC_ENDPOINT_ENV, server.endpoint())
        .env(IPC_CAPABILITY_ENV, server.capability())
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true)
        .spawn()
        .unwrap()
}

async fn reap(child: &mut Child) -> std::process::ExitStatus {
    match tokio::time::timeout(TIMEOUT, child.wait()).await {
        Ok(status) => status.unwrap(),
        Err(_) => {
            child.kill().await.unwrap();
            let status = child.wait().await.unwrap();
            panic!("stdio process did not exit without kill: {status}");
        }
    }
}

fn call(arguments: Value) -> CallToolRequestParams {
    CallToolRequestParams::new("anywork_wait_agent").with_arguments(invocation(arguments).arguments)
}

async fn wait_ended(backend: &Backend) {
    let token = backend.0.wait_token.lock().unwrap().clone().unwrap();
    tokio::time::timeout(TIMEOUT, async {
        token.cancelled().await;
        while backend.0.active.load(Ordering::SeqCst) != 0 {
            backend.0.ended.notified().await;
        }
    })
    .await
    .unwrap();
}

#[tokio::test]
async fn production_stdio_official_client_catalog_results_concurrency_cancel_and_eof() {
    let backend = Backend::default();
    let mut server = IpcServer::bind(backend.clone(), CancellationToken::new())
        .await
        .unwrap();
    let mut child = child(&server);
    let mut service = tokio::time::timeout(
        TIMEOUT,
        ().serve((child.stdout.take().unwrap(), child.stdin.take().unwrap())),
    )
    .await
    .unwrap()
    .unwrap();
    let catalog = service.list_tools(None).await.unwrap();
    assert_eq!(catalog.tools.len(), 1);
    assert_eq!(catalog.tools[0].name, "anywork_wait_agent");
    let success = service.call_tool(call(json!({"answer":42}))).await.unwrap();
    assert_eq!(success.structured_content, Some(json!({"answer":42})));
    assert_eq!(success.is_error, Some(false));
    let error = service
        .call_tool(call(json!({"error":true})))
        .await
        .unwrap();
    assert_eq!(error.structured_content, Some(json!({"error":true})));
    assert_eq!(error.is_error, Some(true));
    let mut calls = tokio::task::JoinSet::new();
    for id in 0..16u64 {
        let peer = service.peer().clone();
        calls.spawn(async move {
            let response = peer.call_tool_once(call(json!({"id":id}))).await.unwrap();
            let CallToolResponse::Complete(response) = response else {
                panic!("unexpected non-final response");
            };
            assert_eq!(response.structured_content, Some(json!({"id":id})));
        });
    }
    tokio::time::timeout(TIMEOUT, async {
        while let Some(joined) = calls.join_next().await {
            joined.unwrap();
        }
    })
    .await
    .unwrap();
    let handle = service
        .send_cancellable_request(
            ClientRequest::CallToolRequest(CallToolRequest::new(call(json!({"wait":true})))),
            PeerRequestOptions::no_options(),
        )
        .await
        .unwrap();
    tokio::time::timeout(TIMEOUT, backend.0.started.notified())
        .await
        .unwrap();
    handle.cancel(None).await.unwrap();
    wait_ended(&backend).await;
    assert_eq!(backend.0.calls.load(Ordering::SeqCst), 19);
    // Official client closes its writer, giving production stdin a real EOF.
    service.close().await.unwrap();
    assert!(reap(&mut child).await.success());
    let mut diagnostics = String::new();
    child
        .stderr
        .take()
        .unwrap()
        .read_to_string(&mut diagnostics)
        .await
        .unwrap();
    assert!(!diagnostics.contains(server.capability()));
    server.close().await.unwrap();
    assert_eq!(backend.0.active.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn production_stdio_ipc_loss_joins_pending_call_and_exits_without_replay() {
    let backend = Backend::default();
    let mut server = IpcServer::bind(backend.clone(), CancellationToken::new())
        .await
        .unwrap();
    let mut child = child(&server);
    let mut service = tokio::time::timeout(
        TIMEOUT,
        ().serve((child.stdout.take().unwrap(), child.stdin.take().unwrap())),
    )
    .await
    .unwrap()
    .unwrap();
    let handle = service
        .send_cancellable_request(
            ClientRequest::CallToolRequest(CallToolRequest::new(call(json!({"wait":true})))),
            PeerRequestOptions::no_options(),
        )
        .await
        .unwrap();
    tokio::time::timeout(TIMEOUT, backend.0.started.notified())
        .await
        .unwrap();
    server.close().await.unwrap();
    assert!(!reap(&mut child).await.success());
    assert!(
        tokio::time::timeout(TIMEOUT, handle.await_response())
            .await
            .unwrap()
            .is_err()
    );
    service.close().await.unwrap();
    assert_eq!(backend.0.calls.load(Ordering::SeqCst), 1);
    assert_eq!(backend.0.active.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn production_stdio_eof_before_and_during_initialize_has_no_orphan_connection() {
    let backend = Backend::default();
    let mut server = IpcServer::bind(backend.clone(), CancellationToken::new())
        .await
        .unwrap();
    let mut unopened = child(&server);
    drop(unopened.stdin.take());
    assert!(!reap(&mut unopened).await.success());

    let mut half = child(&server);
    // Use only official typed transport/model: no fixture MCP implementation or codec.
    let mut transport = AsyncRwTransport::<RoleClient, _, _>::new(
        half.stdout.take().unwrap(),
        half.stdin.take().unwrap(),
    );
    transport
        .send(ClientJsonRpcMessage::request(
            ClientRequest::InitializeRequest(InitializeRequest::new(
                InitializeRequestParams::new(
                    ClientCapabilities::default(),
                    Implementation::default(),
                )
                .with_protocol_version(ProtocolVersion::V_2025_03_26),
            )),
            RequestId::Number(1),
        ))
        .await
        .unwrap();
    assert!(
        tokio::time::timeout(TIMEOUT, transport.receive())
            .await
            .unwrap()
            .is_some()
    );
    // rmcp 3.9 enters its service loop immediately after InitializeResult;
    // it deliberately does not gate on the initialized notification. Therefore
    // this half-handshake EOF is a normal (successful) transport shutdown.
    transport.close().await.unwrap();
    assert!(reap(&mut half).await.success());
    drop(transport);
    server.close().await.unwrap();
    assert_eq!(backend.0.calls.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn production_stdio_ipc_disappears_during_initialize_with_stdin_still_open() {
    let backend = Backend::default();
    let mut server = IpcServer::bind(backend.clone(), CancellationToken::new())
        .await
        .unwrap();
    let mut child = child(&server);
    let mut transport = AsyncRwTransport::<RoleClient, _, _>::new(
        child.stdout.take().unwrap(),
        child.stdin.take().unwrap(),
    );
    transport
        .send(ClientJsonRpcMessage::request(
            ClientRequest::InitializeRequest(InitializeRequest::new(
                InitializeRequestParams::new(
                    ClientCapabilities::default(),
                    Implementation::default(),
                )
                .with_protocol_version(ProtocolVersion::V_2025_03_26),
            )),
            RequestId::Number(1),
        ))
        .await
        .unwrap();
    assert!(
        tokio::time::timeout(TIMEOUT, transport.receive())
            .await
            .unwrap()
            .is_some()
    );
    server.close().await.unwrap();
    // Keep writer alive: IPC termination, not stdin EOF, must end the process.
    assert!(!reap(&mut child).await.success());
    transport.close().await.unwrap();
    assert_eq!(backend.0.calls.load(Ordering::SeqCst), 0);
}
