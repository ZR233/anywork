//! 对已有头尾片段做一次严格包含省略行的 UTF-8 字节预算投影。
use super::TruncatedOutput;

// 原始字节长度由 original_length 表达；lossy 解码后的展示不冒充原始字节计量。
const MARKER: &str = "\n\n... [output omitted] ...\n\n";

/// 有界 producer 留下的原始头尾与省略事实，尚未插入展示标记。
#[derive(Debug, Clone)]
pub struct OutputExcerpt {
    head: String,
    tail: String,
    omitted_bytes: usize,
    original_length: usize,
}

impl OutputExcerpt {
    /// 接管原始字节；连续片段先拼接再解码，避免在片段边界破坏多字节字符。
    pub fn from_parts(mut head: Vec<u8>, tail: Vec<u8>, omitted_bytes: usize) -> Self {
        let original_length = head
            .len()
            .saturating_add(tail.len())
            .saturating_add(omitted_bytes);
        let (head, tail) = if omitted_bytes == 0 {
            head.extend_from_slice(&tail);
            (decode(head), String::new())
        } else {
            (decode(head), decode(tail))
        };
        Self {
            head,
            tail,
            omitted_bytes,
            original_length,
        }
    }

    /// 不受额外预算约束时，正文与唯一省略行合计的字节数。
    pub fn display_len(&self) -> usize {
        self.head
            .len()
            .saturating_add(self.tail.len())
            .saturating_add(if self.omitted_bytes == 0 {
                0
            } else {
                MARKER.len()
            })
    }

    /// 整段输出（含省略行）不超过 `max_bytes`；边界始终落在 UTF-8 字符之间。
    pub fn project(self, max_bytes: usize) -> TruncatedOutput {
        self.project_with_omission(max_bytes).0
    }

    /// Returns the generated omission marker's byte range separately from source text.
    /// Consumers can account for omitted source bytes without mistaking marker bytes for output.
    pub fn project_with_omission(
        self,
        max_bytes: usize,
    ) -> (TruncatedOutput, Option<std::ops::Range<usize>>) {
        let available = self.head.len().saturating_add(self.tail.len());
        if self.omitted_bytes == 0 && available <= max_bytes {
            return (
                TruncatedOutput {
                    content: self.head,
                    was_truncated: false,
                    original_length: self.original_length,
                },
                None,
            );
        }
        if max_bytes < MARKER.len() {
            let end = self
                .head
                .floor_char_boundary(max_bytes.min(self.head.len()));
            return (
                TruncatedOutput {
                    content: self.head[..end].into(),
                    was_truncated: true,
                    original_length: self.original_length,
                },
                None,
            );
        }
        let payload = max_bytes - MARKER.len();
        let head_budget = payload / 2;
        let tail_budget = payload - head_budget;
        let head_end = self
            .head
            .floor_char_boundary(head_budget.min(self.head.len()));
        let tail_source = if self.omitted_bytes == 0 {
            &self.head
        } else {
            &self.tail
        };
        let tail_start =
            tail_source.ceil_char_boundary(tail_source.len().saturating_sub(tail_budget));
        let mut content =
            String::with_capacity(head_end + MARKER.len() + tail_source.len() - tail_start);
        content.push_str(&self.head[..head_end]);
        content.push_str(MARKER);
        content.push_str(&tail_source[tail_start..]);
        (
            TruncatedOutput {
                content,
                was_truncated: true,
                original_length: self.original_length,
            },
            Some(head_end..head_end + MARKER.len()),
        )
    }
}

fn decode(bytes: Vec<u8>) -> String {
    match String::from_utf8(bytes) {
        Ok(text) => text,
        Err(error) => String::from_utf8_lossy(error.as_bytes()).into_owned(),
    }
}
