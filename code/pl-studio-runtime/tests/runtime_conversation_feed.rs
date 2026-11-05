#[expect(
    dead_code,
    reason = "shared isolated fixtures also serve other integration test binaries"
)]
mod support;

use anyhow::{Context, Result, ensure};
use pl_protocol::{
    ChatAtom, ChatAtomContent, ChatAtomLifecycle, ChatBatch, ChatEntry, ChatPlacement, ChatScope,
    ContentOwner, ContentRange, ContentRef, ContentTarget, PayloadData, ReadDemand,
    ThreadNotification, ThreadSubscriptionUpdate, ThreadWorkspaceMode, TimelineItem, TurnState,
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
async fn finish_feed<T>(feed: &mut ConversationFeed, result: Result<T>) -> Result<T> {
    let reader = feed.reader().clone();
    feed.request_close();
    reader.request_close();
    let producer = feed.close().await;
    let read = reader.close().await;
    let result =
        result.with_context(|| format!("feed cleanup: producer={producer:?}, read={read:?}"))?;
    producer?;
    read?;
    Ok(result)
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
    let end = reader
        .read_content(
            reference,
            ContentRange {
                offset: len,
                max_bytes: 1,
            },
        )
        .await?;
    ensure!(end.offset == len && end.bytes.is_empty() && end.sealed);
    ensure!(end.available_through == len && generation.as_ref() == Some(&end.generation));
    Ok(bytes)
}

fn items(entries: Vec<ChatEntry>) -> Result<Vec<TimelineItem>> {
    entries
        .into_iter()
        .map(|entry| match entry {
            ChatEntry::Item(item) => Ok(*item),
            _ => anyhow::bail!("Main delivered a raw member/source instead of a Timeline item"),
        })
        .collect()
}

fn atoms(entries: Vec<ChatEntry>) -> Result<Vec<ChatAtom>> {
    let mut atoms = Vec::new();
    for entry in entries {
        match entry {
            ChatEntry::Atom(atom) => {
                ensure!(
                    atom.source_state
                        .as_ref()
                        .is_some_and(|state| state.source == atom.source),
                    "member omitted its real source state"
                );
                atoms.push(*atom);
            }
            ChatEntry::Source(_) => (),
            ChatEntry::Item(_) => anyhow::bail!("member scope delivered a Main item"),
        }
    }
    Ok(atoms)
}

async fn envelope(
    reader: &ConversationReader,
    payload: Option<&PayloadData>,
    owner: &str,
) -> Result<serde_json::Value> {
    let bytes = match payload.context("completed payload")? {
        PayloadData::Inline { bytes } => bytes.clone(),
        PayloadData::Deferred {
            reference,
            byte_length,
        } => {
            ensure!(
                matches!(&reference.target, ContentTarget::ItemPayload { item_id } if item_id == owner),
                "payload reference changed its original completion owner"
            );
            content(reader, reference, *byte_length).await?
        }
    };
    let value: serde_json::Value = serde_json::from_slice(&bytes)?;
    ensure!(value["contract"] == "anywork.chat/1");
    Ok(value)
}

async fn bodies(
    reader: &ConversationReader,
    value: &serde_json::Value,
    contents: &[ChatAtomContent],
    owner: &str,
) -> Result<Vec<Vec<u8>>> {
    let mut bodies = Vec::new();
    for body in value["bodies"].as_array().context("body manifest")? {
        let key = body["key"].as_str().context("body key")?;
        let len = body["byteLength"].as_u64().context("body length")?;
        let reference = &contents
            .iter()
            .find(|content| {
                matches!(&content.reference.target,
                ContentTarget::Body { owner: ContentOwner::Item { item_id }, key: actual }
                    if item_id == owner && actual == key)
            })
            .context("body has no matching original Item-owned content reference")?
            .reference;
        let bytes = content(reader, reference, len).await?;
        if let Some(inline) = body.get("inline") {
            ensure!(serde_json::from_value::<Vec<u8>>(inline.clone())? == bytes);
        } else {
            ensure!(serde_json::from_value::<ContentRef>(body["reference"].clone())? == *reference);
        }
        bodies.push(bytes);
    }
    Ok(bodies)
}

async fn pages(
    reader: &ConversationReader,
    scope: &ChatScope,
    first: ChatBatch,
    read_demand: ReadDemand,
) -> Result<Vec<ChatEntry>> {
    ensure!(first.placement == ChatPlacement::Set);
    first.validate_for(scope)?;
    ensure!(first.entries.len() <= read_demand.max_items as usize);
    ensure!(first.encoded_len()? <= read_demand.max_bytes as usize);
    let mut entries = first.entries;
    let mut before = first.before;
    let mut cursors = HashSet::new();
    while let Some(cursor) = before {
        ensure!(
            cursors.insert(cursor.clone()),
            "opaque continuation repeated"
        );
        let page = reader.load_older(&cursor, read_demand).await?;
        ensure!(page.placement == ChatPlacement::Prepend && page.current.is_none());
        page.validate_for(scope)?;
        ensure!(page.entries.len() <= read_demand.max_items as usize);
        ensure!(page.encoded_len()? <= read_demand.max_bytes as usize);
        ensure!(
            page.before.as_ref() != Some(&cursor),
            "opaque continuation did not advance"
        );
        // A byte-limited short page is not EOF; a final empty page is legal.
        before = page.before;
        entries.splice(0..0, page.entries);
    }
    Ok(entries)
}

async fn history(
    reader: &ConversationReader,
    first: ChatBatch,
    read_demand: ReadDemand,
) -> Result<Vec<TimelineItem>> {
    let messages = items(pages(reader, &ChatScope::Main, first, read_demand).await?)?;
    let ids: HashSet<_> = messages.iter().map(|message| &message.id).collect();
    ensure!(
        ids.len() == messages.len(),
        "history repeated a completed identity"
    );
    ensure!(
        messages
            .windows(2)
            .all(|pair| pair[0].position < pair[1].position),
        "Main history did not preserve item positions"
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
        let seed = completed_prompt(&env.runtime, id, "feed-first").await?;
        ensure!(matches!(seed.state, TurnState::Completed(_)));
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
            let terminal = completed_prompt(&env.runtime, id, "feed-next").await?;
            ensure!(matches!(terminal.state, TurnState::Completed(_)));
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
            let display_id = current
                .items
                .iter()
                .find(|item| {
                    item.contents
                        .iter()
                        .any(|content| content.reference == response)
                })
                .context("current response has no Timeline item")?
                .id
                .clone();
            let old = history(&reader, first, demand(1)).await?;
            ensure!(
                !old.iter().any(|message| {
                    message.id == display_id
                        || message.content_item_id.as_deref() == Some(response_id.as_str())
                }),
                "Set chased completions after its open cut"
            );
            let mut saw_seed = false;
            for item in &old {
                let owner = item
                    .content_item_id
                    .as_deref()
                    .context("old content owner")?;
                let value = envelope(&reader, item.payload.as_ref(), owner).await?;
                if value["turnId"] == seed.id
                    && value["type"] == "text"
                    && matches!(
                        value["data"]["channel"].as_str(),
                        Some("final" | "commentary")
                    )
                {
                    ensure!(
                        bodies(&reader, &value, &item.contents, owner).await?
                            == [b"first real response".to_vec()]
                    );
                    saw_seed = true;
                }
            }
            ensure!(saw_seed, "nonempty Set lost the earlier response");
            let mut identities: HashSet<_> = old.iter().map(|message| message.id.clone()).collect();
            let mut last_position = old.last().and_then(|item| item.position);
            let mut saw_response = false;
            loop {
                let batch = chat(&mut feed).await?;
                batch.validate_for(&ChatScope::Main)?;
                ensure!(batch.placement == ChatPlacement::Append && batch.before.is_none());
                ensure!(batch.entries.len() <= 1);
                ensure!(batch.encoded_len()? <= demand(1).max_bytes as usize);
                let completed = items(batch.entries.clone())?;
                let completes_response = completed.iter().any(|item| item.id == display_id);
                for message in &completed {
                    ensure!(
                        message.position > last_position,
                        "Append changed item order"
                    );
                    last_position = message.position;
                    ensure!(
                        identities.insert(message.id.clone()),
                        "completion repeated across Set/Append"
                    );
                }
                if completes_response {
                    let item = completed
                        .iter()
                        .find(|item| item.id == display_id)
                        .context("completed response item")?;
                    ensure!(item.content_item_id.as_deref() == Some(response_id.as_str()));
                    let value = envelope(&reader, item.payload.as_ref(), &response_id).await?;
                    ensure!(value["turnId"] == terminal.id && value["type"] == "text");
                    ensure!(
                        bodies(&reader, &value, &item.contents, &response_id).await?
                            == [b"second real response".to_vec()]
                    );
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
                    ensure!(
                        !current.items.iter().any(|item| item.id == display_id),
                        "delivered response stayed in current"
                    );
                    saw_response = true;
                }
                if !saw_response && let Some(current) = &batch.current {
                    ensure!(
                        current.items.iter().any(|item| item.id == display_id),
                        "current response retired before its item was delivered"
                    );
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

    let active = ReplyStage::new();
    let sealed = ReplyStage::new();
    let frames = pl_provider_fixture::responses_reasoning_text(
        &["independently sealed reasoning"],
        &["independently sealed member"],
        "member",
        support::MODEL,
    );
    let mut second = frames[1..=3].to_vec();
    // Two actual provider reasoning items share a group. Open only the newer
    // member; its older cursor must keep the first member's pre-completion cut.
    for frame in &mut second {
        frame["output_index"] = 1.into();
        if frame.get("item").is_some() {
            frame["item"]["id"] = "reasoning-2".into();
        } else {
            frame["item_id"] = "reasoning-2".into();
        }
    }
    second[2]["item"]["summary"][0]["id"] = "reasoning-2-part".into();
    let mut text = frames[4..frames.len() - 1].to_vec();
    for frame in &mut text {
        frame["output_index"] = 2.into();
    }
    let mut prefix = frames[..3].to_vec();
    prefix.extend(second[..2].iter().cloned());
    let mut completion = vec![frames[3].clone(), second[2].clone()];
    completion.extend(text);
    let reply = ReplyStage::staged(
        vec![
            prefix,
            completion,
            vec![frames.last().context("fixture terminal")?.clone()],
        ],
        &[&active, &sealed],
    );
    let env = Environment::new(
        vec![
            prompt_step("member-seed", 0, text_reply("durable seed", "seed")),
            prompt_step("member-next", 1, reply),
        ],
        vec![],
    )
    .await?;
    let result = async {
        let thread = env.start(ThreadWorkspaceMode::Worktree, "member-seed").await?;
        let id = &thread.thread.id;
        let seed = completed_prompt(&env.runtime, id, "member-seed").await?;
        ensure!(matches!(seed.state, TurnState::Completed(_)));
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
                reached(&active).await?;
                let reference = loop {
                    let batch = chat(&mut feed).await?;
                    batch.validate_for(&ChatScope::Main)?;
                    ensure!(batch.placement == ChatPlacement::Append && batch.before.is_none());
                    if let Some(group) = batch.current.as_ref().and_then(|current|
                        current.items.iter().find(|item| item.is_work_group()
                            && item.summary.as_ref().is_some_and(|summary|
                                summary.member_count == 2 && summary.active_count == 2))) {
                        break group.members.clone().context("active group reference")?;
                    }
                };
                let scope = ChatScope::GroupMembers { reference };
                let mut members = env.runtime.open_conversation_feed(id, scope.clone(), demand(1)).await?;
                let member_observation = async {
                    let first = chat(&mut members).await?;
                    first.validate_for(&scope)?;
                    ensure!(first.placement == ChatPlacement::Set && first.current.is_none());
                    let cursor = first.before.clone().context("two-member window needs an older cursor")?;
                    let initial = atoms(first.entries)?;
                    ensure!(initial.len() == 1);
                    let initial = &initial[0];
                    ensure!(initial.completion_seq.is_none() && initial.payload.is_none());
                    ensure!(matches!(initial.lifecycle, ChatAtomLifecycle::Active { .. }));
                    active.release();
                    reached(&sealed).await?;
                    let completed = 'completed: loop {
                        let batch = chat(&mut members).await?;
                        batch.validate_for(&scope)?;
                        ensure!(batch.placement == ChatPlacement::Append && batch.current.is_none());
                        ensure!(batch.encoded_len()? <= demand(1).max_bytes as usize);
                        for atom in atoms(batch.entries)? {
                            ensure!(atom.id == initial.id, "member feed escaped its opened window");
                            if atom.completion_seq.is_some() {
                                break 'completed atom;
                            }
                        }
                    };
                    let owner = completed.completion_item_id.as_deref().context("member completion owner")?;
                    let value = envelope(members.reader(), completed.payload.as_ref(), owner).await?;
                    ensure!(value["type"] == "thinking");
                    ensure!(bodies(members.reader(), &value, &completed.contents, owner).await?
                        == [b"independently sealed reasoning".to_vec()]);
                    ensure!(completed.source == initial.source && completed.source_order == initial.source_order);

                    let older = members.reader().load_older(&cursor, demand(1)).await?;
                    older.validate_for(&scope)?;
                    ensure!(older.placement == ChatPlacement::Prepend);
                    let older = atoms(older.entries)?;
                    ensure!(older.len() == 1 && older[0].id != completed.id);
                    ensure!(older[0].source_order < completed.source_order);
                    ensure!(older[0].completion_seq.is_none() && older[0].payload.is_none(),
                        "old GroupMembers cursor borrowed a future completion cut");
                    ensure!(matches!(older[0].lifecycle, ChatAtomLifecycle::Active { .. }));

                    let text_owner = loop {
                        let batch = chat(&mut feed).await?;
                        batch.validate_for(&ChatScope::Main)?;
                        ensure!(batch.placement == ChatPlacement::Append && batch.before.is_none());
                        let mut found = None;
                        for item in items(batch.entries.clone())? {
                            if item.is_work_group() { continue; }
                            let owner = item.content_item_id.as_deref().context("text completion owner")?;
                            let value = envelope(feed.reader(), item.payload.as_ref(), owner).await?;
                            if value["type"] == "text"
                                && matches!(value["data"]["channel"].as_str(), Some("final" | "commentary"))
                            {
                                ensure!(bodies(feed.reader(), &value, &item.contents, owner).await?
                                    == [b"independently sealed member".to_vec()]);
                                let current = batch.current.as_ref().context("text omitted same-batch current")?;
                                ensure!(current.active_turn.is_some(), "member waited for the whole attempt");
                                ensure!(!current.items.iter().any(|current| current.id == item.id));
                                ensure!(!current.previews.iter().any(|preview| matches!(&preview.reference.target,
                                    ContentTarget::Body { owner: ContentOwner::Item { item_id }, .. }
                                        if item_id == owner)), "sealed member stayed active");
                                found = Some(owner.to_owned());
                            }
                        }
                        if let Some(owner) = found { break owner; }
                    };
                    ensure!(!sealed.is_released(), "provider attempt escaped its terminal barrier");
                    let snapshot = env.runtime.thread_snapshot(id).await?;
                    let turn = snapshot.active_turn.context("member waited for the real Turn terminal")?;
                    ensure!(matches!(turn.state, TurnState::Running(_)));
                    ensure!(completed.turn_id.as_deref() == Some(turn.id.as_str()));
                    for owner in [owner, text_owner.as_str()] {
                        ensure!(transaction.query_one_raw(Statement::from_sql_and_values(
                            DbBackend::Sqlite, "SELECT item_id FROM conversation_items WHERE item_id=?",
                            [owner.to_owned().into()],
                        )).await?.is_none(), "member was already durable despite the reserved writer");
                    }
                    let mut latest = env.runtime.open_conversation_feed(id, scope.clone(), demand(1)).await?;
                    let queried = async {
                        let set = chat(&mut latest).await?;
                        let queried = atoms(pages(latest.reader(), &scope, set, demand(1)).await?)?;
                        ensure!(queried.len() == 2 && queried.iter().all(|atom| atom.completion_seq.is_some()),
                            "pending members were pushed but not independently queryable");
                        for atom in queried {
                            let owner = atom.completion_item_id.as_deref().context("queried original owner")?;
                            let queried = envelope(latest.reader(), atom.payload.as_ref(), owner).await?;
                            ensure!(queried["type"] == "thinking");
                            ensure!(bodies(latest.reader(), &queried, &atom.contents, owner).await?
                                == [b"independently sealed reasoning".to_vec()]);
                        }
                        Ok(())
                    }.await;
                    finish_feed(&mut latest, queried).await?;
                    Ok(())
                }.await;
                finish_feed(&mut members, member_observation).await
            }.await;
            finish_feed(&mut feed, observed).await
        }.await;
        let rollback = transaction.rollback().await;
        let close = db.close().await;
        active.release();
        sealed.release();
        observed.with_context(|| format!("SQLite cleanup: rollback={rollback:?}, close={close:?}"))?;
        rollback?;
        close?;
        let terminal = completed_prompt(&env.runtime, id, "member-next").await?;
        ensure!(matches!(terminal.state, TurnState::Completed(_)));
        Ok(())
    }.await;
    active.release();
    sealed.release();
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
        let terminal = completed_prompt(&env.runtime, id, "feed-restart").await?;
        ensure!(matches!(terminal.state, TurnState::Completed(_)));
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
            let original = history(&reader, old, demand(1)).await?;
            ensure!(!original.is_empty());
            let mut frozen = Vec::new();
            for message in &original {
                let owner = message
                    .content_item_id
                    .as_deref()
                    .context("original content owner")?;
                let value = envelope(&reader, message.payload.as_ref(), owner).await?;
                let body = bodies(&reader, &value, &message.contents, owner).await?;
                frozen.push((message.clone(), value, body));
            }
            ensure!(
                frozen
                    .iter()
                    .any(|(_, value, body)| value["turnId"] == terminal.id
                        && body == &[b"a persisted completed response".to_vec()]),
                "saved nonempty feed did not contain the real response body"
            );
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
                let saved = history(restored.reader(), first, demand(1)).await?;
                ensure!(
                    saved.len() == frozen.len(),
                    "restart changed the published item count"
                );
                for (item, original, body) in &frozen {
                    let saved = saved
                        .iter()
                        .find(|message| message.id == item.id)
                        .context("restart lost a published identity")?;
                    ensure!(
                        saved.position == item.position
                            && saved.source == item.source
                            && saved.kind == item.kind
                            && saved.content_item_id == item.content_item_id
                            && saved.contents == item.contents,
                        "restart changed item order, source or original content ownership"
                    );
                    let owner = saved
                        .content_item_id
                        .as_deref()
                        .context("saved content owner")?;
                    let value = envelope(restored.reader(), saved.payload.as_ref(), owner).await?;
                    ensure!(value == *original, "restart changed frozen payload");
                    ensure!(
                        bodies(restored.reader(), &value, &saved.contents, owner).await? == *body,
                        "restart changed original body bytes"
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

async fn count_payload(
    reader: &ConversationReader,
    payload: Option<&PayloadData>,
    owner: &str,
    contents: &[ChatAtomContent],
    identities: &mut HashSet<String>,
    turns: &mut HashSet<String>,
) -> Result<(usize, u64)> {
    ensure!(
        identities.insert(owner.to_owned()),
        "original completion identity repeated"
    );
    let value = envelope(reader, payload, owner).await?;
    let response_text = value["type"] == "text"
        && matches!(
            value["data"]["channel"].as_str(),
            Some("final" | "commentary")
        );
    if !response_text && value["type"] != "thinking" {
        return Ok((0, 0));
    }
    turns.insert(
        value["turnId"]
            .as_str()
            .context("output Turn identity")?
            .to_owned(),
    );
    let bodies = bodies(reader, &value, contents, owner).await?;
    ensure!(
        !bodies.is_empty(),
        "output member omitted its original body"
    );
    let mut bytes = 0;
    for raw in bodies {
        let (parts, remainder) = raw.as_chunks::<2>();
        ensure!(
            remainder.is_empty() && parts.iter().all(|part| part == b" a"),
            "public body differs from provider output"
        );
        bytes += raw.len() as u64;
    }
    Ok((1, bytes))
}

async fn count_output(
    env: &Environment,
    thread_id: &str,
    reader: &ConversationReader,
    messages: &[TimelineItem],
    display_ids: &mut HashSet<String>,
    identities: &mut HashSet<String>,
    turns: &mut HashSet<String>,
) -> Result<(usize, u64)> {
    let mut count = 0;
    let mut bytes = 0;
    for message in messages {
        ensure!(
            display_ids.insert(message.id.clone()),
            "Main repeated a Timeline item"
        );
        let (members, body_bytes) = if message.is_work_group() {
            ensure!(
                message.contents.is_empty()
                    && message.payload.is_none()
                    && message.content_item_id.is_none(),
                "folded WorkGroup copied original content"
            );
            let scope = ChatScope::GroupMembers {
                reference: message
                    .members
                    .clone()
                    .context("completed group reference")?,
            };
            let mut feed = env
                .runtime
                .open_conversation_feed(thread_id, scope.clone(), demand(1))
                .await?;
            let read = async {
                let first = chat(&mut feed).await?;
                let members = atoms(pages(feed.reader(), &scope, first, demand(1)).await?)?;
                ensure!(
                    members.len()
                        == message
                            .summary
                            .as_ref()
                            .context("group summary")?
                            .member_count as usize
                );
                ensure!(
                    members
                        .windows(2)
                        .all(|pair| pair[0].source_order < pair[1].source_order),
                    "member pagination changed real source order"
                );
                let mut ids = HashSet::new();
                let mut sequences = HashSet::new();
                let mut count = 0;
                let mut bytes = 0;
                for atom in members {
                    ensure!(
                        ids.insert(atom.id.clone()),
                        "member pagination repeated an identity"
                    );
                    ensure!(
                        sequences.insert(
                            atom.completion_seq
                                .context("uncompleted historical member")?
                        )
                    );
                    ensure!(atom.source == message.source && atom.turn_id == message.turn_id);
                    ensure!(matches!(atom.lifecycle, ChatAtomLifecycle::Terminal { .. }));
                    let owner = atom
                        .completion_item_id
                        .as_deref()
                        .context("original member owner")?;
                    let (members, body_bytes) = count_payload(
                        feed.reader(),
                        atom.payload.as_ref(),
                        owner,
                        &atom.contents,
                        identities,
                        turns,
                    )
                    .await?;
                    count += members;
                    bytes += body_bytes;
                }
                Ok((count, bytes))
            }
            .await;
            finish_feed(&mut feed, read).await?
        } else {
            let owner = message
                .content_item_id
                .as_deref()
                .context("original Main content owner")?;
            count_payload(
                reader,
                message.payload.as_ref(),
                owner,
                &message.contents,
                identities,
                turns,
            )
            .await?
        };
        count += members;
        bytes += body_bytes;
    }
    Ok((count, bytes))
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
            let mut retired = first.current.as_ref().is_some_and(|current|
                current.active_turn.is_none() && current.items.is_empty());
            let mut peak_batch = first.encoded_len()?;
            let initial_tail = items(first.entries.clone())?;
            let mut last_position = initial_tail.last().and_then(|item| item.position);
            let mut appended = Vec::new();
            let mut display_ids = HashSet::new();
            let mut identities = HashSet::new();
            let mut turns = HashSet::new();
            let mut terminal = None;
            let (completed_items, body_bytes) = tokio::time::timeout(Duration::from_secs(120), async {
                // Accept the list/current facts without waiting for independent member
                // pagination or body reads, as the production Main consumer does.
                while terminal.is_none() || !retired {
                    match next(&mut feed).await? {
                        ConversationEvent::Chat { batch } => {
                            batch.validate_for(&ChatScope::Main)?;
                            ensure!(batch.placement == ChatPlacement::Append && batch.before.is_none());
                            ensure!(batch.entries.len() <= demand(37).max_items as usize);
                            peak_batch = peak_batch.max(batch.encoded_len()?);
                            ensure!(peak_batch <= demand(37).max_bytes as usize);
                            if let Some(current) = &batch.current {
                                retired = current.active_turn.is_none() && current.items.is_empty();
                            }
                            let items = items(batch.entries)?;
                            for item in &items {
                                ensure!(item.position > last_position, "Main Append changed item order");
                                last_position = item.position;
                            }
                            appended.extend(items);
                        }
                        ConversationEvent::State { update } => {
                            if let ThreadSubscriptionUpdate::Notification { notification } = *update
                                && let ThreadNotification::TurnCompleted { turn } = notification.notification
                            {
                                ensure!(turn.input_id.as_deref() == Some(format!("input-{prompt}").as_str()));
                                ensure!(matches!(turn.state, TurnState::Completed(_)),
                                    "real output Turn failed: {:?}", turn.state);
                                terminal = Some(turn.id);
                            }
                        }
                    }
                }
                // Preserve the original Set's paging cut and verify every original
                // member/body after the reliable feed has delivered its final handoff.
                let mut completed = history(feed.reader(), first, demand(37)).await?;
                completed.extend(appended);
                count_output(&env, &thread.thread.id, feed.reader(), &completed,
                    &mut display_ids, &mut identities, &mut turns).await
            }).await.context("paced fixture feed exceeded its observation deadline")??;
            ensure!(turns.len() == 1 && turns.contains(terminal.as_ref().context("typed Turn terminal")?),
                "public output belonged to a different Turn");
            ensure!(completed_items == item_count, "observed {completed_items}/{item_count} independent output members");
            ensure!(body_bytes == (OUTPUT_TOKENS * 2) as u64, "public output body length mismatch: {body_bytes}");
            eprintln!("realistic output: items={item_count}, reference_tokens={OUTPUT_TOKENS}, completed_items={completed_items}, body_bytes={body_bytes}, peak_chat_bytes={peak_batch}");
            Ok(())
        }.await;
        finish_feed(&mut feed, observed).await
    }.await;
    env.finish(result).await
}
