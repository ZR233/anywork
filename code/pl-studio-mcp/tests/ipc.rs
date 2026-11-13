#![cfg(unix)]

mod support;

use std::{os::unix::fs::PermissionsExt, path::Path, sync::atomic::Ordering};

use pl_studio_mcp::{
    HostError, HostTools, MAX_MESSAGE_BYTES,
    ipc::{IpcClient, IpcServer},
};
use serde_json::json;
use support::{Backend, TIMEOUT, invocation};
use tokio_util::sync::CancellationToken;

#[tokio::test]
async fn domain_roundtrip_flow_control_limits_authentication_and_join() {
    let backend = Backend::default();
    let mut server = IpcServer::bind(backend.clone(), CancellationToken::new())
        .await
        .unwrap();
    let endpoint = server.endpoint().to_owned();
    let capability = server.capability().to_owned();
    let socket = Path::new(&endpoint);
    assert_eq!(
        std::fs::metadata(socket).unwrap().permissions().mode() & 0o777,
        0o600
    );
    assert_eq!(
        std::fs::metadata(socket.parent().unwrap())
            .unwrap()
            .permissions()
            .mode()
            & 0o777,
        0o700,
    );
    assert!(!format!("{server:?}").contains(&capability));
    let client = IpcClient::connect(endpoint.clone(), capability.clone())
        .await
        .unwrap();
    assert!(!format!("{client:?}").contains(&capability));
    let catalog = client.catalog().await.unwrap();
    assert_eq!(catalog.len(), 1);
    assert_eq!(catalog[0].operation.tool_name(), "anywork_wait_agent");

    let wrong = IpcClient::connect(endpoint.clone(), uuid::Uuid::new_v4().to_string())
        .await
        .unwrap();
    assert!(matches!(
        wrong.catalog().await,
        Err(HostError::Unauthorized)
    ));
    assert!(matches!(
        wrong
            .invoke(invocation(json!({"id": 999})), CancellationToken::new())
            .await,
        Err(HostError::Unauthorized)
    ));
    assert_eq!(backend.0.calls.load(Ordering::SeqCst), 0);
    wrong.close().await.unwrap();
    wrong.closed().await;

    let payload = "a".repeat(300_000); // exceeds both initial h2 flow-control windows
    let result = tokio::time::timeout(
        TIMEOUT,
        client.invoke(
            invocation(json!({"payload":payload})),
            CancellationToken::new(),
        ),
    )
    .await
    .unwrap()
    .unwrap();
    assert_eq!(result.value["payload"], payload);
    assert!(!result.is_error);
    let error = client
        .invoke(
            invocation(json!({"error":true, "message":"business failure"})),
            CancellationToken::new(),
        )
        .await
        .unwrap();
    assert!(error.is_error);
    assert_eq!(error.value["message"], "business failure");

    let calls = backend.0.calls.load(Ordering::SeqCst);
    assert!(matches!(
        client
            .invoke(
                invocation(json!({"payload":"a".repeat(MAX_MESSAGE_BYTES)})),
                CancellationToken::new()
            )
            .await,
        Err(HostError::TooLarge)
    ));
    assert_eq!(backend.0.calls.load(Ordering::SeqCst), calls);
    assert!(matches!(
        client
            .invoke(
                invocation(json!({"generate":MAX_MESSAGE_BYTES})),
                CancellationToken::new()
            )
            .await,
        Err(HostError::TooLarge)
    ));
    assert_eq!(client.catalog().await.unwrap().len(), 1);
    {
        let close = client.close();
        tokio::pin!(close);
        assert!(futures::poll!(&mut close).is_pending());
        // Cancelling close retains its strongly shared original driver join.
    }
    client.close().await.unwrap();
    assert!(matches!(client.catalog().await, Err(HostError::Closed)));
    {
        let close = server.close();
        tokio::pin!(close);
        assert!(futures::poll!(&mut close).is_pending());
        // Cancellation leaves the server's original join handle available to retry.
    }
    server.close().await.unwrap();
    assert!(!socket.exists());
    assert!(!socket.parent().unwrap().exists());
    assert_eq!(backend.0.active.load(Ordering::SeqCst), 0);
    assert!(IpcClient::connect(endpoint, capability).await.is_err());
}

#[tokio::test]
async fn concurrent_streams_do_not_cross_results_or_replay() {
    let backend = Backend::default();
    let mut server = IpcServer::bind(backend.clone(), CancellationToken::new())
        .await
        .unwrap();
    let client = IpcClient::connect(server.endpoint().into(), server.capability().into())
        .await
        .unwrap();
    let mut calls = tokio::task::JoinSet::new();
    for id in 0..64u64 {
        let client = client.clone();
        calls.spawn(async move {
            let result = client
                .invoke(invocation(json!({"id":id})), CancellationToken::new())
                .await
                .unwrap();
            assert_eq!(result.value["id"], id);
        });
    }
    tokio::time::timeout(TIMEOUT, async {
        while let Some(result) = calls.join_next().await {
            result.unwrap();
        }
    })
    .await
    .unwrap();
    assert_eq!(backend.0.calls.load(Ordering::SeqCst), 64);
    assert_eq!(backend.0.echoes.lock().unwrap().len(), 64);
    client.close().await.unwrap();
    server.close().await.unwrap();
}

#[tokio::test]
async fn token_cancel_future_drop_and_owner_close_end_pending_observation() {
    let backend = Backend::default();
    let mut server = IpcServer::bind(backend.clone(), CancellationToken::new())
        .await
        .unwrap();
    let client = IpcClient::connect(server.endpoint().into(), server.capability().into())
        .await
        .unwrap();
    for drop_future in [false, true] {
        let cancellation = CancellationToken::new();
        {
            let invoke = client.invoke(invocation(json!({"wait":true})), cancellation.clone());
            tokio::pin!(invoke);
            tokio::select! {
                _ = backend.0.started.notified() => {},
                _ = &mut invoke => panic!("wait unexpectedly completed"),
            }
            if !drop_future {
                cancellation.cancel();
                assert!(matches!(invoke.await, Err(HostError::Closed)));
            }
            // Otherwise drop the actual borrowed transport future, without
            // cancelling the caller token. Its h2 stream must still reset.
        }
        let token = backend.0.wait_token.lock().unwrap().clone().unwrap();
        tokio::time::timeout(TIMEOUT, token.cancelled())
            .await
            .unwrap();
        tokio::time::timeout(TIMEOUT, async {
            while backend.0.active.load(Ordering::SeqCst) != 0 {
                backend.0.ended.notified().await;
            }
        })
        .await
        .unwrap();
    }

    let invoke = client.invoke(invocation(json!({"wait":true})), CancellationToken::new());
    tokio::pin!(invoke);
    tokio::select! {
        _ = backend.0.started.notified() => {},
        _ = &mut invoke => panic!("wait unexpectedly completed"),
    }
    tokio::time::timeout(TIMEOUT, server.close())
        .await
        .unwrap()
        .unwrap();
    assert!(invoke.await.is_err());
    client.closed().await;
    // Normal owner shutdown sends GOAWAY(NO_ERROR); join is not a cleanup failure.
    client.close().await.unwrap();
    assert_eq!(backend.0.calls.load(Ordering::SeqCst), 3);
    assert_eq!(backend.0.active.load(Ordering::SeqCst), 0);
}
