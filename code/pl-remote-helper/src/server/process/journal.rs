//! Unconfirmed per-process output, independent of any HTTP/2 stream incarnation.
use super::*;
use crate::transport::{Bytes, EVENT_CONTENT, Response, send_bytes};
use base64::{Engine, engine::general_purpose::STANDARD};
use std::collections::VecDeque;

#[derive(Debug)]
struct Record {
    sequence: u64,
    bytes: Bytes,
    _memory: Option<ByteLease>,
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
    budget: ResourceBudget,
    parent: ResourceBudget,
    credit: Mutex<ByteLease>,
}
impl Journal {
    pub(super) fn new(parent: ResourceBudget) -> Result<Self, RemoteError> {
        let mut allocation = parent.allocation();
        allocation.resident_bytes = allocation.fragment_bytes.saturating_mul(4);
        let credit = parent
            .try_reserve(allocation.resident_bytes)
            .ok_or_else(|| {
                remote_error(
                    RemoteErrorCode::ResourceExhausted,
                    "process output progress reservation unavailable",
                )
            })?;
        let budget = ResourceBudget::new(allocation)
            .map_err(|e| io_error("process output allocation", e))?;
        Ok(Self {
            state: Mutex::new(State::default()),
            changed: Notify::new(),
            budget,
            parent,
            credit: Mutex::new(credit),
        })
    }
    pub(super) fn fragment_bytes(&self) -> usize {
        self.budget.allocation().fragment_bytes
    }
    async fn resize(&self) {
        let mut allocation = self.parent.allocation();
        allocation.fragment_bytes = allocation
            .fragment_bytes
            .min(self.budget.allocation().fragment_bytes);
        allocation.resident_bytes = allocation.fragment_bytes.saturating_mul(4);
        let required = allocation.resident_bytes.max(self.budget.usage().0);
        if self.credit.lock().await.resize(required) {
            let _ = self.budget.resize(allocation);
        }
    }
    pub(super) async fn push(
        &self,
        id: &str,
        stream: RemoteOutputStream,
        bytes: &[u8],
        stop: &CancellationToken,
    ) -> Result<(), RemoteError> {
        let cost = bytes
            .len()
            .saturating_mul(2)
            .saturating_add(std::mem::size_of::<RemoteOutputRecord>() + id.len());
        let memory = self
            .budget
            .reserve(cost, stop)
            .await
            .map_err(|e| io_error("reserve output replay", e))?;
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
            _memory: Some(memory),
        }));
        drop(state);
        self.changed.notify_waiters();
        Ok(())
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
        // Terminal metadata belongs to the process reservation, not the blocked output budget.
        if let Ok(bytes) = encode(record) {
            state.records.push_back(Arc::new(Record {
                sequence,
                bytes,
                _memory: None,
            }));
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
        self.resize().await;
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
    Ok(sse_stream::Sse::default()
        .id(record.sequence.to_string())
        .data(data)
        .into())
}
