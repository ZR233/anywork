//! Live projection of a Thread's admitted writes for realtime notifications.
//!
//! The Thread's observation worker owns the only instance of this projection. It consumes the
//! **admitted** writes of the Thread's reliable handoff queue in admission order, projects each
//! immutable `ThreadWrite` exactly once, freezes each item that reached its reliable completion
//! boundary into an immutable completion batch (`Session::publish_batch`) and broadcasts the same
//! typed changes. The history writer consumes that same prepared batch, so live and durable history
//! stay one projection of the same fact (`design/15` §15.3, `design/26`).
//!
//! Active canonical payloads, execution placement and report facts stay in bounded Runtime tables.
//! A reliable fact referencing a retired identity resolves that exact identity from the explicitly
//! bound execution history and completion collection; streaming never reads storage.
//!
//! Execution ordinals and content revisions are this projection's own facts: new identities draw
//! their placement from the Runtime's shared execution-order index (seeded from `history_items`'s
//! durable ceiling), streaming previews stay in the Runtime's bounded tables only — they are never
//! published into the completion session — and an identity that already sealed a completion is
//! never re-published, not even by a later execution revision of the same identity.

use std::{
    collections::{BTreeMap, BTreeSet, HashMap},
    sync::Arc,
};

use pl_core::{
    chat::{ChatDraft, ChatItem, PresentationPart, Session},
    model::{
        AggregateChannel, ContentBlock, ModelTextChannel, ObservedItemKind, ObservedPart,
        ObservedPartIdentity, ObservedPartKind,
    },
    thread::{ThreadEffectBatch, ThreadSnapshot, TurnState},
};
use pl_protocol::{
    InteractionContent, InteractionContinuationMessage, InteractionPurpose, InteractionRequest,
    SkillActivationCause, SkillActivationResourceBase, ThreadAgentItem, ThreadAgentState,
    ThreadAttachment, ThreadContentLifecycle, ThreadInferenceItem, ThreadInferenceState,
    ThreadItem, ThreadItemState, ThreadRawItem, ThreadSkillItem, ThreadTextChannel, ThreadTextItem,
    ThreadThinkingItem, ThreadToolItem, ThreadToolOutput, ThreadToolState, ToolApprovalState, Turn,
    TurnCancellationCause, TurnPhase, TurnRolloverOutcome, UserInputAnswer, UserInputState,
    UserQuestion, UserQuestionOption,
};

use super::ProjectionError;
use crate::studio::runtime::chat_item::{
    BodyKey, TOOL_RESULT_FIELD, background_started_draft, completion_draft_reusing, static_state,
};
use crate::studio::storage::thread_writer::{ExecutionMaterialization, RuntimeOrderIndex};

/// What one effect's identities resolve to.
///
/// Canonical payloads plus the identities read from durable history in this pass.
/// Resolution performs no index allocation; the final metadata batch commits once.
type ResolvedIdentities = (BTreeMap<String, ThreadItem>, BTreeSet<String>);

fn completion_ready(item: &ThreadItem) -> bool {
    item.is_terminal()
        && !matches!(
            item.state(),
            ThreadItemState::Tool(tool) if tool.user_input().is_some_and(|input| matches!(
                input.state(), pl_protocol::ThreadToolUserInputState::Pending
            ))
        )
}

/// Upper bounds for the short replay window a live projection retains.
///
/// The projection is a bounded observation owner, not a second history: the committed facts it
/// keeps are the ones a running Turn can still reference, and anything older is read from durable
/// history on reconnect. These windows never grow with the Thread's history.
pub(in crate::studio) const LIVE_ITEM_WINDOW: usize = 1024;

/// Commentary parts kept as the fallback text of a Turn that committed no final summary.
///
/// The report's result is the committed final text, which is kept in full. A Turn that stopped
/// without one is described by the tail of its visible commentary; this bound keeps that diagnostic
/// from turning the report accumulator into the Turn's whole process log.
const TURN_COMMENTARY_PARTS: usize = 16;

/// Fixed per-identity charge of the retained-size estimate.
///
/// The estimate sums every variable-length body of an item, so this constant only covers the
/// identity, ordinals and payload shells around them. It never serializes an item.
const RETAINED_ITEM_OVERHEAD: u64 = 512;

/// Fixed per-entry charge of one map or set node whose key is measured separately.
///
/// Placement metadata (`Fact`) and the report accumulator are keyed collections; the key strings
/// themselves are summed by the estimator, and this constant covers the node and ordering overhead
/// around them.
const RETAINED_ENTRY_OVERHEAD: u64 = 64;

/// Which lifecycle notification a projected Turn produces.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::studio) enum TurnEvent {
    Started,
    Updated,
    Completed,
}

/// One non-content change projected from a single committed effect.
///
/// Content is deliberately not part of this vocabulary. The single projection owner writes every
/// committed body and streaming preview into the shared chat session, and the GUI reads them from
/// that one content window; a second content frame on the status feed would be the same bytes on a
/// parallel carrier. The status feed therefore only carries the facts the window does not own —
/// Turn lifecycle and interactions — and no subscriber ever projects content.
#[derive(Debug, Clone)]
pub(in crate::studio) enum LiveEvent {
    Turn { turn: Turn, event: TurnEvent },
    Interaction(Box<InteractionRequest>),
}

impl LiveEvent {
    /// Conservative retained-memory estimate of this one status-feed event.
    ///
    /// The estimate covers the event's own shell (`size_of::<LiveEvent>()`, an interaction's `Box`
    /// pointer included) plus the independently owned variable-length bodies it carries: a Turn's
    /// identities and its state's diagnostics, an interaction's scope, purpose, questions,
    /// accepted answers, approval request, continuation and lifecycle reasons. It follows the same
    /// style as the free `retained_bytes` item estimate below: every body is walked in place,
    /// nothing is serialized or cloned into a `ThreadItem`, every keyed entry pays a fixed
    /// [`RETAINED_ENTRY_OVERHEAD`] shell, and all arithmetic saturates. Content bodies are
    /// deliberately absent from this vocabulary (see [`LiveEvent`]), so no event charges bytes the
    /// content window owns, and the items a commit also produced are charged by
    /// [`PreparedEffect::retained_bytes`] — a status-feed event is a separate resident fact, never
    /// the shared `Arc` of a prepared batch.
    ///
    /// Shell contract: the value includes the element's own shell, so a caller holding a
    /// `Vec<LiveEvent>` charges only its spare capacity on top — `(capacity - len) *
    /// size_of::<LiveEvent>()` — instead of re-charging the shells of the elements it already
    /// holds; an empty list therefore adds no dynamic budget.
    pub(in crate::studio) fn retained_bytes(&self) -> u64 {
        match self {
            Self::Turn { turn, .. } => (std::mem::size_of::<Self>() as u64)
                .saturating_add(turn.id.len() as u64)
                .saturating_add(turn.thread_id.len() as u64)
                .saturating_add(optional_bytes(turn.input_id.as_deref()))
                .saturating_add(turn_state_bytes(&turn.state)),
            Self::Interaction(interaction) => (std::mem::size_of::<Self>() as u64)
                .saturating_add(std::mem::size_of::<InteractionRequest>() as u64)
                .saturating_add(interaction_request_bytes(interaction)),
        }
    }
}

/// One in-flight streaming preview's resident fact.
///
/// The content blocks are shared with the producer (cloning them only clones the pointer), the
/// static structure is encoded once per identity, and `observed_version` is the observation's own
/// monotonic counter (model content version / tool accumulated length) — only when it advances does
/// the preview re-emit a frame. Nothing here materializes the whole body per token.
///
/// The `revision` delivered to the window comes from [`LiveProjection::revisions`], this
/// projection's own item content version: the preview and the terminal item share one counter, so
/// the preview can neither pass nor collide with the commit.
#[derive(Clone)]
struct LivePreview {
    /// All field blocks currently delivered; a model observation is one field, a tool preview is
    /// the arguments plus the streamed result.
    fields: BTreeMap<BodyKey, Arc<ContentBlock>>,
    /// Cheap stable identity of one provider/aggregate observation, absent for a tool-output
    /// preview.
    ///
    /// The preview map itself is keyed by the projection id because the runtime's own preview
    /// contract is defined on it; this short key is what the streaming hot path compares, so an already
    /// delivered part never has to rebuild that long identity to be recognized. Its index entry is
    /// charged to the same retained budget ([`observed_index_bytes`]) as the rest of the projection.
    observed: Option<ObservedKey>,
    /// Delivered structure / terminal shape (dynamic bodies cleared, see
    /// [`crate::studio::runtime::chat_item::static_state`]). The content version compares it, so a
    /// tool state transition or an execution terminal advances the version while a volatile
    /// timestamp that only the projection re-stamps does not.
    ///
    /// A preview never carries completion metadata: the terminal-only timeline meta belongs to
    /// sealed records, and this runtime shape is the preview's own structural fact.
    shape: ThreadItemState,
    /// Newest **observation** version this identity delivered (model content version / tool
    /// accumulated length), used only for de-duplication; it is not the window item's content
    /// version, which [`LiveProjection::revisions`] owns.
    observed_version: u64,
    /// Position in the producer's current generation, not lexical preview or execution order.
    /// Checked against that snapshot before activity reads the part; replacement/reordering
    /// invalidates the observation version even when its bytes did not change.
    model_part: Option<super::current::ModelPartLocation>,
}

/// Cheap stable identity of one provider/aggregate streaming observation.
///
/// It carries exactly the facts [`crate::chat::presentation_item_id`] derives the projection id
/// from — the provider item id and the part discriminator, never the late output index or part id —
/// so two observations of one identity always agree on it, while an observation that only learned
/// late metadata keeps its key.
///
/// The streaming hot path compares one of these instead of the projection id: the id has a long
/// common prefix across every part of a response, so ordering and comparing it per part per frame is
/// what turns a mostly-unchanged preview into work proportional to the whole response.
#[derive(Clone, PartialEq, Eq, Hash)]
enum ObservedKey {
    /// One request-scoped aggregate channel, published before the adapter itemizes the response.
    Aggregate(u32, AggregateChannel),
    /// One provider item part: the item identity plus its part discriminator.
    Provider(u32, Arc<str>, PresentationPart),
}

#[derive(Clone, Copy, PartialEq, Eq)]
struct ObservedVersion {
    content: u64,
    ended: bool,
    model_part: Option<super::current::ModelPartLocation>,
}

/// Cheap key of one observation identity, derived without building its projection id.
fn observed_key(generation: u32, identity: &ObservedPartIdentity) -> ObservedKey {
    match identity {
        ObservedPartIdentity::Aggregate { channel } => ObservedKey::Aggregate(generation, *channel),
        ObservedPartIdentity::Provider(provider) => ObservedKey::Provider(
            generation,
            provider.item_id.clone(),
            provider.presentation_part(),
        ),
    }
}

/// Retained bytes of one placement fact keyed by its identity, its fixed entry shell included.
fn fact_bytes(id: &str, fact: &Fact) -> u64 {
    (id.len() as u64)
        .saturating_add(fact.turn_id.len() as u64)
        .saturating_add(RETAINED_ENTRY_OVERHEAD)
}

/// Retained bytes of one in-flight preview keyed by its identity.
///
/// The resident bodies are shared content blocks, each counted at its observed length; the
/// Runtime's static execution shape and field-map structure are charged alongside them.
fn preview_bytes(id: &str, preview: &LivePreview) -> u64 {
    preview_entry_bytes(id.len() as u64, preview)
}

/// Retained bytes of one preview entry with its identity length supplied separately.
///
/// This is the one formula every site scores a preview entry with — insert, replacement, release and
/// the re-derivation after the bounded window — so a replacement can never keep a hand-copied older
/// estimate that omits a term the projection added since (for example the short-key observation
/// index). `BTreeMap::insert` hands back the replaced entry without its key, so the caller passes the
/// key length it just used; the replaced key is the very same identity.
///
/// The delivered content blocks are shared pointers: each is charged once at its observed length and
/// never copied here.
fn preview_entry_bytes(id_len: u64, preview: &LivePreview) -> u64 {
    let mut bytes = id_len
        .saturating_add(RETAINED_ENTRY_OVERHEAD)
        .saturating_add(RETAINED_ITEM_OVERHEAD)
        .saturating_add(state_body_bytes(&preview.shape))
        .saturating_add((preview.fields.len() as u64).saturating_mul(RETAINED_ENTRY_OVERHEAD))
        .saturating_add(preview.fields.keys().fold(0_u64, |bytes, field| {
            bytes.saturating_add(match field {
                BodyKey::Host(key) => key.len() as u64,
                _ => 0,
            })
        }))
        .saturating_add(preview_fields_bytes(preview));
    // The short-key observation index is resident metadata of the same projection, so its entry is
    // part of the same budget instead of living outside it.
    if let Some(observed) = &preview.observed {
        bytes = bytes.saturating_add(observed_index_bytes(observed));
    }
    bytes
}

/// Retained bytes of one short-key observation-index entry.
///
/// A provider key carries the provider item identity (its `Arc<str>` is shared with the observation,
/// so only the identity's own bytes are resident) and one entry shell for the key, the delivered
/// version and the map slot; an aggregate key carries no heap body at all. Charging one shell keeps
/// the estimate conservative without materializing anything.
fn observed_index_bytes(observed: &ObservedKey) -> u64 {
    match observed {
        ObservedKey::Aggregate(_, _) => RETAINED_ENTRY_OVERHEAD,
        ObservedKey::Provider(_, item_id, _) => {
            (item_id.len() as u64).saturating_add(RETAINED_ENTRY_OVERHEAD)
        }
    }
}

/// Retained bytes of one preview's delivered field blocks.
fn preview_fields_bytes(preview: &LivePreview) -> u64 {
    preview.fields.values().fold(0_u64, |total, block| {
        total.saturating_add(block.len() as u64)
    })
}

/// Retained bytes of one content-version entry keyed by its identity.
fn revision_bytes(id: &str) -> u64 {
    (id.len() as u64).saturating_add(RETAINED_ENTRY_OVERHEAD)
}

/// The product content one committed effect contributes, projected exactly once.
///
/// It is the output of the Thread's single live projection owner: the same projection that
/// freezes the effect's completion batch and broadcasts its typed changes. The reliable
/// admission queue carries it to the history writer, which commits this exact identity/revision
/// set instead of projecting the effect a second time.
///
/// Every item carries its own **content version** (never the effect sequence that happens to
/// commit it). The writer stores that exact version and confirms it back by identity/version, so a
/// save receipt can never acknowledge a payload it did not write.
#[derive(Debug, Clone)]
pub(in crate::studio) struct PreparedEffect {
    /// Effect sequence this batch belongs to; the writer matches it against its admission queue.
    pub(in crate::studio) sequence: u64,
    /// Original journal timestamp in Unix seconds, retained across publication/ACK retries.
    committed_at: i64,
    pub(in crate::studio) accounting: Arc<super::PreparedAccounting>,
    pub(in crate::studio) current:
        Arc<crate::studio::storage::history::conversation::current::PreparedCurrent>,
    pub(in crate::studio) current_state: Option<Arc<super::CurrentState>>,
    pub(in crate::studio) display: Option<Arc<super::presentation::PreparedDisplayDelta>>,
    /// Reliable effect-local changes of already admitted members, not new immutable phases.
    /// Publication consumes these into the original frozen display delta.
    display_atom_updates: Arc<[pl_protocol::ChatAtom]>,
    display_text_visible: Arc<[super::presentation::TextVisible]>,
    display_observation_plan: Arc<super::presentation::ObservationPlan>,
    /// Only requested boundary cuts survive retirement; publication never consults newer live data.
    display_observations: Arc<BTreeMap<String, observations::Observation>>,
    /// The canonical items the effect committed, in the order the durable rows are written.
    pub(in crate::studio) items: Arc<[ThreadItem]>,
    /// The frozen completion records this batch published atomically before the handoff.
    ///
    /// The completion session allocated their `append_seq` in one short critical section and keeps
    /// the very same `Arc` records in its pending set; the writer submits exactly these records in
    /// the same `history.sqlite` transaction that persists the items, then confirms the durable
    /// prefix through them (`design/26` §26.3). They are the completion-pending bytes of this
    /// batch, charged by [`PreparedEffect::retained_bytes`].
    pub(in crate::studio) completions: Arc<[Arc<ChatItem>]>,
    /// Frozen publication work owned by the pending handoff, before any history read can wait.
    /// `Some([])` still owes publication; only `None` may enter the writer.
    pub(in crate::studio) completion_drafts: Option<Vec<ChatDraft>>,
    /// Exact terminal handoff, committed in the same history transaction as its terminal effect.
    pub(in crate::studio) parent_report: Option<Arc<pl_core::thread::inbox::ThreadMessage>>,
    pub(in crate::studio) terminal_retention:
        Option<std::sync::Arc<crate::thread_assembler::review_dispatch::TerminalMaterialRetention>>,
    /// Immutable diagnostics produced by application CAS changes in this very effect.
    pub(in crate::studio) review_delivery:
        Arc<[crate::thread_assembler::review_delivery::ReviewDeliveryFact]>,
}

fn review_delivery_facts(
    thread_id: &str,
    effect: &ThreadEffectBatch,
) -> anyhow::Result<Vec<crate::thread_assembler::review_delivery::ReviewDeliveryFact>> {
    use crate::thread_assembler::review_delivery::{EXTENSION_PREFIX, ReviewDeliveryFact};
    let mut facts = Vec::new();
    for change in effect.extensions.iter() {
        if let pl_core::thread::extensions::ExtensionChange::Put { id, record } = change
            && id.starts_with(EXTENSION_PREFIX)
        {
            let fact = ReviewDeliveryFact::decode(&record.payload)?;
            anyhow::ensure!(
                fact.extension_id() == *id
                    && fact.message.source_id == format!("studio.review:{thread_id}")
                    && fact.terminal_sequence < effect.sequence,
                "review delivery carrier provenance mismatch"
            );
            facts.push(fact);
        }
    }
    Ok(facts)
}

impl PreparedEffect {
    /// The report's current share of this batch's charge, before terminal transfer.
    pub(in crate::studio) fn parent_report_retained_bytes(&self) -> u64 {
        self.parent_report.as_ref().map_or(0, |message| {
            if self.terminal_retention.is_some() {
                0
            } else {
                (message.payload.content().len() as u64)
                    .saturating_mul(2)
                    .saturating_add(message.id.len() as u64)
                    .saturating_add(256)
            }
        })
    }

    /// Cheap retained-memory estimate of this prepared batch, owner-provided for the reliable
    /// budget.
    ///
    /// This is the batch's one estimate — the very value the writer's reliable queue has always
    /// charged at handoff — moved next to the content it sizes, so the projection owner that
    /// builds a batch and the writer that budgets it can never drift into two formulas for one
    /// fact. It stays the established conservative estimate rather than a claim of exact physical
    /// memory: the items are summed by the free `retained_bytes` item estimate below (every
    /// variable-length body plus each item's fixed shell), and each report-like message is charged as
    /// `content * 2 + id + 256` — its context carries a second copy of the same content text, and the
    /// fixed term covers the message shell and short identity fields. A parent report already held by
    /// `terminal_retention` is excluded here because that managed owner carries its one charge.
    /// Nothing is serialized, no second budget account is created, and the arithmetic saturates.
    ///
    /// 条目使用共享的 Arc 切片，本估算已包含条目与报告本身的外壳；没有 Vec 预留容量。
    /// 即使内容批次为空，也保留准备好的记账资料及其对应预算。
    pub(in crate::studio) fn retained_bytes(&self) -> u64 {
        let parent_report = self.parent_report_retained_bytes();
        let review_delivery = self.review_delivery.iter().fold(0_u64, |bytes, fact| {
            bytes
                .saturating_add((fact.message.payload.content().len() as u64).saturating_mul(2))
                .saturating_add(fact.message.id.len() as u64)
                .saturating_add(256)
        });
        // The payload and explicit content owners are the same Arcs retained by pending and writer.
        let completions = self.completions.iter().fold(0_u64, |bytes, record| {
            bytes
                .saturating_add(completion_bytes(
                    &record.header.item_id,
                    &record.payload,
                    &record.contents,
                ))
                .saturating_add(RETAINED_ITEM_OVERHEAD)
                .saturating_add(record.header.metadata.len() as u64)
        });
        retained_bytes(&self.items)
            .saturating_add(
                self.display
                    .as_ref()
                    .map_or(0, |delta| delta.retained_bytes),
            )
            .saturating_add(self.accounting.retained_bytes())
            .saturating_add(self.current.projection_retained_bytes())
            .saturating_add(self.current.operation_bytes())
            .saturating_add(
                serde_json::to_vec(self.current.atom_facts.as_ref())
                    .map_or(u64::MAX, |bytes| bytes.len() as u64),
            )
            .saturating_add(
                serde_json::to_vec(self.display_atom_updates.as_ref())
                    .map_or(u64::MAX, |bytes| bytes.len() as u64),
            )
            .saturating_add(
                serde_json::to_vec(self.display_text_visible.as_ref())
                    .map_or(u64::MAX, |bytes| bytes.len() as u64),
            )
            .saturating_add(
                serde_json::to_vec(self.display_observation_plan.as_ref())
                    .map_or(u64::MAX, |bytes| bytes.len() as u64),
            )
            .saturating_add(self.display_observations.iter().fold(
                0u64,
                |bytes, (key, observation)| {
                    bytes
                        .saturating_add(key.len() as u64)
                        .saturating_add(observation.retained_bytes())
                },
            ))
            .saturating_add(
                serde_json::to_vec(self.current.source_changes.as_ref())
                    .map_or(u64::MAX, |bytes| bytes.len() as u64),
            )
            .saturating_add(
                self.current_state
                    .as_ref()
                    .map_or(0, |state| state.metadata_bytes()),
            )
            .saturating_add(parent_report)
            .saturating_add(review_delivery)
            .saturating_add(completions)
            .saturating_add(self.completion_drafts.as_ref().map_or(0, |drafts| {
                drafts.iter().fold(0_u64, |bytes, draft| {
                    bytes
                        .saturating_add(RETAINED_ITEM_OVERHEAD)
                        .saturating_add(draft.metadata.len() as u64)
                        .saturating_add(completion_bytes(
                            &draft.item_id,
                            &draft.payload,
                            &draft.contents,
                        ))
                })
            }))
    }
}

fn completion_bytes(id: &str, payload: &[u8], contents: &pl_core::chat::ChatContents) -> u64 {
    contents.iter().fold(
        (id.len() as u64).saturating_add(payload.len() as u64),
        |bytes, (key, content)| {
            bytes
                .saturating_add(key.owner.as_str().len() as u64)
                .saturating_add(key.key.len() as u64)
                .saturating_add(content.data.len() as u64)
                .saturating_add(RETAINED_ENTRY_OVERHEAD)
        },
    )
}

/// Cheap retained-memory estimate of one prepared batch.
///
/// Every variable-length body a retained item can carry is summed — text, reasoning, tool
/// arguments and streamed output and results, attachment metadata, opaque JSON payloads, agent and
/// inference diagnostics, Skill and file facts — and every identity is charged a fixed overhead for
/// its ordinals and payload shell. Nothing is serialized, so the estimate can be taken before the
/// reliable queue's lock. An attachment's blob is not resident, so only its metadata is charged.
pub(in crate::studio) fn retained_bytes(items: &[ThreadItem]) -> u64 {
    items.iter().fold(0_u64, |total, item| {
        total.saturating_add(charged_item_bytes(item))
    })
}

/// Resident bytes one retained item holds, its fixed identity overhead included.
fn charged_item_bytes(item: &ThreadItem) -> u64 {
    item_body_bytes(item).saturating_add(RETAINED_ITEM_OVERHEAD)
}

/// Sums every resident body of one item's category payload.
fn item_body_bytes(item: &ThreadItem) -> u64 {
    state_body_bytes(item.state())
}

fn state_body_bytes(state: &ThreadItemState) -> u64 {
    match state {
        ThreadItemState::Raw(raw) => raw
            .payloads
            .iter()
            .fold(0_u64, |total, payload| {
                total.saturating_add(payload.content.len() as u64)
            })
            .saturating_add(raw.notice.len() as u64),
        ThreadItemState::Text(text) => (text.text().len() as u64)
            .saturating_add(attachments_bytes(text.attachments()))
            .saturating_add(lifecycle_bytes(text.lifecycle())),
        ThreadItemState::Thinking(thinking) => thinking
            .summary()
            .iter()
            .chain(thinking.content())
            .fold(0_u64, |total, chunk| {
                total.saturating_add(chunk.len() as u64)
            })
            .saturating_add(lifecycle_bytes(thinking.lifecycle())),
        ThreadItemState::Tool(tool) => tool_bytes(tool),
        ThreadItemState::Agent(agent) => agent_bytes(agent),
        ThreadItemState::Turn(turn) => optional_bytes(turn.input_id()),
        ThreadItemState::Inference(inference) => inference_bytes(inference),
        ThreadItemState::Skill(skill) => skill_bytes(skill),
        ThreadItemState::File(file) => {
            (file.path().len() as u64).saturating_add(optional_bytes(file.media_type()))
        }
        ThreadItemState::ContextCompaction(_) => 0,
    }
}

fn optional_bytes(value: Option<&str>) -> u64 {
    value.map_or(0, |text| text.len() as u64)
}

/// Diagnostic bodies a text or reasoning lifecycle can carry beyond its content.
fn lifecycle_bytes(lifecycle: &ThreadContentLifecycle) -> u64 {
    optional_bytes(lifecycle.failure())
        .saturating_add(optional_bytes(lifecycle.cancellation_reason()))
}

/// Metadata of one attachment list; the referenced blobs are not resident.
fn attachments_bytes(attachments: &[ThreadAttachment]) -> u64 {
    attachments.iter().fold(0_u64, |total, attachment| {
        total
            .saturating_add(attachment.id.len() as u64)
            .saturating_add(attachment.media_type.len() as u64)
            .saturating_add(optional_bytes(attachment.filename.as_deref()))
            .saturating_add(RETAINED_ENTRY_OVERHEAD)
    })
}

/// Arguments and state bodies of one tool item.
fn tool_bytes(tool: &ThreadToolItem) -> u64 {
    let invocation = tool.invocation();
    let mut bytes = 0_u64;
    for text in [
        invocation.tool_call_id(),
        invocation.name(),
        invocation.arguments(),
    ] {
        bytes = bytes.saturating_add(text.len() as u64);
    }
    for text in [
        invocation.call_id(),
        invocation.provider_item_id(),
        invocation.working_directory(),
        invocation.task_id(),
    ] {
        bytes = bytes.saturating_add(optional_bytes(text));
    }
    match tool.state() {
        ThreadToolState::Queued(_)
        | ThreadToolState::Started(_)
        | ThreadToolState::Streaming(_)
        | ThreadToolState::AwaitingApproval(_)
        | ThreadToolState::Approved(_) => {}
        ThreadToolState::Cancelling(state) => {
            bytes = bytes.saturating_add(state.streamed_output().len() as u64);
        }
        ThreadToolState::Interrupted(state) => {
            bytes = bytes.saturating_add(state.reason().len() as u64);
        }
        ThreadToolState::Running(state) => {
            bytes = bytes.saturating_add(state.streamed_output().len() as u64);
        }
        ThreadToolState::Succeeded(state) => {
            bytes = bytes.saturating_add(tool_output_bytes(state.output()));
        }
        ThreadToolState::Failed(state) => {
            bytes = bytes
                .saturating_add(state.failure().message().len() as u64)
                .saturating_add(state.output().map_or(0, tool_output_bytes));
        }
        ThreadToolState::Denied(state) => {
            bytes = bytes.saturating_add(state.reason().len() as u64);
        }
        ThreadToolState::Cancelled(state) => {
            bytes = bytes.saturating_add(state.reason().len() as u64);
        }
    }
    if let Some(user_input) = tool.user_input() {
        bytes = bytes.saturating_add(user_input_bytes(user_input));
    }
    if let Some(wait) = tool.wait() {
        bytes = bytes.saturating_add(wait_bytes(wait));
    }
    bytes
}

fn wait_bytes(wait: &pl_protocol::ThreadWaitPresentation) -> u64 {
    match wait.intent() {
        pl_protocol::ThreadWaitIntent::Events { targets, .. } => {
            targets
                .iter()
                .fold(RETAINED_ENTRY_OVERHEAD, |total, target| {
                    total
                        .saturating_add(target.task_id().len() as u64)
                        .saturating_add(optional_bytes(target.tool_name()))
                        .saturating_add(optional_bytes(target.summary()))
                        .saturating_add(RETAINED_ENTRY_OVERHEAD)
                })
        }
        pl_protocol::ThreadWaitIntent::Timer { .. } => RETAINED_ENTRY_OVERHEAD,
    }
}

/// Question bodies of one user-input request, shared by every owner of [`UserQuestion`].
///
/// Both owners of the same questions — the tool item's typed history projection and the status
/// feed's interaction event — score them with this one formula: header, question and option bodies
/// plus a fixed entry shell per question and per option. A pending question's id is not charged;
/// an accepted answer names it by id and that answer entry is charged on resolution, which is the
/// split the tool-item estimate has always used.
fn user_questions_bytes(questions: &[UserQuestion]) -> u64 {
    questions.iter().fold(0_u64, |total, question| {
        total
            .saturating_add(question.header.len() as u64)
            .saturating_add(question.question.len() as u64)
            .saturating_add(question.options.as_ref().map_or(0, |options| {
                options.iter().fold(0_u64, |total, option| {
                    total
                        .saturating_add(option.label.len() as u64)
                        .saturating_add(option.description.len() as u64)
                        .saturating_add(RETAINED_ENTRY_OVERHEAD)
                })
            }))
            .saturating_add(RETAINED_ENTRY_OVERHEAD)
    })
}

/// Questions and accepted answers of one user-input history projection.
///
/// The question bodies and the answer values are resident here and in the content fields the window
/// delivers, so the residency estimate charges every one of them exactly once per item.
fn user_input_bytes(user_input: &pl_protocol::ThreadToolUserInput) -> u64 {
    let questions = user_questions_bytes(user_input.questions()).saturating_add(
        user_input.plan_document().map_or(0, |identity| {
            (identity.content_hash.len() as u64).saturating_add(RETAINED_ENTRY_OVERHEAD)
        }),
    );
    user_input
        .answers()
        .iter()
        .fold(questions, |total, answer| {
            answer.answers().iter().fold(
                total.saturating_add(answer.question_id().len() as u64),
                |total, value| {
                    total
                        .saturating_add(value.len() as u64)
                        .saturating_add(RETAINED_ENTRY_OVERHEAD)
                },
            )
        })
}

