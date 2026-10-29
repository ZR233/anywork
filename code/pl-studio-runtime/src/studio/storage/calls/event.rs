//! 轻量调用事件与版本化 JSONL 记录的编解码。
//!
//! 队列只承载这里提取出的轻量记录：绝不 clone/encode 整个 [`pl_core::thread::ThreadEffectBatch`]，
//! 记录里不包含 context、tools 或其它重型正文。每条记录序列化成一行版本化 JSON，写入滚动日志。

use super::*;

/// 单条 JSONL 记录的 schema 版本；写入每行的 `version` 字段，构成“版本化 JSONL”。
///
/// v2 把账号/模型接入身份改为 `accountId`/`modelId`/`effort`。v1 行只在读取边界按
/// 已知字段转换后交给当前类型，不做全局文本替换，也不改写既有日志正文。
/// v3 保存 core 用量状态与首次内容观测来源；v1/v2 的轻量投影在读取边界明确标为历史未知。
pub(super) const CALL_LOG_RECORD_VERSION: u32 = 3;
/// 单条记录的最大字节数；超过即显式 `truncated`，绝不静默截断正文。
pub(super) const CALL_LOG_RECORD_MAX_BYTES: usize = 1024 * 1024;

/// 迁移自旧 `model_calls` 的调用记录类别。
pub(super) const CALL_LOG_KIND_ATTEMPT: &str = "attempt";
pub(super) const CALL_LOG_KIND_BILLING: &str = "billing";
pub(super) const CALL_LOG_KIND_MIGRATED: &str = "migrated";

/// 六个 token 计数；`None` 表示未测得，绝不以零冒充。
#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(super) struct CallUsageRecord {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) input_tokens: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) output_tokens: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) cache_read_tokens: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) cache_write_tokens: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) reasoning_tokens: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) total_tokens: Option<u64>,
}

/// 当前统计口径的标识；旧记录没有该字段，解码后为 0，不会被当作当前口径样本。
///
/// 口径从 decode 分母切换到含首字等待的总响应分母时递增一次。原始调用日志保留可读，
/// 只有派生统计以此为门槛，避免旧日志回填复活旧口径。
pub(super) const THROUGHPUT_EPOCH: u32 = 1;

/// 一次成功调用的耗时事实；缺失的计时不会被折叠成零样本。
#[derive(Debug, Clone, Copy, Default, serde::Serialize, serde::Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(super) struct CallTimingRecord {
    #[serde(default = "legacy_output_source")]
    pub(super) first_output_source: pl_protocol::FirstOutputSource,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) ttft_millis: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) decode_millis: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) response_millis: Option<u64>,
}

impl CallTimingRecord {
    /// 投影一次计时的原始事实。
    pub(super) fn measured(timing: pl_protocol::InferenceTiming) -> Self {
        Self {
            first_output_source: timing.first_output_source,
            ttft_millis: timing.ttft_millis,
            decode_millis: timing.decode_millis,
            response_millis: Some(timing.response_millis),
        }
    }

    /// 旧调用结构的耗时列；它们只作诊断，不进入速度样本。
    pub(super) fn legacy(
        ttft_millis: Option<u64>,
        decode_millis: Option<u64>,
        response_millis: Option<u64>,
    ) -> Self {
        Self {
            first_output_source: pl_protocol::FirstOutputSource::LegacyUnknown,
            ttft_millis,
            decode_millis,
            response_millis,
        }
    }

    fn protocol_timing(self) -> pl_protocol::InferenceTiming {
        pl_protocol::InferenceTiming {
            first_output_source: self.first_output_source,
            ttft_millis: self.ttft_millis,
            decode_millis: self.decode_millis,
            response_millis: self.response_millis.unwrap_or(0),
        }
    }
}

fn legacy_output_source() -> pl_protocol::FirstOutputSource {
    pl_protocol::FirstOutputSource::LegacyUnknown
}

