//! 按身份读取当前元数据：复用 Session 的事实所有者与有界发布证明，不建立另一份内容缓存。

use std::{
    collections::{BTreeMap, BTreeSet},
    sync::Arc,
};

use sha2::{Digest, Sha256};

use crate::chat::{
    ChatError, ChatField, ChatItem, ChatLifecycle, MAX_PAGE_ITEMS, PAGE_PREVIEW_BYTES,
    PresentationPart, Session,
    item::item_structure_bytes,
    session::{TimelineState, memory_items, validate_metadata, withdrawals_since},
};

/// Current item facts without any field body or content-block handle.
///
/// `meta` remains opaque to core. Field values are complete UTF-8 byte lengths, not the lengths of
/// the bounded previews. Save and execution facts remain independent of the content revision.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatItemMetadata {
    pub item_id: String,
    pub turn_id: String,
    pub order: u64,
    pub revision: u64,
    pub meta: Arc<[u8]>,
    pub fields: BTreeMap<ChatField, u64>,
    pub saved: bool,
    pub lifecycle: ChatLifecycle,
}

/// One answer at the same position as its requested identity.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ChatItemMetadataRead {
    Present(ChatItemMetadata),
    /// No item can currently be found. This is neither a durable deletion nor proof that the
    /// identity never existed; preview-cache eviction and lost coverage are not tombstones.
    Missing {
        item_id: String,
    },
}

impl Session {
    /// Reads current metadata for `1..=100` nonempty, distinct identities, in request order.
    ///
    /// Hot facts are captured without retaining bodies. Missing or outdated hot candidates use
    /// sequential history point reads; each decoded item's bodies are released before the next
    /// read. Before returning, one timeline critical section reconciles newer revisions, field
    /// sets, save acknowledgements and terminal facts, and proves the withdrawal window. A withdrawn
    /// captured preview cannot reappear through either a retained candidate or an older cold row.
    ///
    /// The whole result, including identities, opaque `meta` and field indexes, must fit
    /// [`PAGE_PREVIEW_BYTES`]. It is never truncated or partially returned. This read does not seed
    /// caches, advance the content version, notify observers, allocate orders or start execution.
    /// Dropping its future publishes nothing and leaves no Session-owned query task.
    ///
    /// # Errors
    /// [`ChatError::InvalidArgument`] for an empty, oversized or duplicate request or an empty ID;
    /// [`ChatError::Overloaded`] for a metadata budget overflow; [`ChatError::ReadInvalidated`] for
    /// a withdrawal, unprovable publication window or known newer fact without readable metadata;
    /// and the host's typed storage failures.
    pub async fn read_metadata(
        &self,
        item_ids: &[String],
    ) -> Result<Vec<ChatItemMetadataRead>, ChatError> {
        let mut used = validate_request(item_ids)?;
        let (since, candidates, cold) = self.with_timeline(|state| {
            let mut candidates = Vec::with_capacity(item_ids.len());
            let mut cold = Vec::with_capacity(item_ids.len());
            for id in item_ids {
                let item = memory_metadata(state, id);
                replace_bytes(
                    &mut used,
                    missing_bytes(id),
                    candidate_bytes(id, item.as_ref()),
                )?;
                cold.push(item.is_none() || validate_metadata(state, id, item.as_ref()).is_err());
                candidates.push(item);
            }
            Ok::<_, ChatError>((state.version, candidates, cold))
        })?;
        let mut read = MetadataRead {
            item_ids,
            since,
            candidates,
        };
        for (index, id) in item_ids.iter().enumerate() {
            if !cold[index] {
                continue;
            }
            let stored = self.0.history.item(id).await?;
            if stored.as_ref().is_some_and(|item| item.item_id != *id) {
                return Err(ChatError::Conflict(id.clone()));
            }
            self.with_timeline(|state| {
                read.reconcile(state, stored.as_ref().map(|item| (index, item)))
            })?;
        }
        self.with_timeline(|state| {
            read.reconcile(state, None)?;
            for (id, candidate) in item_ids.iter().zip(&read.candidates) {
                validate_metadata(state, id, candidate.as_ref())?;
            }
            Ok::<_, ChatError>(())
        })?;
        Ok(item_ids
            .iter()
            .zip(read.candidates)
            .map(|(id, item)| match item {
                Some(item) => ChatItemMetadataRead::Present(item),
                None => ChatItemMetadataRead::Missing {
                    item_id: id.clone(),
                },
            })
            .collect())
    }
}

