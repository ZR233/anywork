use super::*;
use log::{FileSync, SegmentSync};

/// 不可重试的批量失败；保留消息用于错误上报与诊断。
#[derive(Debug)]
pub(super) struct BatchFailure {
    pub(super) message: String,
    pub(super) retryable: bool,
}

#[derive(Default)]
pub(super) struct MaterialChanges {
    performance: bool,
    costs: bool,
    status: bool,
}

pub(super) async fn apply_batch(
    shared: &CallsWriter,
    pending: &VecDeque<QueuedCallMutation>,
) -> Result<(usize, Vec<String>, Option<BatchFailure>)> {
    apply_batch_with_sync(shared, pending, FileSync).await
}

pub(super) async fn apply_batch_with_sync(
    shared: &CallsWriter,
    pending: &VecDeque<QueuedCallMutation>,
    sync: impl SegmentSync,
) -> Result<(usize, Vec<String>, Option<BatchFailure>)> {
    #[cfg(feature = "benchmarks")]
    let lock_started = std::time::Instant::now();
    let mut log = shared.log.lock().await;
    #[cfg(feature = "benchmarks")]
    shared
        .observation
        .write_lock_acquired(lock_started.elapsed());
    // Locator recovery is a prerequisite only for diagnostics, never for absolute costs.
    // Recovery commits independently before this batch; its pending segment responsibility
    // stays with the log on failure, while rejected diagnostics report the original error.
    let locator_error = if pending.iter().any(|entry| {
        matches!(
            &entry.mutation,
            CallMutation::Records(_) | CallMutation::Billing(_)
        )
    }) {
        log.repair_pending_index(&shared.db)
            .await
            .err()
            .map(|error| error.to_string())
    } else {
        None
    };
    let tx = shared.db.begin().await?;
    let mut completed = 0;
    let mut failures = Vec::new();
    let mut deferred = None;
    let mut changes = MaterialChanges::default();
    let mut summaries = BTreeMap::<&str, (usize, usize)>::new();
    let mut summary_identities = BTreeMap::<(&str, u64), &str>::new();
    let mut summary_conflicts = BTreeSet::new();
    for (index, entry) in pending.iter().enumerate() {
        if let CallMutation::Summary(summary) = &entry.mutation {
            if let Some(hash) =
                summary_identities.get(&(summary.thread_id.as_str(), summary.revision))
                && *hash != summary.hash
            {
                summary_conflicts.insert(index);
                continue;
            }
            summary_identities.insert((&summary.thread_id, summary.revision), &summary.hash);
            let previous = summaries.get(summary.thread_id.as_str()).copied();
            if previous.is_none_or(|(_, previous)| {
                let CallMutation::Summary(old) = &pending[previous].mutation else {
                    unreachable!()
                };
                summary.revision > old.revision
            }) {
                summaries.insert(
                    &summary.thread_id,
                    (previous.map_or(index, |(first, _)| first), index),
                );
            }
        }
    }
    for (index, entry) in pending.iter().enumerate() {
        let result = match &entry.mutation {
            CallMutation::Summary(summary) => {
                if summary_conflicts.contains(&index) {
                    Err(classify_failure(anyhow::anyhow!(
                        "conflicting call summary revision"
                    )))
                } else {
                    let (first, newest) = summaries[summary.thread_id.as_str()];
                    if first == index {
                        apply_live_mutation(shared, &mut log, &tx, &pending[newest].mutation).await
                    } else {
                        Ok(MaterialChanges::default())
                    }
                }
            }
            CallMutation::AcpPerformance(_) => {
                apply_live_mutation(shared, &mut log, &tx, &entry.mutation).await
            }
            CallMutation::Records(_) | CallMutation::Billing(_) => {
                if let Some(error) = &locator_error {
                    // Do not defer the batch suffix behind failed diagnostic recovery: it may
                    // contain reliable Summary projections. The next diagnostic batch retries
                    // the still-pending repair before consulting identities or appending bodies.
                    failures.push(error.clone());
                    completed += 1;
                    continue;
                }
                apply_live_mutation(shared, &mut log, &tx, &entry.mutation).await
            }
        };
        match result {
            Ok(change) => {
                changes.performance |= change.performance;
                changes.costs |= change.costs;
                changes.status |= change.status;
            }
            Err(failure) if failure.retryable => {
                deferred = Some(failure);
                break;
            }
            Err(failure) => {
                failures.push(failure.message);
            }
        }
        completed += 1;
    }
    // Includes complete orphan lines left by failed savepoints. No SQL success or receipt
    // can escape before every segment touched by this batch crosses its file barrier.
    if let Err(error) = log.sync_pending_with(sync).await {
        // Drop only queues the SQLx rollback. Join it before releasing the log lock
        // so the next batch cannot race the failed batch's still-held write lock.
        tx.rollback()
            .await
            .with_context(|| format!("{error}; call batch rollback failed"))?;
        return Err(error);
    }
    // Keep the final SQLite maintenance and commit adjacent, rather than parking its worker
    // behind log I/O after the last SQL statement. The file barrier still precedes all SQL success.
    if changes.performance {
        #[cfg(feature = "benchmarks")]
        shared
            .observation
            .increment(observation::Metric::PerformanceTrimSql);
        performance::trim(&tx).await?;
    }
    tx.commit().await?;
    #[cfg(feature = "benchmarks")]
    shared
        .observation
        .increment(observation::Metric::BatchCommit);
    shared.materials.send_if_modified(|progress| {
        if changes.performance {
            progress.versions.performance += 1;
        }
        if changes.costs {
            progress.versions.costs += 1;
        }
        if changes.status {
            progress.versions.status += 1;
        }
        changes.performance || changes.costs || changes.status
    });
    Ok((completed, failures, deferred))
}

