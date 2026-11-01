//! Product-independent immutable completion records. Payload bytes are never interpreted by Core.

use std::{collections::BTreeMap, fmt::Write as _, sync::Arc};

use crate::chat::{ChatContent, ChatContentKey, ChatError};

/// A provider part's identity does not depend on late output indexes or part IDs.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum PresentationPart {
    OutputText(u32),
    ReasoningText(u32),
    SummaryText(u32),
}

pub fn presentation_prefix(attempt_id: &str) -> String {
    let mut prefix = String::with_capacity(attempt_id.len() + PRESENTATION_PREFIX_BYTES);
    write_presentation_prefix(&mut prefix, attempt_id);
    prefix
}

pub fn presentation_item_id(
    attempt_id: &str,
    generation: u32,
    provider_item_id: &str,
    part: Option<PresentationPart>,
) -> String {
    let mut base = String::with_capacity(
        PRESENTATION_PREFIX_BYTES + attempt_id.len() + provider_item_id.len(),
    );
    write_presentation_prefix(&mut base, attempt_id);
    if generation != 0 {
        let _ = write!(base, "generation:{generation}:");
    }
    let _ = write!(base, "{}:{provider_item_id}", provider_item_id.len());
    match part {
        Some(PresentationPart::OutputText(index)) => {
            let _ = write!(base, ":text:{index}");
        }
        Some(PresentationPart::ReasoningText(index)) => {
            let _ = write!(base, ":reasoning:{index}");
        }
        Some(PresentationPart::SummaryText(index)) => {
            let _ = write!(base, ":summary:{index}");
        }
        None => base.push_str(":empty"),
    }
    base
}

const PRESENTATION_PREFIX_BYTES: usize = "model::presentation:item:".len();
fn write_presentation_prefix(id: &mut String, attempt_id: &str) {
    let _ = write!(
        id,
        "model:{}:{attempt_id}:presentation:item:",
        attempt_id.len()
    );
}

/// Unambiguous typed identity, also usable as a persisted parent/owner key.
/// Core does not assign meaning to the domain or require a parent to be a completion item.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct ChatKey(String);

impl ChatKey {
    pub fn new(domain: &str, id: &str) -> Result<Self, ChatError> {
        if domain.is_empty() || id.is_empty() {
            return Err(ChatError::InvalidArgument(
                "empty identity domain or id".into(),
            ));
        }
        Ok(Self(format!("{}:{domain}{id}", domain.len())))
    }

    pub fn from_encoded(encoded: String) -> Result<Self, ChatError> {
        let valid = encoded.split_once(':').is_some_and(|(prefix, rest)| {
            prefix.parse::<usize>().ok().is_some_and(|length| {
                length > 0
                    && length < rest.len()
                    && rest.is_char_boundary(length)
                    && length.to_string() == prefix
            })
        });
        if !valid {
            return Err(ChatError::InvalidArgument("invalid typed identity".into()));
        }
        Ok(Self(encoded))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// Query membership only. A missing parent selects the whole class, not just NULL parents.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct ChatQuery {
    pub query_class: String,
    pub parent_id: Option<ChatKey>,
}

impl ChatQuery {
    pub fn new(query_class: impl Into<String>, parent_id: Option<ChatKey>) -> Self {
        Self {
            query_class: query_class.into(),
            parent_id,
        }
    }

    pub fn matches(&self, header: &ChatItemHeader) -> bool {
        self.query_class == header.query_class
            && self
                .parent_id
                .as_ref()
                .is_none_or(|parent| Some(parent) == header.parent_id.as_ref())
    }

    pub(crate) fn validate(&self) -> Result<(), ChatError> {
        if self.query_class.is_empty() {
            return Err(ChatError::InvalidArgument("empty query class".into()));
        }
        Ok(())
    }
}

/// Lightweight indexed columns plus length(payload); obtaining this must not fetch the payload.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatItemHeader {
    pub append_seq: u64,
    pub item_id: String,
    pub query_class: String,
    pub parent_id: Option<ChatKey>,
    pub byte_length: u64,
}

/// Producer-supplied, immutable content ownership. Normal pages never clone this manifest.
pub type ChatContents = BTreeMap<ChatContentKey, Arc<ChatContent>>;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatDraft {
    pub item_id: String,
    pub query_class: String,
    pub parent_id: Option<ChatKey>,
    pub payload: Arc<[u8]>,
    pub contents: Arc<ChatContents>,
}

impl ChatDraft {
    pub fn new(
        item_id: impl Into<String>,
        query_class: impl Into<String>,
        payload: Arc<[u8]>,
    ) -> Self {
        Self {
            item_id: item_id.into(),
            query_class: query_class.into(),
            parent_id: None,
            payload,
            contents: Arc::new(BTreeMap::new()),
        }
    }

    pub(crate) fn validate(&self) -> Result<(), ChatError> {
        if self.item_id.is_empty() || self.query_class.is_empty() {
            return Err(ChatError::InvalidArgument(
                "empty item identity or query class".into(),
            ));
        }
        for (key, content) in self.contents.iter() {
            if key != &content.descriptor.key
                || content.descriptor.byte_length != content.data.len() as u64
            {
                return Err(ChatError::InvalidArgument(
                    "inconsistent content manifest".into(),
                ));
            }
        }
        Ok(())
    }
}

/// The same frozen allocation is retained by pending and handed to the original writer.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatItem {
    pub header: ChatItemHeader,
    pub payload: Arc<[u8]>,
    pub contents: Arc<ChatContents>,
}

impl ChatItem {
    pub fn complete(draft: ChatDraft, append_seq: u64) -> Self {
        Self {
            header: ChatItemHeader {
                append_seq,
                item_id: draft.item_id,
                query_class: draft.query_class,
                parent_id: draft.parent_id,
                byte_length: draft.payload.len() as u64,
            },
            payload: draft.payload,
            contents: draft.contents,
        }
    }
}

pub(crate) fn draft_matches_record(draft: &ChatDraft, record: &ChatItem) -> bool {
    draft.item_id == record.header.item_id
        && draft.query_class == record.header.query_class
        && draft.parent_id == record.header.parent_id
        && draft.payload == record.payload
        && draft.contents == record.contents
}
