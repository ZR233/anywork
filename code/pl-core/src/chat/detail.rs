//! Explicit content manifests and true bounded byte ranges, independent of product payloads.

use crate::{
    chat::{ChatError, ChatKey, ReadDemand, TimelineEpoch},
    model::ContentBlock,
};
use std::{ops::Range, sync::Arc};

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct ChatContentKey {
    pub owner: ChatKey,
    pub key: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ContentDescriptor {
    pub key: ChatContentKey,
    pub byte_length: u64,
    pub generation: u64,
    pub media_type: Option<String>,
}

/// A sealed text owner with a shared byte-offset index built once at ownership handoff.
#[derive(Debug, Clone)]
pub struct IndexedText {
    block: Arc<ContentBlock>,
    chunks: Arc<[(usize, Arc<str>)]>,
}

impl IndexedText {
    pub fn new(block: Arc<ContentBlock>) -> Self {
        let chunks = block.shared_chunks().into();
        Self { block, chunks }
    }

    pub fn block(&self) -> &Arc<ContentBlock> {
        &self.block
    }

    pub fn len(&self) -> usize {
        self.block.len()
    }

    pub fn is_empty(&self) -> bool {
        self.block.is_empty()
    }

    fn bytes(&self) -> impl Iterator<Item = &u8> {
        self.chunks.iter().flat_map(|(_, chunk)| chunk.as_bytes())
    }

    fn range(&self, start: usize, len: usize) -> ContentBytes {
        self.range_with_visit(start, len, || {})
    }

    fn range_with_visit(&self, start: usize, len: usize, mut visit: impl FnMut()) -> ContentBytes {
        let end = start + len;
        let mut bytes = Vec::with_capacity(len);
        if len != 0 {
            let first = self
                .chunks
                .partition_point(|(offset, _)| *offset <= start)
                .saturating_sub(1);
            for (offset, chunk) in &self.chunks[first..] {
                if *offset >= end {
                    break;
                }
                visit();
                let from = start.saturating_sub(*offset);
                let through = (end - offset).min(chunk.len());
                bytes.extend_from_slice(&chunk.as_bytes()[from..through]);
            }
        }
        ContentBytes::from(Arc::<[u8]>::from(bytes))
    }
}

impl PartialEq for IndexedText {
    fn eq(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.block, &other.block)
            || (self.len() == other.len() && self.bytes().eq(other.bytes()))
    }
}

impl Eq for IndexedText {}

/// Model chunks are indexed without flattening. Binary bodies retain shared immutable storage.
/// Neither representation is copied by page queries.
#[derive(Debug, Clone)]
pub enum ContentData {
    Text(Arc<IndexedText>),
    Bytes(Arc<[u8]>),
}
impl ContentData {
    pub fn text(block: Arc<ContentBlock>) -> Self {
        Self::Text(Arc::new(IndexedText::new(block)))
    }

    pub fn len(&self) -> usize {
        match self {
            Self::Text(block) => block.len(),
            Self::Bytes(bytes) => bytes.len(),
        }
    }
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
    pub fn range(&self, offset: u64, max_bytes: usize) -> Result<ContentBytes, ChatError> {
        let start = checked_start(offset, self.len())?;
        let len = max_bytes.min(self.len() - start);
        match self {
            Self::Bytes(bytes) => Ok(ContentBytes {
                storage: bytes.clone(),
                range: start..start + len,
            }),
            Self::Text(text) => Ok(text.range(start, len)),
        }
    }
}

// Storage may materialize a text owner as binary chunks. Immutable identity is the byte sequence,
// not its in-memory representation or the boundaries the producer originally appended at.
impl PartialEq for ContentData {
    fn eq(&self, other: &Self) -> bool {
        match (self, other) {
            (Self::Text(left), Self::Text(right)) => left == right,
            (Self::Bytes(left), Self::Bytes(right)) => left == right,
            (Self::Text(text), Self::Bytes(bytes)) | (Self::Bytes(bytes), Self::Text(text)) => {
                text.len() == bytes.len() && text.bytes().eq(bytes.iter())
            }
        }
    }
}