/// Result, attachment metadata and opaque artifacts of one terminal tool output.
fn tool_output_bytes(output: &ThreadToolOutput) -> u64 {
    (output.result().len() as u64)
        .saturating_add(attachments_bytes(output.attachments()))
        .saturating_add(
            output
                .output_artifacts()
                .iter()
                .fold(0_u64, |total, artifact| {
                    total.saturating_add(json_bytes(artifact))
                }),
        )
}

/// Resident size of one opaque JSON body, walked in place instead of re-serialized.
fn json_bytes(value: &serde_json::Value) -> u64 {
    match value {
        serde_json::Value::Null | serde_json::Value::Bool(_) => 8,
        serde_json::Value::Number(_) => 16,
        serde_json::Value::String(text) => text.len() as u64,
        serde_json::Value::Array(values) => values.iter().fold(0_u64, |total, value| {
            total.saturating_add(json_bytes(value))
        }),
        serde_json::Value::Object(entries) => entries.iter().fold(0_u64, |total, (key, value)| {
            total
                .saturating_add(key.len() as u64)
                .saturating_add(json_bytes(value))
        }),
    }
}

/// Identity and state bodies of one agent item.
fn agent_bytes(agent: &ThreadAgentItem) -> u64 {
    let identity = agent.identity();
    let mut bytes = 0_u64;
    for text in [
        identity.id(),
        identity.path(),
        identity.role(),
        identity.task(),
    ] {
        bytes = bytes.saturating_add(text.len() as u64);
    }
    bytes = bytes.saturating_add(optional_bytes(identity.parent_path()));
    match agent.state() {
        ThreadAgentState::Queued(_) | ThreadAgentState::Running(_) => {}
        ThreadAgentState::Succeeded(state) => {
            bytes = bytes.saturating_add(state.summary().len() as u64);
        }
        ThreadAgentState::Denied(state) => {
            bytes = bytes.saturating_add(state.reason().len() as u64);
        }
        ThreadAgentState::Cancelled(state) => {
            bytes = bytes.saturating_add(state.reason().len() as u64);
        }
        ThreadAgentState::Failed(state) => {
            bytes = bytes.saturating_add(state.error().len() as u64);
        }
    }
    bytes
}

/// Identity and diagnostic bodies of one inference item.
fn inference_bytes(inference: &ThreadInferenceItem) -> u64 {
    let mut bytes =
        (inference.inference_id().len() as u64).saturating_add(inference.model().len() as u64);
    match inference.state() {
        ThreadInferenceState::Running(_) | ThreadInferenceState::Completed(_) => {}
        ThreadInferenceState::Failed(state) => {
            bytes = bytes.saturating_add(state.error().len() as u64);
        }
        ThreadInferenceState::Cancelled(state) => {
            bytes = bytes.saturating_add(state.reason().len() as u64);
        }
    }
    bytes
}

/// Bodies of one Skill activation item.
fn skill_bytes(skill: &ThreadSkillItem) -> u64 {
    let activation = skill.activation();
    let mut bytes = 0_u64;
    for text in [
        activation.name.as_str(),
        activation.source.as_str(),
        activation.provider_id.as_str(),
        activation.turn_id.as_str(),
    ] {
        bytes = bytes.saturating_add(text.len() as u64);
    }
    bytes = bytes.saturating_add(match &activation.cause {
        SkillActivationCause::Tool { tool_call_id } => tool_call_id.len() as u64,
        SkillActivationCause::UserGesture { invocation_id } => invocation_id.len() as u64,
    });
    bytes.saturating_add(match &activation.resource_base {
        SkillActivationResourceBase::Directory { path } => path.len() as u64,
        SkillActivationResourceBase::Url { url } => url.len() as u64,
        SkillActivationResourceBase::Opaque { description } => description.len() as u64,
    })
}

/// Variable-length diagnostics one Turn lifecycle state holds beyond its inline scalars.
///
/// The state's scalar shell is already part of `Turn`'s inline layout, so only owned strings are
/// charged: a failed Turn's structured failure, a coalesced cancellation's target identity and a
/// budget rollover's error. Every other variant carries only timestamps and copied discriminants.
fn turn_state_bytes(state: &pl_protocol::TurnState) -> u64 {
    match state {
        pl_protocol::TurnState::Queued(_) | pl_protocol::TurnState::Running(_) => 0,
        pl_protocol::TurnState::Completed(_) => 0,
        pl_protocol::TurnState::Cancelled(state) => match state.cause() {
            TurnCancellationCause::Coalesced { target_turn_id } => target_turn_id.len() as u64,
            TurnCancellationCause::Unspecified
            | TurnCancellationCause::UserRequested
            | TurnCancellationCause::RuntimeShutdown
            | TurnCancellationCause::AgentClosed
            | TurnCancellationCause::Interrupted
            | TurnCancellationCause::Recovery => 0,
        },
        pl_protocol::TurnState::Failed(state) => {
            let failure = state.failure();
            optional_bytes(failure.code.as_deref()).saturating_add(failure.message.len() as u64)
        }
        pl_protocol::TurnState::BudgetLimited(state) => match state.rollover() {
            TurnRolloverOutcome::Failed { error } => error.len() as u64,
            TurnRolloverOutcome::NotAttempted | TurnRolloverOutcome::Succeeded => 0,
        },
    }
}

/// Variable-length bodies one interaction aggregate holds beyond its inline shells.
///
/// The interaction is boxed inside [`LiveEvent`], so its heap shell is charged separately by
/// [`LiveEvent::retained_bytes`]; this walks only the owned strings, the question and answer bodies
/// and the opaque approval arguments.
pub(super) fn interaction_request_bytes(interaction: &InteractionRequest) -> u64 {
    let scope = &interaction.scope;
    let mut bytes = (interaction.interaction_id.len() as u64)
        .saturating_add(scope.thread_id.len() as u64)
        .saturating_add(scope.turn_id.len() as u64)
        .saturating_add(optional_bytes(scope.item_id.as_deref()))
        .saturating_add(optional_bytes(scope.tool_id.as_deref()))
        .saturating_add(optional_bytes(scope.agent_path.as_deref()))
        .saturating_add(interaction_purpose_bytes(&scope.purpose))
        .saturating_add(interaction_content_bytes(&interaction.content));
    if let Some(continuation) = &interaction.continuation {
        bytes = bytes.saturating_add(match &continuation.message {
            InteractionContinuationMessage::Resolution => 0,
            InteractionContinuationMessage::Question { question_id } => question_id.len() as u64,
        });
    }
    bytes
}

/// Owned identity strings one interaction purpose carries; the general purpose carries none.
fn interaction_purpose_bytes(purpose: &InteractionPurpose) -> u64 {
    match purpose {
        InteractionPurpose::General => 0,
        InteractionPurpose::AgentSessionPlanConfirmation(purpose) => (purpose.operation_id.len()
            as u64)
            .saturating_add(purpose.argument_hash.len() as u64)
            .saturating_add(purpose.plan_hash.len() as u64),
    }
}

/// Event-only estimate of one user-input request's questions.
///
/// Unlike the shared history formula ([`user_questions_bytes`]), a status-feed
/// event keeps every question — pending or resolved — resident on its own, so
/// each question's id is charged here. The slice arrives through a borrowed
/// `&[UserQuestion]`, whose capacity is not public; the element shells are
/// therefore a logical estimate over the initialized elements, and each public
/// `String`/`Vec` body is charged by its visible capacity plus element shells.
/// Inline `String`/`Vec` stack shells are already part of
/// `size_of::<UserQuestion>()` and are never charged twice.
fn event_user_questions_bytes(questions: &[UserQuestion]) -> u64 {
    let mut bytes =
        (std::mem::size_of::<UserQuestion>() as u64).saturating_mul(questions.len() as u64);
    for question in questions {
        bytes = bytes
            .saturating_add(question.id.capacity() as u64)
            .saturating_add(question.header.capacity() as u64)
            .saturating_add(question.question.capacity() as u64);
        if let Some(options) = &question.options {
            bytes = bytes.saturating_add(
                (std::mem::size_of::<UserQuestionOption>() as u64)
                    .saturating_mul(options.capacity() as u64),
            );
            for option in options {
                bytes = bytes
                    .saturating_add(option.label.capacity() as u64)
                    .saturating_add(option.description.capacity() as u64);
            }
        }
    }
    bytes
}

/// Event-only recursive heap estimate of one opaque JSON body.
///
/// Scalars carry no heap of their own; a string charges its visible capacity,
/// an array charges its capacity in `Value` shells plus each element's dynamic
/// bodies, and an object charges one logical entry shell per visible
/// `(key, value)` pair plus both sides' dynamic bodies. This intentionally does
/// not guess private map-node or allocator metadata, which the budget contract
/// already documents as out of scope.
fn event_json_heap_bytes(value: &serde_json::Value) -> u64 {
    match value {
        serde_json::Value::Null | serde_json::Value::Bool(_) | serde_json::Value::Number(_) => 0,
        serde_json::Value::String(text) => text.capacity() as u64,
        serde_json::Value::Array(values) => {
            let mut bytes = (std::mem::size_of::<serde_json::Value>() as u64)
                .saturating_mul(values.capacity() as u64);
            for value in values {
                bytes = bytes.saturating_add(event_json_heap_bytes(value));
            }
            bytes
        }
        serde_json::Value::Object(entries) => {
            let entry_shell = (std::mem::size_of::<String>() as u64)
                .saturating_add(std::mem::size_of::<serde_json::Value>() as u64);
            let mut bytes = 0_u64;
            for (key, value) in entries {
                bytes = bytes
                    .saturating_add(entry_shell)
                    .saturating_add(key.capacity() as u64)
                    .saturating_add(event_json_heap_bytes(value));
            }
            bytes
        }
    }
}

/// Questions, answers and approval bodies of one interaction's typed content.
///
/// This is the status-feed event path: questions use [`event_user_questions_bytes`]
/// (every pending id is charged) and approval arguments use the event-only JSON
/// heap walk, keeping the shared history formula untouched.
fn interaction_content_bytes(content: &InteractionContent) -> u64 {
    match content {
        InteractionContent::UserInput(user_input) => {
            event_user_questions_bytes(user_input.questions())
                .saturating_add(user_input_state_bytes(user_input.state()))
        }
        InteractionContent::ToolApproval(tool_approval) => {
            let request = tool_approval.request();
            (request.name.len() as u64)
                .saturating_add(event_json_heap_bytes(&request.arguments))
                .saturating_add(optional_bytes(request.working_directory.as_deref()))
                .saturating_add(optional_bytes(request.parent_agent_id.as_deref()))
                .saturating_add(tool_approval_state_bytes(tool_approval.state()))
        }
    }
}

/// Operation identities, accepted answers and cancellation reasons of one user-input interaction.
///
/// Event-path estimate: every public `String` charges its visible capacity, the
/// resolved answer map pays one logical entry shell per visible `(key, value)`
/// pair (the private hash node stays uncharged), and each answer's `Vec` pays
/// its capacity in `String` shells plus the strings' own dynamic bodies. Inline
/// stack shells already sit inside the entry shell and are never re-charged.
fn user_input_state_bytes(state: &UserInputState) -> u64 {
    match state {
        UserInputState::Pending(state) => state.operation_id().len() as u64,
        UserInputState::Resolved(state) => {
            let entry_shell = (std::mem::size_of::<String>() as u64)
                .saturating_add(std::mem::size_of::<UserInputAnswer>() as u64);
            let mut bytes = state.operation_id().len() as u64;
            for (question_id, answer) in state.answers() {
                bytes = bytes
                    .saturating_add(entry_shell)
                    .saturating_add(question_id.capacity() as u64)
                    .saturating_add(
                        (std::mem::size_of::<String>() as u64)
                            .saturating_mul(answer.answers.capacity() as u64),
                    );
                for value in &answer.answers {
                    bytes = bytes.saturating_add(value.capacity() as u64);
                }
            }
            bytes
        }
        UserInputState::Cancelled(state) => {
            (state.operation_id().len() as u64).saturating_add(state.reason().len() as u64)
        }
        UserInputState::Expired(state) => state.operation_id().len() as u64,
    }
}

/// Operation identities and decision reasons of one tool-approval interaction.
fn tool_approval_state_bytes(state: &ToolApprovalState) -> u64 {
    match state {
        ToolApprovalState::Pending(state) => state.operation_id().len() as u64,
        ToolApprovalState::Resolved(state) => {
            (state.operation_id().len() as u64).saturating_add(optional_bytes(state.reason()))
        }
        ToolApprovalState::Cancelled(state) => {
            (state.operation_id().len() as u64).saturating_add(state.reason().len() as u64)
        }
        ToolApprovalState::Expired(state) => state.operation_id().len() as u64,
    }
}

/// The facts a parent/child report and the directory summary need from one Turn.
///
/// The report is the committed **result** plus the stable identities it belongs to — not the
/// Turn's process bodies. Keeping this accumulator instead of the Turn's whole item set is what
/// bounds the live projection's memory: the final text, a bounded commentary fallback, the newest
/// tool item and every identity the Turn produced.
///
/// Text facts are keyed by identity and ordinal, so a later revision of the same body replaces its
/// entry instead of appending a second copy: an uncommitted streaming preview and the committed
/// item it finalizes share one key, a Turn that rewrote its own summary keeps only the latest text,
/// and the report never grows with the number of revisions a long Turn committed.
#[derive(Debug, Default, Clone)]
pub(in crate::studio) struct TurnResult {
    identities: BTreeSet<String>,
    identity_bytes: u64,
    finals: BTreeMap<(u64, String), String>,
    /// Tail of the visible commentary, used only when the Turn committed no final text.
    commentary: BTreeMap<(u64, String), String>,
    last_tool: Option<(u64, ThreadToolItem)>,
    pub(in crate::studio) finish: Option<pl_tool::finish_turn::SavedFinishTurn>,
}

impl TurnResult {
    /// Every identity the Turn committed, in no particular order.
    pub(in crate::studio) fn identities(&self) -> impl Iterator<Item = &str> {
        self.identities.iter().map(String::as_str)
    }

    /// The committed final text, or `None` when the Turn committed none.
    pub(in crate::studio) fn final_text(&self) -> Option<String> {
        let text = self
            .finals
            .values()
            .cloned()
            .collect::<Vec<_>>()
            .join("\n\n");
        (!text.is_empty()).then_some(text)
    }

    /// The bounded commentary tail, joined; the fallback description of a Turn without a summary.
    pub(in crate::studio) fn commentary(&self) -> String {
        self.commentary
            .values()
            .cloned()
            .collect::<Vec<_>>()
            .join("\n\n")
    }

    /// The newest committed tool item, used when the Turn produced no final text.
    pub(in crate::studio) fn last_tool(&self) -> Option<&ThreadToolItem> {
        self.last_tool.as_ref().map(|(_, tool)| tool)
    }

    /// Bytes this Turn's report facts retain: the texts kept in full plus one shell per entry.
    /// Identity charges are accumulated at insertion; the accumulator's own fixed size is charged too.
    ///
    /// The report needs these texts, so a Turn under storage pressure keeps them instead of losing
    /// its result: the value is what the Thread's reliable budget charges, which is how a Turn that
    /// would otherwise grow its accumulator without bound becomes visible pressure.
    pub(in crate::studio) fn retained_bytes(&self) -> u64 {
        let mut bytes = self
            .identity_bytes
            .saturating_add(std::mem::size_of::<u64>() as u64);
        for (key, text) in self.finals.iter().chain(self.commentary.iter()) {
            bytes = bytes
                .saturating_add(key.1.len() as u64)
                .saturating_add(text.len() as u64)
                .saturating_add(RETAINED_ENTRY_OVERHEAD);
        }
        if let Some((_, tool)) = &self.last_tool {
            bytes = bytes.saturating_add(tool_bytes(tool));
        }
        if let Some(finish) = &self.finish {
            bytes = bytes
                .saturating_add(finish.message.len() as u64)
                .saturating_add(
                    finish
                        .feedback_message
                        .as_ref()
                        .map_or(0, |body| body.len()) as u64,
                )
                .saturating_add(finish.review.as_ref().map_or(0, |review| {
                    review.summary.len() + review.reviewed_version.len()
                }) as u64);
        }
        bytes
    }

    /// Adds one committed payload to the Turn's result facts.
    fn observe(&mut self, item: &ThreadItem) {
        if self.identities.insert(item.id.clone()) {
            self.identity_bytes = self
                .identity_bytes
                .saturating_add(item.id.len() as u64)
                .saturating_add(RETAINED_ENTRY_OVERHEAD);
        }
        if let Some(tool) = item.tool() {
            let newest = self
                .last_tool
                .as_ref()
                .is_none_or(|(ordinal, _)| item.ordinal >= *ordinal);
            if newest {
                self.last_tool = Some((item.ordinal, tool.clone()));
            }
        }
        if let Some(text) = item.text() {
            let key = (item.ordinal, item.id.clone());
            match text.channel() {
                ThreadTextChannel::Final => {
                    self.finals.insert(key, text.text().to_owned());
                }
                ThreadTextChannel::Commentary => {
                    self.commentary.insert(key, text.text().to_owned());
                    // The tail is a diagnostic fallback, not a second process log: keep only the
                    // newest parts and drop the oldest by their canonical placement.
                    while self.commentary.len() > TURN_COMMENTARY_PARTS {
                        let oldest = self
                            .commentary
                            .keys()
                            .next()
                            .cloned()
                            .expect("commentary is non-empty");
                        self.commentary.remove(&oldest);
                    }
                }
                _ => {}
            }
        }
    }

    /// Result facts of one durable Turn slice, used by the cold recovery paths.
    pub(in crate::studio) fn from_items(items: &[ThreadItem]) -> Self {
        let mut result = Self::default();
        for item in items {
            result.observe(item);
        }
        result
    }
}

/// Ordinal, revision and creation stamp of one identity the projection has already published.
///
/// A later revision of the same identity is stamped from this instead of a storage lookup. The body
/// itself is only kept while it can still change, so this metadata is what makes "release the
/// process body" safe without losing the identity's canonical placement.
#[derive(Debug, Clone)]
struct Fact {
    ordinal: u64,
    revision: u64,
    created_at: i64,
    turn_id: String,
}

impl Fact {
    /// Stand-in payload for an identity whose body left the live window.
    ///
    /// The projection only reads placement metadata and identity presence from it; a projection
    /// that needs the released body itself (re-projecting a pruned tool call) fails closed instead
    /// of inventing content.
    fn placeholder(&self, id: &str, thread_id: &str) -> ThreadItem {
        ThreadItem::new(
            id.to_owned(),
            thread_id.to_owned(),
            self.turn_id.clone(),
            self.ordinal,
            self.revision,
            self.created_at,
            self.created_at,
            ThreadItemState::Raw(ThreadRawItem::stored(
                Vec::new(),
                "This item's body is no longer resident in the live window.",
                self.created_at,
            )),
        )
    }
}

mod observations;
/// Folds admitted writes into the live product facts and yields the changes each one made.
mod provenance;

pub(in crate::studio) struct LiveProjection {
    atom_starts: BTreeMap<String, pl_protocol::ChatAtom>,
    source_states: BTreeMap<pl_protocol::ChatSourceId, pl_protocol::ChatSourceState>,
    provenance_restored: bool,
    /// Canonical payloads of identities that can still change.
    ///
    /// A non-terminal item is updated by a later effect, and the newest Turn's tool items are
    /// re-projected by a late delivery, so their bodies stay. A terminal body that can no longer
    /// change is released: durable history and the frozen completion records own the presentation
    /// from then on.
    items: BTreeMap<String, ThreadItem>,
    /// Placement metadata of every identity inside the retained window.
    facts: BTreeMap<String, Fact>,
    /// Report facts of the newest Turn.
    results: BTreeMap<String, TurnResult>,
    /// Hidden input identities this projection has learned from effects or the cold seed.
    hidden_inputs: BTreeSet<String>,
    /// Turns already announced on the feed, so a repeat is reported as an update.
    turns_seen: BTreeSet<String>,
    /// Last phase already published for each running Turn.
    ///
    /// The Turn record only changes when a Turn starts or finishes, but the canonical phase is
    /// derived from running tasks and the newest attempt outcome. Keeping the published phase lets
    /// the projection emit a `turnUpdated` frame for each real phase transition instead of leaving
    /// the activity row at the phase captured when the Turn started.
    turn_phases: BTreeMap<String, TurnPhase>,
    turn_failures: BTreeMap<String, pl_protocol::TurnFailure>,
    /// Identity of the attempt the resident streaming previews belong to.
    ///
    /// A new attempt uses entirely new observation identities, so the caches of the previous one no
    /// longer apply.
    preview_attempt: Option<String>,
    /// Confirmed terminal prefix of the current model generation. Its weak
    /// layout identity retains no completed bodies or per-part key inventory.
    retired_model_prefix: Option<(u32, pl_core::model::ModelPartsPrefix, usize)>,
    /// In-flight streaming previews keyed by their stable identity.
    ///
    /// Each observation snapshot carries its own content version and only an identity whose version
    /// advanced is re-delivered; the hot path only clones the shared `Arc<ContentBlock>`, and the
    /// terminal commit replaces the same identity directly.
    previews: BTreeMap<String, LivePreview>,
    /// Newest observation version delivered per provider/aggregate identity.
    ///
    /// It mirrors exactly the `observed_version` of every provider/aggregate entry in
    /// [`LiveProjection::previews`], which is keyed by the long projection id the session contract
    /// needs; this short-keyed index is what the streaming hot path compares, so an unchanged part
    /// never rebuilds that id and never re-walks the long common prefix of every sibling key. The
    /// two can never disagree: every insert or removal of a provider preview moves both, and
    /// [`LiveProjection::retain`] re-derives this index from the entries that survived.
    observed: HashMap<ObservedKey, ObservedVersion>,
    /// Content version of every window item, owned by this projection and independent of the
    /// execution commit sequence.
    ///
    /// It is the source of the execution `ThreadItem::revision`: it advances on first delivery and whenever the
    /// body, structure or terminal state really changed, and otherwise keeps its old value. A
    /// streaming preview and its terminal commit therefore converge on one counter; the effect
    /// sequence stays only the commit / reliable-save watermark and no longer bounds the item
    /// version. A save confirmation does not advance the version, but any transition of the
    /// **persistable payload** (body, tool state, execution terminal) does — otherwise an old
    /// receipt would confirm a payload it never wrote.
    ///
    /// The version is the identity's own monotonic fact, not a property of this cache: an identity
    /// that was evicted from the retained window, or re-encountered after the projection was
    /// re-seeded, recovers its baseline from the canonical fact it was seeded with
    /// ([`LiveProjection::adopt_revisions`]) instead of restarting at 1.
    revisions: BTreeMap<String, u64>,
    /// Running retained-byte totals of the four tables that grow with a response.
    ///
    /// `retained_bytes` is the projection's only budget input and is published on every preview
    /// frame, so recomputing these totals from the tables on that path costs O(parts) per frame
    /// while a real change moves a single entry. Each mutation keeps them exact, and
    /// [`LiveProjection::retain`] re-derives them after actual pruning. Its predicates, window
    /// ordering and shared order-index retention still run on every commit; only a pass without
    /// removals can keep these already-current totals and the observation mirror unchanged.
    items_bytes: u64,
    facts_bytes: u64,
    previews_bytes: u64,
    revisions_bytes: u64,
    /// The Runtime's shared execution-order index of this Thread, resolved once and cached.
    ///
    /// It is the same index the kernel's synchronous presentation reservations draw from, so an
    /// identity's preview frame and its terminal commit resolve one ordinal from one allocator.
    order_index: Option<Arc<RuntimeOrderIndex>>,
    execution_history: Option<crate::studio::storage::history::HistoryStore>,
    current: super::current::CurrentOwner,
    presentation: super::presentation::PresentationHandle,
    presentation_restored: bool,
}

impl Drop for LiveProjection {
    fn drop(&mut self) {
        if let Some(index) = &self.order_index {
            // The original fact owner is leaving. Pending saves and real live
            // sources keep their own protection after these references retire.
            let removed = std::mem::take(&mut self.facts).into_keys().collect();
            index.retain::<()>(&BTreeMap::new(), removed);
        }
    }
}

impl LiveProjection {
    /// Creates an empty projection owner.
    ///
    /// The caller seeds it with the durable facts of unfinished work while installing the Thread's
    /// observation, once, before any commit is projected.
    pub(in crate::studio) fn new() -> Self {
        Self {
            atom_starts: BTreeMap::new(),
            source_states: BTreeMap::new(),
            provenance_restored: false,
            items: BTreeMap::new(),
            facts: BTreeMap::new(),
            results: BTreeMap::new(),
            hidden_inputs: BTreeSet::new(),
            turns_seen: BTreeSet::new(),
            turn_phases: BTreeMap::new(),
            turn_failures: BTreeMap::new(),
            preview_attempt: None,
            retired_model_prefix: None,
            previews: BTreeMap::new(),
            observed: HashMap::new(),
            revisions: BTreeMap::new(),
            order_index: None,
            execution_history: None,
            current: Default::default(),
            presentation: Default::default(),
            presentation_restored: false,
            items_bytes: 0,
            facts_bytes: 0,
            previews_bytes: 0,
            revisions_bytes: 0,
        }
    }

    /// Bind the channel-owned allocation authority and exact durable lookup boundary once.
    pub(in crate::studio) fn bind_execution_history(
        &mut self,
        index: Arc<RuntimeOrderIndex>,
        history: crate::studio::storage::history::HistoryStore,
    ) -> Result<(), ProjectionError> {
        if self.order_index.is_some() || self.execution_history.is_some() {
            return Err(ProjectionError::History(
                "execution history is already bound".into(),
            ));
        }
        self.order_index = Some(index);
        self.execution_history = Some(history);
        Ok(())
    }
    pub(in crate::studio) fn bind_conversation_identity(
        &mut self,
        database_id: String,
    ) -> Result<(), ProjectionError> {
        self.current
            .bind(database_id)
            .map_err(|error| ProjectionError::History(error.to_string()))?;
        Ok(())
    }

