#[expect(
    dead_code,
    reason = "shared isolated fixtures also serve other integration test binaries"
)]
mod support;

use anyhow::{Context, Result, ensure};
use pl_protocol::{
    ChatAtom, ChatBatch, ChatEntry, ChatPlacement, ChatScope, ContentRange, ContentRef,
    PayloadData, ReadDemand, ThreadWorkspaceMode,
    studio::{StudioPromptInput, SubmitPromptRequest},
};
use pl_provider_fixture::{ReplyStage, responses_text};
use pl_studio_runtime::{ConversationEvent, ConversationFeed, ConversationReader};
use std::{collections::HashSet, time::Duration};
use support::{Environment, completed_prompt, prompt_step, reached, text_reply};

fn demand(max_items: u32) -> ReadDemand {
    ReadDemand {
        max_items,
        max_bytes: 256 * 1024,
    }
}

async fn next(feed: &mut ConversationFeed) -> Result<ConversationEvent> {
    tokio::time::timeout(Duration::from_secs(10), feed.recv())
        .await
        .context("conversation feed did not deliver its pending facts")??
        .context("conversation feed ended before its pending facts")
}

async fn chat(feed: &mut ConversationFeed) -> Result<ChatBatch> {
    loop {
        if let ConversationEvent::Chat { batch } = next(feed).await? {
            return Ok(*batch);
        }
    }
}

// Close both independent owners even if the observation or one close failed.
async fn finish_feed(feed: &mut ConversationFeed, result: Result<()>) -> Result<()> {
    let reader = feed.reader().clone();
    feed.request_close();
    reader.request_close();
    let producer = feed.close().await;
    let read = reader.close().await;
    result.with_context(|| format!("feed cleanup: producer={producer:?}, read={read:?}"))?;
    producer?;
    read
}

async fn content(reader: &ConversationReader, reference: &ContentRef, len: u64) -> Result<Vec<u8>> {
    let mut bytes = Vec::new();
    let mut generation = None;
    while (bytes.len() as u64) < len {
        let offset = bytes.len() as u64;
        let window = reader
            .read_content(
                reference,
                ContentRange {
                    offset,
                    max_bytes: (len - offset).min(64 * 1024) as u32,
                },
            )
            .await?;
        ensure!(window.offset == offset && window.sealed && window.available_through == len);
        ensure!(!window.bytes.is_empty() && window.bytes.len() as u64 <= len - offset);
        ensure!(
            generation
                .as_ref()
                .is_none_or(|value| value == &window.generation)
        );
        generation = Some(window.generation);
        bytes.extend(window.bytes);
    }
    Ok(bytes)
}

fn atoms(entries: Vec<ChatEntry>) -> Vec<ChatAtom> {
    entries
        .into_iter()
        .filter_map(|entry| match entry {
            ChatEntry::Atom(atom) if atom.completion_seq.is_some() => Some(*atom),
            _ => None,
        })
        .collect()
}

async fn envelope(reader: &ConversationReader, message: &ChatAtom) -> Result<serde_json::Value> {
    let bytes = match message.payload.as_ref().context("completed payload")? {
        PayloadData::Inline { bytes } => bytes.clone(),
        PayloadData::Deferred {
            reference,
            byte_length,
        } => content(reader, reference, *byte_length).await?,
    };
    let value: serde_json::Value = serde_json::from_slice(&bytes)?;
    ensure!(value["contract"] == "anywork.chat/1");
    Ok(value)
}

async fn history(reader: &ConversationReader, first: ChatBatch) -> Result<Vec<ChatAtom>> {
    let mut messages = atoms(first.entries);
    let mut before = first.before;
    while let Some(cursor) = before {
        let page = reader.load_older(&cursor, demand(7)).await?;
        ensure!(page.placement == ChatPlacement::Prepend && page.current.is_none());
        ensure!(
            page.before.as_ref() != Some(&cursor),
            "opaque continuation did not advance"
        );
        // A byte-limited short page is not EOF; a final empty page is legal.
        before = page.before;
        messages.splice(0..0, atoms(page.entries));
    }
    let ids: HashSet<_> = messages.iter().map(|message| &message.id).collect();
    ensure!(
        ids.len() == messages.len(),
        "history repeated a completed identity"
    );
    Ok(messages)
}