/// 一行版本化 JSONL 日志记录；也是队列事件的载荷。
#[derive(Debug, Clone, Default, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct CallLogRecord {
    #[serde(default = "record_version")]
    pub(super) version: u32,
    pub(super) kind: String,
    pub(super) thread_id: String,
    pub(super) call_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) root_thread_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) turn_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) retry_of: Option<String>,
    pub(super) status: String,
    pub(super) terminal: bool,
    pub(super) revision: i64,
    pub(super) recorded_at: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) retention: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) purpose: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) account_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) account_display_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) model_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) sent_model: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) reported_model: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) effort: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) usage: Option<CallUsageRecord>,
    pub(super) usage_status: Option<pl_core::usage::UsageStatus>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) cost: Option<RuntimeCostAmount>,
    #[serde(default, skip_serializing_if = "is_false")]
    pub(super) has_unpriced_usage: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) timing: Option<CallTimingRecord>,
    /// 写出该记录时的统计口径；缺失或低于当前值时只作为原始调用日志保留。
    #[serde(default)]
    pub(super) throughput_epoch: u32,
    /// 正文超过单条上限，字段被显式丢弃；读取端据此区分截断与完整记录。
    #[serde(default, skip_serializing_if = "is_false")]
    pub(super) truncated: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) input_revision: Option<u64>,
    /// Bounded JSON text of this result/error only, never a request or context snapshot.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) diagnostic: Option<String>,
}

impl CallLogRecord {
    /// 该记录是否由当前统计口径写出；旧口径记录只保留为原始调用日志。
    pub(super) fn is_current_throughput_epoch(&self) -> bool {
        self.throughput_epoch == THROUGHPUT_EPOCH
    }

    /// Speed is a derived, paired fact. Raw counters and timings remain in the log even when this
    /// validation rejects them for performance statistics.
    pub(super) fn throughput_sample(&self) -> Option<(u64, pl_protocol::InferenceTiming)> {
        if self.status != CallStatus::Committed.as_str() || !self.is_current_throughput_epoch() {
            return None;
        }
        let usage = self.usage.as_ref()?;
        let report = pl_protocol::UsageReport {
            input_tokens: usage.input_tokens,
            output_tokens: usage.output_tokens,
            cache_read_tokens: usage.cache_read_tokens,
            cache_write_tokens: usage.cache_write_tokens,
            reasoning_tokens: usage.reasoning_tokens,
            total_tokens: usage.total_tokens,
        };
        let timing = self.timing?.protocol_timing();
        if self.usage_status? == pl_core::usage::UsageStatus::LegacyUnknown {
            return None;
        }
        pl_model::model::usage::throughput_output_tokens(timing, &report)
            .map(|output_tokens| (output_tokens, timing))
    }

    /// 构造一条最小身份的显式截断记录。
    pub(super) fn truncated_fallback(&self) -> Self {
        Self {
            version: self.version,
            kind: self.kind.clone(),
            thread_id: self.thread_id.clone(),
            call_id: self.call_id.clone(),
            root_thread_id: self.root_thread_id.clone(),
            turn_id: None,
            retry_of: None,
            status: self.status.clone(),
            terminal: self.terminal,
            revision: self.revision,
            recorded_at: self.recorded_at,
            retention: self.retention.clone(),
            purpose: None,
            account_id: None,
            account_display_name: None,
            model_id: None,
            sent_model: None,
            reported_model: None,
            effort: None,
            usage: None,
            usage_status: self.usage_status,
            cost: None,
            has_unpriced_usage: self.has_unpriced_usage,
            timing: None,
            throughput_epoch: self.throughput_epoch,
            truncated: true,
            input_revision: self.input_revision,
            diagnostic: None,
        }
    }
}

fn record_version() -> u32 {
    CALL_LOG_RECORD_VERSION
}

