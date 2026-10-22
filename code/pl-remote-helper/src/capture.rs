//! Shared physical output framing. The host supplies all formatting and budget policy.
use std::io;
use tokio::io::{AsyncWrite, AsyncWriteExt};

pub fn chunk_cost(prefix: &[u8], body: &[u8], terminate_line: bool) -> u64 {
    prefix.len() as u64 + body.len() as u64 + u64::from(terminate_line && !body.ends_with(b"\n"))
}
pub async fn write_chunk<W: AsyncWrite + Unpin>(
    writer: &mut W,
    prefix: &[u8],
    body: &[u8],
    terminate_line: bool,
) -> io::Result<()> {
    writer.write_all(prefix).await?;
    writer.write_all(body).await?;
    if terminate_line && !body.ends_with(b"\n") {
        writer.write_all(b"\n").await?;
    }
    Ok(())
}