    async fn ensure_database_identity(&mut self) -> Result<(), ProjectionError> {
        if self.current.database_id().is_none() {
            let database_id = self
                .execution_history
                .as_ref()
                .ok_or_else(|| ProjectionError::History("execution history is not bound".into()))?
                .conversation_database_id()
                .await
                .map_err(|error| ProjectionError::History(error.to_string()))?
                .ok_or_else(|| {
                    ProjectionError::History(
                        "execution database has not crossed initialization".into(),
                    )
                })?;
            self.current
                .bind(database_id)
                .map_err(|error| ProjectionError::History(error.to_string()))?;
        }
        if !self.presentation_restored {
            let database = self.current.database_id().expect("bound identity");
            if let Some(history) = &self.execution_history {
                let seed = history
                    .display_recovery()
                    .await
                    .map_err(|error| ProjectionError::History(error.to_string()))?;
                if let Some(seed) = seed {
                    self.presentation
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner)
                        .restore(
                            database,
                            seed.published,
                            seed.last_order,
                            seed.effect,
                            seed.open,
                            seed.unfinished,
                        )
                        .map_err(|error| ProjectionError::History(error.to_string()))?;
                } else {
                    self.presentation
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner)
                        .bind(database)
                        .map_err(|error| ProjectionError::History(error.to_string()))?;
                }
            } else {
                self.presentation
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .bind(database)
                    .map_err(|error| ProjectionError::History(error.to_string()))?;
            }
            self.presentation_restored = true;
        }
        Ok(())
    }

    pub(in crate::studio) fn presentation(&self) -> super::presentation::PresentationHandle {
        self.presentation.clone()
    }

    pub(in crate::studio) fn current_state(&self) -> Option<Arc<super::CurrentState>> {
        self.current.snapshot()
    }

    /// Controlled producer progress for cross-module delivery tests; uses the real current owner.
    #[cfg(test)]
    pub(in crate::studio) fn observe_test_current(
        &mut self,
        thread: &pl_protocol::Thread,
        active: Vec<super::current::ActiveText>,
    ) -> Result<(), ProjectionError> {
        self.current
            .observe(thread, &ThreadSnapshot::default(), 0, active)
            .map_err(|error| ProjectionError::History(error.to_string()))?;
        Ok(())
    }
    pub(in crate::studio) fn current_activity(&self) -> Option<pl_protocol::ThreadActivity> {
        self.current.activity()
    }

    fn freeze_current(
        &mut self,
        thread: &pl_protocol::Thread,
        state: &ThreadSnapshot,
        effect: &ThreadEffectBatch,
    ) -> Result<
        (
            Arc<crate::studio::storage::history::conversation::current::PreparedCurrent>,
            Arc<super::CurrentState>,
        ),
        ProjectionError,
    > {
        let active = self.current_texts();
        self.sync_provenance()?;
        let (mut prepared, current) = self
            .current
            .freeze(thread, state, effect.sequence, active)
            .map_err(|error| ProjectionError::History(error.to_string()))?;
        if let Some(attempt) = &effect.attempt
            && matches!(
                attempt.outcome,
                pl_core::thread::AttemptOutcome::Interrupted
            )
        {
            Arc::make_mut(&mut prepared).recovery_interruption = Some((
                attempt.attempt_id.clone(),
                pl_protocol::ChatFactPosition {
                    effect_seq: effect.sequence,
                    suborder: 0,
                },
            ));
        }
        Ok((prepared, current))
    }

    fn current_texts(&self) -> Vec<super::current::ActiveText> {
        self.previews
            .iter()
            .filter(|(id, _)| {
                !self
                    .order_index
                    .as_ref()
                    .is_some_and(|index| index.is_sealed(id))
            })
            .flat_map(|(id, preview)| {
                let ordinal = self.facts.get(id).map_or(0, |fact| fact.ordinal);
                let text_channel = match &preview.shape {
                    ThreadItemState::Text(text) => Some(text.channel()),
                    _ => None,
                };
                preview.fields.iter().map(move |(key, block)| {
                    (
                        id.clone(),
                        key.clone(),
                        block.clone(),
                        ordinal,
                        text_channel,
                        preview.model_part,
                    )
                })
            })
            .collect()
    }

    /// Installs the durable facts of work that started before this projection existed.
    ///
    /// The caller reads the bounded slice once, while installing the observation: the newest Turn's
    /// committed items plus the hidden dispositions of the Thread's inputs. Everything the hot path
    /// resolves afterwards comes from these tables, so a commit or a preview never waits on a
    /// history reader — including for a Thread re-activated in the middle of a Turn.
    pub(in crate::studio) fn seed(&mut self, items: Vec<ThreadItem>, hidden: BTreeSet<String>) {
        // The seeded bodies already carry the content version durable history stored, so they are
        // the baseline of this projection's counter: re-encountering the same identity must never
        // restart at 1, because a lower version would be rejected by the durable row's revision
        // fence and the preview would stay stuck on the old body.
        for item in &items {
            self.raise_revision(&item.id, item.revision);
        }
        for item in items {
            self.fact(&item);
            self.observe_result(&item);
            self.committed_body(item);
        }
        self.hidden_inputs.extend(hidden);
    }

    /// Report facts of one Turn, if the projection still holds them.
    pub(in crate::studio) fn turn_result(&self, turn_id: &str) -> Option<&TurnResult> {
        self.results.get(turn_id)
    }

    /// Whether this projection still holds the committed terminal tool result for `id`.
    ///
    /// A reliable-output repair must know whether it can supplement the result in memory or has to
    /// read the already-committed body back first; only a resident terminal tool item is a body this
    /// owner can project without a durable read.
    pub(in crate::studio) fn holds_terminal_tool(&self, id: &str) -> bool {
        self.items.get(id).is_some_and(|item| {
            matches!(item.state(), ThreadItemState::Tool(tool) if tool.terminal_output().is_some())
        })
    }

    /// Whether this projection still holds the canonical tool body of `id`, in any state.
    ///
    /// A user-input interaction — an ordinary question or a Plan confirmation — lands on the call
    /// that raised it, and the answering effect carries neither the call nor its task: after a
    /// restart, or once a finished Turn leaves the retained window, this projection holds no body for
    /// that identity. Placement metadata alone is not a body — only a real tool item can carry the
    /// answer.
    pub(in crate::studio) fn holds_tool_body(&self, id: &str) -> bool {
        self.items.get(id).is_some_and(|item| item.tool().is_some())
    }

    /// The actual resident preview blocks inspected by storage fault regressions.
    #[cfg(test)]
    pub(in crate::studio) fn preview_fields(
        &self,
        id: &str,
    ) -> Option<&BTreeMap<BodyKey, Arc<ContentBlock>>> {
        self.previews.get(id).map(|entry| &entry.fields)
    }

    /// Bytes this projection currently retains in its own tables.
    ///
    /// The retained bodies, their placement metadata and the report accumulator are the projection's
    /// own resident memory: they outlive the prepared batch the writer has already written, so the
    /// Thread's reliable budget has to cover them too. The value is absolute, not cumulative, so
    /// releasing a body lowers the budget in the same step that released it.
    ///
    /// The value is read on **every** published frame, while a long response streams one part per
    /// identity; the four part-keyed tables that grow with the response therefore carry running
    /// totals that each real change moves by one entry ([`LiveProjection::store_item`],
    /// [`LiveProjection::store_fact`], [`LiveProjection::store_preview`],
    /// [`LiveProjection::raise_revision`]), so reading these four totals does not walk their tables.
    ///
    /// The remaining terms are not all equally cheap, and this is deliberately not claimed to be
    /// O(turns): `hidden_inputs`, `turns_seen` and `turn_phases` are bounded by the Thread's inputs
    /// and Turns, and a Turn's identity charge is accumulated at insertion, but
    /// [`TurnResult::retained_bytes`] still walks that Turn's kept final/commentary parts.
    /// A frame while many final parts remain resident therefore still visits those report entries;
    /// the identity accumulator does not make the whole retention query constant-time.
    pub(in crate::studio) fn retained_bytes(&self) -> u64 {
        self.retained_without_display().saturating_add(
            self.presentation
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .retained_bytes(),
        )
    }

    pub(in crate::studio) fn retained_after_display(
        &self,
        plan: &super::presentation::PresentationPlan,
    ) -> u64 {
        self.retained_without_display()
            .saturating_add(plan.retained_bytes())
    }

    fn retained_without_display(&self) -> u64 {
        let mut bytes = self
            .items_bytes
            .saturating_add(self.facts_bytes)
            .saturating_add(self.previews_bytes)
            .saturating_add(self.revisions_bytes)
            .saturating_add(self.retired_model_prefix.as_ref().map_or(0, |_| {
                std::mem::size_of::<(u32, pl_core::model::ModelPartsPrefix, usize)>() as u64
                    + RETAINED_ENTRY_OVERHEAD
            }))
            .saturating_add(self.current.retained_bytes());
        bytes = bytes
            .saturating_add(
                serde_json::to_vec(&self.atom_starts).map_or(u64::MAX, |bytes| bytes.len() as u64),
            )
            .saturating_add(
                serde_json::to_vec(&self.source_states.values().collect::<Vec<_>>())
                    .map_or(u64::MAX, |bytes| bytes.len() as u64),
            );
        for (turn_id, result) in &self.results {
            bytes = bytes
                .saturating_add(turn_id.len() as u64)
                .saturating_add(result.retained_bytes());
        }
        for identity in &self.hidden_inputs {
            bytes = bytes
                .saturating_add(identity.len() as u64)
                .saturating_add(RETAINED_ENTRY_OVERHEAD);
        }
        for turn_id in &self.turns_seen {
            bytes = bytes
                .saturating_add(turn_id.len() as u64)
                .saturating_add(RETAINED_ENTRY_OVERHEAD);
        }
        for (turn_id, failure) in &self.turn_failures {
            bytes = bytes
                .saturating_add(turn_id.len() as u64)
                .saturating_add(serde_json::to_vec(failure).map_or(0, |bytes| bytes.len() as u64));
        }
        for turn_id in self.turn_phases.keys() {
            bytes = bytes
                .saturating_add(turn_id.len() as u64)
                .saturating_add(RETAINED_ENTRY_OVERHEAD);
        }
        bytes
    }

    /// Projects one admitted write and freezes its publication work without awaiting publication.
    ///
    /// The owner must retain and charge this batch before calling `publish_prepared`. A history
    /// error or cancellation then resumes the same frozen drafts, never the projection.
    ///
    /// `deliver` controls only outward frame materialization. Phase, hidden-input and Turn identity
    /// session publication and the reliable prepared batch never depend on demand.
    ///
    /// # Errors
    /// Returns a projection failure when the effect references facts this projection cannot resolve
    /// from memory. The caller reports it, so the durable barrier fails closed with the real reason
    /// instead of writing a timeline with a hole.
    pub(in crate::studio) async fn prepare(
        &mut self,
        thread: &pl_protocol::Thread,
        effect: &ThreadEffectBatch,
        state: &ThreadSnapshot,
        deliver: bool,
    ) -> Result<(Option<Vec<LiveEvent>>, Arc<PreparedEffect>), ProjectionError> {
        self.ensure_database_identity().await?;
        let mut provenance = self.begin_provenance(effect)?;
        let display_text_visible = self.text_visibility(effect)?;
        let observation_inputs = self
            .observation_inputs(&thread.id)
            .map_err(|error| ProjectionError::History(error.to_string()))?;
        let accounting = Arc::new(super::PreparedAccounting::prepare(effect)?);
        let turns = self.prepare_turn_frames(thread, effect, state, deliver)?;
        let (items, review_delivery, mut completion_drafts) =
            self.project(thread, effect, state).await?;
        self.complete_provenance(effect, &items, &mut completion_drafts, &mut provenance)
            .await?;
        let mut events = deliver.then(Vec::new);
        self.emit_frames(thread, effect, state, turns, &mut events);
        self.retire_effect_source(effect)?;
        let (mut current, current_state) = self.freeze_current(thread, state, effect)?;
        let display_facts = provenance
            .2
            .iter()
            .chain(provenance.0.iter())
            .cloned()
            .collect::<Vec<_>>();
        let (display_observations, display_observation_plan) = self
            .retain_display_observations(
                &thread.id,
                effect.sequence,
                &display_facts,
                &display_text_visible,
                observation_inputs,
            )
            .map_err(|error| ProjectionError::History(error.to_string()))?;
        Arc::make_mut(&mut current).atom_facts = provenance.0.into();
        Arc::make_mut(&mut current).source_changes = provenance.1.into();
        // Admission, source ends and terminals are folded together only after
        // reliable retention/publication assigns the original completion seqs.
        let prepared = Arc::new(PreparedEffect {
            sequence: effect.sequence,
            committed_at: effect.committed_at,
            accounting,
            current: current.clone(),
            current_state: Some(current_state),
            display: None,
            display_atom_updates: provenance.2.into(),
            display_text_visible,
            display_observation_plan,
            display_observations,
            items: items.into(),
            completions: Arc::from(Vec::new()),
            completion_drafts: Some(completion_drafts),
            parent_report: None,
            terminal_retention: None,
            review_delivery: review_delivery.into(),
        });
        if let Some(events) = events.as_mut()
            && let Some(canonical) = super::prepared_terminal_turn(&prepared)
        {
            for event in events {
                if let LiveEvent::Turn { turn, .. } = event
                    && turn.id == canonical.id
                {
                    *turn = canonical.clone();
                }
            }
        }
        self.retain(state);
        Ok((events, prepared))
    }

    /// Projects one admitted write this owner installed *behind*: it folds the fact into memory and
    /// returns the frozen publication work, but emits no live status frames.
    ///
    /// A commit the owner had already folded into the snapshot this projection was seeded from is
    /// never replayed as a live frame — the subscriber's baseline already carries it — yet the
    /// durable writer still owes it a row, so the same single projection produces its content here.
    ///
    /// # Errors
    /// Same as [`LiveProjection::prepare`].
    pub(in crate::studio) async fn prepare_committed(
        &mut self,
        thread: &pl_protocol::Thread,
        effect: &ThreadEffectBatch,
        state: &ThreadSnapshot,
    ) -> Result<Arc<PreparedEffect>, ProjectionError> {
        self.ensure_database_identity().await?;
        let mut provenance = self.begin_provenance(effect)?;
        let display_text_visible = self.text_visibility(effect)?;
        let observation_inputs = self
            .observation_inputs(&thread.id)
            .map_err(|error| ProjectionError::History(error.to_string()))?;
        let accounting = Arc::new(super::PreparedAccounting::prepare(effect)?);
        let (items, review_delivery, mut completion_drafts) =
            self.project(thread, effect, state).await?;
        self.complete_provenance(effect, &items, &mut completion_drafts, &mut provenance)
            .await?;
        self.retire_effect_source(effect)?;
        let (mut current, current_state) = self.freeze_current(thread, state, effect)?;
        let display_facts = provenance
            .2
            .iter()
            .chain(provenance.0.iter())
            .cloned()
            .collect::<Vec<_>>();
        let (display_observations, display_observation_plan) = self
            .retain_display_observations(
                &thread.id,
                effect.sequence,
                &display_facts,
                &display_text_visible,
                observation_inputs,
            )
            .map_err(|error| ProjectionError::History(error.to_string()))?;
        Arc::make_mut(&mut current).atom_facts = provenance.0.into();
        Arc::make_mut(&mut current).source_changes = provenance.1.into();
        let prepared = Arc::new(PreparedEffect {
            sequence: effect.sequence,
            committed_at: effect.committed_at,
            accounting,
            current: current.clone(),
            current_state: Some(current_state),
            display: None,
            display_atom_updates: provenance.2.into(),
            display_text_visible,
            display_observation_plan,
            display_observations,
            items: items.into(),
            completions: Arc::from(Vec::new()),
            completion_drafts: Some(completion_drafts),
            parent_report: None,
            terminal_retention: None,
            review_delivery: review_delivery.into(),
        });
        self.retain(state);
        Ok(prepared)
    }

    fn retire_effect_source(&self, effect: &ThreadEffectBatch) -> Result<(), ProjectionError> {
        if let Some(attempt) = &effect.attempt
            && !matches!(attempt.outcome, pl_core::thread::AttemptOutcome::Running)
        {
            self.order_index_of()?.finish_source(&attempt.attempt_id);
        }
        Ok(())
    }

    /// Projects one effect's canonical content exactly once.
    ///
    /// Resident identities resolve against this projection's own tables and its channel index;
    /// a reliable identity miss is checked against durable history before allocating a new ordinal.
    /// The projected bodies are folded into this projection in the same step, so a later effect of
    /// the same Turn resolves them without a second projection or a storage lookup.
    async fn project(
        &mut self,
        thread: &pl_protocol::Thread,
        effect: &ThreadEffectBatch,
        state: &ThreadSnapshot,
    ) -> Result<
        (
            Vec<ThreadItem>,
            Vec<crate::thread_assembler::review_delivery::ReviewDeliveryFact>,
            Vec<ChatDraft>,
        ),
        ProjectionError,
    > {
        let review_delivery =
            review_delivery_facts(&thread.id, effect).map_err(ProjectionError::ReviewDelivery)?;
        let mut turn_failures = self.turn_failures.clone();
        turn_failures.retain(|turn, _| state.turns.iter().any(|record| &record.turn_id == turn));
        if let Some(attempt) = &effect.attempt {
            if let pl_core::thread::AttemptOutcome::Failed(error) = &attempt.outcome {
                turn_failures.insert(attempt.turn_id.clone(), super::turns::model_failure(error));
            } else if matches!(attempt.outcome, pl_core::thread::AttemptOutcome::Running) {
                turn_failures.remove(&attempt.turn_id);
            }
        }
        let mut hidden_inputs = self.hidden_inputs.clone();
        for change in effect.inputs.iter() {
            if let pl_core::thread::input::InputChange::Accepted(record) = change
                && super::input_presentation(record) == pl_protocol::MessagePresentation::Hidden
            {
                hidden_inputs.insert(record.input.id.clone());
            }
        }
        let provisional = super::project_effect_items(
            thread,
            state,
            effect,
            &BTreeMap::new(),
            &BTreeMap::new(),
            &BTreeSet::new(),
        )?;
        // The same identity set the durable writer enumerates: the items this effect produces,
        // the pruned inputs it still references, and the calls whose producing attempt left the
        // state. All three are resolved from the projection's own facts.
        let mut ids = provisional
            .items
            .iter()
            .map(|item| item.id.clone())
            .collect::<Vec<_>>();
        ids.extend(provisional.unresolved_inputs.iter().cloned());
        ids.extend(provisional.unresolved_calls.iter().cloned());
        // Only a channel this projection already started may be finalized by this effect. A channel
        // the response never produced must not be reserved here: reserving a name is not starting a
        // row, and an effect mentioning a channel would otherwise fabricate an empty aggregate item
        // (an empty `reasoning`/`text` row) the provider never emitted. A provider part the window
        // already showed is a started identity too: `finalize` has to name it even when the outcome's
        // own receipt cannot carry it, so this commit closes the identity the streaming frames used
        // instead of inventing a second aggregate one.
        if let Some(attempt) = &effect.attempt {
            for channel in ["reasoning", "text"] {
                let id = super::attempt_channel_id(&attempt.attempt_id, channel);
                if self.identity_is_started(&id) {
                    ids.push(id);
                }
            }
            ids.extend(self.started_provider_ids(&attempt.attempt_id));
            // Later generations can still use channel aggregates (for example Chat).
            // They must be resolved as started identities just like generation zero.
            let prefix = super::order::observation_prefix(&attempt.attempt_id);
            ids.extend(
                self.previews
                    .range(prefix.clone()..)
                    .take_while(|(id, _)| id.starts_with(&prefix))
                    .map(|(id, _)| id.clone()),
            );
        }
        let mut background_ids = Vec::new();
        if let Some(context) = &effect.context {
            let revision = match context {
                pl_core::thread::journal::ContextChange::Append { revision, .. } => *revision,
                pl_core::thread::journal::ContextChange::Replace(snapshot) => snapshot.revision,
            };
            for task in effect.tasks.iter() {
                if task
                    .acknowledgement
                    .as_ref()
                    .is_some_and(|ack| ack.context_revision == revision)
                {
                    let id = super::order::tool_background_started_id(&task.call_id);
                    if !self.completion_exists(&id).await? {
                        ids.push(id.clone());
                        background_ids.push((task.call_id.clone(), id));
                    }
                }
            }
        }
        let terminal_turns = provisional
            .items
            .iter()
            .filter(|item| matches!(item.state(), ThreadItemState::Turn(_)) && item.is_terminal())
            .map(|item| item.id.clone())
            .collect();
        let (mut existing, restored) = self
            .resolve(thread, ids, &terminal_turns, effect.sequence)
            .await?;
        // Only a bounded reception may take its committed body from the preview the window already
        // showed: the stream stopped before the provider's authoritative item, so the prefix that did
        // arrive stays on the identity it was shown on instead of being lost. A normally received
        // response always carries its complete provider parts in its own receipt, so its committed
        // content never depends on what a subscriber happened to observe.
        if let Some(attempt) = &effect.attempt {
            for (id, item) in
                self.attempt_preview_items(&thread.id, &attempt.attempt_id, &attempt.turn_id)?
            {
                // The provider part the window is showing is the body this commit must close. A
                // placement fact alone resolves to a release placeholder, so it must never beat the
                // preview that still holds the streamed text; a canonical committed payload (this
                // projection's own body) stays authoritative.
                if !self.items.contains_key(&id)
                    && (self.atom_starts.contains_key(&id)
                        || super::responses::keeps_bounded_preview(&attempt.outcome))
                {
                    existing.insert(id, item);
                }
            }
        }
        let projected = super::project_effect_items(
            thread,
            state,
            effect,
            &existing,
            &BTreeMap::new(),
            &hidden_inputs,
        )?;
        // 实时帧同样不允许带着无法补全的 identity 继续：投影失败由调用方转成报告并 fail-closed。
        projected.ensure_complete()?;
        let mut items = projected.items;
        // Model/Core already checked the final receipt against independently admitted members.
        // Their frozen product fact must not acquire the final attempt's time, source or revision.
        // A sealed presentation part is immutable, unlike mutable tool delivery metadata.
        let member_prefixes = effect
            .attempt
            .iter()
            .map(|attempt| &attempt.attempt_id)
            .chain(effect.model_members.iter().map(|member| &member.attempt_id))
            .map(|attempt| super::order::presentation_prefix(attempt))
            .collect::<BTreeSet<_>>();
        let index = self.order_index_of()?;
        items.retain(|item| {
            !(matches!(
                item.state(),
                ThreadItemState::Text(_) | ThreadItemState::Thinking(_)
            ) && index.is_sealed(&item.id)
                && member_prefixes
                    .iter()
                    .any(|prefix| item.id.starts_with(prefix)))
        });
        for item in &mut items {
            if let pl_protocol::ThreadItemState::Turn(turn) = item.state()
                && let pl_protocol::TurnState::Failed(failed) = turn.state()
                && let Some(failure) = turn_failures.get(&item.turn_id)
            {
                let state = pl_protocol::TurnState::Failed(pl_protocol::FailedTurnState::new(
                    failed.started_at(),
                    failed.completed_at(),
                    failure.clone(),
                ));
                let turn = pl_protocol::ThreadTurnItem::new(state)
                    .with_input_id(turn.input_id().map(str::to_owned));
                *item = item
                    .clone()
                    .with_state(pl_protocol::ThreadItemState::Turn(turn));
            }
        }
        // 先在候选载荷上计算内容版本；整批身份预算通过之前不修改投影自己的版本表。
        // 冷恢复的 canonical revision 仍是单调下限，已驻留身份继续使用本所有者的版本域。
        // 每一条目的内容版本由本投影自己的内容版本给出，和 effect 序号（提交 / 可靠保存水位）无关：
        // Turn 绑定、正文、结构或终态状态真的变了才递增，否则沿用旧版本（例如只推进 saved 的保存确认，
        // 或与上次完全相同的重新投影）。该版本同时被流式预览使用，因此同一身份的预览与终态沿同一个
        // 计数器收束，终态不会被预览版本挡住，旧保存回执也无法确认它没写过的新载荷。
        for item in items.iter_mut() {
            // The payload this revision was last delivered with, when this projection still knows
            // it: the deterministic comparison partner for a repeat projection.
            let previous = self
                .items
                .get(item.id.as_str())
                .or_else(|| existing.get(item.id.as_str()))
                .map(|previous| {
                    (
                        previous.ordinal,
                        previous.turn_id.clone(),
                        previous.created_at,
                        previous.updated_at,
                    )
                });
            let changed = self.content_changed(item.id.as_str(), item, &existing)?;
            let stable_terminal = self
                .items
                .get(&item.id)
                .or_else(|| existing.get(&item.id))
                .filter(|previous| {
                    !changed
                        && previous.is_terminal()
                        && matches!(previous.state(), ThreadItemState::Turn(_))
                });
            let mut current = stable_terminal.map_or_else(
                || self.revisions.get(item.id.as_str()).copied().unwrap_or(0),
                |previous| previous.revision,
            );
            if !self.items.contains_key(&item.id) {
                current = current.max(
                    existing
                        .get(&item.id)
                        .map_or(0, |previous| previous.revision),
                );
            }
            item.revision = match (current, changed) {
                (current, false) if current > 0 => current,
                _ => current.saturating_add(1),
            };
            // One `(identity, revision)` pair is one canonical payload. A repeat projection whose
            // body, structure and terminal shape are unchanged therefore keeps the placement and the
            // timestamps of the payload it was last delivered with instead of restamping the
            // projection clock: otherwise the same revision would be written twice with two
            // different payloads, and the durable row's own revision fence rejects that as a real
            // conflict. A body that did change takes the fresh stamp together with its new version.
            if !changed && let Some((ordinal, turn_id, created_at, updated_at)) = previous {
                item.ordinal = ordinal;
                item.turn_id = turn_id;
                item.created_at = created_at;
                item.updated_at = updated_at;
            }
        }
        let index = self.order_index_of()?;
        let mut backgrounds = Vec::with_capacity(background_ids.len());
        for (call_id, id) in &background_ids {
            let item = items
                .iter()
                .find(|item| item.id == super::order::tool_id(call_id))
                .ok_or_else(|| ProjectionError::MissingDurableToolCall(call_id.clone()))?;
            backgrounds.push(ExecutionMaterialization {
                item_id: id,
                ordinal: None,
                ..ExecutionMaterialization::from_item(item)
            });
        }
        let completion_drafts = self
            .prepare_completion_drafts(thread, state, effect, &items, &background_ids)
            .await?;
        let current_ids = items
            .iter()
            .map(|item| item.id.as_str())
            .collect::<BTreeSet<_>>();
        // No projection body, revision or report accumulator changes until every
        // identity and stamp in this effect has passed the same atomic budget check.
        let orders = index
            .materialize_execution_batch(
                restored
                    .iter()
                    .filter(|id| !current_ids.contains(id.as_str()))
                    .map(|id| ExecutionMaterialization::from_item(&existing[id]))
                    .chain(items.iter().map(ExecutionMaterialization::from_item))
                    .chain(backgrounds),
                effect.sequence,
            )
            .map_err(|error| ProjectionError::History(error.to_string()))?;
        for item in &mut items {
            item.ordinal = orders[&item.id];
        }
        items.sort_by_key(|item| item.ordinal);
        // Execution ordinals still order execution material, but must never
        // reorder the producer's terminal receipts before Session assigns seq.
        self.turn_failures = turn_failures;
        self.hidden_inputs = hidden_inputs;
        self.adopt_revisions(&existing);
        for item in &items {
            self.raise_revision(&item.id, item.revision);
            self.record(item.clone())?;
        }
        for delivery in effect.deliveries.iter() {
            if let Some(finish) = super::completions::committed_finish(delivery)
                && let Some(turn) = state.live_calls.get(&delivery.call_id)
            {
                self.results.entry(turn.clone()).or_default().finish = Some(finish);
            }
        }
        Ok((items, review_delivery, completion_drafts))
    }

    /// Freezes and publishes this effect's completion batch, exactly once per identity.
    ///
    /// An item contributes a completion only at its reliable completion boundary — a terminal
    /// execution fact inside an admitted effect: an accepted input is complete at acceptance, a
    /// tool result seals when its own call finishes (a sibling tool may still be running), a text
    /// or thinking part seals at the attempt's finalization or its explicit bounded-interrupted
    /// boundary, and a Turn seals at its terminal transition. Non-terminal bodies stay live facts
    /// of the runtime and never occupy the completion timeline. An identity that already sealed —
    /// including a seeded durable terminal identity or a later higher-revision execution repair —
    /// is skipped: the completion atom is immutable and one identity publishes once.
    ///
    /// # Errors
    /// Propagates the completion session's typed failures (payload conflict, sequence exhaustion,
    /// storage reads) as projection failures; nothing is marked sealed until the whole batch
    /// published.
    async fn prepare_completion_drafts(
        &self,
        thread: &pl_protocol::Thread,
        state: &ThreadSnapshot,
        effect: &ThreadEffectBatch,
        items: &[ThreadItem],
        background_ids: &[(String, String)],
    ) -> Result<Vec<ChatDraft>, ProjectionError> {
        let mut drafts = Vec::new();
        let database = self
            .current
            .database_id()
            .ok_or_else(|| ProjectionError::History("missing database identity".into()))?;
        // Completion order within an effect: accepted inputs, accepted inbox,
        // then its original terminal receipts. All share Session's one allocator.
        for (index, change) in effect.inputs.iter().enumerate() {
            if let pl_core::thread::input::InputChange::Accepted(record) = change
                && let Some(draft) = crate::studio::runtime::chat_item::accepted_input_draft(
                    thread,
                    record,
                    pl_protocol::ChatFactPosition {
                        effect_seq: effect.sequence,
                        suborder: u32::try_from(
                            index.checked_add(1).ok_or(ProjectionError::Count)?,
                        )
                        .map_err(|_| ProjectionError::Count)?,
                    },
                    effect.committed_at,
                    database,
                )?
            {
                drafts.push(draft);
            }
        }
        for (index, record) in effect.inbox.iter().enumerate() {
            // A forwarded final task result is already sealed by its real tool producer.
            if state
                .tasks
                .values()
                .chain(effect.tasks.iter())
                .any(|task| task.id == record.message.source_id)
            {
                continue;
            }
            if let Some(draft) = crate::studio::runtime::chat_item::accepted_inbox_draft(
                thread,
                record,
                pl_protocol::ChatFactPosition {
                    effect_seq: effect.sequence,
                    suborder: u32::try_from(
                        effect
                            .inputs
                            .len()
                            .checked_add(1)
                            .ok_or(ProjectionError::Count)?
                            .checked_add(index)
                            .ok_or(ProjectionError::Count)?,
                    )
                    .map_err(|_| ProjectionError::Count)?,
                },
                effect.committed_at,
                database,
            )? {
                drafts.push(draft);
            }
        }

        // An acknowledgement is an explicit Core context fact. Neither a running task nor a
        // task_id alone proves that a background receipt was actually returned.
        if let Some(context) = &effect.context {
            let (revision, records) = match context {
                pl_core::thread::journal::ContextChange::Append { revision, records } => {
                    (*revision, records.as_ref())
                }
                pl_core::thread::journal::ContextChange::Replace(snapshot) => {
                    (snapshot.revision, snapshot.records.as_ref())
                }
            };
            for task in effect.tasks.iter() {
                let Some(ack) = &task.acknowledgement else {
                    continue;
                };
                let id = super::order::tool_background_started_id(&task.call_id);
                // Use the same durable-filtered candidates as metadata materialization.
                // A durable completion may have no resident index entry after pruning;
                // checking only is_sealed again would recreate an unordered draft.
                if ack.context_revision != revision
                    || !background_ids.iter().any(|(_, candidate)| candidate == &id)
                {
                    continue;
                }
                let receipt = records.iter().find(|record| {
                    record.id == ack.record_id
                        && record.turn_id.as_deref() == Some(task.turn_id.as_str())
                        && matches!(&record.source, pl_core::context::ContextSource::ToolResult {
                            call_id, tool_id
                        } if call_id == &task.call_id && tool_id == &task.tool_id)
                }).ok_or_else(|| ProjectionError::History(
                    "background acknowledgement does not match its committed context fact".into()
                ))?;
                let item = items
                    .iter()
                    .find(|item| item.id == super::order::tool_id(&task.call_id))
                    .ok_or_else(|| ProjectionError::MissingDurableToolCall(task.call_id.clone()))?;
                let draft = background_started_draft(
                    item,
                    &task.id,
                    &super::content::text_content(&receipt.content),
                    effect.sequence,
                    effect.committed_at,
                    self.current.database_id().ok_or_else(|| {
                        ProjectionError::History("missing database identity".into())
                    })?,
                )
                .map_err(|error| ProjectionError::History(error.to_string()))?;
                drafts.push(draft);
            }
        }
        for item in items {
            if crate::studio::runtime::chat_item::atom(item).kind
                == pl_protocol::ChatAtomKind::Input
                || state.inputs.iter().any(|record| record.input.id == item.id)
                || effect.inputs.iter().any(|change| match change {
                    pl_core::thread::input::InputChange::Accepted(record) => {
                        record.input.id == item.id
                    }
                    pl_core::thread::input::InputChange::Transition { id, .. } => id == &item.id,
                })
                || state
                    .inbox
                    .iter()
                    .chain(effect.inbox.iter())
                    .any(|record| super::order::message_id(&record.message.id) == item.id)
            {
                continue;
            }
            if !completion_ready(item)
                || self.order_index_of()?.is_sealed(&item.id)
                || matches!(item.state(), ThreadItemState::Inference(_))
            {
                continue;
            }
            // A cold reliable-output repair may carry a new execution-item revision
            // without a resident completion qualification. Read that exact original
            // identity only for repair targets; never reseal its supplemented payload.
            if effect
                .delivery_repairs
                .iter()
                .any(|repair| super::order::tool_id(&repair.call_id) == item.id)
                && self.completion_exists(&item.id).await?
            {
                continue;
            }
            drafts.push(
                completion_draft_reusing(
                    item,
                    effect.sequence,
                    self.current.database_id().ok_or_else(|| {
                        ProjectionError::History("missing database identity".into())
                    })?,
                    &self.current.item_contents(),
                )
                .map_err(|error| ProjectionError::History(error.to_string()))?,
            );
        }
        Ok(drafts)
    }

    /// Publishes only the retained batch's original drafts. Every wait belongs to that batch.
    pub(in crate::studio) fn plan_display(
        &self,
        prepared: &PreparedEffect,
        records: &[Arc<ChatItem>],
    ) -> anyhow::Result<(
        super::presentation::PresentationPlan,
        Arc<super::presentation::PreparedDisplayDelta>,
    )> {
        let presentation = self
            .presentation
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let display_facts = prepared
            .display_atom_updates
            .iter()
            .filter(|atom| presentation.accepts_update(atom))
            .chain(prepared.current.atom_facts.iter())
            .cloned()
            .collect::<Vec<_>>();
        presentation.plan_visible(
            prepared.sequence,
            prepared.committed_at,
            super::presentation::DisplayInput {
                facts: &display_facts,
                visible: &prepared.display_text_visible,
                observations: Some(&prepared.display_observation_plan),
            },
            records,
            |member| {
                prepared
                    .display_observations
                    .get(&member.association_key)
                    .ok_or_else(|| anyhow::anyhow!("boundary has no retained effect observation"))?
                    .freeze()
            },
        )
    }

    pub(in crate::studio) fn apply_display(&self, plan: super::presentation::PresentationPlan) {
        self.presentation
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .apply_visible(plan);
    }

    pub(in crate::studio) fn complete_prepared(
        prepared: &mut PreparedEffect,
        records: Arc<[Arc<ChatItem>]>,
        display: Arc<super::presentation::PreparedDisplayDelta>,
    ) {
        Arc::make_mut(&mut prepared.current).display = Some(display.clone());
        prepared.display = Some(display);
        prepared.display_atom_updates = Arc::from([]);
        prepared.display_text_visible = Arc::from([]);
        prepared.display_observation_plan = Arc::new(BTreeMap::new());
        prepared.display_observations = Arc::new(BTreeMap::new());
        prepared.completions = records;
        prepared.completion_drafts = None;
    }

    /// 明确的恢复／重放入口；普通新批次由 Store 的同步准入负责。
    #[cfg(test)]
    pub(in crate::studio) async fn publish_prepared(
        &mut self,
        chat: &Session,
        prepared: &mut Arc<PreparedEffect>,
    ) -> Result<(), ProjectionError> {
        let Some(candidates) = prepared.completion_drafts.as_ref() else {
            return Ok(());
        };
        let records = if prepared.completions.is_empty() {
            let records = chat
                .publish_batch(candidates.clone())
                .await
                .map_err(|error| ProjectionError::History(error.to_string()))?;
            // The original publication remains owned by this retained batch if
            // a later fold step fails; retry must not filter its records away.
            Arc::make_mut(prepared).completions = records.clone();
            records
        } else {
            prepared.completions.clone()
        };
        for record in records.iter() {
            self.order_index_of()?
                .mark_completion(&record.header.item_id, true);
        }
        // Existing-member Active updates precede this effect's starts/terminals, so a
        // terminal of the same identity remains its final display state. This walks only
        // effect-local changes; progress/token observation never enters this path.
        let mut presentation = self
            .presentation
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let display_facts = prepared
            .display_atom_updates
            .iter()
            .filter(|atom| presentation.accepts_update(atom))
            .chain(prepared.current.atom_facts.iter())
            .cloned()
            .collect::<Vec<_>>();
        let display = presentation
            .prepare_visible(
                prepared.sequence,
                prepared.committed_at,
                super::presentation::DisplayInput {
                    facts: &display_facts,
                    visible: &prepared.display_text_visible,
                    observations: Some(&prepared.display_observation_plan),
                },
                &records,
                |member| {
                    prepared
                        .display_observations
                        .get(&member.association_key)
                        .ok_or_else(|| {
                            anyhow::anyhow!("boundary has no retained effect observation")
                        })?
                        .freeze()
                },
            )
            .map_err(|error| ProjectionError::History(error.to_string()))?;
        let prepared = Arc::make_mut(prepared);
        Arc::make_mut(&mut prepared.current).display = Some(display.clone());
        prepared.display = Some(display);
        prepared.display_atom_updates = Arc::from([]);
        prepared.display_text_visible = Arc::from([]);
        prepared.display_observation_plan = Arc::new(BTreeMap::new());
        prepared.display_observations = Arc::new(BTreeMap::new());
        prepared.completions = records;
        prepared.completion_drafts = None;
        Ok(())
    }

    async fn completion_exists(&self, id: &str) -> Result<bool, ProjectionError> {
        let index = self.order_index_of()?;
        if index.is_sealed(id) {
            return Ok(true);
        }
        if index.completion_checked(id) {
            return Ok(false);
        }
        let history = self
            .execution_history
            .as_ref()
            .ok_or_else(|| ProjectionError::History("execution history is not bound".into()))?;
        let sealed = pl_core::chat::ChatHistory::item(history, id)
            .await
            .map_err(|error| ProjectionError::History(error.to_string()))?
            .is_some();
        index.mark_completion(id, sealed);
        Ok(sealed)
    }

    /// Projects the ephemeral streaming preview the owner publishes between committed effects.
    ///
    /// Streaming text, reasoning and tool output never appear in an effect batch, so the overlay is
    /// the only projection of them. It consumes typed observations — a stable identity per provider
    /// item part, or a whole channel before the adapter itemizes the response — so it never decodes a
    /// producer payload again. The hot path writes the observation's **shared** `Arc<ContentBlock>`
    /// straight into the window's fields: it never calls `part.text()`, never JSON-encodes the whole
    /// item and never copies the full body again. An identity whose observation version did not
    /// advance neither re-materializes its body nor re-emits a frame; its static execution shape
    /// stays in this Runtime owner and is never encoded as terminal completion metadata.
    ///
    /// The preview stays a fact of this Runtime owner's bounded tables and emits no content frame
    /// of its own; the runtime's activity projection reads it from here instead of a second mirror
    /// published into the completion session. `applied` is the subscriber's committed-effect
    /// watermark;
    /// it is only the commit / reliable-save watermark and **not** the item content version, which
    /// comes from this projection's own [`LiveProjection::revisions`] — the same counter the terminal
    /// commit uses, so multi-token text is never dropped merely because the commit watermark did not
    /// move.
    pub(in crate::studio) async fn stream(
        &mut self,
        _chat: &Session,
        thread: &pl_protocol::Thread,
        state: &ThreadSnapshot,
        _applied: u64,
    ) -> Result<(), ProjectionError> {
        self.ensure_database_identity().await?;
        self.stream_model_progress(thread, state).await?;
        self.stream_tool_progress(state)?;
        let active = self.current_texts();
        self.sync_provenance()?;
        self.current
            .observe(thread, state, state.commit_sequence, active)
            .map_err(|error| ProjectionError::History(error.to_string()))?;
        if let Some(activity) = self.current.activity()
            && activity.kind == pl_protocol::ThreadActivityKind::Thinking
            && let Some(summary) = activity.thinking_summary.as_deref()
        {
            self.presentation
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .observe_thinking_summary(summary);
        }
        Ok(())
    }

    async fn stream_model_progress(
        &mut self,
        thread: &pl_protocol::Thread,
        state: &ThreadSnapshot,
    ) -> Result<(), ProjectionError> {
        let Some(preview) = state.model_progress.as_ref() else {
            self.preview_attempt = None;
            self.clear_model_previews();
            return Ok(());
        };
        let Some(attempt) = state.attempts.iter().find(|attempt| {
            attempt.attempt_id == preview.attempt_id
                && matches!(attempt.status, pl_core::thread::AttemptStatus::Running)
        }) else {
            if self.preview_attempt.as_deref() == Some(preview.attempt_id.as_str()) {
                self.preview_attempt = None;
                self.clear_model_previews();
            }
            return Ok(());
        };
        let at = crate::studio::unix_seconds();
        // A new attempt uses entirely new observation identities, so the previous attempt's caches
        // no longer apply.
        if self.preview_attempt.as_deref() != Some(preview.attempt_id.as_str()) {
            self.preview_attempt = Some(preview.attempt_id.clone());
            self.clear_model_previews();
        }
        let progress = &preview.progress;
        // The producer retires the whole-channel aggregate observation the moment it itemizes the
        // response, yet the aggregate preview rows it published before still have to leave the window
        // and this projection, otherwise the same text would show up twice.
        if progress.parts().iter().any(|part| {
            #[cfg(test)]
            super::activity::part_cost::model();
            matches!(part.identity(), ObservedPartIdentity::Provider(_))
        }) {
            for channel in [AggregateChannel::Text, AggregateChannel::Reasoning] {
                let id = aggregate_id(
                    &attempt.attempt_id,
                    progress.observation().generation,
                    channel,
                );
                let streaming = self
                    .items
                    .get(&id)
                    .is_some_and(|item| !item.state().is_terminal());
                if streaming || self.previews.contains_key(&id) {
                    self.release_item(&id);
                    self.release_preview(&id);
                }
            }
        }
        for failed in &progress.observation().failed {
            self.stream_observation_parts(
                thread,
                attempt,
                failed.generation,
                &failed.parts,
                Some(&failed.message),
            )?;
        }
        self.stream_observation_parts(
            thread,
            attempt,
            progress.observation().generation,
            progress.parts(),
            None,
        )?;
        for (id, message) in
            super::responses::recovery_notices(&attempt.attempt_id, progress.observation())
        {
            let fields = BTreeMap::from([(BodyKey::Body, ContentBlock::from_text(&message))]);
            if self
                .previews
                .get(&id)
                .is_some_and(|entry| fields_equal(&entry.fields, &fields))
            {
                continue;
            }
            let revision = self.bump_content_revision(&id);
            let order = self
                .order_index_of()?
                .reserve_observed(&attempt.attempt_id, &id)
                .map_err(|error| ProjectionError::History(error.to_string()))?;
            let created_at = self.created_at(&id, at);
            let state = ThreadItemState::Text(ThreadTextItem::new(
                ThreadTextChannel::Commentary,
                String::new(),
                Vec::new(),
                ThreadContentLifecycle::completed(at),
            ));
            self.store_fact(
                id.clone(),
                Fact {
                    ordinal: order,
                    revision,
                    created_at,
                    turn_id: attempt.turn_id.clone(),
                },
            );
            let entry = LivePreview {
                fields,
                observed: None,
                shape: static_state(&state),
                observed_version: progress.version(),
                model_part: None,
            };
            self.store_preview(id, entry);
        }
        Ok(())
    }

    fn stream_observation_parts(
        &mut self,
        _thread: &pl_protocol::Thread,
        attempt: &pl_core::thread::RequestAttempt,
        generation: u32,
        parts: &pl_core::model::ModelParts,
        failure: Option<&Arc<str>>,
    ) -> Result<(), ProjectionError> {
        let at = crate::studio::unix_seconds();
        let (prefix, prefix_end) = parts.stable_prefix();
        let mut retired = if failure.is_none() {
            self.retired_model_prefix
                .as_ref()
                .filter(|(known_generation, known_prefix, _)| {
                    *known_generation == generation && *known_prefix == prefix
                })
                .map_or(0, |(_, _, retired)| *retired)
        } else {
            0
        };
        // Consume each shared part in place, never an allocated per-frame list of observations.
        let first = retired;
        for index in first..parts.len() {
            let part = parts.get(index).expect("model part index is in range");
            #[cfg(test)]
            super::activity::part_cost::model();
            // An observation with no body yet is not a displayable preview; wait for its first byte.
            if part.is_empty() {
                continue;
            }
            // An identity whose observation version did not advance is not re-delivered, and this is
            // the one condition a long response hits for every already-delivered part on every
            // preview frame. It is decided on the observation's own short identity rather than on the
            // projection id: rebuilding that id and order-comparing its long sibling prefix for every
            // part every frame is what would make this loop cost O(parts) per frame for parts that
            // already delivered their newest body. [`LiveProjection::observed`] mirrors exactly the
            // `observed_version` of the identity's resident preview, so this skips the same set the
            // preview lookup would.
            //
            // It runs before the terminal test below because unchanged observations need no
            // further lookup in the channel's scoped identity table. Both
            // checks skip the same way (neither touches a delivered body or frame), so reordering
            // cannot pull a terminal identity back in: an advanced version still reaches, and is
            // rejected by, the terminal test.
            let key = observed_key(generation, part.identity());
            let observed_version = ObservedVersion {
                content: part.version(),
                ended: failure.is_some(),
                model_part: Some(super::current::ModelPartLocation { generation, index }),
            };
            if self.observed.get(&key) == Some(&observed_version) {
                continue;
            }
            let lifecycle = failure.map_or_else(ThreadContentLifecycle::streaming, |message| {
                ThreadContentLifecycle::failed(at, message.to_string())
            });
            let Some((id, field, static_item)) =
                observation_preview(&attempt.attempt_id, generation, part, &lifecycle)
            else {
                return Err(ProjectionError::UnsupportedOutput(
                    "provider presentation part does not match its item".into(),
                ));
            };
            // Within the still-active source, terminal identities cannot be pulled back by a later
            // frame. Ended sources were rejected before any identity or body is materialized.
            if self.identity_is_terminal(&id)
                || self
                    .items
                    .get(&id)
                    .is_some_and(|previous| previous.state().is_terminal())
            {
                // Only a continuous prefix inside the immutable filled index
                // may retire. A still-active earlier part blocks this advance.
                if failure.is_none() && index == retired && index < prefix_end {
                    retired += 1;
                }
                continue;
            }
            // The observation's own content version advanced, so this is a real body change: advance
            // this projection's content version and deliver the frame. It is never skipped because
            // "the committed revision equals the commit watermark" — the content version and the
            // commit watermark are two different facts.
            let revision = self.bump_content_revision(&id);
            let mut entry = match self.previews.get(&id).cloned() {
                Some(known) => known,
                None => {
                    // A preview's ordinal is allocated by the Runtime's shared execution-order
                    // index — the same allocator the kernel's presentation reservations and the
                    // terminal commit resolve from, so one identity keeps one ordinal across its
                    // preview, its reservation and its durable row without a history read.
                    let order = self
                        .order_index_of()?
                        .reserve_observed(&attempt.attempt_id, &id)
                        .map_err(|error| ProjectionError::History(error.to_string()))?;
                    let created_at = self.created_at(&id, at);
                    let shape = static_state(&static_item);
                    // Placement metadata, so the retained window bounds this identity like any other
                    // fact instead of keeping its body alive for the whole Turn.
                    self.store_fact(
                        id.clone(),
                        Fact {
                            ordinal: order,
                            revision,
                            created_at,
                            turn_id: attempt.turn_id.clone(),
                        },
                    );
                    LivePreview {
                        fields: BTreeMap::new(),
                        // Filled in below with the key this part already resolved, so the identity is
                        // built once per delivered part instead of once per part per frame.
                        observed: None,
                        shape,
                        observed_version: part.version(),
                        model_part: observed_version.model_part,
                    }
                }
            };
            let shape = static_state(&static_item);
            if entry.shape != shape {
                entry.shape = shape;
            }
            entry.observed = Some(key);
            entry.observed_version = part.version();
            entry.model_part = observed_version.model_part;
            entry.fields.insert(field, part.content().clone());
            self.store_preview(id, entry);
        }
        if failure.is_none() {
            self.retired_model_prefix = (retired > 0).then_some((generation, prefix, retired));
        }
        Ok(())
    }

    /// Streaming output preview of a running task: the producer's own shared content block,
    /// delivered in the `tool.result` field and keyed by the stable call identity.
    ///
    /// The Thread publishes each opaque output identity with its immutable content block and its
    /// own observation version, so this shares the newest block instead of rebuilding it from an
    /// accumulated string: an unchanged identity is recognized by version (and by pointer inside the
    /// block comparison), a changed one carries a new block, and a bounded window that rolled over
    /// arrives as a block the consumer's baseline no longer extends. No JSON is encoded and no
    /// canonical `ThreadItem` is materialized per chunk.
    fn stream_tool_progress(&mut self, state: &ThreadSnapshot) -> Result<(), ProjectionError> {
        for (task_id, progress) in state.tool_progress.iter() {
            let Some(task) = state.tasks.get(task_id) else {
                continue;
            };
            if task.status != pl_core::thread::task::TaskStatus::Running {
                continue;
            }
            // An observation with no body yet is not a displayable preview; wait for its first byte.
            if progress.bytes() == 0 {
                continue;
            }
            let id = super::order::tool_id(&task.call_id);
            // The tool identity and its static structure come from the committed canonical fact: no
            // identity is invented here that the commit does not have, and no coarser meta is
            // hand-assembled.
            let Some(committed) = self.items.get(&id).cloned() else {
                continue;
            };
            // A terminal item is never pulled back by a late streaming observation.
            if committed.state().is_terminal() {
                continue;
            }
            // Only an identity whose own version advanced is delivered: an unchanged observation
            // neither re-materializes its body nor re-emits a frame.
            if self
                .previews
                .get(&id)
                .is_some_and(|known| known.observed_version == progress.version())
            {
                continue;
            }
            let result_field = BodyKey::host(TOOL_RESULT_FIELD);
            // One shared block per identity: an unchanged window is the same `Arc`, and a rollover is
            // a different block, so the typed field diff reports a whole replacement instead of
            // appending onto a body that changed identity.
            let block = progress.content();
            // The tool identity's content version advances here so the terminal commit and the
            // preview converge on one counter even though the preview no longer leaves this owner.
            self.bump_content_revision(&id);
            let mut entry = match self.previews.get(&id).cloned() {
                Some(known) => known,
                None => {
                    // Reuse the canonical item's body partner fields, swapping only the streamed
                    // result for a shared block; the preview keeps the runtime's own shape fact.
                    LivePreview {
                        fields: crate::studio::runtime::chat_item::content_fields(
                            committed.state(),
                        )
                        .map_err(|error| ProjectionError::History(error.to_string()))?,
                        // A tool-output preview is keyed by the call identity, not by a provider
                        // observation, so it never enters the provider observation index.
                        observed: None,
                        shape: static_state(committed.state()),
                        observed_version: progress.version(),
                        model_part: None,
                    }
                }
            };
            entry.observed_version = progress.version();
            entry.fields.insert(result_field, block);
            self.store_preview(id, entry);
        }
        Ok(())
    }

    /// Raises the content-version baseline to the lower bound of the known canonical facts.
    ///
    /// The content version is each identity's own monotonic fact, not a property of this cache: when
    /// an identity was evicted from the retained window, or the projection was re-seeded and meets it
    /// again, the canonical payload resolved back already carries its version and this projection must
    /// continue from it. Restarting at 1 would be lower than the persisted old version, and the shared
    /// session would ignore the frame as stale.
    ///
    /// An identity already resident in `self.items` is left alone: while this projection holds it, its
    /// own counter is the session's authoritative baseline, and re-applying an external version would
    /// only jump it into another version domain. The ordinary path therefore never re-reads storage;
    /// only a cold identity resolved from a placement fact is raised here.
    fn adopt_revisions(&mut self, existing: &BTreeMap<String, ThreadItem>) {
        for (id, item) in existing {
            if item.revision == 0 || self.items.contains_key(id) {
                continue;
            }
            self.raise_revision(id, item.revision);
        }
    }

    /// Advances and returns one identity's new content version.
    fn bump_content_revision(&mut self, id: &str) -> u64 {
        let next = self
            .revisions
            .get(id)
            .copied()
            .unwrap_or(0)
            .saturating_add(1);
        self.raise_revision(id, next);
        next
    }

    /// Raises one identity's content-version baseline, keeping the retained-byte estimate in step.
    ///
    /// Inserting an identity's first version also inserts its charged entry, so the running total
    /// follows the table exactly; raising a version the identity already had does not change the
    /// entry's size.
    fn raise_revision(&mut self, id: &str, version: u64) {
        match self.revisions.get_mut(id) {
            Some(known) => {
                if version > *known {
                    *known = version;
                }
            }
            None => {
                self.revisions.insert(id.to_owned(), version);
                self.revisions_bytes = self.revisions_bytes.saturating_add(revision_bytes(id));
            }
        }
    }

    /// Whether this projected item differs from the **persistable payload** last delivered for it.
    ///
    /// The payload is the turn binding (a queued input/item identity that is only later bound to the
    /// Turn that consumes it, so the binding is durable content and not placement metadata), the
    /// dynamic fields ([`crate::studio::runtime::chat_item::content_fields`], compared by shared
    /// chain without materializing a body) plus the structure / terminal shape
    /// ([`crate::studio::runtime::chat_item::static_state`], covering kind, attachments, lifecycle and
    /// tool state). None of them includes the `ThreadItem` timestamps that only this projection
    /// restamps, so a repeated projection keeps its version — and with it a byte-identical payload —
    /// while a real transition (turn binding, terminal admission, tool state) always reads as a
    /// change.
    fn content_changed(
        &self,
        id: &str,
        item: &ThreadItem,
        existing: &BTreeMap<String, ThreadItem>,
    ) -> Result<bool, ProjectionError> {
        let candidate_fields = crate::studio::runtime::chat_item::content_fields(item.state())
            .map_err(|error| ProjectionError::History(error.to_string()))?;
        let candidate_shape = static_state(item.state());
        if let Some(preview) = self.previews.get(id) {
            return Ok(preview.shape != candidate_shape
                || !fields_equal(&candidate_fields, &preview.fields));
        }
        // A committed fact resident in memory wins; on cold recovery the canonical fact resolved by
        // this pass is compared the same way, so a payload identical to the stored one is not treated
        // as a first delivery and does not raise the version for nothing.
        Ok(match self.items.get(id).or_else(|| existing.get(id)) {
            Some(previous) => {
                previous.turn_id != item.turn_id
                    || static_state(previous.state()) != candidate_shape
                    || !fields_equal(
                        &candidate_fields,
                        &crate::studio::runtime::chat_item::content_fields(previous.state())
                            .map_err(|error| ProjectionError::History(error.to_string()))?,
                    )
            }
            None => true,
        })
    }

    /// Reads canonical identities without assigning placement or changing the index.
    async fn resolve(
        &self,
        thread: &pl_protocol::Thread,
        ids: impl IntoIterator<Item = String>,
        terminal_turns: &BTreeSet<String>,
        effect: u64,
    ) -> Result<ResolvedIdentities, ProjectionError> {
        let mut existing = BTreeMap::new();
        let mut restored = BTreeSet::new();
        let mut seen = BTreeSet::new();
        for id in ids {
            if !seen.insert(id.clone()) {
                continue;
            }
            if let Some(item) = self.items.get(&id) {
                existing.insert(id, item.clone());
                continue;
            }
            let placement = self
                .facts
                .get(&id)
                .map(|fact| fact.placeholder(&id, &thread.id))
                .or_else(|| {
                    self.order_index
                        .as_ref()
                        .and_then(|index| index.pending_placement(&id, &thread.id))
                });
            // A placement-only Raw shell cannot compare a sealed Turn's state
            // or normalize its real terminal clock. Recover that exact canonical
            // item on the reliable path; never reinterpret a shell as its body.
            if !terminal_turns.contains(&id)
                && let Some(item) = placement.clone()
            {
                existing.insert(id, item);
                continue;
            }
            if self
                .order_index
                .as_ref()
                .is_some_and(|index| index.is_new_reservation(&id, effect))
            {
                continue;
            }
            // Unknown and restored identities retain their explicit history validation.
            let history = self
                .execution_history
                .as_ref()
                .ok_or_else(|| ProjectionError::History("execution history is not bound".into()))?;
            if let Some(item) = history
                .item(&id)
                .await
                .map_err(|error| ProjectionError::History(error.to_string()))?
            {
                restored.insert(id.clone());
                existing.insert(id, item);
            } else if let Some(item) = placement {
                existing.insert(id, item);
            }
        }
        Ok((existing, restored))
    }

    /// The channel-owned execution-order index explicitly bound to this projection.
    ///
    /// # Errors
    /// Fails when the owner has not bound execution history.
    fn order_index_of(&self) -> Result<Arc<RuntimeOrderIndex>, ProjectionError> {
        self.order_index
            .clone()
            .ok_or_else(|| ProjectionError::History("execution history is not bound".into()))
    }

    /// Whether one identity is an execution fact this projection already knows to be terminal.
    ///
    /// This marker has the same active/pending lifetime as its execution placement. Frames from
    /// an ended source are rejected before this lookup, even after the marker was reclaimed.
    fn identity_is_terminal(&self, id: &str) -> bool {
        self.order_index
            .as_ref()
            .is_some_and(|index| index.is_terminal(id))
    }

    /// Whether one identity is a row this projection or the Runtime's order index already holds.
    ///
    /// Placement metadata alone does not make an identity started: a fact can outlive the preview
    /// it described (the window replaces an aggregate preview the moment the adapter itemizes the
    /// response), and reserving its name would fabricate a terminal row nothing ever showed.
    fn identity_is_started(&self, id: &str) -> bool {
        self.items.contains_key(id)
            || self.previews.contains_key(id)
            || self
                .order_index
                .as_ref()
                .is_some_and(|index| index.assigned(id).is_some())
    }

    /// Provider part identities this projection already showed for one attempt.
    ///
    /// The terminal commit must close the identity the streaming frames used, so every started
    /// provider part is part of the finalize set even when the outcome's own receipt cannot carry it.
    fn started_provider_ids(&self, attempt_id: &str) -> Vec<String> {
        self.provider_previews(attempt_id)
            .map(|(id, _)| id.clone())
            .collect()
    }

    /// Resident previews of one attempt's provider parts.
    ///
    /// A provider part's identity begins with its attempt's presentation prefix, and a `BTreeMap`
    /// keeps its keys in lexicographic order, so one attempt's identities are a single contiguous
    /// range: an effect that finalizes an attempt enumerates that attempt's parts instead of walking
    /// every part the response ever streamed. Only one attempt is ever resident (`stream` clears the
    /// table when the attempt changes), so the range is also bounded by the parts of that attempt.
    fn provider_previews<'a>(
        &'a self,
        attempt_id: &str,
    ) -> impl Iterator<Item = (&'a String, &'a LivePreview)> + 'a {
        let prefix = super::order::presentation_prefix(attempt_id);
        self.previews
            .range(prefix.clone()..)
            .take_while(move |(id, _)| id.starts_with(prefix.as_str()))
    }

    /// Canonical items for one attempt's in-flight provider previews.
    ///
    /// Read only for a **bounded** reception (see [`super::responses::keeps_bounded_preview`]): the
    /// Runtime preview is the one representation of the in-flight body, so the terminal projection
    /// materializes that received prefix only here instead of keeping a second body copy, and
    /// [`super::responses::finalize_missing_presentation`] closes it
    /// on the same identity. A normally received response takes its body from its own receipt instead.
    /// Only provider-part identities qualify — an aggregate channel is not a provider part, and its own
    /// liveness is decided by [`LiveProjection::identity_is_started`].
    fn attempt_preview_items(
        &self,
        thread_id: &str,
        attempt_id: &str,
        turn_id: &str,
    ) -> Result<Vec<(String, ThreadItem)>, ProjectionError> {
        self.provider_previews(attempt_id)
            .map(|(id, preview)| {
                let fact = self.facts.get(id).ok_or_else(|| {
                    ProjectionError::History(format!("preview {id} has no execution placement"))
                })?;
                // Only this bounded-interruption boundary materializes the received prefix.
                // Execution placement and lifecycle come from the Runtime's own facts, never
                // from terminal-only completion metadata or an invented append sequence.
                let text = |field| {
                    preview
                        .fields
                        .get(&field)
                        .map(|block| block.text())
                        .unwrap_or_default()
                };
                let state = match &preview.shape {
                    ThreadItemState::Text(value) => ThreadItemState::Text(ThreadTextItem::new(
                        value.channel(),
                        text(BodyKey::Body),
                        value.attachments().to_vec(),
                        value.lifecycle().clone(),
                    )),
                    ThreadItemState::Thinking(value) => {
                        ThreadItemState::Thinking(ThreadThinkingItem::new(
                            preview
                                .fields
                                .iter()
                                .filter(|(field, _)| {
                                    matches!(field, BodyKey::Part(PresentationPart::SummaryText(_)))
                                })
                                .map(|(_, block)| block.text())
                                .collect(),
                            preview
                                .fields
                                .iter()
                                .filter(|(field, _)| {
                                    matches!(
                                        field,
                                        BodyKey::Part(PresentationPart::ReasoningText(_))
                                    )
                                })
                                .map(|(_, block)| block.text())
                                .collect(),
                            value.lifecycle().clone(),
                        ))
                    }
                    _ => {
                        return Err(ProjectionError::UnsupportedOutput(
                            "provider preview is neither text nor thinking".into(),
                        ));
                    }
                };
                Ok((
                    id.clone(),
                    ThreadItem::new(
                        id.clone(),
                        thread_id.to_owned(),
                        turn_id.to_owned(),
                        fact.ordinal,
                        fact.revision,
                        fact.created_at,
                        fact.created_at,
                        state,
                    ),
                ))
            })
            .collect()
    }

    /// Maintains lifecycle continuity and optionally emits this effect's Turn and interaction frames.
    ///
    /// The frames are derived from the same effect-matched state the content was projected from, so
    /// a live subscriber and durable history describe one commit rather than two drifting views.
    fn prepare_turn_frames(
        &self,
        thread: &pl_protocol::Thread,
        effect: &ThreadEffectBatch,
        state: &ThreadSnapshot,
        deliver: bool,
    ) -> Result<BTreeMap<String, Turn>, ProjectionError> {
        let mut turns = BTreeMap::new();
        if deliver {
            for record in effect
                .turn
                .iter()
                .chain(state.turns.iter().filter(|record| {
                    record.state == TurnState::Running
                        && self.turn_phases.get(&record.turn_id)
                            != Some(&super::turns::phase(state, &record.turn_id))
                }))
            {
                let turn = super::turns::project_turn(
                    &thread.id,
                    state,
                    record,
                    effect.committed_at,
                    effect.committed_at,
                    effect.sequence,
                )?;
                turns.insert(record.turn_id.clone(), turn);
            }
        }
        Ok(turns)
    }

    fn emit_frames(
        &mut self,
        thread: &pl_protocol::Thread,
        effect: &ThreadEffectBatch,
        state: &ThreadSnapshot,
        mut turns: BTreeMap<String, Turn>,
        events: &mut Option<Vec<LiveEvent>>,
    ) {
        if let Some(record) = &effect.turn {
            let event = if record.state == TurnState::Running {
                if self.turns_seen.insert(record.turn_id.clone()) {
                    TurnEvent::Started
                } else {
                    TurnEvent::Updated
                }
            } else {
                self.turns_seen.insert(record.turn_id.clone());
                TurnEvent::Completed
            };
            if record.state == TurnState::Running {
                self.turn_phases.insert(
                    record.turn_id.clone(),
                    super::turns::phase(state, &record.turn_id),
                );
            } else {
                self.turn_phases.remove(&record.turn_id);
            }
            if let Some(events) = events.as_mut() {
                let turn = turns
                    .remove(&record.turn_id)
                    .expect("effect Turn frame was validated before projection");
                events.push(LiveEvent::Turn { turn, event });
            }
        }
        // A Turn record is only committed when a Turn starts or finishes, but a task start, a tool
        // completion or a model attempt commit changes the running Turn's derived phase. Publishing
        // each real phase transition keeps the activity row on the canonical phase instead of the
        // phase captured at Turn start. The frame carries the same revision as the item updates of
        // this effect, so a late busy frame can never outrank the terminal Turn.
        for record in state.turns.iter() {
            if record.state != TurnState::Running {
                continue;
            }
            let phase = super::turns::phase(state, &record.turn_id);
            if self.turn_phases.get(&record.turn_id) == Some(&phase) {
                continue;
            }
            self.turn_phases.insert(record.turn_id.clone(), phase);
            let event = if self.turns_seen.insert(record.turn_id.clone()) {
                TurnEvent::Started
            } else {
                TurnEvent::Updated
            };
            if let Some(events) = events.as_mut() {
                let turn = turns
                    .remove(&record.turn_id)
                    .expect("phase Turn frame was validated before projection");
                events.push(LiveEvent::Turn { turn, event });
            }
        }
        if let Some(events) = events.as_mut() {
            for record in effect.interactions.iter() {
                if let Ok(Some(interaction)) = crate::thread_assembler::project_thread_interaction(
                    &thread.id,
                    &record.request.id,
                    state,
                ) {
                    events.push(LiveEvent::Interaction(Box::new(interaction)));
                }
            }
            for permission in effect.permissions.iter() {
                if let Ok(Some(interaction)) = crate::thread_assembler::project_thread_interaction(
                    &thread.id,
                    &permission.id,
                    state,
                ) {
                    events.push(LiveEvent::Interaction(Box::new(interaction)));
                }
            }
        }
        let mut active_inputs = state
            .turns
            .iter()
            .filter_map(|turn| {
                (turn.state == TurnState::Running)
                    .then_some(turn.input_id.as_deref())
                    .flatten()
            })
            .collect::<BTreeSet<_>>();
        active_inputs.extend(state.inputs.iter().map(|record| record.input.id.as_str()));
        self.hidden_inputs
            .retain(|id| active_inputs.contains(id.as_str()));
    }

    /// Records one projected payload and keeps its revision strictly monotonic.
    ///
    /// The ordinal is the placement this projection resolved and the revision is this projection's own
    /// content version ([`LiveProjection::revisions`]), never the effect sequence that happened to
    /// commit the payload. Live frames, resubscription, the window and the durable writer therefore
    /// agree on one content version per identity, while the effect sequence stays only the commit /
    /// reliable-save watermark. A stale payload is ignored rather than renumbered.
    fn record(&mut self, item: ThreadItem) -> Result<(), ProjectionError> {
        if item.ordinal == 0 {
            return Err(ProjectionError::ItemOrder(item.id));
        }
        if self
            .items
            .get(&item.id)
            .is_some_and(|previous| previous.revision > item.revision)
        {
            // A stale payload never regresses a newer body; it produces no frame either way.
            return Ok(());
        }
        // A committed fact replaces the same identity's preview: dropping the cache makes the next
        // streaming observation rebuild its static meta and argument partner fields from the freshly
        // committed canonical fact instead of reusing a stale preview.
        self.release_preview(&item.id);
        // The channel index holds scoped terminal/completion markers alongside execution placement.
        self.fact(&item);
        self.observe_result(&item);
        self.store_item(item);
        Ok(())
    }

    /// Keeps the placement metadata of one identity that the projection may update later.
    fn fact(&mut self, item: &ThreadItem) {
        self.store_fact(
            item.id.clone(),
            Fact {
                ordinal: item.ordinal,
                revision: item.revision,
                created_at: item.created_at,
                turn_id: item.turn_id.clone(),
            },
        );
    }

    /// Retains one committed body while it can still change or be re-projected.
    fn committed_body(&mut self, item: ThreadItem) {
        self.store_item(item);
    }

    /// Stores one canonical body, keeping the retained-byte estimate in step.
    ///
    /// Replacing a body charges the difference instead of double counting it, so the running total
    /// stays the exact value [`LiveProjection::retained_bytes`] would compute from the table.
    fn store_item(&mut self, item: ThreadItem) {
        let next = charged_item_bytes(&item);
        match self.items.insert(item.id.clone(), item) {
            Some(previous) => {
                self.items_bytes = self
                    .items_bytes
                    .saturating_sub(charged_item_bytes(&previous))
                    .saturating_add(next);
            }
            None => self.items_bytes = self.items_bytes.saturating_add(next),
        }
    }

    /// Releases one canonical body, keeping the retained-byte estimate in step.
    fn release_item(&mut self, id: &str) {
        if let Some(previous) = self.items.remove(id) {
            self.items_bytes = self
                .items_bytes
                .saturating_sub(charged_item_bytes(&previous));
        }
    }

    /// Stores one placement fact, keeping the retained-byte estimate in step.
    fn store_fact(&mut self, id: String, fact: Fact) {
        if !self.facts.contains_key(&id)
            && let Some(index) = &self.order_index
        {
            index.retain_reference(&id);
        }
        let next = fact_bytes(&id, &fact);
        let id_len = id.len() as u64;
        match self.facts.insert(id, fact) {
            Some(replaced) => {
                let replaced_bytes = id_len
                    .saturating_add(replaced.turn_id.len() as u64)
                    .saturating_add(RETAINED_ENTRY_OVERHEAD);
                self.facts_bytes = self
                    .facts_bytes
                    .saturating_sub(replaced_bytes)
                    .saturating_add(next);
            }
            None => self.facts_bytes = self.facts_bytes.saturating_add(next),
        }
    }

    /// Stores one in-flight preview by projection id, keeping the byte estimate and the short-key
    /// observation index in step.
    fn store_preview(&mut self, id: String, entry: LivePreview) {
        // One formula scores both sides of the replacement (`preview_entry_bytes`), so the running
        // total moves by the exact difference instead of re-deriving a smaller hand-copied estimate
        // that could omit the observation-index term.
        let next = preview_bytes(&id, &entry);
        let id_len = id.len() as u64;
        let observed = entry.observed.clone();
        let version = ObservedVersion {
            content: entry.observed_version,
            ended: entry.shape.is_terminal(),
            model_part: entry.model_part,
        };
        match self.previews.insert(id, entry) {
            Some(replaced) => {
                let replaced_bytes = preview_entry_bytes(id_len, &replaced);
                self.previews_bytes = self
                    .previews_bytes
                    .saturating_sub(replaced_bytes)
                    .saturating_add(next);
                // One projection id is a function of one observation identity, so a replacement under
                // it always carries the same short key and this branch is unreachable in the current
                // identity derivation. It is still handled: a replaced key whose mirror entry would
                // otherwise outlive its preview is dropped here instead of quietly making the hot
                // path skip an identity the preview map no longer holds.
                if replaced.observed != observed
                    && let Some(stale) = &replaced.observed
                {
                    self.observed.remove(stale);
                }
            }
            None => self.previews_bytes = self.previews_bytes.saturating_add(next),
        }
        // The index mirrors the delivered entry's own version, so the hot path can compare it
        // without rebuilding the projection id.
        if let Some(observed) = observed {
            self.observed.insert(observed, version);
        }
    }

    /// Releases one in-flight preview by projection id, keeping the byte estimate and the short-key
    /// observation index in step.
    fn release_preview(&mut self, id: &str) {
        let Some(removed) = self.previews.remove(id) else {
            return;
        };
        self.previews_bytes = self
            .previews_bytes
            .saturating_sub(preview_bytes(id, &removed));
        if let Some(observed) = &removed.observed {
            self.observed.remove(observed);
        }
    }

    /// Model attempts do not own background tools: preserve their observation baselines until
    /// their own committed result or retained-fact release retires them.
    fn clear_model_previews(&mut self) {
        self.retired_model_prefix = None;
        self.previews.retain(|id, preview| {
            if preview.observed.is_none() || self.atom_starts.contains_key(id) {
                return true;
            }
            self.previews_bytes = self
                .previews_bytes
                .saturating_sub(preview_bytes(id, preview));
            false
        });
        self.observed.retain(|key, _| {
            self.previews
                .values()
                .any(|preview| preview.observed.as_ref() == Some(key))
        });
    }

    /// Adds one committed payload to the report facts of its Turn.
    fn observe_result(&mut self, item: &ThreadItem) {
        if item.turn_id.is_empty() {
            return;
        }
        self.results
            .entry(item.turn_id.clone())
            .or_default()
            .observe(item);
    }

    fn created_at(&self, id: &str, fallback: i64) -> i64 {
        self.facts.get(id).map_or(fallback, |fact| fact.created_at)
    }

    /// Bounds the live tables to the facts a later effect can still reference.
    ///
    /// The projection outlives many Turns, so it keeps only the newest Turn's facts plus the
    /// identities the current owner state still references. Anything older is a durable history fact
    /// a reconnect reads from SQL, and a body released here is replaced by its placement metadata so
    /// the identity itself is never mistaken for a new item.
    fn retain(&mut self, state: &ThreadSnapshot) {
        let before = (
            self.items.len(),
            self.facts.len(),
            self.previews.len(),
            self.revisions.len(),
        );
        let mut live = state
            .turns
            .iter()
            .filter(|turn| turn.state == TurnState::Running)
            .map(|turn| turn.turn_id.clone())
            .collect::<BTreeSet<_>>();
        if let Some(newest) = state.turns.last() {
            live.insert(newest.turn_id.clone());
        }
        let mut referenced = state
            .tasks
            .values()
            .filter(|task| task.status == pl_core::thread::task::TaskStatus::Running)
            .map(|task| super::order::tool_id(&task.call_id))
            .collect::<BTreeSet<_>>();
        referenced.extend(state.inputs.iter().map(|record| record.input.id.clone()));
        // A complete parent message is still mutable placement: its first model consumption
        // binds it to a Turn. Keep its canonical payload and version until the inbox releases it.
        let inbox_items = state
            .inbox
            .iter()
            .map(|record| super::order::message_id(&record.message.id))
            .collect::<BTreeSet<_>>();
        referenced.extend(inbox_items.iter().cloned());
        referenced.extend(state.interactions.values().filter_map(|record| {
            pl_core::tool::opaque::interaction_tool_call_id(&record.request.id)
                .map(super::order::tool_id)
        }));
        for attempt in state.attempts.iter() {
            referenced.insert(super::order::response_id(&attempt.attempt_id, "inference"));
            for channel in ["reasoning", "text"] {
                referenced.insert(super::attempt_channel_id(&attempt.attempt_id, channel));
            }
            // A tool result whose call belongs to a still-resident attempt is part of the same
            // unfinished Turn: a later effect of that Turn re-references the tool identity, so it is
            // as required as the attempt's own channels.
        }
        referenced.extend(
            state
                .live_calls
                .iter()
                .filter(|(_, turn)| state.turns.iter().any(|record| &record.turn_id == *turn))
                .map(|(id, _)| super::order::tool_id(id)),
        );
        // A result still owed to model context is delivered by a later effect of a live Turn, so its
        // tool identity is required until that delivery commits.
        referenced.extend(
            state
                .deliveries
                .iter()
                .map(|delivery| super::order::tool_id(&delivery.call_id)),
        );
        // A live Turn's own facts stay required for every later effect of that Turn: the input that
        // opened it (named by `turns[].input_id` after the consuming commit pruned the resident
        // record), and the Turn item itself, which each later task / phase / terminal commit
        // re-projects. Both must keep their placement fact, because an identity released here is
        // resolved again with a fresh content version: the input would surface as a hole, and the
        // re-projected Turn item would restart at revision 1 and the durable row would reject the
        // new payload as a revision conflict. The window therefore only ever releases *optional*
        // history, never an identity a live Turn still references.
        for turn in state.turns.iter() {
            if !live.contains(&turn.turn_id) {
                continue;
            }
            referenced.insert(super::order::turn_id(&turn.turn_id));
            if let Some(input_id) = &turn.input_id {
                referenced.insert(input_id.clone());
            }
        }
        let keep = |id: &str, turn_id: &str| live.contains(turn_id) || referenced.contains(id);
        let mut removed = Vec::new();
        self.facts.retain(|id, fact| {
            let retained = keep(id, &fact.turn_id);
            if !retained {
                removed.push(id.clone());
            }
            retained
        });
        self.results.retain(|turn_id, _| live.contains(turn_id));
        self.turn_phases.retain(|turn_id, _| live.contains(turn_id));
        self.turns_seen.retain(|turn_id| live.contains(turn_id));
        self.items.retain(|id, item| {
            let retained = match self.facts.get(id) {
                Some(fact) => keep(id, &fact.turn_id),
                None => false,
            };
            // A body is only worth its bytes while it can still change: a non-terminal item is
            // updated by a later effect, the newest Turn's tool items are re-projected by a late
            // delivery, and everything else keeps placement metadata only.
            retained
                && (!item.state().is_terminal()
                    || item.kind() == pl_protocol::ThreadItemKind::Tool
                    || referenced.contains(id))
        });
        // A Turn that opened more identities than the window is still bounded here: the oldest
        // non-terminal bodies and tool facts are dropped by canonical placement, and the identity
        // itself stays as placement metadata so a later effect still resolves it.
        if self.facts.len() > LIVE_ITEM_WINDOW {
            let mut placed = self
                .facts
                .iter()
                .map(|(id, fact)| (fact.ordinal, id.clone()))
                .collect::<Vec<_>>();
            placed.sort_unstable();
            let mut newest = placed
                .into_iter()
                .rev()
                .take(LIVE_ITEM_WINDOW)
                .map(|(_, id)| id)
                .collect::<BTreeSet<_>>();
            // The window bounds *optional* retained history; the identities the live snapshot still
            // requires (a live Turn's input, the inference/channel and tool identities of its
            // resident attempts, running tasks and undelivered results) are not optional. Numbering
            // by ordinal would evict them exactly when a Turn produced more parts than the window, so
            // they are always kept on top of the newest `LIVE_ITEM_WINDOW` others.
            newest.extend(
                referenced
                    .iter()
                    .filter(|id| self.facts.contains_key(*id))
                    .cloned(),
            );
            self.facts.retain(|id, _| {
                let retained = newest.contains(id);
                if !retained {
                    removed.push(id.clone());
                }
                retained
            });
            self.items.retain(|id, _| newest.contains(id));
        }
        // An in-flight preview belongs to an identity still inside the retained window; once its
        // placement fact is gone it can no longer be resolved or committed, so its body is released
        // with it. The content versions follow the same bounded window and are not a second history:
        // an identity evicted here recovers its baseline from the canonical fact
        // ([`LiveProjection::adopt_revisions`]) instead of restarting at 1.
        self.previews.retain(|id, _| self.facts.contains_key(id));
        self.revisions
            .retain(|id, _| self.items.contains_key(id) || self.previews.contains_key(id));
        if let Some(index) = &self.order_index {
            index.retain(&self.facts, removed);
        }
        // This pass only removes entries: equal lengths prove that the charged store helpers'
        // totals and observation mirror remain current. Predicates, window ordering and the
        // shared order-index retention above still run on every commit.
        let after = (
            self.items.len(),
            self.facts.len(),
            self.previews.len(),
            self.revisions.len(),
        );
        if before != after {
            self.rederive_totals();
        }
    }

    /// Re-derives the running retained-byte totals and the observation index from the live tables.
    fn rederive_totals(&mut self) {
        self.items_bytes = self.items.values().fold(0_u64, |total, item| {
            total.saturating_add(charged_item_bytes(item))
        });
        self.facts_bytes = self.facts.iter().fold(0_u64, |total, (id, fact)| {
            total.saturating_add(fact_bytes(id, fact))
        });
        self.previews_bytes = self.previews.iter().fold(0_u64, |total, (id, preview)| {
            total.saturating_add(preview_bytes(id, preview))
        });
        self.revisions_bytes = self
            .revisions
            .keys()
            .fold(0_u64, |total, id| total.saturating_add(revision_bytes(id)));
        self.observed.clear();
        for preview in self.previews.values() {
            if let Some(observed) = &preview.observed {
                self.observed.insert(
                    observed.clone(),
                    ObservedVersion {
                        content: preview.observed_version,
                        ended: preview.shape.is_terminal(),
                        model_part: preview.model_part,
                    },
                );
            }
        }
    }
}