/// 版本化日志记录的读取边界：同时接受当前字段与 v1 的账号/模型接入字段名。
///
/// 转换只发生在这里，且只映射已知语义相同的三个字段；未知字段保持忽略，不改写日志正文。
#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawCallLogRecord {
    #[serde(default = "legacy_record_version")]
    version: u32,
    #[serde(default)]
    kind: String,
    #[serde(default)]
    thread_id: String,
    #[serde(default)]
    call_id: String,
    #[serde(default)]
    root_thread_id: Option<String>,
    #[serde(default)]
    turn_id: Option<String>,
    #[serde(default)]
    retry_of: Option<String>,
    #[serde(default)]
    status: String,
    #[serde(default)]
    terminal: bool,
    #[serde(default)]
    revision: i64,
    #[serde(default)]
    recorded_at: i64,
    #[serde(default)]
    retention: Option<String>,
    #[serde(default)]
    purpose: Option<String>,
    #[serde(default)]
    account_id: Option<String>,
    #[serde(default)]
    account_display_name: Option<String>,
    #[serde(default)]
    model_id: Option<String>,
    #[serde(default)]
    sent_model: Option<String>,
    #[serde(default)]
    reported_model: Option<String>,
    #[serde(default)]
    effort: Option<String>,
    #[serde(default)]
    usage: Option<CallUsageRecord>,
    #[serde(default)]
    usage_status: Option<pl_core::usage::UsageStatus>,
    #[serde(default)]
    cost: Option<RuntimeCostAmount>,
    #[serde(default)]
    has_unpriced_usage: bool,
    #[serde(default)]
    timing: Option<CallTimingRecord>,
    #[serde(default)]
    throughput_epoch: u32,
    #[serde(default)]
    truncated: bool,
    #[serde(default)]
    input_revision: Option<u64>,
    #[serde(default)]
    diagnostic: Option<String>,
    /// v1 的账号接入身份（真实旧字段 `providerInstanceId`）；只在读取边界并入 `account_id`。
    #[serde(default)]
    provider_instance_id: Option<String>,
    /// v1 的账号展示名（真实旧字段 `providerDisplayName`）。
    #[serde(default)]
    provider_display_name: Option<String>,
    /// v1 的目录配置模型（真实旧字段 `configuredModel`）；只在读取边界并入 `model_id`。
    #[serde(default)]
    configured_model: Option<String>,
    /// v1 的推理强度（真实旧字段 `reasoningEffort`）；只在读取边界并入 `effort`。
    #[serde(default)]
    reasoning_effort: Option<String>,
}

fn legacy_record_version() -> u32 {
    1
}

impl RawCallLogRecord {
    fn into_current(self) -> CallLogRecord {
        CallLogRecord {
            // 已知旧版本在读取边界归一化为当前版本（身份字段已并入当前语义）；
            // 未知的未来版本保留原值，交给版本门显式拒绝而不是静默升级。
            version: if self.version <= CALL_LOG_RECORD_VERSION {
                record_version()
            } else {
                self.version
            },
            kind: self.kind,
            thread_id: self.thread_id,
            call_id: self.call_id,
            root_thread_id: self.root_thread_id,
            turn_id: self.turn_id,
            retry_of: self.retry_of,
            status: self.status,
            terminal: self.terminal,
            revision: self.revision,
            recorded_at: self.recorded_at,
            retention: self.retention,
            purpose: self.purpose,
            account_id: self.account_id.or(self.provider_instance_id),
            account_display_name: self.account_display_name.or(self.provider_display_name),
            model_id: self.model_id.or(self.configured_model),
            sent_model: self.sent_model,
            reported_model: self.reported_model,
            effort: self.effort.or(self.reasoning_effort),
            usage: self.usage,
            usage_status: if self.version < 3 {
                Some(pl_core::usage::UsageStatus::LegacyUnknown)
            } else {
                self.usage_status
            },
            cost: self.cost,
            has_unpriced_usage: self.has_unpriced_usage,
            timing: self.timing,
            throughput_epoch: self.throughput_epoch,
            truncated: self.truncated,
            input_revision: self.input_revision,
            diagnostic: self.diagnostic,
        }
    }
}

impl<'de> serde::Deserialize<'de> for CallLogRecord {
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        Ok(RawCallLogRecord::deserialize(deserializer)?.into_current())
    }
}

fn is_false(value: &bool) -> bool {
    !*value
}

/// 从一次 effect 的 attempt 更新提取轻量记录；`tools`、context 与 request 元数据一律不进入记录。
pub(super) fn attempt_record(
    thread_id: &str,
    revision: i64,
    committed_at: i64,
    attempt: &AttemptUpdate,
) -> CallLogRecord {
    let status = attempt_status(&attempt.outcome);
    let (diagnostic, truncated) = diagnostic(&attempt.outcome);
    CallLogRecord {
        version: CALL_LOG_RECORD_VERSION,
        kind: CALL_LOG_KIND_ATTEMPT.to_owned(),
        thread_id: thread_id.to_owned(),
        call_id: attempt.attempt_id.clone(),
        root_thread_id: None,
        turn_id: Some(attempt.turn_id.clone()),
        retry_of: attempt.retry_of.clone(),
        status: status.as_str().to_owned(),
        terminal: status.is_terminal(),
        revision,
        recorded_at: committed_at,
        retention: None,
        purpose: None,
        account_id: None,
        account_display_name: None,
        model_id: None,
        sent_model: None,
        reported_model: None,
        effort: None,
        usage: outcome_usage(&attempt.outcome).map(usage_record_from_model),
        usage_status: outcome_usage(&attempt.outcome)
            .map(|usage| pl_core::usage::analyze_usage(usage).status),
        cost: None,
        has_unpriced_usage: false,
        timing: None,
        throughput_epoch: 0,
        truncated,
        input_revision: Some(attempt.input_revision),
        diagnostic: Some(diagnostic),
    }
}

