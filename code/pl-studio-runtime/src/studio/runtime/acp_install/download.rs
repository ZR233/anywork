//! 分发包下载：复用 `downlowd` 的续传、`.part`/sidecar 与文件关闭责任。
//!
//! 取消与失败都通过回调让库自己收束，然后 `await send()` 完成——绝不以丢弃 future 或 join handle
//! 冒充"文件已关闭"。进度按约 250ms 合并发布；重试次数用累计 `total_tries`，因为库的连续
//! `retries` 会在有进展后归零（见 design/28 §28.6）。

use std::path::Path;
use std::sync::{Arc, Mutex, PoisonError};
use std::time::{Duration, Instant};

use pl_protocol::studio::{
    AcpInstallFailure, AcpInstallFailureCode, AcpInstallProgress, AcpInstallStage,
};
use tokio_util::sync::CancellationToken;

use super::mapping::failure;

/// 下载总预算。
pub(super) const DOWNLOAD_BUDGET: Duration = Duration::from_secs(60 * 60);
/// 允许的自动重试累计次数。
const MAX_AUTO_RETRIES: u64 = 3;
/// 进度合并间隔。
const PROGRESS_INTERVAL: Duration = Duration::from_millis(250);
/// 单个分发包上限。
pub(super) const MAX_ARCHIVE_BYTES: u64 = 1024 * 1024 * 1024;

/// 进度回调：`(进度, 累计自动重试次数)`。
pub(super) type ProgressSink = Arc<dyn Fn(AcpInstallProgress, u32) + Send + Sync>;
/// 重试前"确认/重建缺失 sidecar"的产品回调（路径与权限检查在调用方，本模块不复制边界）。
pub(super) type SidecarEnsure = Arc<dyn Fn() -> Result<(), AcpInstallFailure> + Send + Sync>;

#[derive(Default)]
struct Throttle {
    last_emit: Option<Instant>,
    sample: Option<(u64, Instant)>,
    total: Option<u64>,
    retries: u32,
}

/// 下载结果：对端公布的总量（可能未知）。本地长度已由进度与文件元数据表达。
pub(super) struct Downloaded {
    pub total: Option<u64>,
}

