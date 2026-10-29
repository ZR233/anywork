//! 稳定身份、字段身份与有界预览的条目表示。
//!
//! 一个条目是「静态结构 + 若干按身份版本化的正文域」：`meta` 承载产品静态结构，`fields` 承载
//! 可流式推进的正文。每个字段同时记录**完整正文**的 UTF-8 字节数，因此有界预览截断正文时不会
//! 改写原始长度、顺序、revision 或字段身份，详情读取也能按该长度声明省略量。

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
    /// distinct streaming content that is not a provider presentation part (for example tool
    /// arguments versus a tool result) its own stable field without decoding the body or stuffing a
    /// dynamic domain into `meta` and copying the whole item per token.
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

/// Execution terminal fact of one timeline item, independent of the save watermark.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum ChatLifecycle {
    /// Still executing: a later revision of the same identity may still advance the content.
    Streaming,
    /// The producer will not advance this identity again. A late preview or a different body at this
    /// identity is rejected from this fact alone, independent of any save acknowledgement.
    Terminal,
}

impl ChatLifecycle {
    /// Reports whether the item reached its execution terminal fact.
    pub const fn is_terminal(self) -> bool {
        matches!(self, Self::Terminal)
    }

    /// Reports whether the identity may still advance its content.
    pub const fn is_streaming(self) -> bool {
        matches!(self, Self::Streaming)
    }
}

/// One content field of an item: the bounded preview value plus the complete length it came from.
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

/// One timeline item as a set of typed, independently versioned content fields.
///
/// Four independent facts are in play, none of which substitutes for another:
///
/// - `revision` is this item's content version. It advances with the streamed content and is the
///   commit point one delivered [`TailChange::UpdateItem`](crate::chat::TailChange::UpdateItem)
///   validates and applies once.
/// - [`ChatTailBaseline::version`](crate::chat::ChatTailBaseline::version) is the subscription's
///   continuity watermark. Its `from`/`to` refer to that and never to any item's content version.
/// - `saved` is the save watermark: the history writer acknowledged this exact `revision` durable.
///   [`Session::confirm_saved`](crate::chat::Session::confirm_saved) only flips it, without changing
///   identity, order, revision, body or the execution lifecycle.
/// - [`ChatItem::lifecycle`] is the execution terminal fact, not a final content revision. Later
///   reliable terminal revisions remain legal. A terminal item is accepted without any save
///   acknowledgement, and a late speculative streaming preview is rejected from this fact alone.
///
/// `fields` holds the bounded preview values that are actually shown; the complete body of an
/// omitted field is read by identity through
/// [`Session::read_detail`](crate::chat::Session::read_detail). The model context is unrelated to
/// this representation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatItem {
    pub item_id: String,
    pub turn_id: String,
    pub order: u64,
    /// Content version of this item. It advances with the streamed content and stays independent of
    /// the save or execution watermark.
    pub revision: u64,
    pub fields: BTreeMap<ChatField, ChatFieldPreview>,
    pub meta: Arc<[u8]>,
    /// Save watermark: the history writer acknowledged this exact `revision` durable. Independent of
    /// [`ChatItem::lifecycle`].
    pub saved: bool,
    /// Execution terminal fact, independent of the content revision and of `saved`.
    pub lifecycle: ChatLifecycle,
}

/// 构造一条**完整**条目所需的全部事实。
///
/// 用命名字段而不是一长串位置参数：预览与完整长度由 [`ChatFieldPreview::complete`] 从各字段正文推导，
/// 保存水位与执行终态是两个独立事实，调用点必须各自点名，不能靠位置或布尔顺序表达。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatItemParts {
    pub item_id: String,
    pub turn_id: String,
    pub order: u64,
    pub revision: u64,
    pub fields: BTreeMap<ChatField, Arc<ContentBlock>>,
    pub meta: Arc<[u8]>,
    pub saved: bool,
    pub lifecycle: ChatLifecycle,
}