/// Reads the already-committed body of a repaired identity the live window no longer holds.
///
/// A reliable-output repair names an already-committed call, but the bounded live window may already
/// have released that identity — no GUI open, a slow reader, or a rolled-over window. The Thread's
/// single projection owner stays the only fact source for the canonical item and its content version,
/// so it reads the committed body from history here and folds it back into its own tables. The
/// following projection then supplements that identity in memory and the writer only confirms the
/// projected item; no content version is invented outside this owner, nothing re-reads the effect being
/// written, and a repeated repair of the same effect finds the identity already resident.
///
/// # Errors
/// Returns a projection failure when the already-committed body cannot be read or decoded.
pub(in crate::studio) async fn seed_repaired_targets(
    projection: &mut LiveProjection,
    history: &crate::studio::storage::history::HistoryStore,
    effect: &ThreadEffectBatch,
) -> Result<(), ProjectionError> {
    if effect.delivery_repairs.is_empty() {
        return Ok(());
    }
    let mut seeded = Vec::new();
    for repair in effect.delivery_repairs.iter() {
        let tool_id = super::order::tool_id(&repair.call_id);
        if projection.holds_terminal_tool(&tool_id) {
            continue;
        }
        if let Some(item) = history
            .item(&tool_id)
            .await
            .map_err(|error| ProjectionError::History(error.to_string()))?
        {
            seeded.push(item);
        }
    }
    if !seeded.is_empty() {
        projection.seed(seeded, std::collections::BTreeSet::new());
    }
    Ok(())
}

