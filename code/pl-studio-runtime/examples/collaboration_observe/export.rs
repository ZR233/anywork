//! Paginated public Chat export; content is copied through bounded ranges.
use super::super::evidence::{Evidence, MAX_ITEMS, Manifest, ThreadExport};
use anyhow::{Context, Result, ensure};
use pl_protocol::{
    ChatAtomKind, ChatAtomLifecycle, ChatEntry, ChatPlacement, ChatScope, ChatSourceId,
    ContentRange, ContentRef, ContentTarget, PayloadData, ReadDemand,
};
use pl_studio_runtime::{ConversationEvent, ConversationReader, StudioRuntime};
use std::{collections::HashSet, io::Write};

const DEMAND: ReadDemand = ReadDemand {
    max_items: 100,
    max_bytes: 256 * 1024,
};
const WINDOW_BYTES: u32 = 64 * 1024;

pub(super) async fn thread(
    runtime: &StudioRuntime,
    evidence: &Evidence,
    id: &str,
    index: usize,
    manifest: &mut Manifest,
    budget: &super::super::Boundary,
) -> Result<()> {
    budget.check()?;
    let prefix = format!("threads/{index:03}");
    let export_index = manifest.thread_exports.len();
    manifest.thread_exports.push(ThreadExport {
        thread_id: id.into(),
        directory: prefix.clone(),
        ..ThreadExport::default()
    });
    let snapshot = budget.read(runtime.thread_snapshot(id)).await?;
    manifest.thread_exports[export_index].snapshot_revision = Some(snapshot.revision);
    manifest.thread_exports[export_index].storage = snapshot.storage.clone();
    evidence.json(&format!("{prefix}/snapshot.json"), id, &snapshot)?;
    let mut cursor = None;
    let mut page_index = 0;
    loop {
        let page = budget
            .read(runtime.list_thread_turns(id, cursor.as_deref(), 200))
            .await
            .with_context(|| format!("read Turn page {page_index} for {id}"))?;
        if page_index == 0 {
            manifest.thread_exports[export_index].latest_turn =
                page.turns.first().map(|history| history.turn.clone());
        }
        evidence.json(&format!("{prefix}/turns/{page_index:05}.json"), id, &page)?;
        manifest.thread_exports[export_index].turn_pages += 1;
        let next = page.next_cursor;
        ensure!(
            next.is_none() || next != cursor,
            "Turn cursor did not advance"
        );
        cursor = next;
        page_index += 1;
        if cursor.is_none() {
            break;
        }
        evidence.check_disk_budget()?;
    }

    // Children parents come only from the public terminal-Turn envelope. Never
    // synthesize a parent key or derive a Core position from an opaque cursor.
    let mut scopes = vec![ChatScope::Main];
    let mut parents = HashSet::new();
    let mut scope_index = 0;
    while scope_index < scopes.len() {
        let scope = scopes[scope_index].clone();
        let mut feed = budget
            .read(runtime.open_conversation_feed(id, scope.clone(), DEMAND))
            .await?;
        let reader = feed.reader().clone();
        let result = async {
            let mut batch = loop {
                let event = budget
                    .read(feed.recv())
                    .await?
                    .context("chat export ended before its Set")?;
                if let ConversationEvent::Chat { batch } = event {
                    break *batch;
                }
            };
            ensure!(batch.placement == ChatPlacement::Set);
            ensure!(matches!(scope, ChatScope::Main) == batch.current.is_some());
            let mut page_index = 0;
            loop {
                budget.check()?;
                evidence.check_limit(
                    manifest.timeline_items + batch.entries.len() <= MAX_ITEMS,
                    "chat entry budget exceeded (10000)",
                )?;
                let page_prefix = format!("{prefix}/chat/{scope_index:03}/{page_index:05}");
                evidence.json(&format!("{page_prefix}.json"), id, &batch)?;
                // The existing evidence manifest counts all exported Chat scopes.
                manifest.thread_exports[export_index].timeline_pages += 1;
                for (item_index, entry) in batch.entries.iter().enumerate() {
                    manifest.timeline_items += 1;
                    let item_prefix = format!("{page_prefix}-{item_index:03}");
                    let ChatEntry::Atom(atom) = entry else {
                        evidence.json(&format!("{item_prefix}.source.json"), id, entry)?;
                        continue;
                    };
                    let completion_id = atom.completion_item_id.as_deref();
                    if matches!(&atom.lifecycle, ChatAtomLifecycle::Active { .. }) {
                        ensure!(
                            atom.payload.is_none() && completion_id.is_none(),
                            "active chat atom unexpectedly carried terminal payload identity"
                        );
                        evidence.json(&format!("{item_prefix}.active.json"), &atom.id, atom)?;
                        manifest.unfinished.push(format!(
                            "{id}: active chat atom {} exported as metadata only; it has no terminal payload",
                            atom.id
                        ));
                        continue;
                    }
                    let Some(payload) = atom.payload.as_ref() else {
                        anyhow::bail!(
                            "{id}: terminal chat atom {} omitted its payload",
                            atom.id
                        );
                    };
                    let identity = completion_id.context("terminal atom omitted completion_item_id")?;
                    let raw = match payload {
                        PayloadData::Inline { bytes } => {
                            evidence.raw(
                                &format!("{item_prefix}.payload.json"),
                                identity,
                                bytes,
                            )?;
                            Some(bytes.clone())
                        }
                        PayloadData::Deferred {
                            reference,
                            byte_length,
                        } => {
                            ensure!(
                                matches!(
                                    &reference.target,
                                    ContentTarget::ItemPayload { item_id }
                                        if item_id.as_str() == identity
                                ),
                                "terminal atom payload reference did not match completion_item_id"
                            );
                            copy_reference(
                                &reader,
                                reference,
                                Some(*byte_length),
                                evidence,
                                &format!("{item_prefix}.payload.json"),
                                identity,
                                budget,
                                true,
                            )
                            .await?
                        }
                    };
                    // Preserve unknown payloads verbatim. Only inspect the stable
                    // envelope to discover public parent identity/nonterminal facts.
                    if let Some(value) = raw
                        .as_deref()
                        .and_then(|raw| serde_json::from_slice::<serde_json::Value>(raw).ok())
                        && value["contract"] == "anywork.chat/1"
                    {
                        if let Some(turn_id) = atom.turn_id.as_deref()
                            && let Some(payload_turn_id) = value["turnId"].as_str()
                        {
                            ensure!(
                                turn_id == payload_turn_id,
                                "atom metadata and frozen payload disagree on turn identity"
                            );
                        }
                        let payload_kind = value["type"].as_str();
                        let metadata_matches = match atom.kind {
                            ChatAtomKind::Input | ChatAtomKind::Text => payload_kind == Some("text"),
                            ChatAtomKind::Reasoning => {
                                matches!(payload_kind, Some("thinking" | "inference"))
                            }
                            ChatAtomKind::ToolCall => payload_kind == Some("tool"),
                            ChatAtomKind::FileChange => payload_kind == Some("file"),
                            ChatAtomKind::Skill => payload_kind == Some("skill"),
                            ChatAtomKind::Interaction => {
                                payload_kind == Some("tool")
                                    && value["data"]
                                        .get("userInput")
                                        .is_some_and(|input| !input.is_null())
                            }
                            ChatAtomKind::Plan => payload_kind == Some("plan"),
                            ChatAtomKind::Compaction => payload_kind == Some("contextCompaction"),
                            ChatAtomKind::TurnReceipt => payload_kind == Some("turn"),
                            ChatAtomKind::Receipt | ChatAtomKind::Unknown => true,
                        };
                        ensure!(
                            metadata_matches,
                            "atom kind {:?} conflicts with frozen payload type {payload_kind:?}",
                            atom.kind
                        );
                        if value["type"] == "turn" {
                            ensure!(
                                atom.kind == ChatAtomKind::TurnReceipt,
                                "Turn payload was not labeled as a TurnReceipt atom"
                            );
                            let turn_id = atom
                                .turn_id
                                .as_deref()
                                .context("TurnReceipt atom omitted its real turn_id")?;
                            let payload_turn_id = value["turnId"]
                                .as_str()
                                .context("Turn payload omitted its turn identity")?;
                            ensure!(
                                turn_id == payload_turn_id,
                                "TurnReceipt atom and payload turn identities disagree"
                            );
                            ensure!(
                                matches!(
                                    &atom.source,
                                    ChatSourceId::ForegroundTurn { turn_id: source_turn }
                                        if source_turn.as_str() == turn_id
                                ),
                                "TurnReceipt source identity did not match its turn_id"
                            );
                            let parent = pl_core::chat::ChatKey::new("turn", turn_id)?
                                .as_str()
                                .to_owned();
                            if parents.insert(parent.clone()) {
                                evidence.check_limit(
                                    scopes.len() < MAX_ITEMS,
                                    "children scope budget exceeded",
                                )?;
                                scopes.push(ChatScope::Children {
                                    parent_id: parent,
                                });
                            }
                        }
                        if value["type"] == "tool" {
                            let state = value["data"]["state"]["kind"].as_str();
                            if !matches!(
                                state,
                                Some(
                                    "succeeded" | "failed" | "denied" | "cancelled" | "interrupted"
                                )
                            ) {
                                let path = format!("{item_prefix}.nonterminal.json");
                                evidence.json(&path, identity, &value)?;
                                manifest.thread_exports[export_index].nonterminal_tools += 1;
                                manifest.unfinished.push(format!(
                                    "{id}: exported tool has nonterminal/unknown state; see {path}"
                                ));
                            }
                        }
                    }
                    // Manifests are producer-supplied. Do not decode tool history
                    // or infer content references from renderer-specific fields.
                    let mut continuation = None;
                    let mut manifest_page = 0;
                    loop {
                        let page = budget
                            .read(reader.list_contents(
                                identity,
                                continuation.as_deref(),
                                DEMAND,
                            ))
                            .await?;
                        evidence.json(
                            &format!("{item_prefix}.contents-{manifest_page:03}.json"),
                            identity,
                            &page,
                        )?;
                        for (body_index, entry) in page.entries.iter().enumerate() {
                            let path = format!(
                                "{item_prefix}.body-{manifest_page:03}-{body_index:03}.bin"
                            );
                            copy_reference(
                                &reader,
                                &entry.reference,
                                None,
                                evidence,
                                &path,
                                identity,
                                budget,
                                false,
                            )
                            .await?;
                            evidence.json(&format!("{path}.ref.json"), identity, entry)?;
                            manifest.thread_exports[export_index].detail_fields += 1;
                        }
                        ensure!(
                            page.continuation.is_none() || page.continuation != continuation,
                            "content manifest continuation did not advance"
                        );
                        continuation = page.continuation;
                        if continuation.is_none() {
                            break;
                        }
                        manifest_page += 1;
                        evidence.check_disk_budget()?;
                    }
                }
                let Some(before) = batch.before else {
                    break;
                };
                batch = budget.read(reader.load_older(&before, DEMAND)).await?;
                ensure!(batch.placement == ChatPlacement::Prepend && batch.current.is_none());
                ensure!(
                    batch.before.as_ref() != Some(&before),
                    "chat continuation did not advance"
                );
                // Neither a short page nor a nonempty continuation proves EOF.
                page_index += 1;
                evidence.check_disk_budget()?;
            }
            Ok::<_, anyhow::Error>(())
        }
        .await;
        // Native feed and read lease are independent. A failed export or failed
        // producer close must not prevent the original reader from being joined.
        feed.request_close();
        reader.request_close();
        let producer = feed.close().await;
        let read = reader.close().await;
        result.with_context(|| format!("export cleanup: producer={producer:?}, read={read:?}"))?;
        producer?;
        read?;
        scope_index += 1;
    }
    manifest.thread_exports[export_index].complete = true;
    Ok(())
}