impl ChatItem {
    /// Builds a complete item: every field preview holds the whole body.
    pub fn complete(parts: ChatItemParts) -> Self {
        Self {
            item_id: parts.item_id,
            turn_id: parts.turn_id,
            order: parts.order,
            revision: parts.revision,
            fields: parts
                .fields
                .into_iter()
                .map(|(field, block)| (field, ChatFieldPreview::complete(block)))
                .collect(),
            meta: parts.meta,
            saved: parts.saved,
            lifecycle: parts.lifecycle,
        }
    }

    /// Preview block of one field, if this item carries it.
    pub fn field(&self, field: &ChatField) -> Option<&Arc<ContentBlock>> {
        self.fields.get(field).map(|preview| &preview.block)
    }

    /// Every preview field of this item, in field identity order.
    pub fn field_previews(&self) -> impl Iterator<Item = (&ChatField, &ChatFieldPreview)> {
        self.fields.iter()
    }

    /// Complete UTF-8 byte length of one field, if this item carries it.
    pub fn field_total_bytes(&self, field: &ChatField) -> Option<u64> {
        self.fields.get(field).map(|preview| preview.total_bytes)
    }

    /// Reports whether one field's preview holds its whole body.
    pub fn field_is_complete(&self, field: &ChatField) -> bool {
        self.fields
            .get(field)
            .is_some_and(ChatFieldPreview::is_complete)
    }

    /// Bytes omitted from the bounded preview of this item; zero means every field is complete.
    pub fn omitted_bytes(&self) -> u64 {
        self.fields.values().fold(0u64, |total, preview| {
            total.saturating_add(preview.omitted_bytes())
        })
    }

    /// Reports whether every field preview holds its whole body.
    pub fn is_complete(&self) -> bool {
        self.omitted_bytes() == 0
    }

    /// Reports whether this item reached its execution terminal fact.
    pub fn is_terminal(&self) -> bool {
        self.lifecycle.is_terminal()
    }

    /// Reports whether the identity may still advance its content.
    pub fn is_streaming(&self) -> bool {
        self.lifecycle.is_streaming()
    }

    /// Reports whether the history writer acknowledged this exact revision durable.
    pub fn is_saved(&self) -> bool {
        self.saved
    }

    /// The item's primary body block, if it has one.
    pub fn body(&self) -> Option<&Arc<ContentBlock>> {
        self.field(&ChatField::Body)
    }

    /// One provider part's block, if this item carries it.
    pub fn part(&self, part: PresentationPart) -> Option<&Arc<ContentBlock>> {
        self.field(&ChatField::Part(part))
    }

    /// Bytes of the previewed body UTF-8 this item actually retains.
    pub(crate) fn content_bytes(&self) -> usize {
        self.fields.values().fold(0usize, |total, preview| {
            total.saturating_add(preview.block.len())
        })
    }

    /// Conservative, deterministic cost of the structure this item cannot shrink.
    ///
    /// The preview budget is an admission estimate, not an allocator or wire measurement: it must
    /// still account for the parts a preview can never trim, otherwise a host can "fit" an item only by
    /// declaring an unbounded number of empty or short fields. Counted here:
    ///
    /// - the static `meta` bytes the item carries verbatim;
    /// - the item and Turn identities (their real UTF-8 bytes);
    /// - one fixed item record estimate ([`ITEM_STRUCTURE_BYTES`]) for the ordered record itself: the
    ///   field map spine, order/revision, save and lifecycle facts, and the identity/block handles;
    /// - one fixed field estimate ([`FIELD_STRUCTURE_BYTES`]) per content region, covering the field key
    ///   slot, its block handle, the declared complete length and the detail reference it can produce;
    /// - the real UTF-8 bytes of a [`ChatField::Host`] key. Fixed discriminators and their index digits
    ///   are covered by the per-field estimate.
    ///
    /// The fixed coefficients are deterministic, additive and non-negative round numbers. They are an
    /// *admission estimate* for one item's non-shrinkable part, not a bound on the Rust heap layout,
    /// the wire encoding or the process RSS: they only have to be stable and comparable so a page, the
    /// hot preview cache and a subscription copy all charge the same non-shrinkable cost.
    pub fn preview_structure_bytes(&self) -> usize {
        let total = ITEM_STRUCTURE_BYTES
            .saturating_add(self.meta.len())
            .saturating_add(self.item_id.len())
            .saturating_add(self.turn_id.len());
        let mut fields = FIELD_STRUCTURE_BYTES.saturating_mul(self.fields.len());
        for field in self.fields.keys() {
            fields = fields.saturating_add(field.key_bytes());
        }
        total.saturating_add(fields)
    }