/// Reads the tool items an effect's user-input interactions name, when this projection holds no
/// canonical body for them.
///
/// A pending question outlives the Turn that asked it: the asking call is already terminal, its body
/// leaves the retained window, and a projection seeded after a restart never saw the call at all.
/// The answering effect carries only the interaction and the hidden continuation, so the answer can
/// only land on the call's own item if the owner reads that one identity back from reliable history
/// and hands it to the projection as a fact — the same shape as a reliable-output repair target. A
/// Plan confirmation is answered after the same `plan_submit` call is already terminal, so it needs
/// the same identity read-back. Nothing else is read: no Turn is scanned, no tool is activated, no
/// model step starts. A missing or non-tool durable
/// item fails explicitly, because an accepted answer must never be dropped or published as a
/// fabricated row.
pub(in crate::studio) async fn seed_interaction_targets(
    projection: &mut LiveProjection,
    thread_id: &str,
    history: &crate::studio::storage::history::HistoryStore,
    effect: &ThreadEffectBatch,
) -> Result<(), ProjectionError> {
    let mut seeded = Vec::new();
    for record in effect.interactions.iter() {
        let Some(user_input) = super::user_input::project_user_input(thread_id, record)? else {
            continue;
        };
        let tool_id =
            match pl_core::tool::opaque::interaction_tool_call_id(user_input.interaction_id()) {
                Some(call_id) => super::order::tool_id(call_id),
                None => {
                    return Err(ProjectionError::UserInput(format!(
                        "user-input interaction `{}` names no tool call",
                        user_input.interaction_id()
                    )));
                }
            };
        if projection.holds_tool_body(&tool_id) {
            continue;
        }
        let item = history
            .item(&tool_id)
            .await
            .map_err(|error| ProjectionError::History(error.to_string()))?
            .ok_or_else(|| ProjectionError::MissingDurableToolCall(tool_id.clone()))?;
        if item.tool().is_none() {
            return Err(ProjectionError::UserInput(format!(
                "durable item `{tool_id}` is not a tool call and cannot own a user-input history"
            )));
        }
        seeded.push(item);
    }
    if !seeded.is_empty() {
        projection.seed(seeded, std::collections::BTreeSet::new());
    }
    Ok(())
}

/// The canonical identity of one aggregate streaming channel of an attempt.
/// It is the same in-memory identity the committed effect later finalizes for the whole channel, so a
/// preview and the terminal item it precedes never disagree on the id.
fn aggregate_id(attempt_id: &str, generation: u32, channel: AggregateChannel) -> String {
    match channel {
        AggregateChannel::Text => super::order::observation_id(attempt_id, generation, "text"),
        AggregateChannel::Reasoning => {
            super::order::observation_id(attempt_id, generation, "reasoning")
        }
    }
}

/// Projects one live observation into its stable item identity, content field and static structure.
///
/// The identity comes from the observation's own stable fact — a request-level aggregate channel, or a
/// provider item id plus part discriminator — never from the provider payload or a late output index.
/// The returned `ThreadItemState` carries **no body**: it is the Runtime's static execution shape,
/// while the body is handed out by the caller straight from the observation's
/// shared `Arc<ContentBlock>`, so the hot path never calls `part.text()`.
///
/// The field index is fixed at `0`: one presentation id owns exactly one part, and the commit side
/// `project_presentation_items` puts that part into a chunk vector of length 1, so the streaming and
/// terminal field identities agree and a streaming `SummaryText(n)` never misaligns with a terminal
/// reasoning chunk. `None` reports a part that cannot belong to its item kind instead of inventing a
/// row.
pub(super) fn observation_preview(
    attempt_id: &str,
    generation: u32,
    part: &ObservedPart,
    lifecycle: &ThreadContentLifecycle,
) -> Option<(String, BodyKey, ThreadItemState)> {
    observation_start(attempt_id, generation, part.identity(), lifecycle)
}

fn observation_start(
    attempt_id: &str,
    generation: u32,
    identity: &ObservedPartIdentity,
    lifecycle: &ThreadContentLifecycle,
) -> Option<(String, BodyKey, ThreadItemState)> {
    Some(match identity {
        ObservedPartIdentity::Aggregate { channel } => {
            let id = aggregate_id(attempt_id, generation, *channel);
            match channel {
                AggregateChannel::Text => (
                    id,
                    BodyKey::Body,
                    ThreadItemState::Text(ThreadTextItem::new(
                        ThreadTextChannel::Commentary,
                        String::new(),
                        Vec::new(),
                        lifecycle.clone(),
                    )),
                ),
                AggregateChannel::Reasoning => (
                    id,
                    BodyKey::Part(PresentationPart::ReasoningText(0)),
                    ThreadItemState::Thinking(ThreadThinkingItem::new(
                        Vec::new(),
                        vec![String::new()],
                        lifecycle.clone(),
                    )),
                ),
            }
        }
        ObservedPartIdentity::Provider(identity) => {
            let id = super::order::presentation_id(
                attempt_id,
                generation,
                identity.item_id.as_ref(),
                Some(identity.presentation_part()),
            );
            match (identity.item_kind, identity.part) {
                (ObservedItemKind::Text(channel), ObservedPartKind::OutputText) => (
                    id,
                    BodyKey::Body,
                    ThreadItemState::Text(ThreadTextItem::new(
                        trace_channel(channel),
                        String::new(),
                        Vec::new(),
                        lifecycle.clone(),
                    )),
                ),
                (ObservedItemKind::Reasoning, ObservedPartKind::ReasoningText) => (
                    id,
                    BodyKey::Part(PresentationPart::ReasoningText(0)),
                    ThreadItemState::Thinking(ThreadThinkingItem::new(
                        Vec::new(),
                        vec![String::new()],
                        lifecycle.clone(),
                    )),
                ),
                (ObservedItemKind::Reasoning, ObservedPartKind::SummaryText) => (
                    id,
                    BodyKey::Part(PresentationPart::SummaryText(0)),
                    ThreadItemState::Thinking(ThreadThinkingItem::new(
                        vec![String::new()],
                        Vec::new(),
                        lifecycle.clone(),
                    )),
                ),
                _ => return None,
            }
        }
    })
}

/// Maps the core observation channel vocabulary onto the protocol text channel.
fn trace_channel(channel: ModelTextChannel) -> ThreadTextChannel {
    match channel {
        ModelTextChannel::User => ThreadTextChannel::User,
        ModelTextChannel::Commentary => ThreadTextChannel::Commentary,
        ModelTextChannel::Final => ThreadTextChannel::Final,
    }
}

/// Whether two field maps carry byte-identical text, compared by shared chain without materializing a
/// body. The field set itself participates: dropping or adding a field is a structural change.
fn fields_equal(
    left: &BTreeMap<BodyKey, Arc<ContentBlock>>,
    right: &BTreeMap<BodyKey, Arc<ContentBlock>>,
) -> bool {
    left.len() == right.len()
        && left.iter().all(|(field, block)| {
            right
                .get(field)
                .is_some_and(|other| ContentBlock::text_eq(block, other))
        })
}

#[cfg(test)]
mod completion_boundary_tests {
    //! Producer ports → original projection → Session → real HistoryStore transaction.
    use super::*;
    use crate::studio::storage::{history::HistoryStore, thread_writer::HistoryChannel};
    use anyhow::{Context, Result};
    use pl_core::{
        chat::{ChatHistory, ContentReadRequest, TimelineEpoch},
        context::OpaquePayload,
        model::{
            ActiveModelProgress, ModelProgress, ModelStartedMember, ObservedItemKind, ObservedPart,
            ObservedPartIdentity, ObservedPartKind, ProviderPartIdentity,
        },
        thread::{AttemptOutcome, AttemptStatus, RequestAttempt, TurnRecord, TurnState},
    };
    use pl_model::{
        completion::{
            CompletionPresentationItem, CompletionPresentationItemKind, CompletionPresentationPart,
            CompletionPresentationPartKind,
        },
        runtime::{ModelMemberReceipt, ModelMemberState},
    };
    use pl_protocol::{ChatAtom, ChatAtomKind, ChatAtomLifecycle, ChatTerminalOutcome};
    use sea_orm::{ConnectionTrait, Database};

    fn started(id: &str) -> ModelStartedMember {
        ModelStartedMember {
            turn_id: "boundary-turn".into(),
            attempt_id: "boundary-attempt".into(),
            generation: 0,
            identity: ObservedPartIdentity::Provider(ProviderPartIdentity {
                item_id: id.into(),
                output_index: None,
                content_index: 0,
                item_kind: ObservedItemKind::Reasoning,
                part: ObservedPartKind::ReasoningText,
            }),
        }
    }

    fn content_available(
        start: &ModelStartedMember,
    ) -> pl_core::model::ModelContentAvailableMember {
        pl_core::model::ModelContentAvailableMember {
            turn_id: start.turn_id.clone(),
            attempt_id: start.attempt_id.clone(),
            generation: start.generation,
            identity: start.identity.clone(),
        }
    }

    async fn publish(
        projection: &mut LiveProjection,
        history: &HistoryStore,
        chat: &Session,
        thread: &pl_protocol::Thread,
        state: &ThreadSnapshot,
        effect: &ThreadEffectBatch,
    ) -> Result<Arc<PreparedEffect>> {
        let (_, mut prepared) = projection.prepare(thread, effect, state, false).await?;
        projection.publish_prepared(chat, &mut prepared).await?;
        super::restore_tests::save(history, effect, &prepared).await?;
        Ok(prepared)
    }

    #[tokio::test]
    async fn v364_reliable_empty_text_start_preserves_work_and_atomic_started() -> Result<()> {
        let env = crate::runtime_test_support::Environment::new(vec![], vec![]).await?;
        let result = async {
            let thread = pl_protocol::Thread::from(
                env.runtime
                    .create_thread(&env.project.id, "v364 empty Text")
                    .await?,
            );
            let history =
                HistoryStore::open(&env._temp.path().join("v364-empty.sqlite"), &thread.id).await?;
            history.prepare_write().await?;
            let database = history
                .conversation_database_id()
                .await?
                .context("database")?;
            let chat = Session::new(history.clone(), TimelineEpoch::new("v364-empty")?);
            let channel = HistoryChannel::new(Arc::new(std::sync::atomic::AtomicU64::new(0)));
            let mut projection = LiveProjection::new();
            projection.bind_execution_history(channel.order_index(), history.clone())?;
            projection.bind_conversation_identity(database)?;
            let state = ThreadSnapshot {
                turns: vec![TurnRecord {
                    turn_id: "boundary-turn".into(),
                    input_id: None,
                    state: TurnState::Running,
                    elapsed_ms: None,
                    model_steps: 1,
                }]
                .into(),
                attempts: vec![RequestAttempt::new(
                    "boundary-turn".into(),
                    "boundary-attempt".into(),
                    0,
                    AttemptStatus::Running,
                )]
                .into(),
                ..Default::default()
            };
            let first = ThreadEffectBatch {
                thread_id: thread.id.clone(),
                sequence: 1,
                committed_at: 10,
                model_member_starts: vec![started("R")].into(),
                ..Default::default()
            };
            publish(&mut projection, &history, &chat, &thread, &state, &first).await?;
            let text = ModelStartedMember {
                identity: ObservedPartIdentity::Provider(ProviderPartIdentity {
                    item_id: "empty".into(),
                    output_index: None,
                    content_index: 0,
                    item_kind: ObservedItemKind::Text(pl_core::model::ModelTextChannel::Final),
                    part: ObservedPartKind::OutputText,
                }),
                ..started("empty")
            };
            let second = ThreadEffectBatch {
                thread_id: thread.id.clone(),
                sequence: 2,
                committed_at: 20,
                model_member_starts: vec![text].into(),
                ..Default::default()
            };
            let prepared =
                publish(&mut projection, &history, &chat, &thread, &state, &second).await?;
            assert!(
                prepared
                    .current
                    .atom_facts
                    .iter()
                    .any(|atom| atom.kind == ChatAtomKind::Text)
            );
            assert_eq!(chat.head_seq(), 0);
            let presentation = projection.presentation();
            let cut = presentation.lock().unwrap().capture(None, 8, Some(0), 8);
            assert_eq!(
                cut.published, 0,
                "reliable Started is not content availability"
            );
            assert_eq!(cut.open.len(), 1, "no empty Single shell");
            assert!(matches!(
                cut.open[0].body,
                pl_protocol::DisplayBlockBody::Work { .. }
            ));
            Ok(())
        }
        .await;
        env.finish(result).await
    }

