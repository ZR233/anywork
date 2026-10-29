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
    pub(super) purpose: Option<String>,
    pub(super) usage_status: pl_core::usage::UsageStatus,
    pub(super) first_output_source: pl_protocol::FirstOutputSource,
    pub(super) throughput_valid: bool,
    pub(super) completed_at: i64,
    pub(super) account_id: Option<String>,
    pub(super) account_display_name: Option<String>,
    pub(super) model_id: Option<String>,
    pub(super) sent_model: Option<String>,
    pub(super) reported_model: Option<String>,
    pub(super) effort: Option<String>,
    pub(super) output_tokens: Option<i64>,
    pub(super) ttft_millis: Option<i64>,
    pub(super) decode_millis: Option<i64>,
    pub(super) response_millis: Option<i64>,
}

/// 从轻量日志记录构造性能样本；旧统计口径的记录只保留为原始调用日志。
pub(super) fn sample_from_record(record: &CallLogRecord) -> Option<PerformanceSample> {
    if !record.is_current_throughput_epoch() {
        return None;
    }
    let usage = record.usage.as_ref();
    let timing = record.timing.as_ref();
    Some(PerformanceSample {
        thread_id: record.thread_id.clone(),
        call_id: record.call_id.clone(),
        purpose: record.purpose.clone(),
        usage_status: record
            .usage_status
            .unwrap_or(pl_core::usage::UsageStatus::LegacyUnknown),
        first_output_source: timing.map_or(pl_protocol::FirstOutputSource::Unobserved, |timing| {
            timing.first_output_source
        }),
        throughput_valid: record.throughput_sample().is_some(),
        completed_at: record.recorded_at,
        account_id: record.account_id.clone(),
        account_display_name: record.account_display_name.clone(),
        model_id: record.model_id.clone(),
        sent_model: record.sent_model.clone(),
        reported_model: record.reported_model.clone(),
        effort: record.effort.clone(),
        output_tokens: usage
            .and_then(|usage| usage.output_tokens)
            .and_then(opt_i64),
        // 未测得的时延保持 NULL，绝不折叠成零；成对有效性由读取汇总的查询判定。
        ttft_millis: timing
            .and_then(|timing| timing.ttft_millis)
            .and_then(opt_i64),
        decode_millis: timing
            .and_then(|timing| timing.decode_millis)
            .and_then(opt_i64),
        response_millis: timing
            .and_then(|timing| timing.response_millis)
            .and_then(opt_i64),
    })
}

/// 幂等写入一条性能样本；同身份以最新事实覆盖。
pub(super) async fn record(db: &impl ConnectionTrait, sample: &PerformanceSample) -> Result<()> {
    db.execute_raw(statement(
        "INSERT INTO performance_samples(
            thread_id,call_id,completed_at,account_id,account_display_name,
            model_id,sent_model,reported_model,effort,output_tokens,
            ttft_millis,decode_millis,response_millis,purpose,usage_status,first_output_source,throughput_valid)
         VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
         ON CONFLICT(thread_id,call_id) DO UPDATE SET
            completed_at=excluded.completed_at,
            account_id=excluded.account_id,
            account_display_name=excluded.account_display_name,
            model_id=excluded.model_id,
            sent_model=excluded.sent_model,
            reported_model=excluded.reported_model,
            effort=excluded.effort,
            output_tokens=excluded.output_tokens,
            ttft_millis=excluded.ttft_millis,
            decode_millis=excluded.decode_millis,
            response_millis=excluded.response_millis,
            purpose=excluded.purpose,usage_status=excluded.usage_status,
            first_output_source=excluded.first_output_source,throughput_valid=excluded.throughput_valid",
        vec![
            sample.thread_id.clone().into(),
            sample.call_id.clone().into(),
            sample.completed_at.into(),
            sample.account_id.clone().into(),
            sample.account_display_name.clone().into(),
            sample.model_id.clone().into(),
            sample.sent_model.clone().into(),
            sample.reported_model.clone().into(),
            sample.effort.clone().into(),
            sample.output_tokens.into(),
            sample.ttft_millis.into(),
            sample.decode_millis.into(),
            sample.response_millis.into(),
            sample.purpose.clone().into(),
            enum_text(sample.usage_status)?.into(),
            enum_text(sample.first_output_source)?.into(),
            (sample.throughput_valid as i32).into(),
        ],
    ))
    .await?;
    Ok(())
}

