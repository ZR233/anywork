//! 稳定身份、字段身份与有界预览的完成条目表示。
//!
//! 一条完成条目是不可变的最小完成事实：静态结构（`meta`）、若干完整正文域（`fields`），以及
//! 发布时已经确定的顺序、来源与封口元数据。完成事实不携带 streaming／terminal／saved／revision
//! 等执行或保存水位：封口后的记录永远不会再被改写，同一身份的重复发布只能幂等或冲突。
//!
//! 每个字段同时记录**完整正文**的 UTF-8 字节数，因此有界预览截断正文时不会改写原始长度、顺序或
//! 字段身份，详情读取也能按该长度声明省略量。

use std::{
    collections::BTreeMap,
    fmt::{self, Write as _},
    sync::Arc,
};

use crate::model::ContentBlock;

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
    // The identity of one streamed provider part is rebuilt once per part per preview frame, so it is
    // assembled in one allocation instead of formatting an intermediate prefix string and two
    // temporary concatenations. The bytes are unchanged.
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

/// Fixed bytes of the presentation prefix that are neither the length digits nor the attempt id.
const PRESENTATION_PREFIX_BYTES: usize = "model::presentation:item:".len();

/// Appends the presentation prefix of one attempt without building an intermediate string.
fn write_presentation_prefix(id: &mut String, attempt_id: &str) {
    let _ = write!(
        id,
        "model:{}:{attempt_id}:presentation:item:",
        attempt_id.len()
    );
}

/// Stable identity of one content region inside a [`ChatItem`].
///
/// Core never encodes a protocol tag here. The host interprets these identities and maps them to
/// its own field (for example a `ThreadContentField`), so one content region is addressable without
/// decoding or re-encoding a whole payload string.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum ChatField {
    /// The item's primary body: a non-streaming item, or one provider part that maps 1:1 to it.
    Body,
    /// One provider content part identified by the model port's own [`PresentationPart`].
    Part(PresentationPart),
    /// A host-defined content region: an opaque, product-agnostic domain key.
    ///
    /// Core never interprets the key or infers a domain from the field's text, so a product can give
    /// distinct completion content that is not a provider presentation part (for example tool
    /// arguments versus a tool result) its own stable field without decoding the body or stuffing a
    /// dynamic domain into `meta` and copying the whole item per update.
    Host(Arc<str>),
}

impl ChatField {
    /// Field identity for one provider content part.
    pub const fn part(part: PresentationPart) -> Self {
        Self::Part(part)
    }

    /// Field identity for one opaque host-defined content region.
    pub fn host(key: impl Into<Arc<str>>) -> Self {
        Self::Host(key.into())
    }

    /// UTF-8 bytes of the variable part of this field identity.
    ///
    /// Fixed discriminators and their index digits are already covered by the per-field structure
    /// estimate; only a host key has unbounded identity text that has to be charged as it really is.
    fn key_bytes(&self) -> usize {
        match self {
            Self::Host(key) => key.len(),
            Self::Body | Self::Part(_) => 0,
        }
    }
}

impl fmt::Display for ChatField {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Body => formatter.write_str("body"),
            Self::Part(PresentationPart::OutputText(index)) => write!(formatter, "text:{index}"),
            Self::Part(PresentationPart::ReasoningText(index)) => {
                write!(formatter, "reasoning:{index}")
            }
            Self::Part(PresentationPart::SummaryText(index)) => {
                write!(formatter, "summary:{index}")
            }
            Self::Host(key) => formatter.write_str(key),
        }
    }
}

/// Field identity for the item's primary body.
pub const CHAT_BODY_FIELD: ChatField = ChatField::Body;

/// One content field of a record: the bounded preview value plus the complete length it came from.
///
/// The two facts live together on purpose. A preview that truncates the body must not rewrite the
/// original length, so a detail reference can always state how many bytes exist, and reconciling a
/// preview against a complete copy is a field-local comparison instead of a second map that could
/// drift. `total_bytes == block.len()` means this field is complete.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatFieldPreview {
    pub block: Arc<ContentBlock>,
    pub total_bytes: u64,
}

impl ChatFieldPreview {
    /// A complete field: the preview is the whole body.
    pub fn complete(block: Arc<ContentBlock>) -> Self {
        let total_bytes = block.len() as u64;
        Self { block, total_bytes }
    }

    /// Reports whether the bounded preview holds the whole body.
    pub fn is_complete(&self) -> bool {
        self.block.len() as u64 == self.total_bytes
    }

    /// Bytes the preview leaves out of this field.
    pub fn omitted_bytes(&self) -> u64 {
        self.total_bytes.saturating_sub(self.block.len() as u64)
    }
}

