use super::*;
use std::time::Duration;

#[tokio::test]
async fn closing_a_backpressured_pump_joins_it_and_releases_the_peer() {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let (sent_tx, sent_rx) = oneshot::channel();
    let server = tokio::spawn(async move {
        let (socket, _) = listener.accept().await.unwrap();
        let mut socket = tokio_tungstenite::accept_async(socket).await.unwrap();
        for index in 0..96 {
            socket
                .feed(Message::Text(format!("frame-{index}").into()))
                .await
                .unwrap();
        }
        socket.flush().await.unwrap();
        sent_tx.send(()).unwrap();
        // This peer must really observe the socket release, not only a local abort flag.
        assert!(!matches!(socket.next().await, Some(Ok(Message::Text(_)))));
    });
    let (socket, _) = tokio_tungstenite::connect_async(format!("ws://{address}"))
        .await
        .unwrap();
    let mut connection = ResponsesWebSocketConnection::new(socket);
    tokio::time::timeout(Duration::from_secs(10), async {
        sent_rx.await.unwrap();
        while connection.message_rx.len() != 32 {
            tokio::task::yield_now().await;
        }
        assert!(
            !connection.is_closed(),
            "full queue must keep its original owner"
        );
        connection.close().await.unwrap();
        assert!(connection.pump_task.is_none());
        assert!(connection.command_tx.is_closed());
        server.await.unwrap();
    })
    .await
    .expect("closing a full queue must interrupt capacity waiting and join");
}

#[tokio::test]
async fn buffered_frames_do_not_disconnect_an_already_waiting_consumer() {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let (release_tx, release_rx) = oneshot::channel();
    let server = tokio::spawn(async move {
        let (socket, _) = listener.accept().await.unwrap();
        let mut socket = tokio_tungstenite::accept_async(socket).await.unwrap();
        release_rx.await.unwrap();
        // A proxy/network read can deliver many small frames together. Feed then flush
        // exercises that normal wire condition without delaying the real consumer.
        for index in 0..96 {
            socket
                .feed(Message::Text(format!("frame-{index}").into()))
                .await
                .unwrap();
        }
        socket.flush().await.unwrap();
        let _ = socket.next().await;
    });
    let (socket, _) = tokio_tungstenite::connect_async(format!("ws://{address}"))
        .await
        .unwrap();
    let mut connection = ResponsesWebSocketConnection::new(socket);
    let (waiting_tx, waiting_rx) = oneshot::channel();
    let consumer = tokio::spawn(async move {
        waiting_tx.send(()).unwrap();
        let mut frames = Vec::new();
        let mut error = None;
        for _ in 0..96 {
            match connection.next().await {
                Some(Ok(Message::Text(text))) => frames.push(text.to_string()),
                other => {
                    error = Some(format!("{other:?}"));
                    break;
                }
            }
        }
        connection.close().await.unwrap();
        (frames, error)
    });
    // The consumer has polled next() on the empty queue before the peer is released.
    waiting_rx.await.unwrap();
    release_tx.send(()).unwrap();
    let (frames, error) = tokio::time::timeout(Duration::from_secs(10), consumer)
        .await
        .unwrap()
        .unwrap();
    tokio::time::timeout(Duration::from_secs(10), server)
        .await
        .unwrap()
        .unwrap();
    assert!(
        error.is_none(),
        "waiting consumer lost the stream after {} frames: {error:?}",
        frames.len()
    );
    pretty_assertions::assert_eq!(
        frames,
        (0..96).map(|i| format!("frame-{i}")).collect::<Vec<_>>()
    );
}
