//! Typed FRB mirror of the canonical current-activity projection.
//!
//! 活动正文通过有界 begin/text/commit 事件直接交付；分块 staging 与当前态归约归 SDK。

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeActivityTextRegion {
    Reasoning { item_id: String },
    Response { item_id: String },
    ToolArguments { call_id: String },
    ToolOutput { call_id: String, part_id: String },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeActivityPartMetadata {
    pub item_id: String,
    pub complete: bool,
    pub total_bytes: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeActivityToolMetadata {
    pub call_id: String,
    pub task_id: Option<String>,
    pub name: String,
    pub state: BridgeThreadActivityToolState,
    pub started_at: Option<i64>,
    pub source_order: Option<u64>,
    pub arguments_bytes: Option<u64>,
    pub output_bytes: Option<u64>,
    pub output_parts: Vec<BridgeActivityToolOutputMetadata>,
    pub wait: Option<super::BridgeThreadWaitPresentation>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeActivityToolOutputMetadata {
    pub part_id: String,
    pub total_bytes: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeActivityTextOperation {
    Append {
        region: BridgeActivityTextRegion,
        text: String,
    },
    Replace {
        region: BridgeActivityTextRegion,
        text: String,
    },
    Remove {
        region: BridgeActivityTextRegion,
    },
}

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeActivityContentFrame {
    Begin {
        generation: String,
        base_revision: Option<u64>,
        revision: u64,
        activity: Option<Box<BridgeThreadActivity>>,
        reasoning: Vec<BridgeActivityPartMetadata>,
        response: Vec<BridgeActivityPartMetadata>,
        tools: Vec<BridgeActivityToolMetadata>,
        total_bytes: u64,
    },
    Text {
        generation: String,
        revision: u64,
        operations: Vec<BridgeActivityTextOperation>,
    },
    Commit {
        generation: String,
        revision: u64,
    },
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeThreadActivity {
    pub thread_id: String,
    pub identity: String,
    pub revision: u64,
    pub turn_id: Option<String>,
    pub execution_id: Option<String>,
    pub input_id: Option<String>,
    pub attempt_id: Option<String>,
    pub kind: BridgeThreadActivityKind,
    pub summary: String,
    pub summary_truncated: bool,
    pub thinking_summary: Option<String>,
    pub thinking_seconds: Option<u64>,
    pub tools: BridgeThreadActivityTools,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeThreadActivityKind {
    Preparing,
    Compacting,
    WaitingApi,
    Thinking,
    Responding,
    Planning,
    RunningTool,
    AwaitingApproval,
    AwaitingInput,
    Stopping,
}

/// 活跃工具参数事实的可用程度：命令行摘要在参数不完整或无法提取时回落工具名称。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeThreadActivityArguments {
    CommandLine,
    Opaque,
    Streaming,
    Unavailable,
}

/// 一条工具调用的执行状态；活动条目只会取到前三个变体，终态调用是 `finished`。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeThreadActivityToolState {
    Running,
    AwaitingApproval,
    Cancelling,
    Finished,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadActivityToolEntry {
    pub call_id: String,
    pub task_id: Option<String>,
    pub name: String,
    pub summary: String,
    pub arguments: BridgeThreadActivityArguments,
    pub state: BridgeThreadActivityToolState,
    pub ordinal: Option<u64>,
    pub started_at: Option<i64>,
    pub wait: Option<super::BridgeThreadWaitPresentation>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct BridgeThreadActivityTools {
    pub count: u32,
    /// 其中处于后台的活跃工具数量；前台就是工具本身时为 0。
    pub background: u32,
    pub active: Vec<BridgeThreadActivityToolEntry>,
    pub latest_started: Option<BridgeThreadActivityToolEntry>,
}

/// Thread 存储状态；所有字段都是 typed 事实，缺失表示未知而不是零。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadStorageState {
    pub fault: Option<BridgeHistoryFault>,
    pub fault_generation: u64,
    pub accepted_sequence: Option<u64>,
    pub durable_sequence: Option<u64>,
    pub execution: BridgeThreadStorageExecution,
    pub pressure_paused: bool,
    /// 硬故障是否仍闩住新准入，必须由用户显式 `resume_thread_history` 继续。
    ///
    /// `pressure_paused` 是自动恢复的背压；本字段为 `true` 时重试保存成功也不会自动继续。
    pub resume_required: bool,
    /// 现在显式继续是否真的会被后端接受。
    ///
    /// `resume_required` 只说明故障闩住了准入；本字段还要求恢复已被核验（保存重试的目标水位已
    /// durable、没有仍在报告的硬故障、没有未上交批次、也没有字节阈值挡住）。UI 只能用本字段启用
    /// “继续”；后端 resume 仍会重查，所以它不是前端推断。
    pub can_resume: bool,
    /// core 提供的原始错误文本；它不是故障类别的来源。
    pub last_error: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeHistoryFault {
    QueueFull,
    WriteFailed,
    WriterUnavailable,
    NoProgress,
    CheckpointFailed,
    BlobFailed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeThreadStorageExecution {
    Running,
    Pausing,
    Paused,
}
