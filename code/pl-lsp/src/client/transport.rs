use std::io::{BufReader, Write};
use std::thread::{self, JoinHandle};

use lsp_server::Message;
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::runtime::Handle;
use tokio::sync::mpsc;
use tokio_util::io::SyncIoBridge;

use crate::runtime::{LspResult, LspRuntimeError};

const MESSAGE_CHANNEL_CAPACITY: usize = 256;

pub(super) enum OutboundMessage {
    Message(Message),
    Close,
}

#[derive(Clone)]
pub(crate) struct TransportSender {
    pub(super) outbound: mpsc::Sender<OutboundMessage>,
}

pub(crate) struct LspTransport {
    outbound: Option<mpsc::Sender<OutboundMessage>>,
    reader: Option<JoinHandle<()>>,
    writer: Option<JoinHandle<()>>,
}

impl LspTransport {
    pub(crate) fn spawn<W, R>(
        stdin: W,
        stdout: R,
    ) -> LspResult<(Self, mpsc::Receiver<LspResult<Message>>)>
    where
        W: AsyncWrite + Unpin + Send + 'static,
        R: AsyncRead + Unpin + Send + 'static,
    {
        Self::spawn_io(stdin, stdout, Handle::current())
    }

    fn spawn_io<W, R>(
        stdin: W,
        stdout: R,
        runtime: Handle,
    ) -> LspResult<(Self, mpsc::Receiver<LspResult<Message>>)>
    where
        W: AsyncWrite + Unpin + Send + 'static,
        R: AsyncRead + Unpin + Send + 'static,
    {
        let (outbound, mut outbound_rx) =
            mpsc::channel::<OutboundMessage>(MESSAGE_CHANNEL_CAPACITY);
        let (inbound_tx, inbound) = mpsc::channel(MESSAGE_CHANNEL_CAPACITY);
        let writer_inbound = inbound_tx.clone();
        let writer_runtime = runtime.clone();
        let writer = thread::Builder::new()
            .name("pl-lsp-writer".to_string())
            .spawn(move || {
                let mut writer = SyncIoBridge::new_with_handle(stdin, writer_runtime);
                while let Some(outbound) = outbound_rx.blocking_recv() {
                    match outbound {
                        OutboundMessage::Message(message) => {
                            if let Err(error) =
                                message.write(&mut writer).and_then(|()| writer.flush())
                            {
                                // Reject new sends before reporting the actual transport fault,
                                // so a dispatcher writing a response cannot block this event.
                                outbound_rx.close();
                                let _ =
                                    writer_inbound.blocking_send(Err(LspRuntimeError::Io(error)));
                                break;
                            }
                        }
                        OutboundMessage::Close => break,
                    }
                }
            })
            .map_err(|error| {
                LspRuntimeError::Unavailable(format!("failed to start LSP writer thread: {error}"))
            })?;
        let reader = thread::Builder::new()
            .name("pl-lsp-reader".to_string())
            .spawn(move || {
                let mut reader = BufReader::new(SyncIoBridge::new_with_handle(stdout, runtime));
                loop {
                    let message = match Message::read(&mut reader) {
                        Ok(Some(message)) => Ok(message),
                        // The writer also owns an inbound sender to report write faults,
                        // so EOF must be explicit rather than relying on channel closure.
                        Ok(None) => Err(LspRuntimeError::Unavailable("LSP stdout closed".into())),
                        Err(error) => Err(LspRuntimeError::Io(error)),
                    };
                    let terminal = message.is_err();
                    if inbound_tx.blocking_send(message).is_err() || terminal {
                        break;
                    }
                }
            });
        let reader = match reader {
            Ok(reader) => reader,
            Err(error) => {
                drop(outbound);
                let _ = writer.join();
                return Err(LspRuntimeError::Unavailable(format!(
                    "failed to start LSP reader thread: {error}"
                )));
            }
        };
        Ok((
            Self {
                outbound: Some(outbound),
                reader: Some(reader),
                writer: Some(writer),
            },
            inbound,
        ))
    }

    pub(crate) fn sender(&self) -> LspResult<TransportSender> {
        self.outbound
            .clone()
            .map(|outbound| TransportSender { outbound })
            .ok_or_else(|| LspRuntimeError::Unavailable("LSP transport is closed".to_string()))
    }

    pub(crate) fn close(&mut self) {
        if let Some(outbound) = self.outbound.take() {
            let _ = outbound.blocking_send(OutboundMessage::Close);
        }
        if let Some(writer) = self.writer.take() {
            let _ = writer.join();
        }
        if let Some(reader) = self.reader.take() {
            let _ = reader.join();
        }
    }
}

impl TransportSender {
    pub(crate) async fn send(&self, message: Message) -> LspResult<()> {
        self.outbound
            .send(OutboundMessage::Message(message))
            .await
            .map_err(|_| LspRuntimeError::Unavailable("LSP writer channel closed".to_string()))
    }
}
