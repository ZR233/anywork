use super::*;

/// 受理一次调用写入的轻量工作单元。
pub(super) enum CallMutation {
    /// 从 effect 提取的实际 attempt/delivery 记录，不携带全 effect 水位。
    Records(Vec<PreparedRecord>),
    Billing(Box<PreparedRecord>),
    Summary(PreparedSummary),
    AcpPerformance(Box<performance::PerformanceSample>),
}

impl CallMutation {
    /// 估算条目保留字节，用于队列与批次的压力预算；只序列化轻量记录。
    pub(super) fn estimated_bytes(&self) -> usize {
        match self {
            Self::Records(records) => {
                128 + records
                    .iter()
                    .map(PreparedRecord::retained_bytes)
                    .sum::<usize>()
            }
            Self::Billing(record) => record.retained_bytes(),
            Self::Summary(projection) => projection.bytes,
            Self::AcpPerformance(sample) => sample.retained_bytes(),
        }
    }
}

pub(super) struct PreparedSummary {
    pub(super) projection: SessionUsageProjection,
    pub(super) hash: String,
    pub(super) bytes: usize,
}
impl std::ops::Deref for PreparedSummary {
    type Target = SessionUsageProjection;
    fn deref(&self) -> &Self::Target {
        &self.projection
    }
}
impl PreparedSummary {
    pub(super) fn new(projection: SessionUsageProjection) -> Result<Self> {
        let encoded = serde_json::to_vec(&projection)?;
        Ok(Self {
            projection,
            hash: pl_core::context::content_hash(&encoded),
            bytes: encoded.len(),
        })
    }
}

/// The final (possibly truncated) fact and its bytes are selected before the queue lock.
/// SQL identity checks, JSONL and samples all consume this same fact.
pub(super) struct PreparedRecord {
    pub(super) record: CallLogRecord,
    pub(super) line: String,
    pub(super) hash: String,
    pub(super) truncated: bool,
    /// Bound to `record` after final truncation selection; never decoded from JSONL.
    pub(super) throughput_valid: bool,
}

impl std::ops::Deref for PreparedRecord {
    type Target = CallLogRecord;
    fn deref(&self) -> &Self::Target {
        &self.record
    }
}

impl PreparedRecord {
    pub(super) fn new(record: CallLogRecord) -> Result<Self> {
        Self::with_usage_analysis(record, pl_model::model::usage::analyze)
    }

    pub(super) fn with_usage_analysis(
        mut record: CallLogRecord,
        analyze: impl FnOnce(&crate::UsageReport) -> pl_core::usage::UsageAnalysis,
    ) -> Result<Self> {
        let analysis = if record.version == event::CALL_LOG_RECORD_VERSION
            && matches!(
                record.kind.as_str(),
                event::CALL_LOG_KIND_BILLING | event::CALL_LOG_KIND_MIGRATED
            )
            && record.usage_status != Some(pl_core::usage::UsageStatus::LegacyUnknown)
            && let Some(usage) = &record.usage
        {
            let analysis = analyze(&usage.report());
            record.usage_status = Some(analysis.status);
            Some(analysis)
        } else {
            None
        };
        let mut line = serde_json::to_string(&record)?;
        if line.len() >= event::CALL_LOG_RECORD_MAX_BYTES {
            record = record.truncated_fallback();
            line = serde_json::to_string(&record)?;
        }
        ensure!(
            line.len() < event::CALL_LOG_RECORD_MAX_BYTES,
            "call identity exceeds log record budget"
        );
        // Derive the pair only after selecting the final fact. Fallback keeps the explanatory
        // status but has neither the raw numerator nor timing, so it cannot inherit a valid pair.
        let throughput_valid = analysis
            .as_ref()
            .is_some_and(|analysis| record.throughput_sample_with_analysis(analysis).is_some());
        let hash = pl_core::context::content_hash(line.as_bytes());
        let truncated = record.truncated;
        Ok(Self {
            record,
            line,
            hash,
            truncated,
            throughput_valid,
        })
    }

    pub(super) fn retained_bytes(&self) -> usize {
        self.line.len() + 1 + std::mem::size_of::<bool>()
    }
}

