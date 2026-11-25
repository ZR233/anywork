use super::*;

pub(super) fn committed_output<'a>(
    state: &'a ThreadSnapshot,
    attempt: &RequestAttempt,
) -> Option<&'a pl_core::context::ContextRecord> {
    let id = format!("{}:output", attempt.attempt_id);
    state.context.records.iter().find(|record| record.id == id)
}

/// 活动摘要：当前步骤文本的最新非空逻辑行（只读**有界尾部**），或活跃工具的命令行摘要。
pub(super) fn summary(
    state: &ThreadSnapshot,
    attempt: Option<&RequestAttempt>,
    foreground_turn: Option<&str>,
    kind: ThreadActivityKind,
    tools: &ThreadActivityTools,
    admitted: Option<&AdmittedActivity<'_>>,
) -> (String, bool) {
    let line = match kind {
        ThreadActivityKind::Thinking | ThreadActivityKind::Responding => {
            let Some(attempt) = attempt else {
                return (String::new(), false);
            };
            let stream = if kind == ThreadActivityKind::Responding {
                ObservedStream::Response
            } else {
                ObservedStream::Reasoning
            };
            let Some(line) = latest_stream_line(state, attempt, stream, admitted) else {
                return (String::new(), false);
            };
            // 有界尾部读取可能连行首一起截掉，此时摘要本身也如实标记为截断。
            let (summary, truncated) = bounded_summary(&line.text);
            return (summary, truncated || line.cut);
        }
        ThreadActivityKind::RunningTool
        | ThreadActivityKind::AwaitingApproval
        | ThreadActivityKind::Stopping => tools
            .active
            .iter()
            .rev()
            .find(|entry| {
                entry
                    .task_id
                    .as_ref()
                    .and_then(|id| state.tasks.get(id))
                    .is_some_and(|task| Some(task.turn_id.as_str()) == foreground_turn)
            })
            .map_or_else(String::new, |entry| entry.summary.clone()),
        ThreadActivityKind::Preparing
        | ThreadActivityKind::Compacting
        | ThreadActivityKind::Planning
        | ThreadActivityKind::WaitingApi
        | ThreadActivityKind::AwaitingInput => String::new(),
    };
    bounded_summary(&line)
}

/// 当前 attempt 最新的思考摘要（`ObservedStream::Summary`）；无摘要事实时返回 `None`。
pub(super) fn latest_thinking_summary(
    state: &ThreadSnapshot,
    attempt: Option<&RequestAttempt>,
    admitted: Option<&AdmittedActivity<'_>>,
) -> Option<String> {
    let attempt = attempt?;
    let progress = state
        .model_progress
        .as_ref()
        .filter(|progress| progress.attempt_id == attempt.attempt_id)?;
    for part in activity_parts(&progress.progress, admitted).rev() {
        if part.is_empty() || observed_stream(part) != Some(ObservedStream::Summary) {
            continue;
        }
        if let Some(text) = thinking_summary_block(part.content()) {
            return Some(text);
        }
    }
    None
}

/// 摘要尾部窗口的字节上限。
///
/// 摘要是“当前执行行”，因此只需要末尾有界字节：读取它的代价与已经流出的正文长度无关。窗口大于摘要
/// 上限若干倍，足以在不物化整段正文的前提下取到最新非空逻辑行。
pub(super) const ACTIVITY_SUMMARY_TAIL_BYTES: usize = 4096;

/// Shared by activity and timeline: summary facts only, never raw reasoning.
fn thinking_summary_block(block: &pl_core::model::ContentBlock) -> Option<String> {
    let window = block_tail(block)?;
    thinking_summary_line(&window.text)
}

fn thinking_summary_line(tail: &str) -> Option<String> {
    last_logical_line(tail)
        .map(|line| bounded_summary(line).0)
        .filter(|line| !line.is_empty())
}

/// 有界尾部：文本片段，以及该片段是否可能截掉了最后一行（或正文）的开头。
struct TailWindow {
    text: String,
    cut: bool,
}

/// 有界尾部里的一条逻辑行。
struct TailLine {
    text: String,
    cut: bool,
}