/// One immutable completion record of the timeline.
///
/// Every field is a publish-time fact. `append_seq` is the completion order the session assigned in
/// one short critical section; `source_effect_seq` and `sealed_at` are optional provenance the
/// producer already knew when it sealed the item — a migration that cannot confirm them keeps them
/// `None` instead of disguising a last-write time as a sealing time. Nothing here may be advanced,
/// patched or removed after publication: republishing the same identity is idempotent only with the
/// same payload, and a different payload is a contract error.
///
/// `fields` holds the bounded preview values that are actually shown; the complete body of an
/// omitted field is read by identity through
/// [`Session::read_detail`](crate::chat::Session::read_detail). The model context is unrelated to
/// this representation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatItem {
    pub item_id: String,
    /// The Turn this completion belongs to, when the producer knew it at seal time. The consuming
    /// Turn of an accepted input is not patched in later.
    pub turn_id: Option<String>,
    /// Completion order assigned by the session: strictly positive, strictly increasing, never
    /// greater than the signed 64-bit range the store keeps.
    pub append_seq: u64,
    /// Provenance of the effect that produced this completion, when the producer tracks one.
    pub source_effect_seq: Option<u64>,
    /// Unix seconds at which the producer sealed this completion, when known.
    pub sealed_at: Option<i64>,
    pub fields: BTreeMap<ChatField, ChatFieldPreview>,
    pub meta: Arc<[u8]>,
}

/// Everything needed to construct one complete, sequenced record.
///
/// Named fields instead of positional arguments: the previews and complete lengths are derived from
/// each field body by [`ChatFieldPreview::complete`], so a caller cannot pair a truncated block with
/// an invented total.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatItemParts {
    pub item_id: String,
    pub turn_id: Option<String>,
    pub append_seq: u64,
    pub source_effect_seq: Option<u64>,
    pub sealed_at: Option<i64>,
    pub fields: BTreeMap<ChatField, Arc<ContentBlock>>,
    pub meta: Arc<[u8]>,
}

/// One complete, not-yet-sequenced completion input for [`Session::publish_batch`].
///
/// A draft is the frozen payload the producer prepared when its effect completed. It carries no
/// `append_seq`: the session validates the whole batch and assigns consecutive sequences in one
/// short critical section, so the completion order is the publication order, not the start order.
///
/// [`Session::publish_batch`]: crate::chat::Session::publish_batch
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatDraft {
    pub item_id: String,
    pub turn_id: Option<String>,
    pub source_effect_seq: Option<u64>,
    pub sealed_at: Option<i64>,
    pub fields: BTreeMap<ChatField, Arc<ContentBlock>>,
    pub meta: Arc<[u8]>,
}

impl ChatDraft {
    /// A draft with an identity, no body fields and empty static metadata.
    pub fn new(item_id: impl Into<String>) -> Self {
        Self {
            item_id: item_id.into(),
            turn_id: None,
            source_effect_seq: None,
            sealed_at: None,
            fields: BTreeMap::new(),
            meta: Arc::from(Vec::new()),
        }
    }

    /// Binds the Turn this completion belongs to.
    pub fn with_turn_id(mut self, turn_id: impl Into<String>) -> Self {
        self.turn_id = Some(turn_id.into());
        self
    }

    /// Attaches the provenance of the effect that produced this completion.
    pub fn with_source_effect_seq(mut self, source_effect_seq: u64) -> Self {
        self.source_effect_seq = Some(source_effect_seq);
        self
    }

    /// Attaches the Unix-second sealing time.
    pub fn with_sealed_at(mut self, sealed_at: i64) -> Self {
        self.sealed_at = Some(sealed_at);
        self
    }

    /// Replaces the static metadata.
    pub fn with_meta(mut self, meta: Arc<[u8]>) -> Self {
        self.meta = meta;
        self
    }

    /// Adds one complete content field.
    pub fn with_field(mut self, field: ChatField, block: Arc<ContentBlock>) -> Self {
        self.fields.insert(field, block);
        self
    }

    /// Adds one complete text field.
    pub fn with_text(self, field: ChatField, text: &str) -> Self {
        self.with_field(field, ContentBlock::from_text(text))
    }
}

impl ChatItem {
    /// Builds a complete record: every field preview holds the whole body.
    pub fn complete(parts: ChatItemParts) -> Self {
        Self {
            item_id: parts.item_id,
            turn_id: parts.turn_id,
            append_seq: parts.append_seq,
            source_effect_seq: parts.source_effect_seq,
            sealed_at: parts.sealed_at,
            fields: parts
                .fields
                .into_iter()
                .map(|(field, block)| (field, ChatFieldPreview::complete(block)))
                .collect(),
            meta: parts.meta,
        }
    }

    /// Preview block of one field, if this record carries it.
    pub fn field(&self, field: &ChatField) -> Option<&Arc<ContentBlock>> {
        self.fields.get(field).map(|preview| &preview.block)
    }

    /// Every preview field of this record, in field identity order.
    pub fn field_previews(&self) -> impl Iterator<Item = (&ChatField, &ChatFieldPreview)> {
        self.fields.iter()
    }

    /// Complete UTF-8 byte length of one field, if this record carries it.
    pub fn field_total_bytes(&self, field: &ChatField) -> Option<u64> {
        self.fields.get(field).map(|preview| preview.total_bytes)
    }

