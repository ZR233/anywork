use futures::{SinkExt, StreamExt};
use pl_protocol::PureError;
use std::sync::Arc;
use tokio::net::TcpStream;
use tokio::sync::{OwnedSemaphorePermit, Semaphore, mpsc, oneshot};
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::{MaybeTlsStream, WebSocketStream};

use crate::runtime::responses_websocket::error::{connection_error, protocol_error, socket_error};

type RawResponsesWebSocket = WebSocketStream<MaybeTlsStream<TcpStream>>;
const MAX_QUEUED_BYTES: u32 = 64 * 1024 * 1024;

enum WebSocketCommand {
    Send {
        message: Message,
        result: oneshot::Sender<std::result::Result<(), PureError>>,
    },
}

struct QueuedMessage {
    message: Message,
    _bytes: OwnedSemaphorePermit,
}

/// 持续驱动物理 WebSocket 的连接句柄。
///
/// 收包循环独立于模型事件消费者，因此 agent 执行工具或等待下一轮输入时仍会及时
/// 回复 ping。有响应积压时以原帧数和字节预算向套接字施加背压，不把消费者暂慢
/// 当作断线。该类型只管理物理连接，不持有 continuation 或 provider 配置。
pub(crate) struct ResponsesWebSocketConnection {
    command_tx: mpsc::Sender<WebSocketCommand>,
    message_rx: mpsc::Receiver<QueuedMessage>,
    terminal_rx: Option<oneshot::Receiver<PureError>>,
    pump_task: Option<tokio::task::JoinHandle<()>>,
}

impl ResponsesWebSocketConnection {
    pub(crate) fn new(mut socket: RawResponsesWebSocket) -> Self {
        let (command_tx, mut command_rx) = mpsc::channel(8);
        let (message_tx, message_rx) = mpsc::channel(32);
        let (terminal_tx, terminal_rx) = oneshot::channel();
        // Bound bytes as well as frame count; otherwise 32 large JSON frames could
        // retain gigabytes while the consumer is stalled. Ping/Pong never enter this queue.
        let queued_bytes = Arc::new(Semaphore::new(MAX_QUEUED_BYTES as usize));
        let pump_task = tokio::spawn(async move {
            let terminal = loop {
                tokio::select! {
                    command = command_rx.recv() => {
                        let Some(command) = command else {
                            break connection_error("connection owner closed");
                        };
                        match command {
                            WebSocketCommand::Send { message, result } => {
                                let send_result = socket
                                    .send(message)
                                    .await
                                    .map_err(socket_error);
                                match send_result {
                                    Ok(()) => { let _ = result.send(Ok(())); }
                                    Err(error) => {
                                        let _ = result.send(Err(error));
                                        break connection_error("request send failed");
                                    }
                                }
                            }
                        }
                    }
                    message = socket.next() => {
                        match message {
                            Some(Ok(Message::Ping(payload))) => {
                                if let Err(error) = socket.send(Message::Pong(payload)).await {
                                    break socket_error(error);
                                }
                            }
                            Some(Ok(Message::Pong(_))) => {}
                            Some(Ok(message)) => {
                                let is_close = matches!(message, Message::Close(_));
                                let bytes = u32::try_from(message.len().saturating_add(64))
                                    .ok().filter(|bytes| *bytes <= MAX_QUEUED_BYTES);
                                let Some(bytes) = bytes else {
                                    break protocol_error("single response event exceeds the 64 MiB queue byte limit");
                                };
                                // next() can repeatedly return buffered frames without yielding.
                                // Wait for the original consumer instead of mistaking a full queue
                                // for a transport failure. Only this one pending frame is retained;
                                // close/retire still abort and join this owned pump while it waits.
                                let permit = match Arc::clone(&queued_bytes).acquire_many_owned(bytes).await {
                                    Ok(permit) => permit,
                                    Err(_) => break connection_error("connection owner closed"),
                                };
                                if message_tx.send(QueuedMessage { message, _bytes: permit }).await.is_err() {
                                    break connection_error("connection owner closed");
                                }
                                if is_close {
                                    break connection_error("server closed the connection");
                                }
                            }
                            Some(Err(error)) => {
                                break socket_error(error);
                            }
                            None => break connection_error("connection ended without a terminal response"),
                        }
                    }
                }
            };
            let _ = terminal_tx.send(terminal);
        });
        Self {
            command_tx,
            message_rx,
            terminal_rx: Some(terminal_rx),
            pump_task: Some(pump_task),
        }
    }

    pub(crate) async fn close(&mut self) -> Result<(), PureError> {
        let Some(task) = self.pump_task.as_mut() else {
            return Ok(());
        };
        task.abort();
        let outcome = task.await;
        self.pump_task = None;
        match outcome {
            Ok(()) => Ok(()),
            Err(error) if error.is_cancelled() => Ok(()),
            Err(error) => Err(connection_error(format!(
                "Responses WebSocket pump failed while closing: {error}"
            ))),
        }
    }

    pub(crate) fn is_closed(&self) -> bool {
        self.command_tx.is_closed()
            || self
                .pump_task
                .as_ref()
                .is_none_or(|task| task.is_finished())
    }

    pub(crate) fn retire(&self) {
        if let Some(task) = &self.pump_task {
            task.abort();
        }
    }

    pub(crate) async fn send(&self, message: Message) -> std::result::Result<(), PureError> {
        let (result_tx, result_rx) = oneshot::channel();
        self.command_tx
            .send(WebSocketCommand::Send {
                message,
                result: result_tx,
            })
            .await
            .map_err(|_| connection_error("Responses WebSocket connection is closed"))?;
        result_rx
            .await
            .unwrap_or_else(|_| Err(connection_error("Responses WebSocket connection is closed")))
    }

    pub(crate) async fn next(&mut self) -> Option<std::result::Result<Message, PureError>> {
        if let Some(message) = self.message_rx.recv().await {
            return Some(Ok(message.message));
        }
        let terminal = self.terminal_rx.as_mut()?;
        let error = terminal
            .await
            .unwrap_or_else(|_| connection_error("connection pump stopped"));
        self.terminal_rx = None;
        Some(Err(error))
    }
}

impl Drop for ResponsesWebSocketConnection {
    fn drop(&mut self) {
        if let Some(task) = &self.pump_task {
            task.abort();
        }
    }
}

#[cfg(test)]
mod tests {
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
}
