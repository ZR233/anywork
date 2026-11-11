//! Unconfirmed per-process output, independent of any HTTP/2 stream incarnation.
use super::*;
use crate::transport::{Bytes, EVENT_CONTENT, Response, send_bytes};
use base64::{Engine, engine::general_purpose::STANDARD};
use std::collections::VecDeque;

#[derive(Debug)]
struct Record {
    sequence: u64,
    bytes: Bytes,
}
#[derive(Debug, Default)]
struct State {
    records: VecDeque<Arc<Record>>,
    sequence: u64,
    acknowledged: u64,
    terminal: Option<RemoteProcessExit>,
}
#[derive(Debug)]
pub(super) struct Journal {
    state: Mutex<State>,
    changed: Notify,
}
impl Journal {
    pub(super) fn new() -> Self {
        Self {
            state: Mutex::new(State::default()),
            changed: Notify::new(),
        }
    }
    pub(super) async fn push(
        &self,
        id: &str,
        stream: RemoteOutputStream,
        bytes: &[u8],
        stop: &CancellationToken,
    ) -> Result<(), RemoteError> {
        let mut state = self.state.lock().await;
        state.sequence = state
            .sequence
            .checked_add(1)
            .ok_or_else(|| remote_error(RemoteErrorCode::Io, "output sequence exhausted"))?;
        let sequence = state.sequence;
        let record = RemoteOutputRecord {
            sequence,
            event: RemoteEvent::ProcessOutput(RemoteProcessOutput {
                process_id: id.to_owned(),
                sequence,
                stream,
            }),
            bytes: STANDARD.encode(bytes),
        };
        state.records.push_back(Arc::new(Record {
            sequence,
            bytes: encode(record)?,
        }));
        drop(state);
        self.changed.notify_waiters();
        // The producer retains its current handoff across attachment replacement. Reading the
        // next pipe chunk follows confirmed consumption, rather than a separate byte quota.
        loop {
            let changed = self.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            if self.state.lock().await.acknowledged >= sequence {
                return Ok(());
            }
            tokio::select! {
                _ = changed => {},
                _ = stop.cancelled() => return Err(remote_error(RemoteErrorCode::RemoteDisconnected, "process output cancelled")),
            }
        }
    }
    pub(super) async fn finish(&self, exit: RemoteProcessExit) {
        let mut state = self.state.lock().await;
        state.sequence += 1;
        let sequence = state.sequence;
        state.terminal = Some(exit.clone());
        let record = RemoteOutputRecord {
            sequence,
            event: RemoteEvent::ProcessExit(exit),
            bytes: String::new(),
        };
        if let Ok(bytes) = encode(record) {
            state
                .records
                .push_back(Arc::new(Record { sequence, bytes }));
        }
        drop(state);
        self.changed.notify_waiters();
    }
    pub(super) async fn acknowledge(&self, sequence: u64) -> Result<(), RemoteError> {
        let mut state = self.state.lock().await;
        if sequence > state.sequence {
            return Err(remote_error(
                RemoteErrorCode::InvalidRequest,
                "output acknowledgement exceeds produced sequence",
            ));
        }
        state.acknowledged = state.acknowledged.max(sequence);
        while state
            .records
            .front()
            .is_some_and(|record| record.sequence <= sequence)
        {
            state.records.pop_front();
        }
        if state.records.is_empty() {
            state.records.shrink_to_fit();
        }
        drop(state);
        self.changed.notify_waiters();
        Ok(())
    }
    pub(super) async fn is_finished(&self) -> bool {
        self.state.lock().await.terminal.is_some()
    }
    pub(super) async fn wait(&self) -> RemoteProcessExit {
        loop {
            let changed = self.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            if let Some(exit) = self.state.lock().await.terminal.clone() {
                return exit;
            }
            changed.await;
        }
    }
    pub(super) async fn stream(
        &self,
        mut after: u64,
        mut sender: h2::server::SendResponse<Bytes>,
        stop: CancellationToken,
    ) -> io::Result<()> {
        {
            let state = self.state.lock().await;
            if after < state.acknowledged || after > state.sequence {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    "invalid output continuation",
                ));
            }
        }
        let response = Response::builder()
            .header("content-type", EVENT_CONTENT)
            .body(())
            .map_err(io::Error::other)?;
        let mut output = sender
            .send_response(response, false)
            .map_err(io::Error::other)?;
        loop {
            let changed = self.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            let (record, terminal) = {
                let state = self.state.lock().await;
                (
                    state
                        .records
                        .iter()
                        .find(|record| record.sequence > after)
                        .cloned(),
                    state.terminal.is_some(),
                )
            };
            if let Some(record) = record {
                send_bytes(&mut output, record.bytes.clone(), false, &stop).await?;
                after = record.sequence;
            } else if terminal {
                output
                    .send_data(Bytes::new(), true)
                    .map_err(io::Error::other)?;
                return Ok(());
            } else {
                tokio::select! { _ = changed => {}, _ = stop.cancelled() => return Ok(()) }
            }
        }
    }
}
fn encode(record: RemoteOutputRecord) -> Result<Bytes, RemoteError> {
    let data = serde_json::to_string(&record)
        .map_err(|e| remote_error(RemoteErrorCode::Io, e.to_string()))?;
    sse_stream::Sse::default()
        .id(record.sequence.to_string())
        .data(data)
        .encode()
        .map_err(|error| remote_error(RemoteErrorCode::Io, error.to_string()))
}