#[tokio::test]
async fn nonempty_feed_keeps_its_open_cut_and_appends_completed_current_in_one_batch() -> Result<()>
{
    let stage = ReplyStage::new();
    let frames = responses_text("second real response", "feed-next", support::MODEL);
    let delta = frames
        .iter()
        .position(|frame| frame["type"] == "response.output_text.delta")
        .context("fixture delta")?;
    let env = Environment::new(
        vec![
            prompt_step(
                "feed-first",
                0,
                text_reply("first real response", "feed-first"),
            ),
            prompt_step(
                "feed-next",
                1,
                stage.gated(frames[..=delta].to_vec(), frames[delta + 1..].to_vec()),
            ),
        ],
        vec![],
    )
    .await?;
    let result = async {
        let thread = env
            .start(ThreadWorkspaceMode::Worktree, "feed-first")
            .await?;
        let id = &thread.thread.id;
        completed_prompt(&env.runtime, id, "feed-first").await?;
        let snapshot = env.runtime.thread_snapshot(id).await?;
        env.runtime
            .submit_prompt_command(
                id.clone(),
                SubmitPromptRequest {
                    input: StudioPromptInput {
                        input_id: "input-feed-next".into(),
                        text: "feed-next".into(),
                        attachment_draft_ids: vec![],
                    },
                    expected_model_route_revision: snapshot
                        .model_route
                        .as_ref()
                        .context("model route")?
                        .revision,
                },
            )
            .await?;
        reached(&stage).await?;
        // The provider barrier proves bytes were sent, not that the product
        // projection consumed them. Observe the real current before opening H0.
        let mut probe = env
            .runtime
            .open_conversation_feed(id, ChatScope::Main, demand(1))
            .await?;
        let ready = async {
            loop {
                let batch = chat(&mut probe).await?;
                if batch.current.as_ref().is_some_and(|current| {
                    current
                        .previews
                        .iter()
                        .any(|preview| preview.role == pl_protocol::CurrentContentRole::Response)
                }) {
                    break Ok(());
                }
            }
        }
        .await;
        finish_feed(&mut probe, ready).await?;
        let mut feed = env
            .runtime
            .open_conversation_feed(id, ChatScope::Main, demand(1))
            .await?;
        let observed = async {
            let reader = feed.reader().clone();
            // Complete production before the first recv: open, not recv, owns H0.
            stage.release();
            completed_prompt(&env.runtime, id, "feed-next").await?;
            let first = chat(&mut feed).await?;
            ensure!(first.placement == ChatPlacement::Set && first.current.is_some());
            ensure!(first.entries.len() <= 1);
            ensure!(first.encoded_len()? <= demand(1).max_bytes as usize);
            let current = first.current.as_ref().context("main current")?;
            let response = current
                .previews
                .iter()
                .find(|preview| preview.role == pl_protocol::CurrentContentRole::Response)
                .context("gated response preview")?
                .reference
                .clone();
            let response_id = match &response.target {
                pl_protocol::ContentTarget::Body {
                    owner: pl_protocol::ContentOwner::Item { item_id },
                    ..
                } => item_id.clone(),
                _ => anyhow::bail!("active response has no stable Item owner"),
            };
            let old = history(&reader, first).await?;
            ensure!(old.iter().all(|atom| {
                atom.source_state
                    .as_ref()
                    .is_some_and(|source| source.source == atom.source)
            }));
            ensure!(
                !old.iter().any(|message| message.id == response_id),
                "Set chased completions after its open cut"
            );
            let mut identities: HashSet<_> = old.iter().map(|message| message.id.clone()).collect();
            let mut saw_response = false;
            loop {
                let batch = chat(&mut feed).await?;
                ensure!(batch.placement == ChatPlacement::Append && batch.before.is_none());
                ensure!(batch.entries.len() <= 1);
                ensure!(batch.encoded_len()? <= demand(1).max_bytes as usize);
                let completed = atoms(batch.entries.clone());
                ensure!(completed.iter().all(|atom| {
                    atom.source_state
                        .as_ref()
                        .is_some_and(|source| source.source == atom.source)
                }));
                let completes_response = completed.iter().any(|message| message.id == response_id);
                for message in &completed {
                    ensure!(
                        identities.insert(message.id.clone()),
                        "completion repeated across Set/Append"
                    );
                }
                if completes_response {
                    let current = batch
                        .current
                        .as_ref()
                        .context("completion must carry retired current in the same batch")?;
                    ensure!(
                        !current
                            .previews
                            .iter()
                            .any(|preview| preview.reference == response),
                        "completed member stayed active"
                    );
                    saw_response = true;
                }
                if batch
                    .current
                    .as_ref()
                    .is_some_and(|current| current.active_turn.is_none())
                {
                    ensure!(
                        saw_response,
                        "current retired before completed response delivery"
                    );
                    break;
                }
            }
            ensure!(!old.is_empty());
            // Closing only the producer must not revoke this original read lease.
            feed.close().await?;
            let bytes = content(&reader, &response, "second real response".len() as u64).await?;
            ensure!(bytes == b"second real response");
            Ok(())
        }
        .await;
        finish_feed(&mut feed, observed).await
    }
    .await;
    stage.release();
    env.finish(result).await
}

