//! Bounded record framing shared by both peers.
//!
//! A record is exactly two length-delimited frames: a JSON header carrying the typed
//! message and the declared body length, followed by the raw body bytes (the second
//! frame exists even when the body is empty). Each frame is limited to
//! [`MAX_RECORD_BYTES`]; the limit applies to one record, never to the total an
//! operation may transfer.

use std::fmt;

use bytes::Bytes;
use futures::StreamExt;
use pl_protocol::remote::{RemoteEvent, RemoteMessage, RemoteRecordHeader};
use tokio::io::{AsyncRead, AsyncWrite};
use tokio_util::codec::{FramedRead, FramedWrite, LengthDelimitedCodec};

use crate::remote_transport::MAX_RECORD_BYTES;
use crate::remote_transport::error::TransportError;

/// One framed record: typed header plus raw body.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RemoteRecord {
    /// Typed message of this record.
    pub message: RemoteMessage,
    /// Raw body bytes; empty for messages that carry no payload.
    pub body: Bytes,
}

/// Reads records from one operation stream.
///
/// A clean end of stream on a record boundary yields `Ok(None)`; whether the operation
/// actually reached its business terminal record is the caller's concern.
///
/// The reader also defends itself against misuse: it is marked invalid *before* the first
/// I/O that may suspend in the middle of a record, so a cancelled read leaves it failing
/// with [`TransportError::Cancelled`] and later calls never continue a half record. A real
/// I/O or decoding failure replaces that marker with its own typed failure. Only a complete
/// record — or a clean end of records — clears it again.
pub struct RecordReader<R> {
    frames: FramedRead<R, LengthDelimitedCodec>,
    /// Set while a half record may exist; only a whole record or clean EOF clears it.
    fault: Option<TransportError>,
}

impl<R> RecordReader<R> {
    /// Wraps the read side of one stream.
    pub fn new(reader: R) -> Self {
        Self {
            frames: FramedRead::new(reader, record_codec()),
            fault: None,
        }
    }
}

impl<R> RecordReader<R>
where
    R: AsyncRead + Unpin,
{
    /// Reads the next record.
    ///
    /// # Errors
    ///
    /// Returns [`TransportError::Encoding`] when the header is not valid JSON for the
    /// typed protocol, [`TransportError::InvalidRecord`] for a record whose declared body
    /// and actual body disagree or whose message cannot carry a body, and
    /// [`TransportError::Io`] for every framing or channel failure, keeping the real source
    /// (including a frame above the record budget). Cancelling this future in the middle of
    /// a record leaves this reader permanently invalid with [`TransportError::Cancelled`];
    /// the caller must discard the whole operation stream instead of retrying.
    pub async fn read(&mut self) -> Result<Option<RemoteRecord>, TransportError> {
        if let Some(fault) = &self.fault {
            return Err(fault.clone());
        }
        // The next I/O may suspend half way through a record. Mark the reader first: if this
        // future is dropped at any await, the half record can never be stitched together
        // with a later call, and later calls fail without touching the stream.
        self.fault = Some(TransportError::Cancelled);

        let next = self.frames.next().await;
        let header_bytes = match next {
            None => {
                // A clean end on a record boundary leaves no half record behind.
                self.fault = None;
                return Ok(None);
            }
            Some(Ok(frame)) => frame,
            Some(Err(error)) => return Err(self.fail(TransportError::io(error))),
        };
        let header: RemoteRecordHeader = match serde_json::from_slice(&header_bytes) {
            Ok(header) => header,
            // The serde source is preserved: this is a JSON problem, not a framing one.
            Err(error) => return Err(self.fail(TransportError::encoding(error))),
        };

        let declared = header.body_len as usize;
        if declared > MAX_RECORD_BYTES {
            return Err(self.fail(TransportError::RecordTooLarge {
                limit: MAX_RECORD_BYTES,
                actual: declared,
            }));
        }
        if declared > 0 && !carries_body(&header.message) {
            return Err(self.fail(TransportError::invalid_record(format!(
                "message {header:?} must not carry a binary body"
            ))));
        }

        let next = self.frames.next().await;
        let body = match next {
            None => {
                return Err(self.fail(TransportError::invalid_record(
                    "record ended before its body frame".to_owned(),
                )));
            }
            Some(Ok(frame)) => frame,
            Some(Err(error)) => return Err(self.fail(TransportError::io(error))),
        };
        let carried = body.len();
        if carried != declared {
            return Err(self.fail(TransportError::invalid_record(format!(
                "record body declared {declared} bytes but carried {carried}"
            ))));
        }

        // The record is complete; the reader is usable again.
        self.fault = None;
        Ok(Some(RemoteRecord {
            message: header.message,
            body: body.freeze(),
        }))
    }

    fn fail(&mut self, error: TransportError) -> TransportError {
        self.fault = Some(error.clone());
        error
    }
}

impl<R> fmt::Debug for RecordReader<R> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("RecordReader")
            .field("faulted", &self.fault.is_some())
            .finish_non_exhaustive()
    }
}