/// Per-call, body-free candidates only. Every cold admission and the final commit use the same
/// whole-request budget decision; a cost captured before IO cannot block an earlier item's shrink.
struct MetadataRead<'a> {
    item_ids: &'a [String],
    since: u64,
    candidates: Vec<Option<ChatItemMetadata>>,
}

impl MetadataRead<'_> {
    fn reconcile(
        &mut self,
        state: &TimelineState,
        stored: Option<(usize, &ChatItem)>,
    ) -> Result<(), ChatError> {
        let withdrawn = withdrawals_since(state, self.since)?;
        for id in self.item_ids {
            if withdrawn.contains(id.as_str())
                || (memory_items(state, id).next().is_none()
                    && state.log.iter().any(|entry| {
                        entry.version > self.since
                            && entry
                                .identities
                                .iter()
                                .any(|identity| identity.item_id.as_ref() == id)
                    }))
            {
                // A publication can leave the hot cache before this read commits. Neither its
                // numeric watermark nor a released captured reference can reconstruct its shell.
                return Err(ChatError::ReadInvalidated);
            }
        }
        // Select by borrowed facts first. In particular, do not clone an oversized stale cold field
        // index before discovering its newer hot replacement, or charge growing rows before the
        // same critical section has accounted for shrinking rows elsewhere in the request.
        let mut used = 0;
        for (index, id) in self.item_ids.iter().enumerate() {
            let captured = self.candidates[index].as_ref();
            let stored = stored
                .filter(|(target, _)| *target == index)
                .map(|(_, item)| item);
            let selected = select_metadata(state, id, captured, stored);
            let bytes = selected.item.map_or_else(
                || candidate_bytes(id, captured),
                ChatItem::preview_structure_bytes,
            );
            replace_bytes(&mut used, 0, bytes)?;
        }
        // Only winning indexes are materialized, after the entire current request fits. The owned
        // cold item remains local to this iteration of the caller and releases its body before IO.
        for (index, id) in self.item_ids.iter().enumerate() {
            let stored = stored
                .filter(|(target, _)| *target == index)
                .map(|(_, item)| item);
            let selected = select_metadata(state, id, self.candidates[index].as_ref(), stored);
            if let Some(item) = selected.item {
                let mut metadata = metadata_of(item);
                metadata.saved = selected.saved;
                metadata.lifecycle = selected.lifecycle;
                self.candidates[index] = Some(metadata);
            }
        }
        Ok(())
    }
}

/// The winning borrowed shell and independent progress facts. A missing `item` means the captured
/// candidate already wins (or is still Missing), so its field index need not be copied again.
struct SelectedMetadata<'a> {
    item: Option<&'a ChatItem>,
    revision: Option<u64>,
    saved: bool,
    lifecycle: ChatLifecycle,
}

fn select_metadata<'a>(
    state: &'a TimelineState,
    item_id: &'a str,
    captured: Option<&ChatItemMetadata>,
    stored: Option<&'a ChatItem>,
) -> SelectedMetadata<'a> {
    let mut selected = SelectedMetadata {
        item: None,
        revision: captured.map(|item| item.revision),
        saved: captured.is_some_and(|item| item.saved),
        lifecycle: captured.map_or(ChatLifecycle::Streaming, |item| item.lifecycle),
    };
    for item in stored.into_iter().chain(memory_items(state, item_id)) {
        if selected
            .revision
            .is_some_and(|revision| revision > item.revision)
        {
            continue;
        }
        if selected.revision == Some(item.revision) {
            selected.saved |= item.saved;
            selected.lifecycle = selected.lifecycle.max(item.lifecycle);
        } else {
            selected.saved = item.saved;
            selected.lifecycle = item.lifecycle;
        }
        selected.revision = Some(item.revision);
        selected.item = Some(item);
    }
    selected
}

fn validate_request(item_ids: &[String]) -> Result<usize, ChatError> {
    if !(1..=MAX_PAGE_ITEMS).contains(&item_ids.len()) {
        return Err(ChatError::InvalidArgument(format!(
            "metadata request count {} is outside 1..={MAX_PAGE_ITEMS}",
            item_ids.len(),
        )));
    }
    let mut unique = BTreeSet::new();
    let mut used = 0;
    for id in item_ids {
        if id.is_empty() || !unique.insert(id.as_str()) {
            return Err(ChatError::InvalidArgument(
                "metadata identities must be nonempty and distinct".to_owned(),
            ));
        }
        replace_bytes(&mut used, 0, missing_bytes(id))?;
    }
    Ok(used)
}

