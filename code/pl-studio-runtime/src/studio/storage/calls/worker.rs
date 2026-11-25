use super::*;

/// writer supervisor：worker panic 后重启；在途事实由等待方重试，不会被静默丢弃。
pub(super) async fn supervise_writer(shared: Arc<CallsWriter>) {
    loop {
        let worker = tokio::spawn(run_writer(shared.clone()));
        let Err(error) = worker.await else {
            return;
        };
        let message = format!("call writer terminated unexpectedly: {error}");
        if shared.in_flight_bytes.swap(0, Ordering::AcqRel) > 0 {
            record_statistics_gap(&shared, message);
        } else {
            record_last_error(&shared, message);
        }
        if shared.stopping.load(Ordering::Acquire) {
            return;
        }
        tokio::time::sleep(Duration::from_secs(1)).await;
        if shared.stopping.load(Ordering::Acquire) {
            return;
        }
    }
}

/// 唯一的调用库写入循环：取批、应用、重试、推进水位，并周期性清理日志。
async fn run_writer(shared: Arc<CallsWriter>) {
    let mut retries = 0usize;
    // 周期清理以绝对截止时间为准，即使队列一直非空（写入/重试未停）也会到点清理，
    // 避免文档承诺的“每 15 分钟清理”被持续压力饿死。
    let mut next_cleanup = tokio::time::Instant::now() + LOG_CLEANUP_INTERVAL;
    loop {
        if tokio::time::Instant::now() >= next_cleanup {
            next_cleanup = tokio::time::Instant::now() + LOG_CLEANUP_INTERVAL;
            let mut log = shared.log.lock().await;
            if let Err(error) = maintenance(&shared.db, &mut log).await {
                record_last_error(&shared, format!("call log cleanup failed: {error}"));
            }
        }
        let stopping = shared.stopping.load(Ordering::Acquire);
        let pressure = queue_pressure(&shared);
        if pressure.mutations == 0 {
            if stopping {
                return;
            }
            tokio::select! {
                _ = shared.work_notify.notified() => continue,
                // 到点后唤醒执行顶部截止时间检查，而不是在空闲分支里重复清理逻辑。
                _ = tokio::time::sleep_until(next_cleanup) => continue,
            }
        }
        if pressure.bytes >= MAX_QUEUE_BYTES {
            tracing::warn!(
                mutations = pressure.mutations,
                bytes = pressure.bytes,
                oldest_age_ms = pressure
                    .oldest_accepted_at
                    .map_or(0, |oldest| oldest.elapsed().as_millis() as u64),
                "call writer queue is under pressure"
            );
        }
        let mut pending: VecDeque<QueuedCallMutation> = drain_batch(&shared).into();
        if pending.is_empty() {
            continue;
        }
        let batch_bytes = pending.iter().fold(0u64, |total, entry| {
            total.saturating_add(entry.bytes as u64)
        });
        shared.in_flight_bytes.store(batch_bytes, Ordering::Release);
        let deferred = match apply_batch(&shared, &pending).await {
            Ok((completed, failures, deferred)) => {
                if completed > 0 {
                    retries = 0;
                    clear_last_error(&shared);
                    for failure in failures {
                        fail_mutation(&shared, &failure);
                    }
                    let ticket = pending[completed - 1].ticket;
                    pending.drain(..completed);
                    // No receipt may outrun the commit of the outer transaction.
                    advance_processed(&shared, ticket);
                }
                deferred
            }
            Err(error) => Some(classify_failure(error)),
        };
        // 本批已处理完（含退回队首的 deferred 条目），不再有 in-flight 字节。
        shared.in_flight_bytes.store(0, Ordering::Release);
        let Some(failure) = deferred else {
            continue;
        };
        record_last_error(&shared, failure.message.clone());
        if !failure.retryable || shared.stopping.load(Ordering::Acquire) {
            fail_mutation(&shared, &failure.message);
            if let Some(last) = pending.back() {
                advance_processed(&shared, last.ticket);
            }
            continue;
        }
        requeue(&shared, pending);
        retries = retries.saturating_add(1);
        if shared.stopping.load(Ordering::Acquire) {
            tokio::task::yield_now().await;
            continue;
        }
        let backoff = if retries <= FAST_RETRIES {
            RETRY_BACKOFF * u32::try_from(retries).unwrap_or(u32::MAX)
        } else {
            let exponent = u32::try_from(retries.saturating_sub(FAST_RETRIES + 1))
                .unwrap_or(u32::MAX)
                .min(5);
            Duration::from_secs(1u64 << exponent).min(MAX_RETRY_BACKOFF)
        };
        tracing::warn!(
            attempt = retries,
            error = failure.message,
            "call writer retrying after a transient failure"
        );
        wait_for_retry(&shared, backoff).await;
    }
}

