//! Enforce the product receive budget before the upstream SSE decoder buffers
//! an event. Line framing, UTF-8 and field semantics belong to sse-stream.
use futures::{Stream, TryStreamExt};
use pl_protocol::{PureError, Result};

pub(super) fn bounded<B>(
    stream: impl Stream<Item = Result<B>> + Send + 'static,
) -> impl Stream<Item = Result<B>> + Send
where
    B: AsRef<[u8]> + Send + 'static,
{
    let mut event_bytes = 0usize;
    let mut line_bytes = 0usize;
    let mut skip_lf = false;
    stream
        .map_ok(move |chunk| {
            // This adapter only counts bytes; it never copies or decodes input.
            for &byte in chunk.as_ref() {
                if skip_lf {
                    skip_lf = false;
                    if byte == b'\n' {
                        continue;
                    }
                }
                if matches!(byte, b'\r' | b'\n') {
                    if line_bytes == 0 {
                        event_bytes = 0;
                        skip_lf = byte == b'\r';
                        continue;
                    }
                    line_bytes = 0;
                    skip_lf = byte == b'\r';
                } else {
                    line_bytes = line_bytes.saturating_add(1);
                }
                event_bytes = event_bytes.saturating_add(1);
                if event_bytes > 64 * 1024 * 1024 {
                    return Err(PureError::Protocol(
                        "SSE event exceeds the 64 MiB receive limit".into(),
                    ));
                }
            }
            Ok(chunk)
        })
        .and_then(futures::future::ready)
}