    /// Reports whether one field's preview holds its whole body.
    pub fn field_is_complete(&self, field: &ChatField) -> bool {
        self.fields
            .get(field)
            .is_some_and(ChatFieldPreview::is_complete)
    }

    /// Bytes omitted from the bounded previews of this record; zero means every field is complete.
    pub fn omitted_bytes(&self) -> u64 {
        self.fields.values().fold(0u64, |total, preview| {
            total.saturating_add(preview.omitted_bytes())
        })
    }

    /// Reports whether every field preview holds its whole body.
    pub fn is_complete(&self) -> bool {
        self.omitted_bytes() == 0
    }

    /// The record's primary body block, if it has one.
    pub fn body(&self) -> Option<&Arc<ContentBlock>> {
        self.field(&ChatField::Body)
    }

    /// One provider part's block, if this record carries it.
    pub fn part(&self, part: PresentationPart) -> Option<&Arc<ContentBlock>> {
        self.field(&ChatField::Part(part))
    }

    /// Bytes of the previewed body UTF-8 this record actually retains.
    pub(crate) fn content_bytes(&self) -> usize {
        self.fields.values().fold(0usize, |total, preview| {
            total.saturating_add(preview.block.len())
        })
    }

    /// Conservative, deterministic cost of the structure this record cannot shrink.
    ///
    /// The preview budget is an admission estimate, not an allocator or wire measurement: it must
    /// still account for the parts a preview can never trim, otherwise a host can "fit" a record
    /// only by declaring an unbounded number of empty or short fields. Counted here:
    ///
    /// - the static `meta` bytes the record carries verbatim;
    /// - the item identity and, when known, the Turn identity (their real UTF-8 bytes);
    /// - one fixed record estimate ([`ITEM_STRUCTURE_BYTES`]) for the ordered record itself: the
    ///   field map spine, the completion sequence and the optional provenance slots;
    /// - one fixed field estimate ([`FIELD_STRUCTURE_BYTES`]) per content region, covering the field
    ///   key slot, its block handle, the declared complete length and the detail reference it can
    ///   produce;
    /// - the real UTF-8 bytes of a [`ChatField::Host`] key. Fixed discriminators and their index
    ///   digits are covered by the per-field estimate.
    ///
    /// The fixed coefficients are deterministic, additive and non-negative round numbers. They are an
    /// *admission estimate* for one record's non-shrinkable part, not a bound on the Rust heap
    /// layout, the wire encoding or the process RSS: they only have to be stable and comparable so a
    /// page, a baseline and a completion batch all charge the same non-shrinkable cost.
    pub fn preview_structure_bytes(&self) -> usize {
        let identities = self
            .item_id
            .len()
            .saturating_add(self.turn_id.as_ref().map_or(0, String::len));
        let total = ITEM_STRUCTURE_BYTES
            .saturating_add(self.meta.len())
            .saturating_add(identities);
        let mut fields = FIELD_STRUCTURE_BYTES.saturating_mul(self.fields.len());
        for field in self.fields.keys() {
            fields = fields.saturating_add(field.key_bytes());
        }
        total.saturating_add(fields)
    }

    /// Bytes resident for this record: the non-shrinkable structure plus the body UTF-8 it keeps.
    pub(crate) fn resident_bytes(&self) -> usize {
        self.preview_structure_bytes()
            .saturating_add(self.content_bytes())
    }
}

/// Fixed admission estimate of one record, excluding identity text and field regions.
const ITEM_STRUCTURE_BYTES: usize = 128;
/// Fixed admission estimate of one content field: key slot, block handle, complete length, detail ref.
const FIELD_STRUCTURE_BYTES: usize = 128;

/// Whether two records of one identity carry the same sealed payload.
///
/// The completion sequence is deliberately excluded: it is placement, not payload. Bodies are
/// compared by shared block first, so reconciling the session's own records costs reference checks
/// instead of re-reading text.
pub(crate) fn same_payload(left: &ChatItem, right: &ChatItem) -> bool {
    left.turn_id == right.turn_id
        && left.source_effect_seq == right.source_effect_seq
        && left.sealed_at == right.sealed_at
        && left.meta == right.meta
        && left.fields.len() == right.fields.len()
        && left.fields.iter().all(|(field, preview)| {
            right
                .fields
                .get(field)
                .is_some_and(|other| Arc::ptr_eq(&preview.block, &other.block) || preview == other)
        })
}

/// Whether one draft carries exactly the payload of an already-sealed record.
pub(crate) fn draft_matches_record(draft: &ChatDraft, record: &ChatItem) -> bool {
    record.turn_id == draft.turn_id
        && record.source_effect_seq == draft.source_effect_seq
        && record.sealed_at == draft.sealed_at
        && record.meta == draft.meta
        && record.fields.len() == draft.fields.len()
        && draft.fields.iter().all(|(field, block)| {
            record.fields.get(field).is_some_and(|preview| {
                Arc::ptr_eq(&preview.block, block) || preview.block.as_ref() == block.as_ref()
            })
        })
}