fn enum_text(value: impl serde::Serialize) -> Result<String> {
    Ok(serde_json::to_value(value)?
        .as_str()
        .context("expected enum string")?
        .to_owned())
}

pub(super) async fn read_history(
    db: &impl ConnectionTrait,
    limit: u32,
) -> Result<Vec<PerformanceSampleRow>> {
    let rows = db.query_all_raw(statement(
        "SELECT * FROM performance_samples ORDER BY completed_at DESC,thread_id DESC,call_id DESC LIMIT ?",
        vec![i64::from(limit.min(PERFORMANCE_SAMPLE_LIMIT as u32)).into()]
    )).await?;
    rows.iter()
        .map(|row| {
            let optional = |name| -> Result<Option<u64>> {
                row.try_get::<Option<i64>>("", name)?
                    .map(u64::try_from)
                    .transpose()
                    .map_err(Into::into)
            };
            Ok(PerformanceSampleRow {
                thread_id: row.try_get("", "thread_id")?,
                call_id: row.try_get("", "call_id")?,
                purpose: row.try_get("", "purpose")?,
                completed_at: row.try_get("", "completed_at")?,
                account_id: row
                    .try_get::<Option<String>>("", "account_id")?
                    .unwrap_or_default(),
                account_display_name: row
                    .try_get::<Option<String>>("", "account_display_name")?
                    .unwrap_or_default(),
                model_id: row.try_get("", "model_id")?,
                sent_model: row
                    .try_get::<Option<String>>("", "sent_model")?
                    .unwrap_or_default(),
                reported_model: row.try_get("", "reported_model")?,
                effort: row.try_get("", "effort")?,
                completion_tokens: optional("output_tokens")?,
                usage_status: serde_json::from_value(serde_json::Value::String(
                    row.try_get("", "usage_status")?,
                ))?,
                first_output_source: serde_json::from_value(serde_json::Value::String(
                    row.try_get("", "first_output_source")?,
                ))?,
                ttft_millis: optional("ttft_millis")?,
                decode_millis: optional("decode_millis")?,
                response_millis: optional("response_millis")?,
                has_throughput_sample: row.try_get::<i64>("", "throughput_valid")? != 0,
            })
        })
        .collect()
}

