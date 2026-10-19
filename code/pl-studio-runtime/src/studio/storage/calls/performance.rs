//! 有界性能投影：最多保留最近 [`PERFORMANCE_SAMPLE_LIMIT`] 条成功调用样本。
//!
//! 样本自带展示所需字段，不依赖已删除的正文或旧的 `model_calls`；成员超出上限时按完成时间裁剪。

use super::*;

pub(crate) const PERFORMANCE_SAMPLE_LIMIT: usize = 3_000;

/// 一条成功调用样本；未测得的时延保持 `None`，绝不折叠成零时延。
#[derive(Debug, Clone)]
pub(super) struct PerformanceSample {
    pub(super) thread_id: String,
    pub(super) call_id: String,
    pub(super) completed_at: i64,
    pub(super) provider_instance_id: Option<String>,
    pub(super) provider_display_name: Option<String>,
    pub(super) configured_model: Option<String>,
    pub(super) sent_model: Option<String>,
    pub(super) reported_model: Option<String>,
    pub(super) reasoning_effort: Option<String>,
    pub(super) output_tokens: Option<i64>,
    pub(super) ttft_millis: Option<i64>,
    pub(super) decode_millis: Option<i64>,
    pub(super) response_millis: Option<i64>,
}

/// 从轻量日志记录构造性能样本。
pub(super) fn sample_from_record(record: &CallLogRecord) -> PerformanceSample {
    let usage = record.usage.as_ref();
    let timing = record.timing.as_ref();
    let throughput = record.throughput_sample();
    PerformanceSample {
        thread_id: record.thread_id.clone(),
        call_id: record.call_id.clone(),
        completed_at: record.recorded_at,
        provider_instance_id: record.provider_instance_id.clone(),
        provider_display_name: record.provider_display_name.clone(),
        configured_model: record.configured_model.clone(),
        sent_model: record.sent_model.clone(),
        reported_model: record.reported_model.clone(),
        reasoning_effort: record.reasoning_effort.clone(),
        output_tokens: usage
            .and_then(|usage| usage.output_tokens)
            .and_then(opt_i64),
        ttft_millis: timing
            .map(|timing| opt_i64(timing.ttft_millis))
            .unwrap_or(None),
        // This table is the bounded performance projection, not the raw call log. An invalid
        // pair contributes neither side to SQL aggregation; its raw timing remains in JSONL.
        decode_millis: throughput.and_then(|(_, timing)| opt_i64(timing.decode_millis)),
        response_millis: timing
            .map(|timing| opt_i64(timing.response_millis))
            .unwrap_or(None),
    }
}

/// 幂等写入一条性能样本；同身份以最新事实覆盖。
pub(super) async fn record(db: &impl ConnectionTrait, sample: &PerformanceSample) -> Result<()> {
    db.execute_raw(statement(
        "INSERT INTO performance_samples(
            thread_id,call_id,completed_at,provider_instance_id,provider_display_name,
            configured_model,sent_model,reported_model,reasoning_effort,output_tokens,
            ttft_millis,decode_millis,response_millis)
         VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
         ON CONFLICT(thread_id,call_id) DO UPDATE SET
            completed_at=excluded.completed_at,
            provider_instance_id=excluded.provider_instance_id,
            provider_display_name=excluded.provider_display_name,
            configured_model=excluded.configured_model,
            sent_model=excluded.sent_model,
            reported_model=excluded.reported_model,
            reasoning_effort=excluded.reasoning_effort,
            output_tokens=excluded.output_tokens,
            ttft_millis=excluded.ttft_millis,
            decode_millis=excluded.decode_millis,
            response_millis=excluded.response_millis",
        vec![
            sample.thread_id.clone().into(),
            sample.call_id.clone().into(),
            sample.completed_at.into(),
            sample.provider_instance_id.clone().into(),
            sample.provider_display_name.clone().into(),
            sample.configured_model.clone().into(),
            sample.sent_model.clone().into(),
            sample.reported_model.clone().into(),
            sample.reasoning_effort.clone().into(),
            sample.output_tokens.into(),
            sample.ttft_millis.into(),
            sample.decode_millis.into(),
            sample.response_millis.into(),
        ],
    ))
    .await?;
    Ok(())
}

/// 裁剪到固定上限；调用方与其它统计共用一个批次事务提交。
pub(super) async fn trim(db: &impl ConnectionTrait) -> Result<()> {
    db.execute_raw(statement(
        "DELETE FROM performance_samples WHERE (thread_id,call_id) IN (
           SELECT thread_id,call_id FROM performance_samples
           ORDER BY completed_at DESC,thread_id DESC,call_id DESC LIMIT -1 OFFSET ?)",
        vec![(PERFORMANCE_SAMPLE_LIMIT as i64).into()],
    ))
    .await?;
    Ok(())
}

