//! 认证命令的阶段预算、入站字节预算与流层故障观察。
//!
//! 登录阶段不设置墙钟期限；关闭预算由宿主提供。这里仅保留额度回合与字节资源限制。

use std::io;
use std::pin::Pin;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::task::{Context, Poll};
use std::time::Duration;

use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};

/// 固定 `/usage` 回合预算；只覆盖 prompt 请求及报告收集，不限制登录流程。
pub(super) const USAGE_QUERY_BUDGET: Duration = Duration::from_secs(60);
/// 单次认证命令允许消费的入站字节上限。
pub(super) const INPUT_BYTE_BUDGET: u64 = 8 * 1024 * 1024;
/// 固定 `/usage` 报告中允许保留的 agent text 总量。
pub(super) const USAGE_REPORT_BYTE_BUDGET: usize = 256 * 1024;

/// 流层观察句柄：入站预算耗尽与真实读/写失败。
///
/// 三个标志互相独立，只用于失败分类，不发布其他数据，因此宽松顺序即可。
#[derive(Clone, Default)]
pub(super) struct StreamGuard(Arc<StreamFaults>);

#[derive(Default)]
struct StreamFaults {
    budget_exhausted: AtomicBool,
    read_failed: AtomicBool,
    write_failed: AtomicBool,
}

impl StreamGuard {
    pub(super) fn new() -> Self {
        Self::default()
    }

    /// 入站字节预算是否已经耗尽。
    pub(super) fn budget_exhausted(&self) -> bool {
        self.0.budget_exhausted.load(Ordering::Relaxed)
    }

    /// 是否已有真实的读或写失败。
    ///
    /// 用于把连接级失败归类为 [`super::AuthFailureKind::Transport`]，而不是靠解析错误文案。
    pub(super) fn io_failed(&self) -> bool {
        self.0.read_failed.load(Ordering::Relaxed) || self.0.write_failed.load(Ordering::Relaxed)
    }

    fn record_budget_exhausted(&self) {
        self.0.budget_exhausted.store(true, Ordering::Relaxed);
    }

    fn record_read_failure(&self) {
        self.0.read_failed.store(true, Ordering::Relaxed);
    }

    fn record_write_failure(&self) {
        self.0.write_failed.store(true, Ordering::Relaxed);
    }
}

/// 有界入站读取器：越过预算后返回 IO 错误，由协议层收束连接。
///
/// 它只约束字节总量并记录真实读失败，仍然把解析与分帧完全交给官方 SDK。
pub(super) struct BudgetedReader<R> {
    inner: R,
    remaining: u64,
    guard: StreamGuard,
}

impl<R> BudgetedReader<R> {
    pub(super) fn new(inner: R, remaining: u64, guard: StreamGuard) -> Self {
        Self {
            inner,
            remaining,
            guard,
        }
    }
}

impl<R: AsyncRead + Unpin> AsyncRead for BudgetedReader<R> {
    fn poll_read(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        let this = self.get_mut();
        let before = buf.filled().len();
        let poll = Pin::new(&mut this.inner).poll_read(cx, buf);
        match &poll {
            Poll::Ready(Ok(())) => {
                let consumed = (buf.filled().len() - before) as u64;
                if consumed > this.remaining {
                    this.remaining = 0;
                    this.guard.record_budget_exhausted();
                    return Poll::Ready(Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        "ACP input exceeded the configured byte budget",
                    )));
                }
                this.remaining -= consumed;
            }
            Poll::Ready(Err(_)) => this.guard.record_read_failure(),
            Poll::Pending => {}
        }
        poll
    }
}

/// 记录真实写/flush/shutdown 失败的写端适配器。
///
/// 它只是把故障身份带给上层分类，不改变字节流语义。
pub(super) struct GuardedWriter<W> {
    inner: W,
    guard: StreamGuard,
}

impl<W> GuardedWriter<W> {
    pub(super) fn new(inner: W, guard: StreamGuard) -> Self {
        Self { inner, guard }
    }
}

impl<W: AsyncWrite + Unpin> AsyncWrite for GuardedWriter<W> {
    fn poll_write(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<io::Result<usize>> {
        let this = self.get_mut();
        let poll = Pin::new(&mut this.inner).poll_write(cx, buf);
        if let Poll::Ready(Err(_)) = &poll {
            this.guard.record_write_failure();
        }
        poll
    }

    fn poll_flush(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        let this = self.get_mut();
        let poll = Pin::new(&mut this.inner).poll_flush(cx);
        if let Poll::Ready(Err(_)) = &poll {
            this.guard.record_write_failure();
        }
        poll
    }

    fn poll_shutdown(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        let this = self.get_mut();
        let poll = Pin::new(&mut this.inner).poll_shutdown(cx);
        if let Poll::Ready(Err(_)) = &poll {
            this.guard.record_write_failure();
        }
        poll
    }
}