pub(super) async fn read_summary(db: &impl ConnectionTrait) -> Result<Vec<PerformanceSummaryRow>> {
    let rows = db
        .query_all_raw(statement(
            "SELECT account_id,COALESCE(MAX(account_display_name),'') AS account_display_name,
                model_id,effort,COUNT(*) AS sample_count,
                SUM(output_tokens) AS completion_tokens,
                COALESCE(SUM(ttft_millis),0) AS total_ttft_millis,
                COUNT(ttft_millis) AS ttft_sample_count,
                SUM(response_millis) AS total_response_millis
         FROM performance_samples
         WHERE account_id IS NOT NULL AND account_id<>'' AND model_id IS NOT NULL AND model_id<>''
           AND throughput_valid=1 AND output_tokens>0 AND response_millis>0
           AND usage_status NOT IN ('invalid','legacyUnknown')
         GROUP BY account_id,model_id,effort
         ORDER BY account_id,model_id,effort IS NOT NULL,effort",
            vec![],
        ))
        .await?;
    rows.iter().map(performance_summary_row).collect()
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

#[cfg(test)]
mod tests {
    use super::*;

    const LEGACY_V6_SAMPLES: &str = "
CREATE TABLE performance_samples (
    thread_id TEXT NOT NULL,
    call_id TEXT NOT NULL,
    completed_at INTEGER NOT NULL,
    provider_instance_id TEXT,
    provider_display_name TEXT,
    configured_model TEXT,
    sent_model TEXT,
    reported_model TEXT,
    reasoning_effort TEXT,
    output_tokens INTEGER,
    ttft_millis INTEGER,
    decode_millis INTEGER,
    response_millis INTEGER,
    PRIMARY KEY(thread_id,call_id)
);
INSERT INTO performance_samples VALUES
 ('thread','a','10','deepseek','DeepSeek','deepseek-flash','deepseek-flash',NULL,'high',10,20,100,120),
 ('thread','b','11','deepseek','DeepSeek','deepseek-flash','deepseek-flash',NULL,'low',20,30,200,230),
 ('thread','c','12','deepseek','DeepSeek',NULL,'deepseek-flash',NULL,'high',30,40,300,340),
 ('thread','d','13','second','Second','deepseek-reasoner','alias-sent',NULL,'high',40,50,400,450);
";

    /// 当前口径样本：`b` 没有首字，`e` 输出为零，`f` 的首字边界与总响应矛盾。
    const CURRENT_EPOCH_SAMPLES: &str = "
UPDATE calls_meta SET throughput_epoch=1;
CREATE TABLE performance_samples (
    thread_id TEXT NOT NULL,
    call_id TEXT NOT NULL,
    completed_at INTEGER NOT NULL,
    account_id TEXT,
    account_display_name TEXT,
    model_id TEXT,
    sent_model TEXT,
    reported_model TEXT,
    effort TEXT,
    output_tokens INTEGER,
    ttft_millis INTEGER,
    decode_millis INTEGER,
    response_millis INTEGER,
    PRIMARY KEY(thread_id,call_id)
        );
INSERT INTO performance_samples VALUES
 ('thread','a','10','deepseek','DeepSeek','deepseek-flash','deepseek-flash',NULL,'high',100,200,800,1000),
 ('thread','b','11','deepseek','DeepSeek','deepseek-flash','deepseek-flash',NULL,'low',1,NULL,NULL,100),
 ('thread','c','12','deepseek','DeepSeek',NULL,'deepseek-flash',NULL,'high',30,40,300,340),
 ('thread','d','13','second','Second','deepseek-reasoner','alias-sent',NULL,'high',40,50,400,450),
 ('thread','e','14','deepseek','DeepSeek','deepseek-flash','deepseek-flash',NULL,'high',0,10,90,100),
 ('thread','f','15','deepseek','DeepSeek','deepseek-flash','deepseek-flash',NULL,'high',5,90,5,100);
";

    #[tokio::test]
    async fn schema_seven_preserves_current_rows_without_inventing_raw_validity() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let path = temp.path().join("calls.sqlite");
        schema::seed_version_for_test(&path, 7, CURRENT_EPOCH_SAMPLES).await?;
        let db = Database::connect(
            crate::studio::paths::sqlite_file_options(
                &path,
                crate::studio::paths::SqliteFileMode::Create,
                |options| options,
            )
            .await?,
        )
        .await?;
        db.execute_unprepared(
            "UPDATE performance_samples SET output_tokens=NULL WHERE call_id='b'",
        )
        .await?;
        db.close().await?;
        let store = CallsStore::open(&path).await?;
        let history = store.recent_performance_samples(100).await?;
        assert_eq!(history.len(), 6);
        let unknown = history.iter().find(|row| row.call_id == "b").unwrap();
        assert_eq!(unknown.completion_tokens, None);
        assert_eq!(unknown.response_millis, Some(100));
        assert_eq!(
            unknown.usage_status,
            pl_core::usage::UsageStatus::LegacyUnknown
        );
        assert_eq!(
            unknown.first_output_source,
            pl_protocol::FirstOutputSource::LegacyUnknown
        );
        assert_eq!(unknown.purpose, None);
        assert!(!unknown.has_throughput_sample);
        let known = history.iter().find(|row| row.call_id == "a").unwrap();
        assert_eq!(known.account_id, "deepseek");
        assert_eq!(known.model_id.as_deref(), Some("deepseek-flash"));
        assert_eq!(known.completion_tokens, Some(100));
        assert!(
            store
                .read_statistics(StatisticsReadRequest {
                    costs: false,
                    performance: true,
                })
                .await?
                .summary
                .expect("performance summary requested")
                .is_empty()
        );
        store.close().await?;
        let reopened = CallsStore::open(&path).await?;
        assert_eq!(reopened.recent_performance_samples(100).await?.len(), 6);
        assert!(
            reopened
                .read_statistics(StatisticsReadRequest {
                    costs: false,
                    performance: true,
                })
                .await?
                .summary
                .expect("performance summary requested")
                .is_empty()
        );
        reopened.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn previous_epoch_samples_are_discarded_instead_of_migrated() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let path = temp.path().join("calls.sqlite");
        schema::seed_version_for_test(&path, 6, LEGACY_V6_SAMPLES).await?;
        let store = CallsStore::open(&path).await?;
        assert!(
            store
                .read_statistics(StatisticsReadRequest {
                    costs: false,
                    performance: true,
                })
                .await?
                .summary
                .expect("performance summary requested")
                .is_empty(),
            "the previous statistics epoch is dropped, never converted"
        );
        let kept = store
            .writer
            .db
            .query_one_raw(statement(
                "SELECT COUNT(*) AS count FROM performance_samples",
                vec![],
            ))
            .await?
            .unwrap();
        assert_eq!(kept.try_get::<i64>("", "count")?, 0);
        let epoch = store
            .writer
            .db
            .query_one_raw(statement(
                "SELECT throughput_epoch FROM calls_meta WHERE id=1",
                vec![],
            ))
            .await?
            .unwrap();
        assert_eq!(
            epoch.try_get::<i64>("", "throughput_epoch")?,
            i64::from(event::THROUGHPUT_EPOCH)
        );
        store.stop_best_effort();
        Ok(())
    }

    #[tokio::test]
    async fn summary_weights_output_by_total_response_time_and_counts_known_first_tokens()
    -> Result<()> {
        let temp = tempfile::tempdir()?;
        let path = temp.path().join("calls.sqlite");
        schema::seed_version_for_test(&path, 7, CURRENT_EPOCH_SAMPLES).await?;
        let store = CallsStore::open(&path).await?;
        // This fixture tests SQL grouping, not migration provenance. Mark only the
        // deliberately paired artificial rows usable after the migration boundary.
        store
            .writer
            .db
            .execute_unprepared(
                "UPDATE performance_samples SET usage_status='partial',throughput_valid=1
             WHERE call_id IN ('a','b','c','d');",
            )
            .await?;
        let summary = store
            .read_statistics(StatisticsReadRequest {
                costs: false,
                performance: true,
            })
            .await?
            .summary
            .expect("performance summary requested");
        let flashes: Vec<_> = summary
            .iter()
            .filter(|row| row.account_id == "deepseek" && row.model_id == "deepseek-flash")
            .collect();
        assert_eq!(flashes.len(), 2, "effort stays a secondary breakdown");
        let total: u64 = flashes.iter().map(|row| row.sample_count).sum();
        assert_eq!(
            total, 2,
            "zero-output and inconsistent samples stay excluded"
        );
        let high = flashes
            .iter()
            .find(|row| row.effort.as_deref() == Some("high"))
            .expect("high effort group");
        assert_eq!(high.completion_tokens, 100);
        assert_eq!(high.total_response_millis, 1_000);
        assert_eq!(high.total_ttft_millis, 200);
        assert_eq!(high.ttft_sample_count, 1);
        let low = flashes
            .iter()
            .find(|row| row.effort.as_deref() == Some("low"))
            .expect("low effort group");
        assert_eq!(low.completion_tokens, 1);
        assert_eq!(low.total_response_millis, 100);
        assert_eq!(
            low.ttft_sample_count, 0,
            "an unmeasured first token is not a zero-millisecond sample"
        );
        assert_eq!(low.total_ttft_millis, 0);
        assert!(
            summary
                .iter()
                .all(|row| row.account_id != "deepseek" || row.model_id == "deepseek-flash"),
            "unknown configured models never mix into a known account model"
        );
        let alias = summary
            .iter()
            .find(|row| row.account_id == "second")
            .expect("sent-model alias does not hide the configured model");
        assert_eq!(alias.model_id, "deepseek-reasoner");
        store.stop_best_effort();
        Ok(())
    }

    #[test]
    fn only_current_epoch_records_enter_the_performance_projection() {
        let mut record = CallLogRecord {
            status: "committed".to_owned(),
            usage_status: Some(pl_core::usage::UsageStatus::Partial),
            usage: Some(event::CallUsageRecord {
                output_tokens: Some(100),
                ..Default::default()
            }),
            timing: Some(event::CallTimingRecord {
                first_output_source: pl_protocol::FirstOutputSource::Incremental,
                ttft_millis: Some(200),
                decode_millis: Some(800),
                response_millis: Some(1_000),
            }),
            ..Default::default()
        };
        assert!(
            record.throughput_sample().is_none(),
            "a record without the current epoch marker is old diagnostics"
        );
        assert!(sample_from_record(&record).is_none());

        record.throughput_epoch = event::THROUGHPUT_EPOCH;
        let sample = sample_from_record(&record).expect("current epoch records are projected");
        assert_eq!(sample.response_millis, Some(1_000));
        assert_eq!(sample.ttft_millis, Some(200));
        assert_eq!(sample.decode_millis, Some(800));
        let (output_tokens, timing) = record.throughput_sample().expect("paired sample");
        assert_eq!(output_tokens, 100);
        assert_eq!(timing.response_millis, 1_000);

        let mut inconsistent = record;
        inconsistent.timing = Some(event::CallTimingRecord {
            first_output_source: pl_protocol::FirstOutputSource::Incremental,
            ttft_millis: Some(900),
            decode_millis: Some(5),
            response_millis: Some(1_000),
        });
        assert!(
            inconsistent.throughput_sample().is_none(),
            "a first-token boundary that disagrees with the total is not a speed sample"
        );
        assert!(
            sample_from_record(&inconsistent).is_some(),
            "raw timing stays visible in history even when it is not a speed sample"
        );
    }

    #[test]
    fn invalid_cache_report_is_visible_but_not_a_throughput_pair() {
        let record = CallLogRecord {
            status: "committed".into(),
            throughput_epoch: event::THROUGHPUT_EPOCH,
            usage_status: Some(pl_core::usage::UsageStatus::Invalid),
            usage: Some(event::CallUsageRecord {
                input_tokens: Some(10),
                output_tokens: Some(20),
                cache_read_tokens: Some(11),
                ..Default::default()
            }),
            timing: Some(event::CallTimingRecord {
                first_output_source: pl_protocol::FirstOutputSource::CompletedToolInput,
                response_millis: Some(100),
                ..Default::default()
            }),
            ..Default::default()
        };
        let sample = sample_from_record(&record).unwrap();
        assert_eq!(sample.output_tokens, Some(20));
        assert_eq!(
            sample.first_output_source,
            pl_protocol::FirstOutputSource::CompletedToolInput
        );
        assert!(!sample.throughput_valid);
        let mut unknown = record;
        unknown.usage.as_mut().unwrap().output_tokens = None;
        let sample = sample_from_record(&unknown).unwrap();
        assert_eq!(
            sample.output_tokens, None,
            "an unknown numerator is not an explicit zero"
        );
        assert!(!sample.throughput_valid);
    }

    #[tokio::test]
    async fn legacy_call_logs_keep_billing_and_never_backfill_previous_epoch_samples() -> Result<()>
    {
        let temp = tempfile::tempdir()?;
        let path = temp.path().join("calls.sqlite");
        let now = crate::studio::unix_seconds();
        schema::seed_legacy_for_test(
            &path,
            &format!(
                "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i<3005)
             INSERT INTO model_calls(thread_id,call_id,turn_id,attempt_id,revision,admitted_at,
               started_at,finished_at,status,terminal,root_thread_id,provider_instance_id,
               provider_display_name,sent_model,output_tokens,ttft_millis,decode_millis,
               response_millis,cost_currency,cost_amount)
             SELECT 'thread',printf('call-%04d',i),'turn',printf('call-%04d',i),i,{now},{now},{now},
               'committed',1,'root','legacy-account','Legacy DeepSeek','model',10,20,100,120,
               'USD',1.0 FROM n;
             UPDATE model_calls SET output_tokens=0 WHERE call_id='call-3005';
             UPDATE model_calls SET response_millis=1 WHERE call_id='call-3004';
             UPDATE model_calls SET output_tokens=NULL WHERE call_id='call-3003';
             UPDATE model_calls SET reasoning_tokens=20 WHERE call_id='call-3002';
             UPDATE calls_meta SET schema_version=3;"
            ),
        )
        .await?;
        let upgraded = CallsStore::open(&path).await?;
        let samples = upgraded.recent_performance_samples(5000).await?;
        assert!(
            samples.is_empty(),
            "previous-epoch log records never return as performance history"
        );
        assert!(
            upgraded
                .read_statistics(StatisticsReadRequest {
                    costs: false,
                    performance: true,
                })
                .await?
                .summary
                .expect("performance summary requested")
                .is_empty(),
            "previous-epoch log records never refill the bounded performance projection"
        );
        let kept = upgraded
            .writer
            .db
            .query_one_raw(statement(
                "SELECT COUNT(*) AS count FROM performance_samples",
                vec![],
            ))
            .await?
            .unwrap();
        assert_eq!(
            kept.try_get::<i64>("", "count")?,
            0,
            "the previous statistics epoch is discarded, not migrated"
        );
        // 原始调用日志与冻结费用必须保留：口径切换只作废派生的速度统计。
        let logs = upgraded
            .writer
            .db
            .query_one_raw(statement(
                "SELECT COUNT(*) AS count FROM call_log_index
                 WHERE kind='migrated' AND thread_id='thread'",
                vec![],
            ))
            .await?
            .unwrap();
        assert_eq!(
            logs.try_get::<i64>("", "count")?,
            3005,
            "the raw call log is preserved across the statistics epoch change"
        );
        let costs = upgraded.session_cost_rollups().await?;
        assert_eq!(costs[0].estimated_costs[0].amount, 3005.0);

        // 新口径样本从空集合开始建立，且只由新写入的计费事件产生。
        let tx = upgraded.writer.db.begin().await?;
        record(
            &tx,
            &PerformanceSample {
                thread_id: "thread".to_owned(),
                call_id: "call-new".to_owned(),
                purpose: None,
                usage_status: pl_core::usage::UsageStatus::Partial,
                first_output_source: pl_protocol::FirstOutputSource::Unobserved,
                throughput_valid: true,
                completed_at: now,
                account_id: Some("account".to_owned()),
                account_display_name: Some("Account".to_owned()),
                model_id: Some("model".to_owned()),
                sent_model: Some("model".to_owned()),
                reported_model: None,
                effort: None,
                output_tokens: Some(200),
                ttft_millis: None,
                decode_millis: None,
                response_millis: Some(1_000),
            },
        )
        .await?;
        trim(&tx).await?;
        tx.commit().await?;
        let summary = upgraded
            .read_statistics(StatisticsReadRequest {
                costs: false,
                performance: true,
            })
            .await?
            .summary
            .expect("performance summary requested");
        assert_eq!(summary.len(), 1, "new epoch samples are usable");
        assert_eq!(summary[0].completion_tokens, 200);
        assert_eq!(summary[0].total_response_millis, 1_000);
        assert_eq!(
            summary[0].ttft_sample_count, 0,
            "an unknown first token stays outside the first-token average"
        );
        assert_eq!(
            upgraded.recent_performance_samples(5000).await?.len(),
            1,
            "history consumes the same SQL material as summary"
        );
        upgraded.stop_best_effort();
        Ok(())
    }
}