/// 迁移时把旧 `model_calls` 的成功调用一次性有界投影为样本集合。
pub(super) async fn migrate_from_legacy(db: &DatabaseConnection) -> Result<()> {
    let rows = db
        .query_all_raw(statement(
            "SELECT thread_id,call_id,root_thread_id,turn_id,retry_of,revision,
                    admitted_at,started_at,finished_at,status,terminal,retention,purpose,
                    provider_instance_id,provider_display_name,configured_model,sent_model,
                    reported_model,reasoning_effort,input_tokens,output_tokens,cache_read_tokens,
                    cache_write_tokens,reasoning_tokens,total_tokens,ttft_millis,decode_millis,
                    response_millis,cost_currency,cost_amount,has_unpriced_usage
             FROM model_calls
         WHERE terminal=1 AND status='committed'
         ORDER BY COALESCE(finished_at,started_at) DESC,thread_id DESC,call_id DESC LIMIT ?",
            vec![(PERFORMANCE_SAMPLE_LIMIT as i64).into()],
        ))
        .await?;
    // Reuse the migration decoder and the live projection's paired validation. A second SQL
    // rendition of UsageReport's rules would silently diverge for malformed legacy counters.
    // Explicit metadata columns also keep old inline bodies out of this bounded projection.
    let tx = db.begin().await?;
    for row in &rows {
        let legacy = schema::legacy_record(row)?;
        record(&tx, &sample_from_record(&legacy)).await?;
    }
    trim(&tx).await?;
    tx.commit().await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn migration_bounds_performance_without_losing_billing_or_reintroducing_old_samples()
    -> Result<()> {
        let temp = tempfile::tempdir()?;
        let path = temp.path().join("calls.sqlite");
        schema::seed_legacy_for_test(
            &path,
            "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i<3005)
             INSERT INTO model_calls(thread_id,call_id,turn_id,attempt_id,revision,admitted_at,
               started_at,finished_at,status,terminal,root_thread_id,provider_instance_id,
               sent_model,output_tokens,ttft_millis,decode_millis,response_millis,
               cost_currency,cost_amount)
             SELECT 'thread',printf('call-%04d',i),'turn',printf('call-%04d',i),i,i,i,i,
               'committed',1,'root','provider','model',10,20,100,120,'USD',1.0 FROM n;
             UPDATE model_calls SET output_tokens=0 WHERE call_id='call-3005';
             UPDATE model_calls SET response_millis=1 WHERE call_id='call-3004';
             UPDATE model_calls SET output_tokens=NULL WHERE call_id='call-3003';
             UPDATE model_calls SET reasoning_tokens=20 WHERE call_id='call-3002';
             UPDATE calls_meta SET schema_version=3;",
        )
        .await?;
        let upgraded = CallsStore::open(&path).await?;
        let samples = upgraded.recent_performance_samples(5000).await?;
        assert!(
            samples.is_empty(),
            "expired diagnostics must not reappear from performance summaries"
        );
        let summary = upgraded.performance_summary_rows().await?;
        // All 3000 bounded records survive migration, but invalid usage, zero/missing output and
        // inconsistent timing contribute neither side. Their monetary facts are still retained.
        assert_eq!(summary[0].sample_count, 2996);
        assert_eq!(summary[0].completion_tokens, 29960);
        assert_eq!(summary[0].total_decode_millis, 299600);
        let costs = upgraded.session_cost_rollups().await?;
        assert_eq!(costs[0].estimated_costs[0].amount, 3005.0);

        // 迟到的旧调用样本不能挤掉真正更新的样本。
        let tx = upgraded.writer.db.begin().await?;
        record(
            &tx,
            &PerformanceSample {
                thread_id: "thread".to_owned(),
                call_id: "call-0001".to_owned(),
                completed_at: 1,
                provider_instance_id: Some("provider".to_owned()),
                provider_display_name: Some("provider".to_owned()),
                configured_model: Some("model".to_owned()),
                sent_model: Some("model".to_owned()),
                reported_model: None,
                reasoning_effort: None,
                output_tokens: Some(10),
                ttft_millis: Some(20),
                decode_millis: Some(100),
                response_millis: Some(120),
            },
        )
        .await?;
        trim(&tx).await?;
        tx.commit().await?;
        let reopened = CallsStore::open(&path).await?;
        let samples = reopened.recent_performance_samples(5000).await?;
        assert!(samples.is_empty());
        let bounds = reopened
            .writer
            .db
            .query_one_raw(statement(
                "SELECT COUNT(*) AS count,MIN(completed_at) AS oldest FROM performance_samples",
                vec![],
            ))
            .await?
            .unwrap();
        assert_eq!(bounds.try_get::<i64>("", "count")?, 3000);
        assert_eq!(bounds.try_get::<i64>("", "oldest")?, 6);
        upgraded.stop_best_effort();
        reopened.stop_best_effort();
        Ok(())
    }
}