impl Eq for ContentData {}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatContent {
    pub descriptor: ContentDescriptor,
    pub data: ContentData,
}

/// An accepted range can keep its original Arc alive after commit/clear, without copying a payload.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ContentBytes {
    pub storage: Arc<[u8]>,
    pub range: Range<usize>,
}
impl ContentBytes {
    pub fn as_bytes(&self) -> &[u8] {
        &self.storage[self.range.clone()]
    }
}
impl From<Arc<[u8]>> for ContentBytes {
    fn from(storage: Arc<[u8]>) -> Self {
        let end = storage.len();
        Self {
            storage,
            range: 0..end,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ContentRef {
    ItemPayload(String),
    Body(ChatContentKey),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ContentReadRequest {
    pub epoch: TimelineEpoch,
    pub reference: ContentRef,
    pub offset: u64,
    pub max_bytes: usize,
    pub generation: Option<u64>,
}
impl ContentReadRequest {
    pub(crate) fn validate(&self) -> Result<(), ChatError> {
        if !(1..=super::MAX_READ_BYTES).contains(&self.max_bytes) {
            return Err(ChatError::InvalidDemand(
                "invalid content range size".into(),
            ));
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ContentWindow {
    pub offset: u64,
    pub bytes: ContentBytes,
    pub generation: u64,
    pub available_through: u64,
    pub sealed: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ContentManifestRequest {
    pub epoch: TimelineEpoch,
    pub item_id: String,
    pub after: Option<ChatContentKey>,
    pub demand: ReadDemand,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ContentManifestPage {
    pub entries: Vec<ContentDescriptor>,
    pub next: Option<ChatContentKey>,
}

pub(crate) fn checked_start(offset: u64, len: usize) -> Result<usize, ChatError> {
    usize::try_from(offset)
        .ok()
        .filter(|start| *start <= len)
        .ok_or_else(|| ChatError::InvalidArgument("content offset exceeds length".into()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn indexed_suffix_and_boundary_reads_visit_only_the_target_chunks() {
        for count in [2, 128, 8192] {
            let mut block = ContentBlock::empty();
            for _ in 0..count {
                block = ContentBlock::append(&block, "汉📖");
            }
            let text = IndexedText::new(block.clone());
            assert!(Arc::ptr_eq(text.block(), &block));
            assert_eq!(text.chunks.len(), count);
            for (start, len, expected_visits, expected) in [
                (text.len() - 1, 1, 1, &"📖".as_bytes()[3..]),
                (0, 1, 1, &"汉".as_bytes()[..1]),
                (6, 2, 2, &[0x96, 0xe6][..]),
                (text.len(), 0, 0, &[][..]),
            ] {
                let mut visited = 0;
                let window = text.range_with_visit(start, len, || visited += 1);
                assert_eq!(window.as_bytes(), expected);
                assert_eq!(
                    visited,
                    expected_visits,
                    "range {start}..{} in {count} chunks",
                    start + len
                );
            }
        }
    }

    #[test]
    fn indexed_ranges_handle_empty_eof_and_split_code_points_without_widening() {
        let empty = IndexedText::new(ContentBlock::empty());
        let mut visited = 0;
        assert!(
            empty
                .range_with_visit(0, 0, || visited += 1)
                .as_bytes()
                .is_empty()
        );
        assert_eq!(visited, 0);
        let chunks = ["汉", "📖", "abc", "语"];
        let body = chunks.concat();
        let mut block = ContentBlock::empty();
        for chunk in chunks {
            block = ContentBlock::append(&block, chunk);
        }
        let data = ContentData::text(block);
        for offset in 0..=body.len() {
            for size in [0, 1, 2, 5, usize::MAX] {
                let window = data.range(offset as u64, size).unwrap();
                let end = offset.saturating_add(size).min(body.len());
                assert_eq!(window.as_bytes(), &body.as_bytes()[offset..end]);
            }
        }
        assert!(matches!(
            data.range(body.len() as u64 + 1, 1),
            Err(ChatError::InvalidArgument(_))
        ));
    }
}