async fn apply_live_mutation(
    shared: &CallsWriter,
    log: &mut CallLog,
    db: &DatabaseTransaction,
    mutation: &CallMutation,
) -> Result<MaterialChanges, BatchFailure> {
    let id = match mutation {
        CallMutation::Records(records) => records.first().map(|record| record.thread_id.as_str()),
        CallMutation::Billing(record) => Some(record.thread_id.as_str()),
        CallMutation::Summary(summary) => Some(summary.thread_id.as_str()),
        CallMutation::AcpPerformance(sample) => Some(sample.thread_id.as_str()),
    };
    if id.is_some_and(|id| {
        shared
            .deleted_threads
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .contains(id)
    }) {
        return Ok(MaterialChanges::default());
    }
    apply_mutation(log, db, mutation).await
}

async fn apply_mutation(
    log: &mut CallLog,
    db: &DatabaseTransaction,
    mutation: &CallMutation,
) -> Result<MaterialChanges, BatchFailure> {
    let tx = db
        .begin()
        .await
        .map_err(|error| classify_failure(error.into()))?;
    let result = match mutation {
        CallMutation::Records(records) => {
            let mut result = Ok(());
            for record in records {
                if let Err(error) = apply_attempt(&tx, log, record).await {
                    result = Err(error);
                    break;
                }
            }
            result.map(|()| MaterialChanges {
                status: true,
                ..Default::default()
            })
        }
        CallMutation::Billing(record) => {
            apply_billing(log, &tx, record)
                .await
                .map(|performance| MaterialChanges {
                    performance,
                    ..Default::default()
                })
        }
        CallMutation::AcpPerformance(sample) => {
            performance::record(&tx, sample)
                .await
                .map(|()| MaterialChanges {
                    performance: true,
                    ..Default::default()
                })
        }
        CallMutation::Summary(projection) => summary::replace(
            &tx,
            projection,
            &projection.hash,
            #[cfg(feature = "benchmarks")]
            Some(&log.observation),
        )
        .await
        .map(|costs| MaterialChanges {
            costs,
            ..Default::default()
        }),
    };
    match result {
        Ok(changes) => {
            tx.commit()
                .await
                .map_err(|error| classify_failure(error.into()))?;
            Ok(changes)
        }
        Err(error) => {
            tx.rollback().await.map_err(|rollback| {
                classify_failure(anyhow::anyhow!(
                    "{error}; savepoint rollback failed: {rollback}"
                ))
            })?;
            Err(classify_failure(error))
        }
    }
}

pub(super) fn classify_failure(error: anyhow::Error) -> BatchFailure {
    let message = error.to_string();
    BatchFailure {
        retryable: is_retryable_write(&message),
        message,
    }
}

/// attempt 记录按 revision 单调：更旧的修订不覆盖已索引的更新。
pub(super) async fn apply_attempt(
    db: &DatabaseTransaction,
    log: &mut CallLog,
    record: &PreparedRecord,
) -> Result<()> {
    let existing = db
        .query_one_raw(statement(
            "SELECT revision FROM call_log_index WHERE thread_id=? AND call_id=? AND kind=?",
            vec![
                record.thread_id.clone().into(),
                record.call_id.clone().into(),
                record.kind.clone().into(),
            ],
        ))
        .await?;
    if let Some(row) = existing {
        let stored: i64 = row.try_get("", "revision")?;
        if record.revision <= stored {
            return Ok(());
        }
    }
    let now = crate::studio::unix_seconds();
    append_record(db, log, record, now).await
}

