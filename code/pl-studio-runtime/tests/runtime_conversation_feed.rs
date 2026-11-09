#[expect(
    dead_code,
    reason = "shared isolated fixtures also serve other integration test binaries"
)]
mod support;

use anyhow::{Context, Result, ensure};
use pl_protocol::{
    ActivitySnapshot, COMPLETED_READ_INDEX_VERSION, ChatAtomContent, ChatAtomLifecycle, ChatBatch,
    ChatPlacement, ChatScope, ChatSourceId, CompletedEntry, CompletionRunRef, ContentOwner,
    ContentRange, ContentRef, ContentTarget, MainPresentation, PayloadData, ReadDemand,
    ThreadNotification, ThreadSubscriptionUpdate, ThreadWorkspaceMode, TurnState,
    studio::{StudioPromptInput, SubmitPromptRequest},
};
use pl_provider_fixture::{ReplyStage, responses_text};
use pl_studio_runtime::{
    ConversationEvent as ContentEvent, ConversationFeed as ContentFeed, ConversationReader,
    ConversationStateFeed, StudioRuntime,
};

// This test-only multiplexer observes both production owners. It does not impose
// ordering between State and content; each assertion checks its own stream's prefix.
enum Observation {
    Chat {
        batch: Box<ChatBatch>,
    },
    Activity {
        snapshot: std::sync::Arc<ActivitySnapshot>,
    },
    State {
        update: Box<ThreadSubscriptionUpdate>,
    },
}
struct ObservedFeed {
    content: ContentFeed,
    state: ConversationStateFeed,
}
impl std::ops::Deref for ObservedFeed {
    type Target = ContentFeed;
    fn deref(&self) -> &ContentFeed {
        &self.content
    }
}
impl ObservedFeed {
    async fn recv(&mut self) -> Result<Option<Observation>> {
        tokio::select! {
            biased;
            state = self.state.recv() => state.map(|update| update.map(|update| Observation::State { update: Box::new(update) })),
            content = self.content.recv() => content.map(|event| event.map(|event| match event {
                ContentEvent::Chat { batch } => Observation::Chat { batch },
                ContentEvent::Activity { snapshot } => Observation::Activity { snapshot },
            })),
        }
    }
    fn request_close(&self) {
        self.content.request_close();
        self.state.request_close();
    }
    async fn close(&mut self) -> Result<()> {
        let state = self.state.close().await;
        let content = self.content.close().await;
        state?;
        content
    }
}
trait ObserveConversation {
    fn open_observed_feed(
        &self,
        id: &str,
        scope: ChatScope,
        demand: ReadDemand,
    ) -> impl std::future::Future<Output = Result<ObservedFeed>> + Send;
}
impl ObserveConversation for StudioRuntime {
    async fn open_observed_feed(
        &self,
        id: &str,
        scope: ChatScope,
        demand: ReadDemand,
    ) -> Result<ObservedFeed> {
        let mut state = self.open_conversation_state_feed(id).await?;
        match self.open_conversation_feed(id, scope, demand).await {
            Ok(content) => Ok(ObservedFeed { content, state }),
            Err(error) => {
                state.close().await?;
                Err(error)
            }
        }
    }
}
use std::{collections::HashSet, time::Duration};
use support::{Environment, completed_prompt, prompt_step, reached, text_reply};

fn demand(max_items: u32) -> ReadDemand {
    ReadDemand {
        max_items,
        max_bytes: 256 * 1024,
    }
}

async fn next(feed: &mut ObservedFeed) -> Result<Observation> {
    let event = tokio::time::timeout(Duration::from_secs(10), feed.recv())
        .await
        .context("conversation feed did not deliver its pending facts")??
        .context("conversation feed ended before its pending facts")?;
    if let Observation::State { update } = &event
        && let ThreadSubscriptionUpdate::Snapshot {
            completed_history_version,
            snapshot,
        } = update.as_ref()
    {
        ensure!(*completed_history_version == 1 && snapshot.schema_version == 17);
        if !snapshot.interactions.is_empty() {
            ensure!(
                snapshot.business_refs.interactions.is_some(),
                "real pending interactions omitted their business read reference"
            );
        }
        if snapshot
            .runtime
            .as_ref()
            .is_some_and(|runtime| runtime.plan.is_some())
        {
            ensure!(
                snapshot.business_refs.plan.is_some(),
                "real Plan omitted its business read head"
            );
        }
    }
    Ok(event)
}

async fn chat(feed: &mut ObservedFeed) -> Result<ChatBatch> {
    loop {
        if let Observation::Chat { batch } = next(feed).await? {
            return Ok(*batch);
        }
    }
}

