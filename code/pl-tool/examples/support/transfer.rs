//! 观察入口共享的流式验收工具。
//!
//! 这里只有验收侧的确定性造块、增量哈希与准入闸门；不复制被测的生产传输、文件或进程实现。
//! 所有工具都使用固定内存：生成器按需产块，sink 只累计哈希与字节数。
#![allow(dead_code)]

use std::future::Future;
use std::io;
use std::pin::Pin;
use std::sync::Arc;
use std::task::{Context, Poll};

use sha2::{Digest, Sha256};
use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};
use tokio::sync::{AcquireError, OwnedSemaphorePermit, Semaphore, mpsc};

/// 确定性字节流：按块生成并增量哈希，不构造整文件缓冲。
pub struct PatternReader {
    remaining: u64,
    state: u64,
    hasher: Sha256,
}

impl PatternReader {
    pub fn new(total_len: u64) -> Self {
        Self {
            remaining: total_len,
            state: 0x9e37_79b9_7f4a_7c15,
            hasher: Sha256::new(),
        }
    }

    /// 已生成内容的十六进制摘要。
    pub fn finish(self) -> String {
        hex::encode(self.hasher.finalize())
    }
}

impl AsyncRead for PatternReader {
    fn poll_read(
        mut self: Pin<&mut Self>,
        _context: &mut Context<'_>,
        buffer: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        let wanted = buffer.remaining().min(self.remaining as usize);
        let start = buffer.filled().len();
        {
            let target = buffer.initialize_unfilled_to(start + wanted);
            for slot in target.iter_mut() {
                self.state ^= self.state << 13;
                self.state ^= self.state >> 7;
                self.state ^= self.state << 17;
                *slot = self.state as u8;
            }
        }
        buffer.advance(wanted);
        self.hasher.update(&buffer.filled()[start..start + wanted]);
        self.remaining -= wanted as u64;
        Poll::Ready(Ok(()))
    }
}

/// 增量哈希 sink：下载校验使用固定内存。
pub struct HashingWriter {
    bytes: u64,
    hasher: Sha256,
}

impl HashingWriter {
    pub fn new() -> Self {
        Self {
            bytes: 0,
            hasher: Sha256::new(),
        }
    }

    pub fn bytes(&self) -> u64 {
        self.bytes
    }

    /// 已接收内容的十六进制摘要。
    pub fn finish(self) -> String {
        hex::encode(self.hasher.finalize())
    }
}

impl Default for HashingWriter {
    fn default() -> Self {
        Self::new()
    }
}

impl AsyncWrite for HashingWriter {
    fn poll_write(
        mut self: Pin<&mut Self>,
        _context: &mut Context<'_>,
        buffer: &[u8],
    ) -> Poll<io::Result<usize>> {
        self.hasher.update(buffer);
        self.bytes += buffer.len() as u64;
        Poll::Ready(Ok(buffer.len()))
    }

    fn poll_flush(self: Pin<&mut Self>, _context: &mut Context<'_>) -> Poll<io::Result<()>> {
        Poll::Ready(Ok(()))
    }

    fn poll_shutdown(self: Pin<&mut Self>, _context: &mut Context<'_>) -> Poll<io::Result<()>> {
        Poll::Ready(Ok(()))
    }
}

/// 等待准入的 acquire future：多等待者语义由 `Semaphore` 提供，这里只保存进行中的一次等待。
type AcquireFuture =
    Pin<Box<dyn Future<Output = Result<OwnedSemaphorePermit, AcquireError>> + Send>>;

/// 上传准入闸门。
///
/// reader 第一次被 poll 时报告“该操作已被接受并进入数据阶段”，随后等待放行。
/// 多等待者语义交给 Tokio `Semaphore`（成熟的多等待者原语）：闸门初始没有 permit，
/// [`UploadGate::release`] 一次性补足与 reader 数相同的 permit，所有已等待和之后才开始
/// 等待的 reader 都会前进；不存在单个 waker 覆盖、注册与放行竞态或自研唤醒逻辑。
#[derive(Clone)]
pub struct UploadGate {
    semaphore: Arc<Semaphore>,
    entered: mpsc::UnboundedSender<()>,
    capacity: usize,
}

impl UploadGate {
    /// `capacity` 必须等于本次将要创建的 reader 数；`release` 补齐同数量的 permit。
    pub fn new(capacity: usize) -> (Self, mpsc::UnboundedReceiver<()>) {
        let (entered, receiver) = mpsc::unbounded_channel();
        (
            Self {
                semaphore: Arc::new(Semaphore::new(0)),
                entered,
                capacity,
            },
            receiver,
        )
    }

    /// 放行所有已进入和之后进入的 reader。
    pub fn release(&self) {
        self.semaphore.add_permits(self.capacity);
    }

    /// 声明 `total_len` 字节的受控 reader；放行前不会提供任何字节。
    pub fn reader(&self, total_len: u64) -> GatedReader {
        GatedReader {
            semaphore: Arc::clone(&self.semaphore),
            entered: self.entered.clone(),
            wait: None,
            ready: false,
            reported: false,
            remaining: total_len,
        }
    }
}

pub struct GatedReader {
    semaphore: Arc<Semaphore>,
    entered: mpsc::UnboundedSender<()>,
    wait: Option<AcquireFuture>,
    ready: bool,
    reported: bool,
    remaining: u64,
}

impl AsyncRead for GatedReader {
    fn poll_read(
        mut self: Pin<&mut Self>,
        context: &mut Context<'_>,
        buffer: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        if !self.reported {
            self.reported = true;
            let _ = self.entered.send(());
        }
        if !self.ready {
            if self.wait.is_none() {
                let wait: Pin<
                    Box<dyn Future<Output = Result<OwnedSemaphorePermit, AcquireError>> + Send>,
                > = Box::pin(Arc::clone(&self.semaphore).acquire_owned());
                self.wait = Some(wait);
            }
            let polled = {
                // 内部不变量：上面刚填过 Some。违反时按 I/O 错误报告，而不是 panic。
                let Some(wait) = self.wait.as_mut() else {
                    return Poll::Ready(Err(io::Error::other(
                        "upload gate acquire future is missing",
                    )));
                };
                wait.as_mut().poll(context)
            };
            match polled {
                Poll::Pending => return Poll::Pending,
                // 闸门被关闭时按已放行处理，由具体场景的 deadline 报告异常。
                Poll::Ready(_) => {
                    self.wait = None;
                    self.ready = true;
                }
            }
        }
        if self.remaining == 0 {
            return Poll::Ready(Ok(()));
        }
        let start = buffer.filled().len();
        let count = buffer.remaining().min(self.remaining as usize);
        {
            let target = buffer.initialize_unfilled_to(start + count);
            target.fill(b'g');
        }
        buffer.advance(count);
        self.remaining -= count as u64;
        Poll::Ready(Ok(()))
    }
}