/// 清理日志并回收索引；周期任务与启动路径共用。
pub(super) async fn maintenance(db: &DatabaseConnection, log: &mut CallLog) -> Result<()> {
    log.repair_pending_index(db).await?;
    let outcome = log.cleanup(crate::studio::unix_seconds()).await;
    if !outcome.removed.is_empty() {
        let tx = db.begin().await?;
        prune_index(&tx, &outcome.removed).await?;
        tx.commit().await?;
    }
    if let Some(failure) = outcome.failure {
        return Err(failure).context("call log cleanup incomplete");
    }
    let root_dir = log.root_dir();
    schema::retry_pending_cleanup(db, &root_dir).await?;
    Ok(())
}

/// One disk commit per bounded batch. Each mutation uses a savepoint, so a bad statistics fact
/// cannot poison the remaining valid facts; a transient failure leaves that suffix queued.
async fn wait_for_retry(shared: &CallsWriter, backoff: Duration) {
    tokio::select! {
        _ = shared.retry_notify.notified() => {}
        _ = tokio::time::sleep(backoff) => {}
    }
}

/// 一次受理得到结论（提交或显式拒绝）后推进处理 ticket，不表示成功物化。
fn advance_processed(shared: &CallsWriter, ticket: u64) {
    let current = *shared.processed_ticket.borrow();
    if ticket > current {
        shared.processed_ticket.send_replace(ticket);
    }
    shared.materials.send_if_modified(|progress| {
        if ticket <= progress.processed_ticket {
            return false;
        }
        progress.processed_ticket = ticket;
        true
    });
}

pub(super) fn publish_status(shared: &CallsWriter) {
    let error = shared
        .last_error
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .clone();
    let gap = shared.statistics_gap.load(Ordering::Acquire);
    shared.materials.send_if_modified(|progress| {
        if progress.last_error == error && progress.statistics_gap == gap {
            return false;
        }
        progress.last_error = error;
        progress.statistics_gap = gap;
        progress.versions.status += 1;
        true
    });
}

pub(super) fn fail_mutation(shared: &CallsWriter, message: &str) {
    tracing::error!(error = message, "call writer rejected a call fact");
    record_statistics_gap(shared, message.to_owned());
}

pub(super) fn record_statistics_gap(shared: &CallsWriter, message: String) {
    shared.statistics_gap.store(true, Ordering::Release);
    record_last_error(shared, message);
}

/// An operation error is not evidence that an accounting fact was discarded.
/// Retained retry work and retryable maintenance errors must not latch a gap.
fn record_last_error(shared: &CallsWriter, message: String) {
    tracing::error!(error = message, "call writer is degraded");
    *shared
        .last_error
        .lock()
        .unwrap_or_else(|error| error.into_inner()) = Some(message);
    publish_status(shared);
}

/// A durable write succeeded, so the previously recorded degradation no longer describes the
/// writer. The error is retained until this point instead of clearing on admission or retry.
fn clear_last_error(shared: &CallsWriter) {
    *shared
        .last_error
        .lock()
        .unwrap_or_else(|error| error.into_inner()) = None;
    publish_status(shared);
}