#[tokio::test]
async fn reliable_member_is_public_before_attempt_end_or_sqlite_commit() -> Result<()> {
    use sea_orm::{ConnectionTrait, Database, DbBackend, Statement, TransactionTrait};

    let stage = ReplyStage::new();
    let frames = responses_text("independently sealed member", "member", support::MODEL);
    let done = frames
        .iter()
        .position(|frame| frame["type"] == "response.output_item.done")
        .context("fixture independent member completion")?;
    let env = Environment::new(
        vec![
            prompt_step("member-seed", 0, text_reply("durable seed", "seed")),
            prompt_step(
                "member-next",
                1,
                stage.gated(frames[..=done].to_vec(), frames[done + 1..].to_vec()),
            ),
        ],
        vec![],
    )
    .await?;
    let result = async {
        let thread = env.start(ThreadWorkspaceMode::Worktree, "member-seed").await?;
        let id = &thread.thread.id;
        completed_prompt(&env.runtime, id, "member-seed").await?;
        env.runtime.synchronize_thread_observation(id).await?;
        // The saved fixture locates this isolated Thread's DB by identity only;
        // no checkpoint or receipt supplies the public chat text below.
        let saved = support::saved(&env.home, id).await?;
        let db = Database::connect(format!("sqlite://{}?mode=rw", saved.path.display())).await?;
        let transaction = db.begin().await?;
        // An actual SQLite write reservation holds the production writer, not a
        // mocked Session algorithm or a timing-dependent persistence delay.
        transaction.execute_unprepared("UPDATE history_meta SET schema_version=schema_version WHERE id=1").await?;
        let observed = async {
            let mut feed = env.runtime.open_conversation_feed(id, ChatScope::Main, demand(7)).await?;
            let observed = async {
                let first = chat(&mut feed).await?;
                ensure!(first.placement == ChatPlacement::Set);
                let snapshot = env.runtime.thread_snapshot(id).await?;
                env.runtime.submit_prompt_command(id.clone(), SubmitPromptRequest {
                    input: StudioPromptInput { input_id: "input-member-next".into(), text: "member-next".into(), attachment_draft_ids: vec![] },
                    expected_model_route_revision: snapshot.model_route.as_ref().context("model route")?.revision,
                }).await?;
                reached(&stage).await?;
                let completed_id = loop {
                    let batch = chat(&mut feed).await?;
                    ensure!(batch.placement == ChatPlacement::Append && batch.before.is_none());
                    let mut completed = None;
                    for message in &atoms(batch.entries.clone()) {
                        let value = envelope(feed.reader(), message).await?;
                        if value["type"] == "text"
                            && matches!(value["data"]["channel"].as_str(), Some("final" | "commentary"))
                            && value["turnId"] != serde_json::Value::Null {
                            let body = value["bodies"].as_array().context("member bodies")?
                                .first().context("member body")?;
                            let bytes = if let Some(inline) = body.get("inline") {
                                serde_json::from_value::<Vec<u8>>(inline.clone())?
                            } else {
                                content(feed.reader(), &serde_json::from_value(body["reference"].clone())?,
                                    body["byteLength"].as_u64().context("member body length")?).await?
                            };
                            ensure!(bytes == b"independently sealed member");
                            let current = batch.current.as_ref().context("member completion omitted same-batch current")?;
                            ensure!(current.active_turn.is_some(), "member waited for the whole attempt");
                            ensure!(!current.previews.iter().any(|preview| matches!(&preview.reference.target,
                                pl_protocol::ContentTarget::Body { owner: pl_protocol::ContentOwner::Item { item_id }, .. }
                                if item_id == &message.id)), "sealed member stayed active");
                            completed = Some(message.id.clone());
                        }
                    }
                    if let Some(id) = completed { break id; }
                };
                ensure!(transaction.query_one_raw(Statement::from_sql_and_values(
                    DbBackend::Sqlite, "SELECT item_id FROM conversation_items WHERE item_id=?",
                    [completed_id.clone().into()],
                )).await?.is_none(), "member was already durable despite the reserved writer");
                let mut latest = env.runtime.open_conversation_feed(id, ChatScope::Main, demand(1)).await?;
                let queried = async {
                    let set = chat(&mut latest).await?;
                    ensure!(set.placement == ChatPlacement::Set);
                    ensure!(atoms(set.entries.clone()).iter().any(|message| message.id == completed_id),
                        "pending member was pushed but not independently queryable");
                    Ok(())
                }.await;
                finish_feed(&mut latest, queried).await
            }.await;
            finish_feed(&mut feed, observed).await
        }.await;
        let rollback = transaction.rollback().await;
        let close = db.close().await;
        stage.release();
        observed.with_context(|| format!("SQLite cleanup: rollback={rollback:?}, close={close:?}"))?;
        rollback?;
        close?;
        completed_prompt(&env.runtime, id, "member-next").await?;
        Ok(())
    }.await;
    stage.release();
    env.finish(result).await
}