pub(super) async fn download(
    client: &downlowd::Client,
    url: &str,
    destination: &Path,
    sink: ProgressSink,
    ensure_sidecar: SidecarEnsure,
    cancellation: &CancellationToken,
) -> Result<Downloaded, AcpInstallFailure> {
    let stage = AcpInstallStage::Download;
    if let Some(parent) = destination.parent() {
        tokio::fs::create_dir_all(parent)
            .await
            .map_err(|_| failure(AcpInstallFailureCode::Io, stage, true))?;
    }
    let started = Instant::now();
    let throttle = Arc::new(Mutex::new(Throttle::default()));
    let (violation_sender, mut violations) = tokio::sync::mpsc::channel(1);

    let progress_throttle = Arc::clone(&throttle);
    let progress_sender = violation_sender.clone();
    let progress_sink = Arc::clone(&sink);
    let progress_cancel = cancellation.clone();
    let on_progress = move |state: &mut downlowd::ProgressHandle| {
        let bytes = state.bytes();
        let total = state.remote_length();
        let violation = if bytes > MAX_ARCHIVE_BYTES || total.is_some_and(|t| t > MAX_ARCHIVE_BYTES)
        {
            Some(AcpInstallFailureCode::TooLarge)
        } else if started.elapsed() >= DOWNLOAD_BUDGET {
            Some(AcpInstallFailureCode::Timeout)
        } else {
            None
        };
        if let Some(code) = violation {
            let _ = progress_sender.try_send(code);
            state.cancel();
            return;
        }
        if progress_cancel.is_cancelled() {
            state.cancel();
            return;
        }
        let report = {
            let mut guard = progress_throttle
                .lock()
                .unwrap_or_else(PoisonError::into_inner);
            guard.total = total;
            let complete = total.is_some_and(|total| bytes >= total);
            let due = guard
                .last_emit
                .is_none_or(|last| last.elapsed() >= PROGRESS_INTERVAL);
            if !due && !complete {
                None
            } else {
                let speed = guard.sample.map(|(sample_bytes, sample_at)| {
                    let span = sample_at.elapsed().as_millis().max(1) as u64;
                    bytes.saturating_sub(sample_bytes).saturating_mul(1000) / span
                });
                let retries = guard.retries;
                guard.sample = Some((bytes, Instant::now()));
                guard.last_emit = Some(Instant::now());
                Some((
                    AcpInstallProgress {
                        completed_bytes: bytes,
                        total_bytes: total,
                        bytes_per_second: speed,
                    },
                    retries,
                ))
            }
        };
        if let Some((progress, retries)) = report {
            progress_sink(progress, retries);
        }
    };

    let retry_throttle = Arc::clone(&throttle);
    let retry_sender = violation_sender.clone();
    let retry_ensure = Arc::clone(&ensure_sidecar);
    let retry_sink = Arc::clone(&sink);
    let retry_cancel = cancellation.clone();
    let on_retry = move |retry: &mut downlowd::RetryHandle| {
        let total_tries = retry.total_tries();
        let (retries, local, total) = {
            let mut guard = retry_throttle
                .lock()
                .unwrap_or_else(PoisonError::into_inner);
            guard.retries = total_tries.saturating_sub(1).min(u32::MAX as u64) as u32;
            let local = guard.sample.map(|(bytes, _)| bytes).unwrap_or(0);
            // 重启传输后旧样本不再代表同一段字节流：清空采样，等新 attempt 形成有效样本。
            guard.sample = None;
            guard.last_emit = None;
            (guard.retries, local, guard.total)
        };
        if retry_cancel.is_cancelled() {
            retry.cancel();
            return;
        }
        if started.elapsed() >= DOWNLOAD_BUDGET {
            let _ = retry_sender.try_send(AcpInstallFailureCode::Timeout);
            retry.cancel();
            return;
        }
        if total_tries > MAX_AUTO_RETRIES {
            let _ = retry_sender.try_send(AcpInstallFailureCode::Network);
            retry.cancel();
            return;
        }
        // `downlowd` 在 FileChanged 分支会先 truncate part、再 `reset` 删除 sidecar，然后才调用
        // 本回调；这里在放行下一次 attempt 之前确认/重建 sidecar（create_new 0600，路径与权限检查
        // 复用产品边界）。失败则按 typed Io 终止本次下载，await 库返回后不留宽权限文件。
        if retry_ensure().is_err() {
            let _ = retry_sender.try_send(AcpInstallFailureCode::Io);
            retry.cancel();
            return;
        }
        retry.set_delay(retry.delay().min(Duration::from_secs(2)));
        retry_sink(
            AcpInstallProgress {
                completed_bytes: local,
                total_bytes: total,
                bytes_per_second: None,
            },
            retries,
        );
    };

    // 库负责在取消/失败/成功后关闭文件；这里必须 await 完整返回。
    let result = client
        .get(url)
        .destination(destination)
        .on_progress(on_progress)
        .on_retry(on_retry)
        .send()
        .await;

    if let Ok(code) = violations.try_recv() {
        return Err(failure(code, stage, retryable(code)));
    }
    if cancellation.is_cancelled() {
        return Err(failure(AcpInstallFailureCode::Cancelled, stage, true));
    }
    // 成熟库已给出 typed cause：来源政策/重定向上限拒绝不是可重试网络故障。这里只按枚举变体分类，
    // 不解析 `reason`/`cause`/URL，也不额外发起预检请求。
    result.map_err(|error| match error {
        downlowd::Error::BadRedirect { .. } => {
            failure(AcpInstallFailureCode::SourceRejected, stage, false)
        }
        // `downlowd::Error` 是 `#[non_exhaustive]`：其余（含将来新增变体）保持当前
        // `Network`/可重试语义，不静默扩大"来源拒绝"的范围。
        _ => failure(AcpInstallFailureCode::Network, stage, true),
    })?;

    let metadata = tokio::fs::metadata(destination)
        .await
        .map_err(|_| failure(AcpInstallFailureCode::Io, stage, true))?;
    if metadata.len() == 0 {
        return Err(failure(AcpInstallFailureCode::Network, stage, true));
    }
    if metadata.len() > MAX_ARCHIVE_BYTES {
        return Err(failure(AcpInstallFailureCode::TooLarge, stage, false));
    }
    let file = tokio::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .open(destination)
        .await
        .map_err(|_| failure(AcpInstallFailureCode::Io, stage, true))?;
    file.sync_all()
        .await
        .map_err(|_| failure(AcpInstallFailureCode::Io, stage, true))?;
    let (total, retries) = {
        let guard = throttle.lock().unwrap_or_else(PoisonError::into_inner);
        (guard.total, guard.retries)
    };
    sink(
        AcpInstallProgress {
            completed_bytes: metadata.len(),
            total_bytes: total,
            bytes_per_second: None,
        },
        retries,
    );
    Ok(Downloaded { total })
}

fn retryable(code: AcpInstallFailureCode) -> bool {
    matches!(
        code,
        AcpInstallFailureCode::Network | AcpInstallFailureCode::Timeout
    )
}