/// 当前 attempt 在某条流上的最新非空逻辑行；只读共享内容块的有界尾部。
///
/// 运行中的 attempt 直接读 owner 已发布的 typed 观察（[`ObservedPart`]）：每条观察都有自己的稳定身份
/// 与只追加内容块，因此这里只需要末尾有界字节，不按 token 复制整段正文。reasoning 完全没有可显示行
/// 时用 summary part 补充（它是 reasoning 的补充事实，不是另一段 raw 正文）。已提交的 attempt 用提交
/// 的输出正文（同样是尾部有界读取）。没有事实时返回 `None`——活动不会用历史正文冒充“当前正在输出的
/// 文本”。
fn latest_stream_line(
    state: &ThreadSnapshot,
    attempt: &RequestAttempt,
    stream: ObservedStream,
    admitted: Option<&AdmittedActivity<'_>>,
) -> Option<TailLine> {
    let Some(progress) = state
        .model_progress
        .as_ref()
        .filter(|progress| progress.attempt_id == attempt.attempt_id)
    else {
        return admitted
            .is_none()
            .then(|| committed_stream_line(state, attempt, stream))
            .flatten();
    };
    for part in activity_parts(&progress.progress, admitted).rev() {
        if part.is_empty() || observed_stream(part) != Some(stream) {
            continue;
        }
        if let Some(line) = observed_tail_line(part) {
            return Some(line);
        }
    }
    if stream != ObservedStream::Reasoning {
        return None;
    }
    for part in activity_parts(&progress.progress, admitted).rev() {
        if part.is_empty() || observed_stream(part) != Some(ObservedStream::Summary) {
            continue;
        }
        if let Some(line) = observed_tail_line(part) {
            return Some(line);
        }
    }
    None
}

/// 一条观察的有界尾部 → 最新非空逻辑行。
fn observed_tail_line(part: &ObservedPart) -> Option<TailLine> {
    tail_line(observed_tail(part)?)
}

/// 共享内容块的有界尾部：只物化末尾有界字节，不复制已观察的整段正文。
fn observed_tail(part: &ObservedPart) -> Option<TailWindow> {
    let block = part.content();
    block_tail(block)
}

fn block_tail(block: &pl_core::model::ContentBlock) -> Option<TailWindow> {
    let len = block.len();
    if len == 0 {
        return None;
    }
    let start = len.saturating_sub(ACTIVITY_SUMMARY_TAIL_BYTES);
    // `suffix_since` 只接受字符边界；UTF-8 字符最多 4 字节，因此最多向后试 4 个偏移即可命中边界。
    for offset in 0..4 {
        let candidate = start.saturating_add(offset);
        if candidate > len {
            break;
        }
        if let Some(text) = block.suffix_since(candidate) {
            return Some(TailWindow {
                text,
                cut: candidate > 0,
            });
        }
    }
    None
}

/// 已提交输出的最新非空逻辑行；提交输出只承载正文，没有 reasoning 事实。
fn committed_stream_line(
    state: &ThreadSnapshot,
    attempt: &RequestAttempt,
    stream: ObservedStream,
) -> Option<TailLine> {
    if stream != ObservedStream::Response {
        return None;
    }
    let output = committed_output(state, attempt)?;
    tail_line(committed_tail(&output.content)?)
}

/// 提交输出的有界尾部：只取末尾若干文本段的有界字节，不物化整段提交正文。
fn committed_tail(content: &[ContextContent]) -> Option<TailWindow> {
    // 只统计长度（O(文本段数)，不复制正文），用来判断窗口是否截掉了更早的正文。
    let total: usize = content
        .iter()
        .filter_map(|part| match part {
            ContextContent::Text { text } => Some(text.len()),
            _ => None,
        })
        .sum();
    if total == 0 {
        return None;
    }
    let mut pieces: Vec<&str> = Vec::new();
    let mut collected = 0usize;
    for part in content.iter().rev() {
        let ContextContent::Text { text } = part else {
            continue;
        };
        if text.is_empty() {
            continue;
        }
        let remaining = ACTIVITY_SUMMARY_TAIL_BYTES.saturating_sub(collected);
        if text.len() <= remaining {
            pieces.push(&**text);
            collected += text.len();
        } else {
            // 末尾窗口落在这一段内部：只取这一段的末尾 `remaining` 字节（对齐到字符边界），
            // 绝不复制更早的正文。
            let mut start = text.len() - remaining;
            while start < text.len() && !text.is_char_boundary(start) {
                start += 1;
            }
            pieces.push(&text[start..]);
            collected += text.len() - start;
        }
        if collected >= ACTIVITY_SUMMARY_TAIL_BYTES {
            // 窗口已填满，更早的文本段被主动放弃。
            break;
        }
    }
    if pieces.is_empty() {
        return None;
    }
    let mut text = String::with_capacity(collected.min(ACTIVITY_SUMMARY_TAIL_BYTES));
    for piece in pieces.iter().rev() {
        text.push_str(piece);
    }
    Some(TailWindow {
        cut: text.len() < total,
        text,
    })
}

