use std::collections::VecDeque;

/// 保留输出前缀和后缀的有界缓冲。
#[derive(Debug)]
pub(super) struct HeadTailBuffer {
    decoder: Option<encoding_rs::Decoder>,
    text_lossy: bool,
    max_bytes: usize,
    head_budget: usize,
    tail_budget: usize,
    head: VecDeque<Vec<u8>>,
    tail: VecDeque<Vec<u8>>,
    head_bytes: usize,
    tail_bytes: usize,
    omitted_bytes: usize,
}

impl HeadTailBuffer {
    pub(super) fn new(max_bytes: usize) -> Self {
        let head_budget = max_bytes / 2;
        let tail_budget = max_bytes.saturating_sub(head_budget);
        Self {
            decoder: Some(encoding_rs::UTF_8.new_decoder_without_bom_handling()),
            text_lossy: false,
            max_bytes,
            head_budget,
            tail_budget,
            head: VecDeque::new(),
            tail: VecDeque::new(),
            head_bytes: 0,
            tail_bytes: 0,
            omitted_bytes: 0,
        }
    }

    pub(super) fn text_lossy(&self) -> bool {
        self.text_lossy
    }
    pub(super) fn finish_text(&mut self) {
        if let Some(mut decoder) = self.decoder.take() {
            let mut text = String::with_capacity(4);
            let (_, _, lossy) = decoder.decode_to_string(b"", &mut text, true);
            self.text_lossy |= lossy;
        }
    }
    pub(super) fn push_chunk(&mut self, chunk: &[u8]) {
        if let Some(decoder) = &mut self.decoder {
            let mut text = String::with_capacity(chunk.len().saturating_mul(3).saturating_add(4));
            let (_, _, lossy) = decoder.decode_to_string(chunk, &mut text, false);
            self.text_lossy |= lossy;
        }
        if chunk.is_empty() {
            return;
        }
        if self.max_bytes == 0 {
            self.omitted_bytes = self.omitted_bytes.saturating_add(chunk.len());
            return;
        }
        if self.head_bytes < self.head_budget {
            let remaining_head = self.head_budget.saturating_sub(self.head_bytes);
            if chunk.len() <= remaining_head {
                self.head_bytes = self.head_bytes.saturating_add(chunk.len());
                self.head.push_back(chunk.to_vec());
                return;
            }
            let (head_part, tail_part) = chunk.split_at(remaining_head);
            if !head_part.is_empty() {
                self.head_bytes = self.head_bytes.saturating_add(head_part.len());
                self.head.push_back(head_part.to_vec());
            }
            self.push_to_tail(tail_part.to_vec());
            return;
        }
        self.push_to_tail(chunk.to_vec());
    }

    pub(super) fn excerpt(&self) -> pl_output::OutputExcerpt {
        let mut head = Vec::with_capacity(self.head_bytes);
        let mut tail = Vec::with_capacity(self.tail_bytes);
        for chunk in &self.head {
            head.extend_from_slice(chunk);
        }
        for chunk in &self.tail {
            tail.extend_from_slice(chunk);
        }
        let mut omitted = self.omitted_bytes;
        if omitted > 0 {
            // The bounded window may cut a valid code point. Those boundary bytes are omitted,
            // rather than shown as decoding errors in an otherwise valid source stream.
            let mut cursor = 0;
            while cursor < head.len() {
                match std::str::from_utf8(&head[cursor..]) {
                    Ok(_) => break,
                    Err(error) => match error.error_len() {
                        Some(length) => cursor += error.valid_up_to() + length,
                        None => {
                            let end = cursor + error.valid_up_to();
                            omitted += head.len() - end;
                            head.truncate(end);
                            break;
                        }
                    },
                }
            }
            let skip = tail
                .iter()
                .take(3)
                .take_while(|byte| (**byte & 0xc0) == 0x80)
                .count();
            tail.drain(..skip);
            omitted += skip;
        }
        pl_output::OutputExcerpt::from_parts(head, tail, omitted)
    }

    pub(super) fn take_excerpt(&mut self) -> pl_output::OutputExcerpt {
        let replacement = Self::new(self.max_bytes);
        std::mem::replace(self, replacement).excerpt()
    }

    pub(super) fn total_bytes(&self) -> usize {
        self.head_bytes
            .saturating_add(self.tail_bytes)
            .saturating_add(self.omitted_bytes)
    }

    fn push_to_tail(&mut self, chunk: Vec<u8>) {
        if self.tail_budget == 0 {
            self.omitted_bytes = self.omitted_bytes.saturating_add(chunk.len());
            return;
        }
        if chunk.len() >= self.tail_budget {
            let start = chunk.len().saturating_sub(self.tail_budget);
            let kept = chunk[start..].to_vec();
            let dropped = chunk.len().saturating_sub(kept.len());
            self.omitted_bytes = self
                .omitted_bytes
                .saturating_add(self.tail_bytes)
                .saturating_add(dropped);
            self.tail.clear();
            self.tail_bytes = kept.len();
            self.tail.push_back(kept);
            return;
        }
        self.tail_bytes = self.tail_bytes.saturating_add(chunk.len());
        self.tail.push_back(chunk);
        self.trim_tail_to_budget();
    }

    fn trim_tail_to_budget(&mut self) {
        let mut excess = self.tail_bytes.saturating_sub(self.tail_budget);
        while excess > 0 {
            match self.tail.front_mut() {
                Some(front) if excess >= front.len() => {
                    excess -= front.len();
                    self.tail_bytes = self.tail_bytes.saturating_sub(front.len());
                    self.omitted_bytes = self.omitted_bytes.saturating_add(front.len());
                    self.tail.pop_front();
                }
                Some(front) => {
                    front.drain(..excess);
                    self.tail_bytes = self.tail_bytes.saturating_sub(excess);
                    self.omitted_bytes = self.omitted_bytes.saturating_add(excess);
                    break;
                }
                None => break,
            }
        }
    }
}
