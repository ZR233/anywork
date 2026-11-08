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

/// Product-independent visibility and adjacent-run membership. Keys are opaque to Core.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub enum ChatReadHint {
    #[default]
    Hidden,
    Single,
    Adjacent {
        key: ChatKey,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ChatRunPosition {
    pub start_seq: u64,
    pub ordinal: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatRunSeed {
    pub seq: u64,
    pub hint: ChatReadHint,
    pub position: ChatRunPosition,
}

/// One cold snapshot's publication head and last visible record, never a retained group.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ChatPublicationSeed {
    pub head_seq: u64,
    pub last_visible: Option<ChatRunSeed>,
}

impl ChatPublicationSeed {
    pub fn validate(&self) -> Result<(), ChatError> {
        if self.head_seq > i64::MAX as u64 {
            return Err(ChatError::SeqExhausted);
        }
        if let Some(last) = &self.last_visible {
            validate_run(last.seq, &last.hint, Some(last.position))?;
            if last.seq > self.head_seq {
                return Err(ChatError::Conflict("visible seed exceeds head".into()));
            }
        }
        Ok(())
    }

    /// Checked allocation shared by publication and host migrations. Failure leaves the seed intact.
    pub fn advance(
        &mut self,
        hint: &ChatReadHint,
    ) -> Result<(u64, Option<ChatRunPosition>), ChatError> {
        let seq = self
            .head_seq
            .checked_add(1)
            .filter(|seq| *seq <= i64::MAX as u64)
            .ok_or(ChatError::SeqExhausted)?;
        let run = match hint {
            ChatReadHint::Hidden => None,
            ChatReadHint::Single => Some(ChatRunPosition {
                start_seq: seq,
                ordinal: 1,
            }),
            ChatReadHint::Adjacent { .. } => {
                let position = match self.last_visible.as_ref().filter(|last| last.hint == *hint) {
                    Some(last) => ChatRunPosition {
                        start_seq: last.position.start_seq,
                        ordinal: last
                            .position
                            .ordinal
                            .checked_add(1)
                            .filter(|ordinal| *ordinal <= i64::MAX as u64)
                            .ok_or(ChatError::SeqExhausted)?,
                    },
                    None => ChatRunPosition {
                        start_seq: seq,
                        ordinal: 1,
                    },
                };
                Some(position)
            }
        };
        if let Some(position) = run {
            self.last_visible = Some(ChatRunSeed {
                seq,
                hint: hint.clone(),
                position,
            });
        }
        self.head_seq = seq;
        Ok((seq, run))
    }
}

fn validate_run(
    seq: u64,
    hint: &ChatReadHint,
    run: Option<ChatRunPosition>,
) -> Result<(), ChatError> {
    let valid = seq > 0
        && seq <= i64::MAX as u64
        && match (hint, run) {
            (ChatReadHint::Hidden, None) => true,
            (ChatReadHint::Single, Some(position)) => {
                position.start_seq == seq && position.ordinal == 1
            }
            (ChatReadHint::Adjacent { .. }, Some(position)) => {
                position.start_seq > 0
                    && position.start_seq <= seq
                    && position.ordinal > 0
                    && position.ordinal <= seq - position.start_seq + 1
            }
            _ => false,
        };
    if valid {
        Ok(())
    } else {
        Err(ChatError::Conflict("invalid completion run".into()))
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum ChatSelection {
    /// Every matching completion, including Hidden.
    #[default]
    Records,
    /// Latest visible representative per run in descending pages; every visible record in replay.
    RunHeads,
    /// Every member of the exact immutable run.
    Run { start_seq: u64 },
}

/// Query membership only. A missing parent selects the whole class, not just NULL parents.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct ChatQuery {
    pub query_class: String,
    pub parent_id: Option<ChatKey>,
    pub selection: ChatSelection,
}

impl ChatQuery {
    pub fn new(query_class: impl Into<String>, parent_id: Option<ChatKey>) -> Self {
        Self {
            query_class: query_class.into(),
            parent_id,
            selection: ChatSelection::Records,
        }
    }

    pub fn matches(&self, header: &ChatItemHeader) -> bool {
        self.query_class == header.query_class
            && self
                .parent_id
                .as_ref()
                .is_none_or(|parent| Some(parent) == header.parent_id.as_ref())
            && match self.selection {
                ChatSelection::Records => true,
                ChatSelection::RunHeads => header.run.is_some(),
                ChatSelection::Run { start_seq } => {
                    header.run.is_some_and(|run| run.start_seq == start_seq)
                }
            }
    }

    pub(crate) fn validate(&self) -> Result<(), ChatError> {
        if self.query_class.is_empty() {
            return Err(ChatError::InvalidArgument("empty query class".into()));
        }
        if self.selection != ChatSelection::Records && self.parent_id.is_some() {
            return Err(ChatError::InvalidArgument(
                "run selection cannot have a parent".into(),
            ));
        }
        if let ChatSelection::Run { start_seq } = self.selection
            && (start_seq == 0 || start_seq > i64::MAX as u64)
        {
            return Err(ChatError::InvalidArgument("invalid run start".into()));
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
    pub read_hint: ChatReadHint,
    pub run: Option<ChatRunPosition>,
    pub byte_length: u64,
    /// Producer-owned lightweight atomic provenance; Core never decodes it.
    /// Empty is valid for generic consumers without a product envelope.
    pub metadata: Arc<[u8]>,
}

impl ChatItemHeader {
    pub fn validate_run(&self) -> Result<(), ChatError> {
        validate_run(self.append_seq, &self.read_hint, self.run)
    }
}

/// Producer-supplied, immutable content ownership. Normal pages never clone this manifest.
pub type ChatContents = BTreeMap<ChatContentKey, Arc<ChatContent>>;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatDraft {
    pub item_id: String,
    pub query_class: String,
    pub parent_id: Option<ChatKey>,
    pub read_hint: ChatReadHint,
    pub metadata: Arc<[u8]>,
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
            read_hint: ChatReadHint::Hidden,
            metadata: Arc::from([]),
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
    /// Freeze bytes with the seq/run allocated by the owner (or restored by a history adapter).
    /// Only Session publication allocates new positions; adapters restore the original columns.
    pub fn complete(draft: ChatDraft, append_seq: u64, run: Option<ChatRunPosition>) -> Self {
        Self {
            header: ChatItemHeader {
                append_seq,
                item_id: draft.item_id,
                query_class: draft.query_class,
                parent_id: draft.parent_id,
                read_hint: draft.read_hint,
                run,
                byte_length: draft.payload.len() as u64,
                metadata: draft.metadata,
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
        && draft.read_hint == record.header.read_hint
        && draft.metadata == record.header.metadata
        && draft.payload == record.payload
        && draft.contents == record.contents
}