    async fn read_frozen_payload(
        history: &HistoryStore,
        chat: &Session,
        record: &pl_protocol::DisplayRecord,
    ) -> Result<(serde_json::Value, Vec<String>)> {
        use pl_protocol::{ContentOwner, ContentTarget, PayloadData};
        assert!(matches!(
            record.atom.lifecycle,
            ChatAtomLifecycle::Active { .. }
        ));
        assert!(record.atom.completion_item_id.is_none());
        assert!(record.atom.finished_at.is_none());
        let read = |reference: &pl_protocol::ContentRef| {
            let ContentTarget::Body { owner, key } = &reference.target else {
                panic!("owned body")
            };
            assert!(matches!(owner, ContentOwner::DisplayObservation { .. }));
            ContentReadRequest {
                epoch: chat.epoch(),
                reference: pl_core::chat::ContentRef::Body(pl_core::chat::ChatContentKey {
                    owner: crate::studio::conversation_identity::content_owner_key(owner).unwrap(),
                    key: key.clone(),
                }),
                offset: 0,
                max_bytes: 64 * 1024,
                generation: None,
            }
        };
        let Some(PayloadData::Deferred { reference, .. }) = &record.atom.payload else {
            anyhow::bail!("frozen payload is not an owned reference");
        };
        let payload = ChatHistory::read_content(history, &read(reference)).await?;
        assert!(payload.sealed);
        let value: serde_json::Value = serde_json::from_slice(payload.bytes.as_bytes())?;
        assert_eq!(
            value["contract"], "anywork.chat/1",
            "frozen payload must use the public codec"
        );
        let mut texts = Vec::new();
        for body in value["bodies"].as_array().context("body manifest")? {
            let reference: pl_protocol::ContentRef =
                serde_json::from_value(body["reference"].clone())?;
            assert!(
                record
                    .atom
                    .contents
                    .iter()
                    .any(|content| content.reference == reference)
            );
            let window = ChatHistory::read_content(history, &read(&reference)).await?;
            assert!(window.sealed);
            assert_eq!(
                window.bytes.as_bytes().len() as u64,
                body["byteLength"].as_u64().unwrap()
            );
            texts.push(std::str::from_utf8(window.bytes.as_bytes())?.to_string());
        }
        Ok((value, texts))
    }

    #[tokio::test]
    async fn a07_streamed_summary_payload_owns_prefix_through_progress_terminal_and_cold_read()
    -> Result<()> {
        use pl_core::model::ModelProgressSender;
        let prefix = "这段推理在正文开始后继续保持活动。";
        assert_eq!(prefix.len(), 51);
        let env = crate::runtime_test_support::Environment::new(vec![], vec![]).await?;
        let result = async {
            let thread = pl_protocol::Thread::from(
                env.runtime
                    .create_thread(&env.project.id, "A07 observation payload")
                    .await?,
            );
            let path = env._temp.path().join("a07-payload.sqlite");
            let history = HistoryStore::open(&path, &thread.id).await?;
            history.prepare_write().await?;
            let database = history
                .conversation_database_id()
                .await?
                .context("database")?;
            let chat = Session::new(history.clone(), TimelineEpoch::new("a07-hot")?);
            let channel = HistoryChannel::new(Arc::new(std::sync::atomic::AtomicU64::new(0)));
            let mut projection = LiveProjection::new();
            projection.bind_execution_history(channel.order_index(), history.clone())?;
            projection.bind_conversation_identity(database.clone())?;
            let turn = TurnRecord {
                turn_id: "boundary-turn".into(),
                input_id: None,
                state: TurnState::Running,
                elapsed_ms: None,
                model_steps: 1,
            };
            let mut state = ThreadSnapshot {
                turns: vec![turn.clone()].into(),
                attempts: vec![RequestAttempt::new(
                    "boundary-turn".into(),
                    "boundary-attempt".into(),
                    0,
                    AttemptStatus::Running,
                )]
                .into(),
                ..Default::default()
            };
            let effect = |sequence| ThreadEffectBatch {
                thread_id: thread.id.clone(),
                sequence,
                committed_at: sequence as i64 + 10,
                ..Default::default()
            };
            let mut reason = started("A07");
            let ObservedPartIdentity::Provider(provider) = &mut reason.identity else {
                unreachable!()
            };
            provider.part = ObservedPartKind::SummaryText;
            let mut first = effect(1);
            first.turn = Some(turn);
            first.model_member_starts = vec![reason.clone()].into();
            let prepared =
                publish(&mut projection, &history, &chat, &thread, &state, &first).await?;
            let atom_id = prepared
                .current
                .atom_facts
                .iter()
                .find(|atom| atom.kind == ChatAtomKind::Reasoning)
                .context("reliable Core member start")?
                .id
                .clone();
            // No atom with a body is fabricated: the Core producer's watch and the real stream owner
            // supply the immutable part that the reliable Text Started boundary will capture.
            let sender = ModelProgressSender::detached(1024 * 1024);
            sender.edit_parts(|parts| {
                parts.push(ObservedPart::new(reason.identity).appended(prefix))
            });
            state.model_progress = Some(ActiveModelProgress {
                attempt_id: "boundary-attempt".into(),
                progress: sender.latest(),
            });
            projection.stream(&chat, &thread, &state, 1).await?;
            let mut boundary = effect(2);
            let mut text = started("A07-text");
            text.identity = ObservedPartIdentity::Provider(ProviderPartIdentity {
                item_id: "A07-text".into(),
                output_index: None,
                content_index: 0,
                item_kind: ObservedItemKind::Text(pl_core::model::ModelTextChannel::Final),
                part: ObservedPartKind::OutputText,
            });
            boundary.model_member_content_available = vec![content_available(&text)];
            boundary.model_member_starts = vec![text].into();
            let prepared =
                publish(&mut projection, &history, &chat, &thread, &state, &boundary).await?;
            let frozen = prepared
                .display
                .as_ref()
                .context("display")?
                .members
                .iter()
                .find(|member| member.head.record.atom.id == atom_id)
                .context("frozen A")?;
            let block = frozen.block_id.clone();
            let page = history
                .display_member_page(&database, &block, None, 8, None)
                .await?;
            let record = page
                .entries
                .iter()
                .find(|member| member.head.record.atom.id == atom_id)
                .context("persisted display head")?
                .head
                .record
                .clone();
            let expected = read_frozen_payload(&history, &chat, &record).await?;
            assert_eq!(expected.0["data"]["outcome"]["kind"], "streaming");
            assert_eq!(expected.1, [prefix]);
            assert_eq!(record.end_fact, None);
            let pl_protocol::ContentTarget::Body { owner, key } =
                &record.atom.contents[0].reference.target
            else {
                unreachable!()
            };
            let content_key = pl_core::chat::ChatContentKey {
                owner: crate::studio::conversation_identity::content_owner_key(owner)?,
                key: key.clone(),
            };
            assert_eq!(
                projection
                    .presentation()
                    .lock()
                    .unwrap()
                    .observation_content(&content_key)
                    .context("pending RAM observation body")?
                    .data
                    .range(0, 1024)?
                    .as_bytes(),
                prefix.as_bytes()
            );
            sender.edit_parts(|parts| parts[0] = parts[0].appended("LATER_PROGRESS"));
            state.model_progress = Some(ActiveModelProgress {
                attempt_id: "boundary-attempt".into(),
                progress: sender.latest(),
            });
            projection.stream(&chat, &thread, &state, 2).await?;
            publish(
                &mut projection,
                &history,
                &chat,
                &thread,
                &state,
                &effect(3),
            )
            .await?;
            let receipt = ModelMemberReceipt {
                item: CompletionPresentationItem {
                    provider_item_id: "A07".into(),
                    output_index: None,
                    kind: CompletionPresentationItemKind::Reasoning,
                    parts: vec![CompletionPresentationPart {
                        kind: CompletionPresentationPartKind::SummaryText,
                        content_index: 0,
                        provider_part_id: None,
                        text: "FUTURE_COMPLETED_ORIGINAL".into(),
                    }],
                },
                state: ModelMemberState::Completed,
            };
            let mut terminal = effect(4);
            terminal.model_members = vec![pl_core::model::ModelCompletedMember {
                turn_id: "boundary-turn".into(),
                attempt_id: "boundary-attempt".into(),
                generation: 0,
                member_id: "A07".into(),
                payload: OpaquePayload::new(
                    "pl.model.completed-member",
                    1,
                    serde_json::to_string(&receipt)?,
                )?,
            }]
            .into();
            publish(&mut projection, &history, &chat, &thread, &state, &terminal).await?;
            let unchanged = history
                .display_member_page(&database, &block, None, 8, None)
                .await?;
            assert_eq!(
                unchanged
                    .entries
                    .iter()
                    .find(|member| member.head.record.atom.id == atom_id)
                    .unwrap()
                    .head
                    .record,
                record
            );
            assert_eq!(
                read_frozen_payload(&history, &chat, &record).await?,
                expected
            );
            drop(projection);
            drop(chat);
            let cold = HistoryStore::open(&path, &thread.id).await?;
            let cold_chat = Session::new(cold.clone(), TimelineEpoch::new("a07-cold")?);
            let page = cold
                .display_member_page(&database, &block, None, 8, None)
                .await?;
            let cold_record = &page
                .entries
                .iter()
                .find(|member| member.head.record.atom.id == atom_id)
                .unwrap()
                .head
                .record;
            assert_eq!(cold_record, &record);
            assert_eq!(
                read_frozen_payload(&cold, &cold_chat, cold_record).await?,
                expected
            );
            Ok(())
        }
        .await;
        env.finish(result).await
    }

    #[tokio::test]
    async fn activity_token_cost_visits_only_active_parts_without_summary() -> Result<()> {
        use pl_core::model::ModelProgressSender;
        use pl_protocol::{ThreadActivityKind, ThreadContentLifecycle, ThreadItem};

        const COMPLETED: usize = 4096;
        const UPDATES: usize = 3;
        let env = crate::runtime_test_support::Environment::new(vec![], vec![]).await?;
        let result = async {
        let thread = pl_protocol::Thread::from(
            env.runtime.create_thread(&env.project.id, "activity part cost").await?,
        );
        let history = HistoryStore::open(&env._temp.path().join("activity-parts.sqlite"), &thread.id).await?;
        history.prepare_write().await?;
        let chat = Session::new(history.clone(), TimelineEpoch::new("activity-parts")?);
        let channel = HistoryChannel::new(Arc::new(std::sync::atomic::AtomicU64::new(0)));
        let index = channel.order_index();
        let mut projection = LiveProjection::new();
        projection.bind_execution_history(index.clone(), history.clone())?;
        projection.bind_conversation_identity(history.conversation_database_id().await?.context("database")?)?;

        // Assemble the retained completed prefix through the original execution owner. There is no
        // history read or test-side imitation of activity selection in the measured stream path.
        let mut parts = Vec::new();
        for part_index in 0..COMPLETED {
            let mut member = started(&format!("completed-{part_index}"));
            let ObservedPartIdentity::Provider(provider) = &mut member.identity else { unreachable!() };
            provider.part = ObservedPartKind::SummaryText;
            let part = ObservedPart::new(member.identity).appended("OLD_SUMMARY");
            let (id, _, shape) = observation_preview(
                "boundary-attempt", 0, &part, &ThreadContentLifecycle::completed(10),
            ).context("completed part shape")?;
            let order = index.reserve_observed("boundary-attempt", &id)?;
            index.materialize(&ThreadItem::new(
                id.clone(), thread.id.clone(), "boundary-turn".into(), order, 1, 9, 10, shape,
            ), 1)?;
            index.mark_completion(&id, true);
            assert!(index.is_terminal(&id));
            parts.push(part);
        }
        let active = started("active-reasoning");
        parts.push(ObservedPart::new(active.identity.clone()).appended("CURRENT_REASONING"));
        let turn = TurnRecord { turn_id:"boundary-turn".into(), input_id:None,
            state:TurnState::Running, elapsed_ms:None, model_steps:1 };
        let mut state = ThreadSnapshot {
            turns:vec![turn.clone()].into(),
            attempts:vec![RequestAttempt::new("boundary-turn".into(),"boundary-attempt".into(),0,AttemptStatus::Running)].into(),
            ..Default::default()
        };
        let effect = ThreadEffectBatch { thread_id:thread.id.clone(), sequence:1, committed_at:11,
            turn:Some(turn), model_member_starts:vec![active].into(), ..Default::default() };
        publish(&mut projection, &history, &chat, &thread, &state, &effect).await?;
        let sender = ModelProgressSender::detached(1024 * 1024);
        sender.publish(ModelProgress::new(1, parts));
        state.model_progress = Some(ActiveModelProgress {attempt_id:"boundary-attempt".into(), progress:sender.latest()});
        projection.stream(&chat, &thread, &state, 1).await?; // establish the immutable retired prefix

        let mut visits = (0, 0);
        for _ in 0..UPDATES {
            sender.edit_parts(|parts| {
                parts[COMPLETED] = parts[COMPLETED].appended(" token");
            });
            state.model_progress = Some(ActiveModelProgress {attempt_id:"boundary-attempt".into(), progress:sender.latest()});
            super::super::activity::part_cost::begin();
            projection.stream(&chat, &thread, &state, 1).await?;
            let frame = super::super::activity::part_cost::finish();
            visits.0 += frame.0;
            visits.1 += frame.1;
            let activity = projection.current.activity().context("current activity")?;
            assert_eq!(activity.kind, ThreadActivityKind::Thinking);
            assert!(activity.summary.starts_with("CURRENT_REASONING"));
            assert_eq!(activity.thinking_summary, None, "completed summaries are not active");
        }
        eprintln!("ACTIVITY_PART_COST {}", serde_json::json!({
            "path":"stream/current/activity", "completed_parts":COMPLETED, "active_parts":1,
            "token_updates":UPDATES, "model_part_visits":visits.0, "activity_part_visits":visits.1,
        }));
        assert!(visits.0 <= UPDATES * 4, "live owner revisited completed parts: {visits:?}");
        assert!(visits.1 <= UPDATES * 4, "activity revisited completed parts: {visits:?}");

        // The no-line path must not scan the completed list either, including its summary fallback.
        sender.edit_parts(|parts| parts[COMPLETED] = parts[COMPLETED].authorized(" \n"));
        state.model_progress = Some(ActiveModelProgress {attempt_id:"boundary-attempt".into(), progress:sender.latest()});
        super::super::activity::part_cost::begin();
        projection.stream(&chat, &thread, &state, 1).await?;
        let missing = super::super::activity::part_cost::finish();
        let activity = projection.current.activity().context("missing-line activity")?;
        assert_eq!(activity.summary, "");
        assert_eq!(activity.thinking_summary, None);
        eprintln!("ACTIVITY_PART_COST {}", serde_json::json!({
            "path":"stream/current/activity/no_matching_line", "completed_parts":COMPLETED,
            "active_parts":1, "model_part_visits":missing.0, "activity_part_visits":missing.1,
        }));
        assert!(missing.0 <= 4 && missing.1 <= 4, "missing-line lookup scanned history: {missing:?}");

        // Lexical ids and execution ordinals are not the producer's current part order.
        let mut first_summary = started("z-first-summary");
        let mut last_summary = started("a-last-summary");
        for member in [&mut first_summary, &mut last_summary] {
            let ObservedPartIdentity::Provider(provider) = &mut member.identity else { unreachable!() };
            provider.part = ObservedPartKind::SummaryText;
        }
        let start_summaries = ThreadEffectBatch {thread_id:thread.id.clone(), sequence:2, committed_at:12,
            model_member_starts:vec![first_summary.clone(), last_summary.clone()].into(), ..Default::default()};
        publish(&mut projection, &history, &chat, &thread, &state, &start_summaries).await?;
        sender.edit_parts(|parts| {
            parts.push(ObservedPart::new(first_summary.identity).appended("FIRST_SUMMARY"));
            parts.push(ObservedPart::new(last_summary.identity).appended("LAST_SUMMARY"));
        });
        state.model_progress = Some(ActiveModelProgress {attempt_id:"boundary-attempt".into(), progress:sender.latest()});
        projection.stream(&chat, &thread, &state, 2).await?;
        let activity = projection.current.activity().context("summary activity")?;
        assert_eq!(activity.summary, "LAST_SUMMARY");
        assert_eq!(activity.thinking_summary.as_deref(), Some("LAST_SUMMARY"));
        let cut = projection.presentation.lock().unwrap().capture(None, 8, Some(0), 8);
        let work = cut.open.iter().find(|header| Some(&header.id) == cut.current_work_id.as_ref()).context("open Work")?;
        assert_eq!(work.thinking_summary.as_deref(), Some("LAST_SUMMARY"));
        sender.edit_parts(|parts| {
            let first = parts[COMPLETED + 1].clone();
            parts[COMPLETED + 1] = parts[COMPLETED + 2].clone();
            parts[COMPLETED + 2] = first;
        });
        state.model_progress = Some(ActiveModelProgress {attempt_id:"boundary-attempt".into(), progress:sender.latest()});
        projection.stream(&chat, &thread, &state, 2).await?;
        let activity = projection.current.activity().context("reordered activity")?;
        assert_eq!(activity.summary, "FIRST_SUMMARY", "unchanged versions still follow producer order");
        assert_eq!(activity.thinking_summary.as_deref(), Some("FIRST_SUMMARY"));

        // Replace the entire list at the same length/version with different, unadmitted identities.
        // Old locations must not return either their stale blocks or the replacement's bytes.
        let before = sender.latest();
        let mut replaced = before.parts().iter().cloned().collect::<Vec<_>>();
        for (offset, part) in replaced[COMPLETED..].iter_mut().enumerate() {
            let mut replacement = started(&format!("unadmitted-{offset}"));
            let ObservedPartIdentity::Provider(provider) = &mut replacement.identity else { unreachable!() };
            provider.part = ObservedPartKind::SummaryText;
            *part = ObservedPart::new(replacement.identity).appended("NOT_ADMITTED");
        }
        sender.publish(ModelProgress::new(before.version(), replaced));
        state.model_progress = Some(ActiveModelProgress {attempt_id:"boundary-attempt".into(), progress:sender.latest()});
        projection.stream(&chat, &thread, &state, 2).await?;
        let activity = projection.current.activity().context("replaced activity")?;
        assert_eq!(activity.summary, "");
        assert_eq!(activity.thinking_summary, None);

        sender.begin_recovery(1, Arc::from("retry"))?;
        sender.edit_parts(|parts| parts.push(
            ObservedPart::new(started("active-reasoning").identity).appended("NEXT_GENERATION"),
        ));
        state.model_progress = Some(ActiveModelProgress {attempt_id:"boundary-attempt".into(), progress:sender.latest()});
        let mut next = started("active-reasoning");
        next.generation = 1;
        let next_start = ThreadEffectBatch {thread_id:thread.id.clone(), sequence:3, committed_at:13,
            model_member_starts:vec![next].into(), ..Default::default()};
        publish(&mut projection, &history, &chat, &thread, &state, &next_start).await?;
        projection.stream(&chat, &thread, &state, 3).await?;
        let activity = projection.current.activity().context("next generation activity")?;
        assert_eq!(activity.summary, "NEXT_GENERATION");
        assert_eq!(activity.thinking_summary, None, "old generation summaries cannot leak");
        Ok(())
    }.await;
        env.finish(result).await
    }

    fn started_body(
        prepared: &PreparedEffect,
        kind: ChatAtomKind,
        database: &str,
    ) -> Result<pl_protocol::ChatAtomContent> {
        let atom = prepared
            .current
            .atom_facts
            .iter()
            .find(|atom| {
                atom.kind == kind && matches!(atom.lifecycle, ChatAtomLifecycle::Active { .. })
            })
            .context("reliable active start")?;
        assert_eq!(
            atom.contents.len(),
            1,
            "start must carry its allocated body"
        );
        let content = &atom.contents[0];
        assert_eq!(content.reference.database_id, database);
        let pl_protocol::ContentTarget::Body { owner, key } = &content.reference.target else {
            anyhow::bail!("start content is not a canonical body");
        };
        assert_eq!(
            owner,
            &pl_protocol::ContentOwner::Item {
                item_id: atom.id.clone()
            }
        );
        let current_key = pl_core::chat::ChatContentKey {
            owner: crate::studio::conversation_identity::content_owner_key(owner)?,
            key: key.clone(),
        };
        let current = prepared
            .current_state
            .as_ref()
            .context("frozen current owner")?
            .contents()
            .get(&current_key)
            .context("start reference resolves to its real allocated body")?;
        assert_eq!(current.descriptor.byte_length, 0, "no token is required");
        assert_eq!(
            prepared
                .display
                .as_ref()
                .context("frozen display")?
                .members
                .iter()
                .find(|member| member.head.record.atom.id == atom.id)
                .context("display member")?
                .head
                .record
                .atom
                .contents,
            atom.contents
        );
        Ok(content.clone())
    }