/// 幂等写入一次计费/性能事实；同一身份不同正文明确失败。
pub(super) async fn apply_billing(
    log: &mut CallLog,
    db: &DatabaseTransaction,
    record: &PreparedRecord,
) -> Result<bool> {
    #[cfg(feature = "benchmarks")]
    log.observation
        .increment(observation::Metric::BillingIdentitySql);
    let existing = db
        .query_one_raw(statement(
            "SELECT content_hash FROM call_log_index WHERE thread_id=? AND call_id=? AND kind=?",
            vec![
                record.thread_id.clone().into(),
                record.call_id.clone().into(),
                record.kind.clone().into(),
            ],
        ))
        .await?;
    if let Some(row) = existing {
        let stored: Option<String> = row.try_get("", "content_hash")?;
        match stored {
            Some(stored) if stored == record.hash => return Ok(false),
            Some(_) => {
                bail!(
                    "model call {} conflicts with the durable call record",
                    record.call_id
                );
            }
            None => {}
        }
    }
    let now = crate::studio::unix_seconds();
    append_record(db, log, record, now).await?;
    if record.status == CallStatus::Committed.as_str()
        && let Some(sample) = performance::sample_from_prepared(record)
    {
        #[cfg(feature = "benchmarks")]
        log.observation
            .increment(observation::Metric::PerformanceWriteSql);
        performance::record(db, &sample).await?;
        return Ok(true);
    }
    Ok(false)
}

/// 追加一条记录到 JSONL 日志并在 SQLite 索引中登记位置；顺带回收被清理段的索引行。
pub(super) async fn append_record(
    db: &impl ConnectionTrait,
    log: &mut CallLog,
    record: &PreparedRecord,
    now: i64,
) -> Result<()> {
    if now.saturating_sub(record.recorded_at) >= log::LOG_RETENTION_SECONDS {
        return Ok(());
    }
    let outcome = log
        .append(event::record_day(record.recorded_at), now, &record.line)
        .await?;
    prune_index(db, &outcome.removed).await?;
    #[cfg(feature = "benchmarks")]
    log.observation
        .increment(observation::Metric::LogIndexWriteSql);
    index_record(db, record, &record.hash, &outcome.record, record.truncated).await
}

pub(super) async fn index_record(
    db: &impl ConnectionTrait,
    record: &CallLogRecord,
    content_hash: &str,
    location: &log::AppendedRecord,
    truncated: bool,
) -> Result<()> {
    index_locator(
        db,
        &event::CallLogLocator::from(record),
        content_hash,
        location,
        truncated,
    )
    .await
}

pub(super) async fn index_locator(
    db: &impl ConnectionTrait,
    record: &event::CallLogLocator,
    content_hash: &str,
    location: &log::AppendedRecord,
    truncated: bool,
) -> Result<()> {
    db.execute_raw(statement(
        "INSERT INTO call_log_index(
            thread_id,call_id,kind,revision,content_hash,segment,offset,length,truncated,recorded_at)
         VALUES(?,?,?,?,?,?,?,?,?,?)
         ON CONFLICT(thread_id,call_id,kind) DO UPDATE SET
            revision=MAX(excluded.revision,call_log_index.revision),
            content_hash=excluded.content_hash,
            segment=excluded.segment,
            offset=excluded.offset,
            length=excluded.length,
            truncated=excluded.truncated,
            recorded_at=excluded.recorded_at WHERE excluded.revision >= call_log_index.revision",
        vec![
            record.thread_id.clone().into(),
            record.call_id.clone().into(),
            record.kind.clone().into(),
            record.revision.into(),
            content_hash.into(),
            location.segment.clone().into(),
            integer(location.offset)?.into(),
            integer(location.length)?.into(),
            (truncated as i32).into(),
            record.recorded_at.into(),
        ],
    ))
    .await?;
    Ok(())
}

/// 删除被清理段的索引行。
pub(super) async fn prune_index(db: &impl ConnectionTrait, segments: &[String]) -> Result<()> {
    for segment in segments {
        db.execute_raw(statement(
            "DELETE FROM call_log_index WHERE segment=?",
            vec![segment.clone().into()],
        ))
        .await?;
    }
    Ok(())
}