fn memory_metadata(state: &TimelineState, item_id: &str) -> Option<ChatItemMetadata> {
    let mut metadata = None;
    for item in memory_items(state, item_id) {
        merge_metadata(&mut metadata, metadata_of(item));
    }
    metadata
}

fn metadata_of(item: &ChatItem) -> ChatItemMetadata {
    ChatItemMetadata {
        item_id: item.item_id.clone(),
        turn_id: item.turn_id.clone(),
        order: item.order,
        revision: item.revision,
        meta: item.meta.clone(),
        fields: item
            .fields
            .iter()
            .map(|(field, preview)| (field.clone(), preview.total_bytes))
            .collect(),
        saved: item.saved,
        lifecycle: item.lifecycle,
    }
}

pub(crate) fn item_metadata_fingerprint(item: &ChatItem) -> [u8; 32] {
    shell_fingerprint(
        &item.turn_id,
        &item.meta,
        item.fields
            .iter()
            .map(|(field, preview)| (field, preview.total_bytes)),
    )
}

pub(crate) fn metadata_fingerprint(item: &ChatItemMetadata) -> [u8; 32] {
    shell_fingerprint(
        &item.turn_id,
        &item.meta,
        item.fields.iter().map(|(field, total)| (field, *total)),
    )
}

/// Revision identifies content, not the shell. Hash only the opaque shell and ordered field index,
/// never preview/body bytes. Length framing and typed field tags keep distinct identities distinct;
/// no serialized item, second metadata cache or body-sized allocation is needed.
fn shell_fingerprint<'a>(
    turn_id: &str,
    meta: &[u8],
    fields: impl IntoIterator<Item = (&'a ChatField, u64)>,
) -> [u8; 32] {
    let mut hash = Sha256::new();
    hash.update((turn_id.len() as u64).to_le_bytes());
    hash.update(turn_id.as_bytes());
    hash.update((meta.len() as u64).to_le_bytes());
    hash.update(meta);
    for (field, total_bytes) in fields {
        match field {
            ChatField::Body => hash.update([0]),
            ChatField::Part(part) => {
                let (tag, index) = match part {
                    PresentationPart::OutputText(index) => (0, index),
                    PresentationPart::ReasoningText(index) => (1, index),
                    PresentationPart::SummaryText(index) => (2, index),
                };
                hash.update([1, tag]);
                hash.update(index.to_le_bytes());
            }
            ChatField::Host(key) => {
                hash.update([2]);
                hash.update((key.len() as u64).to_le_bytes());
                hash.update(key.as_bytes());
            }
        }
        hash.update(total_bytes.to_le_bytes());
    }
    hash.finalize().into()
}

/// At equal revision the current source owns the field set and opaque shell; only independent
/// progress flags are folded monotonically. In particular this never unions removed fields back in.
fn merge_metadata(slot: &mut Option<ChatItemMetadata>, mut current: ChatItemMetadata) {
    if let Some(previous) = slot {
        if previous.revision > current.revision {
            return;
        }
        if previous.revision == current.revision {
            current.saved |= previous.saved;
            current.lifecycle = current.lifecycle.max(previous.lifecycle);
        }
    }
    *slot = Some(current);
}

fn missing_bytes(item_id: &str) -> usize {
    item_structure_bytes(item_id, "", 0, std::iter::empty())
}

fn candidate_bytes(item_id: &str, item: Option<&ChatItemMetadata>) -> usize {
    item.map_or_else(
        || missing_bytes(item_id),
        |item| {
            item_structure_bytes(
                &item.item_id,
                &item.turn_id,
                item.meta.len(),
                item.fields.keys(),
            )
        },
    )
}

fn replace_bytes(used: &mut usize, previous: usize, current: usize) -> Result<(), ChatError> {
    *used = used
        .checked_sub(previous)
        .and_then(|used| used.checked_add(current))
        .filter(|used| *used <= PAGE_PREVIEW_BYTES)
        .ok_or_else(|| {
            ChatError::Overloaded(format!(
                "metadata result exceeds {PAGE_PREVIEW_BYTES} bytes",
            ))
        })?;
    Ok(())
}