// Close both independent owners even if the observation or one close failed.
async fn finish_feed<T>(feed: &mut ObservedFeed, result: Result<T>) -> Result<T> {
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

fn items(entries: Vec<CompletedEntry>) -> Result<Vec<CompletedEntry>> {
    for entry in &entries {
        ensure!(entry.atom.completion_item_id.as_deref() == Some(entry.record_id.as_str()));
        ensure!(entry.atom.completion_seq == Some(entry.completion_seq));
        ensure!(matches!(
            entry.atom.lifecycle,
            ChatAtomLifecycle::Terminal { .. }
        ));
        ensure!(entry.run.is_some() && entry.main_presentation != MainPresentation::Hidden);
        if matches!(
            entry.main_presentation,
            MainPresentation::ForegroundWork | MainPresentation::BackgroundResults
        ) {
            ensure!(
                matches!(entry.atom.payload, Some(PayloadData::Deferred { .. })),
                "Main work representative read or inlined its member body"
            );
        }
    }
    Ok(entries)
}

async fn payload_bytes(
    reader: &ConversationReader,
    payload: Option<&PayloadData>,
    owner: &str,
) -> Result<Vec<u8>> {
    match payload.context("completed payload")? {
        PayloadData::Inline { bytes } => Ok(bytes.clone()),
        PayloadData::Deferred {
            reference,
            byte_length,
        } => {
            ensure!(
                matches!(&reference.target, ContentTarget::ItemPayload { item_id } if item_id == owner),
                "payload reference changed its original completion owner"
            );
            content(reader, reference, *byte_length).await
        }
    }
}

async fn envelope(
    reader: &ConversationReader,
    payload: Option<&PayloadData>,
    owner: &str,
) -> Result<serde_json::Value> {
    let bytes = payload_bytes(reader, payload, owner).await?;
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
    let mut manifest = Vec::new();
    let mut manifest_loaded = false;
    for body in value["bodies"].as_array().context("body manifest")? {
        let key = body["key"].as_str().context("body key")?;
        let len = body["byteLength"].as_u64().context("body length")?;
        let header_reference = contents
            .iter()
            .find(|content| {
                matches!(&content.reference.target,
                ContentTarget::Body { owner: ContentOwner::Item { item_id }, key: actual }
                    if item_id == owner && actual == key)
            })
            .map(|content| &content.reference);
        // Atom contents is a role-selected lightweight header. Accepted input
        // also retains its original opaque payload in the canonical manifest.
        if header_reference.is_none() && !manifest_loaded {
            let mut continuation = None;
            let mut seen = HashSet::new();
            loop {
                let page = reader
                    .list_contents(owner, continuation.as_deref(), demand(16))
                    .await?;
                manifest.extend(page.entries);
                continuation = page.continuation;
                let Some(cursor) = &continuation else {
                    break;
                };
                ensure!(
                    seen.insert(cursor.clone()),
                    "manifest continuation repeated"
                );
            }
            manifest_loaded = true;
        }
        let reference = header_reference
            .or_else(|| {
                manifest
                    .iter()
                    .find(|entry| {
                        matches!(&entry.reference.target,
                ContentTarget::Body { owner: ContentOwner::Item { item_id }, key: actual }
                    if item_id == owner && actual == key)
                    })
                    .map(|entry| &entry.reference)
            })
            .with_context(|| format!("body {key} has no original Item-owned manifest reference"))?;
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

async fn accepted_input(
    reader: &ConversationReader,
    entries: &[CompletedEntry],
    input_id: &str,
    text: &str,
) -> Result<(CompletedEntry, Vec<u8>)> {
    let inputs = entries.iter().filter(|entry|
        matches!(&entry.atom.source, ChatSourceId::Input { input_id: actual } if actual == input_id))
        .collect::<Vec<_>>();
    ensure!(
        inputs.len() == 1,
        "accepted input {input_id} was missing or published more than once"
    );
    let input = inputs[0];
    ensure!(input.record_id == input_id && input.main_presentation == MainPresentation::Single);
    ensure!(input.atom.completion_item_id.as_deref() == Some(input_id));
    ensure!(input.atom.completion_seq == Some(input.completion_seq));
    let bytes = payload_bytes(reader, input.atom.payload.as_ref(), input_id).await?;
    let value: serde_json::Value = serde_json::from_slice(&bytes)?;
    let body_bytes = bodies(reader, &value, &input.atom.contents, input_id).await?;
    let text_index = value["bodies"]
        .as_array()
        .context("input body manifest")?
        .iter()
        .position(|body| body["key"] == "body")
        .context("accepted visible text body")?;
    ensure!(body_bytes[text_index] == text.as_bytes());
    let original: ContentRef =
        serde_json::from_value(value["data"]["acceptedPayload"]["reference"].clone())?;
    ensure!(
        matches!(&original.target, ContentTarget::Body {
        owner: ContentOwner::Item { item_id }, .. } if item_id == input_id),
        "accepted opaque payload changed its original input owner"
    );
    Ok((input.clone(), bytes))
}

async fn pages(
    reader: &ConversationReader,
    scope: &ChatScope,
    first: ChatBatch,
    read_demand: ReadDemand,
) -> Result<Vec<CompletedEntry>> {
    ensure!(first.placement == ChatPlacement::Set);
    first.validate_for(scope)?;
    ensure!(first.entries.len() <= read_demand.max_items as usize);
    ensure!(first.encoded_len()? <= read_demand.max_bytes as usize);
    let mut entries = first.entries;
    let ceiling = first.through_seq;
    let mut before = first.before;
    let mut cursors = HashSet::new();
    while let Some(cursor) = before {
        ensure!(
            cursors.insert(cursor.clone()),
            "opaque continuation repeated"
        );
        let page = reader.load_older(&cursor, read_demand).await?;
        ensure!(page.placement == ChatPlacement::Prepend && page.from_seq.is_none());
        ensure!(
            page.through_seq == ceiling,
            "old page borrowed a future completion cut"
        );
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
    env: &Environment,
    thread_id: &str,
    reader: &ConversationReader,
    first: ChatBatch,
    read_demand: ReadDemand,
) -> Result<Vec<CompletedEntry>> {
    let heads = items(pages(reader, &ChatScope::Main, first, read_demand).await?)?;
    let mut messages = Vec::new();
    for head in heads {
        let run = head.run.context("Main run position")?;
        if head.main_presentation == MainPresentation::Single {
            messages.push(head);
            continue;
        }
        let PayloadData::Deferred { reference, .. } =
            head.atom.payload.as_ref().context("work payload")?
        else {
            anyhow::bail!("Main work must remain deferred");
        };
        let scope = ChatScope::Run {
            reference: CompletionRunRef {
                database_id: reference.database_id.clone(),
                index_version: COMPLETED_READ_INDEX_VERSION,
                start_seq: run.start_seq,
            },
        };
        let mut feed = env
            .runtime
            .open_observed_feed(thread_id, scope.clone(), read_demand)
            .await?;
        let read = async {
            let first = chat(&mut feed).await?;
            // A separately opened Run may already include newer completions. The
            // Main representative's immutable seq/ordinal defines this inventory.
            let members = pages(feed.reader(), &scope, first, read_demand)
                .await?
                .into_iter()
                .filter(|entry| entry.completion_seq <= head.completion_seq)
                .collect::<Vec<_>>();
            ensure!(members.len() as u64 == run.ordinal);
            for (index, member) in members.iter().enumerate() {
                ensure!(
                    member
                        .run
                        .is_some_and(|position| position.start_seq == run.start_seq
                            && position.ordinal == index as u64 + 1)
                );
            }
            Ok(members)
        }
        .await;
        messages.extend(finish_feed(&mut feed, read).await?);
    }
    let ids: HashSet<_> = messages.iter().map(|message| &message.record_id).collect();
    ensure!(
        ids.len() == messages.len(),
        "history repeated a completed identity"
    );
    ensure!(
        messages
            .windows(2)
            .all(|pair| pair[0].completion_seq < pair[1].completion_seq),
        "history did not preserve completion order"
    );
    Ok(messages)
}

#[tokio::test]
async fn websocket_burst_keeps_reliable_members_and_bodies_through_restart() -> Result<()> {
    observe_reliable_websocket_output(false).await
}

#[tokio::test]
async fn websocket_reconnect_keeps_admitted_members_and_bodies_through_restart() -> Result<()> {
    observe_reliable_websocket_output(true).await
}

async fn observe_reliable_websocket_output(reconnect: bool) -> Result<()> {
    use pl_model::model::ModelTransportProfile;
    use pl_provider_fixture::{Protocol, Reply, Step, WebSocketAction};
    use tokio_util::sync::CancellationToken;

    let reached = CancellationToken::new();
    let release = CancellationToken::new();
    let frames = pl_provider_fixture::responses_reasoning_text(
        &[" a"],
        &[" a"; 96],
        "burst",
        support::MODEL,
    );
    let mut actions = frames[..4]
        .iter()
        .cloned()
        .map(WebSocketAction::Event)
        .collect::<Vec<_>>();
    actions.push(WebSocketAction::Barrier {
        reached: reached.clone(),
        release: release.clone(),
    });
    if reconnect {
        actions.push(WebSocketAction::Event(serde_json::json!({
            "type":"error","status":400,"error":{
                "code":"websocket_connection_limit_reached",
                "message":"Responses websocket connection limit reached (60 minutes). Create a new websocket connection to continue."
            }
        })));
    } else {
        actions.extend(frames[4..].iter().cloned().map(WebSocketAction::Event));
    }
    let mut steps = vec![Step::prompt(
        Protocol::ResponsesWebSocket,
        "burst",
        0,
        Reply::WebSocketScript(actions),
    )];
    if reconnect {
        // Reuse the same provider item IDs. The observation generation, not a new
        // display-only ID or deletion of old output, must isolate the two attempts.
        steps.push(Step::prompt(
            Protocol::ResponsesWebSocket,
            "burst",
            1,
            Reply::WebSocket(frames),
        ));
    }
    let expected_members = if reconnect { 3 } else { 2 };
    let expected_bytes = if reconnect { 196 } else { 194 };
    let mut env =
        Environment::with_transport(steps, vec![], ModelTransportProfile::responses_websocket())
            .await?;
    let result = async {
        let thread = env.start(ThreadWorkspaceMode::Worktree, "burst").await?;
        let id = thread.thread.id;
        let mut feed = env
            .runtime
            .open_observed_feed(&id, ChatScope::Main, demand(7))
            .await?;
        let observed = async {
            let first = chat(&mut feed).await?;
            ensure!(first.placement == ChatPlacement::Set);
            tokio::time::timeout(support::integration_test_deadline()?, reached.cancelled())
                .await?;
            let mut through = first.through_seq;
            let mut appended = Vec::new();
            // The canonical first part must already be published while the
            // provider is held before its remaining burst/reconnect.
            let initial = history(&env, &id, feed.reader(), first.clone(), demand(7)).await?;
            while !initial
                .iter()
                .chain(&appended)
                .any(|entry| entry.atom.kind == pl_protocol::ChatAtomKind::Reasoning)
            {
                let batch = chat(&mut feed).await?;
                batch.validate_for(&ChatScope::Main)?;
                ensure!(batch.from_seq == Some(through));
                through = batch.through_seq;
                appended.extend(items(batch.entries)?);
            }
            release.cancel();
            let mut terminal = None;
            let mut retired = false;
            while terminal.is_none() || !retired {
                match next(&mut feed).await? {
                    Observation::Chat { batch } => {
                        batch.validate_for(&ChatScope::Main)?;
                        ensure!(batch.placement == ChatPlacement::Append);
                        ensure!(batch.from_seq == Some(through));
                        through = batch.through_seq;
                        appended.extend(items(batch.entries)?);
                    }
                    Observation::Activity { snapshot } => {
                        ensure!(snapshot.completed_through == through);
                        retired = snapshot.entries.is_empty();
                    }
                    Observation::State { update } => {
                        if let ThreadSubscriptionUpdate::Notification { notification } = *update
                            && let ThreadNotification::TurnCompleted { turn } =
                                notification.notification
                        {
                            ensure!(
                                matches!(turn.state, TurnState::Completed(_)),
                                "burst Turn failed: {:?}",
                                turn.state
                            );
                            terminal = Some(turn.id);
                        }
                    }
                }
            }
            let mut published = history(&env, &id, feed.reader(), first, demand(7)).await?;
            published.extend(appended);
            let (members, bytes) = websocket_output(feed.reader(), &published, reconnect).await?;
            ensure!(
                members == expected_members && bytes == expected_bytes,
                "burst lost or duplicated original output: {members} members, {bytes} bytes"
            );
            Ok(published
                .into_iter()
                .map(|item| item.record_id)
                .collect::<Vec<_>>())
        }
        .await;
        let identities = finish_feed(&mut feed, observed).await?;
        let recorded = env.root_provider.recorded();
        ensure!(recorded.len() == if reconnect { 2 } else { 1 });
        ensure!(
            recorded
                .iter()
                .all(|request| request.accepted && request.method == "WS")
        );
        if reconnect {
            ensure!(recorded[1].body.get("previous_response_id").is_none());
            ensure!(recorded[0].body["input"] == recorded[1].body["input"]);
        }
        env.restart().await?;
        let mut reopened = env
            .runtime
            .open_observed_feed(&id, ChatScope::Main, demand(7))
            .await?;
        let read = async {
            let first = chat(&mut reopened).await?;
            let published = history(&env, &id, reopened.reader(), first, demand(7)).await?;
            ensure!(
                published
                    .iter()
                    .map(|item| &item.record_id)
                    .eq(identities.iter()),
                "restart changed completion identities/order"
            );
            let (members, bytes) =
                websocket_output(reopened.reader(), &published, reconnect).await?;
            ensure!(members == expected_members && bytes == expected_bytes);
            Ok(())
        }
        .await;
        finish_feed(&mut reopened, read).await?;
        ensure!(
            env.root_provider.recorded().len() == recorded.len(),
            "cold read activated the provider"
        );
        Ok(())
    }
    .await;
    release.cancel();
    env.finish(result).await
}

async fn websocket_output(
    reader: &ConversationReader,
    messages: &[CompletedEntry],
    reconnect: bool,
) -> Result<(usize, u64)> {
    let mut output = Vec::new();
    let mut notices = HashSet::new();
    for message in messages {
        let owner = message.record_id.as_str();
        let notice = if owner.ends_with(":recovery:retry:1") {
            Some("连接中断，正在重试（1/5）。")
        } else if owner.ends_with(":recovery:result") {
            Some("连接已恢复，继续执行。")
        } else {
            None
        };
        if let Some(notice) = notice {
            ensure!(
                reconnect && notices.insert(notice),
                "unexpected or repeated recovery notice"
            );
            let value = envelope(reader, message.atom.payload.as_ref(), owner).await?;
            ensure!(value["type"] == "text" && value["data"]["channel"] == "commentary");
            ensure!(
                bodies(reader, &value, &message.atom.contents, owner).await? == [notice.as_bytes()]
            );
        } else {
            output.push(message.clone());
        }
    }
    ensure!(notices.len() == if reconnect { 2 } else { 0 });
    count_output(
        reader,
        &output,
        &mut HashSet::new(),
        &mut HashSet::new(),
        &mut HashSet::new(),
    )
    .await
}

#[tokio::test]
async fn nonempty_feed_keeps_its_open_cut_and_delivers_activity_after_completions() -> Result<()> {
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
        let mut probe = env
            .runtime
            .open_observed_feed(id, ChatScope::Main, demand(1))
            .await?;
        let ready = async {
            loop {
                if let Observation::Activity { snapshot } = next(&mut probe).await?
                    && let Some(target) = live_body_target(&snapshot)?
                {
                    let input = probe
                        .reader()
                        .read_completed("input-feed-next", demand(1))
                        .await?;
                    let (input, bytes) = accepted_input(
                        probe.reader(),
                        std::slice::from_ref(&input),
                        "input-feed-next",
                        "feed-next",
                    )
                    .await?;
                    break Ok((target, input, bytes));
                }
            }
        }
        .await;
        let (target, accepted, accepted_bytes) = finish_feed(&mut probe, ready).await?;
        let mut feed = env
            .runtime
            .open_observed_feed(id, ChatScope::Main, demand(1))
            .await?;
        let observed = async {
            let reader = feed.reader().clone();
            // open, rather than recv, must capture H0 and its activity.
            stage.release();
            let terminal = completed_prompt(&env.runtime, id, "feed-next").await?;
            ensure!(matches!(terminal.state, TurnState::Completed(_)));
            let first = chat(&mut feed).await?;
            let mut through = first.through_seq;
            ensure!(first.placement == ChatPlacement::Set && first.from_seq.is_none());
            let old = history(&env, id, &reader, first, demand(1)).await?;
            ensure!(
                !old.iter().any(|entry| entry.record_id == target.record_id),
                "Set chased a future completion"
            );
            let (input, bytes) =
                accepted_input(&reader, &old, "input-feed-next", "feed-next").await?;
            ensure!(input.completion_seq == accepted.completion_seq && input.run == accepted.run);
            ensure!(
                bytes == accepted_bytes,
                "input transition changed its frozen bytes"
            );
            let mut saw_seed = false;
            for entry in &old {
                let value =
                    envelope(&reader, entry.atom.payload.as_ref(), &entry.record_id).await?;
                if value["turnId"] == seed.id
                    && value["type"] == "text"
                    && matches!(
                        value["data"]["channel"].as_str(),
                        Some("final" | "commentary")
                    )
                {
                    ensure!(
                        bodies(&reader, &value, &entry.atom.contents, &entry.record_id).await?
                            == [b"first real response".to_vec()]
                    );
                    saw_seed = true;
                }
            }
            ensure!(saw_seed);
            let mut identities: HashSet<_> =
                old.iter().map(|entry| entry.record_id.clone()).collect();
            let mut saw_response = false;
            let mut revision = 0;
            loop {
                match next(&mut feed).await? {
                    Observation::Chat { batch } => {
                        batch.validate_for(&ChatScope::Main)?;
                        ensure!(
                            batch.placement == ChatPlacement::Append
                                && batch.from_seq == Some(through)
                        );
                        ensure!(
                            batch.entries.len() <= 1
                                && batch.encoded_len()? <= demand(1).max_bytes as usize
                        );
                        through = batch.through_seq;
                        for entry in items(batch.entries)? {
                            ensure!(identities.insert(entry.record_id.clone()));
                            if entry.record_id == target.record_id {
                                let value = envelope(
                                    &reader,
                                    entry.atom.payload.as_ref(),
                                    &entry.record_id,
                                )
                                .await?;
                                ensure!(value["turnId"] == terminal.id && value["type"] == "text");
                                ensure!(
                                    bodies(&reader, &value, &entry.atom.contents, &entry.record_id)
                                        .await?
                                        == [b"second real response".to_vec()]
                                );
                                saw_response = true;
                            }
                        }
                    }
                    Observation::Activity { snapshot } => {
                        ensure!(
                            snapshot.completed_through == through && snapshot.revision >= revision
                        );
                        revision = snapshot.revision;
                        if saw_response {
                            ensure!(
                                !snapshot.entries.iter().any(|entry| entry
                                    .atom
                                    .contents
                                    .iter()
                                    .any(|content| content.reference == target.reference)),
                                "completed activity resurrected"
                            );
                        }
                        // A resident owner can be idle. Only retire this
                        // observed response after accepting its completed entry.
                        if snapshot.entries.is_empty() && saw_response {
                            break;
                        }
                    }
                    Observation::State { .. } => {}
                }
            }
            feed.close().await?;
            let input = reader.read_completed("input-feed-next", demand(1)).await?;
            ensure!(input.completion_seq == accepted.completion_seq && input.run == accepted.run);
            ensure!(
                payload_bytes(&reader, input.atom.payload.as_ref(), &input.record_id).await?
                    == accepted_bytes,
                "Turn completion re-sealed the accepted input"
            );
            ensure!(
                content(
                    &reader,
                    &target.reference,
                    "second real response".len() as u64
                )
                .await?
                    == b"second real response"
            );
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
        let thread = env
            .start(ThreadWorkspaceMode::Worktree, "member-seed")
            .await?;
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
        transaction
            .execute_unprepared("UPDATE history_meta SET schema_version=schema_version WHERE id=1")
            .await?;
        let observed = async {
            let mut feed = env
                .runtime
                .open_observed_feed(id, ChatScope::Main, demand(7))
                .await?;
            let observed = async {
                let first = chat(&mut feed).await?;
                ensure!(first.placement == ChatPlacement::Set);
                let snapshot = env.runtime.thread_snapshot(id).await?;
                env.runtime
                    .submit_prompt_command(
                        id.clone(),
                        SubmitPromptRequest {
                            input: StudioPromptInput {
                                input_id: "input-member-next".into(),
                                text: "member-next".into(),
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
                reached(&active).await?;
                let mut through = first.through_seq;
                loop {
                    match next(&mut feed).await? {
                        Observation::Chat { batch } => {
                            batch.validate_for(&ChatScope::Main)?;
                            ensure!(batch.from_seq == Some(through));
                            through = batch.through_seq;
                        }
                        Observation::Activity { snapshot } => {
                            ensure!(snapshot.completed_through == through);
                            if snapshot
                                .entries
                                .iter()
                                .filter(|entry| {
                                    entry.atom.kind == pl_protocol::ChatAtomKind::Reasoning
                                })
                                .count()
                                == 2
                            {
                                break;
                            }
                        }
                        Observation::State { .. } => {}
                    }
                }
                active.release();
                reached(&sealed).await?;
                let mut reasoning = Vec::new();
                let mut text_owner = None;
                while reasoning.len() < 2 || text_owner.is_none() {
                    match next(&mut feed).await? {
                        Observation::Chat { batch } => {
                            batch.validate_for(&ChatScope::Main)?;
                            ensure!(
                                batch.placement == ChatPlacement::Append
                                    && batch.from_seq == Some(through)
                            );
                            through = batch.through_seq;
                            for entry in items(batch.entries)? {
                                if entry.atom.kind == pl_protocol::ChatAtomKind::Reasoning {
                                    reasoning.push(entry);
                                } else if entry.atom.kind == pl_protocol::ChatAtomKind::Text {
                                    let value = envelope(
                                        feed.reader(),
                                        entry.atom.payload.as_ref(),
                                        &entry.record_id,
                                    )
                                    .await?;
                                    if matches!(
                                        value["data"]["channel"].as_str(),
                                        Some("final" | "commentary")
                                    ) {
                                        ensure!(
                                            bodies(
                                                feed.reader(),
                                                &value,
                                                &entry.atom.contents,
                                                &entry.record_id
                                            )
                                            .await?
                                                == [b"independently sealed member".to_vec()]
                                        );
                                        text_owner = Some(entry.record_id);
                                    }
                                }
                            }
                        }
                        Observation::Activity { snapshot } => {
                            ensure!(snapshot.completed_through == through);
                            ensure!(
                                snapshot.execution_present,
                                "completion waited for attempt terminal"
                            );
                        }
                        Observation::State { .. } => {}
                    }
                }
                ensure!(!sealed.is_released());
                let snapshot = env.runtime.thread_snapshot(id).await?;
                let turn = snapshot.active_turn.context("real Turn still running")?;
                ensure!(matches!(turn.state, TurnState::Running(_)));
                let run = reasoning[0].run.context("first reasoning run")?;
                ensure!(
                    run.ordinal == 1
                        && reasoning[1]
                            .run
                            .is_some_and(|position| position.start_seq == run.start_seq
                                && position.ordinal == 2)
                );
                let PayloadData::Deferred { reference, .. } = reasoning[0]
                    .atom
                    .payload
                    .as_ref()
                    .context("deferred Main work")?
                else {
                    anyhow::bail!("Main inlined reasoning");
                };
                let scope = ChatScope::Run {
                    reference: CompletionRunRef {
                        database_id: reference.database_id.clone(),
                        index_version: COMPLETED_READ_INDEX_VERSION,
                        start_seq: run.start_seq,
                    },
                };
                let mut members = env
                    .runtime
                    .open_observed_feed(id, scope.clone(), demand(1))
                    .await?;
                let read = async {
                    let set = chat(&mut members).await?;
                    let queried = pages(members.reader(), &scope, set, demand(1)).await?;
                    ensure!(queried.len() == 2);
                    ensure!(
                        queried
                            .iter()
                            .map(|entry| &entry.record_id)
                            .eq(reasoning.iter().map(|entry| &entry.record_id))
                    );
                    for entry in &queried {
                        let point = members
                            .reader()
                            .read_completed(&entry.record_id, demand(1))
                            .await?;
                        ensure!(
                            point.completion_seq == entry.completion_seq && point.run == entry.run
                        );
                        let value = envelope(
                            members.reader(),
                            point.atom.payload.as_ref(),
                            &entry.record_id,
                        )
                        .await?;
                        ensure!(value["type"] == "thinking");
                        ensure!(
                            bodies(
                                members.reader(),
                                &value,
                                &point.atom.contents,
                                &entry.record_id
                            )
                            .await?
                                == [b"independently sealed reasoning".to_vec()]
                        );
                    }
                    Ok(())
                }
                .await;
                finish_feed(&mut members, read).await?;
                for owner in reasoning
                    .iter()
                    .map(|entry| entry.record_id.as_str())
                    .chain(text_owner.as_deref())
                {
                    ensure!(
                        transaction
                            .query_one_raw(Statement::from_sql_and_values(
                                DbBackend::Sqlite,
                                "SELECT item_id FROM conversation_items WHERE item_id=?",
                                [owner.to_owned().into()]
                            ))
                            .await?
                            .is_none(),
                        "completion was durable despite reserved writer"
                    );
                }
                Ok(())
            }
            .await;
            finish_feed(&mut feed, observed).await
        }
        .await;
        let rollback = transaction.rollback().await;
        let close = db.close().await;
        active.release();
        sealed.release();
        observed
            .with_context(|| format!("SQLite cleanup: rollback={rollback:?}, close={close:?}"))?;
        rollback?;
        close?;
        let terminal = completed_prompt(&env.runtime, id, "member-next").await?;
        ensure!(matches!(terminal.state, TurnState::Completed(_)));
        Ok(())
    }
    .await;
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
            .open_observed_feed(id, ChatScope::Main, demand(1))
            .await?;
        let observed = async {
            let old = chat(&mut feed).await?;
            ensure!(old.placement == ChatPlacement::Set);
            let cursor = old
                .before
                .clone()
                .context("one-item first page must have older facts")?;
            let reader = feed.reader().clone();
            let original = history(&env, id, &reader, old, demand(1)).await?;
            ensure!(!original.is_empty());
            let (original_input, input_bytes) =
                accepted_input(&reader, &original, "input-feed-restart", "feed-restart").await?;
            let mut frozen = Vec::new();
            for message in &original {
                let owner = message.record_id.as_str();
                let value = envelope(&reader, message.atom.payload.as_ref(), owner).await?;
                let body = bodies(&reader, &value, &message.atom.contents, owner).await?;
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
                    Ok(Some(Observation::State { .. } | Observation::Activity { .. })) => (),
                    Ok(Some(Observation::Chat { batch })) => {
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
                .open_observed_feed(id, ChatScope::Main, demand(1))
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
                let saved = history(&env, id, restored.reader(), first, demand(1)).await?;
                let (input, bytes) = accepted_input(
                    restored.reader(),
                    &saved,
                    "input-feed-restart",
                    "feed-restart",
                )
                .await?;
                ensure!(
                    input.completion_seq == original_input.completion_seq
                        && input.run == original_input.run
                );
                ensure!(
                    bytes == input_bytes,
                    "restart re-sealed or changed the accepted input"
                );
                ensure!(
                    saved.len() == frozen.len(),
                    "restart changed the published item count"
                );
                for (item, original, body) in &frozen {
                    let saved = saved
                        .iter()
                        .find(|message| message.record_id == item.record_id)
                        .context("restart lost a published identity")?;
                    ensure!(
                        saved.completion_seq == item.completion_seq
                            && saved.run == item.run
                            && saved.main_presentation == item.main_presentation
                            && saved.atom.source == item.atom.source
                            && saved.atom.kind == item.atom.kind
                            && saved.atom.contents == item.atom.contents,
                        "restart changed item order, source or original content ownership"
                    );
                    let owner = saved.record_id.as_str();
                    let value =
                        envelope(restored.reader(), saved.atom.payload.as_ref(), owner).await?;
                    ensure!(value == *original, "restart changed frozen payload");
                    ensure!(
                        bodies(restored.reader(), &value, &saved.atom.contents, owner).await?
                            == *body,
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
    reader: &ConversationReader,
    messages: &[CompletedEntry],
    display_ids: &mut HashSet<String>,
    identities: &mut HashSet<String>,
    turns: &mut HashSet<String>,
) -> Result<(usize, u64)> {
    let (mut count, mut bytes) = (0, 0);
    for entry in messages {
        ensure!(
            display_ids.insert(entry.record_id.clone()),
            "completion repeated"
        );
        ensure!(matches!(
            entry.atom.lifecycle,
            ChatAtomLifecycle::Terminal { .. }
        ));
        let (members, body_bytes) = count_payload(
            reader,
            entry.atom.payload.as_ref(),
            &entry.record_id,
            &entry.atom.contents,
            identities,
            turns,
        )
        .await?;
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
        let mut feed = env.runtime.open_observed_feed(&thread.thread.id, ChatScope::Main, demand(37)).await?;
        let observed = async {
            let first = chat(&mut feed).await?;
            ensure!(first.placement == ChatPlacement::Set);
            let mut retired = false;
            let mut through = first.through_seq;
            let mut peak_batch = first.encoded_len()?;
            let initial_tail = items(first.entries.clone())?;
            let mut last_position = initial_tail.last().map(|item| item.completion_seq);
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
                        Observation::Chat { batch } => {
                            batch.validate_for(&ChatScope::Main)?;
                            ensure!(batch.placement == ChatPlacement::Append && batch.before.is_none());
                            ensure!(batch.entries.len() <= demand(37).max_items as usize);
                            peak_batch = peak_batch.max(batch.encoded_len()?);
                            ensure!(peak_batch <= demand(37).max_bytes as usize);
                            ensure!(batch.from_seq == Some(through));
                            through = batch.through_seq;
                            let items = items(batch.entries)?;
                            for item in &items {
                                ensure!(Some(item.completion_seq) > last_position, "Main Append changed item order");
                                last_position = Some(item.completion_seq);
                            }
                            appended.extend(items);
                        }
                        Observation::Activity { snapshot } => {
                            ensure!(snapshot.completed_through == through);
                            retired = snapshot.entries.is_empty();
                        }
                        Observation::State { update } => {
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
                let mut completed = history(&env, &thread.thread.id, feed.reader(), first, demand(37)).await?;
                completed.extend(appended);
                count_output(feed.reader(), &completed,
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

#[derive(Debug)]
struct LiveBodyTarget {
    reference: ContentRef,
    record_id: String,
    turn_id: String,
}

fn live_body_target(snapshot: &ActivitySnapshot) -> Result<Option<LiveBodyTarget>> {
    if !snapshot.execution_present {
        return Ok(None);
    }
    let Some(atom) = snapshot
        .entries
        .iter()
        .map(|entry| &entry.atom)
        .find(|atom| atom.kind == pl_protocol::ChatAtomKind::Text && !atom.contents.is_empty())
    else {
        return Ok(None);
    };
    let reference = atom.contents[0].reference.clone();
    let ContentTarget::Body {
        owner: ContentOwner::Item { item_id },
        ..
    } = &reference.target
    else {
        anyhow::bail!("active response has no stable Item owner");
    };
    Ok(Some(LiveBodyTarget {
        record_id: item_id.clone(),
        reference,
        turn_id: atom.turn_id.clone().context("active response Turn")?,
    }))
}

fn running_execution<'a>(
    snapshot: &'a pl_protocol::ThreadSnapshot,
    turn_id: &str,
) -> Option<&'a str> {
    let turn = snapshot.active_turn.as_ref()?;
    if turn.id != turn_id || !matches!(turn.state, TurnState::Running(_)) {
        return None;
    }
    let execution = snapshot.runtime.as_ref()?.execution.as_ref()?;
    (execution.phase() == pl_protocol::AgentExecutionPhase::Running
        && execution.turn_id() == Some(turn_id))
    .then_some(execution.id())
}

#[derive(Debug)]
struct LiveBodyConsumption {
    target: LiveBodyTarget,
    execution_id: String,
    bytes: u64,
    windows: usize,
    live_reads: usize,
    live_bytes: u64,
}

async fn consume_live_body(
    runtime: &pl_studio_runtime::StudioRuntime,
    thread_id: &str,
    reader: &ConversationReader,
    target: LiveBodyTarget,
) -> Result<LiveBodyConsumption> {
    let first = runtime.thread_snapshot(thread_id).await?;
    let execution_id = running_execution(&first, &target.turn_id)
        .context("first live body arrived after its original execution ended")?
        .to_owned();
    let total = (pl_provider_fixture::GUI_STREAMING_OUTPUT_REFERENCE_TOKENS * 2) as u64;
    let mut watch = reader
        .watch_content(
            &target.reference,
            ContentRange {
                offset: 0,
                max_bytes: 64 * 1024,
            },
        )
        .await?;
    let result = async {
        let mut cursor = 0;
        let mut available = 0;
        let mut generation = None;
        let mut windows = 0;
        let mut live_reads = 0;
        let mut live_bytes = 0;
        loop {
            let before = runtime.thread_snapshot(thread_id).await?;
            let window = watch
                .recv()
                .await?
                .context("content watch ended before a sealed body")?;
            ensure!(window.offset == 0 && window.bytes.len() <= 64 * 1024);
            ensure!(window.bytes.len() as u64 <= window.available_through);
            ensure!(window.available_through >= available && window.available_through <= total);
            ensure!(generation.as_ref().is_none_or(|value| value == &window.generation));
            generation = Some(window.generation.clone());
            available = window.available_through;
            let sealed = window.sealed;
            let previous = cursor;
            let (parts, remainder) = window.bytes.as_chunks::<2>();
            ensure!(remainder.is_empty() && parts.iter().all(|part| part == b" a"));
            if cursor < window.bytes.len() as u64 {
                cursor = window.bytes.len() as u64;
            }
            // Retain only the cursor/generation, not a second growing body or a queue of windows.
            drop(window);
            while cursor < available {
                let suffix = reader
                    .read_content(
                        &target.reference,
                        ContentRange {
                            offset: cursor,
                            max_bytes: (available - cursor).min(64 * 1024) as u32,
                        },
                    )
                    .await?;
                ensure!(suffix.offset == cursor && !suffix.bytes.is_empty());
                ensure!(suffix.bytes.len() as u64 <= available - cursor);
                ensure!(suffix.available_through >= available && suffix.available_through <= total);
                ensure!(generation.as_ref() == Some(&suffix.generation));
                let (parts, remainder) = suffix.bytes.as_chunks::<2>();
                ensure!(remainder.is_empty() && parts.iter().all(|part| part == b" a"));
                cursor += suffix.bytes.len() as u64;
            }
            let after = runtime.thread_snapshot(thread_id).await?;
            windows += 1;
            // Fresh hot snapshots bracket the actual read. A pending Main notification alone
            // cannot prove that the original Turn/execution was still running.
            if cursor > previous
                && running_execution(&before, &target.turn_id) == Some(execution_id.as_str())
                && running_execution(&after, &target.turn_id) == Some(execution_id.as_str())
            {
                live_reads += 1;
                live_bytes += cursor - previous;
            }
            if sealed {
                ensure!(cursor == total, "continuous reader did not consume the complete body");
                let end = reader
                    .read_content(
                        &target.reference,
                        ContentRange {
                            offset: cursor,
                            max_bytes: 1,
                        },
                    )
                    .await?;
                ensure!(end.offset == cursor && end.bytes.is_empty() && end.sealed);
                ensure!(end.available_through == total && generation.as_ref() == Some(&end.generation));
                ensure!(live_reads >= 2 && live_bytes > 0,
                    "no repeated original-running body reads: windows={windows}, live_reads={live_reads}, live_bytes={live_bytes}");
                break;
            }
        }
        Ok(LiveBodyConsumption {
            target,
            execution_id,
            bytes: cursor,
            windows,
            live_reads,
            live_bytes,
        })
    }
    .await;
    watch.request_close();
    let closed = watch.close().await;
    let result = result.with_context(|| format!("live content-watch cleanup: {closed:?}"))?;
    closed?;
    Ok(result)
}

#[tokio::test]
async fn realistic_output_limit_single_item_reads_live_body() -> Result<()> {
    let prompt = "realistic-single-live-body";
    let env = Environment::new(
        vec![prompt_step(
            prompt,
            0,
            pl_provider_fixture::gui_streaming_output_reply(1, 1),
        )],
        vec![],
    )
    .await?;
    let result = async {
        let thread = env.start(ThreadWorkspaceMode::Worktree, prompt).await?;
        let id = &thread.thread.id;
        let mut feed = env
            .runtime
            .open_observed_feed(id, ChatScope::Main, demand(37))
            .await?;
        let observed = async {
            let first = chat(&mut feed).await?;
            first.validate_for(&ChatScope::Main)?;
            ensure!(first.placement == ChatPlacement::Set);
            let reader = feed.reader().clone();
            let (offer, received) = tokio::sync::oneshot::channel();
            let mut offer = Some(offer);
            let mut retired = false;
            let mut through = first.through_seq;
            let mut peak_batch = first.encoded_len()?;
            ensure!(first.entries.len() <= demand(37).max_items as usize);
            ensure!(peak_batch <= demand(37).max_bytes as usize);
            let mut last_position = items(first.entries.clone())?.last().map(|item| item.completion_seq);
            let consume = async {
                let target = received.await.context("Main never published an original live body")?;
                consume_live_body(&env.runtime, id, &reader, target).await
            };
            let observe = async {
                let result = async {
                    let mut appended = Vec::new();
                    let mut terminal = None;
                    while terminal.is_none() || !retired {
                        match next(&mut feed).await? {
                            Observation::Chat { batch } => {
                                batch.validate_for(&ChatScope::Main)?;
                                ensure!(batch.placement == ChatPlacement::Append && batch.before.is_none());
                                ensure!(batch.entries.len() <= demand(37).max_items as usize);
                                peak_batch = peak_batch.max(batch.encoded_len()?);
                                ensure!(peak_batch <= demand(37).max_bytes as usize);
                                ensure!(batch.from_seq == Some(through));
                                through = batch.through_seq;
                                let items = items(batch.entries)?;
                                for item in &items {
                                    ensure!(Some(item.completion_seq) > last_position, "Main Append changed item order");
                                    last_position = Some(item.completion_seq);
                                }
                                appended.extend(items);
                            }
                            Observation::Activity { snapshot } => {
                            ensure!(snapshot.completed_through == through);
                            if let Some(target) = live_body_target(&snapshot)? && let Some(sender) = offer.take() {
                                sender.send(target).map_err(|_| anyhow::anyhow!("live reader closed before its first target"))?;
                            }
                            retired = snapshot.entries.is_empty();
                        }
                        Observation::State { update } => {
                                if let ThreadSubscriptionUpdate::Notification { notification } = *update
                                    && let ThreadNotification::TurnCompleted { turn } = notification.notification
                                {
                                    ensure!(turn.input_id.as_deref() == Some(format!("input-{prompt}").as_str()));
                                    ensure!(matches!(turn.state, TurnState::Completed(_)), "real output Turn failed: {:?}", turn.state);
                                    terminal = Some(turn.id);
                                }
                            }
                        }
                    }
                    Ok::<_, anyhow::Error>((appended, terminal.context("typed Turn terminal")?, peak_batch))
                }
                .await;
                drop(offer);
                result
            };
            tokio::time::timeout(Duration::from_secs(120), async {
                // The one-time identity transfer is synchronous; it cannot stall Main on body IO.
                // Both owners remain joined even if either branch fails.
                let (main, body) = tokio::join!(observe, consume);
                let (appended, terminal, peak_batch) = main.with_context(|| format!("continuous body result: {body:?}"))?;
                let body = body?;
                let mut completed = history(&env, id, &reader, first, demand(37)).await?;
                completed.extend(appended);
                let matching = completed.iter().filter(|item| item.record_id == body.target.record_id).collect::<Vec<_>>();
                ensure!(matching.len() == 1 && body.target.turn_id == terminal);
                ensure!(matching[0].atom.contents.iter().any(|content| content.reference == body.target.reference));
                let mut display_ids = HashSet::new();
                let mut identities = HashSet::new();
                let mut turns = HashSet::new();
                let (count, bytes) = count_output(&reader, &completed,
                    &mut display_ids, &mut identities, &mut turns).await?;
                ensure!(turns.len() == 1 && turns.contains(&terminal));
                ensure!(count == 1 && bytes == body.bytes && bytes == 256_000);
                eprintln!("continuous single body: execution={}, turn={}, bytes={}, windows={}, original_running_reads={}, original_running_bytes={}, peak_chat_bytes={}",
                    body.execution_id, terminal, bytes, body.windows, body.live_reads, body.live_bytes, peak_batch);
                Ok::<_, anyhow::Error>(())
            }).await.context("paced single-item live consumer exceeded its original deadline")?
        }
        .await;
        finish_feed(&mut feed, observed).await
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn realistic_output_limit_many_items_reads_bodies_while_running() -> Result<()> {
    const ITEMS: usize = 2_000;
    const BYTES: u64 = 256_000;
    let prompt = "realistic-many-live-bodies";
    let env = Environment::new(
        vec![prompt_step(
            prompt,
            0,
            pl_provider_fixture::gui_streaming_output_reply(ITEMS, 1),
        )],
        vec![],
    )
    .await?;
    let result = async {
        let thread = env.start(ThreadWorkspaceMode::Worktree, prompt).await?;
        let id = &thread.thread.id;
        let (turn_id, execution_id) = {
            let snapshot = env.runtime.thread_snapshot(id).await?;
            let turn = snapshot.active_turn.as_ref().context("original active Turn")?;
            ensure!(turn.input_id.as_deref() == Some(format!("input-{prompt}").as_str()));
            let execution = running_execution(&snapshot, &turn.id)
                .context("original execution was not running before the many-item read")?;
            (turn.id.clone(), execution.to_owned())
        };
        let mut feed = env
            .runtime
            .open_observed_feed(id, ChatScope::Main, demand(37))
            .await?;
        let observed = async {
            let first = chat(&mut feed).await?;
            first.validate_for(&ChatScope::Main)?;
            ensure!(first.placement == ChatPlacement::Set);
            ensure!(first.entries.len() <= demand(37).max_items as usize);
            let mut peak_batch = first.encoded_len()?;
            ensure!(peak_batch <= demand(37).max_bytes as usize);
            let mut through = first.through_seq;
            let mut retired = false;
            let reader = feed.reader().clone();
            let initial = history(&env, id, &reader, first, demand(37)).await?;
            let mut last_position = initial.last().map(|item| item.completion_seq);
            // This is the single admitted header inventory used by the assertion, not a second
            // body or window queue. The independent reader clones at most one demand-sized slice.
            let admitted = std::sync::Mutex::new((initial, false));
            let consumed = std::sync::Mutex::new((0_usize, 0_u64));
            let (changed, mut changes) = tokio::sync::watch::channel(0_usize);
            let observe = async {
                let result = async {
                    let mut terminal = None;
                    while terminal.is_none() || !retired {
                        match next(&mut feed).await? {
                            Observation::Chat { batch } => {
                                batch.validate_for(&ChatScope::Main)?;
                                ensure!(batch.placement == ChatPlacement::Append && batch.before.is_none());
                                ensure!(batch.entries.len() <= demand(37).max_items as usize);
                                peak_batch = peak_batch.max(batch.encoded_len()?);
                                ensure!(peak_batch <= demand(37).max_bytes as usize);
                                ensure!(batch.from_seq == Some(through));
                                through = batch.through_seq;
                                let items = items(batch.entries)?;
                                for item in &items {
                                    ensure!(Some(item.completion_seq) > last_position, "Main Append changed item order");
                                    last_position = Some(item.completion_seq);
                                }
                                let count = {
                                    let mut state = admitted.lock().expect("test header owner poisoned");
                                    state.0.extend(items);
                                    state.0.len()
                                };
                                changed.send_replace(count);
                            }
                            Observation::Activity { snapshot } => {
                            ensure!(snapshot.completed_through == through);
                            retired = snapshot.entries.is_empty();
                        }
                        Observation::State { update } => {
                                if let ThreadSubscriptionUpdate::Notification { notification } = *update
                                    && let ThreadNotification::TurnCompleted { turn } = notification.notification
                                {
                                    ensure!(turn.id == turn_id);
                                    ensure!(turn.input_id.as_deref() == Some(format!("input-{prompt}").as_str()));
                                    ensure!(matches!(turn.state, TurnState::Completed(_)),
                                        "real many-item Turn failed: {:?}", turn.state);
                                    ensure!(terminal.replace(turn.id).is_none(), "duplicate target terminal");
                                }
                            }
                        }
                    }
                    terminal.context("typed many-item terminal").map(|terminal| (terminal, peak_batch))
                }.await;
                let count = {
                    let mut state = admitted.lock().expect("test header owner poisoned");
                    state.1 = true;
                    state.0.len()
                };
                changed.send_replace(count);
                result
            };
            let consume = async {
                let mut cursor = 0;
                let mut display_ids = HashSet::new();
                let mut identities = HashSet::new();
                let mut turns = HashSet::new();
                let (mut count, mut bytes) = (0, 0);
                let (mut live_batches, mut live_items, mut live_bytes) = (0, 0, 0);
                loop {
                    let (batch, done) = {
                        let state = admitted.lock().expect("test header owner poisoned");
                        (state.0.iter().skip(cursor).take(37).cloned().collect::<Vec<_>>(), state.1)
                    };
                    if batch.is_empty() {
                        if done {
                            break;
                        }
                        changes.changed().await.context("header observation closed before completion")?;
                        continue;
                    }
                    let before = env.runtime.thread_snapshot(id).await?;
                    let (members, body_bytes) = count_output(&reader, &batch,
                        &mut display_ids, &mut identities, &mut turns).await?;
                    let after = env.runtime.thread_snapshot(id).await?;
                    if members > 0
                        && running_execution(&before, &turn_id) == Some(execution_id.as_str())
                        && running_execution(&after, &turn_id) == Some(execution_id.as_str())
                    {
                        live_batches += 1;
                        live_items += members;
                        live_bytes += body_bytes;
                    }
                    cursor += batch.len();
                    count += members;
                    bytes += body_bytes;
                    *consumed.lock().expect("test read counters poisoned") = (count, bytes);
                }
                ensure!(turns.len() == 1 && turns.contains(&turn_id));
                ensure!(count == ITEMS && bytes == BYTES,
                    "many-item body coverage changed: items={count}, bytes={bytes}");
                ensure!(live_batches >= 2 && live_items >= 2 && live_bytes > 0,
                    "no repeated original-running many-item reads: batches={live_batches}, items={live_items}, bytes={live_bytes}");
                Ok::<_, anyhow::Error>((count, bytes, live_batches, live_items, live_bytes))
            };
            tokio::time::timeout(Duration::from_secs(120), async {
                let (main, bodies) = tokio::join!(observe, consume);
                let (terminal, peak_batch) = main.with_context(|| format!("many-item body consumer: {bodies:?}"))?;
                let (count, bytes, live_batches, live_items, live_bytes) = bodies?;
                ensure!(terminal == turn_id);
                eprintln!("continuous many bodies: execution={execution_id}, turn={turn_id}, items={count}, bytes={bytes}, original_running_batches={live_batches}, original_running_items={live_items}, original_running_bytes={live_bytes}, peak_chat_bytes={peak_batch}");
                Ok::<_, anyhow::Error>(())
            }).await.with_context(|| {
                let admitted = admitted.lock().expect("test header owner poisoned");
                let consumed = consumed.lock().expect("test read counters poisoned");
                format!("paced many-item live consumer exceeded its original deadline: admitted={}, observation_done={}, read_items={}, read_bytes={}", admitted.0.len(), admitted.1, consumed.0, consumed.1)
            })?
        }.await;
        finish_feed(&mut feed, observed).await
    }.await;
    env.finish(result).await
}
