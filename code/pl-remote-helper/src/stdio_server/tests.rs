//! Exercise cancellation at the production h2 request/pipe ownership boundary.
use super::*;
use std::time::Duration;

async fn peer() -> (
    h2::client::SendRequest<Bytes>,
    tokio::task::JoinHandle<()>,
    tokio::task::JoinHandle<Result<(), crate::ServerError>>,
) {
    let (client, server) = tokio::io::duplex(1024 * 1024);
    let server = tokio::spawn(serve(server));
    let (sender, connection) = h2::client::handshake(client).await.unwrap();
    let driver = tokio::spawn(async move {
        let _ = connection.await;
    });
    (sender, driver, server)
}
fn request(method: http::Method, path: &str) -> http::Request<()> {
    http::Request::builder()
        .method(method)
        .uri(path)
        .body(())
        .unwrap()
}
async fn close(
    sender: h2::client::SendRequest<Bytes>,
    driver: tokio::task::JoinHandle<()>,
    server: tokio::task::JoinHandle<Result<(), crate::ServerError>>,
) {
    drop(sender);
    driver.abort();
    let _ = driver.await;
    // Closing a deliberately reset transport may report its IO cause; the owner must finish.
    let _ = tokio::time::timeout(Duration::from_secs(5), server)
        .await
        .unwrap()
        .unwrap();
}

#[tokio::test]
async fn cancelled_preparing_rejects_late_pipes_without_recreating_an_owner() {
    for complete_descriptor in [false, true] {
        let (mut sender, driver, server) = peer().await;
        sender = sender.ready().await.unwrap();
        let (_response, mut main) = sender
            .send_request(request(http::Method::POST, "/process/spawn"), false)
            .unwrap();
        let key = main.stream_id().as_u32();
        if complete_descriptor {
            // The descriptor is complete but two of three declared pipes never arrive.
            let executor = Executor::local().unwrap();
            let mut command = executor.command("/definitely/not/started");
            command
                .stdin(Stdio::Piped)
                .stdout(Stdio::Piped)
                .stderr(Stdio::Piped);
            main.send_data(
                serde_json::to_vec(&wire::CommandSpec::from(&command))
                    .unwrap()
                    .into(),
                true,
            )
            .unwrap();
        }
        sender = sender.ready().await.unwrap();
        let (pipe, _) = sender
            .send_request(
                request(http::Method::GET, &format!("/process/{key}/stdout")),
                true,
            )
            .unwrap();
        main.send_reset(h2::Reason::CANCEL);
        // A pipe accepted before reset is dropped with Preparing; it cannot hold the owner open.
        let _ = tokio::time::timeout(Duration::from_secs(2), pipe)
            .await
            .unwrap();
        sender = sender.ready().await.unwrap();
        let (late, _) = sender
            .send_request(
                request(http::Method::GET, &format!("/process/{key}/stderr")),
                true,
            )
            .unwrap();
        let late = tokio::time::timeout(Duration::from_secs(2), late)
            .await
            .unwrap()
            .unwrap_err();
        assert_eq!(late.reason(), Some(h2::Reason::REFUSED_STREAM));
        close(sender, driver, server).await;
    }
}

#[cfg(unix)]
#[tokio::test]
async fn losing_the_spawn_confirmation_cleans_the_started_root_without_replay() {
    let (mut sender, driver, server) = peer().await;
    let temp = tempfile::tempdir().unwrap();
    let marker = temp.path().join("starts");
    let executor = Executor::local().unwrap();
    let mut command = executor.command("/bin/sh");
    command.args([
        "-c",
        "printf x >> \"$1\"; exec sleep 100000",
        "owned",
        marker.to_str().unwrap(),
    ]);
    sender = sender.ready().await.unwrap();
    let (response, mut main) = sender
        .send_request(request(http::Method::POST, "/process/spawn"), false)
        .unwrap();
    main.send_data(
        serde_json::to_vec(&wire::CommandSpec::from(&command))
            .unwrap()
            .into(),
        true,
    )
    .unwrap();
    let response = response.await.unwrap();
    assert_eq!(response.status(), http::StatusCode::OK);
    let pid: u32 = response.headers()["x-process-id"]
        .to_str()
        .unwrap()
        .parse()
        .unwrap();
    tokio::time::timeout(Duration::from_secs(2), async {
        while !marker.exists() {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    main.send_reset(h2::Reason::CANCEL);
    drop(response);
    close(sender, driver, server).await;
    assert_eq!(std::fs::read(marker).unwrap(), b"x");
    #[cfg(target_os = "linux")]
    assert!(
        !std::path::Path::new(&format!("/proc/{pid}")).exists(),
        "cancelled start retained its direct child"
    );
    #[cfg(not(target_os = "linux"))]
    let _ = pid;
}