#[tokio::test]
async fn saved_nonempty_feed_requires_a_new_set_after_restart() -> Result<()> {
    let mut env = Environment::new(
        vec![prompt_step(
            "feed-restart",
            0,
            text_reply("a persisted completed response", "feed-restart"),
        )],
        vec![],
    )
    .await?;
    let result = async {
        let thread = env
            .start(ThreadWorkspaceMode::Worktree, "feed-restart")
            .await?;
        let id = &thread.thread.id;
        completed_prompt(&env.runtime, id, "feed-restart").await?;
        let mut feed = env
            .runtime
            .open_conversation_feed(id, ChatScope::Main, demand(1))
            .await?;
        let observed = async {
            let old = chat(&mut feed).await?;
            ensure!(old.placement == ChatPlacement::Set);
            let cursor = old
                .before
                .clone()
                .context("one-item first page must have older facts")?;
            let reader = feed.reader().clone();
            let original = history(&reader, old).await?;
            ensure!(!original.is_empty());
            let mut frozen = Vec::new();
            for message in &original {
                frozen.push((message.id.clone(), envelope(&reader, message).await?));
            }
            env.runtime.synchronize_thread_observation(id).await?;
            env.restart().await?;
            let error = loop {
                match tokio::time::timeout(Duration::from_secs(10), feed.recv()).await? {
                    Err(error) => break error,
                    Ok(Some(ConversationEvent::State { .. })) => (),
                    Ok(Some(ConversationEvent::Chat { batch })) => {
                        ensure!(batch.placement == ChatPlacement::Append)
                    }
                    Ok(None) => anyhow::bail!("old source ended without explicit resync"),
                }
            };
            ensure!(
                error
                    .downcast_ref::<pl_protocol::studio::StudioError>()
                    .and_then(|error| error.reason())
                    == Some("conversationResyncRequired"),
                "{error:#}"
            );
            let stale = reader
                .load_older(&cursor, demand(1))
                .await
                .err()
                .context("old reader survived restart")?;
            ensure!(
                stale
                    .downcast_ref::<pl_protocol::studio::StudioError>()
                    .and_then(|error| error.reason())
                    == Some("conversationResyncRequired"),
                "{stale:#}"
            );
            let mut restored = env
                .runtime
                .open_conversation_feed(id, ChatScope::Main, demand(1))
                .await?;
            let read = async {
                let first = chat(&mut restored).await?;
                ensure!(first.placement == ChatPlacement::Set);
                ensure!(
                    restored
                        .reader()
                        .load_older(&cursor, demand(1))
                        .await
                        .is_err(),
                    "new lease accepted an old opaque continuation"
                );
                let saved = history(restored.reader(), first).await?;
                for (id, original) in &frozen {
                    let saved = saved
                        .iter()
                        .find(|message| &message.id == id)
                        .context("restart lost a published identity")?;
                    ensure!(
                        envelope(restored.reader(), saved).await? == *original,
                        "restart changed frozen payload"
                    );
                }
                Ok(())
            }
            .await;
            finish_feed(&mut restored, read).await
        }
        .await;
        finish_feed(&mut feed, observed).await
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn realistic_output_limit_single_item() -> Result<()> {
    observe_realistic_output_limit(1).await
}

#[tokio::test]
async fn realistic_output_limit_many_items() -> Result<()> {
    observe_realistic_output_limit(2_000).await
}

async fn count_output(
    reader: &ConversationReader,
    messages: &[ChatAtom],
    identities: &mut HashSet<String>,
) -> Result<(usize, u64, Option<String>)> {
    let mut count = 0;
    let mut bytes = 0;
    let mut parent = None;
    for message in messages {
        ensure!(
            identities.insert(message.id.clone()),
            "completed identity repeated"
        );
        let value = envelope(reader, message).await?;
        if value["type"] == "turn" {
            parent = message.turn_id.clone();
        }
        let response_text = value["type"] == "text"
            && matches!(
                value["data"]["channel"].as_str(),
                Some("final" | "commentary")
            );
        if !response_text && value["type"] != "thinking" {
            continue;
        }
        count += 1;
        for body in value["bodies"]
            .as_array()
            .context("text/thinking body manifest")?
        {
            let len = body["byteLength"].as_u64().context("body length")?;
            let raw = if let Some(inline) = body.get("inline") {
                serde_json::from_value::<Vec<u8>>(inline.clone())?
            } else {
                content(
                    reader,
                    &serde_json::from_value(body["reference"].clone())?,
                    len,
                )
                .await?
            };
            ensure!(raw.len() as u64 == len);
            let (parts, remainder) = raw.as_chunks::<2>();
            ensure!(
                remainder.is_empty() && parts.iter().all(|part| part == b" a"),
                "public body differs from provider output"
            );
            bytes += len;
        }
    }
    Ok((count, bytes, parent))
}

async fn observe_realistic_output_limit(item_count: usize) -> Result<()> {
    const OUTPUT_TOKENS: usize = pl_provider_fixture::GUI_STREAMING_OUTPUT_REFERENCE_TOKENS;
    let prompt = format!("realistic-output-{item_count}");
    let env = Environment::new(
        vec![prompt_step(
            &prompt,
            0,
            pl_provider_fixture::gui_streaming_output_reply(item_count, 1),
        )],
        vec![],
    )
    .await?;
    let result = async {
        let thread = env.start(ThreadWorkspaceMode::Worktree, &prompt).await?;
        let mut feed = env.runtime.open_conversation_feed(&thread.thread.id, ChatScope::Main, demand(37)).await?;
        let observed = async {
            let first = chat(&mut feed).await?;
            ensure!(first.placement == ChatPlacement::Set);
            let mut identities = HashSet::new();
            let (mut completed_items, mut body_bytes, initial_parent) = count_output(feed.reader(), &atoms(first.entries.clone()), &mut identities).await?;
            let mut peak_batch = first.encoded_len()?;
            let _terminal = tokio::time::timeout(Duration::from_secs(120), async {
                if let Some(parent) = initial_parent { return Ok(parent); }
                loop {
                    let batch = chat(&mut feed).await?;
                    ensure!(batch.placement == ChatPlacement::Append && batch.before.is_none());
                    peak_batch = peak_batch.max(batch.encoded_len()?);
                    ensure!(peak_batch <= demand(37).max_bytes as usize);
                    let (count, bytes, parent) = count_output(feed.reader(), &atoms(batch.entries.clone()), &mut identities).await?;
                    completed_items += count;
                    body_bytes += bytes;
                    if let Some(parent) = parent { break Ok::<_, anyhow::Error>(parent); }
                }
            }).await.context("paced fixture feed exceeded its observation deadline")??;
            ensure!(completed_items == item_count, "observed {completed_items}/{item_count} independent output members");
            ensure!(body_bytes == (OUTPUT_TOKENS * 2) as u64, "public output body length mismatch: {body_bytes}");
            eprintln!("realistic output: items={item_count}, reference_tokens={OUTPUT_TOKENS}, completed_items={completed_items}, body_bytes={body_bytes}, peak_chat_bytes={peak_batch}");
            Ok(())
        }.await;
        finish_feed(&mut feed, observed).await
    }.await;
    env.finish(result).await
}