    /// Bytes resident for this item: the non-shrinkable structure plus the body UTF-8 it keeps.
    pub(crate) fn resident_bytes(&self) -> usize {
        self.preview_structure_bytes()
            .saturating_add(self.content_bytes())
    }
}

/// Fixed admission estimate of one item record, excluding identity text and field regions.
const ITEM_STRUCTURE_BYTES: usize = 128;
/// Fixed admission estimate of one content field: key slot, block handle, complete length, detail ref.
const FIELD_STRUCTURE_BYTES: usize = 128;

/// Whether two items carry the same field content.
pub(crate) fn same_content(left: &ChatItem, right: &ChatItem) -> bool {
    left.meta == right.meta
        && left.fields.len() == right.fields.len()
        && left.fields.iter().all(|(field, preview)| {
            right
                .fields
                .get(field)
                .is_some_and(|other| Arc::ptr_eq(&preview.block, &other.block) || preview == other)
        })
}

/// Merges candidates of one identity into one ordered, de-duplicated list.
///
/// A newer revision wins outright. At the same revision a strictly more complete preview wins per
/// field, but the independent state facts are reconciled monotonically (a save acknowledgement only
/// flips false -> true, an execution terminal fact only advances streaming -> terminal), so a more
/// complete body never rolls back a newer save watermark or terminal fact carried by another
/// candidate.
pub(crate) fn merge_items(items: impl IntoIterator<Item = ChatItem>) -> Vec<ChatItem> {
    let mut merged = BTreeMap::<String, ChatItem>::new();
    for item in items {
        let key = item.item_id.clone();
        if let Some(slot) = merged.get_mut(&key) {
            merge_into(slot, item);
            continue;
        }
        merged.insert(key, item);
    }
    let mut items: Vec<_> = merged.into_values().collect();
    items.sort_by(|left, right| {
        left.order
            .cmp(&right.order)
            .then_with(|| left.item_id.cmp(&right.item_id))
    });
    items
}

/// Folds one candidate of the same identity into `slot`.
pub(crate) fn merge_into(slot: &mut ChatItem, item: ChatItem) {
    if slot.revision > item.revision {
        return;
    }
    if slot.revision < item.revision {
        *slot = item;
        return;
    }
    let saved = slot.saved || item.saved;
    let lifecycle = slot.lifecycle.max(item.lifecycle);
    overlay_complete_fields(slot, &item);
    slot.saved = saved;
    slot.lifecycle = lifecycle;
}

/// Upgrades only the preview values of `slot` from a strictly more complete copy at the same
/// revision, never the independent state facts.
pub(crate) fn overlay_complete_fields(slot: &mut ChatItem, complete: &ChatItem) {
    if complete.revision != slot.revision {
        return;
    }
    for (field, candidate) in &complete.fields {
        match slot.fields.get_mut(field) {
            Some(existing) => {
                if !existing.is_complete() && candidate.block.len() > existing.block.len() {
                    existing.block = candidate.block.clone();
                    existing.total_bytes = existing.total_bytes.max(candidate.total_bytes);
                }
            }
            None => {
                slot.fields.insert(field.clone(), candidate.clone());
            }
        }
    }
}