#[derive(Default)]
pub(super) struct MutationQueue {
    pub(super) entries: VecDeque<QueuedCallMutation>,
    pub(super) bytes: usize,
    pub(super) billing: BTreeMap<(String, String, String), BTreeMap<u64, String>>,
}
impl std::ops::Deref for MutationQueue {
    type Target = VecDeque<QueuedCallMutation>;
    fn deref(&self) -> &Self::Target {
        &self.entries
    }
}
impl MutationQueue {
    pub(super) fn push_back(&mut self, entry: QueuedCallMutation) {
        self.index_billing(&entry);
        self.bytes += entry.bytes;
        self.entries.push_back(entry);
    }
    fn push_front(&mut self, entry: QueuedCallMutation) {
        self.index_billing(&entry);
        self.bytes += entry.bytes;
        self.entries.push_front(entry);
    }
    fn pop_front(&mut self) -> Option<QueuedCallMutation> {
        let entry = self.entries.pop_front()?;
        self.bytes -= entry.bytes;
        if let CallMutation::Billing(record) = &entry.mutation {
            let key = (
                record.thread_id.clone(),
                record.call_id.clone(),
                record.kind.clone(),
            );
            if let Some(tickets) = self.billing.get_mut(&key) {
                tickets.remove(&entry.ticket);
                if tickets.is_empty() {
                    self.billing.remove(&key);
                }
            }
        }
        Some(entry)
    }
    fn index_billing(&mut self, entry: &QueuedCallMutation) {
        if let CallMutation::Billing(record) = &entry.mutation {
            self.billing
                .entry((
                    record.thread_id.clone(),
                    record.call_id.clone(),
                    record.kind.clone(),
                ))
                .or_default()
                .insert(entry.ticket, record.hash.clone());
        }
    }
    pub(super) fn retain(&mut self, mut keep: impl FnMut(&QueuedCallMutation) -> bool) {
        let bytes = &mut self.bytes;
        let billing = &mut self.billing;
        self.entries.retain(|entry| {
            if keep(entry) {
                true
            } else {
                *bytes -= entry.bytes;
                if let CallMutation::Billing(record) = &entry.mutation {
                    let key = (
                        record.thread_id.clone(),
                        record.call_id.clone(),
                        record.kind.clone(),
                    );
                    if let Some(tickets) = billing.get_mut(&key) {
                        tickets.remove(&entry.ticket);
                        if tickets.is_empty() {
                            billing.remove(&key);
                        }
                    }
                }
                false
            }
        });
    }
}

pub(super) struct QueuedCallMutation {
    pub(super) ticket: u64,
    pub(super) accepted_at: tokio::time::Instant,
    pub(super) bytes: usize,
    pub(super) mutation: CallMutation,
}

#[derive(Debug, Clone, Copy, Default)]
pub(super) struct QueuePressure {
    pub(super) mutations: usize,
    pub(super) bytes: usize,
    pub(super) oldest_accepted_at: Option<tokio::time::Instant>,
}

/// 从队首按条目/字节预算取一批 entry；保持 FIFO 顺序。
pub(super) fn drain_batch(shared: &CallsWriter) -> Vec<QueuedCallMutation> {
    let mut queue = shared
        .queue
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    let mut entries = Vec::with_capacity(MAX_BATCH_MUTATIONS.min(queue.len().max(1)));
    let mut bytes = 0usize;
    while entries.len() < MAX_BATCH_MUTATIONS {
        let Some(front) = queue.front() else {
            break;
        };
        let next_bytes = bytes.saturating_add(front.bytes);
        if !entries.is_empty() && next_bytes > MAX_BATCH_BYTES {
            break;
        }
        bytes = next_bytes;
        #[cfg(feature = "benchmarks")]
        shared.observation.dequeued(front.accepted_at.elapsed());
        entries.push(queue.pop_front().expect("front entry checked"));
    }
    entries
}

/// 瞬时失败后把未完成条目按原顺序放回队首等待重试。
pub(super) fn requeue(shared: &CallsWriter, entries: VecDeque<QueuedCallMutation>) {
    let mut queue = shared
        .queue
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    for entry in entries.into_iter().rev() {
        queue.push_front(entry);
    }
}

pub(super) fn queue_bytes(queue: &MutationQueue) -> usize {
    queue.bytes
}

pub(super) fn queue_pressure(shared: &CallsWriter) -> QueuePressure {
    let queue = shared
        .queue
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    QueuePressure {
        mutations: queue.len(),
        bytes: queue.bytes,
        oldest_accepted_at: queue.front().map(|entry| entry.accepted_at),
    }
}
