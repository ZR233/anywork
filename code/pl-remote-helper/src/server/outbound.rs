use std::io;
use std::sync::Arc;

use pl_protocol::remote::{
    REMOTE_OUTPUT_CHUNK_BYTES, REMOTE_OUTPUT_WINDOW, RemoteEvent, RemoteMessage,
};
use tokio::io::AsyncWrite;
use tokio::sync::{OwnedSemaphorePermit, mpsc, oneshot, watch};
use tokio::task::JoinHandle;

use crate::codec::write_frame;

type WriteResult = Result<(), Arc<io::Error>>;

struct WriteRequest {
    request_id: Option<u64>,
    message: RemoteMessage,
    body: Vec<u8>,
    receipt: Option<oneshot::Sender<WriteResult>>,
}

/// Clones enqueue frames; only OutboundTask owns and writes the byte stream.
#[derive(Debug, Clone)]
pub(super) struct Outbound {
    queue: mpsc::Sender<WriteRequest>,
    stop: watch::Sender<bool>,
    failure: watch::Receiver<Option<Arc<io::Error>>>,
}

pub(super) struct OutboundTask {
    join: JoinHandle<WriteResult>,
}

impl Outbound {
    pub(super) fn new(writer: Box<dyn AsyncWrite + Send + Unpin>) -> (Self, OutboundTask) {
        let writer = Box::new(tokio::io::BufWriter::with_capacity(
            REMOTE_OUTPUT_CHUNK_BYTES * REMOTE_OUTPUT_WINDOW,
            writer,
        ));
        let (queue, receiver) = mpsc::channel(32);
        let (stop, stopped) = watch::channel(false);
        let (report, failure) = watch::channel(None);
        let join = tokio::spawn(async move {
            let result = write_loop(writer, receiver, stopped)
                .await
                .map_err(Arc::new);
            if let Err(error) = &result {
                report.send_replace(Some(error.clone()));
            }
            result
        });
        (
            Self {
                queue,
                stop,
                failure,
            },
            OutboundTask { join },
        )
    }

    pub(super) async fn write(
        &self,
        request_id: Option<u64>,
        message: RemoteMessage,
        body: &[u8],
    ) -> io::Result<()> {
        // Reserve before allocating a copy: blocked producers do not grow an unbounded queue.
        let permit = self
            .queue
            .reserve()
            .await
            .map_err(|_| self.closed_error())?;
        let (receipt, response) = oneshot::channel();
        permit.send(WriteRequest {
            request_id,
            message,
            body: body.to_vec(),
            receipt: Some(receipt),
        });
        response
            .await
            .map_err(|_| self.closed_error())?
            .map_err(shared_error)
    }

    pub(super) fn close(&self) {
        self.stop.send_replace(true);
    }

    /// Transfers a completed ordinary response to the bounded writer. Release admission
    /// before publishing the response, so a peer may immediately submit its next request.
    pub(super) async fn respond(
        &self,
        request_id: Option<u64>,
        response: pl_protocol::remote::RemoteResponse,
        body: Vec<u8>,
        admission: OwnedSemaphorePermit,
    ) -> io::Result<()> {
        let position = self
            .queue
            .reserve()
            .await
            .map_err(|_| self.closed_error())?;
        let response = WriteRequest {
            request_id,
            message: RemoteMessage::Response(response),
            body,
            receipt: None,
        };
        drop(admission);
        position.send(response);
        Ok(())
    }

    pub(super) async fn failed(&self) -> io::Error {
        let mut failure = self.failure.clone();
        match failure.wait_for(Option::is_some).await {
            Ok(error) => match error.as_ref() {
                Some(error) => shared_error(error.clone()),
                None => io::Error::other("writer failure notification was empty"),
            },
            Err(_) => io::Error::new(io::ErrorKind::BrokenPipe, "remote writer closed"),
        }
    }

    fn closed_error(&self) -> io::Error {
        match self.failure.borrow().as_ref() {
            Some(error) => shared_error(error.clone()),
            None => io::Error::new(io::ErrorKind::BrokenPipe, "remote writer closed"),
        }
    }
}

impl OutboundTask {
    pub(super) async fn wait(&mut self) -> io::Result<()> {
        (&mut self.join)
            .await
            .map_err(io::Error::other)?
            .map_err(shared_error)
    }
}

impl Drop for OutboundTask {
    fn drop(&mut self) {
        // Cancellation discards the entire stream, never resumes a partially written frame.
        self.join.abort();
    }
}

async fn write_loop(
    mut writer: Box<dyn AsyncWrite + Send + Unpin>,
    mut queue: mpsc::Receiver<WriteRequest>,
    mut stopped: watch::Receiver<bool>,
) -> io::Result<()> {
    let mut sequence = 0_u64;
    loop {
        let mut request = tokio::select! {
            biased;
            _ = stopped.wait_for(|stopped| *stopped) => return Ok(()),
            request = queue.recv() => match request { Some(request) => request, None => return Ok(()) },
        };
        if let RemoteMessage::Event(RemoteEvent::ProcessOutput(output)) = &mut request.message {
            sequence = sequence
                .checked_add(1)
                .ok_or_else(|| io::Error::other("output sequence exhausted"))?;
            output.sequence = sequence;
        }
        let result = tokio::select! {
            biased;
            _ = stopped.wait_for(|stopped| *stopped) => return Ok(()),
            result = write_frame(&mut writer, request.request_id, request.message, &request.body) => result,
        };
        match result {
            Ok(()) => {
                if let Some(receipt) = request.receipt {
                    let _ = receipt.send(Ok(()));
                }
            }
            Err(error) => {
                let error = Arc::new(error);
                if let Some(receipt) = request.receipt {
                    let _ = receipt.send(Err(error.clone()));
                }
                return Err(shared_error(error));
            }
        }
    }
}

#[derive(Debug, thiserror::Error)]
#[error("remote writer: {0}")]
struct SharedWriteError(#[source] Arc<io::Error>);

fn shared_error(error: Arc<io::Error>) -> io::Error {
    io::Error::new(error.kind(), SharedWriteError(error))
}