/// 从一次计费观察提取轻量记录；只保留展示与统计所需的身份、用量、价格与时延。
pub(super) fn billing_record(
    root_thread_id: &str,
    thread_id: &str,
    retention: CallRetention,
    billing: &InferenceBillingRecord,
    status: CallStatus,
) -> CallLogRecord {
    let usage = &billing.accounting.usage;
    // 统计身份只取冻结的账号与目录配置模型；发送/返回模型保持独立诊断维度。
    let (sent_model, reported_model) = match &billing.model_observation {
        Some(observation) => (
            Some(observation.sent_model.clone()),
            observation.reported_model.clone(),
        ),
        None => (None, None),
    };
    let cost = billing.accounting.estimated_costs().into_iter().next();
    let timing = billing.timing.map(CallTimingRecord::measured);
    CallLogRecord {
        version: CALL_LOG_RECORD_VERSION,
        kind: CALL_LOG_KIND_BILLING.to_owned(),
        thread_id: thread_id.to_owned(),
        call_id: billing.inference_id.clone(),
        root_thread_id: Some(root_thread_id.to_owned()),
        turn_id: None,
        retry_of: None,
        status: status.as_str().to_owned(),
        terminal: true,
        revision: 0,
        recorded_at: billing.recorded_at,
        retention: Some(retention.as_str().to_owned()),
        purpose: billing.purpose.clone(),
        account_id: Some(billing.account_id.clone()),
        account_display_name: billing.account_display_name.clone(),
        model_id: billing.model_id.clone(),
        sent_model,
        reported_model,
        effort: billing.effort.clone(),
        usage: Some(CallUsageRecord {
            input_tokens: usage.input_tokens,
            output_tokens: usage.output_tokens,
            cache_read_tokens: usage.cache_read_tokens,
            cache_write_tokens: usage.cache_write_tokens,
            reasoning_tokens: usage.reasoning_tokens,
            total_tokens: usage.total_tokens,
        }),
        usage_status: Some(pl_model::model::usage::analyze(usage).status),
        cost,
        has_unpriced_usage: billing.accounting.has_unpriced_usage(),
        timing,
        throughput_epoch: THROUGHPUT_EPOCH,
        truncated: false,
        input_revision: None,
        diagnostic: None,
    }
}

fn usage_record_from_model(usage: &ModelUsage) -> CallUsageRecord {
    CallUsageRecord {
        input_tokens: usage.input_tokens,
        output_tokens: usage.output_tokens,
        cache_read_tokens: usage.cache_read_tokens,
        cache_write_tokens: usage.cache_write_tokens,
        reasoning_tokens: usage.reasoning_tokens,
        total_tokens: usage.total_tokens,
    }
}

/// 记录所属的日志日（UTC 自然日）；跨日时轮转到新段。
pub(super) fn record_day(recorded_at: i64) -> i64 {
    recorded_at.div_euclid(SECONDS_PER_DAY)
}

/// 编码一行记录；返回 `(line, truncated)`，`line` 不含换行。
///
/// 正文超过 [`CALL_LOG_RECORD_MAX_BYTES`] 时逐步丢弃可选字段并显式标记 `truncated`，绝不写出
/// 超长或非法的单行，也绝不静默截断。
#[cfg(test)]
pub(super) fn encode_record(record: &CallLogRecord) -> Result<(String, bool)> {
    let prepared = PreparedRecord::new(record.clone())?;
    Ok((prepared.line, prepared.truncated))
}

/// 解析一行版本化 JSONL 记录；损坏的行返回错误而不猜测内容。
pub(super) fn decode_record(line: &str) -> Result<CallLogRecord> {
    ensure!(
        line.len() <= CALL_LOG_RECORD_MAX_BYTES,
        "oversized call log record"
    );
    let record: CallLogRecord = serde_json::from_str(line)?;
    ensure!(
        record.version == CALL_LOG_RECORD_VERSION,
        "unsupported call log record version"
    );
    Ok(record)
}