    #[tokio::test]
    async fn reliable_permission_status_changes_update_display_without_rewriting_start()
    -> Result<()> {
        use pl_core::{
            context::{ContextRecord, ContextSource},
            model::ModelToolCall,
            thread::{
                journal::ContextChange,
                permissions::{PermissionRecord, PermissionState},
                task::{TaskRecord, TaskStatus},
            },
        };
        use pl_protocol::ChatActiveStatus;

        let env = crate::runtime_test_support::Environment::new(vec![], vec![]).await?;
        let result = async {
        let thread = pl_protocol::Thread::from(
            env.runtime
                .create_thread(&env.project.id, "display permission changes")
                .await?,
        );
        let path = env._temp.path().join("display-permission.sqlite");
        let history = HistoryStore::open(&path, &thread.id).await?;
        history.prepare_write().await?;
        let database = history
            .conversation_database_id()
            .await?
            .context("database")?;
        let sql = Database::connect(format!("sqlite://{}?mode=rw", path.display())).await?;
        let chat = Session::new(history.clone(), TimelineEpoch::new("display-permission")?);
        let channel = HistoryChannel::new(Arc::new(std::sync::atomic::AtomicU64::new(0)));
        let mut projection = LiveProjection::new();
        projection.bind_execution_history(channel.order_index(), history.clone())?;
        projection.bind_conversation_identity(database.clone())?;
        let turn = TurnRecord {
            turn_id: "boundary-turn".into(),
            input_id: None,
            state: TurnState::Running,
            elapsed_ms: None,
            model_steps: 1,
        };
        let task = TaskRecord {
            parent_call_id: None,
            invocation: None,
            id: "task:approval-call".into(),
            call_id: "approval-call".into(),
            tool_id: "exec".into(),
            turn_id: turn.turn_id.clone(),
            revision: 1,
            status: TaskStatus::Running,
            cancel_requested: false,
            acknowledgement: None,
            started_sequence: Some(1),
        };
        let record = ContextRecord {
            id: "call-record".into(),
            turn_id: Some(turn.turn_id.clone()),
            source: ContextSource::Assistant,
            content: Vec::new(),
            tool_calls: vec![ModelToolCall {
                call_id: task.call_id.clone(),
                tool_id: task.tool_id.clone(),
                arguments: OpaquePayload::new("pl.tool.input", 1, "{}")?,
                presentation_contract: None,
                rejection: None,
            }],
        };
        let mut state = ThreadSnapshot {
            turns: vec![turn.clone()].into(),
            attempts: vec![RequestAttempt::new(
                "boundary-turn".into(),
                "boundary-attempt".into(),
                0,
                AttemptStatus::Running,
            )]
            .into(),
            ..Default::default()
        };
        state.context.revision = 1;
        state.context.records = vec![record.clone()].into();
        state
            .live_calls
            .insert(task.call_id.clone(), task.turn_id.clone());
        state.tasks.insert(task.id.clone(), task.clone());
        let effect = |sequence| ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence,
            committed_at: sequence as i64 + 10,
            ..Default::default()
        };
        let mut first = effect(1);
        first.turn = Some(turn);
        first.context = Some(ContextChange::Append {
            revision: 1,
            records: vec![record].into(),
        });
        first.tasks = vec![task.clone()].into();
        let prepared = publish(&mut projection, &history, &chat, &thread, &state, &first).await?;
        let tool_atom = prepared
            .current
            .atom_facts
            .iter()
            .find(|atom| atom.kind == ChatAtomKind::ToolCall)
            .context("original tool start")?
            .clone();
        let owner = projection.presentation();
        let first_cut = owner.lock().unwrap().capture(None, 1, Some(0), 1);
        let block_id = first_cut.open[0].id.clone();
        let structure_revision = first_cut.revision;
        let mut previous_revision = first_cut.open[0].revision;
        let mut changes = owner.lock().unwrap().subscribe_members();
        let start_row = || {
            sea_orm::Statement::from_sql_and_values(
                sea_orm::DbBackend::Sqlite,
                "SELECT metadata FROM conversation_atom_facts WHERE atom_id=? AND phase='start'",
                vec![tool_atom.id.clone().into()],
            )
        };
        let original_start: Vec<u8> = sql
            .query_one_raw(start_row())
            .await?
            .context("start row")?
            .try_get("", "metadata")?;

        let mut permission = PermissionRecord {
            id: "approval".into(),
            task_id: task.id.clone(),
            call_id: task.call_id.clone(),
            turn_id: task.turn_id.clone(),
            tool_id: task.tool_id.clone(),
            revision: 1,
            created_at: 12,
            updated_at: 12,
            response: None,
            state: PermissionState::Pending,
            payload: OpaquePayload::new(
                "pl.studio.tool-approval",
                1,
                serde_json::to_string(&serde_json::json!({
                    "name": "exec",
                    "arguments": OpaquePayload::new("pl.tool.input", 1, "{}")?,
                    "workingDirectory": "/workspace",
                }))?,
            )?,
        };
        for (sequence, status, waiting) in [
            (2, PermissionState::Pending, 1),
            (3, PermissionState::Allowed, 0),
        ] {
            permission.state = status;
            permission.revision = sequence - 1;
            permission.updated_at = sequence as i64 + 10;
            state
                .permissions
                .insert(permission.id.clone(), permission.clone());
            state.interaction_collection_revision = sequence - 1;
            let mut update = effect(sequence);
            update.permissions = vec![permission.clone()].into();
            let prepared =
                publish(&mut projection, &history, &chat, &thread, &state, &update).await?;
            assert!(
                !prepared
                    .current
                    .atom_facts
                    .iter()
                    .any(|atom| atom.id == tool_atom.id),
                "a status transition is not a replacement start fact"
            );
            let cut = owner
                .lock()
                .unwrap()
                .member_cut(&block_id, None, 2)
                .context("hot member cut")?;
            assert_eq!(cut.header.next_member, 1);
            assert_eq!(cut.header.unfinished, 1);
            assert!(cut.header.revision > previous_revision);
            previous_revision = cut.header.revision;
            assert_eq!(
                owner.lock().unwrap().capture(None, 1, Some(0), 1).revision,
                structure_revision
            );
            assert!(changes.has_changed()?);
            changes.borrow_and_update();
            let expected = if waiting == 1 {
                ChatActiveStatus::Waiting
            } else {
                ChatActiveStatus::Running
            };
            assert!(matches!(cut.overlay[0].head.record.atom.lifecycle,
                ChatAtomLifecycle::Active { status, .. } if status == expected));
            let saved = history
                .display_member_page(&database, &block_id, None, 2, None)
                .await?;
            assert_eq!(saved.header.as_ref(), cut.header.as_ref());
            assert_eq!(saved.entries[0], *cut.overlay[0]);
            assert_eq!(
                sql.query_one_raw(start_row())
                    .await?
                    .context("preserved start")?
                    .try_get::<Vec<u8>>("", "metadata")?,
                original_start
            );
        }
        let before_token = history
            .display_member_page(&database, &block_id, None, 2, None)
            .await?;
        let mut part = ObservedPart::new(started("preview-only").identity);
        for version in 1..=2 {
            part = part.authorized(&"token".repeat(version as usize));
            state.model_progress = Some(ActiveModelProgress {
                attempt_id: "boundary-attempt".into(),
                progress: ModelProgress::new(version, vec![part.clone()]),
            });
            projection.stream(&chat, &thread, &state, 3).await?;
        }
        let after_token = owner
            .lock()
            .unwrap()
            .member_cut(&block_id, None, 2)
            .context("after token")?;
        assert_eq!(after_token.header.as_ref(), before_token.header.as_ref());
        assert!(!changes.has_changed()?);
        assert_eq!(
            history
                .display_member_page(&database, &block_id, None, 2, None)
                .await?
                .entries,
            before_token.entries
        );
        let mut boundary = effect(4);
        let mut text = started("tool-boundary");
        text.identity = ObservedPartIdentity::Provider(ProviderPartIdentity {
            item_id: "tool-boundary".into(),
            output_index: None,
            content_index: 0,
            item_kind: ObservedItemKind::Text(pl_core::model::ModelTextChannel::Final),
            part: ObservedPartKind::OutputText,
        });
        boundary.model_member_content_available = vec![content_available(&text)];
        boundary.model_member_starts = vec![text].into();
        publish(&mut projection, &history, &chat, &thread, &state, &boundary).await?;
        let page = history
            .display_member_page(&database, &block_id, None, 2, None)
            .await?;
        let frozen = &page
            .entries
            .iter()
            .find(|member| member.head.record.atom.id == tool_atom.id)
            .context("real unfinished tool")?
            .head
            .record;
        let (payload, texts) = read_frozen_payload(&history, &chat, frozen).await?;
        assert_eq!(payload["type"], "tool");
        assert_eq!(payload["data"]["state"]["kind"], "running");
        assert_eq!(payload["data"]["invocation"]["name"], "exec");
        assert_eq!(texts, ["{}", ""]);
        let saved_payload = payload;
        permission.state = PermissionState::Pending;
        permission.revision += 1;
        permission.updated_at = 15;
        state
            .permissions
            .insert(permission.id.clone(), permission.clone());
        let mut later = effect(5);
        later.permissions = vec![permission].into();
        publish(&mut projection, &history, &chat, &thread, &state, &later).await?;
        assert_eq!(
            read_frozen_payload(&history, &chat, frozen).await?,
            (saved_payload, texts),
            "later public tool status cannot rewrite its frozen payload"
        );
        Ok(())
    }
    .await;
        env.finish(result).await
    }

    #[tokio::test]
    async fn reliable_text_visibility_hands_off_work_without_a_new_atomic_completion() -> Result<()>
    {
        let env = crate::runtime_test_support::Environment::new(vec![], vec![]).await?;
        let result = async {
        let thread = pl_protocol::Thread::from(
            env.runtime
                .create_thread(&env.project.id, "display boundary")
                .await?,
        );
        let history = HistoryStore::open(
            &env._temp.path().join("display-boundary.sqlite"),
            &thread.id,
        )
        .await?;
        history.prepare_write().await?;
        let database = history
            .conversation_database_id()
            .await?
            .context("database")?;
        let chat = Session::new(history.clone(), TimelineEpoch::new("display-start")?);
        let channel = HistoryChannel::new(Arc::new(std::sync::atomic::AtomicU64::new(0)));
        let mut projection = LiveProjection::new();
        projection.bind_execution_history(channel.order_index(), history.clone())?;
        projection.bind_conversation_identity(database.clone())?;
        let turn = TurnRecord {
            turn_id: "boundary-turn".into(),
            input_id: None,
            state: TurnState::Running,
            elapsed_ms: None,
            model_steps: 1,
        };
        let mut state = ThreadSnapshot {
            turns: vec![turn.clone()].into(),
            attempts: vec![RequestAttempt::new("boundary-turn".into(), "boundary-attempt".into(), 0, AttemptStatus::Running)].into(),
            ..Default::default()
        };
        let effect = |sequence| ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence,
            committed_at: sequence as i64 + 10,
            ..Default::default()
        };
        let mut first = effect(1);
        first.turn = Some(turn);
        first.model_member_starts = vec![started("R")].into();
        let first_prepared = publish(&mut projection, &history, &chat, &thread, &state, &first).await?;
        assert!(matches!(&first_prepared.display.as_ref().unwrap().blocks[0].header.body,
            pl_protocol::DisplayBlockBody::Work { timing, .. }
            if timing.started_at == Some(first.committed_at) && timing.finished_at.is_none()));
        started_body(&first_prepared, ChatAtomKind::Reasoning, &database)?;
        let mut second = effect(2);
        let receipt = ModelMemberReceipt {
            item: CompletionPresentationItem {
                provider_item_id: "R".into(),
                output_index: None,
                kind: CompletionPresentationItemKind::Reasoning,
                parts: vec![CompletionPresentationPart {
                    kind: CompletionPresentationPartKind::ReasoningText,
                    content_index: 0,
                    provider_part_id: None,
                    text: "完整思考".into(),
                }],
            },
            state: ModelMemberState::Completed,
        };
        second.model_members = vec![pl_core::model::ModelCompletedMember {
            turn_id: "boundary-turn".into(),
            attempt_id: "boundary-attempt".into(),
            generation: 0,
            member_id: "R".into(),
            payload: OpaquePayload::new(
                "pl.model.completed-member",
                1,
                serde_json::to_string(&receipt)?,
            )?,
        }]
        .into();
        publish(&mut projection, &history, &chat, &thread, &state, &second).await?;
        let h = chat.head_seq();
        let presentation = projection.presentation();
        {
            let owner = presentation.lock().unwrap();
            let cut = owner.capture(None, 8, Some(0), 8);
            assert_eq!(cut.published, 0);
            assert!(
                matches!(&cut.open[0].body, pl_protocol::DisplayBlockBody::Work { timing, .. }
                if cut.open[0].next_member == 1 && cut.open[0].unfinished == 0
                    && timing.started_at == Some(first.committed_at)
                    && timing.finished_at.is_none())
            );
        }
        let mut text = started("T");
        text.identity = ObservedPartIdentity::Provider(ProviderPartIdentity {
            item_id: "T".into(),
            output_index: None,
            content_index: 0,
            item_kind: ObservedItemKind::Text(pl_core::model::ModelTextChannel::Final),
            part: ObservedPartKind::OutputText,
        });
        let mut third = effect(3);
        third.model_member_content_available = vec![content_available(&text)];
        third.model_member_starts = vec![text].into();
        let prepared = publish(&mut projection, &history, &chat, &thread, &state, &third).await?;
        let frozen_work = prepared.display.as_ref().unwrap().blocks.iter()
            .find(|block| block.header.sealed).context("published Work")?;
        assert!(matches!(&frozen_work.header.body,
            pl_protocol::DisplayBlockBody::Work { timing, .. }
            if timing.started_at == Some(first.committed_at) && timing.finished_at == Some(third.committed_at)));
        let cold_work = history.display_history_heads(&database, 0, 1, None, 8, true).await?;
        assert_eq!(cold_work[0].body, frozen_work.header.body);
        let text_body = started_body(&prepared, ChatAtomKind::Text, &database)?;
        assert_eq!(chat.head_seq(), h);
        assert!(prepared.completions.is_empty());
        assert_eq!(prepared.display.as_ref().unwrap().ready_frontier, 1);
        assert!(Arc::ptr_eq(
            prepared.display.as_ref().unwrap(),
            prepared.current.display.as_ref().unwrap()
        ));
        let cold = history
            .display_recovery()
            .await?
            .context("saved display cut")?;
        assert_eq!(cold.published, 1);
        assert_eq!(cold.open.len(), 1);
        assert_eq!(cold.unfinished.len(), 1);
        let mut recovered = super::super::presentation::PresentationState::default();
        recovered.restore(
            &database,
            cold.published,
            cold.last_order,
            cold.effect,
            cold.open,
            cold.unfinished,
        )?;
        assert!(
            !recovered
                .member_cut(
                    &prepared
                        .display
                        .as_ref()
                        .unwrap()
                        .blocks
                        .iter()
                        .find(|b| !b.header.sealed)
                        .unwrap()
                        .header
                        .id,
                    None,
                    8
                )
                .unwrap()
                .complete
        );
        let completed_id = &prepared.display.as_ref().unwrap().blocks.iter()
            .find(|block| block.header.sealed).context("completed work")?.header.id;
        assert!(presentation.lock().unwrap().member_cut(completed_id,None,8).context("retained completed member")?
            .overlay.iter().any(|member| member.terminal));
        presentation.lock().unwrap().begin_cost_observation();
        let mut part = ObservedPart::new(third.model_member_starts[0].identity.clone());
        for version in 1..=2 {
            part = part.authorized(&"正文 token".repeat(version as usize));
            state.model_progress = Some(ActiveModelProgress {
                attempt_id:"boundary-attempt".into(), progress:ModelProgress::new(version,vec![part.clone()]),
            });
            projection.stream(&chat,&thread,&state,3).await?;
        }
        let pl_protocol::ContentTarget::Body { owner, key } = &text_body.reference.target else {
            unreachable!("started_body checked the target");
        };
        let current_key = pl_core::chat::ChatContentKey {
            owner: crate::studio::conversation_identity::content_owner_key(owner)?,
            key: key.clone(),
        };
        assert!(
            projection.current.snapshot().context("streamed current")?
                .contents().get(&current_key).context("same body after tokens")?
                .descriptor.byte_length > 0
        );
        let visits = presentation.lock().unwrap().finish_cost_observation();
        assert_eq!((visits.members.reads,visits.members.writes,visits.heads.reads,visits.heads.writes),(0,0,0,0));
        eprintln!("PRESENTATION_COST {}",serde_json::json!({
            "event":"production_token_preview", "token_updates":2, "retained_completed_members_at_least":1,
            "member_reads":visits.members.reads, "member_writes":visits.members.writes,
            "head_reads":visits.heads.reads, "head_writes":visits.heads.writes,
        }));
        projection.confirm_sources(3);
        assert_eq!(
            presentation.lock().unwrap().capture(None, 8, Some(0), 8).published,
            1
        );
        super::restore_tests::save(&history, &third, &prepared).await?; // exact lost-ACK replay
        Ok(())
    }
    .await;
        env.finish(result).await
    }

    #[tokio::test]
    async fn progress_never_writes_prefix_and_real_restart_interrupt_preserves_completed_member()
    -> Result<()> {
        let env = crate::runtime_test_support::Environment::new(vec![], vec![]).await?;
        let result = async {
        let thread = pl_protocol::Thread::from(env.runtime.create_thread(
            &env.project.id, "completion boundary",
        ).await?);
        let path = env._temp.path().join("completion-boundary.sqlite");
        let history = HistoryStore::open(&path, &thread.id).await?;
        history.prepare_write().await?;
        let database = history.conversation_database_id().await?.context("database")?;
        let sql = Database::connect(format!("sqlite://{}?mode=rw", path.display())).await?;
        let chat = Session::new(history.clone(), TimelineEpoch::new("before-restart")?);
        let channel = HistoryChannel::new(Arc::new(std::sync::atomic::AtomicU64::new(0)));
        let mut projection = LiveProjection::new();
        projection.bind_execution_history(channel.order_index(), history.clone())?;
        projection.bind_conversation_identity(database.clone())?;
        let turn = TurnRecord { turn_id:"boundary-turn".into(),input_id:None,
            state:TurnState::Running,elapsed_ms:None,model_steps:1 };
        let mut state = ThreadSnapshot { turns:vec![turn.clone()].into(),
            attempts:vec![RequestAttempt::new("boundary-turn".into(),"boundary-attempt".into(),0,AttemptStatus::Running)].into(), ..Default::default() };
        let effect = |sequence| ThreadEffectBatch { thread_id:thread.id.clone(),sequence,
            committed_at:sequence as i64 + 10, ..Default::default() };
        let mut first = effect(1);
        first.turn = Some(turn);
        first.model_member_starts = vec![started("A")].into();
        publish(&mut projection,&history,&chat,&thread,&state,&first).await?;
        let mut part = ObservedPart::new(started("A").identity);
        for sequence in 2..=5 {
            let prefix = "流式前缀".repeat(sequence as usize * 4096);
            part = part.authorized(&prefix);
            state.model_progress = Some(ActiveModelProgress {
                attempt_id:"boundary-attempt".into(),
                progress:ModelProgress::new(sequence,vec![part.clone()]),
            });
            state.commit_sequence = sequence;
            projection.stream(&chat,&thread,&state,sequence).await?;
            let prepared = publish(&mut projection,&history,&chat,&thread,&state,&effect(sequence)).await?;
            assert!(prepared.current.contents.is_empty(), "progress prepared a body write");
            let row=sql.query_one_raw(sea_orm::Statement::from_string(sea_orm::DbBackend::Sqlite,
                "SELECT (SELECT COUNT(*) FROM conversation_contents) AS bodies,
                        (SELECT COUNT(*) FROM conversation_items) AS items".to_owned()))
                .await?.context("counts")?;
            assert_eq!(row.try_get::<i64>("","bodies")?,0);
            assert_eq!(row.try_get::<i64>("","items")?,0);
        }
        let full = "完整思考".repeat(40_000);
        let receipt=ModelMemberReceipt { item:CompletionPresentationItem {
            provider_item_id:"A".into(),output_index:None,kind:CompletionPresentationItemKind::Reasoning,
            parts:vec![CompletionPresentationPart {content_index:0,provider_part_id:None,text:full.clone(),
                kind:CompletionPresentationPartKind::ReasoningText}],
        },state:ModelMemberState::Completed };
        let mut complete=effect(6);
        complete.model_members=vec![pl_core::model::ModelCompletedMember {
            turn_id:"boundary-turn".into(),attempt_id:"boundary-attempt".into(),generation:0,
            member_id:"A".into(),payload:OpaquePayload::new("pl.model.completed-member",1,
                serde_json::to_string(&receipt)?)?,
        }].into();
        state.model_progress=None;
        let saved=publish(&mut projection,&history,&chat,&thread,&state,&complete).await?;
        let record=saved.completions.iter().find(|record| record.contents.values()
            .any(|content| content.descriptor.byte_length==full.len() as u64)).context("A record")?;
        let a_id=record.header.item_id.clone();
        let content=record.contents.values().find(|content| content.descriptor.byte_length==full.len() as u64)
            .context("A body")?;
        let window=ChatHistory::read_content(&history,&ContentReadRequest {
            epoch:chat.epoch(),reference:pl_core::chat::ContentRef::Body(content.descriptor.key.clone()),
            offset:0,max_bytes:64*1024,generation:Some(content.descriptor.generation),
        }).await?;
        assert!(window.sealed);
        assert_eq!(window.available_through,full.len() as u64);
        assert_eq!(window.bytes.as_bytes(),&full.as_bytes()[..64*1024]);
        assert_eq!(record.header.append_seq, 1, "a completed member must publish immediately");
        let mut second=effect(7);
        second.model_member_starts=vec![started("B")].into();
        publish(&mut projection,&history,&chat,&thread,&state,&second).await?;
        drop(projection);
        drop(chat);
        drop(channel);
        // A passive cold read does not manufacture an interruption or restore a preview.
        let current=history.conversation_current().await?.context("cold current")?;
        assert!(!current.execution_present);
        assert!(current.previews.is_empty());
        let restored_chat=Session::new(history.clone(),TimelineEpoch::new("after-restart")?);
        let restored_channel=HistoryChannel::new(Arc::new(std::sync::atomic::AtomicU64::new(0)));
        let mut restored=LiveProjection::new();
        restored.bind_execution_history(restored_channel.order_index(),history.clone())?;
        restored.bind_conversation_identity(database.clone())?;
        state.attempts=vec![RequestAttempt::new("boundary-turn".into(),"boundary-attempt".into(),
            0,AttemptStatus::Interrupted)].into();
        restored.restore_current(&restored_chat,&thread,&state).await?;
        assert!(restored.current_state().context("restored current")?.contents().is_empty());
        let mut interrupted=effect(8);
        interrupted.turn=Some(TurnRecord {turn_id:"boundary-turn".into(),input_id:None,
            state:TurnState::Interrupted,elapsed_ms:None,model_steps:1});
        interrupted.attempt=Some(pl_core::thread::journal::AttemptUpdate {
            turn_id:"boundary-turn".into(),attempt_id:"boundary-attempt".into(),retry_of:None,
            input_revision:0,request_metadata:None,usage_binding:None,tool_projection:None,
            tools:Arc::from([]),outcome:AttemptOutcome::Interrupted,input_estimate:None,
        });
        state.turns=vec![interrupted.turn.clone().unwrap()].into();
        state.commit_sequence=8;
        let settled=publish(&mut restored,&history,&restored_chat,&thread,&state,&interrupted).await?;
        assert!(settled.completions.iter().all(|record| record.header.item_id!=a_id));
        assert!(settled.current.projection().atoms.is_empty());
        let members=sql.query_all_raw(sea_orm::Statement::from_string(sea_orm::DbBackend::Sqlite,
            "SELECT atom_id,phase,metadata FROM conversation_atom_facts WHERE phase='terminal'".to_owned())).await?;
        let metadata=members.iter().find_map(|row| {
            let atom:ChatAtom=serde_json::from_slice(&row.try_get::<Vec<u8>>("","metadata").ok()?).ok()?;
            (atom.id != a_id && atom.kind==ChatAtomKind::Reasoning).then_some(atom)
        }).context("interrupted B fact")?;
        assert!(matches!(metadata.lifecycle,ChatAtomLifecycle::Terminal {outcome:ChatTerminalOutcome::Cancelled,
            started:Some(_),ended:Some(at)} if at.effect_seq==8));
        assert!(metadata.completion_item_id.is_none() && metadata.completion_seq.is_none()
            && metadata.payload.is_none() && metadata.contents.is_empty());
        let source_end = settled.current.source_changes.iter().find(|source| source.source == metadata.source)
            .and_then(|source| source.ended).context("enclosing Turn source end")?;
        let b_end = match metadata.lifecycle { ChatAtomLifecycle::Terminal { ended: Some(at), .. } => at, _ => unreachable!() };
        assert!(b_end < source_end, "restart cancellation must precede its Turn's enclosure");
        let receipt_end = settled.current.atom_facts.iter().find(|atom| atom.kind == ChatAtomKind::TurnReceipt)
            .and_then(|atom| match atom.lifecycle { ChatAtomLifecycle::Terminal { ended, .. } => ended, _ => None })
            .context("Turn closing receipt")?;
        assert!(b_end < receipt_end && receipt_end < source_end);
        let frozen_positions = serde_json::to_vec(&(settled.current.atom_facts.as_ref(),
            settled.current.source_changes.as_ref()))?;
        let mut replay = settled.clone();
        restored.publish_prepared(&restored_chat, &mut replay).await?;
        super::restore_tests::save(&history, &interrupted, &replay).await?;
        assert_eq!(serde_json::to_vec(&(replay.current.atom_facts.as_ref(),
            replay.current.source_changes.as_ref()))?, frozen_positions);
        assert_eq!(replay.completions.len(),settled.completions.len());
        assert!(history.recovery_atom_starts(None,128).await?.is_empty());
        Ok(())
    }.await;
        env.finish(result).await
    }

    #[tokio::test]
    async fn same_effect_text_boundary_retains_preterminal_prefix_after_the_current_atom_retires()
    -> Result<()> {
        let env = crate::runtime_test_support::Environment::new(vec![], vec![]).await?;
        let result = async {
            let thread = pl_protocol::Thread::from(
                env.runtime
                    .create_thread(&env.project.id, "same effect cut")
                    .await?,
            );
            let history =
                HistoryStore::open(&env._temp.path().join("same-effect.sqlite"), &thread.id)
                    .await?;
            history.prepare_write().await?;
            let database = history
                .conversation_database_id()
                .await?
                .context("database")?;
            let chat = Session::new(history.clone(), TimelineEpoch::new("same-effect-cut")?);
            let channel = HistoryChannel::new(Arc::new(std::sync::atomic::AtomicU64::new(0)));
            let mut projection = LiveProjection::new();
            projection.bind_execution_history(channel.order_index(), history.clone())?;
            projection.bind_conversation_identity(database.clone())?;
            let turn = TurnRecord {
                turn_id: "boundary-turn".into(),
                input_id: None,
                state: TurnState::Running,
                elapsed_ms: None,
                model_steps: 1,
            };
            let mut state = ThreadSnapshot {
                turns: vec![turn.clone()].into(),
                attempts: vec![RequestAttempt::new(
                    "boundary-turn".into(),
                    "boundary-attempt".into(),
                    0,
                    AttemptStatus::Running,
                )]
                .into(),
                ..Default::default()
            };
            let effect = |sequence| ThreadEffectBatch {
                thread_id: thread.id.clone(),
                sequence,
                committed_at: 10 + sequence as i64,
                ..Default::default()
            };
            let mut first = effect(1);
            first.turn = Some(turn);
            first.model_member_starts = vec![started("A")].into();
            publish(&mut projection, &history, &chat, &thread, &state, &first).await?;
            let part = ObservedPart::new(started("A").identity).appended("BOUNDARY_PREFIX");
            state.model_progress = Some(ActiveModelProgress {
                attempt_id: "boundary-attempt".into(),
                progress: ModelProgress::new(1, vec![part]),
            });
            projection.stream(&chat, &thread, &state, 1).await?;
            let mut second = effect(2);
            let mut text = started("T");
            text.identity = ObservedPartIdentity::Provider(ProviderPartIdentity {
                item_id: "T".into(),
                output_index: None,
                content_index: 0,
                item_kind: ObservedItemKind::Text(pl_core::model::ModelTextChannel::Final),
                part: ObservedPartKind::OutputText,
            });
            second.model_member_content_available = vec![content_available(&text)];
            second.model_member_starts = vec![text].into();
            let receipt = ModelMemberReceipt {
                item: CompletionPresentationItem {
                    provider_item_id: "A".into(),
                    output_index: None,
                    kind: CompletionPresentationItemKind::Reasoning,
                    parts: vec![CompletionPresentationPart {
                        kind: CompletionPresentationPartKind::ReasoningText,
                        content_index: 0,
                        provider_part_id: None,
                        text: "FUTURE_ORIGINAL".into(),
                    }],
                },
                state: ModelMemberState::Completed,
            };
            second.model_members = vec![pl_core::model::ModelCompletedMember {
                turn_id: "boundary-turn".into(),
                attempt_id: "boundary-attempt".into(),
                generation: 0,
                member_id: "A".into(),
                payload: OpaquePayload::new(
                    "pl.model.completed-member",
                    1,
                    serde_json::to_string(&receipt)?,
                )?,
            }]
            .into();
            let (_, mut prepared) = projection.prepare(&thread, &second, &state, false).await?;
            let ended = prepared
                .current
                .atom_facts
                .iter()
                .find(|atom| atom.kind == ChatAtomKind::Reasoning)
                .unwrap();
            let a_id = ended.id.clone();
            assert!(
                prepared
                    .current_state
                    .as_ref()
                    .unwrap()
                    .projection()
                    .atoms
                    .iter()
                    .all(|atom| atom.id != a_id)
            );
            assert!(
                projection.preview_fields(&a_id).is_none(),
                "the producer really retired the old owner"
            );
            // Mutation after preparation cannot change this effect's saved boundary material.
            projection.store_preview(
                a_id.clone(),
                LivePreview {
                    fields: BTreeMap::from([(
                        BodyKey::Part(PresentationPart::ReasoningText(0)),
                        ContentBlock::from_text("LATEST_WRONG"),
                    )]),
                    shape: ThreadItemState::Thinking(ThreadThinkingItem::new(
                        Vec::new(),
                        Vec::new(),
                        ThreadContentLifecycle::streaming(),
                    )),
                    observed: None,
                    observed_version: 9,
                    model_part: None,
                },
            );
            projection.publish_prepared(&chat, &mut prepared).await?;
            super::restore_tests::save(&history, &second, &prepared).await?;
            let delta = prepared.display.as_ref().unwrap();
            let frozen = delta
                .members
                .iter()
                .find(|member| {
                    member.head.record.atom.id == a_id
                        && matches!(
                            member.head.record.content_source,
                            pl_protocol::DisplayContentSource::FrozenObservation { .. }
                        )
                })
                .unwrap();
            let terminal = delta
                .members
                .iter()
                .find(|member| member.head.record.atom.id == a_id && member.terminal)
                .unwrap();
            assert_ne!(frozen.head.member_key, terminal.head.member_key);
            assert_eq!(frozen.head.record.end_fact, None);
            assert_eq!(terminal.head.record.start_fact, None);
            let reference = &frozen.head.record.atom.contents[0].reference;
            let pl_protocol::ContentTarget::Body { owner, key } = &reference.target else {
                panic!()
            };
            let read = ChatHistory::read_content(
                &history,
                &ContentReadRequest {
                    epoch: chat.epoch(),
                    reference: pl_core::chat::ContentRef::Body(pl_core::chat::ChatContentKey {
                        owner: crate::studio::conversation_identity::content_owner_key(owner)?,
                        key: key.clone(),
                    }),
                    offset: 0,
                    max_bytes: 64,
                    generation: None,
                },
            )
            .await?;
            assert!(read.sealed);
            assert_eq!(read.bytes.as_bytes(), b"BOUNDARY_PREFIX");
            let (payload, texts) =
                read_frozen_payload(&history, &chat, &frozen.head.record).await?;
            assert_eq!(payload["type"], "thinking");
            assert_eq!(payload["data"]["outcome"]["kind"], "streaming");
            assert_eq!(texts, ["BOUNDARY_PREFIX"]);
            assert_eq!(prepared.completions.len(), 1);
            let digest = delta.digest()?;
            super::restore_tests::save(&history, &second, &prepared).await?;
            assert_eq!(prepared.display.as_ref().unwrap().digest()?, digest);
            Ok(())
        }
        .await;
        env.finish(result).await
    }

    #[tokio::test]
    async fn nested_task_invocation_survives_the_production_projection_and_cold_history()
    -> Result<()> {
        use pl_core::{
            model::ModelToolCall,
            thread::{
                ToolDelivery, ToolDeliveryTarget, ToolOutcome,
                task::{TaskRecord, TaskStatus},
            },
            tool::ToolOutput,
        };
        let env = crate::runtime_test_support::Environment::new(vec![], vec![]).await?;
        let result = async {
            let thread = pl_protocol::Thread::from(
                env.runtime
                    .create_thread(&env.project.id, "nested projection regression")
                    .await?,
            );
            let path = env._temp.path().join("nested-projection.sqlite");
            let history = HistoryStore::open(&path, &thread.id).await?;
            history.prepare_write().await?;
            let database = history
                .conversation_database_id()
                .await?
                .context("database")?;
            let chat = Session::new(history.clone(), TimelineEpoch::new("nested-hot")?);
            let channel = HistoryChannel::new(Arc::new(std::sync::atomic::AtomicU64::new(0)));
            let mut projection = LiveProjection::new();
            projection.bind_execution_history(channel.order_index(), history.clone())?;
            projection.bind_conversation_identity(database)?;
            let turn = TurnRecord {
                turn_id: "nested-turn".into(),
                input_id: None,
                state: TurnState::Running,
                elapsed_ms: None,
                model_steps: 1,
            };
            let call = ModelToolCall {
                call_id: "outer:nested:1".into(),
                tool_id: "exec_command".into(),
                arguments: OpaquePayload::new(
                    "application/json",
                    1,
                    "{\"command\":\"printf original\"}",
                )?,
                presentation_contract: None,
                rejection: None,
            };
            let mut task = TaskRecord {
                id: format!("task:{}", call.call_id),
                call_id: call.call_id.clone(),
                tool_id: call.tool_id.clone(),
                turn_id: turn.turn_id.clone(),
                revision: 1,
                status: TaskStatus::Running,
                cancel_requested: false,
                acknowledgement: None,
                started_sequence: Some(1),
                parent_call_id: Some("outer".into()),
                invocation: Some(call.clone()),
            };
            let mut state = ThreadSnapshot {
                turns: vec![turn.clone()].into(),
                ..Default::default()
            };
            state.tasks.insert(task.id.clone(), task.clone());
            let mut effect = ThreadEffectBatch {
                thread_id: thread.id.clone(),
                sequence: 1,
                committed_at: 1,
                turn: Some(turn),
                tasks: vec![task.clone()].into(),
                ..Default::default()
            };
            // There is deliberately no fabricated model call in context: Task owns this invocation.
            let prepared =
                publish(&mut projection, &history, &chat, &thread, &state, &effect).await?;
            let id = super::super::order::tool_id(&call.call_id);
            let item = prepared
                .items
                .iter()
                .find(|item| item.id == id)
                .context("nested start item")?;
            assert_eq!(
                item.tool().context("tool")?.invocation().arguments(),
                call.arguments.content()
            );
            task.revision = 2;
            task.status = TaskStatus::Succeeded;
            state.tasks.insert(task.id.clone(), task.clone());
            let delivery = ToolDelivery {
                target: ToolDeliveryTarget::Nested {
                    parent_call_id: "outer".into(),
                },
                call_id: call.call_id.clone(),
                tool_id: call.tool_id.clone(),
                output: ToolOutput::new(
                    OpaquePayload::text("PRIVATE_ORIGINAL"),
                    vec![pl_core::context::ContextContent::Text {
                        text: "PRIVATE_ORIGINAL".into(),
                    }],
                ),
                delivered_context: vec![],
                outcome: ToolOutcome::Succeeded,
            };
            state.deliveries = vec![delivery.clone()].into();
            effect.sequence = 2;
            effect.committed_at = 2;
            effect.turn = None;
            effect.tasks = vec![task].into();
            effect.deliveries = vec![delivery].into();
            publish(&mut projection, &history, &chat, &thread, &state, &effect).await?;
            assert!(state.context.records.is_empty());
            drop(projection);
            drop(chat);
            drop(history);
            let cold = HistoryStore::open(&path, &thread.id).await?;
            let item = cold.item(&id).await?.context("cold nested item")?;
            let tool = item.tool().context("cold tool")?;
            assert_eq!(tool.invocation().name(), "exec_command");
            assert_eq!(
                tool.terminal_output().context("terminal output")?.result(),
                "PRIVATE_ORIGINAL"
            );
            Ok(())
        }
        .await;
        env.finish(result).await
    }
}

#[cfg(test)]
mod restore_tests {
    //! Activation must make saved content available before the next reliable effect is prepared.
    use super::*;
    use crate::studio::storage::{
        history::{EffectCommit, HistoryStore},
        thread_writer::HistoryChannel,
    };
    use pl_core::{
        chat::{ChatHistory, ContentReadRequest, TimelineEpoch},
        model::{
            ActiveModelProgress, ModelProgress, ModelStartedMember, ObservedPart,
            ProviderPartIdentity,
        },
        thread::{AttemptOutcome, AttemptStatus, RequestAttempt, TurnRecord, TurnState},
    };

    pub(super) async fn save(
        history: &HistoryStore,
        effect: &ThreadEffectBatch,
        prepared: &PreparedEffect,
    ) -> anyhow::Result<()> {
        history
            .commit_effect(
                effect.sequence,
                EffectCommit {
                    items: &prepared.items,
                    completions: &prepared.completions,
                    current: &prepared.current,
                    rolled_back_turns: &Default::default(),
                    identities: &[],
                    messages: &[],
                    receipts: &[],
                    tasks: &[],
                    deliveries: &[],
                    delivery_repairs: &[],
                    attempt: effect.attempt.as_ref(),
                },
            )
            .await
    }

    #[tokio::test]
    async fn compaction_current_restores_without_an_item_and_settles_each_real_outcome()
    -> anyhow::Result<()> {
        use anyhow::Context as _;
        use pl_core::thread::{
            ContextCompactionEvent as Event, ContextCompactionOutcome as Outcome,
        };
        use pl_protocol::{
            ChatActiveStatus, ChatAtom, ChatAtomKind, ChatAtomLifecycle, ChatDeliveryKind,
            ChatFactPosition, ChatSourceId, ChatSourceLifecycle, ChatTerminalOutcome,
        };

        let env = crate::runtime_test_support::Environment::new(vec![], vec![]).await?;
        let result = async {
            let thread = pl_protocol::Thread::from(
                env.runtime
                    .create_thread(&env.project.id, "compaction restore")
                    .await?,
            );
            for (case, outcome, terminal, associated) in [
                (
                    "changed",
                    Outcome::Changed {
                        context_revision: 9,
                    },
                    ChatTerminalOutcome::Completed,
                    true,
                ),
                (
                    "unchanged",
                    Outcome::Unchanged,
                    ChatTerminalOutcome::Completed,
                    false,
                ),
                (
                    "failed",
                    Outcome::Failed {
                        message: "provider refused".into(),
                    },
                    ChatTerminalOutcome::Failed,
                    true,
                ),
                (
                    "cancelled",
                    Outcome::Cancelled,
                    ChatTerminalOutcome::Cancelled,
                    false,
                ),
            ] {
                let history = HistoryStore::open(
                    &env._temp.path().join(format!("compaction-{case}.sqlite")),
                    &thread.id,
                )
                .await?;
                history.prepare_write().await?;
                let database = history
                    .conversation_database_id()
                    .await?
                    .context("database")?;
                let session = Session::new(history.clone(), TimelineEpoch::new(case)?);
                let channel = HistoryChannel::new(Arc::new(std::sync::atomic::AtomicU64::new(0)));
                let mut projection = LiveProjection::new();
                projection.bind_execution_history(channel.order_index(), history.clone())?;
                projection.bind_conversation_identity(database.clone())?;
                let state = ThreadSnapshot::default();
                let turn_id = associated.then(|| "actual-turn".to_owned());
                let attempt_id = associated.then(|| "actual-attempt".to_owned());
                let start_position = ChatFactPosition {
                    effect_seq: 1,
                    suborder: 1,
                };
                let source = ChatSourceId::Operation {
                    operation_id: case.into(),
                };
                let effect = ThreadEffectBatch {
                    thread_id: thread.id.clone(),
                    sequence: 1,
                    committed_at: 10,
                    context_compactions: vec![Event::Started {
                        operation_id: case.into(),
                        turn_id: turn_id.clone(),
                        attempt_id: attempt_id.clone(),
                    }]
                    .into(),
                    ..Default::default()
                };
                let (_, mut prepared) = projection.prepare(&thread, &effect, &state, false).await?;
                projection.publish_prepared(&session, &mut prepared).await?;
                assert_eq!(session.head_seq(), 0);
                assert!(prepared.items.is_empty() && prepared.completions.is_empty());
                let active = prepared
                    .current
                    .projection()
                    .atoms
                    .first()
                    .context("active compaction")?
                    .clone();
                assert_eq!(active.kind, ChatAtomKind::Compaction);
                assert_eq!(active.source, source);
                assert_eq!(active.delivery, ChatDeliveryKind::Independent);
                assert_eq!(active.turn_id, turn_id);
                assert_eq!(active.attempt_id, attempt_id);
                assert_eq!(
                    active.lifecycle,
                    ChatAtomLifecycle::Active {
                        started: Some(start_position),
                        status: ChatActiveStatus::Running,
                    }
                );
                assert!(active.completion_seq.is_none() && active.payload.is_none());
                save(&history, &effect, &prepared).await?;
                drop(projection);
                // The reliable Started fact suffices; no current snapshot or business item was saved.
                let saved = history
                    .conversation_current()
                    .await?
                    .context("saved current")?;
                assert!(saved.atoms.is_empty());
                assert_eq!(
                    history.recovery_atom_starts(None, 128).await?,
                    vec![active.clone()]
                );
                assert!(!saved.execution_present);
                assert!(
                    saved.active.is_none(),
                    "cold facts do not claim a resident execution phase"
                );
                let mut restored = LiveProjection::new();
                restored.bind_execution_history(channel.order_index(), history.clone())?;
                restored.bind_conversation_identity(database)?;
                restored.restore_current(&session, &thread, &state).await?;
                assert_eq!(
                    restored
                        .current_state()
                        .context("restored current")?
                        .projection()
                        .atoms,
                    vec![active.clone()]
                );
                let unchanged = ThreadEffectBatch {
                    thread_id: thread.id.clone(),
                    sequence: 2,
                    committed_at: 11,
                    ..Default::default()
                };
                let mut prepared = restored
                    .prepare_committed(&thread, &unchanged, &state)
                    .await?;
                restored.publish_prepared(&session, &mut prepared).await?;
                assert!(prepared.completions.is_empty());
                assert_eq!(prepared.current.projection().atoms, vec![active.clone()]);
                let effect = ThreadEffectBatch {
                    thread_id: thread.id.clone(),
                    sequence: 3,
                    committed_at: 12,
                    context_compactions: vec![Event::Finished {
                        operation_id: case.into(),
                        outcome,
                    }]
                    .into(),
                    ..Default::default()
                };
                let (_, mut prepared) = restored.prepare(&thread, &effect, &state, false).await?;
                restored.publish_prepared(&session, &mut prepared).await?;
                assert_eq!(session.head_seq(), 1);
                assert_eq!(prepared.completions.len(), 1);
                let atom: ChatAtom =
                    serde_json::from_slice(&prepared.completions[0].header.metadata)?;
                assert_eq!(atom.id, active.id);
                assert_eq!(atom.source, source);
                assert_eq!(atom.delivery, ChatDeliveryKind::Independent);
                assert_eq!(atom.turn_id, turn_id);
                assert_eq!(atom.attempt_id, attempt_id);
                assert_eq!(atom.started_at, Some(10));
                let end_position = ChatFactPosition {
                    effect_seq: 3,
                    suborder: 1,
                };
                assert_eq!(
                    atom.lifecycle,
                    ChatAtomLifecycle::Terminal {
                        started: Some(start_position),
                        ended: Some(end_position),
                        outcome: terminal,
                    }
                );
                assert!(prepared.current.projection().atoms.is_empty());
                assert!(prepared.current.projection().active.is_none());
                assert!(
                    prepared
                        .current
                        .source_changes
                        .iter()
                        .any(|state| state.source == source
                            && state.lifecycle == ChatSourceLifecycle::Ended { outcome: terminal })
                );
                save(&history, &effect, &prepared).await?;
                assert!(
                    history
                        .conversation_current()
                        .await?
                        .context("terminal saved current")?
                        .atoms
                        .is_empty()
                );
                let mut repeated = prepared.clone();
                restored.publish_prepared(&session, &mut repeated).await?;
                assert!(Arc::ptr_eq(&prepared, &repeated));
                assert!(Arc::ptr_eq(&prepared.completions, &repeated.completions));
                save(&history, &effect, &repeated).await?;
                assert_eq!(session.head_seq(), 1);
            }
            Ok(())
        }
        .await;
        env.finish(result).await
    }

    #[derive(Debug, Clone, Copy)]
    enum Settlement {
        Completed,
        Failed,
        Cancelled,
    }

    #[tokio::test]
    async fn cold_completion_uses_its_full_receipt_without_restoring_progress() -> anyhow::Result<()>
    {
        immediate_settlement(Settlement::Completed).await
    }

    #[tokio::test]
    async fn resident_failure_freezes_its_accepted_prefix_only_at_terminal() -> anyhow::Result<()> {
        immediate_settlement(Settlement::Failed).await
    }

    #[tokio::test]
    async fn resident_cancellation_freezes_its_accepted_prefix_only_at_terminal()
    -> anyhow::Result<()> {
        immediate_settlement(Settlement::Cancelled).await
    }

    async fn immediate_settlement(settlement: Settlement) -> anyhow::Result<()> {
        use anyhow::Context as _;
        use pl_core::context::OpaquePayload;
        use pl_model::{
            completion::{
                CompletionPresentationItem, CompletionPresentationItemKind,
                CompletionPresentationPart, CompletionPresentationPartKind,
            },
            runtime::{ModelMemberReceipt, ModelMemberState},
        };

        let env = crate::runtime_test_support::Environment::new(vec![], vec![]).await?;
        let result = async {
        let thread = pl_protocol::Thread::from(
            env.runtime
                .create_thread(&env.project.id, "restore immediate completion")
                .await?,
        );
        // Synthetic effects use a real, separate database, not the Runtime coordinator's clock.
        let history =
            HistoryStore::open(&env._temp.path().join("restore-content.sqlite"), &thread.id)
                .await?;
        history.prepare_write().await?;
        let database = history
            .conversation_database_id()
            .await?
            .context("database")?;
        let chat = Session::new(history.clone(), TimelineEpoch::new("before-activation")?);
        let channel = HistoryChannel::new(Arc::new(std::sync::atomic::AtomicU64::new(0)));
        let mut projection = LiveProjection::new();
        projection.bind_execution_history(channel.order_index(), history.clone())?;
        projection.bind_conversation_identity(database.clone())?;
        let turn = TurnRecord {
            turn_id: "restore-turn".into(),
            input_id: None,
            state: TurnState::Running,
            elapsed_ms: None,
            model_steps: 1,
        };
        let mut state = ThreadSnapshot {
            turns: vec![turn.clone()].into(),
            attempts: vec![RequestAttempt::new(
                "restore-turn".into(),
                "restore-attempt".into(),
                0,
                AttemptStatus::Running,
            )]
            .into(),
            ..Default::default()
        };
        let effect = ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 1,
            committed_at: 10,
            turn: Some(turn),
            ..Default::default()
        };
        let (_, mut prepared) = projection.prepare(&thread, &effect, &state, false).await?;
        projection.publish_prepared(&chat, &mut prepared).await?;
        save(&history, &effect, &prepared).await?;
        let start = ModelStartedMember {
            turn_id: "restore-turn".into(),
            attempt_id: "restore-attempt".into(),
            generation: 0,
            identity: ObservedPartIdentity::Provider(ProviderPartIdentity {
                item_id: "restore-text".into(),
                output_index: None,
                content_index: 0,
                item_kind: ObservedItemKind::Text(ModelTextChannel::Final),
                part: ObservedPartKind::OutputText,
            }),
        };
        let mut part = ObservedPart::new(start.identity.clone());
        let effect = ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 2,
            committed_at: 11,
            model_member_starts: vec![start].into(),
            ..Default::default()
        };
        let (_, mut prepared) = projection.prepare(&thread, &effect, &state, false).await?;
        projection.publish_prepared(&chat, &mut prepared).await?;
        save(&history, &effect, &prepared).await?;

        let body = "新".repeat(50_000);
        // Exercise the real observation path: two authoritative replacements advance the original
        // current owner's content generation to 3. No private preview/generation state is edited.
        for (sequence, text) in [(3, "old body"), (4, "replacement"), (5, body.as_str())] {
            part = part.authorized(text);
            state.commit_sequence = sequence;
            state.model_progress = Some(ActiveModelProgress {
                attempt_id: "restore-attempt".into(),
                progress: ModelProgress::new(sequence, vec![part.clone()]),
            });
            projection.stream(&chat, &thread, &state, sequence).await?;
            let effect = ThreadEffectBatch {
                thread_id: thread.id.clone(),
                sequence,
                committed_at: sequence as i64 + 10,
                ..Default::default()
            };
            let (_, mut next) = projection.prepare(&thread, &effect, &state, false).await?;
            projection.publish_prepared(&chat, &mut next).await?;
            save(&history, &effect, &next).await?;
            prepared = next;
        }
        let saved_atom = prepared.current.projection().atoms[0].clone();
        assert!(prepared.current.contents.is_empty());
        let saved_content = prepared.current_state.as_ref().context("current owner")?
            .contents().values().find(|content| content.descriptor.key.key == "body")
            .context("active body")?.content();
        assert_eq!(saved_content.descriptor.generation, 3);
        assert_eq!(saved_content.descriptor.byte_length, 150_000);
        let receipt = ModelMemberReceipt {
            item: CompletionPresentationItem {
                provider_item_id: "restore-text".into(),
                output_index: None,
                kind: CompletionPresentationItemKind::Text(
                    pl_protocol::trace::TraceTextChannel::Final,
                ),
                parts: vec![CompletionPresentationPart {
                    content_index: 0,
                    provider_part_id: None,
                    text: body.clone(),
                    kind: CompletionPresentationPartKind::OutputText,
                }],
            },
            state: ModelMemberState::Completed,
        };
        let mut effect = ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 6,
            committed_at: 20,
            model_members: vec![pl_core::model::ModelCompletedMember {
                turn_id: "restore-turn".into(),
                attempt_id: "restore-attempt".into(),
                generation: 0,
                member_id: "restore-text".into(),
                payload: OpaquePayload::new(
                    "pl.model.completed-member",
                    1,
                    serde_json::to_string(&receipt)?,
                )?,
            }]
            .into(),
            ..Default::default()
        };
        let expected_outcome = match settlement {
            Settlement::Completed => pl_protocol::ChatTerminalOutcome::Completed,
            Settlement::Failed | Settlement::Cancelled => {
                // A terminal attempt may have no member receipt: its admitted preview is finalized
                // through the original attempt path, preserving the same saved body and refs.
                let error = Arc::new(pl_core::model::ModelError {
                    details: None,
                    kind: match settlement {
                        Settlement::Cancelled => pl_core::model::ModelFailureKind::Cancelled,
                        _ => pl_core::model::ModelFailureKind::Unavailable,
                    },
                    usage: Box::default(),
                    source: None,
                });
                let (status, outcome, terminal) = match settlement {
                    Settlement::Failed => (
                        AttemptStatus::Failed,
                        AttemptOutcome::Failed(error),
                        pl_protocol::ChatTerminalOutcome::Failed,
                    ),
                    Settlement::Cancelled => (
                        AttemptStatus::Cancelled,
                        AttemptOutcome::Cancelled { result: Err(error) },
                        pl_protocol::ChatTerminalOutcome::Cancelled,
                    ),
                    Settlement::Completed => unreachable!(),
                };
                state.attempts = vec![RequestAttempt::new(
                    "restore-turn".into(),
                    "restore-attempt".into(),
                    0,
                    status,
                )]
                .into();
                state.model_progress = None;
                effect.model_members = Arc::from([]);
                effect.attempt = Some(pl_core::thread::journal::AttemptUpdate {
                    turn_id: "restore-turn".into(),
                    attempt_id: "restore-attempt".into(),
                    retry_of: None,
                    input_revision: 0,
                    request_metadata: None,
                    usage_binding: None,
                    tool_projection: None,
                    tools: Arc::from([]),
                    outcome,
                    input_estimate: None,
                });
                terminal
            }
        };
        state.commit_sequence = effect.sequence;
        let restored_chat = Session::new(history.clone(), TimelineEpoch::new("after-activation")?);
        let mut restored = if matches!(settlement, Settlement::Completed) {
            let mut owner = LiveProjection::new();
            // The Runtime's original index owns execution placement, independently of
            // this dropped/re-created product projection and its discarded progress.
            owner.bind_execution_history(channel.order_index(), history.clone())?;
            owner.bind_conversation_identity(database)?;
            owner.restore_current(&restored_chat, &thread, &state).await?;
            assert!(owner.current_state().context("restored current")?.contents().is_empty());
            owner
        } else {
            projection
        };
        let restored_snapshot = restored.current_state();

        // Nothing warms the restored owner between restore_current and its first reliable effect.
        let (_, mut completed) = restored.prepare(&thread, &effect, &state, false).await?;
        let content = completed
            .completion_drafts
            .as_ref()
            .context("completion drafts")?
            .iter()
            .flat_map(|draft| draft.contents.values())
            .find(|content| content.descriptor.key == saved_content.descriptor.key)
            .context("completion body")?
            .clone();
        eprintln!(
            "restore immediate {settlement:?}: saved_generation={}, bytes={}, completion_generation={}",
            saved_content.descriptor.generation,
            saved_content.descriptor.byte_length,
            content.descriptor.generation
        );
        restored
            .publish_prepared(&restored_chat, &mut completed)
            .await?;
        save(&history, &effect, &completed).await?;
        let expected_generation = if matches!(settlement, Settlement::Completed) { 1 } else { 3 };
        assert_eq!(content.descriptor.generation, expected_generation);
        assert_eq!(content.data.range(0, 150_000)?.as_bytes(), body.as_bytes());
        let completed_atom = completed.completions.iter()
            .map(|record| serde_json::from_slice::<pl_protocol::ChatAtom>(&record.header.metadata))
            .collect::<Result<Vec<_>, _>>()?.into_iter()
            .find(|atom| atom.id == saved_atom.id).context("settled atom")?;
        assert_eq!(completed_atom.source, saved_atom.source);
        assert_eq!(completed_atom.source_order, saved_atom.source_order);
        assert!(matches!(completed_atom.lifecycle, pl_protocol::ChatAtomLifecycle::Terminal {outcome,..}
            if outcome == expected_outcome));
        assert!(completed_atom.source_state.is_none());
        if matches!(settlement, Settlement::Completed) {
            let snapshot = restored_snapshot.context("restored current")?;
            assert!(snapshot.projection().previews.is_empty());
            assert!(snapshot.contents().is_empty());
        }
        let mut bytes = Vec::new();
        while bytes.len() < body.len() {
            let window = ChatHistory::read_content(&history, &ContentReadRequest {
                epoch: restored_chat.epoch(), reference: pl_core::chat::ContentRef::Body(content.descriptor.key.clone()),
                offset: bytes.len() as u64, max_bytes: 64 * 1024, generation: Some(expected_generation),
            }).await?;
            assert_eq!(window.available_through, 150_000);
            assert!(window.sealed);
            assert!(!window.bytes.as_bytes().is_empty());
            bytes.extend_from_slice(window.bytes.as_bytes());
        }
        assert_eq!(bytes, body.as_bytes());
        Ok(())
    }
    .await;
        env.finish(result).await
    }
}