/// Writes records to one operation stream.
///
/// Both frames of a record are encoded and validated before any byte is published, so a
/// locally oversized or unencodable record is reported as a typed error while the physical
/// connection, and every other stream, stays usable.
///
/// The writer also defends itself against misuse: it is marked invalid *before* the first
/// I/O that may leave a half-written record, so a cancelled or failed `send`/`finish` keeps
/// it failing with that real cause and later calls never continue a half record. A local
/// encoding or length rejection happens before any byte is published and never invalidates a
/// healthy writer.
pub struct RecordWriter<W> {
    frames: FramedWrite<W, LengthDelimitedCodec>,
    /// Set while a half record may exist; only a fully published record clears it.
    fault: Option<TransportError>,
}

impl<W> RecordWriter<W> {
    /// Wraps the write side of one stream.
    pub fn new(writer: W) -> Self {
        Self {
            frames: FramedWrite::new(writer, record_codec()),
            fault: None,
        }
    }
}

impl<W> RecordWriter<W>
where
    W: AsyncWrite + Unpin,
{
    /// Encodes and publishes one record.
    ///
    /// # Errors
    ///
    /// Returns [`TransportError::RecordTooLarge`] for a body or header above
    /// [`MAX_RECORD_BYTES`], [`TransportError::Encoding`] when the header cannot be
    /// serialized, [`TransportError::InvalidRecord`] when the body does not belong to
    /// this message, and [`TransportError::Io`] when the stream failed. Cancelling this
    /// future may leave half a record on the stream, so this writer then stays invalid with
    /// [`TransportError::Cancelled`] and the caller must discard the operation stream.
    pub async fn send(
        &mut self,
        message: &RemoteMessage,
        body: &[u8],
    ) -> Result<(), TransportError> {
        if let Some(fault) = &self.fault {
            return Err(fault.clone());
        }
        // Local rejections happen before a single byte is published and never invalidate a
        // healthy writer.
        if body.len() > MAX_RECORD_BYTES {
            return Err(TransportError::RecordTooLarge {
                limit: MAX_RECORD_BYTES,
                actual: body.len(),
            });
        }
        if !body.is_empty() && !carries_body(message) {
            return Err(TransportError::invalid_record(format!(
                "message {message:?} must not carry a binary body"
            )));
        }

        let header = RemoteRecordHeader {
            message: message.clone(),
            body_len: body.len() as u32,
        };
        let header = serde_json::to_vec(&header).map_err(TransportError::encoding)?;
        if header.len() > MAX_RECORD_BYTES {
            return Err(TransportError::RecordTooLarge {
                limit: MAX_RECORD_BYTES,
                actual: header.len(),
            });
        }

        // The first byte is about to be published: from here a suspension can leave half a
        // record behind, so the writer is invalid until this whole record is out.
        self.fault = Some(TransportError::Cancelled);
        // Both frames are complete in memory before the first byte reaches the stream. The
        // codec encodes both `Bytes` and `&[u8]`, so the sink item type is named explicitly.
        if let Err(error) =
            futures::SinkExt::<Bytes>::feed(&mut self.frames, Bytes::from(header)).await
        {
            return Err(self.fail(TransportError::io(error)));
        }
        if let Err(error) =
            futures::SinkExt::<Bytes>::feed(&mut self.frames, Bytes::copy_from_slice(body)).await
        {
            return Err(self.fail(TransportError::io(error)));
        }
        if let Err(error) = futures::SinkExt::<Bytes>::flush(&mut self.frames).await {
            return Err(self.fail(TransportError::io(error)));
        }
        self.fault = None;
        Ok(())
    }

    /// Flushes the stream and half-closes its send direction.
    ///
    /// The peer keeps the ability to answer on the same stream, and it observes a clean
    /// end of records rather than a reset.
    ///
    /// # Errors
    ///
    /// Returns [`TransportError::Io`] when flushing or closing the stream failed, and the
    /// writer's stored failure when a previous record already left it invalid.
    pub async fn finish(&mut self) -> Result<(), TransportError> {
        // A half-written record must never be forgotten, even by a failed or cancelled
        // `finish`.
        if let Some(fault) = &self.fault {
            return Err(fault.clone());
        }
        self.fault = Some(TransportError::Cancelled);
        if let Err(error) = futures::SinkExt::<Bytes>::close(&mut self.frames).await {
            return Err(self.fail(TransportError::io(error)));
        }
        self.fault = None;
        Ok(())
    }

    /// Stores the real failure and keeps the writer invalid.
    fn fail(&mut self, error: TransportError) -> TransportError {
        self.fault = Some(error.clone());
        error
    }
}

impl<W> fmt::Debug for RecordWriter<W> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("RecordWriter")
            .field("faulted", &self.fault.is_some())
            .finish_non_exhaustive()
    }
}

/// Messages whose record may carry raw bytes.
fn carries_body(message: &RemoteMessage) -> bool {
    matches!(
        message,
        RemoteMessage::Data { .. }
            | RemoteMessage::Stdin
            | RemoteMessage::Event(RemoteEvent::ProcessOutput(_))
    )
}

fn record_codec() -> LengthDelimitedCodec {
    let mut builder = LengthDelimitedCodec::builder();
    builder.length_field_length(4);
    builder.max_frame_length(MAX_RECORD_BYTES);
    builder.new_codec()
}