/// Stops encoding before allocating an unbounded diagnostic buffer.
pub(super) fn diagnostic(value: &impl serde::Serialize) -> (String, bool) {
    struct Bounded(Vec<u8>);
    impl std::io::Write for Bounded {
        fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
            let keep = bytes
                .len()
                .min((128 * 1024_usize).saturating_sub(self.0.len()));
            self.0.extend_from_slice(&bytes[..keep]);
            if keep < bytes.len() {
                return Err(std::io::Error::other("diagnostic truncated"));
            }
            Ok(keep)
        }
        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }
    let mut writer = Bounded(Vec::new());
    let truncated = serde_json::to_writer(&mut writer, value).is_err();
    (String::from_utf8_lossy(&writer.0).into_owned(), truncated)
}

pub(super) fn tool_record(
    thread_id: &str,
    turn_id: Option<String>,
    revision: i64,
    recorded_at: i64,
    delivery: &pl_core::thread::ToolDelivery,
) -> CallLogRecord {
    let (diagnostic, truncated) = diagnostic(delivery);
    let status = match delivery.outcome {
        pl_core::thread::ToolOutcome::Succeeded => "committed",
        pl_core::thread::ToolOutcome::Failed(_) => "failed",
        pl_core::thread::ToolOutcome::Cancelled => "cancelled",
        pl_core::thread::ToolOutcome::Interrupted => "interrupted",
    };
    CallLogRecord {
        version: CALL_LOG_RECORD_VERSION,
        kind: "tool".into(),
        thread_id: thread_id.into(),
        call_id: delivery.call_id.clone(),
        turn_id,
        revision,
        recorded_at,
        status: status.into(),
        terminal: true,
        diagnostic: Some(diagnostic),
        truncated,
        ..Default::default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn v1_log_record_identity_fields_convert_only_at_the_read_boundary() {
        let line = r#"{
            "version": 1,
            "kind": "billing",
            "threadId": "thread",
            "callId": "call",
            "status": "committed",
            "terminal": true,
            "revision": 3,
            "recordedAt": 11,
            "providerInstanceId": "deepseek",
            "providerDisplayName": "DeepSeek",
            "configuredModel": "deepseek-flash",
            "sentModel": "deepseek-flash",
            "reasoningEffort": "high",
            "usage": { "outputTokens": 12 }
        }"#;
        // 走真实解码门（日志读取与重建索引都经过它），而不是绕过版本检查的 serde 调用。
        let record = decode_record(line).expect("v1 record passes the current decode gate");
        assert_eq!(record.version, CALL_LOG_RECORD_VERSION);
        assert_eq!(record.account_display_name.as_deref(), Some("DeepSeek"));
        assert_eq!(record.model_id.as_deref(), Some("deepseek-flash"));
        assert_eq!(record.sent_model.as_deref(), Some("deepseek-flash"));
        assert_eq!(record.effort.as_deref(), Some("high"));
        assert_eq!(
            record.usage.as_ref().and_then(|usage| usage.output_tokens),
            Some(12)
        );
    }

    #[test]
    fn unknown_future_log_version_is_rejected_by_the_shared_gate() {
        let mut record = serde_json::json!({
            "version": CALL_LOG_RECORD_VERSION,
            "kind": "billing",
            "threadId": "thread",
            "callId": "call",
            "status": "committed",
            "terminal": true,
            "recordedAt": 11
        });
        assert!(decode_record(&record.to_string()).is_ok());
        record["version"] = (CALL_LOG_RECORD_VERSION + 1).into();
        assert!(decode_record(&record.to_string()).is_err());
    }

    #[test]
    fn v1_record_without_configured_model_keeps_identity_unknown() {
        let line = r#"{
            "version": 1,
            "kind": "billing",
            "threadId": "thread",
            "callId": "call",
            "status": "committed",
            "terminal": true,
            "recordedAt": 11,
            "providerInstanceId": "deepseek",
            "sentModel": "deepseek-flash"
        }"#;
        let record: CallLogRecord = serde_json::from_str(line).expect("v1 record decodes");
        assert!(
            record.model_id.is_none(),
            "sent model never becomes configured"
        );
        assert_eq!(record.sent_model.as_deref(), Some("deepseek-flash"));
    }
}
