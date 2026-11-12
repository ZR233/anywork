use bytes::{Bytes, BytesMut};
use futures::future::poll_fn;
use h2::{RecvStream, SendStream};
use prost::Message;
use serde::{Serialize, de::DeserializeOwned};

use crate::{HostError, MAX_MESSAGE_BYTES};

pub(super) const CAPABILITY_HEADER: &str = "x-anywork-host-capability";

// Private protobuf envelope; JSON remains the original typed domain payload.
#[derive(Clone, PartialEq, Message)]
pub(super) struct Envelope {
    #[prost(bytes = "vec", tag = "1")]
    pub payload: Vec<u8>,
    #[prost(uint32, tag = "2")]
    pub error: u32,
}

impl Envelope {
    pub fn json(value: &impl Serialize) -> Result<Self, HostError> {
        let envelope = Self {
            payload: serde_json::to_vec(value).map_err(|_| HostError::InvalidRequest)?,
            error: 0,
        };
        if envelope.encoded_len() > MAX_MESSAGE_BYTES {
            return Err(HostError::TooLarge);
        }
        Ok(envelope)
    }

    pub fn failure(error: HostError) -> Self {
        Self {
            payload: Vec::new(),
            error: match error {
                HostError::Closed => 1,
                HostError::Transport => 2,
                HostError::Unauthorized => 3,
                HostError::InvalidRequest => 4,
                HostError::TooLarge => 5,
            },
        }
    }

    pub fn value<T: DeserializeOwned>(self) -> Result<T, HostError> {
        match self.error {
            0 => serde_json::from_slice(&self.payload).map_err(|_| HostError::InvalidRequest),
            1 => Err(HostError::Closed),
            2 => Err(HostError::Transport),
            3 => Err(HostError::Unauthorized),
            4 => Err(HostError::InvalidRequest),
            5 => Err(HostError::TooLarge),
            _ => Err(HostError::InvalidRequest),
        }
    }
}

pub(super) async fn receive(body: &mut RecvStream) -> Result<Envelope, HostError> {
    let mut bytes = BytesMut::new();
    while let Some(chunk) = body.data().await {
        let chunk = chunk.map_err(|_| HostError::Transport)?;
        let len = chunk.len();
        // Return capacity even for the chunk which exceeds the aggregate limit.
        body.flow_control()
            .release_capacity(len)
            .map_err(|_| HostError::Transport)?;
        if len > MAX_MESSAGE_BYTES.saturating_sub(bytes.len()) {
            return Err(HostError::TooLarge);
        }
        bytes.extend_from_slice(&chunk);
    }
    Envelope::decode(bytes).map_err(|_| HostError::InvalidRequest)
}

pub(super) async fn send(
    stream: &mut SendStream<Bytes>,
    envelope: Envelope,
) -> Result<(), HostError> {
    if envelope.encoded_len() > MAX_MESSAGE_BYTES {
        return Err(HostError::TooLarge);
    }
    let mut bytes = Bytes::from(envelope.encode_to_vec());
    while !bytes.is_empty() {
        stream.reserve_capacity(bytes.len().min(16 * 1024));
        let capacity = poll_fn(|cx| stream.poll_capacity(cx))
            .await
            .ok_or(HostError::Transport)?
            .map_err(|_| HostError::Transport)?;
        if capacity == 0 {
            continue;
        }
        let chunk = bytes.split_to(capacity.min(bytes.len()).min(16 * 1024));
        stream
            .send_data(chunk, bytes.is_empty())
            .map_err(|_| HostError::Transport)?;
    }
    if envelope.encoded_len() == 0 {
        stream
            .send_data(Bytes::new(), true)
            .map_err(|_| HostError::Transport)?;
    }
    Ok(())
}

// A dropped invocation future must reset its stream, including while receiving a response.
pub(super) struct ResetOnDrop(pub SendStream<Bytes>);

impl Drop for ResetOnDrop {
    fn drop(&mut self) {
        self.0.send_reset(h2::Reason::CANCEL);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{HostInvocation, HostOperation};
    use serde_json::json;

    #[test]
    fn protobuf_overhead_counts_toward_the_message_limit() {
        // For this size, the bytes field uses one key byte + four length bytes.
        let value = "x".repeat(MAX_MESSAGE_BYTES - 7);
        let envelope = Envelope::json(&value).unwrap();
        assert_eq!(envelope.encoded_len(), MAX_MESSAGE_BYTES);
        assert_eq!(envelope.value::<String>().unwrap(), value);
        assert!(matches!(
            Envelope::json(&format!("{value}x")),
            Err(HostError::TooLarge)
        ));
    }

    #[test]
    fn domain_decode_rejects_authority_fields_and_unknown_operations() {
        for request in [
            json!({"operation":"wait_agent","arguments":{},"caller":"forged"}),
            json!({"operation":"wait_agent","arguments":{},"call_id":"forged"}),
            json!({"operation":"invented_operation","arguments":{}}),
        ] {
            assert!(matches!(
                Envelope::json(&request).unwrap().value::<HostInvocation>(),
                Err(HostError::InvalidRequest),
            ));
        }
        let request = Envelope::json(&json!({
            "operation":"wait_agent","arguments":{"nested":{"value":42}}
        }))
        .unwrap()
        .value::<HostInvocation>()
        .unwrap();
        assert_eq!(request.operation, HostOperation::WaitAgent);
        assert_eq!(request.arguments["nested"]["value"], 42);
    }
}