/// 有界尾部 → 最新非空逻辑行；只有窗口里没有任何行边界时，最后一行才可能被窗口截掉行首。
fn tail_line(window: TailWindow) -> Option<TailLine> {
    let text = last_logical_line(&window.text)?.to_owned();
    let has_break = window.text.contains('\n') || window.text.contains('\r');
    Some(TailLine {
        text,
        cut: window.cut && !has_break,
    })
}

/// 一条活动观察所属的流。
///
/// `Summary` 是 reasoning item 的 summary part：它是 reasoning 的补充事实（没有 raw reasoning
/// 时才用于摘要），因此与 raw reasoning 分开聚合，不混成同一段正文。
/// 当前 attempt 是否已有输出正文 / reasoning 的流式事实。
///
/// 只检查每条观察的长度，因此活动分类不会为判断“是否在思考/回复”而物化任何正文。
#[derive(Clone, Copy, PartialEq, Eq)]
enum ObservedStream {
    Response,
    Reasoning,
    Summary,
}

fn observed_stream(part: &ObservedPart) -> Option<ObservedStream> {
    Some(match classify(part.identity())? {
        ObservedKind::Text(_) => ObservedStream::Response,
        ObservedKind::Reasoning => ObservedStream::Reasoning,
        ObservedKind::Summary => ObservedStream::Summary,
    })
}

pub(super) fn has_stream_facts(
    state: &ThreadSnapshot,
    attempt: &RequestAttempt,
    admitted: Option<&AdmittedActivity<'_>>,
) -> (bool, bool) {
    if let Some(view) = admitted {
        // Reliable admission owns activity, even before a bounded progress window has bytes.
        let mut response = false;
        let mut reasoning = false;
        for atom in view.atoms.iter().filter(|atom| {
            atom.attempt_id.as_deref() == Some(&attempt.attempt_id)
                && atom.turn_id.as_deref() == Some(&attempt.turn_id)
                && matches!(atom.lifecycle, crate::ChatAtomLifecycle::Active { .. })
        }) {
            response |= atom.kind == crate::ChatAtomKind::Text;
            reasoning |= atom.kind == crate::ChatAtomKind::Reasoning;
        }
        return (response, reasoning);
    }
    let Some(progress) = state
        .model_progress
        .as_ref()
        .filter(|progress| progress.attempt_id == attempt.attempt_id)
    else {
        return (false, false);
    };
    let mut response = false;
    let mut reasoning = false;
    for part in progress.progress.parts() {
        if part.is_empty() {
            continue;
        }
        match observed_stream(part) {
            Some(ObservedStream::Response) => response = true,
            Some(ObservedStream::Reasoning | ObservedStream::Summary) => reasoning = true,
            None => {}
        }
    }
    (response, reasoning)
}

/// 文本的最新非空逻辑行；`\n` / `\r` 都是行边界，尾部没有换行符的行同样参与。
fn last_logical_line(text: &str) -> Option<&str> {
    text.rsplit(['\n', '\r'])
        .map(str::trim)
        .find(|line| !line.is_empty())
}

/// 摘要按可见字符上限截断：(文本, 是否被截断)。
pub(in crate::studio::thread_projection) fn bounded_summary(text: &str) -> (String, bool) {
    let mut chars = text.chars();
    let summary = chars.by_ref().take(ACTIVITY_SUMMARY_LIMIT).collect();
    (summary, chars.next().is_some())
}