#[expect(
    clippy::too_many_arguments,
    reason = "bounded copy keeps evidence and read ownership explicit"
)]
async fn copy_reference(
    reader: &ConversationReader,
    reference: &ContentRef,
    expected_length: Option<u64>,
    evidence: &Evidence,
    relative: &str,
    identity: &str,
    budget: &super::super::Boundary,
    capture_envelope: bool,
) -> Result<Option<Vec<u8>>> {
    let mut file = evidence.create(relative, identity)?;
    // Huge/unknown envelopes remain raw files, not an unbounded in-memory JSON tree.
    let mut captured = (capture_envelope
        && expected_length.is_some_and(|length| length <= DEMAND.max_bytes as u64))
    .then(Vec::new);
    let result = async {
        let mut offset = 0;
        let mut generation = None;
        let mut length = expected_length;
        loop {
            let window = budget
                .read(reader.read_content(
                    reference,
                    ContentRange {
                        offset,
                        max_bytes: WINDOW_BYTES,
                    },
                ))
                .await?;
            ensure!(
                window.offset == offset && window.sealed,
                "export cannot splice changing content"
            );
            ensure!(
                generation
                    .as_ref()
                    .is_none_or(|value| value == &window.generation),
                "content generation changed"
            );
            generation = Some(window.generation);
            if let Some(length) = length {
                ensure!(window.available_through == length, "content length changed");
            } else {
                length = Some(window.available_through);
            }
            let end = offset
                .checked_add(window.bytes.len() as u64)
                .context("content offset overflow")?;
            ensure!(
                end <= window.available_through,
                "content exceeded declared length"
            );
            ensure!(
                end == window.available_through || end > offset,
                "content range did not advance"
            );
            file.write_all(&window.bytes)?;
            if let Some(bytes) = captured.as_mut() {
                bytes.extend(&window.bytes);
            }
            offset = end;
            budget.check()?;
            evidence.check_disk_budget()?;
            if offset == window.available_through {
                break;
            }
        }
        Ok::<_, anyhow::Error>(())
    }
    .await;
    let finish = file.finish(result.is_ok());
    result.with_context(|| format!("finishing {relative}: {finish:?}"))?;
    finish?;
    Ok(captured)
}