#[cfg(test)]
mod completion_tests {
    use super::*;

    fn original_result_bytes(result: &TurnResult) -> u64 {
        let identities = result.identities().fold(0_u64, |bytes, id| {
            bytes
                .saturating_add(id.len() as u64)
                .saturating_add(RETAINED_ENTRY_OVERHEAD)
        });
        let mut bytes = result.finals.iter().chain(result.commentary.iter()).fold(
            identities,
            |bytes, (key, text)| {
                bytes
                    .saturating_add(key.1.len() as u64)
                    .saturating_add(text.len() as u64)
                    .saturating_add(RETAINED_ENTRY_OVERHEAD)
            },
        );
        if let Some((_, tool)) = &result.last_tool {
            bytes = bytes.saturating_add(tool_bytes(tool));
        }
        if let Some(finish) = &result.finish {
            bytes = bytes
                .saturating_add(finish.message.len() as u64)
                .saturating_add(
                    finish
                        .feedback_message
                        .as_ref()
                        .map_or(0, |body| body.len()) as u64,
                )
                .saturating_add(finish.review.as_ref().map_or(0, |review| {
                    review.summary.len() + review.reviewed_version.len()
                }) as u64);
        }
        bytes
    }

    fn result_item(id: &str, ordinal: u64, revision: u64, state: ThreadItemState) -> ThreadItem {
        ThreadItem::new(
            id.into(),
            "thread".into(),
            "turn".into(),
            ordinal,
            revision,
            10,
            10,
            state,
        )
    }

    #[test]
    fn turn_result_identity_charge_matches_original_sum_across_revisions_and_restore() {
        let text = |channel, body: &str| {
            ThreadItemState::Text(ThreadTextItem::new(
                channel,
                body.into(),
                Vec::new(),
                ThreadContentLifecycle::completed(10),
            ))
        };
        let mut items = vec![
            result_item(
                "reasoning-a",
                1,
                1,
                ThreadItemState::Thinking(ThreadThinkingItem::new(
                    Vec::new(),
                    vec!["first reasoning".into()],
                    ThreadContentLifecycle::completed(10),
                )),
            ),
            result_item(
                "reasoning-b",
                2,
                1,
                ThreadItemState::Thinking(ThreadThinkingItem::new(
                    Vec::new(),
                    vec!["second reasoning".into()],
                    ThreadContentLifecycle::completed(10),
                )),
            ),
            result_item("final-b", 4, 1, text(ThreadTextChannel::Final, "β")),
            result_item("final-a", 3, 1, text(ThreadTextChannel::Final, "α")),
            result_item("final-a", 3, 2, text(ThreadTextChannel::Final, "revised α")),
            result_item("final-a", 9, 3, text(ThreadTextChannel::Final, "moved α")),
        ];
        for index in 0..TURN_COMMENTARY_PARTS + 2 {
            items.push(result_item(
                &format!("commentary-{index:02}"),
                10 + index as u64,
                1,
                text(
                    ThreadTextChannel::Commentary,
                    &format!("commentary {index}"),
                ),
            ));
        }
        let mut result = TurnResult::default();
        assert_eq!(result.retained_bytes(), std::mem::size_of::<u64>() as u64);
        for item in &items {
            result.observe(item);
            assert_eq!(
                result.retained_bytes(),
                original_result_bytes(&result).saturating_add(std::mem::size_of::<u64>() as u64)
            );
        }
        let identities = items
            .iter()
            .map(|item| item.id.as_str())
            .collect::<BTreeSet<_>>();
        assert_eq!(result.identities().collect::<BTreeSet<_>>(), identities);
        assert_eq!(
            result.final_text().as_deref(),
            Some("revised α\n\nβ\n\nmoved α")
        );
        assert_eq!(
            result.commentary(),
            (2..TURN_COMMENTARY_PARTS + 2)
                .map(|index| format!("commentary {index}"))
                .collect::<Vec<_>>()
                .join("\n\n")
        );
        let before = result.retained_bytes();
        result.observe(items.last().unwrap());
        assert_eq!(
            result.retained_bytes(),
            before,
            "repeated identity/body was charged twice"
        );
        let cloned = result.clone();
        let restored = TurnResult::from_items(&items);
        for equivalent in [&cloned, &restored] {
            assert_eq!(equivalent.retained_bytes(), before);
            assert_eq!(equivalent.identities().collect::<BTreeSet<_>>(), identities);
            assert_eq!(equivalent.final_text(), result.final_text());
            assert_eq!(equivalent.commentary(), result.commentary());
        }
    }

    fn store_retention_entry(projection: &mut LiveProjection, ordinal: usize, revision: u64) {
        let id = format!("part-{ordinal:04}");
        let body = format!("body {ordinal}, revision {revision}");
        let shape = ThreadItemState::Text(ThreadTextItem::new(
            ThreadTextChannel::Final,
            body.clone(),
            Vec::new(),
            ThreadContentLifecycle::streaming(),
        ));
        let item = result_item(&id, ordinal as u64, revision, shape.clone());
        projection.store_item(item.clone());
        projection.fact(&item);
        projection.raise_revision(&id, revision);
        projection.store_preview(
            id.clone(),
            LivePreview {
                fields: BTreeMap::from([(BodyKey::Body, ContentBlock::from_text(&body))]),
                observed: Some(ObservedKey::Provider(
                    0,
                    Arc::from(id),
                    PresentationPart::OutputText(0),
                )),
                shape,
                observed_version: revision,
                model_part: None,
            },
        );
    }

    fn assert_retention_tables(projection: &LiveProjection) {
        let items = projection.items.values().fold(0_u64, |bytes, item| {
            bytes.saturating_add(charged_item_bytes(item))
        });
        let facts = projection.facts.iter().fold(0_u64, |bytes, (id, fact)| {
            bytes.saturating_add(fact_bytes(id, fact))
        });
        let previews = projection
            .previews
            .iter()
            .fold(0_u64, |bytes, (id, preview)| {
                bytes.saturating_add(preview_bytes(id, preview))
            });
        let revisions = projection
            .revisions
            .keys()
            .fold(0_u64, |bytes, id| bytes.saturating_add(revision_bytes(id)));
        assert_eq!(
            (
                projection.items_bytes,
                projection.facts_bytes,
                projection.previews_bytes,
                projection.revisions_bytes
            ),
            (items, facts, previews, revisions)
        );
        let observed = projection
            .previews
            .values()
            .filter_map(|preview| {
                preview.observed.as_ref().map(|key| {
                    (
                        key.clone(),
                        ObservedVersion {
                            content: preview.observed_version,
                            ended: preview.shape.is_terminal(),
                            model_part: preview.model_part,
                        },
                    )
                })
            })
            .collect::<HashMap<_, _>>();
        assert!(
            projection.observed == observed,
            "observation mirror differs from retained previews"
        );
    }

    #[test]
    fn retain_preserves_running_totals_and_observed_mirror_with_and_without_pruning() {
        let mut projection = LiveProjection::new();
        let turn = pl_core::thread::TurnRecord {
            turn_id: "turn".into(),
            input_id: None,
            state: TurnState::Running,
            elapsed_ms: None,
            model_steps: 1,
        };
        let mut state = ThreadSnapshot {
            turns: vec![turn.clone()].into(),
            ..Default::default()
        };
        store_retention_entry(&mut projection, 0, 1);
        store_retention_entry(&mut projection, 1, 1);
        store_retention_entry(&mut projection, 1, 22);
        assert_retention_tables(&projection);
        let before = (
            projection.items_bytes,
            projection.facts_bytes,
            projection.previews_bytes,
            projection.revisions_bytes,
        );
        projection.retain(&state);
        assert_retention_tables(&projection);
        assert_eq!(projection.facts.len(), 2);
        assert_eq!(
            (
                projection.items_bytes,
                projection.facts_bytes,
                projection.previews_bytes,
                projection.revisions_bytes
            ),
            before
        );

        for ordinal in 2..=LIVE_ITEM_WINDOW {
            store_retention_entry(&mut projection, ordinal, 1);
        }
        assert_retention_tables(&projection);
        assert_eq!(projection.facts.len(), LIVE_ITEM_WINDOW + 1);
        projection.retain(&state);
        assert_retention_tables(&projection);
        assert_eq!(
            (
                projection.items.len(),
                projection.facts.len(),
                projection.previews.len(),
                projection.revisions.len()
            ),
            (
                LIVE_ITEM_WINDOW,
                LIVE_ITEM_WINDOW,
                LIVE_ITEM_WINDOW,
                LIVE_ITEM_WINDOW
            )
        );
        assert!(!projection.facts.contains_key("part-0000"));
        assert!(
            projection
                .facts
                .contains_key(&format!("part-{LIVE_ITEM_WINDOW:04}"))
        );
        projection.retain(&state);
        assert_retention_tables(&projection);

        state.turns = vec![pl_core::thread::TurnRecord {
            turn_id: "next-turn".into(),
            ..turn
        }]
        .into();
        projection.retain(&state);
        assert_retention_tables(&projection);
        assert!(
            projection.items.is_empty()
                && projection.facts.is_empty()
                && projection.previews.is_empty()
                && projection.revisions.is_empty()
        );
        assert!(projection.observed.is_empty());
        projection.retain(&state);
        assert_retention_tables(&projection);
    }

    #[test]
    fn interrupted_reasoning_uses_runtime_fields_and_execution_placement() -> anyhow::Result<()> {
        let mut projection = LiveProjection::new();
        let id = super::super::order::presentation_id(
            "attempt",
            0,
            "provider-item",
            Some(PresentationPart::ReasoningText(0)),
        );
        projection.store_fact(
            id.clone(),
            Fact {
                ordinal: 42,
                revision: 9,
                created_at: 10,
                turn_id: "turn".into(),
            },
        );
        projection.store_preview(
            id.clone(),
            LivePreview {
                fields: BTreeMap::from([(
                    BodyKey::Part(PresentationPart::ReasoningText(0)),
                    ContentBlock::from_text("received reasoning prefix"),
                )]),
                observed: None,
                shape: ThreadItemState::Thinking(ThreadThinkingItem::new(
                    Vec::new(),
                    Vec::new(),
                    ThreadContentLifecycle::streaming(),
                )),
                observed_version: 8,
                model_part: None,
            },
        );
        let items = projection.attempt_preview_items("thread", "attempt", "turn")?;
        assert_eq!(items.len(), 1);
        let (actual_id, item) = &items[0];
        assert_eq!(actual_id, &id);
        assert_eq!((item.ordinal, item.revision, item.created_at), (42, 9, 10));
        let ThreadItemState::Thinking(thinking) = item.state() else {
            anyhow::bail!("thinking preview lost its execution kind");
        };
        assert_eq!(thinking.content(), ["received reasoning prefix"]);
        assert!(
            !item.is_terminal(),
            "only the subsequent reliable effect closes the prefix"
        );
        Ok(())
    }

    #[test]
    fn terminal_tool_with_pending_interaction_does_not_seed_a_sealed_completion() {
        let tool = ThreadToolItem::new(
            pl_protocol::ThreadToolInvocation::new("call".into(), "ask".into(), "{}".into()),
            ThreadToolState::Interrupted(pl_protocol::InterruptedThreadTool::new(
                10,
                "waiting".into(),
            )),
        )
        .with_user_input(Some(pl_protocol::ThreadToolUserInput::new(
            "interaction".into(),
            Vec::new(),
            pl_protocol::ThreadToolUserInputState::Pending,
        )));
        let item = ThreadItem::new(
            "tool:4:call".into(),
            "thread".into(),
            "turn".into(),
            1,
            1,
            10,
            10,
            ThreadItemState::Tool(tool),
        );
        assert!(!completion_ready(&item));
        let mut projection = LiveProjection::new();
        projection.seed(vec![item.clone()], BTreeSet::new());
        assert!(
            !projection
                .order_index
                .as_ref()
                .is_some_and(|index| index.is_sealed(&item.id))
        );
        let ThreadItemState::Tool(tool) = item.state() else {
            unreachable!()
        };
        let answered = item.clone().with_state(ThreadItemState::Tool(
            ThreadToolItem::new(tool.invocation().clone(), tool.state().clone()).with_user_input(
                Some(pl_protocol::ThreadToolUserInput::new(
                    "interaction".into(),
                    Vec::new(),
                    pl_protocol::ThreadToolUserInputState::Cancelled,
                )),
            ),
        ));
        assert!(completion_ready(&answered));
    }
}
